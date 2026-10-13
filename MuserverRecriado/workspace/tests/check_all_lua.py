#!/usr/bin/env python3
"""Valida a sintaxe de TODOS os .lua das tres arvores Data/Script com o parser Lua.

Existe por dois motivos concretos:
  * a porta antiga so tentava utf-8 e 'ignorava' os arquivos latin-1 (com acentos
    nos comentarios) - 22 arquivos ficavam sem verificar, que e exatamente a
    situacao em que um arquivo corrompido passaria;
  * editar Lua por script de substituicao ja quebrou parenteses duas vezes nesta
    auditoria; esta e a rede de seguranca que impede isso de voltar.
Sai 1 se algum arquivo for sintaticamente invalido. Arquivos binarios criptografados
pelo LuaEncryptorTool sao contados a parte (nao sao fonte).
"""
import glob
import os
import re
import sys

ROOTS = ["MuServer/Data/Script", "MuServer/SpeedServer/Data/Script",
         "MuServer/SubSalatest/Data/Script"]

try:
    from luaparser import ast
except ImportError:
    sys.exit("luaparser ausente: /home/user/.venv-tools/bin/pip install luaparser")


def read_src(path):
    """utf-8 -> utf-8 com BOM -> latin-1. Latin-1 nunca falha, entao qualquer
    arquivo de texto chega ao parser em vez de ser 'ignorado'."""
    raw = open(path, "rb").read()
    # Lua de verdade comeca com '--' ou por nome de funcao; o que contem byte nulo
    # nos primeiros 4 KB e binario. Os 21 arquivos assim neste pack tem o mesmo
    # cabecalho de alta entropia (0xaa 0x21 0x91 0xa6 ...) = saida do
    # LuaEncryptorTool. Nao sao fonte, nao dao para parsear - e a unicidade do
    # cabecalho entre mapas distintos prova que e cifra de bloco, nao texto.
    if b"\x00" in raw[:4096]:
        return None, "binario (LuaEncryptorTool)"
    if raw[:4] == b"\x1bLua":
        return None, "bytecode Lua"
    for enc in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return raw.decode(enc), enc
        except UnicodeDecodeError:
            continue
    return None, "indecifavel"


def main():
    files = []
    for r in ROOTS:
        files += glob.glob(os.path.join(r, "**", "*.lua"), recursive=True)
    files = sorted(set(files))
    checked = skipped = bad = 0
    for f in files:
        src, enc = read_src(f)
        if src is None:
            print("  PULADO (%s): %s" % (enc, f))
            skipped += 1
            continue
        try:
            ast.parse(src)
            checked += 1
        except Exception as exc:  # noqa: BLE001 - queremos o 1o erro, nao a classe
            print("  LUA INVALIDO [%s]: %s\n      %s" % (enc, f, str(exc)[:160]))
            bad += 1
    print("  %d verificados, %d pulados (binarios criptografados), %d invalidos"
          % (checked, skipped, bad))
    if skipped:
        print("  NOTA: os %d binarios so tem texto legivel nos backups do editor"
              " (*.tmp) - ver workspace/recovered/lua/" % skipped)
    if not checked:
        print("  ERRO: nenhum arquivo verificado - o ambiente de teste esta errado")
        return 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

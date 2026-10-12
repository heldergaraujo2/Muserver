#!/usr/bin/env python3
"""wire_probe.py — cliente de conformidade byte a byte do protocolo v2 (fase R-6).

Diferença para `tests/netclient.c`: este envia **bytes exatos escolhidos pelo teste**, inclusive
quadros inválidos de propósito (tamanho menor que o cabeçalho, tamanho acima do máximo, campo de
tamanho com a ordem trocada, opcode inexistente). É o que permite testar conformidade com o
contrato escrito em `include/mu2/mu2.h` em vez de só "o serviço responde".

Somente leitura em relação à referência; não toca em `MuServer/`. Sem dependência externa.

Saída determinística (sem timestamp, sem caminho absoluto):
  enviados_bytes= recebidos_bytes=
  reply_hex=<hex>
  reply_ascii=<imprimível, byte de controle como \\xNN>
  resultado=OK|DIVERGENTE|SEM_RESPOSTA
Exit: 0 quando `resultado=OK`, 1 caso contrário, 2 erro de uso.
"""
import argparse
import socket
import sys


def ascii_seguro(b: bytes) -> str:
    return "".join(chr(c) if 0x20 <= c < 0x7F else "\\x%02x" % c for c in b)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--hex", default="", help="bytes a enviar, em hex (ex.: 01000400)")
    ap.add_argument("--hex-2", default="", help="segunda escrita, depois de --pause-ms")
    ap.add_argument("--pause-ms", type=int, default=0, help="espera entre --hex e --hex-2")
    ap.add_argument("--read-ms", type=int, default=1500, help="janela de leitura da resposta")
    ap.add_argument("--expect-hex", default="", help="resposta esperada, em hex")
    ap.add_argument("--expect-ascii-prefix", default="", help="prefixo ASCII esperado no corpo")
    ap.add_argument("--skip", type=int, default=0,
                    help="bytes a descartar do início da resposta antes de comparar (cabeçalho)")
    ap.add_argument("--connect-ms", type=int, default=2000)
    a = ap.parse_args()

    try:
        payload = bytes.fromhex(a.hex.replace(" ", ""))
        payload2 = bytes.fromhex(a.hex_2.replace(" ", "")) if a.hex_2 else b""
    except ValueError:
        print("wire_probe: --hex/--hex-2 nao sao hex valido", file=sys.stderr)
        return 2

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(a.connect_ms / 1000.0)
    try:
        s.connect((a.host, a.port))
    except OSError as e:
        print(f"wire_probe: conexao falhou: {e}", file=sys.stderr)
        return 2
    s.settimeout(a.read_ms / 1000.0)

    enviados = 0
    try:
        if payload:
            s.sendall(payload)
            enviados += len(payload)
        if payload2:
            if a.pause_ms:
                s.settimeout(a.pause_ms / 1000.0)
                try:
                    s.recv(1, socket.MSG_PEEK)     # pausa real, sem consumir
                except socket.timeout:
                    pass
                s.settimeout(a.read_ms / 1000.0)
            s.sendall(payload2)
            enviados += len(payload2)
    except OSError as e:
        print(f"enviados_bytes={enviados}")
        print(f"wire_probe: escrita falhou: {e}", file=sys.stderr)
        s.close()
        return 2

    buf = bytearray()
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf.extend(chunk)
            if a.expect_hex and len(buf) >= len(bytes.fromhex(a.expect_hex)):
                break
    except socket.timeout:
        pass
    except OSError:
        pass
    s.close()

    corpo = bytes(buf[a.skip:]) if a.skip else bytes(buf)
    print(f"enviados_bytes={enviados}")
    print(f"recebidos_bytes={len(buf)}")
    print(f"reply_hex={bytes(buf).hex()}")
    # reply_ascii respeita --skip: quem pede o corpo quer ler o corpo, nao o cabecalho escapado
    print(f"reply_ascii={ascii_seguro(corpo)}")
    print(f"corpo_bytes={len(corpo)}")
    if a.expect_hex:
        ok = bytes(buf).hex() == a.expect_hex.lower()
        print("resultado=" + ("OK" if ok else "DIVERGENTE"))
        return 0 if ok else 1
    if a.expect_ascii_prefix:
        ok = corpo.startswith(a.expect_ascii_prefix.encode("ascii"))
        print("resultado=" + ("OK" if ok else "DIVERGENTE"))
        return 0 if ok else 1
    ok = len(buf) > 0
    print("resultado=" + ("OK" if ok else "SEM_RESPOSTA"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

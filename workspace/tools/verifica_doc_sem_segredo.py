#!/usr/bin/env python3
"""verifica_doc_sem_segredo.py — prova que um documento nosso nao carrega valor sensivel do pacote.

Por que isto existe: a regra "nao incluir segredos em relatorio" era, ate aqui, uma promessa de
quem escreve. Promessa nao se reproduz. Esta ferramenta a transforma em verificacao com codigo de
saida: ela extrai os valores das chaves sensiveis dos arquivos de configuracao do pacote (somente
leitura) e procura esses valores no documento alvo. Se algum aparecer, sai 1.

Garantia dura, testada em `workspace/tests/test_verifica_doc_sem_segredo.py`:
**a saida desta ferramenta nunca contem o valor** — so o NOME da chave, a origem e a contagem. Um
verificador anti-vazamento que vaza no proprio relatorio nao serve para nada.

Limites declarados (nao escondidos):
  - e uma verificacao por pertinencia de valor literal; valores curtos (< --min-len, padrao 6) sao
    ignorados de proposito porque casariam com qualquer texto (ex.: senha de party com 4 digitos);
  - so cobre as chaves que o extrator reconhece; nao e prova de ausencia de segredo em formato
    atipico, nem substitui revisao humana;
  - nao abre `.bak`, `.dmp`, binarios nem restaura nada.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

RAIZ_PADRAO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Chaves cujo valor e material sensivel. O nome da chave pode ser reportado; o valor, nunca.
CHAVE_SENSIVEL = re.compile(
    r"^\s*(?P<chave>[A-Za-z0-9_.\- ]*(?:senha|password|passwd|pwd|pass|token|secret|serial|"
    r"licenca|licen[çc]a|crc|private|apikey|api_key|key\d?[a-z]*)\s*)\s*[:=]\s*(?P<valor>.+?)\s*$",
    re.IGNORECASE,
)

# Fontes padrao: os arquivos do pacote onde o inventario de exposicao mediu credencial preenchida.
FONTES_PADRAO = [
    "MuServer/PSGuard/PSGG.ini",
    "MuServer/JoinServer/JoinServer.ini",
    "MuServer/DiscordServer/DiscordServer.ini",
    "MuServer/MHPServer/MHPServer.ini",
    "MuServer/Tools/Editores/MuEditor/config.ini",
    "MuServer/Tools/Editores/Editor de conta Muemu/config.ini",
    "MuServer/GameServer/Data/GameServerInfo - Common.dat",
    "MuServer/GameServerCS/DATA/GameServerInfo - Common.dat",
    "MuServer/SpeedServer/GameServer/Data/GameServerInfo - Common.dat",
    "MuServer/SubSalatest/GameServer/Data/GameServerInfo - Common.dat",
    "MuServer/Tools/Gerador de Main/MAIN_INFO v41 - Season 6/MainInfo.ini",
    # caminho corrigido em 2026-10-13: a segunda pasta real e `MAIN_INFOS6.20`, nao `MAIN_INFO`.
    # Medido: com o caminho errado o extrator via 10 valores; com o certo, 12 (a copia extra traz
    # serial de cliente e chave de presenca do Discord). Fonte conferida em `git ls-tree origin/main`.
    "MuServer/Tools/Gerador de Main/MAIN_INFOS6.20/MainInfo.ini",
]

# Valores que podem aparecer num documento sem serem vazamento, porque ja sao publicos por
# construcao (nome de banco, nome de DSN, caminho de arquivo versionado, id publico do Discord).
# Cada entrada tem de ter justificativa — a lista e curta de proposito.
PERMITIDOS_PADRAO = {
    "MuOnline": "nome do banco; e o nome dos proprios arquivos .bak/.reg versionados desde o upload",
    "MuOnline64": "idem, variante 64-bit do DSN",
    "MuOnline.bak": "nome de arquivo versionado",
    "MuOnline_old.bak": "nome de arquivo versionado",
    "back_hinet.bak": "nome de arquivo versionado",
    "mw_v6.bak": "nome de arquivo versionado",
}


def ler_texto(caminho: str) -> str:
    """Le texto tentando UTF-8 e UTF-16 (o pacote tem .reg/.dat em UTF-16LE)."""
    with open(caminho, "rb") as fh:
        bruto = fh.read()
    for cod in ("utf-8-sig", "utf-16", "latin-1"):
        try:
            return bruto.decode(cod)
        except UnicodeDecodeError:
            continue
    return bruto.decode("latin-1", errors="replace")


def extrair_valores(caminho_fonte: str, min_len: int) -> list[tuple[str, str]]:
    """Devolve [(nome_da_chave, valor)] das chaves sensiveis preenchidas da fonte.

    O valor sai daqui para comparacao em memoria; quem chama NUNCA o imprime.
    """
    if not os.path.isfile(caminho_fonte):
        return []
    achados: list[tuple[str, str]] = []
    for linha in ler_texto(caminho_fonte).splitlines():
        if "=" not in linha and ":" not in linha:
            continue
        m = CHAVE_SENSIVEL.match(linha)
        if not m:
            continue
        valor = m.group("valor").strip().strip('"').strip("'").strip()
        if len(valor) < min_len:
            continue
        if valor.lower() in {"null", "none", "vazio", "changeme", "example", "placeholder"}:
            continue
        if len(set(valor)) <= 2:  # "00000000", "--------": nao e credencial
            continue
        achados.append((m.group("chave").strip(), valor))
    return achados


def coletar(fontes: list[str], raiz: str, min_len: int) -> list[dict]:
    itens = []
    for rel in fontes:
        for chave, valor in extrair_valores(os.path.join(raiz, rel), min_len):
            itens.append({"chave": chave, "origem": rel, "valor": valor})
    return itens


# Marcadores que significam "aqui NAO ha valor": se o documento usa um deles, e redacao, nao vazamento.
MARCADOR = re.compile(r"^[<\[(]?(redigid\w*|vazio|removid\w*|omitid\w*|nao[_ ]?exibido|exemplo|"
                      r"placeholder|cole_aqui\w*|troque_aqui\w*|x{3,}|\*{3,}|\.{3,}|-+|n/?a)[>\])]?$",
                      re.IGNORECASE)


def formas_suspeitas(texto: str) -> list[str]:
    """Segunda checagem, independente da primeira: o documento contem uma LINHA de credencial?

    A checagem por valor tem um ponto cego declarado (valores curtos sao ignorados). Esta cobre
    esse ponto pela forma: `chave_sensivel = <algo com cara de credencial>`. Devolve so os NOMES
    das chaves — nunca o valor.
    """
    suspeitas = []
    for linha in texto.splitlines():
        m = CHAVE_SENSIVEL.match(linha)
        if not m:
            continue
        valor = m.group("valor").strip().strip('"').strip("'").strip()
        if not valor or MARCADOR.match(valor):
            continue
        # so conta se PARECE credencial: >=8 caracteres com letra e digito (ou base64-ish)
        tem_letra = any(c.isalpha() for c in valor)
        tem_digito = any(c.isdigit() for c in valor)
        if len(valor) >= 8 and (tem_letra and tem_digito):
            suspeitas.append(m.group("chave").strip())
    return suspeitas


def verificar(itens: list[dict], alvos: dict[str, str], permitidos: dict[str, str]) -> list[dict]:
    """Procura cada valor nos alvos. Devolve achados SEM o valor (so chave/origem/alvo/contagem)."""
    encontrados = []
    for item in itens:
        valor = item["valor"]
        if valor in permitidos:
            continue
        for nome, texto in alvos.items():
            quantos = texto.count(valor)
            if quantos:
                encontrados.append(
                    {"chave": item["chave"], "origem": item["origem"], "alvo": nome,
                     "ocorrencias": quantos, "tamanho_do_valor": len(valor)}
                )
    return encontrados


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Verifica se um documento carrega valor sensivel do pacote.")
    ap.add_argument("--alvo", action="append", default=[],
                    help="arquivo a verificar (pode repetir). '-' le a entrada padrao.")
    ap.add_argument("--fontes", nargs="*", default=None,
                    help="fontes de valores sensiveis (padrao: os configs medidos no inventario)")
    ap.add_argument("--raiz", default=RAIZ_PADRAO, help="raiz do repositorio")
    ap.add_argument("--min-len", type=int, default=6, dest="min_len",
                    help="tamanho minimo de valor considerado (padrao 6)")
    ap.add_argument("--json", dest="json_saida", default=None, help="grava o resultado em JSON")
    ap.add_argument("--detalhar", action="store_true",
                    help="lista chave/origem/alvo de cada casamento (nunca o valor)")
    args = ap.parse_args(argv)

    if not args.alvo:
        ap.error("informe ao menos um --alvo")

    fontes = args.fontes if args.fontes is not None else FONTES_PADRAO
    itens = coletar(fontes, args.raiz, args.min_len)

    alvos: dict[str, str] = {}
    for caminho in args.alvo:
        if caminho == "-":
            alvos["<stdin>"] = sys.stdin.read()
        elif os.path.isfile(caminho):
            alvos[caminho] = ler_texto(caminho)
        else:
            print(f"alvo ausente: {caminho}", file=sys.stderr)
            return 2

    encontrados = verificar(itens, alvos, PERMITIDOS_PADRAO)
    formas: list[tuple[str, str]] = []
    for nome, texto in alvos.items():
        for chave in formas_suspeitas(texto):
            formas.append((nome, chave))

    fontes_presentes = sum(1 for f in fontes if os.path.isfile(os.path.join(args.raiz, f)))
    print(f"# fontes: {fontes_presentes}/{len(fontes)} presentes  valores_extraidos={len(itens)}  "
          f"permitidos_declarados={len(PERMITIDOS_PADRAO)}  alvos={len(alvos)}")
    for achado in encontrados:
        if args.detalhar:
            print(f"  VAZAMENTO-POR-VALOR chave={achado['chave']} origem={achado['origem']} "
                  f"alvo={achado['alvo']} ocorrencias={achado['ocorrencias']}")
    for nome, chave in formas:
        print(f"  VAZAMENTO-POR-FORMA chave={chave} alvo={nome} "
              f"(linha de credencial com valor com cara de segredo)")
    total = len(encontrados) + len(formas)
    print(f"# verifica_doc_sem_segredo: por_valor={len(encontrados)} por_forma={len(formas)} "
          f"total={total} exit={1 if total else 0}")

    if args.json_saida:
        with open(args.json_saida, "w", encoding="utf-8") as fh:
            json.dump({"fontes_presentes": fontes_presentes, "valores_extraidos": len(itens),
                       "alvos": sorted(alvos),
                       "casamentos_por_valor": len(encontrados),
                       "casamentos_por_forma": len(formas),
                       "achados": encontrados,
                       "chaves_suspeitas_por_forma": [c for _n, c in formas]},
                      fh, ensure_ascii=False, indent=1)

    return 1 if (encontrados or formas) else 0


if __name__ == "__main__":
    sys.exit(main())

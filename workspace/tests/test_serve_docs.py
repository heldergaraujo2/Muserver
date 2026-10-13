#!/usr/bin/env python3
"""Testes do servidor de documentacao `workspace/tools/serve-docs.py`.

Cobrem o que o auditor pediu em 2026-10-13: lista explicita de aprovados (sem glob), tratamento
seguro de HTML e TESTES NEGATIVOS de acesso. Rodam em porta efemera, sem tocar a preview publica.

Uso: python3 workspace/tests/test_serve_docs.py        (exit 0 = todos passaram)
"""

import importlib.util
import io
import os
import re
import sys
import tempfile
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

RAIZ = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SERVIDOR_PY = os.path.join(RAIZ, "workspace", "tools", "serve-docs.py")

n = 0
falhas = 0


def ck(descricao, condicao):
    global n, falhas
    n += 1
    if condicao:
        print(f"ok {n} - {descricao}")
    else:
        falhas += 1
        print(f"not ok {n} - {descricao}")


def carrega_modulo():
    spec = importlib.util.spec_from_file_location("serve_docs", SERVIDOR_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def http(porta, caminho, metodo="GET", cabecalhos=None):
    """Devolve (codigo, corpo). Nunca levanta: 4xx/5xx viram codigo."""
    req = urllib.request.Request(f"http://127.0.0.1:{porta}{caminho}", method=metodo,
                                 headers=cabecalhos or {})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # conexao recusada etc: trata como falha do teste, nao do servidor
        return None, str(e)


def main():
    ck("o servidor existe no caminho documentado", os.path.isfile(SERVIDOR_PY))
    mod = carrega_modulo()

    # ---------------------------------------------------------------- 1) lista explicita
    aprovados = [rel for _g, caminhos in mod.DOCS_APROVADOS for rel in caminhos]
    ck("a lista de aprovados e uma LISTA (nao ha glob/pattern)", isinstance(mod.DOCS_APROVADOS, list))
    ck("todo caminho aprovado e .md", all(p.endswith(".md") for p in aprovados))
    ck("nenhum caminho aprovado casa com padrao proibido",
       not any(pad.lower() in p.lower() for p in aprovados for pad in mod.PADROES_PROIBIDOS))
    ck("todo caminho aprovado existe no disco", all(os.path.isfile(os.path.join(RAIZ, p)) for p in aprovados))
    ck("nenhum caminho aprovado esta dentro de MuServer/",
       not any(p.startswith("MuServer/") for p in aprovados))

    # ---------------------------------------------------------------- 2) sanitizacao
    hostis = [
        ("<script>alert(1)</script>", "<script>"),
        ("<iframe src=//mal.example></iframe>", "<iframe"),
        ("<object data=x></object>", "<object"),
        ('<img src=x onerror="alert(1)">', "onerror="),
        ("<a href=\"javascript:alert(1)\">x</a>", "javascript:"),
        ("<div srcdoc=\"<b>x</b>\">y</div>", "srcdoc="),
        ("<a href='vbscript:msgbox(1)'>z</a>", "vbscript:"),
    ]
    for payload, proibido in hostis:
        saida = mod.sanitizar_html(payload)
        ck(f"sanitizacao neutraliza {proibido!r}",
           proibido.lower() not in saida.lower())
    ck("sanitizacao preserva conteudo legitimo",
       "<strong>ok</strong>" in mod.sanitizar_html("<strong>ok</strong>"))

    # ---------------------------------------------------------------- 3) servidor no ar
    itens, mapa = mod.catalogo()
    ck("catalogo montado com os documentos aprovados existentes", len(mapa) >= 25)
    servidor = ThreadingHTTPServer(("127.0.0.1", 0), mod.Handler)
    porta = servidor.server_address[1]
    th = threading.Thread(target=servidor.serve_forever, daemon=True)
    th.start()
    try:
        # 3a) o que PODE ser servido
        codigo, corpo = http(porta, "/")
        ck("indice principal responde 200", codigo == 200)
        primeiro = next(iter(mapa))
        codigo, corpo = http(porta, primeiro)
        ck(f"documento aprovado responde 200 ({primeiro})", codigo == 200)
        codigo, corpo = http(porta, "/recriado/docs/AUDIT_HANDOFF.md", metodo="HEAD")
        ck("HEAD responde 200", codigo == 200)

        # 3b) TESTES NEGATIVOS de acesso
        negativos = [
            ("/recriado/reports/r6-config.tsv", "tsv com dado pessoal"),
            ("/recriado/reports/net-orig.tsv", "tsv de relatorio"),
            ("/MuServer/PSGuard/PSGG.ini", "config com credencial"),
            ("/MuServer/DB/MuOnline.bak", "backup de banco"),
            ("/workspace/seguranca/inventario-exposicao-2026-10-13.tsv", "tsv do inventario"),
            ("/../../../etc/passwd", "travessia por .."),
            ("/recriado/docs/../reports/r6-config.tsv", "travessia misturada"),
            ("/recriado/out/gate.tsv", "artefato de execucao"),
            ("/README.md", "arquivo da raiz fora da lista"),
        ]
        for caminho, oque in negativos:
            codigo, _ = http(porta, caminho)
            ck(f"404 para {caminho} ({oque})", codigo == 404)

        codigo, _ = http(porta, "/", metodo="POST")
        ck("POST responde 405 (somente leitura)", codigo == 405)
        codigo, _ = http(porta, "/", metodo="PUT")
        ck("PUT responde 405", codigo == 405)
        codigo, _ = http(porta, "/", metodo="DELETE")
        ck("DELETE responde 405", codigo == 405)

        # 3c) documento NOVO em disco nao entra sozinho (lista explicita, nao glob)
        impostor = os.path.join(RAIZ, "recriado", "docs", "ZZZ-impostor-do-teste.md")
        with open(impostor, "w", encoding="utf-8") as fh:
            fh.write("# documento nao aprovado\n<script>alert(1)</script>\n")
        try:
            codigo, _ = http(porta, "/recriado/docs/ZZZ-impostor-do-teste.md")
            ck("markdown novo no repositorio NAO e servido (lista explicita, nao glob)", codigo == 404)
        finally:
            os.unlink(impostor)

        # 3d) host externo (formato da preview) e cabecalhos
        codigo, _ = http(porta, "/", cabecalhos={"Host": "40427-exemplo.e2b.app",
                                                 "Origin": "https://40427-exemplo.e2b.app"})
        ck("aceita Host/Origin externos (preview)", codigo == 200)
        req = urllib.request.Request(f"http://127.0.0.1:{porta}/")
        with urllib.request.urlopen(req, timeout=10) as r:
            cab = {k.lower(): v for k, v in r.headers.items()}
        ck("sem X-Frame-Options (preview pode embutir)", "x-frame-options" not in cab)
        ck("Cache-Control: no-store", cab.get("cache-control") == "no-store")
        ck("nosniff presente", cab.get("x-content-type-options") == "nosniff")
    finally:
        servidor.shutdown()
        servidor.server_close()

    print(f"1..{n}")
    print(f"# serve-docs={n} falhas={falhas}")
    return 1 if falhas else 0


if __name__ == "__main__":
    raise SystemExit(main())

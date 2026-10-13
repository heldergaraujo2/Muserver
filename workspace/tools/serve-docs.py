#!/usr/bin/env python3
"""Servidor estatico SOMENTE LEITURA para a documentacao de auditoria do projeto Muserver.

Por que existe: a auditoria independente precisa LER os documentos publicados numa pagina navegavel,
sem clonar o repositorio. Este servidor serve uma lista FECHADA de arquivos Markdown — nao e servidor
de arquivos generico, nao aceita escrita, nao expoe o pacote `MuServer/` nem os relatorios `.tsv`.

Garantias (todas verificaveis no codigo abaixo):
  * apenas GET e HEAD; qualquer outro metodo responde 405 (nao ha caminho de escrita);
  * cada URL e resolvida por busca EXATA num dicionario montado na inicializacao — nenhum caminho e
    construido a partir da URL, logo nao ha travessia de diretorio (`..`) possivel;
  * so entram arquivos `.md` das listas explicitas em `catalogo()`; `.tsv`, `.raw`, binarios e o
    pacote `MuServer/` ficam de fora por decisao;
  * `Cache-Control: no-store` (o auditor sempre le o conteudo atual do disco).

Uso:
    python3 workspace/tools/serve-docs.py [--bind 0.0.0.0] [--port 40427]

Sem dependencia obrigatoria: se `mistune` estiver disponivel o Markdown e renderizado; caso contrario
o texto e exibido em <pre> (fonte fiel, so sem formatacao).

Verificacao anti-vazamento (2026-10-13, com o servidor no ar): buscamos, em todos os 30 documentos
servidos, os valores sensiveis dos configs do pacote (senha, token, serial, chave, usuario) e os
e-mails de `PSGuard/PSGG.ini`/`preparar-destino.sh` → **0 vazamentos**. O unico casamento e o NOME do
banco, que ja e publico nos nomes dos proprios arquivos `DB/*.bak`/`DB/*.reg` e que a documentacao
tecnica precisa citar. Os `.tsv` (inclusive `r6-config.tsv`, que carrega 1 e-mail) **nao** entram.
"""

import argparse
import glob
import html
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Documentos de auditoria fora de `recriado/` (entregas desta etapa ao auditor).
EXTRAS = [
    ("Entrega da consolidacao", "workspace/migracao/RELATORIO-CONSOLIDACAO-AUDITORIA-2026-10-13.md"),
    ("Riscos P0 (pedido da auditoria)", "workspace/migracao/RELATORIO-TRATAMENTO-RISCOS-P0-2026-10-13.md"),
    ("Riscos P0 (pedido da auditoria)", "workspace/seguranca/INVENTARIO-EXPOSICAO-2026-10-13.md"),
]

GRUPOS = [
    ("Documentacao do v2 - `recriado/docs/`", "recriado/docs/*.md"),
    ("Relatorios de execucao - `recriado/reports/*.md`", "recriado/reports/*.md"),
]


def catalogo():
    """Monta {url: caminho absoluto} e a estrutura para o indice. Lista fechada, sem glob de usuario."""
    itens = []  # (grupo, titulo, url, abspath, bytes)
    for grupo, padrao in GRUPOS:
        for caminho in sorted(glob.glob(os.path.join(RAIZ, padrao))):
            rel = os.path.relpath(caminho, RAIZ)
            itens.append((grupo, titulo_de(caminho, rel), "/" + rel.replace(os.sep, "/"), caminho,
                          os.path.getsize(caminho)))
    for grupo, rel in EXTRAS:
        caminho = os.path.join(RAIZ, rel)
        if os.path.isfile(caminho):
            itens.append((grupo, titulo_de(caminho, rel), "/" + rel.replace(os.sep, "/"), caminho,
                          os.path.getsize(caminho)))
    mapa = {url: caminho for _, _, url, caminho, _ in itens}
    return itens, mapa


def titulo_de(caminho, rel):
    """Primeiro titulo `# ` do arquivo; se nao houver, o nome do arquivo."""
    try:
        with open(caminho, encoding="utf-8", errors="replace") as fh:
            for _ in range(40):
                linha = fh.readline()
                if not linha:
                    break
                if linha.startswith("# "):
                    return linha[2:].strip()
    except OSError:
        pass
    return os.path.basename(rel)


def renderizador():
    """Devolve funcao markdown->html, ou None (o handler cai no <pre>)."""
    try:
        import mistune  # type: ignore
    except ImportError:
        return None
    try:
        return mistune.create_markdown(plugins=["table", "strikethrough", "task_lists", "footnotes"])
    except Exception:
        try:
            return mistune.create_markdown()
        except Exception:
            return None


def pagina(titulo, corpo):
    return f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(titulo)}</title>
<style>
 :root {{ color-scheme: light dark; }}
 body {{ font: 16px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
        max-width: 76ch; margin: 2rem auto; padding: 0 1.1rem; }}
 h1 {{ font-size: 1.5rem; line-height: 1.25; }}
 a {{ text-decoration-thickness: .08em; }}
 table {{ border-collapse: collapse; display: block; overflow-x: auto; max-width: 100%; margin: 1rem 0; }}
 th, td {{ border: 1px solid color-mix(in srgb, currentColor 30%, transparent); padding: .35rem .6rem;
           text-align: left; vertical-align: top; }}
 th {{ background: color-mix(in srgb, currentColor 7%, transparent); }}
 pre {{ overflow-x: auto; padding: .7rem; background: color-mix(in srgb, currentColor 6%, transparent); }}
 code {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: .92em; }}
 blockquote {{ margin: 1rem 0; padding: .2rem 1rem; border-left: 3px solid color-mix(in srgb, currentColor 35%, transparent); }}
 .aviso {{ font-size: .88rem; opacity: .85; border: 1px dashed color-mix(in srgb, currentColor 35%, transparent);
           padding: .6rem .8rem; border-radius: .4rem; }}
 .rodape {{ font-size: .82rem; opacity: .8; margin-top: 2.5rem; border-top: 1px solid
            color-mix(in srgb, currentColor 25%, transparent); padding-top: .7rem; }}
 ul.lista {{ list-style: none; padding-left: 0; }}
 ul.lista li {{ margin: .3rem 0; }}
 small {{ opacity: .75; }}
</style></head><body>
{corpo}
<div class="rodape">Somente leitura · conteudo ja publicado no repositorio
<code>heldergaraujo2/Muserver</code>, branch <code>arena/cf1de8ce-muserver</code> ·
<code>MuServer/</code>, relatorios <code>.tsv</code>/<code>.raw</code> e qualquer arquivo fora da
lista acima NAO sao servidos · <a href="/">indice</a></div>
</body></html>
"""


def corpo_indice(itens):
    partes = ['<h1>Muserver — documentacao de auditoria</h1>',
              '<p class="aviso"><strong>Servidor somente leitura.</strong> Lista fechada de documentos '
              'Markdown (GET/HEAD apenas). Nenhum valor de credencial e servido: os relatorios '
              '<code>.tsv</code> e o pacote <code>MuServer/</code> ficam de fora por decisao.</p>']
    grupo_atual = None
    for grupo, titulo, url, _caminho, tamanho in itens:
        if grupo != grupo_atual:
            if grupo_atual is not None:
                partes.append("</ul>")
            partes.append(f"<h2>{html.escape(grupo)}</h2><ul class='lista'>")
            grupo_atual = grupo
        partes.append(f"<li><a href='{html.escape(url)}'>{html.escape(titulo)}</a> "
                      f"<small>{html.escape(os.path.basename(url))} · {tamanho // 1024} KiB</small></li>")
    if grupo_atual is not None:
        partes.append("</ul>")
    return pagina("Muserver — documentacao de auditoria", "\n".join(partes))


class Handler(BaseHTTPRequestHandler):
    server_version = "muserver-docs/1.0"
    protocol_version = "HTTP/1.1"

    def _responde(self, codigo, corpo_bytes, tipo="text/html; charset=utf-8", cabecalhos=None):
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(corpo_bytes)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (cabecalhos or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD" and corpo_bytes:
            self.wfile.write(corpo_bytes)

    def _texto(self, codigo, texto):
        self._responde(codigo, texto.encode("utf-8"))

    def do_GET(self):
        caminho = unquote(urlsplit(self.path).path)
        if caminho in ("", "/"):
            itens, _ = catalogo()  # re-le a cada acesso: arquivo novo/alterado aparece sem reiniciar
            self._responde(200, corpo_indice(itens).encode("utf-8"))
            return
        _itens, mapa = catalogo()
        alvo = mapa.get(caminho.rstrip("/"))
        if not alvo or not os.path.isfile(alvo):
            self._texto(404, "<h1>404</h1><p>Fora da lista servida. "
                             "<a href='/'>Ver o indice</a>.</p>")
            return
        try:
            with open(alvo, encoding="utf-8", errors="replace") as fh:
                markdown = fh.read()
        except OSError as erro:
            self._texto(500, f"<h1>500</h1><p>Falha ao ler o arquivo: {html.escape(str(erro))}</p>")
            return
        render = renderizador()
        if render is not None:
            corpo = render(markdown)
        else:
            corpo = "<pre>" + html.escape(markdown) + "</pre>"
        titulo = titulo_de(alvo, caminho)
        # links relativos entre documentos servidos
        corpo = re.sub(r"\]\((docs|reports)/([^)]+)\)", r"](/recriado/\1/\2)", corpo)
        self._responde(200, pagina(titulo, corpo).encode("utf-8"))

    def do_HEAD(self):
        self.do_GET()

    def _recusa(self):
        self._responde(405, b"<h1>405</h1><p>Este servidor e somente leitura (apenas GET e HEAD).</p>",
                       cabecalhos={"Allow": "GET, HEAD"})

    do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = _recusa

    def log_message(self, formato, *args):
        sys.stdout.write("%s %s\n" % (self.address_string(), formato % args))
        sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser(description="Serve a documentacao de auditoria (somente leitura).")
    ap.add_argument("--bind", default="0.0.0.0", help="endereco de escuta (padrao 0.0.0.0, exigido pela preview)")
    ap.add_argument("--port", type=int, default=40427)
    args = ap.parse_args()

    itens, mapa = catalogo()
    if not mapa:
        print("nenhum documento encontrado — confira se o cwd/raiz do repositorio esta correto", file=sys.stderr)
        return 2
    render = renderizador()
    servidor = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"servindo {len(mapa)} documentos em http://{args.bind}:{args.port}/ (somente leitura)")
    print(f"markdown: {'renderizado (mistune)' if render else 'exibido como texto simples (<pre>)'}")
    print("grupos:", "; ".join(sorted({g for g, *_ in itens})))
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        servidor.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

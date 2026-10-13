#!/usr/bin/env python3
"""Servidor estatico SOMENTE LEITURA para a documentacao de auditoria do projeto Muserver.

Por que existe: a auditoria independente precisa LER os documentos publicados numa pagina navegavel,
sem clonar o repositorio.

Garantias (verificadas por `workspace/tests/test_serve_docs.py`, que roda em porta efemera):
  * **lista EXPLICITA de arquivos aprovados** (`DOCS_APROVADOS`) — nao ha glob. Um Markdown novo no
    repositorio NAO passa a ser servido sozinho: entra quando alguem o acrescenta a lista, de
    proposito. (Correcao pedida pelo auditor em 2026-10-13: "padroes glob podem incluir documentos
    Markdown adicionados futuramente".)
  * apenas GET e HEAD; qualquer outro metodo responde 405 (nao ha caminho de escrita);
  * cada URL e resolvida por busca EXATA num dicionario montado na inicializacao — nenhum caminho e
    construido a partir da URL, logo nao ha travessia de diretorio (`..`) possivel;
  * so entram arquivos `.md` da lista; `.tsv`, `.raw`, binarios e o pacote `MuServer/` ficam de fora
    por decisao (o `r6-config.tsv`, por exemplo, carrega um e-mail);
  * **HTML sanitizado**: o Markdown e renderizado com o HTML bruto escapado e, ainda assim, o
    resultado passa por `sanitizar_html()` (remove `script`/`iframe`/`object`/`embed`/`form`,
    atributos `on*`, `srcdoc` e URLs `javascript:`/`data:` em `href`/`src`);
  * `Cache-Control: no-store`; sem cabecalho que bloqueie iframe (a preview precisa embutir).

Uso:
    python3 workspace/tools/serve-docs.py [--bind 0.0.0.0] [--port 40427] [--listar]

Sem dependencia obrigatoria: se `mistune` estiver disponivel o Markdown e renderizado; caso contrario
o texto e exibido em <pre> (fonte fiel, so sem formatacao) e a sanitizacao continua valendo.
"""

import argparse
import html
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# --------------------------------------------------------------------------- lista explicita
# Grupo, caminho relativo a raiz do repositorio. Nada fora desta lista e servido — inclusive um .md
# que exista em disco. Para publicar um documento novo, acrescente-o aqui (e rode o teste, que
# confere que todo caminho da lista existe e que nenhum deles e sensivel).
DOCS_APROVADOS = [
    ("Documentacao do v2 - `recriado/docs/`", [
        "recriado/docs/ADMIN_CONSOLE.md",
        "recriado/docs/ARCHITECTURE.md",
        "recriado/docs/AUDIT_HANDOFF.md",
        "recriado/docs/BUILD_AND_RUN.md",
        "recriado/docs/CHANGELOG.md",
        "recriado/docs/CONTINUITY.md",
        "recriado/docs/CURRENT_STATE.md",
        "recriado/docs/DATABASE.md",
        "recriado/docs/DECISIONS.md",
        "recriado/docs/DEPENDENCIES_AND_LICENSES.md",
        "recriado/docs/ENVIRONMENT.md",
        "recriado/docs/NEXT_TASK.md",
        "recriado/docs/PROJECT_STATUS.md",
        "recriado/docs/PROTOCOLS.md",
        "recriado/docs/ROADMAP.md",
        "recriado/docs/SECURITY.md",
        "recriado/docs/TESTING.md",
    ]),
    ("Relatorios de execucao - `recriado/reports/*.md`", [
        "recriado/reports/README.md",
        "recriado/reports/auditoria-rastreabilidade.md",
        "recriado/reports/enc-cifragem-lua.md",
        "recriado/reports/r5-relatorio.md",
        "recriado/reports/r6-interop-relatorio.md",
        "recriado/reports/r6-relatorio.md",
        "recriado/reports/r7-relatorio.md",
        "recriado/reports/r8-relatorio.md",
        # acrescentado de proposito em 2026-10-13 (R-11): a lista e explicita justamente para que
        # documento novo entre por decisao, nunca por aparecer na pasta
        "recriado/reports/r11-persistencia.md",
        "recriado/reports/rc-formatos-auditoria.md",
        "recriado/reports/rf-lua-protocolo.md",
    ]),
    ("Entregas de auditoria - `workspace/`", [
        "workspace/migracao/RELATORIO-CONSOLIDACAO-AUDITORIA-2026-10-13.md",
        "workspace/migracao/RELATORIO-TRATAMENTO-RISCOS-P0-2026-10-13.md",
        "workspace/seguranca/INVENTARIO-EXPOSICAO-2026-10-13.md",
    ]),
]

# Padroes que nunca podem entrar na lista, mesmo por engano (o teste cobra isto).
PADROES_PROIBIDOS = (".tsv", ".raw", ".bak", ".dmp", ".exe", ".dll", ".pem", ".key", ".env",
                     ".ini", ".reg", ".dat", "MuServer/")


def catalogo():
    """Monta {url: caminho absoluto} e a estrutura do indice a partir da LISTA EXPLICITA."""
    itens = []
    for grupo, caminhos in DOCS_APROVADOS:
        for rel in caminhos:
            caminho = os.path.join(RAIZ, rel)
            if not os.path.isfile(caminho):
                continue  # ausente nao quebra o servidor; o teste acusa
            itens.append((grupo, titulo_de(caminho, rel), "/" + rel, caminho,
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


# --------------------------------------------------------------------------- sanitizacao de HTML
_TAGS_PERIGOSAS = re.compile(r"(?is)<\s*/?\s*(script|iframe|object|embed|form|link|meta|base)\b[^>]*>")
_ATRIBUTOS_ON = re.compile(r"(?i)\son[a-z]+\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+)")
_SRCDOC = re.compile(r"(?i)\ssrcdoc\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+)")
_URL_PERIGOSA = re.compile(r"(?i)\s(href|src|action|formaction|xlink:href)\s*=\s*(\"|')?\s*"
                           r"(javascript|vbscript|data)\s*:[^\"'>\s]*(\"|')?")


def sanitizar_html(conteudo):
    """Remove do HTML renderizado o que pode executar codigo ou carregar conteudo externo.

    Nao e um sanitizador completo (nao ha biblioteca de sanitizacao disponivel sem dependencia): e
    uma segunda barreira, testada, sobre um renderizador que ja escapa HTML bruto. Preferimos
    descrever o alcance exato a fingir cobertura total.
    """
    conteudo = _TAGS_PERIGOSAS.sub(lambda m: html.escape(m.group(0)), conteudo)
    conteudo = _ATRIBUTOS_ON.sub(" data-atributo-removido", conteudo)
    conteudo = _SRCDOC.sub(" data-atributo-removido", conteudo)
    conteudo = _URL_PERIGOSA.sub(lambda m: f' {m.group(1)}="#"', conteudo)
    return conteudo


def renderizador():
    """Devolve funcao markdown->html (com HTML bruto escapado), ou None (o handler cai no <pre>)."""
    try:
        import mistune  # type: ignore
    except ImportError:
        return None
    try:
        return mistune.create_markdown(escape=True,
                                       plugins=["table", "strikethrough", "task_lists", "footnotes"])
    except Exception:
        try:
            return mistune.create_markdown(escape=True)
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
<div class="rodape">Somente leitura · lista EXPLICITA de documentos aprovados (sem glob) ·
conteudo ja publicado no repositorio <code>heldergaraujo2/Muserver</code>, branch
<code>arena/cf1de8ce-muserver</code> · <code>MuServer/</code>, relatorios
<code>.tsv</code>/<code>.raw</code> e qualquer arquivo fora da lista NAO sao servidos ·
<a href="/">indice</a></div>
</body></html>
"""


def corpo_indice(itens):
    partes = ['<h1>Muserver — documentacao de auditoria</h1>',
              '<p class="aviso"><strong>Servidor somente leitura.</strong> Lista explicita de '
              'documentos Markdown aprovados (GET/HEAD apenas). Nenhum valor de credencial e '
              'servido: os relatorios <code>.tsv</code> e o pacote <code>MuServer/</code> ficam de '
              'fora por decisao.</p>']
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
    server_version = "muserver-docs/2.0"
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
            itens, _ = catalogo()
            self._responde(200, corpo_indice(itens).encode("utf-8"))
            return
        _itens, mapa = catalogo()
        alvo = mapa.get(caminho.rstrip("/"))
        if not alvo or not os.path.isfile(alvo):
            self._texto(404, "<h1>404</h1><p>Fora da lista de documentos aprovados. "
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
            corpo = sanitizar_html(render(markdown))
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
    ap.add_argument("--listar", action="store_true", help="imprime a lista aprovada e sai")
    args = ap.parse_args()

    itens, mapa = catalogo()
    if args.listar:
        for grupo, titulo, url, caminho, tamanho in itens:
            print(f"{url}\t{tamanho}\t{titulo}")
        return 0
    if not mapa:
        print("nenhum documento aprovado encontrado — confira a raiz do repositorio", file=sys.stderr)
        return 2
    render = renderizador()
    servidor = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"servindo {len(mapa)} documentos aprovados em http://{args.bind}:{args.port}/ (somente leitura)")
    print(f"markdown: {'renderizado (mistune, HTML bruto escapado + sanitizacao)' if render else 'texto simples (<pre>)'}")
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

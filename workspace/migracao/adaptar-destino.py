#!/usr/bin/env python3
"""adaptar-destino.py — adapta a arvore do v2 para o repositorio publicado (raiz = projeto).

Substitui o patch `0001-migracao.patch`: um patch fica PINADO na base em que foi gerado, e a base
muda a cada commit da origem (medido: ao avancar o split de 34 para 38 commits o patch deixou de
aplicar). Aqui cada transformacao e' uma substituicao literal com ASSERCAO — se o texto de origem
mudar, o script FALHA e diz qual substituicao, em vez de aplicar torto ou silenciosamente.

Uso:  python3 workspace/migracao/adaptar-destino.py <diretorio-do-destino-despachado>
      (o diretorio deve ja' conter a arvore vinda do split; workspace/ e' copiado pelo
       preparar-destino.sh e nao e' tocado aqui)

Os blocos grandes substituidos sao os 7 assets deste diretorio: destino.gitignore,
destino.gitattributes, README-secao-continuacao.md, README-secao-layout.md, CONTINUITY-secao6.md,
NEXT_TASK-passo-zero.md e MIGRACAO-destino.md. Eles sao revisados a cada rodada da origem; o script
nunca inventa texto: asset ausente ou texto fora do lugar aborta a rodada nomeando a substituicao.
"""
import io
import os
import re
import sys

RAIZ = sys.argv[1] if len(sys.argv) > 1 else "."
AQUI = os.path.dirname(os.path.abspath(__file__))
falhas = []
feitas = 0


def ler(rel):
    with io.open(os.path.join(RAIZ, rel), encoding="utf-8") as f:
        return f.read()


def asset(nome):
    with io.open(os.path.join(AQUI, nome), encoding="utf-8") as f:
        return f.read().rstrip("\n")


def escrever(rel, txt):
    global feitas
    with io.open(os.path.join(RAIZ, rel), "w", encoding="utf-8") as f:
        f.write(txt)
    feitas += 1


def sub(rel, velho, novo, obrigatorio=True):
    """Substituicao literal; exige exatamente 1 ocorrencia (ou nenhuma, se opcional)."""
    global feitas
    s = ler(rel)
    n = s.count(velho)
    if n != 1:
        if obrigatorio:
            falhas.append("%s: esperava 1 ocorrencia, achei %d — %r" % (rel, n, velho[:70]))
        return
    escrever(rel, s.replace(velho, novo, 1))
    feitas += 1


def sub_re(rel, padrao, novo, flags=re.S):
    """Substituicao por padrao; exige exatamente 1 casamento (falha nomeando se houver 0 ou 2)."""
    global feitas
    s = ler(rel)
    n = len(re.findall(padrao, s, flags))
    if n != 1:
        falhas.append("%s: esperava 1 casamento, achei %d — %r" % (rel, n, padrao[:70]))
        return
    escrever(rel, re.sub(padrao, lambda m: novo, s, count=1, flags=flags))
    feitas += 1


def escrever_de(rel, arquivo_origem):
    escrever(rel, asset(arquivo_origem) + "\n")


CABECALHO = u"""
> **Layout desta publicação (migração de 2026-10-12).** Este repositório é a árvore `recriado/` do
> monorepo `heldergaraujo2/Muserver` publicada na **raiz**. Onde um destes documentos escrever
> `recriado/X` (inclusive em registros históricos), leia-se `X`; `workspace/` mantém o mesmo caminho
> relativo. A referência `MuServer/` (~615 MB, do fornecedor) **não** viaja com a reconstrução: as
> etapas que dependem dela (`pe`, `data`, `cfg`, `ref-intacta`, `interop` camada 3, `lua`) saem
> **BLOCKED** — e bloqueado não é
> aprovado. Detalhes, exclusões, hashes e como publicar: `docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`.
"""

# ------------------------------------------------------------------ 1. cabecalho nos canonicos
for doc in ("docs/CONTINUITY.md", "docs/CURRENT_STATE.md", "docs/NEXT_TASK.md", "docs/DECISIONS.md",
            "docs/CHANGELOG.md", "docs/ENVIRONMENT.md", "docs/ROADMAP.md"):
    s = ler(doc)
    if "Layout desta publicação" in s:
        continue                                    # idempotente
    linhas = s.split("\n")
    escrever(doc, linhas[0] + "\n" + CABECALHO + "\n".join(linhas[1:]))
    feitas += 1

# ------------------------------------------------------------------ 2. caminhos de workspace
for doc in os.listdir(os.path.join(RAIZ, "docs")):
    if not doc.endswith(".md"):
        continue
    rel = "docs/" + doc
    s = ler(rel)
    if "../../workspace/" in s:
        escrever(rel, s.replace("../../workspace/", "../workspace/"))
        feitas += 1

# ------------------------------------------------------------------ 3. .gitignore / .gitattributes
escrever_de(".gitignore", "destino.gitignore")
escrever_de(".gitattributes", "destino.gitattributes")

# ------------------------------------------------------------------ 4. Makefile
sub("Makefile",
    "# Makefile do v2 (mu2). Build sempre fora da raiz (build/, ignorado por recriado/.gitignore),",
    "# Makefile do v2 (mu2). Build sempre fora da raiz (out/, ignorado por .gitignore),")

# ------------------------------------------------------------------ 5. README (entry point)
sub("README.md",
    "Portão único: `make -s gate` → 18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED (339 asserções, 22 etapas).",
    "Portão único: `make -s gate` → 18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED (339 asserções, 22 etapas) **no monorepo de origem**; **neste repositório publicado: 14 PASS, 0 FAIL, 6 BLOCKED, 2 SKIPPED, 281 asserções** — as 6 BLOCKED são as etapas que exigem a referência `MuServer/`, que não viaja.")
sub("README.md",
    "cd recriado\nmake -s build          # out/wire.o, out/mud2, out/mu2ctl, out/netclient (ASAN+UBSAN+-Werror)\nmake -s gate           # PORTAO UNICO: 22 etapas, mesa de estados, 339 assercoes",
    "make -s build          # out/wire.o, out/mud2, out/mu2ctl, out/netclient (ASAN+UBSAN+-Werror)\nmake -s gate           # PORTAO UNICO: 22 etapas, mesa de estados, 339 assercoes (281 aqui; 6 etapas BLOCKED sem a referencia)")
sub("README.md",
    "Portão de build: `make -s check` → 182 asserções, 0 falhas. Teste do portão: `make -s gate-selftest` → 19/19.",
    "Portão de build: `make -s check` → 182 asserções, 0 falhas, **no monorepo de origem** (`pe`/`data`\ndependem da referência e aqui saem BLOCKED); teste do portão: `make -s gate-selftest` → 19/19.")
sub_re("README.md",
       r"## Por que mora dentro de `Muserver/` \(e não num clone irmão\)\n.*?sem contorno daqui\.",
       asset("README-secao-continuacao.md"))
sub_re("README.md",
       r"## Layout\n\n```\ndocs/.*?`interop` exige binário original em execução \(\*\*BLOCKED\*\*\)\.",
       asset("README-secao-layout.md"))

# ------------------------------------------------------------------ 6. CONTINUITY (§6/§7/§8)
sub("docs/CONTINUITY.md", "`recriado/out/`): conferir", "`out/`): conferir")
sub("docs/CONTINUITY.md",
    "O bundle contém **apenas** a árvore `recriado/`. A cópia independente do repositório\n"
    "publicado é outra (escopo diferente, decisão D2-38): ela é regravada **dentro** do destino por\n"
    "`workspace/migracao/preparar-destino.sh` e restaura a árvore publicada, não o monorepo.",
    "O bundle contém **apenas** a árvore do projeto (o v2). A cópia independente do repositório\n"
    "publicado é outra (escopo diferente, decisão D2-38): ela é regravada **dentro** do destino e\n"
    "restaura a árvore publicada, não o monorepo.")
sub("docs/CONTINUITY.md", "snapshot orphan da árvore `recriado/`", "snapshot orphan da árvore do projeto")
sub("docs/CONTINUITY.md",
    "| pe / data | `make -s pe` · `make -s data` | 14 e 21 casos, 0 falhas |",
    "| pe / data | `make -s pe` · `make -s data` | 14 e 21 casos, 0 falhas **no monorepo**; aqui saem `BLOCKED` (a referência não viaja) |")
sub("docs/CONTINUITY.md",
    "| persistência | `FULL=1 bash scripts/verify-backup.sh` | **15/15** (opt-in; o portão padrão marca `SKIPPED`) |",
    "| persistência | `FULL=1 bash scripts/verify-backup.sh` | **15/15** no monorepo (opt-in; o portão padrão marca `SKIPPED`); aqui, o verificador acusa **a publicação em falta** (falha honesta) e a referência ausente (BLOCKED) |")
sub("docs/CONTINUITY.md",
    "1. Incluir `MuserverRecriado` na seleção da instalação do App GitHub (Contents: Read and write).",
    "1. Incluir `MuserverRecriado` na seleção da instalação do App GitHub (Contents: Read and write).\n   Erro medido: `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`.")
sub_re("docs/CONTINUITY.md", r"## 6\. Último commit e publicação\n.*?\n## 7\.",
       asset("CONTINUITY-secao6.md") + "\n\n## 7.")

# ------------------------------------------------------------------ 7. CURRENT_STATE (mesa)
sub("docs/CURRENT_STATE.md",
    "| HEAD / remoto | atualizado no fim desta unidade (ver §6 do `CONTINUITY.md`); monorepo `arena/cf1de8ce-muserver` == remoto conferido por `git ls-remote` |",
    "| HEAD / remoto | no monorepo de origem: branch `arena/cf1de8ce-muserver`; **neste repositório**: `main`, a publicar (403 no destino) |")
sub("docs/CURRENT_STATE.md",
    "| portão único | `make -s gate` → **18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções, 22 etapas** (medido em ambiente limpo, sem `out/` residual) |",
    "| portão único (monorepo de origem) | `make -s gate` → **18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções, 22 etapas** (medido em ambiente limpo, sem `out/` residual) |\n"
    "| portão único (aqui) | `make -s gate` → **14 PASS, 0 FAIL, 6 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 281 asserções** — as 6 BLOCKED exigem a referência `MuServer/`, que não viaja |")
sub("docs/CURRENT_STATE.md",
    "| integridade | `FULL=1 scripts/verify-backup.sh` → 15/15 |",
    "| integridade | `FULL=1 scripts/verify-backup.sh` → 15/15 no monorepo; aqui, `scripts/verify-backup.sh` acusa **a publicação em falta** (falha honesta) e a referência ausente (BLOCKED) |")

sub("docs/CURRENT_STATE.md",
    "| portão de build | `make -s check` → 182 asserções (unit/make-sintaxe/net/pe/data) |",
    "| portão de build (monorepo de origem) | `make -s check` → 182 asserções (unit/make-sintaxe/net/pe/data); aqui, `pe`/`data` saem BLOCKED e o `check` cobre unit/make-sintaxe/net |")

# ------------------------------------------------------------------ 8. NEXT_TASK (passo zero)
sub_re("docs/NEXT_TASK.md",
       r"## Passo zero \(bloqueado no proprietário\): publicar o destino\n.*?Branch `arena/cf1de8ce-muserver`\.",
       asset("NEXT_TASK-passo-zero.md"))

# ------------------------------------------------------------------ 9. reports/README (evidencia)
sub("reports/README.md",
    "- saida de ferramenta que precisa virar evidenci versionada: **`.tsv`** (dados) e\n  **`.md`** (prosa), ambos dentro de `recriado/reports/`;\n"
    "- saida descartavel, regeneravel ou de um unico run sem valor: **`.raw`** (esta\n  ignorada por `recriado/.gitignore`);",
    "- saida de ferramenta que precisa virar evidenci versionada: **`.tsv`** (dados) e\n  **`.md`** (prosa), ambos dentro de `reports/`;\n"
    "- saida descartavel, regeneravel ou de um unico run sem valor: **`.raw`** (esta\n  ignorada por `.gitignore`);\n"
    "- **os relatorios aqui sao evidencia historica**: foram escritos quando o v2 morava em `recriado/`\n"
    "  dentro do monorepo `heldergaraujo2/Muserver`, e por isso citam `recriado/...` e `../workspace/...`.\n"
    "  Nao foram reescritos na migracao de 2026-10-12 (reescrever evidencia seria adulterar registro):\n"
    "  o mapeamento de caminhos esta em `docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`.\n"
    "- `migracao-destino.tsv` registra a **primeira** rodada da migracao (split de 34 commits); as\n"
    "  medidas da publicacao vigente estao em `workspace/backups/MANIFEST.md` e em\n"
    "  `docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`.")

# ------------------------------------------------------------------ 10. relatorio da migracao
escrever_de("docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md", "MIGRACAO-destino.md")

if falhas:
    print("adaptar-destino: FALHOU (%d substituicao(oes) nao casaram)" % len(falhas))
    for f in falhas:
        print("  - " + f)
    sys.exit(1)
print("adaptar-destino: %d transformacao(oes) aplicadas, nenhuma assercao violada" % feitas)

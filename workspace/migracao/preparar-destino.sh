#!/usr/bin/env bash
# preparar-destino.sh — (re)constroi o repositorio de destino a partir do monorepo, de forma
# reproduzivel, e confere o resultado por conteudo (arvore git), nao por "parece igual".
#
# Uso:  bash workspace/migracao/preparar-destino.sh [destino] [--gate]
#         destino  diretorio onde o repositorio sera criado (padrao /tmp/mu2dest)
#         --gate   roda tambem `make -s gate` no destino (lento; o padrao ja roda `make -s check`)
#
# O QUE ELE FAZ (e o que ele NAO faz)
#   1. split do historico: `git subtree split --prefix=recriado` num clone TEMPORARIO com
#      sparse-checkout (o split exige o diretorio no worktree; a referencia de 615 MB nao e'
#      materializada). O monorepo NAO e' tocado: nenhum ref novo, nenhum objeto escrito nele.
#   2. destino = `git init` + `git fetch file://<clone> mu2-import:main`. Nao e' `git clone`: o clone
#      local copiaria o pack inteiro do monorepo (134 MB, com os blobs do MuServer/) para dentro de
#      um repositorio que nao deve carrega-los (medido; com o fetch by protocol, o .git fica < 1 MB).
#   3. evidencia `workspace/` copiada do monorepo (arquivos rastreados).
#   4. adaptacao da arvore por `adaptar-destino.py` (caminhos, layout e documentos), com uma
#      assercao por substituicao: texto de origem fora do lugar FALHA nomeando a substituicao.
#   5. copia independente regravada DENTRO do destino (snapshot orphan + bundle + MANIFEST), para
#      que o repositorio publicado se restaure sozinho.
#   6. verificacoes: `git bundle verify`, restauracao por clone + `make -s check`, e comparacao da
#      ARVORE final com o valor esperado registrado em ESPERADOS (abaixo).
#
# Nao faz push. Para publicar, ver publicar-destino.sh.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../.." && pwd)
dst=${1:-/tmp/mu2dest}
gate=0
[ "${2:-}" = "--gate" ] && gate=1
if [ "$dst" = "--gate" ]; then dst=/tmp/mu2dest; gate=1; fi

# Valores de referencia desta migracao (medidos no artefato conferido de 2026-10-12, split de 39 commits).
# Reproduzibilidade medida: duas construcoes independentes deram o mesmo HEAD, a mesma arvore e o
# mesmo sha256 de bundle (constantes refixadas apos re-medir). Divergir daqui
# nao e' falha automatica — o conteudo do monorepo pode ter evoluido — mas TEM de ser explicado.
TREE_ESPERADA=${TREE_ESPERADA:-233c2bd08cb37c0f8aa2196831fa99f53a3b8453}
ARQ_ESPERADOS=${ARQ_ESPERADOS:-174}
SHA_ESPERADO=${SHA_ESPERADO:-05b8cff7df066b2aa8b1d5459051f08be768117c1d9d3ef7d6ecc1b5c5fdef98}

ok=0; bad=0
say() { printf '%-38s %s\n' "$1" "$2"; }
chk() { if [ "$2" = ok ]; then ok=$((ok+1)); say "$1" "OK ${3:-}"; else bad=$((bad+1)); say "$1" "FALHA ${3:-}"; fi; }

export GIT_AUTHOR_NAME="Arena Agent" GIT_AUTHOR_EMAIL="agent@arena.local"
export GIT_COMMITTER_NAME="Arena Agent" GIT_COMMITTER_EMAIL="agent@arena.local"
export GIT_AUTHOR_DATE="2026-10-12T12:00:00-03:00" GIT_COMMITTER_DATE="2026-10-12T12:00:00-03:00"

command -v git >/dev/null 2>&1 || { say "git" "ausente"; exit 2; }
[ -d "$root/recriado" ] || { say "monorepo" "nao encontrei $root/recriado"; exit 2; }
[ -d "$root/workspace" ] || { say "workspace" "nao encontrei $root/workspace"; exit 2; }

work=$(mktemp -d /tmp/mu2-split.XXXXXX) || exit 2
trap 'rm -rf "$work"' EXIT INT TERM

say "monorepo" "$root"
say "destino" "$dst"
say "clone temporario" "$work"

# ---- 1. split do historico ---------------------------------------------------------------------
git clone -q --no-checkout --single-branch --branch "$(git -C "$root" rev-parse --abbrev-ref HEAD)" \
    "$root" "$work/split" || { say "clone local" "falhou"; exit 2; }
git -C "$work/split" sparse-checkout init --cone >/dev/null 2>&1
git -C "$work/split" sparse-checkout set recriado >/dev/null 2>&1
git -C "$work/split" checkout -q || { say "checkout do subdiretorio" "falhou"; exit 2; }
split_out=$(git -C "$work/split" subtree split --prefix=recriado -b mu2-import HEAD 2>&1)
split_tip=$(printf '%s\n' "$split_out" | tail -1)
n_split=$(git -C "$work/split" rev-list --count mu2-import 2>/dev/null || echo 0)
[ -n "$split_tip" ] || { say "subtree split" "falhou: $split_out"; exit 2; }
say "split" "$split_tip com $n_split commits"

# ---- 2. destino: init + fetch (nao clone) ------------------------------------------------------
rm -rf "$dst" || { say "limpar destino" "falhou"; exit 2; }
git init -q "$dst" || exit 2
git -C "$dst" fetch -q "file://$work/split" mu2-import:main || { say "fetch do split" "falhou"; exit 2; }
git -C "$dst" checkout -q main || { say "checkout do destino" "falhou"; exit 2; }
say "destino criado em" "$dst"

# ---- 3. evidencia workspace/ -------------------------------------------------------------------
git -C "$root" archive HEAD workspace | tar -x -C "$dst" || { say "copiar workspace" "falhou"; exit 2; }
# `workspace/migracao/` NAO viaja: e' ferramenta da ORIGEM (split, patch, bundle de transporte) e
# dentro do destino seria circular — conteria um bundle do proprio destino. A evidencia que interessa
# (backups, changes, reports, docs, tools, tests, inventory) vai inteira.
rm -rf "$dst/workspace/migracao"
git -C "$dst" add workspace >/dev/null 2>&1
git -C "$dst" commit -q -F - <<'EOF' || { say "commit do workspace" "falhou"; exit 2; }
Publica a evidencia do workspace: mudancas Lua, auditorias, recuperacao e backup restaurável

workspace/ mantem o caminho relativo do monorepo de origem por razao tecnica: o bundle
workspace/backups/mu2-v2.bundle e o que carrega a arvore restauravel, e
scripts/verify-backup.sh, tests/lua.sh, tests/ref_check.sh e tools/lua_probe.py resolvem
workspace/... a partir da raiz do projeto. Mover a evidencia quebraria o manifesto e a
restauracao conferida.

Conteudo: changes/ (baselines originais dos 6 .lua + patch + copia pre-ff), reports/ (auditoria
de continuidade, pedido de recuperacao, busca do v1 perdido, A1-segredos redigido), tools/ e
tests/ da fase de auditoria, inventory/, docs/ historicos e backups/ (bundle + MANIFEST).
Relatorios NAO foram reescritos: sao evidencia do layout de origem (ver reports/README.md).
EOF
say "commit 1" "$(git -C "$dst" rev-parse --short HEAD) workspace"

# ---- 4. adaptacao de layout e documentos -------------------------------------------------------
# O transformador (assercao por substituicao) substitui o patch `0001-migracao.patch`, que ficava
# PINADO na base do split: medido — ao avancar o historico de 34 para 36 commits ele deixou de
# aplicar. Falha aqui nomeia a substituicao que nao casou, sem aplicar parcialmente.
if python3 "$here/adaptar-destino.py" "$dst" >"$work/adaptar.out" 2>&1; then
  st=ok
else
  st=bad
fi
sed 's/^/  /' "$work/adaptar.out" 2>/dev/null
chk "adaptador do destino (com assercao)" "$st"
[ "$st" = ok ] || { say "diagnostico" "veja $work/adaptar.out"; exit 2; }
git -C "$dst" add .gitignore .gitattributes Makefile README.md docs reports/README.md >/dev/null 2>&1
git -C "$dst" commit -q -F - <<'EOF' || { say "commit da adaptacao" "falhou"; exit 2; }
Adapta a raiz publicada: caminhos, layout e documentos canonicos

O repositorio publicado E a arvore do v2 (nao ha mais o nivel `recriado/`): documentos canonicos
ganham o mapeamento de caminhos, README perde o `cd recriado`, CONTINUITY registra o estado real
da publicacao, NEXT_TASK ganha o passo zero (publicar), reports/README registra que os relatorios
sao evidencia historica e nao foram reescritos. .gitignore/.gitattributes proprios do destino
(regras de MuServer/** sairam; politica de bytes conservadora). Adaptacao por
workspace/migracao/adaptar-destino.py: cada substituicao tem assercao propria e falha nomeando o
texto que nao casou (o patch anterior ficava pinado na base do split). Relatorio completo em
docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md.
EOF
say "commit 2" "$(git -C "$dst" rev-parse --short HEAD) adaptacao"

# ---- 5. copia independente do destino ----------------------------------------------------------
snap=$(git -C "$dst" commit-tree "HEAD^{tree}" -m "snapshot orphan da arvore publicada (v2) — 2026-10-12")
git -C "$dst" branch -f mu2-snapshot "$snap" >/dev/null 2>&1
rm -f "$dst/workspace/backups/mu2-v2.bundle"
git -C "$dst" bundle create workspace/backups/mu2-v2.bundle mu2-snapshot >/dev/null 2>&1 || {
  say "gerar bundle" "falhou"; exit 2; }
sha=$(sha256sum "$dst/workspace/backups/mu2-v2.bundle" | cut -d' ' -f1)
tam=$(stat -c%s "$dst/workspace/backups/mu2-v2.bundle")
n=$(git -C "$dst" ls-tree -r --name-only HEAD | grep -vc '^workspace/backups/mu2-v2.bundle$')
sed -e "s/@ARQUIVOS@/$((n + 1))/g" -e "s/@TIP@/$snap/g" -e "s/@SIZE@/$tam/g" \
    -e "s/@SHA@/$sha/g" -e "s/@TREE@/$(git -C "$dst" rev-parse HEAD^{tree})/g" \
    "$here/MANIFEST-destino.template.md" > "$dst/workspace/backups/MANIFEST.md"
git -C "$dst" add workspace/backups/MANIFEST.md workspace/backups/mu2-v2.bundle >/dev/null 2>&1
git -C "$dst" commit -q -F - <<EOF || { say "commit do backup" "falhou"; exit 2; }
Regrava a copia independente a partir da arvore publicada (snapshot $snap, $tam B)

O snapshot deixa de ser gerado no monorepo de origem e passa a ser um orphan commit da arvore
DESTE repositorio: a copia restaurável agora cobre o que foi publicado (inclusive a evidencia
workspace/), e o MANIFEST registra a historia do artefato sem reescreve-la.

sha256: $sha
ponta: $snap
Teste: git bundle verify ok; git clone -b mu2-snapshot => make -s check sem falhas.
EOF
say "commit 3" "$(git -C "$dst" rev-parse --short HEAD) backup"
say "bundle" "$tam B  sha256 ${sha:0:16}..."
say "ponta do snapshot" "$snap"

# ---- 6. verificacoes ---------------------------------------------------------------------------
if git -C "$dst" bundle verify workspace/backups/mu2-v2.bundle >/dev/null 2>&1; then st=ok; else st=bad; fi
chk "bundle: git bundle verify" "$st"
if [ "$sha" = "$SHA_ESPERADO" ]; then st=ok; else st=bad; fi
chk "bundle: sha256 reproduzido" "$st" "${sha:0:16}... (esperado ${SHA_ESPERADO:0:16}...)"
tree=$(git -C "$dst" rev-parse "HEAD^{tree}")
if [ "$tree" = "$TREE_ESPERADA" ]; then st=ok; else st=bad; fi
chk "arvore final == conferida em 2026-10-12" "$st" "$tree"
na=$(git -C "$dst" ls-files | wc -l)
if [ "$na" = "$ARQ_ESPERADOS" ]; then st=ok; else st=bad; fi
chk "arquivos rastreados" "$st" "$na (esperado $ARQ_ESPERADOS)"

rest=$(mktemp -d /tmp/mu2-restore.XXXXXX)
if git clone -q --no-hardlinks -b mu2-snapshot "$dst/workspace/backups/mu2-v2.bundle" "$rest/r" 2>/dev/null \
   && (cd "$rest/r" && make -s check >/dev/null 2>&1); then st=ok; else st=bad; fi
chk "restauracao do bundle + make check" "$st" "$(cd "$rest/r" 2>/dev/null && git ls-files | wc -l) arquivos"
rm -rf "$rest"

if [ "$gate" = 1 ]; then
  ( cd "$dst" && make -s gate >"$work/gate.out" 2>&1 )
  res=$(grep -E '^PASS=' "$work/gate.out" | tail -1)
  say "make -s gate" "${res:-sem resumo (ver $work/gate.out)}"
  say "  nao_testado" "$(grep -E '^nao_testado=' "$work/gate.out" | tail -1 | cut -c1-140)"
fi

say "HEAD do destino" "$(git -C "$dst" rev-parse HEAD)"
say "commits/arquivos" "$(git -C "$dst" rev-list --count HEAD) commits, $na arquivos"
echo "——— ok=$ok falhas=$bad ———"
[ "$bad" -eq 0 ] || echo "Divergência do registro esperado: explique antes de publicar (TREE_ESPERADA=... pode ser sobreposta por env)."
exit $((bad > 0))

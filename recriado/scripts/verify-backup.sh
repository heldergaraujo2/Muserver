#!/usr/bin/env bash
# verify-backup.sh — o invariante da D2-09, executavel e com saida legivel.
# Um backup que nao foi restaurado de verdade nao e um backup; uma rodada que nao
# conferiu o SHA remoto nao e uma rodada entregue.
# Uso:  bash recriado/scripts/verify-backup.sh          (a partir da raiz do repo)
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"; root="$(cd "$here/.." && pwd)"; cd "$root" || exit 2
ok=0; bad=0
say() { printf '%-34s %s\n' "$1" "$2"; }
chk() { if [ "$2" = ok ]; then ok=$((ok+1)); say "$1" "OK ${3:-}"; else bad=$((bad+1)); say "$1" "FALHA ${3:-}"; fi; }

# 1) HEAD local
local_sha=$(git rev-parse HEAD)
say "HEAD local" "$local_sha"

# 2) o remoto da sessao tem exatamente este commit?
branch=$(git rev-parse --abbrev-ref HEAD)
remote_sha=$(git ls-remote origin "refs/heads/$branch" 2>/dev/null | awk '{print $1}')
if [ -n "$remote_sha" ] && [ "$remote_sha" = "$local_sha" ]; then st=ok; else st=bad; fi
chk "publicacao: origin/$branch" "$st" "remoto=${remote_sha:-ninguem}"

# 3) arvore limpa nos caminhos do v2 (nada escrito sem comitar)
dirty=$(git status --porcelain -- recriado | head -3)
if [ -z "$dirty" ]; then st=ok; else st=bad; fi
chk "arvore recriado/ limpa" "$st" "${dirty:-}"

# 4) o bundle de backup existe, verifica, e o hash bate com o MANIFEST.
#    Ele mora em workspace/backups/ e NAO dentro de recriado/: o bundle e gerado a partir
#    do subtree split de recriado/, entao aloja-lo la dentro faria cada regravacao embutir a
#    anterior (medido: 17 225 -> 38 233 -> 66 195 -> 134 694 bytes, ~2x por rodada, e o limite de
#    persistencia da plataforma e ~128 MB somados). Fora da arvore dividida o custo e constante.
bundle=workspace/backups/mu2-v2.bundle
if [ -f "$bundle" ]; then
  if out=$(git bundle verify "$bundle" 2>&1); then st=ok; else st=bad; fi
  chk "bundle: git bundle verify" "$st" "$(printf '%s' "$out" | grep -aoE '[0-9]+ objects?.*' | head -1)"
  want=$(awk '/^sha256:/{print $2}' workspace/backups/MANIFEST.md 2>/dev/null)
  got=$(sha256sum "$bundle" | cut -d' ' -f1)
  if [ -n "$want" ] && [ "$want" = "$got" ]; then st=ok; else st=bad; fi
  chk "bundle: sha256 do MANIFEST" "$st" "${got:0:16}..."
  # 5) restauracao real: clonar o bundle (snapshot orphan, branch mu2-snapshot) num diretorio
#    descartavel e comparar o conjunto de arquivos rastreados.
#    O proprio diretorio backup/ fica de fora da comparacao: ele contem o bundle, e o
#    bundle nao pode conter a si mesmo (o historico coberto e ate o commit anterior).
  tmp=$(mktemp -d /tmp/mu2-restore.XXXXXX)
  a=""; b=""
  # -b mu2-v2 e obrigatorio: o bundle leva so esse ref, e o HEAD remoto do clone apontaria
      # para um main inexistente (a ausencia deste -b deixou o clone sem arvore na 1a versao do teste).
      if git clone -q --no-hardlinks -b mu2-snapshot "$bundle" "$tmp/clone" 2>/dev/null; then
    # o bundle carrega a arvore do subtree split (recriado/ vira a raiz). Compara-se o CONJUNTO de
    # arquivos rastreados: o conteudo do commit do bundle e o commit anterior, por construcao (o
    # bundle nao pode conter a si mesmo) - por isso a integridade de conteudo e conferida pelo
    # SHA de ponta do bundle contra o MANIFEST, logo abaixo.
    a=$(git ls-tree -r --name-only HEAD -- recriado | grep -v "^recriado/backup/" | sed 's|^recriado/||' | sort | sha256sum | cut -c1-16)
    b=$(cd "$tmp/clone" && git ls-tree -r --name-only HEAD 2>/dev/null | grep -v "^backup/" | sort | sha256sum | cut -c1-16)
    if [ -n "$b" ] && [ "$a" = "$b" ]; then st=ok; else st=bad; fi
    chk "restauracao por clone" "$st" "arvore=$a"
    n=$(git ls-tree -r --name-only HEAD -- recriado | grep -vc "^recriado/backup/")
    say "  arquivos do v2 no bundle" "$n"
  else
    chk "restauracao por clone" bad "git clone do bundle falhou"
  fi
  # 6) ponta do bundle == SHA registrado no MANIFEST (integridade de conteudo do snapshot)
  tip=$(git bundle list-heads "$bundle" 2>/dev/null | awk '{print $1}')
  want_tip=$(awk -F'`' '/branch (local criada|do snapshot)/{print $4}' workspace/backups/MANIFEST.md 2>/dev/null)
  if [ -n "$tip" ] && [ -n "$want_tip" ] && case "$tip" in "$want_tip"*) true;; *) false;; esac; then st=ok; else st=bad; fi
  chk "bundle: ponta == MANIFEST" "$st" "${tip:0:7} vs ${want_tip:-?}"
  rm -rf "$tmp"
else
  chk "bundle presente" bad "$bundle ausente"
fi

# 7) a referencia original esta intacta? Ela e somente leitura e nenhuma rodada pode toca-la.
mu_want=fade04615fabd17778a0e2fd7adf032c8386c924
mu_tree=$(git rev-parse HEAD:MuServer 2>/dev/null)
mu_dirty=$(git status --porcelain -- MuServer | wc -l)
if [ "$mu_tree" = "$mu_want" ] && [ "$mu_dirty" = 0 ]; then st=ok; else st=bad; fi
chk "referencia MuServer/ intacta" "$st" "tree=${mu_tree:0:7} alteracoes=$mu_dirty"

# 8) documentos de continuidade presentes: um agente novo tem de achar o estado sem ler chat.
missing=""
for d in recriado/docs/CONTINUITY.md recriado/docs/CURRENT_STATE.md recriado/docs/NEXT_TASK.md \
         recriado/docs/DECISIONS.md recriado/docs/CHANGELOG.md recriado/docs/ENVIRONMENT.md \
         recriado/docs/ROADMAP.md workspace/backups/MANIFEST.md; do
  [ -f "$d" ] || missing="$missing ${d#recriado/docs/}"
done
if [ -z "$missing" ]; then st=ok; else st=bad; fi
chk "documentos de continuidade" "$st" "${missing:-todos presentes}"

# 9) evidencia nao pode morar em caminho ignorado pelo git (a armadilha ja custou trabalho antes:
#    workspace/reports/*.json e recriado/reports/*.raw sao ignorados e simplesmente nao persistem).
lost=$(git status --porcelain --ignored=matching -- recriado/reports workspace/reports 2>/dev/null \
       | grep '^!!' | grep -v '/$' | head -3)
if [ -z "$lost" ]; then st=ok; else st=bad; fi
chk "nenhuma evidencia em caminho ignorado" "$st" "${lost:-}"

# 10) FULL=1: a prova que importa — o bundle como ele existe DEPOIS do push, lido de um clone do
#    remoto. Foi assim que apareceu o CRLF que corrompia o blob comitado sem tocar no worktree.
if [ "${FULL:-0}" = 1 ]; then
  tf=$(mktemp -d)
  if git clone -q --depth 2 --single-branch -b "$branch" "https://github.com/heldergaraujo2/Muserver.git" "$tf/remote" 2>/dev/null; then
    rsha=$(cd "$tf/remote" && sha256sum workspace/backups/mu2-v2.bundle 2>/dev/null | cut -c1-16)
    lsha=$(sha256sum "$bundle" | cut -c1-16)
    if [ -n "$rsha" ] && [ "$rsha" = "$lsha" ]; then st=ok; else st=bad; fi
    chk "publicado: bundle byte a byte" "$st" "remoto=${rsha:-?} local=${lsha:0:16}"
    if (cd "$tf/remote" && git bundle verify workspace/backups/mu2-v2.bundle >/dev/null 2>&1); then st=ok; else st=bad; fi
    chk "publicado: bundle verify no clone" "$st"
    if (cd "$tf/remote" && git clone -q --no-hardlinks -b mu2-snapshot workspace/backups/mu2-v2.bundle restored 2>/dev/null && [ -f restored/src/wire.c ]); then
      st=ok
    else
      st=bad
    fi
    chk "publicado: restaurar arvore a partir do bundle clonado" "$st"
    rsha_head=$(cd "$tf/remote" && git rev-parse HEAD)
    if [ "${rsha_head#"$local_sha"}" != "$rsha_head" ]; then st=ok; else st=bad; fi
    chk "publicado: HEAD local esta no remoto" "$st" "${rsha_head:0:7}"
  else
    chk "clone do remoto para FULL" bad "falhou (sem rede ou sem autorizacao: registrar bloqueio, nao afirmar publicacao)"
  fi
  rm -rf "$tf"
fi

echo "——— ok=$ok falhas=$bad ———"
[ "$bad" -eq 0 ] || echo "Bloqueio registrado: rodada sem publicacao/backup conferidos NAO conta como entregue (D2-09)."
exit $((bad>0))

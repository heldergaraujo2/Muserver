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

# 4) o bundle de backup existe, verifica, e o hash bate com o MANIFEST
bundle=recriado/backup/mu2-v2.bundle
if [ -f "$bundle" ]; then
  if out=$(git bundle verify "$bundle" 2>&1); then st=ok; else st=bad; fi
  chk "bundle: git bundle verify" "$st" "$(printf '%s' "$out" | grep -aoE '[0-9]+ objects?.*' | head -1)"
  want=$(awk '/^sha256:/{print $2}' recriado/backup/MANIFEST.md 2>/dev/null)
  got=$(sha256sum "$bundle" | cut -d' ' -f1)
  if [ -n "$want" ] && [ "$want" = "$got" ]; then st=ok; else st=bad; fi
  chk "bundle: sha256 do MANIFEST" "$st" "${got:0:16}..."
  # 5) restauracao real: clonar o bundle num diretorio descartavel e comparar a arvore v2.
#    O proprio diretorio backup/ fica de fora da comparacao: ele contem o bundle, e o
#    bundle nao pode conter a si mesmo (o historico coberto e ate o commit anterior).
  tmp=$(mktemp -d /tmp/mu2-restore.XXXXXX)
  if git clone -q --no-hardlinks "$bundle" "$tmp/clone" 2>/dev/null; then
    a=$(git ls-tree -r --name-only HEAD -- recriado | grep -v "^recriado/backup/" | sort | sha256sum | cut -c1-16)
    b=$(cd "$tmp/clone" && git ls-tree -r --name-only HEAD -- recriado 2>/dev/null | grep -v "^recriado/backup/" | sort | sha256sum | cut -c1-16)
    if [ -n "$b" ] && [ "$a" = "$b" ]; then st=ok; else st=bad; fi
    chk "restauracao por clone" "$st" "arvore=$a"
    n=$(git ls-tree -r --name-only HEAD -- recriado | grep -vc "^recriado/backup/")
    say "  arquivos do v2 no bundle" "$n"
  else
    chk "restauracao por clone" bad "git clone do bundle falhou"
  fi
  rm -rf "$tmp"
else
  chk "bundle presente" bad "$bundle ausente"
fi

echo "——— ok=$ok falhas=$bad ———"
[ "$bad" -eq 0 ] || echo "Bloqueio registrado: rodada sem publicacao/backup conferidos NAO conta como entregue (D2-09)."
exit $((bad>0))

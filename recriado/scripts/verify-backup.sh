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
  want_tip=$(awk -F'`' '/branch local criada/{print $4}' workspace/backups/MANIFEST.md 2>/dev/null)
  if [ -n "$tip" ] && [ -n "$want_tip" ] && case "$tip" in "$want_tip"*) true;; *) false;; esac; then st=ok; else st=bad; fi
  chk "bundle: ponta == MANIFEST" "$st" "${tip:0:7} vs ${want_tip:-?}"
  rm -rf "$tmp"
else
  chk "bundle presente" bad "$bundle ausente"
fi

echo "——— ok=$ok falhas=$bad ———"
[ "$bad" -eq 0 ] || echo "Bloqueio registrado: rodada sem publicacao/backup conferidos NAO conta como entregue (D2-09)."
exit $((bad>0))

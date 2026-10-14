#!/usr/bin/env bash
# publicar-destino.sh — publica o repositorio de destino e CONFERE o que foi publicado.
#
# Uso:  bash workspace/migracao/publicar-destino.sh [diretorio-do-destino]
#         (padrao: /tmp/mu2dest, exatamente o que preparar-destino.sh cria)
#
# O script existe porque "deu certo" nao e' evidencia: ele faz push, le de volta com `git ls-remote`,
# clona o remoto num diretorio temporario e roda o portao no clone — so' entao afirma publicacao.
#
# ATENCAO (estado medido em 2026-10-12): o push para `heldergaraujo2/MuserverRecriado` responde
#   403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2
# e a API responde `Resource not accessible by integration` NO DESTINO (no repo de origem, normal).
# Isso e' a selecao de repositorios da INSTALACAO DO GITHUB APP, nao a permissao do usuario (a ACL
# do usuario diz push=true nos dois repos). Nao ha contorno: o proprietario precisa incluir
# `MuserverRecriado` na instalacao com *Contents: Read and write*. Este script NAO tenta burlar
# permissao, NAO usa force push e NAO repete a tentativa em laco — ele para e reporta.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dst=${1:-/tmp/mu2dest}
url=${DESTINO_URL:-https://github.com/heldergaraujo2/MuserverRecriado.git}
branch=main
ok=0; bad=0
say() { printf '%-34s %s\n' "$1" "$2"; }
chk() { if [ "$2" = ok ]; then ok=$((ok+1)); say "$1" "OK ${3:-}"; else bad=$((bad+1)); say "$1" "FALHA ${3:-}"; fi; }

[ -d "$dst/.git" ] || { say "destino" "nao e' repositorio git: $dst (rode preparar-destino.sh)"; exit 2; }
cd "$dst" || exit 2
local_sha=$(git rev-parse HEAD)
say "HEAD local" "$local_sha"
say "remote" "$url"

# 1) push (uma tentativa). A mensagem de erro e' repassada ao usuario como veio — sem contorno.
if out=$(git push "$url" "$branch:$branch" 2>&1); then
  chk "push" ok
else
  chk "push" bad
  printf '%s\n' "$out" | sed -n '1,6p'
  echo
  echo "BLOQUEIO DE PERMISSAO. Nada foi publicado; o destino continua como estava."
  echo "Acao do proprietario: incluir MuserverRecriado na instalacao do GitHub App (Contents: Read and write)."
  echo "Diagnostico ja medido: 403 denied para o usuario; 'Resource not accessible by integration' na API do destino."
  exit 1
fi

# 2) le de volta: o SHA remoto tem de ser exatamente o local.
remote_sha=$(git ls-remote "$url" "refs/heads/$branch" | awk '{print $1}')
if [ -n "$remote_sha" ] && [ "$remote_sha" = "$local_sha" ]; then st=ok; else st=bad; fi
chk "ls-remote confere" "$st" "${remote_sha:-ninguem}"

# 3) clone independente do remoto + portao no clone (a prova que o dono pediu).
tf=$(mktemp -d)
if git clone -q --single-branch -b "$branch" "$url" "$tf/r" 2>/dev/null; then st=ok; else st=bad; fi
chk "clone independente do remoto" "$st" "$tf/r"
if [ "$st" = ok ]; then
  a=$(cd "$tf/r" && git ls-tree -r --name-only HEAD | sort | sha256sum | cut -c1-16)
  b=$(git ls-tree -r --name-only HEAD | sort | sha256sum | cut -c1-16)
  if [ -n "$a" ] && [ "$a" = "$b" ]; then st2=ok; else st2=bad; fi
  chk "inventario remoto == local" "$st2" "$a"
  ( cd "$tf/r" && make -s gate >"$tf/gate.out" 2>&1 )
  say "portao no clone" "$(grep -E '^PASS=' "$tf/gate.out" | tail -1)"
  say "  nao_testado" "$(grep -E '^nao_testado=' "$tf/gate.out" | tail -1 | cut -c1-140)"
  ( cd "$tf/r" && FULL=1 bash scripts/verify-backup.sh ) 2>&1 | tail -4
fi
say "limpeza" "rm -rf $tf (manual: guarde se quiser a evidencia do clone)"
echo "——— ok=$ok falhas=$bad ———"
[ "$bad" -eq 0 ] || echo "Publicacao NAO confirmada. Nada foi afirmado alem do que o ls-remote mostrou."
exit $((bad > 0))

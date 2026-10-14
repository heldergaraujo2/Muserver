#!/usr/bin/env bash
# Tira artefatos nao-fonte do INDICE do git sem apagar do disco.
# Nao reescreve historico. Rode APRES de:
#   1. workspace/tools/recover_tmp_lua.py   (os .tmp contem a unica copia de um script)
#   2. preservar os dumps usados no laudo:  git add -f MuServer/GameServer/*.dmp
#   3. tratar o incidente das credenciais/PII (DB/*.bak) - ver docs/NEXT_TASK.md T1
# Para reduzir o historico de verdade e preciso git-filter-repo + force-push,
# o que e decisao do dono do repositorio (ver DECISIONS.md D-05).
set -eu
cd "$(dirname "$0")/../.."
if [ "${1:-}" != "--apply" ]; then
  echo "SIMULACAO (dry-run). Passe --apply para executar."
  DRY=echo
else DRY=; fi
$DRY git rm -r --cached --quiet --ignore-unmatch \
  "$(find MuServer -type d -name LOG -printf '%p ')" 2>/dev/null || true
for pat in '*.log' '*.dmp' '*.tmp' '*.bak'; do
  files=$(git ls-files -- 'MuServer' | grep -E "\.${pat#\*}\$" || true)
  [ -n "$files" ] && { echo "$files" | wc -l | xargs echo "  a remover do indice:"; }
done
echo
echo "Passos recomendados (por etapa, conferindo entre elas):"
echo "  git rm -r --cached --ignore-unmatch MuServer/**/LOG"
echo "  git rm --cached --ignore-unmatch $(git ls-files "MuServer/**/*.bak")"
echo "  git rm --cached \$(git ls-files 'MuServer/**/*.tmp')"
echo "  git commit -m 'chore(repo): remove artefatos de runtime do indice'"
echo "  git count-objects -vH   # comparar antes/depois"

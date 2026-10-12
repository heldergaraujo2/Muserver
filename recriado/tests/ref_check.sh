#!/usr/bin/env bash
# ref_check.sh — prova, por medição e somente leitura, que a referência original não foi tocada.
#
# O portão precisa desta etapa porque "não escrevi em MuServer/" é afirmação que só vale medida.
# O invariante forte é a árvore git: conteúdo, nomes e estrutura mudando ⇒ hash da árvore muda.
# As âncoras de conteúdo (caso 5) pegam o caso que a árvore sozinha não pega: alguém modificar a
# referência **e** commitar. Os valores esperados vêm de `reports/r5-pe.tsv`, evidência publicada
# na R-5 — não de uma constante chutada aqui.
#
# Contrato de saída: `# ref-intacta=<n> falhas=<f> blocked=<b>`
#   blocked=1 quando a referência não existe neste ambiente (restore de bundle): ausência de objeto
#   a verificar não é aprovação.
set -u
# caminhos derivados do proprio script: valem tanto no repositorio (raiz/recriado) quanto num
# restore de bundle (onde a raiz ja E a arvore recriado/ e nao existe o prefixo).
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$(cd "$V2/.." && pwd)
REF=${MU_REF_DATA:-$ROOT/MuServer}
n=0; bad=0
ESPERADA=fade04615fabd17778a0e2fd7adf032c8386c924   # árvore publicada: contrato fixo
ESPERADOS_ARQ=10021
EVID=$V2/reports/r5-pe.tsv

ck() { n=$((n+1)); if "$3" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi; }

if [ ! -d "$REF" ]; then
  printf '1..0\n# ref-intacta=0 falhas=0 blocked=1\n'
  printf '# BLOCKED motivo=referencia ausente em %s\n' "$REF"
  exit 0
fi
cd "$V2" || exit 2
G="git -C $ROOT"

t01() { [ "$($G rev-parse HEAD:MuServer)" = "$ESPERADA" ]; }
t02() { [ "$($G status --porcelain -- MuServer | wc -l)" = 0 ]; }
t03() { $G diff --quiet HEAD -- MuServer; }
t04() { [ "$($G ls-tree -r --name-only HEAD:MuServer | wc -l)" = "$ESPERADOS_ARQ" ]; }
# 5. âncoras de conteúdo: tamanho + sha256_16 conferidos contra a evidência da R-5
t05() { [ -r "$EVID" ] || return 1
        local f esperado got
        for f in ConnectServer/ConnectServer.exe GameServer/GameServer.exe \
                 DataServer/DataServer.exe ConnectServer/ConnectServer_old.exe; do
          esperado=$(awk -F'\t' -v p="$f" '$1==p {print $2"|"$3; exit}' "$EVID")
          [ -n "$esperado" ] || return 1
          [ -f "$REF/$f" ] || return 1
          got="$(stat -c%s "$REF/$f")|$(sha256sum "$REF/$f" | cut -c1-16)"
          [ "$got" = "$esperado" ] || return 1
        done; }
# 6. nada de novo (arquivo untracked) apareceu dentro da referência
t06() { [ "$($G status --porcelain -- MuServer | grep -c '^??')" = 0 ]; }

ck 1 "arvore git de MuServer/ == $ESPERADA" t01
ck 2 "nenhuma alteracao nao commitada em MuServer/ (inclui untracked)" t02
ck 3 "git diff HEAD -- MuServer vazio" t03
ck 4 "contagem de arquivos rastreados == $ESPERADOS_ARQ" t04
ck 5 "ancoras de conteudo (tamanho+sha256_16 de 4 PE) batem com reports/r5-pe.tsv" t05
ck 6 "nenhum arquivo novo dentro da referencia" t06

printf '1..%d\n# ref-intacta=%d falhas=%d blocked=0\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1

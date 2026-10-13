#!/usr/bin/env bash
# matriz.sh — regressão do defeito `net-matrix` × `persistencia` (achado do auditor, corrigido em
# 2026-10-13). Sem `set -e`: cada caso decide por si.
#
# O defeito, medido antes da correção: a etapa `net-matrix` (GATE_FULL=1) gravava a matriz em
# `reports/net-{orig,mur0}.tsv` — arquivos VERSIONADOS — e a etapa seguinte, `persistencia`, exige
# `git status --porcelain` limpo. Resultado: `FULL=1 make -s gate` dava FAIL por construção
# (19 PASS / 1 FAIL / 3 BLOCKED), e o único jeito de ficar verde era pular a própria etapa.
#
# A correção isola o artefato: a matriz escreve em `out/` (ignorado pelo git) e só o alvo explícito
# `make net-matrix-publish` escreve em `reports/`. Esta suíte cobra as duas metades dessa promessa —
# inclusive a que é fácil esquecer: que o critério de "árvore limpa" da etapa `persistencia` CONTINUA
# detectando sujeira real. Um portão que deixa de detectar não é portão.
#
# Contrato de saída: `# matriz-artefatos=<n> falhas=<f> blocked=0`
set -u
cd "$(dirname "$0")/.." || exit 2

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
n=0; bad=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

# O criterio e "a CORRIDA nao mexeu em reports/", medido por antes-e-depois — nao "reports/ esta
# vazio". A versao anterior comparava com a string vazia e acusava falha por um relatorio novo
# (legitimo, ainda nao commitado) que existia antes da corrida e nao tinha nada a ver com ela.
# Criterio que mede a coisa errada reprova trabalho certo: e o mesmo defeito que a suite combate, do
# outro lado.
sujo_reports() { git status --porcelain -- reports/ | sort | md5sum | cut -c1-12; }
REP_ANTES=$(sujo_reports)

CONFIG_RAPIDA="1 10 0 0 0"
PUB=reports/net-orig.tsv
SHA_ANTES=$(sha256sum "$PUB" | cut -c1-16)

# ---------------------------------------------------------------- preservacao de terceiros
# Defeito real, medido em 2026-10-13 no `make -s gate-full`: a etapa `net-matrix` roda ANTES desta e
# produziu a matriz completa em `out/net-matrix/`; o `rm -rf out/net-matrix` daqui APAGAVA o trabalho
# da etapa anterior (e o `persistencia`, que vem depois, encontrava a pasta vazia). Suite que sabota
# outra etapa do proprio portao e defeito, nao limpeza. Agora: tira-se um retrato do diretorio, o
# sentinela garante que o caso "sobreviveu" vale SEMPRE (mesmo sem artefato previo) e o retrato e
# restaurado no fim — inclusive o que ja estava la e nao era nosso.
SENT=out/net-matrix/.sentinela-matriz-artefatos
CRIOU_DIR=0
[ -d out/net-matrix ] || { mkdir -p out/net-matrix; CRIOU_DIR=1; }
: > "$SENT"
cp -a out/net-matrix "$T/antes"
restaura_artefatos() { rm -rf out/net-matrix; cp -a "$T/antes" out/net-matrix; }

# ------------------------------------------------------------------ 1) os alvos, como declarados
make -n net-matrix > "$T/nm.txt" 2>&1
make -n net-matrix-publish > "$T/nmp.txt" 2>&1

ck "alvo net-matrix (rodado pelo portao) grava em out/net-matrix, nunca em reports/" \
   'grep -q "NET_REPORT_DIR=out/net-matrix" "$T/nm.txt" && ! grep -q "NET_REPORT_DIR=reports" "$T/nm.txt"'
ck "alvo net-matrix-publish e o unico caminho explicito para reports/" \
   'grep -q "NET_REPORT_DIR=reports" "$T/nmp.txt"'

# ------------------------------------------------------------------ 2) execução real, reduzida
# NET_CONFIGS limita a matriz a UMA configuração: o que está em teste é o DESTINO do artefato,
# não o volume. NET_REPS=1 idem.
export DEST="$T/destino"
mkdir -p "$DEST"
NET_QUICK=0 NET_REPORT_DIR="$DEST" NET_PROFILE=orig NET_REPS=1 NET_CONFIGS="$CONFIG_RAPIDA" \
  bash tests/net.sh > "$T/run1.log" 2>&1
export RC1=$?

ck "matriz completa (QUICK=0) com destino explicito roda e sai 0" \
   '[ "$RC1" -eq 0 ]'
ck "artefato nasceu no destino pedido, com cabecalho e colunas do contrato" \
   '[ -s "$DEST/net-orig.tsv" ] && grep -q "^perfil	" "$DEST/net-orig.tsv" &&
    grep -q "perda_sem_fechamento" "$DEST/net-orig.tsv"'
ck "linha da configuracao pedida esta no artefato (valores conferidos, nao so o arquivo)" \
   'awk -F"\t" "\$2==1 && \$3==10 && \$4==0 && \$5==0 && \$6==0 {achou=1} END{exit !achou}" "$DEST/net-orig.tsv"'
ck "rodada com destino explicito nao muda o estado de reports/" \
   '[ "$(sujo_reports)" = "$REP_ANTES" ]'

# default de uma corrida completa sem override: out/net-matrix (e nunca reports/).
# Sem apagar nada antes: o caso mede a ESTRUTURA do arquivo produzido (1 configuracao x 1 repeticao =
# exatamente 1 linha de dados), que e falsificavel mesmo com artefato alheio ja presente.
NET_QUICK=0 NET_PROFILE=orig NET_REPS=1 NET_CONFIGS="$CONFIG_RAPIDA" \
  bash tests/net.sh > "$T/run2.log" 2>&1

ck "sem destino explicito, QUICK=0 usa out/net-matrix/ (ignorado pelo git)" \
   '[ -s out/net-matrix/net-orig.tsv ] && [ "$(sujo_reports)" = "$REP_ANTES" ]'
ck "o arquivo do destino padrao e o desta corrida (1 config x 1 repeticao = 1 linha de dados)" \
   '[ "$(grep -c "^orig" out/net-matrix/net-orig.tsv)" -eq 1 ]'

# ------------------------------------------------------------------ 3) o critério continua detectando
# A metade que não pode ser esquecida: escrita DELIBERADA em reports/ tem de sujar a árvore e ser
# detectada pela etapa `persistencia`. Publica-se de verdade (sobrescreve o arquivo versionado),
# mede-se a detecção e RESTAURA-SE, com a restauração conferida por sha256.
NET_QUICK=0 NET_REPORT_DIR=reports NET_PROFILE=orig NET_REPS=1 NET_CONFIGS="$CONFIG_RAPIDA" \
  bash tests/net.sh > "$T/run3.log" 2>&1
export PUBLICOU=$?
export SUJO=$(git status --porcelain -- reports/ | wc -l)
# A marca tem de ser lida AQUI: a restauracao logo abaixo apaga o sinal, e medir depois dela daria
# "nao modificado" em qualquer caso — teste que mede no instante errado aprova por acidente.
export MARCADO=$(git status --porcelain -- "$PUB" | wc -l)
git checkout -- "$PUB" 2>/dev/null
export SHA_DEPOIS=$(sha256sum "$PUB" | cut -c1-16)

# O criterio aqui e por ARQUIVO: o `git status --porcelain` nao muda de texto quando o conteudo de
# um arquivo ja modificado muda de novo, entao "hash do status" nao serve para esta metade. O que
# prova a deteccao e o arquivo versionado aparecer como modificado, e depois voltar a nao aparecer.
ck "publicacao deliberada deixa o arquivo versionado marcado como modificado (o criterio detecta)" \
   '[ "$PUBLICOU" -eq 0 ] && [ "$SUJO" -gt 0 ] && [ "$MARCADO" -gt 0 ]'
ck "artefato publicado restaurado e identico ao original (sha256 antes == depois)" \
   '[ "$SHA_ANTES" = "$SHA_DEPOIS" ]'
ck "depois da restauracao o estado de reports/ volta ao de antes" \
   '[ -z "$(git status --porcelain -- "$PUB")" ] && [ "$(sujo_reports)" = "$REP_ANTES" ]'

ck "artefato de outra etapa em out/net-matrix sobreviveu (a suite nao sabota o portao)" \
   '[ -e "$SENT" ]'

restaura_artefatos
if [ "$CRIOU_DIR" = 1 ]; then
  rm -rf out/net-matrix
else
  rm -f "$SENT"
fi

printf '1..%d\n# matriz-artefatos=%d falhas=%d blocked=0\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1

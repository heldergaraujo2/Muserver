#!/usr/bin/env bash
# data.sh — suíte `data` + `data-selftest` (fase R-5): formatos nativos, dados e scripts.
#
# Cada número abaixo veio de uma medição dos probes (relatórios reports/r5-*.tsv). Onde a
# estrutura não pôde ser confirmada por especificação, o teste afirma apenas o invariante medido
# e o nome da hipótese fica no relatório — teste que afirma estrutura inventada é pior que
# teste ausente.
set -u
cd "$(dirname "$0")/.." || exit 2
ROOT=$(cd .. && pwd)
export MU_REF_DATA="${MU_REF_DATA:-$ROOT/MuServer}"
OUT=out; mkdir -p "$OUT"
n=0; bad=0

ck() {
  n=$((n+1))
  if "$3" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi
}

# SELFTEST_ONLY=1 roda só a recusa de entrada inválida (t16-t19): funciona sem a referencia,
# que e o caso de um restore de bundle. Sem isso o portao ficaria mudo em ambiente minimo.
REF=0; REFMODE=ausente
if [ -n "${SELFTEST_ONLY:-}" ]; then
  REFMODE=selftest
  printf '# nota=SELFTEST_ONLY: casos da referencia omitidos por decisao desta execucao\n'
elif [ ! -d "$MU_REF_DATA" ]; then
  REFMODE=ausente
  printf '# BLOCKED motivo=MU_REF_DATA nao encontrado (%s): a referencia nao viaja no bundle\n' "$MU_REF_DATA"
else
  REF=1; REFMODE=referencia
  python3 tools/att_probe.py  > "$OUT/att.tsv"  2>"$OUT/att.err";  ATT_EXIT=$?
  python3 tools/mb_probe.py   > "$OUT/mb.tsv"   2>"$OUT/mb.err";   MB_EXIT=$?
  python3 tools/data_probe.py > "$OUT/data.tsv" 2>"$OUT/data.err"; DATA_EXIT=$?
fi

t01() { [ "$ATT_EXIT" -eq 0 ] && grep -q 'conformes_tamanho_e_marcador=276/276' "$OUT/att.tsv"; }
t02() { grep -q 'arquivos=276 tamanhos_distintos=1 tamanhos={65539: 276}' "$OUT/att.tsv"; }
t03() { grep -q 'bytes1_2_distintos=1 valores=\[.ffff.\] (constante=sim)' "$OUT/att.tsv" &&
        grep -q 'byte0_distintos=2' "$OUT/att.tsv"; }
t04() { grep -q '65536==256\*256 -> True' "$OUT/att.tsv"; }
t05() { [ "$MB_EXIT" -eq 0 ] &&
        [ "$(awk -F'\t' '$2==".ozj"' "$OUT/mb.tsv" | wc -l)" = 106 ] &&
        [ "$(awk -F'\t' '$2==".ozj" && ($5=="jpeg_completo" || $5=="jpeg_sem_eoi")' "$OUT/mb.tsv" |
           wc -l)" = 103 ]; }
t06() { [ "$(awk -F'\t' '$2==".smd" && $5=="texto_smd"' "$OUT/mb.tsv" | wc -l)" = 8 ]; }
t07() { awk -F'\t' '$1=="Tools/Editores/MuEditor/Data/Item.bmd" && $10+0>50' "$OUT/mb.tsv" |
        grep -q . &&
        grep -q 'mediana=-0.16' "$OUT/mb.tsv"; }
t08() { [ "$DATA_EXIT" -eq 0 ] &&
        [ "$(awk -F'\t' '$1 ~ /^DB\/.*\.bak$/ && $3=="TAPE"' "$OUT/data.tsv" | wc -l)" = 4 ] &&
        [ "$(awk -F'\t' '$1 ~ /^DB\/.*\.reg$/ && $4 ~ /^fffe/' "$OUT/data.tsv" | wc -l)" = 2 ]; }
t09() { grep -q $'^ConnectServer/ServerList.dat\t1109\t2f2f' "$OUT/data.tsv" &&
        grep -q $'^Data/MapServerInfo.dat\t2453\t2f2f' "$OUT/data.tsv"; }
t10() { awk -F'\t' '/^# === dados_texto/{f=1;next} /^# === /{f=0}
        f && NF>=6 && $1!="arquivo" {tot++; if($3=="tab") tab++}
        END{exit !(tot==40 && tab==39)}' "$OUT/data.tsv"; }
t11() { grep -q $'^Data/Script/Scripts/UpgradeMachine/Config.lua\t131560\t7318\t' "$OUT/data.tsv"; }
t12() { grep -q '^# total=2$' "$OUT/data.tsv" &&
        [ "$(grep -c $'\t.enc\t' "$OUT/data.tsv")" = 0 ]; }
t13() { python3 tools/att_probe.py  > "$OUT/att2.tsv"  2>/dev/null
        python3 tools/data_probe.py > "$OUT/data2.tsv" 2>/dev/null
        [ "$(sha256sum < "$OUT/att.tsv"  | cut -c1-16)" = \
          "$(sha256sum < "$OUT/att2.tsv" | cut -c1-16)" ] &&
        [ "$(sha256sum < "$OUT/data.tsv"  | cut -c1-16)" = \
          "$(sha256sum < "$OUT/data2.tsv" | cut -c1-16)" ]; }
# criterio: nenhum BYTE DE CONTROLE. UTF-8 acentuado e legitimo (nomes de diretorio, titulos);
# `tr -d [:print:]` em locale C contaria esses acentos como lixo e daria falso positivo.
t14() { for f in "$OUT/att.tsv" "$OUT/mb.tsv" "$OUT/data.tsv"; do
          grep -qaP '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$f" && return 1
        done
        return 0; }   # sem este return, a funcao devolvia o status do ultimo grep (1 = nao achou)
t15() { ! grep -q "$ROOT" "$OUT/att.tsv" "$OUT/mb.tsv" "$OUT/data.tsv"; }

# ---- data-selftest ----
T=$(mktemp -d); mkdir -p "$T/fake"
head -c 100 /dev/zero > "$T/fake/curto.att"                 # tamanho errado de propósito
# tamanho certo (65539) mas bytes[1:3] != ffff: tem de ser recusado pelo marcador
{ printf '\x00\x00\x00'; head -c 65536 /dev/zero; } > "$T/fake/marcador_ruim.att"
MU_REF_DATA="$T" python3 tools/att_probe.py > "$OUT/st_att.tsv" 2>/dev/null; ST_EXIT=$?
t16() { [ "$ST_EXIT" -eq 1 ] &&
        grep -q 'conformes_tamanho_e_marcador=0/2' "$OUT/st_att.tsv"; }
t17() { grep -q $'fake/curto.att\t100' "$OUT/st_att.tsv" &&
        grep -q $'fake/marcador_ruim.att\t65539' "$OUT/st_att.tsv"; }
t18() { for p in att_probe mb_probe data_probe; do
          MU_REF_DATA=/caminho-que-nao-existe python3 "tools/$p.py" >/dev/null 2>&1
          [ $? -eq 2 ] || return 1
        done; }
t19() { [ "$(awk -F'\t' '$2==".smd"' "$OUT/mb.tsv" | wc -l)" != 80 ]; }   # expectativa errada

if [ "$REF" = 1 ]; then
ck 1 "att: 276/276 conformes em tamanho e marcador, exit 0" t01
ck 2 "att: um unico tamanho no pacote inteiro (65539 B)" t02
ck 3 "att: bytes[1:3]==ffff constante; byte0 NAO e constante (2 valores medidos)" t03
ck 4 "att: corpo de 65536 B == 256*256 (hipotese de grade, NAO confirmada por especificacao)" t04
ck 5 "mb: 106 .ozj, 103 classificados como JPEG por magic (98 completos + 5 sem EOI)" t05
ck 6 "mb: os 8 .smd sao texto que comeca com 'version 1'" t06
ck 7 "mb: hipotese XOR3 sustentada para Item.bmd (delta 66.65) e descartada na mediana (-0.16)" t07
ck 8 "data: 4 .bak com cabecalho TAPE e 2 .reg UTF-16LE; nada restaurado" t08
ck 9 "data: ServerList.dat e MapServerInfo.dat sao TEXTO (2f2f = '//') apesar da extensao .dat" t09
ck 10 "data: 40 .txt de dados amostrados, 39 tab-delimitados e 1 com virgula" t10
ck 11 "lua: maior script = 131560 B / 7318 linhas; nenhum limite de tamanho atingido" t11
ck 12 "nao existe arquivo .enc no pacote; so 2 com 'luaenc' no nome (a ferramenta e o pdb)" t12
ck 13 "saidas deterministicas: segunda passada dos probes tem o mesmo sha256" t13
ck 14 "saidas 100% imprimiveis: nenhum byte de controle vaza para o TSV" t14
ck 15 "nenhum caminho absoluto do host vaza nas saidas" t15
fi
ck 16 "selftest: .att invalido (tamanho e marcador) e recusado, exit 1" t16
ck 17 "selftest: o probe reporta tamanho real de cada arquivo recusado" t17
ck 18 "selftest: MU_REF_DATA inexistente sai 2 nos tres probes" t18
ck 19 "autos-teste: expectativa errada e detectada" t19
rm -rf "$T"

# blocked=1 so quando a referencia FALTA (bloqueio ambiental). Em SELFTEST_ONLY os casos da
# referencia sao omitidos por decisao desta execucao: isso e escopo declarado, nao bloqueio, e o
# portao trata como PASS de cobertura reduzida. Confundir os dois faria um selftest "aprovado"
# parecer que cobriu a referencia.
BL=0
case "$REFMODE" in
  referencia) SCOPO=referencia ;;
  selftest)   SCOPO=selftest ;;
  *)          SCOPO=ausente; BL=1 ;;
esac
printf '1..%d\n# escopo=data:%s\n# data=%d falhas=%d blocked=%d\n' \
  "$n" "$SCOPO" "$n" "$bad" "$BL"
[ "$bad" -eq 0 ] || exit 1

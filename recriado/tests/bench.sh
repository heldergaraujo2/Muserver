#!/usr/bin/env bash
# bench.sh — baseline EXPLORATÓRIA de desempenho (fase R-7).
#
# ROTULO OBRIGATÓRIO, e não é formalidade: **não existe requisito de desempenho definido pelo
# dono**. Nenhum número daqui é critério de aceitação, meta de produção ou "o desempenho do
# servidor". O objetivo é ter uma medição reproduzível que torne regressão visível no mesmo host
# e na mesma configuração.
#
# Critérios de validade, declarados ANTES de rodar (e cobrados por tools/bench_check.py, que é
# separado de quem mede de propósito — quem mede não pode ser quem julga se a medição vale):
#   REPS repetições, WARMUP primeiras descartadas como aquecimento;
#   DRIFT_MAX_PCT de desvio máximo entre uma repetição medida e a mediana — acima disso o
#   resultado é BLOCKED por ambiente (host de 2 vCPUs compartilhadas), não número publicado;
#   perda de quadro é FALHA, não ambiente (exit 3 do validador);
#   latência é LIMITE SUPERIOR: tools/rtt_probe.py é um cliente Python e o custo dele está dentro.
#
# B5 mede um LIMITE, não uma meta: a fila de resposta tem UMA vaga (D2-05) e o contrato fecha a
# conexão que faz pipeline além do que os buffers do socket absorvem. O cenário existe para que o
# número esteja registrado e para que o serviço prove que sobrevive a isso.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
MUD2=$V2/out/mud2; CTL=$V2/out/mu2ctl; CLI=$V2/out/netclient
LOG=$V2/out/bench.log; TSV=$V2/out/bench.tsv; QF=$V2/out/bench-stats-queries.txt
CONTAB=$V2/out/bench-contab.txt; B2DIR=$V2/out/bench-b2
REPS=5; WARMUP=1; DRIFT_MAX_PCT=25
# BENCH_FRAMES existe para experimentar a janela de medicao sem editar o roteiro: foi assim que se
# mediu que 2000 quadros (~20 ms por repeticao) davam drift de 40% e 20000 (~85 ms) dao ~10%.
FRAMES=${BENCH_FRAMES:-20000}; BODY=64; BATCH=64; CONNS=8; CONN_FRAMES=2000
RTT_FRAMES=500; RTT_WARMUP=20; B4_FRAMES=1000
B5_FRAMES=2000; B5_BODY=2048
n=0; bad=0; BL=0; SENT=0; SRV_EXIT=1
# "${@:3}" (e nao "$3") para que a funcao testada possa receber argumento, como em "contabilidade B1".
ck() { n=$((n+1)); if "${@:3}" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi; }

for b in "$MUD2" "$CTL" "$CLI"; do
  [ -x "$b" ] || { printf '1..0\n# bench=0 falhas=0 blocked=1\n# BLOCKED motivo=falta %s\n' "$b"; exit 0; }
done
[ -f "$V2/tools/bench_check.py" ] && [ -f "$V2/tools/rtt_probe.py" ] || {
  printf '1..0\n# bench=0 falhas=0 blocked=1\n# BLOCKED motivo=ferramenta de medicao ausente\n'; exit 0; }
command -v python3 >/dev/null 2>&1 || {
  printf '1..0\n# bench=0 falhas=0 blocked=1\n# BLOCKED motivo=python3 ausente\n'; exit 0; }

SRV_PID=0; PORT=0
start_srv() {
  rm -f "$LOG" "$QF"; SENT=0   # contadores do servico nascem zerados: os meus tambem
  "$MUD2" --port 0 --log-file "$LOG" "$@" >/dev/null 2>&1 &
  SRV_PID=$!; PORT=0
  for _ in $(seq 1 200); do
    PORT=$(awk '/listen addr=/{for(i=1;i<=NF;i++) if($i ~ /^port=/){sub(/port=/,"",$i); print $i}}' \
           "$LOG" 2>/dev/null)
    [ -n "$PORT" ] && break; sleep 0.02
  done
}
stop_srv() { [ "$SRV_PID" -gt 0 ] || return 0
  kill -TERM "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; SRV_EXIT=$?; SRV_PID=0; }
trap 'stop_srv' EXIT
# Cada leitura de contador é UM quadro STATS no fio. Contar em arquivo porque $(st ...) roda em
# subshell e um contador em variável se perderia — a contabilidade da F19 depende disto.
st() { printf 'q\n' >> "$QF"; "$CTL" stats --port "$PORT" --profile orig 2>/dev/null |
       tr ' ' '\n' | awk -F= -v k="$1" '$1==k{print $2}'; }

# F19 — contabilidade por instância. O quadro STATS conta no `frames` do serviço; se alguém medir
# throughput por esse contador em vez dos quadros do cliente, a diferença aparece aqui.
contabilidade() {
  SRV_FRAMES=$(st frames)
  CONSULTAS=$(wc -l < "$QF" 2>/dev/null | tr -d ' ' || echo 0)
  # Em arquivo porque ck() silencia a saida da funcao testada: a evidencia tem de sobreviver.
  printf 'contabilidade[%s]: frames_servico=%s quadros_dos_clientes=%s consultas_stats=%s\n' \
    "$1" "${SRV_FRAMES:-?}" "$SENT" "${CONSULTAS:-0}" >> "$CONTAB"
  [ "${SRV_FRAMES:-0}" = $((SENT + ${CONSULTAS:-0})) ]
}

# ---------------------------------------------------------------- ambiente (medido, não suposto)
CPU=$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null || echo desconhecida)
SAN=desconhecido
if ldd "$MUD2" 2>/dev/null | grep -q libasan; then SAN=address,undefined
elif nm -D "$MUD2" 2>/dev/null | grep -q __asan; then SAN=address,undefined
elif ldd "$MUD2" >/dev/null 2>&1; then SAN=nenhum; fi
printf '# ambiente: nproc=%s cpu=%s kernel=%s cc=%s sanitizadores=%s\n' \
  "$(nproc 2>/dev/null || echo '?')" "$CPU" "$(uname -r)" \
  "$(cc -dumpversion 2>/dev/null || echo '?')" "$SAN"
printf '# criterio: reps=%d warmup=%d drift_max_pct=%s frames=%d corpo=%d lote=%d conns=%d\n' \
  "$REPS" "$WARMUP" "$DRIFT_MAX_PCT" "$FRAMES" "$BODY" "$BATCH" "$CONNS"
printf '# aviso: latencia e limite superior (inclui o cliente Python)\n'
printf '# aviso: NENHUM numero aqui e criterio de aceitacao\n'
printf 'cenario\trepeticao\tenviados\trecebidos\tms\tquadros_por_s\tbytes_por_s\tresultado\tp50_us\tp95_us\tp99_us\n' > "$TSV"
rm -rf "$B2DIR"; rm -f "$CONTAB"; mkdir -p "$B2DIR"

# taxa = "-" quando nao ha janela de tempo: um zero numa coluna numerica le-se como medicao, e o
# cenario B3 (latencia) nao mede throughput nenhum.
taxa() { awk -v f="$1" -v b="$2" -v m="$3" -v fmt="$4" \
  'BEGIN{ if (m ~ /^[0-9]+([.][0-9]+)?$/ && m+0 > 0) printf fmt, f*b*1000/m; else printf "-"; }'; }
linha() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$1" "$2" "$3" "$4" "$5" \
  "$(taxa "$4" 1 "$5" '%.1f')" "$(taxa "$4" "$6" "$5" '%.0f')" \
  "$7" "${8:--}" "${9:--}" "${10:--}" >> "$TSV"; }

# ---------------------------------------------------------------- B1 throughput, 1 conexao
start_srv --profile orig
[ "$PORT" -gt 0 ] || { printf '1..0\n# bench=0 falhas=0 blocked=1\n# BLOCKED motivo=servico nao subiu\n'; exit 1; }
B1_OK=0
for r in $(seq 1 "$REPS"); do
  t0=$(date +%s%3N)
  R=$("$CLI" --port "$PORT" --frames "$FRAMES" --code 2 --body-size "$BODY" --batch "$BATCH" \
       --expect "$FRAMES" --timeout-ms 60000 2>&1)
  t1=$(date +%s%3N); ms=$((t1 - t0))
  rec=$(printf '%s' "$R" | sed -n 's/^recebidos=\([0-9]*\).*/\1/p')
  res=NAO_OK; if [ "${rec:-0}" = "$FRAMES" ] && printf '%s' "$R" | grep -q 'resultado=OK'
    then res=OK; B1_OK=$((B1_OK+1)); fi
  SENT=$((SENT + FRAMES))
  linha B1 "$r" "$FRAMES" "${rec:-0}" "$ms" "$((BODY+4))" "$res"
done
t01() { [ "$B1_OK" -eq "$REPS" ]; }
ck 1 "B1 throughput 1 conexao: $FRAMES quadros ida-e-volta completos em $REPS de $REPS repeticoes" t01
ck 2 "F19 contabilidade em B1: frames do servico = quadros dos clientes + consultas STATS" contabilidade B1
stop_srv

# ---------------------------------------------------------------- B2 throughput agregado
start_srv --profile orig
B2_T0=$(date +%s%3N); PIDS=""
for c in $(seq 1 "$CONNS"); do
  "$CLI" --port "$PORT" --frames "$CONN_FRAMES" --code 2 --body-size "$BODY" --batch "$BATCH" \
    --expect "$CONN_FRAMES" --timeout-ms 60000 > "$B2DIR/$c.txt" 2>&1 &
  PIDS="$PIDS $!"
done
for p in $PIDS; do wait "$p"; done
B2_T1=$(date +%s%3N); B2_MS=$((B2_T1 - B2_T0))
B2_REC=0
for c in $(seq 1 "$CONNS"); do
  r=$(sed -n 's/^recebidos=\([0-9]*\).*/\1/p' "$B2DIR/$c.txt" 2>/dev/null)
  B2_REC=$((B2_REC + ${r:-0}))
done
SENT=$((SENT + CONNS * CONN_FRAMES))
linha B2 1 "$((CONNS * CONN_FRAMES))" "$B2_REC" "$B2_MS" "$((BODY+4))" \
  "$( [ "$B2_REC" = "$((CONNS * CONN_FRAMES))" ] && echo OK || echo NAO_OK )"
t02() { [ "$B2_REC" = $((CONNS * CONN_FRAMES)) ]; }
ck 3 "B2 $CONNS conexoes paralelas: $((CONNS*CONN_FRAMES)) quadros entregues, nenhum perdido" t02
stop_srv

# ---------------------------------------------------------------- B3 latencia (limite superior)
start_srv --profile orig
RTT=$(python3 "$V2/tools/rtt_probe.py" --port "$PORT" --frames "$RTT_FRAMES" \
      --body-size "$BODY" --warmup "$RTT_WARMUP" 2>/dev/null); RC_RTT=$?
P50=$(printf '%s' "$RTT" | sed -n 's/.*rtt_p50_us=\([0-9.]*\).*/\1/p')
P95=$(printf '%s' "$RTT" | sed -n 's/.*rtt_p95_us=\([0-9.]*\).*/\1/p')
P99=$(printf '%s' "$RTT" | sed -n 's/.*rtt_p99_us=\([0-9.]*\).*/\1/p')
SENT=$((SENT + RTT_FRAMES + RTT_WARMUP))
printf '# B3 rtt_us: p50=%s p95=%s p99=%s medidos=%s erros=%s (limite superior)\n' \
  "$P50" "$P95" "$P99" "$(printf '%s' "$RTT" | sed -n 's/^quadros=\([0-9]*\).*/\1/p')" \
  "$(printf '%s' "$RTT" | sed -n 's/.*erros=\([0-9]*\).*/\1/p')"
linha B3 1 "$RTT_FRAMES" "$RTT_FRAMES" - - "$( [ "$RC_RTT" = 0 ] && echo OK || echo NAO_OK )" \
  "${P50:-0}" "${P95:-0}" "${P99:-0}"
t03() { [ "$RC_RTT" -eq 0 ]; }
ck 4 "B3 $RTT_FRAMES ida-e-volta completas, 0 erros (aquecimento de $RTT_WARMUP descartado)" t03
t04() { awk -v a="${P50:-0}" -v b="${P95:-0}" -v c="${P99:-0}" 'BEGIN{exit !(a>0 && a<=b && b<=c)}'; }
ck 5 "B3 percentis coerentes: 0 < p50 <= p95 <= p99" t04
stop_srv

# ---------------------------------------------------------------- B4 custo por tamanho de corpo
# Em PASSO-TRANCADO real (um quadro no fio, espera a resposta inteira, só então o próximo), que é o
# que tools/rtt_probe.py faz. O netclient não serve aqui: ele envia tudo ANTES de começar a ler, e
# com corpo de 2048 B o volume não lido estoura a fila de uma vaga — mediria a capacidade (cenário
# B5) e não o custo do corpo. Medido: com --batch 1 e 5000 quadros de 2048 B chegaram 59 de 5000.
start_srv --profile orig
B4_OK=0
for B in 64 2048; do
  R=$(python3 "$V2/tools/rtt_probe.py" --port "$PORT" --frames "$B4_FRAMES" \
      --body-size "$B" --warmup "$RTT_WARMUP" 2>/dev/null)
  RC4=$?
  rec=$(printf '%s' "$R" | sed -n 's/^quadros=\([0-9]*\).*/\1/p')
  err=$(printf '%s' "$R" | sed -n 's/.* erros=\([0-9]*\).*/\1/p')
  jan=$(printf '%s' "$R" | sed -n 's/.*janela_ms=\([0-9.]*\).*/\1/p')
  q50=$(printf '%s' "$R" | sed -n 's/.*rtt_p50_us=\([0-9.]*\).*/\1/p')
  q95=$(printf '%s' "$R" | sed -n 's/.*rtt_p95_us=\([0-9.]*\).*/\1/p')
  q99=$(printf '%s' "$R" | sed -n 's/.*rtt_p99_us=\([0-9.]*\).*/\1/p')
  SENT=$((SENT + B4_FRAMES + RTT_WARMUP))
  res=NAO_OK; if [ "$RC4" = 0 ] && [ "${err:-1}" = 0 ] && [ "${rec:-0}" = "$B4_FRAMES" ]
    then res=OK; B4_OK=$((B4_OK+1)); fi
  linha "B4-corpo$B" 1 "$B4_FRAMES" "${rec:-0}" "${jan:-0}" "$((B+4))" "$res" \
    "${q50:-0}" "${q95:-0}" "${q99:-0}"
done
printf '# B4 passo-trancado: o custo do cliente Python domina nesta faixa, entao a diferenca\n'
printf '#    entre corpo 64 e 2048 NAO e separavel com este cliente (ver relatorio)\n'
t05() { [ "$B4_OK" = 2 ]; }
ck 6 "B4 corpo 64 e corpo 2048: $B4_FRAMES quadros em passo-trancado nos dois, 0 erros" t05
QF_B4=$(st queue_full_closes)
t06() { [ "${QF_B4:-1}" = 0 ]; }
ck 7 "nenhum queue_full_closes de B1 a B4 (carga dentro da capacidade dos buffers)" t06
ck 8 "F19 contabilidade em B4: frames do servico = quadros dos clientes + consultas STATS" contabilidade B4
MAUS=$(grep -c 'close=\(write_error\|bad_frame\|queue_full\|socket_error\|encode_error\|stats_error\)' \
       "$LOG" 2>/dev/null || true)
t07() { [ "${MAUS:-0}" = 0 ]; }
ck 9 "nenhum fechamento por erro de B1 a B4 (write_error/bad_frame/queue_full/socket_error)" t07
stop_srv

# ---------------------------------------------------------------- B5 limite: fila de uma vaga
start_srv --profile orig
# --rcvbuf 1024 e o que torna o cenario DETERMINISTICO. Sem ele, os 4 MB do pipeline cabiam nos
# buffers do socket e o queue_full simplesmente nao acontecia (medido: 1 falha em 15 corridas, com
# close=socket_error no lugar de close=queue_full). Um teste que aposta em corrida nao e teste.
B5=$("$CLI" --port "$PORT" --rcvbuf 1024 --frames "$B5_FRAMES" --code 2 --body-size "$B5_BODY" \
     --batch "$B5_FRAMES" --expect 0 --never-read --eof-wait-ms 2000 --timeout-ms 30000 2>&1)
B5_EOF=$(printf '%s' "$B5" | sed -n 's/.*eof=\([0-9]*\).*/\1/p')
printf '# B5 pipeline de %s quadros de %s B sem ler: eof=%s (o servico fechou a conexao)\n' \
  "$B5_FRAMES" "$B5_BODY" "${B5_EOF:-?}"
linha B5 1 "$B5_FRAMES" 0 - - "$( [ "${B5_EOF:-0}" = 1 ] && echo FECHADA || echo ABERTA )"
t08() { [ "${B5_EOF:-0}" = 1 ]; }
ck 10 "B5 pipeline alem dos buffers: o cliente observa o FIN (contrato D2-05, nao queda silenciosa)" t08
B5_QF=$(st queue_full_closes)
t09() { [ "${B5_QF:-0}" -ge 1 ] && grep -q 'close=queue_full' "$LOG"; }
ck 11 "B5 o servico classifica a causa: queue_full_closes>=1 e close=queue_full no log" t09
VIVO=$("$CLI" --port "$PORT" --frames 1 --code 1 --expect 1 --timeout-ms 5000 2>&1)
t10() { printf '%s' "$VIVO" | grep -q 'resultado=OK'; }
ck 12 "B5 o servico continua vivo e responde a um PING novo depois do fechamento" t10
linha B5-pos 1 1 1 - - "$(printf '%s' "$VIVO" | grep -q 'resultado=OK' && echo OK || echo NAO_OK)"
stop_srv
t11() { [ "$SRV_EXIT" = 0 ]; }
ck 13 "servico encerrado por SIGTERM sai 0 ao fim da bateria" t11

# ---------------------------------------------------------------- critérios de validade
VOUT=$(python3 "$V2/tools/bench_check.py" "$TSV" --reps "$REPS" --warmup "$WARMUP" \
       --drift-max "$DRIFT_MAX_PCT" --ignorar B5 2>&1); VRC=$?
printf '%s\n' "$VOUT" | sed 's/^/# /'
[ "$VRC" -eq 1 ] && BL=1
[ "$VRC" -gt 1 ] && bad=$((bad+1))
t12() { [ "$VRC" -le 1 ]; }
ck 14 "validador de criterios: drift dentro de ${DRIFT_MAX_PCT}% e sem perda de quadro" t12
sed 's/^/# /' "$CONTAB" 2>/dev/null

# ---------------------------------------------------------------- F18: o validador é falsificável
# Se o critério de drift for neutralizado, o validador tem de deixar de reclamar — e é essa mudança
# de comportamento que prova que o critério existe. Sem este caso, apagar a comparação do drift
# passaria despercebido e um número instável viraria "baseline".
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; stop_srv' EXIT
{ printf 'cenario\trepeticao\tenviados\trecebidos\tms\tquadros_por_s\tbytes_por_s\tresultado\tp50_us\tp95_us\tp99_us\n'
  printf 'B1\t1\t100\t100\t100\t1000\t1000\tOK\t-\t-\t-\n'
  printf 'B1\t2\t100\t100\t100\t1000\t1000\tOK\t-\t-\t-\n'
  printf 'B1\t3\t100\t100\t400\t250\t250\tOK\t-\t-\t-\n'
} > "$TMPD/instavel.tsv"
sed 's/drift_ok = drift <= a.drift_max/drift_ok = True/' "$V2/tools/bench_check.py" \
  > "$TMPD/bench_check_mutado.py"
python3 "$V2/tools/bench_check.py" "$TMPD/instavel.tsv" --reps 3 --warmup 1 --drift-max 25 \
  >/dev/null 2>&1; RC_REAL=$?
python3 "$TMPD/bench_check_mutado.py" "$TMPD/instavel.tsv" --reps 3 --warmup 1 --drift-max 25 \
  >/dev/null 2>&1; RC_MUT=$?
t13() { [ "$RC_REAL" = 1 ] && [ "$RC_MUT" = 0 ]; }
ck 15 "F18 validador bloqueia drift de 300% (exit 1) e o mutado sem o criterio nao bloqueia (exit 0)" t13

printf '1..%d\n# escopo=bench:baseline-exploratoria\n# bench=%d falhas=%d blocked=%d\n' \
  "$n" "$n" "$bad" "$BL"
printf '# relatorio=out/bench.tsv host_vcpus=%s\n' "$(nproc 2>/dev/null || echo '?')"
[ "$bad" -eq 0 ] || exit 1

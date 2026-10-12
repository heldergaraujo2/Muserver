#!/usr/bin/env bash
# net.sh — suíte de rede da R-4: o servico mud2, o controlador mu2ctl e o cliente de ensaio.
#
# Sem `set -e` de proposito: cada verificacao decide por si, e um cenario que falha nao pode
# esconder os seguintes (regra de portao deste projeto: blocked != aprovado, e falha silenciosa
# e pior que falha declarada).
#
# O que esta suíte prova, e onde cada coisa esta escrita:
#   D2-05  fila de 1 vaga, fechamento com log proprio, contador queue_full_closes;
#   D2-14  POLLOUT sempre que ha resposta pendente: quem le atrasado recebe TUDO com
#          queue_full_closes == 0; quem nao le nada e pede de novo produz o fechamento;
#   D2-16  opcodes e motivos de fechamento (`close=<motivo>`) como vocabulario do log.
#
# Classificacao obrigatoria: toda linha `close=` do log tem de cair num motivo conhecido, e
# nenhuma resposta perdida pode ficar sem um fechamento que a explique. Sem isso o caso nao vale.
set -u
cd "$(dirname "$0")/.." || exit 2

OUT=out
MUD2=$OUT/mud2
CTL=$OUT/mu2ctl
CLI=$OUT/netclient
LOG=$OUT/net-server.log
TMP=$OUT/net-tmp

QUICK=${NET_QUICK:-1}
REPS=${NET_REPS:-}
[ -n "$REPS" ] || { [ "$QUICK" = 1 ] && REPS=2 || REPS=5; }
PROFILES=${NET_PROFILE:-}
[ -n "$PROFILES" ] || { [ "$QUICK" = 1 ] && PROFILES=orig || PROFILES="orig mur0"; }
REPORT_DIR=reports
[ "$QUICK" = 1 ] && REPORT_DIR=out   # a corrida do portao nao sobrescreve a matriz publicada

n=0; bad=0
ck() { # ck "descricao" "comando-avaliado"
  n=$((n+1))
  if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi
}

for b in "$MUD2" "$CTL" "$CLI"; do
  [ -x "$b" ] || { echo "net.sh: falta o binario $b (rode 'make build')" >&2; exit 2; }
done
mkdir -p "$TMP"

SRV_PID=0; SRV_PORT=0; SRV_EXIT=-1
start_srv() { # start_srv [args...] — porta efêmera, log proprio
  rm -f "$LOG"
  "$MUD2" --port 0 --log-file "$LOG" "$@" >/dev/null 2>&1 &
  SRV_PID=$!
  SRV_PORT=0
  for _ in $(seq 1 100); do
    SRV_PORT=$(awk '/listen addr=/{for(i=1;i<=NF;i++) if($i ~ /^port=/){sub(/port=/,"",$i); print $i}}' "$LOG" 2>/dev/null)
    [ -n "$SRV_PORT" ] && break
    sleep 0.02
  done
}
stop_srv() {
  [ "$SRV_PID" -gt 0 ] || return 0
  kill -TERM "$SRV_PID" 2>/dev/null
  wait "$SRV_PID" 2>/dev/null
  SRV_EXIT=$?
  SRV_PID=0
}
closes() { grep -c "close=$1" "$LOG" 2>/dev/null || true; }
closes_total() { grep -c 'close=' "$LOG" 2>/dev/null || true; }
stats_field() { "$CTL" stats --port "$SRV_PORT" --profile "$1" 2>/dev/null | tr ' ' '\n' | awk -F= -v k="$2" '$1==k{print $2}'; }

echo "# net.sh: quick=$QUICK reps=$REPS perfis='$PROFILES' relatorios_em=$REPORT_DIR"

# ---------------------------------------------------------------- cenarios de contrato (S1..S13)
PROFILE=orig

# S1 leitura fragmentada: um quadro escrito em fatias de 2 bytes
start_srv --profile "$PROFILE"
ck "S1 servico sobe e anuncia a porta" '[ "$SRV_PORT" -gt 0 ]'
R=$("$CLI" --port "$SRV_PORT" --frames 1 --split 2 --gap-ms 5 --expect 1 2>&1)
ck "S1 quadro escrito em fatias de 2 bytes e respondido" 'printf "%s" "$R" | grep -q "resultado=OK"'
# O pedido de stats conta a si mesmo em `frames` (handle_frame incrementa antes de montar a
# linha), entao 1 ping + a propria consulta = 2. Nao e off-by-one: e o que o codigo faz, e a
# assercao abaixo trava essa semantica para ninguem "conserta-la" sem perceber.
ck "S1 contador frames conta 1 ping + a propria consulta de stats" '[ "$(stats_field "$PROFILE" frames)" = 2 ]'
stop_srv
ck "S1 encerramento por SIGTERM sai 0" '[ "$SRV_EXIT" -eq 0 ]'

# S2 quadros concatenados numa gravacao so (e o detector da falsificacao F5)
start_srv --profile "$PROFILE"
R=$("$CLI" --port "$SRV_PORT" --frames 4 --batch 4 --expect 4 2>&1)
ck "S2 quatro quadros num unico write produzem quatro respostas" 'printf "%s" "$R" | grep -q "resultado=OK"'
ck "S2 feed() consome todos os quadros do buffer (4 + a consulta de stats)" '[ "$(stats_field "$PROFILE" frames)" = 5 ]'
stop_srv

# S3 D2-14 (i): leitor atrasado recebe TUDO, sem fechamento de fila.
# Buffers no padrao de proposito: encolher o rcvbuf aqui misturaria a propriedade em teste
# (POLLOUT retoma a resposta pendente) com capacidade de buffer, que e o que o S4 mede.
start_srv --profile "$PROFILE"
R=$("$CLI" --port "$SRV_PORT" --frames 10 --code 2 --body-size 64 \
      --read-delay-ms 50 --expect 10 2>&1)
ck "S3 leitor atrasado (10x50ms) recebe as 10 respostas" 'printf "%s" "$R" | grep -q "resultado=OK"'
ck "S3 queue_full_closes == 0 no cenario que nao deveria lotar" '[ "$(stats_field "$PROFILE" queue_full_closes)" = 0 ]'
ck "S3 nenhuma linha close=queue_full no log" '[ "$(closes queue_full)" = 0 ]'
stop_srv

# S3b mesma propriedade com a janela curta (rcvbuf 1024) e volume que cabe nela: o POLLOUT tem
# de retomar a resposta pendente mesmo quando o primeiro send() nao esvazia a vaga.
start_srv --profile "$PROFILE" --sndbuf 1024
R=$("$CLI" --port "$SRV_PORT" --rcvbuf 1024 --frames 3 --code 2 --body-size 64 \
      --read-delay-ms 30 --expect 3 2>&1)
ck "S3b janela curta + leitor atrasado: 3 respostas entregues" 'printf "%s" "$R" | grep -q "resultado=OK"'
ck "S3b queue_full_closes continua 0" '[ "$(stats_field "$PROFILE" queue_full_closes)" = 0 ]'
stop_srv

# S4 D2-14 (ii) / D2-05: quem nao le nada e continua pedindo provoca o fechamento da vaga
start_srv --profile "$PROFILE" --sndbuf 1024
R=$("$CLI" --port "$SRV_PORT" --rcvbuf 1024 --frames 60 --code 2 --body-size 64 \
      --expect 0 --never-read --eof-wait-ms 3000 2>&1)
ck "S4 cliente que nao le e pede mais acaba desconectado" 'printf "%s" "$R" | grep -q "eof=1"'
ck "S4 queue_full_closes incrementou" '[ "$(stats_field "$PROFILE" queue_full_closes)" -ge 1 ]'
ck "S4 log traz o motivo proprio close=queue_full" '[ "$(closes queue_full)" -ge 1 ]'
ck "S4 linhas close=queue_full == contador (uma linha por evento)" \
   '[ "$(closes queue_full)" = "$(stats_field "$PROFILE" queue_full_closes)" ]'
RCV=$(printf '%s' "$R" | awk '/^rcvbuf /{for(i=1;i<=NF;i++) if($i ~ /^efetivo=/){sub(/efetivo=/,"",$i); print $i}}')
ck "S4 SO_RCVBUF pedido antes do connect e clampado pelo kernel (1024 -> >=2048)" \
   '[ -n "$RCV" ] && [ "$RCV" -ge 2048 ]'
stop_srv

# S5 desconexao limpa do cliente
start_srv --profile "$PROFILE"
"$CLI" --port "$SRV_PORT" --frames 1 --expect 1 >/dev/null 2>&1
sleep 0.2
ck "S5 close normal do cliente vira close=client_eof" '[ "$(closes client_eof)" -ge 1 ]'
stop_srv

# S6 desconexao abrupta (RST) tem de ser classificada diferente de EOF limpo
start_srv --profile "$PROFILE"
"$CLI" --port "$SRV_PORT" --frames 1 --expect 1 --abort >/dev/null 2>&1
sleep 0.3
ck "S6 RST nao e classificado como client_eof" '[ "$(closes client_eof)" -eq 0 ]'
ck "S6 RST cai em socket_error, client_hup ou write_error" \
   '[ $(( $(closes socket_error) + $(closes client_hup) + $(closes write_error) )) -ge 1 ]'
stop_srv

# S7 encerramento do servico com conexao aberta
start_srv --profile "$PROFILE"
"$CLI" --port "$SRV_PORT" --frames 0 --expect 0 --no-read-ms 900 >/dev/null 2>&1 &
CPID=$!
sleep 0.4
stop_srv
ck "S7 conexao aberta no SIGTERM vira close=shutdown" '[ "$(closes shutdown)" -ge 1 ]'
ck "S7 servico encerra com codigo 0" '[ "$SRV_EXIT" -eq 0 ]'
wait "$CPID" 2>/dev/null

# S8 timeout ocioso
start_srv --profile "$PROFILE" --idle-ms 200
"$CLI" --port "$SRV_PORT" --frames 0 --expect 0 --no-read-ms 900 >/dev/null 2>&1
ck "S8 conexao ociosa alem de --idle-ms vira close=idle_timeout" '[ "$(closes idle_timeout)" -ge 1 ]'
stop_srv

# S9 capacidade: --max-clients recusa com motivo proprio, nao com silencio
start_srv --profile "$PROFILE" --max-clients 2
PIDS=""
for _ in 1 2 3; do "$CLI" --port "$SRV_PORT" --frames 0 --expect 0 --no-read-ms 500 >/dev/null 2>&1 & PIDS="$PIDS $!"; done
# wait sem argumento esperaria tambem o mud2, que esta vivo: a suíte inteira travaria aqui.
wait $PIDS 2>/dev/null
ck "S9 a terceira conexao com --max-clients 2 vira close=max_clients" '[ "$(closes max_clients)" -ge 1 ]'
ck "S9 recusa de capacidade conta em rejects" '[ "$(stats_field "$PROFILE" rejects)" -ge 1 ]'
stop_srv

# S10 metricas coerentes com o trafego (5 pings + 1 pedido de stats = 6 quadros, 2 conexoes)
start_srv --profile "$PROFILE"
"$CLI" --port "$SRV_PORT" --frames 5 --expect 5 >/dev/null 2>&1
# UMA consulta so: cada chamada de mu2ctl abre uma conexao e conta em conns e frames, entao
# consultar dois campos em duas chamadas mediria o efeito da propria medicao.
LINHA=$("$CTL" stats --port "$SRV_PORT" --profile "$PROFILE" 2>/dev/null)
F=$(printf '%s' "$LINHA" | tr ' ' '\n' | awk -F= '$1=="frames"{print $2}')
CN=$(printf '%s' "$LINHA" | tr ' ' '\n' | awk -F= '$1=="conns"{print $2}')
ck "S10 frames == 5 pings + 1 stats" '[ "$F" = 6 ]'
ck "S10 conns == 2 (cliente + mu2ctl)" '[ "$CN" = 2 ]'
stop_srv

# S11 corpo no limite do contrato (2048) vai e volta integro
start_srv --profile "$PROFILE"
R=$("$CLI" --port "$SRV_PORT" --frames 1 --code 2 --body-size 2048 --expect 1 2>&1)
ck "S11 echo de corpo 2048 (limite do contrato) volta integro" 'printf "%s" "$R" | grep -q "resultado=OK"'
stop_srv

# S12 quadro invalido: size=0 enviado em cru (sem passar pelo nosso encoder)
start_srv --profile "$PROFILE"
( exec 3<>"/dev/tcp/127.0.0.1/$SRV_PORT"; printf '\001\000\000\000' >&3; sleep 0.3; exec 3>&- ) 2>/dev/null
sleep 0.2
ck "S12 size=0 e recusado com close=bad_frame" '[ "$(closes bad_frame)" -ge 1 ]'
ck "S12 quadro invalido conta em rejects" '[ "$(stats_field "$PROFILE" rejects)" -ge 1 ]'
stop_srv

# S13 opcode desconhecido e descartado sem derrubar a conexao; o ping seguinte ainda e respondido
start_srv --profile "$PROFILE" --log-level 3
( exec 3<>"/dev/tcp/127.0.0.1/$SRV_PORT"; printf '\377\177\004\000\001\000\004\000' >&3
  head -c 4 <&3 | od -An -tx1 | tr -d ' \n' > "$TMP/s13.hex"; exec 3>&- ) 2>/dev/null
sleep 0.2
stop_srv
ck "S13 opcode desconhecido nao fecha a conexao" '[ "$(closes bad_frame)" -eq 0 ]'
ck "S13 o ping seguinte na mesma conexao e respondido (01000400)" \
   '[ "$(cat "$TMP/s13.hex" 2>/dev/null)" = "01000400" ]'
ck "S13 opcode desconhecido conta no resumo de saida (unknown>=1)" \
   'grep -q "unknown=[1-9]" "$LOG"'

# ---------------------------------------------------------------- matriz de backpressure
# Colunas do contrato (docs/NEXT_TASK.md item 4): N_conn, N_frames, t_sem_ler, delay_entre_leituras,
# --sndbuf. SO_RCVBUF=1024 e aplicado no cliente ANTES do connect(); os efetivos vao no relatorio.
matrix_configs() {
  if [ "$QUICK" = 1 ]; then
    printf '%s\n' "1 10 0 0 0" "1 30 0 0 1024" "1 31 1000 0 1024" "4 30 0 50 1024"
    return
  fi
  local nc nf t d sb
  for nc in 1 4; do
    for nf in 10 29 30 31 60 120; do
      for t in 0 1000; do
        for d in 0 50; do
          for sb in 0 1024; do printf '%s\n' "$nc $nf $t $d $sb"; done
        done
      done
    done
  done
  for nf in 10 30; do for sb in 0 1024; do printf '%s\n' "16 $nf 0 0 $sb"; done; done
}

median() { printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END{if(NR%2)print a[(NR+1)/2]; else print int((a[NR/2]+a[NR/2+1])/2)}'; }

for PROFILE in $PROFILES; do
  TSV="$REPORT_DIR/net-$PROFILE.tsv"
  mkdir -p "$REPORT_DIR"
  {
    echo "# matriz de rede da R-4 — perfil $PROFILE (gerado por tests/net.sh)"
    echo "# quick=$QUICK reps=$REPS host=$(uname -r) cc=$(cc -dumpversion 2>/dev/null) data=$(date -u +%FT%TZ)"
    echo "# rcvbuf do cliente pedido antes do connect(); efetivos lidos por getsockopt"
    printf 'perfil\tn_conn\tn_frames\tt_sem_ler_ms\tdelay_ms\tsndbuf\trcvbuf_pedido\trcvbuf_efetivo\tsndbuf_efetivo\tmediana_recebidos\tmin\tmax\tesperados_por_conn\tclose_queue_full\tclose_client_eof\tclose_socket_error\tclose_write_error\tclose_client_hup\tclose_idle\tclose_max_clients\tclose_bad_frame\tclose_shutdown\tclose_nao_classificado\tperda_sem_fechamento\n'
  } > "$TSV"

  UNCLASSIFIED_TOTAL=0; UNEXPLAINED_TOTAL=0; CONFIGS=0
  while read -r NC NF T D SB; do
    [ -n "${NC:-}" ] || continue
    CONFIGS=$((CONFIGS+1))
    SRV_ARGS=(--profile "$PROFILE")
    [ "$SB" -gt 0 ] && SRV_ARGS+=(--sndbuf "$SB")
    start_srv "${SRV_ARGS[@]}"
    if [ "$SRV_PORT" -le 0 ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t-\t-\t-\t-\t-\t%s\tSERVIDOR-NAO-SUBIU\n' \
        "$PROFILE" "$NC" "$NF" "$T" "$D" "$SB" "$NF" >> "$TSV"
      bad=$((bad+1)); n=$((n+1)); printf 'not ok %d - matriz: servico nao subiu (n_conn=%s n_frames=%s)\n' "$n" "$NC" "$NF"
      continue
    fi
    SB_EF=$(awk '/sndbuf pedido=/{for(i=1;i<=NF;i++) if($i ~ /^efetivo=/){sub(/efetivo=/,"",$i); print $i}}' "$LOG")
    [ -n "$SB_EF" ] || SB_EF=-
    RCVP=-; RCVE=-
    RECEBIDOS=""
    PERDA=0
    for _ in $(seq 1 "$REPS"); do
      CPIDS=""
      for c in $(seq 1 "$NC"); do
        # --timeout-ms generoso de proposito: com o padrao de 5 s o orcamento do CLIENTE aparecia
        # como perda do servico (medido: 1 config deu 107/120 com 5 s e 120/120 com 20 s, com um
        # close=write_error do servidor ao escrever para um par que ja tinha desistido).
        A=(--port "$SRV_PORT" --rcvbuf 1024 --frames "$NF" --code 2 --body-size 64 --expect "$NF"
           --timeout-ms 20000)
        [ "$T" -gt 0 ] && A+=(--no-read-ms "$T")
        [ "$D" -gt 0 ] && A+=(--read-delay-ms "$D")
        "$CLI" "${A[@]}" > "$TMP/c.$c.out" 2>&1 &
        CPIDS="$CPIDS $!"
      done
      wait $CPIDS 2>/dev/null   # soh os clientes: o servico continua vivo de proposito
      for c in $(seq 1 "$NC"); do
        G=$(awk '/^recebidos=/{split($1,a,"="); print a[2]}' "$TMP/c.$c.out" 2>/dev/null)
        [ -n "$G" ] || G=0
        RECEBIDOS="$RECEBIDOS $G"
        [ "$G" -lt "$NF" ] && PERDA=$((PERDA+1))
        if [ "$RCVP" = - ]; then
          RCVP=$(awk '/^rcvbuf /{for(i=1;i<=NF;i++) if($i ~ /^pedido=/){sub(/pedido=/,"",$i); print $i}}' "$TMP/c.$c.out")
          RCVE=$(awk '/^rcvbuf /{for(i=1;i<=NF;i++) if($i ~ /^efetivo=/){sub(/efetivo=/,"",$i); print $i}}' "$TMP/c.$c.out")
          [ -n "$RCVP" ] || RCVP=-
          [ -n "$RCVE" ] || RCVE=-
        fi
      done
    done
    # contagem de fechamentos ANTES de consultar stats (o mu2ctl abre uma conexao propria)
    C_QF=$(closes queue_full); C_EOF=$(closes client_eof); C_SE=$(closes socket_error)
    C_WE=$(closes write_error); C_HUP=$(closes client_hup); C_IDLE=$(closes idle_timeout)
    C_MC=$(closes max_clients); C_BF=$(closes bad_frame); C_SD=$(closes shutdown)
    C_ALL=$(closes_total)
    C_CLASS=$((C_QF + C_EOF + C_SE + C_WE + C_HUP + C_IDLE + C_MC + C_BF + C_SD))
    C_UN=$((C_ALL - C_CLASS)); [ "$C_UN" -lt 0 ] && C_UN=0
    UNCLASSIFIED_TOTAL=$((UNCLASSIFIED_TOTAL + C_UN))
    # perda sem fechamento = resposta que sumiu sem nenhum motivo no log (nao pode existir)
    UNEX=0
    [ "$PERDA" -gt 0 ] && [ "$C_ALL" -eq 0 ] && UNEX=1
    UNEXPLAINED_TOTAL=$((UNEXPLAINED_TOTAL + UNEX))
    QFC=$(stats_field "$PROFILE" queue_full_closes); [ -n "$QFC" ] || QFC=-
    stop_srv
    MED=$(median $RECEBIDOS); MIN=$(printf '%s\n' $RECEBIDOS | sort -n | head -1); MAX=$(printf '%s\n' $RECEBIDOS | sort -n | tail -1)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$PROFILE" "$NC" "$NF" "$T" "$D" "$SB" "$RCVP" "$RCVE" "$SB_EF" "$MED" "$MIN" "$MAX" "$NF" \
      "$C_QF" "$C_EOF" "$C_SE" "$C_WE" "$C_HUP" "$C_IDLE" "$C_MC" "$C_BF" "$C_SD" "$C_UN" "$UNEX" >> "$TSV"
    [ "$QFC" = "$C_QF" ] || { bad=$((bad+1)); n=$((n+1))
      printf 'not ok %d - matriz: contador queue_full_closes (%s) != linhas de log (%s) em n_conn=%s n_frames=%s sndbuf=%s\n' \
        "$n" "$QFC" "$C_QF" "$NC" "$NF" "$SB"; }
  done <<EOF2
$(matrix_configs)
EOF2

  n=$((n+1))
  if [ "$UNCLASSIFIED_TOTAL" -eq 0 ]; then printf 'ok %d - matriz %s: todo close= do log tem motivo conhecido\n' "$n" "$PROFILE"
  else bad=$((bad+1)); printf 'not ok %d - matriz %s: %s fechamentos sem classificacao\n' "$n" "$PROFILE" "$UNCLASSIFIED_TOTAL"; fi
  n=$((n+1))
  if [ "$UNEXPLAINED_TOTAL" -eq 0 ]; then printf 'ok %d - matriz %s: nenhuma perda de resposta sem fechamento que a explique\n' "$n" "$PROFILE"
  else bad=$((bad+1)); printf 'not ok %d - matriz %s: %s configuracoes com perda sem fechamento\n' "$n" "$PROFILE" "$UNEXPLAINED_TOTAL"; fi
  echo "# matriz $PROFILE: $CONFIGS configuracoes x $REPS repeticoes -> $TSV"
done

printf '1..%d\n# net=%d falhas=%d\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1

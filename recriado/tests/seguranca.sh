#!/usr/bin/env bash
# seguranca.sh — Etapa D: validação de entrada na porta, estabilidade de recursos, higiene de log.
#
# Difere de tests/net.sh (que prova o comportamento CONTRATADO) e de tools/mu2fuzz.c (que ataca o
# codec em processo): aqui o ataque é pela porta, com bytes deliberadamente ruins, e o que se afirma
# é resiliência — o serviço sobrevive, não vaza descritor nem memória, encerra limpo e não escreve
# dado sensível no log.
#
# TSan: disponível neste host (medido), mas o produto é single-threaded por construção — 0 ocorrências
# de primitivas de thread em src/. Rodar TSan num servidor sem threads não detectaria nada; a
# concorrência real está no epoll do kernel e é exercitada pelos cenários de múltiplas conexões com
# ASan+UBSan. Isso é registrado como asserção (caso 10), não omitido em silêncio.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
SRV=$V2/out/mud2; PROBE=$V2/tools/malform_probe.py
OUTD=$V2/out/seguranca
CICLOS=${SEG_CICLOS:-1000}
n=0; bad=0; BL=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

for f in "$SRV" "$PROBE"; do
  [ -e "$f" ] || { printf '1..0\n# seguranca=0 falhas=0 blocked=1\n# BLOCKED motivo=falta %s\n' "$f"; exit 0; }
done
command -v python3 >/dev/null 2>&1 || {
  printf '1..0\n# seguranca=0 falhas=0 blocked=1\n# BLOCKED motivo=python3 ausente\n'; exit 0; }

mkdir -p "$OUTD"; rm -f "$OUTD"/* 2>/dev/null
LOG=$OUTD/servidor.log

"$SRV" --port 0 --profile orig --log-level 2 --log-file "$LOG" >"$OUTD/servidor.out" 2>&1 &
SPID=$!
trap 'kill -TERM $SPID 2>/dev/null; wait $SPID 2>/dev/null; true' EXIT
PORT=0
for _ in $(seq 1 100); do
  PORT=$(sed -n 's/.*listen .*port=\([0-9]*\).*/\1/p' "$LOG" 2>/dev/null | head -1)
  [ -n "$PORT" ] && break
  sleep 0.05
done
if [ -z "$PORT" ]; then
  printf '1..0\n# seguranca=0 falhas=0 blocked=1\n# BLOCKED motivo=servico nao anunciou porta\n'; exit 0
fi
printf '# escopo=seguranca:entrada-de-rede+recursos+log porta=%s ciclos=%s\n' "$PORT" "$CICLOS"

RSS() { awk '/VmRSS/{print $2}' "/proc/$SPID/status" 2>/dev/null || echo 0; }
FD()  { ls "/proc/$SPID/fd" 2>/dev/null | wc -l; }
RSS_ANTES=$(RSS); FD_ANTES=$(FD)

# --srv-pid "$SPID": a sonda NAO descobre o servico varrendo /proc (defeito medido em 2026-10-12:
# a varredura por "mud2" no cmdline casava com o proprio shell do teste e media fd de outro
# processo). O pid e' o `$!` deste script, e a assercao 4b abaixo prova a procedencia.
python3 "$PROBE" --port "$PORT" --ciclos "$CICLOS" --srv-pid "$SPID" > "$OUTD/probe.tsv" 2>"$OUTD/probe.err"
PROBE_EXIT=$?
BF=$(grep -c 'close=bad_frame' "$LOG")     # tirado antes da 2a sonda: o log acumula
python3 "$PROBE" --port "$PORT" --ciclos 50 --srv-pid "$SPID" > "$OUTD/probe2.tsv" 2>/dev/null
RSS_DEPOIS=$(RSS)

kill -TERM $SPID 2>/dev/null; wait $SPID 2>/dev/null; SRV_EXIT=$?
trap - EXIT

CASOS=$(awk -F'\t' 'NR>1 && $1!~/^#/{c++} END{print c+0}' "$OUTD/probe.tsv")
MORTOS=$(sed -n 's/^# casos=[0-9]* servico_morto_depois_de=//p' "$OUTD/probe.tsv")

ck "bateria de $CASOS entradas malformadas na porta: serviço vivo depois de cada caso" \
      "[ '$(awk -F'\t' 'NR>1 && $1!~/^#/{if($4!=1) m++} END{print m+0}' "$OUTD/probe.tsv")' = 0 ]"
ck "sonda relata servico_morto_depois_de=nenhum e sai 0" \
      "[ '$MORTOS' = nenhum ] && [ '$PROBE_EXIT' = 0 ]"
ck "serviço encerra com código 0 no SIGTERM depois de toda a bateria (sem abort de sanitizador)" \
      "[ '$SRV_EXIT' = 0 ]"
# A medida que interessa é ACÚMULO, não o instante do último close: o close do cliente devolve o
# socket de forma assíncrona, e contar fd logo depois de fechar o 1000º dá 9 mesmo sem vazamento
# (medido). A sonda espera estabilizar (limite 2 s, custo real medido 0–20 ms) em DUAS rodadas: um
# vazamento real não estabiliza e a rodada 2 soma sobre a 1 — a asserção continua podendo falhar.
FD_A=$(sed -n 's/.*fd_antes=\([0-9]*\).*/\1/p'   "$OUTD/probe.tsv" | tail -1)
FD_I=$(sed -n 's/.*fd_imed=\([0-9]*\).*/\1/p'    "$OUTD/probe.tsv" | tail -1)
FD_D=$(sed -n 's/.*fd_depois=\([0-9]*\).*/\1/p'  "$OUTD/probe.tsv" | tail -1)
FD_R2=$(sed -n 's/.*fd_rodada2=\([0-9]*\).*/\1/p' "$OUTD/probe.tsv" | tail -1)
ck "sem acúmulo de descritores: base=$FD_A imediato=$FD_I estabilizado=$FD_D e 2a rodada=$FD_R2 (2x$CICLOS ciclos)" \
   "[ -n '$FD_A' ] && [ '$FD_A' = '$FD_D' ] && [ '$FD_D' = '$FD_R2' ]"
# 4b) procedência: a contagem acima só vale se tiver sido feita no processo do serviço. Um pid
# errado dá "estável" por acidente (foi o que aconteceu) e a asserção viraria ruído verde.
ck "a contagem de fd veio do processo do serviço (srv_pid=$SPID, pid_fonte=argumento)" \
   "grep -q 'srv_pid=$SPID pid_fonte=argumento' '$OUTD/probe.tsv'"
ck "RSS não cresce com a bateria + $CICLOS ciclos (medido: ${RSS_ANTES} kB -> ${RSS_DEPOIS} kB)" \
      "[ '$((RSS_DEPOIS - RSS_ANTES))' -le 512 ]"

# Comportamento medido, não suposto. 11 dos casos mandam cabeçalho inválido por construção
# (size_zero, size_um, size_tres, size_2053, size_65535, lixo_aleatorio, muitos_ruins,
# bom_ruim_bom, tudo_zero_1024, tudo_ff_1024, corpo_maior_que_declarado). Os demais não devem
# fechar por quadro ruim: codigo_zero tem size válido (opcode desconhecido NAO fecha), o cabeçalho
# parcial é seguido de close do cliente, o gotejamento entrega um ping válido.
ck "quadro malformado fecha a conexão com motivo próprio: close=bad_frame == 11 (derivado dos casos)" \
      "[ '$BF' = 11 ]"
ck "opcode desconhecido com size válido NÃO fecha a conexão (caso codigo_zero segue vivo)" \
      "awk -F'\t' '\$1==\"codigo_zero_size_valido\"{exit !(\$4==1 && \$3==0)}' '$OUTD/probe.tsv'"
ck "medido: quadro ruim encerra a conexão, então o ping válido seguinte NÃO é respondido
      (bom_ruim_bom devolve 1 resposta, não 2) — política registrada, não perda silenciosa" \
      "awk -F'\t' '\$1==\"bom_ruim_bom\"{exit !(\$3==1)}' '$OUTD/probe.tsv'"
ck "higiene de log: sem dump hex de payload, sem caminho absoluto do host, sem chave de credencial" \
      "! grep -Eq '([0-9a-f]{2} ){8,}' '$LOG' && ! grep -q '/home/' '$LOG' && \
       ! grep -Eiq '(token|senha|password|secret|api_key)=' '$LOG'"
ck "TSan não se aplica: 0 primitivas de thread em src/ (produto single-threaded; registrado)" \
      "[ \"\$(grep -rEc 'pthread|thread_create|std::thread' '$V2/src/'*.c | awk -F: '{s+=\$2} END{print s+0}')\" = 0 ]"
ck "sonda determinística: duas execuções produzem a mesma lista de casos e os mesmos resultados" \
      "diff -q <(cut -f1,3,4 '$OUTD/probe.tsv') <(cut -f1,3,4 '$OUTD/probe2.tsv') >/dev/null"
ck "nenhuma linha de erro da sonda vazou para stderr" "[ ! -s '$OUTD/probe.err' ]"

printf '1..%d\n' "$n"
printf '# seguranca=%d falhas=%d blocked=%d\n' "$n" "$bad" "$BL"
printf '# casos=%d rss_antes=%s rss_depois=%s fd_antes=%s fd_imed=%s fd_estabilizado=%s fd_rodada2=%s close_bad_frame=%s\n' \
  "$CASOS" "$RSS_ANTES" "$RSS_DEPOIS" "$FD_A" "$FD_I" "$FD_D" "$FD_R2" "$BF"
printf '# sanitizadores=address,undefined (-fno-sanitize-recover=all); thread NAO (produto sem threads)\n'
[ "$bad" -eq 0 ] || exit 1

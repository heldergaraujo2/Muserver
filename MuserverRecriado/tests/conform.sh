#!/usr/bin/env bash
# conform.sh — conformidade do protocolo v2 com o contrato escrito (fase R-6).
#
# CAMADA 1 de três (ver reports/r6-relatorio.md):
#   1. conformidade interna do v2  ← é o que esta suíte testa
#   2. compatibilidade observada   ← matriz de evidências, medição estática
#   3. compatibilidade comprovada  ← exige binário original em execução: BLOCKED
# Passar aqui NÃO afirma compatibilidade com o MU Server original. Os opcodes são do v2
# (include/mu2/proto.h) e o contrato é include/mu2/mu2.h.
#
# Cada caso nomeia a cláusula que verifica. Quadro: code(2 LE) + size(2 LE) + corpo, onde
# `size` é o comprimento TOTAL (MU2_HEADER_SIZE + corpo), medido em src/wire.c.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
MUD2=$V2/out/mud2; CTL=$V2/out/mu2ctl; CLI=$V2/out/netclient
WP="python3 $V2/tools/wire_probe.py"
LOG=$V2/out/conform.log
n=0; bad=0
ck() { n=$((n+1)); if "$3" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi; }

for b in "$MUD2" "$CTL" "$CLI"; do
  [ -x "$b" ] || { printf '1..0\n# conform=0 falhas=0 blocked=1\n# BLOCKED motivo=falta %s (rode make build)\n' "$b"; exit 0; }
done
command -v python3 >/dev/null 2>&1 || {
  printf '1..0\n# conform=0 falhas=0 blocked=1\n# BLOCKED motivo=python3 ausente\n'; exit 0; }

SRV_PID=0; PORT=0
start_srv() {
  rm -f "$LOG"
  "$MUD2" --port 0 --log-file "$LOG" "$@" >/dev/null 2>&1 &
  SRV_PID=$!
  PORT=0
  for _ in $(seq 1 150); do
    PORT=$(awk '/listen addr=/{for(i=1;i<=NF;i++) if($i ~ /^port=/){sub(/port=/,"",$i); print $i}}' \
           "$LOG" 2>/dev/null)
    [ -n "$PORT" ] && break
    sleep 0.02
  done
}
stop_srv() {
  [ "$SRV_PID" -gt 0 ] || return 0
  kill -TERM "$SRV_PID" 2>/dev/null
  wait "$SRV_PID" 2>/dev/null
  SRV_PID=0
}
trap 'stop_srv' EXIT
st() { "$CTL" stats --port "$PORT" --profile "${2:-orig}" 2>/dev/null |
       tr ' ' '\n' | awk -F= -v k="$1" '$1==k{print $2}'; }
probe() { $WP --port "$PORT" --read-ms "${READ_MS:-900}" "$@" 2>/dev/null; }
hexde() { probe "$@" | awk -F= '/^reply_hex=/{print $2}'; }
bytesde() { probe "$@" | awk -F= '/^recebidos_bytes=/{print $2}'; }

start_srv --profile orig
[ "$PORT" -gt 0 ] || { printf '1..0\n# conform=0 falhas=0 blocked=1\n# BLOCKED motivo=servico nao subiu\n'; exit 1; }

# corpos exatos em hex: `printf 'a%.0s' $(seq 1 N)` nao e confiavel para N grande (medido:
# devolveu 16 bytes para N=2048 e gerou hex de tamanho impar). head -c + tr e deterministico.
# od -v: sem o -v o od colapsa linhas repetidas em '*' e o hex sai truncado (medido: 33 chars
# para 2048 bytes de 'a').
hexn() { head -c "$1" /dev/zero | tr '\0' "$2" | od -An -v -tx1 | tr -d ' \n'; }
HEX_MAX=$(hexn 2048 a)      # corpo no limite
HEX_OVER=$(hexn 2049 a)     # corpo acima do limite
HEX_1788=$(hexn 1788 b)     # corpo para size=1792

# --- C-01 quadro mínimo: PING tem resposta de corpo vazio (proto.h)
t01() { [ "$(hexde --hex 01000400)" = 01000400 ]; }
ck 1 "C-01 PING: quadro minimo (4 B) devolve os mesmos 4 bytes, corpo vazio" t01

# --- C-02 ECHO devolve o corpo identico
t02() { [ "$(hexde --hex 02000700616263)" = 02000700616263 ]; }
ck 2 "C-02 ECHO: corpo 'abc' volta byte a byte" t02

# --- C-03 corpo no limite MU2_MAX_BODY=2048 e aceito (size=2052=0804 LE -> 0408)
t03() { [ "$(hexde --hex "02000408$HEX_MAX" | cut -c1-8)" = 02000408 ] &&
        [ "$(bytesde --hex "02000408$HEX_MAX")" = 2052 ]; }
ck 3 "C-03 MU2_MAX_BODY: corpo de 2048 B aceito, resposta de 2052 B" t03

# --- C-04 acima do limite: size=2053 (0508) > MU2_MAX_FRAME -> rejeitado, rejects++
R0=$(st rejects)
B4=$(bytesde --hex "02000508$HEX_OVER")
R1=$(st rejects)
t04() { [ "$B4" = 0 ] && [ "$R1" -gt "$R0" ]; }
ck 4 "C-04 corpo de 2049 B (size=2053) rejeitado: sem resposta e rejects incrementa" t04

# --- C-05 size menor que o cabecalho -> MU2_E_BAD_LEN
R0=$(st rejects); B5=$(bytesde --hex 02000200); R1=$(st rejects)
t05() { [ "$B5" = 0 ] && [ "$R1" -gt "$R0" ]; }
ck 5 "C-05 size=2 (< MU2_HEADER_SIZE) rejeitado: sem resposta e rejects incrementa" t05

# --- C-06 size acima do maximo -> MU2_E_BAD_LEN
R0=$(st rejects); B6=$(bytesde --hex 0200b80b); R1=$(st rejects)
t06() { [ "$B6" = 0 ] && [ "$R1" -gt "$R0" ]; }
ck 6 "C-06 size=3000 (> MU2_MAX_FRAME) rejeitado: sem resposta e rejects incrementa" t06

# --- C-07 little-endian: size declarado 1792 (0007 em LE) so faz sentido se o campo for LE.
# size=1792 => corpo de 1788 B (1792 - 4 do cabecalho); enviados 1792 bytes no total; se a ordem fosse BE o servidor leria 7 e responderia outra coisa.
t07() { [ "$(bytesde --hex "02000007$HEX_1788")" = 1792 ]; }
ck 7 "C-07 campo de tamanho e little-endian: size=0x0700 tratado como 1792, eco completo" t07

# --- C-08 opcode inexistente e descartado SEM derrubar a conexao
t08() { [ "$(hexde --hex ff00040001000400)" = 01000400 ]; }
ck 8 "C-08 opcode 0x00ff descartado; o PING seguinte na mesma conexao e respondido" t08

# --- C-09 quadro fragmentado: cabecalho, pausa, corpo
t09() { [ "$(hexde --hex 0200 --hex-2 0700616263 --pause-ms 120)" = 02000700616263 ]; }
ck 9 "C-09 MU2_E_INCOMPLETE: quadro em duas escritas com 120 ms de intervalo e respondido" t09

# --- C-10 dois quadros num unico write -> duas respostas
t10() { [ "$(hexde --hex 0100040001000400)" = 0100040001000400 ]; }
ck 10 "C-10 dois quadros concatenados num unico write produzem duas respostas" t10

# --- C-11 D2-17: o corpo de STATS comeca exatamente em "STATS " (nao deslocado 4 bytes)
t11() { probe --hex 03000400 --skip 4 --expect-ascii-prefix "STATS " >/dev/null; }
ck 11 "C-11 D2-17: mu2_frame_body recebe o inicio do quadro — corpo comeca em 'STATS '" t11

# --- C-12 formato da linha de metricas: 9 campos, nesta ordem (proto.h)
# sed, nao `awk -F=`: a linha STATS contem '=' e o awk cortaria no primeiro
LINHA=$(probe --hex 03000400 --skip 4 | sed -n 's/^reply_ascii=//p')
t12() { printf '%s' "$LINHA" | grep -q '^STATS registros=[0-9]* usados=[0-9]* conns=[0-9]* frames=[0-9]* rejects=[0-9]* queue_full_closes=[0-9]* uptime_ms=[0-9]* slotsz=[0-9]* maxbody=[0-9]*$'; }
ck 12 "C-12 linha STATS tem os 9 campos do contrato, na ordem declarada" t12

# --- C-13 nenhuma resposta parcial para quadro invalido
t13() { [ "$B5" = 0 ] && [ "$B6" = 0 ]; }
ck 13 "C-13 quadro invalido nao vaza bytes parciais (0 bytes recebidos, nao resposta truncada)" t13
stop_srv

# --- C-14 equivalencia funcional entre os dois perfis (mu2.h: assercao obrigatoria)
start_srv --profile orig
R_ORIG=$("$CLI" --port "$PORT" --profile orig --frames 5 --code 2 --body-size 64 --expect 5 2>&1)
O_OK=$(printf '%s' "$R_ORIG" | grep -c 'resultado=OK')
O_REC=$(printf '%s' "$R_ORIG" | awk -F'[= ]' '/^recebidos=/{print $2}')
stop_srv
start_srv --profile mur0
R_MUR0=$("$CLI" --port "$PORT" --profile mur0 --frames 5 --code 2 --body-size 64 --expect 5 2>&1)
M_OK=$(printf '%s' "$R_MUR0" | grep -c 'resultado=OK')
M_REC=$(printf '%s' "$R_MUR0" | awk -F'[= ]' '/^recebidos=/{print $2}')
stop_srv
t14() { [ "$O_OK" = 1 ] && [ "$M_OK" = 1 ] && [ "$O_REC" = 5 ] && [ "$O_REC" = "$M_REC" ]; }
ck 14 "C-14 perfis orig e mur0 equivalentes: 5/5 quadros nos dois, mesmos recebidos" t14

# --- C-15 (F15) a conformidade depende do comparador real, nao de um "OK" decorativo.
# Diferencial em copia temporaria: se alguem neutralizar a comparacao, os dois lados concordam e
# este caso falha. Sem isso, "14/14" poderia ser produzido por uma sonda que sempre diz OK.
start_srv --profile orig
TM=$(mktemp -d)
sed 's/^        ok = bytes(buf).hex() == a.expect_hex.lower()$/        ok = True  # F15/' \
  "$V2/tools/wire_probe.py" > "$TM/wp_mut.py"
python3 "$V2/tools/wire_probe.py" --port "$PORT" --read-ms 900 --hex 01000400 \
  --expect-hex 01000400deadbeef >/dev/null 2>&1; RC_REAL=$?
python3 "$TM/wp_mut.py" --port "$PORT" --read-ms 900 --hex 01000400 \
  --expect-hex 01000400deadbeef >/dev/null 2>&1; RC_MUT=$?
rm -rf "$TM"
stop_srv
t15() { grep -q 'ok = True  # F15' <(sed 's/^        ok = bytes(buf).hex() == a.expect_hex.lower()$/        ok = True  # F15/' "$V2/tools/wire_probe.py") &&
        [ "$RC_REAL" -ne 0 ] && [ "$RC_MUT" -eq 0 ]; }
ck 15 "C-15 (F15) expectativa errada e detectada pela sonda real (mutada diz OK: diferenca medida)" t15

printf '1..%d\n# escopo=conform:v2-interno\n# conform=%d falhas=%d blocked=0\n' "$n" "$n" "$bad"
printf '# nota=camada: conformidade interna do v2; NAO afirma compatibilidade com o original\n'
[ "$bad" -eq 0 ] || exit 1

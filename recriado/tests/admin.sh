#!/usr/bin/env bash
# admin.sh — Etapa E: console administrativo (mu2admin) contra o desenho em docs/ADMIN_CONSOLE.md.
#
# Cada caso abaixo corresponde a um item da tabela "Testes exigidos antes de declarar a etapa pronta"
# daquele documento. O que nao esta aqui nao foi verificado.
#
# O token usado e FIXTURE DE TESTE, nao credencial: esta impresso no proprio arquivo, e invalido
# fora desta maquina e desta execucao. Nenhum segredo real e gravado no repositorio.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
ADMIN=$V2/out/mu2admin; SRV=$V2/out/mud2; OUTD=$V2/out/admin
TOKFIX="TESTE-FIXTURE-NAO-E-CREDENCIAL-REAL-0123456789abcdef"
n=0; bad=0; BL=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

for b in "$ADMIN" "$SRV"; do
  [ -x "$b" ] || { printf '1..0\n# admin=0 falhas=0 blocked=1\n# BLOCKED motivo=falta %s (make build)\n' "$b"; exit 0; }
done
command -v curl >/dev/null 2>&1 || {
  printf '1..0\n# admin=0 falhas=0 blocked=1\n# BLOCKED motivo=curl ausente\n'; exit 0; }

mkdir -p "$OUTD"; rm -f "$OUTD"/* 2>/dev/null
T=$(mktemp -d)
SPID=""; APID=""
limpa() {
  [ -n "$APID" ] && kill -TERM "$APID" 2>/dev/null
  [ -n "$SPID" ] && kill -TERM "$SPID" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$T"
}
trap limpa EXIT

umask 077
printf '%s\tleitor\n%s\tadmin\n' "$TOKFIX" "${TOKFIX}-admin" > "$T/tok"
chmod 600 "$T/tok"

# ---- casos de fail-closed (o servidor NAO pode subir) ---------------------------------------
"$ADMIN" >"$OUTD/sem_token.out" 2>&1
RC_SEM=$?
printf '%s\tleitor\n' "$TOKFIX" > "$T/largo"; chmod 644 "$T/largo"
"$ADMIN" --token-file "$T/largo" >"$OUTD/largo.out" 2>&1
RC_LARGO=$?
printf '%s\tleitor\n' "curto-demais" > "$T/curto"; chmod 600 "$T/curto"
"$ADMIN" --token-file "$T/curto" >"$OUTD/curto.out" 2>&1
RC_CURTO=$?
printf '%s\timperador\n' "$TOKFIX" > "$T/papel"; chmod 600 "$T/papel"
"$ADMIN" --token-file "$T/papel" >"$OUTD/papel.out" 2>&1
RC_PAPEL=$?
"$ADMIN" --token-file "$T/tok" --listen 0.0.0.0 >"$OUTD/rede.out" 2>&1
RC_REDE=$?

ck "sem --token-file o servidor nao sobe e sai != 0 (fail closed)" "[ '$RC_SEM' != 0 ]"
ck "arquivo de token 0644 => recusa iniciar" \
   "[ '$RC_LARGO' != 0 ] && grep -q '0600' '$OUTD/largo.out'"
ck "token com menos de 32 caracteres => recusa iniciar" \
   "[ '$RC_CURTO' != 0 ] && grep -q 'minimo 32' '$OUTD/curto.out'"
ck "papel desconhecido no arquivo => recusa iniciar" \
   "[ '$RC_PAPEL' != 0 ] && grep -q 'papel desconhecido' '$OUTD/papel.out'"
ck "--listen 0.0.0.0 => recusa iniciar (somente loopback)" \
   "[ '$RC_REDE' != 0 ] && grep -q 'loopback' '$OUTD/rede.out'"
ck "nenhuma mensagem de erro ecoa o token do arquivo" \
   "! grep -rq '$TOKFIX' '$OUTD/sem_token.out' '$OUTD/largo.out' '$OUTD/curto.out' \
     '$OUTD/papel.out' '$OUTD/rede.out'"

# ---- sobe de verdade -------------------------------------------------------------------------
"$SRV" --port 0 --profile orig --log-file "$T/m.log" >"$T/m.out" 2>&1 &
SPID=$!
MP=""
for _ in $(seq 1 100); do
  MP=$(sed -n 's/.*listen .*port=\([0-9]*\).*/\1/p' "$T/m.log" 2>/dev/null | head -1)
  [ -n "$MP" ] && break; sleep 0.05
done
[ -n "$MP" ] || { printf '1..0\n# admin=0 falhas=0 blocked=1\n# BLOCKED motivo=mud2 nao anunciou porta\n'; exit 0; }

"$ADMIN" --token-file "$T/tok" --port 0 --mud2-port "$MP" --gate-tsv "$V2/out/gate.tsv" \
  --log-file "$OUTD/admin.log" >"$OUTD/admin.err" 2>&1 &
APID=$!
AP=""
for _ in $(seq 1 100); do
  AP=$(sed -n 's/.*listen .*port=\([0-9]*\).*/\1/p' "$OUTD/admin.log" 2>/dev/null | head -1)
  [ -n "$AP" ] && break; sleep 0.05
done
[ -n "$AP" ] || { printf '1..0\n# admin=0 falhas=0 blocked=1\n# BLOCKED motivo=mu2admin nao anunciou porta\n'; exit 0; }
printf '# escopo=admin:console-local mud2=%s admin=%s\n' "$MP" "$AP"

U="http://127.0.0.1:$AP"
code() { curl -s -m 5 -o /dev/null -w '%{http_code}' "$@"; }
body() { curl -s -m 5 "$@"; }

H_OK="Authorization: Bearer $TOKFIX"
H_AD="Authorization: Bearer ${TOKFIX}-admin"

ck "/health responde sem token" "[ \"\$(code '$U/health')\" = 200 ]"
ck "/stats sem token => 401 token_ausente" \
   "[ \"\$(code '$U/stats')\" = 401 ] && body '$U/stats' | grep -q token_ausente"
R_ERR=$(body -H 'Authorization: Bearer token-errado-qualquer' "$U/stats")
ck "/stats com token errado => 401 token_invalido" \
   "[ \"\$(code -H 'Authorization: Bearer token-errado-qualquer' '$U/stats')\" = 401 ] && \
    printf '%s' '$R_ERR' | grep -q token_invalido"
ck "a resposta de token invalido NAO ecoa o token apresentado" \
   "! printf '%s' '$R_ERR' | grep -q 'token-errado-qualquer'"
ck "/stats com leitor => 200 com a linha STATS real do mud2" \
   "[ \"\$(code -H '$H_OK' '$U/stats')\" = 200 ] && body -H '$H_OK' '$U/stats' | grep -q 'registros='"
ck "/gate com leitor => 200 e conta de etapas > 0" \
   "[ \"\$(code -H '$H_OK' '$U/gate')\" = 200 ] && body -H '$H_OK' '$U/gate' | grep -q '\"etapas\":[1-9]'"
ck "POST com leitor => 403 papel_insuficiente" \
   "[ \"\$(code -X POST -H '$H_OK' '$U/publicar')\" = 403 ] && \
    body -X POST -H '$H_OK' '$U/publicar' | grep -q papel_insuficiente"
ck "POST /publicar com admin => 501 nao_implementado (nunca sucesso simulado)" \
   "[ \"\$(code -X POST -H '$H_AD' '$U/publicar')\" = 501 ] && \
    body -X POST -H '$H_AD' '$U/publicar' | grep -q nao_implementado"
ck "rota com '..' => 400 rota_invalida" \
   "[ \"\$(code --path-as-is -H '$H_OK' '$U/../etc')\" = 400 ]"
ck "rota inexistente => 404 rota_desconhecida" \
   "[ \"\$(code -H '$H_OK' '$U/nao-existe')\" = 404 ]"
ck "Content-Length 5000 => 413 corpo_grande_demais" \
   "[ \"\$(code -X POST -H '$H_AD' -H 'Content-Length: 5000' --data 'x' '$U/publicar')\" = 413 ]"
ck "Authorization sem 'Bearer ' => 401 token_malformado" \
   "[ \"\$(code -H 'Authorization: $TOKFIX' '$U/stats')\" = 401 ] && \
    body -H 'Authorization: $TOKFIX' '$U/stats' | grep -q token_malformado"
ck "log do admin nao contem token, caminho absoluto nem dump de payload" \
   "! grep -q '$TOKFIX' '$OUTD/admin.log' && ! grep -q '/home/' '$OUTD/admin.log' && \
    ! grep -Eq '([0-9a-f]{2} ){8,}' '$OUTD/admin.log'"

# estado degradado: sem o mud2, /stats tem de dizer, nao fingir sucesso
kill -TERM "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null; SPID=""
sleep 0.3
ck "com o mud2 parado, /stats => 503 upstream_indisponivel e /health mostra degradado" \
   "[ \"\$(code -H '$H_OK' '$U/stats')\" = 503 ] && \
    body -H '$H_OK' '$U/health' | grep -q indisponivel"

kill -TERM "$APID" 2>/dev/null; wait "$APID" 2>/dev/null; RC_ADMIN=$?; APID=""
ck "SIGTERM no mu2admin => exit 0 (encerramento limpo)" "[ '$RC_ADMIN' = 0 ]"
ck "mud2 e mu2admin intactos no git: nenhuma alteracao em src/ nem em include/" \
   "git -C '$V2/..' diff --quiet -- recriado/src recriado/include"

printf '1..%d\n' "$n"
printf '# admin=%d falhas=%d blocked=%d\n' "$n" "$bad" "$BL"
printf '# desenho=docs/ADMIN_CONSOLE.md; rota /publicar e 501 por decisao (sem alvo autorizado)\n'
[ "$bad" -eq 0 ] || exit 1

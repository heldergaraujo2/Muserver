#!/usr/bin/env bash
# concorrencia.sh — F3: o que acontece quando `mu2db_verify` e uma ESCRITA se encontram.
#
# POR QUE ESTA SUITE EXISTE, JA QUE `dbctl` JA TEM CASOS DE LOCK
# Os casos de lock do `dbctl` seguram o lock com `flock(1)` — um processo que *segura lock*, mas nao
# escreve no banco. Isso prova compatibilidade de locks; nao prova o comportamento do ESCRITOR REAL
# (o que a biblioteca faz quando o arquivo esta' tomado, e o que acontece com o dado). Aqui o escritor
# e' o `mu2dbcontend`: mesmo `mu2db_abrir` do servico (portanto `flock(LOCK_EX|LOCK_NB)` pelo ciclo
# de vida do handle), transacoes reais com CRC real, commit real. Nada aqui simula lock.
#
# COMO A JANELA E' TORNADA DETERMINISTA (e por que isso importa)
# Verificar "durante" uma escrita por sorte de agendamento mede sorte. O driver aceita
# `--hold-until-arquivo ARQ`: depois das transacoes ele NAO solta o lock ate' ARQ existir. Assim a
# suite afirma "enquanto HAVIA escritor com lock" sem corrida entre abrir e verificar.
#
# ARMADILHA MEDIDA NESTA PROPRIA SUITE (fica registrada porque e' silenciosa)
# `flock -n 9` (sem -s/-x) toma lock EXCLUSIVO — e, no MESMO descritor, CONVERTE o compartilhado em
# exclusivo. A primeira versao usava isso para "conferir que o SH estava tomado" e, com isso, o
# cenario virava outro: o teste passava a segurar LOCK_EX e a medir exclusao contra si mesmo. O jeito
# correto de conferir o estado e' de FORA: `flock -s -n <arquivo> -c true` (leitor entra, logo o
# nosso e' compartilhado) e `flock -x -n <arquivo> -c true` (escritor nao entra, logo HA lock).
#
# O que se mede, e por que cada medicao importa:
#   - recusa NOMEADA e IMEDIATA dos dois lados (nao ha espera nem retry escondido: o tempo e' medido);
#   - ausencia de falso positivo de corrupcao (o pior defeito possivel: chamar de corrompido o que e'
#     escrita em curso) e ausencia de "ok" mentiroso;
#   - livro-caixa: toda transacao commitada e' legivel depois, e nenhuma aparece a mais;
#   - LOCK e' ADVISORY: leitura crua nao e' impedida pelo sistema — limite declarado, nao garantia.
#
# Dados 100% SINTETICOS, em diretorio temporario. Nada de `MuServer/` e' lido ou usado.
# Contrato de saida: `# concorrencia=<n> falhas=<f> blocked=0`
set -u
cd "$(dirname "$0")/.." || exit 2

CTL=out/mu2dbctl
WRI=out/mu2dbcontend
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
DB=$T/conc.db
n=0; bad=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }
ms_agora() { date +%s%3N; }
tam() { stat -c%s "$1"; }

[ -x "$CTL" ] || { echo "concorrencia.sh: falta $CTL (rode 'make build')" >&2; exit 2; }
[ -x "$WRI" ] || { echo "concorrencia.sh: falta $WRI (rode 'make build')" >&2; exit 2; }

# ---------------------------------------------------------------- linha de base
"$CTL" "$DB" criar-conta base0 senha-de-teste-0 >/dev/null 2>&1
"$CTL" "$DB" criar-personagem base0 Alfa 1 >/dev/null 2>&1
ck "sem escritor ativo, verificar aprova (linha de base do cenario)" \
   '"$CTL" "$DB" verificar | grep -q "^integridade=ok$"'

# ---------------------------------------------------------------- (A) ESCRITOR REAL segurando o lock
N_OPS=20
"$WRI" "$DB" $N_OPS --gap-ms 5 --prefix con --hold-until-arquivo "$T/go" > "$T/w.txt" 2>&1 &
WPID=$!
for _ in $(seq 1 400); do
    grep -q '^hold=aguardando$' "$T/w.txt" 2>/dev/null && break
    kill -0 "$WPID" 2>/dev/null || break
    sleep 0.02
done
ck "escritor REAL abriu o banco, commitou as transacoes e esta' segurando o lock (hold=aguardando)" \
   '[ "$(grep -c "^op=.* estado=ok" "$T/w.txt")" = "$N_OPS" ] && grep -q "^hold=aguardando$" "$T/w.txt"'

TAM_A=$(tam "$DB")
A_OK=0; A_REC=0; A_OUT=0; A_MAX_MS=0
: > "$T/rec1.txt"
for _ in $(seq 1 12); do
    t0=$(ms_agora)
    if out=$("$CTL" "$DB" verificar 2>&1); then
        A_OK=$((A_OK+1))
    elif printf '%s' "$out" | grep -q "escritor ativo"; then
        A_REC=$((A_REC+1))
        [ -s "$T/rec1.txt" ] || printf '%s\n' "$out" > "$T/rec1.txt"
        t1=$(ms_agora); dt=$((t1-t0)); [ "$dt" -gt "$A_MAX_MS" ] && A_MAX_MS=$dt
    else
        A_OUT=$((A_OUT+1)); printf '# info: resposta fora do contrato: %s\n' "$out"
    fi
done
printf '# info: (A) com escritor real segurando o lock — verificar(recusado=%d aprovado=%d fora_do_contrato=%d) recusa_max_ms=%d, tentativas=12\n' \
       "$A_REC" "$A_OK" "$A_OUT" "$A_MAX_MS"

ck "(A) as 12 tentativas foram recusadas (nenhuma 'aprovou' com escritor ativo: aprovado=$A_OK)" '[ "$A_REC" = 12 ] && [ "$A_OK" = 0 ]'
ck "(A) nenhuma verificacao chamou de CORROMPIDO o que era escrita em curso (fora_do_contrato=$A_OUT)" '[ "$A_OUT" = 0 ]'
ck "(A) a recusa e' imediata, sem espera nem retry (pior caso medido: ${A_MAX_MS} ms < 2000 ms)" '[ "$A_MAX_MS" -lt 2000 ]'
ck "(A) a recusa nomeia motivo E estado: 'arquivo travado por outro processo' + 'escritor ativo'" \
   'grep -q "^erro=arquivo travado por outro processo$" "$T/rec1.txt" && grep -q "escritor ativo" "$T/rec1.txt"'
ck "(A) e a recusa NAO se disfarca de aprovacao (nenhum integridade=ok na mensagem)" \
   '! grep -q "^integridade=ok$" "$T/rec1.txt"'
if st_out=$("$CTL" "$DB" stats 2>&1); then ST_RC=0; else ST_RC=$?; fi
ck "(A) a leitura de DADOS (stats) tambem e' recusada com escritor ativo (exit=$ST_RC)" '[ "$ST_RC" = 1 ]'
ck "(A) as 13 tentativas recusadas nao alteraram um byte do arquivo (tamanho estavel)" \
   '[ "$(tam "$DB")" = "$TAM_A" ]'

touch "$T/go"
wait "$WPID"; RC_W=$?
ck "(A) o escritor terminou as $N_OPS transacoes com exit 0 depois da liberacao" \
   '[ "$RC_W" = 0 ] && grep -q "^# contend=$N_OPS falhas=0$" "$T/w.txt" && grep -q "^hold=liberado$" "$T/w.txt"'
ck "(A) depois do escritor, verificar APROVA (o lock nao ficou pendurado)" \
   '"$CTL" "$DB" verificar | grep -q "^integridade=ok$"'
ck "(A) livro-caixa: contas = 1 (base) + $N_OPS (escritor), nem uma a mais" \
   '"$CTL" "$DB" stats | grep -q "^contas=$((N_OPS+1))$"'
ck "(A) toda transacao commitada e' autenticavel (primeira, do meio e ultima)" \
   '"$CTL" "$DB" autenticar con0 senha-de-teste-0 | grep -q "^autenticado=sim$" &&
    "$CTL" "$DB" autenticar con10 senha-de-teste-10 | grep -q "^autenticado=sim$" &&
    "$CTL" "$DB" autenticar con19 senha-de-teste-19 | grep -q "^autenticado=sim$"'

# ---------------------------------------------------------------- (B) LEITOR ativo x ESCRITOR real
exec 9>>"$DB"
flock -s -n 9
ck "(B) o processo de teste segurou LOCK_SH de verdade no arquivo" 'flock -s -n "$DB" -c true'
ck "(B) e' um lock COMPARTILHADO, nao exclusivo (outro leitor entra; outro escritor nao)" \
   'flock -s -n "$DB" -c true && ! flock -x -n "$DB" -c true'
TAM_B=$(tam "$DB")
T0=$(ms_agora)
"$WRI" "$DB" 3 --prefix pos > "$T/v.txt" 2>&1
RC_V=$?
T1=$(ms_agora); DT_V=$((T1-T0))
ck "(B) com LEITOR ativo, o escritor real e' recusado (exit 3) com motivo nomeado" \
   '[ "$RC_V" = 3 ] && grep -q "^erro=abrir$" "$T/v.txt" && grep -q "arquivo em uso" "$T/v.txt"'
ck "(B) a recusa do escritor tambem e' imediata (${DT_V} ms < 2000 ms): nao ha espera por lock" '[ "$DT_V" -lt 2000 ]'
ck "(B) NENHUMA transacao entrou (arquivo com o mesmo tamanho depois da recusa)" '[ "$(tam "$DB")" = "$TAM_B" ]'
ck "(B) e a recusa nao deixou rastro: nada de 'hold=aguardando' nem resumo de sucesso" \
   '! grep -q "^hold=" "$T/v.txt" && ! grep -q "^# contend=" "$T/v.txt"'
ck "(B) com o LEITOR ativo, verificar APROVA (leitor convive com leitor: LOCK_SH e' compartilhado)" \
   '"$CTL" "$DB" verificar | grep -q "^integridade=ok$"'
flock -u 9; exec 9>&-
ck "(B) liberado o leitor, o escritor real entra normalmente e o livro-caixa fecha" \
   '"$WRI" "$DB" 2 --prefix pos >/dev/null 2>&1 && "$CTL" "$DB" stats | grep -q "^contas=$((N_OPS+3))$"'
ck "(B) o segundo escritor so' entrou depois da liberacao (as 2 contas novas existem de verdade)" \
   '"$CTL" "$DB" autenticar pos0 senha-de-teste-0 | grep -q "^autenticado=sim$" &&
    "$CTL" "$DB" autenticar pos1 senha-de-teste-1 | grep -q "^autenticado=sim$"'

# ---------------------------------------------------------------- (C) LOCK ADVISORY: o limite, medido
# Isto nao e' uma garantia — e' o LIMITE dela, e precisa estar escrito em teste: o kernel nao impede
# ninguem de ler o arquivo ignorando o lock. A protecao existe porque TODOS os consumidores usam a
# biblioteca; um leitor cru (cat/dd/backup) le o arquivo no meio de uma escrita sem ser impedido.
exec 8>>"$DB"
flock -x -n 8
ck "(C) o teste tomou LOCK_EX de verdade (pre-condicao do limite)" '! flock -x -n "$DB" -c true'
if dd if="$DB" of="$T/cru.bin" bs=32 count=1 2>/dev/null; then LIM_OK=1; else LIM_OK=0; fi
ck "(C) LIMITE declarado: leitura CRUA ignora o lock (kernel nao impede) — protecao e' cooperativa" '[ "$LIM_OK" = 1 ]'
if "$CTL" "$DB" verificar >/dev/null 2>&1; then LIM_LIB=1; else LIM_LIB=0; fi
ck "(C) a MESMA tentativa pela biblioteca e' recusada — a diferenca e' o consumidor, nao o sistema" '[ "$LIM_LIB" = 0 ]'
if "$CTL" "$DB" stats >/dev/null 2>&1; then LIM_ST=1; else LIM_ST=0; fi
ck "(C) o caminho de leitura de DADOS (stats) tambem passa por lock exclusivo na abertura: recusado" '[ "$LIM_ST" = 0 ]'
flock -u 8; exec 8>&-
ck "(C) liberado, o arquivo volta ao uso normal e permanece integro" \
   '"$CTL" "$DB" verificar | grep -q "^integridade=ok$" && "$CTL" "$DB" stats | grep -q "^contas=$((N_OPS+3))$"'

printf '1..%d\n# concorrencia=%d falhas=%d blocked=0\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1

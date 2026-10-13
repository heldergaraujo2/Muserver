#!/usr/bin/env bash
# sincronia.sh — regressao da garra de durabilidade da R-11, medida por SEQUENCIA DE SYSCALLS.
#
# Origem (auditoria P3, 2026-10-13): o relatorio `reports/r11-persistencia.md` §1 lista "flock" e a
# §5 diz que "durabilidade" esta coberta. A leitura de `src/db.c` mostrou uma assimetria: o commit
# de transacao explicita (`mu2db_tx_commit`) sincronizava, mas a operacao implicita (`registra`)
# gravava e voltava sem `fsync` — a sincronizacao so acontecia no `mu2db_fechar()`.
#
# O conteudo do arquivo NAO distingue os dois casos (a pagina suja esta no page cache e qualquer
# leitura a encontra) e `strace` nao existe neste ambiente. Por isso a medicao e a sequencia real de
# `pwrite`/`fsync` observada por interposicao (`tests/io_trace.c`, LD_PRELOAD, nada compilado no
# produto). Contrato de saida: `# sincronia=<n> falhas=<f> blocked=<b>`.
#
# Dados 100% SINTETICOS. Nada de `MuServer/` e lido, copiado ou usado como fixture.
set -u
cd "$(dirname "$0")/.." || exit 2

CTL=out/mu2dbctl
SHIM=out/io_trace.so
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
DB=$T/sinc.db
n=0; bad=0

bloqueia() {  # pre-condicao ausente: BLOCKED nomeado, nunca aprovacao silenciosa
    printf '1..0\n# sincronia=0 falhas=0 blocked=1\n# BLOCKED motivo=%s\n' "$1"
    exit 0
}

[ -x "$CTL" ] || bloqueia "falta $CTL (rode 'make build')"
command -v cc >/dev/null 2>&1 || bloqueia "cc ausente (instrumento de traco nao pode ser construido)"
cc -shared -fPIC -O1 -o "$SHIM" tests/io_trace.c -ldl > "$T/cc.log" 2>&1 \
    || bloqueia "falha ao construir $SHIM: $(head -1 "$T/cc.log")"

ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

# traco <arquivo-de-log> <comando...> — roda o CLI sob o instrumento e guarda a sequencia
traco() {
    local log=$1; shift
    rm -f "$log"
    ASAN_OPTIONS=verify_asan_link_order=0 MU2DB_IO_LOG="$log" LD_PRELOAD="$PWD/$SHIM" \
        "$CTL" "$DB" "$@" > "$T/cmd.out" 2>&1
    return $?
}

# analisa <log> — imprime: n_fsync  linha_fsync_inline  tamanho_fsync_inline  fim_do_ultimo_registro
#                            ultima_linha_de_reescrita_do_cabecalho  linha_do_ultimo_registro
# Regra do produto: registros sao acrescentados em offset > 0; o cabecalho (64 B) e reescrito em
# offset 0 na abertura e no fechamento. O `fsync` "inline" e o que cai entre o fim dos registros e a
# reescrita final do cabecalho, com tamanho igual ao fim do ultimo registro (cobre o que foi gravado).
analisa() {
    awk '
        $1 == "pwrite" && $3 == "off=0" {
            split($4, l, "="); if (l[2] + 0 == 64) cab_linha = NR
        }
        $1 == "pwrite" && $3 != "off=0" {
            split($3, o, "="); off = o[2] + 0
            split($4, l, "="); reg_fim = off + l[2]; reg_linha = NR
        }
        $1 == "fsync" {
            nf++
            split($3, t, "="); tam = t[2] + 0
            if (NR > reg_linha && inline_linha == 0 && tam == reg_fim) { inline_linha = NR; inline_tam = tam }
        }
        END { printf "%d %d %d %d %d %d\n", nf, inline_linha, inline_tam, reg_fim, cab_linha, reg_linha }
    ' "$1"
}

# ---------------------------------------------------------------- preparo
"$CTL" "$DB" criar-conta jogador1 senha-forte-1 >/dev/null 2>&1
"$CTL" "$DB" criar-personagem jogador1 Alfa 1 >/dev/null 2>&1
"$CTL" "$DB" criar-personagem jogador1 Beta 1 >/dev/null 2>&1
ck "preparo: conta e dois personagens" \
   '"$CTL" "$DB" stats | grep -q "^contas=1$" && "$CTL" "$DB" stats | grep -q "^personagens=2$"'

# ---------------------------------------------------------------- 1) operacao IMPLICITA sincroniza
traco "$T/imp.log" criar-conta outro senha1234 >/dev/null 2>&1
read -r NF IMP_LINHA IMP_TAM REG_FIM CAB_LINHA REG_LINHA <<EOF
$(analisa "$T/imp.log")
EOF
ck "operacao implicita: houve fsync no fd do banco (>=1)" '[ "$NF" -ge 1 ]'
ck "operacao implicita: existe fsync ENTRE o fim dos registros e a reescrita final do cabecalho" \
   '[ "$IMP_LINHA" -gt 0 ] && [ "$IMP_LINHA" -gt "$REG_LINHA" ] && [ "$IMP_LINHA" -lt "$CAB_LINHA" ]'
ck "operacao implicita: o fsync cobre exatamente o ultimo registro gravado (tamanho == fim)" \
   '[ "$IMP_TAM" -eq "$REG_FIM" ] && [ "$REG_FIM" -gt 64 ]'
ck "operacao implicita: ha DOIS fsync (inline + fechamento) — a garra que a auditoria P3 encontrou" \
   '[ "$NF" -ge 2 ]'
ck "operacao implicita: o efeito esta visivel em processo novo" \
   '"$CTL" "$DB" stats | grep -q "^contas=2$" && "$CTL" "$DB" autenticar outro senha1234 | grep -q "^autenticado=sim$"'

# ---------------------------------------------------------------- 2) TX EXPLICITA continua sincronizada
"$CTL" "$DB" dar-item jogador1 Alfa 700 1 9 >/dev/null 2>&1
traco "$T/tx.log" transferir jogador1 Alfa 0 Beta >/dev/null 2>&1
read -r NF_TX TX_LINHA TX_TAM REG_FIM_TX CAB_LINHA_TX REG_LINHA_TX <<EOF
$(analisa "$T/tx.log")
EOF
ck "transacao explicita: existe fsync ENTRE o fim dos registros e a reescrita final do cabecalho" \
   '[ "$TX_LINHA" -gt 0 ] && [ "$TX_LINHA" -gt "$REG_LINHA_TX" ] && [ "$TX_LINHA" -lt "$CAB_LINHA_TX" ]'
ck "transacao explicita: o fsync cobre exatamente o ultimo registro (tamanho == fim)" \
   '[ "$TX_TAM" -eq "$REG_FIM_TX" ] && [ "$REG_FIM_TX" -gt 64 ]'
ck "transacao explicita: efeito visivel em processo novo (item no destino, origem vazia)" \
   '"$CTL" "$DB" listar-inventario jogador1 Beta | grep -q "^quantidade=1$" &&
    "$CTL" "$DB" listar-inventario jogador1 Alfa | grep -q "^quantidade=0$"'

# ---------------------------------------------------------------- 3) leitura nao grava registro
ANTES=$(stat -c %s "$DB")
traco "$T/lei.log" autenticar jogador1 senha-forte-1 >/dev/null 2>&1
DEPOIS=$(stat -c %s "$DB")
ck "leitura pura: nenhum registro novo entra no arquivo (tamanho inalterado)" '[ "$ANTES" = "$DEPOIS" ]'
ck "leitura pura: nenhum pwrite em offset > 0 (so o cabecalho e reescrito)" \
   '! awk "\$1 == \"pwrite\" && \$3 != \"off=0\" { saiu = 1 } END { exit saiu ? 0 : 1 }" "$T/lei.log"'

# ---------------------------------------------------------------- 4) recusa nao deixa rabo
# `tipo 0` e recusado antes de qualquer gravacao (medido: tipo 99 e aceito como tipo livre de item,
# entao o caso de recusa tem de ser um argumento que a validacao rejeita de fato).
ANTES=$(stat -c %s "$DB")
traco "$T/rec.log" dar-item jogador1 Alfa 0 1 9 >/dev/null 2>&1 && RECUSA_OK=0 || RECUSA_OK=1
DEPOIS=$(stat -c %s "$DB")
ck "operacao recusada (tipo 0) sai != 0 com erro nomeado" \
   '[ "$RECUSA_OK" = 1 ] && grep -q "^erro=" "$T/cmd.out"'
ck "operacao recusada nao grava registro (nenhum pwrite em offset > 0, tamanho inalterado)" \
   '[ "$ANTES" = "$DEPOIS" ] &&
    ! awk "\$1 == \"pwrite\" && \$3 != \"off=0\" { saiu = 1 } END { exit saiu ? 0 : 1 }" "$T/rec.log"'
ck "arquivo continua integro depois das recusas" '"$CTL" "$DB" verificar | grep -q "^integridade=ok$"'

# ---------------------------------------------------------------- 5) custo, medido e declarado
ini=$(date +%s%N)
for i in $(seq 1 10); do "$CTL" "$DB" dar-item jogador1 Alfa $((600 + i)) 1 9 >/dev/null 2>&1; done
fim=$(date +%s%N)
ck "10 operacoes implicitas completam e ficam visiveis" \
   '"$CTL" "$DB" listar-inventario jogador1 Alfa | grep -q "^quantidade=10$"'
printf '# info: custo_10_operacoes_implicitas_ms=%d (processo novo por operacao; inclui 1 fsync inline cada)\n' \
       $(( (fim - ini) / 1000000 ))

printf '1..%d\n# sincronia=%d falhas=%d blocked=0\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1

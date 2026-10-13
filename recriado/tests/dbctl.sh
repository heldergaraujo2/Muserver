#!/usr/bin/env bash
# dbctl.sh — integracao do CLI `mu2dbctl` com a biblioteca de persistencia (fase R-11).
#
# O valor deste teste esta em duas escolhas:
#   1. cada comando e um PROCESSO NOVO: o estado tem de vir do arquivo, nunca de memoria do
#      processo anterior. E a forma de provar durabilidade sem depender de sorte de agendamento;
#   2. o CLI e a biblioteca de teste (db_test) sao consumidores diferentes da MESMA API — um defeito
#      de contrato aparece nos dois.
#
# Dados 100% SINTETICOS. Nada do `MuServer/` e lido ou usado como fixture.
# Contrato de saida: `# dbctl=<n> falhas=<f> blocked=0`
set -u
cd "$(dirname "$0")/.." || exit 2

CTL=out/mu2dbctl
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
DB=$T/contas.db
n=0; bad=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

[ -x "$CTL" ] || { echo "dbctl.sh: falta $CTL (rode 'make build')" >&2; exit 2; }

# ---------------------------------------------------------------- ciclo de operacao real
"$CTL" "$DB" criar-conta jogador1 senha-forte-1 > "$T/1.txt" 2>&1
ck "criar-conta pelo CLI sai 0 e imprime a conta e o id" \
   'grep -q "^conta=jogador1$" "$T/1.txt" && grep -q "^id=1$" "$T/1.txt"'
ck "conta duplicada e recusada (exit != 0, erro nomeado)" \
   '! "$CTL" "$DB" criar-conta jogador1 outra-senha-9 > "$T/2.txt" 2>&1 &&
    grep -q "^erro=nome ja usado$" "$T/2.txt"'
ck "autenticacao correta pelo CLI" \
   '"$CTL" "$DB" autenticar jogador1 senha-forte-1 | grep -q "^autenticado=sim$"'
ck "senha errada e recusada pelo CLI (exit != 0)" \
   '! "$CTL" "$DB" autenticar jogador1 senha-errada-1 > "$T/3.txt" 2>&1 &&
    grep -q "^erro=senha invalida$" "$T/3.txt"'

"$CTL" "$DB" criar-personagem jogador1 Guerreiro 1 > "$T/4.txt" 2>&1
ck "criar-personagem pelo CLI" 'grep -q "^personagem=Guerreiro$" "$T/4.txt"'
"$CTL" "$DB" criar-personagem jogador1 Mago 2 > "$T/5.txt" 2>&1
ck "segundo personagem na mesma conta" '"$CTL" "$DB" listar-personagens jogador1 | grep -q "^quantidade=2$"'

# estado gravado por processo A tem de aparecer para o processo B (durabilidade entre execucoes)
"$CTL" "$DB" mover jogador1 Guerreiro 3 200 42 >/dev/null 2>&1
"$CTL" "$DB" zen jogador1 Guerreiro 777 >/dev/null 2>&1
"$CTL" "$DB" dar-item jogador1 Guerreiro 4001 3 255 > "$T/6.txt" 2>&1
ck "dar-item pelo CLI informa o slot" 'grep -q "^slot=0$" "$T/6.txt"'
ck "estado movido/zen/item aparece em processo NOVO (arquivo e a fonte)" \
   '"$CTL" "$DB" mostrar-personagem jogador1 Guerreiro | grep -q "^mapa=3$" &&
    "$CTL" "$DB" mostrar-personagem jogador1 Guerreiro | grep -q "^zen=777$" &&
    "$CTL" "$DB" mostrar-personagem jogador1 Guerreiro | grep -q "^itens=1$"'
ck "listar-inventario mostra tipo, nivel e durabilidade" \
   '"$CTL" "$DB" listar-inventario jogador1 Guerreiro | grep -q "tipo:4001" &&
    "$CTL" "$DB" listar-inventario jogador1 Guerreiro | grep -q "durabilidade:255"'

# transferencia entre personagens, com o MESMO id de item
ID_ITEM=$("$CTL" "$DB" listar-inventario jogador1 Guerreiro | awk -F'id:| tipo' '/^item1=/{print $2}')
"$CTL" "$DB" transferir jogador1 Guerreiro 0 Mago > "$T/7.txt" 2>&1
ck "transferir pelo CLI sai 0" 'grep -q "^transferido=sim$" "$T/7.txt"'
ck "item saiu de um personagem e entrou no outro, mantendo o id" \
   '"$CTL" "$DB" listar-inventario jogador1 Guerreiro | grep -q "^quantidade=0$" &&
    "$CTL" "$DB" listar-inventario jogador1 Mago | grep -q "^quantidade=1$" &&
    "$CTL" "$DB" listar-inventario jogador1 Mago | grep -q "id:$ID_ITEM"'

# troca de senha vale no processo seguinte
"$CTL" "$DB" trocar-senha jogador1 senha-nova-2026 >/dev/null 2>&1
ck "senha antiga deixa de valer e a nova vale (processos distintos)" \
   '! "$CTL" "$DB" autenticar jogador1 senha-forte-1 >/dev/null 2>&1 &&
    "$CTL" "$DB" autenticar jogador1 senha-nova-2026 | grep -q "^autenticado=sim$"'

# apagar personagem e conferir o limite/estado
"$CTL" "$DB" apagar-personagem jogador1 Mago >/dev/null 2>&1
ck "apagar-personagem pelo CLI e visivel no processo seguinte" \
   '"$CTL" "$DB" listar-personagens jogador1 | grep -q "^quantidade=1$"'

# ---------------------------------------------------------------- stats e integridade
"$CTL" "$DB" stats > "$T/8.txt" 2>&1
ck "stats conta 1 conta, 1 personagem e schema 1" \
   'grep -q "^contas=1$" "$T/8.txt" && grep -q "^personagens=1$" "$T/8.txt" &&
    grep -q "^schema=1$" "$T/8.txt"'
ck "verificar aprova o arquivo produzido pelo uso normal" \
   '"$CTL" "$DB" verificar | grep -q "^integridade=ok$"'

# ---------------------------------------------------------------- recusas (entrada ruim)
ck "comando desconhecido sai 2 com uso" \
   '! "$CTL" "$DB" comando-que-nao-existe >/dev/null 2>&1'
ck "arquivo inexistente em diretorio inexistente falha com erro nomeado" \
   '! "$CTL" "$T/nao/existe/x.db" stats > "$T/9.txt" 2>&1 && grep -q "^erro=abrir$" "$T/9.txt"'

# corrupcao: o CLI tem de recusar, nao "consertar" sozinho
cp "$DB" "$T/corrompido.db"
printf 'X' | dd of="$T/corrompido.db" bs=1 seek=100 conv=notrunc status=none
ck "verificar detecta corrupcao e sai != 0" \
   '! "$CTL" "$T/corrompido.db" verificar > "$T/10.txt" 2>&1 && grep -q "^erro=" "$T/10.txt"'

# ---------------------------------------------------------------- morte REAL no meio da transacao
# Este bloco existe porque a versao anterior so simulava o corte truncando o arquivo: truncar testa
# o que NOS escrevemos, nao o que o SO ja tinha em disco quando o processo morreu. Aqui o processo
# morre de verdade no meio (MU2DB_TESTE_ABORTA_APOS, gancho de teste em src/db.c): o codigo de
# recuperacao tem de desfazer sozinho, sem o processo ter chance de limpar nada.
CR=$T/crash.db
"$CTL" "$CR" criar-conta jogador1 senha-forte-1 >/dev/null 2>&1
"$CTL" "$CR" criar-personagem jogador1 Alfa 1 >/dev/null 2>&1
"$CTL" "$CR" criar-personagem jogador1 Beta 2 >/dev/null 2>&1
"$CTL" "$CR" dar-item jogador1 Alfa 7001 1 100 >/dev/null 2>&1

for ponto in 1 2; do
  MU2DB_TESTE_ABORTA_APOS=$ponto "$CTL" "$CR" transferir jogador1 Alfa 0 Beta >/dev/null 2>&1
  matou=$?
  ck "processo morre de verdade no ponto $ponto da transferencia (exit 97)" "[ $matou -eq 97 ]"
  ck "morte no ponto $ponto: item continua na ORIGEM (transacao desfeita, nao metade aplicada)" \
     '"$CTL" "$CR" listar-inventario jogador1 Alfa | grep -q "^quantidade=1$"'
  ck "morte no ponto $ponto: destino NAO recebeu nada" \
     '"$CTL" "$CR" listar-inventario jogador1 Beta | grep -q "^quantidade=0$"'
  ck "morte no ponto $ponto: arquivo continua integro para o verify" \
     '"$CTL" "$CR" verificar | grep -q "^integridade=ok$"'
done
# A recuperacao nao so conta: ela REPARA. Medido aqui: o arquivo volta ao tamanho de antes do
# corte, a primeira abertura relata o descarte e a seguinte ja encontra tudo limpo.
TAM_ANTES=$(stat -c %s "$CR")
MU2DB_TESTE_ABORTA_APOS=1 "$CTL" "$CR" transferir jogador1 Alfa 0 Beta >/dev/null 2>&1
DESC1=$("$CTL" "$CR" stats | sed -n "s/^descartados=//p")
DESC2=$("$CTL" "$CR" stats | sed -n "s/^descartados=//p")
TAM_DEPOIS=$(stat -c %s "$CR")
ck "primeira abertura apos o corte relata a operacao descartada (descartados=$DESC1)" \
   '[ "${DESC1:-0}" -ge 1 ]'
ck "segunda abertura ja encontra arquivo reparado (descartados=$DESC2, sem contar duas vezes)" \
   '[ "${DESC2:-x}" = 0 ]'
ck "o rabo sem commit saiu do arquivo (tamanho volta ao valor de antes do corte)" \
   '[ "$TAM_DEPOIS" = "$TAM_ANTES" ]'
ck "depois da recuperacao o item continua na origem (registro abandonado nao foi replaysado)" \
   '"$CTL" "$CR" listar-inventario jogador1 Alfa | grep -q "^quantidade=1$" &&
    "$CTL" "$CR" listar-inventario jogador1 Beta | grep -q "^quantidade=0$"'
ck "depois da recuperacao a base volta a aceitar operacao normal" \
   '"$CTL" "$CR" transferir jogador1 Alfa 0 Beta >/dev/null 2>&1 &&
    "$CTL" "$CR" listar-inventario jogador1 Beta | grep -q "^quantidade=1$" &&
    "$CTL" "$CR" listar-inventario jogador1 Alfa | grep -q "^quantidade=0$"'

printf '1..%d\n# dbctl=%d falhas=%d blocked=0\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1

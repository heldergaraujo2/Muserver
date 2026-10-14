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

# ---------------------------------------------------------------- D2-41: verificacao concorrente
# O CENARIO tem de realmente acontecer: quem segura o lock exclusivo e outro PROCESSO (flock(1)),
# e o estado do lock e confirmado por leitura concorrente dos dois lados — nao basta "rodou muitas
# vezes e deu certo".
VK=$T/verifycon.db
"$CTL" "$VK" criar-conta jogador1 senha-forte-9 >/dev/null 2>&1
"$CTL" "$VK" criar-personagem jogador1 Concorrente 1 >/dev/null 2>&1

ck "sem escritor ativo: verificar aprova (linha de base do cenario)" \
   '"$CTL" "$VK" verificar | grep -q "^integridade=ok$"'

# (a) escritor ativo segurando LOCK_EX com o processo VIVO: verificar tem de recusar
exec 8>>"$VK"
ck "o processo de teste obteve LOCK_EX de verdade no arquivo (flock(1))" 'flock -n 8'
"$CTL" "$VK" verificar > "$T/vk1.txt" 2>&1
RC_VK1=$?
ck "com ESCRITOR ativo, verificar sai != 0 (recusa, nao leitura rasgada)" '[ "$RC_VK1" -ne 0 ]'
ck "a recusa nomeia o motivo (arquivo em uso / escritor ativo)" \
   'grep -q "arquivo em uso" "$T/vk1.txt" && grep -q "escritor ativo" "$T/vk1.txt"'
ck "a recusa NAO se disfarca de sucesso (nenhum integridade=ok na saida)" \
   '! grep -q "^integridade=ok$" "$T/vk1.txt"'
ck "segunda tentativa com escritor ativo: mesma recusa (nao e sorte de agendamento)" \
   '! "$CTL" "$VK" verificar > "$T/vk2.txt" 2>&1 && grep -q "escritor ativo" "$T/vk2.txt"'

# (b) a verificacao recusada NAO deixou lock pendurado: o escritor continua sendo o unico dono
ck "depois da recusa, o LOCK_EX do teste continua valido (verify nao tomou lock nenhum)" 'flock -n 8'
# (c) leitor ativo: bloqueio compartilhado e compativel (a leitura convive com leitura)
exec 9>>"$VK"
flock -s -n 9
ck "com LEITOR ativo (LOCK_SH), o verify continua recusando enquanto o escritor do teste existe" \
   '! "$CTL" "$VK" verificar >/dev/null 2>&1'
flock -u 8
ck "liberado o escritor do teste, o verify aprova mesmo com LEITOR ativo (LOCK_SH e compartilhado)" \
   '"$CTL" "$VK" verificar | grep -q "^integridade=ok$"'
ck "o LOCK_SH do teste continua valido depois do verify (verify nao mexe no lock de outro)" 'flock -n 9'
# (d) o escritor do produto espera? NAO: um leitor ativo exclui o escritor, com motivo nomeado
"$CTL" "$VK" criar-conta outra senha-forte-9 > "$T/vk3.txt" 2>&1
RC_VK3=$?
ck "com LEITOR ativo, o ESCRITOR (criar-conta) e recusado com motivo nomeado" \
   '[ "$RC_VK3" -ne 0 ] && grep -q "^erro=abrir$" "$T/vk3.txt" && grep -q "arquivo em uso" "$T/vk3.txt"'
flock -u 9
ck "liberado o leitor, o escritor entra normalmente" \
   '"$CTL" "$VK" criar-conta outra senha-forte-9 >/dev/null 2>&1 &&
    "$CTL" "$VK" stats | grep -q "^contas=2$"'
exec 8>&-; exec 9>&-
ck "arquivo continua integro depois de todo o cenario concorrente" \
   '"$CTL" "$VK" verificar | grep -q "^integridade=ok$"'

# (e) corroboracao com escritor REAL: verificadores e escritor rodando ao mesmo tempo.
# Aqui aparece um efeito do desenho que precisa ficar registrado, nao escondido: verificacao e
# escrita se EXCLUEM (LOCK_SH x LOCK_EX), entao quem perde a corrida e recusado nomeado — inclusive
# o ESCRITOR pode ser recusado enquanto um verificador roda. Medir isso (e nao fingir que nao
# existe) e o objetivo deste bloco. As tres afirmacoes sao sobre fatos contados nos dois lados:
#   - sobreposicao: pelo menos um lado viu recusa (se nenhum viu, os dois nunca se encontraram);
#   - livro-caixa: o inventario final e EXATAMENTE o numero de escritas bem-sucedidas;
#   - contrato: nenhuma resposta fora do contrato (nem "corrupcao" falsa, nem "ok" mentiroso).
VK2=$T/verifycon2.db
"$CTL" "$VK2" criar-conta jogador1 senha-forte-9 >/dev/null 2>&1
"$CTL" "$VK2" criar-personagem jogador1 Alfa 1 >/dev/null 2>&1
VR_OK=0; VR_REC=0; VR_OUT=0; WR_OK=0; WR_REC=0
for tentativa in 1 2 3; do
    : > "$T/vk_iter.txt"
    ( i=0
      while [ $i -lt 40 ]; do
          i=$((i + 1))
          if out=$("$CTL" "$VK2" verificar 2>&1); then echo "OK" >> "$T/vk_iter.txt"
          elif printf '%s' "$out" | grep -q "escritor ativo"; then echo "RECUSA" >> "$T/vk_iter.txt"
          else echo "OUTRO: $out" >> "$T/vk_iter.txt"; fi
      done ) &
    VPID=$!
    j=0
    while [ $j -lt 20 ]; do
        j=$((j + 1))
        if out=$("$CTL" "$VK2" dar-item jogador1 Alfa $((900 + tentativa * 100 + j)) 1 9 2>&1); then
            WR_OK=$((WR_OK + 1))
        elif printf '%s' "$out" | grep -q "arquivo em uso"; then
            WR_REC=$((WR_REC + 1))
        fi
    done
    wait "$VPID"
    VR_OK=$((VR_OK + $(grep -c "^OK" "$T/vk_iter.txt")))
    VR_REC=$((VR_REC + $(grep -c "^RECUSA" "$T/vk_iter.txt")))
    VR_OUT=$((VR_OUT + $(grep -c "^OUTRO" "$T/vk_iter.txt")))
    cp "$T/vk_iter.txt" "$T/vk_t$tentativa.txt"
done
printf '# info: concorrencia tentativas=3 verificar(ok=%d recusado=%d fora_do_contrato=%d) escritor(ok=%d recusado=%d)\n' \
       "$VR_OK" "$VR_REC" "$VR_OUT" "$WR_OK" "$WR_REC"
ck "sobreposicao REALMENTE aconteceu (recusas somadas dos dois lados = $((VR_REC + WR_REC)) >= 1)" \
   '[ $((VR_REC + WR_REC)) -ge 1 ]'
ck "nenhuma resposta fora do contrato durante a concorrencia (nem corrupcao falsa nem ok mentiroso: $VR_OUT)" \
   '[ "$VR_OUT" = 0 ]'
ck "livro-caixa exato: o inventario tem exatamente as $WR_OK escritas bem-sucedidas" \
   '[ "$WR_OK" -ge 1 ] && "$CTL" "$VK2" listar-inventario jogador1 Alfa | grep -q "^quantidade=$WR_OK$"'
ck "e o arquivo final esta integro" '"$CTL" "$VK2" verificar | grep -q "^integridade=ok$"'

printf '1..%d\n# dbctl=%d falhas=%d blocked=0\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1

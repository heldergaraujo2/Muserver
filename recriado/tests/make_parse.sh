#!/usr/bin/env bash
# make_parse.sh — o Makefile e parte do contrato: se as flags mudam silenciosamente, o portao
# de qualidade muda junto. 7 casos, cada um com o motivo escrito na saida.
set -u
cd "$(dirname "$0")/.." || exit 2
n=0; bad=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"; else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

ck "1. CFLAGS padrao carregam -Werror e os dois sanitizadores" \
   "make -s dump-CFLAGS | grep -q -- '-Werror' && make -s dump-CFLAGS | grep -q -- '-fsanitize=address,undefined'"
ck "2. SAN=0 desliga sanitizadores mas mantem otimizacao e avisos" \
   "make -s SAN=0 dump-CFLAGS | grep -q -- '-O2' && make -s SAN=0 dump-CFLAGS | grep -q -- '-Werror' && ! make -s SAN=0 dump-CFLAGS | grep -q -- '-fsanitize'"
ck "3. out/ fica fora da arvore rastreada (ignorado) e o produto nao" \
   "git check-ignore -q out/mud2 && ! git check-ignore -q src/wire.c"
# -B e obrigatorio aqui: sem ele, um diretorio de saida ja atualizado faz o make -n imprimir só
# "./out/unit" e o caso passa a falhar por estado ambiente, nao por defeito do Makefile (foi assim
# que ele quebrou na primeira execucao desta suíte). -B forcga o grafo de dependencias inteiro.
ck "4. a build descrita compila os dois objetos e os liga no binario de teste" \
   "make -s -B -n unit | grep -q -- '-c src/wire.c -o out/wire.o' && make -s -B -n unit | grep -q -- '-c tests/unit.c -o out/unit.o' && make -s -B -n unit | grep -q -- 'out/wire.o out/unit.o -o out/unit'"
ck "5. alvo inexistente falha com erro proprio (nada de engolir digitacao errada)" \
   "! make -s alvo-que-nao-existe >/dev/null 2>&1"
ck "6. a build do servico compila mud2, mu2ctl e netclient e liga o codec em cada um" \
   "make -s -B -n build | grep -q -- 'src/mud2.c out/wire.o -o out/mud2' && make -s -B -n build | grep -q -- 'src/mu2ctl.c out/wire.o -o out/mu2ctl' && make -s -B -n build | grep -q -- 'tests/netclient.c out/wire.o -o out/netclient'"
# O portao nao pode perder a suíte de rede em silencio: se alguem tirar `net` do check, o caso
# abaixo falha. Portao que encolhe sem avisar e o jeito mais barato de fingir qualidade.
ck "7. check inclui a suíte de rede (nao so unit e make-sintaxe)" \
   "make -s -n check | grep -q 'tests/net.sh'"

printf '1..%d\n# make-sintaxe=%d falhas=%d\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1

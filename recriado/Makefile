# Makefile do v2 (mu2). Build sempre fora da raiz (build/, ignorado por recriado/.gitignore),
# sanitizadores ligados por padrao: `make SAN=0` e a unica forma de desliga-los, e serve para
# comparar custo, nao para publicar resultado.
CC       ?= cc
STD      ?= -std=c11
OPT      ?= -O2 -g
SAN      ?= 1
WARN     := -Wall -Wextra -Werror -Wshadow -Wconversion -Wsign-conversion
HARDEN   := -fstack-protector-strong -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3
SANFLAGS := -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
ifeq ($(SAN),0)
SANFLAGS :=
endif

CFLAGS   ?= $(STD) $(OPT) $(WARN) $(HARDEN) $(SANFLAGS) -Iinclude
LDFLAGS  ?= $(if $(filter 1,$(SAN)),-fsanitize=address,undefined,)

BUILD := out
SRC   := src/wire.c
SRV   := src/mud2.c
CTL   := src/mu2ctl.c
NCLI  := tests/netclient.c
CODEC := tools/mu2codec.c
FUZZ  := tools/mu2fuzz.c
HDR   := include/mu2/mu2.h include/mu2/proto.h
OBJ   := $(BUILD)/wire.o
UNIT  := $(BUILD)/unit
MUD2  := $(BUILD)/mud2
MU2CTL:= $(BUILD)/mu2ctl
NETCLI:= $(BUILD)/netclient
CODECBIN:= $(BUILD)/mu2codec
FUZZBIN:= $(BUILD)/mu2fuzz

.PHONY: all build unit make-sintaxe net net-matrix pe data pe-selftest data-selftest cfg cfg-selftest conform matriz golden interop fuzz bench gate gate-selftest check dump-CC dump-CFLAGS dump-SAN dump-BUILD dump-SRC

all: build

build: $(OBJ) $(MUD2) $(MU2CTL) $(NETCLI) $(CODECBIN) $(FUZZBIN)

$(BUILD):
	@mkdir -p $(BUILD)

$(OBJ): src/wire.c include/mu2/mu2.h | $(BUILD)
	$(CC) $(CFLAGS) -c src/wire.c -o $@

$(BUILD)/unit.o: tests/unit.c $(HDR) | $(BUILD)
	$(CC) $(CFLAGS) -c tests/unit.c -o $@

$(UNIT): $(OBJ) $(BUILD)/unit.o | $(BUILD)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

$(MUD2): $(SRV) $(OBJ) $(HDR) | $(BUILD)
	$(CC) $(CFLAGS) $(SRV) $(OBJ) -o $@ $(LDFLAGS)

$(MU2CTL): $(CTL) $(OBJ) $(HDR) | $(BUILD)
	$(CC) $(CFLAGS) $(CTL) $(OBJ) -o $@ $(LDFLAGS)

$(NETCLI): $(NCLI) $(OBJ) $(HDR) | $(BUILD)
	$(CC) $(CFLAGS) $(NCLI) $(OBJ) -o $@ $(LDFLAGS)

# CLI de teste do codec: liga contra o MESMO wire.o do servico, para que golden test exercite o
# caminho real em vez de uma reimplementacao. Nao sobe servico nem abre socket.
$(CODECBIN): $(CODEC) $(OBJ) $(HDR) | $(BUILD)
	$(CC) $(CFLAGS) $(CODEC) $(OBJ) -o $@ $(LDFLAGS)

# Fuzzing deterministico do codec: mesmo wire.o, oraculo de invariantes do contrato. Nao ha motor
# de fuzz neste host (sem afl/clang), entao nao ha cobertura guiada por feedback — a diferenca esta
# documentada na saida da ferramenta e no relatorio.
$(FUZZBIN): $(FUZZ) $(OBJ) $(HDR) | $(BUILD)
	$(CC) $(CFLAGS) $(FUZZ) $(OBJ) -o $@ $(LDFLAGS)

unit: $(UNIT)
	./$(UNIT)

make-sintaxe:
	@bash tests/make_parse.sh

# net: a matriz reduzida, rapida o bastante para morar dentro do portao.
# net-matrix: a matriz completa (5 repeticoes por configuracao), para publicar em reports/.
net: $(MUD2) $(MU2CTL) $(NETCLI)
	@NET_QUICK=1 bash tests/net.sh

net-matrix: $(MUD2) $(MU2CTL) $(NETCLI)
	@NET_QUICK=0 bash tests/net.sh

# R-5: sondas de formato. MU_REF_DATA e a referencia somente leitura (o pacote original).
# Se ela nao existir, pe/data imprimem BLOCKED e saem 0: bloqueado nao e aprovado, mas tambem
# nao e falha do codigo. Os alvos *-selftest rodam so a recusa de entrada invalida, sem tocar
# na referencia, e por isso funcionam num restore de bundle.
MU_REF_DATA ?= $(CURDIR)/../MuServer
export MU_REF_DATA

pe:
	@bash tests/pe.sh

data:
	@bash tests/data.sh

# R-6: endpoints e segredos da configuracao original (sonda redige credencial por regra)
cfg:
	@bash tests/cfg.sh

cfg-selftest:
	@SELFTEST_ONLY=1 bash tests/cfg.sh

pe-selftest:
	@SELFTEST_ONLY=1 bash tests/pe.sh

data-selftest:
	@SELFTEST_ONLY=1 bash tests/data.sh

# R-6: conformidade do protocolo v2 (byte a byte) e validacao da matriz de evidencias
conform: $(MUD2) $(MU2CTL) $(NETCLI)
	@bash tests/conform.sh

matriz:
	@python3 tools/matrix_check.py reports/r6-matriz.tsv

# R-7: baseline EXPLORATORIA de desempenho. Nao faz parte de `check` de proposito: e sensivel ao
# ruido do host e pode sair BLOCKED por drift, o que atrapalharia um alvo de verificacao rapida.
# O portao (`make gate`) a executa como etapa obrigatoria.
bench: $(MUD2) $(MU2CTL) $(NETCLI)
	@bash tests/bench.sh

# Golden: corpus byte a byte do codec, exercitado pela CLI que liga contra o mesmo wire.o do
# servico. Inclui as falsificacoes F20 (1 byte corrompido) e F21 (perfil trocado).
golden: $(CODECBIN)
	@bash tests/golden.sh

# Interop: as tres camadas separadas. A camada 3 (binario original) sai BLOCKED com a causa exata
# enquanto nao houver wine/qemu-i386 E autorizacao explicita; nada original e executado aqui.
interop:
	@bash tests/interop.sh

# Fuzz deterministico do codec: sementes do corpus golden, oraculo de invariantes, F22 diferencial.
# FUZZ_ITERS ajusta o volume (padrao 50000 por rodada).
fuzz: $(FUZZBIN) $(CODECBIN)
	@bash tests/fuzz.sh

# R-8: portao unico. `gate` executa tudo e imprime a mesa de estados; `gate-selftest` testa o
# proprio portao (inclui as falsificacoes F12-F14) e e o que deve rodar primeiro: um portao que
# nao sabe falhar nao e portao. `gate` nao entra em `check` para nao haver recursao.
gate:
	@bash tests/run_all.sh

gate-selftest:
	@bash tests/gate_state.sh

check: unit make-sintaxe net pe data

# Introspecao usada por tests/make_parse.sh: o Makefile e contrato tambem, e tem de ser lido.
dump-CC:
	@printf '%s\n' '$(CC)'
dump-CFLAGS:
	@printf '%s\n' '$(CFLAGS)'
dump-SAN:
	@printf '%s\n' '$(SAN)'
dump-BUILD:
	@printf '%s\n' '$(BUILD)'
dump-SRC:
	@printf '%s\n' '$(SRC)'

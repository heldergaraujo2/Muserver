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
HDR   := include/mu2/mu2.h
OBJ   := $(BUILD)/wire.o
UNIT  := $(BUILD)/unit

.PHONY: all build unit make-sintaxe check dump-CC dump-CFLAGS dump-SAN dump-BUILD dump-SRC

all: build

build: $(OBJ)

$(BUILD):
	@mkdir -p $(BUILD)

$(OBJ): $(SRC) $(HDR) | $(BUILD)
	$(CC) $(CFLAGS) -c $(SRC) -o $@

$(BUILD)/unit.o: tests/unit.c $(HDR) | $(BUILD)
	$(CC) $(CFLAGS) -c tests/unit.c -o $@

$(UNIT): $(OBJ) $(BUILD)/unit.o | $(BUILD)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

unit: $(UNIT)
	./$(UNIT)

make-sintaxe:
	@bash tests/make_parse.sh

check: unit make-sintaxe

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

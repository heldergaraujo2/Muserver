# BUILD_AND_RUN — pré-requisitos e instruções reproduzíveis de compilação e execução

| campo | valor |
|---|---|
| data | 2026-10-13 |
| ambiente medido | Debian 12, kernel 6.1.158+, **2 vCPUs**, `gcc 12.2.0`, `make 4.3`, `python3 3.11.2`, `bash 5.2.15`, `git 2.39.5` (detalhe em `ENVIRONMENT.md`) |
| onde rodar | `recriado/` (monorepo) ou a raiz do repositório publicado — os scripts derivam o prefixo por medição (`PFX`), não por constante (`D2-37`) |

## 1. Pré-requisitos

**Obrigatórios** (todos usados por `make -s check`/`gate`): `cc`/`gcc` com C11 + ASan/UBSan, `make`,
`bash`, `python3` ≥ 3.8, `git`, `coreutils` (`timeout`, `setsid`, `realpath`), `awk`, `sed`, `grep`.

**Opcional** (muda o resultado de etapas específicas):

| ausente | efeito medido |
|---|---|
| `../MuServer` (referência, via `MU_REF_DATA`) | `pe`, `data`, `cfg`, `ref-intacta`, `interop`, `lua`, `lua-enc` → **`BLOCKED`** (nunca `PASS`) |
| interpretador **Lua** | `lua` sem verificação de sintaxe/execução (registrado na etapa) |
| `wine`/`qemu-i386` + autorização | `interop` camada 3 `BLOCKED` (a suíte **não** tem caminho de execução de binário original) |
| `clang` (libFuzzer), `valgrind`, `gdb` | não há fuzz com feedback nem memcheck — fuzzer próprio determinístico (D2-33) |

Nada disso é instalável a partir deste ambiente sem rede aprovada; cada ausência aparece como
`BLOCKED` com causa na mesa do portão, e **bloqueado não conta como aprovado**.

## 2. Compilar

```sh
cd recriado
make -s build            # saída em out/ (IGNORADA pelo git)
make -s SAN=0 build      # só para MEDIR custo; nunca para publicar resultado (D2-13)
make -s dump-CC dump-CFLAGS dump-SAN dump-BUILD dump-SRC   # introspecção usada pelo make-sintaxe
```

Artefatos produzidos (medidos nesta rodada, com sanitizadores): `out/wire.o`, `out/mud2`,
`out/mu2ctl`, `out/netclient`, `out/mu2codec`, `out/mu2fuzz`, `out/mu2admin`, `out/unit`.
Flags padrão: `-std=c11 -O2 -g -Wall -Wextra -Werror -Wshadow -Wconversion -Wsign-conversion
-fstack-protector-strong -D_FORTIFY_SOURCE=3 -fsanitize=address,undefined -fno-sanitize-recover=all`.

## 3. Rodar o serviço de ensaio

```sh
./out/mud2 --port 0 --log-file /tmp/mud2.log --profile orig &      # 127.0.0.1 por padrão
PORT=$(awk '/listen addr=/{for(i=1;i<=NF;i++) if($i ~ /^port=/){sub(/port=/,"",$i); print $i}}' /tmp/mud2.log)
./out/mu2ctl stats --port "$PORT"        # pede STATS e imprime a linha de métricas
./out/mu2codec encode --code 258 --body-size 8 --profile orig | od -A d -t x1z   # CLI do MESMO codec
kill -TERM %1                             # encerramento limpo; o log fecha com o resumo de contadores
```

Opções do `mud2`: `--listen`, `--port`, `--max-clients` (teto 8192), `--sndbuf`, `--idle-ms`,
`--profile orig|mur0`, `--log-level`, `--log-file`.

## 4. Rodar o console administrativo

```sh
printf '<token-forte>\tadmin\n' > /tmp/mu2admin.tok && chmod 600 /tmp/mu2admin.tok
./out/mu2admin --token-file /tmp/mu2admin.tok --port 0 --mud2-port "$PORT" --gate-tsv out/gate.tsv
curl -s -H "Authorization: Bearer <token-forte>" "http://127.0.0.1:ADMINPORT/admin" | head
```

Sem arquivo de token válido o processo **não sobe**; qualquer `--listen` fora de `127.0.0.1` é
recusado na partida; rotas de admin com papel `leitor` devolvem `403`; `/publicar` devolve `501`
**por decisão** (`docs/ADMIN_CONSOLE.md`).

## 5. Testar — alvos do Makefile (o contrato; `make-sintaxe` valida o próprio Makefile)

| alvo | o que roda | resultado de referência (2026-10-13) |
|---|---|---|
| `make -s check` | `unit` + `make-sintaxe` + `net` + `pe` + `data` | **182 asserções, 0 falhas, exit 0** |
| `make -s unit` | unidade do codec | 106/106 |
| `make -s make-sintaxe` | o Makefile como contrato | 10/10 |
| `make -s net` / `make -s net-matrix` | rede: matriz rápida / completa (100 config × 5 reps por perfil) | 34/34 · 36/36 (opt-in, ~11 min) |
| `make -s conform` | conformidade byte a byte | 15/15 |
| `make -s golden` | 38 vetores versionados + F20/F21 | 42/42 |
| `make -s interop` | 3 camadas (3ª `BLOCKED`) | 12/12, `blocked=1` |
| `make -s fuzz` | fuzzer determinístico (`FUZZ_ITERS`, padrão 50 000/rodada) | 12/12 |
| `make -s seguranca` | malformados, fd/RSS, SIGTERM, log | 13/13 |
| `make -s admin` | console: token, papéis, loopback | 25/25 |
| `make -s lua` / `make -s lua-enc` | camada Lua / cifragem do Lua | 13/13 (`blocked=1`) · 27/27 (`blocked=2`) |
| `make -s cfg` / `make -s matriz` / `make -s bench` | configuração (segredos redigidos) / matriz de evidências / baseline exploratória | 15/15 · exit 0 · 15/15 |
| `make -s pe` / `make -s data` | PE e dados da referência (`MU_REF_DATA`) | 14/14 · 21/21 |
| `make -s pe-selftest data-selftest cfg-selftest` | só a recusa de entrada inválida (sem tocar 615 MB) | 4/4 · 4/4 · 5/5 |
| `make -s gate` | **o portão único** (28 etapas) | **23 PASS / 0 FAIL / 3 BLOCKED / 2 SKIPPED, 553 asserções, exit 0** (2026-10-13) |
| `make -s gate-selftest` | testa o próprio portão (F12–F14, etapa duplicada) | 19/19 |

## 6. O portão único (é ele que define "verde")

```sh
make -s gate                       # 28 etapas; mesa de estados no stdout; TSV em out/gate.tsv
GATE_FULL=1 make -s gate           # inclui net-matrix e persistencia (opt-in, caros)
GATE_ONLY="golden fuzz" make -s gate   # roda só etapas nomeadas; o resto fica SKIPPED
GATE_SKIP=bench make -s gate           # dispensa explícita
```

| estado | significa |
|---|---|
| `PASS` | exit 0, `falhas=0`, `blocked=0` e linha de resumo presente |
| `FAIL` | exit ≠ 0, ou `falhas>0`, ou resumo ausente, ou timeout |
| `BLOCKED` | dependência externa concreta ausente — **não é aprovação** |
| `NOT_IMPLEMENTED` | etapa prevista sem arquivo — **não é aprovação** |
| `SKIPPED` | dispensada nesta execução (opt-in/`GATE_ONLY`/`GATE_SKIP`) — declarada, não silenciosa |

Exit do portão: `0` sem FAIL; `1` com qualquer FAIL; `130` se interrompido. A linha
`assercoes=` do resumo conta **apenas etapas PASS/FAIL** (as `BLOCKED` não entram) — somar os
números de todas as etapas dá mais; os dois números estão em `TESTING.md`.

**Persistência (não é banco de dados):** a etapa `persistencia` roda
`bash scripts/verify-backup.sh` — verifica o **bundle de backup do repositório** (clone real,
`MANIFEST.md`, sha256, ponta) e, com `FULL=1`, confere **o que está publicado no remoto**. Não há
nenhuma relação com banco de dados do jogo (`DATABASE.md`).

## 7. Sondas (somente leitura sobre a referência)

```sh
python3 tools/pe_probe.py    | python3 tools/data_probe.py  | python3 tools/cfg_probe.py
python3 tools/lua_probe.py   | python3 tools/enc_probe.py   | python3 tools/interop_probe.py
python3 tools/malform_probe.py | python3 tools/bench_check.py | python3 tools/matrix_check.py
# MU_REF_DATA=../MuServer (padrão) — a referência NUNCA é escrita; a etapa lua-enc confere o hash
# da árvore antes/depois, e cfg_probe redige 29 valores sensíveis por nome e por forma.
```

## 8. Reproduzir a auditoria (receita mínima)

```sh
git clone https://github.com/heldergaraujo2/Muserver.git && cd Muserver
git checkout arena/cf1de8ce-muserver     # a consolidação vive nesta branch (PR #1 aberto para main)
# ATENCAO: clone COMPLETO. Com `--depth 1` a etapa `ref-intacta` acusa 2 falhas (casos 7 e 8)
# porque o commit do upload nao existe no clone raso — medido em 2026-10-13. Se ja clonou raso:
#   git fetch --unshallow
cd recriado
make -s check ; make -s gate-selftest ; make -s gate     # 182 · 19/19 · portão único
GATE_FULL=1 make -s gate                                 # com as etapas opt-in
FULL=1 bash scripts/verify-backup.sh                     # backup e estado publicado
python3 tools/enc_probe.py > /tmp/enc.tsv                # a evidência da etapa `enc`
```

## 9. Limites deste ambiente (o que não dá para rodar aqui)

- sem intérprete Lua nem `wine`/`qemu-i386` ⇒ as etapas `lua` (execução) e `interop` (camada 3)
  permanecem `BLOCKED`, com causa nomeada;
- sem `clang`/`valgrind`/`gdb` ⇒ sem libFuzzer e sem memcheck;
- sem Windows/SQL Server ⇒ o procedimento de banco do original (`DATABASE.md` §3) está
  **documentado, não executado**;
- host de 2 vCPUs compartilhadas ⇒ `bench` pode reportar `BLOCKED` por drift de ambiente: é o juiz
  funcionando (D2-27), não falha do código;
- **clone raso (`--depth 1`)**: as etapas `ref-intacta` (casos 7–8, que comparam com o commit do
  upload `6eabb45`) e `gate-selftest` (caso 13, que roda o portão real) acusam falha — medido:
  `ref-intacta=8 falhas=2` no clone raso contra `8 falhas=0` no clone completo. Não é defeito do
  conteúdo: é objeto ausente. Rode `git fetch --unshallow` (ou clone completo). Melhoria pendente
  registrada em `AUDIT_HANDOFF.md` §5: degradar para `BLOCKED` quando o objeto não existir.

**Reproduzido em clone limpo (2026-10-13):** clone completo do remoto → `make -s build` exit 0;
`make -s check` **182 asserções, 0 falhas**; `make -s gate-selftest` **19/19**; `make -s gate` (ver
`TESTING.md`).

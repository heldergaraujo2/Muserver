# MuserverRecriado — v2 (reconstrução incremental)

Reconstrução do serviço de rede `mu2` como **história nova**, depois de a implementação anterior
(20 commits, último HEAD conhecido `c5706a5`) ter sido perdida com o sandbox em 2026-10-12.

**Primeira leitura, por perfil:**

- **auditor independente** → [`docs/AUDIT_HANDOFF.md`](docs/AUDIT_HANDOFF.md) (transferência, com
  inventário, evidências e limitações) e [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md);
- **quem vai compilar/rodar** → [`docs/BUILD_AND_RUN.md`](docs/BUILD_AND_RUN.md);
- **índice do projeto** → [`docs/CONTINUITY.md`](docs/CONTINUITY.md).

## O que isto é, e o que não é

- **É**: um projeto novo, com história própria, começando em R-0. O contrato do quadro é decisão
  documentada do v2 (`docs/DECISIONS.md`, numeração `D2-xx`), coberto por 28 etapas de portão.
- **Não é recuperação.** Nenhum arquivo do v1 existe aqui. Nenhum número do v1 é resultado deste
  projeto: valores antigos aparecem só como `[alvo]` histórico.
- **Não é um servidor de MU Online jogável.** Não há login, contas, personagens, mundo, combate,
  itens, guildas nem banco de dados — o inventário item a item, com estado, está em
  [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) §2.
- **Não é compatível com o cliente original — e não afirma ser.** O enquadramento e os opcodes são
  próprios do v2 (`include/mu2/proto.h` diz isso em texto), e a interoperabilidade com os binários
  originais é a **camada 3**, hoje `BLOCKED` com causa: [`docs/PROTOCOLS.md`](docs/PROTOCOLS.md) §4.
- **Não é o MU Server.** `../MuServer/` é a referência original e é **somente leitura** (615 MB,
  10 021 arquivos; os dados sensíveis dela estão mapeados em `docs/SECURITY.md`).

## Estado (medido, não relatado)

Fechadas: R-0 ambiente · R-1 inventário · R-2 baseline · R-3 codec · R-4 serviço de rede · R-5 formatos por medição · R-8 portão único · R-6 protocolo (camadas 1 e 2 comprovadas; interop `BLOCKED`) · **R-7 desempenho (baseline exploratória)** · **etapa `enc` (cifragem do Lua do cliente: estrutura medida, algoritmo `BLOCKED`)**.

| medida | valor (2026-10-13) |
|---|---|
| portão único | `make -s gate` → **23 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 28 etapas** (553 asserções contadas; 605 somando todas as etapas) — medido em 2026-10-13, auditoria P3 |
| portão de build | `make -s check` → **182 asserções, 0 falhas** |
| teste do portão | `make -s gate-selftest` → **19/19** |
| backup | `scripts/verify-backup.sh` **11/11**; `FULL=1` **15/15** (confere o remoto) |
| com as opt-in | `FULL=1 make -s gate` → **net-matrix 36/36** (100 config × 5 reps) e `persistencia` |

Detalhe, limites e o que **não** foi testado: [`docs/TESTING.md`](docs/TESTING.md) e
[`reports/`](reports/).

## Compilar, rodar, testar

```sh
cd recriado
make -s build          # out/wire.o, out/mud2, out/mu2ctl, out/netclient, out/mu2codec, out/mu2fuzz, out/mu2admin (ASan+UBSan, -Werror)
make -s gate           # PORTAO UNICO: 28 etapas, mesa de estados, 553 assercoes contadas
make -s gate-selftest  # testa o proprio portao (19 casos, inclui F12-F14 e etapa duplicada)
make -s check          # unit + make-sintaxe + net + pe + data (182 assercoes)
make -s golden         # 38 vetores versionados + F20/F21
make -s interop        # 3 camadas separadas; camada 3 sai BLOCKED com a causa
make -s fuzz           # fuzzer deterministico (FUZZ_ITERS; 150 000 iteracoes por rodada completa)
make -s seguranca      # malformados na porta, fd/RSS, SIGTERM, higiene de log
make -s admin          # console local: token 0600, papeis, loopback obrigatorio
make -s lua            # camada Lua: inventario medido (execucao BLOCKED: sem interpretador)
make -s lua-enc        # cifragem do Lua do cliente: 27 assercoes, blocked=2 (algoritmo + F23)
make -s bench          # baseline EXPLORATORIA de desempenho (nao e criterio de aceitacao)
make -s conform        # conformidade do protocolo v2, byte a byte (15 clausulas)
make -s cfg            # endpoints da configuracao original (29 segredos redigidos)
make MU_REF_DATA=/caminho/do/pacote -s data    # a referencia e externa ao v2 por decisao
make -s net-matrix     # matriz completa de backpressure (~10 min, opt-in)
make SAN=0 build       # sem sanitizadores: so para comparar custo, nunca para publicar resultado

# serviço de ensaio (porta efêmera, log em arquivo, 127.0.0.1 por padrão)
./out/mud2 --port 0 --log-file /tmp/mud2.log --profile orig &
PORT=$(awk '/listen addr=/{for(i=1;i<=NF;i++) if($i ~ /^port=/){sub(/port=/,"",$i); print $i}}' /tmp/mud2.log)
./out/mu2ctl stats --port "$PORT"      # STATS registros= usados= conns= frames= ...
kill -TERM %1                          # encerramento limpo, com resumo de contadores no log
```

Opcodes do serviço (`include/mu2/proto.h`): `PING` 0x0001, `ECHO` 0x0002, `STATS` 0x0003 — **próprios
do v2**. Motivos de fechamento no log, um por linha: `queue_full`, `client_eof`, `client_hup`,
`socket_error`, `write_error`, `bad_frame`, `idle_timeout`, `max_clients`, `shutdown`.

## Onde o projeto está publicado

| local | o que é | como conferir |
|---|---|---|
| **este monorepo**, branch `arena/cf1de8ce-muserver` | o produto (`recriado/`), a referência (`MuServer/`, somente leitura), a evidência (`workspace/`, `reports/`) e a cópia publicada (`MuserverRecriado/`, 174 arquivos) | `git ls-remote origin refs/heads/arena/cf1de8ce-muserver`; `FULL=1 bash scripts/verify-backup.sh` |
| `MuserverRecriado/` (na raiz deste monorepo) | cópia independente do artefato validado, com bundle/MANIFEST próprios | `cd ../MuserverRecriado && bash scripts/verify-backup.sh` |
| repositório separado `heldergaraujo2/MuserverRecriado` | **vazio** — o `push` responde `403` (seleção de repositórios da instalação do GitHub App) e não é contornado | `gh api repos/heldergaraujo2/MuserverRecriado` |

## Por que mora dentro do repositório da sessão (e não num clone irmão)

O v1 morreu exatamente por morar num clone não rastreado (`/home/user/MuserverRecriado`): o mecanismo
de persistência da sessão grava o diff da árvore do repositório da sessão, e o irmão ficou de fora.
Evidência em `../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md`. Portanto:

1. toda rodada termina com `git add <caminhos explícitos>` (nunca `git add -A`), commit, `git push` e
   `git ls-remote` **lido de volta** para conferir o SHA remoto;
2. uma cópia independente é regravada a cada marco em `../workspace/backups/` (bundle + manifesto com
   sha256), e `scripts/verify-backup.sh` é o que atesta — com `FULL=1` conferindo o que foi
   **publicado**, não só o que está no worktree;
3. `workspace/migracao/` reconstrói o destino `heldergaraujo2/MuserverRecriado` de forma
   reprodutível e `publicar-destino.sh` publica e confere — o que falta é **permissão**, não código.

## Layout

```
docs/       auditoria: AUDIT_HANDOFF PROJECT_STATUS ARCHITECTURE BUILD_AND_RUN DATABASE PROTOCOLS
            TESTING DEPENDENCIES_AND_LICENSES SECURITY
            continuidade: CONTINUITY CURRENT_STATE NEXT_TASK DECISIONS ROADMAP ENVIRONMENT CHANGELOG
            ADMIN_CONSOLE (desenho do console, escrito antes do codigo)
include/    mu2/mu2.h (contrato do codec)  mu2/proto.h (opcodes do v2 e motivos de fechamento)
src/        wire.c (codec)  mud2.c (servico de ensaio)  mu2ctl.c (metricas)
tools/      15 ferramentas: mu2codec/mu2fuzz/mu2admin (C) + 12 sondas/validadores (Python)
tests/      unit.c netclient.c + 16 suites .sh + golden/quadros.tsv (38 vetores)
reports/    evidencia .tsv/.md por rodada (regra de extensao em reports/README.md)
scripts/    verify-backup.sh
out/        build e saidas de teste (IGNORADO pelo git)
```

Existem e rodam (28 etapas no portão): `build`, `unit`, `db`, `dbctl`, `sincronia`, `make-sintaxe`,
`net`, `net-matrix` (opt-in), `pe`, `data`, `cfg`, `conform`, `matriz`, `matriz-artefatos`, `golden`,
`interop`, `fuzz`, `seguranca`, `admin`, `lua`, `lua-enc`, `bench`, `*-selftest`, `ref-intacta`,
`regressao-lua`, `gate`, `gate-selftest`, `persistencia` (opt-in).
`interop` (camada 3), `lua` (execução) e `lua-enc` (algoritmo e `F23`) aparecem como **`BLOCKED`**
com causa — nunca como aprovados. `bench` mede uma **baseline exploratória**: não há requisito de
desempenho do dono, então nenhum número ali é meta.

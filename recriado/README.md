# MuserverRecriado — v2 (reconstrução incremental)

Reconstrução do serviço de rede `mu2` como **história nova**, depois de a implementação anterior
(20 commits, último HEAD conhecido `c5706a5`) ter sido perdida com o sandbox em 2026-10-12.

**Primeira leitura:** [`docs/CONTINUITY.md`](docs/CONTINUITY.md) — índice do projeto, estado, testes,
backup e regras.

## O que isto é, e o que não é

- **É**: um projeto novo, com história própria, começando em R-0. O contrato do quadro é decisão
  documentada do v2 (`docs/DECISIONS.md`, numeração `D2-xx`).
- **Não é recuperação.** Nenhum arquivo do v1 existe aqui. Nenhum número do v1 é resultado deste
  projeto: valores antigos aparecem só como `[alvo]` histórico.
- **Não é compatível com o cliente original — e não afirma ser.** O enquadramento e os opcodes são
  próprios do v2. A comparação com o `ConnectServer.exe` real é trabalho da fase R-6, a ser respondida
  a partir do binário, e até haver teste real reproduzível nenhuma compatibilidade é declarada.
- **Não é o MU Server.** `../MuServer/` é a referência original e é **somente leitura**.

## Estado (medido, não relatado)

Fechadas: R-0 ambiente · R-1 inventário · R-2 baseline · R-3 codec · R-4 serviço de rede · R-5 formatos por medição · R-8 portão único · R-6 protocolo (camada 1 comprovada; interop BLOCKED) · **R-7 desempenho (baseline exploratória; capacidade absoluta BLOCKED)**.
Portão único: `make -s gate` → 18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED (339 asserções, 22 etapas).
Portão de build: `make -s check` → 182 asserções, 0 falhas. Teste do portão: `make -s gate-selftest` → 19/19.
Detalhe e números em [`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md) e [`reports/`](reports/).

## Compilar, rodar, testar

```sh
cd recriado
make -s build          # out/wire.o, out/mud2, out/mu2ctl, out/netclient (ASAN+UBSAN+-Werror)
make -s gate           # PORTAO UNICO: 22 etapas, mesa de estados, 339 assercoes
make -s bench          # baseline EXPLORATORIA de desempenho (nao e criterio de aceitacao)
make -s conform        # conformidade do protocolo v2, byte a byte (15 clausulas)
make -s cfg            # endpoints da configuracao original (segredos redigidos)
make -s matriz         # valida a matriz de evidencias (linha sem teste reproduzivel = falha)
make -s gate-selftest  # testa o proprio portao (19 casos, inclui F12-F14 e etapa duplicada)
make -s check          # unit + make-sintaxe + net + pe + data  (portao de build, sem recursao)
make -s pe             # PE da referencia: 22 .exe, arquitetura, secoes, imports (MU_REF_DATA)
make -s data           # .att/.bmd/.ozj/.smd, dados, Lua, backups: invariantes medidos
make -s pe-selftest    # so a recusa de entrada invalida, sem tocar na referencia de 615 MB
make MU_REF_DATA=/caminho/do/pacote -s data   # a referencia e externa ao v2 por decisao
make -s net-matrix     # matriz completa de backpressure (100 conf x 5 reps por perfil, ~10 min)
make SAN=0 build       # sem sanitizadores: só para comparar custo, nunca para publicar resultado

# serviço de ensaio (porta efêmera, log em arquivo)
./out/mud2 --port 0 --log-file /tmp/mud2.log --profile orig &
PORT=$(awk '/listen addr=/{for(i=1;i<=NF;i++) if($i ~ /^port=/){sub(/port=/,"",$i); print $i}}' /tmp/mud2.log)
./out/mu2ctl stats --port "$PORT"     # STATS registros= usados= conns= frames= ...
kill -TERM %1                          # encerramento limpo, com resumo de contadores no log
```

Opcodes do serviço (`include/mu2/proto.h`): `PING` 0x0001, `ECHO` 0x0002, `STATS` 0x0003 — próprios do
v2. Motivos de fechamento no log, um por linha: `queue_full`, `client_eof`, `client_hup`,
`socket_error`, `write_error`, `bad_frame`, `idle_timeout`, `max_clients`, `shutdown`.

## Por que mora dentro de `Muserver/` (e não num clone irmão)

O v1 morreu exatamente por morar num clone não rastreado (`/home/user/MuserverRecriado`): o mecanismo
de persistência da sessão grava o diff da árvore do repositório da sessão, e o irmão ficou de fora.
Evidência em `../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md`. Portanto:

1. toda rodada termina com `git add <caminhos explícitos>` (nunca `git add -A`), commit, `git push` e
   `git ls-remote` **lido de volta** para conferir o SHA remoto;
2. uma cópia independente é regravada a cada rodada em `../workspace/backups/` (bundle + manifesto com
   sha256), e `scripts/verify-backup.sh` é o que atesta — com `FULL=1` conferindo o que foi **publicado**,
   não só o que está no worktree;
3. `recriado/` **já tem** o repositório próprio pronto: `workspace/migracao/` reconstrói
   `heldergaraujo2/MuserverRecriado` de forma reprodutível (histórico de 39 commits via
   `git subtree split`, evidência `workspace/`, cópia restaurável) e `publicar-destino.sh` publica e
   confere. O que falta é **permissão**: o push responde 403 porque a instalação do GitHub App não
   inclui o destino — ação do proprietário, sem contorno daqui.

## Layout

```
docs/       CONTINUITY (índice) CURRENT_STATE NEXT_TASK DECISIONS ROADMAP ENVIRONMENT CHANGELOG
include/    mu2/mu2.h  mu2/proto.h
src/        wire.c (codec)  mud2.c (serviço)  mu2ctl.c (métricas)
tests/      unit.c  netclient.c  net.sh  make_parse.sh
reports/    r3-*.tsv  r4-*.tsv  net-<perfil>.tsv  (regra de extensão em reports/README.md)
scripts/    verify-backup.sh
out/        build (ignorado pelo git)
```

Existem e rodam: `unit`, `make-sintaxe`, `net`, `net-matrix`, `pe`, `data`, `cfg`, `conform`,
`matriz`, `bench`, `*-selftest`, `gate` (portão), `gate-selftest` (teste do portão), `ref-intacta`.
Ainda **não** existem — no portão aparecem como `NOT_IMPLEMENTED`, nunca como aprovados: `golden`,
`interop`, `fuzz`. `interop` exige binário original em execução (**BLOCKED**).
`bench` mede uma **baseline exploratória**: não há requisito de desempenho do dono, então nenhum
número ali é meta. Critérios de validade declarados antes, juiz separado e limites rotulados —
detalhe em [`reports/r7-relatorio.md`](reports/r7-relatorio.md).

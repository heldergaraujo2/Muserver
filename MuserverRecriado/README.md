# MuserverRecriado — v2 (reconstrução incremental)

Reconstrução do serviço de rede `mu2` como **história nova**, depois de a implementação anterior
(20 commits, último HEAD conhecido `c5706a5`) ter sido perdida com o sandbox em 2026-10-12.

**Primeira leitura:** [`docs/CONTINUITY.md`](docs/CONTINUITY.md) — índice do projeto, estado, testes,
backup e regras.

## Onde este projeto está publicado (2026-10-13)

Esta pasta — `MuserverRecriado/` — **é a publicação** do projeto recriado, dentro do monorepo
[`heldergaraujo2/Muserver`](https://github.com/heldergaraujo2/Muserver), na branch de trabalho
`arena/cf1de8ce-muserver`. Não há nível extra: `MuserverRecriado/` na raiz do monorepo *é* a raiz do
projeto (`Makefile`, `src/`, `tests/`, `docs/`, `reports/`, `workspace/`).

Ela é a cópia do **artefato validado** da migração, reproduzida pelo caminho determinístico do
monorepo (`bash ../workspace/migracao/preparar-destino.sh <dir> --gate`, que fecha com
`ok=6/falhas=0`) e conferida **arquivo por arquivo** contra ele: 174 arquivos, modo e blob idênticos
(ver “Validação desta cópia”, abaixo).

O repositório separado `heldergaraujo2/MuserverRecriado` **continua bloqueado por `403`** (permissão
da instalação do GitHub App) e segue vazio — nada foi publicado nele, e esta pasta não afirma o
contrário. A publicação real do projeto recriado é a que está aqui.

## O que isto é, e o que não é

- **É**: um projeto novo, com história própria, começando em R-0. O contrato do quadro é decisão
  documentada do v2 (`docs/DECISIONS.md`, numeração `D2-xx`).
- **Não é recuperação.** Nenhum arquivo do v1 existe aqui. Nenhum número do v1 é resultado deste
  projeto: valores antigos aparecem só como `[alvo]` histórico.
- **Não é compatível com o cliente original — e não afirma ser.** O enquadramento e os opcodes são
  próprios do v2. A comparação com o `ConnectServer.exe` real é trabalho da fase R-6, a ser respondida
  a partir do binário, e até haver teste real reproduzível nenhuma compatibilidade é declarada.
- **Não é o MU Server.** `../MuServer/` (no monorepo) é a referência original e é **somente leitura**:
  os testes que dependem dela a *leem* e provam por hash de árvore que não a alteraram
  (`tests/ref_check.sh`). Nenhum arquivo dela é copiado para dentro desta pasta.

## Estado (medido, não relatado)

Fechadas: R-0 ambiente · R-1 inventário · R-2 baseline · R-3 codec · R-4 serviço de rede · R-5 formatos por medição · R-8 portão único · R-6 protocolo (camada 1 comprovada; interop BLOCKED) · **R-7 desempenho (baseline exploratória; capacidade absoluta BLOCKED)**.

Portão único (`make -s gate`, medido nesta pasta, com a referência irmã `../MuServer` presente):
**18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED — 339 asserções, 22 etapas, exit 0**.
Os 2 BLOCKED são `interop` (camada 3, exige o binário original em execução) e `lua` (sem intérprete
no host); os 2 SKIPPED são `net-matrix` e `persistencia`, opt-in por `GATE_FULL=1`.

Sem a referência ao lado (perfil do artefato isolado, medido antes de publicar aqui), o mesmo portão
mede **14 PASS, 0 FAIL, 6 BLOCKED, 2 SKIPPED, 281 asserções** — as 4 etapas a mais em BLOCKED são
`pe`, `data`, `cfg` e `ref-intacta`.

Portão de build: `make -s check` → **182 asserções, 0 falhas** (`unit` 106, `make-sintaxe` 7, `net` 34,
`pe` 14, `data` 21). Teste do portão: `make -s gate-selftest` → **19/19**. Fuzzer: `make -s fuzz` →
**12/12**, 150 000 iterações, motor determinístico próprio.

Detalhe e números em [`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md), [`docs/CONTINUITY.md`](docs/CONTINUITY.md)
e [`reports/`](reports/).

## Compilar, rodar, testar

```sh
make -s build          # out/wire.o, out/mud2, out/mu2ctl, out/netclient (ASAN+UBSAN+-Werror)
make -s gate           # PORTAO UNICO: 22 etapas, mesa de estados, 339 assercoes (aqui, com a referencia irma)
make -s bench          # baseline EXPLORATORIA de desempenho (nao e criterio de aceitacao)
make -s conform        # conformidade do protocolo v2, byte a byte (15 clausulas)
make -s cfg            # endpoints da configuracao original (segredos redigidos)
make -s matriz         # valida a matriz de evidencias (linha sem teste reproduzivel = falha)
make -s gate-selftest  # testa o proprio portao (19 casos, inclui F12-F14 e etapa duplicada)
make -s check          # unit + make-sintaxe + net + pe + data  (portao de build, sem recursao)
make -s pe             # PE da referencia: 22 .exe, arquitetura, secoes, imports (MU_REF_DATA)
make -s data           # .att/.bmd/.ozj/.smd, dados, Lua, backups: invariantes medidos
make -s pe-selftest    # so a recusa de entrada invalida, sem tocar na referencia de 615 MB
make MU_REF_DATA=/caminho/do/pacote -s data   # a referencia e externa ao projeto por decisao
make -s net-matrix     # matriz completa de backpressure (100 conf x 5 reps por perfil, ~10 min)
make SAN=0 build       # sem sanitizadores: só para comparar custo, nunca para publicar resultado

# serviço de ensaio (porta efêmera, log em arquivo)
./out/mud2 --port 0 --log-file /tmp/mud2.log --profile orig &
PORT=$(awk '/listen addr=/{for(i=1;i<=NF;i++) if($i ~ /^port=/){sub(/port=/,"",$i); print $i}}' /tmp/mud2.log)
./out/mu2ctl stats --port "$PORT"     # STATS registros= usados= conns= frames= ...
kill -TERM %1                          # encerramento limpo, com resumo de contadores no log
```

Dependências: basta `make` + `cc` com sanitizadores (ASAN/UBSAN) e `python3` para as sondas. Não há
biblioteca externa, não há download de rede nos testes, e a suíte não escreve fora de `out/` e de
diretórios temporários.

A referência original fica **fora** desta pasta e é opcional: `MU_REF_DATA` aponta para ela
(padrão `../MuServer`). Ausente ⇒ `pe`, `data`, `cfg` e `ref-intacta` saem `BLOCKED` (bloqueado não é
aprovado); presente ⇒ rodam como medido acima.

Opcodes do serviço (`include/mu2/proto.h`): `PING` 0x0001, `ECHO` 0x0002, `STATS` 0x0003 — próprios do
v2. Motivos de fechamento no log, um por linha: `queue_full`, `client_eof`, `client_hup`,
`socket_error`, `write_error`, `bad_frame`, `idle_timeout`, `max_clients`, `shutdown`.

## Validação desta cópia (2026-10-13)

| verificação | resultado medido |
|---|---|
| arquivos da pasta vs artefato validado | **174 = 174**, lista idêntica |
| conteúdo (modo + blob git de cada arquivo) | **idêntico nos 174** — nada convertido na cópia (`.gitattributes` próprio: `* -text`) |
| artefato de origem desta cópia | HEAD `51b2b157`, árvore `99c9b8ff`, **42 commits**, 174 arquivos, bundle do snapshot 662 628 B sha256 `76d71bd8…`, ponta `f42769f1` |
| reprodução do artefato | `preparar-destino.sh --gate` no monorepo: `ok=6/falhas=0` (árvore, contagem e sha256 conferidos, não presumidos) |
| `make -s check` | exit 0 — unit 106, make-sintaxe 7, net 34, pe 14, data 21, 0 falhas |
| `make -s gate` | exit 0 — 18 PASS / 0 FAIL / 2 BLOCKED / 2 SKIPPED, 339 asserções |
| `make -s gate-selftest` | exit 0 — 19/19 |
| `make -s fuzz` | exit 0 — 12/12 |
| nada escrito fora da pasta pelos testes | confirmado por `git status` do monorepo: só entradas desta pasta (o `out/` é ignorado) |
| referência `../MuServer` | intacta: `ref-intacta` PASS 8/8, árvore `fade0461…`, 10 021 arquivos |
| segredos/credenciais | nenhuma credencial; `workspace/reports/A1-secrets.md` é o relatório **redigido** da auditoria |

O backup interno (`workspace/backups/mu2-v2.bundle` + `MANIFEST.md`) é a cópia independente do
**artefato** como validado — ele antecede a nota de localização escrita aqui, e a divergência de
`README.md`/`docs/` é declarada (`DIV_OK` do verificador). O backup que acompanha o monorepo (e o que
`scripts/verify-backup.sh` confere com `FULL=1`, incluindo o que está publicado no remoto) é o de
`../workspace/backups/`.

## O que não foi incluído nesta pasta, e por quê

| ausente | motivo |
|---|---|
| `MuServer/` (~615 MB, 10 021 arquivos, binários do fornecedor) | é a referência original; não é código deste projeto e não é redistribuído aqui. Fica no monorepo, ao lado |
| `workspace/migracao/` do monorepo | são ferramentas da *origem* (split do histórico, transformador, bundle de transporte): dentro do projeto seriam circulares |
| credenciais/tokens | nenhum arquivo versionado aqui contém segredo; relatórios de auditoria são redigidos |
| reescrita dos relatórios históricos | `reports/` é evidência publicada do layout de origem e **não** foi reescrita (mapeamento em `reports/README.md`) |

## Como diferenciar este projeto do código original em `../MuServer/`

| | `MuserverRecriado/` (esta pasta) | `../MuServer/` (referência) |
|---|---|---|
| o que é | reconstrução **nova** do serviço de rede `mu2`, em C, com testes e evidência | pacote original do fornecedor (MU Online Season 6.20) |
| tamanho/formato | 174 arquivos rastreados: `src/*.c`, `include/mu2/*.h`, `tests/`, `tools/`, `docs/`, `reports/`, `workspace/` | 10 021 arquivos, ~615 MB, com `.exe`/`.dll`/dados do jogo |
| como é construído | `make -s build` (ASAN+UBSAN, `-Werror`), sem binário pré-compilado versionado | binários prontos do fornecedor; nada é compilado |
| protocolo | opcodes próprios do v2 (`PING`/`ECHO`/`STATS`), enquadramento e limites documentados em `docs/` | protocolo original do cliente; só é **medido** por sondas, nunca executado para “fazer passar” |
| relação entre os dois | leitura apenas, e só onde o teste exige (`pe`, `data`, `cfg`, `ref-intacta`, `interop` camada 3) | fonte de verdade do que o original faz; **nunca** modificada |
| marcadores rápidos | este README, `docs/CONTINUITY.md`, `Makefile` com alvos `gate`/`check`, `reports/*.tsv` | `GameServer/`, `ConnectServer/`, `DataServer/`, `LOG/`, `.dat` do jogo |

## Por que o projeto vive dentro do monorepo (e não num clone solto)

O v1 morreu exatamente por morar num clone não rastreado (`/home/user/MuserverRecriado`): o mecanismo
de persistência da sessão grava o diff da árvore do repositório **da sessão** (`Muserver`), e o irmão
ficou de fora. Evidência em `workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md`. A resposta foi
primeiro tentar um repositório próprio: o histórico do projeto foi separado com
`git subtree split --prefix=recriado` (**39 commits**, mensagens originais) e o pacote de migração
ficou reprodutível. Como a escrita no repositório separado responde `403`, a publicação passou a ser
**esta pasta**, dentro do repositório que já é autorizado — o projeto continua versionado, agora sem
depender de permissão nova.

1. toda rodada termina com `git add <caminhos explícitos>` (nunca `git add -A`), commit, `git push` e
   `git ls-remote` **lido de volta** para conferir o SHA remoto;
2. uma cópia independente é regravada a cada rodada em `workspace/backups/` (bundle + manifesto com
   sha256), e `scripts/verify-backup.sh` é o que atesta — com `FULL=1` conferindo o que foi **publicado**,
   não só o que está no worktree;
3. **`workspace/` mantém o caminho relativo do monorepo de origem** porque o bundle de backup mora ali
   e é ele que carrega a árvore restauravel; mover a evidência quebraria o manifesto e a restauração.

### Estado da publicação

- **2026-10-12 (histórico):** `heldergaraujo2/MuserverRecriado` vazio; `git push` responde
  `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`, e a API responde
  `Resource not accessible by integration` no repositório de destino (funciona em `Muserver`). Isso é
  seleção de repositórios da **instalação do GitHub App**, não permissão do usuário (a ACL do usuário
  diz `push=true`). A tentativa foi repetida com o artefato final validado e respondeu o mesmo `403`.
- **2026-10-13 (vigente):** a publicação mudou de estratégia e passou a ser **esta pasta**, dentro do
  repositório autorizado. O repositório separado continua vazio e continua exigindo a ação do
  proprietário (incluir `MuserverRecriado` na instalação com *Contents: Read and write*) para que o
  pacote de migração — que segue preservado em `../workspace/migracao/` — possa ser publicado lá.

## Layout

```
docs/       CONTINUITY (índice) CURRENT_STATE NEXT_TASK DECISIONS ROADMAP ENVIRONMENT CHANGELOG
            ADMIN_CONSOLE (desenho do console)  MIGRACAO-MUSERVERRECRIADO-2026-10-12
include/    mu2/mu2.h  mu2/proto.h
src/        wire.c (codec)  mud2.c (serviço)  mu2ctl.c (métricas)
tools/      sondas (pe/data/cfg/att/mb/lua/interop/malform), CLI do codec, fuzzer, console
tests/      unit.c  netclient.c  *.sh (unit, net, pe, data, cfg, conform, golden, fuzz,
            seguranca, admin, lua, interop, bench, ref_check, gate_state)  golden/quadros.tsv
reports/    evidência publicada: *.tsv (dados) e *.md (análise) — regra em reports/README.md
scripts/    verify-backup.sh
workspace/  evidência do monorepo de origem: backups/ (bundle + MANIFEST), changes/ (Lua),
            reports/ (auditorias e recuperação), tools/ e tests/ da fase de auditoria
out/        build e saídas de execução (ignorado pelo git)
```

Existem e rodam: `unit`, `make-sintaxe`, `net`, `net-matrix`, `pe`, `data`, `cfg`, `conform`,
`matriz`, `bench`, `golden`, `fuzz`, `seguranca`, `admin`, `lua`, `*-selftest`, `gate` (portão) e
`gate-selftest` (teste do portão) — 22 etapas, mesa de estados em `out/gate.tsv`. Nesta pasta, quem
sai **BLOCKED** é `interop` camada 3 (sem binário original em execução) e `lua` (sem intérprete no
host); sem a referência em `../MuServer`, `pe`, `data`, `cfg` e `ref-intacta` também saem BLOCKED —
foi o perfil medido no artefato isolado (14 PASS / 6 BLOCKED / 281 asserções).
`bench` mede uma **baseline exploratória**: não há requisito de desempenho do dono, então nenhum
número ali é meta. Critérios de validade declarados antes, juiz separado e limites rotulados —
detalhe em [`reports/r7-relatorio.md`](reports/r7-relatorio.md).

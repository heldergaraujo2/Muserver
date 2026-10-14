# CONTINUITY — MU Server v2 (leia isto primeiro)

Índice central. O detalhe mora nos arquivos apontados abaixo; aqui ficam só os ponteiros, o último
estado conferido e as regras que não podem ser quebradas. Se este arquivo divergir do código, dos
testes ou do git, **a evidência vence** — e a divergência deve ser registrada, não escondida.

## 1. Identidade e objetivo

Reconstrução do MU Server como **história nova (v2)**, em C11, com evidência reproduzível por fase.
O código C anterior (v1, último commit conhecido `c5706a5`) **não foi recuperado** e não pode ser
copiado nem citado como resultado reproduzido — seus números históricos aparecem só como `[alvo]`.

## 2. `MuServer/` é SOMENTE LEITURA

`../../MuServer/` é a referência original (10 021 arquivos). Nenhuma linha dela é modificada,
sobrescrita ou usada como destino de teste destrutivo. Conferência: `git diff --quiet HEAD -- MuServer`
e `git rev-parse HEAD:MuServer` (esperado `fade04615fabd17778a0e2fd7adf032c8386c924`).

## 3. Onde está o quê

| assunto | arquivo |
|---|---|
| estado detalhado da última rodada | [CURRENT_STATE.md](CURRENT_STATE.md) |
| próxima tarefa executável | [NEXT_TASK.md](NEXT_TASK.md) |
| decisões técnicas D2-01…D2-39 | [DECISIONS.md](DECISIONS.md) |
| histórico por rodada | [CHANGELOG.md](CHANGELOG.md) |
| host, toolchain e limites do sandbox | [ENVIRONMENT.md](ENVIRONMENT.md) |
| fases R-0…R-9 e metas por categoria | [ROADMAP.md](ROADMAP.md) |
| plano original de reconstrução | [../../workspace/reports/PLANO-RECONSTRUCAO-MU2-2026-10-12.md](../../workspace/reports/PLANO-RECONSTRUCAO-MU2-2026-10-12.md) |
| auditoria completa (2026-10-12) | [../../workspace/reports/AUDITORIA-CONTINUIDADE-2026-10-12.md](../../workspace/reports/AUDITORIA-CONTINUIDADE-2026-10-12.md) |
| incidente e buscas do v1 perdido | [../../workspace/reports/WORKTREE-PERDIDO-2026-10-12.md](../../workspace/reports/WORKTREE-PERDIDO-2026-10-12.md) · [../../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md](../../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md) |
| pedido de recuperação à plataforma | [../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md](../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md) |
| identidade do backup e restauração | [../../workspace/backups/MANIFEST.md](../../workspace/backups/MANIFEST.md) |
| evidências medidas por fase | [../reports/](../reports/) — `r3-*.tsv`, `r4-*.tsv`, `r5-*.tsv`, `r6-*.tsv`, `r8-*.tsv`, `net-<perfil>.tsv` |
| sondas de formato (R-5) | [../tools/](../tools/) — `pe_probe.py`, `att_probe.py`, `mb_probe.py`, `data_probe.py` |
| portão único (R-8) | [../tests/run_all.sh](../tests/run_all.sh) · [../tests/gate_state.sh](../tests/gate_state.sh) · [../tests/ref_check.sh](../tests/ref_check.sh) — alvo **`make -s gate-full`** para as etapas opt-in (**não** `FULL=1`, que é do backup) |
| persistência própria do v2 (R-11) | [db.h](../include/mu2/db.h) · [db.c](../src/db.c) · [db_test.c](../tests/db_test.c) · [mu2dbctl.c](../tools/mu2dbctl.c) · [dbctl.sh](../tests/dbctl.sh) · [DATABASE.md](DATABASE.md) · [D2-40](DECISIONS.md) · [../reports/r11-persistencia.md](../reports/r11-persistencia.md) |
| sondas e suítes da R-6 | [../tools/cfg_probe.py](../tools/cfg_probe.py) · [../tools/wire_probe.py](../tools/wire_probe.py) · [../tools/matrix_check.py](../tools/matrix_check.py) · [../tests/conform.sh](../tests/conform.sh) · [../tests/cfg.sh](../tests/cfg.sh) |
| matriz de evidências (R-6) | [../reports/r6-matriz.tsv](../reports/r6-matriz.tsv) · [../reports/r6-relatorio.md](../reports/r6-relatorio.md) |
| desempenho e limites (R-7) | [../tests/bench.sh](../tests/bench.sh) · [../tools/bench_check.py](../tools/bench_check.py) · [../tools/rtt_probe.py](../tools/rtt_probe.py) · [../reports/r7-baseline.tsv](../reports/r7-baseline.tsv) · [../reports/r7-relatorio.md](../reports/r7-relatorio.md) |
| contrato e resultado do portão | [../reports/r8-relatorio.md](../reports/r8-relatorio.md) · [../reports/r8-gate.tsv](../reports/r8-gate.tsv) · [../reports/r8-gate-state.tsv](../reports/r8-gate-state.tsv) |
| relatório da R-5 (observação × hipótese × conclusão) | [../reports/r5-relatorio.md](../reports/r5-relatorio.md) |
| porta de entrada humana (build/run) | [../README.md](../README.md) |
| projeto recriado **publicado** (2026-10-13) | [`../../MuserverRecriado/`](../../MuserverRecriado/) — a árvore `recriado/` publicada na raiz do monorepo, com o histórico do split; ver §6 |

## 4. Fases

Fechadas: R-0 (ambiente), R-1 (inventário), R-2 (baseline/persistência), R-3 (codec), R-4 (serviço),
R-5 (inspeção do pacote), R-8 (portão único), R-6 **no que é verificável** (camadas 1 e 2; camada 3
BLOCKED), R-7 (desempenho, linha de base exploratória).

Rodada das lacunas (2026-10-12): `golden`, `fuzz`, `seguranca`, `admin`, `lua`, `interop` — as seis
etapas que estavam ausentes — mais a auditoria de classificação de formatos
(`reports/rc-formatos-auditoria.md`) e a **auditoria de rastreabilidade do roadmap inteiro**
(`reports/auditoria-rastreabilidade.md`).

R-9 (documentação e publicação) é contínua por definição. Próxima tarefa: `enc` (cifragem do script
Lua do cliente) — ver `docs/NEXT_TASK.md`.

## 5. Testes — o que roda, o que não existe

| suíte | comando | último resultado |
|---|---|---|
| unit | `make -s unit` | 106 asserções, 0 falhas |
| make-sintaxe | `make -s make-sintaxe` | 10 casos, 0 falhas |
| net (portão) | `make -s net` | 34 verificações, 0 falhas |
| net-matrix | `make -s net-matrix` | 36 verificações, 0 falhas (opt-in `GATE_FULL=1`) |
| pe / data | `make -s pe` · `make -s data` | 14 e 21 casos, 0 falhas |
| pe-selftest / data-selftest / cfg-selftest | `make -s *-selftest` | 4/4, 4/4, 5/5 — rodam **sem a referência** |
| conform | `make -s conform` | 15/15 cláusulas C-01…C-15, byte a byte |
| cfg | `make -s cfg` | 15 casos (portas e segredos redigidos) |
| **golden** | `make -s golden` | **42/42** — 38 vetores versionados + F20 + F21 |
| **fuzz** | `make -s fuzz` | **12/12** — 150 000 iterações, 0 violações, F22 |
| **seguranca** | `make -s seguranca` | **13/13** — 15 malformações na porta, fd e RSS estáveis |
| **admin** | `make -s admin` | **25/25** — console local, fail closed, papéis, 501; o caso do git olha só os arquivos de contrato do serviço (reparo de acoplamento, auditoria P3) |
| **interop** | `make -s interop` | **12/12, `blocked=1`** — camada 3 BLOCKED (sem wine/autorização) |
| **lua** | `make -s lua` | **13/13, `blocked=1`** — inventário medido; sem interpretador no host |
| **lua-enc** | `bash tests/lua-enc.sh` | **27/27, `blocked=2`** — cifragem do Lua do cliente: estrutura medida (janela de 3 B, sem padding, determinística); algoritmo e `F23` `BLOCKED` |
| ref-intacta | `bash tests/ref_check.sh` | **8/8** — inclui a divergência dos 6 `.lua` e a reversão |
| bench | `make -s bench` | 15/15 — linha de base exploratória (R-7) |
| persistência | `bash scripts/verify-backup.sh` | **11/11** (opt-in `GATE_FULL=1`; o portão padrão marca `SKIPPED`); snapshot regravado na rodada P4 (`mu2-snapshot` @ `e2674fa4`, 108 arquivos) |
| portão de build | `make -s check` | unit + make-sintaxe + net + pe + data = **182 asserções**, exit 0 |
| **portão único** | `make -s gate` | **23 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 28 etapas, 553 asserções contadas (605 somadas), exit 0** — medido em 2026-10-13 (auditoria P3) |
| etapas opt-in | `make -s gate-full` | **medido na R-2; não re-executado na auditoria P3** (custa ~12 min e exige árvore limpa). liga `net-matrix` e `persistencia` (a variável é `GATE_FULL`; ver §9): **medido PASS=22 / FAIL=0 / BLOCKED=4 / 502 asserções / 26 etapas, exit 0** — `persistencia` deixa de ser SKIPPED e as três etapas de artefato passam juntas |
| ritual de backup | `bash scripts/verify-backup.sh` · `FULL=1 …` | **11/11** · **15/15** (bundle byte a byte igual ao remoto; `HEAD local esta no remoto`) |
| persistência própria do v2 | `make -s db` · `make -s dbctl` | **144/0** · **48/0** (morte real no meio da transação; versão de esquema sem migração e verificação com `LOCK_SH` — D2-41) |
| **sincronia** (auditoria P3) | `make -s sincronia` | **15/15** — durabilidade medida por sequência de syscalls (`tests/io_trace.c`, `LD_PRELOAD`); reintroduzindo o defeito, 2 casos reprovam |
| **regressao-lua** (fase A/A3) | `make -s regressao-lua` | **53/53, `blocked=0`** — regressão estática dos 6 `.lua`; execução de Lua continua não observada (limite declarado) |
| teste do portão | `make -s gate-selftest` | **21/21**, exit 0 (F12–F14, duplicação de etapa, `BLOCKED` demonstrado, clone raso classificado) |

Não existe, e por quê: `interop` camada 3 (BLOCKED — exige `wine`/`qemu-i386` + autorização; a suíte
não tem caminho de execução de binário original); execução de Lua (sem interpretador no host);
execução da suíte `golden` conter qualquer valor gerado pelo próprio programa — os 38 vetores foram
derivados à mão do contrato, com a derivação escrita na coluna `origem`.

### 5.1 Pendências medidas da auditoria P3 (cada uma com critério de aceitação)

| # | pendência | estado (2026-10-13, rodada P4) | evidência |
|---|---|---|---|
| 1 | **Migração de schema não existe** (`REG_MIGRACAO` nunca gravado) | **fechada por decisão (D2-41), não por implementação**: a promessa saiu do `db.h`; versão antiga é recusada nomeada; `gravar_cabecalho` grava `db->schema_version` | `reports/r11c-schema-e-lock-2026-10-13.md` §1 — migração de verdade exigiria caminho v1→v2 medido: não existe e não é declarada |
| 2 | **`mu2db_verify` sem lock** | **fechada**: `LOCK_SH\|LOCK_NB`, recusa nomeada com escritor ativo, liberação em todo caminho de saída | `reports/r11c-…md` §2–4 (mutações A/B/C medidas); custo declarado: verificação e escrita se excluem (`dbctl` casos 33–48) |
| 3 | **Queda de energia não é reproduzível aqui** | declarado no §1 do relatório P3 | não é pendência de código: é limite de ambiente, e o texto tem de continuar dizendo "o `fsync` foi chamado antes de a API voltar", nunca "o dado sobreviveu a queda" | manter a redação; não promover a afirmação |
| 4 | **Paridade de publicação (`MuserverRecriado/`)** | `diff -rq recriado/reports MuserverRecriado/reports` divergente — **exceto** `reports/r6-config.tsv`, reparado nesta rodada por ser artefato sensível (achado P07-x) | rodada de publicação com o checklist (`NEXT_TASK.md`), arquivo por arquivo, e `verify-backup.sh` verde | pedir autorização; não copiar à mão |

## 6. Último commit e publicação

- **Rodada vigente (2026-10-13, P07-x + higiene da porta de auditoria).** HEAD local `583e196`
  (dois commits: `6d5e225` correção do vazamento do `ClientSerial` + `583e196` porta de auditoria).
  Entrou: fix de `tools/cfg_probe.py` com regeneração do `reports/r6-config.tsv` (663 linhas, diff de
  4 linhas) e espelho na árvore publicada; caso `t07b` no `cfg` (lista independente — o furo que
  deixou o valor passar); varredura anti-vazamento na porta (`por_valor=0`, `por_forma=16` triadas);
  saída gerada movida para `workspace/out/` (caso 9 do verificador); `preparar-venv.sh`.
  Portão vigente medido: **23 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 28 etapas, 616
  asserções, exit 0**; `cfg` 16/16; `cfg-selftest` 5/5; `bash workspace/tests/run_all.sh` exit 0
  (6 etapas PASSOU). Relatório: `reports/r11d-clientserial-em-claro-2026-10-13.md`.
  **P07 segue ABERTO**: a correção acabou com a exposição contínua, mas o valor está no histórico do
  git e a contenção/rotação na origem é ação do proprietário.
  Cópia independente regravada nesta rodada (snapshot orphan + bundle + `MANIFEST.md`); bytes e
  `sha256` no próprio MANIFEST, fora da árvore do snapshot.

- **Rodada anterior (2026-10-13, P1 + A3 + P3 + P4).** HEAD `7ffc35a` em `arena/cf1de8ce-muserver`
  (blobs do remoto conferidos um a um por `gh api`). Entrou nesta ordem:
  P1 (`5093ffe`, verificação anti-vazamento executável + avaliação de risco da exposição);
  **A3** (`04bbaf6`, regressão estática dos 6 `.lua` como etapa obrigatória do portão — 53/0);
  **P3/R-11b** (`9111939`, durabilidade da operação implícita + regressão por sequência de syscalls);
  **P4/R-11c** (`d31108e` código+testes, `0a99488` documentos, `7ffc35a` snapshot do bundle regravado
  — D2-41: `schema_version` sem migração automática e `mu2db_verify` com `LOCK_SH|LOCK_NB`).
  Portão vigente (P4, commit `7ffc35a`): **23 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED,
  28 etapas, 615 asserções contadas, exit 0**; e **`make -s gate-full` 25 PASS, 0 FAIL, 3 BLOCKED,
  0 SKIPPED, 651 asserções, exit 0** — `net-matrix` 36/36 e `persistencia` `ok=11` na mesma passada. Relatórios: `reports/r11b-veredito-auditoria-p3-2026-10-13.md`
  (defeito de durabilidade, corrigido) e `reports/r11c-schema-e-lock-2026-10-13.md` (P4: esquema sem
  migração automática + verificação com `LOCK_SH`, com o custo medido).
  **`MuserverRecriado/` não foi tocada** — a paridade com `recriado/` já estava divergente antes
  desta rodada (faltavam `enc-*`, e `reports/` divergia) e republicar é rodada própria, com
  autorização; o repositório separado segue `403`.
  Os itens abaixo são de rodadas anteriores e ficam como registro.

- **Rodada vigente (2026-10-13): etapa `enc` — cifragem dos scripts Lua do cliente.** O algoritmo
  **não** foi identificado e isso está declarado como `BLOCKED` (2 motivos: função da janela
  desconhecida; `F23` sem decodificador). O que ficou medido e versionado: 4 dos 13 pares são
  byte-idênticos (não cifrados), cabeçalho fixo de 8 B `28aa2191a6dd35f7`, sem padding
  (`len(cif) − 8 == len(claro) + nº de LF`), determinismo, e a estrutura `(A[j], C[j-1..j-3]) → C[j]`
  com 0 discordâncias em 2 510 repetições (0/890 entre arquivos; 2 bytes ⇒ 952/4 403). Artefatos:
  `tools/enc_probe.py`, `tests/lua-enc.sh` (27 asserções), etapa `lua-enc` no portão (22 → 23
  etapas), `reports/enc-probe.tsv` e `reports/enc-cifragem-lua.md` (com as famílias refutadas e o
  caminho de desbloqueio). Portão: **18 PASS, 0 FAIL, 3 BLOCKED, 2 SKIPPED, 23 etapas, exit 0**
  (69 816 ms), nenhum FAIL novo.
- **A pasta publicada `MuserverRecriado/` não foi tocada nesta rodada** — ela é o snapshot da rodada
  anterior, o validador dela segue verde (`ok=11 falhas=0 blocked=0`) e ele só admite arquivos novos
  que casem com padrões declarados; carregar os arquivos do `enc` para lá é uma **rodada de
  publicação nova** (checklist em `NEXT_TASK.md`), não um efeito colateral desta.
- Rodada vigente: `arena/cf1de8ce-muserver`. A rodada corrigiu defasagens numéricas da origem
  (`check` 180→182 asserções, `gate` 336→339, `seguranca` 12→13, `admin` 22→24) e reconstruiu o
  destino do zero com `workspace/migracao/adaptar-destino.py` — cada substituição com asserção
  própria (falha nomeando o texto que não casou) — no lugar do patch, que ficava pinado na base
  do split. A validação do destino achou e corrigiu um quinto defeito: a linha de base do teste de
  descritores era leitura solta e pegava a corrida do close assíncrono (medido: 1 de 10 execuções
  com `fd_antes=9` e piso real 8); passou a ser o piso observado numa janela curta.
- **Publicação dentro do monorepo (2026-10-13): o projeto recriado vive em `MuserverRecriado/`, na
  raiz deste repositório** (commit `a6ddf81`), porque a escrita no repositório separado continua
  bloqueada por `403`. A pasta é o artefato validado conferido **arquivo por arquivo** (174/174, modo
  + blob idênticos), sem `.git` embutido, e roda verde aqui dentro: `check` exit 0, `gate` **18 PASS,
  0 FAIL, 2 BLOCKED, 2 SKIPPED, 339 asserções**, `gate-selftest` 19/19, `fuzz` 12/12, `ref-intacta`
  8/8 (referência `fade0461…` inalterada), nada escrito fora da pasta. Cópia reproduzível pelo
  caminho determinístico: `bash workspace/migracao/preparar-destino.sh … --gate` (`ok=6/falhas=0`).
- **Repositório separado `heldergaraujo2/MuserverRecriado`: reconstruído, conferido e NÃO publicado.** O `git push`
  foi tentado de novo nesta rodada e respondeu, igual,
  `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`; a API responde
  `Resource not accessible by integration` **no destino** (no repo de origem, `role_name=admin`).
  É a seleção de repositórios da **instalação do GitHub App** — a ACL do usuário já diz `push=true`.
  Ação do proprietário, sem efeito sobre a pesquisa: incluir esse repositório na instalação
  (*Contents: Read and write*); depois,
  `bash workspace/migracao/publicar-destino.sh`.
- Medidas desta rodada em `workspace/migracao/medidas-destino-rodada2.tsv`; as da primeira rodada
  ficam em `reports/migracao-destino.tsv` como histórico (não reescrito). O destino carrega a sua
  própria cópia independente (bundle + `MANIFEST.md` em `workspace/backups/`).
- Portão: **18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções, exit 0** aqui,
  e **14 PASS / 6 BLOCKED / 281 asserções** no destino (as 6 BLOCKED exigem a referência, que não
  viaja). `origin/main` intacto: `6eabb45b9e7939a3061f4757ed6791efef7c5c3b`.

## 7. Backup e restauração

`../../workspace/backups/mu2-v2.bundle` — snapshot orphan da árvore `recriado/`, checksum e tamanho no
[MANIFEST](../../workspace/backups/MANIFEST.md). Restauração:

```sh
git bundle verify workspace/backups/mu2-v2.bundle
D=$(mktemp -d)
git clone -q --no-hardlinks -b mu2-snapshot workspace/backups/mu2-v2.bundle "$D/r"   # -b é obrigatório
(cd "$D/r" && make -s check)
```

O bundle contém **apenas** a árvore `recriado/`. A cópia independente do repositório
publicado é outra (escopo diferente, decisão D2-38): ela é regravada **dentro** do destino por
`workspace/migracao/preparar-destino.sh` e restaura a árvore publicada, não o monorepo. Relatórios em `workspace/` vivem só na branch
publicada — por isso a publicação conferida por `ls-remote` faz parte do backup, não é opcional.

## 8. Bloqueios externos e decisões do proprietário

1. Incluir `MuserverRecriado` na seleção da instalação do App GitHub (Contents: Read and write).
2. Decidir o `PR #1` (aberto; nenhum merge é feito por conta do agente).
3. Enviar o pedido de recuperação do ambiente anterior ao suporte da plataforma.
4. Prover host adequado quando `bench` e medições de cliente forem necessários.

## 9. Regras inegociáveis

- Não escrever em `MuServer/`; não sobrescrever originais; não executar binários do pacote.
- Sem `git reset --hard`, `git clean -fd`, `push --force`, `git add -A`, nem reescrita de histórico.
- Sem merge de PR sem autorização. Sem contornar permissão do GitHub. Sem pedir credencial em claro.
- Publicação só é afirmada depois de `git ls-remote` conferir o SHA remoto.
- `blocked != aprovado`; diretório vazio ou especificação não é implementação.
- Não inflar `MU2_MAX_BODY`, buffers ou limites para fazer teste passar.
- **`GATE_FULL` é a variável do portão; `FULL` é do backup.** Usar `FULL=1 make -s gate` não liga nada
  e o portão sai verde com `net-matrix`/`persistencia` **SKIPPED**. Use `make -s gate-full` (achado de
  2026-10-13; o alvo existe para não depender de memória).
- Teste de recuperação de estado se prova com **morte real** do processo (`MU2DB_TESTE_ABORTA_APOS`),
  não truncando o arquivo: truncar testa o que *nós* escrevemos, não o que o SO tinha em disco.
- **Nunca editar arquivo que um portão em execução está lendo.** O bash lê script por deslocamento em
  bytes: editar `tests/run_all.sh` no meio de uma corrida fez o interpretador perder o fio e a corrida
  morrer em `syntax error near unexpected token 'done'` (exit 2) **depois de 11 minutos**. Medido em
  2026-10-13; a lição vale para qualquer script em execução.
- **Suíte não apaga artefato de outra etapa.** `tests/matriz.sh` fazia `rm -rf out/net-matrix` e, com
  `GATE_FULL=1`, apagava a matriz completa que `net-matrix` tinha acabado de produzir. Agora tira
  retrato, restaura no fim e tem caso próprio (sentinela) provando que artefato de terceiros
  sobrevive.
- **Critério que mede a coisa errada reprova trabalho certo.** Três asserções do `matriz.sh` comparavam
  `git status` com string vazia e falhavam por um relatório novo, legítimo e não commitado; passaram a
  medir **mudança** (antes/depois) e, na metade que prova a detecção, o **arquivo versionado aparecer
  marcado** — lido no instante certo, antes da restauração que apaga o sinal.
- Evidência não pode morar em caminho ignorado pelo git (`.json`/`.raw` em `workspace/reports`,
  `recriado/out/`): conferir que o arquivo aparece no `git diff --cached`.
- Binário versionado exige atributo `binary` e conferência **depois** do push (`FULL=1`).
- Matar processo de teste por **PID**, nunca por `pkill -f` com padrão que apareça no próprio script.
- Prazo de etapa por `timeout(1)` + grupo de processo próprio; nunca watchdog de fundo (D2-24:
  processo de controle que sobrevive à etapa já travou uma corrida inteira).
- Falsificação de mecanismo é **diferencial**, em cópia temporária; mutar arquivo real exige
  restauração conferida por sha256 (D2-23).

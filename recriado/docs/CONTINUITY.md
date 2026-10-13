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
| portão único (R-8) | [../tests/run_all.sh](../tests/run_all.sh) · [../tests/gate_state.sh](../tests/gate_state.sh) · [../tests/ref_check.sh](../tests/ref_check.sh) |
| sondas e suítes da R-6 | [../tools/cfg_probe.py](../tools/cfg_probe.py) · [../tools/wire_probe.py](../tools/wire_probe.py) · [../tools/matrix_check.py](../tools/matrix_check.py) · [../tests/conform.sh](../tests/conform.sh) · [../tests/cfg.sh](../tests/cfg.sh) |
| matriz de evidências (R-6) | [../reports/r6-matriz.tsv](../reports/r6-matriz.tsv) · [../reports/r6-relatorio.md](../reports/r6-relatorio.md) |
| desempenho e limites (R-7) | [../tests/bench.sh](../tests/bench.sh) · [../tools/bench_check.py](../tools/bench_check.py) · [../tools/rtt_probe.py](../tools/rtt_probe.py) · [../reports/r7-baseline.tsv](../reports/r7-baseline.tsv) · [../reports/r7-relatorio.md](../reports/r7-relatorio.md) |
| contrato e resultado do portão | [../reports/r8-relatorio.md](../reports/r8-relatorio.md) · [../reports/r8-gate.tsv](../reports/r8-gate.tsv) · [../reports/r8-gate-state.tsv](../reports/r8-gate-state.tsv) |
| relatório da R-5 (observação × hipótese × conclusão) | [../reports/r5-relatorio.md](../reports/r5-relatorio.md) |
| porta de entrada humana (build/run) | [../README.md](../README.md) |

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
| make-sintaxe | `make -s make-sintaxe` | 7 casos, 0 falhas |
| net (portão) | `make -s net` | 34 verificações, 0 falhas |
| net-matrix | `make -s net-matrix` | 36 verificações, 0 falhas (opt-in `GATE_FULL=1`) |
| pe / data | `make -s pe` · `make -s data` | 14 e 21 casos, 0 falhas |
| pe-selftest / data-selftest / cfg-selftest | `make -s *-selftest` | 4/4, 4/4, 5/5 — rodam **sem a referência** |
| conform | `make -s conform` | 15/15 cláusulas C-01…C-15, byte a byte |
| cfg | `make -s cfg` | 15 casos (portas e segredos redigidos) |
| **golden** | `make -s golden` | **42/42** — 38 vetores versionados + F20 + F21 |
| **fuzz** | `make -s fuzz` | **12/12** — 150 000 iterações, 0 violações, F22 |
| **seguranca** | `make -s seguranca` | **13/13** — 15 malformações na porta, fd e RSS estáveis |
| **admin** | `make -s admin` | **24/24** — console local, fail closed, papéis, 501 |
| **interop** | `make -s interop` | **12/12, `blocked=1`** — camada 3 BLOCKED (sem wine/autorização) |
| **lua** | `make -s lua` | **13/13, `blocked=1`** — inventário medido; sem interpretador no host |
| ref-intacta | `bash tests/ref_check.sh` | **8/8** — inclui a divergência dos 6 `.lua` e a reversão |
| bench | `make -s bench` | 15/15 — linha de base exploratória (R-7) |
| persistência | `FULL=1 bash scripts/verify-backup.sh` | **15/15** (opt-in; o portão padrão marca `SKIPPED`) |
| portão de build | `make -s check` | unit + make-sintaxe + net + pe + data = **182 asserções**, exit 0 |
| **portão único** | `make -s gate` | **18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções, 22 etapas, exit 0** |
| teste do portão | `make -s gate-selftest` | **19/19**, exit 0 (F12–F14, duplicação de etapa, `BLOCKED` demonstrado) |

Não existe, e por quê: `interop` camada 3 (BLOCKED — exige `wine`/`qemu-i386` + autorização; a suíte
não tem caminho de execução de binário original); execução de Lua (sem interpretador no host);
execução da suíte `golden` conter qualquer valor gerado pelo próprio programa — os 38 vetores foram
derivados à mão do contrato, com a derivação escrita na coluna `origem`.

## 6. Último commit e publicação

- Rodada vigente: `arena/cf1de8ce-muserver`. A rodada corrigiu defasagens numéricas da origem
  (`check` 180→182 asserções, `gate` 336→339, `seguranca` 12→13, `admin` 22→24) e reconstruiu o
  destino do zero com `workspace/migracao/adaptar-destino.py` — cada substituição com asserção
  própria (falha nomeando o texto que não casou) — no lugar do patch, que ficava pinado na base
  do split. A validação do destino achou e corrigiu um quinto defeito: a linha de base do teste de
  descritores era leitura solta e pegava a corrida do close assíncrono (medido: 1 de 10 execuções
  com `fd_antes=9` e piso real 8); passou a ser o piso observado numa janela curta.
- **Destino `heldergaraujo2/MuserverRecriado`: reconstruído, conferido e NÃO publicado.** O `git push`
  foi tentado de novo nesta rodada e respondeu, igual,
  `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`; a API responde
  `Resource not accessible by integration` **no destino** (no repo de origem, `role_name=admin`).
  É a seleção de repositórios da **instalação do GitHub App** — a ACL do usuário já diz `push=true`.
  Ação do proprietário: incluir o destino na instalação (*Contents: Read and write*); depois,
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
- Evidência não pode morar em caminho ignorado pelo git (`.json`/`.raw` em `workspace/reports`,
  `recriado/out/`): conferir que o arquivo aparece no `git diff --cached`.
- Binário versionado exige atributo `binary` e conferência **depois** do push (`FULL=1`).
- Matar processo de teste por **PID**, nunca por `pkill -f` com padrão que apareça no próprio script.
- Prazo de etapa por `timeout(1)` + grupo de processo próprio; nunca watchdog de fundo (D2-24:
  processo de controle que sobrevive à etapa já travou uma corrida inteira).
- Falsificação de mecanismo é **diferencial**, em cópia temporária; mutar arquivo real exige
  restauração conferida por sha256 (D2-23).

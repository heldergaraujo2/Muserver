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
| decisões técnicas D2-01…D2-21 | [DECISIONS.md](DECISIONS.md) |
| histórico por rodada | [CHANGELOG.md](CHANGELOG.md) |
| host, toolchain e limites do sandbox | [ENVIRONMENT.md](ENVIRONMENT.md) |
| fases R-0…R-9 e metas por categoria | [ROADMAP.md](ROADMAP.md) |
| plano original de reconstrução | [../../workspace/reports/PLANO-RECONSTRUCAO-MU2-2026-10-12.md](../../workspace/reports/PLANO-RECONSTRUCAO-MU2-2026-10-12.md) |
| auditoria completa (2026-10-12) | [../../workspace/reports/AUDITORIA-CONTINUIDADE-2026-10-12.md](../../workspace/reports/AUDITORIA-CONTINUIDADE-2026-10-12.md) |
| incidente e buscas do v1 perdido | [../../workspace/reports/WORKTREE-PERDIDO-2026-10-12.md](../../workspace/reports/WORKTREE-PERDIDO-2026-10-12.md) · [../../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md](../../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md) |
| pedido de recuperação à plataforma | [../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md](../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md) |
| identidade do backup e restauração | [../../workspace/backups/MANIFEST.md](../../workspace/backups/MANIFEST.md) |
| evidências medidas por fase | [../reports/](../reports/) — `r3-*.tsv`, `r4-*.tsv`, `r5-*.tsv`, `net-<perfil>.tsv` |
| sondas de formato (R-5) | [../tools/](../tools/) — `pe_probe.py`, `att_probe.py`, `mb_probe.py`, `data_probe.py` |
| relatório da R-5 (observação × hipótese × conclusão) | [../reports/r5-relatorio.md](../reports/r5-relatorio.md) |
| porta de entrada humana (build/run) | [../README.md](../README.md) |

## 4. Fases

Concluídas: **R-0** ambiente · **R-1** inventário · **R-2** baseline · **R-3** codec · **R-4** serviço
de rede + controlador + suíte de rede · **R-5** investigação de formatos por medição (sondas + suítes
`pe`/`data`; nada decodificado, nada compatível afirmado).
Próxima: **R-8** — portão único (`scripts/run_all.sh` + `tests/gate_state.sh`, `gate-selftest`
primeiro). Antecipada porque R-6 depende de evidência de protocolo inexistente e R-7 segue BLOCKED.
Depois: **R-6** interoperabilidade/golden · **R-7** `bench` (hoje BLOCKED) · **R-9** documentação e
publicação (contínuas, não fim de fila).

## 5. Testes — o que roda, o que não existe

| suíte | comando | último resultado |
|---|---|---|
| unit | `make -s unit` | 106 asserções, 0 falhas |
| make-sintaxe | `make -s make-sintaxe` | 7 casos, 0 falhas |
| net (portão) | `make -s net` | 34 verificações, 0 falhas |
| net-matrix | `make -s net-matrix` | 36 verificações, 0 falhas (100 conf × 5 reps por perfil) |
| pe | `make -s pe` | 14 casos, 0 falhas (`blocked=0` com a referência presente) |
| data | `make -s data` | 19 casos, 0 falhas |
| pe-selftest / data-selftest | `make -s pe-selftest` | 4/4 cada, **`blocked=1`** (rodam sem a referência) |
| portão completo | `make -s check` | unit + make-sintaxe + net + pe + data = **180 asserções**, exit 0, 19,4 s |
| persistência | `bash scripts/verify-backup.sh` (`FULL=1`) | 9/9 (13/13) |

**Não existem** — não tratar como aprovadas: `golden`, `interop`, `conform`, `fuzz`,
`gate_state`, `run_all.sh`. `bench`: **BLOCKED**. `e2e`: não é suíte separada, está em `tests/net.sh`.

## 6. Último commit e publicação

Preencher no fim de cada rodada (é dado volátil, junto com §7):

- HEAD: `03dcaa6` na branch `arena/cf1de8ce-muserver` (commit de conteúdo da R-5; o commit de
  backup/documentação vem logo depois, como em toda rodada)
- remoto: `git ls-remote --heads origin arena/cf1de8ce-muserver` → `03dcaa6…` **igual ao HEAD local**
  (conferido no fim da rodada)
- snapshot: `mu2-snapshot` @ `0e3abcf` (40 arquivos), bundle 112 020 B,
  sha256 `4f2190f19d3b1e15…`; `verify-backup.sh` 9/9 e `FULL=1` 13/13
- `origin/main` intacto: `6eabb45b9e7939a3061f4757ed6791efef7c5c3b`
- `MuserverRecriado`: **bloqueado** (403 na instalação do App); nada publicado lá

## 7. Backup e restauração

`../../workspace/backups/mu2-v2.bundle` — snapshot orphan da árvore `recriado/`, checksum e tamanho no
[MANIFEST](../../workspace/backups/MANIFEST.md). Restauração:

```sh
git bundle verify workspace/backups/mu2-v2.bundle
D=$(mktemp -d)
git clone -q --no-hardlinks -b mu2-snapshot workspace/backups/mu2-v2.bundle "$D/r"   # -b é obrigatório
(cd "$D/r" && make -s check)
```

O bundle contém **apenas** a árvore `recriado/`. Relatórios em `workspace/` vivem só na branch
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

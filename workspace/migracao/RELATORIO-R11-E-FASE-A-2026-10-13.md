# Relatório da rodada — R-11 (persistência própria do v2) + Fase A (artefatos do portão)

| campo | valor |
|---|---|
| data | 2026-10-13 |
| branch | `arena/cf1de8ce-muserver` (única publicada; sem `--force`, sem outra branch) |
| escopo | fechar os artefatos do portão que diziam menos do que aparentavam (A1/A2/A4) e implementar o subsistema de persistência do v2 — o primeiro estado durável do projeto |
| resultado | **A = reconstruído e validado** (persistência com transações, recuperação por morte real de processo, 99 + 31 asserções novas, portão 21 PASS / 0 FAIL) · **B = impedido** (ligação ao banco/serviço original, cliente original, `ozt`/`bmd`, publicação no repositório separado) |

## 1. HEAD inicial e final

| momento | referência |
|---|---|
| HEAD inicial | `414fc0f1bec7ab2027bf09412bd72f65118ee2da` (`arena/cf1de8ce-muserver`), `main` = `6eabb45b…` |
| commits desta rodada | `76fe2fc` (R-11 código+suítes) · `e4bd522` (Fase A: A1/A2/A4) · `b5e0c0f` (documentação) · `b2ffadd` (ritual R-2: snapshot/bundle) · `1cf1781` (documentação das corridas) · `67ad254` (snapshot final) |
| HEAD antes deste relatório | `67ad254e8d7a039ce4e88472201233d2ec76834d`, igual ao remoto conferido por `git ls-remote` |
| `main` | intacta em `6eabb45b9e7939a3061f4757ed6791efef7c5c3b` (não tocada) |
| PR #1 | `OPEN`, `mergedAt=null`, head `arena/cf1de8ce-muserver` — **nenhum merge feito** |

## 2. Auditoria do que já existia (o que foi conferido, não presumido)

- **A2 estava mal resolvido, e o portão mostrava isso:** `net-matrix` (opt-in) regravava
  `reports/net-{orig,mur0}.tsv` — versionados — e a etapa seguinte, `persistencia`, exige árvore
  limpa ⇒ `FAIL` por construção. Corrigido com artefato em `out/` + publicação explícita.
- **`FULL=1` × `GATE_FULL`:** a documentação mandava `FULL=1 make -s gate`, mas o portão lê
  `GATE_FULL`; `FULL` é do `verify-backup.sh`. Quem seguia a documentação rodava com `net-matrix` e
  `persistencia` **SKIPPED** e via verde onde não havia teste. Alvo novo `make -s gate-full`.
- **Clone raso** (A1): `ref_check.sh` acusava falha nos casos 7–8 por **objeto ausente**, não por
  defeito de conteúdo. Agora ausência ⇒ **BLOCKED nomeado** (`# ref-intacta=6 falhas=0 blocked=2`),
  sem `not ok` e sem afrouxar o critério: com o objeto presente, divergência continua `FAIL`.
- **`serve-docs.py` (A4):** o serviço servia por glob e não tratava HTML. Reescrito para **lista
  explícita** (31 documentos, um a um), resolução por dicionário exato, sanitização e `405` em
  `POST/PUT/DELETE/PATCH/OPTIONS`; teste novo com **35 asserções**, incluindo 9 negativos `404`.
- **Backup defasado, acusado com número pela própria etapa `persistencia`:** o bundle era da rodada
  da consolidação ⇒ `divergencia de conteudo dentro do declarado FALHA` (16 arquivos) e
  `arquivos fora do snapshot sao declarados FALHA extras=7 declarados=0`. O ritual R-2 foi executado
  de novo (snapshot orphan + `MANIFEST` + sha256).

## 3. Sistemas: implementado / parcial / ausente (depois desta rodada)

| subsistema | estado | evidência |
|---|---|---|
| persistência própria do v2 (contas, personagens, inventário, transações) | **implementado + testado + operacional** | `src/db.c`, `include/mu2/db.h`, `tools/mu2dbctl.c` → `db` 99/0, `dbctl` 31/0 |
| ligação rede ↔ persistência (login na porta) | **ausente** (decisão de contrato, não omissão) | `src/mud2.c` não tem opcode de controle; item 2 do `NEXT_TASK.md` |
| autenticação de conta | **parcial**: local, com PBKDF2-HMAC-SHA256 (20 000 iterações, salt de 16 B, comparação em tempo constante) | `db` casos de senha certa/errada/conta inexistente |
| personagens/inventário | **parcial**: registro durável (limites, nível que só sobe, zen, 64 slots, transferência atômica) sem nenhuma lógica de jogo | `db` 54–99, `dbctl` 5–14 |
| mundo, combate, guildas, economia | **ausente** | `PROJECT_STATUS.md` §2 |
| banco do original (SQL Server/ODBC) | **ausente e fora de escopo** | `DATABASE.md` §2; nada copiado ou restaurado |

## 4. Alterações e commits

| arquivo | estado | blob (HEAD) |
|---|---|---|
| `recriado/src/db.c` | novo (1 590 linhas) | `f536f0eecd8eb2b336114ead14ae22efce5cd2fe` |
| `recriado/include/mu2/db.h` | novo (148) | `8fe9235816a336a56265cc35e22e44a59e2ba4d3` |
| `recriado/tools/mu2dbctl.c` | novo (221) | `8b20ddf610f43fabfacf3e36a86a2f20b2d6bf6b` |
| `recriado/tests/db_test.c` | novo (514) | `99c7c4d6e1b285dfac9dcecd7b03a2ef0c1e52f2` |
| `recriado/tests/dbctl.sh` | novo (140) | `a0ca857566c36b068d791ee7c20754b5a1371f0c` |
| `recriado/tests/matriz.sh` | novo (regressão A2) | `620f20e6838ae6feba5fcc8449a3c87b4d32ce84` |
| `recriado/reports/r11-persistencia.md` | novo (relatório) | `253b177147de20a6c8ec2a1474e14cb7dbf92edf` |
| `workspace/backups/MANIFEST.md` | atualizado (103 arquivos, 367 995 bytes) | `d6470e6b18da6124e75ae938bcd8443c3ff30d63` |
| `workspace/backups/mu2-v2.bundle` | regravado | `69572003aa4a6e1477524064719a412c7849c987` |
| `recriado/Makefile`, `tests/run_all.sh`, `tests/{net,ref_check,gate_state}.sh`, `workspace/tools/serve-docs.py`, `workspace/tests/test_serve_docs.py` | alterados (A1/A2/A4 + alvos `db`, `dbctl`, `gate-full`) | — |
| `recriado/docs/*.md` (CHANGELOG, CONTINUITY, CURRENT_STATE, DATABASE, DECISIONS, NEXT_TASK, PROJECT_STATUS, ROADMAP, TESTING) | alterados | — |

Nada fora de `recriado/`, `workspace/tools/`, `workspace/tests/` e `workspace/backups/`.
`MuServer/` intocada: `git diff --quiet HEAD -- MuServer` sem saída, tree `fade04615fabd17778a0e2fd7adf032c8386c924`.

## 5. Testes: comandos, números e exit codes

| comando | resultado medido |
|---|---|
| `make -s build` | exit 0 (`-Werror` + ASan/UBSan) |
| `make -s db` | `1..99`, `# db=99 falhas=0` |
| `make -s dbctl` | `1..31`, `# dbctl=31 falhas=0 blocked=0` |
| `make -s gate` (árvore limpa, commit final) | **PASS=21, FAIL=0, BLOCKED=3, NOT_IMPLEMENTED=0, SKIPPED=2, 481 asserções, 26 etapas, exit 0** (80 529 ms) |
| `make -s gate-full` (árvore limpa, remoto sincronizado) | **PASS=22, FAIL=0, BLOCKED=4, SKIPPED=0, 502 asserções, 26 etapas, exit 0** (694 850 ms) |
| `bash scripts/verify-backup.sh` | `ok=11 falhas=0 blocked=0` |
| `FULL=1 bash scripts/verify-backup.sh` | `ok=15 falhas=0 blocked=0` — `bundle byte a byte OK remoto=89de50a8…`, `HEAD local esta no remoto OK 67ad254` |
| `make -s gate-selftest` | 21/21 |
| `bash workspace/tests/test_serve_docs.py` | `# serve-docs=35 falhas=0` |

**A 4ª `BLOCKED` do `gate-full` é o `bench`, e está declarado por quê:** depois de 11 minutos de
matriz de rede o host fica carregado; o drift medido foi **31,1% maior que o máximo de 25%** fixado
**antes** de rodar, e o validador recusou o número (`blocked=1`, 15/15 asserções, 0 falhas, 0 perdas).
No portão padrão, em host ocioso, a mesma etapa é `PASS` 15/15. `BLOCKED` aqui = medição inválida.

## 6. Evidência de integração (não de módulo isolado)

- `net-matrix`, `matriz-artefatos` e `persistencia` passam **na mesma corrida** (`gate-full`), que era
  exatamente o defeito A2 — medido antes (`FAIL` em `persistencia`) e depois (`PASS`).
- O CLI `mu2dbctl` é **segundo consumidor** da mesma API: cada comando é um processo novo, então
  todo caso de `dbctl` prova que o estado veio do arquivo, não de memória de processo.
- A transferência de item entre personagens atravessa três camadas (API → transação → log em disco) e
  é verificada depois de reabrir, inclusive sob morte do processo no meio.

## 7. Persistência e reinício (o que foi provado)

- **Durabilidade:** estado escrito por um processo aparece em outro (`dbctl` casos 8, 12, 13, 14).
- **Atomicidade:** morte real do processo (`_exit` sem `atexit`/`fflush`) no meio de uma transferência
  deixa o item **na origem**, o destino **intacto**, o arquivo **do tamanho de antes** e `verify`
  aprovando; `descartados=1` na primeira abertura e `0` na segunda (casos 19–31).
- **Recuperação:** log cortado no meio é truncado no último registro confirmado; corrupção de payload
  é **detectada** por CRC32C e recusada (o CLI não "conserta" sozinho).
- **Defeito que a rodada encontrou aqui:** a primeira versão do rollback descartava em memória e
  reiniciava a numeração de TX, e uma transação nova **reaplicava** operações abandonadas até o
  arquivo ficar ilegível. Corrigido (D2-40) com regressão que morre de verdade.

## 8. Compatibilidade: o que **não** pode ser inferido

- O formato `MU2DB01` **não** é o banco do original, não lê esquema `WZ_*`, não usa ODBC e não foi
  testado com dado de produção — não há dado de produção legítimo neste ambiente.
- O serviço `mud2` continua **sem autenticação e sem persistência** em seu contrato declarado: a
  ligação entre rede e banco **não existe ainda**.
- Nenhuma medição desta rodada diz nada sobre o cliente original; `interop` camada 3, `lua` e
  `lua-enc` seguem `BLOCKED` com causa.

## 9. Riscos e decisões desta rodada

- **Dois defeitos de processo, registrados porque a lição vale mais que o verde:** (1) editar
  `tests/run_all.sh` **durante** uma corrida matou o portão em `syntax error` depois de 11 minutos
  (bash lê script por deslocamento em bytes) — agora é regra no `CONTINUITY.md` §9; (2) o `matriz.sh`
  fazia `rm -rf out/net-matrix` e **apagava a matriz completa** que a etapa anterior tinha produzido —
  agora tira retrato, restaura e prova com sentinela.
- **Decisão D2-40:** rollback é remoção física e número de transação não se repete.
- **Risco de exposição (inalterado, do proprietário):** os 6 achados P07 e a PII em
  `reports/r6-config.tsv` continuam **pendentes de decisão**; nada foi rotacionado nem publicado.

## 10. Lista priorizada do que falta

1. **A3 — regressão estática dos 6 `.lua` patcheados** (`tests/regressao-lua.sh`): testável hoje, sem
   interpretador. Único item da Fase A ainda aberto.
2. **Ligar `mud2` à persistência** (login de verdade na porta): exige **decisão de contrato** (o v2
   não tem opcode de login) — não é operação de rotina; critério no `NEXT_TASK.md`.
3. **Publicação do repositório separado** e rodada de publicação nova da pasta `MuserverRecriado/`
   (ela é snapshot da rodada anterior: não tem `db.c`, `mu2dbctl.c`, `dbctl.sh`).
4. `ozt`/`.bmd`/`.att` além da classificação; `enc` (algoritmo da cifragem dos `.lua`); capacidade
   absoluta de desempenho — os três já `BLOCKED` com causa e caminho.

## 11. Dependências externas (resultado B — impedido)

| dependência | o que trava | quem destrava |
|---|---|---|
| instalação do GitHub App com `MuserverRecriado` (Contents: Read and write) | publicação do repositório separado (`403`) | proprietário |
| `wine`/`qemu-i386` + autorização de execução | `interop` camada 3, validação contra binário original | proprietário/plataforma |
| cliente original + interpretador Lua | `lua`, `lua-enc`, FPS/fluidez, camada 3 | proprietário |
| SQL Server/ODBC + `.bak` restaurados em ambiente autorizado | acoplamento ao banco original | proprietário |
| host dedicado | capacidade absoluta (`bench` hoje é baseline exploratória) | proprietário |

## 12. Próxima tarefa executável

**A3 — `tests/regressao-lua.sh`**: conferir baseline ↔ patch ↔ árvore dos 6 `.lua` patcheados
(integridade por sha256, presença das correções por análise estática, reversibilidade), como etapa do
portão, sem tocar em `MuServer/` e sem afrouxar `ref-intacta`. Critério de aceitação: suíte nova sem
`not ok`, `make -s gate` verde e `ref-intacta` mantendo 8/8 no repo completo e 6/0/2 no raso.
A tarefa seguinte (login na porta) fica **parada por decisão**, não por falta de tempo.

---

## Publicação desta rodada (lida de volta, não presumida)

- `git push origin arena/cf1de8ce-muserver` em três momentos: `414fc0f..b5e0c0f` (R-11 + Fase A),
  `b5e0c0f..b2ffadd` (ritual R-2), `b2ffadd..67ad254` (documentação e snapshot final). Sem `--force`,
  sem apagar histórico, nenhuma outra branch empurrada.
- `git ls-remote origin refs/heads/arena/cf1de8ce-muserver` lido de volta:
  **`67ad254e8d7a039ce4e88472201233d2ec76834d`** — igual ao HEAD local no momento da leitura.
- Verificador depois da publicação: `FULL=1 bash scripts/verify-backup.sh` → **ok=15 falhas=0**, com o
  bundle conferido **byte a byte dentro do clone do remoto** (`remoto=89de50a8… local=89de50a8…`) e
  `HEAD local esta no remoto OK 67ad254`.
- `main` conferida no remoto: `6eabb45b9e7939a3061f4757ed6791efef7c5c3b` (inalterada).

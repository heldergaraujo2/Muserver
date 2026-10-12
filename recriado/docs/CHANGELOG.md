# CHANGELOG do v2

## R-6 — 2026-10-12
- **Camada 1 (conformidade interna do v2) comprovada**: `tests/conform.sh` com 15 cláusulas
  C-01…C-15 verificadas byte a byte por `tools/wire_probe.py` (quadros inválidos incluídos):
  limite 2048, rejeição por `size`, little-endian, opcode desconhecido sem derrubar conexão,
  fragmentação, D2-17, formato da linha STATS, equivalência `orig`/`mur0`. 15/15.
- **Camada 2 (compatibilidade observada)**: `tools/cfg_probe.py` mede 19 `.ini`, 655 pares,
  endpoints 44406/55557 (ConnectServer), 55960, 55970, 55990, 55998, 55999, 1433; **cliente
  aponta 44405 enquanto o ConnectServer escuta 44406** — divergência registrada como hipótese.
- **Camada 3 (interop)**: **BLOCKED** — exige binário original em execução; `interop` continua
  `NOT_IMPLEMENTED` no portão, nunca `PASS`.
- **Segurança**: 26 valores sensíveis em claro no pacote original; `cfg_probe.py` redige por nome
  de chave **e** por forma do valor, e `tests/cfg.sh` (15 casos) cobra a redação. Nenhum segredo
  em arquivo versionado (conferido: 0 linhas não redigidas). Decisão D2-25.
- **Matriz de evidências** `reports/r6-matriz.tsv` (12 linhas × 9 colunas), validada no portão por
  `tools/matrix_check.py`: linha sem comando reproduzível ⇒ falha.
- **Defeito real**: etapa `conform` criada sem remover o placeholder fez a mesa imprimi-la duas
  vezes e contar asserções em dobro (244 vs 229). Corrigido + guarda de duplicação (exit 2) e
  invariantes no lugar de totais exatos no `gate-selftest`. Decisão D2-26.
- Portão: **13 PASS, 0 FAIL, 4 NOT_IMPLEMENTED, 2 SKIPPED, 229 asserções**; `gate-selftest` 19/19.

## R-8 — 2026-10-12
- **Portão único** `tests/run_all.sh`: 16 etapas em ordem determinística, cinco estados
  (`PASS`/`FAIL`/`BLOCKED`/`NOT_IMPLEMENTED`/`SKIPPED`), mesa legível + TSV, log por etapa,
  exit ≠ 0 somente com `FAIL`. Resultado real: **9 PASS, 0 FAIL, 5 NOT_IMPLEMENTED, 2 SKIPPED,
  194 asserções, 19,7 s**.
- **`tests/gate_state.sh`** — 18 casos sobre o próprio portão (estados, timeout sem órfão,
  SIGTERM → 130, cwd `/` e caminho com espaço, relatório pré-existente, repetibilidade,
  referência ausente, resumo ausente, suíte que morre no fim) + F12/F13/F14. **18/18, exit 0**.
- **`tests/ref_check.sh`** — integridade de `MuServer/` medida de dentro do portão (árvore git,
  ausência de alterações e de untracked, contagem, e âncoras de conteúdo de 4 PE lidas de
  `reports/r5-pe.tsv`): 6/6.
- Alvos `make gate` e `make gate-selftest`; `gate` não entra em `check` (sem recursão).
- **Defeito real achado e corrigido:** o watchdog de fundo da primeira versão sobrevivia à etapa
  (`build.timeout` 600 s depois, `sleep 420` órfão com `PPID 1`), bloqueava a corrida e podia
  sinalizar grupo alheio — substituído por `timeout(1)` + grupo próprio (`set -m`). Decisão D2-24.
- `pe`/`data` passam a distinguir `escopo=selftest` de `blocked=1` (D2-22).
- Decisões D2-22, D2-23, D2-24. Evidências `reports/r8-gate.tsv`, `r8-gate-state.tsv`,
  `r8-relatorio.md`.

## R-5 — 2026-10-12
- **Sondas de formato** em `tools/` (D2-19): `pe_probe.py` (parser PE próprio: DOS/NT/COFF/optional,
  seções, entropia, imports, `--keywords`), `att_probe.py`, `mb_probe.py`, `data_probe.py`. Python
  3.11 só com stdlib, somente leitura sobre `MU_REF_DATA`, saída TSV determinística e sem caminho
  absoluto do host.
- **Suítes novas:** `tests/pe.sh` (14 casos) e `tests/data.sh` (19 casos), cada uma com invariantes
  medidos + recusa de entrada inválida + autos-teste; modo `SELFTEST_ONLY=1` roda sem a referência
  e declara `blocked=1`. Alvos `pe`, `data`, `pe-selftest`, `data-selftest`; `check` agora é
  `unit make-sintaxe net pe data` → **180 asserções, 0 falhas, 19,4 s**.
- **Medidas publicadas:** `reports/r5-pe.tsv`, `r5-formatos-att.tsv`, `r5-formatos-modelo.tsv`,
  `r5-dados.tsv` e o relatório `r5-relatorio.md` (observação × hipótese × conclusão × limitação).
- **Falsificações F8–F11** (sonda fingindo conformidade, aceitando não-PE, vazando caminho
  absoluto, perdendo determinismo): todas detectadas com exit ≠ 0 e revertidas com sha256 conferido.
- **Decisões novas:** D2-19, D2-20, D2-21.
- **Correção de documentação:** a auditoria da R-3 registrava "3 `.enc`"; mediu-se **0 arquivos
  `.enc`** — eram 3 *matches* de `*luaenc*`, hoje 2 (`LuaEncryptorTool.exe` + `.pdb`).
- **Nada alterado em `MuServer/`** (árvore `fade04615fab`, 10 021 arquivos, somente leitura).

## R-0/R-1/R-2 — 2026-10-12
- Aberta a arvore `recriado/` (v2) dentro do repositorio rastreado da sessao, com
  `.gitignore` proprio, `reports/README.md` (regra de extensao por causa dos padroes de
  ignore do hospedeiro) e os docs `README`, `CURRENT_STATE`, `NEXT_TASK`, `DECISIONS`
  (D2-01..D2-10), `ENVIRONMENT`.
- Tentativa de recuperacao do v1 encerrada com veredito (Etapa 1): nenhum mecanismo
  autorizado disponivel do sandbox; solicitacao pronta em
  `../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`.
- Permissao do GitHub diagnosticada com discriminador de API + `push --dry-run` (nenhum
  ref criado): o App de autenticacao **nao tem** `MuserverRecriado` na selecao de
  repositorios. Instrucao manual em `NEXT_TASK.md` secao "acao do dono".
- Ambiente medido (`docs/ENVIRONMENT.md`): sem clang ⇒ sem libFuzzer; sem
  valgrind/gdb/strace/perf/file; ASAN+UBSAN e hardening compilam; 2 vCPUs/4 GiB ⇒ limiar de
  drift do `bench` a recalibrar; `MU_REF_DATA` presente e conferido.
- Mecanismo de backup independente criado: `scripts/verify-backup.sh` + `backup/`
  (bundle limitado a `recriado/**` + `MANIFEST.md` com SHA-256), com teste de restauracao
  por clone a partir do bundle. Nada de `src/` ainda: **nenhum teste de C foi executado**,
  e nenhuma suíte do v1 deve ser considerada reproduzida.

### R-0, fechamento da rodada (mesma data)
- Backup independente gravado e **conferido por restauracao real**: `backup/mu2-v2.bundle`
  (17 225 B, historia do `recriado/**` via subtree split, ponta `17f4f79`) + `backup/MANIFEST.md`
  com SHA-256. `scripts/verify-backup.sh`: 6 verificacoes, todas verdes depois do commit.
- Defeito encontrado pelo proprio verificador: o `git clone` do bundle sem `-b mu2-v2` nascia com
  HEAD para um `main` inexistente (checkout vazio + warning ignorado). Corrigido no script e no
  MANIFEST. Fica registrado porque e o tipo de bug que so aparece quando se testa restaurar.
- Publicacao conferida de volta: `origin/arena/cf1de8ce-muserver` == HEAD local (`git ls-remote`).
  Nenhuma ref extra publicada; `mu2-v2` e branch local de trabalho do backup.
- Etapa 2 com causa exata: `collaborators/.../permission` responde 200 em `Muserver` e
  `403 Resource not accessible by integration` em `MuserverRecriado` para o mesmo token
  autenticado como o dono => selecao de repositorios do App, nao scope. Sonda de escrita
  nao mutante (`push --dry-run`): 403. Nenhum ref criado no repo de desenvolvimento.

## R-3 — 2026-10-12 (enquadramento, codec, Makefile, suíte unitária)
- `include/mu2/mu2.h` + `src/wire.c`: quadro `code(2,LE) | size(2,LE) | corpo`, `MU2_MAX_BODY`
  2048, `MU2_MAX_FRAME` 2052, dois perfis (`orig` cru, `mur0` involutivo), erros distintos por
  causa (`E_ARG`/`E_SIZE`/`E_DST_SMALL`/`E_INCOMPLETE` com `needed`/`E_BAD_LEN`/`E_PROFILE`).
  Layout e decisao do v2 (D2-11), nao compatibilidade afirmada com o `ConnectServer.exe`.
- `Makefile` com ASAN+UBSAN e `-Werror` por padrao; saidas em `out/` (D2-13); `tests/make_parse.sh`.
- `tests/unit.c`: **106 assercoes, 0 falhas** (`reports/r3-unit.tsv`). Contagem desta arvore; o
  `unit=82` do v1 e [alvo] historico e nao foi usado como criterio de nada.
- Falsificacoes executadas (`reports/r3-falsificacao.tsv`): F1 troca de campos do cabecalho →
  45 falhas; F2 validacao de `size` afrouxada → 2 falhas; F3 `mur0` neutralizado → 18 falhas;
  F4 `-Werror` removido do portao → `make-sintaxe` 2 falhas. Reversao conferida com
  `git status --porcelain` vazio em `recriado/{src,tests,include,Makefile}`.
- Dois defeitos de teste encontrados pelo proprio processo desta fase e corrigidos antes do commit:
  (a) caso 4 do `make_parse` dependia do estado de `out/` (flaky) → `make -B -n`; (b) o alvo
  `.PHONY build` colidia com o diretorio `build/` e o `make` descartava dependencia em silencio →
  diretorio virou `out/`.
- Suítes que ainda **nao existem** no v2 (registradas como ausentes, nao como aprovadas): `e2e`,
  `net`, `golden`, `interop`, `conform`, `data`, `fuzz`, `pe`, `bench`, `gate_state` e o
  `scripts/run_all.sh`. Sem laço de rede sem fio: nada do contrato de backpressure foi exercitado
  ainda; isso e a R-4.

### R-3, fechamento com a copia independente consertada por medida
- Realocar o bundle para `workspace/backups/` e troca-lo por snapshot orphan (`git commit-tree
  HEAD:recriado`): 134 694 → 31 771 bytes, e custo constante (a arvore do snapshot nao contem o
  proprio bundle). Registrado como D2-15.
- Defeito grave encontrado ao conferir o blob publicado, nao o do worktree: o `* text=auto` do
  `.gitattributes` da raiz aplicava `text: set` ao `*.bundle`, e o bundle **comitado** nao batia com
  o arquivo em disco (`be79f094… != 1ec952bd…`) — restauracao por clone daria arquivo corrompido.
  Corrigido com `workspace/backups/.gitattributes` (`*.bundle binary`).
- `verify-backup.sh` ganhou modo `FULL=1`: clona a branch **publicada** e la dentro confere bundle
  byte a byte, `git bundle verify`, restauracao da arvore a partir do bundle clonado e presenca do
  HEAD local no remoto. Resultado apos o fix: **10 verificacoes, 0 falhas**.
- Portao da fase re-execuido no fim: `unit=106 falhas=0`, `make-sintaxe=5 falhas=0`.

## R-4 — servico de rede `mud2`, controlador `mu2ctl` e suite de rede (medido nesta arvore)
Novos: `src/mud2.c` (585 linhas), `src/mu2ctl.c`, `include/mu2/proto.h`, `tests/netclient.c`,
`tests/net.sh`; `Makefile` com alvos `mud2`/`mu2ctl`/`netclient`/`net`/`net-matrix` e `check` agora
incluindo a suite de rede; `tests/make_parse.sh` com 2 casos novos (7 no total).
Portao: **unit=106 falhas=0**, **make-sintaxe=7 falhas=0**, **net=34 falhas=0** (matriz reduzida),
**net-matrix=36 falhas=0** (100 configuracoes x 5 repeticoes por perfil, 10m12s). ASAN+UBSAN+`-Werror`
em tudo, zero violacao de sanitizador. Detalhes em `reports/r4-check.tsv`.
Falsificacoes (todas detectadas, `reports/r4-falsificacao.tsv`): **F5** `break` no `feed()` → a suite
nao termina em 300 s e >=4 verificacoes caem; **F6** sem `drain()` imediato → 8 falhas; **F7**
`queue_reply` invertido → 3 falhas.
Tres defeitos achados durante a subida e corrigidos antes de fechar: (1) `mu2_frame_body` recebe o
inicio do quadro, nao o corpo — a linha STATS saia como `S registros=...` (D2-17); (2) `close=queue_full`
saia em dobro, o que dobraria qualquer classificacao por log; (3) `mu2ctl --profile` errado imprimia
lixo com exit 0, porque o perfil nao e detectavel no stream — agora o prefixo `STATS ` e conferido.
Um quarto defeito foi do **processo**, nao do codigo: a reversao da mutacao F6 foi perdida porque o
comando de limpeza usava `pkill -f` com um padrao que casava com a linha de comando do proprio shell
(exit -1, reversao nunca executada). Tres medicoes seguintes foram feitas contra o binario mutado,
detectadas pela contradicao com a matriz, e **refeitas**. Regra nova: matar por PID, nunca por
`pkill -f` com padrao presente no proprio script.
Achados tecnicos: a vaga unica so funciona com `drain()` imediato (F6); com buffers padrao nao houve
perda nem fila cheia em 50/50 configuracoes por perfil; com `--sndbuf 1024` + `SO_RCVBUF 1024` a fila
cheia apareceu em 50/50 e o limite e a janela do cliente (1024 pedido → 2304 efetivo), nao o numero de
quadros — o "~29 respostas de 64 B" do v1 nao se reproduziu (D2-18). Zero fechamentos sem
classificacao e zero perda sem fechamento em 200 corridas.
Ausentes de proposito, como antes: `bench` (BLOCKED), `golden`/`interop`/`conform`/`data`/`pe`/`fuzz`/
`gate_state`/`run_all.sh` (nao implementados). Nenhuma compatibilidade com o cliente original foi
testada ou afirmada.

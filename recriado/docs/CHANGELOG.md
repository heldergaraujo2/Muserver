# CHANGELOG do v2

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

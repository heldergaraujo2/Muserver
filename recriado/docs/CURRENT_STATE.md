# CURRENT_STATE — v2 — 2026-10-12 (mesa atual)

## Onde o projeto esta
Fases **R-0, R-1, R-2 e R-3 concluidas**. A R-3 entregou o enquadramento:
`include/mu2/mu2.h` + `src/wire.c` (quadro `code|size|corpo`, dois perfis, erros por causa),
`Makefile` com ASAN+UBSAN+`-Werror`, `tests/unit.c` e `tests/make_parse.sh`, com os tres
relatorios em `reports/r3-*.tsv`.
**R-4 em diante: nada comecado** — `bench/`, `corpus/`, `tools/`, `scripts/run_all.sh` e
qualquer suíte além de `unit`/`make-sintaxe` ainda nao existem, de proposito.

## Estado do codigo e dos testes (declaracao, nao impressao)
- Codigo do produto: `src/wire.c` (codec de enquadramento) e o unico codigo escrito ate aqui;
  `src/mud2.c` e `src/mu2ctl.c` **nao existem** (R-4/R-5).
- Testes executados nesta arvore [medido, rodada R-3]: `unit` **106 assercoes, 0 falhas** sob
  ASAN+UBSAN; `make-sintaxe` **5 casos, 0 falhas**, conferido independente de estado;
  falsificacao **F1..F4** todas capturadas (45, 2, 18 e 2 falhas) com reversao conferida.
- Portao unico (`scripts/run_all.sh`): **inexistente** (e a R-8). Suítes `e2e`, `net`, `golden`,
  `interop`, `conform`, `data`, `fuzz`, `pe`, `gate_state`: **inexistentes**, registradas como
  ausentes, nunca como aprovadas. Portao de baseline do v1: **inexistente** (a arvore dele nao foi
  recuperada).
- Medicoes de rede/benchmark do v2: **nenhuma**. O `bench` comeca `BLOCKED` e assim fica ate
  os criterios de validade serem reaplicados e recalibrados para as 2 vCPUs deste host.
- Numeros do v1 (round-trip, CPU/quadro, contagens de suíte) **nao** estao reproduzidos; onde
  aparecem, estao como `[alvo]` (D2-02).

## Recuperacao do v1 (Etapa 1) — encerrada, com veredito
- Ambiente anterior **nao reaberto**: nenhum mecanismo autorizado existe dentro do sandbox.
  Verificado [medido]: sem CLI/SDK da plataforma (`arena`, `e2b`, `sandboxctl` ausentes);
  `envd` na porta 49983 e o agente **desta** instancia (`/health` 204, `/files` e `/init` 401
  por faltar token — e nao ha token aqui); `E2B_EVENTS_ADDRESS=http://192.0.2.1` (buraco
  negro); `api.e2b.app` resolve mas a conexao devolve `000` (allowlist de saida), com controle
  positivo `api.github.com`/`pypi.org` = `200`; nenhuma rota de snapshot/restore no `envd`.
- Nenhum conteudo do v1 no disco, nos blocos brutos do `/dev/vda`, no journal ext4, nos
  artefatos do Arena, nos refs remotos (inclusive `refs/pull/*`) nem em `git log --all -S`.
  Comandos e saidas em `../../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md`.
- Solicitacao de recuperacao **pronta para envio**:
  `../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`.

## Permissoes do GitHub (Etapa 2) — diagnostico exato, sem contorno
- `heldergaraujo2/Muserver` (referencia; produto somente leitura): `push=true` pela API **e**
  publica de fato — `origin/arena/cf1de8ce-muserver` confere com o SHA local, conferido a cada
  rodada com `git ls-remote --heads`. `main` segue em `6eabb45`, intacto.
- `heldergaraujo2/MuserverRecriado` (desenvolvimento): `size=0`, nenhum ref publicado, e
  `git push --dry-run` devolve `403 remote: Permission to heldergaraujo2/MuserverRecriado.git
  denied to heldergaraujo2` (sonda nao mutante; nenhum ref criado por mim).
- Discriminador que localiza a causa [medido]: `GET /repos/heldergaraujo2/Muserver/collaborators/heldergaraujo2/permission`
  → **200**, enquanto o mesmo endpoint em `MuserverRecriado` → `403 Resource not accessible by
  integration`. A identidade autenticada **e** o proprio dono (`gh api /user` → `heldergaraujo2`,
  id 323230170), `X-Oauth-Scopes` vazio e `Github-Authentication-Token-Expiration:
  2026-10-12 23:42:17 UTC` (token curto, reemitido entre chamadas). Conclusao: nao falta scope
  classico nem credencial — falta o repositorio na **selecao de repositorios do App GitHub** usado
  pela plataforma. O `.permissions` da API do repo vazio vem `push=true` **nao** contradiz isso:
  ele descreve o usuario, nao as concessoes da instalacao do App.
- Nada neste sandbox guarda credencial gravavel (`git config --list --show-origin` sem helper nem
  `insteadOf`; `/home/user/.gitconfig` e `.git-credentials` inexistentes; `GH_TOKEN`/`GITHUB_TOKEN`
  = `arena-egress-dummy-token`): a autenticacao acontece na camada de saida da plataforma. Nao ha
  nada para rodar/exportar aqui, e nenhum segredo para vazar.
- `PR #1` do repo de referencia: **aberto**, `arena/cf1de8ce-muserver` → `main`, autor
  `heldergaraujo2`, 5 commits. O caminho `recriado/**` passa a figurar nesse PR enquanto a
  branch for atualizada — decisao do dono em `NEXT_TASK.md` (fundir, ou segregar o v2).

## Backups e publicacoes conferidos nesta rodada
- Publicacao: cada commit do `recriado/**` empurrado na branch da sessao e **conferido de volta**
  por `git ls-remote --heads` (SHA remoto == local). O repositorio `MuserverRecriado` continua sem
  nenhuma publicacao nossa: sem autorizacao do App, nao se tenta contornar (D2-09).
- Copia independente: `backup/mu2-v2.bundle` (historico limitado ao caminho `recriado/**`) +
  `backup/MANIFEST.md` com SHA-256, e **teste de restauracao real** (clone a partir do bundle em
  `/tmp`) executado por `scripts/verify-backup.sh`.
- Preservacao: os relatorios das rodadas anteriores, os commits, o stash que virou tag
  `pre-ff-2026-10-12-stash` (objeto ainda recuperavel) e o pacote `MuServer/**` (nao tocado)
  estao intactos. Nenhum `reset --hard`, nenhum `clean -fd`, nenhum `--force`.

## Mesa numerada (para a proxima rodada comecar sem re-ler a conversa)
| chave | valor |
|---|---|
| branch da sessao | `arena/cf1de8ce-muserver` |
| remoto conferido | `origin/arena/cf1de8ce-muserver` == HEAD local; na abertura da R-0 foi `fccaeaa` (a branch avanca a cada rodada, o que vale e a conferencia `ls-remote`) |
| fase atual | R-3 fechada (unit 106/0, make-sintaxe 5/0, F1..F4 capturadas); proxima executavel = **R-4** |
| baseline desta rodada | `90bbfea` (codigo da R-3); relatorios e docs vao no commit seguinte |
| suítes ausentes | e2e, net, golden, interop, conform, data, fuzz, pe, bench, gate_state, run_all |
| bloqueio de publicacao | App GitHub sem `MuserverRecriado` na selecao de repositorios |
| bloqueio de recuperacao | plano de controle inalcancavel do sandbox; depende da plataforma |
| `MU_REF_DATA` | `/home/user/Muserver/MuServer` (presente e conferido) |

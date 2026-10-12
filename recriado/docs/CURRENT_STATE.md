# CURRENT_STATE — v2 — 2026-10-12 (mesa atual)

## Onde o projeto esta
Fase **R-0 concluida** (persistencia + backup + verificacao), **R-1 concluida**
(especificacao congelada como decisao `D2-01..D2-10`) e **R-2 concluida** (ambiente medido
em `ENVIRONMENT.md`). **R-3 em diante: nada comecado.** `src/`, `include/`, `tests/`,
`bench/`, `corpus/` e `scripts/run_all.sh` ainda nao existem — de proposito.

## Estado do codigo e dos testes (declaracao, nao impressao)
- Codigo do produto: **zero linhas escritas** nesta arvore.
- Testes de C executados: **nenhum**. Portao unico (`scripts/run_all.sh`): **inexistente**.
  Portao de baseline do v1: **inexistente** (a arvore dele nao foi recuperada).
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
- Publicacao: commit do `recriado/**` empurrado na branch da sessao e **conferido de volta** por
  `git ls-remote --heads` (SHA remoto == local). O valor fica na tabela abaixo.
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
| fase atual | R-0/R-1/R-2 fechadas (backup verificado: 6/6); proxima executavel = **R-3** |
| bloqueio de publicacao | App GitHub sem `MuserverRecriado` na selecao de repositorios |
| bloqueio de recuperacao | plano de controle inalcancavel do sandbox; depende da plataforma |
| `MU_REF_DATA` | `/home/user/Muserver/MuServer` (presente e conferido) |

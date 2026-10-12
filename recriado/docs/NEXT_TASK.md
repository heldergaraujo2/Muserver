# NEXT_TASK — v2 — próxima rodada

## Tarefa executável: R-8 — portão único (por que antes da R-6)

A ordem do `ROADMAP.md` é execução, não aprovação: a R-6 (`interop`/`golden`) depende de evidência
de protocolo que ainda não existe, e a R-7 continua **BLOCKED** pelos critérios de validade. O que
dá para fechar agora, com dependência só do que já está verde, é o **portão único** — e ele é
pré-requisito para confiar em qualquer rodada seguinte.

### Estado inicial a verificar antes de escrever qualquer linha
1. `git status --porcelain` limpo; `git rev-parse HEAD` == `git ls-remote origin <branch>`.
2. `make -s check` verde: `unit=106`, `make-sintaxe=7`, `net=34`, `pe=14`, `data=19` (180 asserções).
3. `MuServer/` intacta: `git ls-tree HEAD MuServer` = `fade04615fab…`, 10 021 arquivos.
4. `bash scripts/verify-backup.sh` = 9/9.

### O que construir
- **`scripts/run_all.sh`** — roda cada suíte em ordem fixa, captura `exit code` e a linha de resumo
  (`# <nome>=<n> falhas=<f> blocked=<b>`) de cada uma, e imprime uma mesa final
  `nome | estado | asserções | falhas | bloqueado | segundos`.
  Estados: `PASS` (exit 0 e `falhas=0` e `blocked=0`) · `FAIL` (exit ≠ 0 ou `falhas>0`) ·
  `BLOCKED` (exit 0 com `blocked>0`, ou suíte que declara o bloqueio) · `NOT_IMPLEMENTED`
  (suíte listada no plano mas inexistente — `golden`, `interop`, `conform`, `fuzz`, `bench`).
  **Regras herdadas:** sem `set -e`; `blocked != aprovado`; `FAIL` obrigatório ⇒ exit ≠ 0 do portão;
  nada de `pkill -f` (usar `PID=$!` + `kill -TERM "$PID"` + `wait "$PID"`).
- **`tests/gate_state.sh`** — testa **o próprio portão**, nesta ordem:
  1. `gate-selftest` primeiro: injeta uma suíte sintética que falha e verifica que `run_all.sh`
     sai ≠ 0 e marca `FAIL` (portão que não sabe falhar não é portão);
  2. injeta suíte que declara `blocked=1` e verifica que o estado sai `BLOCKED`, **não** `PASS`, e
     que o portão **não** sai ≠ 0 por isso;
  3. injeta suíte inexistente e verifica `NOT_IMPLEMENTED`;
  4. roda o portão real e verifica que a mesa bate com os números das suítes (180 asserções).
- Alvo `make gate` (e `gate-selftest`), sem colocar `gate` dentro de `check` para não recursão.

### Critérios de pronto (todos mensuráveis)
- `make -s gate` imprime a mesa e sai 0 com o estado atual do repositório.
- `bash tests/gate_state.sh` verde, com o `gate-selftest` executado **antes** do portão real.
- Uma suíte listada e inexistente aparece como `NOT_IMPLEMENTED` — nunca como `PASS`.
- Relatório `reports/r8-gate.tsv` + `reports/r8-relatorio.md` com comando, saída, exit code e estado.
- `MuServer/` intacta no diff; `verify-backup.sh` 9/9; push conferido por `git ls-remote`.

### Proibido nesta rodada
- Declarar `golden`/`interop`/`conform` como aprovados (não existem).
- Transformar `BLOCKED` em `PASS` para a mesa ficar bonita.
- Mexer em `MU2_MAX_BODY`, buffers ou limiares para suíte passar.
- `git add -A`, `reset --hard`, `clean -fd`, `push --force`.

### Falsificações obrigatórias da R-8
- F12: `run_all.sh` ignora o exit code de uma suíte ⇒ `gate_state.sh` tem de falhar.
- F13: `run_all.sh` trata `blocked=1` como `PASS` ⇒ tem de falhar.
- F14: uma suíte real é forçada a falhar (mutação revertida em seguida, com sha256 conferido) ⇒
  o portão sai ≠ 0.

## Ação do dono (manual) — para o v2 ter repositório próprio e publicável

Nada disto é bloqueante: com a árvore `recriado/` dentro de `Muserver` na branch da sessão, o trabalho
já está persistido e publicado. A faixa abaixo só importa se você quiser o `MuserverRecriado` ativo.

1. Abra <https://github.com/settings/installations> (logado como `heldergaraujo2`).
2. No App que a Arena usa para este workspace, clique em **Configure**.
3. Em **Repository access**, se estiver "Only select repositories", clique em **Add repository** e
   escolha `MuserverRecriado`. (Se estiver "All repositories", o problema não é a seleção — me avise,
   porque aí a causa é outra e eu reabro a investigação com essa informação.)
4. Confirme que o App tem **Contents: Read and write**.
5. Volte para a conversa e escreva "autorizado". Eu testo com `git ls-remote` e `push --dry-run`, e só
   depois disso crio o remote de verdade — nunca antes de a conferência passar.
6. Publicação: o branch local `mu2-v2` já é a semente (`git push <novo-remote> mu2-v2:main`), com a
   história preservada; o bundle serve de transporte se a rede não permitir push.

Não faço por você: não há como alterar App, token nem visibilidade de repositório a partir do sandbox.

## Ação do dono — pedido de recuperação ao suporte da plataforma

O texto está pronto em
[`../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`](../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md).
Envie pelo canal de suporte/feedback da sessão Arena: **de dentro do sandbox não há como descobrir nem
chamar esse canal** (a saída é limitada a uma allowlist que não inclui serviço da plataforma). Nenhum
endpoint foi inventado nem contornado.
Se o volume anterior voltar, esta árvore vira destino de cópia (backup primeiro, depois
`git rev-parse HEAD == c5706a5`, `git bundle verify`, portão de baseline com
`MU_REF_DATA=/home/user/Muserver/MuServer`) e o v2 passa a ser comparação, não substituto.

## Sobre o `PR #1` (aberto, `arena/cf1de8ce-muserver` → `main`, autor `heldergaraujo2`)

Enquanto o v2 viver nesta branch, ele aparece dentro desse PR — o que mistura a auditoria da camada Lua
com um projeto novo em `recriado/`. Duas saídas, sua escolha: (a) fundir o PR #1 e seguir com o v2 na
branch; (b) manter o v2 na branch e segregar depois por `subtree split` (o branch `mu2-v2` já existe
localmente para isso). **Não fundo nem reorganizo o PR por conta própria.**

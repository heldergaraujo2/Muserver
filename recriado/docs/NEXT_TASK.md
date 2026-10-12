# NEXT_TASK — v2 — próxima rodada

## Tarefa executável: R-7 — desempenho e limites (baseline exploratória)

### Estado inicial a verificar
1. `git status --porcelain` limpo; HEAD == remoto (`git ls-remote`).
2. `make -s gate` → 13 PASS, 0 FAIL, 229 asserções; `make -s gate-selftest` → 19/19.
3. `bash tests/ref_check.sh` = 6/6; `bash scripts/verify-backup.sh` = 9/9.

### Regra de honestidade desta fase
**Não existe requisito de desempenho definido pelo dono.** Então nada aqui é critério de aceitação:
a entrega é uma **baseline exploratória**, rotulada como tal em cada relatório, com o objetivo de
tornar regressões visíveis — não de declarar o servidor "rápido". Proibido escrever "desempenho
melhorado" sem medição comparável.

### O que construir
- **`bench/bench.c`** (ou `tests/bench.sh` dirigindo `netclient`): N conexões, M quadros por conexão,
  corpo fixo, taxa controlada; medir por passagem: throughput (quadros/s e bytes/s), latência
  p50/p95/p99, erros, `queue_full_closes`, fechamentos por motivo.
- **Critérios de validade declarados ANTES** de rodar: número de repetições (≥5), rejeição de
  aquecimento, e **drift máximo entre passadas** — se o drift passar do declarado, o resultado é
  `BLOCKED` por ambiente, não publicado como número.
- **Registro do ambiente** em cada relatório: `nproc`, modelo de CPU, kernel, `cc -v`, flags
  (`SAN=1` ou `SAN=0` — e a comparação dos dois custos, que é medição legítima).
- **Limites**: varrer `--max-clients`, tamanho de corpo até `MU2_MAX_BODY`, e janela de socket;
  registrar onde aparece `queue_full` e qual o custo. **Não aumentar limites para o número ficar
  bom** — se um limite for candidato a mudança, abrir decisão D2-xx com a medição dos dois lados.

### Limitação conhecida do host (registrar, não esconder)
2 vCPUs compartilhadas. Concorrência alta mede o escalonador, não o serviço. Conclusões de
capacidade absoluta são `BLOCKED`; comparações relativas no mesmo host e mesma configuração são
válidas e é o que a baseline pode afirmar.

### Critérios de pronto
- Etapa `bench` no registro do portão, `PASS` com a baseline ou `BLOCKED` com a causa exata.
- `reports/r7-baseline.tsv` + `r7-relatorio.md` com critérios de validade, drift medido e ambiente.
- `make -s gate` e `gate-selftest` verdes; `ref_check.sh` 6/6; `verify-backup.sh` 9/9.
- Push conferido por `git ls-remote`; snapshot regravado.

### Falsificações previstas
- F18: `bench` que ignora o drift declarado ⇒ o próprio validador de critérios falha.
- F19: `bench` contando o quadro de `STATS` como tráfego medido ⇒ inconsistência com `frames` do
  serviço (erro já cometido na R-4; o teste tem de pegá-lo).

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

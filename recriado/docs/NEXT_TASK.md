# NEXT_TASK — v2 — proxima rodada

## Tarefa executavel: R-4 — servico `mud2` e o experimento de backpressure (N-T5.3d2)
Escopo: laço de aceitacao + `poll()` + `feed()` + fila de resposta + `queue_reply`, e a suíte
`tests/net.sh`. Nada de `bench`, nada de `conform`/`data` (sao R-5/R-7).

1. `src/mud2.c`: `--listen`, `--max-clients`, `--sndbuf` (minimo 1024), `--idle-ms`, `--profile`,
   `--log-level`; `feed()` consome **todos** os quadros do buffer lido (premissa contraria foi
   refutada no v1 e o teste tem de continuar provendo isso por fora: dois quadros em um `write`
   contam `frames` +2); `queue_reply` recusa com fechamento + `LOGW` dedicado quando h
   a resposta anterior pendente (D2-05), e **incrementa `queue_full_closes`** (novo, aditivo: o
   v1 deixava essa capacidade invisivel no contador de erros).
2. Pergunta a responder **antes** de escrever o laço, e a registrar no commit: o laço pede
   `POLLOUT` quando existe resposta pendente? Se nao, resposta pendente nunca e retomada —
   starvation demonstravel, e isso muda a decisao de fila (com causa, nao por preferencia).
3. `src/mu2ctl.c` com `stats` (mesma linha do contrato: `STATS registros= usados= conns= frames=
   rejects= queue_full_closes= uptime_ms= slotsz= maxbody=`) para o experimento ler de fora.
4. `tests/net.sh` (variante por perfil `orig`/`mur0`), com os knobs do cliente **antes do
   `connect()`**: `socket()` → `setsockopt(SO_RCVBUF,1024)` → `connect()`, e `getsockopt` impresso
   (pedido **e** efetivo: 1024 → 2304/4608 neste kernel, e sem `CAP_NET_ADMIN` nao ha `SO_*BUFFORCE`).
   Matriz: `N_conn ∈ {1,4,16}`, `N_frames ∈ {10,29,30,31,60,120}`, `t_sem_ler ∈ {0,1s,5s}`,
   `delay_entre_leituras ∈ {0,50ms}`, `--sndbuf ∈ {0,1024}`, corpo pequeno (`ping`) e grande
   (corpo proximo de 2048 por `--serverlist` de teste). 5 repeticoes por configuracao, mediana e
   amplitude publicadas, `reports/net-<perfil>.tsv`.
5. Classificacao obrigatoria de cada desconexao pela linha do log do servidor — fila cheia !=
   bloqueio normal de TCP != timeout ocioso != erro de socket. Sem classificacao, o caso nao vale.

Criterios de saida: `make -s check` verde (unit + make-sintaxe); `net` executado com a matriz
acima e os efetivos de buffer registrados; **falsificacoes**: (i) `break` no `feed()` (um quadro por
`recv`) deve mudar o resultado, (ii) remover o `drain()` imediato deve aumentar fechamentos,
(iii) inverter a politica de `queue_reply` para "enfileirar sempre" deve sumir com os fechamentos —
e, se com (iii) **nenhuma** perda aparecer, a politica atual e mantida e os limites do experimento
 sao escritos (D2-05), sem inflar `MU2_MAX_BODY` nem buffers para forcar resultado. Reverter e
conferir `git status --porcelain` vazio em `src/`.

Se (e somente se) a R-4 mostrar perda ou incompatibilidade com o contrato documentado, a mudanca de
fila vem em commit isolado, com regressao e `bench` antes/depois — e o `bench` continua `BLOCKED`
ate os criterios de validade dele (R-7) existirem neste host de 2 vCPUs.

## Acao do dono (manual) — para o v2 ter repositorio proprio e publicavel
Nada disto e bloqueante: com a opcao A (esta arvore dentro de `Muserver` na branch da sessao) o
trabalho ja esta persistido e publicado. Faixa abaixo so se voce quiser o `MuserverRecriado` ativo.

1. Abra <https://github.com/settings/installations> (logado como `heldergaraujo2`).
2. No App que a Arena usa para este workspace, clique em **Configure**.
3. Em **Repository access**, se estiver "Only select repositories", clique em **Add repository**
   e escolha `MuserverRecriado`. (Se estiver "All repositories", o problema nao e a selecao —
   me avise, porque ai a causa e outra e eu reabro a investigacao com essa informacao.)
4. Confirme que o App tem **Contents: Read and write** (permissao de conteudo de codigo).
5. Volte para a conversa e escreva "autorizado". Eu testo com `git ls-remote` e `push --dry-run`,
   e so depois disso crio o remote de verdade — nunca antes de a conferencia passar.
6. Publicacao: `git subtree split -P recriado -b mu2-v2` → push da branch resultante. A historia
   do v2 vai junto; nenhum commit se perde e o repo de referencia fica intacto.

Nao faco por voce: nao tenho como alterar App, token nem visibilidade de repositorio a partir do
sandbox (a autenticacao acontece fora daqui), e nao toco em permissao de conta.

## Acao do dono — pedido de recuperacao ao suporte da plataforma
O texto esta pronto em `../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`.
Envie o conteudo pelo canal de suporte/feedback da sessao Arena (a interface onde esta conversa
acontece); **nao ha como, de dentro do sandbox, descobrir ou chamar o canal da plataforma** —
a saida e limitada a uma allowlist que nao inclui nenhum servico da Arena/e2b, e os tokens de
ambiente sao dummy. Nao inventei endpoint nem tentei contornar: foi verificado e registrado.
Se o volume anterior voltar, esta arvore vira destino de copia (backup primeiro, depois `git
rev-parse HEAD == c5706a5`, `git bundle verify`, portao de baseline com `MU_REF_DATA=/home/user/Muserver/MuServer`)
e o v2 passa a ser comparacao, nao substituto.

## Sobre o `PR #1` (aberto, `arena/cf1de8ce-muserver` → `main`, autor `heldergaraujo2`)
Enquanto o v2 viver nesta branch, ele aparece dentro desse PR — o que mistura a auditoria da
camada Lua com um projeto novo em `recriado/`. Duas saidas, sua escolha:
(a) fundir o PR #1 (conteudo == `main` + a auditoria Lua + os relatorios) e seguir com o v2 na
branch; (b) manter o v2 na branch e segregar depois por `subtree split`. Eu **nao** fundo nem
reorganiz o PR por conta propria.

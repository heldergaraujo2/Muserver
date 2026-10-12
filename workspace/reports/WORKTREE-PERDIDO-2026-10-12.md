# Worktree do projeto C perdido no sandbox — 2026-10-12 (registro de incidente e plano pronto)

## 1. O que aconteceu

O sandbox foi **recriado** entre a rodada anterior e esta. A árvore de trabalho da segunda
implementação (o serviço C `mud2` + suas suítes e docs) existia em `/home/user/MuserverRecriado`
(clone do repositório `heldergaraujo2/MuserverRecriado`) e **não existe mais aqui**, nem os
artefatos que viviam fora do diretório persistido.

Verificação (comando → saída real):

| comando | resultado |
|---|---|
| `git cat-file -t c5706a5` | `fatal: Not a valid object name c5706a5` |
| `ls -a /home/user` | só `.bash_logout .bashrc .profile Muserver`; `mtime` de `/home/user` = 12/10 14:15 |
| `find / -name "mu2.h" -o -name "net.sh" -o -name "make_parse.sh" -o -name "pe_probe.py" -o -name "muserverrecriado*"` | nenhum resultado |
| `git ls-remote https://github.com/heldergaraujo2/MuserverRecriado.git` | **sem nenhum ref** (repo vazio) |
| API `repos/heldergaraujo2/MuserverRecriado` | `size: 0`, `pushed_at == created_at == 2026-10-11T20:47:12Z` |
| API `repos/heldergaraujo2` (todos os públicos) procurando `mud2`/`mu2`/`net.sh`/`pe_probe` | 0 hits (os docs de `Otimizacao-cliente` são de outro projeto) |

Perda material: os 20 commits de `MuserverRecriado²` (terminando em `c5706a5`), incluindo
`src/mud2.c`, `src/wire.c`, `src/mu2ctl.c`, `include/mu2/mu2.h`, `bench/bench.c`,
`tests/{net.sh,make_parse.sh,unit.c,e2e.sh,golden.sh,interop.sh,conform.c,fuzz.c,gate_state.sh}`,
`tools/{pe_probe,att_probe,mb_probe,data_probe}.py`, `scripts/run_all.sh`, os `reports/*.tsv`
versionados e os docs `CURRENT_STATE/NEXT_TASK/DECISIONS (D-01..D-19)/PERFORMANCE/TEST_RESULTS/
TEST_STRATEGY/DATAFORMATS/COMPATIBILITY/ARCHITECTURE`. Também se perderam o
`/home/user/muserverrecriado-main.bundle` e o venv `/home/user/.venv-tools` (este último
reconstruível: `python3 -m venv /home/user/.venv-tools && .../pip install lupa luaparser capstone`).

Nada disso está no GitHub porque o único caminho de publicação daquele repositório respondeu
**403** (`Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`) — foi
reportado na rodada anterior em vez de contornado.

**Não reconstituí os arquivos a partir de memória de sessão.** Reconstruir `src/mud2.c` e as
suítes de um resumo em prosa produziria um produto *novo* com números *velhos*, e a N-T5.3d2
consiste justamente em medir contra o produto real. Registrar a perda e parar aqui é a única
saída honesta; o plano de execução está no §4, pronto para rodar no momento em que a árvore
(ou o bundle) voltar.

## 2. O que está a salvo, e o que foi feito nesta rodada

- A linha de trabalho deste repositório (auditoria da camada Lua) estava **íntegra**: a árvore
  local era byte-idêntica ao commit já publicado `b5b84da` (`origin/arena/cf1de8ce-muserver`).
  Conferido por hash em 36 arquivos + os 6 `.lua` modificados (0 divergências).
- Sincronizei a branch local com o remoto (`git merge --ff-only origin/arena/cf1de8ce-muserver`),
  HEAD = `b5b84da`. O merge inicial foi recusado duas vezes — primeiro por arquivos *untracked*
  que colidiriam, depois pelos 6 `.lua` modificados — e tratei isso sem força: cópia dos 36
  arquivos para `workspace/changes/pre-ff-2026-10-12/untracked/`, `git stash push` dos 6 `.lua`,
  ff, e depois conferência `cmp` de 36/36 idênticos antes de descartar o stash. `git diff
  --stat b5b84da` vazio; `MuServer/` intocado; nenhum `--force`, nenhum `reset --hard`.
- Backup do estado pré-ff (patch + md5 + cópias) ficou em `workspace/changes/pre-ff-2026-10-12/`.
- O pacote `MuServer/` (748 MB) está presente — é o `MU_REF_DATA` de que as suítes do projeto C
  dependem, então a restauração tem com o que rodar `conform`/`data`/`pe`.

## 3. O que a rodada ganhou mesmo assim: o ambiente que impedia a reprodução

A pergunta em aberto da N-T5.3d era: *por que a fila de 1 resposta nunca mordeu em loopback?*
Medi este kernel diretamente (dois sockets TCP em `127.0.0.1`, escritor não-bloqueante, leitor
que não lê — sem produto no meio, para a conclusão não depender dele).

```
snd_req rcv_req quando   reply frames  escrito esperado travou  lidos
 1024     1024  depois      64     60    3840     3840  False    512   <- o que a rodada anterior fez
 1024     1024  antes       64     60    1856     3840  True     704   <- janela pequena de verdade
 1024     1024  antes       64     60    1856     3840  True    1856   (mesmo caso, leitor lento:
 1024     1024  antes       66     60    1860     3960  True     708     tudo que travou foi lido depois)
 1024     1024  antes     2048      8    2880    16384  True    1152
    0     1024  antes       64     60    3840     3840  False    704   <- so o rcvbuf do cliente: nao basta
 1024        0  n/a         64     60    3840     3840  False   1088   <- so o --sndbuf do produto: nao basta
 1024      256  antes       64     60    1856     3840  True     704   <- piso do kernel, ver abaixo
```

E o que o kernel **aplicou** de verdade, contra o que foi pedido (nada assumido):

| pedido | efetivo | nota |
|---|---|---|
| `SO_RCVBUF` 1024 | **2304** | piso do kernel; pedir 256 dá o mesmo 2304 |
| `SO_SNDBUF` 1024 | **4608** | o kernel dobra o valor de usuário |
| `SO_RCVBUF`/`SNDBUF` 0 (padrão) | 131072 / 2626560 | — |
| `net.core.rmem_max`/`wmem_max` | 212992 | `rmem_min`/`wmem_min` não existem nesta kernel |
| `CapEff` | `0000000000000000`, euid 1001 | **sem `CAP_NET_ADMIN`** ⇒ `SO_RCVBUFFORCE`/`SO_SNDBUFFORCE` indisponíveis; 2304 B é o mínimo alcançável |

As três conclusões, todas medidas:

1. **`setsockopt` depois do `connect()` não fecha a janela.** O SYN/ACK já negociou a janela com
   o buffer padrão, e ela só encolhe na próxima atualização. É exatamente por isso que a rodada
   anterior viu “400 de 400 respostas, zero perda”: o cliente pediu `SO_RCVBUF=1024` depois de
   conectar. Linha `depois` da tabela: `travou=False`.
2. **Aplicar antes do handshake produz o gargalo.** Capacidade total em voo ≈ **1 856 B** com as
   duas pontas apertadas → ~**29 respostas de 64 B** entram; a 30ª escrita do servidor devolve
   `EAGAIN`. Com corpo grande (2 048 B por resposta, ~`MU2_MAX_BODY`), cabe **1** resposta e meia.
3. **Os dois lados importam.** Apertar só o `--sndbuf` do produto (linha `rcv=0`) ou só o
   `rcvbuf` do cliente (linha `snd=0`) **não** trava — é por isso que a D-09 existe e, ainda assim,
   a política não era exercitável: faltava a metade do cliente, aplicada na hora certa.

Ou seja: o fechamento por fila ocupada **é alcançável** neste sandbox, por meio de knobs já
existentes (`--sndbuf` do produto + `SO_RCVBUF` do *teste*, antes do `connect`). A rodada anterior
documentou “não alcançável em loopback”; essa afirmação está **refutada** pela linha `antes` da
tabela e precisa ser corrigida em `PERFORMANCE.md` §5.2 quando a árvore voltar.

## 4. Plano pronto para N-T5.3d2 (rodar assim que a árvore/bundle for restaurado)

Pré-condição zero — estado e linha de base, nesta ordem, sem nada em paralelo:

```sh
cd /home/user/MuserverRecriado && git rev-parse --short HEAD     # deve ser c5706a5
git status --porcelain | wc -l                                   # deve ser 0
git -C /home/user/Muserver rev-parse --short HEAD                # b5b84da, intacto
git bundle verify /home/user/muserverrecriado-main.bundle         # se vier bundle em vez da arvore
cd 'MuserverRecriado²' && make -s build && make -s make-sintaxe
MU_REF_DATA=/home/user/Muserver/MuServer bash scripts/run_all.sh | tail -5   # baseline ANTES de mexer
```

Experimento (passo a passo, cada item com o que registra):

1. Ler `queue_reply`, `drain`, `feed` e o laço de `poll()`: conferir **se o laço pede `POLLOUT`
   quando há resposta pendente**. Se não pedir, uma resposta pendente nunca é retomada — aí há um
   defeito *funcional* demonstrável (starvation), e não apenas backpressure de projeto. Registrar a
   linha do código e o que ela implica, antes de qualquer número.
2. Novo caso em `tests/net.sh` (variante por perfil), com o **rcvbuf do cliente aplicado antes do
   `connect()`** — o ponto que a versão anterior não tinha: `socket.socket()` → `setsockopt` →
   `connect()`. Impresso no resultado: `rcvbuf pedido/efetivo` e `sndbuf pedido/efetivo`
   (`getsockopt`), porque o kernel clampa (2304/4608) e assumir o valor pedido é o erro da rodada
   anterior.
3. Variáveis controladas e declaradas: `N_conn ∈ {1,4,16}`, `N_frames ∈ {10,29,30,31,60,120}`,
   `t_sem_ler ∈ {0,1 s,5 s}`, `delay_entre_leituras ∈ {0,50 ms}`, `--sndbuf ∈ {0,1024}`,
   `--max-clients` fixo, resposta pequena (`ping`) e resposta grande (`list`, `--serverlist` com
   o maior `ServerList` que o *fixture* permite — arquivo de teste, não limite do produto).
   Repetir cada configuração 5×; mediana e amplitude registradas, como no `bench`.
4. Classificar cada desconexão por **evidência do log do servidor** (nível 2+), não por inferência:
   `resposta anterior ainda pendente` ⇒ fila de aplicação cheia; `escrita falhou` ⇒ erro de socket;
   `conexao ... encerrada (timeout ocioso)` ⇒ timeout; e *ausência* dessas linhas com `EAGAIN` no
   cliente ⇒ bloqueio normal de TCP. Dizer qual deles ocorreu, quantas vezes, e com quantas
   respostas entregues — é o que faltou para a rodada anterior separar as quatro coisas.
5. Contadores do produto (`stats`) antes/depois de cada caso, com o `−1` da auto-contagem do
   `stats` aplicado **uma** vez. Registrar se o fechamento por fila aparece em `rejects` — a leitura
   do código diz que não (capacidade perdida invisível no contador de erros); isso é hipótese até o
   experimento mostrar o número, e a asserção deve fixar o que for medido, não o que seria bonito.
6. Falsificação obrigatória do caso novo: `break` em `feed()` (uma resposta por `recv`) deve mudar
   o resultado do caso; e uma mutação que **incremente** o fechamento (ex.: remover o `drain()`
   imediato) deve ser pega. Restaurar byte a byte e conferir `git diff --stat` vazio em `src/`.
7. Decisão, com a regra do projeto: sem perda ou incompatibilidade com contrato documentado, a
   política da D-09 continua e `PERFORMANCE.md`/`NEXT_TASK.md` passam a descrever a *receita* do
   §3 (e o piso do kernel que a limita: 2304 B, sem `CAP_NET_ADMIN`). Haja fechamento com dano
   funcional, a mudança de fila vem isolada, com regressão e `bench` antes/depois — e `bench`
   continua valendo com o critério de validade dele: host ruidoso é `BLOCKED`/AMARELO, não
   “melhorou”.

## 5. Publicação (não contornado)

`git push origin main` em `heldergaraujo2/MuserverRecriado` continua **403**. Autorização que o
proprietário precisa conceder ao token/aplicativo: **`Contents: Read and write`** nesse
repositório (e, se o token estiver em “Only select repositories”, adicionar `MuserverRecriado` à
lista). Com a árvore restaurada e essa permissão, os 20 commits sobem do estado que já existe —
sem re-medir nada. O `MuServer` (deste repositório) tem a branch `arena/cf1de8ce-muserver`
publicada em `b5b84da` ✓.

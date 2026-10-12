# CURRENT_STATE — v2 (estado medido, nao relato)

Atualizado no fim da rodada **R-4**. Índice curto e ponto de entrada: `CONTINUITY.md`.

## Mesa da rodada

| campo | valor |
|---|---|
| fase fechada | **R-4** — serviço de rede mínimo + controlador de métricas + suíte de rede |
| fases fechadas antes | R-0 (ambiente), R-1 (inventário), R-2 (baseline), R-3 (codec) |
| próxima fase | **R-5** — controlador de dados e inspeção do pacote original (`NEXT_TASK.md`) |
| branch | `arena/cf1de8ce-muserver` |
| portão | `make -s check` → `unit=106 falhas=0`, `make-sintaxe=7 falhas=0`, `net=34 falhas=0` |
| matriz completa | `make -s net-matrix` → `net=36 falhas=0`, 100 conf × 5 reps por perfil, 10m12s |
| falsificações da rodada | F5/F6/F7 detectadas (ver `reports/r4-falsificacao.tsv`) |
| benchmark | **BLOCKED** (critérios de validade ausentes; host de 2 vCPUs) |
| compatibilidade com o original | **não testada, não afirmada** (pergunta da R-6) |

## O que existe no código

| arquivo | linhas | papel |
|---|---|---|
| `include/mu2/mu2.h` | 90 | contrato do quadro (R-3) |
| `include/mu2/proto.h` | 26 | opcodes do serviço + prefixo da linha de métricas (D2-16) |
| `src/wire.c` | 170 | codec: encode/decode/size/body/transform/profile/errstr |
| `src/mud2.c` | ~590 | serviço: `poll()`, `feed()` incremental, fila de 1 vaga, `drain()`, ociosidade, capacidade, log classificado |
| `src/mu2ctl.c` | ~170 | `stats` lido de fora, pelo próprio protocolo |
| `tests/unit.c` | 301 | 41 *sites* `CHECK(` em 13 faixas → 106 asserções executadas |
| `tests/netclient.c` | ~380 | cliente de ensaio: `SO_RCVBUF` antes do `connect()`, escrita fatiada/concatenada, espera sem ler, verificação byte a byte |
| `tests/net.sh` | ~330 | 13 cenários de contrato + matriz de backpressure |
| `tests/make_parse.sh` | 30 | 7 casos sobre o Makefile |
| `scripts/verify-backup.sh` | ~120 | publicação + backup restaurável (modo `FULL=1` prova o pós-push) |

## Testes: o que roda e o que não existe

Rodam e passam: `unit` (106/0), `make-sintaxe` (7/0), `net` (34/0), `net-matrix` (36/0),
`verify-backup.sh` (6/6 e `FULL=1` 10/10).
**Não existem** (não marcar como aprovados): `golden`, `interop`, `conform`, `data`, `pe`, `fuzz`,
`gate_state`, `run_all.sh`. `bench` existe como intenção e está **BLOCKED**. `e2e` não é suíte
separada: os cenários ponta a ponta estão dentro de `tests/net.sh`.

## Cenários de rede cobertos (S1…S13)

Leitura fragmentada · quadros concatenados num único `write` · leitor atrasado com buffers padrão ·
leitor atrasado com janela curta · cliente que não lê e pede de novo (fila cheia) · desconexão limpa ·
desconexão abrupta (RST) · encerramento do serviço com conexão aberta · timeout ocioso · estouro de
`--max-clients` · coerência de métricas · corpo no limite (2048) · quadro inválido (`size=0`) ·
opcode desconhecido descartado sem derrubar a conexão.
Mais as duas asserções da D2-14: leitor atrasado recebe tudo com `queue_full_closes == 0`, e quem não
lê nada e pede de novo produz o fechamento com `close=queue_full` e contador incrementado.

## Números que importa não perder

- Buffers padrão (`--sndbuf 0`): **0 perdas e 0 filas cheias em 50/50 configurações** por perfil.
- `--sndbuf 1024` + `SO_RCVBUF 1024` no cliente: fila cheia em **50/50**, mediana de 7 a 16 respostas.
  Efetivos: 2304 no cliente, 4608 no serviço; sem pedir nada, o socket aceito herda 2 626 560.
- O "~29 respostas de 64 B" do v1 (D2-05) **não se reproduziu** aqui: divergência documentada.
- Amplitude entre repetições sob pressão: até 104 respostas. Conclusão só por mediana.
- 200 corridas de configuração: **0 fechamentos sem classificação, 0 perdas sem fechamento**.

## O que continua bloqueado ou pendente de terceiros

- `MuserverRecriado`: fora da seleção da instalação do App GitHub (403). Nenhuma tentativa de contorno.
- Recuperação do v1 (`c5706a5`): esgotada e negativa; pedido pronto em
  `../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`, não enviado (exige humano).
- `PR #1` (`arena/cf1de8ce-muserver` → `main`): aberto, decisão do dono; nenhum merge feito aqui.
- `bench`: sem critérios de validade e sem host adequado.

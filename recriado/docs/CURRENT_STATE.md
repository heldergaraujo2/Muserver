# CURRENT_STATE — v2 (estado medido, nao relato)

Atualizado no fim da rodada **R-5**. Índice curto e ponto de entrada: `CONTINUITY.md`.

## Mesa da rodada

| campo | valor |
|---|---|
| fase fechada | **R-5** — investigação de formatos por medição (PE, `.att`, modelos, dados, Lua) |
| fases fechadas antes | R-0 (ambiente), R-1 (inventário), R-2 (baseline), R-3 (codec), R-4 (serviço de rede) |
| próxima fase | **R-8** — portão único `run_all.sh` + `gate_state.sh` (`NEXT_TASK.md`) |
| branch | `arena/cf1de8ce-muserver` |
| portão | `make -s check` → `unit=106`, `make-sintaxe=7`, `net=34`, `pe=14`, `data=19` — **180 asserções, 0 falhas, 19,4 s** |
| matriz completa | `make -s net-matrix` → `net=36 falhas=0`, 100 conf × 5 reps por perfil, 10m12s |
| falsificações da rodada | F8/F9/F10/F11 detectadas (ver `reports/r5-relatorio.md` §6) |
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
| `tools/pe_probe.py` | ~150 | parser PE próprio: DOS/NT/COFF/optional, seções, entropia, imports, `--keywords` |
| `tools/att_probe.py` | ~80 | `.att`: tamanho, marcador, distribuição de `byte0`/`byte3`, histograma do corpo |
| `tools/mb_probe.py` | ~110 | `.bmd`/`.smd`/`.ozt`/`.ozj`: magic, imprimibilidade, hipótese XOR-3 medida |
| `tools/data_probe.py` | ~170 | inventário por extensão, Lua (bytes/linhas), `.txt` de dados, `.dat`, `.bak`, `luaenc` |
| `tests/pe.sh` | ~90 | 14 casos: invariantes medidos + recusa de entrada inválida + autos-teste |
| `tests/data.sh` | ~110 | 19 casos: idem para formatos nativos, dados e scripts |

## Testes: o que roda e o que não existe

Rodam e passam: `unit` (106/0), `make-sintaxe` (7/0), `net` (34/0), `net-matrix` (36/0),
`pe` (14/0), `data` (19/0), `pe-selftest`/`data-selftest` (4/4 cada, `blocked=1` por definição —
rodar sem a referência é bloqueio declarado, não aprovação), `verify-backup.sh` (9/9 e `FULL=1` 13/13).
**Não existem** (não marcar como aprovados): `golden`, `interop`, `conform`, `fuzz`,
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

## Medidas da R-5 (todas reproduzíveis pelos probes; ver `reports/r5-*.tsv`)

- **PE:** 22 `.exe` = 21 PE32/i386 + 1 PE32+/x86_64 (`PSGuard/Servidor.64.exe`); 49 `.dll` = 45 + 4.
  `.themida` em `GameServer`, `GameServerCS`, `DiscordServer` ⇒ análise estática limitada neles.
  `CreateIoCompletionPort` em 5 binários, `luaL_` em 4; **zero** `PacketSize`/`HEAD_SIZE`/`opcode`
  e zero portas em string (elas vivem nos `.ini`).
- **`.att`:** 276 arquivos, **um único tamanho (65 539 B)**; `bytes[1:3] == ffff` em 276/276;
  `byte0` **não** é constante (`0x00` e `0x20`); corpo 65 536 B = 256 × 256 (hipótese de grade).
- **Modelos:** `.ozj` 106, todos `ffd8` (98 JPEG completos + 5 sem EOI + 3 não classificados);
  `.smd` 8, todos texto `version 1`; `.ozt` 313 com prefixo `0000020000000200`.
- **XOR-3 em `.bmd`:** sustentada só para o banco do MuEditor (`Item.bmd` +66,65 pontos de
  imprimibilidade); **mediana do conjunto −0,16** ⇒ não vale para modelo.
- **Dados:** `ServerList.dat` e `MapServerInfo.dat` **são texto** (`2f2f` = `//`); 39 de 40 `.txt`
  de dados são tab-delimitados, 1 usa vírgula (`CustomGuildReign.txt`); maior Lua 131 560 B /
  7 318 linhas; **nenhum arquivo `.enc` existe** (a auditoria da R-3 contava 3 *matches* de
  `*luaenc*`; hoje são 2: a ferramenta e o `.pdb`).
- **Backups:** 4 `.bak` com cabeçalho `TAPE` (SQL Server) — inventariados, **nenhum restaurado**.

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

# CURRENT_STATE — v2 (estado medido, nao relato)

Atualizado no fim da rodada que corrigiu as defasagens numéricas e reconstruiu o destino (defeitos medidos em ambiente limpo; destino conferido e não publicado). Índice curto e ponto de entrada: `CONTINUITY.md`.

## Mesa da rodada

| campo | valor |
|---|---|
| unidade fechada | **publicação preparada e conferida, push BLOQUEADO por permissão** (403 do GitHub App no destino) + 4 defeitos reais corrigidos, medidos em ambiente reprovisionado |
| fases fechadas antes | R-0…R-5, **R-8** portão único, **R-6** protocolo (camada 3 BLOCKED), **R-7** desempenho |
| próxima tarefa | **destravar a publicação** (ação do proprietário: incluir o repo na instalação do App) e, depois, **`enc`** — cifragem do script Lua do cliente (`NEXT_TASK.md`) |
| branch | `arena/cf1de8ce-muserver` |
| HEAD / remoto | atualizado no fim desta unidade (ver §6 do `CONTINUITY.md`); monorepo `arena/cf1de8ce-muserver` == remoto conferido por `git ls-remote` |
| portão único | `make -s gate` → **18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções, 22 etapas** (medido em ambiente limpo, sem `out/` residual) |
| etapas novas | `golden` 42/42 · `interop` 12/12 (`blocked=1`) · `fuzz` 12/12 · `seguranca` **13/13** · `admin` **24/24** · `lua` 13/13 (`blocked=1`) |
| ferramentas novas | `mu2codec` (CLI do codec real), `mu2fuzz` (fuzzer determinístico), `mu2admin` (console), `interop_probe`, `lua_probe`, `malform_probe` |
| portão de build | `make -s check` → 182 asserções (unit/make-sintaxe/net/pe/data) |
| teste do portão | `make -s gate-selftest` → **19/19**, exit 0 |
| conformidade do v2 | `make -s conform` → **15/15** (camada 1; **não** é compatibilidade) |
| falsificações permanentes | F12–F14 (portão), F15/F16 (R-6), F18/F19 (R-7), **F20/F21** (golden), **F22** (fuzz × codec mutado) |
| capacidade absoluta | **BLOCKED** — 2 vCPUs, cliente e serviço competindo, binário com ASan/UBSan |
| compatibilidade com o original | **não testada, não afirmada** — camada 3 BLOCKED, com causa e caminho de desbloqueio |
| `MuServer/` | inalterada desde `b5b84da`; **6 `.lua` diferem do upload `6eabb45`**; baseline e reversão conferidos por `ref-intacta` 8/8 |
| integridade | `FULL=1 scripts/verify-backup.sh` → 15/15 |

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
| `tests/data.sh` | ~115 | 21 casos: idem para formatos nativos, dados e scripts |
| `tests/run_all.sh` | ~230 | **portão**: 19 etapas, 5 estados, mesa + TSV, log por etapa, grupos próprios, `timeout(1)`, guarda de etapa duplicada |
| `tests/gate_state.sh` | ~210 | 19 casos sobre o próprio portão + falsificações diferenciais F12–F14 |
| `tests/ref_check.sh` | ~60 | integridade de `MuServer/` medida (árvore git + âncoras de conteúdo de 4 PE) |
| `tools/cfg_probe.py` | ~150 | inventário de `.ini`: seções, chaves, portas/IPv4, **segredos redigidos** |
| `tools/wire_probe.py` | ~130 | cliente de conformidade: envia bytes exatos, inclusive quadros inválidos |
| `tools/matrix_check.py` | ~90 | validador da matriz de evidências (linha sem teste reproduzível ⇒ falha) |
| `tests/conform.sh` | ~180 | 15 cláusulas do contrato v2 + F15 diferencial |
| `tests/cfg.sh` | ~120 | 15 casos: endpoints medidos + redação de segredos + autos-teste |
| `tests/bench.sh` | ~210 | **baseline exploratória** (R-7): B1 throughput, B2 agregado, B3 latência, B4 custo por corpo, B5 limite; contabilidade F19 + F18 diferencial |
| `tools/bench_check.py` | ~120 | juiz dos critérios de validade: drift acima ⇒ `BLOCKED`, perda de quadro ⇒ falha real |
| `tools/rtt_probe.py` | ~95 | latência ida-e-volta em passo-trancado, p50/p95/p99, aquecimento descartado, rótulo de limite superior |

## Testes: o que roda e o que não existe

Rodam e passam (medido nesta rodada): `unit` (106/0), `make-sintaxe` (7/0), `net` (34/0),
`pe` (14/0), `data` (21/0), `pe-selftest`/`data-selftest`/`cfg-selftest` (4/4, 4/4, 5/5),
`conform` (15/15), `cfg` (15/15), `matriz` (validador, exit 0), `bench` (15/15),
`ref-intacta` (8/8), `golden` (42/42), `fuzz` (12/12), `seguranca` (13/13), `admin` (24/24),
`interop` (12/12, `blocked=1`), `lua` (13/13, `blocked=1`), `gate`
(**18 PASS, 0 FAIL, 2 BLOCKED, 2 SKIPPED, 339 asserções**), `gate-selftest` (19/19) e
`verify-backup.sh` (`FULL=1` 15/15). `net-matrix` (36/0) e `persistencia` existem mas são
*opt-in* (`GATE_FULL=1`) — no portão aparecem como `SKIPPED`, nunca como `PASS`.
**Neste repositório publicado**, sem a referência `MuServer/`, ficam `BLOCKED`: `pe`, `data`, `cfg`,
`ref-intacta`, `interop` (camada 3) e `lua` — e o portão ali dá **14 PASS / 6 BLOCKED / 281
asserções**.
`e2e` não é suíte separada: os cenários ponta a ponta estão dentro de `tests/net.sh`.

## Cenários de rede cobertos (S1…S13)

Leitura fragmentada · quadros concatenados num único `write` · leitor atrasado com buffers padrão ·
leitor atrasado com janela curta · cliente que não lê e pede de novo (fila cheia) · desconexão limpa ·
desconexão abrupta (RST) · encerramento do serviço com conexão aberta · timeout ocioso · estouro de
`--max-clients` · coerência de métricas · corpo no limite (2048) · quadro inválido (`size=0`) ·
opcode desconhecido descartado sem derrubar a conexão.
Mais as duas asserções da D2-14: leitor atrasado recebe tudo com `queue_full_closes == 0`, e quem não
lê nada e pede de novo produz o fechamento com `close=queue_full` e contador incrementado.

## Estados do portão (R-6) — o que foi testado e o que não foi

`PASS`: `build`, `unit`, `make-sintaxe`, `net`, `pe`, `data`, `pe-selftest`, `data-selftest`,
`conform`, `matriz`, `cfg`, `cfg-selftest`, `ref-intacta`, `golden`, `fuzz`, `seguranca`, `admin`,
`bench`. `SKIPPED` (opt-in `GATE_FULL=1`): `net-matrix`, `persistencia`. `BLOCKED` (exigem a
referência ou o binário de terceiro): `interop`, `lua`. `NOT_IMPLEMENTED`: nenhuma etapa.

## Endpoints medidos na configuração original (R-6)

ConnectServer **44406 TCP / 55557 UDP** · DataServer 55960 · JoinServer 55970 (aponta
`127.0.0.1:55557`) · DiscordServer 55990 · MHPServer 55999 · PSGuard 55998 · SQL 1433.
**Cliente (`MainInfo.ini`) aponta 44405** — divergência registrada como hipótese, não resolvida.
26 valores sensíveis em claro no pacote original; a sonda redige e o teste cobra a redação.
Regra: **resumo ausente é `FAIL`**, e `BLOCKED`/`NOT_IMPLEMENTED` nunca viram `PASS`.

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
- `bench`: critérios de validade declarados desde a R-7; sob host compartilhado pode sair `BLOCKED`
  por drift — bloqueado não é falha nem meta.

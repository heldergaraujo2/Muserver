# ARCHITECTURE — o que existe, como está montado e onde termina

| campo | valor |
|---|---|
| data | 2026-10-13 |
| escopo | árvore `recriado/` (o produto v2) dentro do monorepo `heldergaraujo2/Muserver` |
| estado medido | ver `PROJECT_STATUS.md` (inventário por estado) e `TESTING.md` (resultados) |
| regra deste documento | descreve **só o que existe no repositório**, com o arquivo e o teste que o cobre; o que não existe está listado como tal |

## 1. Em uma frase (e o que isto NÃO é)

O v2 é um **serviço de rede de ensaio (`mud2`) + ferramentas próprias** que implementam, com contrato
documentado e testado, um **enquadramento de quadros próprio do v2**, mais a **instrumentação de
medição** usada para auditar o pacote de referência (`MuServer/`) sem executá-lo.

**Não é** um servidor de MU Online jogável: não há login, contas, personagens, mundos, mapas,
movimento, combate, monstros, inventário, drops, comércio, guildas, eventos, banco de dados nem
protocolo do cliente original. Esses itens aparecem em `PROJECT_STATUS.md` como **AUSENTE** ou
**NÃO VERIFICADO**, com o bloqueio nomeado. Nenhuma compatibilidade com o cliente original é
afirmada — a camada que poderia comprová-la está `BLOCKED` (§6).

## 2. Componentes (arquivo → papel → cobertura)

### 2.1 Produto (o que compila e roda)

| arquivo | linhas | papel | coberto por |
|---|---|---|---|
| `src/wire.c` + `include/mu2/mu2.h` | 170 + 96 | **codec do enquadramento**: `code(2 LE) \| size(2 LE) \| corpo`, `size` = total; perfis `orig` (corpo cru) e `mur0` (corpo sob involução posicional); limites `MU2_MAX_BODY=2048`, `MU2_MAX_FRAME=2052` (D2-03/11/12) | `unit` (106), `golden` (42), `conform` (15), `fuzz` (12) |
| `src/mud2.c` | 590 | **serviço de ensaio**: laço `poll()`, parse incremental (`feed`), escrita com pendência (`drain`), fila de 1 vaga por conexão com fechamento explícito, limites (`--max-clients`, `--idle-ms`, quadro máximo), opcodes `PING`/`ECHO`/`STATS`, motivos de fechamento no log, linha de métricas, `SIGTERM` com encerramento limpo (D2-05/14/16/18) | `net` (34), `seguranca` (13), `bench` (15), `net-matrix` (36, opt-in) |
| `src/mu2ctl.c` | 166 | **cliente de controle**: pede `STATS` e imprime as métricas do serviço | `net`, `conform`, `bench` |
| `tools/mu2codec.c` | 292 | **CLI do codec**, ligada contra o **mesmo `wire.o`** do serviço (não reimplementa) | `golden` (42) |
| `tools/mu2fuzz.c` | 345 | **fuzzer determinístico** com oráculo de invariantes e `--mem-limit-mb` (sem libFuzzer; diferença declarada em D2-33) | `fuzz` (12, 150 000 iterações) |
| `tools/mu2admin.c` | 681 | **console administrativo** (backend): processo separado, **só loopback** (recusa outro endereço na partida), autenticação por token 0600 com comparação em tempo constante, níveis leitor/admin, rotas de leitura; `/publicar` responde `501` **por decisão** (D2-34) | `admin` (24) |

### 2.2 Instrumentação (somente leitura sobre a referência)

| arquivo | linhas | papel |
|---|---|---|
| `tools/{pe,data,cfg,att,mb,lua,enc,interop,malform}_probe.py` | 79–419 | sondas por área: PE dos `.exe`, dados/formatos (`.att`, `.bmd`, `.ozt`, `.ozj`, `.smd`), configuração com **redação de segredos**, camada Lua, cifragem do script de cliente, interop (evidência estática), malformados |
| `tools/{wire,bench,matrix,rtt}_probe.py` / `*_check.py` | 74–132 | conformidade byte a byte, critérios de validade do `bench`, validador da matriz de evidências, sonda de RTT |
| `tools/mu2codec.c` (acima) e `tests/netclient.c` (372) | — | ponte de teste: cliente de carga com controle de socket (`--rcvbuf`, `--sndbuf`, `--no-read-ms`) |

### 2.3 Verificação

| arquivo | linhas | papel |
|---|---|---|
| `tests/run_all.sh` | 266 | **o portão único**: roda as 23 etapas, classifica cada uma (`PASS`/`FAIL`/`BLOCKED`/`NOT_IMPLEMENTED`/`SKIPPED`), grava `out/gate.tsv` + log por etapa |
| `tests/unit.c` | 301 | testes de unidade do codec (106 asserções) |
| `tests/{net,conform,golden,interop,fuzz,seguranca,admin,lua,lua-enc,cfg,data,pe,bench,ref_check,gate_state,make_parse}.sh` | 30–324 | suítes por área (§ `TESTING.md`) |
| `scripts/verify-backup.sh` | 221 | verifica bundle/MANIFEST, restaura por clone e — com `FULL=1` — confere **o que foi publicado** no remoto |
| `tests/golden/quadros.tsv` | — | 38 vetores `(bytes de entrada, bytes de saída, cláusula, origem)` derivados do contrato |

### 2.4 Documentação e evidência

`docs/` (canônicos: `CONTINUITY`, `CURRENT_STATE`, `NEXT_TASK`, `DECISIONS`, `ROADMAP`, `ENVIRONMENT`,
`CHANGELOG`, `ADMIN_CONSOLE` + **este conjunto de auditoria**) e `reports/` (evidência `.tsv`/`.md`
com a convenção de `reports/README.md`).

## 3. Contratos (o que o código promete, e onde está escrito)

| contrato | onde | verificação |
|---|---|---|
| quadro: `code(2 LE) \| size(2 LE) \| corpo`, `size` conta o total | `include/mu2/mu2.h`, D2-11 | `conform` C-01…C-15 byte a byte; `golden` 38 vetores |
| corpo máximo 2048 (`MU2_MAX_FRAME` = 2052) | `mu2.h`, D2-03 | `conform` C-03/C-04; `fuzz` |
| perfil `mur0`: involução posicional do corpo | `wire.c`, D2-12 | `golden`, `conform` C-14 |
| opcodes do serviço: `PING=0x0001`, `ECHO=0x0002`, `STATS=0x0003` — **próprios do v2** | `include/mu2/proto.h`, D2-16 | `conform`, `net` |
| motivos de fechamento: `queue_full`, `client_eof`, `client_hup`, `socket_error`, `write_error`, `bad_frame`, `idle_timeout`, `max_clients`, `shutdown` | `proto.h` | `net` S4–S13, `seguranca` |
| fila de 1 vaga por conexão como backpressure explícito | D2-05/18 | `net` S4, `bench` B5 |
| higiene de log: sem payload, sem caminho absoluto, sem credencial | D2-25 | `seguranca` 9, `admin` 19 |
| redação de segredo na sonda de configuração (por nome **e** por forma) | D2-25 | `cfg` casos 7/8/11/13 |
| só loopback no console administrativo; token obrigatório; falha fechado | `ADMIN_CONSOLE.md`, D2-34 | `admin` 1–24 |

## 4. Fluxo de dados

```
MuServer/ (referência, 10 021 arquivos, SOMENTE LEITURA)      [externo ao v2]
        │  MU_REF_DATA=../MuServer
        ├── tools/*_probe.py  ──►  reports/*.tsv/*.md  (evidência versionada)
        │
recriado/ (o produto v2)
        ├── make -s build  ──►  out/{wire.o, mud2, mu2ctl, netclient, mu2codec, mu2fuzz, mu2admin}
        │        (out/ é ignorado pelo git; nada de binário versionado)
        ├── tests/*.sh  ──►  out/gate.tsv + out/<etapa>/*.log   (rodadas)
        └── scripts/verify-backup.sh  ──►  workspace/backups/{mu2-v2.bundle,MANIFEST.md}
```

O **mesmo** `wire.o` alimenta o serviço, o CLI do codec, o fuzzer e o cliente de teste: o que é
testado é o que é executado, sem segunda implementação (decisão em D2-13).

## 5. Estrutura de diretórios (real, medida)

```
recriado/
  Makefile            contrato de build (alvos = etapas; validado em make-sintaxe)
  README.md           entrada do projeto (aponta para os documentos de auditoria)
  docs/               canônicos + auditoria (este arquivo e os irmãos)
  include/mu2/        mu2.h (contrato do codec/serviço), proto.h (opcodes e motivos)
  src/                wire.c, mud2.c, mu2ctl.c
  tools/              15 ferramentas: 3 CLIs em C + 12 sondas/validadores em Python
  tests/              unit.c, netclient.c, 16 suítes .sh, tests/golden/quadros.tsv
  reports/            evidência .tsv/.md (33 arquivos)
  scripts/            verify-backup.sh
  out/                saída de build e de teste (IGNORADA pelo git)
```

## 6. Onde a arquitetura **termina** (limites declarados)

| limite | consequência | estado |
|---|---|---|
| Sem banco de dados e sem persistência de estado do serviço | não há contas/personagens/progressão; a reinicialização zera tudo | **AUSENTE** (`DATABASE.md`) |
| Sem lógica de jogo (login, mundo, combate, itens, guildas…) | não é servidor jogável | **AUSENTE** (`PROJECT_STATUS.md` §2) |
| Protocolo do cliente original: enquadramento desconhecido; nenhuma captura de tráfego no pacote | não dá para falar com `ConnectServer.exe` sem engenharia nova | **`BLOCKED`** (`PROTOCOLS.md` §5) |
| Opcode do v2 = 2 bytes × espaço de índices do original = 256 ⇒ fator 256× | divergência **medida**, não resolvida | `BLOCKED` para interop; registrado na matriz |
| Serviço single-threaded (0 primitivas de thread) | concorrência por `poll()`; registrado em `seguranca` | decisão, não lacuna |
| Sem TLS/rede externa; escuta em loopback por padrão | não é desenho de produção | por decisão (D-01/D2-34) |
| Sem interface gráfica; `/publicar` = `501` | não há botão sem função nem publicação simulada | por decisão |

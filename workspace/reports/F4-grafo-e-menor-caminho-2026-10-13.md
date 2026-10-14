# F4 — Grafo real de dependências e o menor caminho verificável até o primeiro fluxo

Data: 2026-10-13 · branch `arena/cf1de8ce-muserver` · HEAD de referência: o commit desta rodada
(portões medidos nele; números em §5) · escopo: `recriado/` (projeto v2), com `MuServer/` **somente
leitura**.

Método: cada nó é um arquivo/símbolo que existe; cada aresta é uma relação verificável (chamada,
link, contrato de fio, arquivo lido). Onde a aresta não existe, o relatório diz **que não existe** e
mostra a medição que prova — porque "não integrado" também é um fato e precisa de evidência, não de
impressão.

## 1. O grafo de hoje (arestas medidas)

```
                       ┌──────────────────────────────────────────────┐
   cliente de teste    │  out/mud2   (src/mud2.c, 590 L)              │
   (tests/netclient.c) │  main · accept_new · on_readable · feed      │
        │              │  handle_frame · queue_reply · enforce_idle   │
        │  TCP         │  stats_line · close_conn                     │
        └─────────────►│  conn {fd,id,in,out,last_ms,in_use}          │
           framing     └───────────────┬──────────────────────────────┘
           (contrato v2)               │ usa SÓ o codec
                                       ▼
                    ┌──────────────────────────────────────────────┐
                    │  out/wire.o  (src/wire.c, 170 L)             │
                    │  mu2_frame_encode · mu2_frame_decode ·       │
                    │  mu2_frame_size · mu2_frame_body · profiles  │
                    │  contrato: include/mu2/{mu2.h,proto.h}       │
                    │  códigos: PING 0x0001 · ECHO 0x0002 ·        │
                    │           STATS 0x0003 · MU2_MAX_BODY 2048   │
                    └──────────────────────────────────────────────┘

   ┌───────────────────────────────┐        ┌──────────────────────────────────────────┐
   │  out/mu2dbctl (221 L)         │        │  out/mu2admin (681 L)                    │
   │  CLI de operação do banco     │        │  console local, 127.0.0.1, token 0600    │
   │  criar-conta · autenticar ·   │        │  GET /health · /stats · /gate            │
   │  criar-personagem · mover ·   │        │  POST /publicar → 501 (sem backend)      │
   │  zen · dar-item · transferir  │        │  le_gate(out/gate.tsv)                   │
   └──────────────┬────────────────┘        └───────────────┬──────────────────────────┘
                  │ usa a API                               │ fala STATS pela rede
                  ▼                                         ▼
   ┌───────────────────────────────┐              (fala com out/mud2 via mu2ctl/codec)
   │  out/db.o (src/db.c, 1637 L)  │
   │  abrir/fechar · verify · tx_* │
   │  conta_* · personagem_* ·     │
   │  inv_* · stats_get            │
   │  header include/mu2/db.h      │
   └───────────────────────────────┘
        ▲                 ▲
        │                 │ mesma API (segundo consumidor)
   out/db_test (144)   out/mu2dbcontend (novo, F3)

   ═══════════════ ARESTA QUE NÃO EXISTE (medida) ═══════════════
   src/mud2.c  ──✗──►  mu2/db.h        (`grep include src/mud2.c`: sem db.h)
   $(MUD2)     ──✗──►  $(DBOBJ)        (Makefile:88-89: link é `$(SRV) $(OBJ)`, sem db.o)
   conn        ──✗──►  estado de conta  (struct: fd,id,in,out,last_ms,in_use — nada de sessão)
```

**Conclusão do grafo, em uma frase:** existem **dois blocos maduros e independentes** — rede/codec
(`mud2` + `wire`) e persistência (`db` + CLI + testes) — e **nenhuma aresta entre eles**. O console
admin é a única peça que já atravessa blocos (lê o `mud2` pela rede e o portão pelo arquivo), mas não
toca a persistência.

## 2. Status por ligação (implementado / parcial / ausente / externo)

| # | ligação exigida pelo fluxo | símbolo/arquivo real | estado | teste que cobre hoje |
|---|---|---|---|---|
| 1 | iniciar e configurar o serviço | `main`, `struct opt`, parsing de flags em `src/mud2.c` | **implementado** | `net` 34, `seguranca` 13, `bench` 15 |
| 2 | aceitar conexão, ciclo de vida | `accept_new`, `slots[]`, `close_conn(reason)`, `enforce_idle` | **implementado** | `net` 34, `net-matrix` 36 (opt-in) |
| 3 | enquadrar/validar pacote | `mu2_frame_decode`, `feed` (todos os quadros do buffer), `bad_frame` | **implementado** | `golden` 42, `conform` 15, `fuzz` 12 |
| 4 | identificar sessão (quem é o cliente) | `conn.id` (contador de vaga) **apenas** | **ausente** | — |
| 5 | autenticar (login) | `mu2db_conta_autenticar` existe; **nenhum opcode de login** | **ausente na porta**; existe fora dela | `db` 144, `dbctl` 48 (fora do fluxo de rede) |
| 6 | personagem: criar/carregar/listar | `mu2db_personagem_criar/carregar/listar` | **implementado na biblioteca, ausente na porta** | `db`, `dbctl` |
| 7 | ligar sessão ↔ persistência | falta: `mu2db *` em `mud2`, opcode, campo em `conn` | **ausente** (a aresta não existe, §1) | — |
| 8 | responder e tratar erro | `queue_reply` (vaga única, D2-05), `close_conn(reason)`, contadores `rejects/unknown/queue_full` | **implementado** para os códigos atuais | `net`, `seguranca` |
| 9 | encerrar/desconectar/reconectar | `client_eof`, `idle_timeout`, `socket_error`, `write_error`, `drain` | **implementado** | `net`, `seguranca` |
| 10 | logs e diagnóstico | `logmsg(níveis 0..3)`, `--log-file`, `stats_line`, `GET /stats` do console, `out/gate.tsv` | **implementado** | `admin` 25, `net`, `bench` |
| 11 | desligamento graciosamente / recarga | não existe | **ausente** (declarado em F1 §2, linha 1) | — |
| 12 | compatibilidade com o cliente original | camada 3 do `interop` | **BLOQUEADO** (externo) | `interop` 12/12 com `blocked=1` |

## 3. O menor caminho verificável até o primeiro fluxo

Tudo o que não estiver nesta lista **não é necessário** para o primeiro fluxo (ver §6). O caminho
mínimo, na ordem em que as arestas podem ser provadas:

| passo | ligação | arquivo/símbolo concreto | critério de aceitação (medido) |
|---|---|---|---|
| 1 | serviço abre o banco | `src/mud2.c`: opção `--db ARQ` em `struct opt`, `mu2db_abrir()` na partida; **sem `--db`, comportamento idêntico ao de hoje** | `net` 34, `conform` 15, `golden` 42 **continuam verdes** (prova de que o contrato atual não mudou); `--db` inexistente → recusa nomeada na partida, exit ≠ 0 |
| 2 | login na porta | novo código no **espaço do v2** despachado em `handle_frame` (recomendação em §4) | sem `--db`: resposta de **erro nomeado**, nunca sucesso simulado; com `--db` e senha errada: `MU2DB_E_SENHA` traduzido em erro do protocolo |
| 3 | estado de sessão | campos em `conn` (`conta_id`, `autenticado`) | login duplicado na mesma conexão recusado; conexão fecha → sessão morre (sem estado órfão) |
| 4 | lista de personagens | `mu2db_personagem_listar` | `db` 144 continua verde; resposta traz exatamente os personagens da conta autenticada |
| 5 | movimento validado e persistido | `mu2db_personagem_mover` | mapa/x/y inválidos → erro nomeado; movimento válido → gravado (`fsync` no commit) |
| 6 | reinício e reconexão | parar `mud2`, subir de novo, relogar | a lista e a posição **sobrevivem ao reinício** (é o que transforma "registro" em "servidor") |
| 7 | testes de preservação | etapa nova no portão + `concorrencia`/`db`/`dbctl` inalterados | etapa nova PASS; nenhuma etapa existente regride de estado |

**O único item que falta para os passos 1–7 existirem não é código: é a decisão do contrato do
passo 2.** Todo o resto tem símbolo, arquivo e teste — ou é trivialmente encaixável no que já existe
(`--db` é parsing de flag; os campos de `conn` são aditivos; as três chamadas de persistência já
existem e são testadas).

## 4. Contrato de login: evidência, opções e recomendação (**decisão do proprietário**)

Evidência reunida, sem inventar nada:

- o **contrato v2 de hoje** tem três códigos (`0x0001` PING, `0x0002` ECHO, `0x0003` STATS, em
  `include/mu2/proto.h`) e nada de autenticação. `src/mud2.c:15` declara "não faz… autenticação,
  persistência";
- a **persistência já sabe autenticar** (`mu2db_conta_autenticar`, senha com PBKDF2 + salt por conta,
  testado em `db` 144 e `dbctl` 48) — falta só o transporte até ela;
- o protocolo **do original** (opcode de login do cliente, `JobCode`/`0xF1`) **não está medido**:
  medir exigiria executar o binário protegido, o que está fora de escopo por decisão
  (`interop` camada 3 = **BLOCKED**, sem `wine`/`qemu-i386` e sem autorização). O que existe é o
  enquadramento medido (R-3/D2-11/D2-12), não o dicionário de mensagens.

| opção | o que é | custo | risco | veredito |
|---|---|---|---|---|
| **A — códigos novos no espaço do v2** (`0x0010+`), payload declarado em `proto.h` | estende o contrato do v2 com o que ele já sabe fazer | baixo: 3 códigos + campos em `conn` + etapa de teste | nenhum sobre o que está provado — `conform`/`golden` cobrem que o contrato antigo não mudou | **recomendada** |
| B — implementar o login do **original** a partir de suposição | adivinhar `0xF1` e o formato | alto | afirma compatibilidade sem base — exatamente o que a missão proíbe | **recusar** |
| C — esperar a evidência do original (camada 3) e só então definir | manter a porta sem login | nenhum agora | o primeiro fluxo fica parado numa dependência **externa e bloqueada** | não é caminho para o primeiro fluxo; é o caminho para *compatibilidade* |
| D — canal de controle separado (2ª porta) | contornar o protocolo | médio | duplica o que o console admin já faz, e não é fluxo de jogo | **recusar** |
| E — cliente de teste usar a biblioteca direto | demonstrar "fluxo" sem a porta | baixo | não é o servidor: viola "não classificar interface/teste isolado como servidor funcional" | **recusar** |

**Recomendação objetiva.** Opção **A**, com três condições escritas: (i) os códigos novos ficam num
espaço declaradamente **nosso** (`0x0010+`) e **nunca** são apresentados como equivalentes aos do
original; (ii) a decisão registra que compatibilidade com o cliente original continua exigindo a
camada 3 e que, se ela for medida depois, o mapeamento é trabalho **novo** (o espaço separado existe
para não renumerar nada); (iii) o aceite é o §3 passos 1–7, com reinício no meio. Sem (i)–(iii)
aprovados, **nada é implementado** — e é por isso que esta rodada para aqui, e não inventa opcode.

## 5. O que foi executado nesta rodada enquanto F3/F4 andavam

| item | resultado medido |
|---|---|
| F3 (concorrência `verify`×escrita) | **fechada**: suíte `concorrencia` **27/27**, etapa do portão; escritor real (`tools/mu2dbcontend.c`, novo) com janela determinística; mutação que remove o `LOCK_EX` derruba **9** casos; política comparada e decidida (D2-42) |
| portão após a mudança | `gate` **23 PASS, 0 FAIL, 3 BLOCKED, 2 SKIPPED, 29 etapas, 643 asserções, exit 0** |
| diagnóstico (prioridade 6 da missão) | avaliado e **recusado com motivo**: logar o `peer` do cliente tem valor quase nulo aqui (escuta em loopback: o par é sempre `127.0.0.1`), e a observabilidade que importa — motivo de fechamento, opcode desconhecido, fila cheia — **já existe** (`close=`, `unknown`, `queue_full`) |
| rota nova no console (`/db`) | avaliada e **recusada com motivo**: exige mexer num contrato já desenhado (`docs/ADMIN_CONSOLE.md` §5 tem quatro rotas) e o banco aberto pelo serviço **recusaria** a leitura de qualquer forma (F3 §2). Fica como candidata, não como trabalho feito |

## 6. Explicitamente fora do menor caminho

Monstros/IA/combate/skills/drops, grupos/guildas/missões, comércio, mundo carregado de mapas, Lua em
execução, interface gráfica do console, publicação automática (`POST /publicar`), Execução de binário
original, EncDec do cliente. Nenhum deles é pré-requisito dos passos 1–7 — e cada um tem, no
inventário F1, a linha que diz que está ausente ou bloqueado.

## 7. Para retomar (comando exato)

```sh
# 1) sem decisão de contrato, o que se pode provar hoje (tudo verde, medido nesta rodada):
cd recriado && make -s gate && make -s gate-full && make -s concorrencia
# 2) com a decisão do §4 aprovada, o primeiro passo é o único que não tem dono ainda:
grep -n 'struct opt' src/mud2.c        # onde entra --db
grep -n 'MU2_CODE_' include/mu2/proto.h # onde entram os códigos novos
grep -n 'handle_frame' src/mud2.c       # onde entra o despacho
```

## 8. Limites deste relatório

- Não houve execução de binário do pacote original, nem leitura/escrita em `MuServer/`, nem uso de
  credencial, nem restauração de backup.
- As arestas "ausentes" foram provadas por medição (`grep` de `include`, regra de link do `Makefile`
  que não lista `$(DBOBJ)`, `struct conn` sem campo de sessão) — nenhuma delas por ausência de
  evidência contrária.
- A recomendação do §4 é **recomendação**: a decisão é do proprietário, e este relatório não a toma.

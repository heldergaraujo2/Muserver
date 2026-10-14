# F1 — Inventário do repositório por subsistema, com classificação A–E medida

Data: 2026-10-13 · branch `arena/cf1de8ce-muserver` · HEAD de referência: `375840f` (portões medidos
neste commit) · escopo auditado: `recriado/` (o projeto v2) e, onde indicado, `workspace/` (auditoria)
e o pacote `MuServer/` (**somente leitura**, `tree=fade046`, `alteracoes=0` conferido pelo verificador).

## 1. Método (o que faz um número deste relatório valer)

Toda célula vem de uma destas três fontes, e cada linha diz qual: **(a)** leitura de código com
`grep`/contagem de linhas no commit citado; **(b)** execução de suíte — os resultados de asserção são
os do relatório do portão desta rodada (`recriado/out/gate.tsv`, `make -s gate` e `make -s gate-full`);
**(c)** documento do próprio projeto, indicado na coluna de evidência.

Não entra aqui: nome de arquivo como prova de função implementada; teste simulado apresentado como
sistema real; nem qualquer afirmação de compatibilidade com o cliente ou o servidor original — essa
só existiria com a camada 3 do `interop`, que está **BLOCKED** por falta de `wine`/`qemu-i386` e de
autorização para executar binário protegido.

**Contagem de portão usada nas colunas de teste (medida nesta rodada):** `gate` = **23 PASS, 0 FAIL,
3 BLOCKED, 2 SKIPPED, 28 etapas, 616 asserções somadas, exit 0**; `gate-full` = **25 PASS, 0 FAIL,
3 BLOCKED, 0 SKIPPED, 652 asserções, exit 0**. A soma por etapa é conferível linha a linha no `.tsv`
(704 brutas − 52 dos três BLOCKED, que por convenção não somam).

## 2. Os 15 subsistemas

A missão lista **13** subsistemas; dois deles foram desdobrados por medirem superfícies distintas
(rede ≠ enquadramento; banco ≠ domínio de contas/personagens) e foi acrescentada uma linha para a
**camada de sondagem do pacote de referência**, que existe no repo e não cabia em nenhuma das treze.
O mapeamento está na coluna "origem".

| # | subsistema | classe | implementação medida (arquivos + símbolos) | função | depende de | testes + resultado medido | lacunas / riscos |
|---|---|---|---|---|---|---|---|
| 1 | **init/config/ciclo de vida** | **B** | `src/mud2.c` 590 L (`main`, parsing de `--listen/--port/--profile/--max-clients/--idle-ms/--log-level/--log-file`, `accept_new`, `enforce_idle`); sem arquivo de configuração próprio do v2 | subir, configurar por linha de comando, aceitar conexões, expirar ociosas, encerrar | `wire.c`, `mu2db.h` ausente por escopo | `net` 34, `seguranca` 13, `bench` 15 (todos PASS) | sem serviço/daemon, sem recarga, sem desligamento graciosos; configuração só por flags — declarado, não escondido |
| 2 | **rede: escuta e limites** | **A** | `src/mud2.c` (`MUD2_IN_SLOTS 8192` como teto de `--max-clients`, teto de memória por vaga, `--sndbuf`, conexão expirada por `enforce_idle`) | aceitar N conexões concorrentes com teto declarado e memória medida | sockets POSIX; sem TLS | `net` 34, `net-matrix` 36 (opt-in, PASS no `gate-full`), `bench` 15, `seguranca` 13 | DoS local é o risco declarado em `SECURITY.md` §1: serviço de laboratório, **127.0.0.1**, sem autenticação |
| 3 | **enquadramento e codecs** | **A** | `src/wire.c` 170 L (`mu2_frame_encode/decode`, `mu2_frame_size`, perfis `orig`/`mur0`, chave XOR `k_xor`), `include/mu2/proto.h` (`MU2_CODE_PING/ECHO/STATS`, `MU2_STATS_PREFIX`), `tools/mu2codec.c` 292 L | codificar/decodificar o quadro do v2 e provar o codec pelo **objeto de produção** | `mu2.h`; nada de rede | `golden` 42 (38 vetores versionados + F20/F21), `conform` 15 (C-01…C-15), `pe` 14, `pe-selftest` 4, `fuzz` 12 (150 000 iterações, 0 violações) | contrato é **do v2**; nenhum opcode do original foi inventado nem inferido |
| 4 | **handshake / autenticação / sessões** | **D** | `proto.h` tem **três** códigos (ping/echo/stats) e `mud2.c` não tem estado de sessão além da vaga de conexão | — | — | nenhum teste específico; ausência declarada em `src/mud2.c:15` e `SECURITY.md` §1 | **ausente por escopo**: não há login na porta. Ligar `mud2` ao login da persistência exige **decisão de contrato** (opcode novo) — está na fila do `NEXT_TASK.md`, não é operação de rotina |
| 5 | **contas, personagens e inventário (domínio)** | **A** | `include/mu2/db.h` 154 L (API completa) + `src/db.c` 1637 L: `mu2db_conta_{criar,set_senha,autenticar,existe}`, `mu2db_personagem_{criar,carregar,apagar,listar,nome_valido...}`, `mu2db_inv_{add,mover,remover,contar,listar,transferir}`, `mu2db_personagem_{mover,add_zen,set_zen,add_pontos,up_nivel}` | contas com senha salgada, personagens com atributos e inventário de 64 slots | `src/db.c` (motor abaixo) | `db` **144**, `dbctl` **48**, `persistencia` `ok=11` (PASS no `gate-full`) | formato é **próprio** (`MU2DB01`), **não** o banco do original — afirmação de compatibilidade não existe e não é feita |
| 6 | **mundo, mapas e movimento** | **B** | `mu2db_personagem_mover(db,id,mapa,x,y)` valida e **persiste** a posição; os dados de mapa do pacote são **sondados** (`tools/att_probe.py`) | guardar a posição e permitir consultá-la | `db.c`; dados do pacote em modo leitura | posição: `db` 144 / `dbctl` 48; dados: `data` 21 + `data-selftest` 4 (PASS) | não há simulação de mundo, colisão, walkability nem carregamento de mapa no v2; a sondagem de dados é **leitura**, não gameplay |
| 7 | **monstros, IA, combate, skills, XP e drops** | **D** | nenhum arquivo; nenhum símbolo de monstro/IA/combate/skill/drop | — | — | nenhum teste — e não há teste que finja cobrir | **ausente**: só existe progressão de personagem como **número** (nível, pontos, zen) na persistência |
| 8 | **itens, inventário e comércio** | **B** | inventário: ver #5 (`mu2db_inv_*`, 64 slots, `primeiro_slot_livre`, troca de slots com validação) | guardar/mover/transferir itens entre personagens | `db.c` | `db` 144, `dbctl` 48 (PASS) | **comércio não existe**: sem loja de NPC, sem zen↔item, sem mercado entre jogadores |
| 9 | **grupos, guildas e missões** | **D** | nenhum arquivo; nenhum símbolo | — | — | nenhum teste | **ausente** |
| 10 | **banco: transações, integridade, esquema e concorrência** | **A** (com limites declarados) | `src/db.c`: `crc32c` (poli `0x82F63B78`), `sha256_*` próprio + `ct_eq`, `escrever_completo`/`ler_completo`, `gravar_cabecalho`, `aplica_operacao`, `varre` (recuperação), `trunca_ate`, `estado_rebuild`, `mu2db_tx_{begin,commit,rollback}`, `grava_ops`, `registra`, `mu2db_verify` (com `LOCK_SH\|LOCK_NB`), `MU2DB_MAGIC "MU2DB01"`, `MU2DB_SCHEMA_VERSION 1` | journal com CRC por registro, commit atômico, recuperação de estado, verificação sem aplicar nada, exclusão entre verificação e escrita | nada externo (sem SQLite/openssl) | `db` **144**, `dbctl` **48**, `sincronia` 15, `persistencia` `ok=11` (PASS) | (i) **sem migração automática de esquema** — versão antiga é recusada nomeada (D2-41), `REG_MIGRACAO` existe e ninguém o grava; (ii) queda de energia **não** é reproduzível aqui: o texto afirma "o `fsync` foi chamado antes de a API voltar", nunca "o dado sobreviveu"; (iii) `verify` e escrita se **excluem** (custo medido, `dbctl` 33–48) |
| 11 | **Lua e configuração do pacote** | **B** | `tools/cfg_probe.py` (19 `.ini`, 655 pares, **29 redigidos**), `tests/regressao_lua.sh` 289 L, `ref_check.sh` 105 L, patch dos 6 `.lua` | ler a configuração do pacote sem vazar segredo; regressão **estática** dos 6 scripts | pacote `MuServer/` (leitura) | `cfg` 16, `cfg-selftest` 5, `regressao-lua` **53**, `ref-intacta` 8 (PASS); `lua` 13 e `lua-enc` 27 = **BLOCKED** | execução de Lua **não observada**: sem interpretador no host, e o material cifrado do cliente não é contornado — declarado como limite, não como sucesso |
| 12 | **admin, logs, métricas e segurança** | **A** | `tools/mu2admin.c` 681 L (`carrega_creds` com exigência de modo **0600**, papéis `leitor\|admin`, comparação de token em tempo constante, `rota_valida`, `responde`, `erro_json`, `le_gate`), rotas `GET /health`, `GET /stats`, `GET /gate`, `POST /publicar` → **501** com motivo | operar/observar o serviço por HTTP **só em loopback** | `mud2` (métricas), `out/gate.tsv` | `admin` **25** (PASS), `seguranca` 13 | sem token válido o servidor **não sobe** (fail closed); `/publicar` não finge sucesso — não há alvo autorizado de publicação |
| 13 | **build, testes, artefatos e CI** | **A** para a suíte reprodutível / **D** para CI hospedado | `Makefile` com alvos por etapa + `gate`/`gate-full`; `tests/*.sh` (**21** suítes), `tests/run_all.sh` 271 L; snapshot orphan + `workspace/backups/mu2-v2.bundle` + `MANIFEST.md` conferidos por `scripts/verify-backup.sh` | reconstruir e reprovar regressão com um comando, e manter cópia independente restaurável | `gcc`, `bash`, `python3` (opcional por etapa) | `gate` 23 PASS/616 asserções/exit 0; `gate-full` 25 PASS/652/exit 0; `gate-selftest` 21; `FULL=1 verify-backup.sh` **15/15** | **não existe `.github/workflows`** (medido: nem no monorepo nem em `recriado/`): a reprodutibilidade é local, por `make` — quem clonar precisa rodar o portão à mão |
| 14 | **integração com o cliente original** | **E** (bloqueado) | `tests/interop.sh` 115 L, 3 camadas; camadas 1–2 usam **nosso** codec contra vetores derivados do contrato | provar interoperação | `wine`/`qemu-i386` + autorização de execução | `interop` 12/12 com **camada 3 BLOCKED** | **nenhuma compatibilidade com o cliente original está demonstrada**, e nada neste inventário a sugere; desbloqueio é dependência **humana e de ambiente** |
| 15 | **sondagem do pacote de referência (auditoria)** | **B** | `workspace/tools/*.py` (preflight, `verifica_doc_sem_segredo.py`), `recriado/tools/{cfg,att,enc}_probe.py`, `workspace/tests/run_all.sh` | ler o pacote original **sem modificá-lo** e sem vazar segredo; medir, não supor | `MuServer/` somente leitura | `data` 21 + `data-selftest` 4; varredura anti-vazamento na porta (`por_valor=0`, `por_forma=16` triadas); `run_all.sh` exit 0, 6 etapas PASSOU | os probes descrevem o pacote; **não** reimplementam gameplay. Risco conhecido e aberto: **P07** (segredos/PII no histórico do git) — ação do proprietário |

## 3. Placar

| classe | quantidade | quais |
|---|---|---|
| **A** — implementado e comprovado | **6** | rede/limites; enquadramento/codecs; contas-personagens-inventário; banco (com limites declarados); admin/logs/métricas; build/testes/artefatos |
| **B** — parcial, limite declarado | **5** | ciclo de vida/config; mundo-mapa-movimento; itens/comércio; Lua/configs; sondagem do pacote |
| **C** — só infra ou doc | **0** | — |
| **D** — ausente | **3** | handshake/auth/sessões; monstros-IA-combate-skills-XP-drops; grupos/guildas/missões |
| **E** — bloqueado | **1** | integração com o cliente original (camada 3) |

Observação que o placar esconde: a linha 1 é **B** não por defeito, e sim porque o v2 **não declara**
ser serviço instalável; a linha 13 é **A** para a suíte e **D** para CI hospedado — as duas leituras
estão na mesma linha, de propósito.

## 4. O que este inventário muda no plano

1. **A lacuna-mestra continua sendo a mesma, agora com nome preciso:** a persistência (#5/#10) é a
   parte mais madura do projeto e **não está ligada a nada** — `mud2` (#2) não tem sessão (#4). O
   primeiro servidor funcional passa por **uma** decisão de contrato (opcode de login), não por
   escrever mais biblioteca.
2. **Os ausentes (D) são ausentes de verdade** e não têm teste que os disfarce: onde não há teste,
   este relatório diz "nenhum teste" em vez de herdar verificação de vizinho.
3. **O trabalho paralelizável sem cliente original** está todo nas linhas A/B; o da linha 14 está
   parado em dependência humana, e nada nele será contornado (execução de binário protegido está
   fora de escopo por decisão).

## 5. Limites deste relatório

- Não houve execução de binário do pacote original, nem alteração de `MuServer/`, nem uso de
  credencial, nem restauração de backup de banco.
- As linhas 7, 9 e 14 são **negativas**; um inventário que só listasse o que existe daria a impressão
  falsa de completude. Elas estão aqui exatamente para impedir isso.
- Contagens de asserção são as do portão deste HEAD; rodada futura deve **remedir**, não citar.

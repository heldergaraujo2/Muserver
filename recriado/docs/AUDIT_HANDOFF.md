# AUDIT_HANDOFF — transferência para auditoria técnica independente

| campo | valor |
|---|---|
| data | 2026-10-13 |
| repositório | **https://github.com/heldergaraujo2/Muserver** (público) |
| branch da consolidação | **`arena/cf1de8ce-muserver`** (PR **#1** aberto para `main`; **não** mergeado — decisão do proprietário) |
| branch principal do repositório | `main` @ `6eabb45` (o upload do pacote original; **nada desta auditoria foi empurrado para lá**) |
| commit dos documentos de auditoria | **`578e7e1`** ("Consolidacao para auditoria independente: documentos de estado, arquitetura e limites") |
| tag anotada do estado consolidado | **`auditoria-2026-10-13`** — aponta para o último commit da consolidação; `git tag -n99 auditoria-2026-10-13` mostra a mensagem, e o relatório da rodada traz a leitura de volta do remoto (§13) |
| commit de confirmação/leitura de volta | em `workspace/migracao/RELATORIO-CONSOLIDACAO-AUDITORIA-2026-10-13.md` §13 (SHA remoto lido com `git ls-remote`) |
| como clonar | `git clone https://github.com/heldergaraujo2/Muserver.git && cd Muserver && git checkout arena/cf1de8ce-muserver` |
| tamanho do que está versionado | `MuServer/` 10 021 arquivos (~615 MB) + `recriado/` 87 rastreados + `MuserverRecriado/` 174 + `workspace/` |

## 1. Objetivo desta transferência

Dar a um auditor independente, sem depender de relato: (a) onde está o quê; (b) **o que foi
implementado, testado e verificado de fato**; (c) o que é pacote de terceiros; (d) o que está
bloqueado e por quê; (e) como reproduzir cada número em minutos. Se este documento divergir do
código, dos testes ou do git, **a evidência vence** — e a divergência deve ser reportada como
achado, não escondida.

## 2. Mapa de leitura (ordem sugerida)

| # | documento | para quê |
|---|---|---|
| 1 | `docs/PROJECT_STATUS.md` | inventário por estado (`IMPLEMENTADO`/`TESTADO`/`AUSENTE`/`BLOCKED`…) — **leia primeiro** |
| 2 | `docs/ARCHITECTURE.md` | o que cada arquivo é, contratos, onde a arquitetura termina |
| 3 | `docs/TESTING.md` | os números medidos hoje, etapa por etapa, e o que **não** foi testado |
| 4 | `docs/PROTOCOLS.md` | protocolo do v2, o que foi medido do original e os 6 desconhecidos |
| 5 | `docs/DATABASE.md` | banco: o que o pacote exige e por que o v2 não tem persistência |
| 6 | `docs/DEPENDENCIES_AND_LICENSES.md` | dependências, licenças e **pendências de verificação** |
| 7 | `docs/SECURITY.md` | modelo de ameaças, controles do v2 e **incidentes do pacote original** |
| 8 | `docs/ROADMAP.md` | o que falta, em ordem de dependência real |
| 9 | `docs/BUILD_AND_RUN.md` | compilar, rodar, testar (com os códigos de saída) |
| 10 | `reports/auditoria-rastreabilidade.md` | rastreabilidade fase por fase (com o bloco de atualização de 2026-10-13) |
| 11 | `reports/r6-interop-relatorio.md`, `reports/rf-lua-protocolo.md`, `reports/enc-cifragem-lua.md` | as três investigações de fundo (interop, camada Lua, cifragem) |
| 12 | `docs/CONTINUITY.md`, `docs/DECISIONS.md`, `docs/CHANGELOG.md` | continuidade, as 39 decisões `D2-xx` e o histórico por rodada |

## 3. Estado real em uma página

- **O que o v2 é**: serviço de ensaio (`mud2`) + codec com contrato próprio + CLI + console local +
  fuzzer + sondas de auditoria do pacote. 23 etapas de portão, 339 asserções contadas (391 somadas),
  tudo medido (`docs/TESTING.md`).
- **O que o v2 não é**: servidor de MU Online. Login, personagens, mundo, combate, itens, guildas e
  persistência são **`AUSENTE`** (`docs/PROJECT_STATUS.md` §2).
- **Compatibilidade com o cliente original: não verificada, não afirmada.** A camada de
  interoperabilidade real está `BLOCKED` com causa nomeada e mecanismo de evidência pronto
  (`docs/PROTOCOLS.md` §4).
- **Segurança**: no v2 os controles são medidos por teste; no **pacote original** (pré-existente,
  commit `6eabb45`) há **incidentes reais**: credenciais em claro no histórico e 4 backups de banco
  com PII de jogadores publicados — ações do proprietário listadas em `docs/SECURITY.md` §5.
- **Licenças**: não há arquivo de licença legível em nenhum lugar do repositório; o trabalho próprio
  não tem licença declarada e há componentes comerciais/de terceiros no pacote
  (`docs/DEPENDENCIES_AND_LICENSES.md`).

## 4. Evidência principal (o que olhar para contestar)

| evidência | onde | como reproduzir |
|---|---|---|
| mesa do portão (23 etapas: estado, asserções, falhas, blocked, exit, ms) | `recriado/out/gate.tsv` (regenerado a cada execução; `out/` é ignorado pelo git) | `cd recriado && make -s gate` |
| resultado de cada suíte | `recriado/reports/*.tsv` (versionados) | `make -s check`, `make -s conform`, … |
| conformidade byte a byte | `reports/r6-conform.tsv` | `make -s conform` |
| matriz de rede completa (100 config × 5 reps por perfil) | `reports/net-orig.tsv`, `reports/net-mur0.tsv` | `make -s net-matrix` |
| investigação da cifragem do Lua | `reports/enc-cifragem-lua.md` + `reports/enc-probe.tsv` | `make -s lua-enc` |
| interop (camadas) | `reports/r6-interop-relatorio.md`, `reports/r6-interop.tsv` | `make -s interop` |
| backup restaurável | `workspace/backups/{mu2-v2.bundle,MANIFEST.md}` | `FULL=1 bash recriado/scripts/verify-backup.sh` |
| cópia publicada independente | `MuserverRecriado/` (174 arquivos) | `cd MuserverRecriado && bash scripts/verify-backup.sh` |

## 5. Achados que o auditor deve tratar como prioritários

1. **Credenciais e PII no pacote original** (`docs/SECURITY.md` §1–§2): token de bot Discord, senha
   global do JoinServer, serial/HWID, `EncDecKey1/2` e 4 `.bak` de banco (50 373 632 B). O histórico
   do git **já publicou** os valores: a mitigação real é **rotacionar** — tarefa do proprietário.
2. **Ausência de licença** no trabalho próprio e origem/licença não verificadas de deps de terceiros.
3. **`GATE_FULL=1` tem interação entre etapas** (regravação dos TSVs da matriz antes da checagem de
   árvore limpa): ver `docs/TESTING.md` §3 — documentado, com comando de contorno; correção definitiva
   (trocar a ordem ou publicar a matriz por alvo separado) é melhoria pendente, **não** aplicada para
   não alterar contrato testado nesta consolidação.
4. **Divergência de porta** do cliente (44405) contra o ConnectServer medido (44406): aberta, sem
   captura de tráfego não se resolve (`docs/PROTOCOLS.md` §3.1).
5. **Formatos não decodificados**: `.ozt`, layout do `.bmd`, semântica do `.att`, algoritmo da
   cifragem dos `.lua` — o que foi medido está dito; o resto é desconhecido.

## 6. Limites desta consolidação (declarados)

- **Nenhum binário do pacote foi executado** — nem por mim, nem por nenhuma etapa automatizada;
  `interop` camada 3 e a cifragem (`enc`) ficam `BLOCKED` em vez de "tentar e falhar".
- **Nada foi restaurado** (nem os `.bak` de banco), **nada foi neutralizado** (Themida/VMProtect),
  **nada foi apagado**: `MuServer/` está intacta (tree `fade0461…`, `make -s ref-intacta` 8/8).
- Os números de desempenho são **baseline exploratória** em 2 vCPUs com sanitizadores — **não** são
  metas e não comparam com o servidor original (que não foi executado).
- Host: sem `wine`/`qemu-i386`, sem interpretador Lua, sem `clang`/`valgrind` — cada ausência aparece
  como `BLOCKED` na mesa, com a causa.
- Esta consolidação **não** reescreveu o projeto: o código do v2 não foi alterado (a rodada de
  auditoria adiciona documentos, um alvo `lua-enc` no Makefile e as evidências da etapa `enc` já
  publicada antes).

## 7. Perguntas que o auditor pode (deve) fazer — e onde a resposta está

| pergunta | onde |
|---|---|
| "quantas asserções, e quantas falharam?" | `docs/TESTING.md` §2 + `out/gate.tsv` |
| "isto fala com o cliente original?" | `docs/PROTOCOLS.md` §4 — **não**, `BLOCKED` |
| "onde está o login/personagem/banco?" | `docs/PROJECT_STATUS.md` §2, `docs/DATABASE.md` |
| "algum teste foi afrouxado para passar?" | `docs/DECISIONS.md` D2-27…D2-30 (três casos onde o teste foi corrigido na raiz) e `docs/TESTING.md` §4 (falsificações) |
| "o portão sabe falhar?" | `make -s gate-selftest` (19/19, F12–F14) |
| "dá para restaurar o backup?" | `FULL=1 bash recriado/scripts/verify-backup.sh` (clone real) |
| "o que não foi testado?" | `docs/TESTING.md` §5 |
| "o que é código original vs terceiros?" | `docs/DEPENDENCIES_AND_LICENSES.md` §1–§2 |

## 8. Próximas prioridades propostas (o auditor decide, com base na evidência)

1. Tratar o vazamento do pacote original (rotacionar credenciais; tratar `.bak` como incidente).
2. Decidir licença do trabalho próprio e verificar autorização de redistribuição do pacote.
3. `interop` real (ambiente PE32/i386 + autorização) — destrava protocolo, formatos e validação do cliente.
4. Interpretador Lua — sintaxe/execução dos 148 scripts.
5. Persistência: decisão nova (tecnologia, migrações, teste de reinício) — pré-requisito para
   qualquer lógica de jogo.
6. Correção da interação `net-matrix` × `persistencia` no `GATE_FULL=1` (melhoria pequena, com teste).

O detalhamento, com dependências, está em `docs/ROADMAP.md` (seção "Etapas restantes").

# Tratamento dos riscos P0 — resposta ao auditor independente (2026-10-13)

**Escopo desta rodada:** verificar e tratar riscos P0. **Não** desenvolver funcionalidade, **não**
reescrever arquitetura, **não** alterar histórico Git. **Nenhuma dessas ações foi executada:**
nenhum `push --force`, nenhuma reescrita de histórico, nenhuma tag/branch movida, nenhum arquivo
apagado, nenhuma permissão ou visibilidade de repositório alterada, nenhum backup restaurado, nenhuma
credencial testada, nenhuma implementação de sistema de jogo iniciada.

---

## 1. Estado do repositório: SHAs verificados e a divergência explicada

Comandos: `git ls-remote origin`, `gh api repos/…`, `gh pr view 1`, `git merge-base --is-ancestor`.
Leitura **direta do remoto**, feita nesta rodada (o clone local também foi conferido por hash).

| Referência | Valor verificado |
|---|---|
| `refs/heads/arena/cf1de8ce-muserver` (HEAD do trabalho) | **`44055a933a37e99f7d91fa78e6897861e703d338`** |
| `refs/heads/main` (= `HEAD` simbólico do repo) | **`6eabb45b9e7939a3061f4757ed6791efef7c5c3b`** (inalterada) |
| `refs/tags/auditoria-2026-10-13` | objeto de tag **`cb880d78c8aaaafba91ac34562b6b7da921fb629`**, tipo `tag` (anotada) |
| …commit apontado pela tag (`^{}`) | **`2d121d9cc39d0eb167c062904506e494d007304f`** |
| PR #1 | **OPEN** (`isDraft=false`), base `main`, head `arena/cf1de8ce-muserver`, `mergeable=MERGEABLE`, `mergeStateStatus=CLEAN`, `mergedAt=null` |
| Repositório | `private=false`, `visibility=public`, `default_branch=main`, `size=138 414 KB`, `pushed_at=2026-10-13T15:48:16Z` |

### Por que a entrega citou `44055a9` e o relatório registra `2d121d9`

**Não há contradição nem referência movida — são o mesmo estado em dois instantes:**

- A tag `auditoria-2026-10-13` foi criada quando o tip era `2d121d9` (o relatório §13 registra esse
  instante, corretamente).
- Depois dela subiram **2 commits**, ambos descendentes diretos: `4d4a6d1` (preenchimento do §13 com a
  leitura de volta da publicação) e `44055a9` (achado desta consolidação: reprodução em clone limpo e o
  efeito do clone raso).
- Prova de ancestralidade medida: `git merge-base --is-ancestor 2d121d9 44055a9` → **verdadeiro**,
  distância **2 commits**. Ou seja, `2d121d9` **está contido** em `44055a9`.
- **Nada foi movido**: `git rev-parse` da tag continua resolvendo para `2d121d9`, e a branch continua
  exatamente onde foi publicada. Nenhuma ação foi feita para "fazer os valores coincidirem".

### Evento de infraestrutura ocorrido nesta rodada (declarado)

O ambiente foi reprovisionado e o `.git` local reapareceu no commit-base `6eabb45` (branch local em
`6eabb45`, tag presente no remoto). **O conteúdo em disco estava íntegro.** Conferência feita antes de
qualquer escrita: para os **10 402 arquivos** da referência remota, comparamos `git hash-object` do
arquivo em disco com o blob do remoto → **IGUAIS=10 402, FALTANDO=0, DIFERENTES=0, EXTRAS=0**.
Recuperação usada (a mesma já documentada): `git fetch` + `git reset --mixed origin/arena/cf1de8ce-muserver`
— **só índice e HEAD, nenhum arquivo tocado** (`--hard` nunca é usado neste projeto). Depois disso:
`HEAD` local = `44055a9`, árvore limpa.

### Divergência conhecida entre `main` e a branch, em `MuServer/`

A branch altera **6 arquivos `.lua`** de `MuServer/` em relação ao upload (`ScriptMain.lua` ×3,
`ProtocolCore.lua`, `ScriptCore.lua`, `DataBase.lua`), todos com **originais preservados** em
`workspace/changes/originals/` (6 arquivos) e **monitorados pelo portão** (etapa `ref-intacta`, casos 7
e 8). A árvore `MuServer` da branch é `fade046…`. Nada mais de `MuServer/` difere.

---

## 2. Inventário seguro (sem valores)

Documento completo: **`workspace/seguranca/INVENTARIO-EXPOSICAO-2026-10-13.md`** (e o artefato
`workspace/seguranca/inventario-exposicao-2026-10-13.tsv`, 107 linhas `categoria → caminho → linha`).
Resumo:

- **Credenciais em claro, com valor não vazio:** `PSGuard/PSGG.ini` (21 chaves: usuário/senha/host/banco,
  licença, `crclicenca`, 4 `key*cabal`, `singletoken`…), `JoinServer/JoinServer.ini` (`globalpassword` +
  connection string com senha), `DiscordServer/DiscordServer.ini` (**token de bot**, faixa ≥32),
  `MHPServer/MHPServer.ini` (`clientserial`, `encdeckey1/2`), `Tools/Editores/Editor de conta
  Muemu/config.ini` e `Tools/Editores/MuEditor/config.ini` (usuário+senha de banco),
  `Tools/Gerador de Main/MAIN_INFO*/MainInfo.ini` (serial), 4× `GameServerInfo - Common.dat`
  (serial + hardware id). `DataServer/DataServer.ini` traz só o **nome do DSN**.
  `MAIN_INFO v41 …/Premium/Settings.ini` tem `user`/`password` **presentes e vazios** (falso positivo).
- **Credenciais em logs:** `SpeedServer/GameServer/LOG/COMMAND_LOG/*.txt` (5 arquivos) registram
  `[CommandSetParty][conta][personagem] - Password: <valor>` — senha de party em texto claro com
  identificadores de jogador.
- **PII/dados de terceiros:** **4 backups SQL Server** (`DB/*.bak`, 50 373 632 B = 48,0 MiB) com
  contas/hashes — **conteúdo não inspecionado**; **34 minidumps** (`.dmp`, 9,0 MB) com memória de
  processo; **2 793 arquivos de log** (≈216 MB) com **330 085 linhas de IP** em 1 076 arquivos;
  `JoinServer/LOG_ACCOUNT` com IP + identificador de máquina por evento.
- **PII introduzida por nós:** `recriado/reports/r6-config.tsv` e `MuserverRecriado/reports/r6-config.tsv`
  contêm **1 e-mail idêntico** ao de `PSGuard/PSGG.ini` (comparação booleana — o valor não foi exibido).
- **Confirmado como autoritativo:** o scanner pré-existente `workspace/tools/muserver_preflight.py`
  (check P07) — **22 ERRO / 19 AVISO / 16 OK / 1 INFO**, com valores **redigidos por projeto**; testamos
  que nenhum valor real vaza na saída.
- **Onde está exposto:** no commit de upload `6eabb45`, na branch **`main`** e em todo o histórico do
  repositório **público** — confirmado por `git rev-parse origin/main:<caminho>` para 5 arquivos
  sensíveis, idênticos ao tip.

---

## 3. Plano de contenção e remediação

### Fase 1 — Rotação na origem (obrigatória, independente do Git; **só o proprietário pode executar**)

Fundamento: remover o segredo do último commit/do histórico **não invalida** o valor já exposto; quem
tiver cópia continua usando. Rotacionar **primeiro**, limpar depois.

| # | Segredo exposto | Rotacionar onde (origem) | Responsável |
|---|---|---|---|
| 1 | senha do usuário SQL em `PSGuard/PSGG.ini` (e usuário/host/banco) | instância SQL Server que serve os bancos do servidor (nomes já visíveis nos arquivos `DB/*.bak` e `*.reg`) → trocar senha e/ou usuário; revisar logins e permissões | proprietário / quem administra o banco |
| 2 | senha dentro de connection string (`JoinServer/JoinServer.ini`, `Editor de conta Muemu/config.ini`) | DSN do Windows (ODBC) + usuário no SQL Server | proprietário |
| 3 | `globalpassword` do JoinServer | `JoinServer.ini` **e** todo componente que compartilha o valor (GameServer/ConnectServer) — trocar em conjunto | proprietário |
| 4 | **token do bot Discord** (`DiscordServer.ini`) | Discord Developer Portal → *Bot → Reset Token* (o antigo morre na hora) | proprietário (conta do bot) |
| 5 | licenças/seriais PSGuard, MHP (`licenca`, `crclicenca`, `clientserial`, `encdeckey1/2`) | fornecedor comercial → **reemissão**; se o fornecedor não reemitir, considerar o produto comprometido | proprietário + fornecedor |
| 6 | senhas dos editores (`MuEditor`, `Editor de conta Muemu`) | contas no SQL Server usadas por essas ferramentas | proprietário |
| 7 | backups/logs com dados de jogador | não há "rotação": tratar como **incidente de dados** (§Fase 3) e avaliar comunicação (LGPD) com apoio jurídico | proprietário |
| 8 | IPs de servidores expostos em logs | revisar firewall/regras de rede e credenciais de painel de hospedagem | proprietário / provedor |

### Fase 2 — Tampão no repositório, **sem reescrever histórico** (exige autorização; nada foi feito)

1. **Redigir a PII nossa**: substituir o e-mail em `recriado/reports/r6-config.tsv` e no espelho
   `MuserverRecriado/reports/r6-config.tsv` por marcador, mantendo a linha e a explicação (não se perde
   evidência: o valor permanece no arquivo de origem `MuServer/PSGuard/PSGG.ini`). Regenerar os bundles
   que hoje carregam essa cópia (`workspace/backups/mu2-v2.bundle`, cópia em `MuserverRecriado/...`).
2. **Endurecer o que é nosso**: manter a regra já vigente de nunca versionar segredo e documentar as
   variáveis de configuração necessárias com **exemplo seguro** (`SECURITY.md` já traz a regra e o
   inventário A1; falta o bloco de variáveis/exemplo).
3. **Não tocar `MuServer/`** (instrução vigente): a sanitização desses 19 `.ini`/`.dat` — trocar valor
   por `COLE_AQUI_VIA_VARIAVEL_DE_AMBIENTE` — **só com autorização explícita**, porque altera a
   referência histórica. Ela não remove o que já foi publicado; serve para o pacote não voltar a vazar.
4. **Restringir a exposição dos backups e logs**: (a) eles não podem voltar a ser versionados —
   `workspace/tools/untrack_artifacts.sh` (já existe, **dry-run por padrão**) tira do índice sem apagar
   do disco; (b) manter a única cópia de trabalho em armazenamento **privado** (decisão do proprietário:
   onde/como); (c) se o repositório continuar público, mover `MuServer/` para fora dele (Fase 3).

### Fase 3 — Remoção estrutural (só com autorização explícita e janela combinada)

Três desenhos, com consequências honestas:

| Opção | O que resolve | Custo/risco |
|---|---|---|
| **A. Reescrever o histórico** (`git filter-repo`/BFG) removendo `MuServer/DB/*.bak`, `*.dmp`, `LOG*` e configs sensíveis de todos os commits | tira o material do repositório **e** do histórico | exige **force-push** (nunca feito até hoje); **quebra clones/forks**; PR #1 precisa ser refeito; tag precisa ser reemitida; bundles/snapshots precisam ser regenerados; o GitHub pode manter objetos inalcançáveis acessíveis por API/tempo até o GC; **não** alcança cópias já baixadas |
| **B. Manter histórico e publicar só o v2** (repositório público contendo apenas código próprio + docs; `MuServer/` preservado numa cópia privada do proprietário) | tira do público o material sensível **sem** reescrever nada nem quebrar clonés | `main` atual não pode continuar pública com `MuServer/`; é preciso decidir o destino do `MuServer/` (privado/local/outro host) |
| **C. Tornar o repositório privado** | estanca a exposição nova imediatamente | não desfaz o que já foi baixado; muda a visibilidade — **ação do proprietário, vedada ao agente sem autorização** |

**Recomendação técnica (não decisão):** **B**, isoladamente ou combinada com C — é a de menor risco
operacional e a única que não depende de purge em clones de terceiros. A opção A é a mais completa
quanto ao histórico, porém a mais disruptiva e insuficiente sozinha (rotação continua obrigatória).

### Fase 4 — Prevenção (após decisão)

- GitHub: ligar **secret scanning** e **push protection** (exige admin — não temos; a API de
  `security_and_analysis` respondeu *não disponível*).
- Pré-commit no fluxo de trabalho usando o scanner que já existe (`muserver_preflight.py`, checks P07/P08),
  com o cuidado de não bloquear o trabalho legítimo; e `.gitignore` ampliado no repositório **novo**
  (ignorar `*.bak`, `*.dmp`, `LOG*`, `.tmp`).
- Política de dados escrita: backup/log/dump **nunca** entram no VCS; dados de jogador seguem regra
  própria (retenção, cópia cifrada, acesso restrito).

**O que explicitamente não recomendo:** restaurar os `.bak` "para ver o que tem dentro" numa máquina
compartilhada, ou abrir os dumps fora de ambiente controlado. Se o inventário interno for necessário,
fazer em ambiente isolado, com finalidade e autorização escritas.

---

## 4. Decisões que dependem do proprietário (nada foi feito sem isto)

1. **Modelo de contenção** — A (reescrever histórico + force-push), B (público só com o v2),
   C (tornar privado) ou combinação. *Recomendação: B e/ou C; A apenas se o histórico purgado for
   requisito.* **Sem essa decisão, os arquivos sensíveis continuam públicos.**
2. **Autorizar a rotação da Fase 1** e indicar quem executa (o agente **não** tem e **não** deve ter as
   credenciais; não é possível rotacionar por conta própria).
3. **Autorizar a redação da PII nossa** (`r6-config.tsv` ×2) e a regeneração dos bundles afetados.
4. **Autorizar (ou vetar) a sanitização dos 19 `.ini`/`.dat` do pacote `MuServer/`** — hoje vedado pela
   instrução de não modificar `MuServer/`.
5. **Autorizar as correções de teste** do §5-A/B abaixo (clone raso e `net-matrix`×`persistencia`),
   com os critérios de aceitação já fixados.
6. **Autorizar tag adicional** no tip (`44055a9`) para o marco desta etapa — a tag `auditoria-2026-10-13`
   **não será movida**; sem autorização, fica sem tag nova.
7. **Licenciamento** (ver §5-C): criar `LICENSE`/`NOTICE` na raiz declarando a licença do **código
   próprio** (pergunta direta: pretende abrir sob MIT/Apache, ou manter "todos os direitos reservados"?),
   a atribuição do `json.lua` (MIT, rxi) e o aviso de que `MuServer/` é material de terceiros/proprietário.
8. **PR #1** — manter aberto, mergear ou fechar. **Não mergeei** e não vou mergear sem ordem.
9. **LGPD/incidente** — decidir registro interno e eventual comunicação (com apoio jurídico). O agente
   não é controlador dos dados.
10. **Inventariar o conteúdo dos `.bak`?** *Recomendação: não nesta etapa* — se autorizado, apenas em
    ambiente isolado e com finalidade declarada.

---

## 5. Evidências de cada verificação

| # | Verificação | Comando | Resultado medido |
|---|---|---|---|
| 1 | HEAD da branch no remoto | `git ls-remote origin` | `44055a933a37e99f7d91fa78e6897861e703d338` |
| 2 | Alvo da tag anotada | `gh api …/git/ref/tags/…` + `gh api …/git/tags/cb880d78…` | objeto `cb880d78…`, tipo `tag`, aponta `2d121d9cc39d0eb167c062904506e494d007304f` |
| 3 | Divergência 44055a9 × 2d121d9 | `git merge-base --is-ancestor 2d121d9 44055a9` + `git rev-list --count` | ancestral **verdadeiro**, distância **2** (`4d4a6d1`, `44055a9`) |
| 4 | `main` | `git ls-remote origin refs/heads/main` | `6eabb45b9e7939a3061f4757ed6791efef7c5c3b` (inalterada) |
| 5 | PR #1 | `gh pr view 1 --json …` | OPEN, base `main`, MERGEABLE/CLEAN, `mergedAt=null` |
| 6 | Integridade do disco após reprovisionar | `git ls-tree -r` + `git hash-object` (10 402 arquivos) | **IGUAIS=10 402, FALTANDO=0, DIFERENTES=0, EXTRAS=0** |
| 7 | Recuperação do estado local | `git reset --mixed origin/…` | `HEAD=44055a9`, `git status --porcelain` **vazio** |
| 8 | Reprodução do remoto em clone limpo | `git clone` + `make -s build` / `check` / `gate-selftest` / `gate` | build exit 0; check **182/0**; gate-selftest **19/19**; gate **18 PASS / 0 FAIL / 3 BLOCKED / 2 SKIPPED / 339 asserções / 23 etapas / exit 0** |
| 9 | Efeito do clone **raso** | `git clone --depth 1` + `make -s gate-selftest` | `ref-intacta` = **8 casos, 2 falhas** (casos 7–8) e `gate-selftest` caso 13 falha por consequência — **objeto ausente, não defeito do conteúdo** |
| 10 | Credenciais em claro | varredura regex + `muserver_preflight.py` (P07) | P07: **22 ERRO/19 AVISO/16 OK/1 INFO**; 6 ERROS de segredo/PII; valores redigidos |
| 11 | A saída do P07 vaza valor? | teste de pertinência (valores extraídos dos configs) | 1 casamento, e é o **nome do banco** — que já aparece nos nomes dos próprios arquivos `.bak`/`.reg` versionados; 5 marcadores de redação |
| 11b | **Os próprios documentos desta etapa** vazam valor? | mesmo teste de pertinência sobre os 3 arquivos novos | **0** (a primeira versão casou o nome do banco dentro de uma frase; a frase foi reescrita para não citá-lo) |
| 12 | PII nossa | comparação booleana e-mail `r6-config.tsv` × `PSGG.ini` | **idêntico** (vazamento nosso, listado para correção) |
| 13 | Exposição em `main` | `git rev-parse origin/main:<caminho>` (5 arquivos sensíveis) | existem e são **idênticos** ao tip da branch |
| 14 | Ausência de segredos de infraestrutura | regex `PRIVATE KEY`, `ssh-*`, `.env`/`.pem`/`id_rsa`, connection strings | **nenhum** achado |
| 15 | `security_and_analysis` do GitHub | `gh api repos/…` | *não disponível* (exige admin) |

### §5-A Correção proposta — clone raso (`ref-intacta`)

- **Causa medida:** os casos 7 e 8 dependem do commit de upload `6eabb45`, que **não existe** em clone
  raso (`git cat-file -e` falha). Hoje isso vira **FAIL** e derruba o portão — culpa errada: o conteúdo
  está correto, o objeto é que está ausente.
- **Proposta (não aplicada):** no topo de `tests/ref_check.sh`, verificar a existência do objeto
  (`git cat-file -t "$UPLOAD"`); ausente ⇒ tentar, **opt-in** (`REF_FETCH=1`), um `git fetch` não
  destrutivo apenas desse objeto e, se ainda ausente, reportar **BLOCKED** com causa nomeada
  (`objeto_base_ausente: rode git fetch --unshallow`) e sair 0. **Nunca** FAIL por ausência de objeto,
  **nunca** PASS sem os objetos.
- **Critérios preservados:** com o objeto presente e divergência **não registrada** ⇒ continua **FAIL**
  (é o propósito da etapa). Novo caso no `gate-selftest`: forçar ausência (ex.: `REF_UPLOAD=<sha
  inexistente>`) ⇒ a etapa precisa sair **BLOCKED** e não contada como PASS. Efeito colateral conferido:
  o caso 13 do `gate-selftest` (piso ≥9 PASS / ≥194 asserções) continua satisfeito — bloquear essa etapa
  derruba a contagem para ≈331 asserções e 17 PASS.

### §5-B Correção proposta — `net-matrix` × `persistencia`

- **Causa medida:** `net-matrix` (`make -s net-matrix` → `NET_QUICK=0 bash tests/net.sh`) grava
  `reports/net-orig.tsv` e `reports/net-mur0.tsv` — **arquivos versionados**; a etapa seguinte,
  `persistencia` (`bash scripts/verify-backup.sh`, caso 3), exige árvore limpa
  (`git status --porcelain -- recriado/`) ⇒ **FAIL determinístico**. Medido: `GATE_FULL=1` → 19 PASS /
  **1 FAIL** / 3 BLOCKED; com `GATE_SKIP=net-matrix` → **15/0/0**.
- **Opção A (recomendada, não aplicada):** `tests/net.sh` passa a gravar em `out/net-matrix/` (já
  ignorado por `.gitignore`) e um alvo explícito publica: `make net-matrix-publish` copia para `reports/`.
  O portão deixa de escrever em caminho versionado; `persistencia` continua exigindo árvore limpa.
  Selftests novos: (i) `make net-matrix` em árvore limpa ⇒ `git status --porcelain -- recriado/` vazio;
  (ii) `make net-matrix-publish` ⇒ árvore suja e `persistencia` **FAIL** (prova de que o critério ainda
  detecta sujeira real); (iii) restauração conferida por sha256, no padrão que o `gate-selftest` já usa.
  Mudança mínima que viabiliza: `REPORT_DIR="${NET_REPORT_DIR:-reports}"` em `tests/net.sh`.
- **Opção B (paliativo, insuficiente sozinha):** inverter a ordem do `OPTIN` (`persistencia` antes de
  `net-matrix`). A sujeira permanece **entre execuções**, então a segunda rodada FULL consecutiva volta a
  falhar — só serve junto com A.
- **Opção C (rejeitada por padrão):** afrouxar o critério de `persistencia` para ignorar
  `reports/net-*.tsv`. Enfraquece "nada escrito sem comitar": **não** recomendada; só com autorização
  explícita e registro em `DECISIONS.md`.
- **Regra que não muda:** nenhuma correção pode produzir verde artificial. O portão continua tendo de
  **detectar falha real** — por isso as três provas acima, e não apenas "parar de falhar".

### §5-C Licenciamento — separação por origem (para a decisão §4.7)

| Classe | O que é | Estado |
|---|---|---|
| **Código próprio** | `recriado/` (C, Python, shell, docs), `workspace/` (ferramentas/relatórios nossos), espelho `MuserverRecriado/` | **Sem licença declarada** em lugar nenhum do repositório. Decisão do proprietário (§4.7). Nada foi apresentado como de terceiros nem vice-versa. |
| **Terceiros OSS identificados** | `json.lua` (Copyright (c) 2020 **rxi**, licença **MIT**) — 3 cópias em `Tools/Gerador de Main/…/Data/Custom/Script/Util/Json.lua` | **Aviso de copyright preservado no arquivo** (verificado no cabeçalho). MIT permite redistribuir **com o aviso** — condição hoje satisfeita; não remover. |
| **Binários proprietários / comerciais** | suíte `MuServer/` (GameServer, GameServerCS, ConnectServer, JoinServer, DataServer, MHPServer, DiscordServer, PSGuard), editores, geradores de Main, `LuaEncryptorTool.exe` + `.pdb`, `StartUp/SSU_*.exe`, DLLs (49 `.dll`, 22 `.exe`) | **Sem autorização de redistribuição comprovada**; **8 binários protegidos por Themida** (P11) — **não contornar proteções**, não extrair, não executar. Tratar como material do proprietário/licenciado a terceiros. |
| **Assets do jogo** | 1 021 `.jpg`, 313 `.ozt`, 106 `.ozj`, 276 `.att`, 56 `.bmd` (texturas/modelos do cliente MU Online) | Propriedade de terceiros (publicadora/origem a verificar) — **não** redistribuir como se fosse livre. |
| **Configs com autoria de terceiros** | `Data/EventItemBagManager.txt`, `Data/Command.txt` e afins trazem créditos `© 2025 …` + domínio | **Preservar os avisos**; origem a verificar antes de qualquer reuso. |
| **Dados pessoais** | ver §2 | Não são conteúdo licenciável; são incidente de privacidade (§3). |
| **Protocolos** | docs de protocolo do `recriado/` (implementação independente, medida por engenharia reversa de comportamento observável) | Documento próprio; **não** afirma compatibilidade com o cliente original além do que foi medido (mantido). |

Ausência de licença **não** é autorização: nada de `MuServer/` deve ser apresentado como nosso nem
redistribuído. Nenhuma proteção comercial foi contornada nesta etapa (nem antes).

---

## 6. Pendências e próximos passos recomendados

1. **Aguardando o proprietário**: as 10 decisões do §4 — em especial o modelo de contenção (§4.1) e a
   rotação (§4.2), que **não** dependem do agente para começar.
2. **Após autorização**: aplicar §5-A e §5-B com os selftests propostos; redigir a PII nossa; criar
   `LICENSE`/`NOTICE` conforma a decisão §4.7.
3. **Riscos aceitos conscientemente até decisão**: o material sensível **permanece público**; a
   exposição já ocorreu e **não é reversível por remoção** — apenas por rotação + contenção.
4. **Itens BLOCKED conhecidos** (não são novidade, seguem registrados): `interop` (sem cliente original),
   `lua`/`lua-enc` (sem Lua no ambiente; algoritmo da cifragem **não identificado**), `bench` sob carga.
5. **Não iniciar** desenvolvimento de sistemas de jogo (`ozt`, `regressao-lua` ou qualquer novo) até a
   auditoria independente e as decisões do proprietário.

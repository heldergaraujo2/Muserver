# Inventário de exposição — repositório público `heldergaraujo2/Muserver`

**Data do inventário:** 2026-10-13 · **Autor:** agente (a pedido do auditor independente) · **Refs medidas:
`main` = `6eabb45b9e7939a3061f4757ed6791efef7c5c3b`, branch `arena/cf1de8ce-muserver` =
`44055a933a37e99f7d91fa78e6897861e703d338`**

> **Este documento não contém valores de credenciais, hashes de senha, e-mails completos nem dados
> pessoais.** Ele descreve **onde** há material sensível, **que tipo** de material é e **o que precisa
> ser feito**. O artefato de máquina é o TSV ao lado (`inventario-exposicao-2026-10-13.tsv`, 96 linhas,
> `categoria → caminho → linha`), que também não carrega valores.

## Método (reprodutível)

- Varredura regex sobre o repositório exceto `.git/`, sem abrir arquivos de banco/dump e sem imprimir
  valores. Categorias: `senha-em-texto`
  (`(?i)\b(senha|password|passwd|pwd)\b\s*[:=]\s*\S`), `token-ou-chave`
  (`(?i)\b(token|api[_-]?key|secret|client[_-]?secret|access[_-]?key|private[_-]?key)\b\s*[:=]\s*\S`),
  `string-conexao-bd` (`(?i)(data source|server|host)\s*=\s*[^\s;]+[^\n]*;\s*[^\n]*(uid|user id|userid|usuario)\s*=`),
  `chave-privada` (`-----BEGIN … PRIVATE KEY-----`), `chave-ssh`, `endereco-ip`
  (`\b(?:\d{1,3}\.){3}\d{1,3}\b`), `email-dado-pessoal`, `marcador-lgpd-rg-cpf`.
- Classificação de valor seguiu **chave + faixa de comprimento + classe de caracteres** — nunca o valor.
  Para arquivos-chave, a verificação de presença usou `^\s*<chave>\s*[:=]` e reportou apenas
  `PREENCHIDO`/`VAZIO` + faixa.
- **Não foi feito, por decisão:** abrir/restaurar qualquer `.bak`; testar validade de qualquer credencial;
  ler conteúdo de binários, dumps ou imagens; executar `LuaEncryptorTool.exe` ou qualquer `.exe`.
- Limitação declarada: a varredura é **sintática** (regex + amostragem de formato). Ela **não** garante
  ausência de segredo em formato atípico nem substitui revisão humana linha a linha dos logs.

## 1. Credenciais em claro confirmadas (valor não vazio)

| Arquivo (todos em `MuServer/`) | Chaves com valor | Observação medida |
|---|---|---|
| `PSGuard/PSGG.ini` | `sqlusuario`, `sqlsenha`, `sqlhost`, `sqldatabase`, `sqldatabasechar`, `singletoken`, `licenca`, `crclicenca`, `key1cabal`…`key4cabal`, `db`, `db1`, `db2`, `db3`, `dbperm`, `dbtype`, `loadglobaldb`, `usekeycabal` | **21 chaves preenchidas.** `sqlsenha` faixa 16–31 (alfanum); `crclicenca` faixa 32+; chaves `key*cabal` 1–7 dígitos. Credencial de banco + licenças em texto claro. |
| `JoinServer/JoinServer.ini` | `globalpassword` (8–15, alfanum), `joinserverodbc` (nome de DSN) | Segredo compartilhado do JoinServer. |
| `DiscordServer/DiscordServer.ini` | `discordbottoken` (faixa **≥32**, alfanum), `discordserverodbc`, `discordserverport`, `discordbotactive` | Comprimento/classe compatíveis com token de bot **real** (validade não testada). |
| `MHPServer/MHPServer.ini` | `clientserial` (16–31), `encdeckey1`, `encdeckey2` (1–7 dígitos) | Serial/chaves de licença do MHP. |
| `Tools/Editores/Editor de conta Muemu/config.ini` | `user` (1–7), `password` (16–31, alfanum) | Credencial de banco do editor de contas. |
| `Tools/Editores/MuEditor/config.ini` | `user` (1–7), `pass` (16–31, alfanum), `me_db`, `mu_db` | Credencial de banco do MuEditor. |
| `DataServer/DataServer.ini` | `dataserverodbc` (8–15, alfanum) | Apenas **nome do DSN**; sem senha embutida no arquivo. |
| `Tools/Gerador de Main/MAIN_INFO*/MainInfo.ini` (2 cópias) | `clientserial` (serial do cliente), `discordpresenceapplicationid` | O *application id* do Discord é público por definição; o serial é material licenciado. |
| `DB/MuOnline.reg`, `DB/MuOnline64.reg` (UTF-16) | entradas ODBC: `Driver`, `Description`, `Server`, `Database`, `LastUser`, `Trusted_Connection` | **Sem senha embutida**; expõem host, nome do banco e último usuário. As credenciais de DSN moram no registro do Windows do proprietário (fora do repositório). |

**Falso positivo verificado (não é vazamento):** `Tools/Gerador de Main/MAIN_INFO v41 - Season
6/Premium/Settings.ini` tem as chaves `user`/`password` **presentes e vazias** (`""`). A varredura
sintática inicial acusa a linha; a conferência de presença mostra valor vazio.

## 1b. Inventário **autoritativo** do scanner pré-existente (check P07)

Executado nesta rodada, para conferência cruzada: `python3 workspace/tools/muserver_preflight.py --root
MuServer` → **22 ERRO, 19 AVISO, 16 OK, 1 INFO**. Os 6 ERROS de segredo/PII (**valores REDIGIDOS pelo
próprio scanner**; conferimos que nenhum valor real aparece na saída — ver §4):

| # | Achado | Arquivos |
|---|---|---|
| 1 | token de bot do Discord (1 ocorrência) | `DiscordServer/DiscordServer.ini` |
| 2 | *hardware id* de licença (5) | `DiscordServer/DiscordServer.ini`, `GameServer/Data/GameServerInfo - Common.dat`, `GameServerCS/DATA/GameServerInfo - Common.dat`, `SpeedServer/GameServer/Data/GameServerInfo - Common.dat`, `SubSalatest/GameServer/Data/GameServerInfo - Common.dat` |
| 3 | senha global em texto (1) | `JoinServer/JoinServer.ini` |
| 4 | **senha dentro de connection string** (2) | `JoinServer/JoinServer.ini`, `Tools/Editores/Editor de conta Muemu/config.ini` |
| 5 | serial de cliente (7) | os 4 `GameServerInfo - Common.dat`, `MHPServer/MHPServer.ini`, `Tools/Gerador de Main/MAIN_INFO v41 - Season 6/MainInfo.ini` (+1) |
| 6 | 4 backups de banco versionados — **50 373 632 bytes** (48,0 MiB) com contas/hashes | `DB/MuOnline.bak`, `DB/MuOnline_old.bak`, `DB/back_hinet.bak`, `DB/mw_v6.bak` |
| — | INFO: 1 `.bak` que **não** é banco | `Tools/StartUp/Configuration/bor_StartUp.xml.bak` (backup de config; higiene, não incidente) |

**Divergência declarada entre os dois inventários (honestidade de método):** a varredura por regex do
§Método **subestimou** dois grupos e por isso este documento os corrige —
(i) os 4 arquivos `GameServerInfo - Common.dat` foram classificados como binários pela extensão e **não
tiveram conteúdo lido**, embora contenham serial de cliente e *hardware id* (o scanner P07 lê);
(ii) a categoria `string-conexao-bd` do meu regex deu **0 ocorrências**, mas o P07 registra **2** — meu
padrão exigia `Server=`/`Host=` antes do `Uid=`/`Pwd=` na mesma linha, e o formato real não é esse.
Onde os dois divergirem, **vale o P07** (é o scanner com teste de auto-verificação próprio,
`workspace/tests/test_preflight_selfcheck.py`).

O relatório redigido anterior, `workspace/reports/A1-secrets.md`, já registrava esses achados; o
`reports/preflight.json` que ele cita como fonte **não está no repositório nem no disco** (artefato
efêmero) — a rastreabilidade fica pelo relatório redigido.

## 2. Credenciais em **logs** (texto claro)

Em `SpeedServer/GameServer/LOG/COMMAND_LOG/*.txt` (5 arquivos, 5+ linhas), o formato registrado é
`[CommandSetParty][<conta>][<personagem>] - Password: <valor>` — senha de **party** em texto claro,
junto de conta e personagem. Faixa do valor: 1–7, só dígitos. Não são senhas de conta, mas são
credenciais + identificadores de jogadores em arquivo público.

## 3. Dados pessoais e material sensível (não são credenciais)

| Classe | Caminhos | Volume medido |
|---|---|---|
| Logs de servidor com **IP de jogador** | `ConnectServer/LOG`, `DataServer/LOG`, `JoinServer/LOG`, `JoinServer/LOG_ACCOUNT`, `MHPServer/LOG`, `SpeedServer/GameServer/LOG/**`, `SubSalatest/GameServer/LOG/**` (subpastas `CONNECT_LOG`, `DROP_LOG`, `COMMAND_LOG`, `EVENT_LOG`, `CASH_SHOP_LOG`, `CHAOS_MIX_LOG`, `HACK_LOG`…) | **2 793 arquivos, ≈216 MB**; categoria `endereco-ip` = **330 085 linhas em 1 076 arquivos** |
| `LOG_ACCOUNT` (login/conexão por conta) | `JoinServer/LOG_ACCOUNT/` | 238 arquivos, ≈12 MB; formato `[<cmd>] <texto> (<chave>: <valor>, <chave>: <IP>, …, <chave>: <8-8-8-8>)` — IP + identificador de máquina/serial por evento |
| **Backups de banco** | `DB/MuOnline.bak`, `DB/MuOnline_old.bak`, `DB/back_hinet.bak`, `DB/mw_v6.bak`, `DB/mw_v6.rar` | 4 `.bak` = **48,0 MB** (16,16 + 8,96 + 16,16 + 6,75) + 0,55 MB `.rar`; identificados como backup **Microsoft SQL Server** (magic `TAPE`). **Conteúdo não inspecionado** — pelo padrão do produto contém contas/personagens; tratar como dado de jogador até prova em contrário |
| **Crash dumps de memória** | `MuServer/**/GameServer/`, `GameServerCS/`, `SubSalatest/` (34 arquivos `.dmp`) | **9,0 MB**; formato minidump (`MDMP`); podem conter memória do processo (sessões, contas, strings) |
| **PII em artefato nosso** | `recriado/reports/r6-config.tsv` e `MuserverRecriado/reports/r6-config.tsv` | 1 e-mail **idêntico** ao de `PSGuard/PSGG.ini` (comparação booleana, valor não exibido) — vazamento introduzido pela nossa própria consolidação |
| PII em script nosso | `workspace/migracao/preparar-destino.sh` | 1 e-mail (diferente do anterior) — identidade usada em comando git |

## 4. Confirmações **negativas** (verificadas)

- Nenhuma chave privada (`-----BEGIN … PRIVATE KEY-----`) e nenhuma chave SSH pública/privada no
  repositório.
- A categoria `string-conexao-bd` do meu regex deu **0 ocorrências** — mas isso é um **falso negativo
  do meu padrão**, não uma garantia: o scanner P07 registra **2** senhas dentro de connection string
  (`JoinServer/JoinServer.ini`, `Tools/Editores/Editor de conta Muemu/config.ini`). Ver §1b.
- Os 4 `GameServerInfo - Common.dat` **não** foram lidos por este inventário (classe "binário" pela
  extensão); o P07 confirma que contêm serial/hardware id. Ver §1b.
- Nenhum arquivo com nome de segredo (`.pem`, `.key`, `.pfx`, `id_rsa`, `.env`, `credentials*`,
  `secrets*`) — as 4 ocorrências do filtro por nome são documentos nossos chamados `A1-secrets.md`,
  que **não contêm valores** (0 linhas com chave de credencial, 0 sequências de alta entropia).
- `GitHub → Settings → Security analysis` **não acessível** com a credencial do agente (exige admin):
  não foi possível verificar se há *secret scanning* / *push protection* ligados.
- **Teste de vazamento aplicado a este documento**: comparamos os valores das chaves sensíveis dos
  configs com o próprio texto → **1 casamento benigno**: o **nome do banco**, que aqui só aparece dentro
  dos caminhos de arquivo `DB/<nome>.reg` / `DB/<nome>.bak` — nomes de arquivo públicos desde o commit
  de upload, não conteúdo de segredo. Nenhum outro valor casa (senhas, token, serial, chave ou e-mail:
  0). O teste roda de novo antes de cada commit deste par de documentos.
- **A própria saída do P07 não vaza valores**: teste de pertinência com os valores sensíveis extraídos
  dos configs → **1 casamento**, e ele é o *nome do banco* (`MuOnline`), que já é o nome dos próprios
  arquivos `.bak` versionados; a saída contém 5 marcadores de redação (`REDIGIDOS`). O JSON-fonte foi
  gravado em `/tmp` (efêmero) e **não** é versionado.

## 5. Onde esse material está exposto

- `MuServer/` (10 021 arquivos) foi enviado no commit de upload `6eabb45` e é a árvore da branch
  **`main`** (branch padrão do repositório **público**). Confirmação por arquivo:
  `git rev-parse origin/main:<caminho>` existe e é **idêntico** ao tip da branch `arena/cf1de8ce-muserver`
  para os 5 arquivos sensíveis testados (`PSGG.ini`, `JoinServer.ini`, `DiscordServer.ini`,
  `MuOnline.bak`, `MuEditor/config.ini`).
- Consequência: o material está no **commit atual** e no **histórico** — remover do último commit não
  invalida nada que já foi exposto nem o que já foi clonado.

## 6. Artefatos deste inventário

- `workspace/seguranca/inventario-exposicao-2026-10-13.tsv` — 96 linhas `categoria → caminho → linha`
  (categorias `senha-em-texto` 25, `token-ou-chave` 6, `email-dado-pessoal` 5, `marcador-lgpd-rg-cpf` 60).
  A categoria `endereco-ip` (330 085 linhas ≈ 18,9 MB) foi **omitida do TSV por volume** e fica registrada
  como contagem aqui e reproduzível pelo regex do §Método.
- Plano de contenção, decisões pendentes e evidências: `workspace/migracao/RELATORIO-TRATAMENTO-RISCOS-P0-2026-10-13.md`.

# DATABASE — banco de dados: o que o pacote espera, e o que o v2 faz (nada, hoje)

| campo | valor |
|---|---|
| data | 2026-10-13 |
| resposta curta | **o v2 (`recriado/`) não tem banco de dados, nem persistência de estado**. O pacote de referência (`MuServer/`) exige **SQL Server via ODBC** e traz artefatos de banco versionados |
| regra | nada aqui foi executado, restaurado ou testado com um servidor de banco real; o que está escrito é o que os arquivos **medidos** mostram |

## 1. Estado no v2: AUSENTE (declarado no próprio código)

`src/mud2.c`, cabeçalho, linha 15 — o serviço diz o que **não** faz:

```
 * Nao faz: TLS, autenticacao, persistencia, nem qualquer compatibilidade com o cliente
```

Confirmado por medição: `grep -riE 'odbc|sqlite|sql|mysql|postgres'` em `src/`, `include/`,
`tools/` e `tests/` retorna **0 ocorrências de uso de banco** (os únicos casamentos são a palavra
"persistência" em comentário e o nome da etapa opt-in `persistencia` do portão, que é sobre *backup
do repositório*, não sobre banco — ver `BUILD_AND_RUN.md` §6).

Consequências, sem eufemismo: **não existem contas, personagens, itens, progressão nem qualquer
estado durável** no v2. Reiniciar o serviço zera os contadores. Isso é decisão de escopo da fase
atual, não defeito oculto — e está listado como **AUSENTE** em `PROJECT_STATUS.md`.

## 2. O que o pacote de referência espera (medido nos arquivos)

### 2.1 DSN ODBC nomeado `MuOnline` (dependência dura de boot)

`MuServer/DB/MuOnline.reg` (UTF-16LE, Windows Registry Editor 5.00):

| campo do DSN | valor medido |
|---|---|
| chave | `HKLM\SOFTWARE\ODBC\ODBC.INI\MuOnline` |
| `Driver` | `C:\WINDOWS\system32\SQLSRV32.dll` (driver **SQL Server 32-bit**) |
| `Server` | `(local)` |
| `Database` | `MuOnline` |
| `LastUser` | `sa` |
| `Trusted_Connection` | `Yes` |

Existe a variante `MuOnline64.reg` (mesma família, chave de 64 bits). O relatório da fase anterior
(`workspace/docs/DEPENDENCIES.md`) registra que os binários do pacote são 32-bit (medido: 21 PE32 +
1 PE32+), então o DSN útil seria o de **32 bits** (`SysWOW64\odbcad32.exe`) — o modo de falha de
boot mais provável do stack original. Essa leitura vem do pacote, não de execução.

### 2.2 Backups de banco versionados (e por que são um problema de segurança)

`MuServer/DB/` contém, medido por tamanho:

| arquivo | bytes |
|---|---|
| `MuOnline.bak` | 16 948 736 |
| `back_hinet.bak` | 16 949 760 |
| `MuOnline_old.bak` | 9 398 784 |
| `mw_v6.bak` | 7 076 352 |
| `mw_v6.rar` | 580 612 |
| **soma dos 4 `.bak`** | **50 373 632** |

Os 4 `.bak` têm assinatura de media set (`TAPE`) e **contêm dados de jogadores** (contas e hashes de
senha) — por isso são tratados como **incidente de divulgação** em `SECURITY.md` §5 e no relatório
`workspace/changes/pre-ff-2026-10-12/untracked/workspace/reports/A1-secrets.md`. **Nada foi
restaurado** (restaurar banco original está fora do escopo por decisão) e nada foi copiado para
relatório.

### 2.3 Como o servidor original conversa com o banco (lido do baseline, não do patcheado)

`workspace/changes/originals/DataBase.lua` (blob do commit de upload `6eabb45`, a versão **original**):

- convenção **invertida** em relação ao senso comum, e é contrato: `SQL_NO_DATA = 100` significa
  "sem linhas", e `SQLQuery() == 0` significa **falha**;
- API do bridge exposta ao Lua: `SQLConnect(ODBC, User, Password)`,
  `ConnectQueryAsync(ODBC, User, Password)`, `SQLQuery(sql)`, `SQLFetch()`, `SQLGetString("coluna")`,
  `SQLClose()`;
- as queries montam **nomes de tabela dinamicamente** (`string.format("SELECT %s FROM %s WHERE %s = '%s'", …)`).

Medições associadas:

| medição | valor |
|---|---|
| `.lua` com `SELECT`/`INSERT`/`UPDATE`/`DELETE` | **26** |
| nomes de tabela literais nas queries | só `INFORMATION_SCHEMA` (3×) — o restante é montado em runtime |
| stored procedures versionadas | 4, em `MuServer/Tools/ResetRankingWeb/` (§2.4) |
| editores que falam SQL direto | `Tools/Editores/MuEditor/config.ini` e `Tools/Editores/Editor de conta Muemu/config.ini`, seções `MuOnline`/`Me_MuOnline`, `PORT=1433` |

Consequência honesta: **o schema completo não é enumerável por análise estática do pacote** com
confiança. Enumerá-lo exigiria restaurar um `.bak` num SQL Server — explicitamente fora do escopo
desta auditoria (e os `.bak` são material sensível, §2.2).

### 2.4 Procedimentos armazenados versionados (o schema que aparece em texto)

`MuServer/Tools/ResetRankingWeb/` traz 4 arquivos `.sql` legíveis (UTF-16LE), entre eles
`WZ_GetResetInfo.sql`:

```sql
USE [MuOnline]
GO
ALTER Procedure [dbo].[WZ_GetResetInfo]
@Account varchar(10),
@Name varchar(10)
AS
```

São procedures de consulta/gravação de reset (`WZ_Get/SetResetInfo`, `WZ_Get/SetMasterResetInfo`) do
site/tooling do proprietário — evidência de que o banco se chama `MuOnline` e de que esse tooling
externo também depende dele.

## 3. Procedimento de inicialização do original (documentado, **não executado** aqui)

O que o pacote sugere para subir o banco do servidor original — registrado como referência, com a
marcação de que **não foi executado nem validado** neste ambiente (não há Windows nem SQL Server):

1. restaurar `DB/MuOnline.bak` num SQL Server local (instância `(local)`), base `MuOnline`;
2. criar o DSN ODBC **de 32 bits** `MuOnline` (`SysWOW64\odbcad32.exe`, `Trusted_Connection=Yes`,
   `LastUser=sa`) — é o `DB/MuOnline.reg`;
3. subir JoinServer/DataServer, que são os primeiros a falhar sem o DSN.

Ressalva obrigatória: nada disso é recomendação de segurança (a base vem com `sa`/trusted), e os
`.bak` contêm dados de terceiros — ver `SECURITY.md`.

## 4. O que seria necessário para o v2 ter persistência (não implementado)

Não existe decisão tomada nem código. Qualquer caminho (`sqlite`, arquivo próprio, PostgreSQL) seria
**decisão nova** a registrar em `DECISIONS.md`, com migrações versionadas, teste de reinicialização e
critério de aceitação — e, para falar com o ecossistema original, o acoplamento real é o **DSN ODBC
`MuOnline`** e a convenção `SQL_NO_DATA=100`/`SQLQuery()==0`, que teriam de ser reproduzidos por
bridge ou driver próprio. Hoje isso está **`NOT_IMPLEMENTED`** por decisão de escopo
(`PROJECT_STATUS.md` §3), não por bloqueio de ambiente.

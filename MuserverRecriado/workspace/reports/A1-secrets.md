# A1 — inventário redigido de segredos e PII no repositório

Gerado de `reports/preflight.json` (check P07) por
`/home/user/.venv-tools/bin/python workspace/tools/muserver_preflight.py --root MuServer --json …`.

**Este arquivo não contém nenhum valor de segredo.** Registra apenas *o que* é,
*onde* está e *o que fazer*. A regra da auditoria é não duplicar credenciais
em relatório nenhum — inclusive neste, que será comitado.

| Severidade | Achado | Arquivos |
|---|---|---|
| ERROR | token de bot do Discord: 1 ocorrencia(s) em 1 arquivo(s) | `DiscordServer/DiscordServer.ini` |
| ERROR | hardware id de licenca: 5 ocorrencia(s) em 5 arquivo(s) | `DiscordServer/DiscordServer.ini`, `GameServer/Data/GameServerInfo - Common.dat`, `GameServerCS/DATA/GameServerInfo - Common.dat`, `SpeedServer/GameServer/Data/GameServerInfo - Common.dat`, `SubSalatest/GameServer/Data/GameServerInfo - Common.dat` |
| ERROR | senha global em texto: 1 ocorrencia(s) em 1 arquivo(s) | `JoinServer/JoinServer.ini` |
| ERROR | senha no connection string: 2 ocorrencia(s) em 2 arquivo(s) | `JoinServer/JoinServer.ini`, `Tools/Editores/Editor de conta Muemu/config.ini` |
| ERROR | serial de cliente: 7 ocorrencia(s) em 7 arquivo(s) | `GameServer/Data/GameServerInfo - Common.dat`, `GameServerCS/DATA/GameServerInfo - Common.dat`, `MHPServer/MHPServer.ini`, `SpeedServer/GameServer/Data/GameServerInfo - Common.dat`, `SubSalatest/GameServer/Data/GameServerInfo - Common.dat`, `Tools/Gerador de Main/MAIN_INFO v41 - Season 6/MainInfo.ini (+1)` |
| ERROR | 4 backup(s) de banco versionados (50,373,632 bytes) contendo dados de jogadores | ver detail |
| INFO | 1 arquivo(s) .bak que NAO sao backup de banco | ver detail |

## O que fazer (ordem)

1. **Rotacionar na origem**, antes de qualquer refatoração: reset do token do
   bot no Discord Developer Portal; senha do SQL Server; `GlobalPassword` do
   JoinServer; `ClientSerial`/`ServerSerial` se o contrato de licença exigir.
   Rotacionar é o único passo que importa: **o histórico do Git já contém os
   valores atuais**, então removê-los do HEAD não invalida cópia nenhuma.
2. **Expurgar o histórico** com `git-filter-repo` e avisar colaboradores (um
   clone antigo ainda tem o segredo). Ver `tools/untrack_artifacts.sh`.
3. **Migrar segredo para fora do VCS**: variável de ambiente ou arquivo fora do
   repositório; `JoinServer.ini`/`DiscordServer.ini` passariam a referenciá-lo.
   Atenção: o `GameServer.exe` lê `CustomerHardwareId`/`CustomerSerial` direto do
   `.ini`/`.dat` — esses **não** são externalizáveis sem o fonte, que não existe.
4. **Tratar os 4 backups de banco como incidente de divulgação**: contêm PII de
   contas e hashes de senha. O 5º `.bak` do pack é config XML do StartUp (higiene,
   não incidente) — distinguir exigiu ler a assinatura de media header `TAPE`.

## O que a auditoria NÃO fez
- Não testei se os valores ainda são válidos, nem os usei, nem os copiei para cá.
- Não abri os `.bak` (restaurar banco está fora do isolamento deste workspace).
- Não neutralizei proteção de licença nem alterei IDs para contornar autorização.

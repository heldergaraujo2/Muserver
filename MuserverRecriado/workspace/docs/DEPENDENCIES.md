# DEPENDENCIES — grafo de dependências reais

Extraído dos arquivos de configuração (não presumido). Valores de porta e
endereços estão nos próprios `.ini`/`.dat`.

## 1. Serviços e portas
| Serviço | Porta(s) | Fala com | Config |
|---|---|---|---|
| ConnectServer | TCP 44406, UDP 55557 | JoinServer | `ConnectServer/ConnectServer.ini` + `ServerList.dat` |
| JoinServer | 55970 | ConnectServer 127.0.0.1:55557, SQL (DSN `MuOnline`) | `JoinServer/JoinServer.ini`, `AllowableIpList.txt` |
| DataServer | 55960 | SQL (DSN `MuOnline`) | `DataServer/DataServer.ini`, `BadSyntax.txt` |
| GameServer (Geral) | 55901 | Join 55970, Data 55960, Connect 55557 | `GameServer/Data/GameServerInfo - *.dat` |
| GameServerCS | (próprio) | idem | `GameServerCS/DATA/GameServerInfo - *.dat` |
| SpeedServer | 55905/55906 (via `MapServerInfo.dat`) | idem | `SpeedServer/GameServer/Data/…` mas **`Data/` fica um nível acima** |
| SubSalatest | — | idem | `SubSalatest/Data/…` (idem, Data fora de GameServer/) |
| DiscordServer | 55990 | SQL + Discord (bot) | `DiscordServer.ini`, `Owner.ini` |
| MHPServer | 55999 | cliente (serial) | `MHPServer.ini`, `MHPDetect.dll`, `BlackList.txt` |
| PSGuard | — | GameServer (DLL injection) | `PSGG.ini`, `Servidor.32/.64.exe`, `Monitor.exe` |

`MapServerInfo.dat` faz o roteamento mapa↔instância: `ServerCode 0→55901`,
`1→55902`, `2→55903`, `19→55919` (`InitSetVal 0` = desativado), `23→55905`,
`24→55906`, `29→55929 (InitSetVal 0)`, com o comentário explícito
`//SpeedServer// Está Desativado`.

## 2. Dependências duras
- **ODBC DSN nomeado `MuOnline`** — é compartilhado por JoinServer, DataServer e
  DiscordServer, e pelos 4 GameServer. Criado por `DB/MuOnline.reg` (32-bit) ou
  `DB/MuOnline64.reg`. **Todos os serviços morrem se o DSN não existir**; os
  binários são 32-bit, logo o DSN precisa ser criado no **ODBC de 32 bits**
  (`C:\Windows\SysWOW64\odbcad32.exe`), não no padrão. Este é o modo de falha de
  boot mais provável do stack.
- **`SQL_NO_DATA = 100`** — convênio da camada Lua: `SQLFetch()==100` significa "sem
  linhas", e `SQLQuery()==0` significa falha (invertido em relação ao senso comum).
- VC++ 2010 redist distribuído localmente (`msvcr100.dll`, `mscp100.dll` em cada
  pasta de serviço). `PSGuard` precisa das DLLs MySQL/SSL de 32 bits para o
  MHP/anti-cheat.
- `Owner.ini` (`[License] Owner=1`) presente em 5 locais — o binário o exige.
- Camada Lua → C++ por **nome de função global**: `BridgeFunction_<Evento>`; e
  C++ → Lua chamando essas funções. Não há ABI tipada, o que torna o par
  "nome existe?" a única verificação possível — e o ponto por onde os crashes
  entram (ver AUDIT §3).

## 3. Licenças/autenticação externa (seção 7 da missão)
| Dependência | Propósito | Onde se configura | Risco de boot |
|---|---|---|---|
| Themida/WinLicense | proteção + licença do GameServer/DiscordServer/PSGuard/LuaEncryptorTool | embutido no exe; `CustomerName`+`CustomerHardwareId` nos `.ini`/`.dat` | se o HWID mudar (troca de máquina/UUID de BIOS), o binário recusa |
| `GetMainInfo-Premium.exe` + `.premium` + `main.exe` (VMProtect) | gerador do arquivo "main" autorizado | `Tools/Gerador de Main/**/MainInfo.ini` | sem main válido, GameServer não sobe |
| `GetHardwareId.exe` | lê o identificador de hardware | — | — |
| Gate de licença no Lua | `if GetLicenseCustomerName() ~= ALLOWED_CUSTOMER then return end` | `ALLOWED_CUSTOMER` no script | silencioso: script inteiro não registra nada |

**Política aplicada:** nada de neutralizar, contornar ou forjar proteção/serial.
O diagnóstico se limita à configuração do uso autorizado. Ver `DECISIONS.md` D-01.

## 4. Arquivos de dados consumidos (e os furos encontrados)
`Data/MonsterSetBase/**` → `Data/Terrain/Terrain<map>.att`. A auditoria provou que
**24 mapas têm 1 310 linhas de spawn sem o arquivo de terreno correspondente**
(`Terrain24.att`, `Terrain26.att`, `Terrain27.att`, …), e que os mapas 24/26/27
concentram as rejeições registradas nos logs. 84 terrenos numerados + 8 por nome
(`Lorencia.att`, `Terrain34_Close.att`, `Terrain35_OCCUPIED.att`, …) existem.

## 5. Contrato de formato que a tooling precisa respeitar
- `.ini`/`.dat` do servidor: **ASCII/UTF-8 com CRLF**, `;` e `//` como comentário,
  chaves com espaços e com erro de grafia do fornecedor que **não** se corrige
  (`CustomChatSystemSwith`).
- Números com zero à esquerda em toda parte (`001`, `00`) — quebra leitores que
  usem `int(x, 0)` em Python e quebra parsing ingênuo. (Bug real que o
  autoteste pegou nesta auditoria.)
- `MonsterSetBase`: **dois formatos no mesmo arquivo**, alternados por uma linha
  `0`/`1` (NPCS 6 colunas, SPOTS 8 colunas Begin/End + Quantity).

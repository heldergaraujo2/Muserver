# PROJECT_OVERVIEW — MuServer MU Online Season 6.20

Fonte: `github.com/heldergaraujo2/Muserver`, branch `main` @ `6eabb45`
("Upload completo do MuServer MU Online Season 6.20" — **commit único**).
Auditoria em 2026-10-11.

## 1. O que este repositório É, e o que NÃO é

**É um deploy operacional** (pasta de servidor pronta para Windows), não um
repositório de código-fonte. Isso foi determinado por varredura de extensões,
não por suposição:

```
.cpp .h .hpp .c .cs .sln .vcxproj .py .js  ->  0 arquivos
.exe 22   .dll 49   .lua 148   .ini 19   .sql 4   .bak 5   .dmp 34   .txt 7230
```

Consequência prática que governa toda a missão: **não há o que recompilar**.
Os serviços principais são binários protegidos. O material modificável real é:

| Superfície | Estado | Podemos alterar? |
|---|---|---|
| `MuServer/**/Data/**` (config e dados de jogo, `.txt`/`.dat`) | texto | **sim** |
| `MuServer/Data/Script/**/*.lua` (28 arquivos; **20 legíveis, 8 criptografados** pelo LuaEncryptorTool) | fonte Lua legível (só os 20) | **sim** |
| `*.exe` dos serviços | binário Themida/VMProtect | **não** (ver §5) |
| `ConnectServer`/`JoinServer`/`DataServer`/`MHPServer` `.exe` | binário **sem** protetor | parcialmente (diagnóstico sim; patch não recompilável) |
| Banco de dados | `.bak` + `.reg` de DSN | sim (scripts SQL) |

## 2. Componentes reais encontrados

```
                        ┌──────────────────────┐
  cliente ──TCP 44406──▶│   ConnectServer      │  2017, sem proteção
                        │  UDP 55557           │◀──┐
                        └──────────┬───────────┘    │
                                   │                │ JoinServer.ini:
                        ┌──────────▼───────────┐    │ ConnectServerAddress=127.0.0.1
                        │     JoinServer       │────┘ ConnectServerPort=55557
                        │   porta 55970        │
                        │  (autenticação, HWID) │
                        └──────────┬───────────┘
              JoinServerODBC ┌─────┴────────┐ DataServerODBC
                        ┌────▼─────┐  ┌─────▼──────┐
                        │DataServer│  │  SQL Server │  DSN "MuOnline"
                        │ porta    │  │  DB/*.bak   │
                        │ 55960    │  └─────────────┘
                        └────┬─────┘
        GameServerInfo-*.dat │  ServerPort / JoinServer* / DataServer*
   ┌───────────┬─────────────┼──────────────┬───────────────┐
┌──▼───────┐┌──▼───────┐┌────▼─────┐┌───────▼────┐  ┌────────▼─────┐
│GameServer││GameServer││ Speed    ││ SubSala    │  │DiscordServer │ 55990
│ "Geral"  ││CS        ││ Server   ││ test       │  │ + bot (dpp)  │
│ 55901    ││ (13,7 MB)││ 55905..  ││            │  └──────────────┘
└──┬───────┘└──┬───────┘└────┬─────┘└─────┬──────┘
   └───────────┴─────────────┴────────────┘
              ┌─────────────┐   ┌──────────────────────┐
              │  MHPServer  │   │  PSGuard / Monitor   │
              │  55999      │   │  anti-cheat + Main   │
              │ MHPDetect.dll│  │  Servidor.32/.64.exe │
              └─────────────┘   └──────────────────────┘
```

Nomes e portas extraídos dos arquivos, não presumidos:

- `ConnectServer/ConnectServer.ini` → `ConnectServerPortTCP=44406`,
  `ConnectServerPortUDP=55557`, `MaxIpConnection=20`
- `JoinServer/JoinServer.ini` → `JoinServerPort=55970`,
  `ConnectServerAddress=127.0.0.1`, `JoinServerODBC=MuOnline`,
  `MD5Encryption=0`, `CaseSensitive=0`, `MaxHardwareIdConnection=0`
- `DataServer/DataServer.ini` → `DataServerPort=55960`, `AdvancedLog=0`,
  `CustomChatSystemSwith=0` (o nome da chave tem um erro de grafia do fornecedor:
  "Swith"; não renomear, o binário procura exatamente essa string)
- `MHPServer/MHPServer.ini` → `MHPServerPort=55999`, `ClientVersion=1.04.08`,
  8 endereços absolutos de memória para o "MemoryGuard"
- 4× `GameServerInfo - Common.dat` → `ServerPort`, `ServerCode`,
  `DataServerPort/JoinServerPort/ConnectServerPort`, `CustomerName`,
  `CustomerHardwareId`, `ServerMaxUserNumber=200`

### Instâncias de GameServer

Quatro árvores independentes, **todas carregando o mesmo `GameServer.exe` de
13 449 744 bytes exceto uma**:

| Instância | Exe | MD5 | Data |
|---|---|---|---|
| `GameServer/` | 13 449 744 | `bddf82c5…` | `GameServer/Data/` |
| `SpeedServer/GameServer/` | 13 449 744 | `bddf82c5…` (idêntico) | `SpeedServer/Data/` |
| `SubSalatest/GameServer/` | 13 449 744 | `bddf82c5…` (idêntico) | `SubSalatest/Data/` |
| `GameServerCS/` | **13 716 496** | `facd2628…` (build distinto) | `GameServerCS/DATA/` |

`GameServerCS` é um build **diferente**, não uma cópia — e seu
`ExperienceList.txt` tem 150 905 bytes contra 13 552 dos demais (tabela de
experiência ~11× maior). Isso é uma divergência de balanceamento entre
instâncias, documentada em `reports/AUDIT.md`.

## 3. Sistema de dados (`Data/`)

`MuServer/Data/` tem 1 631 arquivos em 21 subdiretórios de finalidade declarada
(`Item`, `Monster`, `MonsterSetBase`, `Terrain`, `Skill`, `Quest`, `Shop`,
`CashShop`, `Event`, `EventItemBag`, `Hack`, `Message`, `Move`, `Effect`,
`Character`, `Custom`, `Script`, `Util`, `EventItemBag`, …). Cada instância de
GameServer tem a **sua cópia** da árvore `Data/` inteira — fonte de 1,4 GB de
redundância em disco e de drift silencioso (ver P10 do preflight: `SpeedServer/Data`
diverge de `MuServer/Data` em 196 arquivos).

Os arquivos `.dat` não são binários: são INI com extensão trocada
(`GameServerInfo - Common.dat` abre como texto). Já `.ozt`/`.ozj`/`.att`/`.bmd`
são binários do cliente/empacotados.

## 4. Camada Lua — o único código-fonte real

`Data/Script/` (77 arquivos `.lua` nas 3 árvores = 28 raiz + 24 SpeedServer +
25 SubSalatest; **56 legíveis** e 21 com corpo cifrado, reconhecidos pelo byte nulo
nos primeiros 4 KB e pelo cabeçalho `0xAA 0x21 0x91 0xA6` comum a todos):

```
ScriptMain.lua          -> porta de entrada; require() de System/, Utils/, Scripts/
System/ScriptCore.lua   -> TABELA de bridges: GameServer -> Lua (BridgeFunctionAttach)
System/ProtocolCore.lua -> despacho de pacotes do cliente
Utils/DataBase.lua      -> SQLQuery/SQLFetch por cima do DSN ODBC
Utils/DataBaseAsync.lua -> fila assíncrona
Utils/Cron.lua Schedule.lua Functions.lua
Scripts/…               -> sistemas: Musaffe/, UpgradeMachine/, CalCharacter, …
```

O contrato do binário com o Lua é por **nome de função global**: o GameServer
procura `BridgeFunction_<Evento>` no estado Lua, e estas invocam
`_G[nome_do_handler]`. Todo o sistema de customização depende disso — e era
também o ponto frágil (ver `reports/AUDIT.md` §3).

## 5. Licenças, proteção e limitação dura

Determinado por análise de cabeçalho PE + seções:

- **Themida/WinLicense** (`.themida`, entrypoint dentro dela, entropia 7,99):
  os 4 `GameServer.exe`, `DiscordServer.exe`, `LuaEncryptorTool.exe`,
  `PSGuard/{Monitor,Servidor.32,Servidor.64}.exe`.
- **VMProtect** (`.vmp0`,`.vmp1`): `Tools/Gerador de Main/MAIN_INFO v41/main.exe`
  (imagem de 152,6 MB).
- **Sem proteção**: `ConnectServer`, `JoinServer`, `DataServer`, `MHPServer`,
  `MuEditor`, `Editor de conta Muemu`, `GetHardwareId`, `SSU_v1.0.4.164`.

Mecanismo de licenciamento observado no próprio código Lua legível:

```lua
local ALLOWED_CUSTOMER = "<CustomerName da licença — redigido>"
if GetLicenseCustomerName() ~= ALLOWED_CUSTOMER then return end
```

Somado a `Owner.ini [License] Owner=1`, `GetMainInfo-Premium.exe`, arquivos
`.premium`, `GetHardwareId.exe` e ao par `CustomerName`/`CustomerHardwareId` nos
`.ini`/`.dat`.

**Posição desta auditoria (não negociável):** nenhuma proteção de licença será
neutralizada, contornada ou falsificada, e nenhum serial/hardware ID será
reproduzido nos relatórios. Onde a licença é gate de funcionalidade, o trabalho
é documentar o requisito do fornecedor e diagnosticar falha de *configuração*
do uso autorizado. Ver `docs/DECISIONS.md` D-01.

Implicação técnica: como o `GameServer.exe` é empacotado, **não é possível**
recompilar, aplicar hotfix em C++, nem mesmo desassemblá-lo a partir do arquivo
em disco (o `.text` está cifrado). O que *é* possível — e foi feito — é ler o
código já descriptografado na **memória dos crash dumps**
(`tools/dump_disasm.py`), o que produziu o diagnóstico da §3 do relatório.

## 6. Plataforma-alvo

- Windows x86-64; os dumps registram `Windows 6.3 build 9600` (Server 2012 R2)
  e **8 CPUs**.
- Todos os serviços são **PE32 de 32 bits**. Os 4 GameServer têm imagem de
  46,5 MB e **não** têm `LARGEADDRESSAWARE` → teto de ~2 GB de espaço de
  endereço por processo. Ver P01 e `DECISIONS.md` D-03.
- Runtime: `msvcr100.dll`/`mscp100.dll` (Visual C++ 2010) distribuídos ao lado
  de cada serviço; `PSGuard/DLLS MYSQL WIN 32 BITS` (25,8 MB) e
  `DLLS SSL WIN 32 BITS` para o MHP/anti-cheat.
- Banco: SQL Server via DSN ODBC nomeado `MuOnline` (conferir
  `DB/MuOnline.reg`, 32 e 64 bits).

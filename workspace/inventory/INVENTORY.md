# INVENTORY — inventário global (Etapa A)

Medido em 2026-10-11 sobre `6eabb45`. Nenhum arquivo foi aberto em massa: as
contagens vêm de varredura de metadados (`find`/tamanho/hash), e a leitura de
conteúdo foi direcionada (Etapa C).

## Totais
- **10 021 arquivos**, 615 MB em `MuServer/` + 133 MB em `.git` = **748 MB**.
- 1 commit, sem histórico de evolução — não há como saber o que mudou entre versões.

## Por extensão (contagem, bytes)
```
 7230   241 934 589  .txt      <- 85% dos logs de runtime versionados
   22   112 994 800  .exe
   49    95 452 944  .dll
    5    50 374 404  .bak      <- 4 dumps de SQL Server com PII (50 373 632 B) + 1 xml.bak de config
  230    25 785 707  .ozt      (+83 .OZT, 72 .ozj, 34 .OZJ)
   56    22 720 859  .bmd
  276    18 088 764  .att      <- terreno, 256x256 + cabecalho de 3 bytes
   34     9 434 649  .dmp      <- 34 dumps de crash: a mina de ouro da auditoria
    1     8 196 096  .pdb      <- so de LuaEncryptorTool, nao do GameServer
  504     5 631 652  .tmp      <- lixo de sessao; contem codigo que so existe aqui
    7     5 263 724  .premium  <- licenca
   35     7 785 776  .png   1021  2 191 088 .jpg
    8     2 672 505  .smd     118    824 715 .dat
  148     753 497  .lua        19     77 243 .ini
   12     2 439 533  .rar        3     47 628 .hit    276 .att
    4        31 635 .sql  (as 4 sao os procs de ResetRankingWeb)
    2         2 359 .reg (DSN ODBC MuOnline 32/64)   2 .ps  30 .ssul  1 .lnk  1 .xml
```
Ausencias que definem o projeto: **0 arquivos** `.cpp .h .hpp .c .cs .sln .vcxproj
.vcxproj.filters .py .js .ts`. Não há fonte C++/C#, nem solution, nem build system.

## Por componente (arquivos, tamanho)
```
 3152  125M  SubSalatest        4 instancias de GameServer (mesmo exe)
 1888  105M  SpeedServer        idem
 1772  135M  Tools              editores, gerador de Main, StartUp
 1631   17M  Data               dados primarios (21 subdirs)
  466   14M  JoinServer         238 arquivos so em LOG_ACCOUNT
  329   77M  PSGuard            anti-cheat + DLLs MySQL/SSL 32-bit
  288   38M  ConnectServer      282 arquivos so em LOG
  222   22M  GameServer         inclui 18 dumps de crash
  155  2.4M  DataServer
   81   16M  GameServerCS       build DIFERENTE do GameServer
   16    2M  MHPServer
   12   18M  DiscordServer
    7   49M  DB                 5 .bak + 2 .reg
```

## Redundância medida (não é estimativa: comparação byte a byte)
- `MuServer/Data` × `SubSalatest/Data`: 1 439 idênticos, **169 diferentes**, 23 só no primeiro.
- `MuServer/Data` × `SpeedServer/Data`: 1 041 idênticos, **193 diferentes**, 397 só no primeiro.
- 3 cópias **byte-idênticas** de `GameServer.exe` (md5 `bddf82c5…`); a 4ª
  (`GameServerCS`) é build distinto (`facd2628…`, +266 KB).
- `ConnectServer.exe` e `ConnectServer_old.exe`: mesmo tamanho (380 416),
  builds diferentes (2017-10-03 vs 2021-08-13) — provável troca de nomes.
- `.tmp`: 504 arquivos → **146 conteúdos únicos** (71 % de redundância).

## Classificação por disponibilidade de fonte (seção 6 da missão)
| Classe | Componentes |
|---|---|
| 1. fonte disponível e compilável | **nenhum** |
| 2. fonte disponível, build pendente | **nenhum** |
| 3. binário sem fonte | ConnectServer, JoinServer, DataServer, MHPServer (sem protetor) · GameServer ×4, DiscordServer, LuaEncryptorTool, PSGuard/* (Themida) · MAIN_INFO/main.exe (VMProtect) |
| 4. dependência de fornecedor | `msvcr100/msvcp100` (VC++ 2010), `MHPDetect.dll`, DLLs MySQL/SSL 32 bit, `dpp/libsodium/opus/zlib/libssl/libcrypto` (Discord), Themida/WinLicense |
| 5. recurso/config não executável | tudo em `Data/**`, `.ozt/.ozj/.att/.bmd/.smd`, scripts Lua, `DB/*.bak` |

**Fonte modificável real = a camada Lua (28 arquivos × 3 instâncias) + a config/dados.**

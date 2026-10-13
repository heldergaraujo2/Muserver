# DEPENDENCIES_AND_LICENSES — dependências, licenças e o que falta verificar

| campo | valor |
|---|---|
| data | 2026-10-13 |
| regra aplicada | **ausência de licença não é autorização**. Nada de terceiros é apresentado como original, e nenhuma proteção foi (nem será) neutralizada |
| como foi medido | `#include` dos fontes, imports dos scripts Python, `find`/`ls` sobre o pacote, `reports/r5-pe.tsv` (importações dos PE), `workspace/docs/DEPENDENCIES.md` (fase anterior) |

## 1. Dependências do v2 (`recriado/`) — medidas

| dependência | versão medida | papel | licença |
|---|---|---|---|
| `cc`/`gcc` (Debian) | **12.2.0** | compilador C11 (`-std=c11 -O2 -Wall -Wextra -Werror`) | GPLv3 **com GCC Runtime Library Exception** (não afeta o código compilado) |
| GNU `make` | 4.3 | build | GPLv3 |
| `bash` | 5.2.15 | suítes de teste | GPLv3 |
| `python3` | 3.11.2 | sondas (somente leitura) | PSF License |
| `git` | 2.39.5 | versionamento/backup | GPLv2 |
| libc (glibc), sanitizadores ASan/UBSan | do compilador | runtime/teste | glibc (LGPL), ASan/UBSan (runtime do GCC) |

**Nenhuma biblioteca de terceiros é usada, embarcada ou vendored no v2.** Verificado por medição:

- `#include` de todos os `.c`/`.h` do produto: apenas cabeçalhos do sistema (`stdio.h`, `socket.h`,
  `poll.h`, …) e os próprios (`mu2/mu2.h`, `mu2/proto.h`);
- imports de todos os `tools/*.py`: apenas biblioteca padrão (`argparse`, `hashlib`, `math`, `os`,
  `pathlib`, `random`, `re`, `shutil`, `socket`, `statistics`, `struct`, `subprocess`, `sys`, `time`,
  `collections`).

O v2 não tem dependência de runtime além da libc — não há servidor, banco, framework nem pacote
instalável. Não há `CMakeLists`, `package.json`, `requirements.txt` ou similar: o contrato de build é
o `Makefile` (D2-13).

### 1.1 Licença do trabalho próprio

Medição: **não existe arquivo `LICENSE`, `COPYING` ou `NOTICE` em nenhum lugar do repositório fora de
`MuServer/`** (`find . -maxdepth 4 -iname 'LICENSE*' -o -iname 'COPYING*'` → 0 resultados). Ou seja:

- o código do v2 (`recriado/`) é trabalho do proprietário do repositório e **não tem licença
  declarada** — por padrão legal, "todos os direitos reservados";
- **pendência para o proprietário:** escolher e adicionar uma licença (e um `NOTICE` para
  atribuições) antes de qualquer redistribuição por terceiros.

## 2. Componentes do pacote de referência (`MuServer/`) — por tipo

O pacote é um upload do proprietário (commit `6eabb45`, `main`) e **não é trabalho original desta
recriação**. Classificação por tipo, com o que foi medido:

| componente | onde (exemplo medido) | tipo | licença / status |
|---|---|---|---|
| Executáveis do servidor (22 `.exe`: ConnectServer, DataServer, JoinServer, GameServer, GameServerCS, SpeedServer, SubSalatest, MHPServer, DiscordServer) | raiz dos diretórios de serviço | **proprietário de terceiros** (protegidos) | seções `.themida` ⇒ **Themida/WinLicense (licença comercial por HWID)**; redistribuir/contornar = vedado (D-01) |
| `Tools/Gerador de Main/**/{main.exe, GetMainInfo-Premium.exe}` + `.premium` | gerador do *main* do cliente | **proprietário** | **VMProtect** (comercial), por medição de seção/assinatura; autorização a verificar |
| `PSGuard/**` (`Servidor.32/64.exe`, `Monitor.exe`, `PS.dll`, `3DGuard.dll`) | anti-cheat | **proprietário/desconhecido** | origem e licença **a verificar**; screenshot/logs de terceiros no diretório |
| DLLs de runtime **Microsoft VC++ 2010** (`msvcr100.dll`, `msvcp100.dll`, 8 cópias cada) | pastas de serviço | redistribuível Microsoft | redistribuição permitida apenas conforme os termos do VC++ 2010 redistributable |
| Bibliotecas **MySQL** (`libmysql.dll`, `libmysqld.dll`) e **OpenSSL 1.0** (`libeay32.dll`, `ssleay32.dll`) | `PSGuard/DLLS *` | OSS com dupla licença | MySQL = GPLv2 **ou** licença comercial; OpenSSL = estilo Apache; **verificar a origem da build** |
| `libsodium`, `zlib1`, `opus`, `libssl-1_1`/`libcrypto-1_1`, `dpp` | `PSGuard/DLLS *`, outros | OSS | ISC / zlib / BSD / Apache-2.0 / a verificar (versão específica) |
| Módulos do cliente (`arcadia.dll`, `Premium.dll`, `CEffect.dll`, `Audio.dll`, `3DPlugin.dll`, `MHPClient.dll`) | árvores do gerador do main | **desconhecido** | origem, autoria e licença **a verificar** |
| Editores (`MuEditor`, `Editor de conta Muemu`, `Editores/*`) | `Tools/Editores/` | ferramentas de terceiros | **a verificar**; guardam **credenciais de banco em claro** (§`SECURITY.md`) |
| Procedures SQL (`WZ_*ResetInfo.sql`) | `Tools/ResetRankingWeb/` | artefato do proprietário/terceiro | **a verificar** (o `.sql` não traz cabeçalho de licença) |
| Assets do jogo (`.ozt` 313, `.jpg` 1 021, `.bmd` 56, `.att` 276, `.smd` 8, `.dat`/`.txt` de dados) | `Data/**`, `Tools/**` | **assets de terceiros** (jogo comercial MU Online / Season 6.20) | **sem licença no pacote**; direitos de Webzen/terceiros presumíveis — **não redistribuir como original** |
| `DB/*.bak` (4 backups, 50 373 632 B) | `DB/` | **dados de terceiros (PII)** | além da licença: incidente de privacidade — ver `SECURITY.md` §5 |
| `License.ps` (361 B, binário) | `.../MAIN_INFO v41 - Season 6/Premium/PS/` | — | **não é texto de licença legível**; conteúdo não interpretado |

Resumo honesto: **o pacote não contém um único arquivo de licença legível** e mistura componentes
comerciais (Themida/WinLicense, VMProtect, SQL Server), OSS e assets de terceiros. Não há base
documental, dentro do repositório, para afirmar que a redistribuição do pacote é autorizada — a
decisão e a verificação são do proprietário.

## 3. Dependências externas de infraestrutura (do servidor original, não usadas pelo v2)

| dependência | exigida por | status |
|---|---|---|
| **SQL Server** + driver ODBC `SQLSRV32.dll`, DSN `MuOnline` | JoinServer, DataServer, DiscordServer, GameServer, editores | comercial (Microsoft) — ver `DATABASE.md` |
| Windows (Win32/PE32) | todos os binários originais | o v2 **não** os executa; ambiente Linux |
| Serviço **Discord** (bot) | `DiscordServer` | dependência de serviço online de terceiros; token no `.ini` (§`SECURITY.md`) |
| `GetHardwareId.exe` + HWID de licença | Themida/WinLicense | vinculação por hardware — **não contornada** (D-01) |
| Tema/idioma do PSGuard e utilitários | `PSGuard/Utilitário*` | ferramentas de terceiros, a verificar |

## 4. Política já aplicada (não é proposta; é o que o repositório registra)

- **D-01** (`workspace/docs/DECISIONS.md`): nada de neutralizar, contornar ou forjar proteção/serial.
- **D2-25** (`docs/DECISIONS.md`): nenhum segredo entra em arquivo versionado; a redação das sondas é
  testada (`cfg` casos 7/8/11/13; `seguranca` caso 9; `admin` caso 19).
- Terceiros **não** são apresentados como originais: o README do projeto e os documentos de auditoria
  dizem, em texto, o que é trabalho novo e o que é pacote de referência.
- O v2 **não executa** nenhum binário do pacote (`interop` camada 3 `BLOCKED`; `enc` não roda o
  `LuaEncryptorTool.exe`).

## 5. Pendências de verificação (checklist do proprietário)

1. Adicionar `LICENSE` ao trabalho próprio (v2) e decidir a licença.
2. Verificar autorização de redistribuição dos binários/assets do pacote de referência — hoje
   públicos no repositório por upload do proprietário (`6eabb45`).
3. Confirmar as licenças das DLLs de terceiros (MySQL/OpenSSL/libsodium/opus/zlib/dpp) e das
   ferramentas (`MuEditor`, editores de conta, PSGuard).
4. Confirmar se `License.ps` e `.premium`/`*.premium` embutem termos contratuais de terceiros.
5. Rotacionar as credenciais expostas e tratar os backups de banco como incidente de privacidade
   (ação prioritária — `SECURITY.md` §5).

# PROTOCOLS — protocolos, formatos de comunicação e o que permanece desconhecido

| campo | valor |
|---|---|
| data | 2026-10-13 |
| regra | separa **comprovado** de **medido-por-análise-estática** de **desconhecido**; nenhuma compatibilidade com o cliente original é afirmada |
| leitura obrigatória conjunta | `reports/r6-relatorio.md`, `reports/r6-interop-relatorio.md`, `reports/rf-lua-protocolo.md`, `reports/enc-cifragem-lua.md` |

## 1. O protocolo que o v2 implementa (e o que ele **não** é)

Enquadramento próprio do v2, decidido em D2-11/D2-12 e escrito em `include/mu2/mu2.h`:

```
code (2 bytes, little-endian) | size (2 bytes, little-endian) | corpo
```

| item | valor | onde |
|---|---|---|
| `size` | comprimento **total**, cabeçalho incluído | `mu2.h`; `conform` C-07 |
| `MU2_HEADER_SIZE` | 4 | `mu2.h` |
| `MU2_MAX_BODY` / `MU2_MAX_FRAME` | 2048 / 2052 (D2-03) | `mu2.h`; `conform` C-03/C-04 |
| perfis | `orig` = corpo cru; `mur0` = corpo sob XOR posicional dependente do opcode, chave `{AE,EC,D8}`, **involutiva** — explicitamente **não é cifra** | `wire.c`, D2-12 |
| opcodes do serviço | `PING=0x0001` (corpo vazio), `ECHO=0x0002` (devolve o corpo), `STATS=0x0003` (linha ASCII) | `proto.h`, D2-16 |
| linha de STATS | `STATS registros= usados= conns= frames= rejects= queue_full_closes= uptime_ms= slotsz= maxbody=` (9 campos, ordem é contrato) | `proto.h`; `conform` C-11/C-12 |
| motivos de fechamento | `queue_full`, `client_eof`, `client_hup`, `socket_error`, `write_error`, `bad_frame`, `idle_timeout`, `max_clients`, `shutdown` | `proto.h`; `net`, `seguranca` |
| limites de conexão | teto de vagas 8192 (`--max-clients`), padrão 64; `--idle-ms`; `--sndbuf` | `mud2.c` |

**Isto é do v2, e os dois headers dizem isso em texto**: `proto.h` — *"Estes codigos sao do v2. NAO
sao opcodes do MU Server original"*; `mu2.h` — *"NAO e o formato do MuServer real recuperado"*.
Nenhuma linha deste documento autoriza dizer que o v2 "fala MU".

## 2. Camadas de evidência (a separação que a fase R-6 impôs)

| camada | o que afirma | estado | evidência |
|---|---|---|---|
| 1 — conformidade interna | o v2 obedece ao contrato acima, byte a byte | **comprovada** | `conform` 15/15 (C-01…C-15); `golden` 42/42 com 38 vetores |
| 2 — compatibilidade entre implementações **próprias** | `mud2` × `mu2ctl` × `netclient` × `mu2codec` concordam | **comprovada** | `net` 34/34; `net-matrix` 36/36 (opt-in); mesmo `wire.o` em todos |
| 3 — interoperabilidade com os binários **originais** | o v2 fala com o software original | **`BLOCKED`** | precondições ausentes (§4) |

Passar nas camadas 1 e 2 **não diz nada** sobre a 3 — e isso é asserção de teste (`interop` caso 4).

## 3. O que foi medido no pacote de referência (sem executar nada)

### 3.1 Endpoints (configuração é a fonte de verdade; nenhuma porta aparece como string nos `.exe`)

| serviço | chave | valor |
|---|---|---|
| ConnectServer | `ConnectServerPortTCP` / `ConnectServerPortUDP` | **44406** / **55557** |
| DataServer | `DataServerPort` | 55960 |
| JoinServer | `JoinServerPort` | 55970 |
| JoinServer → ConnectServer | `ConnectServerAddress` / `ConnectServerPort` | `127.0.0.1` / 55557 |
| DiscordServer | `DiscordServerPort` | 55990 |
| MHPServer | `MHPServerPort` | 55999 |
| PSGuard | `PortaPadrao` | 55998 |
| **cliente** (`MainInfo.ini`, 2 versões) | `IpAddressPort` | **44405** (com IP externo) |
| editores de conta/item | `PORT` (SQL Server) | 1433 |

**Divergência aberta, registrada e não resolvida:** o cliente aponta `44405` enquanto o
ConnectServer escuta `44406`. Sem captura de tráfego real, não se sabe qual está certo (hipótese
registrada na matriz `reports/r6-matriz.tsv` com confiança média).

Fonte: `tools/cfg_probe.py` sobre 19 `.ini` (655 pares chave/valor, **26 valores sensíveis
redigidos** — §`SECURITY.md`), evidência em `reports/r6-endpoints.tsv` e `reports/r6-config.tsv`.

### 3.2 `Data/Hack/HackPacketCheck.txt` — o espaço de índices do original

| medição | valor |
|---|---|
| entradas úteis | **272** |
| índices distintos | **256** — todos os valores 0..255 |
| bits mínimos para o maior índice | **8** |
| colunas por linha | 6 (`Index Value Encrypt MaxDelay MinCount MaxCount`) |
| `Encrypt = 1` / `= 0` / curinga | 37 / 234 / 1 |
| terminador | `end` |

O que **permite** concluir: o espaço de índices de pacote do original é de **8 bits e está
completamente enumerado**, com 37 pacotes marcados como criptografados e limites de taxa por pacote.
O que **não** permite: enquadramento (tamanho de cabeçalho, ordem dos campos, endianness) — a tabela
indexa pacotes, não descreve quadros.

### 3.3 Divergência quantificada: opcode do v2 × índices do original

`code` do v2 = **2 bytes** (65 536 valores) ⇒ **256×** o espaço de 256 índices do original. É
divergência **medida**, não prova de incompatibilidade (o enquadramento do original é desconhecido),
nem de compatibilidade.

### 3.4 Camada Lua e despacho de pacotes (lida do ORIGINAL, não do patcheado)

Do baseline `workspace/changes/originals/ProtocolCore.lua` (blob do commit de upload `6eabb45`):

- `BridgeFunctionAttach('GameServerProtocol','GameServerProtocolRecv')` e
  `GameServerProtocolRecv(aIndex, Packet, PacketName)` — o despacho é **por nome** (`PacketName`),
  com `Head` numérico nos logs (`Name: %s ... Head: %d`);
- **não há declaração de framing de bytes** nos scripts (tamanho de cabeçalho, offset, comprimento).

Medições: 148 `.lua`; 20 com termos de pacote; 5 chamando `SendPacket`; **8** cópias de
`ProtocolCore.lua` (3 de servidor, 5 do lado cliente). Correção registrada (D2-31): a frase da R-6
"0 declarações de framing em `.lua`" era verdadeira para os tokens procurados, mas a conclusão
"a camada Lua nada tem a ver com pacotes" era **falsa** — há camada real de despacho por nome. Ver
`reports/rf-lua-protocolo.md`.

### 3.5 O que **não** existe no pacote

| procurado | resultado |
|---|---|
| capturas de tráfego (`*.pcap`, `*.pcapng`, `*.cap`, `*.erf`) | **0** |
| cliente de jogo | **não há** — `main.exe` é saída do *Gerador de Main*; os 22 `.exe` são de servidor |
| especificação de protocolo (documento) | **não há** |

Sem captura e sem cliente, a camada 3 não fecha por análise estática — só por execução supervisionada.

## 4. Por que a interoperabilidade real está `BLOCKED` (causa exata)

| precondição | estado medido (2026-10-13) |
|---|---|
| `wine` / `wine64` / `wine32` / `qemu-i386` / `box86` / `box64` | **todos ausentes** |
| binários originais executáveis | 21 PE32/i386 + 1 PE32+; seções `.themida` impedem até distinguir `GameServer` × `GameServerCS` × `SpeedServer` |
| autorização para executar binário original | `MU_INTEROP_ALLOW_ORIGINAL` **não definida** |
| procedimento escrito de execução supervisionada | não existe |

**Condição de desbloqueio:** ambiente que execute PE32/i386 **e** autorização explícita **e**
procedimento. O mecanismo já está pronto: o procedimento manual deposita
`reports/r6-interop-real.tsv` com 8 chaves obrigatórias e `tests/interop.sh` **valida essa
evidência**; sem o arquivo, a etapa segue `BLOCKED` — nunca `PASS` por omissão.

## 5. Cifragens encontradas (nível de **arquivo**, não de rede) — estado honesto

Nenhuma das duas é protocolo de rede; ficam aqui porque são o que existe de "cripto" no material e
o auditor precisa do estado real de cada uma:

| alvo | o que foi medido | estado |
|---|---|---|
| `.bmd` (4 de 56) | camada XOR-3 com chave `ab fc cf` confirmada por âncora de conteúdo (`Data\Item\` no offset 12 do `Item.bmd`); **layout de registros não decodificado** | camada decodificada; layout **`NOT_IMPLEMENTED`** |
| scripts `.lua` do cliente (`LuaEncTool/`) | **estrutura medida**: 4 de 13 pares são byte-idênticos (não cifrados); 9 cifrados com cabeçalho fixo de 8 bytes `28aa2191a6dd35f7`; sem padding; determinística; `(A[j], C[j-1..j-3]) → C[j]` fecha em 0/2 510 repetições (com 2 bytes: 952/4 403). **Algoritmo não identificado** | **`BLOCKED`** — `reports/enc-cifragem-lua.md`; famílias refutadas com número; `F23` `BLOCKED` |

## 6. Desconhecidos (lista explícita, para não serem preenchidos por suposição)

1. Enquadramento do protocolo original: tamanho do cabeçalho, ordem/endianness dos campos.
2. Criptografia **de rede** do original (os 37 pacotes `Encrypt=1` da §3.2): algoritmo, chave e
   escopo (corpo? cabeçalho?) — **não medidos**.
3. Papel exato dos quatro componentes no tráfego (quem inicia, o que troca — a configuração sugere
   `cliente → ConnectServer(44406/55557) → JoinServer(55970)/DataServer(55960) → GameServer(55901…)`,
   mas isso é **leitura de configuração**, não tráfego observado).
4. A divergência `44405` × `44406` (§3.1).
5. Se o servidor original aceita pacotes maiores que 2048 (limite do v2 é decisão, D2-03 — não é
   afirmação sobre o original).
6. Semântica dos arquivos de dados do pacote além do que `rc-formatos-auditoria.md` demonstra.

## 7. Reprodução

```sh
cd recriado
make -s conform            # 15/15 — contrato do v2, byte a byte
make -s golden             # 42/42 — 38 vetores versionados
make -s interop            # 12 asserções, blocked=1 (camada 3 ausente)
python3 tools/cfg_probe.py # endpoints + segredos redigidos
python3 tools/interop_probe.py   # HackPacketCheck, ausências, divergências
python3 tools/lua_probe.py       # camada Lua, ProtocolCore, LuaEncTool
python3 tools/enc_probe.py       # cifragem dos .lua: o que a medição sustenta
```

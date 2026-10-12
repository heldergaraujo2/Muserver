# Etapa F — camada Lua, despacho de pacotes, e DUAS correções de afirmações publicadas

Este relatório existe porque duas coisas que estavam publicadas são falsas ou imprecisas. A regra
aplicada: prevalece a evidência atual, a divergência é registrada e o histórico não é apagado.

## Correção 1 — "0 declarações de framing em .lua" (R-6) está ERRADO

`reports/r6-matriz.tsv` e `reports/r6-interop.tsv` registram que a procura por `HEAD_SIZE`,
`PacketSize` e `opcode` em `.lua`/`.txt` devolveu zero ocorrências. A medição é verdadeira; a
**conclusão tirada dela é falsa**, porque os tokens eram estreitos demais.

Medido agora (`tools/lua_probe.py`, reproduzível):

| Medição | Valor |
| --- | --- |
| arquivos `.lua` no pacote | **148** (não 7 378 — esse número da R-6 era `.lua` + `.txt` somados) |
| `.lua` com termos de pacote (`SendPacket`, `ClearPacket`, `ProtocolCore`, …) | **20** |
| `.lua` que chamam `SendPacket` | 5 |
| cópias de `ProtocolCore.lua` | **8** — 3 de servidor, 5 do lado cliente |

A afirmação correta é: **não há declaração de framing de bytes** (tamanho de cabeçalho, offset,
comprimento) nos scripts; **há** uma camada real de despacho de pacotes por nome. São coisas
diferentes e a R-6 confundiu as duas.

## Correção 2 — "MuServer/ intacta" é impreciso

`recriado/tests/ref_check.sh` verifica `HEAD:MuServer == fade04615fab…` e isso passa. Mas essa
árvore é a **pós-endurecimento-Lua**: o commit `b5b84da` ("Auditoria e endurecimento da camada Lua
+ tooling de reengenharia"), ancestral desta branch, modificou **6 arquivos dentro de `MuServer/`**:

```
 MuServer/Data/Script/ScriptMain.lua             |   4 +-
 MuServer/Data/Script/System/ProtocolCore.lua    | 129 ++++++-
 MuServer/Data/Script/System/ScriptCore.lua      | 488 ++++++++++--------------
 MuServer/Data/Script/Utils/DataBase.lua         |  14 +-
 MuServer/SpeedServer/Data/Script/ScriptMain.lua |   4 +-
 MuServer/SubSalatest/Data/Script/ScriptMain.lua |   4 +-
 6 files changed, 327 insertions(+), 316 deletions(-)
```

Verificado nesta rodada:
- `MuServer/Data/Script/System/ProtocolCore.lua` tem md5 `9f371219805cbe52187e4b2e66f83c8a` e é
  **idêntico a `workspace/changes/patches/ProtocolCore.lua`**, não ao original
  (`04b0495b8cddb7d9f64b071660f57623`, que bate com `ORIGINALS.md5`).
- os 4 baselines em `workspace/changes/originals/` são **blob-idênticos** aos de `6eabb45` —
  a reversão (`git checkout 6eabb45 -- MuServer/`) é real, não prometida.
- `workspace/changes/CHANGELOG.md` documenta objetivo, justificativa e método de validação por
  entrada, e declara que nada foi empurrado para `main`.

Consequência prática: qualquer evidência sobre o **original** tem de vir de
`workspace/changes/originals/` ou das cópias não tocadas (`SpeedServer`, `SubSalatest`) — **nunca**
do arquivo patcheado. Este relatório segue essa regra.

Agora isso é testado: `tests/ref_check.sh` casos 7 e 8 fixam a contagem (6 `.lua`), a extensão e a
recuperabilidade dos baselines. "Referência intacta" passou a significar, explicitamente, "não mudou
desde `b5b84da`".

## Evidência nova e legítima sobre o protocolo (lida do ORIGINAL)

Do baseline `workspace/changes/originals/ProtocolCore.lua` (46 linhas, blob de `6eabb45`):

```lua
BridgeFunctionAttach('GameServerProtocol','GameServerProtocolRecv')
function GameServerProtocolRecv(aIndex, Packet, PacketName)
    ...
    LogColor(3, string.format("[ProtocolCore] Packet sem handler | aIndex: %d Name: %s Head: %d",
                              aIndex, PacketName, Packet))
    ClearPacket(PacketName)
```

Do lado cliente, `Tools/Gerador de Main/LuaEncTool/ClientDecrypted/System/ProtocolCore.lua`:

```lua
BridgeFunctionAttach('ClientProtocol','ClientProtocolRecv')
function ClientProtocolRecv(Packet, PacketName)
    ...
    ClearPacket(PacketName)
ProtocolFunctions.ProtocolRecv: Console(3, string.format("[ProtocolCore] Name: %s Head: %d",
                                                         PacketName, Packet))
    if PacketName == "WindowTitle" then SetWindowTitle("Testando") ...
```

O que isso permite concluir (e só isso):

| Conclusão permitida | Base |
| --- | --- |
| o GameServer entrega pacote ao Lua como `(aIndex, Packet, PacketName)` | assinatura no original, linha 10 |
| o cliente entrega como `(Packet, PacketName)` | assinatura cliente, linha 7 |
| `Packet` é **numérico** e tratado como "Head" | formatado com `%d` em 7 das 8 cópias |
| `PacketName` é **string** e identifica o tipo por **nome** | formatado com `%s` em 7 das 8; caso `"WindowTitle"` |
| existe função nativa `ClearPacket(PacketName)` | presente em 7 das 8 cópias |
| contrato de consumo: callback que devolve `true` encerra o despacho | laço no original |

O que **não** se pode concluir:
- o valor numérico de `Head` para cada pacote — nenhum mapa nome→número aparece nos scripts;
- o framing de bytes na rede — os scripts recebem o pacote já desenquadrado pelo binário;
- qualquer compatibilidade com cliente real — nada foi executado.

## Ferramenta de cifragem de script do cliente (achado)

`MuServer/Tools/Gerador de Main/LuaEncTool/` contém `LuaEncryptorTool.exe`, `.pdb`,
`EncryptorTool.ini` e os pares `ClientEncrypted/` × `ClientDecrypted/` e `ServerEncrypted/` ×
`ServerDecrypted/`. Medido: `ClientEncrypted/System/ProtocolCore.lua` começa com
`28 aa 21 91 a6 dd 35 f7` (sem cabeçalho reconhecível) e a versão decifrada correspondente é texto
legível com a assinatura acima. **O formato de cifragem não foi determinado** — afirmar o contrário
seria invenção; há um par conhecido, o que é ponto de partida, não resultado.

## Estado da Etapa F

| Item | Estado | Motivo |
| --- | --- | --- |
| inventário e evidência estática da camada Lua | **PASS** (13 asserções) | `tests/lua.sh` |
| verificação de sintaxe dos 148 `.lua` | **BLOCKED** | nenhum interpretador no host (`lua`, `lua5.x`, `luajit` ausentes) |
| execução da camada Lua | **BLOCKED** | idem, e os binários originais não são executados por política |
| formato de cifragem do script de cliente | **NOT_IMPLEMENTED** | só há um par cifrado/decifrado; formato não determinado |
| compatibilidade com cliente original | **BLOCKED** | `main.exe` existe apenas como saída do *Gerador de Main* e não foi executado; interoperabilidade real segue bloqueada (R-6) |
| dimensões/estrutura de `.ozt` (3D) | **NOT_IMPLEMENTED** | só há prefixo; nada além dele foi determinado (R-5) |

Reprodução: `make -s lua` (13 asserções, `blocked=1`, exit 0) e `make -s ref-intacta` (8 asserções).

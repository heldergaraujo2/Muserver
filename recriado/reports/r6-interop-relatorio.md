# R-6 / Etapa A — interoperabilidade com o software original

Artefato durável desta etapa: `tests/interop.sh` (12 asserções, `blocked=1`, exit 0) e
`tools/interop_probe.py` (somente leitura). O snapshot bruto da primeira medição está em
`reports/r6-interop.tsv`; a suíte regenera a cada execução em `out/interop/interop.tsv`.

## 1. As três camadas, medidas e separadas

A exigência central desta fase é não deixar uma camada passar por prova da seguinte. O estado real:

| Camada | O que é | Estado | Evidência |
| --- | --- | --- | --- |
| **1. Conformidade interna do protocolo v2** | o v2 concorda consigo mesmo byte a byte | **comprovada** | `tests/conform.sh` 15/15 (C-01…C-15, medido pelo socket); `tests/golden.sh` 42/42 (38 vetores versionados) |
| **2. Compatibilidade entre implementações próprias** | serviço `mud2` × `mu2ctl` × cliente de teste × codec CLI | **comprovada no v2** | `tests/net.sh` 34/34; corpora da R-6 (36/0 opt-in); `tests/golden.sh` usa o mesmo `wire.o` do serviço |
| **3. Compatibilidade com os executáveis originais** | o binário do pacote fala o mesmo protocolo? | **BLOCKED** | causa exata abaixo; nenhuma conexão original é simulada |

Camada 1 e 2 **não** dizem nada sobre a camada 3: ambas medem o v2 contra o v2. Isso está escrito no
cabeçalho do corpus golden e é asserção em `tests/interop.sh` (caso 4).

## 2. Evidência nova desta etapa (medida, sem executar nada)

Toda a evidência abaixo vem de arquivos do pacote, com o probe determinístico. Nenhum binário
original foi executado, nenhuma porta foi aberta, nada foi escrito em `MuServer/`.

### 2.1 `Data/Hack/HackPacketCheck.txt` — o espaço de índices do original

| Medição | Valor |
| --- | --- |
| entradas úteis | **272** |
| índices distintos | **256** — ou seja, **todos** os valores de 0 a 255 |
| menor / maior índice | 0 / 255 |
| bits mínimos para o maior índice | **8** |
| ocorrências redundantes | 16 (índices 77, 78 e 236 aparecem mais de uma vez) |
| colunas por linha | 6 (`Index Value Encrypt MaxDelay MinCount MaxCount`) |
| terminador | `end` presente |
| `Encrypt = 1` / `= 0` / curinga | 37 / 234 / 1 (o curinga é o índice 243) |

O que isso permite concluir: **o espaço de índices de pacote do original é de 8 bits e está
completamente enumerado (0..255)**, com 37 pacotes marcados como criptografados e limites de taxa
por pacote (`MaxDelay`, `MinCount`, `MaxCount`). É o artefato mais informativo do pacote para o
protocolo, e não requer executar nada.

O que **não** permite concluir: o layout de quadro na rede. A tabela indexa pacotes; ela não diz
tamanho de cabeçalho, ordem de campos nem enquadramento.

### 2.2 Divergência medida entre o v2 e o original

| Medição | Valor | Fonte |
| --- | --- | --- |
| campo `code` do v2 | **2 bytes** (65 536 valores possíveis) | `mu2codec encode --code 258` → `02010400` (0x0102 em LE é `02 01`) |
| `MU2_MAX_FRAME` do v2 | 2052 | `include/mu2/mu2.h` |
| espaço de índices do original | **256** valores | `HackPacketCheck.txt` |
| fator entre os dois espaços | **256×** | aritmética dos dois números acima |

Conclusão permitida: o campo de opcode do v2 é **duas ordens de grandeza mais largo** que o espaço
de índices do original. Isso é divergência medida, não opinião — e **não** é prova de
incompatibilidade total (o enquadramento do original é desconhecido), nem de compatibilidade.

### 2.3 O que **não** existe no pacote

| Procurado | Resultado |
| --- | --- |
| capturas de tráfego (`*.pcap`, `*.pcapng`, `*.cap`, `*.erf`) | **0** |
| declaração de framing (`HEAD_SIZE`, `PacketSize`, `MakePacket`, `opcode`) em 148 `.lua` | **0** |
| idem em 7 230 `.txt` | **0** |
| cliente de jogo | **não há** — `main.exe` existe uma única vez, como saída do *Gerador de Main*; os 22 `.exe` são todos de servidor |

Sem captura não há tráfego original observado para comparar; sem declaração de framing nos scripts,
o enquadramento não está documentado no pacote. É por isso que a camada 3 não pode ser fechada por
análise estática.

## 3. Por que a camada 3 está BLOCKED, e o que falta

| Precondição | Estado medido |
| --- | --- |
| `wine`, `wine64`, `wine32`, `qemu-i386`, `box86`, `box64` | **todos ausentes** |
| binários originais são PE32/i386 | R-5: 21 PE32/i386 + 1 PE32+ |
| proteção | seções `.themida` (R-5) — impedem distinguir `GameServer` × `GameServerCS` × `SpeedServer` |
| autorização para executar binário original | `MU_INTEROP_ALLOW_ORIGINAL` **não definida** |

**Condição de desbloqueio, concreta:** existir um ambiente capaz de executar PE32/i386 (wine ou
`qemu-i386`) **e** autorização explícita do proprietário **e** um procedimento escrito. O teste real
exige colocar o `ConnectServer.exe` em execução e conectar-se a ele — nenhuma dessas três coisas
existe hoje.

**Mecanismo implementado para quando existir:** `tests/interop.sh` **não tem caminho de execução de
binário original**. Quando as precondições existirem, o procedimento é manual e supervisionado e
deposita `reports/r6-interop-real.tsv` com 8 chaves obrigatórias (`procedimento`, `responsavel`,
`data`, `ambiente`, `resultado`, `servidor`, `original`, `cliente`, `evidencia`); a suíte então
**valida essa evidência** e passa a reportar `camada3=evidencia-manual-validada`. Sem o arquivo,
segue `BLOCKED` — nunca `PASS` por omissão.

## 4. Portas e configuração (herdado da R-5, verificado)

ConnectServer TCP **44406** / UDP 55557; DataServer 55960; JoinServer 55970; DiscordServer 55990;
MHPServer 55999; PSGuard 55998; cliente `MainInfo.ini` 44405 (divergência aberta, registrada na
R-5). 19 `.ini`, 655 pares, 26 valores redigidos por serem sensíveis.

## 5. Reprodução

```
make -s interop                      # 12 asserções, blocked=1, exit 0
python3 tools/interop_probe.py       # TSV de evidência (chave, valor, fonte)
make -s gate                         # 15 PASS / 0 FAIL / 1 BLOCKED / 286 asserções
```

Nota de registro: a frase publicada na R-6, "0 declarações de framing em .lua", era verdadeira
para os tokens procurados (`HEAD_SIZE|PacketSize|MakePacket|opcode`) e continua verdadeira para
**framing de bytes**; o que a R-6 errou foi a conclusão mais ampla de que a camada Lua nada teria a
ver com pacotes. A correção está em `reports/rf-lua-protocolo.md` e é caso de teste em
`tests/lua.sh`.

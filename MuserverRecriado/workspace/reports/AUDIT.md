# AUDITORIA TÉCNICA — MuServer MU Online Season 6.20
**Data:** 2026-10-11 · **Escopo:** os 10 021 arquivos de `MuServer/` · **Método:** descoberta progressiva, sem cópia integral no workspace

Este relatório separa explicitamente **fato medido**, **inferência com evidência** e **hipótese não provada**.

---

## 1. Severidade e prioridade

| # | Problema | Gravidade | Impacto | Confiança | Dificuldade | Status |
|---|---|---|---|---|---|---|
| A1 | Credenciais, token de bot e serial em texto puro versionados, mais 5 backups de banco com dados de jogadores | **CRÍTICA** | Divulgação de segredo; controle do servidor; LGPD | **medido** | baixa (rotação) / alta (histórico git) | **aguarda o proprietário** |
| A2 | Loop de crash do GameServer: 34 dumps, 100% com causa identificada; **7/7 correlacionados a 0–22 s após hot-reload** (p=1,5e-14) | **CRÍTICA** | Queda do serviço | **medido** | alta (binário protegido) | mitigação operacional entregue |
| A3 | Camada Lua sem nenhuma proteção de erro; handler órfão ⇒ `attempt to call a nil value` dentro do bridge | ALTA | Crash/estado inconsistente | **reproduzido em teste** | baixa | **CORRIGIDO** |
| A4 | `ProtocolCore` acumula handlers a cada reload (medido: 1→3→10 invocações por pacote) e mantém closures obsoletas vivas | ALTA | Custos crescentes + objeto vivo referenciando estado descartado | **reproduzido em teste** | baixa | **CORRIGIDO** |
| A5 | GameServer 32-bit **sem `LARGEADDRESSAWARE`**, imagem de 46,5 MB | ALTA | Exaustão de espaço de endereço | **medido** | **bloqueada** (Themida) | documentado, risco de patch avaliado |
| A6 | 4 `GameServerInfo` expõem `CustomerHardwareId`/`ServerSerial`; chaves de config zeradas candidatas a divisor | MÉDIA | Crash intermitente (6 dumps de `idiv`) | parcial | média | sinalizado no preflight |
| A7 | Dados: **17 spawns com retangulo invertido** em 6 046 linhas validadas, **27 linhas com menos colunas do que a secao exige**, **24 mapas com 1 310 spawns e sem `Terrain<map>.att`**; 1 094 rejeicoes cronicas de posicao | MEDIA | Monstros ausentes, erros de carga | **medido** | baixa | corrigivel pelo editor de dados (T2)
| A8 | Higiene: 296 MB de artefatos não-fonte versionados; 504 `.tmp` (71% redundantes); 3 copies de `GameServer.exe` idênticas | MÉDIA | Repo 748 MB, diff/checkout lentos | **medido** | baixa | `.gitignore`+script entregues |
| A9 | Divergência de config entre instâncias (`GameServerCS` tem build e `ExperienceList` distintos) | MÉDIA | Balanceamento inconsistente | **medido** | — | documentado, decisão do dono |
| A10 | Sistema PvP-balance recuperado **não está plugado** no servidor | BAIXA | Funcionalidade morta | **medido** | baixa | recuperado + sinalizado |

---

## 2. Como os dumps foram lidos (e por que o resultado é confiável)

O projeto não tinha nenhuma ferramenta de análise. Foi escrito um parser de
**minidump do Windows** em Python puro (`tools/minidump_analyze.py`), porque os
`.dmp` eram o único registro forense dos crashes.

Dois detalhes de formato foram determinados **por verificação empírica, não por
suposição** — ambos os modelos ingênuos produziram lixo na primeira tentativa:

1. A *stream directory* tem entradas de **12** bytes (`{tipo, DataSize, Rva}`), não 8.
2. O contexto de registradores **não é `CONTEXT` x86** e sim **`WOW64_CONTEXT`**
   (dump gravado por um helper de 64 bits sobre o processo de 32):
   `Ebp=+0xB4, Eip=+0xB8, SegCs=+0xBC, EFlags=+0xC0, Esp=+0xC4, SegSs=+0xC8`.
   A confirmação veio de invariantes independentes: o `Eip` lido bate exatamente
   com o `ExceptionAddress` da stream, `SegCs=0x23`, `SegSs=0x2B`,
   `EFlags=0x10246` e todos os ponteiros de pilha caem dentro da faixa de pilha
   da thread declarada no dump. Um layout errado não satisfaz tudo isso ao mesmo
   tempo.

E, o mais importante: **o `.text` do `GameServer.exe` está cifrado em disco
(Themida)**, então desassemblar o `.exe` seria inútil. A saída foi desassemblar o
código **na memória do próprio dump** (`tools/dump_disasm.py`), onde o protetor
já o descriptografou. Foi assim que cada família de crash ganhou uma causa
concreta em vez de um endereço cruft.

**Amostra:** 34 dumps, 1 com 0 bytes (`SpeedServer/2026-3-27_12h3m0s.dmp` —
truncado: o processo morreu enquanto escrevia o dump), 33 analisados, **0 erros
de parse**, 1 sem `ExceptionStream`.

---

## 3. Causa raiz dos crashes

### 3.1 Distribuição

```
 9x  ACCESS_VIOLATION  GameServer.exe+0xEC73D   READ
 8x  CPP_EH (0xE06D7363) KERNELBASE+0x11D4D     ← "pure virtual call", ver 3.2
 7x  ACCESS_VIOLATION  +0xBEBA2/+0xBEBC9/+0xBD702/+0xBD736  READ
 6x  INTEGER_DIVIDE_BY_ZERO  +0x17A979/+0x171F73/+0x15BAB0/+0x116153/+0x116165
 2x  ACCESS_VIOLATION  +0xB4201   WRITE
 1x  +0x14F7C (NULL+0x8) · 1x +0x116E96 · 1x sem stream
```

### 3.2 A família de 8 é *pure virtual call*, não um `throw` comum

`ExceptionInformation[0] = 0x19930520` — a constante mágica do `_purecall` da
MSVC (um `throw` normal seria `0x19930522`). E `EBX = 0x19930520` na hora da
falha. Significado: **chamada a um método virtual cujo vtable slot é o stub de
pure-virtual — o objeto já foi destruído (ou está em destruição) mas ainda é
referenciado.**

O backtrace é **determinístico e idêntico nos 8**, em dois builds diferentes:

```
KERNELBASE!RaiseException → GameServer+0x2141C4 → +0x1A7961 → +0x1A0992 → +0x11B5B → +0x3C858   (Speed/SubSala)
KERNELBASE!RaiseException → GameServer+0x218B8C → +0x1ABDA1 → +0x1A4DD2 → +0x11BFB → +0x3CD28   (GameServer)
```

Mesmo caminho, builds distintos, meses distintos (abril → agosto de 2026). Não é
corrupção aleatória: é um **defeito de projeto no caminho de recarga**.

### 3.3 Os 9+7 AVs são dois mecanismos clássicos, lidos diretamente do código

**(a) `+0xEC73D` — cópia em bloco estourando o fim da página.** Instrução da falha:

```asm
lea  eax, [ebp-0x1438]                       ; buffer de pilha de 5 176 bytes
mov  dword ptr [0x2fc55ec], 0
rep  movsd dword ptr es:[edi], dword ptr [esi]   <<<<<< FALHA (READ)
push eax
mov  ecx, 0x1501e68
```

Com `ESI` exatamente numa fronteira de página (`0x11881000`, `0x13FE5000`) e
`ECX` = contagem pequena restante (0xF, 0x7). Leitura além do fim do buffer de
origem, caindo numa página não comitada. Um dos backtraces contém
`mswsock.dll`/`ws2_32.dll` → caminho de I/O de rede. **Comprimento de cópia vindo
de dado não validado** contra um buffer de tamanho fixo.

**(b) `+0xBEBA2`/`+0xBD702`/`+0xBD736` — travessia de árvore STL corrompida.**
O código desassemblado é um lookup `std::map<unsigned short, …>` do MSVC:

```asm
mov  edx, [0x1a59974]          ; head/sentinel do map (em .data)
mov  esi, [edx]                ; primeiro nó
cmp  esi, edx / je fim         ; mapa vazio?
loop:
mov  ecx, [esi+0x20]           ; chave do nó
cmp  ecx, -1 / je next
movzx eax, word ptr [edi]      ; chave procurada
mov  eax, [esi+8]              ; filho direito
cmp  byte ptr [eax+0x0d], 0    <<<<<< FALHA (lea+0xD = flag _Isnil)
```

O nó lido em `[esi+8]` é lixo. **A árvore vermelho-preta está corrompida** — o
padrão de (i) modificação concorrente de um `std::map` sem lock entre a thread
do loop principal e a thread de I/O, ou (ii) `erase` durante iteração. Os dois
são exatamente o que um *reload* que destrói e recria objetos em execução produz
— igual ao 3.2. Aparece em duas instâncias do mapa (globals `0x1a3578c` e
`0x1a59974`), ou seja, dois mapas com o mesmo sintoma.

**(c) `+0xB4201` — sentinela `-1` usada como índice de array.**

```asm
imul ecx, edi, 0xa90                     ; 2704 = sizeof(elemento)
mov  eax, [ecx+0x14d9158]                ; pool de itens de 28 bytes
movups [eax], xmm0                       <<<<<< FALHA (WRITE)
add  dword ptr [ecx+0x14d9158], 0x1c
```

No dump: `EDI = 0xFFFFFFFF`, `ECX = 0xFFFFF570` = `-1 * 2704`. Ou seja, um
resultado "**não encontrado**" (`-1`) foi usado diretamente como índice. O
endereço escrito, `0x3F800000`, é o padrão de bits do `float 1.0` — confirma que
o valor foi lido de dados de configuração, não de um ponteiro válido.
**Índice não validado vindo de uma busca malsucedida.**

**(d) `+0x14F7C` — `NULL+0x8` após busca linear sem sucesso.** Laço que varre um
array global (stride `0x4C`, ~1 997 entradas), e no ramo "não achou" usa o
resultado nulo sem checagem. Ocorreu 22 s depois de `CashShop loaded successfully`.

**(e) 6× `INTEGER_DIVIDE_BY_ZERO` — divisor é um GLOBAL de config.** Todos os
cinco sítios têm a mesma forma:

```asm
mov  eax, [edi+0xd8]
add  eax, [edi+0x108]      ; (CLevel + Reset) plausível
cdq
idiv dword ptr [0x1f3373c] <<<<<< FALHA — divisor é global, valor 0
```

Em `+0x15BAB0` o global é indexado (`mov ecx, [eax*4 + 0x18f0270]`), ou seja, o
divisor é **elemento de vetor de configuração**: um único furo no vetor produz
divisão por zero só para um subconjunto de itens/níveis — compatível com a
intermitência. **Isto é corrigível sem tocar no binário**, pela configuração.

### 3.4 O gatilho: hot-reload (estatística, não intuição)

Reconstruí a janela temporal de cada crash a partir dos `LOG/` do próprio
servidor, e comparei com a linha de base empírica (9 082 eventos de reload em 138
dias de log):

| dia (SubSalatest) | Δ do reload anterior |
|---|---|
| 2026-04-07 | **0 s** |
| 2026-04-10 | **1 s**, 1 s, 1 s, 2 s (4 crashes em 85 s) |
| 2026-04-16 | **2 s** |
| 2026-08-22 | **22 s** |

`7/7` crashes com log disponível ocorreram ≤ 40 s após um reload. A
probabilidade de um instante aleatório cair nessa janela é **1,06 %** → probabilidade
de isso acontecer 7 de 7 vezes por acaso: **p = 1,5 × 10⁻¹⁴**.

Nota de honestidade: com 9 082 reloads e 7 crashes, a taxa é ~0,08 % por reload.
O reload **não** quebra o servidor de forma determinística — o que o resultado
sustenta é o padrão de **condição de corrida / defeito de vida útil** disparado
pelo reload, que é coerente com (a) objeto destruído ainda referenciado,
(b) árvore STL corrompida e (c) A4 acima.

**Corolário operacional (mitigação imediata, sem tocar em binário):** em
produção, não usar hot-reload; aplicar config reiniciando a instância.

### 3.5 O que foi **refutado** durante a auditoria

Registrar isto é parte do método — três hipóteses plausíveis caíram:

1. **"`Incorrect Monster Position` causa os crashes."** Refutado: 1 094 ocorrências
   crônicas em 93 dias, inclusive em dias sem crash. É defeito de dados, não causa
   de crash.
2. **"Os tiles rejeitados são intransitáveis."** Refutado por calibração empírica
   (`tools/terrain_check.py`): em Lorencia/Dungeon os rejeitados estão
   majoritariamente em atributo `0`, que é **70 % do mapa inteiro**. Falta de
   terreno explica os mapas 24/26/27 (que não têm `Terrain<map>.att`), não os demais.
3. **"`ProtocolCore` vaza buffer de pacote (`ClearPacket`)."** Refutado *antes* de
   "corrigir": o único handler que consome pacote (`TesteProtocol`) está
   **comentado** em `ScriptMain.lua` (`--requirefolder`), logo o `ClearPacket` do
   caminho não-tratado roda sempre hoje. Adicionar a chamada seria risco de
   double-free sem defeito a consertar. Registrado como **defeito latente**: qualquer
   handler que venha a retornar `true` sem `ClearPacket` vaza.

---

## 3.6 Auditoria de dados do mundo (`MonsterSetBase` → `Terrain`)

Fiz um validador estatico para os dados de spawn e **ele primeiro me enganou**. As
duas licoes desta secao valem mais que os numeros.

**Licao 1 — o formato tem duas caras.** `Data/MonsterSetBase/<NNN> - <Mapa>.txt`
alterna dois layouts no mesmo arquivo, separados por uma linha `0` ou `1`:

| secao | colunas |
|---|---|
| `0` = `[NPCS]` | `Monster Map Range X Y Dir Comment` |
| `1` = `[SPOTS]` | `Monster Map Range BeginX BeginY EndX EndY Dir Quantity Comment` |

Minha primeira versao assumiu um layout so e marcou **1 113 de 1 113 linhas** como
invalidas. Validador que acusa tudo nao acusa nada: virou AVISO ate distinguir os
formatos (e parar de acusar `Direction` negativa, que e valida neste pack).

**Licao 2 — e eu tinha um bug silencioso no meu proprio `as_int`.** Ele usava
`int(x, 0)`. Em Python 3, base 0 nao aceita `002` (trata como octal e lanca
`ValueError`) — e os dados do MU usam zero-padding em toda parte (`001`, `00`).
O resultado era o pior tipo de erro: `None` → linha ignorada → **check mudo**. A
correcao elevou a cobertura de **1 113 → 6 046 linhas validadas** e triplicou os
defeitos encontrados. E por isso existe `tests/test_preflight_selfcheck.py`
(DECISIONS D-07): ferramenta sem teste e ferramenta nao confiavel.

### O que esta errado de verdade (medido, nao presumido)
1. **17 retangulos de spawn invertidos** (`Begin > End`) em 6 mapas:
   `000 - Lorencia.txt:101`, `001 - Dungeon.txt:56`, `002 - Devias.txt:88,95`,
   `003 - Noria.txt:78`, `010 - Icarus.txt:45,48,49`, `033 - Aida.txt:90`. Ex.:
   `monster=839 map=10 Begin(78,36) > End(19,32)`. Corrigivel em minutos (T2).
   Nao sei se o servidor normaliza ou descarta — por isso e *defeito de dado* e
   nao *causa de crash*.
2. **27 linhas de 6 colunas dentro de secao `[SPOTS]` de 8 colunas** (ex.:
   `038 - Kanturu 2.txt:57-61`). Registro como AVISO: a consequencia exata depende
   do parser do `GameServer.exe`, que e protegido.
3. **24 mapas com spawns e sem `Terrain<map>.att`** no pack — 1 310 linhas.
4. Os logs registram **1 094 ocorrencias de `Incorrect Monster Position` em 93
   dias**. Fiz o cruzamento para nao contar a mesma coisa duas vezes: o mapa 1 tem
   **256 rejeicoes com apenas 92 entradas** (ou seja, o mesmo retangulo e rejeitado
   repetidamente) e **tem terreno**; o mapa 38 idem (199/43); os mapas 24/26/27
   **nao tem** terreno. Ou seja: **falta de terreno nao explica tudo**, e
   "posicao invalida" nao e sinonimo de "tile intransitavel" — o atributo dos tiles
   rejeitados era a moda do mapa. Deixei as duas afirmacoes separadas e nenhuma
   corrigida por palpite.

Contrato de formato que a tooling precisa respeitar (descoberto, nao documentado
em lugar nenhum): **LF** (nao CRLF, ao contrario do que se esperaria de um pack
Windows - medido em 8 719 arquivos de texto: 0 com CRLF puro) + `;` e `//` como comentario, chaves com espaco, nomes com
erro de grafia do fornecedor que **nao** se corrigem (`CustomChatSystemSwith`),
zero-padding numerico, `SQL_NO_DATA=100`.

## 4. Estado de segurança (A1) — detalhe

Valores **redigidos** aqui e em qualquer saída de ferramenta; a lista de
arquivos-origem é o suficiente para agir.

| Tipo | Onde | Formato redigido |
|---|---|---|
| `GlobalPassword` em texto | `JoinServer/JoinServer.ini` | `Py************@@` |
| **token de bot do Discord** | `DiscordServer/DiscordServer.ini` | `MT**********-…-c` |
| `CustomerHardwareId` | `DiscordServer.ini` + 4× `GameServerInfo - Common.dat` | `F4*…*E7` |
| `ClientSerial`/`ServerSerial` | `MHPServer.ini`, 4× `.dat`, 2× `MainInfo.ini` | `BR*…69` |
| senha em connection string | `JoinServer.ini`, `Tools/Editores/…/config.ini` | redigido |
| **PII de jogadores** | `DB/*.bak` — **4** dumps de SQL Server, 50 373 632 B, assinatura de media header `TAPE` no offset 0 | hashes de senha + dados de contas |

Agravantes: `MD5Encryption = 0` (senhas sem hash MD5 no JoinServer) e
`CaseSensitive = 0`; `MaxHardwareIdConnection = 0` (sem limite de vínculos por
hardware ID); `MaxIpConnection = 20`.

**Isto é um incidente, não uma melhoria:** o token do bot e os backups de banco
estão no histórico do Git de um repositório GitHub. A ordem correta é
(1) **revogar** o token do bot no Discord Developer Portal, (2) trocar a senha
global do `JoinServer`, (3) tirar os 4 `.bak` de banco do índice e do histórico (o 5º `.bak` do pack é `Tools/StartUp/Configuration/bor_StartUp.xml.bak`, texto de config: higiene, não incidente — a extensão sozinha não distinguia, e foi preciso ler a assinatura), (4) depois
disso é que faz sentido qualquer refatoração de config. Itens (1) e (2) só o
proprietário pode fazer. Ver `NEXT_TASK.md` T1.

---

## 5. Otimizações e correções implementadas

Ver `changes/CHANGELOG.md` para o diff arquivo-a-arquivo e
`tests/TEST_RESULTS.md` para a evidência executada. Resumo:

- **ScriptCore** (bridge Lua): despacho sob `pcall`, resolução tolerante de
  handler, estatísticas de erro anelares, `BridgeFunctionReset()`. **46 casos de
  teste**; paridade de comportamento comprovada contra o original em 29 cenários.
- **ProtocolCore**: registro idempotente **chaveado por arquivo:linha** (identidade
  de referência não basta: o reload recria a closure), substituição no lugar,
  `pcall`, `ProtocolFunctions.Reset()`. Teste mede 1×/3×/10× → 1× por pacote.
- **ScriptMain** (3 instâncias): `require('Utils\Database')` → `DataBase` — o nome
  real do arquivo. Passava em Windows por FS case-insensitive; quebraria em FS
  sensível a caixa.
- **DataBase.lua**: removidos args espúrios de `string.format` que liam globais
  inexistentes; `tostring()` num `SQLGetString` que podia ser `nil`.
- **Ferramental novo** (7 ferramentas + 2 suítes de teste), todas sem
  dependências obrigatórias fora do padrão, exceto disassembler/parse Lua opcionais.
- **`.gitignore`/`.gitattributes`** para os 296 MB de artefatos + proteção contra
  o Git reescrever CRLF dos `.ini`/`.dat` que o parser do servidor lê.

## 6. Testes: o que não foi possível executar

Testar de verdade exige Windows + SQL Server + cliente; o workspace é Linux.
Detalhe e lista de bloqueios em `tests/TEST_RESULTS.md`. Resumindo: foi possível
**reproduzir em runtime** a camada Lua (interpretador Lua real) e **analisar
forensemente** os crashes; **não** foi possível iniciar os serviços, validar
conectividade entre eles, nem testar em banco. Nada disso foi declarado como
verificado.

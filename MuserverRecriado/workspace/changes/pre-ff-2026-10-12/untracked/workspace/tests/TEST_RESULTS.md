# TEST_RESULTS — separado por componente e por categoria

Registro honesto: o que foi **executado**, o que foi **bloqueado** e o que **não
foi tentado**. Nada aqui foi marcado como verificado sem rodar.

Ambiente: Linux, sem Windows, sem SQL Server, sem cliente MU, sem .NET/MSVC.
Python 3.11.2 + `capstone`/`luaparser`/`lupa` em `/home/user/.venv-tools`
(`bash workspace/tests/run_all.sh` imprime o interpretador usado, para nada depender de suposição).

---
## Tabela-matriz (componente × categoria)
| Categoria | Connect | Join | Data | MHP | GameServer ×4 | Discord | PSGuard | Data (config) | **Lua** | DB |
|---|---|---|---|---|---|---|---|---|---|---|
| Boot/inicialização | ✗ bloqueado | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ estático | ✓ carregamento | ✗ |
| Conectividade | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ portas | — | ✗ |
| Auth/login | — | ✗ | — | — | ✗ | — | — | ✓ estático | ✗ | ✗ |
| Parsing de dados | ✓ OK | ✓ OK | ✓ OK | ✓ OK | ✓ OK | ✓ OK | — | ✓ **achou defeitos** | ✓ AST | — |
| Protocolo | — | — | — | — | ✓ só memória de dump | — | — | — | ✓ 11 casos | — |
| Persistência | — | ✗ SQL | ✗ SQL | — | ✗ SQL | ✗ SQL | — | — | ✓ 35 casos (SQL mock) | ✗ sem restore |
| Carga/estresse | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | — | — | ✓ descarte de closures | — |
| Segurança credencial | — | ✗ **achado** | — | — | — | ✗ **achado** | — | — | — | ✗ **achado** |
| Estabilidade | ✓ | ✓ | ✓ | ✓ | ✓ **33 dumps lidos** | ✓ | ✓ | ✓ | ✓ sem novos vetores | — |

Legenda: ✓ executado/medido · — não aplicável · ✗ bloqueado ou não tentado.

---
## Testes automatizados que existem e rodam (71 casos TAP + 2 verificações de porta, 0 falhas)
### 1. `test_scriptcore_differential.py` — 35/35
`ScriptCore.lua` patcheado × baseline, mesma entrada, mesma saída. Grupos:
- **A (13)** retorno de `BridgeFunctionCall` idêntico nos dois: `nil`, `0`,
  `false`, `true`, `"0"`, número, tabela, `0.5`; e as três convenções de erro
  (`-1`, `0`, `nil`) dos handlers de protocolo — inclusive `return 0`, que um
  "endurecimento" ingênuo converteria em sucesso de operação.
- **B (5)** cenário de crash presente no original e ausente no patch (handler
  órfão, reproduzido em Lua puro: `attempt to call a nil value`).
- **C (6)** o handler executa exatamente 1×, com argumentos intactos, com campo
  extra tolerado, erro de registro contido, estado consistente após falha.
- **D (11)** `ClearCache`: limpa os dois registros e os contadores de chamadas,
  recarrega sem acumular, tabela zerada não explode, `require` do sistema
  sobrevive, recarga real de arquivo modificado, ordem de iteração irrelevante.
Executa o arquivo **em produção** (`MuServer/Data/Script/System/`) e compara com o
baseline de `changes/originals/` — senão o teste diferencial seria
tautologicamente vero.

### 2. `test_protocolcore_reload.py` — 11/11
Ponte de protocolo real: registra 1→2→3→4 pacotes, mede acúmulo no baseline
(1→3→10 invocações, sem duplicação), confirma 0 após `ClearCache`, confirma
`ClearPacket` sem leak por construção (o baseline estoura antes), e a carga
funcional (código novo sem reindexar, tabela obsoleta que não trava, retorno
`-1`/`0` preservado, iteração determinística, recarga real de `EventMapManager`).
**Limitação declarada:** 11.º handler de protocolo não roda em lupa porque o
`EventMapManager` raiz usa `table.unpack`; o teste valida a lógica da ponte com o
mesmo stub e mede o acúmulo real no baseline com o arquivo original, que não usa.

Porta única: `bash workspace/tests/run_all.sh` roda os quatro itens abaixo e mais
as duas verificações de porta, e sai 0/1 (usável em CI). Ela mesma foi corrigida duas
vezes — veja o item 5.

### 3. `test_preflight_selfcheck.py` — 25/25
Autoteste das ferramentas, escrito **depois** de o P04 produzir 1 113 falsos
positivos e de `as_int` silently engolir linhas com zero à esquerda. Cobre:
`parse_ini` (seções, espaços no nome da chave, `;` e `//`), `as_int` (decimal com
padding, hex, não numérico), P04 com os **dois** formatos reais em fixture
(4 linhas, 2 defeitos, 0 falsos positivos em arquivo íntegro), `pe.py` contra o
`GameServer.exe` real (máquina x86, tamanho de imagem, LAA **ausente**, Themida
detectado, `rva2off`), e **9 asserções douradas** do parser de minidump sobre um
dump real do repositório.

### 4. `check_all_lua.py` — 56 verificados, 21 pulados, 0 inválidos
Parseia com `luaparser` **todos** os `.lua` das 3 árvores `Data/Script`. Substituiu
uma versão que só tentava UTF-8 e "ignorava" 22 arquivos latin-1 (com acentos nos
comentários) — ignorar é justamente o estado em que um arquivo corrompido passaria.
Agora: UTF-8 → UTF-8-BOM → Latin-1, e o que contém byte nulo nos primeiros 4 KB é
classificado como **binário cifrado pelo LuaEncryptorTool** (21 arquivos, cabeçalho
comum `0xAA 0x21 0x91 0xA6`), com nota de que o texto legível deles só existe em
`recovered/lua/`.

### 5. A própria porta de testes (corrigida duas vezes)
- Escolhia o `python3` do sistema em vez do venv → os testes de Lua falhavam por
  módulo ausente e pareciam defeito do código sob teste. Agora resolve
  `/home/user/.venv-tools/bin/python`, aceita `PYTHON=` e avisa se faltar.
- Tratava o exit code do preflight (1/2 = "achou defeitos", que é o trabalho dele)
  como falha. Agora exige apenas que a ferramenta rode e produza JSON válido com
  ≥ 11 checks, e reporta os ERROs como informação.

## Testes executados manualmente com evidência (não automatizados)
| Teste | Resultado |
|---|---|
| Leitura de 34 minidumps | 33 analisados, 1 truncado (0 B) reportado como tal |
| Validação do parser | 2 dumps de famílias distintas → RIP/offset/família batem com análise humana |
| Cross-check de contexto | `Eip` do `WOW64_CONTEXT` == `ExceptionAddress` do stream, em todos os dumps |
| Desassemblagem dos 5 sites de falha | cada família reproduzida na instrução exata (`rep movsd`, `idiv [cfg]`, `_Isnil`, `imul …,0xa90`) |
| Carga `ProtocolCore` antes do patch | 2 handlers órfãos ⇒ exceção não pega; 10 closures obsoletas ⇒ 9 chamadas a mais (duplicação confirmada) |
| Carga `ProtocolCore` depois do patch | 1 chamada exata por pacote, 0 obsoletas; **e** o original sob o dispatcher patcheado → 1 chamada exata, 9 obsoletas ainda chamadas |
| `luaparser` nos 4 arquivos alterados | todos válidos **antes e depois** do patch |
| `luaparser` nas 3 árvores `Data/Script` | 56 legíveis válidos, 21 cifrados identificados (virou `check_all_lua.py`) |
| decodificação de `GameServerInfo - Common.dat` (`iconv` + leitura em Python; `xxd` não existe neste sandbox, por isso `od`/Python no lugar) | é INI ASCII/CRLF; chaves de porta/serial/DB extraídas |

## Bloqueados e por quê (e o que desbloqueia)
| Bloqueio | Motivo | Necessário para rodar |
|---|---|---|
| boot dos serviços, conectividade, latência | só existem binários Windows, protegidos | VM Windows + ODBC 32-bit + SQL Server com os `.bak` restaurados |
| `SQLManager_Test.lua` | usa `Win32 API`/FFI do Lua **Windows** | mesmo ambiente |
| patch LAA (A5) | risco de violar integridade do Themida + sem Windows para medir | decisão do dono (T3) |
| teste de licença/anti-cheat | D-01 | fora de escopo |
| diff de versão/config por Git | repo tem 1 commit | histórico real ou arquivo de mudança do fornecedor |
| validação dos 17 spawns invertidos | não sei se o servidor normaliza Begin>End | servidor rodando, ou o interpretador do `GameServer` |

**Não tentado** (deliberado, para não operar fora do isolamento): restaurar os
backups de banco, conectar ao Discord, enviar tráfego de jogo a um servidor vivo.

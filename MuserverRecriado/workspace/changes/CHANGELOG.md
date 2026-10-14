# CHANGELOG — alterações implementadas

Rastreabilidade: cada entrada tem objetivo, justificativa técnica e método de
validação. Baseline pré-patch em `originals/`; cópia do resultado em `patches/`.
Para reverter tudo: `cp workspace/changes/originals/*.lua` de volta aos caminhos
indicados, ou `git checkout 6eabb45 -- MuServer/`.

Estado: **comitado na branch de trabalho `arena/cf1de8ce-muserver`**, que parte de
`6eabb45` (o `main` do dono). Nada foi comitado, forçado ou empurrado para `main`:
a decisão de merge é do dono. `git log --oneline` e `git diff 6eabb45 -- MuServer/`
reproduzem exatamente esta lista.

---

## C-01 · ScriptCore.lua — isolar erro de handler no bridge  [FIX SC-1..SC-4]
- **Arquivo:** `MuServer/Data/Script/System/ScriptCore.lua`
- **Baseline (md5):** `079e0a75ea19956759499a919b193cee` · **novo:** ver `git diff`
- **Objetivo:** um handler Lua com erro não pode derrubar o GameServer.
- **Justificativa:** o original invocava `_G[func.Function]()` sem `pcall` e sem
  checar se o nome existia. Todo handler registrado em bridge é executado dentro
  da thread de serviço do binário. Reproduzido em teste: handler com nome
  inexistente gera `attempt to call a nil value (field '?')` que escapa do bridge.
- **Mudanças:** `pcall` por handler; `Resolve()` tolera nome ou função; anel
  circular de 256 erros + `BridgeFunctionStats` com alerta rate-limited (1 a cada
  50) para não crescer sem limite num processo de 2 GB; `BridgeFunctionReset()`
  para permitir `/reload` limpo. Preservação exata da semântica de retorno de cada
  bridge (`ret~=0→1`, `ret==0→0`, `ret~=0→ret`) e de `Pack/Args` para não perder
  varargs com `nil` intercalado (o que `{...}` + `#` faria).
- **Validação:** `tests/test_scriptcore_differential.py` — 35 casos, 29 de paridade
  com o original e 6 provando as correções.

## C-02 · ProtocolCore.lua — registro idempotente  [FIX PC-1..PC-4]
- **Arquivo:** `MuServer/Data/Script/System/ProtocolCore.lua`
- **Baseline:** `04b0495b8cddb7d9f64b071660f57623`
- **Objetivo:** parar o acúmulo de handlers por reload.
- **Justificativa medida:** `GameServerProtocol_Handles` é `local` a um arquivo
  carregado só no boot, mas os `Scripts/` são recarregados e cada recarga
  re-executa `ProtocolFunctions.GameServerProtocol(...)`. O `table.insert`
  original não deduplica. Teste: 1 / 3 / 10 reloads → 1 / 3 / 10 invocações por
  pacote. Pior: a versão antiga permanece na lista, com closure fechada sobre o
  estado da carga anterior — o padrão de "objeto vivo referenciando estado
  descartado" que os dumps mostram.
- **Mudanças:** dedupe por `short_src:linedefined` (identidade de origem, porque
  a de referência **falha** no reload — a closure é recriada); substituição no
  lugar preservando a ordem; `pcall`; `ProtocolFunctions.Reset()`,
  `HandlerCount()`. **`ClearPacket` intencionalmente inalterado** (ver AUDIT §3.5.3
  — adicionar a chamada seria risco de double-free sem defeito comprovado).
- **Validação:** `tests/test_protocolcore_reload.py` — 11 casos.

## C-03 · ScriptMain.lua — caixa dos `require` (3 instâncias)
- **Arquivos:** `MuServer/Data/Script/ScriptMain.lua`,
  `MuServer/SpeedServer/Data/Script/ScriptMain.lua`,
  `MuServer/SubSalatest/Data/Script/ScriptMain.lua`
- **Baseline do principal:** `3fd88fca017221b57e6c1c8e8a3b9a51`
- **Objetivo/justificativa:** `require('Utils\Database')` apontando para
  `Utils/DataBase.lua` (B maiúsculo). Só funciona porque NTFS não diferencia
  caixa; em FS sensível a caixa, ou num loader que compare nomes exatos, o boot
  do Lua falha silenciosamente. Detectado pelo preflight (P05), não por leitura
  manual.
- **Validação:** `muserver_preflight.py` P05 passa de ERRO para OK nas 3 árvores.

## C-04 · DataBase.lua — limpeza defensiva  [FIX DB-1, DB-2]
- **Arquivo:** `MuServer/Data/Script/Utils/DataBase.lua` · baseline `dca8bc582d14105e1a72f612c3ff087e`
- DB-1: `string.format("SELECT top 1 Name from character order by name desc", codigo, itemid)`
  — a query não tem `%`, e `codigo`/`itemid` são globais nunca definidos (`nil`).
  Trocado por literal. Inofensivo em Lua 5.x, mas esconde variável fantasma.
- DB-2: `string.format("Teste query: %s", Name)` com `Name` possivelmente `nil`
  vindo de `SQLGetString` → virou `tostring(Name)`. `string.format` com `nil` é
  erro não protegido exatamente na função que decide se o servidor sobe com banco.
- **Não alterado:** lógica de `SQLConnect`/`SQLClose` e as queries em concatenação
  (ver "pendências" abaixo).

## C-05 · Higiene de repositório
- **Arquivos novos:** `.gitignore`, `.gitattributes` na raiz; `git core.autocrlf=false`.
- **Justificativa:** 295 940 074 bytes de artefatos não-fonte versionados
  (2 555 logs = 204 MB, 34 dumps = 9,4 MB, 504 `.tmp` = 5,6 MB, 5 `.bak` = 50 MB,
  230 `.ozt` = 25,8 MB) num repo de 748 MB (133 MB só de `.git`).
- `.gitattributes` fixa `eol=crlf` para `.ini/.dat/.txt/.lua/.sql/.reg`: o parser
  de INI do servidor lê esses arquivos em Windows; normalização de final de linha
  pelo Git é uma fonte clássica de "funcionava antes do clone".
- Marcadores binários explícitos para exe/dll/dmp/bak/ozt/ozj/att/bmd.
- **Nada foi apagado.** Remoção do índice é opcional e fica em `tools/untrack_artifacts.sh`.

## C-06 · Ferramentas entregues (novas, não tocam o runtime)
`workspace/tools/`: `muserver_preflight.py` (P01–P11), `minidump_analyze.py`,
`crash_families.py`, `dump_disasm.py`, `pe.py`, `scan_exes.py`, `terrain_check.py`,
`recover_tmp_lua.py`, `untrack_artifacts.sh`. `workspace/tests/`:
`test_scriptcore_differential.py`, `test_protocolcore_reload.py`, `run_all.sh`.

## C-07 · Recuperação de código perdido (adição, não modificação)
- **Saída:** `workspace/recovered/lua/` (146 conteúdos únicos + 2 relatórios).
- **Descoberta:** os 504 `MuServer/**/t*.tmp` (71 % redundantes) são resto de
  sessão do `LuaEncryptorTool`; entre eles está o script **"PvP Balance System
  (Skill + Combo Only)"** — `grep ALLOWED_CUSTOMER` no repositório inteiro casa
  **somente** em `.tmp` e `.dmp`. Ou seja, a única cópia legível desse código
  existia em lixo temporário, sujeita a ser apagada por qualquer `clean`.
- Nenhum `.tmp` foi removido (a remoção era justamente o que destruiria o código).

---

## C-08 · `muserver_preflight.py`: `as_int` parava em números com zero à esquerda
- **Arquivo:** `workspace/tools/muserver_preflight.py`
- **Objetivo:** a ferramenta de auditoria também é software e precisava de teste.
- **Justificativa:** `as_int` usava `int(x, 0)`. No Python 3, base 0 interpreta
  `0`-prefixo como octal e **lança `ValueError` para `002`/`008`** → o `except`
  devolvia `None` → o chamador tratava a linha como comentário e seguia. Os dados
  do MU usam zero-padding em toda parte (`001`, `00`, `000`), então o check P04
  ficava **mudo** e o P09 ignorava valores de config escritos `00`.
- **Mudança:** decimal explícito (`int(t, 10)`), base 0 só com prefixo `0x`/`0o`/`0b`.
- **Validação:** `tests/test_preflight_selfcheck.py` casos 5 e 6 cobrem exatamente
  isso. Efeito medido no dado real: cobertura do P04 de **1 113 → 6 046 linhas**
  validadas, e os defeitos de 4 → **17 + 27**. Achado antes deste fix, eu teria
  publicado um laudo com números subcontados.

## C-09 · `muserver_preflight.py` P04: distinguir os dois formatos de `MonsterSetBase`
- **Objetivo:** parar de acusar tudo.
- **Justificativa:** cada arquivo alterna seção `0` (`[NPCS]`, 6 colunas) e `1`
  (`[SPOTS]`, 8 colunas + Quantity). A primeira versão assumiu um layout só e
  marcou **1 113/1 113** linhas como inválidas. Também parei de acusar
  `Direction` negativa: os valores `-1..-8` são usados no pack e não são erro.
- **Mudança:** parser por seção + validação do que é provável estaticamente
  (coordenadas em 0..255, `Begin <= End`, `Range >= 0`) e duas classes de achado
  separadas: geometria inválida (**ERRO**) e linha com menos colunas que a seção
  exige (**AVISO**, porque a consequência depende do parser do `GameServer.exe`,
  que é protegido — não finci saber o que ele faz).
- **Validação:** fixtures dos dois formatos no autoteste, incluindo um caso
  "arquivo íntegro ⇒ zero defeitos" (anti falso positivo). Resultado no pack:
  **17** retângulos invertidos em 6 mapas, **27** linhas fora do formato,
  **24** mapas com 1 310 spawns sem `Terrain<map>.att`.

## C-10 · Higiene de repositório: `.gitignore`, `.gitattributes`, `core.autocrlf`
- **Objetivo:** impedir que a próxima sessão de trabalho transforme Lixo em dado e
  que o Git corrompa CRLF/encoding de config lida pelo servidor.
- **Justificativa:** 3 328 artefatos não-fonte estão versionados
  (295 940 074 B: 2 555 logs, 504 `.tmp`, 34 `.dmp`, 5 `.bak`, 230 `.ozt/.ozj`).
  E `mu_*.ini`/`*.dat` são ASCII/UTF-8 **com CRLF**: com `core.autocrlf=true` o
  checkout de um colaborador reescreve esses arquivos.
- **Mudanças:** `.gitignore` novo (LOG/, Logs/, `*.log`, `*.dmp`, `*.tmp`, `*.bak`,
  `obj/`, `bin/`, `workspace/recovered/`, `.vs/`, `desktop.ini`), `.gitattributes`
  novo (`text eol=crlf` para `.ini/.dat/.txt/.lua/.sql/.reg`, `binary` para
  exe/dll/pdb/dmp/bak/ozt/ozj/att/bmd/rar/imagens, `diff=astextplain` para
  `MuServer/Data/**`), `git config core.autocrlf false`. Comentários no
  `.gitignore` avisam que os `.tmp` hoje contêm a única cópia legível de script —
  **não** apagar antes de `recover_tmp_lua.py`.
- **Escopo deliberado:** nada foi removido do índice e nenhum histórico foi
  reescrito. `tools/untrack_artifacts.sh` é **dry-run por padrão** e exige
  `--apply`; a decisão de tirar 296 MB do histórico (`git-filter-repo`) é do dono,
  porque reescreve hash e quebra clones existentes.
- **Validação:** `git status --short` limpo quanto a artefatos novos, `git diff`
  dos `.lua` continua legível (CRLF preservado), e `git ls-files` batido contra o
  relatório do script.

## C-11 · Porta de testes: `run_all.sh` consertado, `check_all_lua.py` novo
- **Objetivo:** uma única porta verde/vermelha para o que foi corrigido.
- **Justificativa:** dois defeitos meus na primeira versão: (a) escolhia o
  `python3` do sistema em vez do venv, então os testes de Lua falhavam por
  `ModuleNotFoundError: lupa` e **pareciam** defeito do código sob teste; (b) tratava
  o exit code 1/2 do preflight — que significa "achei defeitos", o trabalho dele —
  como falha. Além disso o checador de sintaxe só tentava UTF-8 e "ignorava" 22
  arquivos latin-1, o estado exato em que um arquivo correntemente inválido passaria.
- **Mudanças:** resolução explícita do interpretador (com override por `PYTHON=` e
  aviso com o comando de setup se faltar o venv), preflight validado por "rodou e
  produziu JSON com ≥ 11 checks" em vez de exit code, e `check_all_lua.py` com
  UTF-8 → BOM → latin-1 e classificação de binário por byte nulo.
- **Validação:** `bash workspace/tests/run_all.sh` → **25 + 35 + 11 casos, 56 `.lua`
  verificados, 0 inválidos, preflight 57 resultados**, porta verde.

## Pendências deliberadas (nada aqui foi "esquecido")
1. **`BridgeFunction_OnUserItemUse`/`OnUserDamage`: `if ret ~= 0 then return ret end`.**
   Handler que não retorna nada devolve `nil`, e `nil ~= 0` é verdadeiro → o
   GameServer recebe "evento tratado". É bug, mas **mudaria regra de jogo**. Não
   alterei; recomendo decidir com o dono (ver NEXT_TASK T4).
2. **SQL por concatenação** em `Utils/DataBase.lua` (28 chamadas `SQLQuery`, 23
   queries montadas com `string.format`). Risco real de injeção, porém os nomes de
   personagem em MU são restritos a `[A-Za-z0-9]` e não há helper de escaping na
   API exposta pelo binário (`SQLQuery` só aceita string). Corrigir exige saber o
   validador do lado C++, que é protegido. Ver NEXT_TASK T5.
3. **`MHPServer.ini`: 8 `MemoryAddress*` absolutos** com valores de float
   (`0x40080000`-like) que não parecem endereços válidos de imagem, e
   `MemoryGuardSwitch=0`/`MacroProtectSwitch=0`: o anti-cheat está configurado mas
   desligado. Mexer aqui é decisão de operação, não de auditoria.
4. **`ConnectServer_old.exe` tem timestamp de build MAIS NOVO (2021-08-13) que o
   `ConnectServer.exe` "atual" (2017-10-03)**, com mesmo tamanho. Provável troca de
   nomes num upgrade. Não renomeei sem poder testar conectividade em Windows.

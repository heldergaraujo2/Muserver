#!/usr/bin/env bash
# regressao_lua.sh — regressão ESTÁTICA dos 6 arquivos .lua modificados dentro de `MuServer/`.
#
# Por que existe: `ref_check.sh` prova que a referência não mudou **desde** a árvore publicada; ele
# não prova que as 6 correções registradas em `workspace/changes/CHANGELOG.md` estão **presentes** no
# conteúdo, nem que dá para voltar ao original. Um `git checkout 6eabb45 -- MuServer/` apagaria as
# correções e o portão continuaria verde — este arquivo fecha esse buraco.
#
# O que ele é: verificação **estática** (texto + conteúdo do git). Nada aqui executa Lua, e nada aqui
# pode ser lido como "o script funciona": **não há interpretador Lua neste ambiente** e a execução
# segue BLOCKED (etapa `lua`, 13/13 com blocked=1). O limite está declarado no resumo e no
# `docs/TESTING.md`.
#
# Como os critérios são falsificáveis (exigência da tarefa): cada critério é uma função que recebe um
# arquivo. A suíte roda cada um três vezes — no arquivo corrigido (tem de passar), numa CÓPIA MUTADA
# no diretório temporário (tem de reprovar) e no baseline em `workspace/changes/originals/` (tem de
# reprovar, porque o baseline é o defeito). Critério que passa nos três não mede nada.
#
# Nada é escrito em `MuServer/`: o teste só lê, e o último caso prova isso.
#
# Contrato de saída: `# regressao-lua=<n> falhas=<f> blocked=<b>`
#   blocked=1 quando a referência não está neste ambiente (restore de bundle) ou quando o sistema de
#   arquivos não diferencia maiúsculas de minúsculas (o critério de `require` deixaria de medir).
#   blocked=2 quando o commit do upload não existe no repositório (clone raso).
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$(cd "$V2/.." && pwd)
REF=${MU_REF_DATA:-$ROOT/MuServer}
BASE=$ROOT/workspace/changes/originals
G="git -C $ROOT"
UPLOAD=${REG_LUA_UPLOAD:-6eabb45b9e7939a3061f4757ed6791efef7c5c3b}
n=0; bad=0; BLOQ=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

# ------------------------------------------------------------------ precondições (nunca viram PASS)
if [ ! -d "$REF" ]; then
  printf '1..0\n# regressao-lua=0 falhas=0 blocked=1\n'
  printf '# BLOCKED motivo=referencia_ausente (%s); desbloqueio: rodar no monorepo ou restaurar MuServer/\n' "$REF"
  exit 0
fi
if ! $G cat-file -e "${UPLOAD}^{commit}" 2>/dev/null; then
  printf '1..0\n# regressao-lua=0 falhas=0 blocked=2\n'
  printf '# BLOCKED motivo=objeto_do_upload_ausente (%s); desbloqueio: git fetch --unshallow\n' "$UPLOAD"
  exit 0
fi
# O sistema de arquivos precisa diferenciar caixa: o critério C-03 mede exatamente isso.
echo x > "$T/SENSIVEL"; mv "$T/SENSIVEL" "$T/sensivel"
if [ -f "$T/SENSIVEL" ]; then
  printf '1..0\n# regressao-lua=0 falhas=0 blocked=1\n'
  printf '# BLOCKED motivo=fs_insensivel_a_caixa; o criterio de require nao mediria nada neste volume\n'
  exit 0
fi

# ================================================================== A) os 6 arquivos, um por um
# Lista explícita: caminho no repositório → nome do baseline em workspace/changes/originals/
# (o baseline é "achatado" com `_` no lugar de `/`, convenção já usada pelo projeto).
MAP=(
  "MuServer/Data/Script/System/ScriptCore.lua:ScriptCore.lua"
  "MuServer/Data/Script/System/ProtocolCore.lua:ProtocolCore.lua"
  "MuServer/Data/Script/ScriptMain.lua:ScriptMain.lua"
  "MuServer/Data/Script/Utils/DataBase.lua:DataBase.lua"
  "MuServer/SpeedServer/Data/Script/ScriptMain.lua:MuServer_SpeedServer_Data_Script_ScriptMain.lua"
  "MuServer/SubSalatest/Data/Script/ScriptMain.lua:MuServer_SubSalatest_Data_Script_ScriptMain.lua"
)

esperados=$(printf '%s\n' "${MAP[@]}" | cut -d: -f1 | sort)
obtidos=$($G diff --name-only "$UPLOAD"..HEAD -- MuServer | sort)
ck "a divergencia vs upload sao EXATAMENTE os 6 .lua esperados (lista, nao contagem)" \
   '[ "$obtidos" = "$esperados" ]'

ck "os 6 estao rastreados pelo git" \
   'for p in $(printf "%s\n" "${MAP[@]}" | cut -d: -f1); do $G ls-files --error-unmatch "$p" >/dev/null 2>&1 || exit 1; done'

ck "os 6 estao limpos na arvore de trabalho (as correcoes estao COMITADAS, nao soltas)" \
   '[ "$($G status --porcelain -- MuServer | wc -l)" = 0 ]'

for par in "${MAP[@]}"; do
  p=${par%%:*}; b=${par##*:}
  ck "baseline de $p existe em workspace/changes/originals/$b" '[ -f "$BASE/$b" ]'
done

# Reversibilidade medida: restaurar o baseline produz o blob EXATO do upload. É a prova de que a
# volta é possível sem depender de repositório externo. (ref_check.sh cobre 4 destes 6; aqui os 6.)
for par in "${MAP[@]}"; do
  p=${par%%:*}; b=${par##*:}
  ck "reversao de $p: baseline == blob do upload ($UPLOAD)" \
     '[ "$($G hash-object "$BASE/$b")" = "$($G rev-parse "$UPLOAD:$p")" ]'
done

ck "os 4 md5 de workspace/changes/ORIGINALS.md5 batem com os baselines em disco" \
   'cd "$ROOT/workspace/changes" && while read -r h f; do
      bn=$(basename "$f"); [ "$(md5sum "originals/$bn" | cut -d" " -f1)" = "$h" ] || exit 1; done < ORIGINALS.md5'

# ================================================================== B) conteúdo: as correções presentes
# Cada `c_*` recebe o caminho de um arquivo e devolve 0/1. É o mesmo código usado no baseline (tem de
# reprovar) e nas cópias mutadas (têm de reprovar) mais abaixo.

# C-01 · ScriptCore: nenhuma invocação de handler sem pcall.
c_scriptcore_pcall() { ! grep -q "_G\[func" "$1" && grep -q "pcall(f" "$1"; }
# C-01 · anel de erros limitado, estatísticas e reset existem.
c_scriptcore_anel() {
  grep -q "BRIDGE_ERROR_RING_MAX = 256" "$1" && grep -q "BridgeFunctionStats" "$1" &&
  grep -q "function BridgeFunctionReset(" "$1" && grep -q "BRIDGE_WARN_EVERY = 50" "$1"; }
# C-01 · Resolve() tolera nome ou função (não estoura "attempt to call a nil value").
c_scriptcore_resolve() {
  grep -q "local function Resolve(fn)" "$1" && grep -q 'type(fn) == "string"' "$1"; }
# C-02 · registro idempotente chaveado por identidade de origem (short_src:linedefined).
c_protocolcore_dedupe() {
  grep -q "local function HandlerKey(fn)" "$1" && grep -q "debug.getinfo" "$1" &&
  grep -q "info.short_src, info.linedefined" "$1"; }
# C-02 · API nova de reload/preflight.
c_protocolcore_api() {
  grep -q "function ProtocolFunctions.Reset()" "$1" &&
  grep -q "function ProtocolFunctions.HandlerCount()" "$1"; }
# C-02 · o que NÃO podia mudar: o ClearPacket do caminho não-tratado continua exatamente uma vez.
c_protocolcore_clearpacket() { [ "$(grep -c "ClearPacket(PacketName)" "$1")" = "1" ]; }
# C-02 · handler chamado sob pcall no dispatch.
c_protocolcore_pcall() { grep -q "pcall(" "$1"; }
# C-04 · a query do top-1 virou literal (não um string.format sem % com globais nil).
c_database_query() {
  grep -q 'local Query = "SELECT top 1 Name from character order by name desc"' "$1" &&
  ! grep -q 'order by name desc", codigo' "$1"; }
# C-04 · log nil-safe.
c_database_tostring() { grep -q 'string.format("Teste query: %s", tostring(Name))' "$1"; }

# C-03 · todo `require`/`requirefolder` NÃO comentado resolve para arquivo/pasta existentes, com a
# caixa exata. Recebe o ScriptMain e o diretório-base da instância (onde os módulos vivem).
resolver_requires() {  # imprime as linhas "nao_resolveu=<modulo>"
  local arq=$1 base=$2 m p
  while read -r m; do
    [ -n "$m" ] || continue
    p=$(printf '%s' "${m//\\//}" | tr -s '/')   # "Utils\\DataBase" -> "Utils/DataBase"
    [ -f "$base/$p.lua" ] || printf 'nao_resolveu=%s\n' "$p.lua"
  done < <(grep -v '^[[:space:]]*--' "$arq" | grep -o "require('[^']*')" | sed "s/require('//;s/')//")
  while read -r m; do
    [ -n "$m" ] || continue
    p=$(printf '%s' "${m//\\//}" | tr -s '/')
    [ -d "$base/$p" ] || printf 'nao_resolveu=%s/\n' "$p"
  done < <(grep -v '^[[:space:]]*--' "$arq" | grep -o "requirefolder('[^']*')" | sed "s/requirefolder('//;s/')//")
}
c_requires_ok() { [ -z "$(resolver_requires "$1" "$2")" ]; }
# O critério do C-03 é sobre o que a correção mudou: nenhum módulo DataBase/DataBaseAsync pode ficar
# sem resolver. "Todos resolvem" é mais forte e só vale nas árvores onde é verdade — SubSalatest tem
# um require não resolvido PRÉ-EXISTENTE, que vem do upload e está registrado no bloco E.
c_requires_databases_ok() { ! resolver_requires "$1" "$2" | grep -qi "database"; }
# ^ grep -i e obrigatorio: o defeito original E a diferenca de caixa ("Database" no require,
#   "DataBase.lua" no disco). Com grep sensivel a caixa o criterio aprovava o proprio defeito.

ck "C-01 ScriptCore: handler nunca mais invocado por _G[] direto (0 bare, pcall presente)" \
   'c_scriptcore_pcall "$REF/Data/Script/System/ScriptCore.lua"'
ck "C-01 ScriptCore: anel limitado a 256, BridgeFunctionStats, BridgeFunctionReset, alerta 1-em-50" \
   'c_scriptcore_anel "$REF/Data/Script/System/ScriptCore.lua"'
ck "C-01 ScriptCore: Resolve(nome|funcao) existe e devolve nil em vez de estourar" \
   'c_scriptcore_resolve "$REF/Data/Script/System/ScriptCore.lua"'
ck "C-02 ProtocolCore: registro idempotente por short_src:linedefined (HandlerKey + debug.getinfo)" \
   'c_protocolcore_dedupe "$REF/Data/Script/System/ProtocolCore.lua"'
ck "C-02 ProtocolCore: ProtocolFunctions.Reset() e HandlerCount() existem" \
   'c_protocolcore_api "$REF/Data/Script/System/ProtocolCore.lua"'
ck "C-02 ProtocolCore: ClearPacket(PacketName) do caminho nao-tratado continua (intocado, 1x)" \
   'c_protocolcore_clearpacket "$REF/Data/Script/System/ProtocolCore.lua"'
ck "C-02 ProtocolCore: dispatch chama handler sob pcall" \
   'c_protocolcore_pcall "$REF/Data/Script/System/ProtocolCore.lua"'
ck "C-04 DataBase: query top-1 literal, sem string.format fantasma com globais nil" \
   'c_database_query "$REF/Data/Script/Utils/DataBase.lua"'
ck "C-04 DataBase: log do teste de query usa tostring(Name) (nil nao derruba o boot)" \
   'c_database_tostring "$REF/Data/Script/Utils/DataBase.lua"'

# C-03 · nas 3 instâncias: nenhum DataBase/DataBaseAsync sem resolver (é o que o patch corrigiu).
for d in "Data/Script" "SpeedServer/Data/Script" "SubSalatest/Data/Script"; do
  ck "C-03 $d/ScriptMain: DataBase e DataBaseAsync resolvem com a caixa exata do arquivo em disco" \
     'c_requires_databases_ok "$REF/'"$d"'/ScriptMain.lua" "$REF/'"$d"'"'
done
# C-03 · nas duas árvores onde vale, TODOS os requires não-comentados resolvem.
for d in "Data/Script" "SpeedServer/Data/Script"; do
  ck "C-03 $d/ScriptMain: todos os requires/requirefolder nao-comentados resolvem" \
     'c_requires_ok "$REF/'"$d"'/ScriptMain.lua" "$REF/'"$d"'"'
done
# C-03 · em SubSalatest, o ÚNICO não resolvido tem de ser exatamente o pré-existente (nada novo).
ck "C-03 SubSalatest: o unico require nao resolvido e o pre-existente Scripts/ReaddRequirement.lua" \
   '[ "$(resolver_requires "$REF/SubSalatest/Data/Script/ScriptMain.lua" "$REF/SubSalatest/Data/Script")" = "nao_resolveu=Scripts/ReaddRequirement.lua" ]'

# ================================================================== C) mutações: o critério DETECTA
# Cópia mutada no temporário. Se o critério não reprovar a mutação, ele não estava medindo nada.
muta() { cp "$1" "$T/$(basename "$1")"; python3 - "$T/$(basename "$1")" "$2" "$3" <<'PYX'
import sys
p, velho, novo = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert s.count(velho) >= 1, "mutacao nao encontrou o alvo: %r" % velho
open(p, "w", encoding="utf-8").write(s.replace(velho, novo, 1))
PYX
}
SC="$REF/Data/Script/System/ScriptCore.lua"; PC="$REF/Data/Script/System/ProtocolCore.lua"
DB="$REF/Data/Script/Utils/DataBase.lua"; SM="$REF/Data/Script/ScriptMain.lua"

muta "$SC" "local function Resolve(fn)" "local function Resolve(fn)"  # copia sã primeiro
muta "$SC" "ok, err = pcall(f, Args(args))" "ok, err = _G[func.Function](Args(args))"
ck "MUTACAO 1 (reintroduz _G[] sem pcall): c_scriptcore_pcall REPROVA a copia mutada" \
   '! c_scriptcore_pcall "$T/ScriptCore.lua"'
ck "MUTACAO 1b: o mesmo criterio APROVA o arquivo real (o teste distingue os dois)" \
   'c_scriptcore_pcall "$SC"'

muta "$SC" "BRIDGE_ERROR_RING_MAX = 256" "BRIDGE_ERROR_RING_MAX = 0"
ck "MUTACAO 2 (anel ilimitado): c_scriptcore_anel REPROVA a copia mutada" \
   '! c_scriptcore_anel "$T/ScriptCore.lua"'

muta "$SC" "local function Resolve(fn)" "local function ResolveSemTolerancia(fn)"
ck "MUTACAO 3 (remove Resolve): c_scriptcore_resolve REPROVA a copia mutada" \
   '! c_scriptcore_resolve "$T/ScriptCore.lua"'

muta "$PC" "local function HandlerKey(fn)" "local function HandlerKeyAntigo(fn)"
ck "MUTACAO 4 (remove a chave de identidade): c_protocolcore_dedupe REPROVA a copia mutada" \
   '! c_protocolcore_dedupe "$T/ProtocolCore.lua"'

muta "$PC" "	ClearPacket(PacketName)" ""
ck "MUTACAO 5 (apaga o ClearPacket do caminho nao-tratado): c_protocolcore_clearpacket REPROVA" \
   '! c_protocolcore_clearpacket "$T/ProtocolCore.lua"'

muta "$SM" 'Utils\\DataBase' 'Utils\\Database'
ck "MUTACAO 6 (desfaz a caixa do require, reabrindo o C-03): os DOIS criterios REPROVAM a copia" \
   '! c_requires_databases_ok "$T/ScriptMain.lua" "$REF/Data/Script" &&
    ! c_requires_ok "$T/ScriptMain.lua" "$REF/Data/Script"'

muta "$DB" 'local Query = "SELECT top 1 Name from character order by name desc"' \
           'local Query = string.format("SELECT top 1 Name from character order by name desc", codigo, itemid)'
ck "MUTACAO 7 (volta o string.format fantasma): c_database_query REPROVA a copia mutada" \
   '! c_database_query "$T/DataBase.lua"'

muta "$DB" 'string.format("Teste query: %s", tostring(Name))' 'string.format("Teste query: %s", Name)'
ck "MUTACAO 8 (tira o tostring): c_database_tostring REPROVA a copia mutada" \
   '! c_database_tostring "$T/DataBase.lua"'

# Mutação no BASELINE: prova que a checagem de reversibilidade detecta baseline alterado.
cp "$BASE/ScriptCore.lua" "$T/baseline-mutado.lua"
printf '\n-- byte intruso\n' >> "$T/baseline-mutado.lua"
ck "MUTACAO 9 (1 byte a mais no baseline): a checagem de reversao REPROVA a copia mutada" \
   '[ "$($G hash-object "$T/baseline-mutado.lua")" != "$($G rev-parse "$UPLOAD:MuServer/Data/Script/System/ScriptCore.lua")" ]'

# ================================================================== D) o baseline é o defeito
# O critério tem de reprovar o ORIGINAL — é isso que prova que ele mede alguma coisa.
ck "BASELINE ScriptCore reprova c_scriptcore_pcall (o defeito original e detectado)" \
   '! c_scriptcore_pcall "$BASE/ScriptCore.lua"'
ck "BASELINE ScriptCore reprova c_scriptcore_anel (nao havia anel nem stats)" \
   '! c_scriptcore_anel "$BASE/ScriptCore.lua"'
ck "BASELINE ScriptCore reprova c_scriptcore_resolve (nao havia Resolve)" \
   '! c_scriptcore_resolve "$BASE/ScriptCore.lua"'
ck "BASELINE DataBase reprova c_database_query (havia o string.format fantasma)" \
   '! c_database_query "$BASE/DataBase.lua"'
ck "BASELINE DataBase reprova c_database_tostring (o log nao era nil-safe)" \
   '! c_database_tostring "$BASE/DataBase.lua"'
for b in "ScriptMain.lua:MuServer/Data/Script" \
         "MuServer_SpeedServer_Data_Script_ScriptMain.lua:MuServer/SpeedServer/Data/Script" \
         "MuServer_SubSalatest_Data_Script_ScriptMain.lua:MuServer/SubSalatest/Data/Script"; do
  ck "BASELINE ${b%%:*} reprova o criterio do C-03 (a caixa errada e detectada)" \
     '! c_requires_databases_ok "$BASE/'"${b%%:*}"'" "$REF/'"${b##*:MuServer/}"'"'
done

# ================================================================== E) achado PRÉ-EXISTENTE (não é nosso)
# Medido em 2026-10-13 e registrado aqui para nunca ser confundido com regressão do patch:
# `SubSalatest` usa `require('Scripts\ReaddRequirement')` no lugar de `requirefolder(...)` — o alvo
# `Scripts/ReaddRequirement.lua` não existe (o módulo mora dentro da pasta homônima). A linha é
# IDÊNTICA no baseline e no patch: vem do upload, não do nosso trabalho.
ck "achado pre-existente SubSalatest: a linha do ReaddRequirement e identica no baseline e no patch" \
   '[ "$(grep -c "ReaddRequirement" "$BASE/MuServer_SubSalatest_Data_Script_ScriptMain.lua")" = "1" ] &&
    [ "$(grep -c "require(.Scripts..ReaddRequirement.)" "$BASE/MuServer_SubSalatest_Data_Script_ScriptMain.lua")" = "1" ] &&
    [ "$(grep -c "require(.Scripts..ReaddRequirement.)" "$REF/SubSalatest/Data/Script/ScriptMain.lua")" = "1" ]'
ck "achado pre-existente SubSalatest: o patch NAO aumentou o numero de requires nao resolvidos" \
   '[ "$(resolver_requires "$REF/SubSalatest/Data/Script/ScriptMain.lua" "$REF/SubSalatest/Data/Script" | wc -l)" -le \
      "$(resolver_requires "$BASE/MuServer_SubSalatest_Data_Script_ScriptMain.lua" "$REF/SubSalatest/Data/Script" | wc -l)" ]'
todas_as_instancias_sem_databases_orfaos() {
  local d
  for d in "Data/Script" "SpeedServer/Data/Script" "SubSalatest/Data/Script"; do
    c_requires_databases_ok "$REF/$d/ScriptMain.lua" "$REF/$d" || return 1
  done
  return 0
}
ck "o patch corrigiu os DataBase/DataBaseAsync nas 3 instancias (0 nao-resolvidos de DataBase*)" \
   'todas_as_instancias_sem_databases_orfaos'

# ================================================================== F) o teste não escreveu na referência
ck "MuServer/ continua limpa depois da suite (o teste so leu)" \
   '[ "$($G status --porcelain -- MuServer | wc -l)" = 0 ]'

# ------------------------------------------------------------------ resumo
printf '# limite=estatico; execucao_lua_nao_observada (sem interpretador Lua no host - ver etapa lua)\n'
printf '1..%d\n# regressao-lua=%d falhas=%d blocked=%d\n' "$n" "$n" "$bad" "$BLOQ"
[ "$bad" -eq 0 ] || exit 1

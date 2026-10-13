#!/usr/bin/env bash
# golden.sh — corpus de referência byte a byte do codec v2.
#
# O caminho exercitado é o codec real: out/mu2codec liga contra out/wire.o, o mesmo objeto do
# serviço e do mu2ctl. Não há reimplementação do codec aqui — comparar uma reimplementação com
# ela mesma não prova nada.
#
# Os valores esperados estão em tests/golden/quadros.tsv, derivados à mão do contrato
# (include/mu2/mu2.h + src/wire.c) e revisáveis. São referências INTERNAS do protocolo v2:
# não afirmam compatibilidade com o MU Server original.
#
# Diagnóstico é parte do contrato desta suíte: uma divergência tem de dizer QUAL vetor e QUAL
# byte. Sem isso a falsificação F20 não tem como ser demonstrada.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
BIN=$V2/out/mu2codec
CORPUS=${GOLDEN_CORPUS:-$V2/tests/golden/quadros.tsv}
n=0; bad=0; BL=0; rods=0; aprovs=0; reprovs=0; falsif=0
ck() { n=$((n+1)); if "${@:3}" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi; }

[ -x "$BIN" ] || { printf '1..0\n# golden=0 falhas=0 blocked=1\n# BLOCKED motivo=falta out/mu2codec (make build)\n'; exit 0; }
[ -f "$CORPUS" ] || { printf '1..0\n# golden=0 falhas=0 blocked=1\n# BLOCKED motivo=corpus ausente %s\n' "$CORPUS"; exit 0; }

# offset da primeira diferenca. Hex par é comparado byte a byte (é o que F20 exige: "qual byte");
# qualquer outra coisa é comparada por caractere. Imprime sempre os dois lados.
diff_offset() {
  local a=$1 b=$2 i n la=${#1} lb=${#2}
  if [ $la -lt $lb ]; then n=$la; else n=$lb; fi
  if [ $((la % 2)) -eq 0 ] && [ $((lb % 2)) -eq 0 ]; then
    i=0
    while [ "$i" -lt "$n" ]; do
      if [ "${a:i:2}" != "${b:i:2}" ]; then
        printf 'offset_byte=%d esperado=%s obtido=%s' "$((i/2))" "${a:i:2}" "${b:i:2}"; return 0
      fi
      i=$((i + 2))
    done
    [ "$la" -ne "$lb" ] && { printf 'offset_byte=%d comprimento_esperado=%d comprimento_obtido=%d' \
      "$((n/2))" "$((la/2))" "$((lb/2))"; return 0; }
    printf 'sem_diferenca'; return 0
  fi
  i=0
  while [ "$i" -lt "$n" ]; do
    [ "${a:i:1}" != "${b:i:1}" ] && { printf 'offset_char=%d esperado=%s obtido=%s' "$i" \
      "${a:i:1}" "${b:i:1}"; return 0; }
    i=$((i + 1))
  done
  printf 'sem_diferenca'
}

campo() { sed -n "s/^$2=//p" <<<"$1" | head -1; }
# hex completo de 2048 bytes tem 4096 caracteres: no diagnostico vai truncado, com o comprimento
# real dito, para que a linha caiba num terminal sem esconder que havia mais.
corta() { local s=$1
  if [ ${#s} -le 128 ]; then printf '%s' "$s"
  else printf '%s...(+%d chars)' "${s:0:128}" $(( ${#s} - 128 )); fi; }

# ---------------------------------------------------------------- corpus
while IFS=$'\t' read -r id op perfil code flags entrada esperado exitx classe clausula origem just; do
  case "$id" in ''|'#'*) continue;; esac
  [ "$id" = id ] && continue                       # linha de cabeçalho
  rods=$((rods + 1))
  args=("$op")
  case "$perfil" in
    num:*) args+=(--profile-num "${perfil#num:}");;
    *)     args+=(--profile "$perfil");;
  esac
  [ "$code" != "-" ] && args+=(--code "$code")
  if [ "$flags" != "-" ]; then
    # shellcheck disable=SC2206  # flags do corpus são fixas e revisáveis, não entrada externa
    f=($flags); args+=("${f[@]}")
  fi
  ent=$entrada; { [ "$ent" = "-" ] || [ "$ent" = VAZIO ]; } && ent=""
  case "$op" in
    encode|roundtrip|transform) args+=(--body-hex "$ent");;
    decode|body)                args+=(--in-hex "$ent");;
  esac
  OUT=$("$BIN" "${args[@]}" 2>/dev/null); RC=$?

  caso="[$id] $op/$perfil"
  [ "$code" != "-" ] && caso="$caso code=$code"
  ok=1; det=""
  if [ "$RC" != "$exitx" ]; then
    ok=0; det="exit_esperado=$exitx exit_obtido=$RC"
  fi
  if [ "$esperado" = "-" ]; then
    # quadro recusado: o que se confere é a classe (e que não veio resultado=OK)
    obt=$(campo "$OUT" classe)
    if [ "$classe" != "uso-invalido" ] && [ "$obt" != "$classe" ]; then
      ok=0; det="$det classe_esperada=$classe classe_obtida=${obt:-nenhuma}"
    fi
    if printf '%s' "$OUT" | grep -q '^resultado=OK$'; then
      ok=0; det="$det inesperado:resultado=OK"
    fi
  else
    case "$op" in
      encode|transform) chave=hex;;
      decode)           chave=decode;;
      *)                chave=corpo_hex;;
    esac
    obt=$(campo "$OUT" "$chave")
    exp=$esperado; [ "$exp" = VAZIO ] && exp=""
    if [ "$obt" != "$exp" ]; then
      ok=0; det="$det $chave: $(diff_offset "$exp" "$obt")"
    fi
  fi
  if [ "$ok" = 1 ]; then
    aprovs=$((aprovs + 1))
    printf 'ok %d - %s\n' "$((n + 1))" "$caso"
    n=$((n + 1))
  else
    reprovs=$((reprovs + 1)); bad=$((bad + 1)); n=$((n + 1))
    printf 'not ok %d - %s | %s\n' "$n" "$caso" "${det# }"
    printf '#   clausula=%s\n#   origem=%s\n#   justificativa=%s\n' "$clausula" "$origem" "$just"
    if [ -n "${exp:-}" ] || [ -n "$obt" ]; then
      printf '#   esperado_completo=%s\n#   obtido_completo=%s\n' "$(corta "$exp")" "$(corta "$obt")"
    fi
  fi
done < "$CORPUS"

# Falsificações só na execução de fora: as rodadas internas (GOLDEN_CORPUS apontando para a cópia
# mutada) usam GOLDEN_NO_FALSIF=1, senão cada uma dispararia a própria F20/F21 e a contagem de
# 'not ok' deixaria de isolar o vetor corrompido.
if [ -z "${GOLDEN_NO_FALSIF:-}" ]; then
# ---------------------------------------------------------------- F20: corromper UM byte
# O corpus é copiado para área temporária; o original é conferido por sha256 antes e depois. Se a
# suíte não disser QUAL vetor e QUAL byte, F20 reprova — é exatamente isso que está em jogo.
CORPUS_SHA_ANTES=$(sha256sum "$CORPUS" | awk '{print $1}')
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
MUT=$TMPD/quadros-mutado.tsv
# G-03 tem esperado 02000700cd8eb9; trocar o byte 4 (cd -> ce) é UM byte, no campo esperado.
awk -F'\t' 'BEGIN{OFS="\t"} $1=="G-03"{$7="02000700ce8eb9"} {print}' "$CORPUS" > "$MUT"
GOLDEN_CORPUS="$MUT" GOLDEN_NO_FALSIF=1 bash "$V2/tests/golden.sh" > "$TMPD/f20.out" 2>&1
RC_F20=$?
falsif=$((falsif + 1))
t_f20() { [ "$RC_F20" -ne 0 ] &&
          grep -q '^not ok .* \[G-03\] ' "$TMPD/f20.out" &&
          grep -q 'offset_byte=4 esperado=ce obtido=cd' "$TMPD/f20.out" &&
          [ "$(grep -c '^not ok' "$TMPD/f20.out")" = 1 ]; }
ck $((n + 1)) "F20 um byte corrompido em G-03: suíte falha, nomeia o vetor, o offset e só ele" t_f20
CORPUS_SHA_DEPOIS=$(sha256sum "$CORPUS" | awk '{print $1}')
t_f20b() { [ "$CORPUS_SHA_ANTES" = "$CORPUS_SHA_DEPOIS" ]; }
ck $((n + 1)) "F20 o corpus original permanece inalterado (sha256 confere)" t_f20b

# ---------------------------------------------------------------- F21: trocar o perfil
# G-13 é o caso discriminante: quadro codificado em mur0, esperado desfazendo a transformacao.
# Lido como orig, o quadro continua VÁLIDO (o enquadramento é o mesmo) — só o corpo difere. É isso
# que garante que a falha vem da seleção de perfil, e não de um arquivo inválido por outro motivo.
MUT2=$TMPD/quadros-perfil.tsv
awk -F'\t' 'BEGIN{OFS="\t"} $1=="G-13"{$3="orig"} {print}' "$CORPUS" > "$MUT2"
GOLDEN_CORPUS="$MUT2" GOLDEN_NO_FALSIF=1 bash "$V2/tests/golden.sh" > "$TMPD/f21.out" 2>&1
RC_F21=$?
falsif=$((falsif + 1))
t_f21() { [ "$RC_F21" -ne 0 ] &&
          grep -q '^not ok .* \[G-13\] body/orig' "$TMPD/f21.out" &&
          grep -q '\[G-13\] body/orig | corpo_hex: offset_byte=0 esperado=61 obtido=cd' "$TMPD/f21.out" &&
          [ "$(grep -c '^not ok' "$TMPD/f21.out")" = 1 ] &&
          ! grep -q 'classe_obtida' "$TMPD/f21.out"; }
ck $((n + 1)) "F21 perfil trocado em G-13: quadro segue valido, corpo difere e a suíte falha" t_f21
t_f21b() { [ "$(sha256sum "$CORPUS" | awk '{print $1}')" = "$CORPUS_SHA_ANTES" ]; }
ck $((n + 1)) "F21 o corpus original permanece inalterado depois da troca de perfil" t_f21b

fi   # fim do bloco de falsificações

printf '1..%d\n# escopo=golden:codec-v2-interno\n' "$n"
printf '# golden=%d falhas=%d blocked=%d\n' "$n" "$bad" "$BL"
printf '# vetores_executados=%d vetores_aprovados=%d vetores_reprovados=%d falsificacoes=%d\n' \
  "$rods" "$aprovs" "$reprovs" "$falsif"
printf '# corpus=%s\n' "${CORPUS#$V2/}"
printf '# aviso=referencias internas do protocolo v2; NAO afirmam compatibilidade com o original\n'
[ "$bad" -eq 0 ] || exit 1

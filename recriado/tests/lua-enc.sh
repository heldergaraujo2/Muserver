#!/usr/bin/env bash
# lua-enc.sh — Etapa `enc`: cifragem dos scripts Lua do cliente (Tools/Gerador de Main/LuaEncTool).
#
# O QUE ESTA ETAPA PROVA E O QUE ELA NAO PROVA (declarado ANTES de medir, ver
# reports/enc-cifragem-lua.md):
#
#   provado por medicao: os 13 pares do material (4 byte-identicos = nao cifrados, 9 cifrados com
#   8 bytes de cabecalho fixo), a relacao de tamanho (payload == claro com LF contado a mais, sem
#   padding), o determinismo da cifragem, e a ESTRUTURA da recorrencia (a janela de 3 bytes do
#   proprio cifrado + o byte de claro determinam o proximo byte: 0 discordancia em 2510 repeticoes;
#   com 2 bytes a mesma janela acusa 952/4403 => 3 e' o menor tamanho que fecha).
#
#   NAO provado: o ALGORITMO. A funcao da janela permanece desconhecida; nenhuma hipotese casou o
#   texto claro BYTE A BYTE (unico criterio de prova aceito nesta etapa). Por isso:
#     * `enc_f23` = BLOCKED: F23 exigiria um decodificador para corromper 1 byte e acusar o offset;
#     * `blocked=1` no resumo. BLOCKED nunca vira PASS aqui.
#
# BLOCKED ambiental: sem MU_REF_DATA (o pacote do servidor) nao ha material a medir.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
PROBE=$V2/tools/enc_probe.py
OUTD=$V2/out/lua
OUT=$OUTD/enc.tsv
GOLD=$OUTD/enc-golden.esperado
REF=${MU_REF_DATA:-../MuServer}
ENC="$REF/Tools/Gerador de Main/LuaEncTool"
n=0; bad=0; BL=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

[ -f "$PROBE" ] || { printf '1..0\n# lua-enc=0 falhas=0 blocked=1\n# BLOCKED motivo=probe ausente\n'; exit 0; }
if [ ! -d "$ENC" ]; then
  printf '1..0\n# lua-enc=0 falhas=0 blocked=1\n# BLOCKED motivo=material ausente (%s)\n' "$ENC"; exit 0
fi
mkdir -p "$OUTD"; rm -f "$OUT" "$GOLD" 2>/dev/null

# somente leitura: o hash da arvore do material tem de ser o mesmo antes e depois do probe
hash_antes=$(cd "$ENC" && find . -type f -print0 | sort -z | xargs -0 md5sum | md5sum)
MU_REF_DATA="$REF" python3 "$PROBE" > "$OUT" 2>"$OUTD/enc.err"
RC=$?
if [ "$RC" -ne 0 ]; then
  printf '1..0\n# lua-enc=0 falhas=0 blocked=1\n# BLOCKED motivo=probe saiu %d\n' "$RC"; exit 0
fi
hash_depois=$(cd "$ENC" && find . -type f -print0 | sort -z | xargs -0 md5sum | md5sum)
printf '# escopo=lua-enc:estrutura+cifragem (algoritmo NAO identificado; sem decodificador)\n'

val() { awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$OUT"; }
tem() { awk -F'\t' -v k="$1" '$1==k{f=1} END{exit !f}' "$OUT"; }

# ---- inventario e cabecalho (criterio C1)
ck "13 pares claro/cifrado no material (12 do cliente + 1 do servidor)" \
   "[ \"\$(val enc_pares)\" = 13 ]"
ck "4 pares byte-identicos (NAO cifrados): ScriptMain.lua, NewWindow/Config.lua,
    TesteProtocol/Config.lua e WindowTitle/Config.lua — md5 fixado" \
   "[ \"\$(val enc_nao_cifrados)\" = 4 ] && \
    [ \"\$(awk -F'\t' '\$1==\"enc_nao_cifrado\"{print \$2}' \"\$OUT\" | sort | tr '\n' ' ')\" = \
      '33ac67a4442ddd5b47e9c5cbfcc0ccca 4f802ab6717c854d4938fbc33fa9ed2a 6993e2e06953c02419fd9d07a49ad44f d0ad621fc8500ea5266fda6f110d00c8 ' ]"
ck "9 pares cifrados, todos com os 8 bytes de cabecalho 28aa2191a6dd35f7 (criterio C1)" \
   "[ \"\$(val enc_cifrados)\" = 9 ] && [ \"\$(val enc_header8_presente)\" = 9/9 ] && \
    [ \"\$(val enc_header8)\" = 28aa2191a6dd35f7 ]"
ck "relacao de tamanho em 9/9: len(cif) - 8 == len(claro) + nº de LF (sem padding, criterio C1)" \
   "[ \"\$(val enc_tamanho_crlf)\" = 9/9 ]"

# ---- determinismo (criterio C2)
ck "determinismo em 6/6 pares com prefixo de claro comum: 0 violacoes (menor prefixo comum = 33 B)" \
   "[ \"\$(val enc_determinismo_prefixo)\" = '0 violacoes em 6 pares com prefixo de claro comum' ]"
ck "vetor de prefixo conhecido: 'local CONFIG = r' -> 14cca1192748a387fd51b74ba7a41574
    (pos=0, igual nas arvores cliente e servidor)" \
   "[ \"\$(val enc_prefixo_conhecido)\" = 14cca1192748a387fd51b74ba7a41574 ]"

# ---- estrutura medida (criterios C3/C4) — estrutura, NAO algoritmo
ck "janela de 3 bytes do cifrado + byte de claro determinam o proximo byte: 0/2510 contradicoes
    (criterio C3 declarado: exigir 0)" \
   "[ \"\$(val enc_recorrencia_janela3)\" = 0/2510 ]"
ck "a mesma janela preve tambem ENTRE arquivos (previsao fora da amostra): 0/890" \
   "[ \"\$(val enc_recorrencia_janela3_entre_arquivos)\" = 0/890 ]"
ck "das 2510 repeticoes, 1206 tem historia profunda DIFERENTE (A[j-1], C[j-4], C[j-5]): a janela de 3
    basta, nao e' coincidencia de vizinhanca" \
   "[ \"\$(val enc_recorrencia_janela3_historia_profunda)\" = 1206/2510 ]"
ck "necessidade da janela de 3 (criterio C4): com 2 bytes => 952/4403 contradicoes;
    com 1 byte => 9813/14068" \
   "[ \"\$(val enc_recorrencia_janela2)\" = 952/4403 ] && [ \"\$(val enc_recorrencia_janela1)\" = 9813/14068 ]"
ck "janela sem ambiguidade: 0/1613 casos de mesma janela + claro diferente com MESMO cifrado
    (condicao necessaria de decodificacao unica)" \
   "[ \"\$(val enc_janela_ambiguidade)\" = 0/1613 ]"
ck "controle de alinhamento: com alinhamento ERRADO (claro cru + zeros no fim) a mesma janela acusa
    74/294 => o alinhamento declarado (LF contado a mais) nao e' arbitrario" \
   "[ \"\$(val enc_controle_alinhamento)\" = 74/294 ]"
ck "limite registrado: trocar CRLF por 00 00 mantem a contagem e TAMBEM fecha (0/2510) => esta
    medicao NAO decide o VALOR dos bytes inseridos, so a contagem" \
   "[ \"\$(val enc_controle_valor_inserido)\" = 0/2510 ]"

# ---- familias refutadas (criterios C5/C6/C7)
ck "refutado keystream puro: (C1,C2,C3) -> (C^A) acusa 1149/3735 contradicoes" \
   "[ \"\$(val enc_keystream_janela)\" = 1149/3735 ]"
ck "refutado o mesmo para soma: (C1,C2,C3) -> (C-A mod 256) acusa 1082/3735" \
   "[ \"\$(val enc_diferenca_janela)\" = 1082/3735 ]"
ck "refutado XOR/soma com chave repetida: nenhum periodo k <= 512 fecha o keystream (criterio C6)" \
   "[ \"\$(val enc_excl_xor_repetido)\" = '0 chaves com periodo <= 512' ]"
ck "refutado ECB: gcd dos 9 payloads = 1 (nenhum tamanho de bloco > 1 fecha) e 8/9 nao sao multiplos
    de 8 nem de 16 (criterio C7)" \
   "[ \"\$(val enc_excl_ecb)\" = 'gcd(payloads)=1, 8/9 nao multiplos de 8 nem de 16' ]"
ck "refutada a familia C = A (xor|soma) T[g] com g entre 6 indices de (A,S1,S2,S3): o MELHOR caso
    ainda erra 90.74% (xor) e 90.50% (soma) da amostra" \
   "[ \"\$(val enc_excl_tabela_xor)\" = '90.74% de erro (indice (A<<1)^S1)' ] && \
    [ \"\$(val enc_excl_tabela_soma)\" = '90.50% de erro (indice (A*3+S1))' ]"
ck "refutada a familia ARX ((A^ka)+rot(S1,r1)+rot(S2,r2)+rot(S3,r3)+kc) & 255: 0 sobreviventes em
    16384 combinacoes (r em 0..3, verificacao declarada nas 512 primeiras amostras)" \
   "[ \"\$(val enc_excl_arx)\" = '0 sobreviventes em 16384 combinacoes' ]"
ck "refutado XOR/ADD repetido tambem pela MELHOR periodicidade: k=224 acerta 16.50% no prefixo de
    2048 B e 7.09% no corpus (nao existe chave repetida)" \
   "[ \"\$(val enc_excl_xor_repetido_melhor)\" = 'melhor k=224: 16.50% de acerto (prefixo de 2048 B), 7.09% no corpus inteiro' ]"
ck "informacao medida (nao conclusao): entropia do claro 5.512 e do payload cifrado 7.916 bits/byte" \
   "[ \"\$(val enc_entropia_claro)\" = 5.512 ] && [ \"\$(val enc_entropia_cifrado)\" = 7.916 ]"

# ---- vetores de ouro (claro, cifrado) por sha256 — o que a etapa PODE fixar sem decodificador
cat > "$GOLD" <<'EOF'
enc_par_ScriptMain_lua 948e70155ca71a25bb4661c49098ee7581f61b33c8031fa11c9bd8beff4901d1
enc_par_Scripts_NewWindow_Config_lua 77debdc7264b8d20be2ed11abb5edc69db94484b2a878f91d6f4753f4dd1df09
enc_par_Scripts_NewWindow_NewWindow_lua 1879ba40a6065951ec0cbeb5daa66a3c5757c38250fe514d70d238f6a1879c76
enc_par_Scripts_TesteProtocol_Config_lua 45fbd6915a5e799ab2af75bce5a6cb2f1592daadb9f7f69f6c7a4c71dd2fe6a6
enc_par_Scripts_TesteProtocol_TesteProtocol_lua ee0dace0429d7236894a3843d49111b4b5b540d270751edc0fbb7dacf0e3bd79
enc_par_Scripts_WindowTitle_Config_lua 6504babc59c77657b4067d55a2ca90d7d8ea6b1016b9915bdf1d588bc3d89f48
enc_par_Scripts_WindowTitle_WindowTitle_lua 4f15f2031364b1acc45e945014553541ede9d4bb30904477f9a8ff9f3455ead6
enc_par_System_LoadImages_lua 4eff7c221637a5e16780f1c8955bfe57a9fcfa40c85c38247778c6863c5958d3
enc_par_System_ProtocolCore_lua 24002f24f4ade02e558bcb249c662ab089fb618c7eb6942fbe0ac8e0200f984f
enc_par_System_ScriptCore_lua 1999f87103e9b08ccf768ba7dd6189257033e89e270833ea6a354b0f3db5cca2
enc_par_Util_Defines_lua c67b043fce4d49a308c6b7e86640224296fc0873461701a79e84f7e43945da13
enc_par_Util_KeysValue_lua 880691c2f6bdce1446fc9d3e8dd056f521353f0c9b8c0aabd46059141cd025e3
enc_par_Scripts_AutoPost_AutoPost_lua dff1b426d7851e9e0108e87b9287dfcc74588b56ac892499cf71248822ffee67
EOF
ck "golden: os 13 vetores (claro, cifrado) batem com o sha256 fixado — regressao de BYTES do material
    (com o algoritmo desconhecido nao existe vetor de decifracao a fixar)" \
   "awk -F'\t' '\$1 ~ /^enc_par_/ {print \$1\" \"\$2}' \"\$OUT\" | diff -q - \"\$GOLD\""
ck "o SHA-256 do texto claro acompanha cada vetor (ProtocolCore: claro a12d3358b35b476e, 944 B;
    cifrado 24002f24f4ade02e, 992 B)" \
   "grep -q 'claro 944 B sha256 a12d3358b35b476e | cifrado 992 B' \"\$OUT\""

# ---- guardas de escopo
ck "somente leitura: o hash da arvore do material (30 arquivos) e' o mesmo antes e depois do probe" \
   "[ -n '$hash_antes' ] && [ '$hash_antes' = '$hash_depois' ]"
ck "o binario do cliente NAO foi executado por esta etapa (sha256 fixado, so' leitura)" \
   "[ \"\$(val enc_executado)\" = 0 ] && [ \"\$(val enc_exe)\" = bf0656b11ecb65a3b22084f80488f661981aa88a12ebcd7e52b85887b31df2a0 ]"
ck "ScriptSystem.premium (766 B) fica registrado por hash e NAO classificado (nem afirmado nem
    negado): b7be712210cde9d1" \
   "[ \"\$(val enc_premium)\" = b7be712210cde9d172e41b92da15312ffeb31e308e8708989d074fc5614cb73f ]"
ck "probe deterministico: duas execucoes produzem o mesmo TSV" \
   "MU_REF_DATA=\"\${MU_REF_DATA:-../MuServer}\" python3 '$PROBE' | diff -q - '$OUT'"

# ---- o que NAO foi provado: conta como BLOCKED, nunca como PASS
printf '# BLOCKED motivo=algoritmo nao identificado: nenhuma hipotese casou o claro byte a byte; a funcao da janela de 3 bytes permanece desconhecida (dominio 2**32, 21931 amostras)\n'
printf '# BLOCKED motivo=F23: sem decodificador nao ha como corromper 1 byte do cifrado e exigir o offset exato\n'
BL=2
[ "$(val enc_f23)" = blocked ] || bad=$((bad+1))

printf '1..%d\n' "$n"
printf '# lua-enc=%d falhas=%d blocked=%d\n' "$n" "$bad" "$BL"
printf '# limite=estrutura medida; algoritmo desconhecido: ver reports/enc-cifragem-lua.md\n'
[ "$bad" -eq 0 ] || exit 1

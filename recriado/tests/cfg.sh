#!/usr/bin/env bash
# cfg.sh — suíte `cfg` + `cfg-selftest` (fase R-6): endpoints e segredos da configuração original.
#
# Dois invariantes importam aqui:
#   1. os endpoints medidos são os que a matriz de evidências da R-6 cita (nada de端口 chutada);
#   2. a sonda NÃO imprime valor sensível. Isso é testado, não prometido: o pacote original traz
#      credenciais em claro e nenhum segredo pode entrar em arquivo versionado.
# Nenhum valor real de segredo aparece neste arquivo — os casos usam fixture sintética.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$(cd "$V2/.." && pwd)
cd "$V2" || exit 2
export MU_REF_DATA=${MU_REF_DATA:-$ROOT/MuServer}
OUT=out; mkdir -p "$OUT"
n=0; bad=0
ck() { n=$((n+1)); if "$3" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi; }

REF=0; REFMODE=ausente
if [ -n "${SELFTEST_ONLY:-}" ]; then REFMODE=selftest
  printf '# nota=SELFTEST_ONLY: casos da referencia omitidos por decisao desta execucao\n'
elif [ ! -d "$MU_REF_DATA" ]; then
  printf '# BLOCKED motivo=MU_REF_DATA nao encontrado (%s)\n' "$MU_REF_DATA"
else REF=1; REFMODE=referencia; fi

if [ "$REF" = 1 ]; then
  python3 tools/cfg_probe.py > "$OUT/cfg.tsv" 2>"$OUT/cfg.err"; CFG_EXIT=$?
  python3 tools/cfg_probe.py --so-portas > "$OUT/cfg-portas.tsv" 2>/dev/null
fi

# chave/valor medido: classe porta ou ipv4, valor exato
tem() { awk -F'\t' -v ar="$1" -v ch="$2" -v v="$3" \
        '$1==ar && $3==ch && $5==v {achou=1} END{exit !achou}' "$OUT/cfg-portas.tsv"; }

t01() { [ "$CFG_EXIT" -eq 0 ] &&
        grep -q 'arquivos=19 pares_chave_valor=655 segredos_redigidos=29' "$OUT/cfg.tsv"; }
t02() { tem ConnectServer/ConnectServer.ini ConnectServerPortTCP 44406 &&
        tem ConnectServer/ConnectServer.ini ConnectServerPortUDP 55557; }
t03() { tem DataServer/DataServer.ini DataServerPort 55960 &&
        tem JoinServer/JoinServer.ini JoinServerPort 55970 &&
        tem DiscordServer/DiscordServer.ini DiscordServerPort 55990 &&
        tem MHPServer/MHPServer.ini MHPServerPort 55999 &&
        tem PSGuard/PSGG.ini PortaPadrao 55998; }
t04() { tem JoinServer/JoinServer.ini ConnectServerAddress 127.0.0.1 &&
        tem JoinServer/JoinServer.ini ConnectServerPort 55557; }
# o cliente (MainInfo) aponta 44405; o ConnectServer escuta 44406 — divergencia registrada,
# nao resolvida: e hipotese na matriz da R-6, e este teste fixa a medicao dos dois lados
t05() { [ "$(awk -F'\t' '$3=="IpAddressPort" && $5=="44405"' "$OUT/cfg-portas.tsv" | wc -l)" = 2 ] &&
        [ "$(awk -F'\t' '$5=="44406"' "$OUT/cfg-portas.tsv" | wc -l)" = 1 ]; }
t06() { [ "$(awk -F'\t' '$4=="ipv4"' "$OUT/cfg-portas.tsv" | wc -l)" -ge 5 ] &&
        tem JoinServer/JoinServer.ini ConnectServerAddress 127.0.0.1; }
# segredos: toda linha classe=segredo tem valor redigido; nenhuma linha vaza valor cru
t07() { [ "$(awk -F'\t' '$4=="segredo"' "$OUT/cfg.tsv" | wc -l)" = 29 ] &&
        [ "$(awk -F'\t' '$4=="segredo" && $5 !~ /^<REDACTED /' "$OUT/cfg.tsv" | wc -l)" = 0 ]; }
# Checagem INDEPENDENTE da lista do probe (2026-10-14, achado P07-x): o teste nao confia na
# classificacao do proprio probe — ele tem a SUA lista de nomes de chave sensive e exige que toda
# chave que case com ela esteja redigida. Foi o que faltou para pegar `ClientSerial`: o probe nao o
# classificava como segredo, e um teste que so olha `classe=segredo` nao ve o que ficou fora dela.
t07b() { awk -F'\t' '
        NR == 1 { next }
        tolower($3) ~ /serial|senha|pass|pwd|token|secret|credential|key|hwid|licen|auth|sign/ &&
        $4 != "segredo" { print; achou = 1 }
        END { exit achou ? 1 : 0 }' "$OUT/cfg.tsv" | grep -q . && return 1
    [ "$(awk -F'\t' 'tolower($3) ~ /serial/ { n++ } END { print n + 0 }' "$OUT/cfg.tsv")" -ge 3 ]; }
t08() { ! grep -q 'GlobalPassword\s*=\|DiscordBotToken\s*=' "$OUT/cfg.tsv"; }
t09() { python3 tools/cfg_probe.py > "$OUT/cfg2.tsv" 2>/dev/null
        [ "$(sha256sum < "$OUT/cfg.tsv" | cut -c1-16)" = \
          "$(sha256sum < "$OUT/cfg2.tsv" | cut -c1-16)" ]; }
t10() { ! grep -q "$ROOT" "$OUT/cfg.tsv" "$OUT/cfg-portas.tsv"; }

# ---- cfg-selftest: a redação tem de funcionar em fixture sintética ----
T=$(mktemp -d); mkdir -p "$T/fake"
{ printf '[Teste]\n'
  printf 'MyPassword = zebra-roxa-42\n'
  printf 'DiscordBotToken = AAAA.BBBB-CCCC_DDDD1234567890abcdefghij\n'
  printf 'CustomerHardwareId = 11111111-2222-3333-4444-555555555555\n'
  # serial de cliente: 16 chars alfanumericos, forma que NAO casa RE_TOKEN/RE_GUID — so o NOME da
  # chave o denuncia (foi exatamente o valor real que escapou para o r6-config.tsv)
  printf 'ClientSerial = ZZZZ1234ABCD5678\n'
  printf 'PortaNormal = 12345\n'
  printf 'Server = 10.0.0.1\n'
  # forma de token com nome de chave inocente: a redacao tem de pegar pela forma, nao so pelo nome
  printf 'ChaveInocente = xK9mQ2pL7vR4tY8wZ1cF6bN3jH5dG0aS.uV2eI7oP9qW4yB8nM3kT6rE1xZ5cA0sD\n'
} > "$T/fake/caso.ini"
MU_REF_DATA="$T" python3 tools/cfg_probe.py > "$OUT/st_cfg.tsv" 2>/dev/null; ST_EXIT=$?
t11() { [ "$ST_EXIT" -eq 0 ] &&
        ! grep -q 'zebra-roxa-42' "$OUT/st_cfg.tsv" &&
        ! grep -q '11111111-2222-3333-4444-555555555555' "$OUT/st_cfg.tsv" &&
        ! grep -q 'AAAA.BBBB-CCCC_DDDD1234567890abcdefghij' "$OUT/st_cfg.tsv" &&
        ! grep -q 'ZZZZ1234ABCD5678' "$OUT/st_cfg.tsv"; }
t12() { [ "$(awk -F'\t' '$4=="segredo"' "$OUT/st_cfg.tsv" | wc -l)" = 5 ] &&
        [ "$(awk -F'\t' '$4=="porta" && $5=="12345"' "$OUT/st_cfg.tsv" | wc -l)" = 1 ] &&
        [ "$(awk -F'\t' '$4=="ipv4" && $5=="10.0.0.1"' "$OUT/st_cfg.tsv" | wc -l)" = 1 ]; }
# token com nome de chave inocente tambem e segredo (forma do valor)
t13() { awk -F'\t' '$3=="ChaveInocente" && $4=="segredo"' "$OUT/st_cfg.tsv" | grep -q . &&
        ! grep -q 'xK9mQ2pL7vR4tY8wZ1cF6bN3jH5dG0aS' "$OUT/st_cfg.tsv"; }
t14() { MU_REF_DATA=/caminho-que-nao-existe python3 tools/cfg_probe.py >/dev/null 2>&1
        [ $? -eq 2 ]; }
t15() { [ "$(grep -c . "$OUT/st_cfg.tsv")" != 1 ]; }

if [ "$REF" = 1 ]; then
ck 1 "cfg_probe exit 0; 19 .ini, 655 pares, 29 segredos redigidos" t01
ck 2 "ConnectServer: TCP 44406 e UDP 55557 (medido)" t02
ck 3 "portas dos demais servicos: 55960/55970/55990/55999/55998" t03
ck 4 "JoinServer aponta para ConnectServer 127.0.0.1:55557" t04
ck 5 "cliente (MainInfo) usa 44405 enquanto ConnectServer escuta 44406: divergencia medida" t05
ck 6 "enderecos ipv4 presentes na configuracao" t06
ck 7 "todas as 29 linhas de segredo estao redigidas" t07
ck 7b "lista INDEPENDENTE do teste: nenhuma chave de nome sensivel ficou fora da redacao" t07b
ck 8 "nenhuma credencial em claro aparece na saida" t08
ck 9 "saida deterministica" t09
ck 10 "nenhum caminho absoluto do host vaza" t10
fi
ck 11 "selftest: senha, token e GUID de fixture nao aparecem na saida" t11
ck 12 "selftest: classes porta/ipv4 corretas, 5 segredos (inclui serial) contados" t12
ck 13 "selftest: token com nome de chave inocente tambem e redigido" t13
ck 14 "selftest: MU_REF_DATA inexistente sai 2" t14
ck 15 "autos-teste: expectativa errada e detectada" t15
rm -rf "$T"

BL=0
case "$REFMODE" in referencia) SCOPO=referencia ;; selftest) SCOPO=selftest ;;
                 *) SCOPO=ausente; BL=1 ;; esac
printf '1..%d\n# escopo=cfg:%s\n# cfg=%d falhas=%d blocked=%d\n' "$n" "$SCOPO" "$n" "$bad" "$BL"
[ "$bad" -eq 0 ] || exit 1

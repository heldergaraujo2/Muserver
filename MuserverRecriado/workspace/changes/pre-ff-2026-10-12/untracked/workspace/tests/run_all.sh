#!/usr/bin/env bash
# Porta unica de testes da auditoria. Sai 1 se algo falhar -> usavel em CI.
#
# Ambiente: Windows + SQL Server + cliente NAO existem neste workspace, entao os
# testes cobrem o que e executavel de fato: a camada Lua (num interpretador Lua
# real) e as ferramentas de analise binaria. Ver TEST_RESULTS.md.
#
# Uso:  bash workspace/tests/run_all.sh
#       PYTHON=/caminho/para/python3 bash workspace/tests/run_all.sh   # outro interpretador
set -u
cd "$(dirname "$0")/../.." || exit 1

# O venv da auditoria e o unico com lupa/capstone/luaparser. Escolher Python
# errado era um bug real desta porta: com o python3 do sistema os testes de Lua
# falhavam por modulo ausente, o que parece defeito do codigo sob teste.
VENV=/home/user/.venv-tools/bin/python
if [ -n "${PYTHON:-}" ]; then
    PY="$PYTHON"
elif [ -x "$VENV" ]; then
    PY="$VENV"
else
    PY=python3
    echo "AVISO: $VENV ausente; usando python3. Os testes que exigem lupa podem falhar."
    echo "       Prepare: python3 -m venv /home/user/.venv-tools &&"
    echo "                 /home/user/.venv-tools/bin/pip install lupa luaparser capstone"
fi
echo "python: $($PY -V 2>&1)  em $PY"

fail=0
run() {
    local name="$1"; shift
    printf '\n=== %s ===\n' "$name"
    if "$@"; then
        echo "  -> PASSOU"
    else
        local rc=$?
        echo "  -> FALHOU (exit $rc)"
        fail=1
    fi
}

run "autoteste das ferramentas (preflight/pe/minidump)" \
    "$PY" workspace/tests/test_preflight_selfcheck.py
run "teste diferencial do bridge Lua (ScriptCore)" \
    "$PY" workspace/tests/test_scriptcore_differential.py
run "teste de regressao de reload (ProtocolCore)" \
    "$PY" workspace/tests/test_protocolcore_reload.py
run "sintaxe Lua de todos os .lua das 3 arvores Data/Script" \
    "$PY" workspace/tests/check_all_lua.py
# O preflight exita 1/2 quando ACHA defeitos (e isso que ele deve fazer), entao o
# codigo de saida dele NAO e falha desta porta. O que verificamos aqui e que a
# ferramenta roda de ponta a ponta e produz JSON valido e completo.
printf '\n=== preflight do MuServer (rodando; achados vao para reports/) ===\n'
if PYTHONPATH=workspace/tools "$PY" workspace/tools/muserver_preflight.py \
        --root MuServer --json workspace/reports/preflight.json \
        > workspace/reports/preflight.txt 2>workspace/reports/preflight.err; then
    rc=0
else
    rc=$?
fi
if [ $rc -gt 2 ]; then
    echo "  -> FALHOU (exit $rc - erro de execucao, nao achado de auditoria)"
    sed -n '1,12p' workspace/reports/preflight.err
    fail=1
else
    "$PY" - <<'PYX'
import json
d = json.load(open('workspace/reports/preflight.json', encoding='utf-8'))
res = d['resultados'] if 'resultados' in d else d.get('results', d)
if isinstance(res, dict):
    res = [dict(check=k, **v) for k, v in res.items()]
chks = sorted({r.get('check') for r in res})
print("  checks executados: %d (%s)" % (len(chks), " ".join(str(c) for c in chks)))
assert len(chks) >= 11, "menos de 11 checks rodam: ferramenta regrediu"
# frescor: protege contra o JSON de uma execucao anterior esconder um crash novo
import datetime, os, time
stamp = d.get('run_stamp')
age = time.time() - datetime.datetime.strptime(stamp, '%Y-%m-%dT%H:%M:%SZ').replace(
    tzinfo=datetime.timezone.utc).timestamp()
assert 0 <= age < 300, "JSON velho (%.0f s) - a execucao de agora nao o escreveu" % age
for r in res:
    if r.get('severity') == 'ERROR':
        print("  achado ERRO: %s %s" % (r['check'], str(r.get('message'))[:78]))
print("  JSON valido, %d resultados, %d linha(s) de relatorio"
      % (len(res), sum(1 for _ in open('workspace/reports/preflight.txt', encoding='utf-8'))))
PYX
    echo "  -> PASSOU (ferramenta OK; os erros acima sao achados ja triados em reports/AUDIT.md)"
fi

printf '\n=================================================\n'
if [ $fail -eq 0 ]; then
    echo "PORTA DE TESTES VERDE (correcoes e ferramentas)"
else
    echo "FALHAS DE TESTE - ver acima"
fi
exit $fail

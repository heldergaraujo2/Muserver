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
# Interpretador: procura em ordem e PARA no primeiro que TEM as bibliotecas (nao basta existir um
# venv: um venv vazio da o mesmo erro de modulo ausente que nao ter venv nenhum). A lista cobre os
# dois caminhos ja usados neste projeto — o antigo (`~/.venv-tools`) e o atual (`~/.venv/tools`,
# dentro de um diretorio excluido dos snapshots da plataforma).
escolhe_py() {
    local c
    for c in "${PYTHON:-}" "$HOME/.venv-tools/bin/python" "$HOME/.venv/tools/bin/python" python3; do
        [ -n "$c" ] && [ -x "$c" ] || continue
        if "$c" -c 'import lupa, luaparser, capstone' >/dev/null 2>&1; then printf '%s\n' "$c"; return 0; fi
    done
    printf '%s\n' python3
    return 1
}
PY=$(escolhe_py)
if ! "$PY" -c 'import lupa, luaparser, capstone' >/dev/null 2>&1; then
    echo "AVISO: nenhum interpretador com lupa/luaparser/capstone encontrado; usando $PY."
    echo "       Os testes que exigem essas bibliotecas vao falhar por AMBIENTE, nao por defeito."
    echo "       Prepare com:  bash workspace/tools/preparar-venv.sh"
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
# Saida gerada vai para workspace/out/ (ignorado). NAO para workspace/reports/: aquele diretorio
# e varrido pelo verificador de backup, que recusa arquivo ignorado ali (caso 9 de
# recriado/scripts/verify-backup.sh) — evidencia versionada e o .md derivado, nao o JSON do dia.
OUTD=workspace/out; mkdir -p "$OUTD"
printf '\n=== preflight do MuServer (rodando; saida gerada em %s/) ===\n' "$OUTD"
if PYTHONPATH=workspace/tools "$PY" workspace/tools/muserver_preflight.py \
        --root MuServer --json "$OUTD/preflight.json" \
        > "$OUTD/preflight.txt" 2>"$OUTD/preflight.err"; then
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
d = json.load(open('workspace/out/preflight.json', encoding='utf-8'))
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
      % (len(res), sum(1 for _ in open('workspace/out/preflight.txt', encoding='utf-8'))))
PYX
    echo "  -> PASSOU (ferramenta OK; os erros acima sao achados ja triados em reports/AUDIT.md)"
fi

run "autoteste do scanner anti-vazamento" \
    "$PY" workspace/tests/test_verifica_doc_sem_segredo.py

# ---------------------------------------------------------------- varredura anti-vazamento (P07-x)
# Ate 2026-10-14 a regra "nenhum arquivo nosso carrega valor sensivel do pacote" valia so para os
# documentos de seguranca (caso 20 do autoteste). A varredura abaixo estende para TODOS os arquivos
# que nos versionamos — e foi ela que achou `ClientSerial` em claro em `reports/r6-config.tsv`
# (a sonda `cfg_probe.py` nao classificava a chave como sensivel). Duas camadas, com pesos
# diferentes e declarados:
#   - POR VALOR (duro): qualquer valor literal extraido dos configs do pacote que apareca em arquivo
#     nosso e FALHA. Nao ha allow-list: valor de credencial nao tem excecao.
#   - POR FORMA (triagem): heuristica "linha de credencial com valor com cara de segredo". Ela
#     dispara em prosa e codigo (constantes, nomes de variavel), entao cada casamento precisa estar
#     na lista TRIADOS abaixo, com o motivo. Casamento NOVO falha e vai para triagem humana.
# MuServer/ fica fora: ele E a fonte dos valores (e o pacote de terceiros, somente leitura).
printf '\n=== varredura anti-vazamento em todos os arquivos proprios ===\n'
ALVOS=()
while IFS= read -r f; do
    case "$f" in *.bundle|*.gz|*.png|*.jpg|*.jpeg) continue;; esac
    [ -f "$f" ] && ALVOS+=(--alvo "$f")
done < <(git ls-files recriado workspace MuserverRecriado .gitattributes .gitignore 2>/dev/null \
         | grep -v '^MuServer/')
"$PY" workspace/tools/verifica_doc_sem_segredo.py "${ALVOS[@]}" --detalhar \
      --json "$OUTD/varredura-segredo.json" > "$OUTD/varredura-segredo.txt" 2>&1
RC_VARR=$?
RESUMO=$(grep '^# verifica_doc_sem_segredo:' "$OUTD/varredura-segredo.txt" | tail -1)
POR_VALOR=$(printf '%s' "$RESUMO" | sed -n 's/.*por_valor=\([0-9]*\).*/\1/p')
POR_FORMA=$(printf '%s' "$RESUMO" | sed -n 's/.*por_forma=\([0-9]*\).*/\1/p')
echo "  alvos=${#ALVOS[@]} $RESUMO"
if [ "${POR_VALOR:-0}" != 0 ]; then
    echo "  -> FALHOU: valor de credencial do pacote em arquivo proprio:"
    grep 'POR-VALOR' "$OUTD/varredura-segredo.txt" | sed 's/^/     /'
    fail=1
else
    echo "  -> por_valor=0 (nenhum valor de credencial do pacote em arquivo nosso)"
        # Triagem por forma: alvo(glob)|chave(glob) — cada linha com o motivo. A lista usa PADROES
    # porque o mesmo texto benigno se repete na arvore publicada (MuserverRecriado/) e no monorepo.
    TRIADOS="*/docs/ADMIN_CONSOLE.md|*token
*/CHANGELOG.md|*PASS
*/r8-relatorio.md|*PASS
*MIGRACAO*|*PASS
*/migracao/*|*PASS
*/include/mu2/db.h|*MU2DB_E_*
*/tests/db_test.c|*crc
*/tests/run_all.sh|*n_pass
*/tools/cfg_probe.py|*RE_TOKEN"
    #   motivos: prosa citando o assunto (token/PASS), constantes de erro do proprio modulo
    #   (MU2DB_E_CRC/MU2DB_E_SENHA), nome de variavel ou constante de codigo (crc, n_pass, RE_TOKEN)
    #   e documentos de migracao — nenhum deles e um valor de credencial; a camada POR VALOR,
    #   que e a que importa, segue com zero excecoes.
    NAO_TRIADOS=""
    while IFS= read -r linha; do
        case "$linha" in *POR-FORMA*) ;; *) continue;; esac
        alvo=$(printf '%s' "$linha" | sed -n 's/.*alvo=\([^ ]*\).*/\1/p')
        chave=$(printf '%s' "$linha" | sed -n 's/.*chave=\(.*\) alvo=.*/\1/p')
        ok=0
        while IFS='|' read -r t_alvo t_chave; do
            [ -z "$t_alvo" ] && continue
            case "$alvo" in $t_alvo) ;; *) continue;; esac
            case "$chave" in $t_chave) ok=1; break;; esac
        done <<< "$TRIADOS"
        [ "$ok" = 1 ] || NAO_TRIADOS="$NAO_TRIADOS\n     $alvo | $chave"
    done < "$OUTD/varredura-segredo.txt"
    if [ -z "$NAO_TRIADOS" ]; then
        echo "  -> por_forma=$POR_FORMA, todas triadas (prosa/constantes — ver lista na porta)"
    else
        echo -e "  -> FALHOU: casamento(s) por forma sem triagem:$NAO_TRIADOS"
        fail=1
    fi
fi

# Autochecagem: esta porta nao pode deixar arquivo ignorado em workspace/reports/ — foi assim que
# ela e o verificador de backup se contradisseram (um escrevia, o outro recusava). O que ela deixa
# atras e o que ela mesma declara: nada em reports/, saida gerada em out/.
printf '\n=== autochecagem: nada ignorado em workspace/reports/ ===\n'
SOBROU=$(git status --porcelain --ignored=matching -- workspace/reports 2>/dev/null | grep '^!!' | grep -v '/$')
if [ -z "$SOBROU" ]; then echo "  -> PASSOU (reports/ sem arquivo ignorado)"
else echo "  -> FALHOU: $SOBROU"; fail=1; fi

printf '\n=================================================\n'
if [ $fail -eq 0 ]; then
    echo "PORTA DE TESTES VERDE (correcoes e ferramentas)"
else
    echo "FALHAS DE TESTE - ver acima"
fi
exit $fail

#!/usr/bin/env bash
# preparar-venv.sh — recria o interpretador com as bibliotecas que a porta de testes da auditoria
# usa (lupa = Lua real dentro do Python; luaparser = sintaxe; capstone = desmontagem).
#
# Por que existe: sem estas bibliotecas, tres testes da porta falham por AMBIENTE e o resultado e
# indistinguivel de defeito do codigo sob teste — foi o que aconteceu num ambiente reprovisionado
# (2026-10-14). O caminho padrao fica DENTRO de `~/.venv/` de proposito: esse diretorio e excluido
# dos snapshots da plataforma, entao o venv (dezenas de MB) nao infla o artefato da sessao.
#
# Uso: bash workspace/tools/preparar-venv.sh [caminho-do-venv]
set -eu
DEST=${1:-"$HOME/.venv/tools"}
if [ -x "$DEST/bin/python" ] && "$DEST/bin/python" -c 'import lupa, luaparser, capstone' 2>/dev/null; then
    echo "ja pronto: $DEST/bin/python"
    "$DEST/bin/python" -c 'import lupa, luaparser, capstone; print("lupa/luaparser/capstone OK")'
    exit 0
fi
echo "criando venv em $DEST"
python3 -m venv "$DEST"
"$DEST/bin/pip" -q install --disable-pip-version-check lupa luaparser capstone
"$DEST/bin/python" -c 'import lupa, luaparser, capstone; print("venv pronto:", __import__("sys").executable)'

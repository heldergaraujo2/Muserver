#!/usr/bin/env bash
# verify-backup.sh — o invariante da D2-09, executavel e com saida legivel.
# Um backup que nao foi restaurado de verdade nao e um backup; uma rodada que nao
# conferiu o SHA remoto nao e uma rodada entregue.
#
# Uso:  bash recriado/scripts/verify-backup.sh     (monorepo Muserver, a partir de qualquer cwd)
#       bash scripts/verify-backup.sh              (repositorio publicado MuserverRecriado)
#
# LAYOUT (medido, nunca suposto). O script mora na arvore do v2; essa arvore E a raiz do repositorio
# publicado (MuserverRecriado) e e o subdiretorio `recriado/` no monorepo de origem. Em vez de fixar
# um dos dois, a raiz e o prefixo sao derivados de `git rev-parse --show-toplevel`:
#   PFX=''          -> arvore do v2 == raiz do repo   (publicado)
#   PFX='recriado/' -> arvore do v2 esta sob a raiz   (monorepo)
# Quando nao ha repositorio nenhum (restore de bundle sem .git), os casos que exigem git ficam
# BLOCKED — e bloqueado nunca e contado como ok.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
INREPO=0
GITROOT=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null || true)
case "$GITROOT" in
  "" )       root="$(cd "$here/.." && pwd)"; PFX="$(basename "$here")/" ;;
  "$here" )  root="$here"; PFX=""; INREPO=1 ;;
  * )        root="$GITROOT"; PFX="${here#"$GITROOT"/}/"; INREPO=1 ;;
esac
cd "$root" || exit 2
ok=0; bad=0; blk=0
say() { printf '%-34s %s\n' "$1" "$2"; }
chk() { if [ "$2" = ok ]; then ok=$((ok+1)); say "$1" "OK ${3:-}"
        elif [ "$2" = blocked ]; then blk=$((blk+1)); say "$1" "BLOCKED ${3:-}"
        else bad=$((bad+1)); say "$1" "FALHA ${3:-}"; fi; }

# 1) HEAD local
if [ "$INREPO" = 1 ]; then
  local_sha=$(git rev-parse HEAD)
  branch=$(git rev-parse --abbrev-ref HEAD)
  say "HEAD local" "$local_sha"
else
  local_sha=""; branch=""
  say "HEAD local" "sem repositorio git (restore de bundle: 'publicado' e 'intacto' nao sao verificaveis)"
fi

# 2) o remoto tem exatamente este commit?
if [ "$INREPO" = 1 ]; then
  remote_sha=$(git ls-remote origin "refs/heads/$branch" 2>/dev/null | awk '{print $1}')
  if [ -n "$remote_sha" ] && [ "$remote_sha" = "$local_sha" ]; then st=ok; else st=bad; fi
  chk "publicacao: origin/$branch" "$st" "remoto=${remote_sha:-ninguem}"
else
  chk "publicacao: origin/$branch" blocked "sem git local: nao ha o que comparar"
fi

# 3) arvore limpa nos caminhos do v2 (nada escrito sem comitar)
if [ "$INREPO" = 1 ]; then
  dirty=$(git status --porcelain -- "${PFX:-.}" | head -3)
  if [ -z "$dirty" ]; then st=ok; else st=bad; fi
  chk "arvore ${PFX:-<raiz>} limpa" "$st" "${dirty:-}"
else
  chk "arvore limpa" blocked "sem repositorio git"
fi

# 4) o bundle de backup existe, verifica, e o hash bate com o MANIFEST.
#    Ele mora em workspace/backups/ e NAO dentro da arvore dividida: o bundle e gerado a partir
#    do subtree split dela, entao aloja-lo la dentro faria cada regravacao embutir a
#    anterior (medido: 17 225 -> 38 233 -> 66 195 -> 134 694 bytes, ~2x por rodada, e o limite de
#    persistencia da plataforma e ~128 MB somados). Fora da arvore dividida o custo e constante.
#    workspace/ mantem o MESMO caminho relativo nos dois layouts (raiz do projeto -> workspace/).
bundle=workspace/backups/mu2-v2.bundle
if [ -f "$bundle" ]; then
  if out=$(git bundle verify "$bundle" 2>&1); then st=ok; else st=bad; fi
  chk "bundle: git bundle verify" "$st" "$(printf '%s' "$out" | grep -aoE '[0-9]+ objects?.*' | head -1)"
  want=$(awk '/^sha256:/{print $2}' workspace/backups/MANIFEST.md 2>/dev/null)
  got=$(sha256sum "$bundle" | cut -d' ' -f1)
  if [ -n "$want" ] && [ "$want" = "$got" ]; then st=ok; else st=bad; fi
  chk "bundle: sha256 do MANIFEST" "$st" "${got:0:16}..."
  # 5) restauracao real: clonar o bundle (snapshot orphan, branch mu2-snapshot) num diretorio
  #    descartavel. Compara-se o CONJUNTO de arquivos rastreados: o conteudo do commit do bundle e
  #    o commit anterior, por construcao (o bundle nao pode conter a si mesmo) — a integridade de
  #    CONTEUDO e o sha256 do bundle contra o MANIFEST (caso 4) e a ponta conferida no caso 6.
  if [ "$INREPO" = 0 ]; then
    chk "restauracao por clone" blocked "sem repositorio git para comparar o conjunto de arquivos"
  else
  tmp=$(mktemp -d /tmp/mu2-restore.XXXXXX)
  if git clone -q --no-hardlinks -b mu2-snapshot "$bundle" "$tmp/clone" 2>/dev/null; then
    snap=$(cd "$tmp/clone" && git ls-tree -r --name-only HEAD 2>/dev/null | grep -v '^backup/' | sort)
    head=$(git ls-tree -r --name-only HEAD -- "${PFX:-.}" | sed "s|^${PFX}||" | grep -v '^backup/' | sort)
    # (a) INCLUSAO: todo arquivo do snapshot tem de existir no HEAD publicado. Publicar nao pode
    #     perder arquivo do snapshot, e essa e a assercao que interessa aqui (o conteudo do snapshot
    #     ja esta congelado pelo sha256 do caso 4).
    faltando=$(printf '%s\n' "$snap" | comm -23 - <(printf '%s\n' "$head"))
    if [ -z "$faltando" ]; then st=ok; else st=bad; fi
    chk "snapshot ⊆ HEAD (nada perdido)" "$st" "$(printf '%s' "$faltando" | tr '\n' ' ')"
    # (b) os arquivos que EXISTEM nos dois mas divergem de conteudo: a lista legal e declarada
    #     abaixo e curta de proposito (adaptacao de caminhos do layout + os 3 scripts tornados
    #     agnosticos de layout). Divergencia fora dela falha — a lista nao e um cheque em branco.
    div_ok=${DIV_OK:-'docs/ README.md reports/README.md reports/rf-lua-protocolo.md tests/admin.sh tests/fuzz.sh scripts/verify-backup.sh'}
    div=""
    for p in $(printf '%s\n' "$snap"); do
      h=$(git rev-parse "HEAD:${PFX}${p}" 2>/dev/null) || continue
      s=$(cd "$tmp/clone" && git rev-parse "HEAD:$p" 2>/dev/null) || continue
      [ "$h" = "$s" ] || div="$div $p"
    done
    fora=""
    for p in $div; do
      keep=0
      for a in $div_ok; do case "$p" in "$a"*) keep=1;; esac; done
      [ "$keep" = 1 ] || fora="$fora $p"
    done
    if [ -z "$fora" ]; then st=ok; else st=bad; fi
    chk "divergencia de conteudo dentro do declarado" "$st" "observadas:${div:- nenhuma}"
    say "  divergentes declarados" "$(printf '%s' "$div" | wc -w)"
    n=$(printf '%s\n' "$snap" | grep -vc '^backup/')
    say "  arquivos do v2 no bundle" "$n"
    # (c) arquivos do HEAD que o snapshot nao tem: podem existir (evidencia workspace/, relatorio de
    #     migracao), mas so se casarem com o padrao declarado. Extra inesperado falha.
    extra=$(printf '%s\n' "$head" | comm -13 <(printf '%s\n' "$snap") -)
    extra_ok=$(printf '%s\n' "$extra" | grep -cE '^(workspace/|docs/MIGRACAO|MIGRACAO|\.gitattributes$)' )
    extra_all=$(printf '%s\n' "$extra" | grep -c .)
    if [ "$extra_ok" = "$extra_all" ]; then st=ok; else st=bad; fi
    chk "arquivos fora do snapshot sao declarados" "$st" "extras=$extra_all declarados=$extra_ok"
  else
    chk "restauracao por clone" bad "git clone do bundle falhou"
  fi
  # 6) ponta do bundle == SHA registrado no MANIFEST (integridade de conteudo do snapshot)
  tip=$(git bundle list-heads "$bundle" 2>/dev/null | awk '{print $1}')
  want_tip=$(awk -F'`' '/branch (local criada|do snapshot)/{print $4}' workspace/backups/MANIFEST.md 2>/dev/null)
  if [ -n "$tip" ] && [ -n "$want_tip" ] && case "$tip" in "$want_tip"*) true;; *) false;; esac; then st=ok; else st=bad; fi
  chk "bundle: ponta == MANIFEST" "$st" "${tip:0:7} vs ${want_tip:-?}"
  rm -rf "$tmp"
  fi
else
  chk "bundle presente" bad "$bundle ausente"
fi

# 7) a referencia original esta intacta? Ela e somente leitura e nenhuma rodada pode toca-la.
#    So existe no monorepo: no repositorio publicado ela NAO viaja (decisao da migracao — ver
#    docs/MIGRACAO-*.md), e por isso aqui o estado e BLOCKED, nunca ok.
mu_want=fade04615fabd17778a0e2fd7adf032c8386c924
if [ "$INREPO" = 1 ] && git cat-file -e "HEAD:MuServer" 2>/dev/null; then
  mu_tree=$(git rev-parse HEAD:MuServer 2>/dev/null)
  mu_dirty=$(git status --porcelain -- MuServer | wc -l)
  if [ "$mu_tree" = "$mu_want" ] && [ "$mu_dirty" = 0 ]; then st=ok; else st=bad; fi
  chk "referencia MuServer/ intacta" "$st" "tree=${mu_tree:0:7} alteracoes=$mu_dirty"
else
  chk "referencia MuServer/ intacta" blocked "nao versionada neste repositorio (publicado sem a referencia)"
fi

# 8) documentos de continuidade presentes: um agente novo tem de achar o estado sem ler chat.
missing=""
for d in "${PFX}docs/CONTINUITY.md" "${PFX}docs/CURRENT_STATE.md" "${PFX}docs/NEXT_TASK.md" \
         "${PFX}docs/DECISIONS.md" "${PFX}docs/CHANGELOG.md" "${PFX}docs/ENVIRONMENT.md" \
         "${PFX}docs/ROADMAP.md" workspace/backups/MANIFEST.md; do
  [ -f "$d" ] || missing="$missing $d"
done
if [ -z "$missing" ]; then st=ok; else st=bad; fi
chk "documentos de continuidade" "$st" "${missing:-todos presentes}"

# 9) evidencia nao pode morar em caminho ignorado pelo git (a armadilha ja custou trabalho antes:
#    workspace/reports/*.json e reports/*.raw sao ignorados e simplesmente nao persistem).
if [ "$INREPO" = 1 ]; then
  lost=$(git status --porcelain --ignored=matching -- "${PFX}reports" workspace/reports 2>/dev/null \
         | grep '^!!' | grep -v '/$' | head -3)
  if [ -z "$lost" ]; then st=ok; else st=bad; fi
  chk "nenhuma evidencia em caminho ignorado" "$st" "${lost:-}"
else
  chk "nenhuma evidencia em caminho ignorado" blocked "sem repositorio git"
fi

# 10) FULL=1: a prova que importa — o bundle como ele existe DEPOIS do push, lido de um clone do
#    remoto. Foi assim que apareceu o CRLF que corrompia o blob comitado sem tocar no worktree.
#    A URL vem do proprio repositorio (`git remote get-url origin`): hardcodar Muserver.git aqui
#    faria o repositorio publicado verificar o repo errado e dar verde por engano.
if [ "${FULL:-0}" = 1 ]; then
  if [ "$INREPO" = 0 ]; then
    chk "clone do remoto para FULL" blocked "sem repositorio git: nao ha origin"
  else
  tf=$(mktemp -d)
  url=$(git remote get-url origin 2>/dev/null || true)
  if [ -z "$url" ]; then
    chk "clone do remoto para FULL" bad "origin sem URL"
  elif git clone -q --depth 2 --single-branch -b "$branch" "$url" "$tf/remote" 2>/dev/null; then
    say "origin" "$url"
    rsha=$(cd "$tf/remote" && sha256sum workspace/backups/mu2-v2.bundle 2>/dev/null | cut -c1-16)
    lsha=$(sha256sum "$bundle" | cut -c1-16)
    if [ -n "$rsha" ] && [ "$rsha" = "$lsha" ]; then st=ok; else st=bad; fi
    chk "publicado: bundle byte a byte" "$st" "remoto=${rsha:-?} local=${lsha:0:16}"
    if (cd "$tf/remote" && git bundle verify workspace/backups/mu2-v2.bundle >/dev/null 2>&1); then st=ok; else st=bad; fi
    chk "publicado: bundle verify no clone" "$st"
    if (cd "$tf/remote" && git clone -q --no-hardlinks -b mu2-snapshot workspace/backups/mu2-v2.bundle restored 2>/dev/null && [ -f restored/src/wire.c ]); then
      st=ok
    else
      st=bad
    fi
    chk "publicado: restaurar arvore a partir do bundle clonado" "$st"
    rsha_head=$(cd "$tf/remote" && git rev-parse HEAD)
    if [ -n "$local_sha" ] && [ "${rsha_head#"$local_sha"}" != "$rsha_head" ]; then st=ok; else st=bad; fi
    chk "publicado: HEAD local esta no remoto" "$st" "${rsha_head:0:7}"
  else
    chk "clone do remoto para FULL" bad "clone de $url falhou (sem rede ou sem autorizacao: registrar bloqueio, nao afirmar publicacao)"
  fi
  rm -rf "$tf"
  fi
fi

echo "——— ok=$ok falhas=$bad blocked=$blk ———"
[ "$bad" -eq 0 ] || echo "Bloqueio registrado: rodada sem publicacao/backup conferidos NAO conta como entregue (D2-09)."
[ "$blk" -eq 0 ] || echo "Nota: $blk verificacao(oes) BLOCKED neste layout (referencia/git ausentes) — nao equivalem a aprovacao."
exit $((bad>0))

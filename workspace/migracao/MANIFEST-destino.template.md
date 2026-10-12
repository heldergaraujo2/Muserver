# MANIFEST da copia independente — republica `MuserverRecriado`

| campo | valor |
|---|---|
| conteudo | arvore do repositorio publicado **inteira** (@ARQUIVOS@ arquivos rastreados), num commit orphan unico (branch local `mu2-snapshot`) |
| origem | `git commit-tree HEAD^{tree}` na arvore `@TREE@` (migracao de 2026-10-12: split do historico + evidencia `workspace/` + adaptacao de caminhos) |
| branch do snapshot | `mu2-snapshot` @ `@TIP@` |
| arquivo | `mu2-v2.bundle` (@SIZE@ bytes) |
| sha256 | ver abaixo |

sha256: @SHA@

## Historia deste artefato (nao reescrita)

Ate a migracao, esta copia era regravada no monorepo `heldergaraujo2/Muserver` a partir de
`HEAD:recriado` (ultimo: snapshot `b609577`, 247 621 B, sha256 `cff7baea…`, com 82 arquivos).
Nesta republica o mesmo procedimento passou a ser aplicado **aqui**: o snapshot e' orphan commit da
arvore deste repositorio, e o bundle volta a conter a arvore inteira — inclusive a evidencia
`workspace/`, que antes vivia fora do snapshot.

Tamanho ao longo das rodadas (registro de por que ele e' constante): 17 225 -> 38 233 -> 66 195 ->
134 694 -> 204 585 -> 247 621 (snapshot do monorepo) -> **@SIZE@** bytes nesta republica. O salto
nao e' inflacao de historico: o bundle agora cobre a arvore publicada inteira (com a evidencia
`workspace/`, incluindo os baselines Lua e os relatorios de auditoria) e nao apenas o v2.
O bundle continua **fora de si mesmo** (o commit do snapshot e' anterior ao arquivo), entao o custo
por regravacao permanece constante.

## Como o backup e' conferido (e o buraco que o `binary` tapou, no monorepo)

Um `* text=auto` no `.gitattributes` da raiz do monorepo aplicava `text: set` ao `*.bundle`: o blob
comitado divergia do arquivo em disco e **o bundle publicado estava corrompido para quem o
recuperasse por clone**, sem que o verificador visse (ele media o worktree). Aqui a politica e'
explicita: `* -text` no `.gitattributes`, com `workspace/backups/*.bundle binary` — nada e'
convertido no caminho.

## Como restaurar (teste real, executado por `scripts/verify-backup.sh` e por `preparar-destino.sh`)

```sh
git bundle verify workspace/backups/mu2-v2.bundle     # deve dizer ok e listar 1 ponta
D=$(mktemp -d)
git clone -q --no-hardlinks -b mu2-snapshot workspace/backups/mu2-v2.bundle "$D/r"   # -b e' obrigatorio
(cd "$D/r" && make -s check)                          # sem -b o clone nasce sem arvore
```

## Regras desta copia

- O bundle e' regravado **no fim de cada rodada**, depois do ultimo commit: ele cobre tudo, exceto a
  si mesmo. A conferencia de conjunto em `scripts/verify-backup.sh` compara exatamente esse escopo
  (por isso `workspace/backups/` fica fora da comparacao de conteudo: bundle e MANIFEST divergem do
  snapshot por construcao, e a integridade deles e' provada pelo sha256 e pela ponta).
- O snapshot e' um commit **orphan**: nao carrega o historico (que ja' esta na branch `main`) e por
  isso nao cresce a cada regravacao.
- Publicacao so' e' afirmada depois de `git ls-remote` conferir o SHA remoto.

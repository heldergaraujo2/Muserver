# Relatório de migração — `recriado/` → `MuserverRecriado`

Máquina de origem: monorepo `heldergaraujo2/Muserver`, branch `arena/cf1de8ce-muserver`.
Destino: `heldergaraujo2/MuserverRecriado`. Data: 2026-10-12.

> **Estado da publicação: NÃO publicada.** O `git push` para o destino responde
> `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2` e a API responde
> `Resource not accessible by integration` **no destino** (no repo de origem responde normalmente).
> A ACL do usuário diz `push=true` nos dois; o que falta é a instalação do GitHub App incluir o
> `MuserverRecriado` com *Contents: Read and write*. Ver §8 e `../workspace/backups/MANIFEST.md`.

## 1. Origem e destino

| | |
|---|---|
| origem | `heldergaraujo2/Muserver`, árvore `recriado/` (o v2 morava dentro do repo da sessão) |
| commit de origem da migração | `3c49470` — base do split (contagens corrigidas + a corrida da linha de base do teste de descritores), sobre `60260f3`, `45033f5` (docs da rodada 2) e `c78a6ed` (pacote `workspace/migracao/`) |
| destino | `heldergaraujo2/MuserverRecriado` (público, criado 2026-10-11, **vazio** na verificação: `size=0`, `GET /git/refs` → 409 "Git Repository is empty") |
| histórico publicado no destino | 39 commits, tip `eee2a353` (split de `3c49470`) + os commits da migração |
| branch do destino | `main` (é a *default branch* do repo vazio) |

## 2. Estratégia de preservação do histórico

`git subtree split --prefix=recriado -b mu2-import HEAD`, executado num **clone temporário** com
`sparse-checkout` (o split exige o diretório no worktree; a árvore de 615 MB não é materializada).
Resultado: **39 commits** com as mensagens originais intactas (`R-3`, `R-4`, `R-5`, `R-8`, `R-6`,
`R-7`, golden/fuzz/segurança/admin/Lua/interop, as auditorias, o pacote de migração e os backups de
cada rodada) e os caminhos reescritos para a raiz.

O destino foi criado por `git init` + `git fetch file://<clone> mu2-import:main` e **não** por
`git clone`: o clone local copia o pack inteiro do monorepo (134 MB, incluindo os blobs do
`MuServer/`) para dentro de um repositório que não deve carregá-los — medido. Com o `fetch` por
protocolo, o `.git` do destino ficou em **≈ 2 MB** (medido: `du -sk .git` ≈ 2100 KB; o pack do
monorepo tem 134 MB).

A adaptação da árvore (caminhos, layout e documentos) é feita por
`workspace/migracao/adaptar-destino.py`, com uma asserção por substituição: o patch anterior ficava
pinado na base do split e deixou de aplicar quando o histórico avançou — medido, e por isso o
caminho foi trocado.

Nada foi reescrito no histórico compartilhado: o split cria objetos **novos** num repositório
descartável; a origem não ganhou ref e o push (bloqueado) não chegou a acontecer.

## 3. O que foi transferido

| conjunto | arquivos | origem |
|---|---|---|
| árvore do v2 (via split, com história) | 83 | `recriado/` (82 + `reports/migracao-destino.tsv`) |
| evidência do workspace | 89 | `workspace/`, menos `migracao/` (ver §4.4) |
| layout/relatório novos do destino | 2 | `.gitattributes` (novo) e este relatório (`.gitignore` foi reescrito no lugar) |
| **total rastreado** | **174** | `git ls-files \| wc -l` |

`workspace/` mantém o **mesmo caminho relativo** dos dois lados por uma razão técnica, não por
estética: `scripts/verify-backup.sh`, `tests/lua.sh`, `tests/ref_check.sh` e `tools/lua_probe.py`
resolvem `workspace/...` a partir da raiz do projeto, e o bundle de backup (que mora em
`workspace/backups/`) é o que carrega a árvore restaurável.

## 4. Exclusões intencionais (e por quê)

1. **`MuServer/`** — 10 021 arquivos, ~615 MB, é o pacote **do fornecedor**, não a reconstrução.
   Não é publicado aqui (não é nosso, e o destino é público). Consequência declarada: `pe`, `data`,
   `cfg`, `lua` e `ref-intacta` saem **BLOCKED** neste repositório — bloqueado, não aprovado.
2. **`workspace/reports/*.{json,txt,err}`, `workspace/recovered/`, `out/`, `build/`,
   `__pycache__/`** — saídas regeneráveis, já ignoradas pelo `.gitignore` da origem; não existem como
   arquivo rastreado, logo não havia o que transferir.
3. **`.gitignore`/`.gitattributes` da origem** — não copiados literalmente: as regras de `MuServer/**`
   não têm objeto aqui. O objetivo da política (não converter bytes de evidência) foi preservado.
4. **`workspace/migracao/`** — ferramenta da **origem** (split, transformador, bundle de transporte):
   dentro do destino seria circular (conteria um bundle do próprio destino). A evidência que interessa
   (backups, changes, reports, docs, tools, tests, inventory) viaja inteira.
5. **Bloqueios e stashes locais** — não existiam na origem no momento da migração.
6. **Nenhum relatório de `reports/` foi reescrito.** Eles são evidência do que foi medido no layout
   do monorepo e continuam escrevendo `recriado/...`; reescrever seria falsificar registro. O
   mapeamento está no cabeçalho dos documentos canônicos e em §2.

## 5. Resultado dos testes no destino (medido)

| verificação | resultado |
|---|---|
| `make -s gate` | **PASS=14 FAIL=0 BLOCKED=6 NOT_IMPLEMENTED=0 SKIPPED=2**, 281 asserções, 22 etapas, exit 0 |
| `make -s check` | sem falhas (`unit` 106, `net` 34; `pe`/`data` BLOCKED por ausência da referência) |
| `make -s fuzz` | 12/12, 150 000 iterações, 52 sementes |
| `make -s gate-selftest` | 19/19 |
| `bash scripts/verify-backup.sh` | ok=9, falhas=1 (a publicação em falta, honestamente), blocked=1 — ver §7; com `FULL=1`, falha também a ausência de `origin` (nada publicado a conferir) |

As 6 etapas BLOCKED são exatamente as que dependem da referência original
(`pe`, `data`, `cfg`, `ref-intacta`, `interop`, `lua`); no monorepo de origem o mesmo portão dá
PASS=18 BLOCKED=2 com 339 asserções. A diferença é 100 % atribuída à referência ausente — nenhuma
etapa "passou por ter sido ignorada".

## 6. Defeitos encontrados durante a migração (corrigidos na origem)

Rodar o portão num ambiente **reprovisionado** (sem `out/` residual) expôs quatro defeitos que o
teste anterior mascarava — todos corrigidos na origem (`9ea61fe`, `8b37936`) e presentes aqui:

1. `tools/malform_probe.py` media o processo **errado** (varredura de `/proc/*/cmdline` por "mud2");
   a asserção de descritores comparava fd de outro processo. Corrigido para `--srv-pid`/inode do
   socket que escuta, com asserção de procedência.
2. A asserção `fd_antes == fd_depois` era **corrida**, não vazamento (medido: imediato 9,9,8,8,8 e
   estabilizado 8 em 0–20 ms). Passou a medir acúmulo entre duas rodadas após estabilizar.
3. `tests/admin.sh` dependia de `out/gate.tsv` de uma execução anterior (estado residual). Passou a
   usar fixture própria com números conhecidos e a cobrir o caso de TSV ausente (503).
4. A etapa `build` do portão exigia o **próprio produto** (`out/wire.o`) e virava `NOT_IMPLEMENTED`
   em clone limpo — a rodada degradava para PASS=10/BLOCKED=9 sem falhar. Passou a exigir
   `src/wire.c` e a construir de fato.

## 7. Backup, hashes e restauração

A cópia independente **deste** repositório mora aqui: `workspace/backups/mu2-v2.bundle` + `MANIFEST.md`
(snapshot orphan `mu2-snapshot` — tamanho, sha256 e ponta no manifesto). Restauração conferida por
`git bundle verify` + clone em diretório temporário + `make -s check` (resultados em §5 e no MANIFEST).

O pacote de migração (split do histórico, transformador `adaptar-destino.py`, os 7 assets, o bundle
de transporte e as medidas da rodada) mora no monorepo `heldergaraujo2/Muserver`, em
`workspace/migracao/` — fora daqui de propósito (§4.4). `reports/migracao-destino.tsv` registra a
primeira rodada (split de 34 commits) e **não** foi reescrito; as medidas desta rodada estão em §5,
no `MANIFEST.md` do backup e no pacote de origem
(`workspace/migracao/medidas-destino-rodada2.tsv`, no monorepo).

## 8. Bloqueios

1. **Publicação: 403** — o proprietário precisa incluir `MuserverRecriado` na instalação do GitHub
   App (*Contents: Read and write*); depois, `bash workspace/migracao/publicar-destino.sh` conclui e
   confere (push + `ls-remote` + clone independente + portão).
2. **`MuServer/` não viaja**: `pe`, `data`, `cfg`, `lua`, `ref-intacta` e a camada 3 de `interop`
   ficam **BLOCKED** neste repositório — bloqueado não é aprovado.

## 9. Nota de localização (2026-10-13)

A publicação **mudou de lugar** e este relatório passa a descrever o *artefato*, não o único destino
possível. O repositório separado `heldergaraujo2/MuserverRecriado` **segue bloqueado por `403`** (vazio:
a tentativa de push foi repetida com o artefato final validado e respondeu o mesmo erro), então o
projeto recriado foi publicado **dentro do monorepo autorizado**, nesta pasta `MuserverRecriado/`.

Medido nesta publicação: a pasta recebeu os **174 arquivos** do artefato validado (HEAD `51b2b157`,
árvore `99c9b8ff`, 42 commits), com **modo e blob idênticos** nos 174 (nada convertido);
`make -s check` exit 0 (182 asserções), `make -s gate` **18 PASS / 0 FAIL / 2 BLOCKED / 2 SKIPPED,
339 asserções** (com a referência irmã `../MuServer` disponível — sem ela o perfil volta a
14 PASS/6 BLOCKED/281), `gate-selftest` 19/19, `fuzz` 12/12, `ref-intacta` PASS 8/8 com a árvore
`fade0461…` da referência inalterada.

O pacote de migração (`preparar-destino.sh`, `adaptar-destino.py`, os 7 assets e o bundle de
transporte) permanece em `../workspace/migracao/` do monorepo: se o proprietário habilitar o
repositório separado, a publicação lá continua reproduzível a partir dele.

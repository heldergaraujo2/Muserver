# Migração para `MuserverRecriado` — o que é este diretório

Pacote **reprodutível** que publica a reconstrução (`recriado/`) como repositório próprio, com
histórico preservado, evidência e cópia restaurável. Nada aqui depende desta conversa: qualquer
pessoa (ou agente) com o monorepo em mãos reproduz o destino com um comando.

| arquivo | papel |
|---|---|
| `preparar-destino.sh` | constrói o destino (split do histórico + evidência + adaptação + backup) e **confere por conteúdo** |
| `publicar-destino.sh` | faz push, lê de volta com `ls-remote` e roda o portão num clone independente |
| `patches/0001-migracao.patch` | adaptação da raiz publicada (caminhos, documentos canônicos, `.gitignore`/`.gitattributes`, README, `tests/run_all.sh`, relatório de migração) |
| `MANIFEST-destino.template.md` | manifesto da cópia independente do destino (preenchido pelo `preparar-destino.sh`) |
| `destino-muserverrecriado.bundle` | transporte: o repositório de destino inteiro (histórico + `main`) num arquivo, para o caso de o push continuar bloqueado |

## Como usar

```sh
bash workspace/migracao/preparar-destino.sh /tmp/mu2dest --gate   # constrói e verifica
bash workspace/migracao/publicar-destino.sh /tmp/mu2dest          # publica (hoje: 403) e confere
```

O `preparar-destino.sh` **não toca no monorepo**: o split roda num clone temporário com
`sparse-checkout`, e o destino nasce de `git init` + `git fetch` (não de `git clone`, que copiaria o
pack de 134 MB com os blobs do `MuServer/` para dentro de um repositório que não deve carregá-los).

## Estado medido em 2026-10-12 (o que sustenta cada afirmação)

| item | valor conferido |
|---|---|
| histórico preservado | **34 commits** via `git subtree split --prefix=recriado` (mensagens originais) |
| reproducibilidade | duas construções independentes ⇒ mesmo HEAD (`587ba4f`), mesma árvore e mesmo sha256 de bundle |
| commits do destino | **37** (34 do split + evidência `workspace/` + adaptação + backup) |
| arquivos rastreados no destino | **173** |
| árvore do destino | `8f1e0f35d3cc082dddccfe5f4caf834dc30946c4` |
| cópia independente | `mu2-snapshot` @ `75a5d2f`, bundle **645 549 B**, sha256 `e30fd48a7d8ebd0c…` |
| transporte | `destino-muserverrecriado.bundle`, **1 326 974 B**, sha256 `0744b9a52be9ea9f…` — clone `-b main` dá árvore idêntica e `make -s check` sem falhas |
| `make -s gate` no destino | **PASS=14 FAIL=0 BLOCKED=6 NOT_IMPLEMENTED=0 SKIPPED=2, 281 asserções, exit 0** |
| clone independente | árvore e inventário **idênticos** ao local (173 arquivos); portão reproduz o mesmo perfil (14/0/6, 281 asserções) |
| `make -s check` / `fuzz` / `gate-selftest` no destino | sem falhas / 12–12 / 19–19 |
| `scripts/verify-backup.sh` no destino | ok=9, **falhas=1** (a publicação, honestamente) e blocked=1 (referência ausente) |
| **publicação** | **BLOQUEADA**: 403 `denied to heldergaraujo2`; API do destino responde `Resource not accessible by integration` |

As 6 etapas BLOCKED no destino são exatamente as que exigem a referência original (`pe`, `data`,
`cfg`, `ref-intacta`, `interop`, `lua`): `MuServer/` (10 021 arquivos, ~615 MB, pacote do
fornecedor) **não** viaja para o repositório público. No monorepo de origem o mesmo portão dá
PASS=18 BLOCKED=2 com 339 asserções — a diferença é 100 % atribuída à referência ausente.

## Bloqueio de permissão (o único impedimento real)

Medido, com o comando exato:

```
$ git push https://github.com/heldergaraujo2/MuserverRecriado.git main:main
remote: Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2.
fatal: unable to access '...': The requested URL returned error: 403
```

A mesma credencial publica normalmente em `heldergaraujo2/Muserver` (o push da branch da sessão
funciona), e a API responde `{"message":"Resource not accessible by integration"}` **só** no destino.
Leitura: o token é de instalação de GitHub App e a instalação não inclui `MuserverRecriado`.

**Ação do proprietário:** incluir `MuserverRecriado` na seleção de repositórios da instalação, com
*Contents: Read and write*. Depois disso, `publicar-destino.sh` conclui e confere. Enquanto isso não
acontece, nada é afirmado como publicado, e o conteúdo continua preservado em dois lugares
independentes: a árvore do monorepo (branch da sessão) e `destino-muserverrecriado.bundle`.

## Base do patch (importante ao reprocessar)

`patches/0001-migracao.patch` está pinado na base `b1a3719` (o split de `9ea61fe`), que é o que o
`preparar-destino.sh` produz a partir deste monorepo. Se a árvore `recriado/` evoluir, o patch é
aplicado com `--3way` e a árvore final é comparada com `TREE_ESPERADA`; divergência aparece como
FALHA com o valor medido, nunca como verde — e o patch deve ser regerado a partir do novo destino
conferido (`git diff <base> <destino> -- . ':(exclude)workspace/**'`).

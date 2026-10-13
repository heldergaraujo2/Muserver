# Migração para `MuserverRecriado` — o que é este diretório

Pacote **reprodutível** que publica a reconstrução (`recriado/`) como repositório próprio, com
histórico preservado, evidência e cópia restaurável. Nada aqui depende de uma conversa: qualquer
pessoa (ou agente) com o monorepo em mãos reproduz o destino com um comando.

| arquivo | papel |
|---|---|
| `preparar-destino.sh` | constrói o destino (split do histórico + evidência `workspace/` + adaptação + cópia independente) e **confere por conteúdo**: árvore, contagem de arquivos e sha256 do bundle são fixados em constantes |
| `publicar-destino.sh` | faz push, lê de volta com `ls-remote`, clona o remoto num diretório temporário e roda o portão no clone — só então afirma publicação |
| `adaptar-destino.py` | transformador da árvore publicada; **cada substituição tem asserção**: texto de origem fora do lugar FALHA nomeando a substituição, em vez de aplicar torto ou em silêncio |
| `destino.gitignore`, `destino.gitattributes`, `README-secao-continuacao.md`, `README-secao-layout.md`, `CONTINUITY-secao6.md`, `NEXT_TASK-passo-zero.md`, `MIGRACAO-destino.md` | os **7 assets**: os trechos grandes que o transformador escreve no destino (revisados a cada rodada; nunca inventados) |
| `MANIFEST-destino.template.md` | manifesto da cópia independente do destino (preenchido pelo `preparar-destino.sh` com os valores medidos) |
| `destino-muserverrecriado.bundle` | transporte: o repositório de destino **inteiro** (histórico + `main`) num arquivo, para o caso de o push continuar bloqueado |
| `patches/0001-migracao.patch` | **superseded**: era a adaptação ancorada na base do split; ficou pinado e deixou de aplicar quando o histórico avançou (medido: de 34 para 36 commits). Mantido como registro; **não** é usado |

## Como usar

```sh
bash workspace/migracao/preparar-destino.sh /tmp/mu2dest --gate   # constrói e verifica
bash workspace/migracao/publicar-destino.sh /tmp/mu2dest          # publica (hoje: 403) e confere
```

O `preparar-destino.sh` **não toca no monorepo**: o split roda num clone temporário com
`sparse-checkout` (nenhum ref novo, nenhum objeto escrito na origem), e o destino nasce de
`git init` + `git fetch` — não de `git clone`, que copiaria o pack de 134 MB com os blobs do
`MuServer/` para dentro de um repositório que não deve carregá-los.

O transformador é a peça que substitui o patch: o patch fica **pinado na base** em que foi gerado;
o `adaptar-destino.py` casa cada substituição com o texto exato da origem e aborta a rodada (sem
aplicar parcialmente) quando o texto mudou. É ele que mantém os documentos canônicos coerentes com
o layout publicado — `recriado/X` → `X`, `../../workspace/` → `../workspace/`, blocos de continuidade
e o relatório de migração.

## Estado medido em 2026-10-12 (rodada de fechamento)

| item | valor conferido |
|---|---|
| histórico preservado | **39 commits** via `git subtree split --prefix=recriado` (mensagens originais), tip `eee2a353` |
| reprodutibilidade | duas construções independentes ⇒ mesmo HEAD (`0edfcf56`), mesma árvore e mesmo sha256 de bundle (constantes conferidas pelo script) |
| commits do destino | **42** (39 do split + evidência `workspace/` + adaptação + backup) |
| arquivos rastreados no destino | **174** (`83` da árvore do v2 + `89` de `workspace/` + `.gitattributes` + relatório) |
| árvore do destino | `233c2bd08cb37c0f8aa2196831fa99f53a3b8453` |
| cópia independente do destino | `mu2-snapshot` @ `72bf476b`, bundle **651 692 B**, sha256 `05b8cff7df066b2aa8b1d5459051f08be768117c1d9d3ef7d6ecc1b5c5fdef98` |
| `.git` do destino | **≈ 2 MB** (`du -sk .git` = 2079 KB; o pack do monorepo tem 134 MB) |
| transporte | `destino-muserverrecriado.bundle`, **1 348 998 B**, sha256 `9eb8e94a5142f24a…` — clone `-b main` dá árvore idêntica e `make -s check` sem falhas |
| `make -s gate` no destino | **PASS=14 FAIL=0 BLOCKED=6 NOT_IMPLEMENTED=0 SKIPPED=2, 281 asserções, exit 0** (medido em execuções quietas; sob carga o `bench` pode sair `BLOCKED` — 13 PASS/7 BLOCKED — e bloqueado não é falha nem meta) |
| clone independente | árvore e inventário **idênticos** ao local (174 arquivos, mesmo blob por arquivo); `make -s check` sem falhas |
| `make -s check` / `fuzz` / `gate-selftest` no destino | sem falhas / 12–12 (150 000 iterações) / 19–19 |
| `scripts/verify-backup.sh` no destino | ok=9, **falhas=1** (a publicação, honestamente) e blocked=1 (referência ausente) |
| **publicação** | **BLOQUEADA**: 403 `denied to heldergaraujo2`; API do destino responde `Resource not accessible by integration` |

As 6 etapas BLOCKED no destino são exatamente as que exigem a referência original (`pe`, `data`,
`cfg`, `ref-intacta`, `interop`, `lua`): `MuServer/` (10 021 arquivos, ~615 MB, pacote do
fornecedor) **não** viaja para o repositório público. No monorepo de origem o mesmo portão dá
PASS=18 BLOCKED=2 com 339 asserções — a diferença é 100 % atribuída à referência ausente.

## Defeito medido e corrigido nesta rodada (teste de descritores)

Ao validar o destino, `make -s seguranca` falhou de forma intermitente (1 em ~10 execuções): a
**linha de base** do teste de descritores era uma leitura solta logo depois da bateria de
malformações, e o close assíncrono do servidor ainda estava em voo — `fd_antes=9` com piso real 8
(as 10 execuções estabilizaram em 8; nenhum acúmulo entre rodadas). A base passou a ser o **piso
observado numa janela curta**; a asserção (`base == estabilizado == 2ª rodada`) continua estrita e um
vazamento real ainda falha. Conferido depois da correção: 8/8 execuções na origem e 6/6 no destino,
`base=8` sempre (o imediato chegou a 10, como já era medido).

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

## Ao reprocessar (o que quebra se a origem evoluir)

`preparar-destino.sh` fixa `TREE_ESPERADA`, `ARQ_ESPERADOS` e `SHA_ESPERADO` no cabeçalho: divergir
disso aparece como **FALHA com os dois valores medidos**, nunca como verde — e as constantes devem
ser refixadas **depois** de medir a construção nova (o mesmo vale para as contagens nos assets).
Rebuild muda hashes por construção; a rodada só fecha quando árvore, contagem e sha256 conferem em
duas construções independentes.

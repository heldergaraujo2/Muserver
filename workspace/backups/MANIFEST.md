# MANIFEST da copia independente (R-0)

| campo | valor |
|---|---|
| conteudo | arvore `recriado/` inteira (**87 arquivos**), num commit orphan unico (branch local `mu2-snapshot`) |
| origem | `git commit-tree 983a409:recriado` (rodada da etapa `enc`: probe, teste, relatorio e docs da cifragem do Lua do cliente; a pasta `MuserverRecriado/` ficou intocada de proposito) |
| branch do snapshot | `mu2-snapshot` @ `8faa6e41eb94122df02fc2bf36fc4d9e95ba3c10` (semente de migracao `mu2-v2` segue local, com historia) |
| arquivo | `mu2-v2.bundle` (283662 bytes) |
| sha256 | ver abaixo |

sha256: 51a24d03a6d66e34951d799f933e3c7e233eb0e05217fa9f4346a877572bb57d

## Como o backup e conferido (e o buraco que o `binary` tapou)

Um `* text=auto` no `.gitattributes` da raiz aplicava `text: set` ao `*.bundle`: o blob comitado
divergia do arquivo em disco (`be79f094… != 1ec952bd…`), ou seja, **o bundle publicado estava
corrompido para qualquer pessoa que o recuperasse por clone**, e o verificador nao via isso porque
media o arquivo do worktree. Corrigido com `workspace/backups/.gitattributes` (`*.bundle binary`) e
com a verificacao `FULL=1`, que clona a branch publicada e re-confere o bundle la dentro.

## Como restaurar (teste real, ja executado por `scripts/verify-backup.sh`)

```sh
git bundle verify workspace/backups/mu2-v2.bundle   # deve dizer que esta ok e listar 1 ponta
git clone -b mu2-snapshot workspace/backups/mu2-v2.bundle /tmp/mu2-v2-restaurado
cd /tmp/mu2-v2-restaurado && git log --oneline | head -3   # sem -b, o clone nasce sem arvore
```

## Por que este bundle, e por que ele fica dentro da arvore

O v1 morreu com os unicos 20 commits num clone irmao nao rastreado e num bundle escrito em
`/home/user/` (fora da arvore persistida). Entao aqui a copia independente mora **dentro** do
caminho rastreado: o `git push` da branch da sessao leva o bundle junto, e ele sobrevive a
qualquer recriacao de sandbox.

## Tamanho e por que ele agora e constante

17 225 (R-0) -> 38 233 -> 66 195 -> 134 694 -> 204 585 (so realocar, nao bastou) -> 31 771
(snapshot orphan, rodada das lacunas) -> 247 621 (rodada da publicacao) -> 258 497
(rodada de fechamento e do destino) -> **259931 bytes** (rodada da publicacao dentro do monorepo,
83 arquivos) -> **283662 bytes** (rodada da etapa `enc`, 87 arquivos). O tamanho acompanha a
arvore `recriado/`; o snapshot orphan garante que ele nao cresce por acumulo de si mesmo.

Nota de conferencia (2026-10-13): a rodada anterior registrou `259727` na linha do tempo e `259931`
no cabecalho; medido agora, o bundle daquela rodada tinha **259931 bytes** — a linha do tempo foi
corrigida para o valor medido, sem reescrever nenhum outro numero.

## O que o verificador ja pegou (e por que ele existe)

A primeira versao deste \`git clone\` nao usava \`-b mu2-v2\`: o HEAD do clone apontava para um
\`main\` que o bundle nao contem, e o checkout saia vazio com um warning que ninguem lia. Um backup
que restaura "com warning" nao restaura. O \`scripts/verify-backup.sh\` passou a exigir o clone com
\`-b\` e a comparar o conjunto de arquivos — e falhou sozinho ate isso ser corrigido.

## Regras desta copia

- O bundle e regravado **no fim de cada rodada** (depois do ultimo commit), entao ele cobre tudo
  exceto a si mesmo; a conferencia de arvore em `verify-backup.sh` compara exatamente esse escopo
  (`recriado/**` sem `recriado/backup/`).
- A branch `mu2-v2` e local: a unica branch que se publica daqui e a da sessao,
  `arena/cf1de8ce-muserver`. Nao se empurram refs extras sem o dono pedir.
- Quando `MuserverRecriado` for autorizado ao App GitHub, o caminho de saida e este mesmo branch:
  `git push <novo-remote> mu2-v2:main` (historia preservada, nenhum commit perdido), ou o bundle como
  transporte se a rede nao permitir push. Antes de afirmar qualquer publicacao, conferir com
  `git ls-remote` que o SHA remoto == o SHA local da branch publicada (conferido nesta rodada).

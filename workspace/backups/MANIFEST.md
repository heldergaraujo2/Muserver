# MANIFEST da copia independente (R-0)

| campo | valor |
|---|---|
| conteudo | historia do v2 (somente a arvore `recriado/`, com o `recriado/.gitignore` como raiz) |
| origem | subtree split de `recriado/` (arquivo fora da arvore dividida, ver D2-15) |
| branch local criada | `mu2-v2` @ `a97d8b6` |
| arquivo | `mu2-v2.bundle` (204585 bytes) |
| sha256 | ver abaixo |

sha256: 83454231af911d85eb2ce1d4e51c0a7edd8f502a1b0a07660e78e6cc58691e51

## Como restaurar (teste real, ja executado por `scripts/verify-backup.sh`)

```sh
git bundle verify recriado/backup/mu2-v2.bundle     # deve dizer que esta ok e listar 1 ponta
git clone -b mu2-v2 recriado/backup/mu2-v2.bundle /tmp/mu2-v2-restaurado
cd /tmp/mu2-v2-restaurado && git log --oneline | head -3   # sem -b, o clone nasce sem arvore
```

## Por que este bundle, e por que ele fica dentro da arvore

O v1 morreu com os unicos 20 commits num clone irmao nao rastreado e num bundle escrito em
`/home/user/` (fora da arvore persistida). Entao aqui a copia independente mora **dentro** do
caminho rastreado: o `git push` da branch da sessao leva o bundle junto, e ele sobrevive a
qualquer recriacao de sandbox.

## Tamanho e por que ele agora e constante

17 225 (R-0) -> 38 233 -> 66 195 -> 134 694 (antes da D2-15) -> atual, e nao cresce mais por recursao.

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
  `git ls-remote` que o SHA remoto == `17f4f79`.

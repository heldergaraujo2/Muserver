## 6. Último commit e publicação

Este repositório (`heldergaraujo2/MuserverRecriado`) é o destino da reconstrução. Ele nasceu de
`git subtree split --prefix=recriado` do monorepo `heldergaraujo2/Muserver` (39 commits, mensagens
preservadas) e recebeu, por cima, a evidência `workspace/` e a adaptação de caminhos — ver
`docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`, que traz origem, destino, exclusões e hashes.

- **publicação: NÃO feita.** `git push` no destino →
  `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`, com
  `Resource not accessible by integration` na API **do destino** (no repo de origem respondendo
  normal). É a seleção de repositórios da instalação do GitHub App, não a ACL do usuário.
  Desbloqueio: o proprietário inclui `MuserverRecriado` na instalação com *Contents: Read and write*;
  depois, no monorepo `heldergaraujo2/Muserver`, `bash workspace/migracao/publicar-destino.sh`
  (o script mora lá: ele depende do split do monorepo e nao pode viver dentro do destino).
- histórico do monorepo: branch `arena/cf1de8ce-muserver` (o v2 vivia lá dentro para não repetir o
  v1, que morreu num clone não rastreado; essa razão deixou de valer agora que existe repo próprio).
- nada aqui é declarado publicado antes de `git ls-remote` conferir o SHA remoto.

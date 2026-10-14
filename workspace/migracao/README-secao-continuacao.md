## Por que este repositório é a continuação (e não um clone solto)

O v1 morreu exatamente por morar num clone não rastreado (`/home/user/MuserverRecriado`): o mecanismo
de persistência da sessão grava o diff da árvore do repositório **da sessão** (`Muserver`), e o irmão
ficou de fora. Evidência em `workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md`. Esta publicação é a
resposta a isso: a reconstrução sai do diretório irmão e passa a ter repositório próprio, com a
história dos commits (`git subtree split --prefix=recriado`, 39 commits) — ver
`docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`.

1. toda rodada termina com `git add <caminhos explícitos>` (nunca `git add -A`), commit, `git push` e
   `git ls-remote` **lido de volta** para conferir o SHA remoto;
2. uma cópia independente é regravada a cada rodada em `workspace/backups/` (bundle + manifesto com
   sha256), e `scripts/verify-backup.sh` é o que atesta — com `FULL=1` conferindo o que foi **publicado**,
   não só o que está no worktree;
3. **`workspace/` mantém o caminho relativo do monorepo de origem** porque o bundle de backup mora ali
   e é ele que carrega a árvore restauravel; mover a evidência quebraria o manifesto e a restauração.

### Estado da publicação (2026-10-12)

`heldergaraujo2/MuserverRecriado` **continua vazio**: o `git push` responde
`403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`, e a API responde
`Resource not accessible by integration` no repositório de destino (funciona em `Muserver`). Isso é
seleção de repositórios da **instalação do GitHub App**, não permissão do usuário (a ACL do usuário
diz `push=true`). O proprietário precisa incluir `MuserverRecriado` na instalação com *Contents: Read
and write*. O conteúdo está pronto e testado neste diretório; publicação não foi afirmada. A
tentativa de push foi repetida no fechamento da rodada e respondeu o mesmo `403`.

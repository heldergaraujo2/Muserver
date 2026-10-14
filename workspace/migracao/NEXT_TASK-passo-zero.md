## Passo zero (bloqueado no proprietário): publicar este repositório

O conteúdo está pronto e testado aqui; o que falta é **permissão**. `git push` para
`heldergaraujo2/MuserverRecriado` responde
`403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`, e a API do GitHub
responde `Resource not accessible by integration` no destino (no repo de origem responde normal).
Isso é a **seleção de repositórios da instalação do GitHub App**, não a ACL do usuário (que diz
`push=true`). Ação do proprietário: incluir `MuserverRecriado` na instalação com *Contents: Read and
write*. Depois disso, no monorepo `heldergaraujo2/Muserver`: `bash workspace/migracao/publicar-destino.sh`
(faz push, confere `ls-remote`, clona de volta e roda o portão). Nada é afirmado publicado antes do `ls-remote` conferir.

Estado de partida no monorepo de origem (medido, não relato): `make -s gate` → **18 PASS, 0 FAIL,
2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções, 22 etapas, exit 0**; `gate-selftest` 19/19;
`make -s check` 182 asserções; `FULL=1 verify-backup.sh` 15/15. Branch `arena/cf1de8ce-muserver`.
Neste repositório publicado, o mesmo portão dá **14 PASS, 0 FAIL, 6 BLOCKED, 281 asserções** — as 6
BLOCKED são as etapas que exigem a referência `MuServer/`, que não viaja (ver
`docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`).

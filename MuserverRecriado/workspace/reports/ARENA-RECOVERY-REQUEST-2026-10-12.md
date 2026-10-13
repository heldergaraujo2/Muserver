# Solicitação de recuperação ao suporte da Arena — 2026-10-12

Pronto para enviar como está. Nada aqui pede alteração de repositório nem operação destrutiva.

---

**Assunto:** workspace perdido — clone Git fora da árvore rastreada não foi coberto pela persistência (sandbox `iv600oxcuk5qmwl1259uk`, ambiente `mn0k6lgvyo6q8utbj8jh`)

**O que aconteceu**

Uma sessão de agente (modos de código, ~20 commits de trabalho) manteve um projeto em
`/home/user/MuserverRecriado` — um **clone de outro repositório** (`heldergaraujo2/MuserverRecriado`),
vizinho ao repositório rastreado pela sessão (`/home/user/Muserver`). O projeto não pôde ser
empurrado para o GitHub durante a sessão (HTTP 403 de permissão do token), então o único depósito dos
commits era o próprio disco do sandbox. Entre duas rodadas, o ambiente foi recriado e o clone
desapareceu. O mecanismo de persistência da sessão gravou um `git diff` **da árvore do repositório
rastreado** (visto em `/tmp/arena-workspace/coding.patch`, 598 KiB, 90 arquivos, todos sob
`MuServer/` e `workspace/` do repo principal) — o clone vizinho, os bundles em `/home/user/` e o
`/tmp` não entraram.

**Identificadores**

| campo | valor |
|---|---|
| ENV_ID / TEMPLATE_ID | `mn0k6lgvyo6q8utbj8jh` |
| BUILD_ID | `39cf4603-0ca1-4a07-8c3a-3e3bb1e12436` |
| sandbox atual | `iv600oxcuk5qmwl1259uk` |
| repositório da sessão / branch | `heldergaraujo2/Muserver` @ `arena/cf1de8ce-muserver` |
| caminho perdido | `/home/user/MuserverRecriado` (clone; branch principal local `main`) |
| último HEAD conhecido | `c5706a5` (20 commits em `'MuserverRecriado²'`, 29 no repo) |
| também perdido | `/home/user/muserverrecriado-main.bundle`, `/home/user/.venv-tools`, arquivos de trabalho em `/tmp` |
| timestamps úteis | `/home/user` com `mtime` 2026-10-12 14:15; repo principal materializado 14:16; VM atual iniciada 14:57:22 (mesma data) |

**O que já foi verificado do lado de dentro (para não repetirem o trabalho)**

- Busca completa e privilegiada no volume: nenhum arquivo com os nomes característicos
  (`mu2.h`, `mud2*`, `net.sh`, `make_parse.sh`, `pe_probe*`, `bench.c`, `*.bundle`) e nenhuma
  ocorrência do conteúdo em nenhum arquivo de texto do disco. Detalhe em
  `workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md` (desta sessão).
- Um único `.git` no disco; 13 inodes apagados pendentes no ext4, todos de outra origem; varredura
  dos 21,8 GiB do `/dev/vda` com `strings` não achou nada do projeto (com controle positivo que
  prova que a técnica acharia); nada em `/lost+found`; nenhum `fd` `(deleted)` de processo vivo
  (todos os processos nasceram no boot novo).
- Do lado do GitHub o repositório correspondente está **vazio** (`size=0`, `git/refs` → 409), sem
  forks, sem gists, sem artifacts de Actions — ou seja, o disco é o único depósito.
- Do sandbox **não** há como alcançar o plano de controle: `E2B_EVENTS_ADDRESS=http://192.0.2.1`
  (buraco negro), os `GH_TOKEN`/`GITHUB_TOKEN` do ambiente são dummy, `api.e2b.app` resolve mas a
  conexão HTTPS é bloqueada pela allowlist de saída, e o agente local `envd` (porta 49983) só serve
  `filesystem`/`process`/`files` **desta** instância — sem endpoint de snapshot/restore, e os
  endpoints privilegiados respondem 401 sem token. Não tentamos contornar nada disso.

**Pedido (em ordem de preferência)**

1. **Reabrir/retomar a instância anterior** desta sessão (a que rodou até ~2026-10-12 14:15, antes
   da recriação), para que possamos ler `/home/user/MuserverRecriado` e criar imediatamente um bundle
   dentro da árvore rastreada.
2. Se a instância não existir mais, mas houver **snapshot de disco retido**: restaurar ou exportar o
   volume daquela janela (2026-10-11 20:47 → 2026-10-12 14:15, UTC-3) e nos devolver os arquivos —
   basta `/home/user/MuserverRecriado` e, se existir, `/home/user/muserverrecriado-main.bundle`.
   Qualquer formato serve (tar.gz, zip, bundle do git); sabemos colocá-los no lugar.
3. Se houver artefatos de turno retidos, o `coding.patch`/`.diff` dos turnos **anteriores** a
   14:15 também ajudaria — mas ele provavelmente só cobre o repo principal, como o que sobreviveu.
4. **Política**: qual é a retenção de sandboxes pausados e existe alguma ação de "exportar
   workspace"? Queremos saber para não projetar trabalho em cima do disco de novo.

**Melhoria sugerida (não é bloqueante)**: a persistência cobrir diretórios não rastreados *irmãos*
do repositório da sessão — ou documentar explicitamente que só a árvore do repositório rastreado é
persistida. Foi exatamente essa lacuna que custou 20 commits: um projeto publicável só existia no
disco porque o `push` estava sem autorização, e o mecanismo de persistência não olhou para fora da
árvore do repo.

---

## Pedido separado, do lado do GitHub (para o dono da conta, não para a Arena)

Permitir que o agente publique: em **Settings → GitHub Apps / Personal access tokens**, adicionar
`heldergaraujo2/MuserverRecriado` à seleção de repositórios do App/token, com **Contents: Read and
write**. Evidência coletada de que é isso que falta (e não "scope `repo`"): `gh api /user` autentica
como o próprio dono (`heldergaraujo2`, id 323230170), `X-Oauth-Scopes` vem **vazio** e
`Github-Authentication-Token-Expiration: 2026-10-12 23:07:08 UTC` ⇒ token de usuário de App GitHub,
de vida curta, com seleção de repositórios que exclui `MuserverRecriado`. O token precisa ser
reemitido depois de incluir o repositório. Com isso, qualquer restauração é publicada na hora e o
disco deixa de ser o único depósito.

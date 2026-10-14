# Busca de recuperação do projeto C — 2026-10-12 (rodada forense, com privilégio)

Objetivo declarado: localizar `MuserverRecriado` (HEAD `c5706a5`) antes de qualquer reconstrução.
Esta rodada refaz as buscas anteriores **como root** (`sudo` sem senha neste sandbox — as buscas
prévias rodaram como usuário e silenciaram erros de permissão com `2>/dev/null`, o que é um defeito
de método que corrigi aqui).

## 1. Workspace e diretórios de trabalho existentes (inventário, não presunção)

| item | valor medido |
|---|---|
| `pwd` / diretório inicial | `/home/user` (raiz do workspace persistido) |
| instância | `E2B_SANDBOX_ID=iv600oxcuk5qmwl1259uk`, `ENV_ID=TEMPLATE_ID=mn0k6lgvyo6q8utbj8jh`, `BUILD_ID=39cf4603-0ca1-4a07-8c3a-3e3bb1e12436` (de `/.e2b`) |
| boot | `uptime -s` = 2026-10-12 14:57:22; 76 processos de usuário; **nenhum** processo de ontem |
| blocos | só `vda` (21,8 GiB, montado em `/`); `loop0..5` sem *backing file* nem filesystem; nenhum outro volume, mount extra ou snapshot montável |
| uso | 1,6 GiB usados / 5 123 043 de 5 724 160 blocos livres (**89 % livre** → quase não houve reaproveitamento de blocos; se os bytes estivessem aqui, estariam legíveis) |
| conteúdo de `/home/user` | `.bash_logout .bashrc .profile Muserver` — nada de `MuserverRecriado`, `.venv-tools`, `muserverrecriado-main.bundle` |
| outros lares | `/home/node` (só dotfiles), `/root` (só `.bashrc`, `.profile`, `.ssh` vazio de interesse), `/lost+found` **vazio** |
| `/code`, `/srv`, `/mnt`, `/media` | vazios; `/opt` só `yarn-v1.22.22`; `/var/tmp` só `systemd-private-*` |

## 2–4. Busca por nome, por conteúdo, e por vestígios de Git/bundle/inodes apagados

Todas as buscas abaixo cobriram **o disco inteiro** com `sudo find / -xdev` / `grep -rlaI`,
excluindo só `/proc /sys /dev`:

- nomes `mu2.h`, `mud2*`, `mu2ctl*`, `net.sh`, `make_parse.sh`, `pe_probe*`, `bench.c`,
  `run_all.sh`, `MuserverRecriado*`, `*.bundle` → **2 resultados, ambos da linha Lua**:
  `workspace/tests/run_all.sh` e a cópia que fiz em `changes/pre-ff-2026-10-12/untracked/`.
- nomes `*c5706a5*` (arquivo de objeto solto de Git teria esse nome) → **nada**.
- conteúdo `MU2_MAX_BODY`, `mu2_frame_encode`, `resposta anterior ainda pendente` em todos os
  arquivos de texto do disco → só 4 arquivos, todos produzidos **por mim nesta sessão**
  (`workspace/reports/WORKTREE-PERDIDO-2026-10-12.md`, `workspace/tools/tcp_window_probe.py` e os
  artefatos `/tmp/arena-workspace/coding.{patch,diff}`).
- `.git` no disco: **um só** (`/home/user/Muserver/.git`); nenhum bare repo, clone alternativo ou
  worktree; sem `.git/worktrees`, sem alternates.
- objetos sem referência no repo A: 6 661 objetos, um único commit pendurado
  (`fd7340c3` = o stash que descartei hoje às 14:43, com os 6 `.lua`; **ainda recuperável** — colei
  uma tag protetora `pre-ff-2026-10-12-stash` nele nesta rodada). Nada do projeto C ali.
- inodes apagados pendentes no ext4 (`debugfs -R lsdel /dev/vda`): **13**, sendo 12 diretórios do
  build da imagem (Jun 15) e 1 diretório de `git stash` de hoje. Nenhum arquivo-fonte.
- varredura do **dispositivo bruto** (`dd if=/dev/vda | strings -n 12 -t d | grep -E
  'MU2_MAX_BODY|queue_reply|mud2|mu2ctl|make_parse|...'`) → 80 ocorrências, **todas explicadas**:
  nomes de arquivo do meu próprio `/tmp/rec`, texto do meu relatório/sonda, e `make_parser` de
  bibliotecas Perl/Python do sistema. Zero conteúdo do projeto C.
  Nota de método: a primeira tentativa dessa varredura **não valeu** — `grep -aob` num dispositivo
  de 21 GiB foi morto por OOM (a "linha" não tem `\n`) e o "0" saiu de um processo morto, não de
  uma leitura completa; e o controle positivo inicial falhou porque `filefrag` numera blocos de
  **4096 B**, não de 1024 B. Refeito com `strings` (que não acumula linha) e com controle positivo
  dirigido no extent físico real do meu relatório (achou `MU2_MAX_BODY`, `WORKTREE-PERDIDO-…md` e
  92× `MuServer`), a técnica passou a ser confiável — e aí o resultado é "nada do projeto C".
- journal ext4 (128 MiB, `debugfs -R 'dump <8>'`): contém 6 ocorrências de `MU2_MAX_BODY` e 5 de
  `queue_reply` — **falso positivo meu**: são os *nomes* `hits_MU2_MAX_BODY.txt` /
  `hits_queue_reply.txt` dos arquivos que eu tinha criado minutos antes em `/tmp/rec`. Todos os
  outros tokens exclusivos (`MU2_PROFILE`, `mu2_frame`, `out_len`, `out_off`, `slotsz`, `mur0`,
  `PER=11`, `registros=`, `sndbuf`) deram **zero**. Registro o engano porque a regra do projeto é não
  atribuir significado a string isolada: o contexto de 600 bytes ao redor do offset mostrava uma
  listagem de diretório, não código.
- `fd` abertos sobre arquivos apagados (`ls -l /proc/*/fd/*` filtrando `(deleted)`): **nenhum** — e
  todos os processos nasceram às 14:57, então não houve sobrevivência de handles da sessão anterior.

## 5. Reabrir o ambiente anterior / mecanismos de exportação

- O único serviço de arquivos acessível daqui é o `envd` (`/usr/bin/envd`, porta **49983**), que
  serve **esta** instância. Não há como, de dentro, apontá-lo para o disco da instância anterior.
- O plano de controle e2b não é alcançável do sandbox: `E2B_EVENTS_ADDRESS=http://192.0.2.1`
  (TEST-NET-1, buraco negro) e os tokens de ambiente são `arena-egress-dummy-token`. Os logs de
  instância do `envd` falham com 400 do coletador — ou seja, nem a exportação de log está ativa.
- O artefato de snapshot que encontrei (`/tmp/arena-workspace/coding.patch`, 598 KiB, 90 arquivos,
  14 229 linhas) é um **`git diff` da branch contra o commit base do repo A** — por construção ele
  só cobre a árvore rastreada de `Muserver`. Ele **não** contém o clone de `MuserverRecriado` nem o
  `.bundle`, porque ambos viviam fora daquela árvore. Isso é a causa da perda, medida e não
  inferida: a persistência é *por repositório*, e o projeto C era outro repositório.
- Não há `~/.ssh/config`, nem remoto alternativo, nem mirror, nem `insteadOf` no repo A: o único
  remoto é `https://github.com/heldergaraujo2/Muserver.git`.

**Consequência prática:** reabrir o ambiente anterior é ação **no lado da Arena** (restaurar/reabrir
o sandbox de ontem, ou extrair o volume daquela instância). Do lado de dentro, os mecanismos foram
todos exercitados e nenhum alcança o disco anterior. Preciso para o pedido: `ENV_ID`
`mn0k6lgvyo6q8utbj8jh`, `BUILD_ID` `39cf4603-0ca1-4a07-8c3a-3e3bb1e12436`, e que o caminho perdido é
`/home/user/MuserverRecriado` (com `/home/user/muserverrecriado-main.bundle` ao lado).

## 6–8. Cópias encontradas, integridade, divergências (e o que foi preservado)

Nada do projeto C foi encontrado, então não houve movimento nem sobrescrita. O que existe e foi
conferido:

| cópia | estado |
|---|---|
| `/home/user/Muserver` (árvore) | HEAD `b5b84da` + 2 commits meus (`c1177ce`, `13c2f17`); `git status` limpo |
| `origin/arena/cf1de8ce-muserver` | `13c2f17` ✓ (empurrado e conferido com `ls-remote`) |
| artefato Arena `coding.patch` | diff da árvore; bate com o conteúdo do repo (mesmos arquivos) |
| tag nova `pre-ff-2026-10-12-stash` → `fd7340c3` | guarda o estado pré-ff dos 6 `.lua` (o stash que descartei): 6 arquivos, 327+/316− — nada descartado de fato |
| `workspace/changes/pre-ff-2026-10-12/` | patch da árvore, `status --porcelain`, `HEAD-antes`, cópias dos 6 `.lua` + os 36 untracked, md5 |
| `MuServer/` (748 MB) | íntegro e conferido: `ConnectServer.exe` `f25eecb6…`, 92 `.att` de 65 539 B, 99 arquivos em `Data/MonsterSetBase`, 71 binários, `MuEditor.exe` em `Tools/Editores/MuEditor/` |

GitHub (medido com o token real, que é **do próprio dono**: `gh api /user` → `heldergaraujo2`, id
323230170):

- `MuserverRecriado`: `size=0`, `pushed_at=2026-10-11T20:47:12Z`, `git/refs` → **409 Git Repository
  is empty**; 0 forks.
- varredura das árvores dos **13** repositórios públicos do dono por `mu2|mud2|net.sh|make_parse|
  pe_probe|CURRENT_STATE|NEXT_TASK|PERFORMANCE`: os únicos hits são de *outros* projetos que seguem
  a mesma convenção de docs (`Nexo/project/CURRENT_STATE.md`, `Otimizacao-cliente/docs/PERFORMANCE.md`,
  `Age-Of-Aether/Docs/PHASE_*_PERFORMANCE_*`, `NEW-ERA-KNOWLEDGE/NEW_ERA_CURRENT_STATE.md`,
  `Nexora`/`Otimizer` `PROJECT_MEMORY/08_CURRENT_STATE.md`). **Nenhum** contém o projeto C.
  Alerta útil: essa semelhança de nomes é exatamente o que faria uma restauração apressada pegar a
  árvore errada — conferir sempre por `mu2.h`/`mud2.c`, não por `CURRENT_STATE.md`.
- busca global de código por `MU2_MAX_BODY`: `total_count 0`; busca de repositórios por
  `MuserverRecriado`: só o próprio (vazio). Gists (público e autenticado): 0. Actions: 0 workflows,
  0 artifacts. Issues/PRs em `Muserver`: nenhum.
- Sobre o 403, agora com evidência do cabeçalho: `X-Oauth-Scopes:` **vazio** e
  `Github-Authentication-Token-Expiration: 2026-10-12 23:07:08 UTC` ⇒ é **user access token de
  GitHub App** de vida curta, sem scopes clássicos. O conserto não é "conceder scope `repo`": é
  na configuração do App, em *Repository access*, incluir `heldergaraujo2/MuserverRecriado` (com
  *Contents: Read and write*), e o token precisa ser reemitido depois disso (ele vence hoje 23:07 UTC).

## 9. Próximo passo seguro

1. **Do lado de fora (dono/Arena):** reabrir ou exportar o volume da instância anterior
   (`ENV_ID mn0k6lgvyo6q8utbj8jh`) e entregar `/home/user/MuserverRecriado` (ou o `.bundle`).
   Alternativa igualmente válida: no GitHub, conceder ao App o repositório `MuserverRecriado` —
   mas só adianta se algum dos discos acima voltar, porque nenhum commit daquele repo foi publicado.
2. **Do lado de dentro, ao receber a árvore:** nada de tocar no produto antes de
   `git rev-parse HEAD == c5706a5`, `git status --porcelain` vazio, `git bundle verify` (se vier
   bundle), e o portão de baseline `make -s build && make -s make-sintaxe &&
   MU_REF_DATA=/home/user/Muserver/MuServer bash scripts/run_all.sh`. O `MU_REF_DATA` já está aqui.
3. **Só então** executar N-T5.3d2 com a receita medida (relatório do incidente, §3–§4):
   `--sndbuf 1024` no serviço **e** `SO_RCVBUF=1024` no cliente **antes do `connect()`**, ≥30
   requisições encadeadas sem leitura, classificando cada desconexão pela linha de log do servidor.
   A afirmação "não alcançável em loopback" (em `PERFORMANCE.md §5.2`) já está refutada por medida.
4. Reconstruir `src/` a partir de memória de sessão continua fora de questão: produziria um produto
   novo com números velhos, e é a única coisa que esta rodada poderia ter feito "parecendo" progresso.

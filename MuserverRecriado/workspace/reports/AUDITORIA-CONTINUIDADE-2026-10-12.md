# AUDITORIA GERAL E RELATÓRIO DE CONTINUIDADE — MU SERVER

Data: 2026-10-12 (medições feitas nesta auditoria, não copiadas de relatos anteriores).
Natureza: **somente leitura**. Nenhuma funcionalidade foi implementada, a R-4 **não** avançou,
`MuServer/` **não** foi alterado, nenhum merge, nenhum `reset --hard`, nenhum `clean`, nenhum
`push --force`, nenhum push de teste.

Comprovação de que nada foi alterado, medida no fim do levantamento:
`git status --porcelain` → 0 linhas; `git diff --quiet HEAD -- MuServer` → sem diferença;
tree `HEAD:MuServer` = `fade04615fabd17778a0e2fd7adf032c8386c924`.

---

## A. Resumo executivo

| item | estado medido |
|---|---|
| Trabalho da reconstrução (v2) | existe, compila, e tem teste verde: **`unit=106 falhas=0`**, **`make-sintaxe=5 falhas=0`**, reproduzido nesta auditoria |
| Escopo real do v2 | **17 arquivos rastreados**, 1 módulo de código (`src/wire.c`, 170 linhas), 1 cabeçalho, 2 testes, 5 docs, 4 relatórios, 1 script |
| Serviço de rede (R-4) | **não existe**: `src/mud2.c`, `src/mu2ctl.c`, `tests/net.sh` ausentes; `POLLOUT`/`queue_reply`/`feed` aparecem só em docs |
| Publicação | branch `arena/cf1de8ce-muserver` = `3f65251181f8673b487d9bfd83f7695841e36706`, local == remoto (conferido por `git ls-remote`) |
| Backup independente | `workspace/backups/mu2-v2.bundle`, 32 679 B, sha256 `34fbb54ca7ef…`, verificador **6/6** e **FULL=1 → 10/10** |
| Referência original | `MuServer/` íntegro: 10 021 arquivos, 615 MB (`du`), 22 `.exe`, 148 `.lua`, `ConnectServer.exe` sha256 `f25eecb6c65214b7` |
| Recuperação do código antigo (v1) | **não recuperado** e não recuperável aqui: `git cat-file -t c5706a5` → `fatal: Not a valid object name` |
| `MuserverRecriado` | vazio (`size=0`, `git/refs` → 409) e fora do alcance da integração (403). **0 refs publicados por mim lá** |
| Bloqueio de benchmark | mantido: `bench/` vazio no disco, nenhum arquivo rastreado, **BLOCKED** |

Frase de uma linha: **o que existe é um codec de enquadramento bem testado; não existe servidor,
não existe rede, não existe compatibilidade provada com o cliente original.**

---

## B. O que existe e funciona, com evidências

### B1. Codec do quadro (único módulo de produto do v2)
- `recriado/include/mu2/mu2.h` (90 linhas): `MU2_HEADER_SIZE 4u` (`code(2,LE)+size(2,LE)`),
  `MU2_MAX_BODY 2048u`, `MU2_MAX_FRAME = 4+2048 = 2052`, `MU2_XOR_KEY_LEN 3u`, perfis
  `MU2_PROFILE_ORIG=0` / `MU2_PROFILE_MUR0=1` / `MU2_PROFILE_COUNT=2`, erros
  `MU2_E_ARG=-1 … MU2_E_PROFILE=-6` (6 códigos, um por causa).
- `recriado/src/wire.c` (170 linhas). Símbolos exportados, lidos do objeto compilado agora com
  `nm` (não do relato): `mu2_frame_encode`, `mu2_frame_decode`, `mu2_frame_size`,
  `mu2_frame_body`, `mu2_body_transform`, `mu2_profile_name`, `mu2_profile_valid`, `mu2_errstr`.
- Validações confirmadas por linha de código: corpo > `MU2_MAX_BODY` → `E_SIZE`; destino pequeno →
  `E_DST_SMALL`; `src_len < 4` → `E_INCOMPLETE` com `f->needed` preenchido (é o que o laço da R-4
  vai consumir); `size < 4 || size > 2052` → `E_BAD_LEN`; perfil fora do conjunto → `E_PROFILE`;
  ponteiro nulo → `E_ARG`.

### B2. Testes que existem e rodam
- `recriado/tests/unit.c` (301 linhas, 13 faixas T1…T13, 41 *sites* `CHECK(` — o total executado é
  106 porque os laços multiplicam). Resultado reproduzido agora: `# unit=106 falhas=0`, exit 0,
  nenhuma violação de sanitizador.
- `recriado/tests/make_parse.sh` (24 linhas, 5 casos sobre o próprio Makefile): `# make-sintaxe=5
  falhas=0`, exit 0, independente do estado de `out/` (usa `make -B -n`).
- Flags realmente usadas, lidas por `make -s dump-CFLAGS`:
  `-std=c11 -O2 -Wall -Wextra -Werror -Wshadow -Wconversion -Wsign-conversion
  -fstack-protector-strong -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3
  -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -Iinclude`
  (`SAN=1` por padrão, `BUILD=out`, e `out/` é ignorado pelo git).

### B3. Falsificação executada (evidência em `recriado/reports/r3-falsificacao.tsv`)
| mutação | resultado | primeira asserção que cai |
|---|---|---|
| F0 referência | `unit=106 falhas=0`; `make-sintaxe=5 falhas=0` | — |
| F1 cabeçalho gravado `size\|code` | `unit=106 falhas=45` | `not ok 10 - T3` |
| F2 `decode` aceita `size < 4` | `unit=106 falhas=2` | `not ok 86 - T7.2` |
| F3 `mur0` vira identidade | `unit=106 falhas=18` | `not ok 47 - T5.2` |
| F4 `-Werror` removido do Makefile | `make-sintaxe=5 falhas=2` | `not ok 1` |

Reversão conferida por `git status --porcelain` vazio em `src/`, `tests/`, `include/`, `Makefile`.

### B4. Cadeia de persistência
- 12 commits do v2 na branch da sessão (`90bbfea` … `3f65251`), cada publicação conferida por
  `git ls-remote` no momento em que foi feita; conferida de novo nesta auditoria.
- `workspace/backups/mu2-v2.bundle` (snapshot orphan, branch local `mu2-snapshot` @ `6968aea`),
  com `MANIFEST.md` (sha256 + tamanho) e `.gitattributes` (`*.bundle binary`).
- `recriado/scripts/verify-backup.sh`: 6 checagens normais + 4 no modo `FULL=1` (clona a branch
  **publicada** e confere, de dentro do clone, bundle byte a byte, `bundle verify`, restauração da
  árvore a partir do bundle clonado e presença do HEAD local no remoto).
  **Nenhuma delas inspeciona `MuServer/`** — a integridade da referência foi conferida aqui à mão.

### B5. Classificação por módulo
| módulo | estado |
|---|---|
| `recriado/include/mu2/mu2.h` | implementado e testado |
| `recriado/src/wire.c` | implementado e testado (106 asserções) |
| `recriado/Makefile` + `tests/make_parse.sh` | implementado e testado (5 casos, portão validado) |
| `recriado/tests/unit.c` | implementado e testado |
| `recriado/scripts/verify-backup.sh` | implementado e testado (10/10 com FULL=1) |
| `recriado/docs/*` (5 arquivos) | documentação escrita; `NEXT_TASK.md` tem 1 defeito cosmético (ver K5) |
| `recriado/reports/*` (4 arquivos) | evidências da R-3, com comando/flags/compilador/commit |
| `recriado/src/mud2.c`, `src/mu2ctl.c`, `tests/net.sh` | **ausentes** (só especificados) |
| `recriado/bench/`, `corpus/`, `tools/` | diretórios vazios no disco, **não rastreados** pelo git → **ausentes do produto** |
| `tests/{e2e,golden,interop,conform,fuzz,gate_state}`, `scripts/run_all.sh` | ausentes |
| benchmark | **bloqueado** (critérios de validade inexistentes neste host de 2 vCPUs) |
| compatibilidade com `ConnectServer.exe` | **não comprovada**; é pergunta da R-6, a responder do binário |

---

## C. Incompleto, ausente ou bloqueado

- **Servidor**: não existe. Nenhum `listen`, nenhum `accept`, nenhum `poll` em código.
- **Rede medida**: zero. Nenhum número de rede desta árvore é resultado — nem alvo atingido.
- **Suítes planejadas**: `net`, `e2e`, `golden`, `interop`, `conform`, `data`, `fuzz`, `pe`,
  `gate_state`, `run_all.sh` → todas ausentes. **Nenhuma pode ser chamada de aprovada.**
- **`bench`**: bloqueado por infraestrutura/critérios, não por falta de vontade.
- **`MuserverRecriado`**: bloqueado por permissão da integração (403 `Resource not accessible by
  integration`); não contornado.
- **Recuperação do v1**: esgotada e negativa; depende de humano (pedido pronto, não enviado).
- **Diretórios vazios não rastreados**: `recriado/{bench,corpus,tools}` existem no disco e **não**
  no repositório (git não rastreia diretório vazio). Um clone novo não os terá.

---

## D. Repositórios, commits e backups

| campo | valor medido |
|---|---|
| diretório de trabalho | `/home/user/Muserver` (raiz do repositório) |
| remoto | `origin → https://github.com/heldergaraujo2/Muserver.git` (fetch/push; sem credencial embutida na URL) |
| branch atual | `arena/cf1de8ce-muserver` |
| HEAD (completo) | `3f65251181f8673b487d9bfd83f7695841e36706` |
| `git status` | limpo (0 linhas); único caminho ignorado presente: `recriado/out/` |
| branches locais | `arena/cf1de8ce-muserver` (3f65251), `main` (6eabb45, == `origin/main`), `mu2-snapshot` (6968aea), `mu2-v2` (a97d8b6, semente de migração, **local**) |
| branches remotas | `origin/main`, `origin/arena/cf1de8ce-muserver` (+ `origin/HEAD → origin/main`) |
| tags | `pre-ff-2026-10-12-stash` (local) |
| stash | 0 |
| publicação | `ls-remote` → `arena/cf1de8ce-muserver` = `3f65251181f8…`, **igual ao HEAD local**; `main` = `6eabb45b9e79…` intacto |
| PR #1 | **#1 OPEN**, autor `heldergaraujo2`, `arena/cf1de8ce-muserver → main`, 19 commits, `mergeable=MERGEABLE`. **Não modificado** |
| `MuserverRecriado` | existe, público, `size=0`, `git/refs` → **409 (vazio)**, sonda de permissão do App → **403**. Nada publicado lá por mim |
| tamanho do repo | `.git` = 135 MB; `MuServer` = 615 MB; total = 751 MB. (O "748 MB" citado em docs antigos = 615 + 133 MB de `.git` daquela época — **não** era o tamanho de `MuServer/`) |
| backup | `workspace/backups/mu2-v2.bundle` 32 679 B, sha256 `34fbb54ca7efbe65f71db1a6ef46dd097d1baf7085afd4f9d260015f46a97647`, snapshot `mu2-snapshot` @ `6968aea`, originado de `93b19a6:recriado` |
| verificador | modo normal **ok=6 falhas=0**; `FULL=1` **ok=10 falhas=0**, exit 0 |
| blob publicado vs disco | `34fbb54ca7efbe65` == `34fbb54ca7efbe65` (o defeito de CRLF que corrompia o blob **está corrigido**) |

### Procedimento exato de restauração (testado pelo verificador, em diretório separado)
```sh
cd /home/user/Muserver
git bundle verify workspace/backups/mu2-v2.bundle            # espera: ok, 1 ponta
sha256sum workspace/backups/mu2-v2.bundle                   # compara com workspace/backups/MANIFEST.md
D=$(mktemp -d)
git clone -q --no-hardlinks -b mu2-snapshot \
    workspace/backups/mu2-v2.bundle "$D/mu2-restaurado"      # -b é obrigatório: sem ele o clone nasce sem árvore
cd "$D/mu2-restaurado" && ls src include tests Makefile      # 17 arquivos
make -s check                                               # espera: unit=106 falhas=0; make-sintaxe=5 falhas=0
```
Alternativa com histórico completo (branch local `mu2-v2`, `subtree split` de `recriado/`):
`git clone -q -b mu2-v2 …` — mesma árvore, com os commits; é também o caminho de migração para o
repositório próprio quando o App for autorizado (`git push <novo-remote> mu2-v2:main`).

---

## E. Situação da R-3 e da R-4

### R-3 — concluída (confirmada no código, não no relato)
Contrato: header de 4 B = `code` (2 B LE) + `size` (2 B LE, total incluindo header); corpo 0…2048;
quadro máximo 2052 B. Perfis: `orig` (cru) e `mur0` (involução posicional
`b[i] ^= k[i%3] ^ byte(code>>(8*(i&1)))`, `k={0xAE,0xEC,0xD8}`). **Ambos são decisão própria do v2**
(D2-11/D2-12), não formato recuperado: o pacote de referência não expõe enquadramento na camada Lua
(`ProtocolCore.lua`: 0 ocorrências de `HEAD_SIZE`/`PacketSize`/`opcode`). O único elemento herdado é
aritmético: `MU2_MAX_BODY=2048` não cabe em 1 byte. O `mur0` alterna posição e opcode, nunca conteúdo,
e **não é cifra**.

### R-4 — especificada, não iniciada
| item da especificação | existe? |
|---|---|
| `src/mud2.c` (laço `poll`, `feed`, `queue_reply`, flags `--listen/--sndbuf/--idle-ms/…`) | **ausente** |
| `src/mu2ctl.c` com `stats` | **ausente** |
| `tests/net.sh` (matriz de backpressure, classificação por linha de log) | **ausente** |
| cenários leitura atrasada / fila cheia / `EAGAIN` | **não testados** (nenhum teste de rede existe) |
| decisão D2-14 (laço pede `POLLOUT` sempre; `EAGAIN` mantém a resposta na vaga; fechamento só em pedido novo com vaga ocupada) | **decidida e documentada**, com asserções especificadas — não implementada |

Resultados de rede: **nenhum real**. O que há são alvos de experimento definidos em
`recriado/docs/NEXT_TASK.md` (matriz `N_conn ∈ {1,4,16}` × `N_frames ∈ {10,29,30,31,60,120}` ×
`t_sem_ler ∈ {0,1s,5s}` × `delay ∈ {0,50ms}` × `--sndbuf ∈ {0,1024}`, 5 repetições, mediana e
amplitude, `SO_RCVBUF` pedido **antes** do `connect()` e efetivos impressos por `getsockopt`), e
`bench` continua **bloqueado**.

---

## F. Inventário da referência original (`MuServer/`, somente leitura)

Escala medida: 10 021 arquivos, 615 MB (`du`; 603 MB aparentes), 13 diretórios de serviço.

| componente | existência | evidência medida |
|---|---|---|
| `ConnectServer` | confirmada | `ConnectServer/ConnectServer.exe` (+ `ConnectServer_old.exe`); config `ConnectServer.ini`, `ServerList.dat`; **portas: TCP 44406, UDP 55557** |
| `DataServer` | confirmada | `DataServer/DataServer.exe`; `DataServer.ini`, `AllowableIpList.txt`; **porta 55960** |
| `JoinServer` | confirmada | `JoinServer/JoinServer.exe`; `JoinServer.ini`; **porta 55970**, fala com o ConnectServer em 55557 |
| `GameServer` | confirmada (3 cópias) | `GameServer/GameServer.exe`, `GameServerCS/GameServer.exe`, `SpeedServer/GameServer/GameServer.exe`; referenciam ConnectServer 55557 e DataServer 55960 |
| `GameServerCS` | confirmada | 81 arquivos; mesmas portas; a diferença de conteúdo observada são dumps `.dmp` presentes em `GameServer/` e ausentes aqui — **a distinção funcional real (CS = Change Server / Castle Siege?) não foi comprovada por evidência nesta auditoria** |
| Banco de dados | confirmada (SQL Server) | `DB/MuOnline.bak` 16 948 736 B, `MuOnline_old.bak`, `back_hinet.bak`, `mw_v6.bak`, `MuOnline.reg`, `MuOnline64.reg`; **porta 1433** declarada; 4 `.sql` em `Tools/ResetRankingWeb/` |
| Outros serviços | confirmados | `DiscordServer.exe`, `MHPServer.exe`, `PSGuard/{Monitor,Servidor.32,Servidor.64}.exe`, `SpeedServer/` (1 888 arquivos), `SubSalatest/` (3 152 arquivos) |
| Ferramentas | confirmadas | 22 `.exe` no total, 71 PE (`.exe`+`.dll`): `MuEditor.exe`, `Editor.exe`, `LuaEncryptorTool.exe`, geradores `main.exe`/`GetMainInfo-Premium.exe` (v41 Season 6 e S6.20), `GetHardwareId.exe`, `SSU_v1.0.4.164.exe` |
| Scripts Lua | confirmados | **148 `.lua`** + 3 `.enc`; `Data/Script/{ScriptMain.lua, Scripts, System, Utils}`; `ProtocolCore.lua` em `Data/Script/System/` e em `SpeedServer/Data/Script/System/` |
| Dados de jogo | confirmados | `Data/` = 1 631 arquivos: `CashShop Character Custom Effect Event EventItemBag Hack Item Message Monster MonsterSetBase Move Quest QuestWorld Script Shop Skill Terrain` + `Command.txt`, `MapManager.txt`, `MapServerInfo.dat`, `ShopManager.txt` |
| Recursos 3D/terreno | confirmados | `.att` **276** (todos de 65 539 B; 92 deles em `Data/Terrain`), `.ozt` 313, `.ozj` 106, `.bmd` 56, `.smd` 8; `Data/MonsterSetBase` = **99 arquivos** em 43 entradas de topo |

Dúvidas que permanecem: papel exato de `GameServerCS` vs `GameServer` vs `SpeedServer`; se os 4
`.bak` são restauráveis e de qual versão; se os `main.exe` geradores correspondem ao cliente em uso;
e a **versão exata** do conjunto (os docs citam Season 6.20, mas os componentes não foram provados
como sendo todos da mesma versão — não presumir).

---

## G. Histórico da reconstrução e da recuperação

- **O que se sabe do v1**: implementação C com último commit conhecido `c5706a5`, vivendo em
  `/home/user/MuserverRecriado/` (clone irmão, fora da árvore persistida) e num bundle em
  `/home/user/`. Ambos **desapareceram com a recriação do sandbox**.
- **Prova de que não está aqui**: `git cat-file -t c5706a5` → `fatal: Not a valid object name
  c5706a5`; nenhuma menção em `git reflog --all`; 6 574 objetos no pack, nenhum deles do v1.
  **O código antigo não foi recuperado.**
- **Buscas executadas** (registradas em `workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md`):
  inventário de `/home/user` e outros lares; `debugfs lsdel` (13 inodes apagados, 12 diretórios);
  varredura do dispositivo bruto; leitura do journal ext4 (encontrou 6 ocorrências de
  `MU2_MAX_BODY` e 5 de outro símbolo — **fragmentos, não arquivos**); procura por nomes
  (`mu2.h`, `mud2*`, `mu2ctl*`, `net.sh`, `bench.c`, `*c5706a5*`) e por conteúdo; `fd` abertos sobre
  arquivos apagados (nenhum); `/code /srv /mnt /media /lost+found` vazios; `envd` local sem rota de
  snapshot; plano de controle e2b inalcançável.
- **Pedido pendente**: `workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md` (5 646 B), pronto,
  **não enviado** — exige humano. IDs: `TEMPLATE_ID mn0k6lgvyo6q8utbj8jh`,
  `BUILD_ID 39cf4603-0ca1-4a07-8c3a-3e3bb1e12436`, sandbox perdido `iv600oxcuk5qmwl1259uk`.
- **Evidências preservadas**: `WORKTREE-PERDIDO-2026-10-12.md`, `RECUPERACAO-BUSCA-2026-10-12.md`,
  `AUDIT.md` (17 947 B), `PLANO-RECONSTRUCAO-MU2-2026-10-12.md`, `A1-secrets.md`,
  `workspace/inventory/INVENTORY.md`, `workspace/changes/` (originais Lua + patches + cópia
  pré-`ff`), e a tag local `pre-ff-2026-10-12-stash → fd7340c3`.
- **O que não pode ser reconstruído fielmente**: o código C do v1 (lógica do laço, contadores,
  limites empíricos de buffer), os números medidos das suítes dele (`unit=82` e afins são **alvo
  histórico**, proibido citar como reproduzido) e qualquer conclusão de compatibilidade que só o
  binário antigo sustentava.

---

## H. Tabela de testes

| suíte | caminho | objetivo | existe | já rodou | comando | último resultado verificável | dependências | situação |
|---|---|---|---|---|---|---|---|---|
| unit | `recriado/tests/unit.c` | contrato do quadro, 2 perfis, erros, involução | sim | sim (nesta auditoria) | `cd recriado && make -s unit` | `unit=106 falhas=0`, sanitizadores limpos | cc, make, ASAN/UBSAN | **aprovado** |
| make-sintaxe | `recriado/tests/make_parse.sh` | Makefile como contrato (5 casos) | sim | sim (nesta auditoria) | `cd recriado && make -s make-sintaxe` | `make-sintaxe=5 falhas=0` | bash, make (`-B -n`) | **aprovado** |
| check (portão) | `recriado/Makefile` | unit + make-sintaxe juntos | sim | sim (nesta auditoria) | `cd recriado && make -s check` | exit 0, `106/0` e `5/0` | idem | **aprovado** |
| verify-backup | `recriado/scripts/verify-backup.sh` | publicação + backup restaurável | sim | sim (nesta auditoria) | `bash recriado/scripts/verify-backup.sh` / `FULL=1 …` | `ok=6 falhas=0` / `ok=10 falhas=0` | git, rede (só no FULL) | **aprovado** |
| net | `recriado/tests/net.sh` | backpressure, fila, `EAGAIN`, classificação por log | **não** | nunca | — | — | requer `mud2`/`mu2ctl` | **ausente** |
| e2e | — | ponta a ponta com cliente simulado | não | nunca | — | — | `mud2` | ausente |
| golden | — | vetores fixos de bytes | não | nunca | — | — | codec | ausente |
| interop | — | contra o `ConnectServer.exe` real | não | nunca | — | — | Wine/Windows + binário | ausente / bloqueado |
| conform | — | conformidade com o protocolo original | não | nunca | — | — | evidência do binário (R-6) | ausente / bloqueado |
| data | — | `Data/` (Lua, itens, mapas) | não | nunca | — | — | parser de formatos | ausente |
| fuzz | — | robustez do `feed`/`decode` | não | nunca | — | — | libFuzzer/AFL | ausente |
| pe | — | inspeção dos PE da referência | não | nunca | — | — | ferramenta de PE | ausente |
| bench | `recriado/bench/` (vazio, não rastreado) | desempenho | não | nunca | — | — | critérios de validade (R-7) | **bloqueado** |
| gate_state | — | estado dos portões por fase | não | nunca | — | — | — | ausente |
| run_all.sh | `recriado/scripts/run_all.sh` | orquestração | não | nunca | — | — | suítes acima | ausente |

Nenhuma suíte foi marcada como aprovada por existir diretório ou especificação.

---

## I. Arquivo central de continuidade recomendado

**Caminho recomendado: `recriado/docs/CONTINUITY.md`** (dentro da árvore do v2, portanto vai junto
no `subtree split` e no bundle de restauração; um arquivo em `workspace/` não viajaria com o produto).

Estrutura proposta (títulos fixos, para que qualquer agente ache a mesma coisa):
1. Identidade e objetivo do projeto (v2 = história nova; referência = somente leitura).
2. Estado atual confirmado (comandos + resultados, com data).
3. Arquitetura e decisões (ponteiro para `DECISIONS.md`, D2-01…D2-15).
4. Fases concluídas / em andamento / pendentes (R-0…R-9).
5. Testes executados e resultados reais (tabela H, apenas o que rodou).
6. Bloqueios e dependências (App GitHub, Arena, bench, Wine).
7. Último commit e publicação confirmada (SHA + `ls-remote`).
8. Backup: caminho, sha256, procedimento de restauração.
9. Próxima tarefa exata (ponteiro para `NEXT_TASK.md`).
10. Regras de proteção (não tocar em `MuServer/`, sem `reset --hard`/`clean -fd`/`push --force`,
    sem `git add -A`, sem merge por conta própria, sem inflar limites para teste passar).

**Recomendação: `CONTINUITY.md` como índice curto (1 página) que aponta para os arquivos existentes,
sem duplicar conteúdo** — duplicação é o que produz documento contraditório. Consolidação proposta:

| arquivo | papel a partir de agora |
|---|---|
| `recriado/docs/CONTINUITY.md` | **fonte principal** (novo, a criar; não criado nesta auditoria) |
| `recriado/docs/CURRENT_STATE.md` | estado detalhado da última rodada (referenciado) |
| `recriado/docs/NEXT_TASK.md` | próxima tarefa executável (referenciado) |
| `recriado/docs/DECISIONS.md` | decisões D2-01…D2-15 (referenciado, nunca resumido) |
| `recriado/docs/CHANGELOG.md` | histórico por rodada (referenciado) |
| `recriado/docs/ENVIRONMENT.md` | host, toolchain, limites do sandbox |
| `recriado/README.md` | porta de entrada humana |
| `workspace/reports/*` | linha de recuperação/incidente + **esta auditoria** |
| `workspace/backups/MANIFEST.md` | identidade do backup |

Risco a evitar: hoje o estado está espalhado em 7 documentos com datas diferentes (o mais recente de
cada um: `CURRENT_STATE.md` @ `3dcc9e7`, `NEXT_TASK.md` @ `d19550d`, `DECISIONS.md` @ `b6ff48f`,
`PLANO-…` @ `def9ad1`). Um agente novo precisa saber qual manda — daí o índice.

---

## J. Roadmap preliminar (metas futuras, nenhuma implementada, nenhuma parte do produto)

| # | meta | o que já existe | a investigar | dependências | testes que provariam |
|---|---|---|---|---|---|
| 1 | Painel administrativo (configurar/iniciar/parar/monitorar) | `mu2ctl stats` **especificado**, não escrito | formato de linha do `stats`; onde persistir config | R-4 (`mud2`) | `e2e` + teste do `stats` |
| 2 | Assistente de publicação online (portas, firewall, IP público, conectividade) | portas da referência medidas (44406/55557/55960/55970/1433) | se o serviço roda fora do sandbox; NAT/firewall do dono | serviço real + acesso do dono | teste de conectividade externa documentado |
| 3 | Gerenciamento dos serviços reais (`GameServerCS` etc.) | executáveis inventariados | papel de CS vs GameServer vs SpeedServer; como são lançados | Wine/Windows ou host do dono | `interop`/smoke por serviço |
| 4 | Pacotes maiores | `MU2_MAX_BODY=2048` documentado e testado | limite real do protocolo no binário (R-6); o que o cliente aceita | evidência do binário | `conform` + regressão de quadro |
| 5 | Lua com arquivos/scripts maiores | 148 `.lua` na referência; patches preservados em `workspace/changes/` | se há limite real comprovado (não presumir) | parser/interpretador | `data` + golden de script |
| 6 | Melhor uso de modelos/animações/3D nativos | `.bmd` 56, `.smd` 8, `.att` 276, `.ozt` 313, `.ozj` 106 | formatos e limites do cliente | parser de formato | `data`/golden por formato |
| 7 | Recursos 3D mais pesados | nada | limites reais de cliente e servidor | item 6 | medição comparativa documentada |
| 8 | FPS, fluidez, latência, tempo de resposta, estabilidade | nada medido | linha de base **antes** de qualquer otimização | `bench` desbloqueado (critérios R-7) | `bench` antes/depois com mediana e amplitude |
| 9 | Memória, CPU, rede, concorrência, observabilidade, diagnóstico | ASAN/UBSAN já no portão; contadores planejados | perfil de alocação do laço | R-4 + `bench` | sanitizadores + `bench` + `stats` |
| 10 | Compatibilidade com cliente original, regressão, segurança, desempenho | decisão D2-11 documenta o que **não** é afirmado | binário (`ConnectServer.exe`) como fonte de verdade | Wine/Windows, R-6 | `interop` + `conform` + fuzz |
| 11 | Backups restauráveis, commits frequentes, publicação verificada, continuidade | **já funciona**: bundle + `verify-backup.sh` 10/10 + `ls-remote` | automatizar o ritual no fim de rodada | nada | o próprio verificador (já verde) |

Nenhum número de desempenho foi estabelecido aqui, por falta de linha de base.

---

## K. Riscos técnicos e de persistência

1. **Perda de sandbox**: o v1 morreu assim. Mitigação ativa: bundle dentro da árvore rastreada +
   publicação na branch da sessão + `FULL=1` provando o caminho de restauração.
2. **`.gitignore` que esconde evidência**: `workspace/reports/*.json`, `workspace/recovered/**`,
   `recriado/out/`, `recriado/reports/*.raw` são ignorados — um relatório salvo nesses formatos
   **não persiste**. `.md`/`.tsv` persistem (verificado por `git check-ignore`).
3. **Binário em repositório**: o bundle só ficou correto depois de `*.bundle binary`; sem isso o
   CRLF corrompia o blob publicado sem alterar o worktree. Regra: todo artefato binário novo
   precisa de atributo `binary` e de conferência **pós-push**.
4. **Crescimento do repositório**: `.git` já tem 135 MB e a referência 615 MB. O snapshot orphan
   mantém o custo do backup constante (32 679 B), mas o histórico da branch continua crescendo; o
   teto de artefatos por patchset (~128 MB / 10 000 arquivos) é um limite real.
5. **Defeito cosmético em `NEXT_TASK.md`**: a especificação da R-4 contém uma quebra de linha no
   meio de uma palavra ("quando h / a resposta anterior pendente"). Não corrigido nesta auditoria
   (a tarefa proibia reescrever documentação); corrigir na R-4.
6. **Diretórios vazios não rastreados** (`bench/`, `corpus/`, `tools/`): parecem estrutura e não são.
   Ou ganham um arquivo (`.gitkeep` + README do que virá) ou saem do discurso.
7. **Host fraco para desempenho**: 2 vCPUs Xeon 2.60 GHz, 3 939 MB de RAM, `valgrind` e `gdb`
   **ausentes**. Benchmarks de throughput seriam ruído — por isso `bench` continua bloqueado.
8. **Permissão do App GitHub**: `MuserverRecriado` fora da seleção da integração; o token é de App
   (expira sozinho, reemitido), então "adicionar scope" não resolve. Só o dono destrava.
9. **PR #1 aberto** mistura a auditoria da camada Lua com o projeto novo em `recriado/`. Decisão do
   dono; nenhum merge feito aqui.
10. **Documentação contraditória** se o estado continuar espalhado em 7 arquivos (ver I).

---

## L. Próxima tarefa recomendada (não executada)

**R-4**, exatamente como especificada em `recriado/docs/NEXT_TASK.md`, nesta ordem:
1. `bash recriado/scripts/verify-backup.sh` (portão de entrada; hoje dá 6/6).
2. `src/mud2.c`: laço `poll()` + `feed()` que consome **todos** os quadros do buffer + fila de 1
   vaga + `queue_reply` (fechamento com log dedicado e contador `queue_full_closes`), respeitando
   D2-14 (`POLLOUT` sempre que `out_len != out_off`; `EAGAIN` mantém a resposta; fechamento só em
   pedido novo com vaga ocupada).
3. `src/mu2ctl.c` com `stats` no formato já especificado.
4. `tests/net.sh` com a matriz, `SO_RCVBUF` antes do `connect()`, efetivos por `getsockopt`,
   5 repetições, classificação obrigatória por linha de log, e as duas asserções de D2-14.
5. Falsificações obrigatórias: `break` no `feed()`; remover o `drain()` imediato; inverter a
   política de `queue_reply` — com reversão conferida por `git status --porcelain`.
6. Fim de rodada: docs + relatórios, commit com caminhos explícitos, push + `ls-remote`, snapshot
   regravado e `FULL=1` verde.
Fora de escopo da R-4: `bench`, `conform`, `data`, `interop`.

---

## M. Comandos para outro agente validar o estado sem destruir nada

```sh
cd /home/user/Muserver

# 1. identidade e publicação
git rev-parse --abbrev-ref HEAD; git rev-parse HEAD
git status --porcelain                     # espera: vazio
git ls-remote --heads origin               # espera: arena/cf1de8ce-muserver == HEAD local; main == 6eabb45b…

# 2. portão do v2 (compila em recriado/out, ignorado pelo git; não suja a árvore)
cd recriado && make -s dump-CFLAGS && make -s check; cd ..   # espera: unit=106 falhas=0; make-sintaxe=5 falhas=0

# 3. persistência
bash recriado/scripts/verify-backup.sh                 # espera: ok=6 falhas=0
FULL=1 bash recriado/scripts/verify-backup.sh          # espera: ok=10 falhas=0 (clona o publicado em /tmp)
sha256sum workspace/backups/mu2-v2.bundle              # compara com workspace/backups/MANIFEST.md

# 4. restauração em diretório separado (não escreve no repo)
D=$(mktemp -d) && git clone -q --no-hardlinks -b mu2-snapshot \
    workspace/backups/mu2-v2.bundle "$D/r" && (cd "$D/r" && make -s check)

# 5. integridade da referência original (somente leitura)
git diff --quiet HEAD -- MuServer && echo "MuServer intacto"
git rev-parse HEAD:MuServer                # espera: fade04615fabd17778a0e2fd7adf032c8386c924
find MuServer -type f | wc -l              # espera: 10021
sha256sum MuServer/ConnectServer/ConnectServer.exe   # espera: f25eecb6c65214b7…

# 6. o que NÃO existe (para ninguém presumir)
for f in recriado/src/mud2.c recriado/src/mu2ctl.c recriado/tests/net.sh recriado/scripts/run_all.sh; do
  [ -e "$f" ] && echo "PRESENTE $f" || echo "ausente  $f"; done
git cat-file -t c5706a5                    # espera: fatal: Not a valid object name

# 7. PR e repositório v2 (somente leitura)
gh pr view 1 --json number,state,headRefName,baseRefName
gh api /repos/heldergaraujo2/MuserverRecriado --jq '.size'   # 0
```

Proibido nesta e nas próximas rodadas, sem exceção: `git reset --hard`, `git clean -fd`,
`git push --force`, `git add -A`, merge de branch ou PR, qualquer escrita em `MuServer/`,
inflar `MU2_MAX_BODY`/buffers para teste passar, e citar número do v1 como reproduzido.

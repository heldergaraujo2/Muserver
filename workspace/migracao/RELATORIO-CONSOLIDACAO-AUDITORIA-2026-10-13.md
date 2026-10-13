# Relatório de consolidação e publicação para auditoria independente

| campo | valor |
|---|---|
| data | 2026-10-13 |
| repositório | **https://github.com/heldergaraujo2/Muserver** (público) |
| branch publicada | **`arena/cf1de8ce-muserver`** (PR **#1** aberto para `main`, **não** mergeado — decisão do proprietário) |
| branch principal do repo | `main` @ `6eabb45` — o upload do pacote original; **nada desta consolidação foi empurrado para lá** |
| tag do estado consolidado | **`auditoria-2026-10-13`** (anotada) |
| commits desta consolidação | `578e7e1` (documentos) · `b465111` (backup do marco) · +1 commit com este relatório e os números finais |
| escopo | **consolidação, documentação, versionamento e publicação** — nenhuma reimplementação, nenhuma fase nova iniciada |

---

## 1. URL completa do repositório remoto

**https://github.com/heldergaraujo2/Muserver**
Clone reproduzível: `git clone https://github.com/heldergaraujo2/Muserver.git`
Fora do repositório (e **não** alterado): `https://github.com/heldergaraujo2/MuserverRecriado` —
segue **vazio**; o `push` responde `403` (seleção de repositórios da instalação do GitHub App) e não
foi contornado.

## 2. Branch principal e commit mais recente publicado

| ref | valor |
|---|---|
| branch principal do repo | `main` = `6eabb45b9e7939a3061f4757ed6791efef7c5c3b` (intocada nesta consolidação) |
| branch da consolidação | `arena/cf1de8ce-muserver` |
| commit dos documentos de auditoria | **`578e7e191236e5f53fb890648b6ea92fab8c458f`** |
| HEAD da branch no fecho | lido de volta com `git ls-remote` — ver §13 (o SHA exato está lá, junto com o da tag) |
| tag | `auditoria-2026-10-13` |

## 3. Estrutura geral do projeto

```
Muserver/                      monorepo (história própria do upload)
├── MuServer/                  pacote original de referência — 10 021 arquivos, ~615 MB, SOMENTE LEITURA
├── recriado/                  o produto v2 — 96 arquivos rastreados (o trabalho próprio)
│   ├── src/ include/          wire.c (codec) · mud2.c (serviço) · mu2ctl.c · mu2/*.h (contratos)
│   ├── tools/                 15 ferramentas: mu2codec, mu2fuzz, mu2admin (C) + 12 sondas Python
│   ├── tests/                 unit.c, netclient.c, 16 suítes .sh, golden/quadros.tsv (38 vetores)
│   ├── docs/                  9 documentos de auditoria + 9 canônicos (CONTINUITY, DECISIONS, …)
│   ├── reports/               33 arquivos de evidência (.tsv/.md)
│   ├── scripts/               verify-backup.sh
│   └── out/                   build/teste — IGNORADO pelo git
├── MuserverRecriado/          cópia publicada independente — 174 arquivos + bundle próprio
└── workspace/                 evidência, baselines dos 6 .lua, migração e backups do repositório
```

Detalhe por componente, com contrato e teste que cobre cada um: `recriado/docs/ARCHITECTURE.md`.

## 4. Linguagens, tecnologias e dependências principais

| item | valor medido |
|---|---|
| linguagens do trabalho próprio | **C11** (produto: 3 fontes + 3 CLIs) e **Python 3** (12 sondas), **Bash** (16 suítes) |
| compilador/toolchain | `gcc 12.2.0`, `make 4.3`, `bash 5.2.15`, `python3 3.11.2`, `git 2.39.5` |
| flags | `-std=c11 -O2 -g -Wall -Wextra -Werror -Wshadow -Wconversion -Wsign-conversion -fstack-protector-strong -D_FORTIFY_SOURCE=3` + **ASan+UBSan** (`-fno-sanitize-recover=all`) |
| dependências de runtime | **apenas libc** — zero biblioteca de terceiros, zero pacote instalável |
| dependências de build | somente padrão do sistema; sem `CMake`/`npm`/`pip` |
| o pacote de referência exige | Windows/PE32, **SQL Server via ODBC** (DSN `MuOnline`, driver `SQLSRV32.dll`), VC++ 2010 redist |
| licenças | trabalho próprio **sem licença declarada** (não há `LICENSE` no repo); terceiros e pendências em §9 |

## 5. Sistemas existentes, separados por estado de implementação

| sistema | estado | evidência |
|---|---|---|
| codec de enquadramento (`code|size|corpo`, 2 perfis) | `TESTADO` + `OPERACIONAL` | `unit` 106 · `golden` 42 · `conform` 15 · `fuzz` 12 |
| serviço de rede de ensaio `mud2` | `TESTADO` + `OPERACIONAL` | `net` 34 · `seguranca` 13 · `bench` 15 · `net-matrix` 36 |
| CLIs (`mu2ctl`, `mu2codec`) | `TESTADO` | `net`, `conform`, `golden` |
| fuzzer determinístico (sem feedback de bordas) | `PARCIAL` (declarado) | `fuzz` 12 — 150 000 iterações, 0 violações |
| console administrativo local (backend) | `TESTADO` (UI e escrita `NOT_IMPLEMENTED` por decisão) | `admin` 24 |
| portão único + teste do portão | `TESTADO` | 23 etapas; `gate-selftest` 19/19 |
| backup restaurável (bundle → clone) | `TESTADO` + `OPERACIONAL` | `verify-backup.sh` 11/11 e 15/15 (`FULL=1`) |
| sondas de auditoria do pacote (PE, dados, config, Lua, cifragem, interop) | `TESTADO` | `pe` 14 · `data` 21 · `cfg` 15 · `lua` 13 · `lua-enc` 27 · `interop` 12 |
| **login, sessões de jogador, personagens** | **`AUSENTE`** | não há código; o serviço não autentica (declarado em `mud2.c:15`) |
| **mundo, mapas, movimento, combate, monstros** | **`AUSENTE`** | idem |
| **inventário, itens, drops, comércio, economia** | **`AUSENTE`** | idem |
| **guildas, grupos, eventos** | **`AUSENTE`** | idem |
| **banco de dados / persistência** | **`AUSENTE`** | `docs/DATABASE.md` |
| protocolo do cliente original / interop real | **`BLOCKED`** (causa nomeada) | `docs/PROTOCOLS.md` §4 |
| compatibilidade com o cliente original | **`NÃO VERIFICADO`** (cliente não existe no pacote) | `reports/r6-interop-relatorio.md` §2.3 |
| formatos `.ozt`, layout `.bmd`, semântica `.att`, cifragem dos `.lua` | `PARCIAL`/`BLOCKED` | `docs/PROTOCOLS.md` §5 |
| verificação de sintaxe/execução Lua | `BLOCKED` (sem interpretador no host) | `tests/lua.sh` |

Inventário completo, linha a linha, com o teste que cobre cada item: `recriado/docs/PROJECT_STATUS.md`.

## 6. Resultado real da compilação e dos testes executados

Tudo abaixo foi **executado neste ambiente, hoje** (números medidos, incluindo os ruins):

| execução | resultado |
|---|---|
| `make -s build` | exit 0 — 8 artefatos em `out/` (com `-Werror` + ASan/UBSan) |
| `make -s check` | **182 asserções, 0 falhas**, exit 0 (unit 106 · make-sintaxe 7 · net 34 · pe 14 · data 21) |
| `make -s gate-selftest` | **19/19**, exit 0 |
| `make -s gate` (23 etapas, após o commit) | **18 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções contadas, exit 0** (69 302 ms) |
| `FULL=1 make -s gate` (1ª passada, antes do commit) | **19 PASS, 1 FAIL, 3 BLOCKED, 375 asserções, exit 1** — o `FAIL` é a etapa `persistencia` exigindo árvore limpa com a rodada em curso (a checagem funcionando; §7) |
| `GATE_FULL=1 GATE_SKIP=net-matrix make -s gate` | `net-matrix` fora por decisão; `persistencia` **PASS** (`ok=11 falhas=0`) |
| `net-matrix` (opt-in, medida separada) | **36/36 PASS** — 100 configurações × 5 repetições por perfil, 619 s |
| `FULL=1 bash scripts/verify-backup.sh` | **ok=15 falhas=0** |
| `lua-enc` (etapa nova) | **27/27, `blocked=2`** |
| `MuserverRecriado/` (cópia publicada) | `verify-backup.sh` **ok=11 falhas=0** |

Leitura correta da mesa: `interop` (camada 3), `lua` (execução) e `lua-enc` (algoritmo + `F23`) são
**`BLOCKED`** com causa; `net-matrix` e `persistencia` são opt-in (`SKIPPED` no portão padrão,
**nunca** contadas como aprovadas nessa condição). Detalhamento e o que **não** foi testado:
`recriado/docs/TESTING.md`.

## 7. Erros e riscos conhecidos

1. **Credenciais em claro versionadas** (token de bot Discord, senha do JoinServer, serial/HWID,
   `EncDecKey1/2`) — o histórico **já publicou** os valores; mitigação real = **rotacionar**
   (`docs/SECURITY.md` §1). **Severidade alta; ação do proprietário.**
2. **4 backups de banco com PII de jogadores** publicados (`DB/*.bak`, 50 373 632 B) — incidente de
   privacidade; nada foi restaurado nem copiado para relatório (`docs/SECURITY.md` §5, `DATABASE.md` §2.2).
3. **2 555 arquivos de log + 34 dumps de crash** rastreados (podem conter memória/IPs/contas).
4. **Ausência de licença** no trabalho próprio e origem/licença não verificadas de DLLs e ferramentas
   de terceiros (`docs/DEPENDENCIES_AND_LICENSES.md` §5).
5. **`GATE_FULL=1`: `net-matrix` regrava dois TSVs de evidência antes de `persistencia`** (que exige
   árvore limpa) ⇒ `FAIL` determinístico na mesma passada. As duas etapas estão verdes quando medidas
   (36/36 e 11/11); o contorno é `GATE_FULL=1 GATE_SKIP=net-matrix`. Melhoria pendente registrada em
   `AUDIT_HANDOFF.md` §5 — **não aplicada** aqui para não alterar contrato testado nesta consolidação.
6. **Divergência de porta** do cliente (44405) × ConnectServer (44406): aberta; sem captura de tráfego
   não se resolve (hoje `BLOCKED`).
7. Nenhum binário do pacote foi executado; **nada** foi neutralizado (Themida/VMProtect) nem apagado.

## 8. Funcionalidades ainda ausentes ou não verificadas

Toda a lógica de jogo (login, sessão de jogador, personagem, mundo, movimento, combate, monstros,
itens, drops, comércio, guildas, eventos), persistência/banco, protocolo do cliente original,
criptografia de rede, sintaxe/execução dos 148 scripts Lua, estruturas dos formatos `.ozt`/`.bmd`/
`.att`, algoritmo da cifragem dos `.lua` do cliente, e qualquer medição de escala/produção
(2 vCPUs, loopback). Compatibilidade com o cliente original: **não verificada, não afirmada**.

## 9. Relação das dependências e questões de licenciamento pendentes

| pendência | quem resolve |
|---|---|
| adicionar `LICENSE` ao trabalho próprio | proprietário |
| verificar autorização de redistribuição do pacote original (hoje público no GitHub) | proprietário |
| confirmar licenças de DLLs (MySQL, OpenSSL, libsodium, opus, zlib, dpp) e das ferramentas (MuEditor, editores, PSGuard) | proprietário |
| conferir se `.premium`/`License.ps` embutem termos de terceiros | proprietário |
| SQL Server (comercial) + ODBC — exigência do original, não do v2 | proprietário (operacional) |

## 10. Documentos de auditoria criados ou atualizados

**Criados (9, em `recriado/docs/`):** `PROJECT_STATUS.md`, `ARCHITECTURE.md`, `BUILD_AND_RUN.md`,
`DATABASE.md`, `PROTOCOLS.md`, `TESTING.md`, `DEPENDENCIES_AND_LICENSES.md`, `SECURITY.md`,
`AUDIT_HANDOFF.md`.
**Atualizados:** `recriado/README.md` (entrada por perfil, estado medido, onde está publicado, layout
real), `recriado/docs/ROADMAP.md` (seção nova: etapas restantes em ordem de dependência),
`recriado/reports/auditoria-rastreabilidade.md` (bloco de atualização de 2026-10-13 preservando o
retrato de 2026-10-12; linha da cifragem corrigida de `NOT_IMPLEMENTED` para `BLOCKED`),
`recriado/Makefile` (+ alvo `lua-enc`, mesmo padrão de `lua`), `recriado/docs/TESTING.md` e
`AUDIT_HANDOFF.md` (números finais), `recriado/reports/net-{orig,mur0}.tsv` (evidência da matriz de
hoje) e `workspace/backups/{mu2-v2.bundle,MANIFEST.md}` (marco).

## 11. Arquivos ou componentes que não puderam ser incluídos (e o motivo)

| item | motivo |
|---|---|
| `recriado/out/**` (build e saídas de teste) | artefato regenerável; ignorado por decisão (D2-13/D2-08) — não é perdido: `make -s build` reconstrói |
| `MuServer/**/LOG/` (2 555), `*.dmp` (34) — **na verdade já estão versionados** desde o upload | o `.gitignore` não remove o que já está no índice (armadilha registrada nele próprio); retirar exige `untrack_artifacts.sh` + decisão do proprietário, e **não** foi feito nesta consolidação para não apagar histórico/evidência |
| `MuServer/DB/*.bak` (4 backups, 50 MB de PII) | **já versionados** no upload; não foram removidos nem processados (decisão de segurança/jurídica do proprietário; §7.2) |
| `/tmp/*` (logs de investigação de rodadas) | efêmeros por natureza do sandbox; os artefatos que importam foram versionados em `reports/` |
| segredos reais | **nunca** incluídos em documento novo: `SECURITY.md` cita arquivo e comprimento, não valores |
| repositório separado `heldergaraujo2/MuserverRecriado` | `403` (instalação do GitHub App) — não contornado; a cópia vive em `MuserverRecriado/` dentro do monorepo |

## 12. Instruções para obter o projeto e reproduzir a compilação e os testes

```sh
git clone https://github.com/heldergaraujo2/Muserver.git
cd Muserver
git checkout arena/cf1de8ce-muserver     # ou: git checkout auditoria-2026-10-13

# --- o produto v2 (não precisa da referência para compilar) ---
cd recriado
make -s build && make -s check && make -s gate-selftest && make -s gate
FULL=1 bash scripts/verify-backup.sh                 # backup restaurável + estado publicado
GATE_FULL=1 GATE_SKIP=net-matrix make -s gate         # inclui a etapa opt-in de persistência

# --- etapas que dependem da referência (MuServer/) ---
make -s pe data cfg ref-intacta interop lua lua-enc
# ou, se a referência estiver em outro lugar: make MU_REF_DATA=/caminho -s data

# --- sondas somente leitura (evidência) ---
python3 tools/enc_probe.py | python3 tools/cfg_probe.py | python3 tools/interop_probe.py
```

Pré-requisitos e o que cada ausência provoca (`BLOCKED`, nunca `PASS`): `recriado/docs/BUILD_AND_RUN.md`.
O que **não** roda neste ambiente (Lua, `wine`, `clang`/`valgrind`, SQL Server): `TESTING.md` §5.

## 13. Confirmação de que o conteúdo foi enviado e verificado no repositório remoto

**Publicado e conferido por leitura de volta (não por presunção).**

| item | valor lido do remoto |
|---|---|
| branch `arena/cf1de8ce-muserver` | **`2d121d9cc39d0eb167c062904506e494d007304f`** (`git ls-remote`) — igual ao HEAD local no momento da leitura |
| tag `auditoria-2026-10-13` (anotada) | objeto `cb880d78c8aaaafba91ac34562b6b7da921fb629` → commit **`2d121d9`** (`refs/tags/…^{}`) |
| branch `main` | `6eabb45b9e7939a3061f4757ed6791efef7c5c3b` — **inalterada** (nada desta consolidação foi para `main`) |
| API do GitHub | `commits/arena/cf1de8ce-muserver` = `2d121d9…`; `git/ref/tags/auditoria-2026-10-13` = tipo `tag`, objeto `cb880d78…` |
| blobs conferidos um a um (remoto == local) | os **9 documentos de auditoria** + `recriado/README.md` + este relatório (`CONTEUDO/…` retornou o mesmo SHA que `git rev-parse HEAD:<caminho>`) |
| commits desta rodada | `578e7e1` (documentos) · `b465111` (backup do marco) · `2d121d9` (números finais + relatório) |
| commits publicados | `git push` → `0f13c66..578e7e1` e `578e7e1..2d121d9` (branch) e a tag; **sem `--force`, sem apagar histórico, nenhuma outra branch** |

**Verificadores depois da publicação** (executados neste estado):

| comando | resultado |
|---|---|
| `bash recriado/scripts/verify-backup.sh` | **ok=11 falhas=0 blocked=0** |
| `FULL=1 bash recriado/scripts/verify-backup.sh` | **ok=15 falhas=0 blocked=0** — inclui `publicado: bundle byte a byte`, `bundle verify no clone`, `restaurar arvore a partir do bundle clonado` e **`HEAD local esta no remoto OK 2d121d9`** |
| `GATE_FULL=1 GATE_ONLY=persistencia make -s gate` | etapa `persistencia` **PASS** (exit 0) |
| `bash MuserverRecriado/scripts/verify-backup.sh` | **ok=11 falhas=0 blocked=0** (cópia publicada consistente) |
| `git diff --quiet HEAD -- MuServer` | vazio — referência intacta (tree `fade046…`) |
| `git status --porcelain` | vazio no fecho (nada escrito sem comitar) |

Este parágrafo entra no commit seguinte à leitura (como no fecho da rodada anterior): o SHA final da
rodada é o que `git ls-remote` devolver depois deste commit, e está reproduzido na resposta ao
proprietário com a tag `auditoria-2026-10-13` (que fixa o conteúdo auditado).

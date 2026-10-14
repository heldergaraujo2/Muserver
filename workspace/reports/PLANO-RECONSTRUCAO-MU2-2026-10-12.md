# Plano de reconstrução incremental do serviço `mu2` (v2) — 2026-10-12

**Enquadramento honesta, antes de tudo.** Isto não é recuperação: é reimplementação com histórico
novo. Nada dos 20 commits perdidos volta; nada do que ele media pode ser citado como
*resultado reproduzido*. Números antigos viram **alvos**, e cada um precisa ser remedido antes de
aparecer em qualquer documento. As suítes que o projeto perdido executou **não** foram executadas
aqui — nem este plano as executa por antecipação.

Disparador: executar **somente** se a solicitação de recuperação (`ARENA-RECOVERY-REQUEST-2026-10-12.md`)
receber resposta negativa. Enquanto houver chance de restauração do volume, este plano fica parado:
reimplementar sobre a possibilidade de recuperar é o caminho para ficar com duas metades de projeto.

## R-0. Persistência antes de código (a causa-raiz, e a única parte que não é opcional)

O projeto morreu porque viveu num clone **fora** da árvore rastreada (`/home/user/MuserverRecriado`)
e o `push` estava sem autorização. Então a primeira entrega é estrutural, não de código:

- **Opção A (recomendada enquanto o 403 existir):** desenvolver dentro do repositório rastreado,
  em `recriado/` do `heldergaraujo2/Muserver`, na branch da sessão. Aí a persistência da plataforma
  cobre tudo por construção, e o `git diff` da árvore é o próprio depósito.
- **Opção B (definitiva):** o dono inclui `MuserverRecriado` na seleção de repositórios do App
  GitHub (Contents: Read and write) e reemite o token; então `recriado/` vira um repositório próprio
  com `origin` funcional. Nesse caso, a *primeira* rodada de código termina com push +
  `git ls-remote` conferido, **antes** de qualquer suíte nascer.
- Invariante de toda rodada: `git add <caminhos explícitos>` (nunca `git add -A`: o `.gitignore` do
  repo principal documenta a armadilha real de `git rm -r --cached` + `git add -A` produzir 2 376
  deleções silenciosas), commit, push, e `ls-remote --heads` lido de volta. Rodada sem `ls-remote`
  confirmado não conta como entregue.
- Fim de rodada também grava um bundle **dentro da árvore**: `recriado/backup/mu2.bundle`
  (`git bundle create` + `git bundle verify`). Bundle em `/home/user/` é o que já perdemos uma vez.
- Armadilhas de ignorar, conferidas agora no `.gitignore` do repo principal — elas mordem de novo se
  o v2 escrever nelas: `workspace/recovered/`, `workspace/reports/*.json|*.txt|*.err` são
  **ignorados** (arquivo de resultado ali não é persistido; use `.tsv`/`.md` dentro de
  `recriado/reports/`), e `*.obj`, `MuServer/**/obj/`, `MuServer/**/bin/`, `MuServer/**/*.tmp`,
  `MuServer/**/*.bak` também. Nada em `recriado/**` é ignorado hoje (verificado com
  `git check-ignore -v`, que respondeu vazio para `recriado/backup/mu2.bundle`,
  `recriado/build/mud2`, `recriado/reports/bench.tsv`, `recriado/src/mud2.c`, `recriado/tests/net.sh`).

Layout-alvo (o mesmo do perdido, porque ele era bom):

```
recriado/{Makefile,scripts/run_all.sh}
  include/mu2/mu2.h            src/{wire.c,mud2.c,mu2ctl.c}      bench/bench.c
  tests/{unit.c,e2e.sh,golden.sh,interop.sh,conform.c,fuzz.c,net.sh,make_parse.sh,gate_state.sh}
  tools/{pe_probe.py,att_probe.py,mb_probe.py,data_probe.py}
  docs/{AGENTS,CURRENT_STATE,NEXT_TASK,DECISIONS,PERFORMANCE,TEST_STRATEGY,TEST_RESULTS,DATAFORMATS,PROTOCOL,CHANGELOG,README}.md
  reports/   backup/mu2.bundle
```

## R-1. Congelar a especificação a partir do que **sobreviveu em arquivo**

Nem tudo do v1 se perdeu: o contrato está descrito (em prosa) nos relatórios que ficaram. Antes de
escrever C, extrair daí uma tabela `fato → onde está hoje → o que fazer`, e marcar o que é
*descrição* e precisa ser re-derivado dos dados:

| item do contrato | estado atual | ação no v2 |
|---|---|---|
| `MU2_MAX_BODY = 2048`, dois perfis de quadro (`mur0`, `orig`), fila de resposta de 1 vaga com fechamento explícito (D-09), `--sndbuf` com mínimo 1024, laço `poll()`, `feed()` consome **todos** os quadros do buffer lido (premissa contrária foi corrigida no v1) | descritos em `workspace/reports/WORKTREE-PERDIDO-2026-10-12.md` | reescrever como spec explícita em `recriado/docs/DECISIONS.md` **numerando de novo** (D2-01…) e rotulando cada um como "reafirmado, não herdado" |
| linha de `stats`: `STATS registros= usados= conns= frames= rejects= uptime_ms= slotsz= maxbody=` | idem | mesma forma, novo código; manter o `show_stats` do controlador |
| contadores de piso das suítes (unit=82, e2e=23, fuzz=4, conform=18, interop=9, golden=3, bench=12, pe=10, data-selftest=33, data=26, gate-selftest=4, pe-selftest=7, make-sintaxe=5, net=22) | idem | viram **alvo mínimo declarado**, não obrigação numérica: o v2 publica o que medir, e o piso do `run_all.sh` só é fixado depois da primeira passada verde |
| medidas de rede do v1 (round-trip med ≈ 107,4 µs `mur0` / 99,6 µs `orig`; CPU 49,9 vs 24,9 µs/quadro em rajada de 401; cliente lento 400/400 com `rcvbuf` efetivo 2304) | idem | **não transportar**. Re-medir no host atual; se divergir, o v2 reporta o seu número e o antigo fica citado como histórico do v1 |
| fatos de dados (92 `.att` de 65 539 B com `slack=0`, entropia ≤ 1,858 B/B, 81 sha256 em 10 grupos idênticos; `MonsterSetBase` 99 arquivos / 6 351 registros / 404 grupos / EOF perderia 4 525 = 71 %; `MuEditor.exe` = .NET com import único `mscoree.dll`; matriz de 71 binários: 58 nativos, 2 .NET, 11 protegidos) | os **números estruturais** (contagens, tamanho, sha do `ConnectServer.exe`) foram conferidos hoje contra `MuServer/` e batem; os analíticos (entropia, grupos, percentuais) só existem em prosa | recalcular tudo com as sondas do v2 a partir de `MuServer/` — o pacote é bit a bit o mesmo, então qualquer divergência é defeito da sonda nova, e isso é um teste de qualidade útil de graça |

Regra da fase: nada entra no código com valor "do v1". Valor sem fonte executável é hipótese, e
hipótese vira asserção só depois de medida.

## R-2. Bring-up do ambiente — com o que este host tem (verificado, não assumido)

| necessidade | disponível | consequência para o v2 |
|---|---|---|
| compilação | `gcc`/`cc` 12.2, `make`, `nm`/`objdump`/`readelf`/`strip` | `-g -O2 -Wall -Wextra -Werror` compila ✓ (testado) |
| sanitizadores | `-fsanitize=address,undefined` ✓ (libasan.so.8 presente); `-fsanitize=fuzzer` **AUSENTE** (sem clang) | suíte `fuzz` com **harness próprio determinístico** + corpus versionado em `recriado/tests/corpus/`, em vez de libFuzzer |
| `valgrind`, `gdb`, `strace`, `ltrace`, `perf`, `tcpdump`, `nc`(✓), `socat`(✓) | ausentes, exceto `ss`/`nc`/`socat` | nada de memcheck/perf; memória por ASAN; rede por sockets programados em Python (como a sonda desta sessão fez) |
| cobertura | `gcov` ✓ (`gcovr` ausente) | meta de cobertura reportada por `gcov` cru, sem dependência nova |
| dados/PE | `python3` 3.11.2, `pip` 23.0.1, módulo `venv` ✓, `patch`/`diff`/`tar` ✓, `file` **ausente** | `pe_probe` precisa ser autossuficiente (sem `file`); instalar `lupa`/`luaparser`/`capstone` num venv **só** para as suítes que usam Lua, e sempre com o `python3 -m venv` + aviso explícito sobre interpreter errado (lição da linha Lua) |
| máquina | 2 vCPUs, 4 GiB, kernel 6.1.158, sem `cpu.max` em cgroup | **`bench` precisa de limiar de drift recalculado para 2 vCPUs**, e `BLOCKED` é resultado legítimo aqui (o host é ruidoso por construção); bloqueado nunca conta como aprovado |
| rede | só `lo`/`eth0`; saída permitida para github.com/api.github.com/codeload/npmjs/pypi/files.pythonhosted | experimentos de rede têm de ser **loopback** (foi assim que a sonda de janela TCP funcionou) e não há como baixar ferramenta nova de outro lugar |

## R-3 a R-8. Fases, cada uma com portão e evidência

Cada fase termina com: build limpo sob `-Werror`, a(s) suíte(s) nomeada(s) executada(s), **uma
falsificação por asserção nova** (mudar o produto para provar que o teste pega; restaurar e conferir
`git diff` vazio em `src/`), commit empurrado, e nenhuma fase começando com portão vermelho da anterior.

| fase | produto | portão de saída |
|---|---|---|
| R-3 `wire` | `mu2.h` + `src/wire.c` + `tests/unit.c` (enquadramento/decodificação dos dois perfis) e `tests/make_parse.sh` | `make -s build` + unit verde; `make-sintaxe` 5/5 no alvo novo; falsificação: inverter ordem de campo no encoder e ver a asserção cair |
| R-4 serviço | `src/mud2.c`: `accept`/`poll`/`feed`/`queue_reply`/`drain`, `--sndbuf`, `--max-clients`, `LOGW` de fila ocupada | `tests/e2e.sh` + `tests/net.sh`; **aqui entra a N-T5.3d2 pendente**, com a receita medida: `--sndbuf 1024` no serviço **e** `SO_RCVBUF=1024` no cliente **antes do `connect()`** (efetivos 4608/2304 lidos por `getsockopt`, porque o kernel clampa), ≥30 requisições encadeadas sem leitura, classificação de cada desconexão pela linha do log (fila cheia ≠ TCP bloqueado ≠ timeout ≠ erro de socket). Falsificação dupla: `break` no `feed()` (um quadro por `recv`) e remoção do `drain()` imediato — ambos têm de mudar o resultado |
| R-5 controlador e dados | `src/mu2ctl.c` (com `show_stats`), `tools/pe_probe.py`, `att_probe.py`, `mb_probe.py`, `data_probe.py` | `conform`/`data`/`data-selftest`/`pe`/`pe-selftest` com `MU_REF_DATA=/home/user/Muserver/MuServer`; os fatos de dados da tabela R-1 saem daqui, remedidos |
| R-6 interoperabilidade | `tests/interop.sh` (contra `ConnectServer.exe` real onde for possível) e `tests/golden.sh` | `interop` + `golden` verdes, com dourados regenerados do pacote conferido e **nada** copiado do v1 |
| R-7 `bench` | `bench/bench.c` com os três critérios de validade (inclusive o de drift entre passadas) | `bench` **vermelho é aceitável se for recusa por ambiente**; o documento reporta `BLOCKED` e a condição que causou, nunca "melhorou" |
| R-8 portão único | `scripts/run_all.sh` + `tests/gate_state.sh` (TAP + `.tsv`), com autos-teste do próprio portão | `gate-selftest` verde primeiro (portão que não sabe falhar não é portão), depois a corrida completa; pisos fixados a partir desta medida e de nenhuma outra |

## R-9. Documentação e publicação

`docs/CURRENT_STATE.md`, `NEXT_TASK.md`, `DECISIONS.md` (numeradas D2-xx), `PERFORMANCE.md`,
`TEST_RESULTS.md` reescritos **do v2**, com uma linha explícita no topo: "história reiniciada em
2026-10-12; os números do v1 não são comparáveis e não foram reproduzidos". Publicação: com a opção
B autorizada, `push` + `ls-remote` conferido; sem autorização, o `recriado/` no repo rastreado já é
o depósito, e isso é dito ao dono em vez de contornado.

## Fora de escopo deste plano

`git reset --hard`, `git clean -fd`, `push --force`, mexer em `MuServer/` (pacote de referência
conferido e intocado), alterar os arquivos da linha Lua, inflar `MU2_MAX_BODY`/buffers para o teste
passar, tocar na política da fila de 1 vaga sem perda demonstrada, e apresentar qualquer número do v1
como se o v2 o tivesse reproduzido.

## Riscos principais e mitigação

1. **Perder o v2 do mesmo jeito** → R-0 é a primeira fase, e o invariante `push + ls-remote` por
   rodada é verificação, não boa intenção.
2. **Contaminação de número** (citar alvo como resultado) → toda tabela nos docs nasce de um `.tsv`
   gerado na mesma rodada, com o comando de geração anotado; revisão final compara texto × `tsv`.
3. **Fixture drift** (a sonda nova divergir do pacote) → tratar divergência como defeito da sonda,
   não do pacote; o `MuServer/` está conferido bit a bit pelos pins da R-1.
4. **Ambiente de 2 vCPUs** para medidas de CPU → CPU medido por rajada (tick de 10 ms), `clock_gettime`
   monotônico, mediana + MAD e amplitude por passada; recusa declarada vale mais que número bonito.
5. **Recomeçar a discussão de contrato sem evidência** → a N-T5.3d2 já tem sua receita medida
   (esta sessão) e está dentro da R-4; se ela não mostrar perda, a política do v1 é reafirmada como
   decisão nova (D2-xx) com os limites do experimento escritos junto.

Estimativa por rodada de agente: R-0 1, R-1 1, R-2 1, R-3 2, R-4 3, R-5 3, R-6 2, R-7 1, R-8 1,
R-9 1 ≈ **16 rodadas**, e nenhuma delas começa sem a anterior com portão publicado.

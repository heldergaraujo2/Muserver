# Auditoria de rastreabilidade do roadmap inteiro

Data: 2026-10-12. Estado de partida medido nesta rodada, não relatado: `make -s gate` →
**18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 336 asserções, 22 etapas, exit 0**;
`gate-selftest` 19/19; `make -s check` 180 asserções; `FULL=1 scripts/verify-backup.sh` 13/13;
HEAD = remoto = `2ca5a04`; `MuServer/` inalterada desde `b5b84da` (ver §5).

## Atualização de 2026-10-13 (consolidação para auditoria) — o que mudou desde a redação acima

O texto desta auditoria é um retrato datado de **2026-10-12** e foi preservado como está. O que
mudou depois dele, medido hoje:

| item | em 2026-10-12 (acima) | medido em 2026-10-13 |
|---|---|---|
| `gate` | 18 PASS / 0 FAIL / **2 BLOCKED** / 22 etapas / 336–339 asserções | 18 PASS / 0 FAIL / **3 BLOCKED** / **23 etapas** (339 contadas; 391 somadas) |
| etapa nova | — | **`lua-enc`** (`enc`): 27/27, `blocked=2` |
| meta C "formato de cifragem do script de cliente" | `NOT_IMPLEMENTED` | **`BLOCKED`** — estrutura medida, algoritmo não identificado, `F23` bloqueada (`reports/enc-cifragem-lua.md`) |
| `check` | 180 asserções | **182** |
| etapas verdes | interop/lua `blocked=1` | idem + `lua-enc blocked=2` |
| backup/verificação | `FULL=1` 13/13 | **11/11** (padrão) e **15/15** (`FULL=1`, agora confere o remoto) |
| repositório | monorepo `heldergaraujo2/Muserver` | idem; a árvore do produto passou a ser também publicada em `MuserverRecriado/` (174 arquivos) |

Estados usados, sem hierarquia implícita: `PASS`, `FAIL`, `BLOCKED`, `NOT_IMPLEMENTED`,
`IN_PROGRESS`, `SKIPPED`. **Nada é marcado como concluído porque o código existe.** Cada linha diz
onde está a evidência; todo bloqueio diz causa, dependência e condição de desbloqueio.

---

## 1. Fases

| Fase | Produto | Estado | Evidência reproduzível | Observação |
|---|---|---|---|---|
| R-0 | ambiente e toolchain | `PASS` | `docs/ENVIRONMENT.md`; `make -s dump-CC dump-CFLAGS` | — |
| R-1 | inventário da referência | `PASS` | contagens do pacote; `tests/pe.sh` 14/14; `tests/data.sh` 21/21 | — |
| R-2 | baseline e ritual de persistência | `PASS` | `scripts/verify-backup.sh` 9/9; `FULL=1` 13/13 | bundle + `MANIFEST.md` |
| R-3 | codec de enquadramento | `PASS` | `unit` 106/0; `make-sintaxe` 7/7; `tests/golden.sh` 42/42 | 38 vetores versionados |
| R-4 | serviço `mud2` + `mu2ctl` | `PASS` | `tests/net.sh` 34/34; `tests/conform.sh` 15/15 | ABI preservado |
| R-5 | inspeção do pacote original | `PASS` | `tests/pe.sh`, `tests/data.sh`, `tests/cfg.sh`; `reports/r5-*.tsv` | 4 falsificações F8–F11 |
| R-6 | interoperabilidade | `IN_PROGRESS` — camadas 1 e 2 `PASS`, camada 3 `BLOCKED` | `tests/interop.sh` 12/12 `blocked=1`; `reports/r6-interop-relatorio.md` | ver §3.A |
| R-7 | desempenho | `PASS` (linha de base exploratória) | `tests/bench.sh` 15/15; `reports/r7-*.tsv` | capacidade absoluta `BLOCKED` (2 vCPUs + ASan) |
| R-8 | portão único | `PASS` | `tests/run_all.sh` 22 etapas; `tests/gate_state.sh` 19/19 | F12–F14 |
| R-9 | documentação e publicação | `IN_PROGRESS` (contínuo por definição) | `docs/CONTINUITY.md`; `git ls-remote` | — |

## 2. Meta A — reconstrução e compatibilidade com o cliente original

| Requisito | Implementação | Teste | Evidência | Documentação | Estado |
|---|---|---|---|---|---|
| codec dos dois perfis | `src/wire.c` | `unit`, `golden` | 106 + 42 asserções | `docs/DECISIONS.md` D2-11/12 | `PASS` |
| serviço de ensaio com contrato de rede | `src/mud2.c` | `net`, `conform` | 34 + 15 asserções | `proto.h` | `PASS` |
| referência de bytes versionada | `tests/golden/quadros.tsv` | `golden` 42/42 | 38 vetores com cláusula e origem | cabeçalho do corpus | `PASS` |
| interoperabilidade com o binário original | — (nenhuma) | `interop` | 12/12, `blocked=1` | `reports/r6-interop-relatorio.md` | `BLOCKED` |
| compatibilidade com o cliente original | — (nenhuma) | — | 0 clientes no pacote (só `main.exe` do gerador) | `rf-lua-protocolo.md` §4 | `BLOCKED` |

**Bloqueio A.1 — interop real.** Causa: nenhum dos `wine`/`wine64`/`wine32`/`qemu-i386`/`box86`/
`box64` existe no host; os binários são PE32/i386 com seções `.themida`; a autorização
(`MU_INTEROP_ALLOW_ORIGINAL=1`) não está dada. Dependência: ambiente capaz de executar PE32/i386 +
autorização do proprietário + procedimento escrito. Desbloqueio: executar o procedimento
supervisionado e depositar `reports/r6-interop-real.tsv` (8 chaves), que `tests/interop.sh` valida —
a suíte não tem caminho de execução de binário original.

**Bloqueio A.2 — cliente.** Causa: o pacote **não contém cliente de jogo**; `main.exe` aparece uma
única vez, como saída do *Gerador de Main*, e não foi executado. Não há como validar compatibilidade
com o cliente a partir deste pacote, mesmo com Wine. Desbloqueio: obter o cliente original e a
autorização de executá-lo.

## 3. Meta B — rede, protocolo e limites

| Requisito | Implementação | Teste | Evidência | Estado |
|---|---|---|---|---|
| framing (cabeçalho, tamanhos, LE) | `src/wire.c` | `conform` | 15/15, C-01…C-15 byte a byte | `PASS` |
| leitura incremental / cabeçalho partido | `feed()` em `mud2.c` | `net` S1/S2/S3 | 34/34 | `PASS` |
| escrita parcial / `POLLOUT` retoma pendência | `drain()` | `net` S3/S3b | 34/34 | `PASS` |
| backpressure e fila de 1 vaga | `queue_reply` | `net` S4, `bench` B5 | `close=queue_full`, 551 quadros de 2048 B | `PASS` |
| limites: `max_clients`, idle, quadro máximo | `mud2.c`, `wire.h` | `net` S8/S9/S10/S11 | 34/34 | `PASS` |
| entrada malformada na porta | — | `seguranca` 15 casos | serviço vivo nos 15; `close=bad_frame` = 11 | `PASS` |
| fuzzing de cabeçalho/tamanho/truncado/opcode/aleatório | `tools/mu2fuzz.c` (determinístico) | `fuzz` 12/12 | 150 000 iterações, 0 violações; F22 | `PASS` (motor próprio) |
| limite de pacote do **original** | — | — | — | `BLOCKED` |
| limite de pacote acima de 2048 no v2 | — | — | contrato fixo em D2-03 | `NOT_IMPLEMENTED` |

**Bloqueio B.1 — limite de pacote do original.** Causa: exigiria medir o binário em execução
(captura ou serviço real). Dependência: mesma do bloqueio A.1. Desbloqueio: com o serviço original
rodando, medir o maior quadro aceito.

**Nota B.2:** o limite de 2048 é decisão do v2 (D2-03), **não** requisito de produção. Não há
evidência de que o original aceite mais, e não há alegação disso em lugar nenhum.

## 4. Meta C — Lua e scripts

| Requisito | Implementação | Teste | Evidência | Estado |
|---|---|---|---|---|
| inventário e evidência estática | `tools/lua_probe.py` | `lua` 13/13 | 148 `.lua`; 20 com termos de pacote; 8 `ProtocolCore.lua` | `PASS` |
| assinatura do ponto de entrada de pacote | — (evidência) | `lua` casos 7–8 | `GameServerProtocolRecv(aIndex, Packet, PacketName)` | `PASS` |
| verificação de sintaxe dos scripts | — | — | nenhum interpretador Lua no host | `BLOCKED` |
| cifragem do script de cliente | `tools/enc_probe.py` (somente leitura) | `lua-enc` 27/27, `blocked=2` | cabeçalho fixo de 8 B, sem padding, determinística, janela de 3 bytes fecha em 0/2 510; **algoritmo não identificado** | `BLOCKED` (ver `enc-cifragem-lua.md`); `F23` `BLOCKED` |
| correção da afirmação "0 declarações de framing" | — | `lua` caso 2 | `reports/rf-lua-protocolo.md` | `PASS` (corrigida) |

**Bloqueio C.1 — sintaxe.** Causa: `lua`, `lua5.1`, `lua5.3`, `lua5.4`, `luajit` ausentes e não
instaláveis sem rede aprovada. Desbloqueio: interpretador Lua disponível; então `luac -p` em 148
arquivos e execução de casos controlados.

## 5. Meta D — recursos 3D e arquivos pesados

| Requisito | Implementação | Teste | Evidência | Estado |
|---|---|---|---|---|
| classificação dos formatos encontrados | `tools/{att,mb,data}_probe.py` | `data` 21/21 | `reports/rc-formatos-auditoria.md` | `PASS` |
| camada XOR-3 dos `.bmd` | — (decodificação) | `data` casos 20–21 | `Data\Item\` no offset 12; 4 de 56 `.bmd` | `PASS` |
| layout de registros dos `.bmd` | — | — | nenhum campo determinado | `NOT_IMPLEMENTED` |
| estrutura interna dos `.ozt` (textura) | — | — | só dois prefixos medidos | `NOT_IMPLEMENTED` |
| validação no cliente real | — | — | não há cliente (bloqueio A.2) | `BLOCKED` |

## 6. Meta E — desempenho

| Requisito | Implementação | Teste | Evidência | Estado |
|---|---|---|---|---|
| critérios de validade declarados **antes** | `tests/bench.sh` | `bench` 15/15 | `reports/r7-relatorio.md` | `PASS` |
| linha de base exploratória | `tools/{rtt,bench}_check` | `bench` | 215 k quadros/s (B1); p50 39,5 µs (B3) | `PASS` |
| capacidade absoluta do host | — | — | 2 vCPUs + ASan, host compartilhado | `BLOCKED` |
| metas de produção | — | — | não há requisito do proprietário | `NOT_IMPLEMENTED` (por decisão) |
| FPS / fluidez | — | — | exige cliente | `BLOCKED` |

## 7. Meta F — painel administrativo

| Requisito | Implementação | Teste | Evidência | Estado |
|---|---|---|---|---|
| desenho antes do código | `docs/ADMIN_CONSOLE.md` | — | arquitetura, auth, permissões, API, estados, validações, erros | `PASS` |
| backend real com autenticação | `tools/mu2admin.c` | `admin` 22/22 | token 0600, fail closed, tempo constante | `PASS` |
| permissões (leitor/admin) | idem | `admin` casos 13–14 | 403 / 501 medidos | `PASS` |
| escrita no serviço (reiniciar, derrubar conexão) | — | — | exigiria opcode novo; invalidaria conformidade | `NOT_IMPLEMENTED` (por decisão) |
| interface gráfica | — | — | seria botão sem função | `NOT_IMPLEMENTED` (por decisão) |

## 8. Meta G — assistente de publicação

| Requisito | Implementação | Teste | Evidência | Estado |
|---|---|---|---|---|
| rota de publicação | `mu2admin` `/publicar` | `admin` caso 14 | `501 nao_implementado` com motivo | `NOT_IMPLEMENTED` (por decisão) |
| publicação real | — | — | falta alvo autorizado, contrato de destino e credencial | `BLOCKED` |
| diagnóstico de portas da referência | `tools/cfg_probe.py` | `cfg` 15/15 | ConnectServer 44406/UDP 55557; 26 valores redigidos | `PASS` |

**Bloqueio G.1.** Causa: não existe alvo de publicação autorizado (o repositório pretendido
`MuserverRecriado` devolve 403 e não é contornado; ver `docs/CONTINUITY.md` §7). Dependência:
decisão do proprietário. Desbloqueio: alvo + contrato + credencial; então a rota deixa de devolver
501 e passa a executar de verdade — com teste que confirme o artefato publicado.

## 9. Meta H — segurança, backup, regressão e continuidade

| Requisito | Implementação | Teste | Evidência | Estado |
|---|---|---|---|---|
| sanitizadores e `-Werror` | `Makefile` | todo o portão | ASan+UBSan, `-fno-sanitize-recover=all` | `PASS` |
| limites de memória no fuzzing | `mu2fuzz --mem-limit-mb` | `fuzz` caso 2 | RLIMIT_AS 64 MB, 0 violações | `PASS` |
| detecção de crash | sanitizadores | `fuzz` caso 4, `seguranca` 3 | exit < 128 exigido | `PASS` |
| higiene de log | `mud2`, `mu2admin` | `seguranca` 9, `admin` 19 | sem token, sem payload, sem caminho absoluto | `PASS` |
| backup restaurável | `scripts/verify-backup.sh` | `FULL=1` | 13/13; bundle 179 992 B sha256 `8a9e9603…` | `PASS` |
| integridade da referência | `tests/ref_check.sh` | `ref-intacta` 8/8 | inclui a divergência registrada (§5) | `PASS` |
| regressão por defeito real | `tests/golden.sh` F20/F21, `tests/net.sh` S4 | `gate` | 3 defeitos corrigidos na R-7 + 1 flakiness | `PASS` |
| continuidade | `docs/CONTINUITY.md` | — | ritual por rodada | `IN_PROGRESS` (contínuo) |

## 10. Itens da lista de lacunas do comando mestre

| Item | Estado | Onde |
|---|---|---|
| golden tests | `PASS` | `tests/golden.sh` 42/42; `tests/golden/quadros.tsv` |
| interoperabilidade | `BLOCKED` | §2, bloqueio A.1 |
| conformidade | `PASS` | `tests/conform.sh` 15/15 |
| corpus versionado e seguro | `PASS` | 38 vetores; sem dado sensível; integridade por sha256 |
| fuzzing | `PASS` (motor próprio, não dedicado) | `tests/fuzz.sh` 12/12; 150 000 iterações |
| regressão por defeito real | `PASS` | D2-27/28/29; `net` S4; F20/F21/F22 |
| análise dos formatos encontrados | `PASS` | `reports/rc-formatos-auditoria.md` |
| auditoria de `mud2`/`mu2ctl` preservando ABI | `PASS` | `net` 34 + `seguranca` 12; `git diff` vazio em `src/` |
| segurança e estabilidade | `PASS` | `tests/seguranca.sh` 12/12 |
| console administrativo | `PASS` (backend; sem UI, por decisão) | `docs/ADMIN_CONSOLE.md`, `tests/admin.sh` |
| assistente de publicação | `NOT_IMPLEMENTED` + `BLOCKED` | §8 |
| Lua / 3D / cliente | `PASS` parcial com 3 bloqueios | §4, §5, §2 |
| auditoria de rastreabilidade | este documento | — |

## 11. O que **não** está sendo afirmado

- Nenhuma compatibilidade com o `ConnectServer.exe` ou com qualquer binário original.
- Nenhum número de desempenho como requisito de produção; a linha de base é exploratória.
- Nenhum formato "decodificado" além do que a §5 de `rc-formatos-auditoria.md` demonstra.
- Nenhuma conclusão sobre o cliente original: ele não está neste pacote.
- Nenhum teste verde por omissão: `BLOCKED` e `NOT_IMPLEMENTED` são estados distintos de `PASS` no
  relatório do portão e aparecem em `nao_testado=`, não em `estado_de_fato=`.

## 12. Próximos passos, por ordem de dependência

1. `interop` real (bloqueio A.1) — desbloqueia também B.1, C.1 parcialmente e D (renderização).
2. Cliente original (bloqueio A.2) — desbloqueia E (FPS) e fecharia meta D.
3. Interpretador Lua (bloqueio C.1) — sintaxe e execução controlada dos 148 scripts.
4. Alvo de publicação (bloqueio G.1) — deixa de ser `NOT_IMPLEMENTED`.
5. `net-matrix` e `persistencia` seguem `SKIPPED` no portao padrao por serem opt-in (`GATE_FULL=1`): a matriz completa custa ~20 min e `persistencia` faz operacao de git. Ambos ja rodaram com `FULL=1` (matriz 36/0; verificador 13/13); manter opt-in e decisao deliberada, nao esquecimento. Restauracao de bundle em ambiente minimo e exercitada por `SELFTEST_ONLY=1` nas suites pe/data/cfg.

---

## Documentos de auditoria desta consolidação (2026-10-13)

Criados em `docs/` para leitura independente, todos ancorados na medição:

`PROJECT_STATUS.md` (inventário por estado) · `ARCHITECTURE.md` · `BUILD_AND_RUN.md` · `DATABASE.md` ·
`PROTOCOLS.md` · `TESTING.md` · `DEPENDENCIES_AND_LICENSES.md` · `SECURITY.md` · `ROADMAP.md`
(revisado) · `AUDIT_HANDOFF.md` (transferência ao auditor).

# PROJECT_STATUS — inventário do que existe, por estado de implementação

| campo | valor |
|---|---|
| data | 2026-10-13 |
| commit de referência | ver `AUDIT_HANDOFF.md` §2 (preenchido no fecho desta rodada) |
| método | cada linha tem **evidência** (arquivo/teste/medição). Não é porque existe classe, arquivo, interface ou documento que o sistema está implementado |
| fonte de verdade | o código e o portão (`tests/run_all.sh`) mandam; se este documento divergir deles, **a evidência vence** e a divergência é registrada |

## 0. Legenda — os estados, e o que cada um **não** significa

| estado | significa | **não** significa |
|---|---|---|
| `IMPLEMENTADO` | código existe no repositório e compila com `-Werror` + sanitizadores | que faz o que promete |
| `TESTADO` | há suíte automatizada com asserções reproduzíveis (numero em `TESTING.md`) | que é completo ou correto fora dos casos cobertos |
| `OPERACIONAL` | foi executado de verdade neste ambiente e o resultado medido está registrado | produção, escala ou compatibilidade |
| `PARCIAL` | parte mensurável existe; a outra parte está nomeada logo ao lado | que o resto está "quase pronto" |
| `AUSENTE` | não existe no repositório | que está planejado para breve |
| `NÃO VERIFICADO` | existe artefato/evidência, mas **sem** verificação independente que o confirme | que é falso — só que não foi provado |
| `BLOCKED` | depende de algo externo concreto, com causa e condição de desbloqueio | aprovação, nem falha do código |
| `NOT_IMPLEMENTED` | decidido como fora de escopo agora, com o motivo registrado | esquecimento |

Duas ressalvas que valem para o documento inteiro: (1) **as metas A–H do roadmap falam de um
servidor de MU Online**; o v2 hoje é um serviço de ensaio com contrato próprio (`ARCHITECTURE.md`
§1) — por isso quase todas as metas estão `AUSENTE`/`BLOCKED` e isso está dito, não escondido;
(2) **compatibilidade com o cliente/binários originais não foi comprovada em nenhum ponto**
(`PROTOCOLS.md` §4).

## 1. Sumário por área

| área | estado | evidência (arquivo → teste) |
|---|---|---|
| codec de enquadramento do v2 (contrato próprio) | `IMPLEMENTADO` + `TESTADO` + `OPERACIONAL` | `src/wire.c`, `include/mu2/mu2.h` → `unit` 106, `golden` 42, `conform` 15, `fuzz` 12 |
| serviço de rede de ensaio (`mud2`) | `IMPLEMENTADO` + `TESTADO` + `OPERACIONAL` | `src/mud2.c` → `net` 34, `seguranca` 13, `bench` 15, `net-matrix` 36 (opt-in) |
| CLI de controle (`mu2ctl`) e CLI do codec (`mu2codec`) | `IMPLEMENTADO` + `TESTADO` | `src/mu2ctl.c`, `tools/mu2codec.c` → `net`, `conform`, `golden` |
| fuzzer determinístico | `IMPLEMENTADO` + `TESTADO` (`PARCIAL` por não ter feedback de bordas) | `tools/mu2fuzz.c` → `fuzz` 12 (150 000 iterações, 0 violações) |
| console administrativo (backend, só loopback) | `IMPLEMENTADO` + `TESTADO` | `tools/mu2admin.c` → `admin` 24 |
| portão único + teste do portão | `IMPLEMENTADO` + `TESTADO` | `tests/run_all.sh` (23 etapas) → `gate_state.sh` 19/19 |
| backup restaurável do repositório | `IMPLEMENTADO` + `TESTADO` + `OPERACIONAL` | `scripts/verify-backup.sh` → 11/11 (15/15 com `FULL=1`) |
| sondas de inspeção do pacote (PE, dados, config, Lua, cifragem, interop) | `IMPLEMENTADO` + `TESTADO` | `tools/*_probe.py` → `pe` 14, `data` 21, `cfg` 15, `lua` 13, `lua-enc` 27, `interop` 12 |
| **sistemas de jogo** (login, sessão, personagem, mundo, combate, itens, guildas…) | **`AUSENTE`** | §2 — não há uma linha de código |
| **banco de dados / persistência** | **`AUSENTE`** no v2 | `DATABASE.md` |
| protocolo do cliente original | **`BLOCKED`** (camada 3) | `PROTOCOLS.md` §4 |
| compatibilidade com o cliente original | **`NÃO VERIFICADO`** (não há cliente no pacote) | `reports/r6-interop-relatorio.md` §2.3 |
| formatos `.ozt` / layout `.bmd` / cifragem dos `.lua` | `PARCIAL` + `BLOCKED` | `PROTOCOLS.md` §5 |

## 2. Sistemas de jogo — inventário honesto (todos `AUSENTE` no v2)

| sistema (pedido na tarefa de auditoria) | no v2 (`recriado/`) | no pacote original (`MuServer/`) |
|---|---|---|
| login e autenticação | **AUSENTE** — o serviço não autentica (o próprio código declara; `SECURITY.md` §1) | existe só como **configuração/binário**: `JoinServer.ini` (porta 55970, senha global em claro), `JoinServer.exe` protegido por Themida; nenhuma fonte |
| gerenciamento de sessões | **PARCIAL, e é outra coisa**: sessões de *conexão TCP de ensaio* (vagas, idle, fd/RSS) — não há sessão de jogador | sessão de jogador é lógica interna do binário; **não analisada** |
| personagens | **AUSENTE** | tabelas/procedures de reset citam conta/personagem (`WZ_*ResetInfo.sql`); o schema completo está em `.bak` — **não restaurado** |
| mundo, mapas, movimentação | **AUSENTE** | `Data/Terrain/*.att` (276), `MapServerInfo.dat`, `MonsterSetBase/**` — **formatos só parcialmente reconhecidos** e 1 310 spawns sem terreno correspondente (achado da fase anterior) |
| combate e monstros | **AUSENTE** | `MonsterSetBase/**` (99 arquivos, texto) — dados, não lógica |
| inventário, equipamentos, drops | **AUSENTE** | `Item.bmd` (XOR-3 decodificado em camada, **layout não decodificado**), `ItemTooltip_*.bmd` |
| comércio e economia | **AUSENTE** | nada medido além de arquivos de configuração de evento |
| guildas, grupos, eventos | **AUSENTE** | configs de eventos em `Data/**` (não analisadas a fundo) |
| anti-cheat / licença | **AUSENTE** | `PSGuard/**` (proprietário), `MHPServer/**`, `HackPacketCheck.txt` (272 entradas, 256 índices — **medido**) |

Consequência prática, sem eufemismo: **não existe servidor de MU Online neste repositório.** O que
existe é (a) o pacote original de terceiros, usado como material de medição, e (b) um projeto novo
que, por enquanto, implementa e prova apenas a **camada de rede de ensaio** e a **instrumentação**.

## 3. O que o v2 tem, item por item (com o número do teste)

| item | estado | teste / evidência direta |
|---|---|---|
| enquadramento `code|size|corpo`, LE, `size` total | `TESTADO` | `conform` C-01…C-15 (bytes exatos) |
| dois perfis (`orig` cru, `mur0` involução) | `TESTADO` | `conform` C-14; `golden` F21 (perfil trocado é detectado) |
| limites: corpo 2048, quadro 2052, `size` curto/longo | `TESTADO` | `conform` C-03…C-06; `fuzz` |
| leitura incremental, cabeçalho partido, escrita parcial | `TESTADO` | `net` S1–S3b |
| backpressure com fila de 1 vaga e fechamento por motivo | `TESTADO` | `net` S4; `seguranca` (`close=bad_frame` = 11) |
| limites de conexão (`max_clients`, idle) | `TESTADO` | `net` S8–S11 |
| entradas malformadas não derrubam o serviço | `TESTADO` | `seguranca` (13 asserções; fd/RSS estáveis) |
| encerramento limpo (`SIGTERM`, exit 0, resumo) | `TESTADO` | `seguranca`, `net` |
| golden com 38 vetores `${cláusula, origem}` | `TESTADO` | `golden` 42/42; falsificações F20/F21 |
| métricas (`STATS`), 9 campos em ordem | `TESTADO` | `conform` C-11/C-12; `net` |
| console admin: token 0600, tempo constante, papéis, loopback | `TESTADO` | `admin` 1–24 |
| publicação pelo console | `NOT_IMPLEMENTED` (decisão) | `/publicar` → `501` com motivo (`admin` caso 14) |
| interface gráfica | `NOT_IMPLEMENTED` (decisão; sem backend real não se faz botão) | `ADMIN_CONSOLE.md` §1 |
| leitura de estado do serviço em runtime pelo admin | `PARCIAL` — leitura sim; escrita não (não há opcode de controle) | `ADMIN_CONSOLE.md` §1; `admin` |

## 4. Metas A–H do roadmap (estado medido na última auditoria + etapa `enc`)

| meta | estado | resumo do que falta / bloqueio |
|---|---|---|
| **A. Reconstrução do servidor e compatibilidade** | `PARCIAL` — codec/serviço/ensaio `PASS`; interop `BLOCKED`; cliente `BLOCKED` | ambiente PE32/i386 + autorização; cliente original inexistente no pacote |
| **B. Rede e protocolo** | `PASS` no que é medível no v2; limite do **original** `BLOCKED` | exige binário original em execução |
| **C. Lua e scripts** | `PARCIAL` — inventário/evidência `PASS`; sintaxe `BLOCKED` (sem interpretador); cifragem `BLOCKED` (etapa `enc`: estrutura medida, algoritmo não identificado; `F23` bloqueada) | interpretador Lua; mais pares claro/cifrado ou desempacotamento autorizado |
| **D. Recursos 3D / arquivos pesados** | `PARCIAL` — classificação `PASS`; `.ozt` só assinatura; `.bmd` só a camada XOR-3 | validação no cliente real |
| **E. Desempenho/FPS** | `PASS` como **baseline exploratória** (sem requisito do dono); capacidade absoluta `BLOCKED` | host dedicado; cliente para FPS |
| **F. Painel administrativo** | `PASS` (backend); UI e escrita `NOT_IMPLEMENTED` **por decisão** | opcode de controle exigiria mudar contrato provado |
| **G. Assistente de publicação** | `NOT_IMPLEMENTED` + `BLOCKED` | alvo autorizado + contrato + credencial |
| **H. Segurança, backup, regressão, continuidade** | `PASS` no v2 (sanitizadores, fuzz, higiene, backup) — **pendências de segurança do pacote original** em `SECURITY.md` §5 | ação do proprietário (rotacionar credenciais; tratar `.bak`) |

Fonte: `reports/auditoria-rastreabilidade.md` (revisada nesta consolidação para incorporar a etapa
`enc`, que na versão anterior aparecia como `NOT_IMPLEMENTED`).

## 5. Funcionalidades ausentes ou não verificadas (lista curta, para o auditor)

1. Qualquer lógica de jogo; qualquer persistência; qualquer autenticação de jogador (§2).
2. Protocolo do cliente original — enquadramento, criptografia de rede, ordem de handshake
   (`PROTOCOLS.md` §6).
3. Compatibilidade com o cliente: **não verificada** (não há cliente no pacote).
4. Formatos: `.ozt` (estrutura), `.bmd` (layout), `.att` (semântica), cifragem dos `.lua` do
   cliente (algoritmo) — `PROTOCOLS.md` §5.
5. Sem intérprete Lua: sintaxe e execução dos 148 scripts **não verificadas**.
6. Exatidão da porta do cliente (44405 × 44406) — divergência medida, não resolvida.
7. Escala real: tudo foi medido em 2 vCPUs, loopback, sem hardware de produção.

## 6. Defeitos conhecidos e riscos abertos

**Corrigidos com teste de regressão** (não estão abertos; ficam citados porque o auditor deve saber
que existiram e que hoje são falsificações): D2-17 (ponteiro do corpo deslocado → métrica truncada),
D2-28 (prazo por iterações × relógio), D2-27 (janela de medição do bench), D2-29/D2-30 (testes que
apostavam em corrida), F12–F14 (o portão sabia não falhar), F20/F21 (golden não detectava mutação de
1 byte/perfil), F22 (fuzzer × codec mutado), o defeito 5 da corrida do teste de descritores, o falso
"12 divergências" do verificador de backup (escopo de bundle errado no layout com prefixo) e o verde
falso do portão em árvore limpa (fix `8b37936`).

**Abertos / a verificar:**

| # | achado | severidade | dono |
|---|---|---|---|
| 1 | credenciais em claro versionadas (token Discord, senha do JoinServer, serial, HWID) — **o histórico já as publicou** | **alta** | proprietário (rotacionar) |
| 2 | 4 backups de banco com PII de jogadores (50 373 632 B) publicados | **alta** | proprietário |
| 3 | 2 555 arquivos de log + 34 dumps de crash rastreados (podem conter memória/IPs/contas) | média | proprietário |
| 4 | ausência de licença no trabalho próprio e de atribuições de terceiros | média (jurídica) | proprietário (`DEPENDENCIES_AND_LICENSES.md` §5) |
| 5 | portas do cliente divergentes (44405 × 44406) | baixa | resolver com captura de tráfego (hoje `BLOCKED`) |
| 6 | 1 310 spawns sem terreno correspondente (fase anterior) | informativa | fora do v2 |
| 7 | `.ozt`/`.bmd`/`enc` sem decodificação completa | informativa | roadmap (`NEXT_TASK.md`) |

## 7. O que pode e o que **não** pode ser dito sobre este projeto

**Pode:** "há um serviço de rede de ensaio com contrato próprio, coberto por 23 etapas de portão e N
asserções medidas (vide `TESTING.md`), com backup restaurável e documentação de estado"; "a
conformidade interna do v2 está comprovada byte a byte"; "o material do pacote foi auditado por
medição, sem executar binários".

**Não pode:** "é um servidor de MU Online"; "é compatível com o cliente"; "implementa o protocolo do
MuEmuS6"; "decifrou a cifragem do Lua"; "a interop funciona". Nenhuma dessas frases tem evidência no
repositório — e a ausência está declarada em `PROTOCOLS.md` §6 e §4.

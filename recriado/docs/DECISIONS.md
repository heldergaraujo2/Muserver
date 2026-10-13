# DECISOES DO v2 (D2-xx)

Toda decisao abaixo e **reafirmada no v2**, com a evidenci desta rodada. Nenhuma foi
herdada do v1 como fato medido: o que o v1 media so aparece aqui como alvo ou como
contrato escolhido de novo. Marcacao obrigatoria: `[alvo]` = numero do v1 que precisa
ser remedido; `[medido]` = obtido nesta arvore/ambiente.

## D2-01 — o v2 mora dentro da arvore rastreada, nao num clone irmao
Motivo: a perda do v1 foi causada por isso, e nao por azar. O mecanismo de persistencia
da sessao grava o diff da arvore do repositorio da sessao; `/home/user/MuserverRecriado`
e `/home/user/muserverrecriado-main.bundle` estavam fora e nao voltaram.
Evidencia [medido]: `../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md` (busca forense
com privilegio, `lsdel`, blocos brutos, journal ext4, `git log --all -S`) e o artefato
`/tmp/arena-workspace/coding.patch` (90 arquivos, todos do repo principal).
Nao decide: onde o v2 vai morar **depois** de `MuserverRecriado` ser autorizado ao App —
a saida e `git subtree split -P recriado`, levando esta historia.

## D2-02 — numeros do v1 sao alvos, nunca resultados
Proibido no v2 escrever round-trip, CPU por quadro, vazao ou contagem de suíte como se
fossem reproduzidos. Valores citados do v1 vao rotulados `[alvo]` e so perdem o rotulo
quando um `.tsv` gerado nesta arvore, com o comando anotado, existir.
Motivo: os `.tsv`/`reports` do v1 estavam na arvore perdida; reescrever numero de memoria
e exatamente o modo de produzir os falsos positivos que esta sessao ja cometeu duas vezes
(o `setsockopt` aplicado depois do `connect`, e as 6 ocorreencias de `MU2_MAX_BODY` no
journal que eram nomes de arquivo meus).

## D2-03 — `MU2_MAX_BODY = 2048` (limite de corpo por quadro)
Escolha de contrato, nao de ambiente. Serve para manter a resposta dentro de um corpo de
`ConnectServer`-compativel e da o piso do experimento de backpressure: com corpo perto de
2048 B, a janela medida deste host ([medido], `tcp_window_probe.py`) comporta **1**
resposta, o que torna o gatilho de fila cheia seco e reproduzivel.
Nao decide: se o valor e otimizado — e um limite de compatibilidade, nao de performance.

## D2-04 — os dois perfis de quadro (`orig` e `mur0`) continuam obrigatorios desde R-3
Requisito do dono no v1 ("preservar os dois perfis"), e a assercao de equivalencia
funcional entre perfis e o que impede o codec de virar um so formato com dois nomes.
Cada suíte que enquadra um quadro roda nos dois perfis, e o `net`/`golden` publicam por perfil.

## D2-05 — fila de resposta de 1 vaga por conexao, com fechamento explicito e log
O v1 fechava quando `out_len != out_off` em `queue_reply` ("resposta anterior ainda
pendente — fechando em vez de enfileirar") e **nao** somava isso em `rejects`. O v2
reafirma a politica (sem perda demonstrada, nao se muda contrato de backpressure), com
duas mudancas de observabilidade, nao de comportamento: um contador proprio
(`queue_full_closes`) e a linha de log como discriminador de causa.
Alvo do experimento (fase R-4, herda a N-T5.3d2): `--sndbuf 1024` no servico **e**
`SO_RCVBUF=1024` no cliente **antes do `connect()`** — aplicar depois do handshake **nao**
fecha a janela [medido: `travou=False` com `depois`, `travou=True` com `antes`, 1 856 B,
~29 respostas de 64 B]. Efeito esperado: 30ª escrita com `EAGAIN` e a 31ª `queue_reply`
no estado ocupado ⇒ fechamento. Classificacao obrigatoria por linha de log do servidor:
fila cheia != bloqueio normal de TCP != timeout != erro de socket.
Nao decide: mudar o laço. Mudanca de laço so com perda reproduzivel causada por ele — e a
hipotese funcional a checar primeiro, que o v1 nao chegou a registrar, e **se o laço pede
`POLLOUT`** quando ha resposta pendente (se nao pede, uma resposta pendente nunca e
retomada: ahi ha starvation demonstravel, e nao apenas backpressure de projeto).

## D2-06 — fuzz proprio e deterministico, sem libFuzzer
[medido] este host nao tem clang, entao `-fsanitize=fuzzer-no-link` falha. O v2 usa
`tests/fuzz.c` com gerador deterministico (semente fixa por caso) + `corpus/` versionado,
e o corpus de regressao cresce a partir de casos que falharem — sem depender de ferramenta
que nao existe aqui nem pode ser instalada (fora da allowlist).

## D2-07 — `bench` com criterios de validade de ambiente; recusa e resultado
[medido] 2 vCPUs, 4 GiB, `perf`/`valgrind` ausentes, `cpu.max` inexistente. O `bench` so
publica numero se (a) as passadas concordam dentro de um limiar de drift **recalibrado para
este host** (o limiar do v1 nao e transportavel), (b) a carga de controle fica quieta, (c) a
amplitude da melhor medicao passa o limite declarado. Fora disso: `BLOCKED`, e o motivo
escrito. `blocked != aprovado` e assercao do proprio `run_all.sh`, nao nota de rodape.

## D2-08 — extensao de relatorio e `.tsv`/`.md`; nada de `.json`/`.txt` no caminho errado
[medido] `git check-ignore -v` confirma que o hospedeiro ignora
`workspace/reports/*.{json,txt,err}` e `workspace/recovered/`, e que `recriado/**` com
`.tsv`/`.md`/`.bundle` **nao** e ignorado (e `recriado/build/` e `recriado/reports/*.raw`
sao, como queremos). Um resultado de teste que nao entra na persistencia e um resultado que
nao existiu; a extensao e parte do metodo, nao burocracia.

## D2-09 — fim de rodada so existe com publicacao e backup conferidos
Sequencia obrigatoria por rodada: `git add <caminhos explicitos>` (nunca `git add -A`: o
`.gitignore` do hospedeiro documenta a armadilha em que `git rm -r --cached` seguido de
`git add -A` produz 2 376 delecoes silenciosas) → commit → `git push` → `git ls-remote`
**lido de volta** e comparado ao SHA local → `scripts/verify-backup.sh` verde (bundle
verificado + SHA-256 do manifesto + clone de teste a partir do bundle).
Rodada sem `ls-remote` conferido **nao** e entregue; se publicacao ou backup falharem, o
avanco que depende dessa protecao para, e o bloqueio e registrado aqui.

## D2-10 — o repo de referencia `Muserver` e somente leitura para o produto; PR #1 e do dono
Nao se altera `MuServer/**`, nem os arquivos da linha Lua (`workspace/**` existente), nenhum merge e feito por conta propria: existe `PR #1` **aberto** (`arena/cf1de8ce-muserver` → `main`, 5 commits,
autor `heldergaraujo2`) e a decisao de fundir e do proprietario. O `recriado/**` e um
acrescimo de arvore nova; a unica escrita fora dele e em `workspace/reports/` (relatorios).

## D2-11 — layout do quadro no v2: `code(2, LE) | size(2, LE) | corpo`
Cabecalho de 4 bytes; `size` e o tamanho **total** do quadro (cabecalho incluido), entao o
corpo e `size - 4`. Coerencia exigida na decodificacao: `4 <= size <= MU2_MAX_FRAME`, com
`MU2_E_BAD_LEN` para o resto e `MU2_E_INCOMPLETE` + `needed` para quadro ainda a meio.
Motivo de o comprimento ser de 16 bits [medido]: `MU2_MAX_BODY = 2048` (D2-03) nao cabe no
campo de 1 byte do MU classico (maximo 255). Nao e escolha estetica nem heranca: e
consequencia aritmetica do contrato.
O que esta **decidido contra** a tentacao obvia: este layout e do v2. O pacote de referencia
nao expoe enquadramento na camada Lua (procura por `HEAD_SIZE`/`PacketSize`/`opcode` em
`MuServer/Data/Script/System/ProtocolCore.lua`: zero ocorrencias), e o codigo do v1 nao foi
recuperado. Compatibilidade byte a byte com o `ConnectServer.exe` real e pergunta da fase
R-6, a responder a partir do binario (o `pe_probe` e as sondas de dados), e ate la o `interop`
do v2 nao existe — ausencia registrada, nao sucesso presumido.
Precisao util para quem ler D2-04 depois: a "equivalencia funcional entre perfis" ali pedida e
de **enquadramento** (mesmo `code`, mesmo `size`, mesmo consumo de stream, mesmas recusas), nao de
bytes de corpo — os corpos dao bytes diferentes por design (D2-12).

## D2-12 — `mur0` = corpo sob involucao posicional; `orig` = corpo cru
`mu2_body_transform` aplica `b[i] ^= key[i % 3] ^ (byte do opcode)` com `key = {AE, EC, D8}`.
Depende da posicao e do opcode, nunca do conteudo, por isso e involutiva (aplicar duas vezes
restaura) — propriedade testada (T5.1). Nao e cifra e nao reivindica ser: o ponto e manter dois
caminhos de enquadramento vivos (D2-04), e o codec recusa explicitamente ler quadro `mur0` como
`orig` sem aviso: o enquadramento continua valido e o corpo sai errado, e isso esta escrito como
assercao (T9.3) em vez de ficar como surpresa futura.

## D2-13 — o Makefile e contrato, e e validado como tal
Alvos `build`/`unit`/`make-sintaxe`/`check`; saidas em `out/` (nao em `build/`: o alvo `.PHONY`
chamado `build` colidia com um diretorio de mesmo nome e o `make` descartava a dependencia com
aviso que ninguem lia); flags `-Werror -Wshadow -Wconversion -Wsign-conversion` + ASAN/UBSAN por
padrao, com `SAN=0` existe so para comparar custo, nunca para publicar numero.
`tests/make_parse.sh` (5 casos) e obrigatorio porque flag que some silenciosamente muda o portao
sem mudar teste nenhum. Licao medida nesta fase: o caso 4 era **flaky por construcao** — sem
`-B`, um `out/` ja atualizado fazia o `make -n` imprimir so `./out/unit`, e o caso passava a
falhar por ambiente. Agora usa `make -s -B -n` e foi conferido em tres situacoes de estado
(saida limpa, saida quente, quente duas vezes).

## D2-14 — o laço do servico registra `POLLOUT` sempre que ha resposta pendente (abre a R-4)
O enunciado da N-T5.3d2 pedia para verificar, no codigo do v1, se o laço de `poll()` pedia
`POLLOUT` quando havia resposta pendente — e o v1 nao registrou a resposta. Como o v1 nao foi
recuperado, a pergunta nao e de arqueologia: ela vira decisao de projeto do v2, e a decisao e
**sim**, sempre:
- `poll()` e chamado com `POLLOUT` no `events` de toda conexao cujo `out_len != out_off`;
- quando `write` devolve `EAGAIN`, a resposta pendente **continua na fila de 1 vaga** e o laço
  volta a tenta-la no próximo `POLLOUT`; o fechamento por fila ocupada so acontece quando um
  **novo** pedido chega com a vaga ainda ocupada (politica de D2-05, mantida);
- isso fecha a unica via pela qual um quadro pendente poderia virar starvation permanente, que e
  justamente o defeito que a pergunta procurava achar. O experimento da R-4 tem de poder
  distinguir os quatro casos (fila cheia / bloqueio normal de TCP / timeout ocioso / erro de
  socket) e a assercao de que `POLLOUT` e registrado e verificada por teste, nao por comentário:
  um cliente que le atrasado e depois le tudo tem de receber **todas** as respostas, com
  `queue_full_closes == 0`, e um cliente que nao le nada e faz novo pedido tem de produzir o
  fechamento com a linha de log propria.
Nao decide: aumentar a fila nem os buffers. Se a R-4 mostrar perda ou contrato violado, a mudanca
de politica vem em commit isolado, com regressao e `bench` antes/depois (D2-05).

## D2-15 — a copia viva do backup mora em `workspace/backups/`, nao dentro de `recriado/backup/`
Descoberto por medida nesta rodada, nao por gosto: o bundle e gerado do `git subtree split -P
recriado`, entao enquanto ele morava dentro de `recriado/backup/` cada regravacao embutia o bundle
anterior. Tamanhos seguidos: **17 225 → 38 233 → 66 195 → 134 694 bytes**. Crescendo ~2× por
rodada, o mecanismo de seguranca estouraria o teto de persistencia da plataforma (≈128 MB somados)
e o backup passaria a *causar* a perda que existe para evitar.
Regra, com o passo a mais que a medida exigiu: so realocar nao resolveu — o bundle refeito
depois de mover ainda deu **204 585 bytes**, porque o `subtree split` reproduz os commits
historicos de `recriado/`, e esses commits continham os bundles antigos. A copia independente
passou entao a ser um **snapshot orphan** (`git commit-tree` da arvore `HEAD:recriado`, um unico
commit): restaura o estado atual em tamanho constante, e a *historia* fica onde ela pertence, no
`git push` (e no branch local `mu2-v2`, que e a semente de migracao para o repo proprio). Nada foi apagado: os blobs antigos seguem no
historico e voltam com `git checkout 5c9e318 -- recriado/backup` se alguem precisar da copia
congelada de uma rodada especifica — e `scripts/verify-backup.sh` passa a conferir o caminho novo.

## D2-16 — protocolo do servico de ensaio: opcodes, motivos de fechamento e a linha de metricas
O servico da R-4 precisa de um vocabulario proprio, e ele fica em `include/mu2/proto.h`:
`MU2_CODE_PING 0x0001` (resposta de corpo vazio), `MU2_CODE_ECHO 0x0002` (devolve o corpo),
`MU2_CODE_STATS 0x0003` (devolve a linha de metricas). **Sao codigos do v2.** Nao ha aqui nenhuma
afirmacao de compatibilidade com o MU Server original — a comparacao com o protocolo real continua
sendo trabalho da R-6, a partir do binario.
Tres escolhas que precisaram de decisao explicita:
- **Opcode desconhecido e descartado, nao punido.** Fechar a conexao por lixo deixaria um cliente
  derrubar a propria conexao de proposito e sujaria a classificacao de causa nos testes de rede.
  O evento conta em `unknown` (visivel no resumo de saida) e a conexao segue.
- **O motivo do fechamento e um token `close=<motivo>` no log, UMA linha por evento.** A primeira
  subida emitia duas (o `WARN` de fila cheia e o `close_conn`), o que dobraria qualquer contagem
  feita por log — medido: 2 linhas para contador 1. Motivos: `queue_full`, `client_eof`,
  `client_hup`, `socket_error`, `write_error`, `bad_frame`, `idle_timeout`, `max_clients`,
  `shutdown`. A suite de rede exige que toda linha `close=` caia num motivo conhecido.
- **A linha `STATS` conta a si mesma em `frames`** (o incremento acontece antes de a linha ser
  montada). Nao e off-by-one a consertar: e o comportamento, e ha assercao que o trava, para que
  ninguem o "corrija" sem perceber que os relatorios mudariam junto.
`slotsz` na linha de metricas e o tamanho em bytes da vaga unica de resposta (`MU2_MAX_FRAME`), e
`maxbody` e `MU2_MAX_BODY`. A linha e lida de fora por `mu2ctl stats`, pelo proprio protocolo: um
segundo consumidor do codec, que falha junto se o enquadramento estiver torto.

## D2-17 — `mu2_frame_body` recebe o INICIO do quadro, nao o ponteiro do corpo
`mu2_frame_decode` devolve em `body_out` o endereco do corpo (`src + 4`), mas `mu2_frame_body` soma
`MU2_HEADER_SIZE` internamente: o `src` dele e o **inicio do quadro**. Passar o corpo desloca tudo
em 4 bytes. O v2 caiu exatamente nisso na primeira subida do servico, e o sintoma foi uma linha de
metricas impressa como `S registros=64 ...` com lixo no fim — o teste de comprimento continuava
passando, porque o comprimento estava certo.
Decisao: **nao mudar a assinatura** (a R-3 esta testada contra ela e mudar ABI por conveniencia de
leitura trocara um defeito visivel por um risco invisivel). O comentario do cabecalho foi
esclarecido e o erro fica registrado aqui. Licao para as suites: conferir **conteudo**, nao so
tamanho — o cliente de ensaio passou a comparar byte a byte o corpo do `ECHO`.

## D2-18 — a vaga unica so e viavel com `drain()` imediato, e o limite de backpressure e a janela do cliente
Duas coisas medidas na R-4, nenhuma das duas obvia antes de medir:
1. **Sem o `drain()` imediato, a fila de 1 vaga nao funciona com pedidos encadeados.** Falsificacao
   F6: removida a tentativa imediata de escrita, o segundo quadro do **mesmo** `recv` encontra a
   vaga ocupada e o servidor fecha a conexao (log: `queue_full pending=4`), e o cliente recebe zero
   respostas. A suite caiu em 8 verificacoes. O `drain()` imediato nao e otimizacao: e o que torna a
   politica de D2-05 compativel com pipelining.
2. **O limite observavel nao e o numero de quadros, e a janela de recepcao do cliente.** Na matriz
   (100 configuracoes x 5 repeticoes por perfil): com buffers padrao, **0 perdas e 0 filas cheias em
   50/50 configuracoes**; com `--sndbuf 1024` no servico **e** `SO_RCVBUF 1024` no cliente antes do
   `connect()`, fila cheia em **50/50**, com mediana de 7 a 16 respostas entregues. Pedidos 1024 →
   efetivos 2304 no cliente e 4608 no servico; sem pedir nada, o socket aceito herda 2 626 560.
   O registro historico do v1 ("~29 respostas de 64 B antes do `EAGAIN`", D2-05) **nao se reproduziu
   neste host**: fica como divergencia documentada, nao como meta nem como regressao.
Duas regras que saem daqui: (a) o orcamento do cliente de teste tem de ser maior que o pior cenario
— com 5 s uma configuracao deu 107/120 e com 20 s deu 120/120 nas cinco repeticoes, ou seja, a
"perda" era do instrumento, e a matriz passou a usar `--timeout-ms 20000`; (b) **nada disso justifica
aumentar `MU2_MAX_BODY` ou buffers** — o comportamento observado e o contrato funcionando.

## D2-19 — sondas de formato são somente leitura, determinísticas e sem dependência externa

**Contexto (R-5).** A fase pede investigação de PE/Lua/dados/`.att`/`.bmd`/`.smd`/`.ozt`/`.ozj`/`.bak`
*por medição*. As alternativas eram binários prontos (`objdump`, `pefile`, `radare2`) ou parser
próprio; `objdump` existe no host, `pefile`/`radare2` não, e o pacote é somente leitura.

**Decisão.** Quatro sondas em Python 3.11 **só com stdlib** (`struct`, `hashlib`, `collections`), em
`tools/`, lendo `MU_REF_DATA` e imprimindo TSV com caminhos **relativos** e **sem timestamp**.
Nenhuma escreve, executa ou abre banco: dos `.bak` lê-se só os 16 primeiros bytes.

**Motivo medido.** Sem dependência externa a sonda roda em qualquer restore de bundle; sem timestamp
a saída é comparável por `sha256` entre passadas (caso 13 de `tests/data.sh`); sem caminho absoluto
o relatório não vaza o host (casos 10/15). Determinismo é o que transforma medição em evidência.

**Consequência.** `pe` e `data` entram no `check`; os alvos `pe-selftest`/`data-selftest` rodam a
mesma lógica de recusa **sem** a referência, para o portão não ficar mudo em ambiente mínimo.

## D2-20 — achar string não é concluir recurso; não achar não é provar ausência

**Contexto (R-5).** A busca por `PacketSize`, `HEAD_SIZE`, `opcode`, `IOCP` e pelas portas do
pacote devolveu **zero** ocorrências nos binários.

**Decisão.** Toda busca por palavra-chave entra no relatório com as duas ressalvas explícitas:
*achar* só prova que o símbolo está lá (não que seja usado no caminho que interessa), e *não achar*
não prova ausência (o nome pode ser montado em execução, vir de import sem string, ou estar em
seção protegida). As asserções de ausência no teste dizem isso no próprio nome do caso.

**Motivo medido.** `GameServer.exe`, `GameServerCS/GameServer.exe` e `DiscordServer.exe` têm seção
`.themida`: neles a análise estática simplesmente para. Declarar "não usa IOCP" porque a string não
apareceu seria inventar conclusão sobre binário ofuscado.

**Consequência.** Nenhum formato é declarado decodificado nesta rodada. O que existe é invariante
medido + hipótese nomeada.

## D2-21 — invariante de formato só se afirma depois de medir a distribuição inteira

**Contexto (R-5).** Com duas amostras de `.att` o prefixo parecia fixo em `00 ff ff`. Em 276
arquivos, `byte0` tem **dois** valores (`0x00` e `0x20`); o que é constante em 276/276 é
`bytes[1:3] == ff ff`, junto com o tamanho único de 65 539 B.

**Decisão.** `att_probe.py` aceita `tamanho == 65539 && bytes[1:3] == ffff` e nada mais; `byte0` e
`byte3` são **relatados como distribuição**, não cobrados como constante. Amostra pequena não vira
invariante, e hipótese de estrutura (grade 256 × 256, bitmask) fica no relatório como hipótese.

**Motivo medido.** A asserção com prefixo fixo falhou em 3 de 276 arquivos na primeira execução —
defeito do teste, não do pacote. Se tivesse entrado no commit, o portão nasceria vermelho por
suposição.

**Consequência.** Regra geral para as próximas rodadas: medir a distribuição antes de escrever o
`grep`. Vale também para o inverso: `.bmd` não é um formato só (XOR-3 vale para o banco do
MuEditor, mediana −0,16 no conjunto), então nenhum decodificador pode depender só da extensão.

## D2-22 — o portão é a única definição de "verde", e resumo ausente é FAIL

**Contexto (R-8).** Com cinco suítes e cinco previstas, "o projeto está verde?" passou a depender de
quem lembrava de rodar o quê. Havia também um risco concreto: suíte que sai 0 sem imprimir nada
conta como aprovada em qualquer agregador ingênuo.

**Decisão.** `tests/run_all.sh` é o único ponto que declara estado. Cinco estados, não equivalentes:
`PASS` (exit 0 + `falhas=0` + `blocked=0` + linha de resumo presente com o rótulo da etapa) ·
`FAIL` (exit ≠ 0, ou `falhas>0`, ou **resumo ausente**, ou timeout) · `BLOCKED` (dependência externa
concreta ausente) · `NOT_IMPLEMENTED` (etapa prevista sem arquivo) · `SKIPPED` (dispensa explícita
com motivo). Só `FAIL` derruba o portão; a mesa imprime `testado_de_fato=` e `nao_testado=` com
nomes, para que ninguém leia 0 falhas como cobertura total.

**Motivo medido.** `gate-selftest` caso 7: suíte que sai 0 sem resumo ⇒ `FAIL`. Sem essa regra,
`golden`/`interop`/`conform` poderiam "passar" vazios no dia em que alguém criar os arquivos.

**Consequência.** `make check` continua existindo (é o portão de build+suítes rápidas) e `gate` não
entra nele, para não haver recursão. `pe-selftest`/`data-selftest` passaram a distinguir
`escopo=selftest` (cobertura reduzida por decisão) de `blocked=1` (referência ausente): antes os
dois saíam `blocked=1` e um selftest aprovado parecia ter coberto a referência.

## D2-23 — falsificação de mecanismo é diferencial, em cópia temporária

**Contexto (R-8).** As falsificações F12–F14 precisam provar que o portão detecta o defeito. O
método da R-3/R-4 era mutar o arquivo real e reverter depois.

**Decisão.** F12 e F13 rodam contra uma **cópia mutada em diretório temporário** e afirmam a
*diferença* de comportamento entre a cópia e o portão verdadeiro. Só F14 muta arquivo real
(`tests/make_parse.sh`), com restauração conferida por sha256 e re-execução da etapa.

**Motivo medido.** Na R-4, o `pkill -f` do teste de mecanismo matou o próprio shell, a reversão não
rodou e três medições seguintes foram feitas contra binário mutado. Mútuo: se a detecção deixar de
depender do mecanismo, cópia e original concordam e o caso falha — a falsificação continua valendo
como teste, não só como demonstração.

**Consequência.** A fixture da F12 sai ≠ 0 **com resumo limpo**; se reportasse `falhas>0`, a contagem
detectaria sozinha e a falsificação não isolaria o exit code. Esse cenário (`exit=3` com resumo
limpo) virou caso permanente do `gate-selftest`.

## D2-24 — prazo de etapa por `timeout(1)` + grupo próprio, nunca watchdog de fundo

**Contexto (R-8).** A primeira versão do portão implementava o prazo com `( sleep $tmo; kill ) &`.

**Decisão.** Prazo vem do `timeout(1)`; cada etapa roda como job com `set -m` (grupo de processo
próprio); ao estourar o prazo, o grupo inteiro é varrido (`TERM` → 1 s → `KILL`); interrupção do
portão varre o grupo da etapa corrente e sai 130. Nenhum processo de fundo de controle.

**Motivo medido.** Artefato da versão anterior: `out/gate/build.timeout` criado **600 s depois** da
etapa e `sleep 420` órfão com `PPID 1` vivo no host. O watchdog sobrevivia à etapa, o `wait` dele
bloqueava a corrida (uma execução completa travou) e um grupo alheio podia ser sinalizado no meio de
outro teste — na mesma corrida, `net` reportou 3 falhas em S4 que não se reproduzem isoladamente
(`make -s net` 34/0, `GATE_ONLY=net` 34/0, `setsid` direto 34/0).

**Consequência.** Regra para qualquer mecanismo de prazo daqui em diante: testar **o que ele deixa
vivo**, não apenas se dispara no tempo certo.

## D2-25 — nenhum segredo entra em arquivo versionado, e a redação é testada

**Contexto (R-6).** A configuração original guarda credenciais em claro: senha global
(`JoinServer.ini`), token de bot (`DiscordServer.ini`), hardware id e chaves `EncDecKey1/2`
(`MHPServer.ini`). Medido: 26 valores sensíveis em 19 arquivos. Qualquer inventário de configuração
que imprimisse valores copiaria segredo para dentro do repositório.

**Decisão.** `tools/cfg_probe.py` substitui valor de chave sensível por
`<REDACTED bytes=N forma=...>`. A detecção é por **nome de chave** (substring: `pass`, `senha`,
`token`, `secret`, `key`, `hardwareid`, `license`, …) **e por forma do valor** (token/GUID com nome
inocente também cai). `tests/cfg.sh` afirma que todas as linhas sensíveis estão redigidas e que
nenhuma credencial em claro aparece na saída, com fixture sintética no selftest.

**Motivo.** Regra do projeto: sem token/segredo em arquivo. E a redação não pode ser promessa —
se ela falhar uma vez, o segredo fica no histórico do git para sempre.

**Consequência.** Os relatórios publicados foram conferidos: 0 linhas sensíveis não redigidas.
Ação do dono registrada: rotacionar as credenciais do pacote antes de qualquer exposição.

## D2-26 — o registro do portão é contrato: etapa duplicada é erro, e totais exatos não viram asserção

**Contexto (R-6).** Ao criar a etapa `conform`, o placeholder `NOT_IMPLEMENTED` da R-8 não foi
removido. A mesa imprimiu `conform` duas vezes e contou as 15 asserções em dobro (244 em vez de
229) — com `PASS` nas duas linhas, nada parecia errado.

**Decisão.** Duas regras:
1. `run_all.sh` valida o registro antes de rodar: nome de etapa duplicado ⇒ **exit 2** com erro
   explícito (`gate_state.sh` caso 19 cobra isso).
2. Teste sobre o portão real não prende totais exatos. Prender "194 asserções" fazia o caso falhar
   toda vez que uma suíte nova entrava. O caso 12 do `gate-selftest` cobra invariantes: exit 0,
   zero `FAIL`, nenhum estado fora do conjunto conhecido, e **piso** de cobertura (≥9 `PASS`,
   ≥194 asserções) para que a R-8 nunca regrida em silêncio.

**Motivo medido.** Contagem em dobro é o tipo de erro que ninguém vê numa mesa verde; e asserção que
quebra por crescimento de cobertura treina todo mundo a ignorar teste vermelho.

## D2-27 — baseline de desempenho é exploratória, com critérios declarados antes e juiz separado de quem mede

**Contexto (R-7).** Não existe requisito de desempenho definido pelo dono. Sem critério declarado,
qualquer número vira meta de facto, e um host de 2 vCPUs produz spread de 40 % entre repetições.

**Decisão.** Três regras:
1. Os critérios de validade ficam **no topo do roteiro e são declarados antes de rodar**: 5
   repetições, 1ª descartada como aquecimento, drift máximo de 25 % em relação à mediana.
2. Quem mede não julga: `tools/bench_check.py` é um programa separado de `tests/bench.sh`, com
   códigos de saída que distinguem natureza — `1` drift acima do declarado ⇒ **`BLOCKED`** por
   ambiente (número não publicado, portão continua verde), `3` perda de quadro ⇒ **falha real**.
   Perda **e** drift alto é falha, não ambiente: classificar como `BLOCKED` esconderia o defeito.
3. Afrouxar critério para o número passar é falsificação. Quando a janela de 2 000 quadros deu
   drift de 40,4 %, o que se corrigiu foi a **janela** (20 000 quadros ⇒ 4,3–17,2 %), não o limite
   de 25 %. O número antigo ficou registrado em `reports/r7-relatorio.md` §5, D-2.

**Motivo.** `BLOCKED` por ambiente é informação; um número instável publicado como baseline é
mentira com casa decimal. A F18 existe para provar que o critério está lá: com a comparação do
drift neutralizada em cópia temporária, o validador deixa passar um drift de 300 %.

**Consequência.** ~1 execução em 15 sai `BLOCKED` por drift (medido). Isso é o comportamento
projetado, não instabilidade a esconder.

## D2-28 — prazo é relógio, nunca contagem de iterações

**Contexto (R-7).** `tests/netclient.c` somava o *timeout* do `poll` a um contador de prazo:

```c
pr = poll(&pfd, 1, 100);
elapsed += 100;      /* com dados prontos o poll volta na hora: 100 ms de orçamento por leitura */
```

Com `--timeout-ms 60000` e 2 000 quadros, o cliente desistia após ~600 leituras. Medido: 3 de 5
repetições terminaram com 1 371, 1 311 e 1 238 quadros de 2 000, e o serviço registrou
`close=write_error` com `rejects=4`. **O harness fabricava "perda do serviço"**: o cliente
desistia, o socket fechava, e a escrita seguinte do serviço falhava.

**Decisão.** Prazo se mede com `clock_gettime(CLOCK_MONOTONIC)` nos dois laços que tinham o padrão
(leitura e espera de EOF). Contador de iteração não é relógio, e o mesmo padrão foi procurado e
corrigido nos dois lugares, não só no que falhou.

**Motivo.** A classe já tinha aparecido na R-4 (`--timeout-ms 5000` → 107/120) e foi tratada como
"orçamento apertado". Era causa raiz: qualquer teste de carga com este cliente media o harness.

**Consequência.** Depois da correção: 5/5 repetições com 20 000 quadros completos, `rejects=0`,
zero `write_error`. As 34 asserções de `net` e as 15 de `conform` — que dependem deste cliente —
continuam verdes.

## D2-29 — teste que aposta em corrida não é teste: condição de contorno se fixa

**Contexto (R-7).** O cenário de limite B5 (pipeline além do que os buffers absorvem) falhou 1 vez
em 15 execuções: sem limitar o buffer de recepção do cliente, os 4 104 000 B do pipeline às vezes
cabiam, e o `queue_full` simplesmente não acontecia (a conexão terminava em `socket_error`).

**Decisão.** A condição que produz o fenômeno medido é **parâmetro do teste**, não aposta: B5 fixa
`--rcvbuf 1024` (efetivo 2 304 B). Com isso, 8 de 8 e depois 15 de 15 execuções reproduzem
`close=queue_full`.

**Motivo.** Um teste intermitente treina todo mundo a reexecutar até ficar verde — e é assim que
`gate-selftest` caso 13 (que roda o portão real) passou a falhar 1 vez em 3.

**Consequência.** O limite medido é condicional e está rotulado como tal: "com `rcvbuf` efetivo de
2 304 B e corpo de 2048 B, 551 quadros passam antes do fechamento". Sem o `rcvbuf` no rótulo, o
número não significa nada.

## D2-30 — flakiness real se corrige na raiz: volume contra capacidade, não critério afrouxado

**Contexto.** `tests/net.sh` S4 ("cliente que não lê e pede mais acaba desconectado") falhava 1 vez
em ~8 execuções do portão. O cenário enviava 60 quadros de 64 B, ou seja **4 080 B** de respostas,
contra capacidade efetiva medida de ~7 kB neste host (`rcvbuf` 1024 → 2 304; `sndbuf` 1024 → 4 608).
Quando tudo cabia nos buffers, o `queue_full` não acontecia, o cliente não via o FIN em 3 s e a
asserção `eof=1` falhava.

**Decisão.** Corrigir a **margem do cenário** (600 quadros = 40 800 B, ~6× a capacidade), nunca o
critério. Depois: `net` 15/15 execuções com 34 asserções e 0 falhas.

**Consequência.** `gate_state.sh` passou a **preservar evidência em falha**: se qualquer caso falhar,
o diretório temporário inteiro é copiado para `out/gate-selftest-falha/` antes de ser apagado. Um
teste que falha e não deixa nada para examinar é indiagnosticável — foi assim que esta falha ficou
sem causa identificada por uma rodada inteira.

## D2-31 — retratação: "0 declarações de framing em .lua" era concluão errada

**Contexto.** A R-6 publicou que a busca por `HEAD_SIZE|PacketSize|MakePacket|opcode` em `.lua`/`.txt`
devolveu zero ocorrências, e daí concluiu que a camada Lua nada tinha a ver com pacotes.

**Decisão.** A **medição** estava correta e continua valendo para framing de bytes; a **conclusão**
estava errada, porque os tokens eram estreitos demais. Medido agora: `148` arquivos `.lua` (o `7 378`
da R-6 somava `.lua` **e** `.txt`), **20** com termos de pacote, **5** chamando `SendPacket`, e
**8** cópias de `ProtocolCore.lua` (3 de servidor, 5 do cliente). A afirmação correta é: não há
declaração de *framing de bytes* nos scripts, mas **há** uma camada real de despacho de pacotes por
nome.

**Consequência.** `tests/lua.sh` fixa os números medidos, e a retratação está em
`reports/rf-lua-protocolo.md`. O histórico não foi apagado: a afirmação antiga continua visível nos
relatórios da R-6, com a correção ao lado.

## D2-32 — "referência intacta" passa a significar o que de fato verifica

**Contexto.** `tests/ref_check.sh` comparava `HEAD:MuServer` com `fade04615fab…` e passava; a
afirmação usada nos resumos era "MuServer/ intacta". Mas essa árvore é a **pós-endurecimento-Lua**:
o commit `b5b84da` modificou **6 arquivos `.lua` dentro de `MuServer/`** (`ScriptMain.lua`,
`ProtocolCore.lua`, `ScriptCore.lua`, `DataBase.lua` e os `ScriptMain` de `SpeedServer` e
`SubSalatest`; 327+/316−).

**Decisão.** A verificação continua válida e ganhou dois casos: (7) exatamente 6 `.lua` diferem do
upload `6eabb45` e nenhum outro arquivo; (8) os baselines em `workspace/changes/originals/` são
**blob-idênticos** aos do upload, ou seja a reversão é real, não prometida. "Intacta" passa a
significar, explicitamente, "não mudou desde `b5b84da`".

**Consequência.** Qualquer evidência sobre o **original** tem de vir do baseline ou das cópias não
tocadas (`SpeedServer`, `SubSalatest`) — nunca do arquivo patcheado. Foi essa regra que permitiu
extrair a assinatura `GameServerProtocolRecv(aIndex, Packet, PacketName)` de fonte legítima.

## D2-33 — fuzzing sem motor dedicado: alternativa determinística, com a diferença declarada

**Contexto.** Medido: não há `afl-fuzz`, `afl++`, `honggfuzz`, `radamsa`, `zzuf` nem `clang` neste
host, e o gcc 12 rejeita `-fsanitize=fuzzer`.

**Decisão.** `tools/mu2fuzz.c` é um motor **próprio e determinístico**: sementes extraídas do corpus
golden, 10 operadores de mutação, julgamento por **oráculo de invariantes** derivado do contrato, com
os sanitizadores do build ligados e a entrada em heap de tamanho exato (a redzone do ASan pega
leitura fora do fim). 150 000 iterações, 0 violações, 0 mortes por sinal.

**Consequência.** A saída da ferramenta **declara** a limitação: não há cobertura guiada por feedback
de bordas, e não se afirma equivalência a fuzzer dedicado. `F22` prova que o oráculo tem dentes: com
o codec mutado numa cópia temporária (piso `size < 4` removido), o fuzzer acusa violações; a entrada
que derrubou o mutante é replayada no codec real e recusada com `MU2_E_BAD_LEN`.

## D2-34 — console administrativo como processo separado, falhando fechado

**Contexto.** O comando mestre proíbe interface sem backend, botão sem função e publicação simulada,
e exige desenho documentado **antes** do código.

**Decisão.** `docs/ADMIN_CONSOLE.md` foi escrito primeiro. O console é `tools/mu2admin.c`, processo
separado, single-threaded, **somente loopback**, que lê o estado do `mud2` pelo protocolo v2 (como o
`mu2ctl`) e não toca no produto. O produto não ganha HTTP nem thread. Token de arquivo `0600` (nunca
de `argv`, que aparece em `ps`), mínimo 32 caracteres, papéis `leitor`/`admin`, comparação em tempo
constante, **fail closed**: sem token válido o servidor não sobe. Publicação é `501` com motivo —
não existe alvo autorizado, e simular é proibido.

**Consequência.** `tests/admin.sh` cobre os 17 itens da tabela de testes do desenho (22 asserções).
`git diff` vazio em `recriado/src` e `recriado/include`: o ABI e o protocolo comprovados em 15/15
permanecem intactos.

## D2-35 — evidência manual supervisionada no lugar de execução automática de binário original

**Contexto.** A camada 3 de interoperabilidade exige executar o `ConnectServer.exe`. A regra do
projeto proíbe executar binário original automaticamente, e não há `wine`/`qemu-i386` no host.

**Decisão.** `tests/interop.sh` **não tem caminho de execução** de binário original. Quando as
precondições existirem, o teste real é manual e supervisionado e deposita
`reports/r6-interop-real.tsv` com 8 chaves obrigatórias; a suíte **valida essa evidência** e só então
reporta `camada3=evidencia-manual-validada`. Sem o arquivo, o estado é `BLOCKED` — nunca `PASS` por
omissão, nunca conexão simulada.

## D2-36 — a reconstrução sai do monorepo e passa a ter repositório próprio

**Decisão.** `recriado/` é publicado como repositório `heldergaraujo2/MuserverRecriado`, com o
histórico levado por `git subtree split`. **Motivo.** A razão de o v2 morar dentro do repo da sessão
era a persistência: o v1 morreu num clone irmão não rastreado. Essa razão deixa de valer quando
existe (a) repositório próprio autorizado, (b) pacote de migração reprodutível e (c) transporte por
bundle — três caminhos independentes em vez de um. **Limite.** Enquanto o push respondendo 403 não
for resolvido no App, o monorepo continua sendo o único lugar onde o trabalho *publicado* existe; a
migração não é declarada concluída.

## D2-37 — testes agnósticos de layout (o prefixo é medido, não constante)

**Decisão.** `tests/admin.sh`, `tests/fuzz.sh` e `scripts/verify-backup.sh` derivam o prefixo da
árvore dentro do repositório por `git rev-parse --show-toplevel` (`PFX=''` no repo publicado,
`'recriado/'` no monorepo). **Motivo.** Um teste que falha por layout não prova nada sobre o código:
o caso `git diff --quiet -- recriado/src` falhava no repositório publicado, onde essa árvore **é** a
raiz. **Limite declarado.** O `verify-backup.sh` mantém a referência `MuServer/` como **BLOCKED** no
layout publicado (nunca `ok`), e a divergência de conteúdo em relação ao snapshot é conferida contra
uma lista declarada e curta.

## D2-38 — a cópia independente passa a ser regravada dentro do repositório publicado

**Decisão.** No destino, o snapshot é um commit **orphan** da própria árvore e o bundle vive em
`workspace/backups/`; o monorepo mantém a sua própria cópia (do `recriado/`). **Motivo.** A cópia
tem de restaurar **o que foi publicado**, e o repositório publicado tem de restaurar a si mesmo sem
depender do monorepo — que é justamente o que se perdeu no incidente do v1. **Medido:** tamanho, sha256 e ponta do bundle vigente no `MANIFEST.md` ao lado dele
(`workspace/backups/`), com restauração conferida por `git clone -b mu2-snapshot` +
`make -s check` sem falhas. **Não confundir:** são duas cópias com escopos diferentes, como o bundle
e os relatórios de auditoria já eram.

## D2-39 — o bundle de transporte é artefato versionado do monorepo

**Decisão.** `workspace/migracao/destino-muserverrecriado.bundle` fica versionado no monorepo, com o pacote
`workspace/migracao/` (tamanho e sha256 vigentes no `README.md` do pacote). **Motivo.** Se a
publicação continuar bloqueada, o destino inteiro (histórico + evidência) tem de sobreviver a uma
recriação de sandbox fora do caminho que depende do push. **Verificação obrigatória do artefato:**
`git clone -b main` a partir do bundle → árvore idêntica à do destino conferido e `make -s check`
sem falhas.
**Limite.** Ele é transporte, não publicação: nada aqui afirma que o remoto foi atualizado.


## D2-40 — persistência do v2: formato próprio, e rollback é remoção física

**Contexto.** O v2 não tinha nenhum estado durável (D2-16 declarava `AUSENTE`): reiniciar o serviço
zerava tudo. A tarefa de auditoria lista persistência como subsistema próprio, e o pacote de
referência exige SQL Server via ODBC — que não existe neste ambiente e cujo esquema não é conhecido
(`DATABASE.md`).

**Decisão (três partes).**
1. **Formato próprio, declarado como próprio.** Arquivo append-only `MU2DB01`, cabeçalho de 64 B,
   registro de 32 B + payload com CRC32C, 13 tipos de registro, `schema_version` no cabeçalho. O
   cabeçalho de `db.h` diz, em uma linha, que isto **não** é compatível com o SQL Server original e
   não tenta ser. Nenhuma alegação de compatibilidade com banco ou cliente original decorre daqui.
2. **Transação só existe no arquivo depois do marcador.** As operações ficam em memória; o
   `TX_COMMIT` é o que as torna visíveis para quem reabrir. Operação única sem transação explícita é
   o próprio commit (um registro válido).
3. **Rollback é remoção física, e número de transação não se repete.** A varredura devolve o fim do
   último registro confirmado e o arquivo é truncado ali (na abertura e no `estado_rebuild()`); o
   maior `tx` visto no arquivo vira o piso do próximo.

**Motivo (medido, não hipotético).** A primeira versão descartava os registros sem commit só em
memória e reiniciava a numeração de TX em 1 a cada abertura. O teste de **morte real** de processo
(`MU2DB_TESTE_ABORTA_APOS`, gancho de teste em `src/db.c`) mostrou a consequência: uma transferência
nova, também `tx=1`, fez a varredura reaplicar o `remove` da transação abandonada junto com a nova, e
o arquivo ficou ilegível (`abrir: varredura: formato invalido`). Depois da correção: morte no ponto 1
e no ponto 2 deixam o item na origem, `descartados=1` na primeira abertura, `0` na segunda, arquivo
de volta **ao tamanho exato** de antes do corte e `verify` aprovando. Evidência:
`reports/r11-persistencia.md`; regressão: `tests/dbctl.sh` casos 19–31.

**Por que não "simular corte truncando o arquivo", como o teste fazia antes.** Truncar testa o que
*nós* escrevemos. A morte do processo testa o que o sistema operacional já tinha em disco — e foi
exatamente aí que o defeito apareceu, nas duas primeiras versões.

**Limite declarado.** Concorrência de dois processos **escrevendo** ao mesmo tempo não está coberta
(o teste cobre o conflito de trava); não há migração de dados de produção porque não existe dado de
produção legítimo neste ambiente; e nada disso é o banco do original.

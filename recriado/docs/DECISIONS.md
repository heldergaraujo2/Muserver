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

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

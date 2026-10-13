# CHANGELOG do v2

## Ritual R-2: snapshot regravado, e as duas corridas completas medidas — 2026-10-13

- **A etapa `persistencia` acusou o bundle velho com número:** `divergencia de conteudo dentro do
  declarado FALHA` (16 arquivos fora da lista declarada) e `arquivos fora do snapshot sao declarados
  FALHA extras=7 declarados=0` — o bundle era da rodada da consolidação e não tinha `db.c`, `db.h`,
  `mu2dbctl.c`, `db_test.c`, `dbctl.sh`, `matriz.sh` nem o relatório da R-11. Regravado:
  `git commit-tree HEAD:recriado` → `mu2-snapshot` @ `cf0c09a1bbd914f23adbbe095aa30bce0ada9a84` →
  bundle **366 445 bytes, 103 arquivos**, sha256 `a0fe917e429945bc…`, tudo no `MANIFEST.md`.
- **`bash scripts/verify-backup.sh` → 11/11**; **`FULL=1 …` → 15/15**, incluindo
  `publicado: bundle byte a byte OK remoto=a0fe917e… local=a0fe917e…` e
  `publicado: HEAD local esta no remoto OK b2ffadd` (o bundle foi conferido **dentro do clone do
  remoto**, não no worktree).
- **`make -s gate-full` na árvore limpa: PASS=22, FAIL=0, BLOCKED=4, SKIPPED=0, 502 asserções, 26
  etapas, exit 0 (694 850 ms).** `net-matrix`, `matriz-artefatos` e `persistencia` passam **na mesma
  passada** — o defeito A2 está fechado com medição, não com promessa. `persistencia` sai de
  `nao_testado`.
- **A 4ª `BLOCKED` é o `bench`, e é honesto:** depois de 11 minutos de matriz de rede o host fica
  carregado, o drift medido foi **31,1% > 25%** (o critério foi declarado antes de rodar) e o
  validador recusou o número — `blocked=1`, 15/15 asserções, 0 falhas. No portão padrão, em host
  ocioso, a mesma etapa é `PASS` 15/15 sem perdas. Número de host carregado não vira baseline.
- **Dois defeitos de processo desta rodada, registrados porque a lição vale mais que o verde:** editar
  `tests/run_all.sh` durante uma corrida matou o portão em `syntax error` **depois de 11 minutos**
  (bash lê script por deslocamento em bytes); e o `matriz.sh` apagava `out/net-matrix/`, destruindo o
  artefato que a etapa `net-matrix` tinha acabado de produzir. Os dois viraram regra no
  `CONTINUITY.md` §9 e caso de teste no `matriz.sh` (12/12).

## R-11 — persistência própria do v2 (contas, personagens, inventário, transações) — 2026-10-13

- **O que existe agora:** `include/mu2/db.h` (148 linhas) + `src/db.c` (1590), arquivo append-only
  `MU2DB01` com CRC32C por registro, 13 tipos, transações com `TX_COMMIT`, PBKDF2-HMAC-SHA256 local,
  `flock`, `schema_version` e migração, limites explícitos (4096 contas/personagens, 16 384 itens, 64
  slots, 5 personagens por conta). **Não é e não tenta ser o banco do original** (D2-40).
- **CLI de operação:** `tools/mu2dbctl.c` (221 linhas), que é **segundo consumidor da mesma API** —
  defeito de contrato aparece nos dois. Não abre porta, não fala rede, não toca em `MuServer/`.
- **Testes:** `tests/db_test.c` (**99 asserções**, `# db=99 falhas=0`) e `tests/dbctl.sh` (**31
  asserções**, `# dbctl=31 falhas=0 blocked=0`), ambos agora etapas do portão (`make -s db`,
  `make -s dbctl`, alvos novos no `Makefile`). Vetores conhecidos conferidos: FIPS 180-4 (SHA-256),
  RFC 7914 (PBKDF2 c=1 e c=2), RFC 3720 (CRC32C).
- **Três defeitos reais encontrados e corrigidos — o terceiro só apareceu no teste de morte real:**
  1. `TX_COMMIT` gravava `len=4` com payload de 8 B: o CRC do marcador de commit nunca conferia na
     volta (sintoma: `CRC divergente no registro 1 (offset 161)`);
  2. operação gravada com **payload zerado** (composto temporário sem `memcpy`) → `varredura: formato
     invalido` ao reabrir;
  3. **`rollback` que não removia nada:** os registros sem commit ficavam no arquivo e o número da
     transação recomeçava em 1 a cada abertura, então uma transação nova fazia a varredura
     **reaplicar registros abandonados** — o arquivo virava ilegível. Correção: truncagem no último
     registro confirmado (`trunca_ate()`, usada na abertura **e** no `estado_rebuild()`) e numeração
     monotônica de TX derivada do arquivo (D2-40).
- **Gancho de teste, declarado:** `MU2DB_TESTE_ABORTA_APOS=<n>` mata o processo com `_exit()` depois
  do n-ésimo registro gravado, sem `atexit`/`fflush`. Desligado por padrão; existe porque truncar o
  arquivo testa o que *nós* escrevemos, não o que o sistema operacional tinha em disco.
- **Medição do reparo, no mesmo cenário de antes:** item continua na origem, destino não recebe nada,
  `verify` aprova, `descartados=1` na primeira abertura e `0` na segunda, e o arquivo volta ao
  **tamanho exato** de antes do corte. Relatório: `reports/r11-persistencia.md`.

## Fase A — os artefatos do portão passam a dizer a verdade (A1/A2/A4) — 2026-10-13

- **A1 — `ref_check.sh` com BLOCKED nomeado.** Clone raso quebrava os casos 7–8 (integridade do
  pacote) e o script acabava em falha sem causa. Agora o objeto do upload é conferido com
  `git cat-file -e`: se falta, os casos ficam **BLOCKED com motivo** e o resumo sai
  `# ref-intacta=6 falhas=0 blocked=2` (exit 0, sem `not ok`); conteúdo divergente com objeto
  presente continua **FAIL**. Medido: repo real 8/0/0; raso 6/0/2.
- **A2 — fim da corrida entre `net-matrix` e `persistencia`.** `net-matrix` regravava
  `reports/net-*.tsv` e derrubava a etapa seguinte, que exige árvore limpa: com `GATE_FULL=1` o
  portão ficava vermelho por artefato, não por código. Agora os TSV vão para `out/net-matrix` e a
  publicação é explícita (`net-matrix-publish`); a etapa nova `matriz-artefatos` (10 asserções)
  guarda a regressão — inclusive que nenhuma regravação acontece por acidente.
- **A3/pendente —** regressão estática dos 6 `.lua` patcheados: ainda não feita (próxima tarefa).
- **A4 — `serve-docs.py` com lista explícita.** O servidor de documentos passa a servir **30 caminhos
  `.md` declarados um por um** (antes: glob), resolve por dicionário exato (nunca montando caminho a
  partir da URL), sanitiza HTML e responde 405 a POST/PUT/DELETE/PATCH/OPTIONS. Teste novo
  `workspace/tests/test_serve_docs.py` com **35 asserções**, incluindo 9 negativos 404 (`.tsv`,
  `PSGG.ini`, `.bak`, `../`, documento novo não aprovado) e "sem `X-Frame-Options`".
- **Achado da rodada:** o `Makefile` documentava `FULL=1` para ligar as etapas opt-in, mas o portão lê
  **`GATE_FULL`** (`FULL=1` é do `scripts/verify-backup.sh`). Ou seja: quem seguia a documentação
  rodava com `net-matrix` e `persistencia` **SKIPPED**, e o verde não cobria o que se queria testar.
  Alvo novo `gate-full` (`make -s gate-full` → `GATE_FULL=1 bash tests/run_all.sh`); a documentação
  passou a citar o alvo, não a variável.

## Etapa `enc` — cifragem dos scripts Lua do cliente: estrutura medida, algoritmo `BLOCKED` — 2026-10-13

- **Resultado honesto: o algoritmo NÃO foi identificado.** A etapa fecha com o que a medição sustenta
  e com o bloqueio nomeado: `F23` **`BLOCKED`** (exige decodificador) e **`blocked=2`** na etapa nova.
  Nenhuma afirmação de decifração nem de compatibilidade com o cliente original.
- **Fatos medidos** (13 pares, 21 931 posições; relatório em `../reports/enc-cifragem-lua.md`): 4 pares
  são **byte-idênticos** (não foram cifrados); os 9 cifrados começam com o cabeçalho fixo de 8 bytes
  `28aa2191a6dd35f7`; `len(cif) − 8 == len(claro) + nº de LF` em 9/9 (sem padding); a cifragem é
  **determinística**; e `(A[j], C[j-1..j-3]) → C[j]` fecha com **0 discordâncias em 2 510 repetições**
  (0/890 entre arquivos; com 2 bytes a mesma janela acusa 952/4 403 — 3 é o menor tamanho que fecha).
- **Famílias refutadas, com número:** XOR/ADD de chave repetida (0 chaves com período ≤ 512; a melhor,
  k=224, acerta 16,50% no prefixo e 7,09% no corpus), ECB (`gcd(payloads)=1`; 8/9 não múltiplos de 8
  nem de 16), tabela de 1 byte por 6 índices de `(A,S1,S2,S3)` (melhor caso erra 90,74%/90,50%), ARX
  com rotações 0..3 (0 sobreviventes em 16 384 combinações), afim sobre GF(2) (sistema inconsistente
  nas 400 primeiras amostras, nos 8 bits de saída) e afim em Z/256 (`LSB(C)=LSB(A)` em 54,47%).
- **Por que não fecha:** a função da janela tem domínio 2³² contra 21 931 amostras (quase todas em
  contextos distintos). O `.pdb` traz os nomes (`gFileProtectLuaXorTable`, `gFileProtectLuaHeader`,
  `CFileLuaProtect::EncryptFileA`, `EncryptLua1/2`), mas o `.exe` é protegido por Themida: a seção
  `.themida` termina exatamente no fim do arquivo e o magic do cabeçalho **não existe** no binário —
  extração estática inviável, e executar binário do cliente é vedado pela regra do projeto.
- **Implementado:** `tools/enc_probe.py` (probe somente-leitura, TSV determinístico em < 1 s),
  `tests/lua-enc.sh` (**27 asserções**, `blocked=2`), etapa `lua-enc` registrada no portão (22 → **23
  etapas**), `reports/enc-probe.tsv` (evidência versionada, sha256 `17b7da13…`) e
  `../reports/enc-cifragem-lua.md`.
- **Portão desta rodada:** **18 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 23 etapas,
  exit 0** (69 816 ms). A linha `assercoes=339` do resumo conta só etapas PASS/FAIL (regra do próprio
  portão); somando todas as etapas, incluindo as 27 da nova, são **391**. Nenhum FAIL novo.
- **A pasta publicada `MuserverRecriado/` não foi tocada:** é o snapshot da rodada anterior e o
  validador dela (`scripts/verify-backup.sh`, verde: `ok=11 falhas=0 blocked=0`) só admite arquivos
  novos que casem com padrões declarados. Levar esta etapa para lá exige uma **rodada de publicação
  nova** (o que ela precisa está listado em `NEXT_TASK.md`).

## Publicação dentro do monorepo — 2026-10-13

- **O projeto recriado passou a ser publicado em `MuserverRecriado/`**, na raiz deste monorepo,
  porque a escrita no repositório separado `heldergaraujo2/MuserverRecriado` continua respondendo
  `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2` (seleção de
  repositórios da instalação do GitHub App). Nenhuma permissão foi contornada e **nada foi publicado
  no repositório separado** — ele segue vazio. Commit da publicação: `a6ddf81`.
- **Fonte: o artefato validado da migração**, não uma reconstrução improvisada. Ele foi reproduzido de
  novo pelo caminho determinístico (`bash workspace/migracao/preparar-destino.sh … --gate` →
  `ok=6/falhas=0`) nos valores que as constantes fixam: HEAD `51b2b157`, árvore `99c9b8ff`,
  **42 commits**, 174 arquivos, bundle do snapshot 662 628 B sha256 `76d71bd8…`, ponta `f42769f1`.
- **A pasta recebeu os 174 arquivos rastreados do artefato** (sem `.git` embutido e sem `out/`),
  conferidos **arquivo por arquivo**: modo e blob git **idênticos nos 174** (o `.gitattributes`
  próprio da pasta mantém `* -text` e `*.bundle binary`, então nada é convertido na cópia).
- **Medido na nova localização:** `make -s check` exit 0 (unit 106, make-sintaxe 7, net 34, pe 14,
  data 21); `make -s gate` **18 PASS, 0 FAIL, 2 BLOCKED, 2 SKIPPED, 339 asserções, 22 etapas**,
  exit 0; `make -s gate-selftest` 19/19; `make -s fuzz` 12/12 (150 000 iterações); `ref-intacta`
  PASS 8/8 com a árvore `fade0461…` da referência inalterada. Com a referência irmã `../MuServer`
  disponível, `pe`/`data`/`cfg`/`ref-intacta` rodam em vez de sair BLOCKED — no artefato isolado o
  mesmo portão mede 14 PASS/6 BLOCKED/281 asserções.
- **Diferenças intencionais vs artefato (9 arquivos, todas documentais):** `README.md` ganhou a seção
  de localização (propósito, como testar, o que não foi incluído, como diferenciar de `MuServer/`), e
  os 7 documentos canônicos mais o relatório de migração ajustaram a localização. O verificador do
  projeto declara essas divergências (`DIV_OK`).
- **`MuServer/` e o restante do monorepo não foram tocados**; `git status` fora da pasta seguiu limpo.

## Fechamento da publicação — 2026-10-12

- **Defasagens numéricas corrigidas na origem** (o portão mede, não relata): `check` 180→**182**
  asserções, `gate` 336→**339**, `seguranca` 12→**13**, `admin` 22→**24**, `ref-intacta` 6→**8**
  casos. As contagens antigas sobreviviam em `README`, `CONTINUITY`, `CURRENT_STATE`, `NEXT_TASK` e
  `ROADMAP`, e foram refeitas em execução limpa (`out/` vazio).
- **Quinto defeito, medido no destino validado:** a linha de base do teste de descritores
  (`tests/seguranca.sh` × `tools/malform_probe.py`) era uma **leitura solta** logo depois da bateria
  de malformações, e o close assíncrono do servidor ainda estava em voo: 1 de 10 execuções leu
  `fd_antes=9` com piso real 8 (as 10 estabilizaram em 8), e o caso falhava por corrida, não por
  vazamento. A base passou a ser o **piso observado numa janela curta**; a asserção
  (`base == estabilizado == 2ª rodada`) continua estrita e um vazamento real ainda falha.
- **Destino reconstruído do zero** com `workspace/migracao/adaptar-destino.py` sobre o split de
  **39 commits** do histórico do v2 (mensagens preservadas), com a evidência `workspace/` e a
  adaptação de caminhos; conferido por portão (`14 PASS/0 FAIL/6 BLOCKED/2 SKIPPED`, 281 asserções),
  `make -s check`, `gate-selftest` 19/19, `fuzz` 12/12, clone independente e restauração do próprio
  bundle. Construções independentes deram o mesmo HEAD, a mesma árvore e o mesmo sha256 de bundle
  (valores no `MANIFEST.md` do destino).
- **Publicação tentada de novo e ainda bloqueada por permissão**: `git push` →
  `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`. Nada foi
  publicado; a ação é do proprietário (incluir o destino na instalação do GitHub App, *Contents:
  Read and write*). Sem contorno e sem retentativa em laço.
- **Cópia independente do monorepo regravada** (`workspace/backups/mu2-v2.bundle`, snapshot orphan da
  árvore `recriado/` com 83 arquivos) e conferida por `FULL=1 verify-backup.sh` 15/15.

## Publicação no `MuserverRecriado` — 2026-10-12

- **Destino preparado e conferido; publicação BLOQUEADA por permissão.** `git push` para
  `heldergaraujo2/MuserverRecriado.git` → `403 Permission to heldergaraujo2/MuserverRecriado.git
  denied to heldergaraujo2`, e a API responde `Resource not accessible by integration` **no destino**
  (no repositório de origem responde normalmente). A ACL do usuário diz `push=true` nos dois: o que
  falta é a **instalação do GitHub App** incluir o destino com *Contents: Read and write*. Sem
  contorno, sem force push, sem retentativa em laço.
- **Histórico preservado** por `git subtree split --prefix=recriado`: os commits do v2 com as
  mensagens originais (contagem e ponta de cada rodada no relatório de migração do destino). O
  destino nasce de `git init` + `git fetch file://…` (não de `git clone`, que levaria o pack de
  134 MB com os blobs de `MuServer/` para dentro de um repositório que não deve carregá-los).
- **A migração deixou de ser um patch pinado na base.** Com o histórico avançado, o patch deixou de
  aplicar; a adaptação passou a ser `workspace/migracao/adaptar-destino.py`, com asserção por
  substituição — texto de origem fora do lugar FALHA nomeando a substituição, em vez de aplicar
  torto ou em silêncio. Os trechos substituídos (os *assets*) ficam em `workspace/migracao/`.
- **Build bit-reprodutível**: as construções independentes desta rodada deram o mesmo HEAD, a mesma
  árvore e o mesmo sha256 de bundle — valores vigentes no `MANIFEST.md` do backup
  (`workspace/backups/`, dentro do destino).
- **Portão no destino**: `PASS=14 FAIL=0 BLOCKED=6 NOT_IMPLEMENTED=0 SKIPPED=2`, 281 asserções,
  exit 0 — as 6 BLOCKED são exatamente as etapas que exigem a referência `MuServer/` (`pe`, `data`,
  `cfg`, `ref-intacta`, `interop`, `lua`). No monorepo de origem: 18 PASS / 2 BLOCKED / 339
  asserções, exit 0. `bench` julga por critério de drift declarado e pode reportar BLOCKED por
  ambiente sob carga (medido: 13 PASS/7 BLOCKED numa execução logo após o build).
- **Quatro defeitos medidos e corrigidos** (aparecem quando se roda o portão num ambiente
  reprovisionado, com `out/` vazio — o estado anterior os mascarava): a sonda de malformação media o
  processo errado; a asserção de descritores era corrida (imediato 9,9,8,8,8 / estabilizado 8 em
  0–20 ms); `tests/admin.sh` dependia de `out/gate.tsv` residual; e a etapa `build` do portão exigia
  o **próprio produto** (`out/wire.o`), virando `NOT_IMPLEMENTED` em clone limpo — a rodada
  degradava para PASS=10/BLOCKED=9 **sem falhar**.
- Medidas: a primeira rodada fica em `reports/migracao-destino.tsv` (histórico, não reescrito); a
  rodada vigente, no `MANIFEST.md` do backup e em
  `docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`.

## R-7 — 2026-10-12
- **Baseline exploratória** (não é critério de aceitação: não existe requisito de desempenho do
  dono). `tests/bench.sh` com 5 cenários e critérios de validade declarados antes de rodar
  (5 repetições, 1ª descartada, drift máximo 25 %), julgados por `tools/bench_check.py` —
  separado de quem mede: drift acima ⇒ `BLOCKED` por ambiente; perda de quadro ⇒ falha real.
- **Números** (`reports/r7-baseline.tsv`): B1 1 conexão ≈ **215 000 quadros/s** (20 000/20 000 em
  5 de 5); B2 8 conexões ≈ **250 000 quadros/s** agregados — **não** é 8×, quem limita são as
  2 vCPUs; B3 latência **p50 39,5 / p95 60,7 / p99 75,3 µs** (limite superior: inclui o cliente
  Python); B4 corpo 64 vs 2048 **não separável** com este cliente (49,7 vs 55,7 µs);
  B5 **limite**: 551 quadros de 2048 B antes de `close=queue_full`, com resposta parcial
  (`out=684/2052`), cliente vendo o FIN e serviço sobrevivendo.
- **Defeito real corrigido (D2-28)**: `netclient` somava o *timeout* do `poll` ao contador de
  prazo, então desistia após ~600 leituras e o serviço registrava `close=write_error` — o harness
  **fabricava perda do serviço** (3 de 5 repetições com 1 371/1 311/1 238 de 2 000 quadros).
  Relógio monotônico nos dois laços; depois, 5/5 e `rejects=0`.
- **Método corrigido (D2-27)**: janela de 2 000 quadros (~20 ms) deu drift de **40,4 %**; o que se
  corrigiu foi a janela (20 000 quadros ⇒ 4,3–17,2 %), **não** o limite declarado de 25 %.
- **Teste intermitente corrigido (D2-29)**: B5 falhava 1 em 15 porque apostava em corrida; com
  `--rcvbuf 1024` fixado, 8/8 e depois 15/15. Era o que fazia o caso 13 do `gate-selftest` falhar.
- **Falsificações**: **F18** (validador sem o critério de drift deixa passar drift de 300 %) e
  **F19** (contabilidade exata: o quadro STATS conta no `frames` — B1 `100 001 = 100 000 + 1`),
  ambas permanentes no portão.
- Etapa `bench` entrou no portão **removendo o placeholder no mesmo ato** (guarda de duplicação).
  Portão: **14 PASS, 0 FAIL, 0 BLOCKED, 3 NOT_IMPLEMENTED, 2 SKIPPED, 244 asserções, 32,6 s**;
  `gate-selftest` 19/19.

## R-6 — 2026-10-12
- **Camada 1 (conformidade interna do v2) comprovada**: `tests/conform.sh` com 15 cláusulas
  C-01…C-15 verificadas byte a byte por `tools/wire_probe.py` (quadros inválidos incluídos):
  limite 2048, rejeição por `size`, little-endian, opcode desconhecido sem derrubar conexão,
  fragmentação, D2-17, formato da linha STATS, equivalência `orig`/`mur0`. 15/15.
- **Camada 2 (compatibilidade observada)**: `tools/cfg_probe.py` mede 19 `.ini`, 655 pares,
  endpoints 44406/55557 (ConnectServer), 55960, 55970, 55990, 55998, 55999, 1433; **cliente
  aponta 44405 enquanto o ConnectServer escuta 44406** — divergência registrada como hipótese.
- **Camada 3 (interop)**: **BLOCKED** — exige binário original em execução; `interop` continua
  `NOT_IMPLEMENTED` no portão, nunca `PASS`.
- **Segurança**: 26 valores sensíveis em claro no pacote original; `cfg_probe.py` redige por nome
  de chave **e** por forma do valor, e `tests/cfg.sh` (15 casos) cobra a redação. Nenhum segredo
  em arquivo versionado (conferido: 0 linhas não redigidas). Decisão D2-25.
- **Matriz de evidências** `reports/r6-matriz.tsv` (12 linhas × 9 colunas), validada no portão por
  `tools/matrix_check.py`: linha sem comando reproduzível ⇒ falha.
- **Defeito real**: etapa `conform` criada sem remover o placeholder fez a mesa imprimi-la duas
  vezes e contar asserções em dobro (244 vs 229). Corrigido + guarda de duplicação (exit 2) e
  invariantes no lugar de totais exatos no `gate-selftest`. Decisão D2-26.
- Portão: **13 PASS, 0 FAIL, 4 NOT_IMPLEMENTED, 2 SKIPPED, 229 asserções**; `gate-selftest` 19/19.

## R-8 — 2026-10-12
- **Portão único** `tests/run_all.sh`: 16 etapas em ordem determinística, cinco estados
  (`PASS`/`FAIL`/`BLOCKED`/`NOT_IMPLEMENTED`/`SKIPPED`), mesa legível + TSV, log por etapa,
  exit ≠ 0 somente com `FAIL`. Resultado real: **9 PASS, 0 FAIL, 5 NOT_IMPLEMENTED, 2 SKIPPED,
  194 asserções, 19,7 s**.
- **`tests/gate_state.sh`** — 18 casos sobre o próprio portão (estados, timeout sem órfão,
  SIGTERM → 130, cwd `/` e caminho com espaço, relatório pré-existente, repetibilidade,
  referência ausente, resumo ausente, suíte que morre no fim) + F12/F13/F14. **18/18, exit 0**.
- **`tests/ref_check.sh`** — integridade de `MuServer/` medida de dentro do portão (árvore git,
  ausência de alterações e de untracked, contagem, e âncoras de conteúdo de 4 PE lidas de
  `reports/r5-pe.tsv`): 6/6.
- Alvos `make gate` e `make gate-selftest`; `gate` não entra em `check` (sem recursão).
- **Defeito real achado e corrigido:** o watchdog de fundo da primeira versão sobrevivia à etapa
  (`build.timeout` 600 s depois, `sleep 420` órfão com `PPID 1`), bloqueava a corrida e podia
  sinalizar grupo alheio — substituído por `timeout(1)` + grupo próprio (`set -m`). Decisão D2-24.
- `pe`/`data` passam a distinguir `escopo=selftest` de `blocked=1` (D2-22).
- Decisões D2-22, D2-23, D2-24. Evidências `reports/r8-gate.tsv`, `r8-gate-state.tsv`,
  `r8-relatorio.md`.

## R-5 — 2026-10-12
- **Sondas de formato** em `tools/` (D2-19): `pe_probe.py` (parser PE próprio: DOS/NT/COFF/optional,
  seções, entropia, imports, `--keywords`), `att_probe.py`, `mb_probe.py`, `data_probe.py`. Python
  3.11 só com stdlib, somente leitura sobre `MU_REF_DATA`, saída TSV determinística e sem caminho
  absoluto do host.
- **Suítes novas:** `tests/pe.sh` (14 casos) e `tests/data.sh` (19 casos), cada uma com invariantes
  medidos + recusa de entrada inválida + autos-teste; modo `SELFTEST_ONLY=1` roda sem a referência
  e declara `blocked=1`. Alvos `pe`, `data`, `pe-selftest`, `data-selftest`; `check` agora é
  `unit make-sintaxe net pe data` → **180 asserções, 0 falhas, 19,4 s**.
- **Medidas publicadas:** `reports/r5-pe.tsv`, `r5-formatos-att.tsv`, `r5-formatos-modelo.tsv`,
  `r5-dados.tsv` e o relatório `r5-relatorio.md` (observação × hipótese × conclusão × limitação).
- **Falsificações F8–F11** (sonda fingindo conformidade, aceitando não-PE, vazando caminho
  absoluto, perdendo determinismo): todas detectadas com exit ≠ 0 e revertidas com sha256 conferido.
- **Decisões novas:** D2-19, D2-20, D2-21.
- **Correção de documentação:** a auditoria da R-3 registrava "3 `.enc`"; mediu-se **0 arquivos
  `.enc`** — eram 3 *matches* de `*luaenc*`, hoje 2 (`LuaEncryptorTool.exe` + `.pdb`).
- **Nada alterado em `MuServer/`** (árvore `fade04615fab`, 10 021 arquivos, somente leitura).

## R-0/R-1/R-2 — 2026-10-12
- Aberta a arvore `recriado/` (v2) dentro do repositorio rastreado da sessao, com
  `.gitignore` proprio, `reports/README.md` (regra de extensao por causa dos padroes de
  ignore do hospedeiro) e os docs `README`, `CURRENT_STATE`, `NEXT_TASK`, `DECISIONS`
  (D2-01..D2-10), `ENVIRONMENT`.
- Tentativa de recuperacao do v1 encerrada com veredito (Etapa 1): nenhum mecanismo
  autorizado disponivel do sandbox; solicitacao pronta em
  `../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`.
- Permissao do GitHub diagnosticada com discriminador de API + `push --dry-run` (nenhum
  ref criado): o App de autenticacao **nao tem** `MuserverRecriado` na selecao de
  repositorios. Instrucao manual em `NEXT_TASK.md` secao "acao do dono".
- Ambiente medido (`docs/ENVIRONMENT.md`): sem clang ⇒ sem libFuzzer; sem
  valgrind/gdb/strace/perf/file; ASAN+UBSAN e hardening compilam; 2 vCPUs/4 GiB ⇒ limiar de
  drift do `bench` a recalibrar; `MU_REF_DATA` presente e conferido.
- Mecanismo de backup independente criado: `scripts/verify-backup.sh` + `backup/`
  (bundle limitado a `recriado/**` + `MANIFEST.md` com SHA-256), com teste de restauracao
  por clone a partir do bundle. Nada de `src/` ainda: **nenhum teste de C foi executado**,
  e nenhuma suíte do v1 deve ser considerada reproduzida.

### R-0, fechamento da rodada (mesma data)
- Backup independente gravado e **conferido por restauracao real**: `backup/mu2-v2.bundle`
  (17 225 B, historia do `recriado/**` via subtree split, ponta `17f4f79`) + `backup/MANIFEST.md`
  com SHA-256. `scripts/verify-backup.sh`: 6 verificacoes, todas verdes depois do commit.
- Defeito encontrado pelo proprio verificador: o `git clone` do bundle sem `-b mu2-v2` nascia com
  HEAD para um `main` inexistente (checkout vazio + warning ignorado). Corrigido no script e no
  MANIFEST. Fica registrado porque e o tipo de bug que so aparece quando se testa restaurar.
- Publicacao conferida de volta: `origin/arena/cf1de8ce-muserver` == HEAD local (`git ls-remote`).
  Nenhuma ref extra publicada; `mu2-v2` e branch local de trabalho do backup.
- Etapa 2 com causa exata: `collaborators/.../permission` responde 200 em `Muserver` e
  `403 Resource not accessible by integration` em `MuserverRecriado` para o mesmo token
  autenticado como o dono => selecao de repositorios do App, nao scope. Sonda de escrita
  nao mutante (`push --dry-run`): 403. Nenhum ref criado no repo de desenvolvimento.

## R-3 — 2026-10-12 (enquadramento, codec, Makefile, suíte unitária)
- `include/mu2/mu2.h` + `src/wire.c`: quadro `code(2,LE) | size(2,LE) | corpo`, `MU2_MAX_BODY`
  2048, `MU2_MAX_FRAME` 2052, dois perfis (`orig` cru, `mur0` involutivo), erros distintos por
  causa (`E_ARG`/`E_SIZE`/`E_DST_SMALL`/`E_INCOMPLETE` com `needed`/`E_BAD_LEN`/`E_PROFILE`).
  Layout e decisao do v2 (D2-11), nao compatibilidade afirmada com o `ConnectServer.exe`.
- `Makefile` com ASAN+UBSAN e `-Werror` por padrao; saidas em `out/` (D2-13); `tests/make_parse.sh`.
- `tests/unit.c`: **106 assercoes, 0 falhas** (`reports/r3-unit.tsv`). Contagem desta arvore; o
  `unit=82` do v1 e [alvo] historico e nao foi usado como criterio de nada.
- Falsificacoes executadas (`reports/r3-falsificacao.tsv`): F1 troca de campos do cabecalho →
  45 falhas; F2 validacao de `size` afrouxada → 2 falhas; F3 `mur0` neutralizado → 18 falhas;
  F4 `-Werror` removido do portao → `make-sintaxe` 2 falhas. Reversao conferida com
  `git status --porcelain` vazio em `recriado/{src,tests,include,Makefile}`.
- Dois defeitos de teste encontrados pelo proprio processo desta fase e corrigidos antes do commit:
  (a) caso 4 do `make_parse` dependia do estado de `out/` (flaky) → `make -B -n`; (b) o alvo
  `.PHONY build` colidia com o diretorio `build/` e o `make` descartava dependencia em silencio →
  diretorio virou `out/`.
- Suítes que ainda **nao existem** no v2 (registradas como ausentes, nao como aprovadas): `e2e`,
  `net`, `golden`, `interop`, `conform`, `data`, `fuzz`, `pe`, `bench`, `gate_state` e o
  `scripts/run_all.sh`. Sem laço de rede sem fio: nada do contrato de backpressure foi exercitado
  ainda; isso e a R-4.

### R-3, fechamento com a copia independente consertada por medida
- Realocar o bundle para `workspace/backups/` e troca-lo por snapshot orphan (`git commit-tree
  HEAD:recriado`): 134 694 → 31 771 bytes, e custo constante (a arvore do snapshot nao contem o
  proprio bundle). Registrado como D2-15.
- Defeito grave encontrado ao conferir o blob publicado, nao o do worktree: o `* text=auto` do
  `.gitattributes` da raiz aplicava `text: set` ao `*.bundle`, e o bundle **comitado** nao batia com
  o arquivo em disco (`be79f094… != 1ec952bd…`) — restauracao por clone daria arquivo corrompido.
  Corrigido com `workspace/backups/.gitattributes` (`*.bundle binary`).
- `verify-backup.sh` ganhou modo `FULL=1`: clona a branch **publicada** e la dentro confere bundle
  byte a byte, `git bundle verify`, restauracao da arvore a partir do bundle clonado e presenca do
  HEAD local no remoto. Resultado apos o fix: **10 verificacoes, 0 falhas**.
- Portao da fase re-execuido no fim: `unit=106 falhas=0`, `make-sintaxe=5 falhas=0`.

## R-4 — servico de rede `mud2`, controlador `mu2ctl` e suite de rede (medido nesta arvore)
Novos: `src/mud2.c` (585 linhas), `src/mu2ctl.c`, `include/mu2/proto.h`, `tests/netclient.c`,
`tests/net.sh`; `Makefile` com alvos `mud2`/`mu2ctl`/`netclient`/`net`/`net-matrix` e `check` agora
incluindo a suite de rede; `tests/make_parse.sh` com 2 casos novos (7 no total).
Portao: **unit=106 falhas=0**, **make-sintaxe=7 falhas=0**, **net=34 falhas=0** (matriz reduzida),
**net-matrix=36 falhas=0** (100 configuracoes x 5 repeticoes por perfil, 10m12s). ASAN+UBSAN+`-Werror`
em tudo, zero violacao de sanitizador. Detalhes em `reports/r4-check.tsv`.
Falsificacoes (todas detectadas, `reports/r4-falsificacao.tsv`): **F5** `break` no `feed()` → a suite
nao termina em 300 s e >=4 verificacoes caem; **F6** sem `drain()` imediato → 8 falhas; **F7**
`queue_reply` invertido → 3 falhas.
Tres defeitos achados durante a subida e corrigidos antes de fechar: (1) `mu2_frame_body` recebe o
inicio do quadro, nao o corpo — a linha STATS saia como `S registros=...` (D2-17); (2) `close=queue_full`
saia em dobro, o que dobraria qualquer classificacao por log; (3) `mu2ctl --profile` errado imprimia
lixo com exit 0, porque o perfil nao e detectavel no stream — agora o prefixo `STATS ` e conferido.
Um quarto defeito foi do **processo**, nao do codigo: a reversao da mutacao F6 foi perdida porque o
comando de limpeza usava `pkill -f` com um padrao que casava com a linha de comando do proprio shell
(exit -1, reversao nunca executada). Tres medicoes seguintes foram feitas contra o binario mutado,
detectadas pela contradicao com a matriz, e **refeitas**. Regra nova: matar por PID, nunca por
`pkill -f` com padrao presente no proprio script.
Achados tecnicos: a vaga unica so funciona com `drain()` imediato (F6); com buffers padrao nao houve
perda nem fila cheia em 50/50 configuracoes por perfil; com `--sndbuf 1024` + `SO_RCVBUF 1024` a fila
cheia apareceu em 50/50 e o limite e a janela do cliente (1024 pedido → 2304 efetivo), nao o numero de
quadros — o "~29 respostas de 64 B" do v1 nao se reproduziu (D2-18). Zero fechamentos sem
classificacao e zero perda sem fechamento em 200 corridas.
Ausentes de proposito, como antes: `bench` (BLOCKED), `golden`/`interop`/`conform`/`data`/`pe`/`fuzz`/
`gate_state`/`run_all.sh` (nao implementados). Nenhuma compatibilidade com o cliente original foi
testada ou afirmada.

---

## Rodada das lacunas (2026-10-12) — golden, fuzz, segurança, console, Lua e rastreabilidade

Estado de partida medido: `gate` 14 PASS / 244 asserções; 3 etapas `NOT_IMPLEMENTED`.
Estado final medido: `gate` **18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 336
asserções, 22 etapas, exit 0**; `gate-selftest` 19/19; `check` 180; `FULL=1 verify-backup.sh` 13/13.

**Duas correções de afirmações publicadas** (retratações, com histórico preservado):
1. "0 declarações de framing em `.lua`" (R-6) — medição certa, **conclusão errada** por tokens
   estreitos demais. Medido: 148 `.lua`, 20 com termos de pacote, 8 `ProtocolCore.lua`. D2-31.
2. "MuServer/ intacta" — impreciso: 6 `.lua` dentro de `MuServer/` diferem do upload `6eabb45`
   (commit `b5b84da`). Reversão verificada por blob-idempotência dos baselines. D2-32.

**Unidades entregues:**
- `golden` (42/42): `tools/mu2codec.c` (CLI sobre o `wire.o` real), corpus de 38 vetores
  versionados com cláusula e origem, F20 (1 byte corrompido ⇒ nomeia vetor e offset) e F21 (perfil
  trocado ⇒ falha discriminante).
- `fuzz` (12/12): motor determinístico próprio, 150 000 iterações, 0 violações; F22 (codec mutado
  numa cópia temporária é pego; entrada replayada é recusada no codec real).
- `seguranca` (12/12): 15 casos de malformação **na porta**, serviço vivo em todos; fd estável em
  1 000 ciclos; RSS plano (6 968 kB); higiene de log; decisão sobre TSan registrada (produto
  single-threaded, 0 primitivas).
- `admin` (22/22): console local com desenho prévio, fail closed, papéis, 501 para publicação.
- `lua` (13/13, execução BLOCKED): inventário e evidência estática; `ProtocolCore.lua` com
  `GameServerProtocolRecv(aIndex, Packet, PacketName)`; tipos medidos (Head numérico, PacketName
  string); par cifrado/decifrado em `LuaEncTool/`.
- `interop` (12/12, `blocked=1`): três camadas separadas; evidência nova do `HackPacketCheck.txt`
  (272 entradas, 256 índices 0..255, 8 bits, 37 criptografados) e divergência medida (code de 16 bits
  × 256 índices = fator 256).
- `rc-formatos-auditoria.md`: classificação em assinatura identificada × parcialmente reconhecido ×
  efetivamente decodificado, com a evidência nova da camada XOR-3 (`Data\Item\` no offset 12; 4 de
  56 `.bmd`; maior corrida de NUL = 255 exato).
- `auditoria-rastreabilidade.md`: roadmap inteiro mapeado por requisito × implementação × teste ×
  evidência × estado, com causa, dependência e condição de desbloqueio para cada bloqueio.

**Defeitos corrigidos na raiz** (não escondidos, não contornados): D2-28 (prazo por relógio, não por
iterações), D2-27 (janela de medição), D2-29 e D2-30 (testes que apostavam em corrida — B5 e net S4),
e o bug do próprio console (`mu2_frame_body` devolve bytes, não `MU2_OK`).

**O que não foi afirmado:** nenhuma compatibilidade com binário ou cliente original; nenhum número de
desempenho como requisito de produção; nenhum formato "decodificado" além da camada demonstrada.

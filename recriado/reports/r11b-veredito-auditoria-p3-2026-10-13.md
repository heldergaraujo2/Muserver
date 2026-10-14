# R-11b — auditoria P3: o que a persistência faz de verdade, medido por sequência de syscalls

Data: 2026-10-13 · branch `arena/cf1de8ce-muserver` · alvo auditado: `reports/r11-persistencia.md`
(esse relatório **não** foi sobrescrito; este é o documento que o confronta com medição).

Este relatório existe porque a auditoria P3 pediu três coisas: **medir** o comportamento da R-11 em
vez de lê-lo, separar *demonstrado* de *hipótese*, e não deixar afirmação de documento passar por
prova. Uma delas caiu: o relatório §1 chama de "flock/migração por `schema_version`" o que o código
faz só em parte, e a §5 lista "durabilidade" como coberta **sem qualificar** o caminho da operação
implícita — que, medido, não sincronizava. O defeito foi corrigido e tem regressão.

Nada de `MuServer/` foi lido, copiado ou usado como fixture. Todos os dados são sintéticos
(`jogador1`, `Alfa`, `Beta`, `outro`) e todos os arquivos ficam em diretório temporário.

## 1. Método (e o que ele *não* consegue provar)

| instrumento | o que mede | limite honesto |
|---|---|---|
| `out/mu2dbctl` em processos separados | efeito visível do estado no arquivo | nada |
| `tests/io_trace.c` (novo, `LD_PRELOAD`) | **ordem real** de `pwrite`/`fsync`/`close`, com fd, offset e tamanho | observa syscalls, não o conteúdo da página suja |
| arquivos forjados byte a byte | corrida com corrupção e com versão de schema não suportada | o CRC32C tem de ser recalculado à mão |
| `kill` real no meio de TX (`MU2DB_TESTE_ABORTA_APOS`, exit 97) | estado após morte de processo | não simula queda de energia do host |

Consequência declarada: **conteúdo de arquivo não distingue "sincronizado" de "ainda no page
cache"** — qualquer leitura acha a página suja. E `strace` não existe neste ambiente. Por isso a
garra de durabilidade só pôde ser medida por interposição de `fsync` (contra: o binário é
construído com ASan, e o runtime do ASan precisa vir primeiro — daí `ASAN_OPTIONS=verify_asan_link_order=0`
na receita; sem ela o processo morre antes de rodar, e o teste trata isso como BLOCKED, nunca como
aprovação).

**Queda de energia não é reproduzível aqui.** Tudo que este relatório diz sobre durabilidade é
"o `fsync` foi chamado antes de a API voltar", não "o dado sobreviveu a um corte de energia".

## 2. Afirmação × medição

| afirmação do `r11-persistencia.md` | medição desta auditoria | veredito |
|---|---|---|
| §1 "`flock`" | segundo escritor durante lock exclusivo: `abrir ...: flock: arquivo em uso` (exit 1); depois de liberar, a mesma operação passa | **confirmado** (para escritor) |
| §5 "durabilidade" (sem qualificar) | o commit de TX sincroniza inline; a **operação implícita não sincronizava** — só no `mu2db_fechar()` | **lacuna real** → §3 |
| §1 "migração por `schema_version`" | não há caminho de migração: arquivo com `schema=2` é **recusado** na abertura (`schema 2 mais novo que o suportado (1)`), e `verificar` no **mesmo** arquivo diz `integridade=ok` (exit 0, não confere a versão) | **promessa maior que o código** → §4 |
| §5 "ids derivados da varredura do log" | item novo recebeu `id:3` depois de o `id:1` sair; personagem novo recebeu `id=3` depois de o `id=2` ser apagado | **confirmado** (não reutiliza) |
| §4 "transferência atômica" (morte real de processo) | `exit=97` no meio da TX: `descartados=1` na 1ª abertura, destino com `quantidade=0`, origem preservada, `integridade=ok` | **confirmado** |
| §5 "corrupção detectada por CRC" | 40 bytes → `motivo=arquivo menor que o cabecalho`; CRC do cabeçalho violado → `motivo=CRC do cabecalho divergente` e `verify` → `erro=CRC divergente (corrupcao)` | **confirmado** |
| §5 "limites de conta/personagem/slots" | 8 bordas exatas medidas (tabela abaixo), todas com erro nomeado | **confirmado** |
| §5 "PBKDF2" | senha errada em conta real 110–114 ms × conta inexistente 113–130 ms (3 rodadas) | **confirmado** (trabalho comparável; não há oráculo de tempo grosseiro) |
| §5 "não coberto: concorrência entre dois processos escrevendo" | 536 `verificar` durante rajada de 300 gravações: 0 falhas | **risco menor do que o declarado** — mas `verificar` não toma lock (§4) |

Bordas medidas (aceita / recusa), todas com mensagem própria:

| campo | limite | aceita | recusa |
|---|---|---|---|
| nome de conta | 3..20 | 3, 20 | 2 (`argumento invalido`), 21 (`argumento invalido`) |
| senha | 6..64 | 6, 64 | 5, 65 (`argumento invalido`) |
| classe de personagem | 0..5 | 5 | 6 (`argumento invalido`) |
| slots de inventário (`MU2DB_SLOTS`) | 64 | 64 itens | 65º (`inventario sem slot livre`) |

Nome no limite não é truncado: 20 caracteres entram e voltam iguais (`nome=AbcdefghijKLMNOPqrst`).

## 3. O defeito: durabilidade assimétrica (corrigido nesta auditoria)

**Critério declarado antes da medição:** *toda operação que a API confirma com sucesso tem de
gravar **e** sincronizar antes de voltar; medido por sequência de syscalls.*

Sequência observada em `dar-item` (operação implícita, um processo novo), **antes**:

```
pwrite fd=3 off=287 len=32      <- registro
pwrite fd=3 off=319 len=13      <- payload
pwrite fd=3 off=332 len=32      <- marcador de commit
pwrite fd=3 off=364 len=8
pwrite fd=3 off=0   len=64      <- cabecalho reescrito no fechamento
fsync  fd=3 tamanho=372         <- o UNICO fsync, e ele e do fechar()
close  fd=3
```

`criar-conta` (também implícita) mostra a mesma forma. A TX explícita mostra a forma correta:

```
pwrite ... off=540 len=32 / off=572 len=8
fsync  fd=3 tamanho=580         <- mu2db_tx_commit: sincroniza ANTES de voltar
pwrite fd=3 off=0 len=64
fsync  fd=3 tamanho=580
close  fd=3
```

Isto é, o `fsync` da linha `src/db.c:1077` era do commit de transação, e a operação implícita
dependia do `fsync` do `mu2db_fechar()`. Um servidor que mantém o banco aberto (o caso de uso real)
recebia `MU2DB_OK` de `mu2db_conta_criar`/`dar-item` e, numa queda antes do fechamento, podia perder
o registro confirmado. `git blame` não ajuda aqui: o defeito é de *contrato*, não de digitação.

**Correção** (`src/db.c`, ramo implícito de `registra`): `fsync` inline depois de `grava_ops`.
Falha de `fsync` → `MU2DB_E_IO` **e** `estado_rebuild()` (o arquivo é a fonte de verdade; a memória
volta a refletir o que está lá, e o erro avisa que não há garantia). Depois da correção:

```
pwrite fd=3 off=373 len=32 / off=405 len=13 / off=418 len=32 / off=450 len=8
fsync  fd=3 tamanho=458         <- inline, cobre exatamente o que foi gravado
pwrite fd=3 off=0 len=64
fsync  fd=3 tamanho=458         <- fechamento (fechar continua sincronizando)
close  fd=3
```

**Regressão:** `tests/sincronia.sh` (15 casos, instrumento `tests/io_trace.c`). Ela não olha
conteúdo: afirma a **ordem** — existe `fsync` entre o fim dos registros e a reescrita final do
cabeçalho, com tamanho igual ao fim do último registro; operação implícita tem dois `fsync`
(inline + fechamento); leitura pura não grava registro (nenhum `pwrite` em offset > 0); operação
recusada não deixa rabo. Registrada no portão (`make -s sincronia`, etapa `sincronia`).

**Sensibilidade a mutação (medida):** removendo o `fsync` inline e recompilando,
`# sincronia=15 falhas=2` — falham os casos 3 e 5, exatamente os que afirmam a garra. Restaurando,
`# sincronia=15 falhas=0`.

**Custo, medido:** 10 operações implícitas = **76–78 ms** (processo novo por operação, incluindo o
`fsync` inline). Quem precisar de lote deve usar `mu2db_tx_*`: a sincronização passa a ser uma por
transação, como sempre foi no commit explícito.

## 4. Lacunas que ficam abertas (com o próximo passo escrito)

1. **Migração não existe.** `REG_MIGRACAO` só aparece no `enum` e num `case` da varredura — nunca é
   gravado (varredura de todo o arquivo). Pior: `gravar_cabecalho` grava **sempre
   `MU2DB_SCHEMA_VERSION`** (constante), não `db->schema_version`; no dia em que a versão subir, um
   arquivo antigo seria reescrito com o carimbo novo **sem** migração. Hoje é latente (só existe v1).
   Próximo passo: decidir entre (a) remover a promessa e documentar "versão é aplicada, migração não
   existe" ou (b) implementar `MIGRACAO` de verdade; e trocar a constante por `db->schema_version`.
2. **`verificar` não toma `flock`.** Medido: `verificar` roda com exit 0 enquanto outro processo
   segura o lock exclusivo. Risco residual: falso alarme de corrupção lendo o meio de um commit. Não
   observado em **536 amostras**, mas o risco não foi medido até o fim. Próximo passo candidato:
   `LOCK_SH` no `mu2db_verify`.
3. **Queda de energia** não é testável neste ambiente: a garantia medida é "o `fsync` foi chamado
   antes de a API voltar".
4. **Paridade de publicação pendente:** `MuserverRecriado/` (snapshot publicado em 2026-10-12/13) já
   estava sem `enc-cifragem-lua.md`, `enc-probe.tsv` e com `reports/` divergente *antes* desta
   auditoria; este relatório aumenta a divergência em um arquivo. Republicar é ato separado, com
   autorização — não foi feito aqui, e nada foi movido para o repositório separado (que segue 403).

## 4.1 Estado destas pendências depois da rodada P4 (2026-10-13)

- **Pendência 1 (migração)** — fechada **por decisão**, não por implementação: `schema_version` é a
  versão do formato, migração automática não existe nem é declarada, versão antiga é recusada nomeada
  (fail closed nas duas pontas) e `gravar_cabecalho` grava a versão carregada. Detalhes e o que ficou
  **sem** teste: `reports/r11c-schema-e-lock-2026-10-13.md` §1.
- **Pendência 2 (`verify` sem lock)** — fechada: `LOCK_SH|LOCK_NB`, recusa nomeada com escritor ativo,
  liberação em todo caminho de saída; medido que o `LOCK_NB` é necessário (com lock bloqueante a suíte
  trava: `exit 124`). Custo declarado: verificação e escrita se excluem.
- **Pendência 3 (queda de energia)** — continua sendo limite de ambiente, com a mesma redação.
- **Pendência 4 (paridade de publicação)** — continua aberta por decisão: `MuserverRecriado/` não foi
  tocada nesta rodada; o snapshot do monorepo (`workspace/backups/mu2-v2.bundle`) foi regravado.

## 5. Achados de teste (não do produto)

1. **Acoplamento em `tests/admin.sh`.** A etapa `admin` falhou nesta rodada com
   `not ok 24 - mud2 e mu2admin intactos no git: nenhuma alteracao em src/ nem em include/` — porque
   `git diff --quiet -- src include` acusa **qualquer** edição pendente em `src/`, inclusive de outro
   subsistema (era `src/db.c`, mudado pela R-11). O invariante que o texto promete é "o console não
   exigiu alterar o serviço". Substituído por lista **explícita** dos arquivos de contrato
   (`src/mud2.c`, `src/wire.c`, `include/mu2/mu2.h`, `include/mu2/proto.h`) + caso novo de "nenhum
   arquivo não rastreado em `src/`/`include/`". `admin` passou de 24 para **25 casos**, todos verdes.
2. **Receita presa no alvo errado (defeito meu, do commit A3).** Ao criar `regressao-lua`, duas
   linhas do `net-matrix-publish` (o aviso de publicação e `git status -- reports/`) ficaram na
   receita do alvo novo: `make -s regressao-lua` imprimia aviso de publicação sem publicar nada, e
   `net-matrix-publish` perdia o aviso. Corrigido, e `tests/make_parse.sh` ganhou o caso 8 — *só
   `net-matrix-publish` fala de `reports/`* — que é o caso que pega essa classe de erro (o `make -n`
   não acusa movimentação de linhas entre receitas).
3. **Etapas novas entram no registro.** `tests/make_parse.sh` casos 9–10 afirmam que `sincronia` roda
   a suíte e que `regressao-lua` e `sincronia` estão no registro do portão como etapas
   obrigatórias — portão que encolhe em silêncio era o risco desta rodada.

## 6. Números medidos (esta rodada)

| comando | resultado |
|---|---|
| `make -s db` | `1..99`, `# db=99 falhas=0` |
| `make -s dbctl` | `1..31`, `# dbctl=31 falhas=0 blocked=0` |
| `make -s sincronia` | `1..15`, `# sincronia=15 falhas=0 blocked=0` |
| `make -s make-sintaxe` | `1..10`, `# make-sintaxe=10 falhas=0` |
| `make -s admin` | `1..25`, `# admin=25 falhas=0 blocked=0` |
| `make -s gate` | `PASS=23 FAIL=0 BLOCKED=3 NOT_IMPLEMENTED=0 SKIPPED=2`, `assercoes=553 falhas_de_asseracao=0 etapas=28`, exit 0 |

Antes desta rodada (mesmo dia, sessão anterior): `PASS=22 FAIL=0 BLOCKED=3 SKIPPED=2`,
`assercoes=534 etapas=27`. A diferença é a etapa `sincronia` (15 asserções), +3 casos em
`make-sintaxe` e +1 caso em `admin`.

Bloqueado, e continua bloqueado (não é falha nem aprovação): `interop` (camada 3), `lua`, `lua-enc`,
`bench` (critérios de comparação não satisfeitos) — e `net-matrix`, `persistencia` seguem opt-in
(`GATE_FULL=1`), como SKIPPED declarado.

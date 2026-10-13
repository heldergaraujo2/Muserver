# R-11 — persistência própria do v2: o que foi medido, inclusive o defeito que apareceu

Data: 2026-10-13 · branch `arena/cf1de8ce-muserver` · decisão de base: D2-30 (`docs/DECISIONS.md`)

Este relatório existe porque a rodada terminou com **defeito real encontrado, corrigido e medido** —
e um relatório que só mostrasse o verde esconderia justamente a parte que importa.

## 1. O que foi construído

| artefato | linhas | papel |
|---|---|---|
| `include/mu2/db.h` | 148 | API pública: contas, personagens, inventário, transações, verificação de integridade |
| `src/db.c` | 1590 | implementação: arquivo append-only, CRC32C por registro, TX com `TX_COMMIT`, PBKDF2-HMAC-SHA256, `flock`, migração por `schema_version` |
| `tools/mu2dbctl.c` | 221 | CLI local de operação — **segundo consumidor da mesma API** (defeito de contrato aparece nos dois) |
| `tests/db_test.c` | 514 | suíte TAP em C, 99 asserções |
| `tests/dbctl.sh` | 140 | integração por processos separados, 31 asserções |

Comandos: `make -s db` (99 casos), `make -s dbctl` (31 casos), ambos dentro do portão (`make -s gate`).

**Limite declarado, sem inferência:** este arquivo **não** é o banco do servidor original e não tenta
ser. O original era SQL Server com esquema próprio; o que existe aqui é um formato novo, escrito do
zero, com nome e schema próprios (`MU2DB01`). Nada neste relatório é evidência de compatibilidade com
o cliente ou com o banco original.

## 2. Formato, em uma tabela

| parte | tamanho | conteúdo |
|---|---|---|
| cabeçalho | 64 B | magic `MU2DB01`, `schema_version`, CRC do cabeçalho |
| registro | 32 B + payload | `len`, `tipo`, `tx`, `seq`, `crc32c(payload)` |
| 13 tipos | — | conta, personagem, item, remoções, nível, zen, posição, senha, `MIGRACAO`, `TX_COMMIT` |

Regra de visibilidade: um registro só passa a existir para quem reabre **depois** do `TX_COMMIT` da
sua transação (ou imediatamente, quando é operação única implícita — o registro já é o commit).

## 3. O defeito que o teste de morte de processo encontrou

Primeira versão dos testes só **simulava** corte truncando o arquivo. Truncar testa o que *nós*
escrevemos; não testa o que o sistema operacional já tinha em disco quando o processo morreu. Foi
adicionado um gancho de teste em `src/db.c` — `MU2DB_TESTE_ABORTA_APOS=<n>`, desligado por padrão —
que mata o processo com `_exit()` logo depois de gravar o n-ésimo registro, **sem** `atexit`,
`fflush` nem fechar o arquivo.

Com ele, o defeito apareceu em três camadas:

1. **`TX_COMMIT` com `len=4` e payload de 8 bytes.** O campo mentia sobre o próprio tamanho, então o
   CRC do marcador de commit nunca conferia na volta. `not ok 31 - reabre o arquivo` com
   `# MOTIVO: CRC divergente no registro 1 (offset 161)`.
2. **Registro de operação gravado com payload zerado** (composto temporário copiado sem `memcpy`).
   Sintoma: `varredura: formato invalido` na reabertura.
3. **O defeito que só a morte real mostra:** a recuperação descartava os registros sem commit
   *apenas em memória* e deixava os bytes no arquivo; e o número da transação era reiniciado em 1 a
   cada abertura. Resultado medido: uma transferência nova (também `tx=1`) fez a varredura **reaplicar
   o `remove` da transação abandonada junto com a transação nova**, e o arquivo passou a ser
   ilegível — `abrir crash.db: varredura: formato invalido`, reproduzido em
   `./out/mu2dbctl $CR listar-inventario jogador1 Alfa`.

Medição do defeito 3 antes da correção (`bash tests/dbctl.sh`, caso 28):

```
not ok 28 - depois da recuperacao a base volta a aceitar operacao normal
```

## 4. A correção, e o que ela mudou de contrato

Duas mudanças em `src/db.c`, ambas registradas como decisão D2-31:

1. **rollback é remoção física:** a varredura devolve o fim do último registro *confirmado* (depois de
   um `TX_COMMIT` ou de uma operação implícita) e o arquivo é truncado nesse ponto — na abertura e no
   `estado_rebuild()`. Registro abandonado não fica no arquivo para ser reaplicado depois.
2. **número de transação não se repete:** o maior `tx` presente no arquivo vira o piso para o próximo
   `tx` da sessão. Mesmo com a truncagem, dois mecanismos independentes evitam o casamento errado.

Medição da correção, no mesmo cenário, com morte real do processo (`exit=97`):

```
ok 19 - processo morre de verdade no ponto 1 da transferencia (exit 97)
ok 20 - morte no ponto 1: item continua na ORIGEM (transacao desfeita, nao metade aplicada)
ok 21 - morte no ponto 1: destino NAO recebeu nada
ok 22 - morte no ponto 1: arquivo continua integro para o verify
ok 27 - primeira abertura apos o corte relata a operacao descartada (descartados=1)
ok 28 - segunda abertura ja encontra arquivo reparado (descartados=0, sem contar duas vezes)
ok 29 - o rabo sem commit saiu do arquivo (tamanho volta ao valor de antes do corte)
ok 30 - depois da recuperacao o item continua na origem (registro abandonado nao foi replaysado)
ok 31 - depois da recuperacao a base volta a aceitar operacao normal
```

O caso 29 é o mais forte: o arquivo volta **exatamente** ao tamanho de antes do corte — prova de que
o rabo sem commit saiu do disco, não só da memória.

## 5. Resultado das suítes

| comando | resultado |
|---|---|
| `make -s db` | `1..99`, `# db=99 falhas=0` |
| `make -s dbctl` | `1..31`, `# dbctl=31 falhas=0 blocked=0` |
| `make -s gate` | ver `docs/CURRENT_STATE.md` (números da rodada; etapa `db` e `dbctl` incluídas) |

Cobertura declarada, sem exagero: vetores conhecidos (`FIPS 180-4` SHA-256, `RFC 7914` PBKDF2 com
c=1 e c=2, `RFC 3720` CRC32C), ciclo de vida e durabilidade, transações (rollback, commit, corte),
corrupção detectada por CRC, limites de conta/personagem/slots, `flock`, ids derivados da varredura do
log, inventário e transferência atômica. **Não coberto:** concorrência entre dois processos
escrevendo ao mesmo tempo (só o conflito de trava), uso prolongado com milhões de registros, e
qualquer forma de migração real de dados de produção — porque não existe dado de produção legítimo
neste ambiente.

## 6. Dados

Todos os dados dos testes são **sintéticos** (`jogador1`, `Alfa`, `Beta`, `Pers1`…). Nenhum arquivo do
`MuServer/` foi lido, copiado ou usado como fixture; nenhuma senha real, hash real ou PII entra aqui.

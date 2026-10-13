# R-8 — portão único de qualidade (2026-10-12)

Arquivos novos: `tests/run_all.sh` (portão), `tests/gate_state.sh` (teste do portão),
`tests/ref_check.sh` (integridade da referência medida de dentro do portão).
Alvos: `make gate`, `make gate-selftest`. Evidência: `r8-gate.tsv`, `r8-gate-state.tsv`.

## 1. Contrato de execução

O portão roda as etapas em ordem determinística (registro embutido no script, coluna por coluna:
`nome | tipo | rotulo | arquivo_exigido | obrigatória | ferramenta | timeout | comando`) e classifica
cada uma:

| estado | condição | derruba o portão? |
|---|---|---|
| `PASS` | exit 0, `falhas=0`, `blocked=0`, **e** linha de resumo presente com o rótulo da etapa | não |
| `FAIL` | exit ≠ 0, **ou** `falhas>0`, **ou** resumo ausente, **ou** timeout | **sim** |
| `BLOCKED` | dependência externa concreta ausente (referência, ferramenta) | não |
| `NOT_IMPLEMENTED` | etapa prevista cujo arquivo ainda não existe | não |
| `SKIPPED` | dispensa explícita desta execução (`GATE_ONLY`, `GATE_SKIP`, opt-in sem `GATE_FULL=1`) | não |

Três escolhas que importam mais do que parecem:

- **Resumo ausente é `FAIL`, não `PASS`.** Uma suíte que sai 0 sem imprimir nada mensurável não
  passou; ela não disse nada. É o que impede "verde por ter sido ignorada em silêncio".
- **`BLOCKED` e `NOT_IMPLEMENTED` nunca viram `PASS`** e são contados à parte, com o motivo na mesa.
  O portão sai 0 com eles — mas a mesa imprime `nao_testado=…` com a lista nominal.
- **`SKIPPED` só existe por decisão explícita** e carrega o motivo (`opt-in(GATE_FULL=1)`,
  `GATE_SKIP`, `fora_de_GATE_ONLY`). Nada é pulado por omissão.

Segurança e higiene, medidas e não prometidas:

- cada etapa roda como job com controle de trabalho (`set -m`), portanto em **grupo de processo
  próprio**; o prazo vem do `timeout(1)` e, ao estourar, o grupo inteiro é varrido
  (`TERM` → 1 s → `KILL`). Nenhum `pkill -f`.
- `SIGINT`/`SIGTERM`/`SIGHUP` no portão varrem o grupo da etapa corrente e saem **130**.
- a saída (`out/gate/`) é **recriada** a cada execução: nenhum resultado de sessão anterior entra.
- caminhos no relatório são relativos (à raiz, ou ao cwd quando a saída está fora dela).
- nada escreve em `MuServer/`; a etapa `ref-intacta` mede a integridade em vez de supô-la.

## 2. Resultado do portão real

`bash tests/run_all.sh` → **exit 0**, 19,7 s, 16 etapas:

```
PASS=9  FAIL=0  BLOCKED=0  NOT_IMPLEMENTED=5  SKIPPED=2
assercoes=194  falhas_de_assercao=0
testado_de_fato=build,unit,make-sintaxe,net,pe,data,pe-selftest,data-selftest,ref-intacta
nao_testado=net-matrix(SKIPPED),persistencia(SKIPPED),golden(NOT_IMPLEMENTED),
            interop(NOT_IMPLEMENTED),conform(NOT_IMPLEMENTED),fuzz(NOT_IMPLEMENTED),
            bench(NOT_IMPLEMENTED)
```

Detalhe por etapa em `r8-gate.tsv`. Os 194 = `unit` 106 + `net` 34 + `data` 19 + `pe` 14 +
`make-sintaxe` 7 + `ref-intacta` 6 + `pe-selftest` 4 + `data-selftest` 4. `build` é `tipo=cmd`
(pré-condição: não produz asserção, vale o exit code).

`make -s check` continua verde e independente do portão: `unit=106`, `make-sintaxe=7`, `net=34`,
`pe=14`, `data=19` (180 asserções). `gate` não entra em `check` para não haver recursão.

## 3. `gate-selftest` — 18 casos, 0 falhas (`r8-gate-state.tsv`)

Sintéticos (sem a referência de 615 MB): suíte que falha ⇒ `FAIL` e portão ≠ 0 · `blocked=1` ⇒
`BLOCKED` sem derrubar · etapa sem arquivo ⇒ `NOT_IMPLEMENTED` · `GATE_SKIP` ⇒ `SKIPPED` ·
ferramenta ausente ⇒ `BLOCKED` (indisponibilidade ambiental ≠ falha real) · timeout ⇒
`FAIL(motivo=timeout)` sem órfão · suíte que sai 0 sem resumo ⇒ `FAIL` · **suíte que morre no fim
com resumo limpo ⇒ `FAIL(motivo=exit=3)`** · `SIGTERM` no portão ⇒ exit 130 · cwd `/` e caminho
com espaço · relatório pré-existente sobrescrito · duas execuções comparáveis.
Reais: portão com 9 `PASS`/194 asserções · `MU_REF_DATA` inexistente ⇒ `pe`/`data` `BLOCKED` com
selftests `PASS` · F12 · F13 · F14 · retorno ao verde após a reversão (`make-sintaxe` volta a `PASS`).

## 4. Falsificações F12–F14

As três são **diferenciais**: a mutação vive numa cópia em diretório temporário e o caso afirma a
*diferença* entre a cópia mutada e o portão verdadeiro. Motivo: na R-4 uma mutação aplicada no
arquivo real nunca foi revertida (o `pkill -f` do teste matou o próprio shell) e três medições
seguintes foram feitas contra binário mutado. Se a detecção deixar de depender do mecanismo, os
dois lados concordam e o caso falha.

| # | mutação na cópia | esperado | medido |
|---|---|---|---|
| F12 | `wait "$pid" \|\| STEP_EXIT=$?` → `STEP_EXIT=0` (ignora o exit code) | mutada não detecta, real detecta | mutada exit 0 · real exit ≠ 0 ✅ |
| F13 | `ST_STATE=BLOCKED` → `ST_STATE=PASS` | mutada diz `PASS`, real diz `BLOCKED` | confirmado ✅ |
| F14 | `exit 1` acrescentado a `tests/make_parse.sh` (arquivo real) | portão exit ≠ 0 e `make-sintaxe` `FAIL` | confirmado; restauração conferida por sha256 (``6d8a84f74cba623f`` antes = depois) ✅ |

F12 só isola o mecanismo porque a fixture sai ≠ 0 **com resumo limpo** (`falhas=0`): se ela também
reportasse `falhas>0`, a contagem detectaria sozinha e a falsificação não provaria nada. Esse
cenário virou caso permanente do `gate-selftest`.

## 5. Defeito real encontrado pelo próprio portão (e corrigido)

A primeira versão do portão usava um watchdog de fundo (`sleep $tmo &` + `kill`) para o prazo.
Medido em artefato: `out/gate/build.timeout` criado **600 s depois** da etapa, e um `sleep 420`
órfão com `PPID 1` vivo no host. O watchdog sobrevivia à etapa, acordava no meio de outra e o
`wait` dele bloqueava a corrida inteira — uma execução completa travou. Além disso, na mesma
corrida, `net` reportou 3 falhas no cenário S4 que **não se reproduzem** isoladamente
(`make -s net` = 34/0, `GATE_ONLY=net` = 34/0, `setsid` direto = 34/0): coerente com um grupo de
processo alheio sendo sinalizado no meio do teste. Substituído por `timeout(1)` + grupo próprio,
sem processo de fundo; `net` voltou a 34/0 dentro do portão.

Lição registrada: **todo mecanismo de prazo precisa ser testado quanto ao que ele deixa vivo**, não
só quanto a disparar no tempo certo.

Outros dois defeitos meus apareceram durante a construção e foram corrigidos antes do commit:
`ref_check.sh` tratava `*.tmp` como sobra de build (os 504 `GameServer/t*.tmp` são originais do
pacote — o caso virou âncora de conteúdo lida de `reports/r5-pe.tsv`) e resolvia um caminho de
evidência a partir do cwd errado.

## 6. O que o portão NÃO diz

- `NOT_IMPLEMENTED` em `golden`/`interop`/`conform`/`fuzz`/`bench` é ausência de implementação, não
  aprovação nem reprovação.
- `BLOCKED` em `pe`/`data` (quando a referência falta) não autoriza concluir nada sobre formatos.
- O portão não prova compatibilidade com o cliente original e não mede desempenho.
- `net-matrix` e `persistencia` só rodam com `GATE_FULL=1`; sem isso são `SKIPPED` com motivo.

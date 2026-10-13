# R-7 — Desempenho: baseline exploratória, limites medidos e defeitos encontrados

Data: 2026-10-12 · Branch: `arena/cf1de8ce-muserver` · Fase: **R-7**
Ferramentas: `tests/bench.sh`, `tools/bench_check.py`, `tools/rtt_probe.py`
Evidências: `reports/r7-baseline.tsv`, `reports/r7-gate.tsv`

---

## 1. Rótulo obrigatório

**Não existe requisito de desempenho definido pelo dono do projeto.** Portanto:

- nenhum número deste relatório é critério de aceitação, meta de produção ou SLA;
- nenhuma comparação com o servidor original é afirmada — o original **não foi executado**;
- os números valem apenas para **regressão relativa** no mesmo host e na mesma configuração
  (mesmo compilador, mesmos sanitizadores, mesmo roteiro).

O objetivo da fase é ter uma medição reproduzível, com critérios de validade declarados antes de
rodar, e investigar limites de pacote/buffer/conexão medindo estabilidade e custo.

## 2. Ambiente (medido, não suposto)

| item | valor |
|---|---|
| vCPUs | **2** (`nproc`) |
| CPU | Intel(R) Xeon(R) Processor @ 2.60GHz |
| RAM | 3 939 MB total, 3 549 MB disponíveis |
| kernel | 6.1.158+ |
| compilador | cc (Debian 12.2.0-14+deb12u1) 12.2.0 |
| binário medido | `out/mud2` com `-O2` **e** `address,undefined` sanitizers |

**Limitações que invalidam conclusões de capacidade:**

1. **2 vCPUs compartilhadas** — cliente e serviço competem pelas mesmas CPUs. Em B2 (8 conexões)
   há 8 processos clientes + 1 serviço para 2 CPUs: o que se mede é o escalonador, não o serviço.
2. **Sanitizadores ligados** — o binário medido é o de teste (ASan+UBSan), não um binário de
   produção. Throughput de produção seria maior; afirmar quanto seria invenção.
3. **Loopback** — nenhum caminho de rede real, MTU, NIC ou RTT de rede está envolvido.
4. `sysctl` de buffers TCP não é legível neste ambiente; os buffers efetivos foram inferidos das
   próprias medições (`rcvbuf pedido=1024 efetivo=2304`, impresso pelo cliente).

Consequência registrada: **capacidade absoluta é `BLOCKED`**. Comparações relativas no mesmo host
e mesma configuração são válidas.

## 3. Critérios de validade (declarados antes de rodar)

Fixos no topo de `tests/bench.sh` e cobrados por `tools/bench_check.py` — que é um programa
**separado** de quem mede, de propósito: quem mede não pode ser quem julga se a medição vale.

| critério | valor declarado |
|---|---|
| repetições (B1) | 5 |
| aquecimento descartado | 1ª repetição |
| drift máximo entre repetição e mediana | 25 % |
| perda de quadro | **falha** (exit 3), nunca ambiente |
| drift acima do declarado | **`BLOCKED`** por ambiente (exit 1), número não publicado |

Códigos de saída do validador: `0` critérios satisfeitos · `1` drift acima do declarado
(`BLOCKED`) · `2` arquivo/schema inválido · `3` perda de quadros ou percentis incoerentes (falha
real). A ordem importa: perda **e** drift alto é falha, não ambiente — classificar como `BLOCKED`
esconderia o defeito.

**Drift medido nesta fase:** 4,3 %–17,2 % em 12 execuções com a janela final. Em 15 execuções
consecutivas, **1** saiu `BLOCKED` por drift (6,7 %) — comportamento esperado e registrado, não
falha: o portão continua `exit 0` porque `BLOCKED` não é `FAIL`.

## 4. Cenários e números

Tabela completa em `reports/r7-baseline.tsv`.

| cenário | o que mede | resultado |
|---|---|---|
| **B1** | throughput, 1 conexão, 20 000 quadros ECHO de 64 B, 5 repetições | 20 000/20 000 em 5 de 5; mediana 87 ms ⇒ **≈ 215 000 quadros/s** (≈ 14,6 MB/s) |
| **B2** | 8 conexões paralelas, 2 000 quadros cada | 16 000/16 000, nenhum perdido; **≈ 250 000 quadros/s** agregados |
| **B3** | latência ida-e-volta, 500 quadros (20 de aquecimento descartados) | **p50 39,5 µs · p95 60,7 µs · p99 75,3 µs** — *limite superior* |
| **B4** | custo por tamanho de corpo, passo-trancado, 1 000 quadros | corpo 64: p50 49,7 µs · corpo 2048: p50 55,7 µs; 0 erros nos dois |
| **B5** | **limite**: pipeline além do que os buffers absorvem | conexão fechada com `close=queue_full` após **551 quadros**; serviço sobrevive |

Leituras honestas:

- **B2 não é 8× B1.** 250 000 vs 215 000 quadros/s. Com 2 vCPUs o agregado quase não sobe: quem
  limita é a CPU, não o serviço. Este é exatamente o número que **não** se pode extrapolar.
- **B3 e B4 são limite superior.** O cliente é Python (`tools/rtt_probe.py`) e o custo dele está
  dentro. A prova está em B4: p50 de 49,7 µs para 64 B e 55,7 µs para 2048 B — 32× mais dados por
  quadro e ~12 % de diferença. **O custo do cliente domina nesta faixa; a diferença de custo por
  tamanho de corpo não é separável com este cliente.** Registrar isso é o resultado; inventar um
  "custo por byte do serviço" seria falsificação.
- **B5 é um limite do contrato, não uma queda.** A fila de resposta tem **uma vaga** (D2-05) e o
  contrato fecha a conexão que faz pipeline além do que os buffers do socket absorvem.

### 4.1 B5 — o limite, com números exatos

Comando: cliente com `--rcvbuf 1024` (efetivo **2304 B**), 2 000 quadros ECHO de 2048 B escritos
sem ler nada (4 104 000 B no fio).

```
WARN  conn=1 queue_full vaga-ocupada pending=1368 causa=resposta-anterior-pendente
INFO  conn=1 close=queue_full in=2052 out=684/2052
STATS ... frames=552 rejects=1 queue_full_closes=1
```

- **551 quadros** de 2048 B foram tratados antes do fechamento (`frames=552` inclui a consulta
  STATS que leu o contador).
- A última resposta ficou **parcialmente escrita** (`out=684/2052`): o serviço não descartou dados
  em silêncio, fechou com causa classificada.
- O cliente **observa o FIN** (`eof=1`) — não fica pendurado.
- O serviço **continua vivo** e responde a um PING novo em outra conexão (asserção 12).
- **Determinístico: 8 de 8 execuções** com `rcvbuf` fixado.

Sem fixar `rcvbuf`, o mesmo pipeline **não** estourava sempre: em 15 execuções, 1 não teve
`queue_full` nenhum (o serviço tratou os 2 000 quadros e a conexão terminou em `socket_error`
quando o cliente saiu). Ou seja, o limite depende do tamanho dos buffers do socket — e um teste
que aposta nessa corrida não é teste. Por isso o cenário fixa `--rcvbuf`.

## 5. Defeitos encontrados e corrigidos

Três defeitos reais apareceram **porque** a bateria foi escrita antes de se aceitar qualquer
número. Nenhum deles estava em `MuServer/`; todos no código recriado.

### D-1 — `netclient` contava iterações de `poll` como se fossem tempo (harness)

```c
pr = poll(&pfd, 1, 100);
elapsed += 100;          /* somava o TIMEOUT, não o tempo decorrido */
```

Com dados prontos o `poll` retorna imediatamente, então o orçamento de `--timeout-ms 60000` se
esgotava em **600 leituras**. Medido antes da correção, 5 repetições de 2 000 quadros:

| repetição | quadros recebidos | resultado |
|---|---|---|
| 1 | 2 000 | OK |
| 2 | 1 371 | DIVERGENTE |
| 3 | 1 311 | DIVERGENTE |
| 4 | 1 238 | DIVERGENTE |
| 5 | 2 000 | OK |

E o serviço registrava `close=write_error` com `rejects=4` — ou seja, **o harness fabricava
"perda do serviço"**: o cliente desistia, fechava o socket, e a próxima escrita do serviço
falhava. A classe de defeito já tinha aparecido na R-4 (`--timeout-ms 5000` → 107/120); a causa
raiz, não.

Correção: relógio monotônico (`clock_gettime(CLOCK_MONOTONIC)`) nos **dois** laços que tinham o
mesmo padrão (leitura e espera de EOF). Depois: **5/5 OK, `rejects=0`, zero `write_error`**, todos
os fechamentos `client_eof`. `make -s check` e o portão inteiro continuaram verdes (as 34
asserções de `net` e as 15 de `conform` dependem deste cliente).

### D-2 — janela de medição curta demais (método)

Com 2 000 quadros por repetição (~20 ms), um único hiato do escalonador vale 30–40 %:
**drift medido de 40,4 %**, acima dos 25 % declarados ⇒ `BLOCKED`. Com 20 000 quadros (~87 ms),
o drift caiu para 4,3 %–17,2 % em 12 execuções. A janela foi alargada e o número antigo fica
registrado aqui; **o critério de 25 % não foi afrouxado** — afrouxar critério para o número passar
é exatamente o que a F18 existe para impedir.

### D-3 — B5 apostava em corrida (teste)

Ver §4.1: 1 falha em 15 execuções. Corrigido fixando `--rcvbuf 1024`; 8/8 e depois 15/15.

### D-4 — dois defeitos do próprio `bench.sh`, pegos pelas asserções

1. A contabilidade da F19 comparava o total de quadros de **quatro serviços diferentes** com o
   contador de um só (cada cenário sobe um serviço novo, com contadores zerados). Corrigido
   zerando `SENT` e o contador de consultas a cada `start_srv`.
2. A função `contabilidade` estava definida **depois** da primeira chamada: as duas asserções
   falhavam por "função inexistente", não por contabilidade errada. Definição movida.

Ambos apareceram como `not ok` e foram tratados como o que eram — defeitos meus — em vez de
serem contornados.

## 6. Falsificações desta fase

| ID | mutação | comportamento esperado | resultado |
|---|---|---|---|
| **F18** | `drift_ok = drift <= a.drift_max` → `drift_ok = True` em cópia temporária do validador | o validador **sem** o critério deixa passar um drift de 300 % que o original bloqueia | detectada: original `exit 1`, mutado `exit 0` (asserção 15, permanente no portão) |
| **F19** | medir throughput pelo contador `frames` do serviço em vez dos quadros do cliente | a diferença aparece: o quadro STATS conta no `frames` | cobrada como igualdade exata: B1 `100 001 = 100 000 + 1`; B4 `2 042 = 2 040 + 2` |

Ambas ficam no portão como asserções permanentes, não como experimento de uma fase.

## 7. O que **não** se pode concluir

- **Capacidade absoluta**: `BLOCKED` (2 vCPUs, cliente e serviço competindo, sanitizadores).
- **Latência do serviço**: não separável do cliente Python; os valores são limite superior.
- **Custo por byte do serviço**: não separável nesta faixa (§4, B4).
- **Compatibilidade de desempenho com o servidor original**: não avaliada — o original não foi
  executado, e executá-lo automaticamente é proibido pelas regras do projeto.
- **Comportamento sob CPU saturada, memória limitada ou rede real**: fora do escopo medido.

## 8. Reprodução

```sh
cd recriado
make -s build
make -s bench          # ou: bash tests/bench.sh  → out/bench.tsv
make -s gate           # etapa `bench` como parte do portão
BENCH_FRAMES=50000 bash tests/bench.sh   # janela maior, para experimentar drift
```

Saída: linhas `ok/not ok`, `# bench=N falhas=F blocked=B`, tabela `out/bench.tsv`,
contabilidade em `out/bench-contab.txt`. Exit `0` sem falha; `BLOCKED` por drift **não** muda o
exit code (não é falha), mas impede publicar o número.

## 9. Estado do portão após a R-7

`make -s gate` → **14 PASS · 0 FAIL · 0 BLOCKED · 3 NOT_IMPLEMENTED · 2 SKIPPED · 244 asserções ·
0 falhas de asserção · 32,6 s · exit 0**.
`make -s gate-selftest` → **19/19, exit 0**.
`NOT_IMPLEMENTED` restantes: `golden`, `interop`, `fuzz` (o `bench` deixou de ser placeholder —
a linha antiga do registro foi removida no mesmo ato em que a etapa real entrou, como exige a
guarda de nome duplicado).

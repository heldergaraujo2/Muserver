# TESTING — testes existentes, comandos, resultados medidos e limitações

| campo | valor |
|---|---|
| data das medições abaixo | **2026-10-13**, neste ambiente (Debian 12, 2 vCPUs, gcc 12.2.0, ASan+UBSan ligados) |
| comando canônico | `cd recriado && make -s gate` (28 etapas) · `make -s gate-full` (inclui as opt-in caras). **Atenção, achado de 2026-10-13:** a variável que liga as opt-in é **`GATE_FULL`** — `FULL=1` é do `scripts/verify-backup.sh` e, se usado aqui, o portão roda com `net-matrix`/`persistencia` **SKIPPED** dando cara de verde. Por isso existe o alvo `gate-full`; use o alvo, não a variável |
| política de honestidade | `BLOCKED`/`NOT_IMPLEMENTED`/`SKIPPED` **nunca** são contados como aprovados; resumo ausente é `FAIL` |

## 1. Resultados desta rodada (números reais, incluindo um FAIL explicado)

| execução | resultado medido |
|---|---|
| `make -s build` | exit 0 — `out/{wire.o, mud2, mu2ctl, netclient, mu2codec, mu2fuzz, mu2admin, unit}` com `-Werror` e ASan+UBSan |
| `make -s check` | **182 asserções, 0 falhas** (unit 106 · make-sintaxe 10 · net 34 · pe 14 · data 21) — a contagem de `check` é a da rodada de referência; `make-sintaxe` subiu de 7 para 10 em 2026-10-13 |
| `make -s gate-selftest` | **19/19**, exit 0 (o portão sabe falhar: F12–F14, etapa duplicada, `BLOCKED` demonstrado) |
| `FULL=1 make -s gate` — **1ª execução, antes do commit desta rodada** | **19 PASS, 1 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 0 SKIPPED, 375 asserções, 23 etapas, exit 1** — o único `FAIL` é a etapa `persistencia`, com motivo medido: `arvore recriado/ limpa → FALHA (M recriado/Makefile; M recriado/reports/net-*.tsv)`. Isto é **a checagem funcionando**, não defeito do produto: ela exige árvore limpa e a rodada estava em curso (§3). |
| `make -s gate` (padrão, **após o commit** dos documentos) | **18 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções contadas, 23 etapas, exit 0** (69 302 ms) — idêntico à mesa de referência; as duas opt-in ficam `SKIPPED` por decisão |
| `FULL=1 make -s gate` — interação `net-matrix` × `persistencia` | **`FAIL` em `persistencia` por construção**: `net-matrix` regrava `reports/net-{orig,mur0}.tsv` (timestamp + contagens) e a checagem seguinte exige árvore limpa. Com `GATE_FULL=1 GATE_SKIP=net-matrix make -s gate` a etapa roda verde (medido: **ok=11 falhas=0**); as duas opt-in ficam comprovadamente verdes nesta rodada (matriz 36/36 em 619 s; persistência 11/11), só não na mesma passada. Achado registrado em §3 e em `AUDIT_HANDOFF.md` §5. |
| `GATE_FULL=1 GATE_ONLY=persistencia make -s gate` (após a regravação do snapshot) | **`PASS`** — log: `ok=11 falhas=0`, `snapshot ⊆ HEAD` OK, `divergencia … observadas: nenhuma`, `arquivos fora do snapshot … extras=0`, `ponta == MANIFEST aa22742…`, `MuServer/ intacta` |
| `FULL=1 bash scripts/verify-backup.sh` | **ok=15 falhas=0** (§3) |
| **reprodução em clone limpo do remoto** (`git clone` completo do ramo publicado, sem estado local) | `make -s build` exit 0 · `make -s check` **182 asserções, 0 falhas** · `make -s gate-selftest` **19/19** · `make -s gate` **18 PASS, 0 FAIL, 3 BLOCKED, 2 SKIPPED, 339 asserções, 23 etapas, exit 0** (71 317 ms) — os mesmos números da árvore de trabalho |
| clone **raso** (`--depth 1`, fora do caminho documentado) | `make -s check` 182/182 igual, mas `ref-intacta` acusa **2 falhas** (casos 7–8: o commit do upload não existe no clone raso) e o caso 13 do `gate-selftest` falha por consequência. **Não é defeito do conteúdo** — é objeto ausente; `git fetch --unshallow` resolve. Registrado em `BUILD_AND_RUN.md` §9 e `AUDIT_HANDOFF.md` §5.5 |
| `make -s lua-enc` (etapa nova) | **27/27, `blocked=2`** (`F23` + algoritmo não identificado), exit 0 |
| `make -s gate` (pós-commit, árvore limpa) | **20 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 448 asserções, 25 etapas, exit 0** (78 365 ms) — etapas novas `db` e `dbctl` incluídas |
| `make -s db` · `make -s dbctl` (etapas novas) | **144/0** · **48/0** (o segundo mata o processo no meio da transação e prova a recuperação, e mede a concorrência verificador×escritor dos dois lados) |
| `make -s gate-full` (árvore limpa, remoto sincronizado) | **PASS=22, FAIL=0, BLOCKED=4, SKIPPED=0, 502 asserções, 26 etapas, exit 0** (694 850 ms); `net-matrix` + `matriz-artefatos` + `persistencia` verdes **na mesma passada**; a 4ª `BLOCKED` é `bench` por **drift 31,1% > 25%** (host carregado pela matriz, critério declarado antes) |
| `bash scripts/verify-backup.sh` · `FULL=1 …` | **11/11** · **15/15** — `bundle byte a byte OK remoto=a0fe917e…`, `HEAD local esta no remoto OK b2ffadd` |
| `make -s make-sintaxe` | 7/7 após a adição do alvo `lua-enc` (o Makefile é contrato e continua válido) |

## 2. Mesa por etapa (o que cada uma prova, com o resultado medido)

| etapa | o que testa | resultado (2026-10-13) | limite declarado |
|---|---|---|---|
| `build` | a build completa compila/linka com `-Werror` + sanitizadores | `PASS` (cmd) | — |
| `unit` | codec: 106 casos de unidade (limites, erros, perfis, involução) | `PASS` 106/0 | — |
| `db` | persistência própria: vetores FIPS 180-4/RFC 7914/RFC 3720, ciclo de vida, transações, corrupção por CRC, limites, `flock`, inventário e transferência, **versão de esquema (atual/futura/antiga/cabeçalho inválido)** e **semântica do lock de verificação** | `PASS` **144/0** | formato **próprio**; não é o banco do original (D2-40); **sem migração automática** (D2-41: versão antiga é recusada) |
| `dbctl` | **integração por processos separados**: cada comando do CLI é um processo novo (o estado tem de vir do arquivo) + **morte real no meio da transação** (`MU2DB_TESTE_ABORTA_APOS`) + **concorrência verificador×escritor medida dos dois lados**, com lock tomado pelo próprio teste e sobreposição confirmada | `PASS` **48/0** | não cobre dois **escritores** simultâneos (impossível por desenho: `LOCK_EX`) |
| `make-sintaxe` | **o Makefile como contrato** (flags, alvos, `out/` ignorado, dono de receita de publicação) | `PASS` 10/10 | — |
| `sincronia` | **durabilidade por sequência de syscalls**: existe `fsync` entre o fim dos registros e a reescrita final do cabeçalho; leitura pura não grava; recusa não deixa rabo | `PASS` **15/15** | mede `fsync`, não sobrevivência a queda de energia (não reproduzível aqui) |
| `regressao-lua` | **regressão estática dos 6 `.lua`** do pacote de terceiros: baselines, reversões por blob, critérios de conteúdo, 9 mutações | `PASS` **53/53**, `blocked=0` | estático: execução de Lua não observada |
| `net` | rede ponta a ponta contra `mud2` real (S1–S13): fragmentação, escrita parcial, backpressure, idle, max_clients, malformado, shutdown | `PASS` 34/34 | matriz rápida (`NET_QUICK=1`) |
| `pe` | inspeção PE da referência (22 `.exe`, arquitetura, seções, imports) | `PASS` 14/14 | requer `MU_REF_DATA`; sem ele → `BLOCKED` |
| `data` | dados/formatos da referência (`.att`, `.bmd`, `.ozj`, `.smd`, Lua, backups) | `PASS` 21/21 | idem |
| `pe-selftest`, `data-selftest`, `cfg-selftest` | só a recusa de entrada inválida, sem tocar em 615 MB (funciona em restore de bundle) | `PASS` 4/4 · 4/4 · 5/5 | — |
| `conform` | conformidade byte a byte do contrato v2 (C-01…C-15) | `PASS` 15/15 | camada **interna** do v2 |
| `matriz` | valida `r6-matriz.tsv` (linha sem teste reproduzível = falha) | `PASS` (cmd) | — |
| `cfg` | endpoints/valores da configuração + **redação de segredos** (nome e forma) | `PASS` 15/15 | 26 valores redigidos |
| `ref-intacta` | `MuServer/` inalterada desde `b5b84da` e os 6 `.lua` divergentes registrados/reversíveis | `PASS` 8/8 | "intacta" = "não mudou desde então" (D2-32) |
| `golden` | 38 vetores versionados `(entrada, saída, cláusula, origem)` + F20 (1 byte) e F21 (perfil) | `PASS` 42/42 | corpus **do v2**; não afirma compatibilidade |
| `interop` | 3 camadas separadas; camada 3 = binário original | `BLOCKED` 12/12, `blocked=1` | sem wine/qemu + autorização |
| `fuzz` | fuzzer determinístico: 52 sementes, 3 rodadas × 50 000 = **150 000 iterações**, oráculo de invariantes, `RLIMIT_AS` 64 MB, F22 diferencial | `PASS` 12/12, 0 violações | **sem feedback de bordas** (não é libFuzzer; D2-33) |
| `seguranca` | malformados na porta (serviço vivo), fd/RSS, `SIGTERM` exit 0, higiene de log, TSan N/A | `PASS` 13/13 | host 2 vCPUs |
| `admin` | console: token 0600, tempo constante, papéis, loopback obrigatório, 501 por decisão, higiene | `PASS` 24/24 | sem UI/escrita por decisão |
| `lua` | inventário e evidência estática da camada Lua (148 `.lua`, 8 `ProtocolCore`) | `BLOCKED` 13/13, `blocked=1` | sem interpretador Lua: sem sintaxe/execução |
| `lua-enc` | cifragem dos scripts do cliente: cabeçalho, determinismo, janela de 3 bytes, famílias refutadas, golden de bytes | `BLOCKED` 27/27, `blocked=2` | **algoritmo não identificado**; `F23` sem decodificador |
| `bench` | baseline exploratória com critérios de validade declarados antes | `PASS` 15/15 | **nenhum número é meta** (R-7) |
| `net-matrix` (opt-in) | matriz completa de backpressure: **100 configurações × 5 repetições por perfil** | `PASS` **36/36** (619 s) | caro; fora do portão padrão por decisão |
| `persistencia` (opt-in) | bundle restaurável (clone real), `MANIFEST`/sha256/ponta, **HEAD publicado no remoto**, árvore limpa | ver §1/§3 | é backup de repositório — **não** é banco de dados |

Leitura da mesa: **o que está verde é o que foi executado**; `interop`, `lua` e `lua-enc` aparecem
como `BLOCKED` com causa, e `net-matrix`/`persistencia` como `SKIPPED` no portão padrão (opt-in
explícito via `GATE_FULL=1`) — nunca como aprovadas.

## 3. A etapa `persistencia` e a interação com `net-matrix` (transparência, e como foi resolvida)

**Estado desta seção em 2026-10-13 (Fase A/A2): resolvida, com regressão versionada.** A causa era
artefato, não código: `net-matrix` regravava `reports/net-{orig,mur0}.tsv` e a etapa seguinte exige
árvore limpa. Agora os TSV vão para `out/net-matrix/` (ignorado pelo git) e a publicação em
`reports/` é passo explícito (`make -s net-matrix-publish`); a etapa `matriz-artefatos` (10
asserções) guarda a regressão — inclusive que `make -s gate-full` **não** regrava os relatórios de
`reports/`. As duas medições `FAIL` abaixo ficam registradas como história: uma rodada que apaga o
resultado ruim não deixa rastro de como o defeito foi encontrado.

1. **1ª passada de `FULL=1`**, com a rodada em curso: `arvore recriado/ limpa → FALHA`
   (`M recriado/Makefile`, `M recriado/reports/net-*.tsv`). É a checagem de D2-09 funcionando: "fim de
   rodada" exige árvore limpa. Após o commit, a etapa roda verde.
2. **`net-matrix` antes de `persistencia` no `GATE_FULL=1`**: a matriz regrava, por construção, dois
   arquivos de evidência versionados (`reports/net-orig.tsv`, `reports/net-mur0.tsv`, com timestamp e
   contagens novos), e a etapa seguinte exige árvore limpa ⇒ `FAIL` determinístico na mesma passada.
   **Contorno documentado:** `GATE_FULL=1 GATE_SKIP=net-matrix make -s gate` (ou rodar
   `bash scripts/verify-backup.sh` depois de commitar os TSVs regravados). As duas etapas estão
   comprovadamente verdes nesta rodada, cada uma medida: `net-matrix` 36/36 em 619 s e
   `persistencia` 11/11 depois da regravação do snapshot.
   **Melhoria pendente (não aplicada nesta consolidação, para não alterar contrato testado):** trocar a
   ordem das duas etapas no registro do portão **ou** fazer a matriz escrever em `out/` e publicar em
   `reports/` por alvo explícito. Fica registrada como achado em `AUDIT_HANDOFF.md` §5.

## 4. Falsificações permanentes (o teste que prova que o teste sabe falhar)

| id | o que falsifica | onde |
|---|---|---|
| F12–F14 | o portão: etapa que falha ⇒ `FAIL`; `blocked` nunca vira `PASS`; resumo ausente ⇒ `FAIL` | `gate-selftest` (19/19) |
| F15/F16 | a comparação da sonda de conformidade (mutação neutralizada ⇒ o caso falha) | `conform` C-15 |
| F18/F19 | critérios de validade do `bench` (drift de 300 % bloqueia o juiz; sem o critério, não) | `bench` |
| F20/F21 | golden: corromper 1 byte / trocar o perfil tem de nomear vetor e offset | `golden` (2 falsificações) |
| F22 | codec mutado × fuzzer: violação > 0 e caso de regressão gravado, com replay contra o codec real | `fuzz` |
| F23 | **`BLOCKED`**: exigiria o decodificador dos `.lua` (algoritmo não identificado) — declarado, não contornado | `lua-enc` |

## 5. O que **não** foi testado (e por quê)

1. **Nenhum binário original foi executado** — nem por este teste, nem por nenhuma etapa: `interop`
   camada 3 é `BLOCKED` e o mecanismo de evidência manual (`r6-interop-real.tsv`, 8 chaves) está
   pronto para quando houver ambiente + autorização.
2. **Compatibilidade com o cliente original**: `NÃO VERIFICADO`. O pacote não contém cliente.
3. **Sintaxe/execução de Lua**: sem interpretador no host (148 scripts só inventariados).
4. **Formatos**: `.ozt` (estrutura), `.bmd` (layout), `.att` (semântica) e a cifragem dos `.lua`
   (algoritmo) — o que foi medido está em `PROTOCOLS.md` §5–§6; o resto é desconhecido, não "ok".
5. **Banco de dados do original**: nada restaurado/consultado (`DATABASE.md`).
6. **Escala/produção**: tudo em loopback, 2 vCPUs; nenhuma medição de carga real, nenhum SLA.
7. **Segurança dos binários de terceiros**: nenhum teste ofensivo; apenas configuração e higiene do
   lado do v2 (`SECURITY.md`).

## 6. Como reproduzir (com os códigos de saída)

```sh
cd recriado
make -s build              # exit 0
make -s check              # exit 0 — 182 asserções, 0 falhas
make -s gate-selftest      # exit 0 — 19/19
make -s gate               # exit 0 — 23 etapas; FAIL aqui ⇒ exit 1
GATE_FULL=1 make -s gate   # exit 0 — inclui net-matrix (~10 min) e persistencia
make -s lua-enc            # exit 0 — 27/27, blocked=2
bash scripts/verify-backup.sh            # ok=11 falhas=0
FULL=1 bash scripts/verify-backup.sh     # ok=15 falhas=0 (confere o remoto)
```

A mesa completa (uma linha por etapa, com asserções/falhas/blocked/exit/ms) sai em `out/gate.tsv`;
o log de cada etapa fica em `out/gate/<etapa>.log`. Ambos são regenerados a cada execução e
`out/` é ignorado pelo git (nada de artefato de build versionado).

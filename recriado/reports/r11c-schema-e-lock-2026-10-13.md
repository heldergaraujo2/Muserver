# R-11c — P4: versão de esquema sem migração automática, e verificação com lock compartilhado

Data: 2026-10-13 · branch `arena/cf1de8ce-muserver` · decisão: **D2-41** (`docs/DECISIONS.md`)
Pendências fechadas aqui: itens 1 e 2 de `docs/CONTINUITY.md` §5.1 (abertos pela auditoria P3).

Dados 100% sintéticos; nada de `MuServer/` foi lido, copiado ou usado como fixture. Este relatório
não substitui o `r11b-veredito-auditoria-p3-2026-10-13.md` (que descreve o defeito de durabilidade) —
ele fecha as duas lacunas que ficaram declaradas lá.

## 1. Decisão de esquema — o que foi registrado, e o que **não** foi implementado

`schema_version` identifica a **versão do formato**. **Não existe migração automática**, não existe
registro de migração e não há alegação de retrocompatibilidade de leitura. O texto do cabeçalho de
`include/mu2/db.h`, que prometia "abrir arquivo mais velho migra em memória na abertura, com um
registro de migração gravado", foi substituído pela regra real. `REG_MIGRACAO` continua existindo no
`enum` e no `case` da varredura, mas **nada o grava** — está declarado, não implementado, e não é
apresentado como funcionalidade.

Comportamento por versão (fail closed nas duas pontas), medido por teste:

| situação | comportamento | detalhe nomeado | teste |
|---|---|---|---|
| **atual** (`== 1`) | abre normalmente; `stats` reporta a versão **carregada** | — | `teste_schema_versao` casos 3–6 |
| **futura** (`> 1`, CRC válido) | **recusa** na abertura e na verificação | `schema 2 mais novo que o suportado (1)` | idem casos 7–10 |
| **antiga** (`< 1`, CRC válido) | **recusa** na abertura e na verificação (não migra, não recarimba) | `schema 0 anterior ao suportado (1): sem caminho de migracao` | idem casos 11–15 |
| **cabeçalho inválido** — arquivo curto | recusa | `arquivo menor que o cabecalho` | idem casos 19–20 |
| **cabeçalho inválido** — magic | recusa | `magic invalido (nao e arquivo MU2DB)` | idem casos 21–22 |
| **cabeçalho inválido** — CRC | recusa | `CRC do cabecalho divergente` | `teste_corrupcao` |

**A troca da constante.** `gravar_cabecalho` carimbava sempre `MU2DB_SCHEMA_VERSION`; agora grava
`db->schema_version`, a versão efetivamente carregada do arquivo. Isto corresponde ao contrato
existente porque a abertura **só** aceita a versão suportada — a gravação e a recusa de versão antiga
andam juntas: sem a recusa, a troca sozinha não bastaria (o arquivo antigo seria aberto e recarimbado
como novo). **Limite declarado:** com v1 única, as duas implementações da gravação são
indistinguíveis por teste; o que existe é a **guarda do formato** — arquivo novo tem exatamente
`MU2DB_SCHEMA_VERSION` no byte 8 do cabeçalho — e o teste que reprova se a versão antiga passar a ser
aceita (mutação A abaixo, 2 asserções).

**Auditoria do teste que já existia:** o antigo caso "versão futura" forjava `schema=99` **e** um CRC
inválido (`0xDEADBEEF`), então era reprovado por CRC — não provava nada sobre versão. Substituído por
um forjador que recalcula o CRC de verdade (`mu2db_teste_crc32c`, já exportado para teste), com
guarda de que a forja **funcionou** (a imagem tem de diferir da cópia limpa).

## 2. Verificação: `LOCK_SH | LOCK_NB`, e por que não bloqueante

`mu2db_verify` agora abre, toma **lock compartilhado não bloqueante** e só então lê. Três razões,
todas verificáveis:

1. **compartilhado** — leitura não pode conviver com escritor no meio de uma gravação: um registro
   ocupa duas escritas (cabeçalho de 32 B e payload) e um leitor sem lock pode ver a primeira sem a
   segunda e chamar de corrupção o que é escrita em curso;
2. **não bloqueante** — um `LOCK_SH` bloqueante dá **deadlock** no caso legítimo que já existe: o
   mesmo processo com o banco aberto (LOCK_EX) verificando o mesmo caminho (`tests/db_test.c` fazia
   exatamente isso);
3. **descritores** — o lock vive no descritor aberto pelo próprio `verify`, sempre `O_RDONLY`; a
   liberação acontece em **todos** os caminhos de saída (`LOCK_UN` + `close`), e o teste confere depois
   que o arquivo volta a aceitar `LOCK_EX` e `LOCK_SH`.

Comportamento: sem escritor ativo → `MU2DB_OK`; com escritor ativo → `MU2DB_E_TRAVADO` e detalhe
`arquivo em uso: verificacao concorrente nao garantida (escritor ativo)`. O `mu2dbctl verificar` sai
**!= 0** e nunca imprime `integridade=ok`. Falha de aquisição não é morte silenciosa; e a asserção
`det[0] != '\0'` garante que a recusa sempre tem motivo escrito.

**Efeito medido que passou a existir (declarado, não escondido).** Verificação e escrita se
**excluem**. Em 3 tentativas de 20 escritas contra um verificador em laço:

```
tentativa 1: verificar(ok=117 recusado=3 fora_do_contrato=0) escritor(ok=57 recusado=3)
tentativa 2: verificar(ok=119 recusado=1 fora_do_contrato=0) escritor(ok=58 recusado=2)
tentativa 3: verificar(ok=117 recusado=3 fora_do_contrato=0) escritor(ok=58 recusado=2)
tentativa 4: verificar(ok=115 recusado=5 fora_do_contrato=0) escritor(ok=55 recusado=5)
```

Ou seja: **um verificador periódico pode causar recusas esporádicas de escrita no serviço** (2–5 em
60 tentativas, ~3–8%). Fica registrado como característica desta versão; política de repetição com
recuo, janela de manutenção ou um `verify` explícito "sem garantia" são **decisões do proprietário** e
não foram tomadas aqui. O livro-caixa é exato: o inventário final é exatamente o número de escritas
bem-sucedidas.

## 3. Como o cenário concorrente é provado (e não "muitas execuções deram certo")

O teste tem duas partes, e a diferença importa:

- **determinística** (`tests/dbctl.sh` casos 33–44): o **próprio teste** toma `LOCK_EX` com `flock(1)`
  no arquivo, confirma que tomou (`flock -n 8`), e então verifica que `mu2dbctl verificar` recusa
  nomeado; libera, confirma que passa; repete com `LOCK_SH` (leitor) para provar que compartilhado é
  compatível e que o escritor é o excluído. Nada aqui depende de agendamento;
- **corroborativa** (casos 45–48): verificador em laço + escritor em laço ao mesmo tempo, contando os
  dois lados. A asserção de sobreposição é `recusas_verificador + recusas_escritor >= 1` — se nenhum
  lado viu recusa, **os dois nunca se encontraram** e o teste FALHA. Medido com o defeito
  reintroduzido (mutação B): `recusas = 0` e a asserção dispara, além de 5 outras.

Margem observada em execuções corretas: recusas somadas 3, 3, 5, 10 (mínimo 3). Residual assumido: sob
carga extrema que serialize os dois lados, a asserção de sobreposição poderia disparar sem defeito —
por isso o caso determinístico é o que sustenta a afirmação, e a mensagem de falha imprime o número.

## 4. Sensibilidade a mutação (medida, restaurada em seguida)

| mutação | resultado | resultado esperado |
|---|---|---|
| **A** remover a recusa de versão antiga | `not ok 114/115`, `# db=144 falhas=2` | detectada |
| **B** remover o `LOCK_SH` do `verify` | `not ok 57/58/139/140/141` (`# db=144 falhas=5`) **e** `not ok 34/35/36/37/39/45` (`# dbctl=48 falhas=6`) | detectada |
| **C** tornar o lock **bloqueante** (`LOCK_SH` sem `LOCK_NB`) | `timeout 25` → **exit 124** (deadlock; nenhuma asserção chega a ser impressa) | detectada |

A mutação C é a justificativa experimental do `LOCK_NB`: sem ele, o caso legítimo de mesmo processo
trava a suíte inteira.

## 5. Números medidos

| comando | antes desta rodada | depois |
|---|---|---|
| `make -s db` | 99/0 | **144/0** (+45) |
| `make -s dbctl` | 31/0 | **48/0** (+17) |
| `make -s sincronia` | 15/0 | 15/0 |
| `make -s make-sintaxe` | 10/0 | 10/0 |
| `make -s admin` | 25/0 | 25/0 |
| `make -s gate` | PASS=23 FAIL=0 BLOCKED=3 SKIPPED=2 · 553 asserções · 28 etapas · exit 0 | **idem, com 615 asserções** |

Nenhuma asserção foi removida: a única que dependia do comportamento antigo (`arquivo reparado por
truncagem fica valido`, que verificava com o banco aberto) foi **substituída por três** — recusa
nomeada com escritor ativo, motivo citado, e aprovação **com o banco fechado**. A soma de asserções
subiu em todas as suítes tocadas.

**Portão completo (opt-in caras), medido na árvore limpa e publicada (commit `7ffc35a`):**

| comando | resultado |
|---|---|
| `make -s gate` | `PASS=23 FAIL=0 BLOCKED=3 NOT_IMPLEMENTED=0 SKIPPED=2`, **615 asserções**, 28 etapas, exit 0 (90 685 ms) |
| `make -s gate-full` | `PASS=25 FAIL=0 BLOCKED=3 NOT_IMPLEMENTED=0 SKIPPED=0`, **651 asserções**, 28 etapas, exit 0 (714 322 ms) — `net-matrix` **PASS 36/36** (619 485 ms) e `persistencia` **PASS** (`ok=11 falhas=0`) na mesma passada; `bench` PASS desta vez |
| `make -s gate-selftest` | `# gate_state=21 falhas=0 blocked=0` |
| `bash recriado/scripts/verify-backup.sh` | `ok=11 falhas=0 blocked=0` |

`BLOCKED` continuam `BLOCKED`, com causa: `interop` camada 3 (exige binário original/wine e
autorização), `lua` (sem interpretador no host), `lua-enc` (algoritmo não decodificado + `F23`).
Nada foi promovido a PASS por conveniência.

**Nota de ordem das operações (medição honesta, não retrabalho escondido).** A primeira execução do
`gate-full` desta rodada deu `FAIL=1`, etapa `persistencia`, com motivo medido: o snapshot declarado
(`workspace/backups/mu2-v2.bundle` + `MANIFEST`) era da rodada anterior, então a checagem acusou
`divergencia de conteudo dentro do declarado ... src/db.c tests/dbctl.sh ...` e
`arquivos fora do snapshot sao declarados FALHA extras=5 declarados=0` — além de `publicacao: origin/...`
falhar porque os commits ainda não tinham ido para o remoto. O snapshot foi regravado pelo ritual da
D2-09/R-2 (`git commit-tree HEAD:recriado` → orphan `mu2-snapshot` @ `e2674fa4` → bundle de 401 476
bytes, 108 arquivos) e a segunda execução passou. O bundle anterior continua recuperável do histórico
do git, e **nada** foi publicado em `MuserverRecriado/`.

## 6. Limites declarados desta rodada

- **Não** há migração implementada nem testada: só a decisão e a recusa nomeada. Declarar migração
  concluída seria falso.
- A recusa de versão diferente da suportada é **fail closed**, não "quase compatível": um arquivo de
  formato futuro fica ilegível mesmo que o layout se sobreponha — é o preço de não adivinhar formato.
- **Não** foi alterado o contrato do protocolo v2, **não** houve integração do `mud2` com a
  persistência e **nada** foi publicado em `MuserverRecriado/` — a paridade de publicação continua
  como item de rodada própria (pendência 4 de §5.1).
- Queda de energia do host continua fora de alcance: o que se mede é a **chamada** de `fsync` antes do
  retorno, não a sobrevivência da mídia.
- **P07 segue risco aberto**: a contenção (remoção histórica na origem) não foi executada nem
  verificada nesta rodada; nenhuma varredura de segredo foi imprimida, nenhum backup foi restaurado.

# R-12 — F3: concorrência entre `mu2db_verify` e escrita, medida

Data: 2026-10-13 · branch `arena/cf1de8ce-muserver` · código no commit desta rodada (ver
`docs/CONTINUITY.md` §6) · natureza: **medição + suíte nova**, sem mudança de contrato.

Pergunta que este relatório responde, com evidência e não com leitura: **o que acontece quando a
verificação e a escrita se encontram?** A leitura de código sugeria recusa nomeada dos dois lados;
"sugeria" não é resposta. Aqui o escritor é um **processo real** usando a mesma biblioteca
(`tools/mu2dbcontend.c`, novo), não um `flock(1)` segurando lock — e a janela de encontro é
**determinística**, não sorte de agendamento.

## 1. Inventário dos bloqueios (medido no código, com linha)

| caminho | arquivo aberto como | lock | onde |
|---|---|---|---|
| abrir (existente) | `O_RDWR` | `flock(LOCK_EX\|LOCK_NB)` — **não bloqueante** | `src/db.c:797`, `:816` |
| abrir (novo) | `O_RDWR\|O_CREAT\|O_EXCL`, 0600 | idem, depois do `open` | `src/db.c:805`, `:816` |
| fechar | — | `fsync` + `flock(LOCK_UN)` + `close` | `src/db.c:890`, `:893` |
| **verificar** | `O_RDONLY` | `flock(LOCK_SH\|LOCK_NB)` — não bloqueante | `src/db.c:937`, `:946` |
| verificar (todas as saídas: formato, CRC, versão, fim) | — | `flock(LOCK_UN)` + `close` em **cada** `return` | `src/db.c:955`, `:961`, `:971`, `:981` |

Não há outro caminho de abertura: **toda leitura de dados passa pelo handle exclusivo** (não existe
API de leitura somente-leitura); o único consumidor que abre em `O_RDONLY` é `mu2db_verify`. É por isso
que a exclusão não é entre "leitor e escritor", e sim entre **escrita** e **varredura de integridade**.

Coerência entre caminhos: um único domínio de lock (`flock`), o mesmo arquivo, os dois lados em modo
não bloqueante, e liberação em todo caminho de saída — inclusive nos de erro (conferido por
`tests/db_test.c:709`, "verify que FALHOU também libera o lock").

## 2. Comportamento medido

Suíte nova: `tests/concorrencia.sh` — **27 casos, 0 falhas**, ~3,8 s, etapa `concorrencia` no portão
(agora 29 etapas, 643 asserções, exit 0). Ela roda com dados sintéticos em diretório temporário.

**(A) Escrita ativa, verificação chegando.** O escritor real abre, commita 20 transações e **continua
segurando o lock** até a suíte criar um arquivo de liberação (`--hold-until-arquivo`) — a janela é
fato, não corrida.

| pergunta | resposta medida |
|---|---|
| 12 tentativas de `verificar` durante a escrita | **12 recusas, 0 aprovações** |
| latência da recusa | pior caso **14 ms** (não há espera nem retry) |
| mensagem | `erro=arquivo travado por outro processo` + `detalhe=arquivo em uso: verificacao concorrente nao garantida (escritor ativo)` |
| falso positivo de corrupção | **0** (nenhuma recusa veio disfarçada de CRC/formato) |
| "ok" mentiroso | **0** |
| efeito no arquivo | tamanho **byte-idêntico** depois das 13 tentativas recusadas |
| leitura de dados (`stats`) durante a escrita | recusada (exit 1) — mesma regra, mesmo motivo |
| depois da liberação | verificar **aprova**, 21 contas (1 base + 20), 3 autenticações conferidas |

**(B) Verificação ativa, escrita chegando.** O caminho `verify` é curto por construção: não existe
modo "verify segurando o arquivo" (e inventar um só para o teste seria medir o teste). O que se segura
é o **mesmo lock que ele toma** — `LOCK_SH` por um processo independente — e a suíte confere o estado
de fora, sem converter o lock:
`flock -s -n <arquivo> -c true` entra (logo é compartilhado) e `flock -x -n <arquivo> -c true` não
entra (logo há lock).

| pergunta | resposta medida |
|---|---|
| escritor real com leitor ativo | **recusado, exit 3**, `erro=abrir` + `motivo=flock: arquivo em uso` |
| latência da recusa | **12 ms** (não bloqueia) |
| transações executadas antes da recusa | **nenhuma** (tamanho do arquivo inalterado; sem `hold=`/`# contend=` no rastro) |
| `verificar` com leitor ativo | **aprova** — `LOCK_SH` convive com `LOCK_SH` |
| após a liberação | escritor entra e o livro-caixa fecha (23 contas = 1 + 20 + 2) |

**(C) `flock` é *advisory*: o limite, medido.** Com `LOCK_EX` tomado por outro processo, `dd` de 32
bytes **lê o arquivo** (o kernel não impede), enquanto a **mesma** tentativa pela biblioteca é
recusada. A proteção existe porque **todos** os consumidores passam pela biblioteca; um leitor cru
(`cat`, `cp`, backup, ferramenta de terceiro) não é impedido de ver o arquivo no meio de uma escrita.
Isso está em teste, e não só em prosa, porque garantia que não se mede vira lenda.

**(D) Mesmo processo.** Coberto por `tests/db_test.c` (in-process, caso a caso): com o próprio handle
aberto (lock exclusivo no arquivo), `mu2db_verify` no **mesmo** caminho devolve `MU2DB_E_TRAVADO` com
motivo nomeado (`db_test.c:253-259`); a verificação **não** deixa lock pendurado (`:671`); a segunda
abertura do mesmo arquivo pelo mesmo processo é recusada (`:677-684`); e uma verificação **que falha**
também libera o lock (`:709-712`). O motivo é medido, não teórico: `flock` é por *open file
description*, então duas aberturas no mesmo processo também conflitam — e é por isso que o modo de
`verify` é **não bloqueante**: `LOCK_SH` bloqueante daria espera infinita contra o próprio processo.

**(E) Corroboração em rajada.** `tests/dbctl.sh` já faz a versão livre (40 verificações concorrendo com
20 escritas em 3 tentativas, com contadores dos dois lados) e cobra: sobreposição aconteceu, nenhuma
resposta fora do contrato, livro-caixa exato. Os dois testes medem a mesma coisa por ângulos
diferentes: um determinístico (janela garantida), outro por volume.

## 3. Discriminação: a suíte pega a remoção da proteção?

Mutação temporária em `src/db.c` (fora de cópia isolada do trabalho publicado; restaurada e conferida
por `sha256`), removendo o `LOCK_EX` da abertura:

| estado | resultado |
|---|---|
| com a mutação | **9 falhas**: `aprovado=12` na janela com escritor ativo, `stats` lê durante a escrita, o escritor **não** é recusado com leitor ativo |
| restaurado | `sha256` idêntico (`f2f4d58a…`) e suíte **27/27 verde** |

Ou seja: as asserções são sensíveis ao defeito que elas afirmam impedir. Uma suíte que passasse nos
dois estados não diria nada.

## 4. Garantias — o que é fato, e o que **não** é

O que o desenho **dá**, nas palavras que os testes sustentam:

1. **Exclusão mútua entre escrita e varredura de integridade**, com recusa imediata e nomeada dos dois
   lados — medida com dois processos reais (§2A, §2B).
2. **Não há leitura rasgada observável pela biblioteca**: um leitor sem o `LOCK_SH` não existe no
   código; e o escritor não pode estar aberto enquanto o `LOCK_SH` existe.
3. **Não há espera nem retry**: os dois lados usam `LOCK_NB`. Consequência prática: **não existe
   deadlock por lock** entre esses caminhos; a falha é explícita, não pendurada.
4. **Durabilidade antes do retorno**: operação implícita → `fsync` inline (`db.c:1103`); commit de
   transação → `fsync` (`db.c:1124`); `fechar` → `fsync` (`db.c:890`). O que se afirma é *"o `fsync`
   foi chamado antes de a API retornar"*; **não** se afirma sobrevivência a queda de energia — isso
   não é reproduzível neste ambiente (limite já declarado em `docs/DATABASE.md`).
5. **Lock liberado em todo caminho de saída**, inclusive nos de erro (`db_test.c:709`).

O que o desenho **não** dá, e por isso está escrito:

1. `flock` é **advisory** e **local ao host/kernel**: não protege contra consumidor que ignore o lock
   (§2C), nem contra acesso por NFS/SMB cujo servidor não honre o bloqueio, nem contra outro SO.
2. **Sem leitura concorrente de dados**: qualquer leitura de conta/personagem exige o handle
   exclusivo. Servir dois clientes simultâneos a partir do mesmo arquivo **não** é possível neste
   desenho — leitores serializam (a fila é do processo, não da biblioteca).
3. **Verificação e operação se excluem integralmente**: enquanto um serviço mantém o banco aberto,
   `verificar` **nunca** vai aprovar — vai recusar. Não é defeito: é a consequência de um escritor por
   arquivo.
4. O lock **não** diz nada sobre o conteúdo: ele impede concorrência, não corrupção. Integridade é o
   CRC32C por registro + cabeçalho, checado na abertura e por `mu2db_verify`.

## 5. Comparação de políticas (e recomendação — sem inventar decisão)

| política | o que muda | impacto medido/previsto | veredito |
|---|---|---|---|
| **(1) Recusa imediata nomeada — atual** | nada | recusa em ≤ 14 ms dos dois lados; zero espera; zero falso positivo; falha explícita para o operador | **manter** |
| (2) Retry com limite no `verify` | adiciona `sleep`+tentativas | não resolve o caso central: contra um **servidor** que mantém o handle aberto, o lock não é liberado em ms — qualquer teto só troca "recusa rápida" por "recusa lenta"; e retry no escritor pode mascarar disputa real | **não implementar** |
| (3) Espera bloqueante (`LOCK_SH` sem `LOCK_NB`) | muda a semântica de `verify` | **deadlock garantido** no caso legítimo do mesmo processo com o banco aberto (`db.c:943-945` documenta o motivo) | **recusar** |
| (4) Janela de manutenção (operacional) | **nenhuma linha de código**: parar o serviço, rodar `verificar`, subir | é a única forma de uma verificação **completa** existir enquanto há serviço; hoje a `admin` já expõe `/gate` e o operador controla o processo | **recomendar como procedimento**, documentado |
| (5) Verificar sobre **cópia** do arquivo | `cp` do arquivo (fora do lock) + `verificar` na cópia | a cópia pode ser rasgada se feita durante escrita (§2C) — serviria ao diagnóstico, **não** como certificação; custa espaço em disco | registrar como opção, **não** como garantia |

**Recomendação.** O comportamento atual (1) é o único sustentado pelo contrato vigente e pelas
medições; **não há mudança de código a fazer** por F3. O que falta é **procedimento**: a janela de
manutenção (4) precisa estar escrita para quem opera — ela é o caminho para uma verificação completa
com o serviço parado, e a opção (5) precisa estar marcada como não-certificadora. Nenhuma das duas
exige decisão de contrato; se em algum momento se quiser verificação **com** serviço rodando, isso é
decisão de produto (exigiria um segundo processo leitor ou um modo snapshot no arquivo) e **não** foi
tomada aqui.

## 6. Limites deste relatório

- Latências são deste host (medianas de 12–14 ms de recusa, dominadas pelo custo de `fork`+`exec` do
  CLI, não pelo lock). O que interessa é a **ordem de grandeza**: nenhuma tentativa ficou perto do
  teto de 2 s que a suíte cobra.
- O caso (B) usa um portador independente do **mesmo lock** que o `verify` toma (`LOCK_SH`), porque o
  caminho `verify` não tem modo "segurar aberto" — dizer que "o processo de verify segurou o arquivo"
  seria falso; dizer que "o lock que ele toma foi segurado" é exato.
- Não houve execução de binário do pacote original, nem leitura/escrita em `MuServer/`, nem uso de
  credencial, nem restauração de backup.

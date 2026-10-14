# R-11d — P07-x: `ClientSerial` estava em claro num relatório **nosso**; a sonda não o redigia

Data: 2026-10-13 (fuso do proprietário; 2026-10-14 UTC) · branch
`arena/cf1de8ce-muserver` · natureza: **achado de segurança próprio, corrigido na mesma rodada**, com
limite declarado.

Este relatório é a evidência de um achado que **não** veio de auditoria por leitura, e sim da varredura
anti-vazamento acrescentada à porta de testes nesta rodada (`workspace/tests/run_all.sh`, modo *por
valor*, sem allow-list). Está registrado aqui, e não dentro do `r6-relatorio.md`, porque aquele
relatório é medição fechada de outra rodada — este é o documento que corrige o que ele mediu.

**Nenhum valor de segredo é reproduzido neste arquivo**, em nenhuma forma (nem truncado, nem
mascarado, nem como hash). O achado é descrito por *chave*, *origem* e *alvo* — que é exatamente o que
a varredura reporta.

## 1. O que estava exposto

O valor real de `ClientSerial` — 16 caracteres alfanuméricos, chave de serial/licença do pacote de
referência (`MuServer/`) — saía **em claro** na coluna de valor de:

- `recriado/reports/r6-config.tsv` (arquivo **nosso**, versionado);
- `MuserverRecriado/reports/r6-config.tsv` (a cópia publicada dentro do monorepo).

O `r6-config.tsv` faz parte do conjunto de evidência do escopo `cfg` e é citado por
`docs/PROTOCOLS.md` e `docs/TESTING.md`. Ou seja: a exposição não estava num relatório esquecido —
estava num artefato de evidência ativo, regenerável, e publicado.

## 2. Causa raiz (medida, não suposta)

`tools/cfg_probe.py` classifica um par chave/valor como sensível por **dois** caminhos:

1. **nome da chave** (`CHAVE_SENSIVEL`: `pass`, `senha`, `token`, `secret`, `key`, `hwid`, `licen`…);
2. **forma do valor** (token longo tipo `AAAA.BBBB…`, GUID de 36 caracteres).

`ClientSerial` não caía em nenhum dos dois: a palavra `serial` não estava na lista de nomes, e o valor
tem 16 caracteres alfanuméricos — forma que não casa nem o padrão de token nem o de GUID. Resultado:
o par era classificado como `texto` e o valor cru era gravado na coluna 5.

O furo **de teste** é o mais importante daqui: `tests/cfg.sh` checava `classe=segredo ⇒ valor
redigido`. Um valor que o probe nunca classificou como segredo está fora do domínio dessa asserção —
o teste passava (15/15) com o valor em claro no relatório. Um teste que só valida a *própria*
classificação da ferramenta não prova que a ferramenta classificou tudo.

## 3. Correção

| # | arquivo | mudança | efeito medido |
|---|---|---|---|
| 1 | `tools/cfg_probe.py` | `"serial"` entra em `CHAVE_SENSIVEL` (com comentário datado) | `segredos_redigidos` **26 → 29**; as 3 linhas `ClientSerial` passam a `<REDACTED bytes=16 forma=dig+alfa>` |
| 2 | `reports/r6-config.tsv` | regenerado pela sonda (determinístico) | 663 linhas; **4 linhas** de diff vs. o arquivo anterior (as 3 de `ClientSerial` + nada mais — as demais linhas são idênticas) |
| 3 | `MuserverRecriado/reports/r6-config.tsv` | mesma gravação, conferida com `cmp` | paridade restaurada (`cmp` idêntico) |
| 4 | `tests/cfg.sh` | contagens 26→29 em t01/t07/t12 e dois casos fortalecidos | `16/16`, `cfg-selftest 5/5` |

O caso **t07b** é a correção do furo de teste: o teste passa a ter a **sua própria** lista de nomes de
chave sensível (`serial|senha|pass|pwd|token|secret|credential|key|hwid|licen|auth|sign`) e reprova se
alguma chave que case com ela tiver ficado fora de `classe=segredo` — **independente** da classificação
do probe. Exige ainda ≥ 3 chaves `serial` no relatório, para que a checagem não possa passar por
ausência de dado. A fixture sintética do autoteste ganhou um `ClientSerial` de forma realista
(16 alfanuméricos) e a asserção de que ele não aparece na saída.

## 4. Discriminação medida (o teste pega a regressão?)

| cenário | resultado |
|---|---|
| com a correção | `make -s cfg` → **16/16**, `cfg-selftest` **5/5** |
| revertendo **só** o fix do probe (`"serial"` fora da lista) | `not ok 1, 7, 7b, 12, 13` — **5 asserções** caem |
| varredura *por valor* no arquivo **novo** | `por_valor=0`, exit 0 |
| varredura *por valor* nos arquivos **antigos** (`git show HEAD:…`) | `por_valor=3`, **exit 1** (nos dois) |

As duas últimas linhas são o que dá significado ao número: a varredura reprova o arquivo anterior e
aprova o atual, medido nos dois estados.

## 5. Limite declarado — o que esta correção **não** resolve

A correção remove a exposição **contínua** (arquivo versionado no `HEAD`). Ela **não** remove o valor do
**histórico** do git: os commits anteriores desta branch — e o `main` pré-existente, que já publicou o
pacote inteiro — continuam contendo o valor. Contenção e rotação **na origem** são ação do proprietário
(P07 segue **ABERTO**). Não houve, em nenhum momento desta correção:

- impressão, cópia para outro arquivo ou uso do valor (nem para "teste");
- uso de credencial alguma, restauração de backup SQL, alteração de visibilidade do repositório;
- reescrita de histórico, `push --force` ou movimento de tag.

A varredura e o teste trabalham por *(chave, origem, alvo)* e pelo **nome** da chave — nunca pelo valor.

## 6. Lição registrada

1. **Artefato de evidência é superfície de exposição.** Um relatório gerado a partir de configuração
   sensível precisa ser tratado como dado sensível: redigir na origem, e varrer o *artefato*, não só a
   saída do terminal.
2. **Teste que confia na classificação do próprio objeto testado não cobre o objeto.** O t07b existe
   porque a única forma de pegar "a ferramenta não classificou" é uma segunda opinião independente.
3. **A lista de nomes sensíveis é finita e sempre atrás da realidade.** Por isso a varredura *por
   valor* (que não depende de conhecer o nome) é a camada dura; a *por forma* e a lista de nomes são
   triagem declarada, não garantia.

## 7. Onde a exposição antiga continua mencionada

Textos históricos (`reports/r6-relatorio.md` §3, `reports/r6-interop-relatorio.md`,
`reports/auditoria-rastreabilidade.md`, entradas antigas do `CHANGELOG.md`) seguem dizendo **26** valores
redigidos: são medição de rodada fechada e **não foram reescritos** (não se reescreve medição
histórica). A contagem vigente é **29**, e os documentos *vivos* que a citam foram atualizados nesta
rodada: `README.md`, `docs/SECURITY.md`, `docs/TESTING.md`, `docs/PROTOCOLS.md`,
`docs/CURRENT_STATE.md`, `docs/BUILD_AND_RUN.md`, `docs/DECISIONS.md`.

A árvore publicada `MuserverRecriado/` recebeu **apenas** o reparo do artefato sensível
(`reports/r6-config.tsv`); os textos dela continuam sendo o snapshot da rodada de publicação, como o
`DIV_OK` do verificador declara. Reparar o texto lá é tarefa da próxima publicação de paridade
(registrada em `docs/NEXT_TASK.md`), não uma edição à mão.

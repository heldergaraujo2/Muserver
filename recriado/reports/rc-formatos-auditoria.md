# Etapa C — auditoria de classificação dos formatos encontrados

Escopo: separar **assinatura identificada** de **formato parcialmente reconhecido** e de **formato
efetivamente decodificado**, com a evidência de cada caso e o que explicitamente **não** está
decodificado. Fonte primária: `reports/r5-formatos-modelo.tsv`, `reports/r5-relatorio.md` e medições
novas desta etapa sobre a referência em `MU_REF_DATA` (somente leitura).

Nenhum byte foi escrito na referência. Nenhum campo, tamanho máximo ou semântica foi inventado:
onde a estrutura não foi determinada, a linha diz "não decodificado".

## 1. Definição operacional das três categorias

| Categoria | Critério para usar | O que **não** autoriza concluir |
| --- | --- | --- |
| **assinatura identificada** | há bytes iniciais ou invariantes de tamanho reproduzíveis em muitos arquivos | que o conteúdo foi lido |
| **parcialmente reconhecido** | há invariantes medidos (tamanho, marcador, delimitador, periodicidade) mas o layout dos campos não foi determinado | nomes de campos, tipos, limites ou semântica |
| **efetivamente decodificado** | existe transformação reproduzível que converte o arquivo em conteúdo verificável (texto legível, formato público, ou âncora de conteúdo que não surge por acaso) | que todo o formato está decodificado — só a camada demonstrada |

A regra que motivou esta auditoria: **bytes iniciais identificados não são formato decodificado**.
Um prefixo constante diz que os arquivos pertencem a uma família; não diz o que há dentro.

## 2. Classificação por formato

| Formato | Contagem medida | Categoria | Evidência | O que **não** está decodificado |
| --- | --- | --- | --- | --- |
| `.ozj` | 106 (98 `jpeg_completo`, 5 `jpeg_sem_eoi`, 3 sem classe) | **efetivamente decodificado** (formato público) | magic JPEG; 98 terminam em EOI | nada relevante: é JPEG renomeado; os 5 sem EOI estão truncados |
| `.smd` | 8 | **efetivamente decodificado** (formato público) | texto que começa com `version 1` (StudioMDL) | nada: é texto; a semântica dos blocos é a do formato público |
| `.bmd` (família XOR-3) | **4 de 56** | **camada de ofuscação decodificada**; layout **não** decodificado | chave `ab fc cf` a partir do offset 0: `Item.bmd` 0,39% → 67,15% imprimível e revela o caminho `Data\Item\` no offset 12; os 3 `ItemTooltip_{eng,por,spn}.bmd` passam de ~0% para ~57% com a mesma chave e produzem o mesmo preenchimento | layout de registros, campos, tipos, tamanhos, índices, contagem de itens. O `255` exato da maior corrida de NUL **sugere** campo limitado a 1 byte de comprimento — hipótese, não conclusão |
| `.bmd` (restante) | 52 de 56 | **não classificado** | delta de imprimibilidade ≤ 40 (mediana do conjunto −0,16): a hipótese XOR-3 **não** vale para eles | tudo. `.bmd` abriga conteúdos heterogêneos; a extensão não identifica formato |
| `.ozt` | 313 (286 prefixo `00 00 02 00 00 00 02 00`; 26 prefixo `00 4b 6d 4b 00 00 02 00`; 1 sem prefixo) | **assinatura identificada** | dois prefixos dominantes e reproduzíveis | estrutura interna, se é textura, dimensões, profundidade de cor. Declarar "textura decodificada" aqui seria invenção |
| `.att` | 276 | **parcialmente reconhecido** | 276/276 com 65 539 B; `bytes[1:3] == ff ff` constante; `byte0` tem 2 valores; corpo 65 536 = 256×256 | o que os 65 536 bytes representam. A hipótese de grade 256×256 é aritmética, **não** confirmada por especificação |
| PE (`.exe`) | 22 (21 PE32/i386 + 1 PE32+ `PSGuard/Servidor.64.exe`) | **efetivamente decodificado** (formato público) até a proteção | cabeçalhos, seções e importações lidos | o que há nas seções `.themida`: ofuscadas/empacotadas, não distinguem `GameServer` × `GameServerCS` × `SpeedServer` |
| `ServerList.dat`, `MapServerInfo.dat` | 2 | **efetivamente decodificado** | são **texto** (`2f 2f` = `//`) apesar da extensão `.dat` | nada: conteúdo legível |
| `.bak` / `.reg` | 4 / 2 | **assinatura identificada** | cabeçalho `TAPE`; `.reg` em UTF-16LE | conteúdo não restaurado por decisão: restaurar backup original está fora de escopo |
| `.txt` de dados | 40 amostrados (39 tab, 1 vírgula) | **efetivamente decodificado** | texto delimitado | esquemas completos de cada arquivo (fora do escopo desta etapa) |
| `.lua` | 7 378 | **efetivamente decodificado** (texto-fonte) | texto; maior = 131 560 B / 7 318 linhas | nenhum: é fonte legível. **0** declarações de framing de pacote neles (medido na R-6) |

## 3. Evidência nova desta etapa

A conclusão da R-5 dizia que a hipótese XOR-3 era sustentada para `Item.bmd` e descartada na
mediana do conjunto. As duas coisas continuam verdadeiras, mas estavam incompletas:

1. **A chave deixou de ser plausibilidade e passou a ser confirmada.** Zeros e o preenchimento do
   texto claro produzem no arquivo cifrado o padrão repetido `fc cf ab`, que é exatamente a chave
   `ab fc cf` rotacionada — o padrão aparece centenas de milhares de vezes. Além disso, o offset 12
   decodifica para o caminho ASCII `Data\Item\`, que não aparece por acaso.
   → fixado em `tests/data.sh` caso 20.
2. **Existe uma família, não um arquivo só.** 4 dos 56 `.bmd` respondem à mesma chave:
   `Item.bmd` e `ItemTooltip_{eng,por,spn}.bmd`. Os três de localização produzem o mesmo
   preenchimento `dW3dW3d…` (108 504 ocorrências do triplo `64 57 33` no alinhamento de 3 em 3),
   o que mostra que o preenchimento é característica da família, não artefato de chave errada.
   → fixado em `tests/data.sh` caso 21 (valores medidos: 67,2% imprimível, 30% NUL,
   maior corrida de NUL = 255).
3. **O que isso não prova.** Decodificar a camada de ofuscação não é decodificar o formato:
   o layout de registros dos `.bmd` continua desconhecido, e o significado do preenchimento
   `W3d` não foi determinado — registrado como desconhecido, não explicado por conjectura.

Correção de registro: o caminho canônico é
`MuServer/Tools/Editores/MuEditor/Data/Item.bmd` (os relatórios da R-5 já traziam o caminho
completo; um resumo intermediário o havia abreviado para `MuEditor/Data/Item.bmd`, que não existe).

## 4. Golden tests para parsers de dados — decisão

A exigência era implementar golden tests **somente** onde houvesse estrutura suficientemente
conhecida, entradas representativas e expectativas verificáveis. Resultado da triagem:

| Candidato | Golden test? | Por quê |
| --- | --- | --- |
| Camada XOR-3 dos `.bmd` | **sim** (casos 20 e 21 de `tests/data.sh`) | transformação reproduzível, âncora de conteúdo verificável, valores medidos do artefato |
| Marcador e tamanho dos `.att` | já coberto (casos 1–4) | invariantes reproduzíveis em 276/276 |
| `.ozj` / `.smd` / `.lua` / `.dat` de texto | já coberto (casos 5, 6, 9–11) | formatos públicos ou texto |
| Layout de registros dos `.bmd` | **não** | estrutura não determinada; um golden test aqui exigiria inventar campos |
| Estrutura interna dos `.ozt` | **não** | só há prefixo; nada além dele foi determinado |
| Corpo dos `.att` | **não** | 65 536 bytes sem layout conhecido |

Escrever golden tests para os três "não" produziria expectativas inventadas — exatamente o que a
exigência proíbe.

## 5. Reprodução

```
make -s data          # 21 asserções com a referência presente (casos 20 e 21 são os novos)
SELFTEST_ONLY=1 bash tests/data.sh   # 4 asserções sem a referência (restore de bundle)
make -s gate          # 16 PASS / 0 FAIL / 1 BLOCKED / 300 asserções / exit 0
```

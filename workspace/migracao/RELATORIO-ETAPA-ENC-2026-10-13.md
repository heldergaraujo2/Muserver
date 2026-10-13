# Relatório da rodada — etapa `enc` (cifragem dos scripts Lua do cliente)

| campo | valor |
|---|---|
| data | 2026-10-13 |
| branch | `arena/cf1de8ce-muserver` |
| escopo | etapa científica `enc` do `NEXT_TASK.md` (a de maior prioridade: é a única lacuna com par claro/cifrado dentro do pacote) |
| resultado | **`BLOCKED`** — estrutura medida, algoritmo **não** identificado; `F23` `BLOCKED`. Nenhuma afirmação de decifração nem de compatibilidade com o cliente original |

---

## 1. Objetivo e escopo

Executar a etapa `enc` exatamente como declarada no `NEXT_TASK.md`: testar, **na ordem declarada**,
as hipóteses 1–5 (XOR com chave derivada; XOR de 1 byte; rotação/transposição por bloco; stream com
estado; não determinística), com **critério declarado antes** de ver o resultado, resultado registrado
como **número medido**, e prova de decifração apenas se o texto decifrado casar **byte a byte** com o
`ClientDecrypted`. Sem fechar: documentar o `BLOCKED` com o testado, o descartado e a medição.
Proibido inventar chave, algoritmo, formato ou compatibilidade.

Fora de escopo (e não feito): executar binário do cliente; modificar `MuServer/`; refazer a publicação
de `MuserverRecriado/`.

## 2. Evidências (medidas, com o comando)

Comando único da evidência: `python3 tools/enc_probe.py > reports/enc-probe.tsv` (somente leitura;
`MU_REF_DATA=../MuServer`), versionado em `recriado/reports/enc-probe.tsv` (51 linhas, sha256
`17b7da1354e93664668aa60e159669ca3c1b69d51d07f973ead45ebd2cfe7fba`). Prosa completa, com o método,
as listas de **fato comprovado / hipótese / desconhecido** e o código reproduzível das duas famílias
medidas à parte: `recriado/reports/enc-cifragem-lua.md`.

Números centrais (21 931 posições, 13 pares, 2 510 contextos repetidos):

| medição | valor |
|---|---|
| pares byte-idênticos (não cifrados) | **4/13** |
| cabeçalho fixo | **`28aa2191a6dd35f7`** em 9/9 |
| padding | **nenhum**: `len(cif) − 8 == len(claro) + nº de LF` em 9/9 |
| determinismo | **0 violações** em 6 pares com prefixo de claro comum; `local CONFIG = r` → `14cca1192748a387fd51b74ba7a41574` (igual cliente × servidor) |
| janela de 3 bytes do cifrado | **0/2 510** discordâncias (e **0/890** entre arquivos) |
| necessidade (controle) | com 2 bytes **952/4 403**; com 1 byte **9 813/14 068** |
| XOR/ADD de chave repetida (período ≤ 512) | **0** chaves; melhor k=224 com 16,50% (prefixo) e 7,09% (corpus) |
| ECB | **refutado**: `gcd(payloads)=1`; 8/9 não múltiplos de 8 nem de 16 |
| tabela de 1 byte (6 índices) | melhor caso erra **90,74%** (⊕) / **90,50%** (⊞) |
| ARX com rotações 0..3 | **0/16 384** sobreviventes |
| afim GF(2) / afim Z/256 | sistema **inconsistente** nas 400 primeiras amostras (8 bits); `LSB(C)=LSB(A)` em **54,47%** |
| `.exe` | Themida cobre **100%** do arquivo (`0x03da00+0x546000` = fim); magic do cabeçalho **não existe** no binário |

## 3. Arquivos alterados (todos dentro de `recriado/`; nada fora)

| arquivo | estado | blob local = remoto |
|---|---|---|
| `recriado/tools/enc_probe.py` | **novo** (probe somente-leitura, TSV determinístico < 1 s) | `2b064261a75d53ec2d504d87941d414da49e0ff5` |
| `recriado/tests/lua-enc.sh` | **novo** (27 asserções, `blocked=2`) | `c75beac22db4ce935788d5e5359676a1ac7417c9` |
| `recriado/tests/run_all.sh` | +1 etapa registrada (22 → 23 etapas) | — |
| `recriado/reports/enc-probe.tsv` | **novo** (evidência versionada) | `57e8a3226f6187c5b999404fc1da07b1e88da01a` |
| `recriado/reports/enc-cifragem-lua.md` | **novo** (relatório da investigação) | `cd1db08774cc749fe81aee4a9bf3ef625bbcf849` |
| `recriado/docs/CHANGELOG.md` | entrada da rodada | — |
| `recriado/docs/CURRENT_STATE.md` | mesa da rodada; próxima = `ozt` | — |
| `recriado/docs/CONTINUITY.md` | §5 (etapa nova, portão) e §6 (rodada) | — |
| `recriado/docs/NEXT_TASK.md` | `enc` fechada como `BLOCKED`; **`ozt` promovida a próxima** | — |
| `recriado/docs/ROADMAP.md` | §C e linha da R-8 | — |
| `workspace/backups/mu2-v2.bundle` + `MANIFEST.md` | backup do marco regravado (87 arquivos) | `91f40e3eb9a6df92553949953f9861748b18d237` (bundle) |

**Não tocados:** `MuServer/` (tree `fade04615fabd17778a0e2fd7adf032c8386c924`, sem alterações) e a pasta
publicada `MuserverRecriado/` (ver §7).

## 4. Testes e resultados (comandos, exit codes, números)

| comando | resultado |
|---|---|
| `python3 tools/enc_probe.py` (2×) | TSV **idêntico** nas duas execuções (determinismo do probe); < 1 s |
| `bash tests/lua-enc.sh` | **`lua-enc=27 falhas=0 blocked=2`**, exit 0 |
| `bash tests/run_all.sh` (portão, 23 etapas) | **18 PASS, 0 FAIL, 3 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED**, 23 etapas, exit 0, 69 816 ms; `assercoes=339` (a linha do resumo conta só PASS/FAIL — somando todas as etapas, incluindo as 27 novas, são **391**) |
| `bash tests/ref_check.sh` | **8/8** — `MuServer/` intacta, 6 `.lua` divergentes registrados, reversão conferida |
| `bash recriado/scripts/verify-backup.sh` | **ok=11 falhas=0 blocked=0** |
| `FULL=1 bash recriado/scripts/verify-backup.sh` | **ok=15 falhas=0 blocked=0** (inclui "bundle verify no clone", "restaurar árvore do bundle" e "HEAD local está no remoto") |
| `bash MuserverRecriado/scripts/verify-backup.sh` (pasta publicada) | **ok=11 falhas=0 blocked=0** — a pasta não foi tocada e segue consistente com o próprio bundle |

Comparação com a baseline anterior (22 etapas): **nenhum FAIL novo**; a etapa `lua-enc` entra como
`BLOCKED` com 2 motivos declarados (algoritmo não identificado; `F23` sem decodificador). Bloqueado
não foi promovido a aprovado em nenhum momento.

## 5. Problemas e limitações

1. **O algoritmo não foi identificado** — a função `(A[j], C[j-1..j-3]) → C[j]` tem domínio 2³² contra
   21 931 amostras; sem forma fechada não existe decodificador. **`BLOCKED`**, com causa.
2. **`F23` `BLOCKED`** — ela exige o decodificador; o golden implementado é de **bytes**
   (13 vetores `(claro, cifrado)` por sha256), não de decifração. Isso está dito no teste e no relatório.
3. **Extração estática inviável** — `.exe` com Themida cobrindo 100% do arquivo; executá-lo é vedado
   pela regra do projeto. Restam: mais pares claro/cifrado, desempacotamento autorizado, ou doc do
   fornecedor (`EncryptorTool.ini` só traz `Customername = MuEmuS6`).
4. **Inconsistência pequena corrigida em artefato vizinho:** o `workspace/backups/MANIFEST.md` trazia
   `259727` na linha do tempo do tamanho e `259931` no cabeçalho; medido, o valor era **259931** — a
   linha do tempo foi corrigida para o valor medido e a nota ficou registrada no próprio MANIFEST.
5. **Nenhuma compatibilidade com o cliente original foi testada** (o cliente não está no pacote).

## 6. Commit local e remoto

- Commit da etapa: **`983a409`** (`enc: etapa enc (cifragem do Lua do cliente) — estrutura medida,
  algoritmo BLOCKED`), 10 arquivos, 996 inserções.
- Commit do backup do marco: **`fc042c4`** (bundle + MANIFEST).
- **Push autorizado (sem force):** `git push origin arena/cf1de8ce-muserver` →
  `d1c0c75..fc042c4`; **`git ls-remote` lido de volta = `fc042c461e3e7b90c07af71e164d1d30c08248f5`**,
  igual ao HEAD local; conferido também pela API (`commits/fc042c46…`) e **blob a blob** para os 4
  arquivos novos (remoto == local).
- Este relatório é o **arquivo novo** da rodada (`workspace/migracao/RELATORIO-ETAPA-ENC-2026-10-13.md`),
  sem sobrescrever nenhum relatório anterior (`RELATORIO-PUBLICACAO-2026-10-13.md` e
  `RELATORIO-FECHAMENTO-2026-10-12.md` seguem intactos).

## 7. Situação da `MuServer/` e de `MuserverRecriado/`

- **`MuServer/`**: intacta — tree `fade04615fabd17778a0e2fd7adf032c8386c924`, `git diff` vazio,
  `ref-intacta` 8/8. O probe desta etapa é somente leitura (o teste confere o hash da árvore do
  material antes/depois) e o binário do cliente **não foi executado**.
- **`MuserverRecriado/` (a publicação da rodada anterior): intocada de propósito.** Ela é o snapshot
  de 174 arquivos daquela rodada, o validador dela está verde (`ok=11 falhas=0 blocked=0`) e o próprio
  validador só admite arquivos novos que casem com padrões declarados (`workspace/`, `docs/MIGRACAO*`)
  — acrescentar `tools/enc_probe.py`, `tests/lua-enc.sh` e um `reports/` novo exigiria **uma rodada de
  publicação nova** (espelhar arquivos, recontar, regravar snapshot + `MANIFEST.md` e refixar as
  constantes do transporte em `workspace/migracao/`). O que essa rodada precisa está listado no
  `NEXT_TASK.md` (seção "Passo zero"). Nada foi copiado para lá por conta própria.

## 8. Próxima tarefa da documentação

**`ozt` — estrutura interna das texturas** (`recriado/docs/NEXT_TASK.md`): medir o que é medível sem
especificação (distribuição de tamanhos, entropia por região, periodicidade, coerência entre tamanho e
os inteiros do cabeçalho, correlação com o `.ozj` do mesmo diretório), sem inventar campo, largura ou
semântica; conclusão só até onde a medição alcançar. Depois dela, `regressao-lua` (integridade
baseline ↔ patch ↔ árvore e presença das correções por análise estática).

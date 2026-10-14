# NEXT_TASK — o que vem agora

## Fila desta rodada (a primeira é a próxima tarefa executável)

| # | tarefa | por que agora | critério objetivo de conclusão | bloqueio |
|---|---|---|---|---|
| 1 | **inventário F1: fechar os 15 subsistemas** — faltam `src/db.c` (1637 L), `tools/mu2admin.c` (681 L), `src/mud2.c` 330–590 e os `docs/` | é o que separa "li o que interessava" de "inventariei", e cada subsistema fechado vira classificação A–E com evidência | cada subsistema com arquivos+símbolos, dependências, teste que o cobre e classificação A–E justificada por medição (não por nome de arquivo) | nenhum |
| 2 | **A3 — regressão estática dos 6 `.lua` patcheados** (fechada em 2026-10-13: `regressao-lua` 53/53) | — | **concluída** | — |
| 2 | **ligar `mud2` à persistência** (login na porta) | primeira ligação entre rede e estado durável — o que transforma "registro" em "servidor" | contrato de opcode novo **declarado** (não inferido do original), teste de ponta a ponta com reinício do serviço entre login e leitura, e `conform`/`golden` provando que o contrato antigo não mudou | **decisão de contrato**: o v2 não tem opcode de login e a autenticação na porta é ausente por escopo declarado — decidir isso não é operação reversível de rotina |
| 3 | **publicação do destino** (`MuserverRecriado`) | está reconstruído e não publicado | `ls-remote` conferindo o SHA do destino | `403` da instalação do GitHub App — ação do proprietário |
| 4 | **rodada de publicação nova** da pasta `MuserverRecriado/` — inclui repassar os textos atualizados (`r11d`, contagem 29 segredos redigidos, fila do `NEXT_TASK`) | ela é snapshot da rodada anterior e não tem `db.c`, `mu2dbctl.c`, `dbctl.sh` nem os docs desta rodada | checklist do `workspace/migracao/` + portão verde dentro da pasta | depende de 3 (ou de decisão explícita de publicar dentro do monorepo de novo) |

O que **não** entra nesta fila por decisão: interface gráfica do console; escrita em runtime no serviço
através de opcode administrativo novo (invalidaria o contrato hoje provado); executar binário do
pacote original; tocar em `MuServer/`.

## Passo zero (bloqueado no proprietário): publicar o destino

O destino está preparado, verificado e reprodutível (`workspace/migracao/`), mas **não publicado**:
`git push` responde `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`
e a API responde `Resource not accessible by integration` **no destino** (no repo de origem,
normal). É a seleção de repositórios da **instalação do GitHub App**, não a ACL do usuário
(`push=true` nos dois). Ação do proprietário: incluir `MuserverRecriado` na instalação com
*Contents: Read and write*; depois, `bash workspace/migracao/publicar-destino.sh` (push + `ls-remote`
+ clone independente + portão). Nada é afirmado publicado antes do `ls-remote` conferir.

**Pendência aberta pela etapa `enc` (2026-10-13):** a pasta `MuserverRecriado/` ficou **intocada de
propósito** — é o snapshot da rodada anterior, o validador dela só admite arquivos novos que casem
com padrões declarados, e levá-los para lá é uma rodada de publicação nova. Essa rodada precisa, no
mínimo: espelhar `tools/enc_probe.py`, `tests/lua-enc.sh`, `tests/run_all.sh`,
`reports/enc-probe.tsv`, `reports/enc-cifragem-lua.md` e os `docs/` atualizados; atualizar a contagem
de arquivos no `README.md` da pasta; regravar o snapshot dela e o `MANIFEST.md`; e refixar as
constantes do transporte em `workspace/migracao/preparar-destino.sh` (foi o que a rodada anterior fez
quando o `workspace/` arquivado mudou). Nada disso acontece automaticamente.

Estado de partida (medido em ambiente limpo, não relato): `make -s gate` → **18 PASS, 0 FAIL, 3 BLOCKED,
0 NOT_IMPLEMENTED, 2 SKIPPED, 23 etapas, 339 asserções contadas (391 somadas), exit 0**; `gate-selftest`
19/19; `make -s check` 182 asserções; `FULL=1 verify-backup.sh` 15/15. Branch `arena/cf1de8ce-muserver`.

As etapas que a rodada anterior listava como pendentes **foram fechadas**: `golden` (42/42),
`interop` (12/12, camada 3 BLOCKED), `fuzz` (12/12), `seguranca` (13/13), `admin` (24/24), `lua`
(13/13, execução BLOCKED) e agora **`lua-enc`** (27/27, `blocked=2` — ver a seção da etapa abaixo). A auditoria de rastreabilidade do roadmap inteiro está em
`../reports/auditoria-rastreabilidade.md`.

Restam três frentes. As duas primeiras **não dependem de nada externo**:

---

## Etapa `enc` — executada em 2026-10-13: estrutura medida, algoritmo `BLOCKED`

**Resultado: o algoritmo NÃO foi identificado.** A etapa foi executada até onde a medição alcança e
fechou como `BLOCKED`, com o que foi testado, o que foi descartado e por qual medição — relatório em
`../../reports/enc-cifragem-lua.md`, evidência em `../../reports/enc-probe.tsv`.

| pergunta | resposta medida |
|---|---|
| é determinística? | **sim** — 0 violações em 6 pares com prefixo de claro comum; `local CONFIG = r` → `14cca1192748a387fd51b74ba7a41574`, igual no arquivo do cliente e no do servidor |
| cabeçalho e padding | **8 bytes fixos** `28aa2191a6dd35f7` em 9/9; **sem padding** (`len(cif) − 8 == len(claro) + nº de LF`) |
| hipóteses 1–3 (XOR derivado, XOR 1 byte, rotação/transposição) | **refutadas** com número (0 chaves de período ≤ 512; `gcd(payloads)=1`) |
| hipótese 4 (stream com estado) | **família confirmada, algoritmo não** — janela de 3 bytes do próprio cifrado: 0/2 510 (e 0/890 entre arquivos); com 2 bytes, 952/4 403; o keystream depende do claro |
| hipótese 5 (não determinística) | **refutada** |
| `F23` | **`BLOCKED`** — exige decodificador, e não existe |

O que desbloquearia, em ordem de custo: (1) **mais pares claro/cifrado** — a lacuna hoje é cobertura
de contexto, não método; (2) desempacotar o `LuaEncryptorTool.exe` (Themida cobre o arquivo inteiro,
e o magic do cabeçalho não existe no binário) num host autorizado, **sem executar** o binário — ou
executá-lo com autorização explícita do proprietário; (3) documentação do fornecedor (o
`EncryptorTool.ini` só traz `Customername = MuEmuS6`).

---

## Próxima tarefa: `ozt` — estrutura interna das texturas

Hoje só existem dois prefixos medidos (`00 00 02 00 00 00 02 00` em 286 arquivos;
`00 4b 6d 4b 00 00 02 00` em 26; 1 sem prefixo). Nada além disso foi determinado, e **não** se deve
inventar campo, largura ou semântica.

Método: medir o que é medível sem especificação — distribuição de tamanhos, entropia por região,
periodicidade, coerência entre o tamanho do arquivo e os inteiros do cabeçalho, correlação com o
`.ozj` (JPEG) do mesmo diretório. Conclusão só até onde a medição alcançar; formato decodificado
exige reconstruir a imagem, e isso depende do cliente (meta D, hoje `BLOCKED`).

---

## Depois: `regressao-lua` — regressão dos 6 `.lua` patcheados

Os 6 arquivos de `MuServer/` que diferem do upload (`b5b84da`) têm baseline em
`workspace/changes/originals/` e patch em `workspace/changes/patches/`. `tests/ref_check.sh` casos
7–8 já fixam a contagem e a recuperabilidade. Falta o que a meta C pedia: **casos de teste sobre o
comportamento corrigido** (PC-1..PC-4), com checksum e diff por arquivo. Bloqueio parcial: sem
interpretador Lua não há execução; o que é testável sem interpretador é a integridade
(baseline ↔ patch ↔ árvore) e a presença das correções por análise estática.

---

## Etapas que permanecem bloqueadas (não começar por elas)

| Etapa | Bloqueio | Condição de desbloqueio |
|---|---|---|
| `interop` camada 3 | sem `wine`/`qemu-i386`; binários PE32/i386 com `.themida`; sem autorização | ambiente PE32/i386 + autorização + procedimento; evidência em `reports/r6-interop-real.tsv` |
| cliente original | o pacote não contém cliente; `main.exe` é saída do *Gerador de Main* | obter o cliente e autorização para executá-lo |
| `lua` execução | nenhum interpretador Lua no host | `lua`/`luajit` disponível |
| `enc` (algoritmo e `F23`) | função da janela não determinada (2³² de domínio contra 21 931 amostras) e `.exe` protegido por Themida (100% do arquivo) | mais pares claro/cifrado; desempacotar num host autorizado (sem executar) ou executar com autorização; documentação do fornecedor |
| capacidade absoluta | 2 vCPUs compartilhadas + ASan | host dedicado com requisito declarado |
| publicação real | sem alvo autorizado (403 em `MuserverRecriado`, não contornado) | decisão do proprietário |

## Pendência de segurança aberta (P07 — ação do proprietário, não do código)

A rodada P07-x acabou com a exposição **contínua** de `ClientSerial` no `reports/r6-config.tsv`
(detalhe em `reports/r11d-clientserial-em-claro-2026-10-13.md`), mas o valor **permanece no histórico
do git** — inclusive no `main` pré-existente, que publicou o pacote inteiro. Ações humanas, na ordem:
(1) **rotacionar** as credenciais e o serial na origem (o histórico já publicou os valores: remover do
`HEAD` não invalida cópia alguma); (2) tratar os 4 `.bak` de banco como incidente de divulgação de PII;
(3) externalizar segredos e, se for o caso, purgar histórico com `git-filter-repo`
(`workspace/tools/untrack_artifacts.sh`, dry-run por padrão). Nada disso é feito por esta linha de
trabalho, e nenhuma credencial é declarada encerrada antes da rotação confirmada.

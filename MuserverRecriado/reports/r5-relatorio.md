# R-5 — investigação de formatos por medição (2026-10-12)

Ferramentas: `tools/pe_probe.py`, `tools/att_probe.py`, `tools/mb_probe.py`, `tools/data_probe.py`
(Python 3.11, só stdlib, **somente leitura** sobre `MU_REF_DATA=/home/user/Muserver/MuServer`).
Suítes: `tests/pe.sh` (14 casos), `tests/data.sh` (19 casos).
Dados brutos versionados: `r5-pe.tsv`, `r5-formatos-att.tsv`, `r5-formatos-modelo.tsv`, `r5-dados.tsv`.

Este relatório separa **observação** (medido e reproduzível), **hipótese** (explicação ainda não
confirmada), **conclusão** (decisão que a medição autoriza) e **limitação** (o que este ambiente
não consegue responder). Nada aqui comprova compatibilidade com o cliente original.

---

## 1. PE — executáveis e bibliotecas

**Observação.** 22 `.exe` no pacote, todos PE válidos: **21 PE32/i386 + 1 PE32+/x86_64**
(`PSGuard/Servidor.64.exe`, o único 64 bits). 49 `.dll`: 45 i386 + 4 x86_64. Subsystem `gui` em
todos os `.exe`. Âncora de integridade usada nos testes: `ConnectServer/ConnectServer.exe` =
380 416 B, sha256_16 `f25eecb6c65214b7`, timestamp PE 1506998062, seções
`.text,.rdata,.data,.rsrc,.reloc`.

**Observação (proteção).** Seção `.themida` em `GameServer.exe`, `GameServerCS/GameServer.exe`,
`DiscordServer.exe` e `.boot` em `PSGuard/Monitor.exe` e `PSGuard/Servidor.32.exe`. Nesses
binários as seções não têm nome legível e a análise estática para aí. `DataServer.exe` tem
`.fptable`.

**Observação (palavras-chave por import/string).** `CreateIoCompletionPort` em 5 arquivos
(10 ocorrências); `luaL_` em 4 arquivos (176 ocorrências); `WSARecv`/`WSASend` no
`ConnectServer`. **Zero** ocorrências de `PacketSize`, `HEAD_SIZE`, `opcode`, `IOCP` (como
string) e das portas `55557`/`44406`/`55960`/`55970`.

**Conclusão.** O `ConnectServer` usa I/O de conclusão (IOCP) e o `GameServer` tem Lua ligado
estaticamente. As portas não vivem nos binários: vivem nos `.ini` (coerente com a auditoria da
R-3).

**Limitação.** Procurar string não achar ≠ recurso ausente: o nome pode ser montado em tempo de
execução, vir de tabela de imports sem string, ou estar dentro de seção protegida. O inverso
também vale: achar `luaL_` não diz *qual* API de script o servidor expõe ao jogo.

## 2. `.att` — atributo de terreno

**Observação.** 276 arquivos, **um único tamanho em todo o pacote: 65 539 B**. `bytes[1:3] == ff ff`
em **276/276**. `byte0` **não é constante**: dois valores medidos, `0x00` e `0x20` (a suposição
inicial de prefixo fixo `00ffff` falhou em 3 arquivos — ver §6). `byte3` tem 7 valores distintos
{0,1,4,5,8,10,12}. O corpo tem 65 536 B = 256 × 256. 151 valores distintos no conjunto; os mais
frequentes: 4 (6 075 639), 12 (5 655 636), 0 (4 671 085), 8 (1 392 756), 1 (152 431).

**Hipótese.** Grade 256 × 256 de um byte por célula, com os valores baixos funcionando como
*bitmask* de flags de terreno. Não confirmada por especificação alguma presente no pacote.

**Conclusão.** O invariante que se pode afirmar por medição é `tamanho == 65539 && bytes[1:3] ==
ffff`; é exatamente isso que `att_probe.py` aceita e que `tests/data.sh` cobra (276/276).

## 3. Modelos, texturas e `.bmd`

**Observação.** `.bmd` 56, `.ozt` 313 (prefixo `0000020000000200`), `.ozj` 106 (98 JPEG completos
+ 5 sem EOI + 3 não classificados; **todos** começam com `ffd8`), `.smd` 8 (todos texto começando
com `version 1\nnodes`).

**Hipótese testada por medida (XOR de 3 bytes em `.bmd`).** Sustentada para
`Tools/Editores/MuEditor/Data/Item.bmd`: imprimível 0,39% → 67,04% com chave `abfccf` (delta
**+66,65**), fase deslocada pelo prefixo de 4 bytes. Fraca em `Skill.bmd` (+13,09). Na **mediana
do conjunto o delta é −0,16**, ou seja a hipótese **não vale** para a maioria dos `.bmd`.

**Conclusão.** `.bmd` abriga conteúdos de naturezas diferentes: o banco de dados do MuEditor é
texto ofuscado por XOR-3; os `.bmd` de modelo não são. Qualquer decodificador precisa distinguir
os dois casos por caminho/tamanho, não por extensão.

## 4. Dados, scripts e backups

**Observação.** `ServerList.dat` (1 109 B) e `Data/MapServerInfo.dat` (2 453 B) **são texto**:
começam com `2f2f` (`//`), apesar da extensão `.dat`. `Data/MapManager.txt` (33 549 B) idem. Dos
40 `.txt` de dados amostrados, **39 são tab-delimitados e 1 usa vírgula**
(`Data/Custom/CustomGuildReign.txt`, 15 linhas). Maior `.txt`: `EventItemBagManager.txt`,
1 306 linhas, 1–18 colunas.

**Observação (Lua).** Maior script: `Data/Script/Scripts/UpgradeMachine/Config.lua`,
131 560 B / 7 318 linhas. Maior linha medida: 1 333 caracteres (`Musaffe/Windows.lua`, em duas
cópias idênticas).

**Observação (backups).** `DB/`: 4 `.bak` com cabeçalho `TAPE` (mídia de backup do SQL Server —
`MuOnline.bak`, `MuOnline_old.bak`, `back_hinet.bak`, `mw_v6.bak`), 2 `.reg` UTF-16LE e 1
`.rar`. **Nenhum foi restaurado nem aberto como banco**; só os 16 primeiros bytes foram lidos.

**Observação (criptografia de Lua).** **Não existe nenhum arquivo `.enc` no pacote.** Os únicos 2
arquivos com `luaenc` no nome são `Tools/Gerador de Main/LuaEncTool/LuaEncryptorTool.exe`
(5 782 016 B) e o `.pdb` correspondente. A auditoria da R-3 registrava "3 `.enc`": eram 3 *matches*
de `*luaenc*`, e um deles já não existe. **Correção registrada, histórico preservado.**

**Conclusão.** Não há corpus de Lua criptografada para comparar; portanto qualquer afirmação de
compatibilidade de script fica sem base empírica nesta rodada.

## 5. Limites investigados (§10 do comando mestre)

| Limite perguntado | Resposta medida |
|---|---|
| Tamanho de script Lua | Maior arquivo 131 560 B; nenhum indício de limite atingido |
| Tamanho de linha Lua | Maior linha 1 333 caracteres; nenhum indício de limite atingido |
| Tamanho de pacote (rede) | **Não medido nesta rodada** — exige binário em execução (Windows/Wine) |
| Limite 3D/textura | `.ozt` 313 e `.ozj` 106 inventariados; dimensões não decodificadas |
| Grade de terreno | 256 × 256 por célula de 1 byte (hipótese) |

**Limitação geral:** nenhum binário do pacote foi executado (decisão D2-06: não executar binário
desconhecido). Tudo o que exigir observação dinâmica permanece `BLOCKED`, não `PASS`.

## 6. Falsificações e erros cometidos nesta rodada

| # | Mutação aplicada | Efeito medido | Estado |
|---|---|---|---|
| F8 | `att_probe.py` finge conformidade (`n_ok = total`) | `data.sh` exit 1, 1 falha (caso 16) | revertido, sha256 confere |
| F9 | `pe_probe.py` aceita arquivo não-PE | `pe.sh` exit 1, 2 falhas (casos 11, 12) | revertido, sha256 confere |
| F10 | `pe_probe.py` imprime caminho absoluto | `pe.sh` exit 1, 3 falhas (casos 3, 4, 10) | revertido, sha256 confere |
| F11 | `data_probe.py` ganha timestamp na saída | `data.sh` exit 1, 1 falha (caso 13) | revertido, sha256 confere |

Erros meus que as suítes pegaram antes de qualquer commit:

1. **Suposição a partir de amostra de 2 arquivos.** Assumi prefixo `.att` = `00ffff`; falhou em 3
   de 276 (`20ffff`). O invariante real é `bytes[1:3]`. Lição: medir a distribuição antes de
   assertar constante.
2. **`awk "\$5"` dentro de `eval`.** O bash expandia `$5` antes do awk ver o programa, e o teste
   falhava por sintaxe de awk, não por defeito do código. Trocado por uma função por caso, sem
   `eval`.
3. **`grep "a\tb"`.** Em BRE o `\t` é o literal `t`; o padrão nunca casava. Trocado por
   `grep -q $'a\tb'`.
4. **Relatório binário.** `decode('latin-1')` do BOM UTF-16 dos `.reg` injetava `NUL` no TSV
   (`data.tsv` virava arquivo binário para o grep). Corrigido com escape `\xNN`; o caso 14 de
   `data.sh` agora é a guarda de regressão (e o critério é *byte de controle*, não "não
   imprimível em locale C" — que daria falso positivo nos acentos dos nomes de diretório).
5. **Função que devolve o status do último `grep`.** `t14` "passava" ao contrário; corrigido com
   `return 0` explícito.
6. **Fixture de selftest que não testava o que dizia.** Meu `.att` "com marcador ruim" tinha
   `00ffff` e era aceito. Trocado por `000000`.

## 7. O que esta rodada NÃO diz

- Não decodifica `.att`, `.bmd`, `.ozt`, `.ozj`, `.smd` — só mede invariantes e testa uma hipótese.
- Não prova compatibilidade de protocolo, script ou asset com o cliente original.
- Não restaura banco, não executa binário, não abre porta, não altera `MuServer/`.
- Não mede desempenho (R-7 continua `BLOCKED` pelos critérios de validade).

# NEXT_TASK — o que vem agora

## Passo zero (bloqueado no proprietário): publicar o destino

O destino está preparado, verificado e reprodutível (`workspace/migracao/`), mas **não publicado**:
`git push` responde `403 Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2`
e a API responde `Resource not accessible by integration` **no destino** (no repo de origem,
normal). É a seleção de repositórios da **instalação do GitHub App**, não a ACL do usuário
(`push=true` nos dois). Ação do proprietário: incluir `MuserverRecriado` na instalação com
*Contents: Read and write*; depois, `bash workspace/migracao/publicar-destino.sh` (push + `ls-remote`
+ clone independente + portão). Nada é afirmado publicado antes do `ls-remote` conferir.

Estado de partida (medido em ambiente limpo, não relato): `make -s gate` → **18 PASS, 0 FAIL, 2 BLOCKED,
0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções, 22 etapas, exit 0**; `gate-selftest` 19/19;
`make -s check` 180 asserções; `FULL=1 verify-backup.sh` 13/13. Branch `arena/cf1de8ce-muserver`.

As etapas que a rodada anterior listava como pendentes **foram fechadas**: `golden` (42/42),
`interop` (12/12, camada 3 BLOCKED), `fuzz` (12/12), `seguranca` (12/12), `admin` (22/22) e `lua`
(13/13, execução BLOCKED). A auditoria de rastreabilidade do roadmap inteiro está em
`../reports/auditoria-rastreabilidade.md`.

Restam três frentes. As duas primeiras **não dependem de nada externo**:

---

## Próxima tarefa: `enc` — formato de cifragem do script Lua do cliente

### Por que esta primeiro

É a única lacuna técnica com **material de ataque completo dentro do pacote**: existe um par
conhecido. Se a cifragem for determinística e sem IV (o que é testável), há um ataque de texto
conhecido clássico, e o resultado é verificável byte a byte.

### O que existe (medido)

| Material | Caminho | Evidência |
|---|---|---|
| texto claro | `Tools/Gerador de Main/LuaEncTool/ClientDecrypted/System/ProtocolCore.lua` | 40 linhas legíveis, com `ClientProtocolRecv(Packet, PacketName)` |
| texto cifrado | `.../ClientEncrypted/System/ProtocolCore.lua` | começa em `28 aa 21 91 a6 dd 35 f7` |
| ferramenta | `.../LuaEncryptorTool.exe` + `.pdb` | não executada (regra do projeto) |
| configuração | `.../EncryptorTool.ini` | a ler |
| segundo par | `ServerDecrypted/` × `ServerEncrypted/` | confirma ou refuta hipótese em outro arquivo |

### Hipóteses a testar, em ordem

1. **XOR com chave derivada da ferramenta** (mesmo padrão da camada `.bmd`: a chave `ab fc cf`
   foi confirmada na Etapa C com âncora de conteúdo). Testar se o par satisfaz
   `claro[i] ^ cifrado[i] == chave[i % k]` para `k` pequeno.
2. **XOR com chave constante de 1 byte** (caso particular de 1).
3. **Rotação/transposição** por bloco (4 ou 8 bytes), verificável por periodicidade do XOR entre
   claro e cifrado.
4. **Stream com estado** (exige chave; se a chave não estiver em disco, `BLOCKED` com a causa).
5. **Não determinística** (IV/sal) — refutável comparando dois arquivos cifrados com o mesmo claro
   em posições diferentes.

### Critérios de aceitação

- Cada hipótese é testada por um critério declarado **antes** de olhar o resultado, e o resultado é
  registrado com o número medido (não "parece").
- Se uma hipótese decodificar o arquivo, a prova é: **o texto decifrado bate byte a byte com o
  `ClientDecrypted`** do mesmo caminho — não imprimibilidade, não semelhança.
- Confirmado o algoritmo, criar golden test com vetor de `(claro, cifrado)` e **F23**: alterar um
  byte do cifrado tem de fazer o decodificador acusar divergência no offset exato.
- Se nenhuma hipótese fechar: `BLOCKED` com o que foi testado, o que foi descartado e por qual
  medição. **Proibido** afirmar "cifragem identificada" sem casar o texto claro.

### Falsificação F23 (declarada desde já)

`F23` — decodificador de `.enc`: dado o par conhecido, corromper exatamente um byte do arquivo
cifrado deve produzir falha apontando o offset alterado, e o arquivo original do pacote permanece
intacto (sha256 conferido antes e depois). Se o decodificador engolir a corrupção, F23 reprova.

---

## Depois: `ozt` — estrutura interna das texturas

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
| capacidade absoluta | 2 vCPUs compartilhadas + ASan | host dedicado com requisito declarado |
| publicação real | sem alvo autorizado (403 em `MuserverRecriado`, não contornado) | decisão do proprietário |

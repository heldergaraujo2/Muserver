# Relatório da etapa `enc` — cifragem dos scripts Lua do cliente

| campo | valor |
|---|---|
| data | 2026-10-13 |
| branch | `arena/cf1de8ce-muserver` |
| material | `MuServer/Tools/Gerador de Main/LuaEncTool/` (30 arquivos; 13 pares claro/cifrado) |
| comando da evidência | `python3 tools/enc_probe.py` → `reports/enc-probe.tsv` (51 linhas, sha256 `17b7da13…`) |
| teste da etapa | `bash tests/lua-enc.sh` → `lua-enc=27 falhas=0 blocked=2`; etapa registrada no portão |
| **veredito** | **`BLOCKED`** — o algoritmo **não** foi identificado. `F23` **`BLOCKED`**. Nenhuma afirmação de compatibilidade com o cliente original |

Esta etapa **não** afirma ter decifrado, reproduzido ou descoberto a cifragem. O que existe é uma
**estrutura medida** (janela de 3 bytes), um conjunto de **famílias refutadas com número** e uma
lista de **desconhecidos**. O único critério de prova aceito era o texto decifrado casar **byte a
byte** com o `ClientDecrypted` — isso não aconteceu.

---

## 1. Veredito por pergunta

| pergunta | resposta | medição (chave do TSV) |
|---|---|---|
| A cifragem é determinística? | **sim** | `enc_determinismo_prefixo` = 0 violações em 6 pares com prefixo de claro comum; `enc_prefixo_conhecido` = `14cca1192748a387fd51b74ba7a41574` para `local CONFIG = r`, igual no cliente e no servidor |
| Tem cabeçalho fixo? | **sim, 8 bytes** | `enc_header8_presente` = 9/9 com `28aa2191a6dd35f7` |
| Tem padding? | **não** | `enc_tamanho_crlf` = 9/9 (`len(cif) - 8 == len(claro) + nº de LF`) |
| É XOR com chave repetida? | **não** | `enc_excl_xor_repetido` = 0 chaves com período ≤ 512; `enc_excl_xor_repetido_melhor` = melhor k=224 com 16,50% de acerto |
| É ECB? | **não** | `enc_excl_ecb` = `gcd(payloads)=1`, 8/9 payloads não múltiplos de 8 nem de 16 |
| É afim (linear) sobre GF(2) ou Z/256? | **não** | §7: sistema inconsistente nas 400 primeiras amostras nos 8 bits; `LSB(C)=LSB(A)` em 54,47% |
| É um stream com estado? | **sim, com estado de 3 bytes do próprio cifrado** | `enc_recorrencia_janela3` = 0/2510; `enc_recorrencia_janela2` = 952/4403 |
| O algoritmo está identificado? | **não** | a função da janela não foi determinada (2³² − 21 931 pontos sem amostra); nada casa o claro |
| Dá para decifrar? | **não** | sem a função não há decodificador; `F23` fica `BLOCKED` (não há o que corromper e conferir) |

---

## 2. Material e método

**Material** (inventário medido, não suposto): 13 pares claro/cifrado em duas árvores
(`ClientDecrypted/` × `ClientEncrypted/`, 12 pares; `ServerDecrypted/` × `ServerEncrypted/`, 1 par),
`EncryptorTool.ini` (38 B; único conteúdo: `[EncryptorTool]` / `Customername = MuEmuS6`),
`LuaEncryptorTool.exe` (5 782 016 B) e `LuaEncryptorTool.pdb` (8 196 096 B), além de
`ScriptSystem.premium` (766 B, **não classificado**: registrado por hash, sem afirmação).

**Regra respeitada:** o binário do cliente **não foi executado** (regra do projeto). O probe é
somente leitura: o teste confere que o hash da árvore do material é o mesmo antes e depois
(asserção 24 de `tests/lua-enc.sh`).

**Comandos (reproduzem todos os números deste relatório):**

```sh
cd recriado
python3 tools/enc_probe.py > reports/enc-probe.tsv   # mede; MU_REF_DATA=../MuServer por padrão
bash tests/lua-enc.sh                                # 27 asserções da etapa
bash tests/run_all.sh                                # portão inteiro (23 etapas)
```

**Modelo usado nas medições estruturais** (declarado antes de medir): seja `A` o texto claro com
`LF` contado a mais (`\n → \r\n`) e `C` o arquivo cifrado **inteiro**, com os 8 bytes de cabeçalho
como história inicial. O teste é: `C[j]` é função de `(A[j], C[j-1], C[j-2], C[j-3])`?

**Amostra:** 21 931 posições (9 pares cifrados), 2 510 contextos repetidos — 1 206 deles com
história profunda **diferente** (`A[j-1]`, `C[j-4]`, `C[j-5]`), o que dá poder discriminante à
medição.

---

## 3. Fatos comprovados (medidos)

1. **4 dos 13 pares não são cifrados** — são byte-idênticos ao claro: `ScriptMain.lua` (497 B),
   `Scripts/NewWindow/Config.lua` (699 B), `Scripts/TesteProtocol/Config.lua` (267 B),
   `Scripts/WindowTitle/Config.lua` (321 B). A ferramenta não cifrou esses quatro.
2. **Os 9 cifrados começam com o mesmo cabeçalho de 8 bytes** `28 aa 21 91 a6 dd 35 f7`
   (9/9), e o cabeçalho **não** aparece em nenhum outro ponto do material.
3. **Sem padding**: `len(cif) − 8 == len(claro) + (nº de `LF`)` em 9/9. Os bytes a mais existem e
   são exatamente a contagem de `LF`; o *valor* desses bytes não é decidido por esta medição (§6).
4. **Determinismo**: prefixo de claro comum ⇒ prefixo de cifrado comum (6 pares com prefixo comum,
   menor prefixo comum 33 B, 0 violações). O vetor de 16 bytes de `local CONFIG = r` é
   `14cca1192748a387fd51b74ba7a41574`, **igual** no arquivo do cliente e no do servidor.
5. **A cifragem é um stream com estado de 3 bytes do próprio cifrado**: `(A[j], C[j-1..j-3]) → C[j]`
   fecha com **0 discordâncias em 2 510 repetições**, inclusive **entre arquivos** (0/890 — previsão
   fora da amostra do arquivo) e com história profunda diferente (1 206/2 510). Com **2** bytes a
   mesma janela acusa **952/4 403** discordâncias; com **1** byte, **9 813/14 068**. Ou seja: 3 é o
   menor tamanho que fecha, e não é coincidência de vizinhança.
6. **Não há ambiguidade** na janela: 0/1 613 casos de mesma janela + claro diferente com o mesmo
   cifrado (condição necessária para uma decifração única).
7. **A dependência do claro é real**: `(C1,C2,C3) → (C^A)` acusa 1 149/3 735 discordâncias e
   `(C1,C2,C3) → (C−A mod 256)` acusa 1 082/3 735. O keystream **não** é função só da janela, logo
   não é um gerador de keystream alimentado pelos últimos 3 bytes do cifrado.
8. **Controle de alinhamento**: com o alinhamento declarado, 0/2 510; com alinhamento errado
   (claro cru + zeros no fim), 74/294. O alinhamento `LF → CRLF` é o que fecha.
9. **Entropia** (informação, não conclusão): claro 5,512 bits/byte; payload cifrado 7,916 bits/byte.

---

## 4. Desconhecidos (o que **não** foi determinado)

- **A função da janela.** `F: (A, C1, C2, C3) → C` tem domínio 2³² e temos 21 931 amostras em
  contextos quase todos distintos: não há cobertura para tabela, e nenhuma forma fechada testada
  fechou (§6). Sem `F` não existe decodificador.
- **O papel do cabeçalho.** Os 8 bytes são constantes nos 9 arquivos, mas não se sabe se são
  constante, versão, identificador ou estado inicial (o `+8` do tamanho mostra que **não** carregam
  o tamanho nem o checksum do conteúdo: `crc32` do claro de `ProtocolCore.lua` é `0eb4fcd7`, e do
  claro normalizado é `ee4d9535` — nenhum aparece no cabeçalho).
- **O valor dos bytes inseridos** onde havia `LF`: trocá-los por `00 00` mantém a contagem, o
  alinhamento e **também fecha** (0/2 510). A medição fixa a contagem, não o valor.
- **A tabela/constante da ferramenta.** O `.pdb` **tem** os nomes
  (`gFileProtectLuaXorTable`, `gFileProtectLuaHeader`, `CFileLuaProtect::EncryptFileA`,
  `CCRC32::Initialize`, `EncryptLua1`, `EncryptLua2`, `LuaProtect.cpp`, `GetLuaEncryptorTool.cpp`),
  mas o `.exe` está protegido por Themida: a seção `.themida` começa em `raw 0x03da00 + 0x546000`,
  terminando exatamente no fim do arquivo (`0x583a00` = 5 782 016 B, **100% do arquivo**), e o magic
  do cabeçalho **não existe** no binário. Extração estática da tabela está fora de alcance sem
  desempacotar o binário — e executá-lo é vedado pela regra do projeto.
- **Compatibilidade com o cliente original.** Não testada, não afirmada.

---

## 5. Hipóteses declaradas na tarefa, em ordem — resultado

| # | hipótese (como estava escrita em `NEXT_TASK.md`) | resultado | medição |
|---|---|---|---|
| 1 | XOR com chave derivada da ferramenta (padrão `.bmd`, chave `ab fc cf`) | **refutada** | `enc_excl_xor_repetido` = 0 chaves com período ≤ 512 sobre 21 931 B de keystream concatenado; a chave do `.bmd` não se aplica |
| 2 | XOR com chave constante de 1 byte | **refutada** | caso particular k=1 da anterior |
| 3 | Rotação/transposição por bloco (4/8 bytes) | **refutada** | `enc_excl_ecb` (gcd dos payloads = 1) e a própria estrutura: uma transposição não introduziria a dependência do claro medida em §3.5/§3.7 |
| 4 | Stream com estado (exige chave; sem chave ⇒ `BLOCKED` com a causa) | **confirmada como família; `BLOCKED` como algoritmo** | estado de 3 bytes do próprio cifrado, dependente do claro (§3.5–3.7); a constante/tabela não está em disco de forma extraível (§4) |
| 5 | Não determinística (IV/sal) | **refutada** | `enc_determinismo_prefixo` = 0 violações em 6 pares com prefixo comum; o vetor de `local CONFIG = r` é idêntico nos dois lados |

---

## 6. Famílias descartadas, com o número medido

| família | medição | onde |
|---|---|---|
| XOR/ADD com chave repetida de período k ≤ 512 | 0 candidatos; melhor k=224 com 16,50% de acerto (prefixo 2 048 B) e 7,09% no corpus | `enc_excl_xor_repetido`, `enc_excl_xor_repetido_melhor` |
| ECB (qualquer tamanho de bloco) | `gcd(payloads)=1`; 8/9 payloads não múltiplos de 8 nem de 16 | `enc_excl_ecb` |
| Keystream puro `C = A ⊕/⊞ f(C1,C2,C3)` | 1 149/3 735 (⊕) e 1 082/3 735 (⊞) discordâncias | `enc_keystream_janela`, `enc_diferenca_janela` |
| Tabela de 1 byte indexada por 6 índices de `(A,S1,S2,S3)` | melhor caso ainda erra **90,74%** (⊕) e **90,50%** (⊞) | `enc_excl_tabela_xor`, `enc_excl_tabela_soma` |
| ARX `((A^ka) + rot(S1,r1) + rot(S2,r2) + rot(S3,r3) + kc) mod 256`, `r ∈ {0..3}` | 0 sobreviventes em 16 384 combinações (verificação em 512 amostras **declaradas**) | `enc_excl_arx` |
| Afim sobre GF(2) (32 bits de entrada + viés, por bit de saída) | sistema **inconsistente** já nas 400 primeiras amostras, nos 8 bits | §7 (código no relatório) |
| Afim sobre Z/256 (`C = a·A + b`) | `LSB(C) = LSB(A)` em 54,47% (o caso afim exigiria 100% ou 0%) | §7 |
| CRC-32 padrão no cabeçalho/keystream | `crc32(claro)=0eb4fcd7`, `crc32(claro normalizado)=ee4d9535`: não aparecem no cabeçalho | §4 |

Os dois últimos itens foram medidos por este relatório (scripts ad-hoc, código abaixo); todos os
demais estão em `reports/enc-probe.tsv` e são reexecutaveis por `python3 tools/enc_probe.py`.

---

## 7. Os dois modelos que a medição fechou (código reproduzível)

**Afim sobre GF(2).** Features = 8 bits de `A` + 8 bits de cada byte da janela (32 bits) + viés.
Eliminação de Gauss sobre GF(2) com as 400 primeiras amostras, por bit de saída — rodado de dentro
de `MuServer/Tools/Gerador de Main/LuaEncTool/`:

```python
import pathlib
H = bytes.fromhex("28aa2191a6dd35f7")
pares = []
for d, e in (("ClientDecrypted", "ClientEncrypted"), ("ServerDecrypted", "ServerEncrypted")):
    for p in sorted(pathlib.Path(d).rglob("*.lua")):
        c = pathlib.Path(str(p).replace(d, e))
        if c.is_file() and p.read_bytes() != c.read_bytes():
            pares.append((p, c))
am = []
for p, c in pares:
    A = p.read_bytes().replace(b"\n", b"\r\n"); S = H + c.read_bytes()[8:]
    am += [(A[j], S[8+j-1], S[8+j-2], S[8+j-3], S[8+j]) for j in range(len(A))]

def bits(a, s1, s2, s3):
    v = 0
    for i, x in enumerate((a, s1, s2, s3)):
        for b in range(8):
            if x >> b & 1: v |= 1 << (i*8 + b)
    return v

for bit in range(8):          # resolve o sistema sobre GF(2) com as 400 primeiras amostras
    base = {}; ok = True
    for a, s1, s2, s3, c in am[:400]:
        m = bits(a, s1, s2, s3) | (1 << 32); rhs = (c >> bit) & 1
        while m:
            p = m.bit_length() - 1
            if p in base: bm, br = base[p]; m ^= bm; rhs ^= br
            else: base[p] = (m, rhs); break
        else:
            if rhs: ok = False; break
    print("bit %d: %s" % (bit, "sistema inconsistente nas 400 primeiras amostras" if not ok else "resolveu"))
print("amostras=%d; LSB(C)==LSB(A) em %.2f%%" % (len(am), 100*sum(1 for a,s1,s2,s3,c in am if (a&1)==(c&1))/len(am)))
```

Saída medida (2026-10-13):

```
bit 0: sistema inconsistente nas 400 primeiras amostras
bit 1: sistema inconsistente nas 400 primeiras amostras
bit 2: sistema inconsistente nas 400 primeiras amostras
bit 3: sistema inconsistente nas 400 primeiras amostras
bit 4: sistema inconsistente nas 400 primeiras amostras
bit 5: sistema inconsistente nas 400 primeiras amostras
bit 6: sistema inconsistente nas 400 primeiras amostras
bit 7: sistema inconsistente nas 400 primeiras amostras
amostras=21931; LSB(C)==LSB(A) em 54.47%
```

Inconsistência com 400 amostras significa: **não existe** mapa afim (linear + viés) que reproduza
nem essas 400 — muito menos o corpus. E para qualquer `C = a·A + b (mod 256)`, `LSB(C)` seria
constante ou igual a `LSB(A)`; medido: 54,47%.

---

## 8. Por que `BLOCKED` (e o que desbloquearia)

A estrutura está medida, mas o **algoritmo não**: a função da janela não é nenhuma das famílias
testadas e não há cobertura de amostras para tabelá-la (2³² de domínio contra 21 931 amostras,
concentradas em contextos repetidos de trechos repetitivos de Lua). Sem a função **não existe
decodificador**, e sem decodificador `F23` não tem o que testar.

Condições de desbloqueio (nesta ordem de custo):

1. **material novo**: mais pares claro/cifrado (idealmente cifrados pela mesma ferramenta), para
   cobrir contexto — o ataque é de texto conhecido e a lacuna hoje é cobertura, não método;
2. **desempacotar o `LuaEncryptorTool.exe`** (Themida) num host autorizado, obtendo
   `gFileProtectLuaXorTable`/`gFileProtectLuaHeader` **sem executar** o binário do cliente — ou
   executá-lo com autorização explícita do proprietário (regra atual: não executar);
3. **documentação do fornecedor** (`EncryptorTool.ini` só traz `Customername = MuEmuS6`).

---

## 9. `F23` e o golden test: o que existe hoje

- **`F23` — `BLOCKED`.** Ela exige um **decodificador** para corromper um byte do cifrado e exigir
  erro no offset exato. Como o algoritmo não foi identificado, não há decodificador. Registrado como
  bloqueio com causa em `tests/lua-enc.sh` (`blocked=2`) — **nunca** como aprovado.
- **Golden de bytes (o que é possível hoje).** `tests/lua-enc.sh` fixa os **13 vetores
  `(claro, cifrado)` por sha256** (`reports/enc-probe.tsv`, chaves `enc_par_*`), mais cabeçalho,
  relação de tamanho, determinismo e os vetores de prefixo. Isso trava **regressão do material** —
  e é explicitamente *não* um vetor de decifração.

---

## 10. O que foi implementado nesta etapa

| arquivo | o que é |
|---|---|
| `tools/enc_probe.py` | **novo**: probe somente-leitura; mede os 13 pares e imprime o TSV (determinístico, < 1 s) |
| `tests/lua-enc.sh` | **novo**: 27 asserções com critério declarado no rótulo; `blocked=2` (`F23` + algoritmo) |
| `tests/run_all.sh` | +1 etapa registrada (`lua-enc`, obrigatória) — o portão passa de 22 para **23 etapas** |
| `reports/enc-probe.tsv` | **novo**: evidência versionada da medição (51 linhas, sha256 `17b7da13…`) |
| `reports/enc-cifragem-lua.md` | este relatório |
| `docs/CHANGELOG.md`, `docs/CURRENT_STATE.md`, `docs/CONTINUITY.md`, `docs/NEXT_TASK.md`, `docs/ROADMAP.md` | continuidade: `enc` fechada como `BLOCKED` documentada; próxima é `ozt` |

**Portão com a etapa nova** (`bash tests/run_all.sh`, 2026-10-13): **18 PASS, 0 FAIL, 3 BLOCKED,
0 NOT_IMPLEMENTED, 2 SKIPPED, 23 etapas, exit 0, 69 816 ms**. A contagem `assercoes=339` do resumo
conta apenas etapas PASS/FAIL (regra do próprio portão); somando todas as etapas, incluindo as 27
novas, são **391**. Comparação com a rodada anterior (22 etapas): nenhum FAIL novo; `lua-enc` entra
como `BLOCKED` (2 motivos), exatamente como declarado — bloqueado não virou aprovado.

**Publicação:** a pasta `MuserverRecriado/` **não foi tocada** nesta etapa — ela é o artefato
publicado da rodada anterior e o validador dela (`scripts/verify-backup.sh`, que segue verde:
`ok=11 falhas=0 blocked=0`) só admite arquivos novos que casem com padrões declarados
(`workspace/`, `docs/MIGRACAO*`). Levar esta etapa para dentro dela exige uma **nova rodada de
publicação** (espelhar arquivos, regravar o snapshot e o `MANIFEST`, atualizar as listas declaradas
e as constantes do transporte em `workspace/migracao/`) — registrado em `docs/NEXT_TASK.md`.

---

## 11. Limitações

- Nada aqui autoriza dizer que "a cifragem do MuEmuS6 é X". O que se sabe: determinística, sem
  padding, cabeçalho fixo de 8 bytes, stream com estado de 3 bytes do próprio cifrado dependente do
  claro — e **nada** sobre a forma fechada da função.
- Os números valem para o material desta pasta (30 arquivos). O `ServerEncrypted/` tem **1** par, o
  que não muda a estrutura, mas também não a confirma em larga escala do lado servidor.
- Nenhuma compatibilidade com o cliente original foi testada (o cliente não está no pacote).

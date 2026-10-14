# R-6 — protocolo e interoperabilidade (2026-10-12)

Novos: `tools/cfg_probe.py` (configuração, com redação de segredos), `tools/wire_probe.py`
(conformidade byte a byte), `tools/matrix_check.py` (validador da matriz), `tests/conform.sh`
(15 cláusulas), `tests/cfg.sh` (15 casos). Alvos `make conform`, `make matriz`, `make cfg`,
`make cfg-selftest`. Evidências: `r6-matriz.tsv`, `r6-config.tsv`, `r6-endpoints.tsv`,
`r6-conform.tsv`, `r6-gate.tsv`.

## 1. As três camadas, sem confusão

| camada | o que afirma | estado |
|---|---|---|
| 1. conformidade interna do v2 | a implementação obedece ao contrato escrito em `include/mu2/mu2.h` | **comprovada**: 15/15 cláusulas (`make conform`) |
| 2. compatibilidade observada | coincidências medidas entre o v2 e artefatos do pacote | matriz com 12 linhas, confiança declarada por linha |
| 3. compatibilidade comprovada por interop | o v2 fala com o software original | **BLOCKED** — exige binário original em execução |

Passar na camada 1 **não** afirma nada sobre a 3. Os opcodes do v2 (`0x0001`/`0x0002`/`0x0003`) não
são opcodes do MU Server e continuam não sendo.

## 2. Endpoints medidos (camada 2)

`cfg_probe.py` sobre 19 `.ini` (655 pares chave/valor):

| serviço | chave | valor |
|---|---|---|
| ConnectServer | `ConnectServerPortTCP` / `ConnectServerPortUDP` | **44406** / **55557** |
| DataServer | `DataServerPort` | 55960 |
| JoinServer | `JoinServerPort` | 55970 |
| JoinServer → ConnectServer | `ConnectServerAddress` / `ConnectServerPort` | `127.0.0.1` / 55557 |
| DiscordServer | `DiscordServerPort` | 55990 |
| MHPServer | `MHPServerPort` | 55999 |
| PSGuard | `PortaPadrao` | 55998 |
| **cliente** (`MainInfo.ini`, 2 versões) | `IpAddressPort` | **44405** |
| editores | `PORT` (SQL) | 1433 |

**Divergência medida, não resolvida:** o cliente aponta `44405` (com IP externo) enquanto o
ConnectServer escuta `44406`. Registrada como hipótese na matriz (confiança média) com o próximo
passo dito com clareza: só captura de tráfego real responde, e isso está `BLOCKED`.

Confirma a medição da R-5: **nenhuma porta aparece como string nos 22 `.exe`** — a configuração é a
fonte de verdade.

## 3. Segredos no pacote original (achado de segurança)

A configuração original guarda **credenciais em claro**: senha global no `JoinServer.ini`, token de
bot no `DiscordServer.ini`, hardware id de cliente, e chaves `EncDecKey1/2` no `MHPServer.ini`.
Medido: **26 valores sensíveis** em 19 arquivos.

Regra aplicada e testada: `cfg_probe.py` **nunca** imprime valor de chave sensível (substitui por
`<REDACTED bytes=N forma=...>`), e a detecção é por nome de chave **e** por forma do valor (token
com nome inocente também é redigido). Os casos 7, 8, 11 e 13 de `tests/cfg.sh` cobram isso; nenhum
valor real foi copiado para arquivo versionado — conferido: 0 linhas sensíveis não redigidas nos
relatórios publicados.

**Ação do dono:** rotacionar essas credenciais antes de qualquer exposição do pacote.

## 4. Conformidade do v2 (camada 1) — 15 cláusulas

Quadro medido em `src/wire.c`: `code(2 LE) + size(2 LE) + corpo`, onde `size` é o comprimento
**total**. Verificado com bytes exatos, inclusive quadros inválidos de propósito:

| cláusula | verificação | resultado |
|---|---|---|
| C-01 | PING devolve os mesmos 4 bytes, corpo vazio | `01000400` → `01000400` |
| C-02 | ECHO devolve o corpo byte a byte | `02000700616263` idêntico |
| C-03 | `MU2_MAX_BODY`=2048 aceito | resposta de 2052 B |
| C-04 | corpo 2049 (`size`=2053) rejeitado | 0 bytes + `rejects` incrementa |
| C-05 | `size`=2 (< cabeçalho) rejeitado | 0 bytes + `rejects` incrementa |
| C-06 | `size`=3000 (> máximo) rejeitado | 0 bytes + `rejects` incrementa |
| C-07 | campo de tamanho é little-endian | `size=0x0700` lido como 1792, eco completo |
| C-08 | opcode `0x00ff` descartado sem derrubar a conexão | PING seguinte respondido |
| C-09 | quadro fragmentado (120 ms entre escritas) | respondido |
| C-10 | dois quadros num único `write` | duas respostas |
| C-11 | D2-17: corpo de STATS começa em `"STATS "` | sem deslocamento de 4 bytes |
| C-12 | 9 campos de métrica na ordem do contrato | regex exata sobre a linha |
| C-13 | quadro inválido não vaza bytes parciais | 0 bytes, não resposta truncada |
| C-14 | perfis `orig` e `mur0` equivalentes | 5/5 nos dois, mesmos recebidos |
| C-15 | **F15**: expectativa errada é detectada pela sonda real | real ≠ 0, mutada = 0 |

C-15 é falsificação diferencial (cópia mutada em diretório temporário): se alguém neutralizar a
comparação da sonda, os dois lados concordam e o caso falha — "15/15" não pode ser produzido por
uma sonda que sempre diz OK.

## 5. Matriz de evidências

`r6-matriz.tsv`, 12 linhas, 9 colunas (hipótese · fonte · método · resultado · limitações ·
confiança · teste · conclusão · próxima). **Toda linha cita o comando que a reproduz**, e isso é
cobrado pelo portão: a etapa `matriz` roda `tools/matrix_check.py` e falha se alguma linha não tiver
teste reproduzível, confiança fora de `{alta, media, baixa, nenhuma}`, ou coluna curta.

Duas linhas registram honestamente o que **não** foi medido (`compatibilidade com o cliente
original`, `limite de pacote do original`): resultado `NAO MEDIDO`, confiança `nenhuma`, conclusão
`NENHUMA conclusao permitida`. Estado `BLOCKED`, não reprovado.

## 6. Papéis dos componentes (o que a evidência sustenta)

- **ConnectServer**: porta de entrada TCP 44406 + UDP 55557; IOCP ligado (import medido); é o alvo
  do JoinServer em `127.0.0.1:55557`.
- **JoinServer**: 55970, ODBC `MuOnline`, autenticação com `MD5Encryption = 0` e senha global.
- **DataServer**: 55960, ODBC `MuOnline`, `AdvancedLog`.
- **DiscordServer**: 55990, bot com token próprio — integração externa, não caminho de jogo.
- **MHPServer**: 55999, com `EncDecKey1/2`, `MemoryGuardNumber`, `MacroProtectNumber` — papel de
  anti-trapaça medido pelos nomes e valores, **não** confirmado por execução.
- **PSGuard**: 55998, 47 chaves de proteção (`ConexoesPorIP`, `TempoCC`, `DisableMD5`).
- **GameServer × GameServerCS × SpeedServer**: a dúvida continua **aberta**. Ambos os GameServer têm
  `.themida`; nada nesta rodada os distingue por evidência. Registrado como lacuna, não como
  suposição.

## 7. Falsificações e defeitos desta rodada

| # | mutação | efeito medido | estado |
|---|---|---|---|
| F15 | comparador do `wire_probe.py` neutralizado (`ok = True`) | `conform` caso 15 detecta a diferença | permanente, em cópia temporária |
| F16 | linha de matriz sem comando reproduzível | `matrix_check.py` exit 1 (2 problemas apontados) | permanente, etapa `matriz` no portão |

F17 (do plano) perdeu o objeto: a etapa `conform` já está no registro e passa a `PASS`, e o
`gate-selftest` caso 19 passou a cobrir o defeito real que apareceu no lugar dele — `conform` foi
criada sem remover o placeholder `NOT_IMPLEMENTED`, a mesa imprimiu a etapa duas vezes e contou as
asserções em dobro (244 em vez de 229). Corrigido removendo o duplicado e acrescentando guarda: nome
de etapa duplicado agora faz o portão sair **2** com erro explícito.

Outros três defeitos meus, todos pegos pelos próprios testes antes do commit:
1. `od -An -tx1` sem `-v` colapsa linhas repetidas em `*` — 2048 bytes de `'a'` viraram 33
   caracteres de hex inválido (o `-v` corrige).
2. `reply_ascii` do `wire_probe.py` ignorava `--skip`, então a asserção de C-12 comparava o
   cabeçalho escapado em vez do corpo.
3. `awk -F= '/^reply_ascii=/{print $2}'` cortava a linha STATS no primeiro `=` (a linha é cheia
   deles) — trocado por `sed -n 's/^reply_ascii=//p'`.

## 8. O que continua bloqueado

- **Interop real** (`tests/interop.sh`): `NOT_IMPLEMENTED` no portão; exige ambiente Windows/Wine
  autorizado e captura isolada. Sem isso, nenhuma afirmação de compatibilidade.
- **Golden** (`tests/golden.sh`): `NOT_IMPLEMENTED` — dourados só fazem sentido depois de evidência
  de formato real; gerar dourados do nosso próprio codec seria tautologia.
- **Fuzz**: `NOT_IMPLEMENTED` (sem libFuzzer no host; alternativa viável é fuzz de estrutura própria
  sobre `mu2_frame_decode`, a fazer).
- **Limite de pacote do original**: desconhecido. `MU2_MAX_BODY=2048` é decisão própria (D2-03),
  não observação.

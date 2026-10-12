# NEXT_TASK — v2 — próxima rodada

## Tarefa executável: R-6 — protocolo e interoperabilidade

O portão (R-8) está no lugar, então agora toda afirmação nova tem de passar por ele. O objetivo da
R-6 **não** é declarar compatibilidade: é descobrir e provar o que for provável, e manter `BLOCKED`
o que depender de binário original em execução.

### Estado inicial a verificar antes de escrever qualquer linha
1. `git status --porcelain` limpo; `git rev-parse HEAD` == `git ls-remote origin <branch>`.
2. `make -s gate` → `PASS=9 FAIL=0`, 194 asserções; `make -s gate-selftest` → 18/18.
3. `MuServer/` intacta: `bash tests/ref_check.sh` = 6/6.
4. `bash scripts/verify-backup.sh` = 9/9.

### 6.1 Inventário de evidências (o que já está medido e o que falta)
Partir de `reports/r5-*.tsv` e listar, por componente, o que pode esclarecer pacote/cabeçalho/opcode/
sessão/handshake/framing/criptografia/encerramento:
- `ConnectServer` (IOCP medido por import, `WSARecv`/`WSASend`), `GameServer` (`.themida` ⇒ análise
  estática limitada), `GameServerCS`, `DataServer`, `JoinServer`, `DiscordServer`, `SpeedServer`,
  `MHPServer`, `SubSalatest`;
- `.ini`/`.dat` de configuração (`ServerList.dat` e `MapServerInfo.dat` **são texto**, medido na R-5);
- scripts Lua (`ProtocolCore.lua`: 0 ocorrências de `HEAD_SIZE`/`PacketSize`/`opcode`, medido na R-3);
- portas conhecidas: TCP 44406 / UDP 55557 (ConnectServer), 55960 (DataServer), 55970 (JoinServer),
  1433 (SQL).
**Diferenciar os papéis por evidência, não pelo nome** — a dúvida `GameServerCS` × `GameServer` ×
`SpeedServer` continua aberta e deve virar linha da matriz, não suposição.

### 6.2 Análise estática segura (somente leitura)
Só ferramentas presentes no host; nada de executar binário do pacote. Ampliar `tools/pe_probe.py`
somente com o que for mensurável (tabela de imports completa, strings por seção, referências
cruzadas entre `.exe`/`.ini`/`.dat`). Onde houver `.themida`, registrar a limitação em vez de
concluir. Ausência de string nunca vira ausência de recurso (D2-20).

### 6.3 Testes de protocolo — três camadas, sem confusão
1. **conformidade interna do v2** (`tests/conform.sh`): o que o nosso codec/serviço garante. É o que
   dá para implementar e testar agora, e entra no portão como etapa nova.
2. **compatibilidade observada**: coincidências medidas entre o v2 e artefatos do pacote.
3. **compatibilidade comprovada por interop**: exige cliente/servidor original em execução ⇒
   `BLOCKED` (Windows/Wine/licença), documentado com o que falta.
A camada 1 nunca é apresentada como prova da 3.

### 6.4 Matriz de evidências (entregável obrigatório)
`reports/r6-matriz.tsv` com colunas: hipótese · fonte · método de medição · resultado observado ·
limitações · confiança · teste reproduzível · conclusão permitida · próxima investigação.
Cada linha aponta para o comando que a reproduz. Linha sem comando reproduzível não entra.

### Critérios de pronto
- `tests/conform.sh` implementado, com autos-teste, e listado no registro do portão (`PASS`).
- `reports/r6-matriz.tsv` + `r6-relatorio.md` com as três camadas separadas.
- `interop`/`golden` continuam `NOT_IMPLEMENTED` ou `BLOCKED` com motivo — nunca `PASS` sem evidência.
- `make -s gate` e `make -s gate-selftest` verdes; `ref_check.sh` 6/6; `verify-backup.sh` 9/9.
- Push conferido por `git ls-remote`; snapshot regravado.

### Proibido nesta rodada
- Executar binário do pacote original; escrever em `MuServer/`.
- Declarar compatibilidade de protocolo sem teste de interoperabilidade.
- Transformar `BLOCKED`/`NOT_IMPLEMENTED` em `PASS`; inflar limites para teste passar.
- `git add -A`, `reset --hard`, `clean -fd`, `push --force`, merge do PR #1.

### Falsificações previstas
- F15: `conform.sh` com expectativa trocada ⇒ o próprio autos-teste falha.
- F16: linha da matriz sem comando reproduzível ⇒ verificador de matriz falha.
- F17: portão deixando `conform` como `NOT_IMPLEMENTED` depois de implementado ⇒ `gate-selftest` falha.

## Ação do dono (manual) — para o v2 ter repositório próprio e publicável

Nada disto é bloqueante: com a árvore `recriado/` dentro de `Muserver` na branch da sessão, o trabalho
já está persistido e publicado. A faixa abaixo só importa se você quiser o `MuserverRecriado` ativo.

1. Abra <https://github.com/settings/installations> (logado como `heldergaraujo2`).
2. No App que a Arena usa para este workspace, clique em **Configure**.
3. Em **Repository access**, se estiver "Only select repositories", clique em **Add repository** e
   escolha `MuserverRecriado`. (Se estiver "All repositories", o problema não é a seleção — me avise,
   porque aí a causa é outra e eu reabro a investigação com essa informação.)
4. Confirme que o App tem **Contents: Read and write**.
5. Volte para a conversa e escreva "autorizado". Eu testo com `git ls-remote` e `push --dry-run`, e só
   depois disso crio o remote de verdade — nunca antes de a conferência passar.
6. Publicação: o branch local `mu2-v2` já é a semente (`git push <novo-remote> mu2-v2:main`), com a
   história preservada; o bundle serve de transporte se a rede não permitir push.

Não faço por você: não há como alterar App, token nem visibilidade de repositório a partir do sandbox.

## Ação do dono — pedido de recuperação ao suporte da plataforma

O texto está pronto em
[`../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`](../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md).
Envie pelo canal de suporte/feedback da sessão Arena: **de dentro do sandbox não há como descobrir nem
chamar esse canal** (a saída é limitada a uma allowlist que não inclui serviço da plataforma). Nenhum
endpoint foi inventado nem contornado.
Se o volume anterior voltar, esta árvore vira destino de cópia (backup primeiro, depois
`git rev-parse HEAD == c5706a5`, `git bundle verify`, portão de baseline com
`MU_REF_DATA=/home/user/Muserver/MuServer`) e o v2 passa a ser comparação, não substituto.

## Sobre o `PR #1` (aberto, `arena/cf1de8ce-muserver` → `main`, autor `heldergaraujo2`)

Enquanto o v2 viver nesta branch, ele aparece dentro desse PR — o que mistura a auditoria da camada Lua
com um projeto novo em `recriado/`. Duas saídas, sua escolha: (a) fundir o PR #1 e seguir com o v2 na
branch; (b) manter o v2 na branch e segregar depois por `subtree split` (o branch `mu2-v2` já existe
localmente para isso). **Não fundo nem reorganizo o PR por conta própria.**

# NEXT_TASK — próximas tarefas, priorizadas

Critério de prioridade: (1) reduz dano ativo, (2) reversível, (3) não depende de
autorização externa. **T0 e T1 são pré-condições de segurança** — o resto pode
esperar, eles não.

---
## T0 · Revogar as credenciais expostas — **imediato, não é opcional**
- **Por quê:** `workspace/reports/A1-secrets.md` guarda o *caminho* de um token de
  bot do Discord versionado no Git, da senha do SQL, da senha global do JoinServer
  e de 5 backups com PII de jogadores. O repositório foi publicado, então
  **qualquer pessoa com acesso ao histórico já tem esses materiais**; remover o
  arquivo do `HEAD` não invalida o que foi copiado.
- **Como:** rotacionar na origem (Discord Developer Portal → Reset Token; senha do
  SQL; `GlobalPassword`; `ClientSerial` se aplicável). Depois rodar
  `git-filter-repo` ou `git filter-branch` para expurgar histórico **e** as refs no
  fork/origin, com os colaboradores avisados de que um clone existente ainda
  contém o segredo antigo.
- **Validação:** o `muserver_preflight.py --only P11` voltar sem ocorrências e o
  `git log -p` não mostrar mais o valor.
- **Nota:** fiz o diagnóstico sem ecoar segredos neste repositório (ver D-01 e o
  §4 do AUDIT).

## T1 · Decidir a política de hot-reload — o maior ganho de estabilidade disponível
- **Por quê:** 7/7 crashes ocorreram ≤22 s após `/reload`; `p = 1,5e-14`; 9 082
  reloads em 138 dias (≈0,08 % de crash por reload, e é uma cauda *sem* proteção:
  não há garantia de que não cresça com o número de scripts).
- **Opções, da mais barata à mais cara:**
  1. **Procedural (recomendo):** banir `/reload` do runbook, reiniciar o processo.
     Zero mudança de código, efeito imediato, reversível em um commit.
  2. **Automatizada:** manter `/reload` só com cache Lua vazio, sob lock que
     suspenda o loop de pacotes. Exige confirmar que o `GameServer.exe` aceita
     "cache vazio" sem pedir o mínimo — medição em Windows.
  3. **No binário:** não é possível (D-01/D-02).
- **Validação:** após adotar 1, monitorar por ≥2 semanas a ausência das famílias
  3.1/3.3/3.4 nos dumps novos (o parser lê o dump em segundos).

## T2 · Corrigir os 17 spawns com retângulo invertido + 27 linhas fora do formato
- **Por quê:** dado defeituoso, correção trivial, risco zero, e é o único achado
  do P04 com impacto direto jogável. Arquivos: `000 - Lorencia.txt:101`,
  `001 - Dungeon.txt:56`, `002 - Devias.txt:88,95`, `003 - Noria.txt:78`,
  `010 - Icarus.txt:45,48,49`, `033 - Aida.txt:90` … (lista completa em
  `out/preflight.txt`).
- **Como:** para cada linha, `Begin=min(Begin,End)`, `End=max(...)` por eixo.
  **Preservar LF** e a codificação original do arquivo (o pack é LF, não CRLF; o
  `.gitattributes` declarado `-text` nos dados de jogo para o Git não converter nada).
  **Não** tocar as 27 linhas de 6-colunas-em-seção-SPOTS sem antes decidir com o
  dono do que são (ver AVISO do P04).
- **Validação:** `muserver_preflight.py --only P04` voltar com 0 geometria
  inválida. Teste unitário de dados a escrever junto (fixture no formato do
  autoteste já existe).

## T3 · Patch LAA no GameServer — **decisão do dono, não executar sozinho**
- **Por quê:** 32 bits sem `LARGEADDRESSAWARE` ⇒ teto de ~2 GB; os logs registram
  12 falhas de aloc de 111/172 MB e o heap era usado de só 13,6 % — um limite
  **endereço-endereço**, não de memória física.
- **Pré-requisitos:** (a) autorização explícita do dono do projeto e consciência do
  risco de invalidar a integridade do Themida; (b) VM Windows com o stack.
- **Como (em cópia, nunca no original):** `editbin /LARGEADDRESSAWARE GameServer.exe`
  → subir → rodar carga por N horas → comparar footprint e dumps com o baseline.
- **Rollback:** substituir pelo exe original do próprio repositório (`git checkout`).
- **Validação:** bit presente no novo PE **e** o serviço inicia e aceita conexão.
  Se o Themida recusar: abandonar a mitigação e registrar a recusa.

## T4 · Reduzir as 21 colisões de serial com MHPServer (`P03`)
- **Por quê:** `ClientSerials.txt` tem 21 serials; cada um com
  `BlockIfHack/BlockIfSpeedHacking = 0`; `MHPServer.ini` com
  `MemoryGuardSwitch=0`, `MacroProtectSwitch=0`. É um estado de *soft ban*
  deliberado? Preciso saber antes de sugerir mudança de política de anti-cheat.
- **Validação:** decisão documentada em `DECISIONS.md`, não uma mudança às cegas.

## T5 · Reconciliar os 193/172 arquivos de `Data/` divergentes entre instâncias
- **Por quê:** `SpeedServer/Data` difere de `MuServer/Data` em 196 arquivos e
  `SubSalatest/Data` em 172 (P10). Hoje não sei quais divergências são
  intencionais (balanceamento de instância) e quais são esquecimento — e é
  justamente esse o terreno onde "subi a versão errada" acontece.
- **Como:** diff arquivo a arquivo, classificar em `[intencional]`/`[esquecido]`,
  e propor *uma* fonte de verdade por arquivo (ou declarar a divergência como
  política, o que também é uma resposta válida).

## T6 · Construir o harness de integração quando houver Windows
- **Alvo:** as 6 categorias em branco na matriz de `TEST_RESULTS.md`
  (boot, conectividade, auth, persistência, carga, credenciais).
- **Peças que já existem para isso:** parser de minidumps (`tools/minidump_analyze.py`),
  `--only P0X` do preflight, teste de ping de portas, e a comparação de dumps por
  família. Falta o orquestrador (VM + SQL + restore dos `.bak` + smoke de login) —
  que não se escreve de forma responsável sem o ambiente.

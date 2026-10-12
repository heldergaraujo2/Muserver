# NEXT_TASK — v2 — próxima rodada

## Tarefa executável: R-5 — inspeção reproduzível do pacote original

Objetivo: **descobrir, não supor**. Tudo o que a reconstrução afirma sobre o MU Server original tem de
sair de ferramenta reproduzível rodando sobre `MU_REF_DATA` (padrão: `/home/user/Muserver/MuServer`),
**somente leitura**. Nenhum arquivo da referência é modificado, movido ou executado.

### Escopo (nesta ordem)

1. `tools/pe_probe.py` — cabeçalho PE dos executáveis: máquina, timestamp, seções com tamanho/entropia,
   imports/exports, e procura por strings e constantes que interessem ao protocolo (tamanhos de
   cabeçalho, opcodes, nomes de função de rede). Saída determinística em TSV.
2. `tools/att_probe.py`, `tools/mb_probe.py`, `tools/data_probe.py` — formatos `.att`, `.bmd`/`.smd` e
   dados de `Data/` (itens, monstros, mapas, Lua): assinatura, tamanho, estrutura aparente, relações
   entre arquivos. Sem alterar nada.
3. `tests/pe.sh` (`pe` + `pe-selftest`) e `tests/data.sh` (`data` + `data-selftest`) — o autos-teste é
   obrigatório: cada probe tem de falhar de forma visível quando recebe entrada inválida.
4. `reports/r5-pe.tsv`, `reports/r5-formatos.tsv`, `reports/r5-dados.tsv` — com comando, hash do
   arquivo de entrada e o que é **observação**, **hipótese** e **conclusão**, separados.

### Regras da fase

- Ausência de string **não** é ausência de recurso no binário (pode estar ofuscado, comprimido ou
  construído em tempo de execução). Escrever isso explicitamente onde ocorrer.
- Tamanho de arquivo **não** é limite de formato. Nenhum limite é declarado sem evidência de estrutura.
- Os 4 `.bak` de `DB/` são inventariados (tamanho, cabeçalho, hash) — **não** restaurados nem abertos
  como banco.
- Nada de executar binário do pacote (nem sob Wine) nesta fase.
- Saída determinística: sem timestamps nem caminhos absolutos do host no conteúdo dos relatórios.

### Critérios de saída

`make -s check` continua verde (unit 106/0, make-sintaxe 7/0, net 34/0); `pe`/`pe-selftest` e
`data`/`data-selftest` verdes; relatórios com evidência e limitações; e **falsificações**:
(i) apontar o probe para uma cópia truncada em diretório temporário tem de produzir recusa, não
inventar estrutura; (ii) entregar um arquivo que não é PE tem de ser recusado como não-PE;
(iii) o autos-teste tem de falhar quando o valor esperado é trocado de propósito.
Reverter qualquer mutação e conferir `git status --porcelain` vazio.

### Fora de escopo da R-5

`interop`/`golden` (R-6), `bench` (R-7, continua BLOCKED), `run_all.sh`/`gate_state` (R-8), painel
administrativo e assistente de publicação (só depois de R-5/R-6, e nunca com controle sobre
`MuServer/`).

---

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

# NEXT_TASK — v2 — proxima rodada

## Tarefa executavel: R-3 — `wire` (enquadramento/decodificacao) + suíte unitaria
Escopo fechado, sem servico de rede ainda:

1. `include/mu2/mu2.h` — constantes do contrato (incluindo `MU2_MAX_BODY = 2048`, D2-03) e as
   declaracoes do codec; dois perfis de quadro (`orig`, `mur0`) como tipo/enum explicito, nao
   flag solta (D2-04).
2. `src/wire.c` — `encode`/`decode` com contrato de erro por retorno (sem `assert` como
   verificacao de entrada), e **recusa** documentada de quadro truncado, exageradamente longo e de
   tamanho inconsistente.
3. `Makefile` com alvos `build:`, `unit:`, `make-sintaxe:` (analise de sintaxe/estilo dos
   arquivos de teste, que foi alvo proprio no v1), build com
   `-g -O2 -Wall -Wextra -Werror -fsanitize=address,undefined -fstack-protector-strong -D_FORTIFY_SOURCE=3`.
4. `tests/unit.c` — casos de ida e volta por perfil, e os quatro casos de borda acima.
5. `tests/make_parse.sh` — parser do Makefile validado nos mesmos 5 formatos que o v1 usava
   (o piso numerico do v1, `make-sintaxe=5`, e **[alvo]**: o v2 publica o que medir).

Criterios de saida (todos obrigatorios, na ordem):
- `make -s build` limpo com `-Werror`; `make -s unit` verde sob ASAN+UBSAN.
- **Falsificacao obrigatoria de cada assercao nova**: trocar a ordem de dois campos no encoder →
  o teste tem de cair; corromper 1 byte do comprimento → o teste tem de cair. Restaurar e
  conferir `git diff` vazio em `src/`.
- `tests/gate_state.sh` ainda nao existe (R-8); enquanto ele nao existir, a rodada registra a
  saida crua em `reports/r3-unit.tsv` (extensao `.tsv`, nunca `.txt` — D2-08).
- Fim de rodada conforme D2-09: `git add` de caminhos explicitos → commit → push →
  `git ls-remote` conferido → `bash recriado/scripts/verify-backup.sh` verde → bundle regravado.

Nao entra na R-3: laço de `poll()`, fila de resposta, `bench`, nada de numero comparativo.

## Acao do dono (manual) — para o v2 ter repositorio proprio e publicavel
Nada disto e bloqueante: com a opcao A (esta arvore dentro de `Muserver` na branch da sessao) o
trabalho ja esta persistido e publicado. Faixa abaixo so se voce quiser o `MuserverRecriado` ativo.

1. Abra <https://github.com/settings/installations> (logado como `heldergaraujo2`).
2. No App que a Arena usa para este workspace, clique em **Configure**.
3. Em **Repository access**, se estiver "Only select repositories", clique em **Add repository**
   e escolha `MuserverRecriado`. (Se estiver "All repositories", o problema nao e a selecao —
   me avise, porque ai a causa e outra e eu reabro a investigacao com essa informacao.)
4. Confirme que o App tem **Contents: Read and write** (permissao de conteudo de codigo).
5. Volte para a conversa e escreva "autorizado". Eu testo com `git ls-remote` e `push --dry-run`,
   e so depois disso crio o remote de verdade — nunca antes de a conferencia passar.
6. Publicacao: `git subtree split -P recriado -b mu2-v2` → push da branch resultante. A historia
   do v2 vai junto; nenhum commit se perde e o repo de referencia fica intacto.

Nao faco por voce: nao tenho como alterar App, token nem visibilidade de repositorio a partir do
sandbox (a autenticacao acontece fora daqui), e nao toco em permissao de conta.

## Acao do dono — pedido de recuperacao ao suporte da plataforma
O texto esta pronto em `../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`.
Envie o conteudo pelo canal de suporte/feedback da sessao Arena (a interface onde esta conversa
acontece); **nao ha como, de dentro do sandbox, descobrir ou chamar o canal da plataforma** —
a saida e limitada a uma allowlist que nao inclui nenhum servico da Arena/e2b, e os tokens de
ambiente sao dummy. Nao inventei endpoint nem tentei contornar: foi verificado e registrado.
Se o volume anterior voltar, esta arvore vira destino de copia (backup primeiro, depois `git
rev-parse HEAD == c5706a5`, `git bundle verify`, portao de baseline com `MU_REF_DATA=/home/user/Muserver/MuServer`)
e o v2 passa a ser comparacao, nao substituto.

## Sobre o `PR #1` (aberto, `arena/cf1de8ce-muserver` → `main`, autor `heldergaraujo2`)
Enquanto o v2 viver nesta branch, ele aparece dentro desse PR — o que mistura a auditoria da
camada Lua com um projeto novo em `recriado/`. Duas saidas, sua escolha:
(a) fundir o PR #1 (conteudo == `main` + a auditoria Lua + os relatorios) e seguir com o v2 na
branch; (b) manter o v2 na branch e segregar depois por `subtree split`. Eu **nao** fundo nem
reorganiz o PR por conta propria.

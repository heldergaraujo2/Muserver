# Avaliação de risco e plano de contenção/rotação — exposição P07

| campo | valor |
|---|---|
| data | 2026-10-13 (segunda medição do dia, após reprovisionamento do ambiente) |
| HEAD verificado | `4713c26f81e1bb2c4e13f89d7083574a3eab71f0` (local = remoto, lido por `git ls-remote`) |
| escopo | credenciais, strings de conexão e backups SQL expostos no repositório **público** `heldergaraujo2/Muserver` |
| o que este documento **não** contém | nenhum valor de credencial, nenhum serial, nenhum e-mail, nenhum IP, nenhuma PII. A verificação disso é executável (§6) |
| o que **não** foi feito | nenhuma rotação, nenhuma mudança de visibilidade, nenhuma reescrita de histórico, nenhuma restauração de backup, nenhum teste de validade de credencial |

Este documento **não substitui** `INVENTARIO-EXPOSICAO-2026-10-13.md` (o inventário arquivo a arquivo) nem
`../migracao/RELATORIO-TRATAMENTO-RISCOS-P0-2026-10-13.md` (o plano original). Ele traz **medições de
hoje**, um **modelo de risco por explorabilidade** e uma **ordem de rotação por dependência**, que é o
que faltava para decidir.

## 1. O que foi verificado hoje (medição, não memória)

| verificação | comando | resultado medido |
|---|---|---|
| repositório é público? | `gh api repos/heldergaraujo2/Muserver` | `private=false`, `visibility=public` |
| **um terceiro anônimo alcança os arquivos sensíveis?** | `curl -H "Authorization:" .../contents/<caminho>?ref=main` | **HTTP 200** em `JoinServer/JoinServer.ini`, `DiscordServer/DiscordServer.ini`, `PSGuard/PSGG.ini` e `DB/MuOnline.bak` — sem token, sem conta |
| os achados continuam iguais? | `python3 workspace/tools/muserver_preflight.py --root MuServer` | **22 erro, 19 aviso, 16 ok, 1 info** — os **6 ERROS de segredo/PII idênticos** ao inventário (token do Discord 1, hardware id 5, senha global 1, senha em connection string 2, serial de cliente 7, 4 backups de banco) |
| volume dos backups | `git cat-file -s origin/main:MuServer/DB/<arquivo>.bak` (**sem baixar conteúdo**) | **50 373 632 bytes** nos 4 arquivos (16 948 736 + 9 398 784 + 16 949 760 + 7 076 352) |
| o `.gitignore` impede re-versionar `*.bak`/`*.dmp`/`LOG*`? | `git check-ignore -v` nos padrões | **sim** para caminho não rastreado; e o próprio arquivo documenta a armadilha de que **não** remove o que já está no índice |

**Fato central, e é este que decide a urgência:** o material está no commit atual de um repositório
**público**, acessível **sem autenticação**. Remover do último commit não desfaz a exposição; o histórico
e as cópias já baixadas continuam valendo. Por isso a rotação (§3) vem **antes** de qualquer limpeza.

**Limite do método, declarado:** a prova de acessibilidade é o `200` do endpoint de conteúdo (metadados
e `download_url`). **Não baixei o conteúdo dos `.bak`** — baixar seria copiar base de dados de jogador
para este ambiente, e a instrução vigente é não restaurar. A prova de que o arquivo é público não
depende de baixá-lo.

## 2. Avaliação de risco por classe (o que um terceiro consegue **fazer**)

| # | material exposto | o que permite a um terceiro | pré-requisito para explorar | impacto | tempo até o dano | prioridade |
|---|---|---|---|---|---|---|
| 1 | token de bot do Discord (1 ocorrência) | assumir o bot: publicar em canais onde ele tem permissão, ler histórico conforme escopos, derrubar serviços que usam o bot | **nenhum** — o valor basta, de qualquer lugar do mundo | reputacional e operacional no Discord do projeto | **imediato** | **P0** |
| 2 | senha do usuário SQL + usuário/host/banco | acesso total ao banco de contas/personagens: ler, alterar, apagar, exfiltrar | a instância SQL estar alcançável (rede/porta 1433 exposta). O valor exposto é **reutilizável para sempre** se a instância for exposta depois | alto (integridade de contas) | imediato se exposta | **P0** |
| 3 | senha dentro de connection string (2 ocorrências) | mesma capacidade do item 2, por outro caminho | idem | alto | idem | **P0** |
| 4 | `globalpassword` do JoinServer | passar pela checagem de sessão do JoinServer com um componente falsificado (bypass de autenticação interna) | alcançar a porta 55970 | alto (bypass de autenticação) | imediato se alcançável | **P0** |
| 5 | 4 backups de banco (48,0 MiB, `TAPE`/SQL Server) | contas de jogador, hashes de senha para quebra offline, possivelmente PII; **conteúdo não inspecionado** | **nenhum** — o arquivo já está público | **o mais alto em dano a terceiros** (dados de jogadores) | contínuo | **P0** |
| 6 | logs de servidor com IP de jogador (2 793 arquivos, ≈216 MB; 330 085 linhas de IP) | correlação de IP↔conta↔personagem; base para ataque direcionado | nenhum | alto em privacidade (LGPD) | contínuo | **P1** |
| 7 | senhas de party em log (`Password: <valor>`, 5 arquivos) | credenciais de jogador em texto claro | nenhum | médio (alcance limitado, mas é credencial real) | contínuo | **P1** |
| 8 | serial de cliente (7), hardware id (5), licenças PSGuard/MHP | uso indevido de licença, impersonação do cliente, correlação de máquina | ferramenta/contexto do produto | médio para o fornecedor; baixo para o dono | lento | **P2** |
| 9 | crash dumps (34 arquivos, 9,0 MB, `MDMP`) | memória de processo pode conter sessões, contas, strings | engenharia de análise | **não medido** (não inspecionado) | — | **P2** |
| 10 | PII **nossa** em `r6-config.tsv` (×2: `recriado/` e `MuserverRecriado/`) | 1 e-mail; o **mesmo** valor já está em `PSGuard/PSGG.ini` (fonte) | nenhum | higiene: nós introduzimos PII num artefato **nosso** | contínuo | **P2** |

**Leitura honesta da tabela:** os itens 5 e 6 são os de maior dano a terceiros (dados de jogador). Os
itens 1–4 são os de maior **explorabilidade** (o valor, sozinho, já é suficiente). O item 1 é o único
que o proprietário resolve em trinta segundos com efeito imediato; os itens 2–4 podem exigir rever todos
os componentes que compartilham o valor.

## 3. Plano de contenção e rotação

Ordem por **dependência** (o que destrava o quê) e não por conveniência. Nada abaixo foi executado.

### Fase R1 — Rotação na origem (só o proprietário; é a única que remove o risco de verdade)

| ordem | o que rotacionar | onde | critério de conclusão (verificável) | cuidado obrigatório |
|---|---|---|---|---|
| 1 | **token do bot Discord** | Discord Developer Portal → Bot → *Reset token* | o token antigo deixa de autenticar (verificar em ferramenta do próprio Discord, fora deste repositório) | atualizar o `.ini` **local** do servidor do dono; não comitar o novo em hipótese alguma |
| 2 | **senha do usuário SQL** (item 2) + usuário, se possível | instância SQL Server | login antigo falha; componentes do servidor reconectam com o novo | trocar **em conjunto** com a Fase R2.3; revisar quem mais usa aquele login |
| 3 | **senha das connection strings** (item 3) | DSN ODBC do Windows + login SQL | idem | são dois arquivos: `JoinServer.ini` e o editor de contas |
| 4 | **`globalpassword` do JoinServer** | `JoinServer.ini` **e todos os componentes que compartilham** | JoinServer e GameServers sobem e trocam sessão entre si | troca tem de ser simultânea; testar em janela de manutenção |
| 5 | **séries licenciadas** (PSGuard/MHP/serial do cliente) | fornecedor comercial | emissão nova recebida e aplicada | depende de terceiro; pode não ser reemitido — nesse caso tratar o produto como comprometido |
| 6 | **senhas das ferramentas de edição** (MuEditor, editor de contas) | contas SQL usadas por elas | ferramenta conecta com a credencial nova | são contas de operador, não de jogo |

**Regra que não pode ser quebrada nesta fase:** não testar a credencial antiga nem a nova a partir deste
repositório ou deste ambiente, e não registrar nenhum valor novo em arquivo rastreado.

### Fase R2 — Tampão no repositório, **sem** reescrever histórico (agente pode executar, com autorização)

1. **Redigir a PII nossa** (§2 item 10) nos dois `r6-config.tsv` e regenerar o snapshot/bundle que a
   carregam (ritual R-2). A evidência não se perde: o valor continua no arquivo de origem do pacote.
2. **Nunca re-versionar** os artefatos: `workspace/tools/untrack_artifacts.sh` já existe e é *dry-run*
   por padrão; qualquer remoção do índice exige conferir `git diff --cached --stat` antes do commit
   (o `.gitignore` documenta o desastre de 2 376 *deletions* silenciosas que já aconteceu aqui).
3. **Não tocar em `MuServer/`**: sanitizar os 19 `.ini`/`.dat` altera a referência histórica e não
   remove o que já foi publicado — é decisão do proprietário, item §4.5.

### Fase R3 — Estrutural (decisão do proprietário; ver §4)

| opção | resolve | custo real |
|---|---|---|
| **A. Reescrever o histórico** (`git filter-repo`/BFG) | tira o material do repositório **e** do histórico | **force-push** (nunca feito neste projeto), quebra clones/forks, PR #1 precisa ser refeito, tag precisa ser reemitida, bundles/snapshots regenerados, objetos podem sobreviver no GitHub por tempo indeterminado — e **não** alcança cópias já baixadas |
| **B. Público só com o código próprio** (`MuServer/` sai do repositório público e vai para cópia privada do dono) | tira do público sem reescrever nada nem quebrar clones | exige decidir **onde** o `MuServer/` passa a viver (é a referência de todo o trabalho de auditoria) |
| **C. Tornar o repositório privado** | estanca exposição nova imediatamente | não desfaz o que já foi baixado; muda visibilidade — **vedado ao agente sem autorização explícita** |

**Recomendação técnica (não é decisão):** **C agora + B em seguida**. C é um clique e fecha a porta hoje;
B organiza o estado final sem tocar no histórico. A vale apenas se purgar o histórico for requisito —
e continua sendo insuficiente sozinha, porque a rotação (R1) é obrigatória de qualquer forma.

### Fase R4 — Prevenção (depois da decisão)

- Ligar **secret scanning** e **push protection** no GitHub — exige admin; a API respondeu que não temos
  acesso (`security_and_analysis` indisponível para o agente).
- Rodar o scanner que já existe (`muserver_preflight.py`, check P07) **antes** de cada publicação que
  envolva o pacote; e a ferramenta anti-vazamento (§6) antes de cada commit de documento sensível.
- `.gitignore` já cobre `*.bak`, `*.dmp`, `LOG*` (verificado hoje); a regra de dados de jogador
  (retenção, cópia cifrada, acesso restrito) continua pendente de decisão.

## 4. O que exige autorização humana (com a ação exata)

1. **Rotacionar credenciais (Fase R1 inteira).** O agente **não tem e não deve ter** esses valores; não
   é tecnicamente possível rotacionar daqui. *Ação do proprietário: executar a tabela da R1 na origem.*
2. **Redigir a PII nossa** (`recriado/reports/r6-config.tsv` e `MuserverRecriado/reports/r6-config.tsv`)
   e regenerar o bundle afetado. *Ação do agente, se autorizado: substituir o valor por marcador mantendo
   a linha, rodar `scripts/verify-backup.sh`, regravar o snapshot (ritual R-2) e conferir por `ls-remote`.*
3. **Tornar o repositório privado** (§2 opção C). **Não faço isso sem ordem explícita.**
4. **Reescrever o histórico / force-push** (§2 opção A). **Nunca foi feito neste projeto e não será sem
   autorização escrita** — inclusive porque quebra o PR #1 e a tag `auditoria-2026-10-13`.
5. **Sanitizar os 19 `.ini`/`.dat` do pacote `MuServer/`** — hoje vedado pela instrução de não modificar
   `MuServer/`. Não reduz o que já vazou; serve para o pacote não voltar a vazar.
6. **Destino do `MuServer/`** (fica no repositório público? vai para cópia privada? sai do versionamento?).
7. **Ligar secret scanning/push protection** (exige credencial de admin).
8. **Incidente de dados (LGPD)**: registro interno e eventual comunicação, com apoio jurídico. O agente
   não é controlador desses dados e não decide isso.

## 5. O que foi feito nesta rodada, e o que foi deliberadamente **não** feito

**Feito (tudo não destrutivo, nada de escrita no pacote):** conferência do HEAD/remoto/branch/PR;
recuperação do ambiente após reprovisionamento (conferida por hash de 392 arquivos); medição de
visibilidade e de acessibilidade anônima; re-execução do scanner P07; medição de tamanho dos backups
**sem baixá-los**; criação da ferramenta anti-vazamento e de 21 testes para ela; este documento
(verificado por §6).

**Não feito, por decisão:** não rotacionei nada (não tenho as credenciais e não devo ter); não mudei a
visibilidade do repositório; não reescrevi histórico nem fiz force-push; não restaurei nem inspecionei o
conteúdo dos `.bak`; não abri os `.dmp`; não testei validade de nenhuma credencial; não removi arquivos
do índice; não toquei em `MuServer/`; não abri PR nem fiz merge.

## 6. Verificação anti-vazamento deste documento (executável, não promessa)

```sh
python3 workspace/tools/verifica_doc_sem_segredo.py \
    --alvo workspace/seguranca/AVALIACAO-RISCO-E-PLANO-ROTACAO-2026-10-13.md \
    --alvo workspace/seguranca/INVENTARIO-EXPOSICAO-2026-10-13.md \
    --alvo workspace/reports/A1-secrets.md
```

A ferramenta extrai os valores das chaves sensíveis dos configs do pacote (somente leitura), procura
esses valores nos documentos e **também** procura linhas com forma de credencial. Ela reporta apenas
**nomes de chave e contagens — nunca valores**, e isso é testado: os casos 7–9 de
`workspace/tests/test_verifica_doc_sem_segredo.py` plantam um segredo sintético e exigem que ele **não**
apareça na saída nem no JSON de resultado. Resultado desta execução: **0 casamentos por valor, 0 por
forma** (saída registrada no CHANGELOG da rodada).

## 7. Consequências de não agir

- O token do bot Discord segue utilizável por qualquer pessoa, hoje, sem nenhum pré-requisito.
- As senhas de banco seguem válidas até serem trocadas: expostas, elas transformam qualquer exposição
  futura da porta SQL em comprometimento total de contas.
- Os 48,0 MiB de backups e os ≈216 MB de logs com IP de jogador permanecem públicos — é dano a
  **terceiros** (jogadores), que não escolheram isso e não podem ser avisados por nós.
- Cada nova publicação no repositório público aumenta a superfície; a única contenção que não depende de
  terceiros é a decisão §4.3 (visibilidade) ou §4.2 (redação da nossa parte).

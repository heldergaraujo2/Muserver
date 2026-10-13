# CONSOLE ADMINISTRATIVO E ASSISTENTE DE PUBLICACAO — DESENHO ANTES DA IMPLEMENTACAO

Este documento existe por exigencia explicita: arquitetura, autenticacao, permissoes, API, estados,
validacoes e erros **documentados antes** de escrever codigo. Nada aqui esta implementado ainda;
cada secao diz o que sera construido e o que foi **recusado** por nao ter backend real.

Regras que moldaram o desenho:
- proibido interface sem backend, botao sem funcao e publicacao simulada;
- nao abrir porta nem alterar firewall sem autorizacao; nao expor nada a internet;
- preservar o ABI e o protocolo do produto (`mud2`, `mu2ctl`, `libmu2`) — o console nao os toca;
- logs sem dado sensivel.

## 1. Escopo e nao-escopo

**Dentro:** um processo separado, `mu2admin`, que expoe uma API administrativa local sobre o estado
real do `mud2` (via o proprio protocolo v2, como `mu2ctl` ja faz) e sobre os relatorios do portao.
Autenticacao por token, dois niveis de permissao, validacoes e erros definidos abaixo.

**Fora, com motivo:**
| Item recusado | Motivo |
| --- | --- |
| Interface grafica/web com botoes | exigiria frontend; sem backend publicado para cada acao, seria botao sem funcao |
| Publicacao automatica de release | nao existe alvo de publicacao autorizado nem contrato de destino; simular seria mentira |
| Escrita no `mud2` (reiniciar, derrubar conexao, mudar limite em runtime) | o produto nao tem opcode de controle para isso; inventar um mudaria o contrato comprovado em 15/15 |
| Escuta fora de 127.0.0.1 | expor servico a rede sem autorizacao |
| Inicio automatico junto com o `mud2` | abrir porta sem pedido explicito |

## 2. Arquitetura

```
  cliente local (curl/teste)
        |  HTTP/1.1 em 127.0.0.1, porta escolhida por quem invoca
        v
  +-------------+   protocolo v2 (quadro 4 B + corpo)   +---------+
  |  mu2admin   | ------------------------------------> |  mud2   |
  | (novo proc.)| <------------------------------------ | (intacto)|
  +-------------+            STATS                      +---------+
        |
        +-- le out/gate.tsv (relatorio do portao) somente leitura
        +-- le o arquivo de token (0600 obrigatorio)
```

Decisoes:
- **A-1 processo separado.** `mud2` nao ganha HTTP, nao ganha thread, nao ganha superficie de ataque.
  O ABI e o protocolo continuam exatamente os que `tests/conform.sh` comprova.
- **A-2 single-threaded com poll()**, como o `mud2`: consistencia de modelo e ausencia de corrida
  por construcao (TSan nao se aplica, como medido na Etapa D).
- **A-3 somente loopback.** `--listen` aceita apenas `127.0.0.1`; qualquer outro endereco e recusado
  na partida, com erro e exit != 0.
- **A-4 opt-in.** Nada inicia o `mu2admin`. Quem quiser, invoca.
- **A-5 sem TLS, e isso e declarado.** Em loopback com token, TLS acrescentaria gerenciamento de
  certificado sem remover risco relevante neste escopo; se algum dia sair do loopback, TLS passa a
  ser obrigatorio — registrado como condicao, nao como escolha permanente.

## 3. Autenticacao

- Token vem de **arquivo** indicado por `--token-file`; nunca de variavel de ambiente nem de
  argumento de linha de comando (ambos aparecem em `ps` e em relatorio de processo).
- Formato do arquivo, uma linha por credencial: `<token><TAB><papel>`. Linhas iniciadas por `#` sao
  comentario. Arquivo vazio ou ilegivel => **o servidor recusa iniciar** (fail closed).
- Permissao do arquivo: o servidor exige `0600` e dono corrente; caso contrario recusa iniciar.
  Motivo: um token legivel por outros usuarios e credencial vazada antes de qualquer request.
- Comparacao em **tempo constante** (varredura completa do tamanho maximo, sem `short-circuit`),
  para nao transformar o tempo de resposta em oraculo de prefixo.
- Comprimento minimo do token: 32 caracteres. Abaixo disso o servidor recusa iniciar.
- O token **nunca** vai para o log, nem para a resposta, nem para mensagem de erro. O log registra
  `auth=falha` sem ecoar o que foi apresentado.
- Sem token de desenvolvimento embutido no binario. Ausencia de configuracao = servidor nao sobe.

## 4. Permissoes

| Papel | Pode | Nao pode |
| --- | --- | --- |
| `leitor` | `GET` em rotas de leitura | qualquer `POST` |
| `admin`  | `GET` de leitura + `POST` em rotas de acao | rotas marcadas `501` |

- Papel desconhecido no arquivo => recusa iniciar (nao existe "papel padrao" por omissao).
- A verificacao de papel acontece **depois** da autenticacao e **antes** de qualquer efeito.
- Rotas `501` sao recusadas mesmo para `admin`: nao ha backend, entao nao ha acao.

## 5. API

Todas as respostas sao `application/json` com uma linha, sem salto de linha no corpo, e trazem o
campo `estado` ou `erro`.

| Rota | Metodo | Papel | Backend real | Resposta de sucesso |
| --- | --- | --- | --- | --- |
| `/health` | GET | nenhum | o proprio processo | `{"estado":"pronto","versao":"v2"}` |
| `/stats` | GET | leitor | quadro STATS do `mud2` | `{"estado":"ok","stats":"registros=... uptime_ms=..."}` |
| `/gate` | GET | leitor | `out/gate.tsv` | `{"estado":"ok","pass":N,"fail":N,"blocked":N,"assercoes":N}` |
| `/publicar` | POST | admin | **nenhum** | `501 {"erro":"nao_implementado",...}` |

`/stats` com o `mud2` fora do ar devolve `503 {"erro":"upstream_indisponivel"}` — **nao** um corpo
vazio de sucesso. Estado degradado e informado, nunca disfarçado.

## 6. Estados

| Estado | Quando | Visível em |
| --- | --- | --- |
| `parado` | processo nao iniciado | — |
| `pronto` | escutando, token carregado | `/health` |
| `degradado` | escutando, mas `mud2` nao responde | `/health` (`upstream="indisponivel"`) e `503` em `/stats` |
| `erro` | falha ao carregar token, porta ocupada, endereco nao-loopback | stderr + exit != 0, nao sobe |

Transicoes: `parado -> pronto` na partida bem-sucedida; `pronto -> degradado -> pronto` conforme o
`mud2` responde; `* -> parado` em `SIGTERM`, com encerramento limpo e exit 0.

## 7. Validacoes (todas antes de qualquer efeito)

| Entrada | Regra | Erro |
| --- | --- | --- |
| linha de request | <= 8 192 B, com metodo, rota e versao | `400 requisicao_invalida` |
| metodo | somente `GET`/`POST` | `405 metodo_nao_permitido` |
| rota | <= 256 B, somente `[A-Za-z0-9/_-]`, sem `..` | `400 rota_invalida` / `404 rota_desconhecida` |
| cabecalhos | <= 32 cabecalhos, <= 8 192 B cada | `400 cabecalho_invalido` |
| corpo | <= 4 096 B; `Content-Length` maior que isso e recusado sem ler o resto | `413 corpo_grande_demais` |
| `Authorization` | `Bearer <token>`, tamanho <= 256 | `401 token_malformado` |
| conexao | 1 requisicao por conexao (sem keep-alive) para limitar superficie | — |
| timeout | 5 s por conexao ociosa | fecha sem resposta |

## 8. Erros

| HTTP | `erro` | Quando | Corpo ecoa a entrada? |
| --- | --- | --- | --- |
| 400 | `requisicao_invalida` | linha ou cabecalho fora da regra | nao |
| 400 | `rota_invalida` | caractere proibido ou `..` na rota | nao |
| 401 | `token_ausente` | sem `Authorization` | nao |
| 401 | `token_malformado` | header fora do formato `Bearer ` | nao |
| 401 | `token_invalido` | token nao confere | **nao** (nunca ecoa o apresentado) |
| 403 | `papel_insuficiente` | `leitor` em `POST` | nao |
| 404 | `rota_desconhecida` | rota valida mas inexistente | nao |
| 405 | `metodo_nao_permitido` | metodo fora de `GET`/`POST` | nao |
| 413 | `corpo_grande_demais` | `Content-Length` > 4 096 | nao |
| 501 | `nao_implementado` | rota sem backend (`/publicar`) | motivo textual |
| 503 | `upstream_indisponivel` | `mud2` nao responde | nao |

Nenhum erro vaza caminho absoluto do host, token, payload ou versao de biblioteca.

## 9. O que fica NOT_IMPLEMENTED / BLOCKED, com o que falta

- **`POST /publicar`: NOT_IMPLEMENTED por decisao.** Falta (a) alvo de publicacao autorizado,
  (b) contrato de destino (repositorio, artefato, assinatura), (c) credencial de publicacao.
  A rota existe e devolve `501` com o motivo — nao devolve sucesso simulado. Publicar de verdade
  continua sendo ato do proprietario (o PR #1 aberto e a prova de que a decisao e dele).
- **Acoes de escrita no `mud2`: NOT_IMPLEMENTED.** Exigiria opcode de controle no contrato v2, o que
  invalidaria a conformidade comprovada; so com decisao registrada e testes novos.
- **TLS: NAO APLICAVEL** enquanto o escuta for loopback; obrigatorio se sair dele.

## 10. Testes exigidos antes de declarar a etapa pronta

| # | O que prova |
| --- | --- |
| 1 | sem `--token-file` o servidor **nao sobe** e sai != 0 (fail closed) |
| 2 | arquivo de token com permissao 0644 => recusa iniciar |
| 3 | token com 31 caracteres => recusa iniciar |
| 4 | papel desconhecido no arquivo => recusa iniciar |
| 5 | `--listen 0.0.0.0` => recusa iniciar (somente loopback) |
| 6 | `/health` responde sem token |
| 7 | `/stats` sem token => `401 token_ausente` |
| 8 | `/stats` com token errado => `401 token_invalido` **e a resposta nao contem o token enviado** |
| 9 | `/stats` com `leitor` => 200 com a linha STATS real do `mud2` |
| 10 | `POST` com `leitor` => `403 papel_insuficiente` |
| 11 | `POST /publicar` com `admin` => `501 nao_implementado` (nunca sucesso) |
| 12 | rota com `..` => `400 rota_invalida`; rota inexistente => `404` |
| 13 | `Content-Length` 5000 => `413` |
| 14 | `mud2` parado => `/stats` devolve `503 upstream_indisponivel` e `/health` mostra degradado |
| 15 | log nao contem token, caminho absoluto nem payload |
| 16 | `SIGTERM` => exit 0, sem descritor vazado |
| 17 | `mud2` intacto: `git diff` vazio em `src/` e `tests/conform.sh` continua 15/15 |

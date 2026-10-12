# NEXT_TASK — o que vem depois da R-7

Estado de partida (medido, não relato): `make -s gate` → **14 PASS, 0 FAIL, 0 BLOCKED,
3 NOT_IMPLEMENTED, 2 SKIPPED, 244 asserções, 32,6 s, exit 0**; `gate-selftest` 19/19;
`make -s check` 180 asserções. Branch `arena/cf1de8ce-muserver`.

Ordem do comando mestre: R-8 ✔ → R-6 ✔ → R-7 ✔ → **cobertura completa das lacunas** →
auditoria de rastreabilidade do roadmap inteiro.

---

## Próxima tarefa: `golden` — testes de referência byte a byte (etapa `NOT_IMPLEMENTED` no portão)

### Por que esta primeiro

Das três etapas `NOT_IMPLEMENTED` (`golden`, `interop`, `fuzz`), é a única que **não depende de
nada externo**:

- `interop` está **BLOCKED** por decisão registrada — exige binário original em execução, e
  executá-lo automaticamente é proibido pelas regras do projeto. Não adianta começar por ela.
- `fuzz` precisa de um **corpus versionado e seguro**, e o corpus só é confiável se houver
  referência byte a byte do que é válido. Sem golden, o fuzzing não tem como distinguir
  "achou um defeito" de "achou um byte que ninguém sabe o que é".

### O que significa "golden" aqui

Pares **versão-controlados** de `entrada → saída esperada`, comparados **byte a byte**, cobrindo:

1. codec nos **dois perfis** (`orig` e `mur0`) — inclusive a equivalência obrigatória entre eles;
2. quadro completo: `code(2 LE) + size(2 LE) + corpo`, com `size` = total;
3. fronteiras: corpo 0, corpo 2048 (máximo), 2049 (recusado), `size` 2 e 3 (recusados),
   `size` 3000 (recusado), `size` little-endian trocado;
4. a linha `STATS` com seus 9 campos na ordem (D2-16) e o prefixo `STATS ` (D2-17);
5. pelo menos um vetor por código de erro: `MU2_E_ARG/SIZE/DST_SMALL/INCOMPLETE/BAD_LEN/PROFILE`.

### Critérios de aceite

- `tests/golden.sh` roda no portão como etapa **obrigatória** e imprime
  `# golden=N falhas=F blocked=B`.
- Cada caso imprime o que comparou (nome do vetor + hex esperado/obtido em caso de divergência).
  Divergência tem de ser **legível**: golden test que só diz "falhou" não serve.
- Os vetores ficam em arquivo versionado (`tests/golden/*.tsv` ou `.hex`), com uma linha de
  cabeçalho declarando o formato. Nada de vetor gerado em tempo de execução sem referência.
- **O caminho medido tem de ser o código real.** Está proibido reimplementar o codec num
  `golden_check.py` e comparar a reimplementação com ela mesma — isso seria um *stand-in*, não um
  teste. Se não existir CLI que exercite o codec sem subir o serviço, **criar o CLI** (ou um
  subcomando de `mu2ctl`, preservando ABI e com teste) é parte da tarefa, não obstáculo.
- Registrar no portão **removendo o placeholder `NOT_IMPLEMENTED` no mesmo ato** — a guarda de
  nome duplicado faz o portão sair 2 se a linha antiga ficar (D2-26).

### Falsificações (propósito declarado antes, como sempre)

- **F20** — corromper **um byte** de um vetor golden em cópia temporária: a suíte tem de apontar
  **qual** vetor e **qual** byte. Se a suíte continuar verde, ela não compara byte a byte.
- **F21** — trocar o perfil de um caso (comparar saída `orig` com esperado `mur0`): a suíte tem de
  falhar. Se não falhar, os dois perfis estão sendo confundidos e a equivalência obrigatória é
  decoração.

Ambas devem ficar **permanentes** na suíte (mutação em cópia temporária + reversão conferida),
não como experimento de uma fase.

### O que **não** fazer nesta tarefa

- não declarar formato decodificado só por bytes iniciais identificados;
- não usar como vetor nenhum dado do pacote original que seja credencial ou segredo
  (D2-25: 26 valores sensíveis em claro no pacote; `cfg_probe.py` redige, e a redação é testada);
- não inflar `MU2_MAX_BODY` para vetor caber;
- não remover caso que falha para o portão ficar verde — corrigir a causa raiz;
- não marcar `golden` como `PASS` se ele apenas "não falhou": `PASS` exige resumo com
  `falhas=0` **e** `blocked=0`.

---

## Depois de `golden`, nesta ordem

1. **corpus versionado e seguro** + `fuzz` (`NOT_IMPLEMENTED`): entradas malformadas dirigidas ao
   codec e ao serviço, com sanitizadores já ligados no build; cada achado vira caso de regressão
   nomeado, não número solto.
2. **auditoria do laço do produto** — `mud2`/`mu2ctl`/framing/leitura incremental/escrita
   parcial/backpressure/limits/timeout/desconexões/concorrência/logs/estatísticas, preservando
   ABI. A R-7 já deixou dois achados para essa auditoria: a fila de **uma vaga** fecha conexões
   que fazem pipeline além dos buffers (medido: 551 quadros de 2048 B com `rcvbuf` efetivo de
   2 304 B) e o `netclient` contava iterações de `poll` como tempo (D2-28).
3. **segurança e estabilidade**: validação de entrada, limites, overflow, corridas, encerramento
   limpo, logs sem dados sensíveis.
4. **`interop`**: continua **BLOCKED** até haver binário original em execução autorizada. Registrar
   o que falta, nunca simular.
5. **só então** console administrativo e assistente de publicação, com arquitetura, autenticação,
   permissões, API, estados, validações e erros documentados **antes**. Proibido interface sem
   backend, botão sem função, publicação simulada.
6. **auditoria de rastreabilidade** do roadmap inteiro: tabela por requisito com implementação,
   teste, evidência, documentação, estado e próximo passo. Nada de "concluído porque o código
   existe".

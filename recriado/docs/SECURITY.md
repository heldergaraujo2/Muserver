# SECURITY — modelo de ameaças, configurações sensíveis e riscos conhecidos

| campo | valor |
|---|---|
| data | 2026-10-13 |
| escopo | duas superfícies distintas: **(A)** o serviço de ensaio do v2 e o console administrativo; **(B)** o pacote de referência `MuServer/` versionado no repositório |
| regra | risco é declarado com a medição que o sustenta; nada de "está seguro" por omissão |

## 1. Modelo de ameaças (o que existe de verdade)

**A. O v2 é um serviço de laboratório.** `mud2` escuta **127.0.0.1** por padrão (`--listen`), sem
TLS, sem autenticação e sem estado persistente — o próprio código declara isso
(`src/mud2.c:15`: *"Nao faz: TLS, autenticacao, persistencia…"*). Não há desenho de produção, e
expor esse serviço a uma rede **não** é caso de uso: qualquer host que o alcance pode abrir conexões
até o teto de vagas e consumir CPU (negação de serviço local). O que existe de proteção é do
**teste**: validadores de enquadramento, limites de conexão, teto de memória no fuzzer e
sanitizadores.

**B. O repositório carrega o pacote de referência original** — binários de servidor de um projeto de
terceiros, arquivos de configuração com credenciais em claro e backups de banco com dados de
jogadores. Essa é a superfície sensível real, e ela **é pré-existente** (commit de upload `6eabb45`,
na branch `main`), não criada por esta consolidação.

| ativo | onde | quem pode ler | risco |
|---|---|---|---|
| credenciais em claro (token de bot Discord, senha global do JoinServer, `EncDecKey1/2`, serial/licença) | 19 `.ini` do pacote; **29 valores redigidos** nas sondas (26 até 2026-10-13; +3 com o achado **P07-x**) | qualquer um (repo **público**) | uso indevido de serviços/credenciais |
| 4 backups de banco (`DB/*.bak`, 50 373 632 B) com contas/hashes de senha | `MuServer/DB/` | idem | **incidente de privacidade** (PII de terceiros) |
| 34 crash dumps (`.dmp`) e 2 555 arquivos de log rastreados | `MuServer/**` | idem | podem conter memória de processo, IPs, nomes de contas |
| 504 `.tmp` do editor de Lua (o `.gitignore` registra que contêm a única cópia legível de um script) | `MuServer/**` | idem | integridade do material, não confidencialidade |
| screenshots e `bugreport.txt` do PSGuard | `MuServer/PSGuard/` | idem | dados de operação de terceiros |

**Ações obrigatórias do proprietário (na ordem, do relatório A1):** (1) **rotacionar** as
credenciais na origem — o histórico do git já publicou os valores, então removê-los do `HEAD` não
invalida cópia alguma; (2) tratar os 4 `.bak` como incidente de divulgação; (3) externalizar os
segredos e, se for o caso, purgar o histórico com `git-filter-repo` (script em
`workspace/tools/untrack_artifacts.sh`, dry-run por padrão). Fonte: `reports/r6-relatorio.md` §3 e
`workspace/changes/pre-ff-2026-10-12/untracked/workspace/reports/A1-secrets.md`.

## 2. Engenharia de segurança do v2 (medida, com o teste que cobra)

| controle | como foi implementado | cobrado por |
|---|---|---|
| build endurecida | `-Wall -Wextra -Werror -Wshadow -Wconversion -Wsign-conversion`, `-fstack-protector-strong`, `-D_FORTIFY_SOURCE=3` | `make-sintaxe`, todo o portão |
| memória indefinida/errônea | **ASan + UBSan** com `-fno-sanitize-recover=all` (abortam o teste) | todas as suítes |
| validação de entrada | bateria de entradas malformadas na porta: serviço **vivo** depois de cada caso; `close=bad_frame` derivado dos casos (**11**) | `seguranca` (13 asserções) |
| limites de recurso | `--max-clients` (teto 8192), `--idle-ms`, quadro ≤ 2052, fila de 1 vaga; fuzzer com `RLIMIT_AS` de 64 MB | `net`, `fuzz` caso 2 |
| vazamento de descritor/memória | contagem de `fd` e RSS antes/depois de ciclos e bateria | `seguranca` (fd estável, RSS sem crescimento) |
| encerramento limpo | `SIGTERM` → exit 0 com resumo de contadores, sem abort de sanitizador | `seguranca`, `net` |
| higiene de log | sem payload, sem caminho absoluto do host, sem chave de credencial | `seguranca` caso 9, `admin` caso 19 |
| fuzzing | motor próprio determinístico, oráculo de invariantes, sementes do corpus golden | `fuzz` (12 asserções) |
| ausência de concorrência | 0 primitivas de thread em `src/` (registrado: TSan não se aplica) | `seguranca` |
| segredos no repositório **novo** | nenhum segredo em arquivo versionado; redação por **nome e forma** nas sondas | `cfg` 7/8/11/13; D2-25 |

### 2.1 Console administrativo (`mu2admin`)

Desenhado antes do código (`docs/ADMIN_CONSOLE.md`) e testado em 24 asserções:

- **só loopback**: qualquer `--listen` fora de `127.0.0.1` é **recusado na partida**;
- **token obrigatório, falha fechado**: sem arquivo de token válido o processo **não sobe**; não há
  token embutido nem aceito por `argv`/ambiente (apareceriam em `ps`);
- arquivo de token exigido com permissão **0600** (outra permissão → erro nomeado);
- comparação de token em **tempo constante** (`ct_eq`, sem short-circuit);
- permissões por papel: `leitor` recebe `403` nas rotas de admin; escrita no serviço **não existe**
  (o produto não tem opcode de controle; `/publicar` devolve `501 nao_implementado` **por decisão**,
  não por esquecimento).

## 3. O que **não** é risco (para não gerar achado falso)

- `mud2` sem autenticação **não** é vulnerabilidade: é um serviço de ensaio em loopback, com contrato
  documentado e ausência de dados — desde que não seja exposto (e o projeto não o expõe).
- `mur0` (XOR posicional, chave `{AE,EC,D8}`) **não é** um esquema de segurança e não é apresentado
  como tal: é um segundo caminho de enquadramento para teste (D2-12).
- Os 38 vetores do corpus golden não contêm dados sensíveis (conferido na fase R-6).
- A cifragem dos `.lua` do cliente (`LuaEncTool/`) continua **não resolvida** (`PROTOCOLS.md` §5) —
  ausência de decodificador não é falha de segurança do v2.

## 4. Limitações da verificação de segurança

- Sem `valgrind`, `gdb`, `strace` nem `clang` no host: a detecção de memória vem dos sanitizadores,
  não de memcheck; não há cobertura de *cobertura* (sem fuzzer com feedback de bordas — declarado em
  D2-33).
- Toda a verificação acima vale para **o v2**. Nenhum teste de segurança foi — nem poderia ter sido —
  executado contra os binários originais (protegidos, e executá-los é vedado).
- O `bench` pode reportar `BLOCKED` sob carga do host (2 vCPUs compartilhadas); isso é ambiente, não
  falha de robustez.

## 5. Reprodução

```sh
cd recriado
make -s seguranca        # 13 asserções: malformados, fd/RSS, SIGTERM, higiene de log
make -s fuzz              # 12 asserções (motor determinístico; FUZZ_ITERS para o volume)
make -s admin             # 24 asserções: token, permissões, loopback, 501 por decisão
make -s cfg               # endpoints da referência com 29 valores sensíveis redigidos
bash scripts/verify-backup.sh && FULL=1 bash scripts/verify-backup.sh
```

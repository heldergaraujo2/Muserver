# Ambiente de medida — verificado em 2026-10-12 (nao assumido)

> **Layout desta publicação (migração de 2026-10-12; localização atualizada em 2026-10-13).** Esta
> pasta (`MuserverRecriado/`, na raiz do monorepo `heldergaraujo2/Muserver`) **é** a publicação
> do projeto recriado, sem nível extra. O repositório separado `heldergaraujo2/MuserverRecriado`
> continua bloqueado por `403` e vazio. Onde um destes documentos escrever
> `recriado/X` (inclusive em registros históricos), leia-se `X`; `workspace/` mantém o mesmo caminho
> relativo. A referência `MuServer/` (~615 MB, do fornecedor) **não** faz parte desta pasta: quando
> ela existe ao lado (`../MuServer`, como neste monorepo), as etapas que dependem dela (`pe`,
> `data`, `cfg`, `ref-intacta`, `interop` camada 3, `lua`) rodam; sem ela, saem **BLOCKED** — e
> bloqueado não é aprovado. Detalhes, exclusões, hashes e como publicar: `docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`.

Tudo abaixo foi executado neste sandbox nesta rodada; se o host trocar, a tabela
precisa ser refeita antes de qualquer numero ser comparado com alvo antigo.

## Ferramenta

| item | estado | consequencia para o v2 |
|---|---|---|
| `gcc`/`cc` | 12.2.0 | base da build |
| `make`, `patch`, `diff`, `tar`, `nm`, `objdump`, `readelf`, `strip` | presentes | suporta os alvos do Makefile |
| `clang` | **ausente** | `-fsanitize=fuzzer` **nao existe** aqui (testado: `unrecognized argument`). O harness `tests/fuzz.c` e proprio, deterministico, com corpus em `corpus/` |
| `-fsanitize=address,undefined` | compila OK (teste real) | sanitizadores de memoria ativos no portao |
| `-fstack-protector-strong -D_FORTIFY_SOURCE=3` | compila OK | hardening ativo na build de teste |
| `-g -O2 -Wall -Wextra -Werror` | compila OK | aviso vira erro desde o primeiro commit |
| `valgrind`, `gdb`, `strace`, `ltrace`, `perf`, `gcovr`, `tcpdump`, `file` | **ausentes** | nada de memcheck/trace/perf; cobertura por `gcov` cru; as sondas de PE nao podem depender de `file` |
| `nc`, `socat`, `ss` | presentes | inspecao de rede limitada a isso; os experimentos usam sockets em Python |
| `python3` | 3.11.2, `pip` 23.0.1, modulo `venv` OK | `lupa`/`luaparser`/`capstone` so via `python3 -m venv` + pypi (host permitido); sem interpreter Lua no PATH (`lua`, `luajit` ausentes) |
| `git` | 2.39.5 | `bundle`, `subtree`, `hash-object` disponiveis |

## Maquina e rede

- 2 vCPUs, 4 034 452 kB de RAM (~424 MB livres no momento da checagem), kernel `6.1.158+`,
  sem `cpu.max` visivel em cgroup. **Host ruidoso por natureza**: o `bench` so e valido com os
  criterios de ambiente do v1 reaplicados e **recalibrados para 2 CPUs** (o limiar de drift do
  v1 foi medido em outro host). `BLOCKED` e resultado legitimo; bloqueado nunca conta como aprovado.
- Interfaces: `lo`, `eth0`. Saida permitida apenas para `github.com`, `api.github.com`,
  `codeload.github.com`, `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`
  (verificado: os tres ultimos respondem `200`; `api.e2b.app` resolve mas a conexao devolve `000`).
- Loopback-only para experimentos de rede. Pisos do kernel medidos nesta sessao com
  `recriado`-independente `workspace/tools/tcp_window_probe.py`: pedir `SO_RCVBUF/SO_SNDBUF`
  1024 da efetivo **2304 / 4608**; pedir 256 da o mesmo 2304; sem `CAP_NET_ADMIN`
  (`CapEff=0`, euid 1001) ⇒ `SO_*BUFFORCE` indisponivel; capacidade em voo com as duas pontas
  apertadas **antes** do handshake ≈ **1 856 B** (~29 respostas de 64 B).
- `MU_REF_DATA` do v2: `/home/user/Muserver/MuServer` (o pacote de referencia conferido bit a bit:
  `ConnectServer.exe` sha256 `f25eecb6…`, 92 `.att` de 65 539 B, 99 arquivos em
  `Data/MonsterSetBase`, 71 binarios, `MuEditor.exe` em `Tools/Editores/MuEditor/`).

## R-8 — dependências do portão (medidas)

Disponíveis e usados por `tests/run_all.sh`: `timeout` (`/usr/bin/timeout`, exit 124 no prazo),
`setsid`, `realpath` (GNU coreutils 9.1), `date +%s%3N`, `ps -o pgid=`, bash 5.2 com `set -m`.
Ausentes: `valgrind`, `gdb`, `column`, `bc` (aritmética vai por `awk`).

Observação que virou regra (D2-24): processo de controle em segundo plano **sobrevive** à etapa se o
`wait` do pai não o recolher. Medido: `build.timeout` criado 600 s depois e `sleep 420` órfão com
`PPID 1`. O portão passou a usar `timeout(1)` + grupo de processo próprio, sem fundo.

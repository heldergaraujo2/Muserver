# ROADMAP — v2: fases e metas

Duas leituras do mesmo caminho: as **fases** (ordem de execução, com portão) e as **metas** (o que o
projeto precisa entregar, agrupadas por assunto). Estado por meta no fim da rodada das lacunas: A parcial (interop e cliente BLOCKED), B e C
parciais (limites do original e execução Lua BLOCKED), D parcial, E fechada como linha de base,
F fechada no backend, G NOT_IMPLEMENTED por decisão, H verde. Detalhe linha a linha em
`reports/auditoria-rastreabilidade.md`.

## Fases

| fase | produto | portão de saída | estado |
|---|---|---|---|
| R-0 | ambiente e toolchain | `docs/ENVIRONMENT.md` + compilação com sanitizadores | fechada |
| R-1 | inventário da referência | contagens reproduzíveis do pacote | fechada |
| R-2 | baseline e ritual de persistência | `verify-backup.sh` verde | fechada |
| R-3 | codec de enquadramento | `unit` 106/0 + `make-sintaxe` + falsificações | fechada |
| R-4 | serviço `mud2` + `mu2ctl` + `tests/net.sh` | `check` verde + matriz + F5/F6/F7 detectadas | **fechada** |
| R-5 | inspeção reproduzível do pacote original (`tools/pe_probe.py`, `att_probe.py`, `mb_probe.py`, `data_probe.py`) | `pe`=14/0 e `data`=21/0 com autos-teste e falsificações F8–F11; `conform` **não** feito (exige cliente real) | **fechada** 2026-10-12 |
| R-6 | interoperabilidade e golden | camada 1 (**conform** 15/15) e camada 2 (implementações próprias) comprovadas; camada 3 com evidência medida (`HackPacketCheck`: 272 entradas, 256 índices, 8 bits; code do v2 = 16 bits ⇒ fator 256) e **BLOCKED** com causa e caminho de desbloqueio; `golden` 42/42 com 38 vetores versionados e F20/F21 | **fechada no que é verificável** 2026-10-12 |
| R-7 | `bench` com critérios de validade (inclusive drift entre passadas) | `make -s bench` 15/15, critérios declarados antes, juiz separado (`tools/bench_check.py`); capacidade absoluta **BLOCKED**; 3 defeitos reais corrigidos (D2-27/28/29) | **fechada** 2026-10-12 no verificável |
| R-8 | portão único (`tests/run_all.sh` + `tests/gate_state.sh` + `tests/ref_check.sh`) | `gate`=18 PASS/0 FAIL/339 asserções em 22 etapas; `gate-selftest`=19/19 com F12–F14; **+ etapa `lua-enc` em 2026-10-13 (23 etapas, 3 BLOCKED)** | **fechada** 2026-10-12 |
| R-9 | documentação, publicação e continuidade | contínuo: `CONTINUITY.md` a cada rodada | em curso |

## Metas por categoria

### A. Reconstrução do servidor e compatibilidade com o cliente original
- **Existe (medido):** codec dos dois perfis (106 asserções); serviço de ensaio com 34 verificações de
  rede; `ConnectServer.exe` íntegro (`f25eecb6c65214b7`) como fonte de verdade futura.
- **Investigar:** enquadramento real no binário (não na Lua — `ProtocolCore.lua` não tem
  `HEAD_SIZE`/`PacketSize`/`opcode`); papel de `GameServerCS` vs `GameServer` vs `SpeedServer`; versão
  exata do conjunto.
- **Depende de:** R-5 (probes), R-6 (interop), Wine/Windows ou host do dono.
- **Prova:** `conform` + `interop` + `golden` verdes contra o binário real.
- **Risco:** alto e não quantificado — até haver `interop` real, qualquer afirmação de compatibilidade
  seria invenção.

### B. Rede e protocolo (inclusive limites de tamanho de pacote)
- **Existe (medido):** quadro de 2052 B; `E_INCOMPLETE` com `needed`; fila de 1 vaga; `POLLOUT` sempre
  que há resposta pendente; buffers padrão sem perda em 50/50 configurações da matriz.
- **Investigar:** se o protocolo original suporta corpo > 2048; limites de buffer/fila/alocação no
  binário; separar limite de protocolo × serviço × SO × cliente.
- **Depende de:** R-5/R-6.
- **Prova:** testes de fronteira (fragmentado, excessivo, truncado, malformado), `fuzz`, regressão de
  quadro e medição de memória sob carga.
- **Risco:** mudar `MU2_MAX_BODY` sem evidência quebra o contrato testado; extensões próprias do v2 não
  podem ser apresentadas como interoperáveis.

### C. Lua e scripts maiores
- **Existe (medido):** 148 `.lua` na referência (nenhum `.enc`: 2 caminhos casam `*luaenc*` — a
  ferramenta e o `.pdb`); originais e patches preservados em
  `../../workspace/changes/`; `LuaEncryptorTool.exe` no pacote.
- **Investigar:** se existe **algum** limite real de tamanho/carregamento (hoje não há medição);
  tratamento de script inválido; loops infinitos.
- **Etapa `enc` executada (2026-10-13):** a cifragem do script Lua do cliente tem **estrutura medida**
  (cabeçalho fixo de 8 B, sem padding, determinística, janela de 3 bytes do próprio cifrado
  suficiente e 2 insuficiente) e **algoritmo `BLOCKED`** com causa, famílias refutadas com número e
  condição de desbloqueio (`../../reports/enc-cifragem-lua.md`); `F23` `BLOCKED` (exige decodificador).
  Teste versionado: `tests/lua-enc.sh` (27 asserções, `blocked=2`).
- **Depende de:** R-5 (`data_probe.py`), suíte `data`.
- **Prova:** golden de scripts + regressão sobre os 6 `.lua` patcheados, com checksums e diffs.
- **Risco:** mexer em script original sem cópia versionada viola regra do projeto.

### D. Recursos 3D nativos e arquivos mais pesados
- **Existe (medido):** `.att` 276 (todos 65 539 B; 92 em `Data/Terrain`), `.ozt` 313, `.ozj` 106,
  `.bmd` 56, `.smd` 8.
- **Investigar:** assinaturas e estruturas; o que é limite do cliente e o que é do servidor; corpus de
  arquivos válidos e inválidos.
- **Depende de:** R-5 (`att_probe.py`, `mb_probe.py`), cliente real para validar renderização.
- **Prova:** validador por formato + regressão + evidência no cliente real quando a mudança depender de
  renderização.
- **Risco:** arquivo maior não é arquivo melhor — pode ser inválido ou estourar o cliente.

### E. Desempenho, FPS, fluidez e estabilidade
- **Existe (medido):** ASAN+UBSAN no portão; host conhecido (2 vCPUs, ~4 GB); `valgrind`/`gdb`
  ausentes; linha de base exploratória da R-7 (`bench` 15/15, critérios de validade declarados
  antes de rodar) — sem meta numérica.
- **Investigar:** linha de base de latência/throughput/CPU/memória; variação entre repetições (a matriz
  da R-4 já mostrou amplitude de até 104 respostas sob pressão).
- **Depende de:** R-7 e host adequado; cliente real para FPS.
- **Prova:** `bench` antes/depois com mediana, amplitude e critérios de validade definidos **antes**.
- **Risco:** publicar número deste host seria ruído; por isso não há meta numérica.

### F. Painel administrativo
- **Existe (medido):** `mu2ctl stats` funcional, lido pelo protocolo — é a base de controle.
- **Investigar:** o que precisa ser configurável; onde persistir configuração; interface desacoplada,
  autenticação e logs auditáveis.
- **Depende de:** R-4 (pronto) e de um mecanismo de controle documentado.
- **Prova:** iniciar, consultar, parar e diagnosticar o serviço reconstruído pelo painel, com testes e
  confirmação do estado real do processo.
- **Risco:** painel exposto sem proteção; e **nenhum** controle sobre `MuServer/`.

### G. Assistente de publicação online
- **Existe (medido):** portas da referência (ConnectServer TCP 44406 / UDP 55557, DataServer 55960,
  JoinServer 55970, SQL 1433) e configs (`ConnectServer.ini`, `ServerList.dat`, `AllowableIpList.txt`).
- **Investigar:** portas efetivas de cada componente da reconstrução; NAT/firewall/IP do dono;
  dependência real de banco.
- **Depende de:** host do dono — o sandbox não valida conectividade externa.
- **Prova:** diagnóstico de configuração, verificação de escuta, checklist e testes de conectividade
  reproduzíveis no ambiente do dono.
- **Risco:** abrir porta ou expor banco por conveniência; afirmar "servidor online" sem teste.

### H. Segurança, backup, regressão e continuidade
- **Existe (medido):** bundle restaurável, restaurado por clone, + `FULL=1 verify-backup.sh` 15/15
  (que clona o remoto e reconfere o bundle publicado); publicação conferida por `ls-remote`; ritual de fim de rodada; sanitizadores e `-Werror` obrigatórios;
  classificação de todo fechamento por motivo.
- **Investigar/estender:** cobertura guiada por feedback no `fuzz` (o motor é próprio e
  determinístico: 12/12, 150 000 iterações; sem `afl`/`clang` no host).
- **Depende de:** nada técnico — é processo.
- **Prova:** o próprio verificador + `gate-selftest` (R-8).
- **Risco:** o histórico do projeto é uma perda de ambiente; trabalho fora da árvore rastreada morre.

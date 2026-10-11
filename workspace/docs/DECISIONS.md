# DECISIONS — decisões de engenharia e suas razões

Formato: contexto → decisão → consequência. Só registro decisões com efeito
duradouro ou que precisem ser questionáveis depois.

---
### D-01 · Não neutralizar proteção de licença, serial ou anti-cheat
**Contexto:** o `GameServer.exe` é Themida/WinLicense; há gate de licença no
próprio Lua (`GetLicenseCustomerName() ~= <CustomerName da licença>`) — o valor literal está no próprio script do fornecedor; não o repito nestes relatórios., `Owner.ini`, `.premium`,
`GetMainInfo-Premium.exe` e vinculação a hardware ID. Seria tecnicamente
possível, em parte, atacar isso.
**Decisão:** não fazer, e não escrever ferramenta que permita fazer. O trabalho
licenciatório fica limitado a *diagnosticar configuração de uso autorizado* e
documentar requisito de fornecedor.
**Consequência:** a causa dos crashes fica fora do alcance de um patch meu — o
que deslocou o esforço para (a) forense de dumps para *informar* o dono/fornecedor
e (b) endurecer a camada Lua e os dados, que são de fato nossos. Registrado em
`AUDIT.md` §2/§5.

### D-02 · Não sobrescrever o binário protegido nem patchear o header PE
**Contexto:** a ausência de `LARGEADDRESSAWARE` (A5) é um defeito real e o patch
clássico é 1 bit no COFF header (`editbin /LARGEADDRESSAWARE`).
**Decisão:** **não** aplicar. Themida frequentemente valida os próprios
metadados de PE; um header alterado pode transformar um problema de 2 GB em um
servidor que não inicia — e não tenho Windows aqui para medir isso.
**Consequência:** entreguei o diagnóstico, a evidência e o *método de validação*
(em `NEXT_TASK.md` T3) para rodar em Windows sobre cópia, com rollback. Nenhum
binário foi tocado.

### D-03 · Corrigir por cima da camada Lua, não por dentro dos scripts de conteúdo
**Contexto:** havia duas formas de reduzir crash: endurecer o *mecanismo* de
bridge, ou reescrever os scripts de conteúdo (`UpgradeMachine/Config.lua` tem
131 KB de tabelas).
**Decisão:** endurecer o mecanismo. Um `pcall` no despachante protege os 28
arquivos de cada instância — inclusive código que eu não lerei por inteiro — e não
muda regra de jogo nenhuma.
**Consequência:** exigi do patch **paridade de comportamento** demonstrada
(teste diferencial) em vez de "parece mais robusto".

### D-04 · Preservar o estado original sem imobilizar o trabalho
**Contexto:** a missão proíbe sobrescrever arquivos originais sem necessidade
documentada.
**Decisão:** tripla camada de reversão: (1) o commit `6eabb45` no Git;
(2) baseline pré-patch copiado em `workspace/changes/originals/` com md5
registrado; (3) cópia do resultado em `changes/patches/`. Além disso `git
core.autocrlf=false` + `.gitattributes` para o Git não reescrever CRLF de
`.ini`/`.dat` que o servidor lê.
**Consequência:** editar no lugar ficou seguro e o `git diff` continua sendo a
revisão legível das mudanças.

### D-05 · Não apagar logs/dumps/`.bak` do disco nem reescrever o histórico
**Contexto:** 296 MB de artefatos versionados, e os `.bak` contêm PII.
**Decisão:** adicionar `.gitignore` + um script de remoção do índice
(`tools/untrack_artifacts.sh`, dry-run por padrão), mas **não** executar remoção
nem `git-filter-repo` sem o dono.
**Duas razões concretas:** (a) os 34 `.dmp` são a única evidência forense deste
laudo; (b) os 504 `.tmp` contêm a **única cópia legível** de um script Lua do
servidor (ver C-07) — apagá-los como "limpeza" destruiria código. Por isso o
script manda rodar `recover_tmp_lua.py` antes.

### D-06 · Separar medido / inferido / refutado, e registrar as refutações
**Contexto:** 3 hipóteses plausíveis caíram durante a auditoria.
**Decisão:** mantê-las escritas em `AUDIT.md` §3.5 com a evidência que as matou.
**Consequência:** o relatório não sugere correções baseadas em hipóteses mortas
(ex.: adicionar `ClearPacket`, que seria risco de double-free).

### D-07 · Testar a ferramenta de teste
**Contexto:** a primeira versão do check P04 marcou 1 113/1 113 linhas como
inválidas — um validador inútil; e o `as_int` usava `int(x, 0)`, que no Python 3
recusa `002`, fazendo o check ignorar 82 % das linhas silenciosamente.
**Decisão:** escrever `test_preflight_selfcheck.py` com fixtures e um teste
dourado do parser de minidump sobre um dump real do repositório.
**Consequência:** o bug do `as_int` foi pego por teste, não por sorte. A cobertura
do P04 subiu de 1 113 para 6 046 linhas validadas e os números deste laudo são os
pós-correção. Ferramenta sem teste é ferramenta não confiável.

### D-08 · Recuperar antes de concluir
**Contexto:** "não descartar recursos por parecerem antigos ou incomuns".
**Decisão:** tratar lixo (`t*.tmp`) como artefato arqueológico, e o `.pdb` único
como pista (é do LuaEncryptorTool, não do GameServer — o que *descarta* a
esperança de símbolos para o GameServer e é informação útil).
**Consequência:** 146 conteúdos únicos preservados em `recovered/lua/` + relatório
JSON/TSV; e descoberto que o sistema "PvP Balance" não está plugado (A10).

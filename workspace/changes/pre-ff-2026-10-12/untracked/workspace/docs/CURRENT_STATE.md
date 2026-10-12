# CURRENT_STATE — estado técnico em 2026-10-11

## Classificação por componente (seção 12 da missão)
| Componente | Função | Fonte | Análises | Diagnóstico | Estado |
|---|---|---|---|---|---|
| **GameServer.exe** (×4) | simulação do mundo | ausente + Themida | 46,5 MB image, PE, 33 dumps, memória descriptografada | causa dos crashes isolada em 5 mecanismos | **estável apenas se não usar hot-reload** |
| ConnectServer | handshake de entrada | ausente, sem protetor | PE, ini, ServerList.dat | build 2017 vs `_old` 2021 — provável troca de nomes | sem defeito funcional detectado |
| JoinServer | autenticação | ausente, sem protetor | PE, ini, AllowableIpList | `MD5Encryption=0`, `MaxHardwareIdConnection=0`, senha global em texto | **risco de segurança** |
| DataServer | persistência | ausente, sem protetor | PE, ini, `BadSyntax.txt` | `BadSyntax.txt` contém só `//Syntax`+`end` → parser OK | OK |
| MHPServer | detecção de hack | ausente, sem protetor | PE, ini, BlackList | `MemoryGuardSwitch=0`, `MacroProtectSwitch=0` = desligado; 8 `MemoryAddress*` com valores que não parecem endereços válidos de imagem | decisão de operação pendente |
| GameServerCS | instância custom | ausente + Themida | PE, `ExperienceList.txt` 150 905 B (11× os demais) | build e balanceamento distintos, deliberados? | **divergência não resolvida** |
| DiscordServer | ponte com bot | ausente + Themida | PE, ini, libs | token do bot versionado | **incidente aberto** |
| PSGuard / Monitor | anti-cheat + Main | ausente + MPRESS/Themida | PE, DLLs MySQL/SSL, Screenshots, Logs | depende de licença de fornecedor | fora do escopo de modificação (D-01) |
| **Data/Script (Lua)** | toda a customização | **fonte legível** | 77 arquivos nas 3 árvores (56 legíveis + 21 criptografados), AST + execução real | 2 defeitos de robustez corrigidos, 1 latente documentado | **MELHORADO E TESTADO** |
| Data/** (config/jogo) | regras do mundo | texto | 6 046 linhas de spawn, .att, .ozt | 17 retângulos invertidos, 27 linhas fora do formato, 24 mapas sem terreno | **corrigível, aguarda decisão** |
| DB (SQL Server) | persistência | só backups | 5 `.bak`, 2 `.reg`, 4 `.sql` | PII + hashes versionados; DSN 32-bit obrigatório | **incidente aberto** |

## O que está provado vs. o que é inferência
**Provado por medição:** assinatura/offset de todos os 33 dumps analisáveis; os 5
mecanismos de falha (por desassemblagem da memória do dump); `p=1,5e-14` de
correlação reload↔crash; acúmulo de handlers 1→3→10 em teste executado; ausência
de LAA; presença de Themida/VMProtect; os números de inventário e redundância.

**Inferência com evidência (não provada):** que o `rep movsd` de `+0xEC73D` lê um
comprimento vindo de pacote sem validação (o contexto instrucional aponta isso,
mas não se viu o chamador); que a árvore STL corrompida vem de concorrência
loop×I/O (poderia ser use-after-free do reload); que a mitigação "não usar
hot-reload" elimina os crashes — elimina o *gatilho observado*, não o defeito.

**Hipóteses abandonadas no caminho (registradas em AUDIT §3.5):** monstro-inválido
como causa de crash; tile intransitável como explicação das rejeições; leak de
`ClearPacket`.

## Métricas atuais
- Testes: **71 casos TAP, 0 falhas** (35 + 11 + 25) + verificação de sintaxe dos
  56 `.lua` legíveis + preflight fim a fim — `bash workspace/tests/run_all.sh` verde.
- Preflight: 22 ERRO / 18 AVISO / 17 OK. Dominados por A1 (credenciais/PII) e
  A11 (protetores), que são restrições, não defeitos corrigíveis por mim.
- Arquivos alterados em produção: **6** (todos Lua/config), com baseline em
  `changes/originals/`.
- Risco remanescente mais alto: **credenciais no histórico do Git** (A1).

## Ambiente deste workspace (limitação estrutural)
Linux, sem Windows, sem SQL Server, sem cliente MU, sem .NET/MSVC. Portanto:
compilação não aplicável (não há fonte), e boot/conectividade/auth não puderam
ser testados. Nada nessas áreas foi declarado verificado.

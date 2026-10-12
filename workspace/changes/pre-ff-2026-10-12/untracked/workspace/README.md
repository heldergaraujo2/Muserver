# Workspace seletivo — auditoria e reengenharia do MuServer (MU Online Season 6.20)

Área de trabalho da missão iniciada em **2026-10-11**. Ela é *adjacente* aos
arquivos de runtime (`MuServer/`), nunca dentro deles, para que nada do deploy
seja confundido com ferramental de análise.

## Regras desta área

1. **Descoberta progressiva.** Nada de copiar os 10 021 arquivos para cá.
   Só entram os arquivos necessários a cada tarefa, com o caminho relativo
   e a origem registrados.
2. **Índice persistente.** Estes documentos são a memória do projeto. Se um
   estiver desatualizado, o trabalho ainda não terminou.
3. **Não destrutividade.** Nenhum arquivo original é apagado ou sobrescrito sem
   justificativa escrita em `changes/CHANGELOG.md`. O baseline pré-patch fica em
   `changes/originals/`.

## Mapa dos documentos

| Arquivo | Conteúdo |
|---|---|
| `docs/PROJECT_OVERVIEW.md` | arquitetura real do servidor, papéis dos componentes |
| `inventory/INVENTORY.md` | inventário global (10 021 arquivos, por tipo/diretório) |
| `docs/DEPENDENCIES.md` | dependências entre serviços, portas, licenças |
| `docs/CURRENT_STATE.md` | estado técnico atual, o que está provado vs. hipótese |
| `docs/DECISIONS.md` | decisões de engenharia e suas razões |
| `tests/TEST_RESULTS.md` | testes executados, bloqueados e não realizados |
| `changes/CHANGELOG.md` | alterações implementadas, arquivo a arquivo |
| `docs/NEXT_TASK.md` | próxima tarefa prioritária e como retomá-la |
| `reports/AUDIT.md` | relatório de auditoria com o diagnóstico dos 34 dumps |

## Ferramentas (`tools/`)

| Ferramenta | Para que serve |
|---|---|
| `muserver_preflight.py` | validação estática pré-boot (P01–P11); saída para CI |
| `minidump_analyze.py` | parser de `.dmp` do Windows sem dependências |
| `crash_families.py` | agrupa dumps por assinatura e desassembla o ponto de falha |
| `dump_disasm.py` | desassembla a memória do dump (código já descriptografado) |
| `pe.py` / `scan_exes.py` | cabeçalho PE, LAA, seções, importações, protetores |
| `terrain_check.py` | spawn × terreno `.att`, calibrado com os logs do servidor |
| `recover_tmp_lua.py` | recupera os scripts Lua perdidos nos `t*.tmp` |

## Testes (`tests/`)

`test_scriptcore_differential.py` e `test_protocolcore_reload.py` são **testes
diferenciais**: comparam o comportamento original e o corrigido executando os
dois em um interpretador Lua real. Rodar tudo:

```sh
./workspace/tests/run_all.sh
```

## Estado em uma linha

6 arquivos Lua corrigidos em produção, 46 testes de paridade/correção passando,
causa raiz dos crashes localizada (reload → bug de vida útil de objeto) e 1
incidente de credenciais expostas aguardando ação do proprietário.
Detalhes em `docs/NEXT_TASK.md`.

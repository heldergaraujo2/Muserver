# Relatorios do v2

Convencao obrigatoria, escolhida por uma razao medida e nao estilistica: o
`.gitignore` do repositorio que hospeda esta arvore ignora
`workspace/reports/*.{json,txt,err}` e `workspace/recovered/`. Ja perdemos um
projeto inteiro por ele viver fora do caminho persistido; entao aqui vale:

- saida de ferramenta que precisa virar evidenci versionada: **`.tsv`** (dados) e
  **`.md`** (prosa), ambos dentro de `reports/`;
- saida descartavel, regeneravel ou de um unico run sem valor: **`.raw`** (esta
  ignorada por `.gitignore`);
- **os relatorios aqui sao evidencia historica**: foram escritos quando o v2 morava em `recriado/`
  dentro do monorepo `heldergaraujo2/Muserver`, e por isso citam `recriado/...` e `../workspace/...`.
  Nao foram reescritos na migracao de 2026-10-12 (reescrever evidencia seria adulterar registro):
  o mapeamento de caminhos esta em `docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`.
- `migracao-destino.tsv` registra a **primeira** rodada da migracao (split de 34 commits); as
  medidas da publicacao vigente estao em `workspace/backups/MANIFEST.md` e em
  `docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md`.
- `.json`/`.txt`/`.err` **nao** vao para `workspace/reports/` — nesse caminho eles
  sao engolidos pelo ignore e deixam de existir na persistencia;
- nenhum numero e publicado sem o comando que o gerou na mesma linha do documento
  ou no rodape do proprio `.tsv`.

# Relatorios do v2

Convencao obrigatoria, escolhida por uma razao medida e nao estilistica: o
`.gitignore` do repositorio que hospeda esta arvore ignora
`workspace/reports/*.{json,txt,err}` e `workspace/recovered/`. Ja perdemos um
projeto inteiro por ele viver fora do caminho persistido; entao aqui vale:

- saida de ferramenta que precisa virar evidenci versionada: **`.tsv`** (dados) e
  **`.md`** (prosa), ambos dentro de `recriado/reports/`;
- saida descartavel, regeneravel ou de um unico run sem valor: **`.raw`** (esta
  ignorada por `recriado/.gitignore`);
- `.json`/`.txt`/`.err` **nao** vao para `workspace/reports/` — nesse caminho eles
  sao engolidos pelo ignore e deixam de existir na persistencia;
- nenhum numero e publicado sem o comando que o gerou na mesma linha do documento
  ou no rodape do proprio `.tsv`.

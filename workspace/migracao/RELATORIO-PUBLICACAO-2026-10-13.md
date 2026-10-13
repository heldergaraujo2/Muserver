# Relatório — publicação do projeto recriado dentro do monorepo (2026-10-13)

Arquivo novo; nenhum relatório anterior foi sobrescrito. Medidas desta rodada também em
`workspace/migracao/medidas-destino-rodada2.tsv` (rodada anterior) e no `MANIFEST.md` do backup.

## 1. Mudança de estratégia

A escrita no repositório separado `heldergaraujo2/MuserverRecriado` responde `403` (permissão da
instalação do GitHub App) e ele **continua vazio**. Em vez de insistir, o projeto recriado passou a ser
publicado **dentro do repositório já autorizado** (`heldergaraujo2/Muserver`), na pasta
**`MuserverRecriado/`** — sem nível extra (`MuserverRecriado/Makefile`, `MuserverRecriado/src/`, …) e
sem tocar em `MuServer/` nem no resto do monorepo.

Nada foi publicado no repositório separado e nenhuma permissão foi contornada.

## 2. Auditoria inicial (antes de alterar arquivo)

| verificação | resultado |
|---|---|
| branch / HEAD local | `arena/cf1de8ce-muserver` — o sandbox renasceu com o `.git` no commit base `6eabb45b9e7939a3061f4757ed6791efef7c5c3b` e a árvore de trabalho restaurada |
| HEAD remoto da branch | `538f8df0e527216d8ac8ab391e9e4ff3717141ac` (o histórico completo estava no remoto) |
| reconciliação | `HEAD` era ancestral do remoto ⇒ fast-forward; o merge recusou por colisão de não rastreado, então o índice foi reconciliado com `git reset --mixed origin/arena/cf1de8ce-muserver` (**só índice**; worktree intocada, sem `reset --hard`, sem `clean`, sem force) e `git status --porcelain` ficou **vazio**: a árvore == commit remoto, byte a byte |
| artefato validado | `/tmp` zerado pelo reprovisionamento: o artefato foi **reconstruído pelo caminho determinístico** `bash workspace/migracao/preparar-destino.sh /tmp/mu2destB5 --gate` → `ok=6/falhas=0`, HEAD `51b2b157`, árvore `99c9b8ff`, 42 commits, 174 arquivos, bundle 662 628 B sha256 `76d71bd8…`, ponta `f42769f1` — os mesmos valores das constantes fixadas |
| origem `recriado/` | árvore `760ac5df…`, 83 arquivos; `make -s check` exit 0 (data=21, 0 falhas) |
| referência `MuServer/` | árvore `fade0461…`, 10 021 arquivos, `status` limpo |
| bundles/manifestos | monorepo `mu2-v2.bundle` (regravado nesta rodada) e transporte `workspace/migracao/destino-muserverrecriado.bundle` (1 360 014 B, sha256 `0a9ab745…`) preservados |

## 3. Cópia para `MuserverRecriado/`

- Fonte: **o artefato validado** (não uma reconstrução improvisada).
- Método: `git -C /tmp/mu2destB5 archive HEAD | tar -x -C MuserverRecriado` — só arquivos rastreados,
  **sem `.git` embutido** e **sem `out/`**.
- Conferência: **174 = 174** arquivos, com **modo e blob git idênticos nos 174** (comparação
  `git ls-tree -r` do artefato × `git ls-files -s` da pasta). O `.gitattributes` próprio da pasta
  (`* -text`, `*.bundle binary`) garante que a cópia não converte bytes: `git check-attr` confirma
  `text: unset` nos arquivos amostrados, incluindo o bundle.
- Nada da pasta é ignorado no monorepo (`git status --ignored` não acusa arquivo ignorado além do
  `out/` de build).
- **Diferenças intencionais — 9 arquivos, todas documentais:** `README.md` (nova seção de localização,
  propósito, como testar, o que não foi incluído, como diferenciar de `MuServer/`), os 7 documentos
  canônicos (`docs/CHANGELOG`, `CONTINUITY`, `CURRENT_STATE`, `DECISIONS`, `ENVIRONMENT`, `NEXT_TASK`,
  `ROADMAP` — cabeçalho de localização) e `docs/MIGRACAO-MUSERVERRECRIADO-2026-10-12.md` (§9, nota de
  localização). O verificador do projeto declara divergência nesses caminhos (`DIV_OK`), então o
  desvio é auditável, não silencioso.

## 4. Validação na nova localização

| conjunto | resultado |
|---|---|
| `make -s check` | exit 0 — unit 106, make-sintaxe 7, net 34, **pe 14, data 21** (a referência irmã `../MuServer` existe, então o escopo "referencia" roda), 0 falhas |
| `make -s gate` | exit 0 — **18 PASS, 0 FAIL, 2 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 339 asserções, 22 etapas** (69 203 ms). BLOCKED: `interop` camada 3, `lua`; SKIPPED: `net-matrix`, `persistencia` (opt-in) — bloqueado/ignorado nunca é aprovado |
| `make -s gate-selftest` | exit 0 — **19/19** |
| `make -s fuzz` | exit 0 — **12/12**, 150 000 iterações, motor determinístico próprio |
| `ref-intacta` (dentro do portão) | **PASS 8/8** — árvore `fade0461…` da referência inalterada |
| efeitos colaterais | nenhum: `git status` do monorepo fora da pasta ficou limpo; só o `out/` da pasta é criado (ignorado) |
| segredos/credenciais | nenhum token, chave ou senha nos 174 arquivos; `workspace/reports/A1-secrets.md` é o relatório **redigido** da auditoria |
| caminhos relativos | funcionam na nova localização: a suíte resolve a raiz pelo próprio script e a referência por `MU_REF_DATA` (padrão `../MuServer`); nada aponta para fora da pasta a não ser essa referência opcional |

Perfil diferente do artefato isolado, medido e explicado: sem a referência ao lado, o mesmo portão
mede **14 PASS / 6 BLOCKED / 281 asserções** (`pe`, `data`, `cfg`, `ref-intacta` a mais em BLOCKED).

## 5. Exclusões (por decisão, registradas)

| excluído da pasta | motivo |
|---|---|
| `MuServer/` (~615 MB, 10 021 arquivos) | é a referência original do fornecedor; não é código deste projeto e não é redistribuído. Permanece no monorepo, ao lado, somente leitura |
| `workspace/migracao/` | ferramenta da **origem** (split, transformador, transporte); dentro do projeto seria circular |
| credenciais | nada sigiloso é copiado ou versionado; auditoria de segredos é publicada redigida |
| reescrita de relatórios históricos | `reports/` é evidência publicada e **não** foi reescrita (mapeamento em `reports/README.md`) |

## 6. Backups

- **Monorepo (regravado nesta rodada, depois do último commit):** snapshot orphan `mu2-snapshot` @
  `401839893cebb7c90ec7445250520af51b61eec8` (83 arquivos), `mu2-v2.bundle` **259 727 B**, sha256
  `ac5d3c86cf8aa14aacf8d5bfe1e79ad9d0a51452486fd4f5728ed24b67405fc8`; `MANIFEST.md` atualizado.
- **Pasta:** `MuserverRecriado/workspace/backups/mu2-v2.bundle` (662 628 B, sha256 `76d71bd8…`) é a
  cópia independente do **artefato** como validado — mantida intacta (antecede a nota de localização);
  a divergência de `README.md`/`docs/` é declarada.
- **Transporte:** `workspace/migracao/destino-muserverrecriado.bundle` (1 360 014 B) preservado, para o
  caso de o repositório separado ser habilitado.

## 7. Commits e publicação

| commit | conteúdo |
|---|---|
| `a6ddf81` | `feat: add standalone MuserverRecriado project` — a pasta com os 174 arquivos |
| `618bb35` | docs de continuidade da origem (CHANGELOG, CURRENT_STATE, CONTINUITY) + README do pacote |
| (este relatório) | entra no commit do backup regravado, junto com `workspace/backups/` |

Push para `origin/arena/cf1de8ce-muserver` em seguida; a confirmação é leitura de volta
(`git ls-remote` + conteúdo da pasta no GitHub), nunca presumida. O repositório separado
`heldergaraujo2/MuserverRecriado` segue vazio.

## 8. Pendências reais e próxima tarefa

1. **`enc`** — cifragem do script Lua do cliente, conforme `docs/NEXT_TASK.md` (é a próxima tarefa
   científica; esta rodada não a iniciou).
2. **Pendência do proprietário (não bloqueia a pesquisa):** incluir `MuserverRecriado` na instalação do
   GitHub App (*Contents: Read and write*) se quiser o artefato publicado lá também; o caminho
   reprodutível (`workspace/migracao/publicar-destino.sh`) continua pronto.
3. **Limitações que seguem valendo:** `interop` camada 3 e `lua` **BLOCKED** (sem binário original em
   execução / sem intérprete no host); `bench` é baseline exploratória e pode sair BLOCKED sob carga;
   nada aqui declara compatibilidade com o cliente original.

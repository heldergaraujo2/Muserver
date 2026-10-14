# Relatório da rodada — fechamento da publicação (2026-10-12/13)

Relatório novo, sem sobrescrever nada. Medidas desta rodada em
`workspace/migracao/medidas-destino-rodada2.tsv`; valores históricos da rodada 1 seguem em
`recriado/reports/migracao-destino.tsv` (não reescrito).

## 1. O destino foi atualizado? **NÃO.**

- Tentativa de operação Git normal, autenticada e autorizada, **com o artefato final validado**:
  `bash workspace/migracao/publicar-destino.sh /tmp/mu2destR10` → exit 1 no passo do push:

  ```
  remote: Permission to heldergaraujo2/MuserverRecriado.git denied to heldergaraujo2.
  fatal: unable to access 'https://github.com/heldergaraujo2/MuserverRecriado.git/': The requested URL returned error: 403
  ```

- Antes de tentar, o estado remoto foi **reconferido** (`git ls-remote` sem refs — repositório
  vazio), para não presumir nada. Depois da falha: **nada foi escrito**, nenhuma retentativa em laço,
  nenhum contorno de permissão.
- **Destino remoto:** `https://github.com/heldergaraujo2/MuserverRecriado.git`, branch padrão `main`,
  **vazio** (SHA remoto inexistente). **Origem:** `heldergaraujo2/Muserver`, branch
  `arena/cf1de8ce-muserver` = **`e8b991bb46bd85d3f9379753ea54adb8772ed7d8`** (conferido por
  `git ls-remote` depois do push).
- **Ação do proprietário (único desbloqueio):** incluir `MuserverRecriado` na seleção de
  repositórios da instalação do GitHub App, com *Contents: Read and write*. Depois disso,
  `bash workspace/migracao/publicar-destino.sh /tmp/mu2destR10` (ou um build novo) conclui e confere.

## 2. O que a rodada fechou (tudo medido)

- **Quinto defeito corrigido na origem** (`3c49470`): a linha de base do teste de descritores era uma
  leitura solta logo depois da bateria de malformações e o close assíncrono ainda estava em voo
  (1 de ~10 execuções lia `fd_antes=9` com piso real 8). A base passou a ser o **piso observado numa
  janela curta**; a asserção (`base == estabilizado == 2ª rodada`) continua estrita. Depois da
  correção: 8/8 na origem e 6/6 + 6/6 no destino, `base=8` sempre.
- **Defasagens numéricas corrigidas** (`check` 182, `gate` 339, `seguranca` 13, `admin` 24,
  `ref-intacta` 8, `verify-backup` `FULL=1` 15/15) — commit `60260f3` e o topo do `CHANGELOG`.
- **Cópia independente do monorepo regravada**: `workspace/backups/mu2-v2.bundle` (snapshot orphan
  `2aa641a1`, 83 arquivos, 258 497 B, sha256 `bd17e807…`), MANIFEST com a linha de ponta no formato
  que o verificador parseia. `FULL=1 bash recriado/scripts/verify-backup.sh` → **ok=15 falhas=0
  blocked=0** (antes: 11 ok / 4 falhas, todas por snapshot velho e HEAD não publicado).
- **Pacote de migração versionado**: `workspace/migracao/` com os 7 assets e o transformador
  `adaptar-destino.py` (asserção por substituição; o patch pinado na base ficou como registro do
  caminho abandonado). README do pacote reescrito (descrevia o patch e números da rodada 34).

## 3. Artefato do destino (local, validado; ainda não publicado)

- Construído **do zero duas vezes** (`/tmp/mu2destR9` e `/tmp/mu2destR10`), com as constantes finais:
  `preparar-destino.sh --gate` → **ok=6 falhas=0** e resultados idênticos nas duas.
- **HEAD** `51b2b1574e2fb02cfd54ab34d49cdfd31d69f6b5`; **árvore** `99c9b8ffe2982da0a1921788d3a173572e4b80e9`;
  **42 commits, 174 arquivos**; `.git` ≈ 2 MB (pack de 543 KiB; o pack do monorepo tem 134 MB).
- **Histórico preservado:** `git subtree split --prefix=recriado` = **39 commits**, tip
  `eee2a353e2468cc3ae2edd8b2108115e4c81e91f` (base `3c49470`), mensagens originais intactas.
- **Bateria:** `make -s gate` → **14 PASS, 0 FAIL, 6 BLOCKED, 0 NOT_IMPLEMENTED, 2 SKIPPED, 281
  asserções, exit 0**; `make -s check` exit 0; `gate-selftest` 19/19; `fuzz` 12/12 (150 000
  iterações, 52 sementes); `verify-backup.sh` ok=9 / falhas=1 (a publicação em falta, honesta) /
  blocked=1 (referência ausente).
- **Clone independente** (`/tmp/cloneR10`): inventário e conteúdo **idênticos**
  (`git ls-tree -r` sha256 `be535006…`), 174 arquivos, `make -s check` sem falhas.
- **Cópia independente do destino:** snapshot `f42769f1…`, bundle 662 628 B, sha256 `76d71bd8…`
  (restauração por `git clone -b mu2-snapshot` + `make -s check` conferida pelo build).
- **Transporte:** `workspace/migracao/destino-muserverrecriado.bundle` (1 360 014 B, sha256
  `0a9ab745…`, 3 refs: `main`, `mu2-snapshot`, `HEAD`) — `git clone -b main` dá a árvore idêntica e
  `make -s check` sem falhas. É este arquivo que preserva o destino inteiro enquanto o push é 403.

## 4. Exclusões (por decisão, registradas)

| excluído | motivo |
|---|---|
| `MuServer/` (~615 MB, 10 021 arquivos) | referência do fornecedor; não é do projeto e não deve ser publicada → 6 etapas do portão saem **BLOCKED** no destino (`pe`, `data`, `cfg`, `ref-intacta`, `interop` camada 3, `lua`) |
| `workspace/migracao/` | ferramenta da **origem** (split, transformador, bundle de transporte); dentro do destino seria circular |
| credenciais | nenhum token/segredo nos arquivos versionados; `A1-secrets.md` é o relatório **redigido** da auditoria |
| reescrita de relatórios | `reports/` do destino é evidência histórica: não foi reescrita, só mapeada (ver `reports/README.md` do destino) |

## 5. Limitações desta rodada

- **Nada aqui afirma publicação.** O destino só é declarado publicado depois de `git ls-remote`
  conferir o SHA remoto — não conferiu (repositório vazio).
- `bench` pode sair `BLOCKED` sob carga (bloqueado não é falha nem meta).
- Números exatos de `.git` do destino são citados como escala (≈ 2 MB) de propósito: o número exato
  muda a própria árvore e nunca fecha.

## 6. Próxima tarefa

- **Publicação:** bloqueada no proprietário (item 1). Nada a fazer do lado técnico enquanto o App não
  incluir o repositório; o artefato e o transporte estão preservados e re-validáveis.
- **`enc`:** **não iniciada.** A instrução vigente após o 403 é parar as tentativas e não avançar para
  `enc`; a retomada depende do proprietário. A próxima tarefa científica segue registrada em
  `recriado/docs/NEXT_TASK.md`.

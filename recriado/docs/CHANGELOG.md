# CHANGELOG do v2

## R-0/R-1/R-2 — 2026-10-12
- Aberta a arvore `recriado/` (v2) dentro do repositorio rastreado da sessao, com
  `.gitignore` proprio, `reports/README.md` (regra de extensao por causa dos padroes de
  ignore do hospedeiro) e os docs `README`, `CURRENT_STATE`, `NEXT_TASK`, `DECISIONS`
  (D2-01..D2-10), `ENVIRONMENT`.
- Tentativa de recuperacao do v1 encerrada com veredito (Etapa 1): nenhum mecanismo
  autorizado disponivel do sandbox; solicitacao pronta em
  `../../workspace/reports/ARENA-RECOVERY-REQUEST-2026-10-12.md`.
- Permissao do GitHub diagnosticada com discriminador de API + `push --dry-run` (nenhum
  ref criado): o App de autenticacao **nao tem** `MuserverRecriado` na selecao de
  repositorios. Instrucao manual em `NEXT_TASK.md` secao "acao do dono".
- Ambiente medido (`docs/ENVIRONMENT.md`): sem clang ⇒ sem libFuzzer; sem
  valgrind/gdb/strace/perf/file; ASAN+UBSAN e hardening compilam; 2 vCPUs/4 GiB ⇒ limiar de
  drift do `bench` a recalibrar; `MU_REF_DATA` presente e conferido.
- Mecanismo de backup independente criado: `scripts/verify-backup.sh` + `backup/`
  (bundle limitado a `recriado/**` + `MANIFEST.md` com SHA-256), com teste de restauracao
  por clone a partir do bundle. Nada de `src/` ainda: **nenhum teste de C foi executado**,
  e nenhuma suíte do v1 deve ser considerada reproduzida.

### R-0, fechamento da rodada (mesma data)
- Backup independente gravado e **conferido por restauracao real**: `backup/mu2-v2.bundle`
  (17 225 B, historia do `recriado/**` via subtree split, ponta `17f4f79`) + `backup/MANIFEST.md`
  com SHA-256. `scripts/verify-backup.sh`: 6 verificacoes, todas verdes depois do commit.
- Defeito encontrado pelo proprio verificador: o `git clone` do bundle sem `-b mu2-v2` nascia com
  HEAD para um `main` inexistente (checkout vazio + warning ignorado). Corrigido no script e no
  MANIFEST. Fica registrado porque e o tipo de bug que so aparece quando se testa restaurar.
- Publicacao conferida de volta: `origin/arena/cf1de8ce-muserver` == HEAD local (`git ls-remote`).
  Nenhuma ref extra publicada; `mu2-v2` e branch local de trabalho do backup.
- Etapa 2 com causa exata: `collaborators/.../permission` responde 200 em `Muserver` e
  `403 Resource not accessible by integration` em `MuserverRecriado` para o mesmo token
  autenticado como o dono => selecao de repositorios do App, nao scope. Sonda de escrita
  nao mutante (`push --dry-run`): 403. Nenhum ref criado no repo de desenvolvimento.

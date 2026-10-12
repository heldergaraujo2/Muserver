# MuserverRecriado — v2 (reconstrucao incremental)

Esta arvore e a **reconstrucao** do servico de rede `mu2` (perfil `orig`/`mur0`,
`ConnectServer`-compativel) depois de a implementacao anterior (20 commits, ultimo
HEAD conhecido `c5706a5`) ter sido perdida com o sandbox em 2026-10-12.

## O que isto e, e o que nao e

- **E**: um projeto novo, com historia propria, comecando em R-0. O contrato do v1
  foi reafirmado como decisao documentada (`docs/DECISIONS.md`, numeracao `D2-xx`).
- **Nao e**: recuperacao. Nenhum arquivo do v1 existe aqui. Nenhum numero do v1 e
  resultado deste projeto: os unicos valores antigos citados sao **alvos**, e a
  frase que marca isso deve acompanhar qualquer tabela de medicao.
- **Ainda nao existe**: nenhum teste de C foi executado nesta arvore. Esta rodada produz estrutura,
  evidencia de ambiente e o mecanismo de persistencia/backup; `src/` esta vazio
  de proposito ate a fase R-3.

## Por que mora dentro de `Muserver/` (e nao num clone irmao)

O v1 morreu exatamente por morar num clone nao rastreado (`/home/user/MuserverRecriado`)
com `push` sem autorizacao: o mecanismo de persistencia da sessao grava o diff da
arvore do repositorio da sessao — o irmao ficou de fora. Ver a evidencia em
`../workspace/reports/RECUPERACAO-BUSCA-2026-10-12.md`. Portanto:

1. toda rodada termina com `git add <caminhos explicitos>` (nunca `git add -A`: o
   `.gitignore` hospedeiro documenta a armadilha de delecao silenciosa), commit,
   `git push`, e `git ls-remote` **lido de volta** para conferir o SHA remoto;
2. uma copia independente e regravada a cada rodada em `backup/` com manifesto e
   hash, e o script `scripts/verify-backup.sh` e que atesta (backup nao conferido
   nao e backup);
3. se e quando `heldergaraujo2/MuserverRecriado` for autorizado ao App do GitHub, o
   `recriado/` vira repositorio proprio com `git subtree split -P recriado`,
   levando esta historia junto — sem perder commit nenhum.

## Layout

```
docs/       CURRENT_STATE, NEXT_TASK, DECISIONS, ENVIRONMENT, CHANGELOG
include/    mu2/mu2.h          src/  wire.c mud2.c mu2ctl.c   (R-3+)
tests/      unit.c e2e.sh golden.sh interop.sh conform.c fuzz.c net.sh make_parse.sh
corpus/     corpus deterministico do harness de fuzz (sem libFuzzer neste host)
bench/      bench.c com criterios de validade de ambiente
reports/    .tsv + .md (ver reports/README.md para a regra de extensao)
scripts/    run_all.sh (R-8) verify-backup.sh (R-0, ja ativo)
backup/     mu2-v2.bundle + MANIFEST.md (copia independente)
```

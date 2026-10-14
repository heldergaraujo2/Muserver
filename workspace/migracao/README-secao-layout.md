## Layout

```
docs/       CONTINUITY (índice) CURRENT_STATE NEXT_TASK DECISIONS ROADMAP ENVIRONMENT CHANGELOG
            ADMIN_CONSOLE (desenho do console)  MIGRACAO-MUSERVERRECRIADO-2026-10-12
include/    mu2/mu2.h  mu2/proto.h
src/        wire.c (codec)  mud2.c (serviço)  mu2ctl.c (métricas)
tools/      sondas (pe/data/cfg/att/mb/lua/interop/malform), CLI do codec, fuzzer, console
tests/      unit.c  netclient.c  *.sh (unit, net, pe, data, cfg, conform, golden, fuzz,
            seguranca, admin, lua, interop, bench, ref_check, gate_state)  golden/quadros.tsv
reports/    evidência publicada: *.tsv (dados) e *.md (análise) — regra em reports/README.md
scripts/    verify-backup.sh
workspace/  evidência do monorepo de origem: backups/ (bundle + MANIFEST), changes/ (Lua),
            reports/ (auditorias e recuperação), tools/ e tests/ da fase de auditoria
out/        build e saídas de execução (ignorado pelo git)
```

Existem e rodam: `unit`, `make-sintaxe`, `net`, `net-matrix`, `pe`, `data`, `cfg`, `conform`,
`matriz`, `bench`, `golden`, `fuzz`, `seguranca`, `admin`, `lua`, `*-selftest`, `gate` (portão) e
`gate-selftest` (teste do portão) — 22 etapas, mesa de estados em `out/gate.tsv`. Neste repositório
publicado, `pe`, `data`, `cfg`, `lua` e `ref-intacta` saem **BLOCKED** (`MU_REF_DATA` ausente: a
referência não viaja) e `interop` camada 3 sai BLOCKED (sem binário original em execução).

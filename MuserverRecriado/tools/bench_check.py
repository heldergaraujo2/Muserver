#!/usr/bin/env python3
"""bench_check.py — validador dos CRITÉRIOS DE VALIDADE da baseline exploratória (fase R-7).

Existe separado do bench.sh de propósito: quem mede não pode ser quem julga se a medição vale.
Os critérios são declarados antes de rodar (reps, aquecimento descartado, drift máximo) e este
validador os cobra sobre o TSV produzido. Sem ele, "drift de 300% num host de 2 vCPUs" e
"throughput estável" chegam ao relatório com a mesma cara.

Saída: linhas `chave=valor` + uma linha `# bench_check=...`. Códigos de saída:
  0 = critérios satisfeitos (número publicável como baseline exploratória)
  1 = drift acima do declarado  => BLOCKED por ambiente, NÃO é falha do serviço
  2 = arquivo/schema inválido   => erro de infraestrutura
  3 = perda de quadros ou percentis incoerentes => falha real
Nenhum número deste roteiro é critério de aceitação: não existe requisito de desempenho do dono.
"""
from __future__ import annotations

import argparse
import sys

COLS = ("cenario", "repeticao", "enviados", "recebidos", "ms",
        "quadros_por_s", "bytes_por_s", "resultado", "p50_us", "p95_us", "p99_us")


def num(txt: str) -> float:
    return float(txt)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv")
    ap.add_argument("--reps", type=int, required=True)
    ap.add_argument("--warmup", type=int, required=True)
    ap.add_argument("--drift-max", type=float, required=True)
    ap.add_argument("--cenario-drift", default="B1")
    ap.add_argument("--ignorar", default="",
                    help="prefixos de cenário excluídos da checagem de perda, separados por vírgula: cenários que medem um LIMITE perdem quadros de propósito")
    a = ap.parse_args()

    problemas: list[str] = []
    try:
        with open(a.tsv, encoding="utf-8") as fh:
            linhas = [ln.rstrip("\n") for ln in fh if ln.strip()]
    except OSError as exc:
        print(f"# bench_check=0 problemas=1 exit=2 motivo=leitura:{exc}")
        return 2

    if not linhas:
        print("# bench_check=0 problemas=1 exit=2 motivo=tsv_vazio")
        return 2
    cab = tuple(linhas[0].split("\t"))
    if cab != COLS:
        print(f"# bench_check=0 problemas=1 exit=2 motivo=schema_obtido={'|'.join(cab)}")
        return 2

    linhas = linhas[1:]
    if a.warmup < 0 or a.reps <= a.warmup:
        print(f"# bench_check=0 problemas=1 exit=2 motivo=reps_ou_aquecimento_invalido "
              f"reps={a.reps} warmup={a.warmup}")
        return 2

    ignorados = tuple(x for x in a.ignorar.split(",") if x)
    perdas = 0
    pulados = 0
    medidos: list[float] = []          # duração das repetições do cenário de drift, sem aquecimento
    n_cenario = 0
    p50 = p95 = p99 = None
    for ln in linhas:
        f = dict(zip(COLS, ln.split("\t")))
        n_cenario += 1 if f["cenario"] == a.cenario_drift else 0
        try:
            enviados = int(f["enviados"])
            recebidos = int(f["recebidos"])
        except ValueError:
            print(f"# bench_check=0 problemas=1 exit=2 motivo=campos_numericos_invalidos linha={ln}")
            return 2
        if f["cenario"].startswith(ignorados):
            pulados += 1     # cenário de limite: a perda é o resultado, não um defeito
        elif recebidos != enviados:
            perdas += 1
            problemas.append(f"perda:{f['cenario']}:rep{f['repeticao']}:"
                             f"{recebidos}/{enviados}")
        if f["cenario"] == a.cenario_drift and int(f["repeticao"]) > a.warmup:
            medidos.append(num(f["ms"]))
        if f["cenario"] == "B3":
            p50, p95, p99 = num(f["p50_us"]), num(f["p95_us"]), num(f["p99_us"])

    if n_cenario < a.reps:
        problemas.append(f"repeticoes_insuficientes:{n_cenario}<{a.reps}")
    if not medidos:
        problemas.append("sem_repeticoes_medidas_apos_aquecimento")

    drift = 0.0
    if medidos:
        ordenado = sorted(medidos)
        meio = len(ordenado) // 2
        mediana = (ordenado[meio] if len(ordenado) % 2
                   else (ordenado[meio - 1] + ordenado[meio]) / 2.0)
        if mediana > 0:
            drift = max(abs(v - mediana) / mediana * 100.0 for v in medidos)

    drift_ok = drift <= a.drift_max          # <-- o critério que a falsificação F18 neutraliza
    if not drift_ok:
        problemas.append(f"drift_acima_do_declarado:{drift:.1f}%>{a.drift_max}%")

    if p50 is not None and not (0 < p50 <= p95 <= p99):
        problemas.append(f"percentis_incoerentes:p50={p50}:p95={p95}:p99={p99}")

    print(f"linhas={len(linhas)} repeticoes_{a.cenario_drift}={n_cenario} "
          f"aquecimento_descartado={a.warmup} mediana_ms={mediana if medidos else 0:.1f} "
          f"drift_pct={drift:.1f} drift_max_pct={a.drift_max} drift_ok={int(drift_ok)} "
          f"perdas={perdas} linhas_de_limite_ignoradas={pulados}")

    # Ordem importa: falha real (3) antes de indisponibilidade ambiental (1). Um bench com perda
    # de quadros E drift alto é falha, não ambiente — classificar como BLOCKED esconderia o defeito.
    falha_real = perdas > 0 or any(p.startswith("percentis_incoerentes") for p in problemas)
    ambiental = (not drift_ok) or any(
        p.startswith(("repeticoes_insuficientes", "sem_repeticoes")) for p in problemas)
    if falha_real:
        rc = 3
    elif ambiental:
        rc = 1
    else:
        rc = 0
    for p in problemas:
        print(f"problema={p}")
    print(f"# bench_check={len(linhas)} problemas={len(problemas)} exit={rc}")
    return rc


if __name__ == "__main__":
    sys.exit(main())

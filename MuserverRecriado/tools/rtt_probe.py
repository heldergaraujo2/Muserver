#!/usr/bin/env python3
"""rtt_probe.py — latência de ida e volta por quadro, com percentis (fase R-7).

Por que existe: `tests/netclient.c` conta quadros, mas não marca tempo por quadro, então p50/p95/p99
não saíam dele. Medir isso no shell é pior (resolução de milissegundo por processo).

AVISO DE HONESTIDADE, e ele importa: o tempo medido aqui **inclui o custo deste cliente Python**
(interpretador, GIL, chamadas de sistema). É portanto um **limite superior** da latência do serviço,
não a latência do serviço. Serve para detectar regressão entre passadas no mesmo host e na mesma
configuração; não serve para afirmar capacidade de produção.

Medição: N pares pedido/resposta sequenciais numa única conexão, `clock_gettime(CLOCK_MONOTONIC)`.
Saída determinística (sem timestamp de parede, sem caminho absoluto):
  quadros= erros= rtt_min_us= rtt_p50_us= rtt_p95_us= rtt_p99_us= rtt_max_us= rtt_media_us=
Exit: 0 se todos os quadros foram respondidos; 1 caso contrário; 2 erro de uso.
"""
import argparse
import socket
import statistics
import struct
import sys
import time

CODE_ECHO = 0x0002


def quadro(corpo: bytes) -> bytes:
    return struct.pack("<HH", CODE_ECHO, 4 + len(corpo)) + corpo


def percentil(amostras: list, p: float) -> float:
    """Percentil por posição mais próxima (mesmo método em todas as passadas)."""
    if not amostras:
        return 0.0
    ordenado = sorted(amostras)
    k = max(0, min(len(ordenado) - 1, int(round((p / 100.0) * (len(ordenado) - 1)))))
    return float(ordenado[k])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--frames", type=int, default=500)
    ap.add_argument("--body-size", type=int, default=64)
    ap.add_argument("--warmup", type=int, default=20, help="quadros descartados antes de medir")
    ap.add_argument("--timeout-ms", type=int, default=2000)
    a = ap.parse_args()
    if a.frames <= a.warmup:
        print("rtt_probe: --frames tem de ser maior que --warmup", file=sys.stderr)
        return 2

    corpo = b"x" * a.body_size
    pedido = quadro(corpo)
    esperado = 4 + len(corpo)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(a.timeout_ms / 1000.0)
    try:
        s.connect((a.host, a.port))
    except OSError as e:
        print(f"rtt_probe: conexao falhou: {e}", file=sys.stderr)
        return 2

    amostras = []
    erros = 0
    inicio_medido = 0.0
    janela_s = 0.0
    total = a.frames + a.warmup
    for i in range(total):
        t0 = time.clock_gettime(time.CLOCK_MONOTONIC)
        try:
            s.sendall(pedido)
            buf = b""
            while len(buf) < esperado:
                chunk = s.recv(esperado - len(buf))
                if not chunk:
                    raise OSError("fim de conexao inesperado")
                buf += chunk
        except OSError:
            erros += 1
            break
        t1 = time.clock_gettime(time.CLOCK_MONOTONIC)
        dt = (t1 - t0) * 1e6
        if i >= a.warmup:
            if inicio_medido == 0.0:
                inicio_medido = t0
            janela_s = t1 - inicio_medido
        if buf[4:] != corpo:
            erros += 1
            break
        if i >= a.warmup:
            amostras.append(dt)
    s.close()

    print(f"quadros={len(amostras)} erros={erros} warmup_descartados={a.warmup} "
          f"janela_ms={janela_s * 1e3:.1f}")
    print(f"rtt_min_us={min(amostras):.1f} rtt_p50_us={percentil(amostras, 50):.1f} "
          f"rtt_p95_us={percentil(amostras, 95):.1f} rtt_p99_us={percentil(amostras, 99):.1f} "
          f"rtt_max_us={max(amostras):.1f} rtt_media_us={statistics.fmean(amostras):.1f}")
    print("# limite_superior: inclui o custo deste cliente Python; nao e latencia do servico")
    return 0 if erros == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

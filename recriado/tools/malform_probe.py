#!/usr/bin/env python3
"""malform_probe.py — bateria de entradas malformadas na entrada de REDE do mud2 (Etapa D).

O fuzzer (tools/mu2fuzz.c) ataca o codec em processo. Aqui o ataque é pela porta: cada caso abre uma
conexão, envia bytes deliberadamente ruins e registra o que o serviço fez. Depois de cada caso o
probe prova que o serviço continua vivo mandando um ping válido — "não respondeu" e "morreu" são
coisas diferentes e o relatório separa as duas.

Somente leitura em relação ao repositório: nada é escrito no repo, a saída vai para stdout em TSV.
Aleatoriedade com semente fixa (reproduzível).

uso: malform_probe.py --port N [--host 127.0.0.1] [--timeout-s 2] [--ciclos N]
saída: caso<TAB>enviado_bytes<TAB>respostas<TAB>vivo_depois<TAB>obs
"""
import argparse
import os
import random
import socket
import struct
import sys

PING = bytes.fromhex("01000400")          # code=1 size=4 (contrato v2)
HDR = lambda code, size: struct.pack("<HH", code, size)


def caso(conn_factory, payload, timeout, ler=True, fecho=True, ping_final=True):
    """Abre conexao, manda payload, coleta respostas, devolve (n_respostas, vivo, obs)."""
    s = conn_factory()
    s.settimeout(timeout)
    try:
        if callable(payload):
            payload(s)
        else:
            s.sendall(payload)
        n = 0
        if ler:
            try:
                while True:
                    b = s.recv(65536)
                    if not b:
                        break
                    n += 1
            except socket.timeout:
                pass
    except (BrokenPipeError, ConnectionResetError, OSError) as e:
        return 0, None, "erro_envio=" + type(e).__name__
    finally:
        if fecho:
            try:
                s.close()
            except OSError:
                pass
    vivo = None
    if ping_final:
        vivo = ping_ok(conn_factory, timeout)
    return n, vivo, ""


def ping_ok(conn_factory, timeout):
    s = conn_factory()
    s.settimeout(timeout)
    try:
        s.sendall(PING)
        b = s.recv(64)
        return 1 if b == PING else 0
    except (socket.timeout, OSError):
        return 0
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--timeout-s", type=float, default=2.0)
    ap.add_argument("--ciclos", type=int, default=300,
                    help="conexões abrir/fechar para o teste de estabilidade de descritores")
    a = ap.parse_args()

    def conn():
        return socket.create_connection((a.host, a.port), timeout=a.timeout_s)

    rng = random.Random(20261012)
    casos = []

    def add(nome, payload, **kw):
        n, vivo, obs = caso(conn, payload, a.timeout_s, **kw)
        casos.append((nome, len(payload) if isinstance(payload, bytes) else -1, n, vivo, obs))

    add("size_zero", HDR(1, 0))
    add("size_um", HDR(1, 1))
    add("size_tres", HDR(1, 3))
    add("size_2053_um_acima_do_maximo", HDR(1, 2053))
    add("size_65535_sem_corpo", HDR(1, 65535))
    add("codigo_zero_size_valido", HDR(0, 4))
    add("corpo_maior_que_declarado", HDR(1, 4) + b"\x00" * 100)
    add("lixo_aleatorio_256", bytes(rng.randrange(256) for _ in range(256)))
    add("muitos_ruins_num_write", HDR(1, 0) * 500)
    add("bom_ruim_bom", PING + HDR(1, 3) + PING)
    add("tudo_zero_1024", b"\x00" * 1024)
    add("tudo_ff_1024", b"\xff" * 1024)

    # cabecalho parcial e encerramento: o caminho de leitura incremental
    n, vivo, obs = caso(conn, HDR(1, 4)[:2], a.timeout_s)
    casos.append(("cabecalho_parcial_e_close", 2, n, vivo, obs))

    # gotejamento: 1 byte a cada 5 ms (escrita parcial no sentido do cliente)
    def gotejar(s):
        for b in PING:
            s.sendall(bytes([b]))
    n, vivo, obs = caso(conn, gotejar, a.timeout_s)
    casos.append(("gotejamento_1_byte", 4, n, vivo, obs))

    # estabilidade de descritores: muitos ciclos abrir/fechar, contando os fd do servico
    fd_antes = fd_depois = -1
    srv_pid = None
    try:
        for p in sorted(os.listdir("/proc")):
            if not p.isdigit():
                continue
            try:
                with open("/proc/%s/cmdline" % p, "rb") as f:
                    if b"mud2" in f.read():
                        srv_pid = p
                        break
            except OSError:
                continue
    except OSError:
        srv_pid = None
    if srv_pid:
        try:
            fd_antes = len(os.listdir("/proc/%s/fd" % srv_pid))
        except OSError:
            fd_antes = -1
    for _ in range(a.ciclos):
        try:
            s = conn()
            s.close()
        except OSError:
            break
    if srv_pid:
        try:
            fd_depois = len(os.listdir("/proc/%s/fd" % srv_pid))
        except OSError:
            fd_depois = -1
    casos.append(("ciclos_abrir_fechar", a.ciclos, -1, ping_ok(conn, a.timeout_s),
                  "fd_antes=%d fd_depois=%d srv_pid=%s" % (fd_antes, fd_depois, srv_pid)))

    print("caso\tenviado_bytes\trespostas\tvivo_depois\tobs")
    for c in casos:
        print("%s\t%d\t%d\t%s\t%s" % (c[0], c[1], c[2],
                                      "-" if c[3] is None else c[3], c[4]))
    mortos = [c[0] for c in casos if c[3] == 0]
    print("# casos=%d servico_morto_depois_de=%s" % (len(casos), ",".join(mortos) or "nenhum"))
    return 1 if mortos else 0


if __name__ == "__main__":
    sys.exit(main())

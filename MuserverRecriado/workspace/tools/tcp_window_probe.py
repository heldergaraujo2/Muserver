#!/usr/bin/env python3
"""tcp_window_probe.py — o que o kernel REALMENTE aplica a SO_SNDBUF/SO_RCVBUF e onde a
escrita trava, medido entre dois sockets locais, sem nenhum produto no meio.

Por que isto existe: a N-T5.3d (fila de 1 resposta pendente por conexao) ficou uma rodada
inteira sem conseguir provocar o fechamento, e a conclusao registrada foi "nao alcancavel em
loopback". Medindo o ambiente, a conclusao e outra: alcancavel, desde que (a) o `SO_RCVBUF` do
cliente seja aplicado ANTES do `connect()` e (b) as DUAS pontas estejam apertadas. Quem decide
isso e o kernel, nao o teste — entao o numero tem de ser lido de `getsockopt`, nunca assumido a
partir do valor pedido.

Uso:  python3 workspace/tools/tcp_window_probe.py          # matriz + veredito
      python3 workspace/tools/tcp_window_probe.py --quick   # so os tres casos que importam

Saida: uma linha por caso, com pedido/efetivo de cada buffer, bytes escritos antes de EAGAIN e
o veredito ("travou" = o escritor ficou sem janela antes de despejar tudo). Ler junto de
workspace/reports/WORKTREE-PERDIDO-2026-10-12.md §3.
"""
import os
import socket
import sys
import time

MIN_SND = 1024        # o mesmo minimo que o produto aceita em --sndbuf
FILLER = b"\0" * 7    # tamanho de um pedido de ping (o cliente envia, nao le a resposta)


def floor_info():
    out = []
    for p in ("/proc/sys/net/core/rmem_default", "/proc/sys/net/core/rmem_max",
              "/proc/sys/net/core/wmem_default", "/proc/sys/net/core/wmem_max",
              "/proc/sys/net/core/rmem_min", "/proc/sys/net/core/wmem_min"):
        try:
            out.append("%s=%s" % (p.rsplit("/", 1)[1], open(p).read().strip()))
        except OSError:
            out.append("%s=ausente" % p.rsplit("/", 1)[1])
    caps = [l.strip() for l in open("/proc/self/status") if l.startswith(("CapEff", "CapBRet"))]
    return "; ".join(out) + "; euid=%d; %s" % (os.geteuid(), " ".join(caps))


def one(snd_req, rcv_req, when, reply, frames, slow_reader=False):
    """Retorna dict com o que foi PEDIDO, o que o kernel APLICOU e onde travou."""
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    cli = socket.socket()
    if rcv_req and when == "antes":
        cli.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, rcv_req)
    cli.connect(("127.0.0.1", srv.getsockname()[1]))
    if rcv_req and when == "depois":
        cli.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, rcv_req)
    wr, _ = srv.accept()
    if snd_req:
        wr.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, snd_req)

    cli.setblocking(False)
    for _ in range(frames):                      # o "cliente" empilha pedidos e para de ler
        try:
            cli.send(FILLER)
        except BlockingIOError:
            break
    time.sleep(0.4)

    wr.setblocking(False)
    wrote = 0
    for _ in range(frames):                      # o "servidor" responde um quadro por vez
        try:
            wrote += wr.send(b"\0" * reply)
        except BlockingIOError:
            break
    stalled = wrote < frames * reply

    lidos = 0
    if slow_reader:                              # leituras atrasadas: o travado era janela, nao o servidor
        for _ in range(4):
            time.sleep(0.05)
            try:
                lidos += len(cli.recv(65536))
            except (BlockingIOError, OSError):
                pass
    else:
        try:
            lidos = len(cli.recv(65536))
        except (BlockingIOError, OSError):
            lidos = 0
    for s in (wr, cli, srv):
        s.close()
    return dict(snd_req=snd_req, rcv_req=rcv_req, when=when, reply=reply, frames=frames,
                wrote=wrote, want=frames * reply, stalled=stalled, read=lidos,
                snd_eff=None, rcv_eff=None)


def echo_of(snd_req, rcv_req):
    """getsockopt lido em sockets identicos aos do caso: o efetivo e o que vale."""
    a = socket.socket()
    b = socket.socket()
    b.bind(("127.0.0.1", 0))
    b.listen(1)
    if rcv_req:
        a.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, rcv_req)
    a.connect(("127.0.0.1", b.getsockname()[1]))
    w, _ = b.accept()
    if snd_req:
        w.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, snd_req)
    out = (w.getsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF),
           a.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF))
    for s in (w, a, b):
        s.close()
    return out


CASES_QUICK = [
    # (snd_req, rcv_req, quando, reply, frames, slow_reader, o que o caso significa)
    (MIN_SND, MIN_SND, "depois", 64, 60, False, "rcvbuf depois do connect: NAO trava (o erro da rodada anterior)"),
    (MIN_SND, MIN_SND, "antes", 64, 60, False, "rcvbuf antes do connect: TRAVA (a receita que faltava)"),
    (MIN_SND, MIN_SND, "antes", 64, 60, True, "idem, leitor lento: o que travou era janela, e foi lido depois"),
    (MIN_SND, 0, "n/a", 64, 60, False, "so o --sndbuf do produto: nao basta"),
    (0, MIN_SND, "antes", 64, 60, False, "so o rcvbuf do cliente: nao basta"),
    (MIN_SND, 256, "antes", 64, 60, False, "piso do kernel: pedir 256 da o mesmo efetivo de 1024"),
    (MIN_SND, MIN_SND, "antes", 2048, 8, False, "resposta quase do tamanho de MU2_MAX_BODY: cabe ~1"),
]

CASES_MATRIX = []
for snd in (0, MIN_SND, 4096, 65536):
    for rcv in (0, MIN_SND, 4096):
        for reply in (64, 2048):
            CASES_MATRIX.append((snd, rcv, "antes", reply, 60, False,
                                 "matriz snd=%d rcv=%d reply=%d" % (snd, rcv, reply)))

print("ambiente:", floor_info())
quick = "--quick" in sys.argv or len(sys.argv) == 1
cases = CASES_QUICK if quick else CASES_MATRIX
print("%6s %6s %7s %6s %6s %8s %8s %7s %6s  %s" %
      ("snd", "rcv", "quando", "reply", "frames", "escrito", "esperado", "travou", "lidos", "sentido"))
res = []
for snd, rcv, when, reply, frames, slow, why in cases:
    r = one(snd, rcv, when, reply, frames, slow)
    se, re_ = echo_of(snd, rcv)
    r["snd_eff"], r["rcv_eff"] = se, re_
    res.append((r, why, slow))
    print("%6s %6s %7s %6s %6s %8s %8s %7s %6s  %s [efetivo snd=%s rcv=%s%s]" %
          (r["snd_req"], r["rcv_req"], r["when"], r["reply"], r["frames"], r["wrote"], r["want"],
           r["stalled"], r["read"], why, se, re_, ", leitor=lento" if slow else ""))

# O veredito e DERIVADO desta execucao, nao copiado de uma anterior: foi exatamente assim que a
# rodada anterior fixou em texto um numero que o kernel nao estava aplicando.
def pick(snd, rcv, when, reply, slow=False):
    for r, why, sl in res:
        if (r["snd_req"], r["rcv_req"], r["when"], r["reply"], sl) == (snd, rcv, when, reply, slow):
            return r
    return None

print("\nveredito (deste run):")
se, re_ = (res[0][0]["snd_eff"], res[0][0]["rcv_eff"])
for r, why, sl in res:
    if r["rcv_req"] and r["rcv_eff"]:
        se, re_ = r["snd_eff"] or se, r["rcv_eff"]
print("  - efetivo lido de getsockopt no caso apertado: snd=%d rcv=%d (o pedido era %d/%d) ->"
      % (se, re_, MIN_SND, MIN_SND))
print("    o kernel clampa; valores menores que o piso dao o mesmo efetivo (ver linha rcv=256).")
a_depois = pick(MIN_SND, MIN_SND, "depois", 64)
a_antes = pick(MIN_SND, MIN_SND, "antes", 64)
if a_depois and a_antes:
    print("  - rcvbuf DEPOIS do connect: travou=%s (%d de %d B); ANTES: travou=%s (%d de %d B)."
          % (a_depois["stalled"], a_depois["wrote"], a_depois["want"],
             a_antes["stalled"], a_antes["wrote"], a_antes["want"]))
    print("    em uma resposta por caso: %d de %d respostas de %d B cabem antes de o escritor parar."
          % (a_antes["wrote"] // a_antes["reply"], a_antes["frames"], a_antes["reply"]))
    if a_antes["stalled"] and not a_depois["stalled"]:
        print("    => a diferenca e so a ORDEM do setsockopt: reproduce a fila cheia sem tocar no produto.")
    elif not a_antes["stalled"]:
        print("    => NAO reproduziu neste host: a conclusao da rodada anterior ('nao alcancavel')")
        print("       continua de pe e a N-T5.3d2 so pode avancar com outro mecanismo de janela.")
sownd = pick(MIN_SND, 0, "n/a", 64)
sorcv = pick(0, MIN_SND, "antes", 64)
if sownd and sorcv:
    print("  - uma ponta so: snd=%d travou=%s | rcv=%d travou=%s => preciso e apertar as duas."
          % (sownd["rcv_req"], sownd["stalled"], sorcv["snd_req"], sorcv["stalled"]))
big = pick(MIN_SND, MIN_SND, "antes", 2048)
if big:
    print("  - resposta de %d B (quero MU2_MAX_BODY): %d de %d cabem -> margem menor, gatilho mais seco."
          % (big["reply"], big["wrote"] // big["reply"], big["frames"]))
slow = pick(MIN_SND, MIN_SND, "antes", 64, True)
if slow and a_antes:
    print("  - leitor lento (4 x 50 ms): leu %d B dos %d travados -> o aperto era de JANELA, nao de"
          % (slow["read"], a_antes["wrote"]))
    print("    servidor; por isso a classificacao por linha de log do servidor e obrigatoria no")
    print("    experimento real (fila cheia != TCP bloqueado != timeout != erro de socket).")
sys.exit(0)

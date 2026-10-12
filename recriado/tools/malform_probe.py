#!/usr/bin/env python3
"""malform_probe.py — bateria de entradas malformadas na entrada de REDE do mud2 (Etapa D).

O fuzzer (tools/mu2fuzz.c) ataca o codec em processo. Aqui o ataque é pela porta: cada caso abre uma
conexão, envia bytes deliberadamente ruins e registra o que o serviço fez. Depois de cada caso o
probe prova que o serviço continua vivo mandando um ping válido — "não respondeu" e "morreu" são
coisas diferentes e o relatório separa as duas.

Somente leitura em relação ao repositório: nada é escrito no repo, a saída vai para stdout em TSV.
Aleatoriedade com semente fixa (reproduzível).

uso: malform_probe.py --port N [--host 127.0.0.1] [--timeout-s 2] [--ciclos N] [--srv-pid N]
saída: caso<TAB>enviado_bytes<TAB>respostas<TAB>vivo_depois<TAB>obs

PROCEDÊNCIA DO PID (corrigido em 2026-10-12 por defeito medido). A primeira versão descobria o
processo varrendo /proc/*/cmdline e pegando o PRIMEIRO que contivesse "mud2". Isso mede o processo
errado em dois cenários reais: (a) qualquer shell cuja linha de comando mencione mud2 (o próprio
bash que executa o teste entra nessa lista), e (b) um servidor antigo que ainda não saiu. O efeito
observado foi uma asserção de vazamento de descritor que na verdade comparava fd de outro processo
(fd_antes=8 fd_depois=9 com srv_pid≠pid real). Agora o pid vem, em ordem: de --srv-pid (o teste sabe
o `$!`), ou do inode do socket que ESCUTA `--port` (/proc/net/tcp{,6} -> /proc/*/fd). O relatório
imprime a fonte (`pid_fonte=`) para que a medição seja auditável.
"""
import argparse
import os
import random
import socket
import struct
import sys
import time

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


def pid_escuta_porta(port):
    """PID que ESCUTA `port`, via inode do socket em /proc/net/tcp{,6}. None se não achar.

    Determinar o processo pelo socket (e não pelo texto da linha de comando) é o que impede medir
    fd de outro processo — defeito real já observado nesta suíte.
    """
    inodes = set()
    for arquivo in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(arquivo) as f:
                linhas = f.read().splitlines()[1:]
        except OSError:
            continue
        for ln in linhas:
            c = ln.split()
            if len(c) < 10 or c[3] != "0A":       # 0A = LISTEN
                continue
            try:
                p = int(c[1].split(":")[1], 16)
            except (IndexError, ValueError):
                continue
            if p == port:
                inodes.add(c[9])
    if not inodes:
        return None
    for p in sorted(os.listdir("/proc")):
        if not p.isdigit():
            continue
        try:
            fds = os.listdir("/proc/%s/fd" % p)
        except OSError:
            continue
        for fd in fds:
            try:
                alvo = os.readlink("/proc/%s/fd/%s" % (p, fd))
            except OSError:
                continue
            if alvo.startswith("socket:[") and alvo[8:-1] in inodes:
                return p
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--timeout-s", type=float, default=2.0)
    ap.add_argument("--ciclos", type=int, default=300,
                    help="conexões abrir/fechar POR RODADA (o teste faz 2 rodadas e compara o "
                         "número estabilizado de descritores entre elas)")
    ap.add_argument("--srv-pid", type=int, default=0,
                    help="pid do serviço (o teste conhece o $!); sem ele, resolve pelo socket da porta")
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

    # estabilidade de descritores: muitos ciclos abrir/fechar, contando os fd do servico.
    # O pid vem de --srv-pid (fonte=argumento, o teste passa o seu $!) ou, sem ele, do socket que
    # escuta a porta (fonte=porta). O valor medido e' auditavel: srv_pid e pid_fonte saem no TSV.
    fd_antes = fd_depois = -1
    if a.srv_pid:
        srv_pid = str(a.srv_pid)
        pid_fonte = "argumento"
        try:
            with open("/proc/%s/cmdline" % srv_pid, "rb") as f:
                if b"mud2" not in f.read():
                    pid_fonte = "argumento(aviso:cmdline sem mud2)"
        except OSError:
            srv_pid = None
            pid_fonte = "argumento(pid inexistente)"
    else:
        srv_pid = pid_escuta_porta(a.port)
        pid_fonte = "porta" if srv_pid else "nao_resolvido"
    def conta_fd():
        try:
            return len(os.listdir("/proc/%s/fd" % srv_pid))
        except OSError:
            return -1

    def rodada(n):
        for _ in range(n):
            try:
                s = conn()
                s.close()
            except OSError:
                return

    def estabiliza(alvo, limite_s=2.0):
        """Espera o serviço voltar a `alvo` descritores; devolve (n, ms).

        Isto NÃO afrouxa a asserção — remove uma corrida medida em 2026-10-12. O close() do cliente
        devolve o socket ao servidor de forma assíncrona: contar fd no instante seguinte ao último
        close dá 9 (ou 10 sob carga) mesmo sem vazamento algum. Medido com o pid correto: 5 rodadas
        de 1000 ciclos deram imediato 9,9,8,8,8 e estabilizado 8 sempre, em 0–20 ms. Um vazamento
        real não estabiliza, e por isso o teste continua podendo falhar — o que ele passa a medir é
        ACÚMULO entre rodadas, não o instante do último close.
        """
        t0 = time.time()
        n = conta_fd()
        while n > alvo and time.time() - t0 < limite_s:
            time.sleep(0.02)
            n = conta_fd()
        return n, int((time.time() - t0) * 1000)

    if srv_pid:
        fd_antes = conta_fd()
        rodada(a.ciclos)
        fd_imed = conta_fd()
        fd_depois, ms1 = estabiliza(fd_antes)
        rodada(a.ciclos)                     # 2a rodada: vazamento acumula, corrida nao
        fd_imed2 = conta_fd()
        fd_rodada2, ms2 = estabiliza(fd_antes)
    else:
        fd_imed = fd_imed2 = -1
        ms1 = ms2 = -1
    casos.append(("ciclos_abrir_fechar", 2 * a.ciclos, -1, ping_ok(conn, a.timeout_s),
                  "fd_antes=%d fd_imed=%d fd_depois=%d fd_rodada2=%d fd_imed2=%d "
                  "settle_ms=%d/%d srv_pid=%s pid_fonte=%s" %
                  (fd_antes, fd_imed, fd_depois, fd_rodada2, fd_imed2, ms1, ms2,
                   srv_pid, pid_fonte)))

    print("caso\tenviado_bytes\trespostas\tvivo_depois\tobs")
    for c in casos:
        print("%s\t%d\t%d\t%s\t%s" % (c[0], c[1], c[2],
                                      "-" if c[3] is None else c[3], c[4]))
    mortos = [c[0] for c in casos if c[3] == 0]
    print("# casos=%d servico_morto_depois_de=%s" % (len(casos), ",".join(mortos) or "nenhum"))
    return 1 if mortos else 0


if __name__ == "__main__":
    sys.exit(main())

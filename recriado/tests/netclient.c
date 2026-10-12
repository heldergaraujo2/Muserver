/* netclient.c — cliente de ensaio para tests/net.sh (fase R-4).
 *
 * Existe como programa proprio porque o experimento de backpressure precisa de controles que um
 * shell nao tem: SO_RCVBUF aplicado ANTES do connect() (depois do handshake nao fecha a janela,
 * e isso ja foi medido), gravacoes parciais, varios quadros numa gravacao so, espera sem ler, e
 * leitura em fatias. Cada knob corresponde a uma coluna da matriz de tests/net.sh.
 *
 * A saida e sempre em linhas chave=valor, para o teste classificar sem interpretar prosa.
 * Codigo de saida: 0 = esperado, 1 = divergencia, 2 = erro de infraestrutura.
 */
#define _GNU_SOURCE 1 /* POLLRDHUP: ver o FIN do par sem consumir os dados pendentes */

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "mu2/mu2.h"
#include "mu2/proto.h"

static void nap_ms(int ms)
{
    struct timespec ts;
    if (ms <= 0)
        return;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    (void)nanosleep(&ts, NULL);
}

static void usage(const char *a0)
{
    fprintf(stderr,
            "uso: %s --port N [--host A] [--profile orig|mur0] [--rcvbuf B] [--sndbuf B]\n"
            "     [--frames N] [--code C] [--body-size B] [--batch K] [--split S] [--gap-ms N]\n"
            "     [--no-read-ms N] [--read-delay-ms N] [--expect N] [--eof-wait-ms N]\n"
            "     [--timeout-ms N] [--abort] [--never-read]\n",
            a0);
}

int main(int argc, char **argv)
{
    const char *host = "127.0.0.1";
    mu2_profile profile = MU2_PROFILE_ORIG;
    int port = 0, rcvbuf = 0, sndbuf = 0, frames = 1, batch = 1, split = 0, gap_ms = 0;
    int no_read_ms = 0, read_delay_ms = 0, expect = -1, eof_wait_ms = 0, timeout_ms = 5000;
    int abortive = 0, never_read = 0;
    unsigned code = MU2_CODE_PING;
    size_t body_size = 0;
    int fd = -1, rc = 2;
    long sent_frames = 0, got_frames = 0, bad_frames = 0, bytes_out = 0, bytes_in = 0;
    int eof_seen = 0;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (strcmp(a, "--abort") == 0) {
            abortive = 1;
            continue;
        }
        if (strcmp(a, "--never-read") == 0) {
            never_read = 1; /* espera o fechamento sem consumir: ler aqui drenaria o socket e o
                             * cenario de fila cheia nunca aconteceria (MSG_PEEK abaixo) */
            continue;
        }
        if (v == NULL) {
            usage(argv[0]);
            return 2;
        }
        if (strcmp(a, "--port") == 0)
            port = atoi(v);
        else if (strcmp(a, "--host") == 0)
            host = v;
        else if (strcmp(a, "--rcvbuf") == 0)
            rcvbuf = atoi(v);
        else if (strcmp(a, "--sndbuf") == 0)
            sndbuf = atoi(v);
        else if (strcmp(a, "--frames") == 0)
            frames = atoi(v);
        else if (strcmp(a, "--code") == 0)
            code = (unsigned)strtoul(v, NULL, 0);
        else if (strcmp(a, "--body-size") == 0)
            body_size = (size_t)strtoul(v, NULL, 10);
        else if (strcmp(a, "--batch") == 0)
            batch = atoi(v);
        else if (strcmp(a, "--split") == 0)
            split = atoi(v);
        else if (strcmp(a, "--gap-ms") == 0)
            gap_ms = atoi(v);
        else if (strcmp(a, "--no-read-ms") == 0)
            no_read_ms = atoi(v);
        else if (strcmp(a, "--read-delay-ms") == 0)
            read_delay_ms = atoi(v);
        else if (strcmp(a, "--expect") == 0)
            expect = atoi(v);
        else if (strcmp(a, "--eof-wait-ms") == 0)
            eof_wait_ms = atoi(v);
        else if (strcmp(a, "--timeout-ms") == 0)
            timeout_ms = atoi(v);
        else if (strcmp(a, "--profile") == 0) {
            if (strcmp(v, "orig") == 0)
                profile = MU2_PROFILE_ORIG;
            else if (strcmp(v, "mur0") == 0)
                profile = MU2_PROFILE_MUR0;
            else {
                usage(argv[0]);
                return 2;
            }
        } else {
            usage(argv[0]);
            return 2;
        }
        i++;
    }
    if (port <= 0 || frames < 0 || body_size > MU2_MAX_BODY || batch < 1) {
        usage(argv[0]);
        return 2;
    }
    if (expect < 0)
        expect = frames; /* padrao: uma resposta por pedido */

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        fprintf(stderr, "netclient: socket: %s\n", strerror(errno));
        return 2;
    }
    /* ANTES do connect: e isso que fecha a janela do outro lado. Depois do handshake o efeito
     * some (medido na D2-05) e o experimento de fila cheia passa a nao acontecer nunca. */
    if (rcvbuf > 0)
        (void)setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof rcvbuf);
    if (sndbuf > 0)
        (void)setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof sndbuf);
    {
        int got = 0;
        socklen_t gl = sizeof got;
        if (rcvbuf > 0 && getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &got, &gl) == 0)
            printf("rcvbuf pedido=%d efetivo=%d\n", rcvbuf, got);
        got = 0;
        gl = sizeof got;
        if (sndbuf > 0 && getsockopt(fd, SOL_SOCKET, SO_SNDBUF, &got, &gl) == 0)
            printf("sndbuf pedido=%d efetivo=%d\n", sndbuf, got);
    }
    {
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof addr);
        addr.sin_family = AF_INET;
        addr.sin_port = htons((uint16_t)port);
        if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
            fprintf(stderr, "netclient: endereco invalido '%s'\n", host);
            goto fim;
        }
        if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
            fprintf(stderr, "netclient: connect %s:%d: %s\n", host, port, strerror(errno));
            goto fim;
        }
    }

    /* ---- fase de escrita ---- */
    {
        uint8_t frame[MU2_MAX_FRAME];
        uint8_t *bodybuf = NULL;
        uint8_t *pend = NULL;
        size_t pend_len = 0, pend_cap = 0;
        int k = 0;

        if (body_size > 0) {
            bodybuf = malloc(body_size);
            if (bodybuf == NULL) {
                rc = 2;
                goto fim_escrita;
            }
        }
        pend_cap = (size_t)batch * MU2_MAX_FRAME;
        pend = malloc(pend_cap);
        if (pend == NULL) {
            rc = 2;
            goto fim_escrita;
        }

        for (int n = 0; n < frames; n++) {
            int r;
            size_t flen;
            if (body_size > 0) {
                for (size_t b = 0; b < body_size; b++)
                    bodybuf[b] = (uint8_t)((n + (int)b) & 0xFF);
            }
            r = mu2_frame_encode(frame, sizeof frame, (uint16_t)code, bodybuf, body_size, profile);
            if (r <= 0) {
                fprintf(stderr, "netclient: encode: %s\n", mu2_errstr(r));
                rc = 2;
                goto fim_escrita;
            }
            flen = (size_t)r;
            if (pend_len + flen > pend_cap) { /* nunca acontece com pend_cap=batch*MAX, mas nao se confia */
                rc = 2;
                goto fim_escrita;
            }
            memcpy(pend + pend_len, frame, flen);
            pend_len += flen;
            k++;
            if (k >= batch || n == frames - 1) {
                size_t off = 0;
                while (off < pend_len) {
                    size_t chunk = pend_len - off;
                    ssize_t w;
                    if (split > 0 && chunk > (size_t)split)
                        chunk = (size_t)split;
                    w = send(fd, pend + off, chunk, MSG_NOSIGNAL);
                    if (w <= 0) {
                        if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR))
                            continue;
                        goto fim_escrita; /* servidor fechou: EOF e informado na fase de leitura */
                    }
                    off += (size_t)w;
                    bytes_out += w;
                    if (split > 0 && gap_ms > 0)
                        nap_ms(gap_ms);
                }
                sent_frames += k;
                pend_len = 0;
                k = 0;
                if (gap_ms > 0 && n != frames - 1)
                    nap_ms(gap_ms);
            }
        }
        rc = 0;
    fim_escrita:
        free(bodybuf);
        free(pend);
    }
    if (rc != 0 && rc != 2)
        rc = 2;
    printf("enviados=%ld bytes_escritos=%ld\n", sent_frames, bytes_out);
    fflush(stdout);

    if (no_read_ms > 0)
        nap_ms(no_read_ms);

    /* ---- fase de leitura ---- */
    if (expect > 0) {
        uint8_t buf[4 * MU2_MAX_FRAME];
        size_t len = 0;
        int elapsed = 0;
        while (got_frames < expect && eof_seen == 0 && elapsed < timeout_ms) {
            struct pollfd pfd;
            ssize_t n;
            int pr;
            if (read_delay_ms > 0)
                nap_ms(read_delay_ms);
            pfd.fd = fd;
            pfd.events = POLLIN;
            pr = poll(&pfd, 1, 100);
            elapsed += 100;
            if (pr <= 0)
                continue;
            n = recv(fd, buf + len, sizeof buf - len, 0);
            if (n == 0) {
                eof_seen = 1;
                break;
            }
            if (n < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
                    continue;
                fprintf(stderr, "netclient: recv: %s\n", strerror(errno));
                eof_seen = 1;
                break;
            }
            len += (size_t)n;
            bytes_in += n;
            for (;;) {
                mu2_frame f;
                const uint8_t *b = NULL;
                int r = mu2_frame_decode(&f, &b, buf, len, profile);
                if (r == MU2_E_INCOMPLETE)
                    break;
                if (r != MU2_OK) {
                    bad_frames++;
                    len = 0;
                    break;
                }
                if (f.code != (uint16_t)code) {
                    bad_frames++;
                } else if (code == MU2_CODE_ECHO) {
                    /* Conferir o conteudo, nao so o comprimento: foi um deslocamento de 4 bytes
                     * no corpo que a primeira subida do servico produziu, e tamanho certo com
                     * corpo errado passaria num teste que olha apenas body_len. */
                    uint8_t tmp[MU2_MAX_BODY];
                    long idx = got_frames;
                    int br = mu2_frame_body(tmp, sizeof tmp, &f, buf, profile);
                    if (br < 0 || f.body_len != body_size) {
                        bad_frames++;
                    } else {
                        for (size_t bi = 0; bi < body_size; bi++) {
                            if (tmp[bi] != (uint8_t)((idx + (long)bi) & 0xFFL)) {
                                bad_frames++;
                                break;
                            }
                        }
                    }
                }
                got_frames++;
                memmove(buf, buf + f.frame_len, len - f.frame_len);
                len -= f.frame_len;
            }
        }
    } else if (eof_wait_ms > 0) {
        int waited = 0;
        while (waited < eof_wait_ms && eof_seen == 0) {
            struct pollfd pfd;
            pfd.fd = fd;
            pfd.events = (short)(POLLIN | POLLRDHUP);
            if (poll(&pfd, 1, never_read ? 20 : 50) > 0) {
                char sink[256];
                ssize_t n;
                /* POLLRDHUP e o unico jeito honesto de ver o FIN do outro lado sem consumir:
                 * recv(MSG_PEEK) com dados pendentes devolve dados, nao 0, e o cenario de fila
                 * cheia desapareceria no exato momento em que fosse observado. */
                if ((pfd.revents & POLLRDHUP) != 0) {
                    eof_seen = 1;
                    break;
                }
                n = recv(fd, sink, never_read ? 1u : sizeof sink, never_read ? MSG_PEEK : 0);
                if (n == 0)
                    eof_seen = 1;
                else if (n > 0 && never_read == 0)
                    bytes_in += n; /* respostas que couberam no buffer antes do fechamento */
            }
            waited += never_read ? 20 : 50;
        }
    }

    printf("recebidos=%ld corrompidos=%ld bytes_lidos=%ld eof=%d\n", got_frames, bad_frames,
           bytes_in, eof_seen);
    if (got_frames == expect && bad_frames == 0) {
        printf("resultado=OK\n");
        rc = 0;
    } else {
        printf("resultado=%s esperado=%d\n", (bad_frames > 0) ? "CORROMPIDO" : "DIVERGENTE", expect);
        rc = 1;
    }
    fflush(stdout);

fim:
    if (fd >= 0) {
        if (abortive) {
            struct linger lg;
            lg.l_onoff = 1;
            lg.l_linger = 0;
            (void)setsockopt(fd, SOL_SOCKET, SO_LINGER, &lg, sizeof lg); /* RST em vez de FIN */
        }
        close(fd);
    }
    return rc;
}

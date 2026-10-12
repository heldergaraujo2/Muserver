/* mu2ctl.c — leitor externo de metricas do mud2 (fase R-4, contrato D2-16).
 *
 * Por que um programa separado: o experimento de backpressure precisa ler o estado do servico
 * de fora, sem compartilhar memoria nem sinal, e o unico caminho honesto para isso e o proprio
 * protocolo. `mu2ctl stats` e portanto tambem um segundo consumidor do codec de mu2 — se o
 * enquadramento estiver torto, ele falha junto, e nao so o teste unitario.
 *
 * Uso: mu2ctl stats --port N [--host ADDR] [--profile orig|mur0] [--timeout-ms N]
 */
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "mu2/mu2.h"
#include "mu2/proto.h"

static void usage(const char *a0)
{
    fprintf(stderr,
            "uso: %s stats --port N [--host ADDR] [--profile orig|mur0] [--timeout-ms N]\n"
            "  imprime a linha STATS devolvida pelo mud2 e sai 0; qualquer outra coisa sai != 0.\n",
            a0);
}

int main(int argc, char **argv)
{
    const char *host = "127.0.0.1";
    const char *cmd = NULL;
    mu2_profile profile = MU2_PROFILE_ORIG;
    int port = 0, timeout_ms = 3000;
    int fd = -1, rc = 1, r;
    uint8_t out[MU2_MAX_FRAME], in[MU2_MAX_FRAME], body[MU2_MAX_BODY];
    struct sockaddr_in addr;
    struct pollfd pfd;

    if (argc >= 2 && strcmp(argv[1], "stats") == 0)
        cmd = "stats";
    if (cmd == NULL) {
        usage(argv[0]);
        return 2;
    }
    for (int i = 2; i < argc; i++) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (v == NULL) {
            usage(argv[0]);
            return 2;
        }
        if (strcmp(a, "--port") == 0)
            port = atoi(v);
        else if (strcmp(a, "--host") == 0)
            host = v;
        else if (strcmp(a, "--timeout-ms") == 0)
            timeout_ms = atoi(v);
        else if (strcmp(a, "--profile") == 0) {
            if (strcmp(v, "orig") == 0)
                profile = MU2_PROFILE_ORIG;
            else if (strcmp(v, "mur0") == 0)
                profile = MU2_PROFILE_MUR0;
            else {
                fprintf(stderr, "mu2ctl: perfil desconhecido '%s'\n", v);
                return 2;
            }
        } else {
            usage(argv[0]);
            return 2;
        }
        i++;
    }
    if (port <= 0 || port > 65535) {
        fprintf(stderr, "mu2ctl: --port obrigatorio e dentro de 1..65535\n");
        return 2;
    }

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        fprintf(stderr, "mu2ctl: socket: %s\n", strerror(errno));
        return 1;
    }
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
        fprintf(stderr, "mu2ctl: endereco invalido '%s'\n", host);
        goto fim;
    }
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        fprintf(stderr, "mu2ctl: connect %s:%d: %s\n", host, port, strerror(errno));
        goto fim;
    }

    r = mu2_frame_encode(out, sizeof out, MU2_CODE_STATS, NULL, 0, profile);
    if (r <= 0) {
        fprintf(stderr, "mu2ctl: encode: %s\n", mu2_errstr(r));
        goto fim;
    }
    {
        size_t off = 0;
        while (off < (size_t)r) {
            ssize_t n = send(fd, out + off, (size_t)r - off, MSG_NOSIGNAL);
            if (n <= 0) {
                fprintf(stderr, "mu2ctl: send: %s\n", (n < 0) ? strerror(errno) : "conexao fechada");
                goto fim;
            }
            off += (size_t)n;
        }
    }

    pfd.fd = fd;
    pfd.events = POLLIN;
    r = poll(&pfd, 1, timeout_ms);
    if (r <= 0) {
        fprintf(stderr, "mu2ctl: %s esperando resposta\n", (r == 0) ? "tempo esgotado" : "poll");
        goto fim;
    }
    {
        ssize_t n = recv(fd, in, sizeof in, 0);
        mu2_frame f;
        const uint8_t *b = NULL;
        if (n <= 0) {
            fprintf(stderr, "mu2ctl: recv: %s\n", (n < 0) ? strerror(errno) : "conexao fechada");
            goto fim;
        }
        r = mu2_frame_decode(&f, &b, in, (size_t)n, profile);
        if (r != MU2_OK) {
            fprintf(stderr, "mu2ctl: decode: %s\n", mu2_errstr(r));
            goto fim;
        }
        if (f.code != MU2_CODE_STATS) {
            fprintf(stderr, "mu2ctl: opcode %u inesperado (esperava %u)\n", (unsigned)f.code,
                    MU2_CODE_STATS);
            goto fim;
        }
        (void)b;
        r = mu2_frame_body(body, sizeof body, &f, in, profile); /* in = inicio do quadro */
        if (r < 0) {
            fprintf(stderr, "mu2ctl: corpo: %s\n", mu2_errstr(r));
            goto fim;
        }
        body[f.body_len] = '\0';
        /* O perfil nao e detectavel no stream (a transformacao toca so o corpo, D2-11/D2-12),
         * entao um --profile errado decodifica "com sucesso" e devolve lixo. Conferir o prefixo
         * e o que transforma lixo em erro claro, em vez de saida bonita e errada. */
        if (strncmp((char *)body, MU2_STATS_PREFIX, sizeof MU2_STATS_PREFIX - 1) != 0) {
            fprintf(stderr,
                    "mu2ctl: corpo nao comeca com '%s' (perfil errado? servidor=%s pedido=%s)\n",
                    MU2_STATS_PREFIX, "orig/mur0", mu2_profile_name(profile));
            goto fim;
        }
        printf("%s\n", (char *)body);
        rc = 0;
    }

fim:
    if (fd >= 0)
        close(fd);
    return rc;
}

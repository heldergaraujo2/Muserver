/* mud2.c — servico minimo de rede do v2 (fase R-4).
 *
 * Escopo: um laco poll() que aceita conexoes, alimenta o decodificador de quadros de mu2
 * com leituras parciais e quadros concatenados, e responde com uma fila de UMA vaga por
 * conexao (D2-05). Nao e o MU Server: e o banco de ensaio do contrato de enquadramento.
 *
 * Contratos que este arquivo implementa, e onde estao escritos:
 *   D2-05  fila de 1 vaga; fechamento com log proprio e contador `queue_full_closes`;
 *   D2-14  poll() pede POLLOUT sempre que ha resposta pendente (out_len != out_off);
 *          EAGAIN mantem a resposta na vaga; fechamento so quando um pedido NOVO a encontra
 *          ocupada;
 *   D2-16  opcodes do servico (PING/ECHO/STATS), motivo de fechamento no log como
 *          `close=<motivo>`, e a linha de `stats` lida de fora por mu2ctl.
 *
 * Nao faz: TLS, autenticacao, persistencia, nem qualquer compatibilidade com o cliente
 * original (isso e pergunta da R-6, a responder do binario).
 */
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "mu2/mu2.h"
#include "mu2/proto.h"

#define MUD2_IN_SLOTS 8192u          /* teto de --max-clients: limita memoria do proprio teste */
#define MUD2_POLL_MS 25              /* granularidade do timeout ocioso e do sinal */
#define MUD2_LOG_LINE 512u

typedef struct {
    int fd;
    unsigned long id;
    uint8_t in[2 * MU2_MAX_FRAME];   /* leituras parciais + quadros concatenados */
    size_t in_len;
    uint8_t out[MU2_MAX_FRAME];      /* a vaga unica de resposta (D2-05) */
    size_t out_len;
    size_t out_off;
    int64_t last_ms;
    int in_use;
} conn;

typedef struct {
    unsigned long conns;            /* aceitacoes totais */
    unsigned long frames;           /* quadros decodificados e despachados */
    unsigned long replies;          /* respostas entregues a vaga */
    unsigned long rejects;          /* quadros invalidos + recusas de capacidade */
    unsigned long queue_full;       /* D2-05/D2-14: pedido novo com a vaga ocupada */
    unsigned long unknown;          /* opcode fora do conjunto conhecido */
} counters;

static struct {
    const char *host;
    int port;
    unsigned max_clients;
    int sndbuf;         /* 0 = nao mexer; senao SO_SNDBUF pedido (minimo 1024) */
    int idle_ms;        /* 0 = desligado */
    mu2_profile profile;
    int log_level;      /* 0=ERRO 1=AVISO 2=INFO 3=DEBUG */
    const char *log_file;
} opt = {"127.0.0.1", 0, 64u, 0, 0, MU2_PROFILE_ORIG, 2, NULL};

static FILE *log_fp; /* nao pode se chamar `logf`: colide com a builtin do gcc e -Wshadow vira erro */
static conn *slots;
static counters C;
static volatile sig_atomic_t stopping;
static int64_t t0_ms;
static unsigned long next_id = 1;

static int64_t now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void logmsg(int level, const char *tag, unsigned long cid, const char *fmt, ...)
{
    va_list ap;
    if (level > opt.log_level || log_fp == NULL)
        return;
    fprintf(log_fp, "[+%06lld] %-5s ", (long long)(now_ms() - t0_ms), tag);
    if (cid != 0)
        fprintf(log_fp, "conn=%lu ", cid);
    va_start(ap, fmt);
    vfprintf(log_fp, fmt, ap);
    va_end(ap);
    fputc('\n', log_fp);
    fflush(log_fp);
}

static void on_signal(int sig)
{
    (void)sig;
    stopping = 1; /* o laco percebe no proximo retorno de poll(): nada de I/O aqui dentro */
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "uso: %s [--listen ADDR] [--port N] [--max-clients N] [--sndbuf BYTES]\n"
            "        [--idle-ms N] [--profile orig|mur0] [--log-level 0..3] [--log-file ARQ]\n"
            "  --port 0 escolhe porta efêmera e a imprime na linha `listen` do log.\n",
            argv0);
}

static int parse_args(int argc, char **argv)
{
    int i;
    for (i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (strcmp(a, "--help") == 0) {
            usage(argv[0]);
            return -1;
        }
        if (v == NULL) {
            fprintf(stderr, "mud2: %s exige um valor\n", a);
            return -1;
        }
        if (strcmp(a, "--listen") == 0)
            opt.host = v;
        else if (strcmp(a, "--port") == 0)
            opt.port = atoi(v);
        else if (strcmp(a, "--max-clients") == 0)
            opt.max_clients = (unsigned)strtoul(v, NULL, 10);
        else if (strcmp(a, "--sndbuf") == 0)
            opt.sndbuf = atoi(v);
        else if (strcmp(a, "--idle-ms") == 0)
            opt.idle_ms = atoi(v);
        else if (strcmp(a, "--profile") == 0) {
            if (strcmp(v, "orig") == 0)
                opt.profile = MU2_PROFILE_ORIG;
            else if (strcmp(v, "mur0") == 0)
                opt.profile = MU2_PROFILE_MUR0;
            else {
                fprintf(stderr, "mud2: perfil desconhecido '%s'\n", v);
                return -1;
            }
        } else if (strcmp(a, "--log-level") == 0)
            opt.log_level = atoi(v);
        else if (strcmp(a, "--log-file") == 0)
            opt.log_file = v;
        else {
            fprintf(stderr, "mud2: opcao desconhecida '%s'\n", a);
            return -1;
        }
        i++;
    }
    if (opt.max_clients == 0u || opt.max_clients > MUD2_IN_SLOTS) {
        fprintf(stderr, "mud2: --max-clients fora de 1..%u\n", MUD2_IN_SLOTS);
        return -1;
    }
    if (opt.sndbuf != 0 && opt.sndbuf < 1024) {
        fprintf(stderr, "mud2: --sndbuf menor que 1024 e recusado (o kernel clamparia e o "
                        "experimento de backpressure perderia o sentido)\n");
        return -1;
    }
    if (opt.port < 0 || opt.port > 65535) {
        fprintf(stderr, "mud2: --port fora de 0..65535\n");
        return -1;
    }
    return 0;
}

static unsigned active_count(void)
{
    unsigned n = 0, i;
    for (i = 0; i < opt.max_clients; i++)
        if (slots[i].in_use)
            n++;
    return n;
}

static int stats_line(char *dst, size_t dst_len)
{
    int n = snprintf(dst, dst_len,
                     "STATS registros=%u usados=%u conns=%lu frames=%lu rejects=%lu "
                     "queue_full_closes=%lu uptime_ms=%lld slotsz=%u maxbody=%u",
                     opt.max_clients, active_count(), C.conns, C.frames, C.rejects, C.queue_full,
                     (long long)(now_ms() - t0_ms), (unsigned)MU2_MAX_FRAME,
                     (unsigned)MU2_MAX_BODY);
    if (n < 0 || (size_t)n >= dst_len)
        return -1;
    return n;
}

static void close_conn(conn *c, const char *reason)
{
    if (c->in_use == 0)
        return;
    logmsg(2, "INFO", c->id, "close=%s in=%zu out=%zu/%zu", reason, c->in_len, c->out_off,
           c->out_len);
    close(c->fd);
    c->fd = -1;
    c->in_use = 0;
    c->in_len = 0;
    c->out_len = 0;
    c->out_off = 0;
}

/* Esvazia a vaga ate onde o socket aceitar. EAGAIN NAO e erro: a resposta continua na vaga e
 * o POLLOUT ja registrado retoma (D2-14). */
static void drain(conn *c)
{
    while (c->out_off < c->out_len) {
        ssize_t n = send(c->fd, c->out + c->out_off, c->out_len - c->out_off, MSG_NOSIGNAL);
        if (n > 0) {
            c->out_off += (size_t)n;
            continue;
        }
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
            /* Diagnostico de backpressure: sem isto, "a vaga ficou ocupada" e indistinguivel de
             * "o socket travou", e foi essa ambiguidade que a R-4 teve de resolver na pratica. */
            logmsg(3, "DEBUG", c->id, "drain bloqueou escrito=%zu pendente=%zu errno=%d", c->out_off,
                   c->out_len - c->out_off, errno);
            return;
        }
        C.rejects++;
        close_conn(c, "write_error");
        return;
    }
    c->out_len = 0;
    c->out_off = 0;
}

/* Fila de UMA vaga (D2-05). Pedido novo com a vaga ocupada => fechamento com log proprio e
 * contador dedicado; nunca se sobreescreve resposta pendente em silencio. */
static void queue_reply(conn *c, const uint8_t *frame, size_t len)
{
    if (c->out_len != c->out_off) { /* vaga ocupada */
        C.queue_full++;
        C.rejects++;
        /* O token `close=` aparece UMA vez por fechamento, emitido por close_conn(). Se esta
         * linha tambem o carregasse, um unico evento viraria duas linhas e toda classificacao
         * por log contaria o dobro — foi o que a primeira subida mostrou (2 linhas, contador 1). */
        logmsg(1, "WARN", c->id, "queue_full vaga-ocupada pending=%zu causa=resposta-anterior-pendente",
               c->out_len - c->out_off);
        close_conn(c, "queue_full");
        return;
    }
    memcpy(c->out, frame, len);
    c->out_len = len;
    c->out_off = 0;
    C.replies++;
    drain(c); /* tentativa imediata; se travar, o POLLOUT retoma (D2-14) */
}

/* `frame` e o INICIO do quadro no buffer, nao o corpo: mu2_frame_body soma MU2_HEADER_SIZE
 * internamente. Passar o ponteiro do corpo desloca tudo em 4 bytes — foi exatamente o defeito
 * que a primeira subida deste servico mostrou (linha STATS saindo como "S registros=..."). */
static void handle_frame(conn *c, const mu2_frame *f, const uint8_t *frame)
{
    uint8_t tmp[MU2_MAX_FRAME];
    uint8_t bodybuf[MU2_MAX_BODY];
    uint16_t reply_code;
    const uint8_t *reply_body = NULL;
    size_t reply_len = 0;
    int r;

    C.frames++;

    if (f->body_len > 0) {
        r = mu2_frame_body(bodybuf, sizeof bodybuf, f, frame, opt.profile);
        if (r < 0) {
            C.rejects++;
            close_conn(c, "bad_frame");
            return;
        }
    }

    switch (f->code) {
    case MU2_CODE_PING: /* D2-16: responde vazio; serve de sonda de vida */
        reply_code = MU2_CODE_PING;
        break;
    case MU2_CODE_ECHO:
        reply_code = MU2_CODE_ECHO;
        reply_body = bodybuf;
        reply_len = f->body_len;
        break;
    case MU2_CODE_STATS: {
        char line[MUD2_LOG_LINE];
        int n = stats_line(line, sizeof line);
        if (n < 0) {
            C.rejects++;
            close_conn(c, "stats_error");
            return;
        }
        memcpy(bodybuf, line, (size_t)n);
        reply_code = MU2_CODE_STATS;
        reply_body = bodybuf;
        reply_len = (size_t)n;
        break;
    }
    default:
        /* Opcode desconhecido e descartado, nao punido: fechar por lixo permitiria que um
         * cliente derrubasse a propria conexao de proposito e sujaria a classificacao de
         * causa nos testes de rede. */
        C.unknown++;
        logmsg(3, "DEBUG", c->id, "opcode=%u descartado body=%zu", (unsigned)f->code,
               f->body_len);
        return;
    }

    r = mu2_frame_encode(tmp, sizeof tmp, reply_code, reply_body, reply_len, opt.profile);
    if (r <= 0) {
        C.rejects++;
        close_conn(c, "encode_error");
        return;
    }
    queue_reply(c, tmp, (size_t)r);
}

/* Consome TODOS os quadros completos do buffer. Um quadro por leitura e exatamente o defeito
 * que a falsificacao F5 procura: com `break` aqui, o segundo quadro de um write concatenado
 * espera por um recv que nunca vem. */
static void feed(conn *c)
{
    for (;;) {
        mu2_frame f;
        const uint8_t *body = NULL;
        int r = mu2_frame_decode(&f, &body, c->in, c->in_len, opt.profile);
        (void)body; /* o corpo se le a partir de c->in, que e o inicio do quadro */

        if (r == MU2_E_INCOMPLETE) {
            if (f.needed > sizeof c->in - c->in_len && c->in_len > 0) {
                /* Buffer cheio sem quadro completo: lixo de enquadramento, nao quadro grande.
                 * Nao se aumenta MU2_MAX_BODY para acomodar (regra do projeto). */
                C.rejects++;
                close_conn(c, "bad_frame");
                return;
            }
            return;
        }
        if (r != MU2_OK) {
            C.rejects++;
            close_conn(c, "bad_frame");
            return;
        }
        handle_frame(c, &f, c->in);
        if (c->in_use == 0)
            return; /* handle_frame fechou a conexao (fila cheia, erro) */
        memmove(c->in, c->in + f.frame_len, c->in_len - f.frame_len);
        c->in_len -= f.frame_len;
    }
}

static void on_readable(conn *c)
{
    ssize_t n = recv(c->fd, c->in + c->in_len, sizeof c->in - c->in_len, 0);
    if (n == 0) {
        close_conn(c, "client_eof");
        return;
    }
    if (n < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
            return;
        C.rejects++;
        close_conn(c, "socket_error");
        return;
    }
    c->in_len += (size_t)n;
    c->last_ms = now_ms();
    feed(c);
}

static void accept_new(int lfd)
{
    int fd = accept(lfd, NULL, NULL);
    unsigned i;
    conn *c = NULL;

    if (fd < 0)
        return;
    for (i = 0; i < opt.max_clients; i++) {
        if (slots[i].in_use == 0) {
            c = &slots[i];
            break;
        }
    }
    if (c == NULL) {
        C.rejects++;
        logmsg(1, "WARN", 0, "close=max_clients usados=%u", opt.max_clients);
        close(fd);
        return;
    }
    {
        int one = 1;
        int fl = fcntl(fd, F_GETFL, 0);
        if (fl >= 0)
            (void)fcntl(fd, F_SETFL, fl | O_NONBLOCK);
        (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    }
    {
        int sb = 0;
        socklen_t sl = sizeof sb;
        if (getsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sb, &sl) == 0)
            logmsg(3, "DEBUG", next_id, "sndbuf_do_socket_aceito=%d", sb);
    }
    memset(c, 0, sizeof *c);
    c->fd = fd;
    c->in_use = 1;
    c->id = next_id++;
    c->last_ms = now_ms();
    C.conns++;
    logmsg(2, "INFO", c->id, "open slot=%u usados=%u", i, active_count());
}

static void enforce_idle(void)
{
    unsigned i;
    int64_t now;
    if (opt.idle_ms <= 0)
        return;
    now = now_ms();
    for (i = 0; i < opt.max_clients; i++)
        if (slots[i].in_use && now - slots[i].last_ms >= opt.idle_ms)
            close_conn(&slots[i], "idle_timeout");
}

int main(int argc, char **argv)
{
    int lfd = -1, one = 1, rc = 0;
    struct sockaddr_in addr;
    socklen_t alen = sizeof addr;
    struct sigaction sa;

    if (parse_args(argc, argv) != 0)
        return 2;

    log_fp = (opt.log_file != NULL) ? fopen(opt.log_file, "w") : stderr;
    if (log_fp == NULL) {
        fprintf(stderr, "mud2: nao consegui abrir --log-file '%s'\n", opt.log_file);
        return 2;
    }
    slots = calloc(opt.max_clients, sizeof *slots);
    if (slots == NULL) {
        fprintf(stderr, "mud2: sem memoria para %u vagas\n", opt.max_clients);
        return 2;
    }
    t0_ms = now_ms();

    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);

    lfd = socket(AF_INET, SOCK_STREAM, 0);
    if (lfd < 0) {
        logmsg(0, "ERRO", 0, "socket: %s", strerror(errno));
        rc = 2;
        goto fim;
    }
    setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (opt.sndbuf != 0) {
        /* Antes do listen: socket aceito herda o valor. Pedir depois nao vale para o
         * experimento de backpressure (mesma razao do SO_RCVBUF no cliente). */
        if (setsockopt(lfd, SOL_SOCKET, SO_SNDBUF, &opt.sndbuf, sizeof opt.sndbuf) != 0)
            logmsg(1, "WARN", 0, "SO_SNDBUF pedido=%d recusado: %s", opt.sndbuf, strerror(errno));
    }
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)opt.port);
    if (inet_pton(AF_INET, opt.host, &addr.sin_addr) != 1) {
        logmsg(0, "ERRO", 0, "endereco invalido '%s'", opt.host);
        rc = 2;
        goto fim;
    }
    if (bind(lfd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        logmsg(0, "ERRO", 0, "bind %s:%d: %s", opt.host, opt.port, strerror(errno));
        rc = 2;
        goto fim;
    }
    if (listen(lfd, 64) != 0) {
        logmsg(0, "ERRO", 0, "listen: %s", strerror(errno));
        rc = 2;
        goto fim;
    }
    if (getsockname(lfd, (struct sockaddr *)&addr, &alen) == 0)
        opt.port = ntohs(addr.sin_port);
    {
        int efetivo = 0;
        socklen_t el = sizeof efetivo;
        if (opt.sndbuf != 0 && getsockopt(lfd, SOL_SOCKET, SO_SNDBUF, &efetivo, &el) == 0)
            logmsg(2, "INFO", 0, "sndbuf pedido=%d efetivo=%d", opt.sndbuf, efetivo);
    }
    logmsg(2, "INFO", 0, "listen addr=%s port=%d profile=%s max_clients=%u sndbuf=%d idle_ms=%d",
           opt.host, opt.port, mu2_profile_name(opt.profile), opt.max_clients, opt.sndbuf,
           opt.idle_ms);
    fflush(log_fp);

    /* Laco principal: poll() sobre o listen + as conexoes vivas. POLLOUT entra no events de
     * toda conexao com resposta pendente (D2-14), sem excecao. As tabelas de poll sao
     * alocadas uma vez: realocar a cada volta seria ruido num laco que existe para medir. */
    {
        struct pollfd *pfds = calloc((size_t)opt.max_clients + 1u, sizeof *pfds);
        conn **map = calloc((size_t)opt.max_clients + 1u, sizeof *map);
        if (pfds == NULL || map == NULL) {
            free(pfds);
            free(map);
            logmsg(0, "ERRO", 0, "sem memoria para as tabelas de poll");
            rc = 2;
            goto fim;
        }
        while (stopping == 0) {
            nfds_t n = 0, i;
            unsigned k;
            int pr;

            pfds[0].fd = lfd;
            pfds[0].events = POLLIN;
            pfds[0].revents = 0;
            map[0] = NULL;
            n = 1;
            for (k = 0; k < opt.max_clients; k++) {
                if (slots[k].in_use == 0)
                    continue;
                pfds[n].fd = slots[k].fd;
                pfds[n].events =
                    (short)(POLLIN | ((slots[k].out_len != slots[k].out_off) ? POLLOUT : 0));
                pfds[n].revents = 0;
                map[n] = &slots[k];
                n++;
            }

            pr = poll(pfds, n, MUD2_POLL_MS);
            if (pr < 0 && errno != EINTR) {
                logmsg(0, "ERRO", 0, "poll: %s", strerror(errno));
                rc = 2;
                break;
            }
            if (pr > 0) {
                if (pfds[0].revents != 0)
                    accept_new(lfd);
                for (i = 1; i < n; i++) {
                    conn *c = map[i];
                    short re = pfds[i].revents;
                    if (c == NULL || c->in_use == 0 || re == 0)
                        continue;
                    if ((re & (POLLERR | POLLNVAL)) != 0) {
                        C.rejects++;
                        close_conn(c, "socket_error");
                        continue;
                    }
                    if ((re & POLLIN) != 0)
                        on_readable(c);
                    if (c->in_use && (re & POLLOUT) != 0)
                        drain(c);
                    if (c->in_use && (re & POLLHUP) != 0 && c->out_len == c->out_off)
                        close_conn(c, "client_hup");
                }
            }
            enforce_idle();
        }
        free(pfds);
        free(map);
    }

    {
        unsigned i;
        for (i = 0; i < opt.max_clients; i++)
            if (slots[i].in_use)
                close_conn(&slots[i], "shutdown");
    }
    logmsg(2, "INFO", 0,
           "exit conns=%lu frames=%lu replies=%lu rejects=%lu queue_full_closes=%lu unknown=%lu "
           "uptime_ms=%lld",
           C.conns, C.frames, C.replies, C.rejects, C.queue_full, C.unknown,
           (long long)(now_ms() - t0_ms));

fim:
    if (lfd >= 0)
        close(lfd);
    free(slots);
    if (log_fp != NULL && log_fp != stderr)
        fclose(log_fp);
    return rc;
}

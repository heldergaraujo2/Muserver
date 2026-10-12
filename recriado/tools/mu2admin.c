/* mu2admin.c — console administrativo local (Etapa E).
 *
 * O desenho completo esta em docs/ADMIN_CONSOLE.md e foi escrito ANTES deste codigo: arquitetura,
 * autenticacao, permissoes, API, estados, validacoes e erros.
 *
 * Regras que este codigo obedece:
 *  - nao toca o mud2: le o estado dele pelo protocolo v2, como o mu2ctl (ABI e contrato intactos);
 *  - escuta somente em 127.0.0.1 — qualquer outro endereco e recusado na partida;
 *  - token vem de arquivo 0600, nunca de argv nem de ambiente (aparecem em `ps`);
 *  - sem token valido o servidor NAO sobe (fail closed); nao existe token embutido;
 *  - comparacao de token em tempo constante;
 *  - o token nunca vai para o log nem para resposta de erro;
 *  - rota sem backend devolve 501, nunca sucesso simulado.
 *
 * Uso: mu2admin --token-file ARQ [--port N] [--listen 127.0.0.1] [--mud2-port N]
 *               [--mud2-host A] [--profile orig|mur0] [--gate-tsv ARQ] [--timeout-ms N]
 *               [--log-file ARQ]
 */
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "mu2/mu2.h"
#include "mu2/proto.h"

#define MAX_CREDS 16
#define TOK_MIN   32u
#define TOK_MAX   256u
#define PAPEL_MAX 15u
#define REQ_MAX   8192u
#define ROTA_MAX  256u
#define NHDR_MAX  32u
#define BODY_MAX  4096u
#define AUTH_MAX  256u

static volatile sig_atomic_t g_saida;

static void ao_sair(int sig)
{
    (void)sig;
    g_saida = 1;
}

struct cred {
    char tok[TOK_MAX + 1];
    char papel[PAPEL_MAX + 1];
};

static FILE *g_log;
static long g_t0;

static long agora_ms(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return 0;
    return (long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void loglinha(const char *fmt, ...)
{
    va_list ap;
    if (g_log == NULL)
        return;
    fprintf(g_log, "[+%06ld] ", agora_ms() - g_t0);
    va_start(ap, fmt);
    vfprintf(g_log, fmt, ap);
    va_end(ap);
    fputc('\n', g_log);
    fflush(g_log);
}

static void uso(const char *a0)
{
    fprintf(stderr,
            "uso: %s --token-file ARQ [--port N] [--listen 127.0.0.1] [--mud2-port N]\n"
            "        [--mud2-host A] [--profile orig|mur0] [--gate-tsv ARQ] [--timeout-ms N]\n"
            "        [--log-file ARQ]\n"
            "  --port 0 escolhe porta efemera e a imprime na linha `listen` do log.\n"
            "  o token vem de arquivo 0600 com linhas `<token>\\t<papel>`; papel: leitor|admin.\n"
            "  sem token valido o servidor nao sobe. escuta apenas em 127.0.0.1.\n",
            a0);
}

/* Comparacao em tempo constante: percorre sempre o mesmo numero de bytes, sem short-circuit, para
 * que o tempo de resposta nao vire oraculo de prefixo. */
static int ct_eq(const char *a, const char *b)
{
    unsigned int diff = 0u;
    size_t i;
    for (i = 0; i < TOK_MAX; i++)
        diff |= (unsigned int)((unsigned char)a[i] ^ (unsigned char)b[i]);
    return diff == 0u;
}

/* Carrega credenciais. Devolve 0 e preenche *n, ou -1 com motivo em err (sem ecoar o token). */
static int carrega_creds(const char *path, struct cred *v, int *n, char *err, size_t errsz)
{
    struct stat st;
    FILE *f;
    char linha[512];
    int cnt = 0;

    if (stat(path, &st) != 0) {
        snprintf(err, errsz, "arquivo de token inacessivel");
        return -1;
    }
    if (!S_ISREG(st.st_mode)) {
        snprintf(err, errsz, "arquivo de token nao e arquivo regular");
        return -1;
    }
    if ((st.st_mode & 0777) != 0600) {
        snprintf(err, errsz, "arquivo de token com permissao %03o (exigido 0600)",
                 (unsigned)(st.st_mode & 0777));
        return -1;
    }
    f = fopen(path, "r");
    if (f == NULL) {
        snprintf(err, errsz, "falha ao abrir arquivo de token");
        return -1;
    }
    while (fgets(linha, (int)sizeof linha, f) != NULL) {
        size_t l = strlen(linha);
        char *tab;
        size_t lt, lp;
        while (l > 0 && (linha[l - 1] == '\n' || linha[l - 1] == '\r'))
            linha[--l] = '\0';
        if (l == 0 || linha[0] == '#')
            continue;
        tab = strchr(linha, '\t');
        if (tab == NULL) {
            snprintf(err, errsz, "linha de credencial sem tab separador");
            fclose(f);
            return -1;
        }
        lt = (size_t)(tab - linha);
        lp = strlen(tab + 1);
        if (lt < TOK_MIN) {
            snprintf(err, errsz, "token com %lu caracteres (minimo %u)",
                     (unsigned long)lt, TOK_MIN);
            fclose(f);
            return -1;
        }
        if (lt > TOK_MAX || lp == 0 || lp > PAPEL_MAX) {
            snprintf(err, errsz, "credencial fora dos limites de tamanho");
            fclose(f);
            return -1;
        }
        if (strcmp(tab + 1, "leitor") != 0 && strcmp(tab + 1, "admin") != 0) {
            snprintf(err, errsz, "papel desconhecido (aceitos: leitor, admin)");
            fclose(f);
            return -1;
        }
        if (cnt >= MAX_CREDS) {
            snprintf(err, errsz, "mais de %d credenciais", MAX_CREDS);
            fclose(f);
            return -1;
        }
        memcpy(v[cnt].tok, linha, lt);
        v[cnt].tok[lt] = '\0';
        memcpy(v[cnt].papel, tab + 1, lp);
        v[cnt].papel[lp] = '\0';
        cnt++;
    }
    fclose(f);
    if (cnt == 0) {
        snprintf(err, errsz, "arquivo de token sem credencial");
        return -1;
    }
    *n = cnt;
    return 0;
}

static const char *acha_papel(const struct cred *v, int n, const char *tok)
{
    char buf[TOK_MAX + 1];
    size_t lt = strlen(tok);
    int i;
    const char *achado = NULL;
    if (lt > TOK_MAX)
        return NULL;
    memset(buf, 0, sizeof buf);
    memcpy(buf, tok, lt);
    /* varre todas as credenciais mesmo apos achar: nao revelar por tempo qual indice casou */
    for (i = 0; i < n; i++)
        if (ct_eq(buf, v[i].tok))
            achado = v[i].papel;
    return achado;
}

static int envia_tudo(int fd, const char *buf, size_t n)
{
    size_t off = 0;
    while (off < n) {
        ssize_t w = send(fd, buf + off, n - off, MSG_NOSIGNAL);
        if (w < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        if (w == 0)
            return -1;
        off += (size_t)w;
    }
    return 0;
}

static void responde(int fd, int status, const char *txt, const char *json)
{
    char cab[512];
    int n = snprintf(cab, sizeof cab,
                     "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\n"
                     "Content-Length: %lu\r\nConnection: close\r\n\r\n",
                     status, txt, (unsigned long)strlen(json));
    if (n <= 0 || (size_t)n >= sizeof cab)
        return;
    if (envia_tudo(fd, cab, (size_t)n) != 0)
        return;
    (void)envia_tudo(fd, json, strlen(json));
}

static void erro_json(int fd, int status, const char *txt, const char *codigo, const char *motivo)
{
    char corpo[512];
    snprintf(corpo, sizeof corpo, "{\"erro\":\"%s\",\"motivo\":\"%s\"}", codigo, motivo);
    responde(fd, status, txt, corpo);
    loglinha("http status=%d erro=%s", status, codigo);
}

/* Le a requisicao ate o fim dos cabecalhos. Devolve 0 ok, 1 timeout, -1 erro/limite. */
static int le_requisicao(int fd, char *buf, size_t cap, size_t *usado, int timeout_ms)
{
    size_t off = 0;
    int restante = timeout_ms;
    while (off + 1 < cap) {
        struct pollfd p;
        int pr;
        ssize_t r;
        p.fd = fd;
        p.events = POLLIN;
        p.revents = 0;
        pr = poll(&p, 1, restante);
        if (pr == 0)
            return 1;
        if (pr < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        r = recv(fd, buf + off, cap - off - 1, 0);
        if (r == 0)
            break;
        if (r < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        off += (size_t)r;
        buf[off] = '\0';
        if (strstr(buf, "\r\n\r\n") != NULL) {
            *usado = off;
            return 0;
        }
    }
    buf[off < cap ? off : cap - 1] = '\0';
    *usado = off;
    return strstr(buf, "\r\n\r\n") != NULL ? 0 : -1;
}

/* Pede a linha STATS ao mud2 pelo protocolo v2. Devolve 0 e preenche linha. */
static int pede_stats(const char *host, int port, mu2_profile profile, int timeout_ms,
                      char *linha, size_t cap)
{
    struct sockaddr_in sa;
    uint8_t out[MU2_MAX_FRAME], in[MU2_MAX_FRAME], body[MU2_MAX_BODY];
    const uint8_t *bout = NULL;
    mu2_frame f;
    size_t off = 0;
    int ne;
    int fd, rc = -1, pr;
    struct pollfd p;

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &sa.sin_addr) != 1) {
        close(fd);
        return -1;
    }
    if (connect(fd, (struct sockaddr *)&sa, sizeof sa) != 0) {
        close(fd);
        return -1;
    }
    ne = mu2_frame_encode(out, sizeof out, MU2_CODE_STATS, NULL, 0, profile);
    if (ne <= 0) {
        close(fd);
        return -1;
    }
    if (envia_tudo(fd, (const char *)out, (size_t)ne) != 0) {
        close(fd);
        return -1;
    }
    p.fd = fd;
    p.events = POLLIN;
    p.revents = 0;
    pr = poll(&p, 1, timeout_ms);
    if (pr <= 0) {
        close(fd);
        return -1;
    }
    for (;;) {
        ssize_t r = recv(fd, in + off, sizeof in - off, 0);
        int dr;
        if (r <= 0)
            break;
        off += (size_t)r;
        dr = mu2_frame_decode(&f, &bout, in, off, profile);
        if (dr == MU2_OK) {
            /* mu2_frame_body devolve o numero de bytes escritos, ou mu2_err < 0 — NAO MU2_OK */
            if (f.code == MU2_CODE_STATS && f.body_len + 1 <= cap &&
                mu2_frame_body(body, sizeof body, &f, in, profile) >= 0) {
                memcpy(linha, body, f.body_len);
                linha[f.body_len] = '\0';
                rc = 0;
            }
            break;
        }
        if (dr != MU2_E_INCOMPLETE || off >= sizeof in)
            break;
    }
    close(fd);
    return rc;
}

/* Le o relatorio do portao e conta estados/assercoes. Devolve 0 ok. */
static int le_gate(const char *path, long *pass, long *fail, long *blocked, long *asserc,
                   long *etapas)
{
    FILE *f;
    char linha[1024];
    int primeiro = 1;

    *pass = *fail = *blocked = *asserc = *etapas = 0;
    f = fopen(path, "r");
    if (f == NULL)
        return -1;
    while (fgets(linha, (int)sizeof linha, f) != NULL) {
        char etapa[128], estado[32];
        long assercoes = 0;
        if (primeiro) {
            primeiro = 0;
            if (strncmp(linha, "etapa\t", 6) == 0)
                continue;
        }
        if (sscanf(linha, "%127[^\t]\t%31[^\t]\t%*d\t%ld", etapa, estado, &assercoes) != 3)
            continue;
        (*etapas)++;
        /* ConvencAO do portao (run_all.sh): assercoes de etapa BLOCKED NAO entram no total —
         * etapa bloqueada nao foi executada de fato. Somar aqui daria um numero que contradiz o
         * relatorio do proprio portao (319 vs 312 medidos), entao a regra e a mesma. */
        if (strcmp(estado, "BLOCKED") != 0)
            *asserc += assercoes;
        if (strcmp(estado, "PASS") == 0)
            (*pass)++;
        else if (strcmp(estado, "FAIL") == 0)
            (*fail)++;
        else if (strcmp(estado, "BLOCKED") == 0)
            (*blocked)++;
    }
    fclose(f);
    return 0;
}

static int rota_valida(const char *rota)
{
    size_t i;
    if (rota[0] != '/' || strlen(rota) > ROTA_MAX)
        return 0;
    for (i = 0; rota[i] != '\0'; i++) {
        char c = rota[i];
        int ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                 (c >= '0' && c <= '9') || c == '/' || c == '_' || c == '-';
        if (!ok)
            return 0;
    }
    return strstr(rota, "..") == NULL;
}

int main(int argc, char **argv)
{
    const char *token_file = NULL, *escuta = "127.0.0.1", *mud2_host = "127.0.0.1";
    const char *gate_tsv = "out/gate.tsv", *log_file = NULL;
    int port = 0, mud2_port = 0, timeout_ms = 5000, i, lfd = -1, rc = 1;
    mu2_profile profile = MU2_PROFILE_ORIG;
    struct cred creds[MAX_CREDS];
    int ncreds = 0;
    char err[256];
    struct sockaddr_in sa;
    socklen_t slen = sizeof sa;
    struct sigaction sact;

    for (i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (strcmp(a, "--token-file") == 0 && v != NULL) { token_file = v; i++; }
        else if (strcmp(a, "--listen") == 0 && v != NULL) { escuta = v; i++; }
        else if (strcmp(a, "--port") == 0 && v != NULL) { port = atoi(v); i++; }
        else if (strcmp(a, "--mud2-host") == 0 && v != NULL) { mud2_host = v; i++; }
        else if (strcmp(a, "--mud2-port") == 0 && v != NULL) { mud2_port = atoi(v); i++; }
        else if (strcmp(a, "--gate-tsv") == 0 && v != NULL) { gate_tsv = v; i++; }
        else if (strcmp(a, "--timeout-ms") == 0 && v != NULL) { timeout_ms = atoi(v); i++; }
        else if (strcmp(a, "--log-file") == 0 && v != NULL) { log_file = v; i++; }
        else if (strcmp(a, "--profile") == 0 && v != NULL) {
            if (strcmp(v, "orig") == 0) profile = MU2_PROFILE_ORIG;
            else if (strcmp(v, "mur0") == 0) profile = MU2_PROFILE_MUR0;
            else { fprintf(stderr, "perfil desconhecido: %s\n", v); return 2; }
            i++;
        } else if (strcmp(a, "--help") == 0) { uso(argv[0]); return 0; }
        else { fprintf(stderr, "opcao desconhecida: %s\n", a); uso(argv[0]); return 2; }
    }

    /* A-3: somente loopback. Recusado na partida, nao em runtime. */
    if (strcmp(escuta, "127.0.0.1") != 0) {
        fprintf(stderr, "estado=erro motivo=listen fora de loopback (%s): somente 127.0.0.1\n",
                escuta);
        return 2;
    }
    if (token_file == NULL) {
        fprintf(stderr, "estado=erro motivo=--token-file ausente (fail closed: sem token nao sobe)\n");
        return 2;
    }
    if (carrega_creds(token_file, creds, &ncreds, err, sizeof err) != 0) {
        fprintf(stderr, "estado=erro motivo=%s\n", err);
        return 2;
    }
    if (log_file != NULL) {
        g_log = fopen(log_file, "w");
        if (g_log == NULL) {
            fprintf(stderr, "estado=erro motivo=log-file inacessivel\n");
            return 2;
        }
    }
    g_t0 = agora_ms();

    memset(&sact, 0, sizeof sact);
    sact.sa_handler = ao_sair;
    (void)sigaction(SIGTERM, &sact, NULL);
    (void)sigaction(SIGINT, &sact, NULL);
    signal(SIGPIPE, SIG_IGN);

    lfd = socket(AF_INET, SOCK_STREAM, 0);
    if (lfd < 0) {
        fprintf(stderr, "estado=erro motivo=socket\n");
        return 2;
    }
    {
        int um = 1;
        (void)setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &um, sizeof um);
    }
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, escuta, &sa.sin_addr) != 1) {
        fprintf(stderr, "estado=erro motivo=endereco invalido\n");
        close(lfd);
        return 2;
    }
    if (bind(lfd, (struct sockaddr *)&sa, sizeof sa) != 0) {
        fprintf(stderr, "estado=erro motivo=bind (%s)\n", strerror(errno));
        close(lfd);
        return 2;
    }
    if (listen(lfd, 8) != 0) {
        fprintf(stderr, "estado=erro motivo=listen\n");
        close(lfd);
        return 2;
    }
    if (getsockname(lfd, (struct sockaddr *)&sa, &slen) == 0)
        loglinha("listen addr=%s port=%d credenciais=%d mud2=%s:%d", escuta,
                 (int)ntohs(sa.sin_port), ncreds, mud2_host, mud2_port);
    fprintf(stderr, "estado=pronto\n");
    rc = 0;

    while (!g_saida) {
        struct pollfd p;
        int pr, cfd;
        char req[REQ_MAX + 1];
        size_t usado = 0;
        char metodo[16], rota[ROTA_MAX + 2], versao[16];
        const char *fim_hdr;
        const char *pauth;
        char auth[AUTH_MAX + 1];
        const char *papel;
        int cl = 0;

        p.fd = lfd;
        p.events = POLLIN;
        p.revents = 0;
        pr = poll(&p, 1, 200);
        if (pr < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        if (pr == 0)
            continue;
        cfd = accept(lfd, NULL, NULL);
        if (cfd < 0)
            continue;

        if (le_requisicao(cfd, req, sizeof req, &usado, timeout_ms) != 0) {
            loglinha("http close=requisicao_incompleta");
            close(cfd);
            continue;
        }
        if (sscanf(req, "%15s %257s %15s", metodo, rota, versao) != 3) {
            erro_json(cfd, 400, "Bad Request", "requisicao_invalida", "linha de requisicao");
            close(cfd);
            continue;
        }
        fim_hdr = strstr(req, "\r\n\r\n");
        if (fim_hdr == NULL) {
            erro_json(cfd, 400, "Bad Request", "requisicao_invalida", "cabecalhos");
            close(cfd);
            continue;
        }

        /* Content-Length: recusar sem ler o resto quando grande demais */
        {
            const char *pcl = strcasestr(req, "\r\nContent-Length:");
            if (pcl != NULL && pcl < fim_hdr) {
                cl = atoi(pcl + 17);
                if (cl < 0 || (size_t)cl > BODY_MAX) {
                    erro_json(cfd, 413, "Payload Too Large", "corpo_grande_demais",
                              "Content-Length acima de 4096");
                    close(cfd);
                    continue;
                }
            }
        }

        /* Authorization */
        auth[0] = '\0';
        pauth = strcasestr(req, "\r\nAuthorization:");
        if (pauth != NULL && pauth < fim_hdr) {
            const char *ini = pauth + 16;
            const char *nl = strstr(ini, "\r\n");
            size_t l;
            while (*ini == ' ')
                ini++;
            l = (nl != NULL) ? (size_t)(nl - ini) : strlen(ini);
            if (l > AUTH_MAX) {
                erro_json(cfd, 401, "Unauthorized", "token_malformado", "header longo demais");
                close(cfd);
                continue;
            }
            memcpy(auth, ini, l);
            auth[l] = '\0';
        }

        /* /health nao exige token (sonda de vida) */
        if (strcmp(metodo, "GET") == 0 && strcmp(rota, "/health") == 0) {
            char corpo[256];
            char stats[MU2_MAX_BODY];
            int vivo = (mud2_port > 0 &&
                        pede_stats(mud2_host, mud2_port, profile, 500, stats, sizeof stats) == 0);
            snprintf(corpo, sizeof corpo,
                     "{\"estado\":\"pronto\",\"versao\":\"v2\",\"upstream\":\"%s\"}",
                     (mud2_port <= 0) ? "nao_configurado" : (vivo ? "ok" : "indisponivel"));
            responde(cfd, 200, "OK", corpo);
            loglinha("http rota=/health status=200");
            close(cfd);
            continue;
        }

        if (strcmp(metodo, "GET") != 0 && strcmp(metodo, "POST") != 0) {
            erro_json(cfd, 405, "Method Not Allowed", "metodo_nao_permitido", metodo);
            close(cfd);
            continue;
        }
        if (!rota_valida(rota)) {
            erro_json(cfd, 400, "Bad Request", "rota_invalida", "caractere ou tamanho");
            close(cfd);
            continue;
        }
        if (auth[0] == '\0') {
            erro_json(cfd, 401, "Unauthorized", "token_ausente", "sem Authorization");
            close(cfd);
            continue;
        }
        if (strncmp(auth, "Bearer ", 7) != 0) {
            erro_json(cfd, 401, "Unauthorized", "token_malformado", "esperado Bearer");
            close(cfd);
            continue;
        }
        papel = acha_papel(creds, ncreds, auth + 7);
        if (papel == NULL) {
            /* nunca ecoar o token apresentado */
            erro_json(cfd, 401, "Unauthorized", "token_invalido", "credencial nao confere");
            loglinha("http auth=falha");
            close(cfd);
            continue;
        }

        if (strcmp(metodo, "GET") == 0 && strcmp(rota, "/stats") == 0) {
            char stats[MU2_MAX_BODY], corpo[MU2_MAX_BODY + 64];
            if (mud2_port <= 0 ||
                pede_stats(mud2_host, mud2_port, profile, 1000, stats, sizeof stats) != 0) {
                erro_json(cfd, 503, "Service Unavailable", "upstream_indisponivel",
                          "mud2 nao respondeu");
                close(cfd);
                continue;
            }
            stats[strcspn(stats, "\"\\\n")] = '\0';
            snprintf(corpo, sizeof corpo, "{\"estado\":\"ok\",\"stats\":\"%s\"}", stats);
            responde(cfd, 200, "OK", corpo);
            loglinha("http rota=/stats status=200 papel=%s", papel);
            close(cfd);
            continue;
        }
        if (strcmp(metodo, "GET") == 0 && strcmp(rota, "/gate") == 0) {
            long pass, fail, blocked, asserc, etapas;
            char corpo[256];
            if (le_gate(gate_tsv, &pass, &fail, &blocked, &asserc, &etapas) != 0) {
                erro_json(cfd, 503, "Service Unavailable", "upstream_indisponivel",
                          "relatorio do portao ilegivel");
                close(cfd);
                continue;
            }
            snprintf(corpo, sizeof corpo,
                     "{\"estado\":\"ok\",\"etapas\":%ld,\"pass\":%ld,\"fail\":%ld,"
                     "\"blocked\":%ld,\"assercoes\":%ld}",
                     etapas, pass, fail, blocked, asserc);
            responde(cfd, 200, "OK", corpo);
            loglinha("http rota=/gate status=200 papel=%s", papel);
            close(cfd);
            continue;
        }
        if (strcmp(rota, "/publicar") == 0) {
            /* Nao ha backend: 501 com motivo, nunca sucesso simulado. */
            if (strcmp(papel, "admin") != 0) {
                erro_json(cfd, 403, "Forbidden", "papel_insuficiente", "exige admin");
                close(cfd);
                continue;
            }
            erro_json(cfd, 501, "Not Implemented", "nao_implementado",
                      "sem alvo de publicacao autorizado");
            close(cfd);
            continue;
        }
        if (strcmp(metodo, "POST") == 0) {
            erro_json(cfd, 404, "Not Found", "rota_desconhecida", rota);
            close(cfd);
            continue;
        }
        erro_json(cfd, 404, "Not Found", "rota_desconhecida", rota);
        close(cfd);
    }

    close(lfd);
    loglinha("exit rc=%d", rc);
    if (g_log != NULL)
        fclose(g_log);
    return rc;
}

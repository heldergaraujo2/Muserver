/* io_trace.c — instrumento de auditoria da R-11: registra a ORDEM real das syscalls de escrita e
 * sincronizacao do banco, sem tocar no produto (interposicao por LD_PRELOAD, nada compilado dentro
 * do `mu2dbctl`).
 *
 * Por que existe (2026-10-13): ler o codigo mostrava que o commit de transacao explicita chamava
 * `fsync` e a operacao implicita nao; isso nao e observavel pelo conteudo do arquivo (a pagina suja
 * esta no page cache e a leitura a encontra), e `strace` nao existe neste ambiente. A unica medicao
 * honesta e a sequencia de chamadas: e o que este instrumento produz.
 *
 * Uso:
 *   cc -shared -fPIC -O1 -o out/io_trace.so tests/io_trace.c -ldl
 *   ASAN_OPTIONS=verify_asan_link_order=0 MU2DB_IO_LOG=/tmp/log LD_PRELOAD=$PWD/out/io_trace.so \
 *       ./out/mu2dbctl /tmp/x.db dar-item jogador1 Alfa 700 1 9
 *
 * Saida (uma linha por evento; fd=1/2 sao stdout/stderr e podem ser ignorados):
 *   pwrite fd=3 off=373 len=32
 *   fsync fd=3 tamanho=458
 *   close fd=3
 *
 * `ASAN_OPTIONS=verify_asan_link_order=0` e necessario porque o binario do produto e construido com
 * ASan e o runtime do ASan exige vir primeiro na lista de bibliotecas. Sem a variavel, o processo
 * morre antes de rodar (exit 1) — o teste trata isso como BLOCKED, nunca como aprovacao.
 *
 * Este arquivo nao le, copia nem usa nada de `MuServer/`: so observa o processo do proprio produto.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

static FILE *lf;
static ssize_t (*real_write)(int, const void *, size_t);
static ssize_t (*real_pwrite)(int, const void *, size_t, off_t);
static int (*real_fsync)(int);
static int (*real_close)(int);

static void abre(void)
{
    const char *p = getenv("MU2DB_IO_LOG");
    if (lf == NULL && p != NULL)
        lf = fopen(p, "a");
}

static void ev(const char *fmt, long a, long b, long c)
{
    abre();
    if (lf != NULL) {
        fprintf(lf, fmt, a, b, c);
        fflush(lf);
    }
}

ssize_t write(int fd, const void *buf, size_t n)
{
    if (real_write == NULL)
        real_write = dlsym(RTLD_NEXT, "write");
    off_t off = lseek(fd, 0, SEEK_CUR);
    ssize_t r = real_write(fd, buf, n);
    ev("write fd=%ld off=%ld len=%ld\n", fd, (long)off, (long)r);
    return r;
}

ssize_t pwrite(int fd, const void *buf, size_t n, off_t o)
{
    if (real_pwrite == NULL)
        real_pwrite = dlsym(RTLD_NEXT, "pwrite");
    ssize_t r = real_pwrite(fd, buf, n, o);
    ev("pwrite fd=%ld off=%ld len=%ld\n", fd, (long)o, (long)r);
    return r;
}

int fsync(int fd)
{
    off_t fim;
    if (real_fsync == NULL)
        real_fsync = dlsym(RTLD_NEXT, "fsync");
    fim = lseek(fd, 0, SEEK_END);
    if (fim >= 0)
        ev("fsync fd=%ld tamanho=%ld\n", fd, (long)fim, 0);
    else
        ev("fsync fd=%ld tamanho=?\n", fd, 0, 0);
    return real_fsync(fd);
}

int close(int fd)
{
    if (real_close == NULL)
        real_close = dlsym(RTLD_NEXT, "close");
    ev("close fd=%ld\n", fd, 0, 0);
    return real_close(fd);
}

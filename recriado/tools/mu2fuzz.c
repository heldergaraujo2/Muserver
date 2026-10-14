/* mu2fuzz.c — fuzzing DETERMINÍSTICO do codec v2 (Etapa B).
 *
 * Não há motor de fuzz neste ambiente (medido: sem afl-fuzz, honggfuzz, radamsa, clang; gcc 12 não
 * aceita -fsanitize=fuzzer). Isto é uma alternativa determinística, e a diferença importa: não há
 * cobertura guiada por feedback de bordas nem descoberta de caminhos novos — há uma sequência
 * reproduzível de mutações a partir de sementes, julgada por um oráculo de invariantes. Não
 * afirmar cobertura equivalente a um fuzzer dedicado é parte do contrato desta ferramenta.
 *
 * Liga contra out/wire.o — o codec real. Sanitizadores do build já dão detecção de erro de memória:
 * com -fno-sanitize-recover=all qualquer violação aborta o processo.
 *
 * Oráculo (derivado de include/mu2/mu2.h, não de outra implementação):
 *   decode OK         => 4 <= frame_len <= 2052, body_len == frame_len-4, body_len <= src_len-4
 *   decode INCOMPLETE => needed > 0 e needed <= 2052
 *   decode BAD_LEN    => size < 4 ou size > 2052, relido dos 4 primeiros bytes
 *   decode OK         => mu2_frame_body cabe em MU2_MAX_BODY e a transformação é involutiva
 *   encode            => devolve 4+body_len, re-decodifica com o mesmo code/body_len e o corpo
 *                        volta idêntico (roundtrip) nos dois perfis
 * A entrada vai para um buffer heap do tamanho exato: se o codec ler além, a redzone do ASan pega.
 *
 * Saída: linhas chave=valor + `# fuzz=N violacoes=V ...`. Exit 0 limpo, 3 com violação de
 * invariante, e morte por sinal se um sanitizador abortar (o harness relata a semente).
 */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

#include "mu2/mu2.h"

#define MAXB 4096u

static uint64_t st;

static uint64_t rnd(void)
{   /* xorshift64*: determinístico, e a semente aparece na saída */
    st ^= st >> 12u;
    st ^= st << 25u;
    st ^= st >> 27u;
    return st * 0x2545F4914F6CDD1Dull;
}
static uint32_t abaixo(uint32_t n) { return (uint32_t)(rnd() % (uint64_t)(n != 0u ? n : 1u)); }

static void ph(FILE *f, const uint8_t *b, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++)
        fprintf(f, "%02x", (unsigned)b[i]);
}

/* ---------------------------------------------------------------- sementes */
static uint8_t seeds[64][MAXB];
static size_t seeds_len[64];
static size_t n_seeds;

static int hex2b(const char *s, uint8_t *d, size_t cap, size_t *out)
{
    size_t n = strlen(s), i;
    if ((n & 1u) != 0u || n / 2u > cap)
        return -1;
    for (i = 0; i < n; i += 2u) {
        unsigned v;
        char tmp[3] = { s[i], s[i + 1u], '\0' };
        if (sscanf(tmp, "%2x", &v) != 1)
            return -1;
        d[i / 2u] = (uint8_t)v;
    }
    *out = n / 2u;
    return 0;
}

/* ---------------------------------------------------------------- mutações */
static const char *op_nome(uint32_t o)
{
    static const char *nomes[] = { "flip_bit", "byte_aleatorio", "byte_fronteira", "apagar_byte",
                                   "inserir_byte", "duplicar_byte", "trocar_bytes", "truncar",
                                   "size_fronteira", "code_aleatorio" };
    return nomes[o % 10u];
}

/* Aplica uma mutação em `in` e escreve em `out`; devolve o novo comprimento. */
static size_t mutar(const uint8_t *in, size_t in_len, uint8_t *out, size_t cap, uint32_t op)
{
    size_t n = in_len < cap ? in_len : cap;
    uint32_t i;
    memcpy(out, in, n);
    switch (op % 10u) {
    case 0: /* flip de um bit */
        if (n == 0u)
            return 0u;
        i = abaixo((uint32_t)n);
        out[i] = (uint8_t)(out[i] ^ (uint8_t)(1u << abaixo(8u)));
        return n;
    case 1:
        if (n == 0u)
            return 0u;
        out[abaixo((uint32_t)n)] = (uint8_t)abaixo(256u);
        return n;
    case 2: {
        static const uint8_t front[8] = { 0x00u, 0xFFu, 0x04u, 0x08u, 0xFDu, 0x00u, 0x01u, 0x7Fu };
        if (n == 0u)
            return 0u;
        out[abaixo((uint32_t)n)] = front[abaixo(8u)];
        return n;
    }
    case 3:
        if (n == 0u)
            return 0u;
        i = abaixo((uint32_t)n);
        memmove(out + i, out + i + 1u, n - i - 1u);
        return n - 1u;
    case 4:
        if (n >= cap)
            return n;
        i = abaixo((uint32_t)(n + 1u));
        memmove(out + i + 1u, out + i, n - i);
        out[i] = (uint8_t)abaixo(256u);
        return n + 1u;
    case 5:
        if (n < 2u || n >= cap)
            return n;
        i = abaixo((uint32_t)n);
        out[i] = out[abaixo((uint32_t)n)];
        return n;
    case 6: {
        uint8_t t;
        uint32_t j;
        if (n < 2u)
            return n;
        i = abaixo((uint32_t)n);
        j = abaixo((uint32_t)n);
        t = out[i];
        out[i] = out[j];
        out[j] = t;
        return n;
    }
    case 7:
        return (size_t)abaixo((uint32_t)(n + 1u)); /* truncar, inclusive para zero */
    case 8: {
        static const uint16_t tam[8] = { 0u, 1u, 3u, 4u, 5u, 2052u, 2053u, 65535u };
        uint16_t v;
        if (n < 4u)
            return n;
        v = tam[abaixo(8u)];
        out[2] = (uint8_t)(v & 0xFFu);
        out[3] = (uint8_t)((v >> 8) & 0xFFu);
        return n;
    }
    default:
        if (n < 2u)
            return n;
        out[0] = (uint8_t)abaixo(256u);
        out[1] = (uint8_t)abaixo(256u);
        return n;
    }
}

/* ---------------------------------------------------------------- oráculo */
static unsigned long viol;
static const char *dir_saida = "out/fuzz";

static void viola(uint64_t seed, uint64_t it, uint32_t op, const uint8_t *b, size_t n,
                  const char *invariante)
{
    FILE *f;
    char caminho[256];
    viol++;
    printf("violacao semente=%llu iter=%llu operador=%s invariante=%s entrada=",
           (unsigned long long)seed, (unsigned long long)it, op_nome(op), invariante);
    ph(stdout, b, n);
    printf("\n");
    (void)snprintf(caminho, sizeof caminho, "%s/regressao-%llu-%llu.hex", dir_saida,
                   (unsigned long long)seed, (unsigned long long)it);
    f = fopen(caminho, "w");
    if (f != NULL) {
        ph(f, b, n);
        fprintf(f, "\n");
        (void)fclose(f);
        printf("regressao_gravada=%s\n", caminho);
    }
}

/* Testa os invariantes de decode/body sobre uma entrada. `src` vai para heap do tamanho exato. */
static void testa_decode(uint64_t seed, uint64_t it, uint32_t op, const uint8_t *b, size_t n)
{
    mu2_profile ps[2] = { MU2_PROFILE_ORIG, MU2_PROFILE_MUR0 };
    size_t k;
    for (k = 0; k < 2u; k++) {
        mu2_frame f;
        const uint8_t *bout = NULL;
        uint8_t *src = NULL;
        uint8_t corpo[MU2_MAX_BODY];
        int r, br;

        src = (uint8_t *)malloc(n != 0u ? n : 1u); /* tamanho exato: redzone do ASan vigia a leitura */
        if (src == NULL)
            return;
        if (n != 0u)
            memcpy(src, b, n);

        r = mu2_frame_decode(&f, &bout, src, n, ps[k]);
        if (r == MU2_OK) {
            if (f.frame_len < MU2_HEADER_SIZE || f.frame_len > (uint16_t)MU2_MAX_FRAME)
                viola(seed, it, op, b, n, "frame_len dentro de 4..2052");
            if (f.body_len != (size_t)f.frame_len - (size_t)MU2_HEADER_SIZE)
                viola(seed, it, op, b, n, "body_len == frame_len - 4");
            if (f.body_len > n - (size_t)MU2_HEADER_SIZE)
                viola(seed, it, op, b, n, "body_len cabe no que foi lido");
            if (bout != src + MU2_HEADER_SIZE)
                viola(seed, it, op, b, n, "corpo aponta para src+4");
            br = mu2_frame_body(corpo, sizeof corpo, &f, src, ps[k]);
            if (br != (int)f.body_len)
                viola(seed, it, op, b, n, "mu2_frame_body devolve body_len num buffer de 2048");
            else if (ps[k] == MU2_PROFILE_MUR0 && f.body_len > 0u) {
                /* involução: aplicar de novo tem de restaurar o que estava no stream */
                uint8_t de_novo[MU2_MAX_BODY];
                memcpy(de_novo, corpo, f.body_len);
                mu2_body_transform(de_novo, f.body_len, f.code, ps[k]);
                if (memcmp(de_novo, src + MU2_HEADER_SIZE, f.body_len) != 0)
                    viola(seed, it, op, b, n, "transformacao mur0 e involutiva");
            }
        } else if (r == MU2_E_INCOMPLETE) {
            if (f.needed == 0u || f.needed > (size_t)MU2_MAX_FRAME)
                viola(seed, it, op, b, n, "needed em 1..2052 quando incompleto");
        } else if (r == MU2_E_BAD_LEN) {
            if (n >= (size_t)MU2_HEADER_SIZE) {
                uint16_t s = (uint16_t)((unsigned)src[2] | ((unsigned)src[3] << 8));
                if (s >= MU2_HEADER_SIZE && s <= (uint16_t)MU2_MAX_FRAME)
                    viola(seed, it, op, b, n, "BAD_LEN so com size <4 ou >2052");
            }
        } else if (r != MU2_E_ARG && r != MU2_E_PROFILE) {
            viola(seed, it, op, b, n, "codigo de retorno conhecido");
        }
        free(src);
    }
}

/* encode -> decode -> body tem de devolver o corpo original, nos dois perfis. */
static void testa_roundtrip(uint64_t seed, uint64_t it, uint32_t op, const uint8_t *corpo,
                            size_t n)
{
    mu2_profile ps[2] = { MU2_PROFILE_ORIG, MU2_PROFILE_MUR0 };
    size_t k;
    if (n > (size_t)MU2_MAX_BODY)
        return;
    for (k = 0; k < 2u; k++) {
        uint8_t frame[MU2_MAX_FRAME];
        uint8_t volta[MU2_MAX_BODY];
        mu2_frame f;
        const uint8_t *bout = NULL;
        uint16_t code = (uint16_t)(abaixo(65536u));
        int r = mu2_frame_encode(frame, sizeof frame, code, corpo, n, ps[k]);
        if (r != (int)(n + (size_t)MU2_HEADER_SIZE)) {
            viola(seed, it, op, corpo, n, "encode devolve 4+body_len");
            continue;
        }
        if (mu2_frame_decode(&f, &bout, frame, (size_t)r, ps[k]) != MU2_OK) {
            viola(seed, it, op, corpo, n, "quadro do encode decodifica");
            continue;
        }
        if (f.code != code || f.body_len != n)
            viola(seed, it, op, corpo, n, "decode devolve o mesmo code e body_len");
        if (mu2_frame_body(volta, sizeof volta, &f, frame, ps[k]) != (int)n ||
            (n > 0u && memcmp(volta, corpo, n) != 0))
            viola(seed, it, op, corpo, n, "roundtrip devolve o corpo original");
    }
}

int main(int argc, char **argv)
{
    uint64_t seed = 1ull, iters = 10000ull, it;
    uint32_t maxb = 300u;
    long mem_mb = 0;
    int i;
    unsigned long ops[10] = { 0 };

    for (i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (strcmp(a, "--seed") == 0 && v != NULL) { seed = (uint64_t)strtoull(v, NULL, 10); i++; }
        else if (strcmp(a, "--iters") == 0 && v != NULL) { iters = (uint64_t)strtoull(v, NULL, 10); i++; }
        else if (strcmp(a, "--max-bytes") == 0 && v != NULL) { maxb = (uint32_t)strtoul(v, NULL, 10); i++; }
        else if (strcmp(a, "--mem-limit-mb") == 0 && v != NULL) { mem_mb = strtol(v, NULL, 10); i++; }
        else if (strcmp(a, "--saida-dir") == 0 && v != NULL) { dir_saida = v; i++; }
        else if (strcmp(a, "--seed-hex") == 0 && v != NULL) {
            if (n_seeds < 64u && hex2b(v, seeds[n_seeds], MAXB, &seeds_len[n_seeds]) == 0)
                n_seeds++;
            i++;
        } else if (strcmp(a, "--progresso-a-cada") == 0 && v != NULL) { i++; }
        else { fprintf(stderr, "mu2fuzz: opcao desconhecida %s\n", a); return 2; }
    }
    if (maxb == 0u || maxb > MAXB) {
        fprintf(stderr, "mu2fuzz: --max-bytes em 1..%u\n", MAXB);
        return 2;
    }
    if (mem_mb > 0) {
        struct rlimit rl;
        rl.rlim_cur = (rlim_t)((uint64_t)mem_mb * 1024u * 1024u);
        rl.rlim_max = rl.rlim_cur;
        if (setrlimit(RLIMIT_AS, &rl) != 0)
            printf("# aviso=RLIMIT_AS nao aplicado\n");
    }
    if (n_seeds == 0u) {   /* semente mínima: o cabeçalho mais curto possível */
        seeds_len[0] = 4u;
        seeds[0][0] = 0x01u; seeds[0][1] = 0x00u; seeds[0][2] = 0x04u; seeds[0][3] = 0x00u;
        n_seeds = 1u;
    }

    st = seed != 0ull ? seed : 1ull;
    printf("# fuzz: semente=%llu iteracoes=%llu sementes=%zu max_bytes=%u mem_limit_mb=%ld\n",
           (unsigned long long)seed, (unsigned long long)iters, n_seeds, (unsigned)maxb, mem_mb);
    printf("# aviso=motor proprio deterministico; nao ha cobertura guiada por feedback (sem afl/clang)\n");

    for (it = 0; it < iters; it++) {
        uint8_t buf[MAXB], mut[MAXB];
        size_t base = (size_t)(rnd() % (uint64_t)n_seeds);
        size_t bl = seeds_len[base];
        uint32_t op;
        size_t ml;

        if (bl > maxb)
            bl = maxb;
        memcpy(buf, seeds[base], bl);
        op = abaixo(10u);
        ops[op % 10u]++;
        ml = mutar(buf, bl, mut, maxb, op);

        testa_decode(seed, it, op, mut, ml);
        if (ml <= (size_t)MU2_MAX_BODY)
            testa_roundtrip(seed, it, op, mut, ml);

        if ((it % 5000ull) == 0ull && it != 0ull)
            printf("# progresso semente=%llu iter=%llu violacoes=%lu\n",
                   (unsigned long long)seed, (unsigned long long)it, viol);
    }

    printf("iteracoes=%lu sementes=%zu violacoes=%lu\n", (unsigned long)iters, n_seeds, viol);
    printf("operadores=");
    for (i = 0; i < 10; i++)
        printf("%s%s=%lu", i != 0 ? "," : "", op_nome((uint32_t)i), ops[i]);
    printf("\n");
    printf("# fuzz=%lu violacoes=%lu exit=%d\n", (unsigned long)iters, viol, viol != 0u ? 3 : 0);
    return viol != 0u ? 3 : 0;
}

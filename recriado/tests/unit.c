/* unit.c — suíte unitária do enquadramento (fase R-3).
 *
 * Saidas: TAP na stdout (plano no fim, como no padrao do projeto) e o resumo em uma linha.
 * Cada `CHECK` e uma assercao contada; nenhum caso desta suíte existe para "passar": cada um
 * e casado com uma falsificacao documentada em docs/CHANGELOG.md (inverter campos do cabecalho,
 * afrouxar a validacao de comprimento, neutralizar a transformacao do perfil). Se a mutacao nao
 * derruba nenhum caso, o caso e que nao mede nada.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mu2/mu2.h"

static int g_total;
static int g_fail;

#define CHECK(cond, name)                                                                        \
    do {                                                                                         \
        g_total++;                                                                               \
        if (cond) {                                                                              \
            printf("ok %d - %s\n", g_total, (name));                                            \
        } else {                                                                                 \
            g_fail++;                                                                            \
            printf("not ok %d - %s\n", g_total, (name));                                        \
        }                                                                                        \
    } while (0)

/* LCG deterministico: a mesma sequencia em qualquer execucao e em qualquer host. */
static uint32_t g_rng = 20261012u;
static uint8_t nxt(void)
{
    g_rng = g_rng * 1664525u + 1013904223u;
    return (uint8_t)((g_rng >> 19) & 0xFFu);
}

static size_t fill(uint8_t *buf, size_t len)
{
    size_t i;
    for (i = 0; i < len; i++) {
        buf[i] = nxt();
    }
    return len;
}

static const size_t k_lens[] = {0u,   1u,   2u,   3u,   4u,    5u,    7u,    16u,   63u,
                                64u,  65u,  255u, 256u, 1023u, 1024u, 2047u, 2048u};

static int roundtrip_ok(uint16_t code, const uint8_t *body, size_t len, mu2_profile p)
{
    uint8_t wire[MU2_MAX_FRAME];
    uint8_t back[MU2_MAX_BODY];
    mu2_frame f;
    const uint8_t *stream_body = NULL;
    int n = mu2_frame_encode(wire, sizeof wire, code, body, len, p);
    if (n != (int)mu2_frame_size(len)) {
        return 0;
    }
    if (mu2_frame_decode(&f, &stream_body, wire, (size_t)n, p) != MU2_OK) {
        return 0;
    }
    if (f.code != code || f.frame_len != (uint16_t)n || f.body_len != len || f.needed != 0u) {
        return 0;
    }
    if (len == 0u) {
        return 1;
    }
    if (mu2_frame_body(back, sizeof back, &f, wire, p) != (int)len) {
        return 0;
    }
    return memcmp(back, body, len) == 0;
}

int main(void)
{
    size_t i, k;
    static const mu2_profile k_prof[2] = {MU2_PROFILE_ORIG, MU2_PROFILE_MUR0};
    uint8_t big[MU2_MAX_FRAME];
    uint8_t probe[MU2_MAX_FRAME];

    /* --- T1: nomes e validade de perfil --- */
    CHECK(mu2_profile_valid(MU2_PROFILE_ORIG) == 1, "T1.1 orig e perfil valido");
    CHECK(mu2_profile_valid(MU2_PROFILE_MUR0) == 1, "T1.2 mur0 e perfil valido");
    CHECK(mu2_profile_valid((mu2_profile)MU2_PROFILE_COUNT) == 0, "T1.3 perfil fora do conjunto e recusado");
    CHECK(strcmp(mu2_profile_name(MU2_PROFILE_ORIG), "orig") == 0 &&
              strcmp(mu2_profile_name(MU2_PROFILE_MUR0), "mur0") == 0,
          "T1.4 nomes dos dois perfis estao presentes no diagnostico");

    /* --- T2: aritmetica de tamanho --- */
    CHECK(mu2_frame_size(0u) == MU2_HEADER_SIZE, "T2.1 corpo vazio ocupa so o cabecalho");
    CHECK(mu2_frame_size(1u) == MU2_HEADER_SIZE + 1u, "T2.2 corpo de 1B");
    CHECK(mu2_frame_size(2047u) == MU2_MAX_FRAME - 1u, "T2.3 um abaixo do teto");
    CHECK(mu2_frame_size(MU2_MAX_BODY) == MU2_MAX_FRAME, "T2.4 no teto do contrato");
    CHECK(mu2_frame_size((size_t)MU2_MAX_BODY + 1u) == 0u, "T2.5 acima do teto devolve 0");

    /* --- T3: bytes exatos do cabecalho (code LE, size LE) --- */
    {
        static const uint8_t body7[7] = {1, 2, 3, 4, 5, 6, 7};
        for (k = 0; k < 2; k++) {
            memset(probe, 0, sizeof probe);
            int n = mu2_frame_encode(probe, sizeof probe, 0x1234u, body7, 7u, k_prof[k]);
            CHECK(n == 11 && probe[0] == 0x34u && probe[1] == 0x12u && probe[2] == 11u &&
                      probe[3] == 0u,
                  "T3 codificacao escreve code LE e size LE no cabecalho");
        }
    }

    /* --- T4: ida e volta por comprimento e por perfil --- */
    for (k = 0; k < 2; k++) {
        for (i = 0; i < sizeof k_lens / sizeof k_lens[0]; i++) {
            size_t len = k_lens[i];
            uint8_t body[MU2_MAX_BODY];
            char name[96];
            (void)fill(body, len);
            (void)snprintf(name, sizeof name, "T4 round-trip perfil=%s corpo=%zu",
                           mu2_profile_name(k_prof[k]), len);
            CHECK(roundtrip_ok((uint16_t)(0x0100u + i), body, len, k_prof[k]), name);
        }
    }

    /* --- T5: a transformacao do mur0 e involutiva e realmente altera o corpo --- */
    for (i = 0; i < sizeof k_lens / sizeof k_lens[0]; i++) {
        size_t len = k_lens[i];
        uint8_t a[MU2_MAX_BODY];
        uint8_t b[MU2_MAX_BODY];
        if (len == 0u) {
            continue;
        }
        (void)fill(a, len);
        (void)memcpy(b, a, len);
        mu2_body_transform(b, len, 0xBEEFu, MU2_PROFILE_MUR0);
        mu2_body_transform(b, len, 0xBEEFu, MU2_PROFILE_MUR0);
        CHECK(memcmp(a, b, len) == 0, "T5.1 aplicar a transformacao duas vezes restaura o corpo");
        (void)memset(b, 0, sizeof b);
        (void)memcpy(b, a, len);
        mu2_body_transform(b, len, 0xBEEFu, MU2_PROFILE_MUR0);
        CHECK(memcmp(a, b, len) != 0, "T5.2 o corpo do mur0 nao sai cru do codec");
    }
    {
        uint8_t orig[MU2_MAX_BODY];
        (void)fill(orig, 32u);
        (void)memset(probe, 0, sizeof probe);
        (void)memcpy(probe, orig, 32u);
        mu2_body_transform(probe, 32u, 0x0000u, MU2_PROFILE_ORIG);
        CHECK(memcmp(probe, orig, 32u) == 0, "T5.3 o perfil orig e identidade, por contrato");
    }

    /* --- T6: recusas da codificacao --- */
    {
        uint8_t body4[MU2_MAX_BODY + 8];
        (void)memset(body4, 0x5Au, sizeof body4);
        memset(probe, 0, sizeof probe);
        CHECK(mu2_frame_encode(probe, sizeof probe, 1u, body4, MU2_MAX_BODY + 1u,
                               MU2_PROFILE_ORIG) == MU2_E_SIZE,
              "T6.1 corpo acima do teto e recusado, nao truncado");
        CHECK(mu2_frame_encode(NULL, 64u, 1u, body4, 4u, MU2_PROFILE_ORIG) == MU2_E_ARG,
              "T6.2 destino nulo e recusado");
        CHECK(mu2_frame_encode(probe, 3u, 1u, body4, 4u, MU2_PROFILE_ORIG) == MU2_E_DST_SMALL,
              "T6.3 destino menor que o quadro e recusado, sem escrever");
        CHECK(mu2_frame_encode(probe, sizeof probe, 1u, NULL, 7u, MU2_PROFILE_ORIG) == MU2_E_ARG,
              "T6.4 corpo nulo com comprimento nao-zero e recusado");
        CHECK(mu2_frame_encode(probe, sizeof probe, 1u, NULL, 0u, MU2_PROFILE_ORIG) ==
                  (int)MU2_HEADER_SIZE,
              "T6.5 corpo nulo de comprimento zero e aceito (quadro so com cabecalho)");
        CHECK(mu2_frame_encode(probe, sizeof probe, 1u, body4, 4u, (mu2_profile)7) == MU2_E_PROFILE,
              "T6.6 perfil desconhecido e recusado na entrada");
    }

    /* --- T7: validacao do enquadramento na decodificacao --- */
    {
        mu2_frame f;
        const uint8_t *bp = NULL;
        memset(probe, 0x41u, sizeof probe);
        for (i = 0; i < MU2_HEADER_SIZE; i++) {
            int rc = mu2_frame_decode(&f, &bp, probe, i, MU2_PROFILE_ORIG);
            if (rc != MU2_E_INCOMPLETE || f.needed != MU2_HEADER_SIZE - i) {
                break;
            }
        }
        CHECK(i == MU2_HEADER_SIZE, "T7.1 todo prefixo menor que o cabecalho e INCOMPLETE com needed exato");

        probe[0] = 0u;
        probe[1] = 0u;
        probe[2] = 0u; /* size = 0 */
        probe[3] = 0u;
        CHECK(mu2_frame_decode(&f, &bp, probe, 16u, MU2_PROFILE_ORIG) == MU2_E_BAD_LEN,
              "T7.2 tamanho declarado 0 e recusado");
        probe[2] = 3u; /* size = 3 < header */
        CHECK(mu2_frame_decode(&f, &bp, probe, 16u, MU2_PROFILE_ORIG) == MU2_E_BAD_LEN,
              "T7.3 tamanho menor que o cabecalho e recusado");
        probe[2] = (uint8_t)(2053u & 0xFFu);
        probe[3] = (uint8_t)(2053u >> 8);
        CHECK(mu2_frame_decode(&f, &bp, probe, 4096u, MU2_PROFILE_ORIG) == MU2_E_BAD_LEN,
              "T7.4 tamanho acima de MU2_MAX_FRAME e recusado");
        probe[2] = (uint8_t)(MU2_MAX_FRAME & 0xFFu);
        probe[3] = (uint8_t)(MU2_MAX_FRAME >> 8);
        CHECK(mu2_frame_decode(&f, &bp, probe, 8u, MU2_PROFILE_ORIG) == MU2_E_INCOMPLETE &&
                  f.needed == MU2_MAX_FRAME - 8u,
              "T7.5 corpo ainda nao chegou inteiro: INCOMPLETE com needed = o que falta");
        CHECK(mu2_frame_decode(NULL, &bp, probe, 8u, MU2_PROFILE_ORIG) == MU2_E_ARG,
              "T7.6 quadro de saida nulo e recusado");
        CHECK(mu2_frame_decode(&f, &bp, NULL, 8u, MU2_PROFILE_ORIG) == MU2_E_ARG,
              "T7.7 stream nulo e recusado");
        CHECK(mu2_frame_decode(&f, &bp, probe, 8u, (mu2_profile)9) == MU2_E_PROFILE,
              "T7.8 perfil desconhecido e recusado antes de ler o stream");
    }

    /* --- T8: corpo extra depois do quadro nao e consumido --- */
    {
        uint8_t body[10];
        uint8_t wire[64];
        mu2_frame f;
        const uint8_t *bp = NULL;
        (void)fill(body, 10u);
        int n = mu2_frame_encode(wire, sizeof wire, 0x77u, body, 10u, MU2_PROFILE_MUR0);
        (void)memcpy(wire + n, "SOBRA", 5u);
        int rc = mu2_frame_decode(&f, &bp, wire, (size_t)n + 5u, MU2_PROFILE_MUR0);
        CHECK(rc == MU2_OK && f.frame_len == (uint16_t)n,
              "T8.1 decodificacao consome exatamente um quadro, nem mais nem menos");
        uint8_t back[64];
        CHECK(mu2_frame_body(back, sizeof back, &f, wire, MU2_PROFILE_MUR0) == 10 &&
                  memcmp(back, body, 10u) == 0,
              "T8.2 o corpo recuperado ignora os bytes que sobraram no buffer");
    }

    /* --- T9: separacao de perfis --- */
    {
        static const uint8_t body[8] = {9, 8, 7, 6, 5, 4, 3, 2};
        uint8_t w_orig[64], w_mur0[64];
        mu2_frame f;
        const uint8_t *bp = NULL;
        (void)mu2_frame_encode(w_orig, sizeof w_orig, 0x22u, body, 8u, MU2_PROFILE_ORIG);
        (void)mu2_frame_encode(w_mur0, sizeof w_mur0, 0x22u, body, 8u, MU2_PROFILE_MUR0);
        CHECK(memcmp(w_orig + MU2_HEADER_SIZE, w_mur0 + MU2_HEADER_SIZE, 8u) != 0,
              "T9.1 os dois perfis produzem bytes diferentes no mesmo corpo");
        CHECK(memcmp(w_orig + MU2_HEADER_SIZE, body, 8u) == 0,
              "T9.2 no perfil orig o corpo no stream e o proprio corpo");
        int rc = mu2_frame_decode(&f, &bp, w_mur0, 12u, MU2_PROFILE_ORIG);
        uint8_t back[64];
        (void)mu2_frame_body(back, sizeof back, &f, w_mur0, MU2_PROFILE_ORIG);
        CHECK(rc == MU2_OK && memcmp(back, body, 8u) != 0,
              "T9.3 ler um quadro mur0 como orig preserva o enquadramento e entrega corpo errado "
              "(por isso o perfil e obrigatorio no contrato, nao opcional)");
    }

    /* --- T10: caminho no lugar (dst == src + header) --- */
    {
        static const uint8_t body[5] = {1, 1, 2, 3, 5};
        uint8_t wire[64], copy[64];
        uint8_t back[64];
        mu2_frame f, f2;
        const uint8_t *bp = NULL;
        const uint8_t *bp2 = NULL;
        int n = mu2_frame_encode(wire, sizeof wire, 0x31u, body, 5u, MU2_PROFILE_MUR0);
        (void)memcpy(copy, wire, (size_t)n);
        (void)mu2_frame_decode(&f, &bp, wire, (size_t)n, MU2_PROFILE_MUR0);
        (void)mu2_frame_body(back, sizeof back, &f, wire, MU2_PROFILE_MUR0);
        (void)mu2_frame_decode(&f2, &bp2, copy, (size_t)n, MU2_PROFILE_MUR0);
        CHECK(memcmp(back, body, 5u) == 0, "T10.1 extracao do corpo no lugar restaura o original");
        (void)mu2_frame_body(copy + MU2_HEADER_SIZE, 64u, &f2, copy, MU2_PROFILE_MUR0);
        CHECK(memcmp(copy + MU2_HEADER_SIZE, back, 5u) == 0,
              "T10.2 os dois caminhos (copia e no lugar) dao o mesmo resultado");
    }

    /* --- T11: extremos de opcode --- */
    {
        static const uint8_t body[3] = {0xFFu, 0x00u, 0xAAu};
        for (k = 0; k < 2; k++) {
            CHECK(roundtrip_ok(0x0000u, body, 3u, k_prof[k]),
                  "T11.1 ida e volta com opcode 0x0000");
            CHECK(roundtrip_ok(0xFFFFu, body, 3u, k_prof[k]),
                  "T11.2 ida e volta com opcode 0xFFFF");
        }
    }

    /* --- T12: fuzz deterministico leve (mesma semente sempre) --- */
    {
        int bad = 0;
        int t;
        for (t = 0; t < 256; t++) {
            size_t len = (size_t)(nxt() | (nxt() << 8)) % (MU2_MAX_BODY + 1u);
            uint16_t code = (uint16_t)(nxt() | (nxt() << 8));
            mu2_profile p = (mu2_profile)(nxt() & 1u);
            (void)fill(big, len);
            if (!roundtrip_ok(code, big, len, p)) {
                bad++;
            }
        }
        CHECK(bad == 0, "T12 round-trip em 256 combinacoes deterministicas de tamanho/opcode/perfil");
    }

    /* --- T13: diagnostico --- */
    CHECK(mu2_errstr(MU2_OK) != NULL && mu2_errstr(MU2_E_BAD_LEN) != NULL,
          "T13.1 todo codigo de erro tem descricao legivel");
    CHECK(strcmp(mu2_errstr(MU2_E_SIZE), mu2_errstr(MU2_E_BAD_LEN)) != 0 &&
              strcmp(mu2_errstr(MU2_E_INCOMPLETE), mu2_errstr(MU2_E_DST_SMALL)) != 0,
          "T13.2 as descricoes distinguem as causas que o laço de rede precisa separar");

    printf("1..%d\n# unit=%d falhas=%d\n", g_total, g_total, g_fail);
    return g_fail == 0 ? 0 : 1;
}

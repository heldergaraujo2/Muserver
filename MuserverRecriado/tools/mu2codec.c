/* mu2codec.c — interface de teste do codec v2 (fase: golden tests).
 *
 * Existe porque golden test que reimplementa o codec em Python/shell compara a reimplementacao
 * com ela mesma e nao prova nada. Esta CLI liga contra out/wire.o — o MESMO objeto que o servico
 * e o mu2ctl usam — entao o caminho exercitado e o caminho de producao.
 *
 * Nao sobe servico, nao abre socket, nao toca em MuServer/. Saida sempre em linhas chave=valor
 * para o teste classificar sem interpretar prosa.
 *
 * Codigos de saida:
 *   0  o codec devolveu MU2_OK
 *   4  o codec devolveu erro (rejeicao legitima: truncado, malformado, incompativel, argumento)
 *   2  uso incorreto da CLI (hex invalido, subcomando desconhecido, opcao faltando)
 * A distincao 0/4 importa: "o codec recusou" e um resultado, "eu chamei errado" e outro.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mu2/mu2.h"

#define MAX_IN 8192u

static int nibble(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

/* hex -> bytes. Devolve 0 e escreve *out_len, ou -1 se o hex for invalido (uso errado da CLI). */
static int unhex(const char *s, uint8_t *dst, size_t dst_len, size_t *out_len)
{
    size_t n = strlen(s), i;
    if ((n & 1u) != 0u)
        return -1; /* nibble solto nao e byte */
    if (n / 2u > dst_len)
        return -1;
    for (i = 0; i < n; i += 2u) {
        int hi = nibble(s[i]), lo = nibble(s[i + 1u]);
        if (hi < 0 || lo < 0)
            return -1;
        dst[i / 2u] = (uint8_t)((unsigned)hi << 4 | (unsigned)lo);
    }
    *out_len = n / 2u;
    return 0;
}

static void phex(const char *chave, const uint8_t *b, size_t n)
{
    size_t i;
    printf("%s=", chave);
    for (i = 0; i < n; i++)
        printf("%02x", (unsigned)b[i]);
    printf("\n");
}

/* Nome do erro, nao o numero: o corpus grava o nome, que sobrevive a renumeracao. */
static const char *err_name(int e)
{
    switch (e) {
    case MU2_OK:           return "MU2_OK";
    case MU2_E_ARG:        return "MU2_E_ARG";
    case MU2_E_SIZE:       return "MU2_E_SIZE";
    case MU2_E_DST_SMALL:  return "MU2_E_DST_SMALL";
    case MU2_E_INCOMPLETE: return "MU2_E_INCOMPLETE";
    case MU2_E_BAD_LEN:    return "MU2_E_BAD_LEN";
    case MU2_E_PROFILE:    return "MU2_E_PROFILE";
    default:               return "MU2_E_DESCONHECIDO";
    }
}

/* Classe do resultado: e o que o corpus compara, alem do hex. "incompativel" existe para o
 * perfil fora do conjunto — nao e quadro ruim, e selecao errada de perfil (F21). */
static const char *classe(int e)
{
    switch (e) {
    case MU2_OK:           return "valido";
    case MU2_E_INCOMPLETE: return "truncado";
    case MU2_E_BAD_LEN:    return "malformado";
    case MU2_E_PROFILE:    return "incompativel";
    case MU2_E_ARG:        return "argumento";
    case MU2_E_SIZE:       return "tamanho";
    case MU2_E_DST_SMALL:  return "destino";
    default:               return "desconhecido";
    }
}

static void uso(void)
{
    fprintf(stderr,
            "uso: mu2codec <encode|decode|body|roundtrip|transform> --profile orig|mur0 ...\n"
            "  encode     [--code N] [--body-hex HEX] [--dst-len N] [--null-body]\n"
            "  decode     --in-hex HEX  [--profile-num N]\n"
            "  body       --in-hex HEX  [--profile-num N]\n"
            "  roundtrip  [--code N] [--body-hex HEX]\n"
            "  transform  [--code N] [--body-hex HEX]\n");
}

int main(int argc, char **argv)
{
    const char *op;
    const char *perfil_s = NULL, *in_hex = NULL, *body_hex = "";
    const char *perfil_num_s = NULL, *code_s = NULL, *dst_len_s = NULL;
    int null_body = 0, i;
    mu2_profile perfil = MU2_PROFILE_ORIG;
    long perfil_num = -1;
    unsigned code = 0u;
    uint8_t in[MAX_IN], body[MU2_MAX_BODY + 1u], frame[MU2_MAX_FRAME + 64u];
    size_t in_len = 0u, body_len = 0u;
    int r;

    if (argc < 2) {
        uso();
        return 2;
    }
    op = argv[1];
    for (i = 2; i < argc; i++) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (strcmp(a, "--profile") == 0 && v != NULL) {
            perfil_s = v;
            i++;
        } else if (strcmp(a, "--profile-num") == 0 && v != NULL) {
            perfil_num_s = v;
            i++;
        } else if (strcmp(a, "--code") == 0 && v != NULL) {
            code_s = v;
            i++;
        } else if (strcmp(a, "--in-hex") == 0 && v != NULL) {
            in_hex = v;
            i++;
        } else if (strcmp(a, "--body-hex") == 0 && v != NULL) {
            body_hex = v;
            i++;
        } else if (strcmp(a, "--dst-len") == 0 && v != NULL) {
            dst_len_s = v;
            i++;
        } else if (strcmp(a, "--null-body") == 0) {
            null_body = 1;
        } else {
            fprintf(stderr, "mu2codec: opcao desconhecida ou sem valor: %s\n", a);
            uso();
            return 2;
        }
    }

    if (perfil_num_s != NULL) {
        /* Caminho explicito para perfil INVALIDO: sem ele, MU2_E_PROFILE seria intestavel pela
         * CLI e a classe "incompativel" existiria so no papel. */
        perfil_num = strtol(perfil_num_s, NULL, 10);
        if (perfil_num < 0 || perfil_num > 1000) {
            fprintf(stderr, "mu2codec: --profile-num fora de faixa\n");
            return 2;
        }
        perfil = (mu2_profile)perfil_num;
    } else if (perfil_s == NULL) {
        fprintf(stderr, "mu2codec: --profile e obrigatorio\n");
        uso();
        return 2;
    } else if (strcmp(perfil_s, "orig") == 0) {
        perfil = MU2_PROFILE_ORIG;
    } else if (strcmp(perfil_s, "mur0") == 0) {
        perfil = MU2_PROFILE_MUR0;
    } else {
        fprintf(stderr, "mu2codec: perfil desconhecido: %s\n", perfil_s);
        return 2;
    }
    if (code_s != NULL) {
        long c = strtol(code_s, NULL, 0);
        if (c < 0 || c > 0xFFFF) {
            fprintf(stderr, "mu2codec: --code fora de 0..65535\n");
            return 2;
        }
        code = (unsigned)c;
    }
    if (unhex(body_hex, body, sizeof body, &body_len) != 0) {
        fprintf(stderr, "mu2codec: --body-hex invalido\n");
        return 2;
    }
    if (in_hex != NULL && unhex(in_hex, in, sizeof in, &in_len) != 0) {
        fprintf(stderr, "mu2codec: --in-hex invalido\n");
        return 2;
    }

    printf("operacao=%s\n", op);
    printf("perfil=%s\n", mu2_profile_name(perfil));
    printf("perfil_valido=%d\n", mu2_profile_valid(perfil));

    if (strcmp(op, "encode") == 0) {
        size_t dst_len = sizeof frame;
        if (dst_len_s != NULL) {
            long d = strtol(dst_len_s, NULL, 10);
            if (d < 0 || d > (long)sizeof frame) {
                fprintf(stderr, "mu2codec: --dst-len fora de faixa\n");
                return 2;
            }
            dst_len = (size_t)d;
        }
        r = mu2_frame_encode(frame, dst_len, (uint16_t)code,
                             null_body != 0 ? NULL : body,
                             null_body != 0 ? 1u : body_len, perfil);
        printf("resultado=%s\n", r > 0 ? "OK" : "ERRO");
        if (r > 0) {
            phex("hex", frame, (size_t)r);
            printf("quadro_len=%d\n", r);
            return 0;
        }
        printf("erro=%s\n", err_name(r));
        printf("classe=%s\n", classe(r));
        return 4;
    }

    if (strcmp(op, "decode") == 0 || strcmp(op, "body") == 0) {
        mu2_frame f;
        const uint8_t *bout = NULL;
        if (in_hex == NULL) {
            fprintf(stderr, "mu2codec: %s exige --in-hex\n", op);
            return 2;
        }
        r = mu2_frame_decode(&f, &bout, in, in_len, perfil);
        printf("resultado=%s\n", r == MU2_OK ? "OK" : "ERRO");
        if (r != MU2_OK) {
            printf("erro=%s\n", err_name(r));
            printf("classe=%s\n", classe(r));
            printf("needed=%zu\n", f.needed);
            return 4;
        }
        /* Tupla canonica: e o que o corpus grava como esperado de decode. */
        printf("decode=%u:%u:%zu:%zu\n", (unsigned)f.code, (unsigned)f.frame_len, f.body_len,
               f.needed);
        if (strcmp(op, "decode") == 0) {
            if (bout != NULL)
                phex("corpo_no_stream", bout, f.body_len);
            return 0;
        }
        {   /* body: desfaz a transformacao do perfil. src e o INICIO do quadro (D2-17). */
            uint8_t out[MU2_MAX_BODY];
            int br = mu2_frame_body(out, sizeof out, &f, in, perfil);
            if (br < 0) {
                printf("erro=%s\n", err_name(br));
                printf("classe=%s\n", classe(br));
                return 4;
            }
            phex("corpo_hex", out, (size_t)br);
            return 0;
        }
    }

    if (strcmp(op, "transform") == 0) {
        uint8_t buf[MU2_MAX_BODY + 1u];
        memcpy(buf, body, body_len);
        mu2_body_transform(buf, body_len, (uint16_t)code, perfil);
        phex("hex", buf, body_len);
        printf("resultado=OK\n");
        return 0;
    }

    if (strcmp(op, "roundtrip") == 0) {
        mu2_frame f;
        const uint8_t *bout = NULL;
        uint8_t out[MU2_MAX_BODY];
        int br;
        r = mu2_frame_encode(frame, sizeof frame, (uint16_t)code, body, body_len, perfil);
        if (r <= 0) {
            printf("resultado=ERRO\nerro=%s\nclasse=%s\n", err_name(r), classe(r));
            return 4;
        }
        if (mu2_frame_decode(&f, &bout, frame, (size_t)r, perfil) != MU2_OK) {
            printf("resultado=ERRO\nclasse=malformado\n");
            return 4;
        }
        br = mu2_frame_body(out, sizeof out, &f, frame, perfil);
        if (br < 0) {
            printf("resultado=ERRO\nclasse=malformado\n");
            return 4;
        }
        phex("corpo_hex", out, (size_t)br);
        printf("resultado=OK\n");
        printf("roundtrip=%s\n",
               ((size_t)br == body_len && memcmp(out, body, body_len) == 0) ? "IGUAL" : "DIFERENTE");
        return (br == (int)body_len && memcmp(out, body, body_len) == 0) ? 0 : 4;
    }

    fprintf(stderr, "mu2codec: subcomando desconhecido: %s\n", op);
    uso();
    return 2;
}

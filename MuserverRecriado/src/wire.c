/* wire.c — enquadramento do v2 (fase R-3). Ver cabeca de include/mu2/mu2.h para a origem
 * do layout (D2-11/D2-12) e para o que este arquivo NAO afirma sobre o MuServer real. */
#include "mu2/mu2.h"

#include <string.h>

static const uint8_t k_xor[MU2_XOR_KEY_LEN] = {0xAEu, 0xECu, 0xD8u};

const char *mu2_profile_name(mu2_profile p)
{
    switch (p) {
    case MU2_PROFILE_ORIG:
        return "orig";
    case MU2_PROFILE_MUR0:
        return "mur0";
    default:
        return "?";
    }
}

int mu2_profile_valid(mu2_profile p)
{
    return (p == MU2_PROFILE_ORIG || p == MU2_PROFILE_MUR0) ? 1 : 0;
}

size_t mu2_frame_size(size_t body_len)
{
    if (body_len > (size_t)MU2_MAX_BODY) {
        return 0u;
    }
    return (size_t)MU2_HEADER_SIZE + body_len;
}

/* Depende da posicao e do opcode, nunca do conteudo: por isso a involucao e exata. */
static uint8_t xor_byte(size_t i, uint16_t code)
{
    unsigned shift = (unsigned)(i & 1u) * 8u;
    uint32_t wide = (uint32_t)code;
    return (uint8_t)(k_xor[i % (size_t)MU2_XOR_KEY_LEN] ^ (uint8_t)((wide >> shift) & 0xFFu));
}

void mu2_body_transform(uint8_t *buf, size_t len, uint16_t code, mu2_profile p)
{
    size_t i;
    if (buf == NULL || p != MU2_PROFILE_MUR0) {
        return; /* orig e identidade, por definicao do perfil */
    }
    for (i = 0; i < len; i++) {
        buf[i] = (uint8_t)(buf[i] ^ xor_byte(i, code));
    }
}

int mu2_frame_encode(uint8_t *dst, size_t dst_len, uint16_t code, const uint8_t *body,
                     size_t body_len, mu2_profile p)
{
    size_t total;
    uint16_t size16;

    if (!mu2_profile_valid(p)) {
        return MU2_E_PROFILE;
    }
    if (dst == NULL) {
        return MU2_E_ARG;
    }
    if (body == NULL && body_len != 0u) {
        return MU2_E_ARG;
    }
    if (body_len > (size_t)MU2_MAX_BODY) {
        return MU2_E_SIZE;
    }
    total = (size_t)MU2_HEADER_SIZE + body_len;
    if (dst_len < total) {
        return MU2_E_DST_SMALL;
    }
    size16 = (uint16_t)total; /* <= MU2_MAX_FRAME por construcao */
    dst[0] = (uint8_t)(code & 0xFFu);
    dst[1] = (uint8_t)((code >> 8) & 0xFFu);
    dst[2] = (uint8_t)(size16 & 0xFFu);
    dst[3] = (uint8_t)((size16 >> 8) & 0xFFu);
    if (body_len != 0u) {
        (void)memcpy(dst + MU2_HEADER_SIZE, body, body_len);
        mu2_body_transform(dst + MU2_HEADER_SIZE, body_len, code, p);
    }
    return (int)total;
}

int mu2_frame_decode(mu2_frame *f, const uint8_t **body_out, const uint8_t *src, size_t src_len,
                     mu2_profile p)
{
    uint16_t code;
    uint16_t size;

    if (f == NULL || src == NULL) {
        return MU2_E_ARG;
    }
    if (!mu2_profile_valid(p)) {
        return MU2_E_PROFILE;
    }
    f->code = 0u;
    f->frame_len = 0u;
    f->body_len = 0u;
    f->needed = 0u;
    if (src_len < (size_t)MU2_HEADER_SIZE) {
        f->needed = (size_t)MU2_HEADER_SIZE - src_len;
        return MU2_E_INCOMPLETE;
    }
    code = (uint16_t)((unsigned)src[0] | ((unsigned)src[1] << 8));
    size = (uint16_t)((unsigned)src[2] | ((unsigned)src[3] << 8));
    f->code = code;
    f->frame_len = size;
    if (size < (uint16_t)MU2_HEADER_SIZE || size > (uint16_t)MU2_MAX_FRAME) {
        return MU2_E_BAD_LEN;
    }
    f->body_len = (size_t)size - (size_t)MU2_HEADER_SIZE;
    if (src_len < (size_t)size) {
        f->needed = (size_t)size - src_len;
        return MU2_E_INCOMPLETE;
    }
    if (body_out != NULL) {
        *body_out = src + MU2_HEADER_SIZE;
    }
    return MU2_OK;
}

int mu2_frame_body(uint8_t *dst, size_t dst_len, const mu2_frame *f, const uint8_t *src,
                   mu2_profile p)
{
    if (dst == NULL || f == NULL || src == NULL) {
        return MU2_E_ARG;
    }
    if (!mu2_profile_valid(p)) {
        return MU2_E_PROFILE;
    }
    if (f->body_len > (size_t)MU2_MAX_BODY) {
        return MU2_E_BAD_LEN;
    }
    if (dst_len < f->body_len) {
        return MU2_E_DST_SMALL;
    }
    if (f->body_len == 0u) {
        return 0;
    }
    if (dst != src + MU2_HEADER_SIZE) {
        (void)memcpy(dst, src + MU2_HEADER_SIZE, f->body_len);
    }
    mu2_body_transform(dst, f->body_len, f->code, p);
    return (int)f->body_len;
}

const char *mu2_errstr(int err)
{
    switch (err) {
    case MU2_OK:
        return "ok";
    case MU2_E_ARG:
        return "argumento invalido";
    case MU2_E_SIZE:
        return "corpo acima de MU2_MAX_BODY";
    case MU2_E_DST_SMALL:
        return "destino menor que o quadro";
    case MU2_E_INCOMPLETE:
        return "quadro incompleto (ver needed)";
    case MU2_E_BAD_LEN:
        return "tamanho declarado incoerente";
    case MU2_E_PROFILE:
        return "perfil desconhecido";
    default:
        return "erro nao mapeado";
    }
}

/* mu2.h — contrato de enquadramento do v2 (fase R-3).
 *
 * Origem deste layout: decisao D2-11/D2-12 em docs/DECISIONS.md. NAO e o formato do
 * MuServer real recuperado, e nao e o formato do v1 (perdido com o sandbox): o pacote de
 * referencia deste workspace nao expoe enquadramento na camada Lua (Procura por
 * HEAD_SIZE/PacketSize/opcode em MuServer/Data/Script/System/ProtocolCore.lua retornou
 * zero ocorrencias), entao afirmar compatibilidade byte a byte seria invencao. A
 * compatibilidade com o ConnectServer real e pergunta da fase R-6, a ser respondida a
 * partir do binario, nao daqui.
 *
 * Unica restricao herdada de decisao anterior: D2-03 fixa MU2_MAX_BODY = 2048, e 2048
 * nao cabe no campo de tamanho de 1 byte do MU classico (max 255). Dai o comprimento ser
 * de 16 bits — consequencia medida, nao preferencia.
 */
#ifndef MU2_WIRE_H
#define MU2_WIRE_H

#include <stddef.h>
#include <stdint.h>

#define MU2_HEADER_SIZE 4u                    /* code(2, LE) + size(2, LE) */
#define MU2_MAX_BODY 2048u                    /* D2-03 */
#define MU2_MAX_FRAME (MU2_HEADER_SIZE + MU2_MAX_BODY)
#define MU2_XOR_KEY_LEN 3u

#ifdef __cplusplus
extern "C" {
#endif

/* Dois perfis de quadro (D2-04): mesmo enquadramento, corpos transformados de formas
 * distintas. Todo teste que enquadra roda nos dois, e a equivalencia funcional entre eles
 * e assercao obrigatoria — foi assim que o v1 evitou que "dois perfis" virassem um formato
 * com dois nomes. */
typedef enum {
    MU2_PROFILE_ORIG = 0, /* corpo cru */
    MU2_PROFILE_MUR0 = 1, /* corpo sob a involucao de D2-12 */
    MU2_PROFILE_COUNT = 2
} mu2_profile;

typedef enum {
    MU2_OK = 0,
    MU2_E_ARG = -1,         /* ponteiro nulo, perfil invalido */
    MU2_E_SIZE = -2,        /* corpo maior que MU2_MAX_BODY */
    MU2_E_DST_SMALL = -3,   /* destino nao comporta o quadro */
    MU2_E_INCOMPLETE = -4,  /* ainda nao ha quadro completo no buffer (ver needed) */
    MU2_E_BAD_LEN = -5,     /* tamanho declarado incoerente (< header, > max, ou < corpo) */
    MU2_E_PROFILE = -6      /* perfil fora do conjunto conhecido */
} mu2_err;

typedef struct {
    uint16_t code;      /* opcode declarado no quadro */
    uint16_t frame_len; /* tamanho total, cabecalho incluido */
    size_t body_len;    /* frame_len - MU2_HEADER_SIZE */
    size_t needed;      /* valido em MU2_E_INCOMPLETE: quantos bytes faltam */
} mu2_frame;

const char *mu2_profile_name(mu2_profile p);
int mu2_profile_valid(mu2_profile p);

/* Bytes totais de um quadro com body_len de corpo; 0 se o corpo excede o contrato. */
size_t mu2_frame_size(size_t body_len);

/* Involucao do perfil mur0 (D2-12): aplicar duas vezes restaura o original. Nao e cifra e
 * nao pretende ser: serve para manter dois caminhos de enquadramento vivos nos testes. */
void mu2_body_transform(uint8_t *buf, size_t len, uint16_t code, mu2_profile p);

/* Retorna o numero de bytes escritos em dst (>0) ou um mu2_err (<0). */
int mu2_frame_encode(uint8_t *dst, size_t dst_len, uint16_t code, const uint8_t *body,
                     size_t body_len, mu2_profile p);

/* Valida apenas o enquadramento (nao toca no corpo). Se o quadro estiver inteiro no buffer,
 * *body_out aponta para o corpo tal como esta no stream (pos-transformacao do perfil) e
 * f->frame_len e o numero de bytes consumidos — quem faz o laço de leitura decide sozinho
 * quanto avancar. Precisa de `needed` em qualquer outra ordem de bytes: e o que o laço usa
 * para pedir mais leitura. */
int mu2_frame_decode(mu2_frame *f, const uint8_t **body_out, const uint8_t *src, size_t src_len,
                     mu2_profile p);

/* Copia o corpo do quadro decodificado para dst, desfazendo a transformacao do perfil.
 * dst_len deve ser >= f->body_len. dst == src e permitido (transforma no lugar). */
int mu2_frame_body(uint8_t *dst, size_t dst_len, const mu2_frame *f, const uint8_t *src,
                   mu2_profile p);

const char *mu2_errstr(int err);

#ifdef __cplusplus
}
#endif

#endif /* MU2_WIRE_H */

/* db.c — persistencia do v2: contas, personagens, inventario (fase R-11, decisao D2-40).
 *
 * Ver include/mu2/db.h para o contrato e o limite declarado. Aqui ficam as decisoes de formato:
 *
 *   CABECALHO (64 bytes, no inicio do arquivo)
 *     u8  magic[8]      "MU2DB01\0"
 *     u32 schema_version
 *     u32 reservado (0)
 *     u64 next_conta_id / next_personagem_id / next_item_id    (atalho; a varredura re-deriva)
 *     u32 crc32c(offset 0..47)
 *     u8  reservado[12]
 *
 *   REGISTRO (32 bytes de cabecalho + payload)
 *     u32 len | u32 tipo | u64 tx | u64 seq | u32 crc32c(payload) | u8 res[4] | payload[len]
 *
 *   TRANSACAO: as operacoes de uma TX vivem em memoria; no commit elas vao para o arquivo
 *   seguidas de um registro TX_COMMIT com o mesmo tx, e so entao sao aplicadas ao estado. Assim
 *   o arquivo nunca contem metade "valida" de uma transacao: ou ha o TX_COMMIT, ou o conjunto
 *   inteiro e descartado na recuperacao. Duas escritas usam tx != 0; escrita avulsa vira uma
 *   transacao implicita de uma operacao.
 *
 * INTEGRIDADE: cada payload tem CRC32C proprio; o cabecalho tambem. `mu2db_verify` percorre o
 * arquivo sem aplicar nada e aponta o primeiro registro ruim.
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "mu2/db.h"

/* ------------------------------------------------------------------ limites internos */
#define MU2DB_CONTAS_MAX 4096u
#define MU2DB_PERS_MAX 4096u
#define MU2DB_ITENS_MAX 16384u
#define MU2DB_OPS_TX_MAX 512u
#define MU2DB_PAYLOAD_MAX 256u
#define MU2DB_REG_CAB 32u
#define MU2DB_CAB 64u

/* ------------------------------------------------------------------ tipos de registro */
enum {
    REG_CONTA_CRIAR = 1,
    REG_CONTA_SET_SENHA = 2,
    REG_PERS_CRIAR = 3,
    REG_PERS_APAGAR = 4,
    REG_PERS_MOVER = 5,
    REG_PERS_ZEN = 6,
    REG_PERS_PONTOS = 7,
    REG_PERS_NIVEL = 8,
    REG_INV_ADD = 9,
    REG_INV_MOVER = 10,
    REG_INV_REMOVER = 11,
    REG_TX_COMMIT = 12,
    REG_MIGRACAO = 13
};

#define MU2DB_PBKDF2_ITERS 20000u
#define MU2DB_SALT_LEN 16u
#define MU2DB_HASH_LEN 32u

/* ------------------------------------------------------------------ tipos internos */
typedef struct {
    uint32_t id;
    char nome[MU2DB_NOME_MAX + 1];
    uint8_t salt[MU2DB_SALT_LEN];
    uint32_t iters;
    uint8_t hash[MU2DB_HASH_LEN];
} conta_t;

typedef struct {
    uint32_t id;
    uint32_t conta_id;
    char nome[MU2DB_NOME_MAX + 1];
    uint8_t classe;
    uint16_t nivel;
    uint32_t forca, agilidade, vitalidade, energia;
    uint32_t zen;
    uint8_t mapa, x, y;
    uint32_t slot_item[MU2DB_SLOTS]; /* id do item; 0 = vazio */
} pers_t;

typedef struct {
    uint32_t id;
    uint32_t pers_id;
    uint16_t tipo;
    uint8_t nivel_item;
    uint8_t slot;
    uint8_t durabilidade;
    int vivo;
} item_t;

typedef struct {
    uint32_t tipo;
    uint64_t tx;
    uint8_t payload[MU2DB_PAYLOAD_MAX];
    uint32_t len;
} op_t;

struct mu2db {
    int fd;
    char caminho[512];
    uint32_t schema_version;

    conta_t contas[MU2DB_CONTAS_MAX];
    size_t n_contas;
    pers_t pers[MU2DB_PERS_MAX];
    size_t n_pers;
    item_t itens[MU2DB_ITENS_MAX];
    size_t n_itens;
    uint32_t next_conta, next_pers, next_item;

    int tx_ativa;
    uint64_t tx_atual;
    op_t *ops;
    size_t n_ops;

    uint64_t registros;
    uint64_t descartados;
    uint64_t seq;
};

/* ------------------------------------------------------------------ CRC32C (Castagnoli) */
static uint32_t crc_tabela[256];
static int crc_pronta;

static void crc_init(void)
{
    uint32_t i, j, c;
    if (crc_pronta)
        return;
    for (i = 0; i < 256; i++) {
        c = i;
        for (j = 0; j < 8; j++)
            c = (c & 1u) ? (0x82F63B78u ^ (c >> 1)) : (c >> 1);
        crc_tabela[i] = c;
    }
    crc_pronta = 1;
}

static uint32_t crc32c(const void *dados, size_t len)
{
    const uint8_t *p = dados;
    uint32_t c = 0xFFFFFFFFu;
    size_t i;
    crc_init();
    for (i = 0; i < len; i++)
        c = crc_tabela[(c ^ p[i]) & 0xFFu] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}

/* ------------------------------------------------------------------ SHA-256 / HMAC / PBKDF2 */
typedef struct {
    uint32_t h[8];
    uint64_t bits;
    uint8_t buf[64];
    size_t n;
} sha256_ctx;

static const uint32_t sha256_k[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u,
    0xab1c5ed5u, 0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu,
    0x9bdc06a7u, 0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu,
    0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
    0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u, 0xa2bfe8a1u, 0xa81a664bu,
    0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u,
    0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u,
    0xc67178f2u
};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void sha256_bloco(sha256_ctx *c, const uint8_t *p)
{
    uint32_t w[64], a, b, cc, d, e, f, g, h, t1, t2;
    int i;
    for (i = 0; i < 16; i++)
        w[i] = ((uint32_t)p[i * 4] << 24) | ((uint32_t)p[i * 4 + 1] << 16) |
               ((uint32_t)p[i * 4 + 2] << 8) | (uint32_t)p[i * 4 + 3];
    for (i = 16; i < 64; i++) {
        uint32_t s0 = ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    a = c->h[0]; b = c->h[1]; cc = c->h[2]; d = c->h[3];
    e = c->h[4]; f = c->h[5]; g = c->h[6]; h = c->h[7];
    for (i = 0; i < 64; i++) {
        uint32_t S1 = ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t S0 = ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22);
        uint32_t maj = (a & b) ^ (a & cc) ^ (b & cc);
        t1 = h + S1 + ch + sha256_k[i] + w[i];
        t2 = S0 + maj;
        h = g; g = f; f = e; e = d + t1;
        d = cc; cc = b; b = a; a = t1 + t2;
    }
    c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d;
    c->h[4] += e; c->h[5] += f; c->h[6] += g; c->h[7] += h;
}

static void sha256_init(sha256_ctx *c)
{
    c->h[0] = 0x6a09e667u; c->h[1] = 0xbb67ae85u; c->h[2] = 0x3c6ef372u; c->h[3] = 0xa54ff53au;
    c->h[4] = 0x510e527fu; c->h[5] = 0x9b05688cu; c->h[6] = 0x1f83d9abu; c->h[7] = 0x5be0cd19u;
    c->bits = 0; c->n = 0;
}

static void sha256_update(sha256_ctx *c, const void *dados, size_t len)
{
    const uint8_t *p = dados;
    c->bits += (uint64_t)len * 8u;
    while (len > 0) {
        size_t espaco = 64 - c->n;
        size_t usar = len < espaco ? len : espaco;
        memcpy(c->buf + c->n, p, usar);
        c->n += usar; p += usar; len -= usar;
        if (c->n == 64) { sha256_bloco(c, c->buf); c->n = 0; }
    }
}

static void sha256_final(sha256_ctx *c, uint8_t saida[32])
{
    uint64_t bits = c->bits;
    uint8_t pad = 0x80;
    uint8_t zero = 0;
    int i;
    sha256_update(c, &pad, 1);
    while (c->n != 56)
        sha256_update(c, &zero, 1);
    for (i = 7; i >= 0; i--) {
        uint8_t b = (uint8_t)((bits >> (i * 8)) & 0xFFu);
        sha256_update(c, &b, 1);
    }
    for (i = 0; i < 8; i++) {
        saida[i * 4]     = (uint8_t)(c->h[i] >> 24);
        saida[i * 4 + 1] = (uint8_t)(c->h[i] >> 16);
        saida[i * 4 + 2] = (uint8_t)(c->h[i] >> 8);
        saida[i * 4 + 3] = (uint8_t)(c->h[i]);
    }
}

static void sha256(const void *dados, size_t len, uint8_t saida[32])
{
    sha256_ctx c;
    sha256_init(&c);
    sha256_update(&c, dados, len);
    sha256_final(&c, saida);
}

static void hmac_sha256(const uint8_t *chave, size_t chave_len, const uint8_t *msg, size_t msg_len,
                        uint8_t saida[32])
{
    uint8_t k[64], ipad[64], opad[64], interno[32];
    sha256_ctx c;
    size_t i;

    memset(k, 0, sizeof k);
    if (chave_len > sizeof k)
        sha256(chave, chave_len, k);
    else
        memcpy(k, chave, chave_len);
    for (i = 0; i < 64; i++) { ipad[i] = k[i] ^ 0x36u; opad[i] = k[i] ^ 0x5Cu; }

    sha256_init(&c);
    sha256_update(&c, ipad, 64);
    sha256_update(&c, msg, msg_len);
    sha256_final(&c, interno);

    sha256_init(&c);
    sha256_update(&c, opad, 64);
    sha256_update(&c, interno, 32);
    sha256_final(&c, saida);
    memset(k, 0, sizeof k);
    memset(ipad, 0, sizeof ipad);
    memset(opad, 0, sizeof opad);
}

static void pbkdf2_sha256(const char *senha, const uint8_t *salt, size_t salt_len, uint32_t iters,
                          uint8_t saida[32])
{
    uint8_t u[32], t[32];
    uint32_t bloco = 1, i, j;
    uint8_t msg[64 + 4];
    size_t senha_len = strlen(senha);

    memcpy(msg, salt, salt_len);
    for (j = 0; j < 4; j++)
        msg[salt_len + j] = (uint8_t)((bloco >> (24 - j * 8)) & 0xFFu);
    hmac_sha256((const uint8_t *)senha, senha_len, msg, salt_len + 4, u);
    memcpy(t, u, 32);
    for (i = 1; i < iters; i++) {
        hmac_sha256((const uint8_t *)senha, senha_len, u, 32, u);
        for (j = 0; j < 32; j++)
            t[j] ^= u[j];
    }
    memcpy(saida, t, 32);
    memset(u, 0, sizeof u);
    memset(t, 0, sizeof t);
}

/* ------------------------------------------------------------------ exposto para teste */
void mu2db_teste_sha256(const void *dados, size_t len, uint8_t saida[32])
{
    sha256(dados, len, saida);
}

void mu2db_teste_pbkdf2(const char *senha, const uint8_t *salt, size_t salt_len, uint32_t iters,
                        uint8_t saida[32])
{
    pbkdf2_sha256(senha, salt, salt_len, iters, saida);
}

uint32_t mu2db_teste_crc32c(const void *dados, size_t len)
{
    return crc32c(dados, len);
}

static int ct_eq(const uint8_t *a, const uint8_t *b, size_t n)
{
    uint8_t dif = 0;
    size_t i;
    for (i = 0; i < n; i++)
        dif |= (uint8_t)(a[i] ^ b[i]);
    return dif == 0;
}

/* ------------------------------------------------------------------ E/S de baixo nivel */
static int escrever_completo(int fd, const uint8_t *p, size_t len, off_t off)
{
    size_t feito = 0;
    while (feito < len) {
        ssize_t r = pwrite(fd, p + feito, len - feito, off + (off_t)feito);
        if (r <= 0) {
            if (r < 0 && errno == EINTR)
                continue;
            return MU2DB_E_IO;
        }
        feito += (size_t)r;
    }
    return MU2DB_OK;
}

static int ler_completo(int fd, uint8_t *p, size_t len, off_t off)
{
    size_t feito = 0;
    while (feito < len) {
        ssize_t r = pread(fd, p + feito, len - feito, off + (off_t)feito);
        if (r == 0)
            return MU2DB_E_FORMATO; /* truncado */
        if (r < 0) {
            if (errno == EINTR)
                continue;
            return MU2DB_E_IO;
        }
        feito += (size_t)r;
    }
    return MU2DB_OK;
}

static void poe_u16(uint8_t *p, uint16_t v) { memcpy(p, &v, 2); }
static void poe_u32(uint8_t *p, uint32_t v) { memcpy(p, &v, 4); }
static void poe_u64(uint8_t *p, uint64_t v) { memcpy(p, &v, 8); }
static uint16_t le_u16(const uint8_t *p) { uint16_t v; memcpy(&v, p, 2); return v; }
static uint32_t le32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint64_t le64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }

static int gravar_cabecalho(mu2db *db)
{
    uint8_t cab[MU2DB_CAB];
    memset(cab, 0, sizeof cab);
    memcpy(cab, MU2DB_MAGIC, 8);
    poe_u32(cab + 8, MU2DB_SCHEMA_VERSION);
    poe_u32(cab + 12, 0);
    poe_u64(cab + 16, db->next_conta);
    poe_u64(cab + 24, db->next_pers);
    poe_u64(cab + 32, db->next_item);
    poe_u32(cab + 40, crc32c(cab, 40));
    return escrever_completo(db->fd, cab, sizeof cab, 0);
}

/* ------------------------------------------------------------------ erros */
const char *mu2db_errstr(int err)
{
    switch (err) {
    case MU2DB_OK: return "ok";
    case MU2DB_E_ARG: return "argumento invalido";
    case MU2DB_E_IO: return "falha de E/S";
    case MU2DB_E_FORMATO: return "formato invalido";
    case MU2DB_E_CRC: return "CRC divergente (corrupcao)";
    case MU2DB_E_TRAVADO: return "arquivo travado por outro processo";
    case MU2DB_E_CHEIO: return "inventario sem slot livre";
    case MU2DB_E_NAO_EXISTE: return "nao existe";
    case MU2DB_E_DUP: return "nome ja usado";
    case MU2DB_E_SENHA: return "senha invalida";
    case MU2DB_E_LIMITE: return "limite por conta excedido";
    case MU2DB_E_SEM_TX: return "escrita fora de transacao";
    case MU2DB_E_SLOT: return "slot invalido";
    default: return "erro desconhecido";
    }
}

/* ------------------------------------------------------------------ aplicacao de operacoes */
static conta_t *acha_conta(mu2db *db, const char *nome)
{
    size_t i;
    for (i = 0; i < db->n_contas; i++)
        if (strcmp(db->contas[i].nome, nome) == 0)
            return &db->contas[i];
    return NULL;
}

static conta_t *acha_conta_id(mu2db *db, uint32_t id)
{
    size_t i;
    for (i = 0; i < db->n_contas; i++)
        if (db->contas[i].id == id)
            return &db->contas[i];
    return NULL;
}

static pers_t *acha_pers(mu2db *db, uint32_t id)
{
    size_t i;
    for (i = 0; i < db->n_pers; i++)
        if (db->pers[i].id == id)
            return &db->pers[i];
    return NULL;
}

static pers_t *acha_pers_nome(mu2db *db, uint32_t conta_id, const char *nome)
{
    size_t i;
    for (i = 0; i < db->n_pers; i++)
        if (db->pers[i].conta_id == conta_id && strcmp(db->pers[i].nome, nome) == 0)
            return &db->pers[i];
    return NULL;
}

static item_t *acha_item(mu2db *db, uint32_t id)
{
    size_t i;
    for (i = 0; i < db->n_itens; i++)
        if (db->itens[i].vivo && db->itens[i].id == id)
            return &db->itens[i];
    return NULL;
}

static int aplica_operacao(mu2db *db, uint32_t tipo, const uint8_t *p, uint32_t len)
{
    switch (tipo) {
    case REG_CONTA_CRIAR: {
        conta_t *c;
        uint32_t id = le32(p);
        uint8_t nl = p[4];
        if (nl == 0 || nl > MU2DB_NOME_MAX || len < 5u + nl + MU2DB_SALT_LEN + 4u + MU2DB_HASH_LEN)
            return MU2DB_E_FORMATO;
        if (db->n_contas >= MU2DB_CONTAS_MAX)
            return MU2DB_E_CHEIO;
        c = &db->contas[db->n_contas++];
        memset(c, 0, sizeof *c);
        c->id = id;
        memcpy(c->nome, p + 5, nl);
        c->nome[nl] = '\0';
        memcpy(c->salt, p + 5 + nl, MU2DB_SALT_LEN);
        c->iters = le32(p + 5 + nl + MU2DB_SALT_LEN);
        memcpy(c->hash, p + 5 + nl + MU2DB_SALT_LEN + 4, MU2DB_HASH_LEN);
        if (id >= db->next_conta)
            db->next_conta = id + 1;
        return MU2DB_OK;
    }
    case REG_CONTA_SET_SENHA: {
        conta_t *c = acha_conta_id(db, le32(p));
        if (c == NULL)
            return MU2DB_E_NAO_EXISTE;
        memcpy(c->salt, p + 4, MU2DB_SALT_LEN);
        c->iters = le32(p + 4 + MU2DB_SALT_LEN);
        memcpy(c->hash, p + 4 + MU2DB_SALT_LEN + 4, MU2DB_HASH_LEN);
        return MU2DB_OK;
    }
    case REG_PERS_CRIAR: {
        pers_t *pp;
        uint32_t id = le32(p), conta_id = le32(p + 4);
        uint8_t classe = p[8], nl = p[9];
        if (nl == 0 || nl > MU2DB_NOME_MAX || len < 10u + nl)
            return MU2DB_E_FORMATO;
        if (db->n_pers >= MU2DB_PERS_MAX)
            return MU2DB_E_CHEIO;
        pp = &db->pers[db->n_pers++];
        memset(pp, 0, sizeof *pp);
        pp->id = id;
        pp->conta_id = conta_id;
        pp->classe = classe;
        pp->nivel = 1;
        pp->forca = 18; pp->agilidade = 18; pp->vitalidade = 18; pp->energia = 18;
        pp->zen = 0;
        pp->mapa = 0; pp->x = 125; pp->y = 125;
        memcpy(pp->nome, p + 10, nl);
        pp->nome[nl] = '\0';
        if (id >= db->next_pers)
            db->next_pers = id + 1;
        return MU2DB_OK;
    }
    case REG_PERS_APAGAR: {
        pers_t *pp = acha_pers(db, le32(p));
        size_t i;
        if (pp == NULL)
            return MU2DB_E_NAO_EXISTE;
        pp->conta_id = 0; /* marcado; a compactacao e a proxima fase (ver docs/DATABASE.md) */
        pp->nome[0] = '\0';
        for (i = 0; i < MU2DB_SLOTS; i++)
            pp->slot_item[i] = 0;
        return MU2DB_OK;
    }
    case REG_PERS_MOVER: {
        pers_t *pp = acha_pers(db, le32(p));
        if (pp == NULL)
            return MU2DB_E_NAO_EXISTE;
        pp->mapa = p[4]; pp->x = p[5]; pp->y = p[6];
        return MU2DB_OK;
    }
    case REG_PERS_ZEN: {
        pers_t *pp = acha_pers(db, le32(p));
        if (pp == NULL)
            return MU2DB_E_NAO_EXISTE;
        pp->zen = le32(p + 4);
        return MU2DB_OK;
    }
    case REG_PERS_PONTOS: {
        pers_t *pp = acha_pers(db, le32(p));
        if (pp == NULL)
            return MU2DB_E_NAO_EXISTE;
        pp->forca += le32(p + 4);
        pp->agilidade += le32(p + 8);
        pp->vitalidade += le32(p + 12);
        pp->energia += le32(p + 16);
        return MU2DB_OK;
    }
    case REG_PERS_NIVEL: {
        pers_t *pp = acha_pers(db, le32(p));
        uint16_t nivel = le_u16(p + 4);
        if (pp == NULL)
            return MU2DB_E_NAO_EXISTE;
        if (nivel < pp->nivel)
            return MU2DB_E_ARG; /* nivel so sobe; decida e teste antes de permitir descida */
        pp->nivel = nivel;
        return MU2DB_OK;
    }
    case REG_INV_ADD: {
        pers_t *pp = acha_pers(db, le32(p + 4));
        uint32_t item_id = le32(p);
        uint8_t slot = p[11];
        item_t *it;
        if (pp == NULL)
            return MU2DB_E_NAO_EXISTE;
        if (slot >= MU2DB_SLOTS || pp->slot_item[slot] != 0)
            return MU2DB_E_CHEIO;
        if (db->n_itens >= MU2DB_ITENS_MAX)
            return MU2DB_E_CHEIO;
        it = &db->itens[db->n_itens++];
        memset(it, 0, sizeof *it);
        it->id = item_id;
        it->pers_id = pp->id;
        it->tipo = le_u16(p + 8);
        it->nivel_item = p[10];
        it->slot = slot;
        it->durabilidade = p[12];
        it->vivo = 1;
        pp->slot_item[slot] = item_id;
        if (item_id >= db->next_item)
            db->next_item = item_id + 1;
        return MU2DB_OK;
    }
    case REG_INV_MOVER: {
        pers_t *pp = acha_pers(db, le32(p));
        uint8_t de = p[4], para = p[5];
        item_t *it;
        if (pp == NULL)
            return MU2DB_E_NAO_EXISTE;
        if (de >= MU2DB_SLOTS || para >= MU2DB_SLOTS)
            return MU2DB_E_SLOT;
        if (pp->slot_item[de] == 0)
            return MU2DB_E_NAO_EXISTE;
        if (pp->slot_item[para] != 0)
            return MU2DB_E_CHEIO;
        pp->slot_item[para] = pp->slot_item[de];
        pp->slot_item[de] = 0;
        it = acha_item(db, pp->slot_item[para]);
        if (it != NULL)
            it->slot = para;
        return MU2DB_OK;
    }
    case REG_INV_REMOVER: {
        pers_t *pp = acha_pers(db, le32(p));
        uint8_t slot = p[4];
        item_t *it;
        if (pp == NULL)
            return MU2DB_E_NAO_EXISTE;
        if (slot >= MU2DB_SLOTS)
            return MU2DB_E_SLOT;
        if (pp->slot_item[slot] == 0)
            return MU2DB_E_NAO_EXISTE;
        it = acha_item(db, pp->slot_item[slot]);
        if (it != NULL)
            it->vivo = 0;
        pp->slot_item[slot] = 0;
        return MU2DB_OK;
    }
    case REG_MIGRACAO:
        return MU2DB_OK;
    default:
        return MU2DB_E_FORMATO;
    }
}

/* ------------------------------------------------------------------ varredura / abertura */
static int varre(mu2db *db, off_t *fim_valido, char *erro, size_t erro_len, int aplicar);

static void estado_reset(mu2db *db)
{
    db->n_contas = 0;
    db->n_pers = 0;
    db->n_itens = 0;
    db->next_conta = 1;
    db->next_pers = 1;
    db->next_item = 1;
    db->registros = 0;
    db->descartados = 0;
    db->seq = 0;
}

/* Corta o arquivo em `fim`. Serve para DUAS coisas, e as duas ja causaram defeito real
 * (achado 2026-10-13 pelo teste de morte de processo em dbctl.sh):
 *   (a) log truncado no meio: o rabo sem commit tem de sair, senao uma transacao nova e gravada
 *       atras de lixo e o arquivo inteiro vira ilegivel;
 *   (b) transacao que morreu com registros completos mas SEM commit: se eles ficam no arquivo e o
 *       numero da TX se repete depois, a recuperacao REAPLICA os registros abandonados junto com os
 *       da TX nova — metade de uma operacao antiga volta a valer. Rollback de verdade e remover. */
static int trunca_ate(mu2db *db, off_t fim)
{
    struct stat st;
    if (fstat(db->fd, &st) != 0)
        return MU2DB_E_IO;
    if (fim >= st.st_size)
        return MU2DB_OK;
    if (ftruncate(db->fd, fim) != 0)
        return MU2DB_E_IO;
    return MU2DB_OK;
}

/* Reconstroi o estado lendo o arquivo: e o mecanismo do rollback (a TX nao esta no arquivo) e da
 * recuperacao de falha de escrita no commit. */
static int estado_rebuild(mu2db *db)
{
    off_t fim = 0;
    int r;
    estado_reset(db);
    r = varre(db, &fim, NULL, 0, 1);
    if (r != MU2DB_OK)
        return r;
    return trunca_ate(db, fim);
}
static int varre(mu2db *db, off_t *fim_valido, char *erro, size_t erro_len, int aplicar)
{
    off_t off = MU2DB_CAB;
    off_t fim_confirmado = MU2DB_CAB; /* fim do ultimo registro que faz parte de estado visivel */
    op_t *pend = NULL;
    size_t n_pend = 0, cap_pend = 64;
    uint64_t tx_pend = 0;
    int tem_pend = 0;

    pend = malloc(cap_pend * sizeof *pend);
    if (pend == NULL)
        return MU2DB_E_IO;

    for (;;) {
        uint8_t cab[MU2DB_REG_CAB];
        uint32_t len, tipo, crc_esp;
        uint64_t tx, seq;
        uint8_t payload[MU2DB_PAYLOAD_MAX];
        int r = ler_completo(db->fd, cab, sizeof cab, off);
        if (r != MU2DB_OK)
            break; /* fim do arquivo (ou truncado no cabecalho): log valido termina aqui */
        len = le32(cab);
        tipo = le32(cab + 4);
        tx = le64(cab + 8);
        seq = le64(cab + 16);
        crc_esp = le32(cab + 24);
        if (len == 0 || len > MU2DB_PAYLOAD_MAX || tipo == 0) {
            if (erro && erro_len)
                snprintf(erro, erro_len, "registro %llu invalido em offset %lld",
                         (unsigned long long)db->registros, (long long)off);
            break;
        }
        r = ler_completo(db->fd, payload, len, off + MU2DB_REG_CAB);
        if (r != MU2DB_OK)
            break;
        if (crc32c(payload, len) != crc_esp) {
            if (erro && erro_len)
                snprintf(erro, erro_len, "CRC divergente no registro %llu (offset %lld)",
                         (unsigned long long)db->registros, (long long)off);
            free(pend);
            return MU2DB_E_CRC;
        }
        off += (off_t)(MU2DB_REG_CAB + len);
        db->registros++;
        if (seq > db->seq)
            db->seq = seq;
        /* o proximo numero de TX tem de ser MAIOR que qualquer um que ja passou pelo arquivo:
         * reusar numero faz a recuperacao casar registros abandonados com a transacao nova. */
        if (tx > db->tx_atual)
            db->tx_atual = tx;

        if (tipo == REG_TX_COMMIT) {
            size_t i;
            if (aplicar) {
                for (i = 0; i < n_pend; i++)
                    if (aplica_operacao(db, pend[i].tipo, pend[i].payload, pend[i].len) != MU2DB_OK) {
                        /* estado inconsistente no log: e defeito nosso, nao do arquivo */
                        free(pend);
                        return MU2DB_E_FORMATO;
                    }
            }
            n_pend = 0; tem_pend = 0;
            fim_confirmado = off; /* so aqui a transacao passa a existir para quem reabrir */
            continue;
        }
        if (tx != 0) {
            if (!tem_pend) { tem_pend = 1; tx_pend = tx; }
            if (tx != tx_pend) { /* TX anterior sem commit: descartada */
                db->descartados += n_pend;
                n_pend = 0; tx_pend = tx;
            }
            if (n_pend == cap_pend) {
                size_t nova = cap_pend * 2;
                op_t *novo = realloc(pend, nova * sizeof *pend);
                if (novo == NULL) { free(pend); return MU2DB_E_IO; }
                pend = novo; cap_pend = nova;
            }
            pend[n_pend].tipo = tipo;
            pend[n_pend].tx = tx;
            pend[n_pend].len = len;
            memcpy(pend[n_pend].payload, payload, len);
            n_pend++;
        } else {
            /* transacao implicita de uma operacao: vale na hora (o registro basta) */
            if (aplicar && aplica_operacao(db, tipo, payload, len) != MU2DB_OK) {
                free(pend);
                return MU2DB_E_FORMATO;
            }
            fim_confirmado = off;
        }
    }
    if (n_pend > 0) { /* ficou sem commit (corte no meio): descartada, e isso e o rollback */
        db->descartados += n_pend;
        if (erro && erro_len && erro[0] == '\0')
            snprintf(erro, erro_len, "%zu operacao(oes) de transacao incompleta descartada(s)",
                     n_pend);
    }
    free(pend);
    if (fim_valido != NULL)
        *fim_valido = fim_confirmado;
    return MU2DB_OK;
}

mu2db *mu2db_abrir(const char *caminho, char *erro, size_t erro_len)
{
    mu2db *db;
    uint8_t cab[MU2DB_CAB];
    struct stat st;
    off_t fim = 0;
    int novo = 0;

    if (erro && erro_len)
        erro[0] = '\0';
    if (caminho == NULL)
        return NULL;

    db = calloc(1, sizeof *db);
    if (db == NULL)
        return NULL;
    snprintf(db->caminho, sizeof db->caminho, "%s", caminho);
    db->tx_ativa = 0;

    db->fd = open(caminho, O_RDWR);
    if (db->fd < 0) {
        if (errno != ENOENT) {
            if (erro && erro_len)
                snprintf(erro, erro_len, "open: %s", strerror(errno));
            free(db);
            return NULL;
        }
        db->fd = open(caminho, O_RDWR | O_CREAT | O_EXCL, 0600);
        if (db->fd < 0) {
            if (erro && erro_len)
                snprintf(erro, erro_len, "create: %s", strerror(errno));
            free(db);
            return NULL;
        }
        novo = 1;
    }

    /* um escritor por arquivo: lock NAO bloqueante; segunda abertura falha nomeada */
    if (flock(db->fd, LOCK_EX | LOCK_NB) != 0) {
        if (erro && erro_len)
            snprintf(erro, erro_len, "flock: %s", MU2DB_E_TRAVADO == 0 ? "?" : "arquivo em uso");
        close(db->fd);
        free(db);
        return NULL;
    }

    db->next_conta = 1; db->next_pers = 1; db->next_item = 1;
    db->schema_version = MU2DB_SCHEMA_VERSION;

    if (novo) {
        if (gravar_cabecalho(db) != MU2DB_OK) {
            if (erro && erro_len) snprintf(erro, erro_len, "cabecalho: falha de E/S");
            close(db->fd); free(db); return NULL;
        }
        (void)fsync(db->fd);
        return db;
    }

    if (fstat(db->fd, &st) != 0 || st.st_size < MU2DB_CAB) {
        if (erro && erro_len) snprintf(erro, erro_len, "arquivo menor que o cabecalho");
        close(db->fd); free(db); return NULL;
    }
    if (ler_completo(db->fd, cab, MU2DB_CAB, 0) != MU2DB_OK ||
        memcmp(cab, MU2DB_MAGIC, 8) != 0) {
        if (erro && erro_len) snprintf(erro, erro_len, "magic invalido (nao e arquivo MU2DB)");
        close(db->fd); free(db); return NULL;
    }
    if (crc32c(cab, 40) != le32(cab + 40)) {
        if (erro && erro_len) snprintf(erro, erro_len, "CRC do cabecalho divergente");
        close(db->fd); free(db); return NULL;
    }
    db->schema_version = le32(cab + 8);
    if (db->schema_version > MU2DB_SCHEMA_VERSION) {
        if (erro && erro_len)
            snprintf(erro, erro_len, "schema %u mais novo que o suportado (%u)",
                     db->schema_version, MU2DB_SCHEMA_VERSION);
        close(db->fd); free(db); return NULL;
    }

    {
        int r = varre(db, &fim, erro, erro_len, 1);
        if (r == MU2DB_E_CRC) {
            close(db->fd); free(db); return NULL;
        }
        if (r != MU2DB_OK) {
            if (erro && erro_len) snprintf(erro, erro_len, "varredura: %s", mu2db_errstr(r));
            close(db->fd); free(db); return NULL;
        }
    }
    /* corte no meio do log: trunca ate o ultimo registro valido para novas escritas nao ficarem
     * atras de lixo. Nada valido e perdido: o que ficou fora nao tinha commit. */
    if (trunca_ate(db, fim) != MU2DB_OK) {
        if (erro && erro_len) snprintf(erro, erro_len, "ftruncate: %s", strerror(errno));
        close(db->fd); free(db); return NULL;
    }
    (void)gravar_cabecalho(db);
    return db;
}

void mu2db_fechar(mu2db *db)
{
    if (db == NULL)
        return;
    (void)gravar_cabecalho(db);
    (void)fsync(db->fd);
    if (db->ops != NULL)
        free(db->ops);
    flock(db->fd, LOCK_UN);
    close(db->fd);
    free(db);
}

int mu2db_stats_get(const mu2db *db, mu2db_stats *fora)
{
    struct stat st;
    size_t i;
    uint64_t vivos = 0, pers_vivos = 0, itens_vivos = 0;
    if (db == NULL || fora == NULL)
        return MU2DB_E_ARG;
    for (i = 0; i < db->n_contas; i++)
        if (db->contas[i].id != 0 && db->contas[i].nome[0] != '\0')
            vivos++;
    for (i = 0; i < db->n_pers; i++)
        if (db->pers[i].id != 0 && db->pers[i].nome[0] != '\0')
            pers_vivos++;
    for (i = 0; i < db->n_itens; i++)
        if (db->itens[i].vivo)
            itens_vivos++;
    memset(fora, 0, sizeof *fora);
    fora->contas = vivos;
    fora->personagens = pers_vivos;
    fora->itens = itens_vivos;
    fora->registros = db->registros;
    fora->descartados = db->descartados;
    fora->schema_version = db->schema_version;
    if (fstat(db->fd, &st) == 0)
        fora->bytes = (uint64_t)st.st_size;
    return MU2DB_OK;
}

int mu2db_verify(const char *caminho, char *detalhe, size_t detalhe_len)
{
    int fd, r;
    uint8_t cab[MU2DB_CAB];
    mu2db tmp;
    off_t fim = 0;

    if (caminho == NULL)
        return MU2DB_E_ARG;
    if (detalhe && detalhe_len)
        detalhe[0] = '\0';
    fd = open(caminho, O_RDONLY);
    if (fd < 0)
        return MU2DB_E_IO;
    r = ler_completo(fd, cab, MU2DB_CAB, 0);
    if (r != MU2DB_OK || memcmp(cab, MU2DB_MAGIC, 8) != 0) {
        close(fd);
        if (detalhe && detalhe_len)
            snprintf(detalhe, detalhe_len, "cabecalho ausente ou magic invalido");
        return MU2DB_E_FORMATO;
    }
    if (crc32c(cab, 40) != le32(cab + 40)) {
        close(fd);
        if (detalhe && detalhe_len)
            snprintf(detalhe, detalhe_len, "CRC do cabecalho divergente");
        return MU2DB_E_CRC;
    }
    memset(&tmp, 0, sizeof tmp);
    tmp.fd = fd;
    tmp.schema_version = le32(cab + 8);
    r = varre(&tmp, &fim, detalhe, detalhe_len, 0);
    close(fd);
    return r;
}

/* ------------------------------------------------------------------ transacoes */
int mu2db_tx_begin(mu2db *db)
{
    if (db == NULL)
        return MU2DB_E_ARG;
    if (db->tx_ativa)
        return MU2DB_E_ARG; /* aninhamento nao existe: decida e teste antes de permitir */
    if (db->ops == NULL) {
        db->ops = malloc(MU2DB_OPS_TX_MAX * sizeof *db->ops);
        if (db->ops == NULL)
            return MU2DB_E_IO;
    }
    db->tx_ativa = 1;
    db->tx_atual++;
    db->n_ops = 0;
    return MU2DB_OK;
}

/* ---- gancho de teste: morte REAL no meio de uma transacao ------------------------------------
 * MU2DB_TESTE_ABORTA_APOS=<n>: depois de gravar o n-esimo registro desta execucao o processo
 * termina com _exit(), SEM atexit/fflush/fechar arquivo. E a unica forma honesta de testar
 * recuperacao: truncar o arquivo testa o que NOS escrevemos, nao o que o SO ja tinha em disco
 * quando o processo morreu. Ausente ou 0 = desligado; nada fora dos testes usa isto. */
#define MU2DB_TESTE_SAIDA 97
static long teste_aborta_apos(void)
{
    static long limite = -1;
    if (limite < 0) {
        const char *v = getenv("MU2DB_TESTE_ABORTA_APOS");
        limite = (v != NULL) ? strtol(v, NULL, 10) : 0;
    }
    return limite;
}

static int grava_ops(mu2db *db, const op_t *ops, size_t n, uint64_t tx)
{
    uint8_t cab[MU2DB_REG_CAB];
    size_t i;
    off_t off;

    if (lseek(db->fd, 0, SEEK_END) < 0)
        return MU2DB_E_IO;
    off = lseek(db->fd, 0, SEEK_CUR);
    for (i = 0; i < n; i++) {
        memset(cab, 0, sizeof cab);
        poe_u32(cab, ops[i].len);
        poe_u32(cab + 4, ops[i].tipo);
        poe_u64(cab + 8, tx);
        poe_u64(cab + 16, ++db->seq);
        poe_u32(cab + 24, crc32c(ops[i].payload, ops[i].len));
        if (escrever_completo(db->fd, cab, sizeof cab, off) != MU2DB_OK)
            return MU2DB_E_IO;
        off += (off_t)sizeof cab;
        if (escrever_completo(db->fd, ops[i].payload, ops[i].len, off) != MU2DB_OK)
            return MU2DB_E_IO;
        off += (off_t)ops[i].len;
        db->registros++;
        if (teste_aborta_apos() != 0 && db->registros >= (uint64_t)teste_aborta_apos())
            _exit(MU2DB_TESTE_SAIDA);   /* gancho de teste: morre com a TX pela metade */
    }
    /* marcador de commit: e ele que torna a transacao visivel na recuperacao */
    memset(cab, 0, sizeof cab);
    poe_u32(cab, 8);   /* BUGFIX 2026-10-13: era 4 e o payload tem 8 bytes (tx) — o len mentia e o
                        * CRC do registro de commit nunca conferia na volta */
    poe_u32(cab + 4, REG_TX_COMMIT);
    poe_u64(cab + 8, tx);
    poe_u64(cab + 16, ++db->seq);
    {
        uint8_t payload[8];
        poe_u64(payload, tx);
        poe_u32(cab + 24, crc32c(payload, 8));
        if (escrever_completo(db->fd, cab, sizeof cab, off) != MU2DB_OK)
            return MU2DB_E_IO;
        off += (off_t)sizeof cab;
        if (escrever_completo(db->fd, payload, 8, off) != MU2DB_OK)
            return MU2DB_E_IO;
        off += 8;
        db->registros++;
    }
    return MU2DB_OK;
}

static int registra(mu2db *db, uint32_t tipo, const uint8_t *payload, uint32_t len)
{
    int r;
    if (len == 0 || len > MU2DB_PAYLOAD_MAX)
        return MU2DB_E_ARG;
    if (db->tx_ativa) {
        op_t *o;
        if (db->n_ops >= MU2DB_OPS_TX_MAX)
            return MU2DB_E_CHEIO;
        /* aplica JÁ: dentro da transacao as operacoes enxergam umas as outras (criar personagem e
         * por item nele na mesma TX e o caso de uso real). O arquivo so recebe no commit; o
         * rollback reconstroi o estado lendo o arquivo, que nao tem nada da TX. */
        r = aplica_operacao(db, tipo, payload, len);
        if (r != MU2DB_OK)
            return r;
        o = &db->ops[db->n_ops++];
        o->tipo = tipo;
        o->tx = db->tx_atual;
        o->len = len;
        memcpy(o->payload, payload, len);
        return MU2DB_OK;
    }
    /* transacao implicita: grava e aplica */
    {
        op_t o;
        o.tipo = tipo;
        o.tx = 0;
        o.len = len;
        memcpy(o.payload, payload, len);
        r = grava_ops(db, &o, 1, 0);
        if (r != MU2DB_OK)
            return r;
    }
    return aplica_operacao(db, tipo, payload, len);
}

int mu2db_tx_commit(mu2db *db)
{
    int r;
    if (db == NULL || !db->tx_ativa)
        return MU2DB_E_SEM_TX;
    /* o estado em memoria ja tem as operacoes; agora elas vao para o arquivo com o marcador de
     * commit. Se a gravacao falhar, o estado e reconstruido do arquivo (sem a TX): nada de metade
     * aplicada em memoria que nao existe em disco. */
    r = grava_ops(db, db->ops, db->n_ops, db->tx_atual);
    if (r == MU2DB_OK && fsync(db->fd) != 0)
        r = MU2DB_E_IO;
    if (r != MU2DB_OK) {
        db->tx_ativa = 0;
        db->n_ops = 0;
        (void)estado_rebuild(db);
        return r;
    }
    db->tx_ativa = 0;
    db->n_ops = 0;
    return MU2DB_OK;
}

int mu2db_tx_rollback(mu2db *db)
{
    int r;
    if (db == NULL || !db->tx_ativa)
        return MU2DB_E_SEM_TX;
    /* Nada da TX foi para o arquivo: descartar as pendentes e reconstruir o estado do arquivo e a
     * definicao exata de rollback. */
    db->tx_ativa = 0;
    db->n_ops = 0;
    r = estado_rebuild(db);
    return r == MU2DB_OK ? MU2DB_OK : r;
}

/* ------------------------------------------------------------------ validacao de entrada */
static int nome_valido(const char *nome)
{
    size_t i, n;
    if (nome == NULL)
        return 0;
    n = strlen(nome);
    if (n < 3 || n > MU2DB_NOME_MAX)  /* dominio do v2: 3..20 — curto demais e recusado na entrada */
        return 0;
    for (i = 0; i < n; i++) {
        char c = nome[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
              c == '_' || c == '-'))
            return 0;
    }
    return 1;
}

static int senha_valida(const char *senha)
{
    size_t n;
    if (senha == NULL)
        return 0;
    n = strlen(senha);
    return n >= 6 && n <= MU2DB_SENHA_MAX;
}

static void salt_novo(uint8_t salt[MU2DB_SALT_LEN])
{
    FILE *f = fopen("/dev/urandom", "rb");
    size_t lido = 0;
    if (f != NULL) {
        lido = fread(salt, 1, MU2DB_SALT_LEN, f);
        fclose(f);
    }
    if (lido != MU2DB_SALT_LEN) {
        /* fallback: mistura de tempo e pid — pior, e declarado (nunca usar como padrao de qualidade) */
        uint64_t s = (uint64_t)time(NULL) ^ ((uint64_t)getpid() << 32);
        uint8_t buf[32], deriva[32];
        size_t i;
        for (i = 0; i < sizeof buf; i++) { s = s * 6364136223846793005ull + 1442695040888963407ull; buf[i] = (uint8_t)(s >> 33); }
        sha256(buf, sizeof buf, deriva);
        memcpy(salt, deriva, MU2DB_SALT_LEN);
        memset(deriva, 0, sizeof deriva);
    }
}

/* ------------------------------------------------------------------ contas */
int mu2db_conta_criar(mu2db *db, const char *nome, const char *senha, uint32_t *id_out)
{
    uint8_t p[4 + 1 + MU2DB_NOME_MAX + MU2DB_SALT_LEN + 4 + MU2DB_HASH_LEN];
    uint32_t id;
    conta_t *c;
    if (db == NULL || !nome_valido(nome) || !senha_valida(senha))
        return MU2DB_E_ARG;
    if (acha_conta(db, nome) != NULL)
        return MU2DB_E_DUP;
    id = db->next_conta;
    memset(p, 0, sizeof p);
    poe_u32(p, id);
    p[4] = (uint8_t)strlen(nome);
    memcpy(p + 5, nome, p[4]);
    salt_novo(p + 5 + p[4]);
    poe_u32(p + 5 + p[4] + MU2DB_SALT_LEN, MU2DB_PBKDF2_ITERS);
    pbkdf2_sha256(senha, p + 5 + p[4], MU2DB_SALT_LEN, MU2DB_PBKDF2_ITERS,
                  p + 5 + p[4] + MU2DB_SALT_LEN + 4);
    {
        int r = registra(db, REG_CONTA_CRIAR, p, 5u + p[4] + MU2DB_SALT_LEN + 4u + MU2DB_HASH_LEN);
        if (r != MU2DB_OK)
            return r;
    }
    if (!db->tx_ativa) {
        c = acha_conta(db, nome);
        if (c != NULL && id_out != NULL)
            *id_out = c->id;
    } else if (id_out != NULL) {
        *id_out = id; /* a TX ainda nao aplicou: o id reservado ja e conhecido */
    }
    return MU2DB_OK;
}

int mu2db_conta_set_senha(mu2db *db, const char *nome, const char *nova_senha)
{
    uint8_t p[4 + MU2DB_SALT_LEN + 4 + MU2DB_HASH_LEN];
    conta_t *c;
    if (db == NULL || !nome_valido(nome) || !senha_valida(nova_senha))
        return MU2DB_E_ARG;
    c = acha_conta(db, nome);
    if (c == NULL)
        return MU2DB_E_NAO_EXISTE;
    memset(p, 0, sizeof p);
    poe_u32(p, c->id);
    salt_novo(p + 4);
    poe_u32(p + 4 + MU2DB_SALT_LEN, MU2DB_PBKDF2_ITERS);
    pbkdf2_sha256(nova_senha, p + 4, MU2DB_SALT_LEN, MU2DB_PBKDF2_ITERS,
                  p + 4 + MU2DB_SALT_LEN + 4);
    return registra(db, REG_CONTA_SET_SENHA, p, sizeof p);
}

int mu2db_conta_autenticar(mu2db *db, const char *nome, const char *senha, uint32_t *id_out)
{
    conta_t *c;
    uint8_t tentativa[MU2DB_HASH_LEN];
    if (db == NULL || nome == NULL || senha == NULL)
        return MU2DB_E_ARG;
    c = acha_conta(db, nome);
    if (c == NULL) {
        /* tempo constante tambem no caminho de "conta inexistente": deriva um hash e descarta */
        uint8_t salt[16] = {0};
        pbkdf2_sha256(senha, salt, sizeof salt, MU2DB_PBKDF2_ITERS, tentativa);
        memset(tentativa, 0, sizeof tentativa);
        return MU2DB_E_SENHA;
    }
    pbkdf2_sha256(senha, c->salt, MU2DB_SALT_LEN, c->iters, tentativa);
    if (!ct_eq(tentativa, c->hash, MU2DB_HASH_LEN)) {
        memset(tentativa, 0, sizeof tentativa);
        return MU2DB_E_SENHA;
    }
    memset(tentativa, 0, sizeof tentativa);
    if (id_out != NULL)
        *id_out = c->id;
    return MU2DB_OK;
}

int mu2db_conta_existe(mu2db *db, const char *nome)
{
    if (db == NULL || nome == NULL)
        return MU2DB_E_ARG;
    return acha_conta(db, nome) != NULL ? 1 : 0;
}

/* ------------------------------------------------------------------ personagens */
int mu2db_personagem_criar(mu2db *db, const char *conta, const char *nome, uint8_t classe,
                           uint32_t *id_out)
{
    uint8_t p[4 + 4 + 1 + 1 + MU2DB_NOME_MAX];
    conta_t *c;
    uint32_t id = db->next_pers;
    size_t i, qtd = 0;

    if (db == NULL || !nome_valido(conta) || !nome_valido(nome) || classe > 5)
        return MU2DB_E_ARG;
    c = acha_conta(db, conta);
    if (c == NULL)
        return MU2DB_E_NAO_EXISTE;
    for (i = 0; i < db->n_pers; i++)
        if (db->pers[i].conta_id == c->id && db->pers[i].nome[0] != '\0')
            qtd++;
    if (qtd >= MU2DB_PERSONAGENS_MAX)
        return MU2DB_E_LIMITE;
    if (acha_pers_nome(db, c->id, nome) != NULL)
        return MU2DB_E_DUP;
    memset(p, 0, sizeof p);
    poe_u32(p, id);
    poe_u32(p + 4, c->id);
    p[8] = classe;
    p[9] = (uint8_t)strlen(nome);
    memcpy(p + 10, nome, p[9]);
    {
        int r = registra(db, REG_PERS_CRIAR, p, 10u + p[9]);
        if (r != MU2DB_OK)
            return r;
    }
    if (id_out != NULL)
        *id_out = id;
    return MU2DB_OK;
}

int mu2db_personagem_carregar(mu2db *db, const char *conta, const char *nome, mu2db_personagem *fora)
{
    conta_t *c;
    pers_t *pp;
    size_t i;
    if (db == NULL || nome == NULL || fora == NULL)
        return MU2DB_E_ARG;
    c = acha_conta(db, conta);
    if (c == NULL)
        return MU2DB_E_NAO_EXISTE;
    pp = acha_pers_nome(db, c->id, nome);
    if (pp == NULL)
        return MU2DB_E_NAO_EXISTE;
    memset(fora, 0, sizeof *fora);
    fora->id = pp->id;
    memcpy(fora->nome, pp->nome, sizeof fora->nome);
    fora->classe = pp->classe;
    fora->nivel = pp->nivel;
    fora->forca = pp->forca; fora->agilidade = pp->agilidade;
    fora->vitalidade = pp->vitalidade; fora->energia = pp->energia;
    fora->zen = pp->zen;
    fora->mapa = pp->mapa; fora->x = pp->x; fora->y = pp->y;
    fora->itens = 0;
    for (i = 0; i < MU2DB_SLOTS; i++)
        if (pp->slot_item[i] != 0)
            fora->itens++;
    return MU2DB_OK;
}

int mu2db_personagem_apagar(mu2db *db, const char *conta, const char *nome)
{
    conta_t *c;
    pers_t *pp;
    uint8_t p[4];
    if (db == NULL || nome == NULL)
        return MU2DB_E_ARG;
    c = acha_conta(db, conta);
    if (c == NULL)
        return MU2DB_E_NAO_EXISTE;
    pp = acha_pers_nome(db, c->id, nome);
    if (pp == NULL)
        return MU2DB_E_NAO_EXISTE;
    poe_u32(p, pp->id);
    return registra(db, REG_PERS_APAGAR, p, sizeof p);
}

int mu2db_personagem_listar(mu2db *db, const char *conta, char nomes[][MU2DB_NOME_MAX + 1],
                            size_t max, size_t *qtd_out)
{
    conta_t *c;
    size_t i, k = 0;
    if (db == NULL || conta == NULL || nomes == NULL || qtd_out == NULL)
        return MU2DB_E_ARG;
    c = acha_conta(db, conta);
    if (c == NULL)
        return MU2DB_E_NAO_EXISTE;
    for (i = 0; i < db->n_pers && k < max; i++) {
        if (db->pers[i].conta_id == c->id && db->pers[i].nome[0] != '\0') {
            memcpy(nomes[k], db->pers[i].nome, sizeof nomes[k]);
            k++;
        }
    }
    *qtd_out = k;
    return MU2DB_OK;
}

static int pers_id_requerido(mu2db *db, uint32_t id, pers_t **pp)
{
    if (id == 0)
        return MU2DB_E_ARG;
    *pp = acha_pers(db, id);
    return *pp == NULL ? MU2DB_E_NAO_EXISTE : MU2DB_OK;
}

int mu2db_personagem_mover(mu2db *db, uint32_t id, uint8_t mapa, uint8_t x, uint8_t y)
{
    uint8_t p[4 + 3];
    pers_t *pp;
    int r;
    if (db == NULL)
        return MU2DB_E_ARG;
    if (mapa > 100) /* dominio do v2: 0..100 (mapas do pacote vao alem; ver docs/DATABASE.md) */
        return MU2DB_E_ARG;
    r = pers_id_requerido(db, id, &pp);
    if (r != MU2DB_OK)
        return r;
    memset(p, 0, sizeof p);
    poe_u32(p, id); p[4] = mapa; p[5] = x; p[6] = y;
    return registra(db, REG_PERS_MOVER, p, sizeof p);
}

int mu2db_personagem_set_zen(mu2db *db, uint32_t id, uint32_t zen)
{
    uint8_t p[8];
    pers_t *pp;
    int r;
    if (db == NULL)
        return MU2DB_E_ARG;
    r = pers_id_requerido(db, id, &pp);
    if (r != MU2DB_OK)
        return r;
    poe_u32(p, id);
    poe_u32(p + 4, zen);
    return registra(db, REG_PERS_ZEN, p, sizeof p);
}

int mu2db_personagem_add_pontos(mu2db *db, uint32_t id, uint32_t forca, uint32_t agilidade,
                                uint32_t vitalidade, uint32_t energia)
{
    uint8_t p[4 + 16];
    pers_t *pp;
    int r;
    if (db == NULL)
        return MU2DB_E_ARG;
    if (forca > 100000u || agilidade > 100000u || vitalidade > 100000u || energia > 100000u)
        return MU2DB_E_ARG; /* teto do v2: valores absurdos sao recusados na entrada */
    r = pers_id_requerido(db, id, &pp);
    if (r != MU2DB_OK)
        return r;
    memset(p, 0, sizeof p);
    poe_u32(p, id);
    poe_u32(p + 4, forca); poe_u32(p + 8, agilidade);
    poe_u32(p + 12, vitalidade); poe_u32(p + 16, energia);
    return registra(db, REG_PERS_PONTOS, p, sizeof p);
}

int mu2db_personagem_up_nivel(mu2db *db, uint32_t id, uint16_t novo_nivel)
{
    uint8_t p[4 + 2];
    pers_t *pp;
    int r;
    if (db == NULL || novo_nivel == 0)
        return MU2DB_E_ARG;
    r = pers_id_requerido(db, id, &pp);
    if (r != MU2DB_OK)
        return r;
    if (novo_nivel <= pp->nivel)
        return MU2DB_E_ARG;
    poe_u32(p, id);
    poe_u16(p + 4, novo_nivel);
    return registra(db, REG_PERS_NIVEL, p, sizeof p);
}

/* ------------------------------------------------------------------ inventario */
static int primeiro_slot_livre(pers_t *pp, uint8_t *slot_out)
{
    size_t i;
    for (i = 0; i < MU2DB_SLOTS; i++)
        if (pp->slot_item[i] == 0) {
            *slot_out = (uint8_t)i;
            return MU2DB_OK;
        }
    return MU2DB_E_CHEIO;
}

int mu2db_inv_add(mu2db *db, uint32_t personagem_id, uint16_t tipo, uint8_t nivel_item,
                  uint8_t durabilidade, uint8_t *slot_out)
{
    uint8_t p[4 + 4 + 2 + 1 + 1 + 1];
    pers_t *pp;
    uint32_t item_id;
    uint8_t slot;
    int r;
    if (db == NULL || tipo == 0)
        return MU2DB_E_ARG;
    r = pers_id_requerido(db, personagem_id, &pp);
    if (r != MU2DB_OK)
        return r;
    r = primeiro_slot_livre(pp, &slot);
    if (r != MU2DB_OK)
        return r;
    item_id = db->next_item;
    memset(p, 0, sizeof p);
    poe_u32(p, item_id);
    poe_u32(p + 4, personagem_id);
    poe_u16(p + 8, tipo);
    p[10] = nivel_item;
    p[11] = slot;
    p[12] = durabilidade;
    r = registra(db, REG_INV_ADD, p, sizeof p);
    if (r != MU2DB_OK)
        return r;
    if (slot_out != NULL)
        *slot_out = slot;
    return MU2DB_OK;
}

int mu2db_inv_mover(mu2db *db, uint32_t personagem_id, uint8_t slot_de, uint8_t slot_para)
{
    uint8_t p[4 + 2];
    pers_t *pp;
    int r;
    if (db == NULL || slot_de >= MU2DB_SLOTS || slot_para >= MU2DB_SLOTS || slot_de == slot_para)
        return MU2DB_E_SLOT;
    r = pers_id_requerido(db, personagem_id, &pp);
    if (r != MU2DB_OK)
        return r;
    if (pp->slot_item[slot_de] == 0)
        return MU2DB_E_NAO_EXISTE;
    if (pp->slot_item[slot_para] != 0)
        return MU2DB_E_CHEIO;
    poe_u32(p, personagem_id);
    p[4] = slot_de;
    p[5] = slot_para;
    return registra(db, REG_INV_MOVER, p, sizeof p);
}

int mu2db_inv_remover(mu2db *db, uint32_t personagem_id, uint8_t slot)
{
    uint8_t p[4 + 1];
    pers_t *pp;
    int r;
    if (db == NULL || slot >= MU2DB_SLOTS)
        return MU2DB_E_SLOT;
    r = pers_id_requerido(db, personagem_id, &pp);
    if (r != MU2DB_OK)
        return r;
    if (pp->slot_item[slot] == 0)
        return MU2DB_E_NAO_EXISTE;
    poe_u32(p, personagem_id);
    p[4] = slot;
    return registra(db, REG_INV_REMOVER, p, sizeof p);
}

int mu2db_inv_contar(mu2db *db, uint32_t personagem_id, size_t *qtd_out)
{
    pers_t *pp;
    size_t i, k = 0;
    int r;
    if (db == NULL || qtd_out == NULL)
        return MU2DB_E_ARG;
    r = pers_id_requerido(db, personagem_id, &pp);
    if (r != MU2DB_OK)
        return r;
    for (i = 0; i < MU2DB_SLOTS; i++)
        if (pp->slot_item[i] != 0)
            k++;
    *qtd_out = k;
    return MU2DB_OK;
}

int mu2db_inv_listar(mu2db *db, uint32_t personagem_id, mu2db_item *fora, size_t max,
                     size_t *qtd_out)
{
    pers_t *pp;
    size_t i, k = 0;
    int r;
    if (db == NULL || fora == NULL || qtd_out == NULL)
        return MU2DB_E_ARG;
    r = pers_id_requerido(db, personagem_id, &pp);
    if (r != MU2DB_OK)
        return r;
    for (i = 0; i < MU2DB_SLOTS && k < max; i++) {
        item_t *it;
        if (pp->slot_item[i] == 0)
            continue;
        it = acha_item(db, pp->slot_item[i]);
        if (it == NULL)
            continue;
        memset(&fora[k], 0, sizeof fora[k]);
        fora[k].id = it->id;
        fora[k].tipo = it->tipo;
        fora[k].nivel_item = it->nivel_item;
        fora[k].slot = it->slot;
        fora[k].durabilidade = it->durabilidade;
        k++;
    }
    *qtd_out = k;
    return MU2DB_OK;
}

int mu2db_inv_transferir(mu2db *db, uint32_t de_personagem, uint8_t de_slot,
                         uint32_t para_personagem)
{
    pers_t *origem, *destino;
    uint32_t item_id;
    uint8_t destino_slot;
    int r;

    if (db == NULL || de_personagem == 0 || para_personagem == 0 ||
        de_personagem == para_personagem || de_slot >= MU2DB_SLOTS)
        return MU2DB_E_ARG;
    r = pers_id_requerido(db, de_personagem, &origem);
    if (r != MU2DB_OK)
        return r;
    r = pers_id_requerido(db, para_personagem, &destino);
    if (r != MU2DB_OK)
        return r;
    item_id = origem->slot_item[de_slot];
    if (item_id == 0)
        return MU2DB_E_NAO_EXISTE;
    r = primeiro_slot_livre(destino, &destino_slot);
    if (r != MU2DB_OK)
        return r;

    /* DUAS operacoes, UMA transacao: ou o item sai de um e entra no outro, ou nada muda. */
    if (!db->tx_ativa) {
        r = mu2db_tx_begin(db);
        if (r != MU2DB_OK)
            return r;
    }
    r = mu2db_inv_remover(db, de_personagem, de_slot);
    if (r == MU2DB_OK) {
        uint8_t p[4 + 4 + 2 + 1 + 1 + 1];
        item_t *it = acha_item(db, item_id);
        memset(p, 0, sizeof p);
        poe_u32(p, item_id);            /* preserva o id do item: transferencia, nao criacao */
        poe_u32(p + 4, para_personagem);
        poe_u16(p + 8, it != NULL ? it->tipo : 1);
        p[10] = it != NULL ? it->nivel_item : 0;
        p[11] = destino_slot;
        p[12] = it != NULL ? it->durabilidade : 0;
        r = registra(db, REG_INV_ADD, p, sizeof p);
    }
    if (r != MU2DB_OK) {
        (void)mu2db_tx_rollback(db);
        return r;
    }
    return mu2db_tx_commit(db);
}

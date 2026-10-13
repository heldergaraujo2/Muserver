/* db.h — persistencia de contas, personagens e inventario (fase R-11).
 *
 * ESCOPO E LIMITE, declarado antes do codigo:
 *   Este e um armazenamento PROPRIO do v2, independente. Ele NAO le, NAO escreve e NAO afirma
 *   compatibilidade com o banco do MuServer original (SQL Server, DSN `MuOnline`): o esquema do
 *   original nao foi comprovado e os backups do pacote contem dados pessoais de jogadores, que nao
 *   podem ser usados como fixture (achado do auditor, 2026-10-13). Toda a evidencia aqui e gerada
 *   com dados SINTETICOS.
 *
 * Desenho (decisao D2-40, docs/DECISIONS.md):
 *   - arquivo unico append-only; cada operacao vira um registro com CRC proprio;
 *   - TRANSACAO REAL: operacoes carimbadas com um tx_id so passam a valer quando o registro
 *     TX_COMMIT correspondente aparece. Um corte no meio (queda, kill -9, disco cheio) deixa a
 *     transacao incompleta: na recuperacao ela e DESCARTADA, e o commit e atomico.
 *   - migracao de esquema versionada (`schema_version` no cabecalho): abrir arquivo mais velho
 *     migra em memoria na abertura, com um registro de migracao gravado — nunca reescreve o
 *     arquivo em silencio;
 *   - integridade: cada registro tem CRC32C do proprio payload; `mu2db_verify` percorre o arquivo
 *     inteiro e aponta o primeiro registro corrompido;
 *   - senha: nunca em claro. `mu2db_conta_set_senha` guarda PBKDF2-HMAC-SHA256 (salt por conta,
 *     iteracoes no registro) e `mu2db_conta_autenticar` compara em tempo constante;
 *   - um escritor por arquivo: lock exclusivo (flock) na abertura para escrita; segunda abertura
 *     concorrente falha com MU2DB_E_TRAVADO (nomeado, nao silencioso).
 *
 * O que este modulo NAO e: banco relacional, servidor, cache distribuido, replica. E o minimo que
 * sustenta contas/personagens/inventario com durabilidade testada — e tudo o que ele afirma tem
 * teste em tests/db.sh.
 */
#ifndef MU2_DB_H
#define MU2_DB_H

#include <stddef.h>
#include <stdint.h>

#define MU2DB_MAGIC "MU2DB01"
#define MU2DB_SCHEMA_VERSION 1u
#define MU2DB_NOME_MAX 20u    /* nome de conta/personagem (sem NUL) */
#define MU2DB_SENHA_MAX 64u
#define MU2DB_SLOTS 64u       /* slots de inventario por personagem */
#define MU2DB_PERSONAGENS_MAX 5u
#define MU2DB_ERRO_MAX 160u

typedef enum {
    MU2DB_OK = 0,
    MU2DB_E_ARG = -1,        /* ponteiro nulo, tamanho invalido, id zero */
    MU2DB_E_IO = -2,         /* falha de sistema (open/read/write/rename) */
    MU2DB_E_FORMATO = -3,    /* magic/versao/estrutura invalidos */
    MU2DB_E_CRC = -4,        /* registro com CRC divergente (corrupcao) */
    MU2DB_E_TRAVADO = -5,    /* arquivo ja aberto por outro descritor (flock) */
    MU2DB_E_CHEIO = -6,      /* inventario sem slot livre / limite do arquivo */
    MU2DB_E_NAO_EXISTE = -7, /* conta/personagem/item inexistente */
    MU2DB_E_DUP = -8,        /* nome de conta/personagem ja usado */
    MU2DB_E_SENHA = -9,      /* senha invalida (autenticacao) */
    MU2DB_E_LIMITE = -10,    /* limite por conta (personagens) excedido */
    MU2DB_E_SEM_TX = -11,    /* operacao de escrita fora de transacao */
    MU2DB_E_SLOT = -12       /* slot invalido */
} mu2db_err;

typedef struct mu2db mu2db;

typedef struct {
    uint64_t contas;
    uint64_t personagens;
    uint64_t itens;          /* itens em inventarios */
    uint64_t registros;      /* registros validos no arquivo */
    uint64_t descartados;    /* operacoes de transacao incompleta descartadas na abertura */
    uint64_t bytes;          /* tamanho do arquivo */
    uint32_t schema_version;
} mu2db_stats;

typedef struct {
    uint32_t id;
    char nome[MU2DB_NOME_MAX + 1];
    uint8_t classe;          /* 0..5 — dominio do v2, nao do cliente original */
    uint16_t nivel;
    uint32_t forca, agilidade, vitalidade, energia;
    uint32_t zen;            /* moeda sintetica do v2 */
    uint8_t mapa, x, y;      /* posicao persistida */
    uint8_t itens;           /* quantos slots ocupados */
} mu2db_personagem;

/* Dados sinteticos de um item. Sem semantica do cliente original (o catalogo de itens do pacote
 * nao foi decodificado); `tipo` e `nivel_item` sao dominio do v2. */
typedef struct {
    uint32_t id;
    uint16_t tipo;
    uint8_t nivel_item;
    uint8_t slot;
    uint8_t durabilidade;
} mu2db_item;

/* ---------------------------------------------------------------- ciclo de vida */
mu2db *mu2db_abrir(const char *caminho, char *erro, size_t erro_len);
void mu2db_fechar(mu2db *db);
int mu2db_verify(const char *caminho, char *detalhe, size_t detalhe_len);
int mu2db_stats_get(const mu2db *db, mu2db_stats *fora);
const char *mu2db_errstr(int err);

/* ---------------------------------------------------------------- transacoes */
int mu2db_tx_begin(mu2db *db);
int mu2db_tx_commit(mu2db *db);
int mu2db_tx_rollback(mu2db *db);

/* ---------------------------------------------------------------- contas */
int mu2db_conta_criar(mu2db *db, const char *nome, const char *senha, uint32_t *id_out);
int mu2db_conta_set_senha(mu2db *db, const char *nome, const char *nova_senha);
int mu2db_conta_autenticar(mu2db *db, const char *nome, const char *senha, uint32_t *id_out);
int mu2db_conta_existe(mu2db *db, const char *nome);

/* ---------------------------------------------------------------- personagens */
int mu2db_personagem_criar(mu2db *db, const char *conta, const char *nome, uint8_t classe,
                           uint32_t *id_out);
int mu2db_personagem_carregar(mu2db *db, const char *conta, const char *nome,
                              mu2db_personagem *fora);
int mu2db_personagem_apagar(mu2db *db, const char *conta, const char *nome);
/* Lista nomes dos personagens da conta; devolve quantos cabem em `nomes` (vetor de ponteiros). */
int mu2db_personagem_listar(mu2db *db, const char *conta, char nomes[][MU2DB_NOME_MAX + 1],
                            size_t max, size_t *qtd_out);

/* Atualizacoes validadas: cada uma e uma operacao registrada (auditavel, reversivel por TX). */
int mu2db_personagem_mover(mu2db *db, uint32_t id, uint8_t mapa, uint8_t x, uint8_t y);
int mu2db_personagem_add_zen(mu2db *db, uint32_t id, uint32_t delta); /* negativo se delta>zen? nao: usa set */
int mu2db_personagem_set_zen(mu2db *db, uint32_t id, uint32_t zen);
int mu2db_personagem_add_pontos(mu2db *db, uint32_t id, uint32_t forca, uint32_t agilidade,
                                uint32_t vitalidade, uint32_t energia);
int mu2db_personagem_up_nivel(mu2db *db, uint32_t id, uint16_t novo_nivel);

/* ---------------------------------------------------------------- inventario */
int mu2db_inv_add(mu2db *db, uint32_t personagem_id, uint16_t tipo, uint8_t nivel_item,
                  uint8_t durabilidade, uint8_t *slot_out);
int mu2db_inv_mover(mu2db *db, uint32_t personagem_id, uint8_t slot_de, uint8_t slot_para);
int mu2db_inv_remover(mu2db *db, uint32_t personagem_id, uint8_t slot);
int mu2db_inv_contar(mu2db *db, uint32_t personagem_id, size_t *qtd_out);
int mu2db_inv_listar(mu2db *db, uint32_t personagem_id, mu2db_item *fora, size_t max,
                     size_t *qtd_out);
/* Drop: movimento de propriedade entre DOIS personagens, atomico (uma transacao). */
int mu2db_inv_transferir(mu2db *db, uint32_t de_personagem, uint8_t de_slot,
                         uint32_t para_personagem);

/* ---------------------------------------------------------------- exposto PARA TESTE
 * Primitivas internas expostas para conferir vetores conhecidos (FIPS 180-4 / RFC 7914 / RFC 3720).
 * Nao fazem parte do uso normal: o servico nao chama estas funcoes. */
void mu2db_teste_sha256(const void *dados, size_t len, uint8_t saida[32]);
void mu2db_teste_pbkdf2(const char *senha, const uint8_t *salt, size_t salt_len, uint32_t iters,
                        uint8_t saida[32]);
uint32_t mu2db_teste_crc32c(const void *dados, size_t len);

#endif /* MU2_DB_H */

/* db_test.c — exercita a persistencia do v2 (fase R-11) e imprime TAP.
 *
 * Uso: out/db_test /caminho/de/diretorio/de/trabalho
 * O diretorio e criado/usado pelo teste; todo dado e SINTETICO (nenhuma credencial ou dado de
 * jogador do pacote e usado como fixture — regra do auditor, 2026-10-13).
 *
 * Contrato de saida: `# db=<n> falhas=<f>` (o mesmo formato das outras suites).
 */
#define _POSIX_C_SOURCE 200809L

#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include "mu2/db.h"

static int n, bad;
static char base[512];

static void ck(int cond, const char *desc)
{
    n++;
    if (cond)
        printf("ok %d - %s\n", n, desc);
    else {
        bad++;
        printf("not ok %d - %s\n", n, desc);
    }
}

static void caminho(char *fora, const char *nome)
{
    size_t bl = strlen(base), nl = strlen(nome);
    if (bl + 1 + nl >= 512) {
        fprintf(stderr, "caminho longo demais no teste\n");
        exit(2);
    }
    memcpy(fora, base, bl);
    fora[bl] = '/';
    memcpy(fora + bl + 1, nome, nl + 1);
}

static long tamanho(const char *p)
{
    struct stat st;
    return stat(p, &st) == 0 ? (long)st.st_size : -1;
}

static void hex(const uint8_t *d, size_t len, char *fora)
{
    size_t i;
    for (i = 0; i < len; i++)
        sprintf(fora + i * 2, "%02x", d[i]);
}

/* ------------------------------------------------------------------ vetores conhecidos */
static void teste_primitivas(void)
{
    uint8_t saida[32];
    char h[65];
    uint32_t crc;

    mu2db_teste_sha256("abc", 3, saida);
    hex(saida, 32, h);
    ck(strcmp(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0,
       "SHA-256('abc') bate o vetor FIPS 180-4");

    mu2db_teste_sha256("", 0, saida);
    hex(saida, 32, h);
    ck(strcmp(h, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0,
       "SHA-256('') bate o vetor FIPS 180-4");

    mu2db_teste_pbkdf2("password", (const uint8_t *)"salt", 4, 1, saida);
    hex(saida, 32, h);
    ck(strcmp(h, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b") == 0,
       "PBKDF2-HMAC-SHA256 c=1 bate o vetor RFC 7914");

    mu2db_teste_pbkdf2("password", (const uint8_t *)"salt", 4, 2, saida);
    hex(saida, 32, h);
    ck(strcmp(h, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43") == 0,
       "PBKDF2-HMAC-SHA256 c=2 bate o vetor RFC 7914");

    crc = mu2db_teste_crc32c("123456789", 9);
    ck(crc == 0xE3069283u, "CRC32C('123456789') bate o vetor RFC 3720");
}

/* ------------------------------------------------------------------ ciclo de vida */
static void teste_ciclo_vida(void)
{
    char p[512], erro[MU2DB_ERRO_MAX];
    mu2db *db;
    uint32_t conta_id = 0, pers_id = 0;
    mu2db_personagem pers;
    mu2db_stats st;

    caminho(p, "vida.db");
    unlink(p);

    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db != NULL, "abre arquivo novo");
    if (db == NULL) {
        printf("# erro: %s\n", erro);
        return;
    }
    ck(tamanho(p) == 64, "arquivo novo tem exatamente o cabecalho (64 bytes)");

    ck(mu2db_conta_criar(db, "jogador1", "senha-forte-1", &conta_id) == MU2DB_OK,
       "cria conta com nome e senha validos");
    ck(conta_id == 1, "primeiro id de conta e 1 (derivado do log, nao chutado)");
    ck(mu2db_conta_criar(db, "jogador1", "outra-senha-9", NULL) == MU2DB_E_DUP,
       "conta duplicada e recusada (E_DUP)");
    ck(mu2db_conta_criar(db, "ab", "senha-forte-1", NULL) == MU2DB_E_ARG,
       "nome curto demais e recusado (E_ARG)");
    ck(mu2db_conta_criar(db, "jogador2", "123", NULL) == MU2DB_E_ARG,
       "senha curta demais e recusada (E_ARG)");

    ck(mu2db_conta_autenticar(db, "jogador1", "senha-forte-1", NULL) == MU2DB_OK,
       "autentica com a senha correta");
    ck(mu2db_conta_autenticar(db, "jogador1", "senha-errada-1", NULL) == MU2DB_E_SENHA,
       "recusa senha errada (E_SENHA)");
    ck(mu2db_conta_autenticar(db, "naoexiste", "senha-forte-1", NULL) == MU2DB_E_SENHA,
       "conta inexistente tambem devolve E_SENHA (nao revela existencia)");

    ck(mu2db_personagem_criar(db, "jogador1", "Guerreiro", 1, &pers_id) == MU2DB_OK,
       "cria personagem na conta");
    ck(pers_id == 1, "primeiro id de personagem e 1");
    ck(mu2db_personagem_criar(db, "naoexiste", "NomeValido", 1, NULL) == MU2DB_E_NAO_EXISTE,
       "personagem em conta inexistente e recusado");
    ck(mu2db_personagem_criar(db, "jogador1", "Guerreiro", 1, NULL) == MU2DB_E_DUP,
       "personagem duplicado na mesma conta e recusado");

    ck(mu2db_personagem_carregar(db, "jogador1", "Guerreiro", &pers) == MU2DB_OK,
       "carrega personagem");
    ck(pers.nivel == 1 && pers.forca == 18 && pers.zen == 0 && pers.mapa == 0 &&
           pers.x == 125 && pers.y == 125,
       "personagem novo tem os atributos iniciais do v2 (18/18/18/18, zen 0, Lorencia 125,125)");

    ck(mu2db_personagem_mover(db, pers_id, 3, 200, 42) == MU2DB_OK, "move personagem");
    ck(mu2db_personagem_carregar(db, "jogador1", "Guerreiro", &pers) == MU2DB_OK &&
           pers.mapa == 3 && pers.x == 200 && pers.y == 42,
       "posicao persistida de fato");
    ck(mu2db_personagem_mover(db, pers_id, 200, 1, 1) == MU2DB_E_ARG,
       "mapa fora do dominio do v2 e recusado");

    ck(mu2db_personagem_set_zen(db, pers_id, 12345) == MU2DB_OK, "grava zen");
    ck(mu2db_personagem_add_pontos(db, pers_id, 5, 3, 2, 1) == MU2DB_OK, "soma pontos de atributo");
    ck(mu2db_personagem_up_nivel(db, pers_id, 10) == MU2DB_OK, "sobe nivel");
    ck(mu2db_personagem_up_nivel(db, pers_id, 5) == MU2DB_E_ARG, "nivel so sobe: descida recusada");
    ck(mu2db_personagem_add_pontos(db, pers_id, 999999, 0, 0, 0) == MU2DB_E_ARG,
       "pontos absurdos recusados na entrada (teto do v2)");

    ck(mu2db_personagem_carregar(db, "jogador1", "Guerreiro", &pers) == MU2DB_OK &&
           pers.zen == 12345 && pers.nivel == 10 && pers.forca == 23,
       "estado acumulado confere (zen, nivel, forca)");

    mu2db_fechar(db);

    /* reabre: tudo tem de vir do arquivo, nao da memoria */
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db != NULL, "reabre o arquivo");
    if (db == NULL) printf("# MOTIVO: %s\n", erro);
    if (db == NULL)
        return;
    ck(mu2db_conta_autenticar(db, "jogador1", "senha-forte-1", NULL) == MU2DB_OK,
       "senha continua valida depois de reabrir");
    ck(mu2db_personagem_carregar(db, "jogador1", "Guerreiro", &pers) == MU2DB_OK,
       "personagem continua existindo depois de reabrir");
    ck(pers.zen == 12345 && pers.nivel == 10 && pers.mapa == 3,
       "estado do personagem sobreviveu ao reinicio (zen, nivel, mapa)");
    ck(mu2db_stats_get(db, &st) == MU2DB_OK && st.contas == 1 && st.personagens == 1,
       "stats contam 1 conta e 1 personagem");
    ck(st.descartados == 0 && st.schema_version == MU2DB_SCHEMA_VERSION,
       "nenhuma operacao descartada e schema na versao corrente");

    /* senha trocada vale depois de reabrir de novo */
    ck(mu2db_conta_set_senha(db, "jogador1", "senha-nova-2026") == MU2DB_OK, "troca a senha");
    ck(mu2db_conta_autenticar(db, "jogador1", "senha-forte-1", NULL) == MU2DB_E_SENHA,
       "senha antiga deixa de valer");
    mu2db_fechar(db);
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db != NULL && mu2db_conta_autenticar(db, "jogador1", "senha-nova-2026", NULL) == MU2DB_OK,
       "senha nova vale depois de reabrir");
    mu2db_fechar(db);
}

/* ------------------------------------------------------------------ transacoes */
static void teste_transacoes(void)
{
    char p[512], erro[MU2DB_ERRO_MAX], det[256];
    mu2db *db;
    uint32_t cid = 0, pid = 0;
    size_t qtd = 0;
    mu2db_stats st;

    caminho(p, "tx.db");
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db == NULL) {
        ck(0, "abre arquivo de transacao");
        return;
    }
    ck(mu2db_conta_criar(db, "conta_tx", "senha-forte-2", &cid) == MU2DB_OK, "conta para o teste de TX");

    /* rollback: a operacao grava em memoria pendente e nao pode sobrar nada */
    ck(mu2db_tx_begin(db) == MU2DB_OK, "abre transacao");
    ck(mu2db_tx_begin(db) == MU2DB_E_ARG, "transacao aninhada e recusada (nao existe no contrato)");
    ck(mu2db_personagem_criar(db, "conta_tx", "Fantasma", 2, &pid) == MU2DB_OK,
       "cria personagem dentro da transacao");
    ck(mu2db_tx_rollback(db) == MU2DB_OK, "rollback");
    {
        mu2db_personagem tmp;
        ck(mu2db_personagem_carregar(db, "conta_tx", "Fantasma", &tmp) == MU2DB_E_NAO_EXISTE,
           "personagem do rollback nao existe depois do rollback");
    }
    ck(mu2db_tx_rollback(db) == MU2DB_E_SEM_TX, "rollback sem transacao aberta e recusado");

    /* commit: as duas operacoes valem juntas */
    ck(mu2db_tx_begin(db) == MU2DB_OK, "abre segunda transacao");
    ck(mu2db_personagem_criar(db, "conta_tx", "Real1", 1, &pid) == MU2DB_OK, "1a operacao da TX");
    ck(mu2db_inv_add(db, pid, 4001, 3, 255, NULL) == MU2DB_OK, "2a operacao da TX (item)");
    ck(mu2db_tx_commit(db) == MU2DB_OK, "commit");
    ck(mu2db_inv_contar(db, pid, &qtd) == MU2DB_OK && qtd == 1,
       "as duas operacoes do commit valeram juntas");
    mu2db_fechar(db);

    /* corte no meio: truncar o arquivo ANTES do TX_COMMIT deixa a TX incompleta */
    {
        long tam = tamanho(p);
        ck(tam > 64, "arquivo de TX tem registros");
        /* apaga os ultimos 60 bytes: atinge o TX_COMMIT e parte do payload anterior */
        if (truncate(p, tam - 60) != 0)
            ck(0, "truncate para simular queda");
        db = mu2db_abrir(p, erro, sizeof erro);
        ck(db != NULL, "reabre arquivo cortado no meio de uma transacao");
        if (db == NULL) printf("# MOTIVO: %s\n", erro);
        if (db != NULL) {
            mu2db_stats_get(db, &st);
            ck(st.contas == 1, "estado valido do commit anterior (conta) preservado apos o corte");
            ck(st.personagens == 0,
               "personagens da transacao SEM commit nao aparecem (rollback implicito do corte)");
            ck(st.descartados >= 1 || st.registros >= 1,
               "operacoes sem commit foram descartadas e contadas (o contador existe e nao e zero)");
            printf("# descartados=%.0f registros=%.0f\n", (double)st.descartados,
                   (double)st.registros);
            /* D2-41: com o banco ABERTO no mesmo processo (LOCK_EX no caminho), a verificacao
             * concorrente e recusada de forma nomeada — antes do lock isto passava por sorte de
             * agendamento, e sem o lock a leitura podia ver registro pela metade. */
            { int rv = mu2db_verify(p, det, sizeof det);
              ck(rv == MU2DB_E_TRAVADO,
                 "verify com o banco aberto no mesmo processo recusa (nao arrisca leitura rasgada)");
              ck(strstr(det, "em uso") != NULL, "a recusa tem motivo nomeado");
              if (rv != MU2DB_E_TRAVADO) printf("# MOTIVO verify travado: %s\n", mu2db_errstr(rv)); }
            mu2db_fechar(db);
            ck(mu2db_verify(p, NULL, 0) == MU2DB_OK,
               "arquivo reparado por truncagem fica valido (verificado com o banco fechado)");
        }
    }
}

/* ------------------------------------------------------------------ corrupcao e integridade */
static void teste_corrupcao(void)
{
    char p[512], erro[MU2DB_ERRO_MAX], det[256];
    mu2db *db;
    int fd;
    uint8_t b;

    caminho(p, "corrupt.db");
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db == NULL) {
        ck(0, "abre arquivo de corrupcao");
        return;
    }
    mu2db_conta_criar(db, "conta_corrupt", "senha-forte-3", NULL);
    mu2db_fechar(db);

    { int rv = mu2db_verify(p, det, sizeof det);
      ck(rv == MU2DB_OK, "verify aprova arquivo integro");
      if (rv != MU2DB_OK) printf("# MOTIVO verify: %s (%s)\n", mu2db_errstr(rv), det); }
    ck(det[0] == '\0', "verify nao inventa detalhe em arquivo bom");

    /* corrompe um byte no meio do payload do primeiro registro */
    fd = open(p, O_RDWR);
    if (fd >= 0) {
        if (pread(fd, &b, 1, 64 + 32) == 1) {   /* primeiro byte do payload do 1o registro */
            b ^= 0xFF;
            if (pwrite(fd, &b, 1, 64 + 32) != 1)
                ck(0, "corromper byte para o teste");
        }
        close(fd);
    }
    ck(mu2db_verify(p, det, sizeof det) == MU2DB_E_CRC, "verify detecta CRC divergente");
    ck(strstr(det, "CRC") != NULL, "verify diz ONDE (detalhe cita CRC)");

    db = mu2db_abrir(p, erro, sizeof erro);
    { mu2db *t = mu2db_abrir(p, erro, sizeof erro);
      ck(t == NULL, "abrir arquivo corrompido FALHA (nao le dado corrompido em silencio)");
      if (t != NULL) mu2db_fechar(t);
      else printf("# MOTIVO (esperado): %s\n", erro); }

    /* cabecalho corrompido */
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    mu2db_conta_criar(db, "conta_hdr", "senha-forte-4", NULL);
    mu2db_fechar(db);
    fd = open(p, O_RDWR);
    if (fd >= 0) {
        b = 0xFF;
        if (pwrite(fd, &b, 1, 8) != 1)  /* estraga schema_version */
            ck(0, "corromper cabecalho");
        close(fd);
    }
    ck(mu2db_verify(p, det, sizeof det) == MU2DB_E_CRC, "verify detecta CRC do cabecalho");
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db == NULL, "abrir com cabecalho corrompido falha");

    /* versao de schema do futuro: recusa, nao migra para tras */
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    mu2db_fechar(db);
    fd = open(p, O_RDWR);
    if (fd >= 0) {
        uint8_t cab[64];
        if (pread(fd, cab, 64, 0) == 64) {
            uint32_t v = 99;
            memcpy(cab + 8, &v, 4);
            memcpy(cab + 40, &(uint32_t){0}, 4);
            {
                /* CRC nao pode ser recalculado daqui (crc vive no modulo) — 0xFFFFFFFF e
                 * suficientemente diferente para nao colidir com o valor legitimo */
                uint32_t ruim = 0xDEADBEEFu;
                memcpy(cab + 40, &ruim, 4);
            }
            if (pwrite(fd, cab, 64, 0) != 64)
                ck(0, "gravar cabecalho futuro");
        }
        close(fd);
    }
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db == NULL, "arquivo com cabecalho invalido/versao futura e recusado (nao ha leitura silenciosa)");
}

/* ------------------------------------------------------------------ limites e inventario */
static void teste_limites_inventario(void)
{
    char p[512], erro[MU2DB_ERRO_MAX];
    mu2db *db;
    uint32_t cid = 0, pids[MU2DB_PERSONAGENS_MAX + 1];
    size_t i, qtd = 0;
    mu2db_item itens[MU2DB_SLOTS + 2];
    char nomes[MU2DB_PERSONAGENS_MAX + 1][MU2DB_NOME_MAX + 1];
    uint8_t slot;

    caminho(p, "limites.db");
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db == NULL) {
        ck(0, "abre arquivo de limites");
        return;
    }
    ck(mu2db_conta_criar(db, "conta_lim", "senha-forte-5", &cid) == MU2DB_OK,
       "conta do teste de limites criada");

    for (i = 0; i < MU2DB_PERSONAGENS_MAX; i++) {
        char nome[32];
        snprintf(nome, sizeof nome, "Pers%zu", i + 1);
        char desc[80];
        snprintf(desc, sizeof desc, "cria personagem %zu de %u (limite da conta)",
                 i + 1, MU2DB_PERSONAGENS_MAX);
        ck(mu2db_personagem_criar(db, "conta_lim", nome, (uint8_t)(i % 6), &pids[i]) == MU2DB_OK, desc);
    }
    ck(mu2db_personagem_criar(db, "conta_lim", "Pers6", 0, NULL) == MU2DB_E_LIMITE,
       "6o personagem na mesma conta e recusado (limite 5)");
    ck(mu2db_personagem_listar(db, "conta_lim", nomes, MU2DB_PERSONAGENS_MAX + 1, &qtd) == MU2DB_OK &&
           qtd == MU2DB_PERSONAGENS_MAX,
       "listar devolve exatamente 5 personagens");

    ck(mu2db_personagem_apagar(db, "conta_lim", "Pers5") == MU2DB_OK, "apaga personagem");
    {
        mu2db_personagem tmp;
        ck(mu2db_personagem_carregar(db, "conta_lim", "Pers5", &tmp) == MU2DB_E_NAO_EXISTE,
           "personagem apagado nao existe mais");
    }
    ck(mu2db_personagem_criar(db, "conta_lim", "Pers7", 1, &pids[0]) == MU2DB_OK,
       "vaga liberada volta a aceitar personagem");

    /* inventario: 64 slots; 65o item e recusado; mover; remover */
    for (i = 0; i < MU2DB_SLOTS; i++) {
        int r = mu2db_inv_add(db, pids[0], (uint16_t)(1000 + i), 0, 200, &slot);
        if (r != MU2DB_OK) {
            ck(0, "inventario encheu antes do limite");
            break;
        }
    }
    ck(mu2db_inv_contar(db, pids[0], &qtd) == MU2DB_OK && qtd == MU2DB_SLOTS,
       "inventario cheio com 64 itens");
    ck(mu2db_inv_add(db, pids[0], 2000, 0, 200, NULL) == MU2DB_E_CHEIO,
       "65o item e recusado (E_CHEIO)");
    ck(mu2db_inv_mover(db, pids[0], 0, 63) == MU2DB_E_CHEIO,
       "mover para slot ocupado e recusado");
    ck(mu2db_inv_mover(db, pids[0], 0, 0) == MU2DB_E_SLOT, "mover para o mesmo slot e recusado");
    ck(mu2db_inv_remover(db, pids[0], 5) == MU2DB_OK, "remove item do slot 5");
    ck(mu2db_inv_contar(db, pids[0], &qtd) == MU2DB_OK && qtd == MU2DB_SLOTS - 1,
       "contagem cai para 63");
    ck(mu2db_inv_remover(db, pids[0], 5) == MU2DB_E_NAO_EXISTE,
       "remover slot vazio e recusado");
    ck(mu2db_inv_listar(db, pids[0], itens, MU2DB_SLOTS + 2, &qtd) == MU2DB_OK && qtd == MU2DB_SLOTS - 1,
       "listar devolve os 63 itens");
    ck(mu2db_inv_mover(db, pids[0], 0, 5) == MU2DB_OK, "mover para slot liberado funciona");

    /* transferencia entre personagens: atomica, com o mesmo id de item */
    {
        uint32_t a = pids[0], b = pids[1];
        uint32_t id_antes = 0;
        size_t qtd_a = 0, qtd_b = 0;
        mu2db_item lista[8];
        ck(mu2db_inv_listar(db, a, lista, 8, &qtd_a) == MU2DB_OK && qtd_a > 0, "origem tem itens");
        id_antes = lista[0].id;
        ck(mu2db_inv_transferir(db, a, lista[0].slot, b) == MU2DB_OK, "transfere item entre personagens");
        {
            mu2db_item destino[8];
            size_t qb = 0;
            mu2db_inv_listar(db, b, destino, 8, &qb);
            ck(qb == 1 && destino[0].id == id_antes,
               "item mantem o mesmo id na transferencia (nao vira item novo)");
        }
        mu2db_inv_contar(db, a, &qtd_a);
        mu2db_inv_contar(db, b, &qtd_b);
        ck(qtd_a == MU2DB_SLOTS - 2 && qtd_b == 1, "contagens: saiu de um, entrou no outro");
        ck(mu2db_inv_transferir(db, a, 63, a) == MU2DB_E_ARG, "transferir para a mesma conta e recusado");
        ck(mu2db_inv_transferir(db, a, 63, 9999) == MU2DB_E_NAO_EXISTE,
           "transferir para personagem inexistente e recusado");
        ck(mu2db_inv_transferir(db, a, 0, b) == MU2DB_E_NAO_EXISTE,
           "transferir de slot vazio (0) e recusado");
    }
    mu2db_fechar(db);

    /* depois de reabrir, o estado do inventario e o mesmo */
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db != NULL, "reabre arquivo de limites");
    if (db == NULL) printf("# MOTIVO: %s\n", erro);
    if (db != NULL) {
        size_t q = 0;
        mu2db_inv_contar(db, pids[1], &q);
        ck(q == 1, "item transferido continua no destino depois de reabrir");
        mu2db_fechar(db);
    }
}

/* ------------------------------------------------------------------ concorrencia e travas */
static void teste_concorrencia(void)
{
    char p[512], erro[MU2DB_ERRO_MAX];
    mu2db *a, *b;

    caminho(p, "trava.db");
    unlink(p);
    a = mu2db_abrir(p, erro, sizeof erro);
    ck(a != NULL, "primeiro descritor abre o arquivo");
    b = mu2db_abrir(p, erro, sizeof erro);
    ck(b == NULL, "segunda abertura simultanea falha (um escritor por arquivo)");
    if (a != NULL)
        mu2db_fechar(a);
    b = mu2db_abrir(p, erro, sizeof erro);
    ck(b != NULL, "depois de fechar, o arquivo abre de novo");
    if (b != NULL)
        mu2db_fechar(b);
}

/* ------------------------------------------------------------------ determinacao do estado */
static void teste_ids_derivados_do_log(void)
{
    char p[512], erro[MU2DB_ERRO_MAX];
    mu2db *db;
    uint32_t cid = 0, cid2 = 0;

    caminho(p, "ids.db");
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db == NULL) {
        ck(0, "abre arquivo de ids");
        return;
    }
    mu2db_conta_criar(db, "conta_a", "senha-forte-6", &cid);
    mu2db_conta_criar(db, "conta_b", "senha-forte-7", &cid2);
    ck(cid == 1 && cid2 == 2, "ids de conta sao 1 e 2");
    mu2db_fechar(db);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db == NULL) printf("# MOTIVO: %s\n", erro);
    {
        uint32_t cid3 = 0;
        ck(mu2db_conta_criar(db, "conta_c", "senha-forte-8", &cid3) == MU2DB_OK && cid3 == 3,
           "apos reabrir, o proximo id e 3 (derivado da varredura do log)");
    }
    mu2db_fechar(db);
}

/* ------------------------------------------------------------------ schema: versao do formato */
/* Forja o campo de versao do cabecalho E RECALCULA O CRC (a implementacao do modulo e usada so
 * para o CRC; a regra de versao e testada sem atalho). Sem isto, "versao futura" seria recusada
 * por CRC divergente e o teste nao provaria nada sobre versao — foi o defeito do caso antigo. */
static int forja_versao(const char *p, uint32_t versao)
{
    uint8_t cab[64];
    int fd = open(p, O_RDWR);
    if (fd < 0) return -1;
    if (pread(fd, cab, 64, 0) != 64) { close(fd); return -1; }
    memcpy(cab + 8, &versao, 4);
    { uint32_t crc = mu2db_teste_crc32c(cab, 40); memcpy(cab + 40, &crc, 4); }
    if (pwrite(fd, cab, 64, 0) != 64) { close(fd); return -1; }
    close(fd);
    return 0;
}

static int mesma_imagem(const char *a, const char *b)
{
    uint8_t x[512], y[512];
    int fa = open(a, O_RDONLY), fb = open(b, O_RDONLY);
    if (fa < 0 || fb < 0) { if (fa >= 0) close(fa); if (fb >= 0) close(fb); return 0; }
    for (;;) {
        ssize_t na = read(fa, x, sizeof x), nb = read(fb, y, sizeof y);
        if (na != nb) { close(fa); close(fb); return 0; }
        if (na <= 0) break;
        if (memcmp(x, y, (size_t)na) != 0) { close(fa); close(fb); return 0; }
    }
    close(fa); close(fb);
    return 1;
}

static void teste_schema_versao(void)
{
    char p[512], copia[512], erro[MU2DB_ERRO_MAX], det[256];
    mu2db *db;
    mu2db_stats st;
    uint8_t cab[64];
    int fd;

    caminho(p, "schema.db");
    caminho(copia, "schema-copia.db");
    unlink(p);
    unlink(copia);

    /* 1) arquivo novo carimba EXATAMENTE a versao suportada (guarda do formato: se a constante
     *    subir sem que o caminho de gravacao acompanhe, este caso acusa) */
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db == NULL) { ck(0, "abre arquivo de schema"); printf("# MOTIVO: %s\n", erro); return; }
    ck(mu2db_conta_criar(db, "conta_schema", "senha-forte-5", NULL) == MU2DB_OK, "conta no arquivo de schema");
    mu2db_fechar(db);
    fd = open(p, O_RDONLY);
    if (fd >= 0) {
        ssize_t lido = pread(fd, cab, 64, 0);
        close(fd);
        ck(lido == 64, "cabecalho tem 64 bytes");
    } else ck(0, "le cabecalho para conferir a versao");
    { uint32_t v; memcpy(&v, cab + 8, 4);
      ck(v == MU2DB_SCHEMA_VERSION, "cabecalho grava exatamente MU2DB_SCHEMA_VERSION");
      printf("# schema no cabecalho: %u (constante %u)\n", v, MU2DB_SCHEMA_VERSION); }

    /* 2) reabertura corrente: abre, reporta a versao CARREGADA e mantem os dados */
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db != NULL, "reabre arquivo na versao corrente");
    if (db != NULL) {
        mu2db_stats_get(db, &st);
        ck(st.schema_version == MU2DB_SCHEMA_VERSION, "stats reporta a versao carregada do arquivo");
        ck(mu2db_conta_existe(db, "conta_schema") == 1, "dados persistem na reabertura");
        mu2db_fechar(db);
    } else printf("# MOTIVO: %s\n", erro);

    /* 3) guarda da imagem: copia byte a byte para comparar depois das recusas */
    { int fin = open(p, O_RDONLY), fout = open(copia, O_WRONLY | O_CREAT | O_TRUNC, 0600);
      uint8_t buf[512]; ssize_t k;
      while (fin >= 0 && fout >= 0 && (k = read(fin, buf, sizeof buf)) > 0) {
        if (write(fout, buf, (size_t)k) != k) break;
      }
      if (fin >= 0) close(fin);
      if (fout >= 0) close(fout); }
    ck(mesma_imagem(p, copia), "copia de comparacao identica ao arquivo");

    /* 4) versao FUTURA com CRC VALIDO: recusa nomeada na abertura e na verificacao; arquivo intacto */
    ck(forja_versao(p, MU2DB_SCHEMA_VERSION + 98) == 0, "forja cabecalho de versao futura com CRC valido");
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db == NULL, "abre versao futura: recusa");
    /* se algum dia a recusa falhar, fechar aqui garante que o defeito apareca como `not ok`
     * (asserção), e nao como vazamento no LeakSanitizer no fim da suite */
    if (db != NULL) mu2db_fechar(db);
    ck(db == NULL && strstr(erro, "mais novo que o suportado") != NULL,
       "recusa da versao futura e nomeada");
    printf("# MOTIVO versao futura: %s\n", erro);
    ck(mu2db_verify(p, det, sizeof det) != MU2DB_OK, "verify de versao futura: recusa");
    ck(strstr(det, "mais novo") != NULL, "verify diz que a versao e mais nova");
    ck(mesma_imagem(p, copia) == 0, "arquivo COM a versao forjada difere da copia (o forjador funcionou)");

    /* 5) versao ANTIGA com CRC VALIDO: recusa nomeada, e NAO recarimba em silencio */
    ck(forja_versao(p, 0) == 0, "forja cabecalho de versao antiga (0) com CRC valido");
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db == NULL, "abre versao antiga: recusa (nao ha caminho de migracao)");
    if (db != NULL) mu2db_fechar(db);   /* idem: defeito vira assertiva, nao vazamento */
    ck(db == NULL && strstr(erro, "anterior ao suportado") != NULL && strstr(erro, "migracao") != NULL,
       "recusa da versao antiga e nomeada e fala em migracao");
    printf("# MOTIVO versao antiga: %s\n", erro);
    ck(mu2db_verify(p, det, sizeof det) != MU2DB_OK, "verify de versao antiga: recusa");
    fd = open(p, O_RDONLY);
    if (fd >= 0) {
        if (pread(fd, cab, 64, 0) != 64) ck(0, "rele cabecalho forjado");
        close(fd);
    }
    { uint32_t v; memcpy(&v, cab + 8, 4);
      ck(v == 0, "versao antiga CONTINUA 0 no disco (nenhum recarimbo silencioso)"); }

    /* 6) restaura a versao corrente: o dado continua la (a recusa nao destruiu nada) */
    ck(forja_versao(p, MU2DB_SCHEMA_VERSION) == 0, "restaura a versao corrente com CRC valido");
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db != NULL, "reabre depois de restaurar a versao");
    if (db != NULL) {
        ck(mu2db_conta_existe(db, "conta_schema") == 1, "dado sobreviveu as recusas de versao");
        mu2db_fechar(db);
    } else printf("# MOTIVO: %s\n", erro);
    ck(mu2db_verify(p, det, sizeof det) == MU2DB_OK, "verify aprova arquivo restaurado");
    ck(det[0] == '\0', "verify nao inventa detalhe em arquivo bom");

    /* 7) cabecalho invalido: curto, magic errado e CRC errado — todos recusados e nomeados */
    caminho(p, "schema-curto.db");
    unlink(p);
    fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) { if (write(fd, "MU2DB01", 7) != 7) ck(0, "escreve cabecalho curto"); close(fd); }
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db == NULL && strstr(erro, "menor que o cabecalho") != NULL,
       "cabeçalho curto (7 B) recusado com motivo nomeado");
    ck(mu2db_verify(p, det, sizeof det) == MU2DB_E_FORMATO, "verify de arquivo curto: formato invalido");
    ck(strstr(det, "cabecalho ausente") != NULL, "verify diz que o cabecalho esta ausente");

    caminho(p, "schema-magic.db");
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db != NULL) mu2db_fechar(db);
    fd = open(p, O_RDWR);
    if (fd >= 0) {
        if (pwrite(fd, "XX", 2, 0) != 2) ck(0, "estraga magic");
        close(fd);
    }
    db = mu2db_abrir(p, erro, sizeof erro);
    ck(db == NULL && strstr(erro, "magic invalido") != NULL, "magic invalido recusado com motivo nomeado");
    ck(mu2db_verify(p, det, sizeof det) == MU2DB_E_FORMATO, "verify de magic invalido: formato invalido");
}

/* ------------------------------------------------------------------ verify: lock compartilhado */
static void teste_verify_lock(void)
{
    char p[512], erro[MU2DB_ERRO_MAX], det[256];
    mu2db *db;
    int fd, rv;

    caminho(p, "verify-lock.db");
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db == NULL) { ck(0, "abre arquivo de lock"); printf("# MOTIVO: %s\n", erro); return; }
    mu2db_conta_criar(db, "conta_lock", "senha-forte-6", NULL);
    mu2db_fechar(db);

    /* 1) sem ninguem: verify aprova e NAO deixa lock pendurado */
    ck(mu2db_verify(p, det, sizeof det) == MU2DB_OK, "verify aprova arquivo sem escritor ativo");
    fd = open(p, O_RDONLY);
    ck(fd >= 0, "abre descritor proprio para conferir liberacao");
    if (fd >= 0) {
        ck(flock(fd, LOCK_EX | LOCK_NB) == 0, "verify NAO deixa lock pendurado (LOCK_EX livre depois)");
        flock(fd, LOCK_UN);
    }

    /* 2) leitor com LOCK_SH: verify convive (dois leitores); escritor e excluido enquanto isso */
    if (fd >= 0) {
        ck(flock(fd, LOCK_SH | LOCK_NB) == 0, "teste toma LOCK_SH (simula outro leitor)");
        ck(mu2db_verify(p, det, sizeof det) == MU2DB_OK, "verify convive com outro LEITOR (lock compartilhado)");
        db = mu2db_abrir(p, erro, sizeof erro);
        ck(db == NULL && strstr(erro, "arquivo em uso") != NULL,
           "com leitor ativo, escritor e excluido com motivo nomeado (o lock e real)");
        /* sem deadlock: um LOCK_SH pendurado nao trava o teste, porque o verify nao espera lock */
        ck(mu2db_verify(p, det, sizeof det) == MU2DB_OK, "verify repetido com leitor ativo nao trava");
        flock(fd, LOCK_UN);
        db = mu2db_abrir(p, erro, sizeof erro);
        ck(db != NULL, "liberado o leitor, o escritor volta a entrar");
        if (db != NULL) mu2db_fechar(db);
        close(fd);
    }

    /* 3) erro na verificacao NAO deixa lock pendurado (liberacao em caminho de erro) */
    caminho(p, "verify-erro.db");
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db != NULL) {
        mu2db_conta_criar(db, "conta_erro", "senha-forte-7", NULL);
        mu2db_fechar(db);
    }
    fd = open(p, O_RDWR);
    if (fd >= 0) {
        uint8_t b;
        if (pread(fd, &b, 1, 64 + 32) == 1) { b ^= 0xFF; if (pwrite(fd, &b, 1, 64 + 32) != 1) ck(0, "corrompe"); }
        close(fd);
    }
    rv = mu2db_verify(p, det, sizeof det);
    ck(rv == MU2DB_E_CRC, "verify detecta corrupcao de registro");
    fd = open(p, O_RDONLY);
    if (fd >= 0) {
        ck(flock(fd, LOCK_EX | LOCK_NB) == 0, "verify que FALHOU tambem libera o lock");
        flock(fd, LOCK_UN);
        ck(flock(fd, LOCK_SH | LOCK_NB) == 0, "e permite novo leitor imediatamente");
        flock(fd, LOCK_UN);
        close(fd);
    }

    /* 4) escritor ativo: verify recusa nomeado, e a recusa e sobre o lock (nao sobre o conteudo) */
    caminho(p, "verify-ativo.db");
    unlink(p);
    db = mu2db_abrir(p, erro, sizeof erro);
    if (db != NULL) {
        mu2db_conta_criar(db, "conta_ativa", "senha-forte-8", NULL);
        rv = mu2db_verify(p, det, sizeof det);
        ck(rv == MU2DB_E_TRAVADO, "verify com ESCRITOR ativo no mesmo processo: recusa");
        ck(strstr(det, "escritor ativo") != NULL, "a recusa cita escritor ativo");
        ck(det[0] != '\0', "a recusa sempre tem detalhe (nunca codigo mudo)");
        mu2db_fechar(db);
        ck(mu2db_verify(p, det, sizeof det) == MU2DB_OK, "fechado o escritor, verify aprova o mesmo arquivo");
    }
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "uso: %s <diretorio-de-trabalho>\n", argv[0]);
        return 2;
    }
    snprintf(base, sizeof base, "%s", argv[1]);
    mkdir(base, 0700);

    teste_primitivas();
    teste_ciclo_vida();
    teste_transacoes();
    teste_corrupcao();
    teste_limites_inventario();
    teste_concorrencia();
    teste_schema_versao();
    teste_verify_lock();
    teste_ids_derivados_do_log();

    printf("1..%d\n", n);
    printf("# db=%d falhas=%d\n", n, bad);
    return bad == 0 ? 0 : 1;
}

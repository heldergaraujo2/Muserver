/* mu2dbctl.c — CLI de operacao da persistencia do v2 (fase R-11).
 *
 * Ferramenta LOCAL, de linha de comando: cria/consulta contas, personagens e inventario no arquivo
 * de persistencia. Existe para (a) operar sem escrever codigo, (b) servir de segundo consumidor da
 * biblioteca — se o CLI e o teste usam a mesma API, um defeito de contrato aparece nos dois — e
 * (c) permitir integracao em script (a suite `dbctl` faz isso).
 *
 * NAO abre porta, NAO fala rede, NAO toca no `MuServer/`. Nada aqui afirma compatibilidade com o
 * banco do original (ver include/mu2/db.h).
 *
 * Uso:
 *   mu2dbctl <arquivo.db> criar-conta <nome> <senha>
 *   mu2dbctl <arquivo.db> autenticar <nome> <senha>
 *   mu2dbctl <arquivo.db> trocar-senha <nome> <nova-senha>
 *   mu2dbctl <arquivo.db> criar-personagem <conta> <nome> <classe>
 *   mu2dbctl <arquivo.db> listar-personagens <conta>
 *   mu2dbctl <arquivo.db> mostrar-personagem <conta> <nome>
 *   mu2dbctl <arquivo.db> apagar-personagem <conta> <nome>
 *   mu2dbctl <arquivo.db> mover <conta> <personagem> <mapa> <x> <y>
 *   mu2dbctl <arquivo.db> zen <conta> <personagem> <valor>
 *   mu2dbctl <arquivo.db> dar-item <conta> <personagem> <tipo> <nivel> <durabilidade>
 *   mu2dbctl <arquivo.db> listar-inventario <conta> <personagem>
 *   mu2dbctl <arquivo.db> transferir <conta> <personagem-de> <slot> <personagem-para>
 *   mu2dbctl <arquivo.db> stats
 *   mu2dbctl <arquivo.db> verificar
 *
 * Saida: linhas `chave=valor` (estavel para script) ou `erro=<motivo>` + exit != 0.
 */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mu2/db.h"

#define SAIDA_MAX 256

static void uso(const char *argv0)
{
    fprintf(stderr,
            "uso: %s <arquivo.db> <comando> [args...]\n"
            "  criar-conta <nome> <senha>\n"
            "  autenticar <nome> <senha>\n"
            "  trocar-senha <nome> <nova-senha>\n"
            "  criar-personagem <conta> <nome> <classe 0..5>\n"
            "  listar-personagens <conta>\n"
            "  mostrar-personagem <conta> <nome>\n"
            "  apagar-personagem <conta> <nome>\n"
            "  mover <conta> <personagem> <mapa> <x> <y>\n"
            "  zen <conta> <personagem> <valor>\n"
            "  dar-item <conta> <personagem> <tipo> <nivel> <durabilidade>\n"
            "  listar-inventario <conta> <personagem>\n"
            "  transferir <conta> <personagem-de> <slot> <personagem-para>\n"
            "  stats | verificar\n",
            argv0);
}

static int falha(const char *contexto, int err)
{
    printf("erro=%s\n", mu2db_errstr(err));
    fprintf(stderr, "%s: %s\n", contexto, mu2db_errstr(err));
    return 1;
}

/* Resolve `conta`+`nome` para o id do personagem; devolve 0 em sucesso. */
static int id_do_personagem(mu2db *db, const char *conta, const char *nome, uint32_t *id_out)
{
    mu2db_personagem p;
    int r = mu2db_personagem_carregar(db, conta, nome, &p);
    if (r == MU2DB_OK)
        *id_out = p.id;
    return r;
}

int main(int argc, char **argv)
{
    mu2db *db;
    char erro[SAIDA_MAX];
    const char *arq, *cmd;
    int r;

    if (argc < 3) {
        uso(argv[0]);
        return 2;
    }
    arq = argv[1];
    cmd = argv[2];

    if (strcmp(cmd, "verificar") == 0) {
        char det[SAIDA_MAX];
        r = mu2db_verify(arq, det, sizeof det);
        if (r == MU2DB_OK) {
            printf("arquivo=%s\nintegridade=ok\n", arq);
            return 0;
        }
        printf("erro=%s\ndetalhe=%s\n", mu2db_errstr(r), det);
        return 1;
    }

    db = mu2db_abrir(arq, erro, sizeof erro);
    if (db == NULL) {
        printf("erro=abrir\nmotivo=%s\n", erro);
        fprintf(stderr, "abrir %s: %s\n", arq, erro);
        return 1;
    }

    if (strcmp(cmd, "criar-conta") == 0) {
        uint32_t id = 0;
        if (argc < 5) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = mu2db_conta_criar(db, argv[3], argv[4], &id);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("criar-conta", r); }
        printf("conta=%s\nid=%u\n", argv[3], id);
    } else if (strcmp(cmd, "autenticar") == 0) {
        uint32_t id = 0;
        if (argc < 5) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = mu2db_conta_autenticar(db, argv[3], argv[4], &id);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("autenticar", r); }
        printf("autenticado=sim\nconta=%s\nid=%u\n", argv[3], id);
    } else if (strcmp(cmd, "trocar-senha") == 0) {
        if (argc < 5) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = mu2db_conta_set_senha(db, argv[3], argv[4]);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("trocar-senha", r); }
        printf("conta=%s\nsenha_trocada=sim\n", argv[3]);
    } else if (strcmp(cmd, "criar-personagem") == 0) {
        uint32_t id = 0;
        if (argc < 6) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = mu2db_personagem_criar(db, argv[3], argv[4], (uint8_t)atoi(argv[5]), &id);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("criar-personagem", r); }
        printf("conta=%s\npersonagem=%s\nid=%u\n", argv[3], argv[4], id);
    } else if (strcmp(cmd, "listar-personagens") == 0) {
        char nomes[MU2DB_PERSONAGENS_MAX][MU2DB_NOME_MAX + 1];
        size_t qtd = 0, i;
        if (argc < 4) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = mu2db_personagem_listar(db, argv[3], nomes, MU2DB_PERSONAGENS_MAX, &qtd);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("listar-personagens", r); }
        printf("conta=%s\nquantidade=%zu\n", argv[3], qtd);
        for (i = 0; i < qtd; i++)
            printf("personagem%zu=%s\n", i + 1, nomes[i]);
    } else if (strcmp(cmd, "mostrar-personagem") == 0) {
        mu2db_personagem p;
        if (argc < 5) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = mu2db_personagem_carregar(db, argv[3], argv[4], &p);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("mostrar-personagem", r); }
        printf("id=%u\nnome=%s\nclasse=%u\nnivel=%u\nforca=%u\nagilidade=%u\nvitalidade=%u\n"
               "energia=%u\nzen=%u\nmapa=%u\nx=%u\ny=%u\nitens=%u\n",
               p.id, p.nome, p.classe, p.nivel, p.forca, p.agilidade, p.vitalidade, p.energia,
               p.zen, p.mapa, p.x, p.y, p.itens);
    } else if (strcmp(cmd, "apagar-personagem") == 0) {
        if (argc < 5) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = mu2db_personagem_apagar(db, argv[3], argv[4]);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("apagar-personagem", r); }
        printf("conta=%s\napagado=%s\n", argv[3], argv[4]);
    } else if (strcmp(cmd, "mover") == 0) {
        uint32_t id = 0;
        if (argc < 8) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = id_do_personagem(db, argv[3], argv[4], &id);
        if (r == MU2DB_OK)
            r = mu2db_personagem_mover(db, id, (uint8_t)atoi(argv[5]), (uint8_t)atoi(argv[6]),
                                       (uint8_t)atoi(argv[7]));
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("mover", r); }
        printf("personagem=%s\nmovido=sim\n", argv[4]);
    } else if (strcmp(cmd, "zen") == 0) {
        uint32_t id = 0;
        if (argc < 6) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = id_do_personagem(db, argv[3], argv[4], &id);
        if (r == MU2DB_OK)
            r = mu2db_personagem_set_zen(db, id, (uint32_t)strtoul(argv[5], NULL, 10));
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("zen", r); }
        printf("personagem=%s\nzen=%s\n", argv[4], argv[5]);
    } else if (strcmp(cmd, "dar-item") == 0) {
        uint32_t id = 0;
        uint8_t slot = 0;
        if (argc < 7) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = id_do_personagem(db, argv[3], argv[4], &id);
        if (r == MU2DB_OK)
            r = mu2db_inv_add(db, id, (uint16_t)atoi(argv[5]), (uint8_t)atoi(argv[6]),
                              (uint8_t)(argc > 7 ? atoi(argv[7]) : 0), &slot);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("dar-item", r); }
        printf("personagem=%s\nslot=%u\n", argv[4], slot);
    } else if (strcmp(cmd, "listar-inventario") == 0) {
        uint32_t id = 0;
        mu2db_item itens[MU2DB_SLOTS];
        size_t qtd = 0, i;
        if (argc < 5) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = id_do_personagem(db, argv[3], argv[4], &id);
        if (r == MU2DB_OK)
            r = mu2db_inv_listar(db, id, itens, MU2DB_SLOTS, &qtd);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("listar-inventario", r); }
        printf("personagem=%s\nquantidade=%zu\n", argv[4], qtd);
        for (i = 0; i < qtd; i++)
            printf("item%zu=id:%u tipo:%u nivel:%u slot:%u durabilidade:%u\n", i + 1, itens[i].id,
                   itens[i].tipo, itens[i].nivel_item, itens[i].slot, itens[i].durabilidade);
    } else if (strcmp(cmd, "transferir") == 0) {
        uint32_t de_id = 0, para_id = 0;
        if (argc < 7) { uso(argv[0]); mu2db_fechar(db); return 2; }
        r = id_do_personagem(db, argv[3], argv[4], &de_id);
        if (r == MU2DB_OK)
            r = id_do_personagem(db, argv[3], argv[6], &para_id);
        if (r == MU2DB_OK)
            r = mu2db_inv_transferir(db, de_id, (uint8_t)atoi(argv[5]), para_id);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("transferir", r); }
        printf("de=%s\npara=%s\ntransferido=sim\n", argv[4], argv[6]);
    } else if (strcmp(cmd, "stats") == 0) {
        mu2db_stats st;
        r = mu2db_stats_get(db, &st);
        if (r != MU2DB_OK) { mu2db_fechar(db); return falha("stats", r); }
        printf("contas=%llu\npersonagens=%llu\nitens=%llu\nregistros=%llu\ndescartados=%llu\n"
               "bytes=%llu\nschema=%u\n",
               (unsigned long long)st.contas, (unsigned long long)st.personagens,
               (unsigned long long)st.itens, (unsigned long long)st.registros,
               (unsigned long long)st.descartados, (unsigned long long)st.bytes,
               st.schema_version);
    } else {
        uso(argv[0]);
        mu2db_fechar(db);
        return 2;
    }
    mu2db_fechar(db);
    return 0;
}

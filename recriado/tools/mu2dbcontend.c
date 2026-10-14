/* mu2dbcontend.c — driver de CONTENCAO para os testes de concorrencia (F3).
 *
 * POR QUE ESTE PROGRAMA EXISTE
 * O comportamento de `mu2db_verify` diante de uma escrita ativa (e o inverso) nao pode ser provado
 * por um teste que *simula* lock: simular lock mede a simulacao. Ele precisa de um ESCRITOR REAL
 * segurando o arquivo pelo tempo em que outro processo tenta entrar. Este driver e' esse escritor:
 * usa a MESMA `mu2db_abrir` que o servico usa (portanto o mesmo `flock(LOCK_EX|LOCK_NB)` pelo ciclo
 * de vida do handle), executa TRANSACOES reais (registros com CRC32C, commit de verdade) e sai.
 *
 * O que ele NAO faz: nao sobe servico, nao abre socket, nao le/escreve em `MuServer/`, nao contorna
 * lock nenhum e nao simula recusa — e' um usuario legitimo da biblioteca. Nao julga nada: quem julga
 * e' a suite, olhando o que os OUTROS processos conseguiram fazer enquanto este estava dentro.
 *
 * Uso: mu2dbcontend <arquivo.db> <n_ops> [--gap-ms N] [--prefix P] [--hold-until-arquivo ARQ]
 *   --gap-ms N          pausa entre transacoes (alarga a janela de contenção de propósito)
 *   --prefix P          prefixo dos nomes criados (padrao: con)
 *   --hold-until-arquivo ARQ
 *                       depois das transacoes, SEGURA o lock ate o arquivo ARQ existir. Existe para
 *                       o teste poder dizer "enquanto HAVIA escritor" sem depender de sorte de
 *                       agendamento: sem isso a suíte mediria uma corrida entre abrir e verificar.
 *
 * Saida (chave=valor, uma por linha, sempre em stdout):
 *   lock=obtido                 logo apos o open: daqui para frente outro processo NAO abre o mesmo
 *                               arquivo com a biblioteca (e o verify so' recusa nomeado)
 *   hold=aguardando             (so' com --hold-until-arquivo) lock ainda tomado, transacoes feitas
 *   hold=liberado               o arquivo de liberacao apareceu; a partir daqui o lock sera' solto
 *   op=<i> estado=ok            uma transacao commitada por linha
 *   # contend=<n> falhas=<f>    resumo (contrato de saida do projeto)
 * Exit: 0 tudo commitado; 3 recusado na abertura (motivo= diz por que); 4 falha de operacao.
 */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "mu2/db.h"

static void dorme_ms(long ms)
{
    struct timespec ts;
    if (ms <= 0)
        return;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

int main(int argc, char **argv)
{
    const char *arq, *prefixo = "con", *hold_arq = NULL;
    long n_ops = 0, gap_ms = 0;
    char erro[256];
    mu2db *db;
    long i;
    long falhas = 0;
    int a;

    if (argc < 3) {
        fprintf(stderr, "uso: %s <arquivo.db> <n_ops> [--gap-ms N] [--prefix P]\n", argv[0]);
        return 2;
    }
    arq = argv[1];
    n_ops = strtol(argv[2], NULL, 10);
    if (n_ops < 1) {
        fprintf(stderr, "%s: n_ops invalido\n", argv[0]);
        return 2;
    }
    for (a = 3; a < argc; a++) {
        if (strcmp(argv[a], "--gap-ms") == 0 && a + 1 < argc) {
            gap_ms = strtol(argv[++a], NULL, 10);
        } else if (strcmp(argv[a], "--prefix") == 0 && a + 1 < argc) {
            prefixo = argv[++a];
        } else if (strcmp(argv[a], "--hold-until-arquivo") == 0 && a + 1 < argc) {
            hold_arq = argv[++a];
        } else {
            fprintf(stderr, "%s: argumento desconhecido: %s\n", argv[0], argv[a]);
            return 2;
        }
    }

    erro[0] = '\0';
    db = mu2db_abrir(arq, erro, sizeof erro);
    if (db == NULL) {
        /* recusa nomeada: e' o estado que a suite cobra quando outro processo esta' escrevendo */
        printf("erro=abrir\nmotivo=%s\n", erro);
        return 3;
    }
    /* A partir daqui o arquivo esta' com LOCK_EX ate mu2db_fechar(); declarar isso na saida e'
     * o sincronismo que a suite usa para saber que a contenção e' real, e nao corrida. */
    printf("lock=obtido\n");
    fflush(stdout);

    for (i = 0; i < n_ops; i++) {
        char nome[64];
        char senha[64];
        uint32_t id = 0;
        int r;

        snprintf(nome, sizeof nome, "%s%ld", prefixo, i);
        snprintf(senha, sizeof senha, "senha-de-teste-%ld", i);
        r = mu2db_tx_begin(db);
        if (r == MU2DB_OK)
            r = mu2db_conta_criar(db, nome, senha, &id);
        if (r == MU2DB_OK)
            r = mu2db_tx_commit(db);
        else if (r != MU2DB_OK)
            (void)mu2db_tx_rollback(db);
        if (r != MU2DB_OK) {
            printf("op=%ld estado=falha erro=%s\n", i, mu2db_errstr(r));
            falhas++;
        } else {
            printf("op=%ld estado=ok conta=%s\n", i, nome);
        }
        fflush(stdout);
        dorme_ms(gap_ms);
    }

    if (hold_arq != NULL && falhas == 0) {
        long esperou_ms = 0;
        printf("hold=aguardando\n");
        fflush(stdout);
        while (access(hold_arq, F_OK) != 0) {
            dorme_ms(10);
            esperou_ms += 10;
            if (esperou_ms > 60000) {   /* teto: o gate nao pode ficar pendurado num teste */
                printf("hold=timeout\n");
                break;
            }
        }
        if (esperou_ms <= 60000)
            printf("hold=liberado\n");
        fflush(stdout);
    }
    mu2db_fechar(db);
    printf("# contend=%ld falhas=%ld\n", n_ops, falhas);
    return falhas == 0 ? 0 : 4;
}

/* proto.h — opcodes do servico de ensaio mud2 (fase R-4, decisao D2-16).
 *
 * Estes codigos sao do v2. NAO sao opcodes do MU Server original e nao ha aqui nenhuma
 * afirmacao de compatibilidade com o ConnectServer.exe: a comparacao com o protocolo real e
 * trabalho da fase R-6, a ser feita a partir do binario (a procura por HEAD_SIZE/PacketSize/
 * opcode em MuServer/Data/Script/System/ProtocolCore.lua retornou zero ocorrencias).
 *
 * Regra de desenho: tres opcodes, todos com resposta de tamanho previsivel, para que os testes
 * de rede possam calcular quantos bytes deveriam voltar e distinguir "nao veio" de "veio menos".
 */
#ifndef MU2_PROTO_H
#define MU2_PROTO_H

#define MU2_CODE_PING 0x0001u  /* corpo ignorado; resposta de corpo vazio (sonda de vida) */
#define MU2_CODE_ECHO 0x0002u  /* resposta com o mesmo corpo (0..MU2_MAX_BODY) */
#define MU2_CODE_STATS 0x0003u /* resposta com a linha de metricas em ASCII */

/* Prefixo da linha devolvida por MU2_CODE_STATS. O formato completo e contrato
 * (docs/NEXT_TASK.md, item 3):
 *   STATS registros= usados= conns= frames= rejects= queue_full_closes= uptime_ms= slotsz= maxbody=
 * `registros` e a capacidade de vagas de conexao, `usados` quantas estao abertas agora,
 * `slotsz` e o tamanho em bytes da vaga unica de resposta (MU2_MAX_FRAME).
 */
#define MU2_STATS_PREFIX "STATS "

#endif /* MU2_PROTO_H */

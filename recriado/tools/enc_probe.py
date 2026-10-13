#!/usr/bin/env python3
"""enc_probe.py — etapa `enc`: o que a MEDICAO sustenta sobre a cifragem do Lua do cliente.

Somente leitura sobre MU_REF_DATA (nunca executa binario, nunca escreve). Mede o material de
`Tools/Gerador de Main/LuaEncTool/` e imprime um TSV chave/valor/obs; onde nao ha evidencia, a linha
diz `desconhecido` em vez de adivinhar.

Regra desta etapa (declarada antes de medir): nada aqui afirma que a cifragem foi identificada. A
unica prova aceita de decifracao e' o texto decifrado casar BYTE A BYTE com o `ClientDecrypted` do
mesmo caminho. Isso NAO acontece (ver reports/enc-cifragem-lua.md), portanto:

  * `enc_recorrencia_*`  mede uma ESTRUTURA observada (janela de 3 bytes do proprio cifrado), nao o
    algoritmo: a funcao F da janela permanece desconhecida em 2**32 - 21 931 pontos do dominio;
  * `enc_excl_*`          mede FAMILIAS refutadas, com o numero medido (nao "parece");
  * `enc_f23`            fica BLOCKED: sem decodificador nao existe o que corromper e conferir.

Criterios declarados ANTES da medicao (cada um virou assercao em tests/lua-enc.sh):
  C1 pares cifrados tem 8 bytes de cabecalho fixo e tamanho == claro apagado(LF->CRLF) + 8;
  C2 cifragem e' deterministica: prefixo de claro igual => prefixo de cifrado igual;
  C3 a janela de 3 bytes do cifrado + o byte de claro determinam o proximo byte (0 discordancia);
  C4 a janela de 3 e' NECESSARIA: com 2 bytes o mesmo teste acusa discordancia (> 0);
  C5 o keystream (C^A) e a diferenca (C-A mod 256) NAO sao funcao da janela (refuta keystream puro);
  C6 nenhuma chave repetida de periodo <= 512 satisfaz o corpus (refuta XOR/ADD repetido);
  C7 o payload nao e' multiplo de 8 nem de 16 => refuta ECB (com ou sem padding);
  C8 F23 (corromper 1 byte do cifrado e acusar o offset) exige decodificador => BLOCKED.

uso: enc_probe.py [--ref CAMINHO]   (ou MU_REF_DATA no ambiente)
"""
import argparse
import hashlib
import os
import pathlib
import sys

HEADER = bytes.fromhex("28aa2191a6dd35f7")
PREFIXO = b"local CONFIG = r"

# rotulos das duas arvores de pares do material
ARVORES = (("ClientDecrypted", "ClientEncrypted"), ("ServerDecrypted", "ServerEncrypted"))


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 16), b""):
            h.update(b)
    return h.hexdigest()


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 16), b""):
            h.update(b)
    return h.hexdigest()


def entropia(blocos):
    freq = [0] * 256
    n = 0
    for b in blocos:
        for x in b:
            freq[x] += 1
        n += len(b)
    if not n:
        return 0.0
    import math
    h = 0.0
    for c in freq:
        if c:
            p = c / n
            h -= p * math.log2(p)
    return h


def carrega_pares(enc):
    """(claro, cifrado, arvore, relativo) de cada par do material — a lista e' medida, nao suposta."""
    pares = []
    for claro_dir, cif_dir in ARVORES:
        d = enc / claro_dir
        if not d.is_dir():
            continue
        for p in sorted(x for x in d.rglob("*") if x.is_file()):
            c = enc / cif_dir / p.relative_to(d)
            if c.is_file():
                pares.append((p, c, claro_dir.split("D")[0], str(p.relative_to(d))))
    pares.sort(key=lambda t: (t[2], t[3]))
    return pares


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default=os.environ.get("MU_REF_DATA", "../MuServer"))
    a = ap.parse_args()
    ref = pathlib.Path(a.ref)
    enc = ref / "Tools/Gerador de Main/LuaEncTool"
    if not enc.is_dir():
        sys.stderr.write("enc_probe: material ausente (%s)\n" % enc)
        return 2

    linhas = []

    def add(chave, valor, obs=""):
        linhas.append((str(chave), str(valor), str(obs)))

    ini = enc / "EncryptorTool.ini"
    if ini.is_file():
        txt = ini.read_text(errors="replace")
        cust = ""
        for ln in txt.splitlines():
            if "=" in ln and "ustomer" in ln.split("=")[0]:
                cust = ln.split("=", 1)[1].strip()
        add("enc_ini_customername", cust or "desconhecido", "EncryptorTool.ini")

    pares = carrega_pares(enc)
    add("enc_pares", len(pares), "ClientDecrypted/ x ClientEncrypted/ + ServerDecrypted/ x ServerEncrypted/")
    if not pares:
        sys.stderr.write("enc_probe: nenhum par encontrado\n")
        return 2

    identicos, cifrados = [], []
    for claro, cif, arvore, rel in pares:
        cb, eb = claro.read_bytes(), cif.read_bytes()
        if cb == eb:
            identicos.append((claro, cif, arvore, rel, cb))
        else:
            cifrados.append((claro, cif, arvore, rel, cb, eb))
    add("enc_nao_cifrados", len(identicos), "pares byte-identicos: nada foi cifrado aqui")
    for claro, cif, arvore, rel, cb in identicos:
        add("enc_nao_cifrado", md5(claro), "%s | %s | %d B" % (arvore, rel, len(cb)))
    add("enc_cifrados", len(cifrados), "pares com bytes diferentes")

    # ---- C1: cabecalho fixo e relacao de tamanho (LF -> CRLF)
    hdr_ok = 0
    tam_ok = 0
    for claro, cif, arvore, rel, cb, eb in cifrados:
        if eb[:8] == HEADER:
            hdr_ok += 1
        n_lf = cb.count(b"\n")
        if len(eb) - 8 == len(cb) + n_lf:
            tam_ok += 1
    add("enc_header8", HEADER.hex(), "primeiros 8 bytes dos cifrados")
    add("enc_header8_presente", "%d/%d" % (hdr_ok, len(cifrados)), "criterio C1")
    add("enc_tamanho_crlf", "%d/%d" % (tam_ok, len(cifrados)),
        "C1: len(cif) - 8 == len(claro) + nº de LF (LF->CRLF, sem padding)")

    # ---- C2: determinismo por prefixo comum de claro
    dados = [(claro, cif, cb, eb, cb.replace(b"\n", b"\r\n")) for claro, cif, arvore, rel, cb, eb in cifrados]
    min_prefixo, n_prefixo, prefixo_viol = 0, 0, 0
    for i in range(len(dados)):
        for j in range(i + 1, len(dados)):
            ai, aj = dados[i][4], dados[j][4]
            L = 0
            while L < len(ai) and L < len(aj) and ai[L] == aj[L]:
                L += 1
            if L == 0:
                continue
            n_prefixo += 1
            if dados[i][3][8:8 + L] != dados[j][3][8:8 + L]:
                prefixo_viol += 1
            min_prefixo = L if min_prefixo == 0 else min(min_prefixo, L)
    add("enc_determinismo_prefixo", "%d violacoes em %d pares com prefixo de claro comum" % (prefixo_viol, n_prefixo),
        "C2: menor prefixo comum=%d B; %s -> prefixo de cifrado igual" % (min_prefixo, PREFIXO.decode()))
    # caso nomeado (o mesmo trecho aparece no cliente e no servidor)
    vistos = {}
    for claro, cif, arvore, rel, cb, eb in cifrados:
        A = cb.replace(b"\n", b"\r\n")
        k = A.find(PREFIXO)
        if k >= 0:
            vistos.setdefault(eb[8 + k:8 + k + len(PREFIXO)].hex(), []).append(
                "%s|%s|pos=%d" % (arvore, rel, k))
    for h, onde in sorted(vistos.items()):
        add("enc_prefixo_conhecido", h, "%s -> %s" % (PREFIXO.decode(), ",".join(sorted(onde))))

    # ---- C3/C4: recorrencia com janela de 3 bytes do proprio cifrado
    # contexto = (A[j], C[j-1], C[j-2], C[j-3]) -> C[j];  C e' o arquivo cifrado INTEIRO (o
    # cabecalho de 8 B entra como historia inicial), A e' o claro com LF->CRLF.
    ctx3, ctx2, ctx1 = {}, {}, {}
    rep3 = disc3 = prof_dif = 0
    rep2 = disc2 = 0
    rep1 = disc1 = 0
    entre_rep = entre_disc = 0
    amb = amb_cmp = 0
    ks, ksrep, ksdisc = {}, 0, 0          # (C1,C2,C3) -> (C^A)
    dif, difrep, difdisc = {}, 0, 0       # (C1,C2,C3) -> ((C-A) mod 256)
    janela = {}                            # (C1,C2,C3) -> {A: C}  (ambiguitdade)
    for fi, (claro, cif, arvore, rel, cb, eb) in enumerate(cifrados):
        A = cb.replace(b"\n", b"\r\n")
        S = HEADER + eb[8:]
        if len(S) != 8 + len(A):
            continue
        for j in range(len(A)):
            S1, S2, S3 = S[8 + j - 1], S[8 + j - 2], S[8 + j - 3]
            saida = S[8 + j]
            k3 = (A[j], S1, S2, S3)
            if k3 in ctx3:
                rep3 += 1
                outro, fi0, j0, prof0 = ctx3[k3]
                if outro != saida:
                    disc3 += 1
                if fi != fi0:
                    entre_rep += 1
                    if outro != saida:
                        entre_disc += 1
                # historia profunda: A[j-1] e C[j-4], C[j-5] (fora da janela declarada)
                prof_a = (A[j - 1] if j >= 1 else None,
                          S[8 + j - 4] if j >= 4 else None,
                          S[8 + j - 5] if j >= 5 else None)
                if prof_a != prof0:
                    prof_dif += 1
            else:
                ctx3[k3] = (saida, fi, j, (A[j - 1] if j >= 1 else None,
                                           S[8 + j - 4] if j >= 4 else None,
                                           S[8 + j - 5] if j >= 5 else None))
            k2 = (A[j], S1, S2)
            if k2 in ctx2:
                rep2 += 1
                if ctx2[k2] != saida:
                    disc2 += 1
            else:
                ctx2[k2] = saida
            k1 = (A[j], S1)
            if k1 in ctx1:
                rep1 += 1
                if ctx1[k1] != saida:
                    disc1 += 1
            else:
                ctx1[k1] = saida
            kj = (S1, S2, S3)
            if kj in ks:
                ksrep += 1
                if ks[kj] != (saida ^ A[j]):
                    ksdisc += 1
            else:
                ks[kj] = saida ^ A[j]
            if kj in dif:
                difrep += 1
                if dif[kj] != (saida - A[j]) & 0xFF:
                    difdisc += 1
            else:
                dif[kj] = (saida - A[j]) & 0xFF
            # mesma janela, A diferente, mesmo C => decifracao ambigua (nao pode acontecer)
            w = janela.setdefault(kj, {})
            if w and A[j] not in w:
                for A0 in w:
                    amb_cmp += 1
                    if w[A0] == saida:
                        amb += 1
                w[A[j]] = saida
            elif not w:
                w[A[j]] = saida
    add("enc_recorrencia_janela3", "%d/%d" % (disc3, rep3),
        "C3: (A[j],C[j-1..j-3]) -> C[j]: discordancia/repeticao (exigido 0)")
    add("enc_recorrencia_janela3_entre_arquivos", "%d/%d" % (entre_disc, entre_rep),
        "C3 entre arquivos: repeticao vista em OUTRO arquivo (exigido 0)")
    add("enc_recorrencia_janela3_historia_profunda", "%d/%d" % (prof_dif, rep3),
        "das repeticoes, quantas tem A[j-1] e C[j-4..j-5] DIFERENTES (e mesmo assim casam)")
    add("enc_recorrencia_janela2", "%d/%d" % (disc2, rep2), "C4 controle: 2 bytes => discordancia > 0")
    # controle de alinhamento: o A declarado e' o claro com LF->CRLF. Se a hipotese de alinhamento
    # estivesse errada (ex.: claro cru + preenchimento no fim), a MESMA janela deixaria de fechar.
    ctx3b, repb, discb = {}, 0, 0
    for claro, cif, arvore, rel, cb, eb in cifrados:
        A2 = cb + b"\x00" * (len(eb) - 8 - len(cb))
        S = HEADER + eb[8:]
        for j in range(len(A2)):
            k3 = (A2[j], S[8 + j - 1], S[8 + j - 2], S[8 + j - 3])
            if k3 in ctx3b:
                repb += 1
                if ctx3b[k3] != S[8 + j]:
                    discb += 1
            else:
                ctx3b[k3] = S[8 + j]
    add("enc_controle_alinhamento", "%d/%d" % (discb, repb),
        "C3': mesma janela com alinhamento ERRADO (claro cru + zeros no fim) => discordancia > 0")
    # controle do VALOR dos bytes inseridos: trocar CRLF por 00 00 mantem o alinhamento e a
    # contagem, e ainda assim fecha. Ou seja: esta medicao NAO decide o valor inserido (decide a
    # contagem, C1, e o alinhamento, controle acima). Registrado para nao virar afirmacao a mais.
    ctx3c, repc, discc = {}, 0, 0
    for claro, cif, arvore, rel, cb, eb in cifrados:
        A3 = cb.replace(b"\n", b"\x00\x00")
        S = HEADER + eb[8:]
        for j in range(len(A3)):
            k3 = (A3[j], S[8 + j - 1], S[8 + j - 2], S[8 + j - 3])
            if k3 in ctx3c:
                repc += 1
                if ctx3c[k3] != S[8 + j]:
                    discc += 1
            else:
                ctx3c[k3] = S[8 + j]
    add("enc_controle_valor_inserido", "%d/%d" % (discc, repc),
        "C3'': LF->00 00 (mesmo alinhamento) tambem fecha: o VALOR dos bytes inseridos nao e' decidido aqui")
    add("enc_recorrencia_janela1", "%d/%d" % (disc1, rep1), "C4 controle: 1 byte => discordancia > 0")
    add("enc_janela_ambiguidade", "%d/%d" % (amb, amb_cmp),
        "mesma janela + claro diferente => mesmo cifrado? (0 e' necessario para decifrar)")
    add("enc_keystream_janela", "%d/%d" % (ksdisc, ksrep),
        "C5: (C1,C2,C3) -> (C^A) nao fecha => keystream depende do claro, nao so da janela")
    add("enc_diferenca_janela", "%d/%d" % (difdisc, difrep),
        "C5': (C1,C2,C3) -> (C-A mod 256) nao fecha")

    # ---- C6: chave repetida (XOR)
    fluxo = b"".join(d[4] for d in dados)
    ksfluxo = bytes(x ^ y for x, y in zip(fluxo, b"".join(d[3][8:] for d in dados)))
    melhor_k = 0
    for k in range(1, 513):
        if k > len(ksfluxo) // 2:
            break
        if all(ksfluxo[i] == ksfluxo[i % k] for i in range(k, len(ksfluxo))):
            melhor_k = k
            break
    add("enc_excl_xor_repetido", "0 chaves com periodo <= 512" if melhor_k == 0 else "candidato k=%d" % melhor_k,
        "C6: keystream concatenado (%d B) testado para todo periodo k em 1..512" % len(ksfluxo))

    def taxa_periodo(k, limite=None):
        n = len(ksfluxo) if limite is None else min(len(ksfluxo), limite)
        return sum(1 for i in range(k, n) if ksfluxo[i] == ksfluxo[i % k]) / max(n - k, 1)

    melhor = max(range(1, 513), key=lambda k: taxa_periodo(k, 2048))
    add("enc_excl_xor_repetido_melhor",
        "melhor k=%d: %.2f%% de acerto (prefixo de 2048 B), %.2f%% no corpus inteiro"
        % (melhor, 100 * taxa_periodo(melhor, 2048), 100 * taxa_periodo(melhor)),
        "C6: mesmo a MELHOR periodicidade de 1..512 nao passa de ~1/4 de acerto => XOR/ADD repetido refutado")

    # ---- C7: ECB
    tamanhos = [len(eb) - 8 for _, _, _, _, _, eb in cifrados]
    nao_mult = sum(1 for pl in tamanhos if pl % 8 and pl % 16)
    from math import gcd
    g = 0
    for pl in tamanhos:
        g = gcd(g, pl)
    add("enc_excl_ecb", "gcd(payloads)=%d, %d/%d nao multiplos de 8 nem de 16" % (g, nao_mult, len(cifrados)),
        "C7: ECB exigiria payload multiplo do bloco em TODOS; payloads=%s"
        % ",".join(str(t) for t in sorted(tamanhos)))

    # ---- familias adicionais refutadas, com o numero medido (declaradas antes de medir)
    amostras = []
    for claro, cif, arvore, rel, cb, eb in cifrados:
        A = cb.replace(b"\n", b"\r\n")
        S = HEADER + eb[8:]
        for j in range(len(A)):
            amostras.append((A[j], S[8 + j - 1], S[8 + j - 2], S[8 + j - 3], S[8 + j]))

    def rot(x, r):
        return ((x << r) | (x >> (8 - r))) & 0xFF if r else x

    INDICES = {
        "A^S1^S2^S3": lambda a, s1, s2, s3: a ^ s1 ^ s2 ^ s3,
        "A+S1+S2+S3": lambda a, s1, s2, s3: (a + s1 + s2 + s3) & 0xFF,
        "S1^S2^S3": lambda a, s1, s2, s3: s1 ^ s2 ^ s3,
        "S1+S2+S3": lambda a, s1, s2, s3: (s1 + s2 + s3) & 0xFF,
        "(A*3+S1)": lambda a, s1, s2, s3: (a * 3 + s1) & 0xFF,
        "(A<<1)^S1": lambda a, s1, s2, s3: ((a << 1) ^ s1) & 0xFF,
    }
    for modo in ("xor", "soma"):
        melhor_nome, melhor_err = "", 100.0
        for nome, g in INDICES.items():
            cont = {}
            for a, s1, s2, s3, c in amostras:
                v = (c ^ a) if modo == "xor" else ((c - a) & 0xFF)
                k = (g(a, s1, s2, s3), v)
                cont[k] = cont.get(k, 0) + 1
            # erro minimo possivel: escolher, por indice, o valor mais frequente
            tabela = {}
            for (gi, v), n in cont.items():
                if gi not in tabela or n > tabela[gi][1]:
                    tabela[gi] = (v, n)
            acertos = sum(n for _, n in tabela.values())
            err = 100.0 * (1 - acertos / max(len(amostras), 1))
            if err < melhor_err:
                melhor_nome, melhor_err = nome, err
        add("enc_excl_tabela_%s" % modo, "%.2f%% de erro (indice %s)" % (melhor_err, melhor_nome),
            "familia C = A %s T[g] com g entre 6 indices de (A,S1,S2,S3): melhor caso ainda erra"
            % ("xor" if modo == "xor" else "mais"))

    # ARX limitado e declarado: C = ((A^ka) + rot(S1,r1) + rot(S2,r2) + rot(S3,r3) + kc) & 255
    # com ka,kc em 0..255 e r em 0..3; kc sai da primeira amostra e a verificacao usa as primeiras
    # 512 amostras (subconjunto DECLARADO; nenhum sobrevivente e' verificado no corpus inteiro).
    SUB = amostras[:512]
    sobre = 0
    for ka in range(256):
        for r1 in range(4):
            for r2 in range(4):
                for r3 in range(4):
                    a0, s10, s20, s30, c0 = amostras[0]
                    kc = (c0 - ((a0 ^ ka) + rot(s10, r1) + rot(s20, r2) + rot(s30, r3))) & 0xFF
                    if all(((a ^ ka) + rot(s1, r1) + rot(s2, r2) + rot(s3, r3) + kc) & 0xFF == c
                           for a, s1, s2, s3, c in SUB):
                        sobre += 1
    add("enc_excl_arx", "%d sobreviventes em 16384 combinacoes" % sobre,
        "familia ((A^ka)+rot(S1,r1)+rot(S2,r2)+rot(S3,r3)+kc) & 255, r em 0..3, kc resolvido e"
        " conferido nas 512 primeiras amostras (subconjunto declarado)")

    # ---- entropia (informacao medida, nao conclusao)
    add("enc_entropia_claro", "%.3f" % entropia([d[4] for d in dados]),
        "bits/byte sobre o claro normalizado, %d B" % sum(len(d[4]) for d in dados))
    add("enc_entropia_cifrado", "%.3f" % entropia([d[3][8:] for d in dados]), "bits/byte sobre o payload cifrado")

    # ---- vetores de ouro (claro, cifrado) por hash: o que a etapa pode fixar
    for claro, cif, arvore, rel in pares:
        chave = ("enc_par_" + rel.replace("/", "_").replace(".", "_").replace(" ", "_"))
        add(chave, sha256(cif), "%s | claro %d B sha256 %s | cifrado %d B" %
            (arvore, claro.stat().st_size, sha256(claro)[:16], cif.stat().st_size))

    exe = enc / "LuaEncryptorTool.exe"
    if exe.is_file():
        add("enc_exe", sha256(exe), "%d B; NAO executado por esta etapa" % exe.stat().st_size)
    add("enc_executado", 0, "regra do projeto: binario do cliente nunca e' executado")
    prem = enc / "ScriptSystem.premium"
    if prem.is_file():
        add("enc_premium", sha256(prem), "%d B; nao classificado (nao afirmado nem negado)" % prem.stat().st_size)
    add("enc_f23", "blocked", "F23 exige decodificador; a funcao da janela nao foi determinada")

    print("chave\tvalor\tobs")
    for c, v, o in linhas:
        print("%s\t%s\t%s" % (c, v, o))
    return 0


if __name__ == "__main__":
    sys.exit(main())

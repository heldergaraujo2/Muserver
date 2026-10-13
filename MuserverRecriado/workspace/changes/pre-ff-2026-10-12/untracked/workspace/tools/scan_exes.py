#!/usr/bin/env python3
"""Varredura de todos os .exe: arquitetura, LAA, protetor/packer, entropy das secoes."""
import sys, os, glob, math, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pe import PE, MACHINE

MARKERS = {'.themida': 'Themida/WinLicense', '.vmp0': 'VMProtect', '.vmp1': 'VMProtect',
           '.vmp': 'VMProtect', '.enigma1': 'Enigma', '.enigma2': 'Enigma',
           '.pentry': 'ASPack', '.boot': 'MPRESS', '.adata': 'packer/diversos',
           '.petite': 'Petite', '.nsp0': 'NsPack', '.upx0': 'UPX'}


def entropy(b):
    if not b:
        return 0.0
    f = [0] * 256
    for x in b:
        f[x] += 1
    n = len(b)
    return -sum((c / n) * math.log2(c / n) for c in f if c)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '/home/user/Muserver/MuServer'
    print('%-46s %-5s %-4s %-7s %-8s %s' % ('EXE', 'ARCH', 'LAA', 'IMG', 'ENTmax', 'PROTETOR / EP'))
    print('-' * 108)
    rows = []
    for p in sorted(glob.glob(root + '/**/*.exe', recursive=True)):
        try:
            pe = PE(p)
        except Exception as e:
            print('%-46s ERRO: %s' % (os.path.relpath(p, root)[:44], e))
            continue
        names = [s['name'] for s in pe.secs]
        prot = set()
        for m, lbl in MARKERS.items():
            if m in names:
                prot.add(lbl)
        unnamed = sum(1 for n in names if len(n.replace('\x00', '').strip()) < 3
                      and n not in ('.rsrc', '.text', '.data', '.rdata', '.reloc', '.edata',
                                    '.idata', '.tls', '.didat'))
        if unnamed >= 2:
            prot.add('nomes-ofuscados(%d)' % unnamed)
        eps = [s['name'] for s in pe.secs
               if s['va'] <= pe.entry < s['va'] + max(s['vsize'], s['rawsize'])]
        epn = eps[0] if eps else '?'
        if epn not in ('.text', '') and ('themida' in epn or 'vmp' in epn or epn.strip('\x00') == ''):
            prot.add('EP-fora-do-.text')
        ents = []
        for s in pe.secs:
            if s['rawsize'] and s['rawsize'] < 60 * 1024 * 1024 and s['rawoff'] + s['rawsize'] <= len(pe.d):
                ents.append((entropy(pe.d[s['rawoff']:s['rawoff'] + min(s['rawsize'], 2 * 1024 * 1024)]), s['name']))
        emax = max(ents)[0] if ents else 0
        if emax > 7.2 and not prot:
            prot.add('alta-entropy(%.2f)' % emax)
        rows.append((os.path.relpath(p, root), MACHINE.get(pe.machine, '?'),
                     'SIM' if pe.laa else 'NAO', '%.1fM' % (pe.sizeimg / 1048576),
                     '%.2f' % emax, (','.join(sorted(prot)) or 'nenhum') + ' | EP=' + (epn or '?')))
    for r in sorted(rows, key=lambda x: -(0 if 'nenhum' in x[5] else 1)):
        print('%-46s %-5s %-4s %-7s %-8s %s' % (r[0][:45], r[1], r[2], r[3], r[4], r[5]))
    print()
    print('LAA ausente em:', sum(1 for r in rows if r[2] == 'NAO' and r[1] == 'x86'), 'de', len(rows), 'binarios')


if __name__ == '__main__':
    main()

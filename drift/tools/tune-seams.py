"""Pick seam rows that force you through a stage instead of past it.

A sector is only as long as its shortest route. If stage 2 is entered at row 3
and exited at row 2, everything in it is decoration — which is exactly the
"walk all the way through at the top" problem.

For each seam this enumerates every row where both chambers can actually be
stood on, then chooses the combination that maximises vertical travel between
consecutive seams, keeping only combinations the solver still passes.
"""
import re, json, itertools
exec(open('skipcheck.py').read().split('print(f"{')[0])   # load(), reach()

SRC = '/mnt/user-data/outputs/drift/src/levels.js'

def split(rows):
    W = len(rows[0]); n = (W - 25) // 24 + 1
    ch = []
    for k in range(n):
        if k == 0: ch.append([r[0:24] + "#" for r in rows])
        else:
            s = 24 * k + 1
            ch.append(["#" + r[s:s+24] if k == n-1 else "#" + r[s:s+23] + "#" for r in rows])
    doors = [{r for r in range(len(rows)) if rows[r][24*k] != "#"} for k in range(1, n)]
    return ch, doors

def join(ch, doors):
    out = list(ch[0])
    for k, nxt in enumerate(ch[1:]):
        out = [out[r][:-1] + ("." if r in doors[k] else "#") + nxt[r][1:] for r in range(len(out))]
    return out

def candidates(a, b):
    """Rows where a seam is usable: open on both sides, with something to stand on."""
    ok = []
    for r in range(1, len(a) - 1):
        if a[r][23] in "#~^" or b[r][1] in "#~^": continue
        support = (a[r+1][23] in "#~-=%" or b[r+1][1] in "#~-=%" or
                   a[r][23] == "Z" or b[r][1] == "Z")
        if support: ok.append(r)
    return ok

def objectives_ok(rows, seen):
    for r in range(len(rows)):
        for c in range(len(rows[0])):
            if rows[r][c] in "SBEACo" and (c, r) not in seen: return False
    return True

results = {}
for name, kit, rows, mp in load(SRC):
    ch, doors = split(rows)
    if len(ch) < 3: results[name] = None; continue
    cands = [candidates(ch[i], ch[i+1]) for i in range(len(ch)-1)]
    if any(not c for c in cands): results[name] = None; continue
    P = next((r) for r in range(len(rows)) for c in range(len(rows[0])) if rows[r][c] == 'P')
    best = None
    combos = list(itertools.product(*[c[:14] for c in cands]))
    # prefer the biggest zigzag: far from the previous seam, far from the spawn row
    combos.sort(key=lambda t: -(abs(t[0]-P) + sum(abs(t[i+1]-t[i]) for i in range(len(t)-1))))
    for combo in combos[:40]:
        nd = [{r} for r in combo]
        cand = join(ch, nd)
        seen = reach(cand, mp, kit)
        if objectives_ok(cand, seen):
            zig = abs(combo[0]-P) + sum(abs(combo[i+1]-combo[i]) for i in range(len(combo)-1))
            best = (combo, zig); break
    old = tuple(sorted(d)[0] for d in doors)
    oldzig = abs(old[0]-P) + sum(abs(old[i+1]-old[i]) for i in range(len(old)-1))
    results[name] = dict(new=list(best[0]) if best else None,
                         newzig=best[1] if best else 0, old=list(old), oldzig=oldzig)

print(f"{'SECTOR':16s}{'OLD SEAMS':16s}{'ZIG':>4}   {'NEW SEAMS':16s}{'ZIG':>4}")
keep = {}
for k, v in results.items():
    if not v or not v["new"]:
        print(f"  {k:14s}{'—':16s}{'':4}   unchanged"); continue
    if v["newzig"] > v["oldzig"]:
        keep[k] = v["new"]
        print(f"  {k:14s}{str(v['old']):16s}{v['oldzig']:4}   {str(v['new']):16s}{v['newzig']:4}  ↑")
    else:
        print(f"  {k:14s}{str(v['old']):16s}{v['oldzig']:4}   already forces the detour")
json.dump(keep, open('newseams.json', 'w'))
print(f"\n{len(keep)} sectors get a longer forced route")

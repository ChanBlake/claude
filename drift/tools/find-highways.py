"""Find highways: a continuous lane the player can traverse the whole sector on.

The complaint is concrete — get to the top and walk the entire level. That isn't
a reachability failure (the verifier is happy), it's a level that has a floor or
ceiling running uninterrupted from one end to the other. This looks for exactly
that: a row you can stand on, in either gravity, spanning the full width, with
no gap wider than a jump.
"""
import re, json
exec(open('skipcheck.py').read().split('print(f"{')[0])   # reuse load()

def lanes(rows, kit):
    R, Cc = len(rows), len(rows[0])
    SPAN = 7 if "B" in kit else 4
    flip = "F" in kit
    solid = lambda c, r: (not (0 <= c < Cc and 0 <= r < R)) or rows[r][c] in "#~-=%"
    free  = lambda c, r: 0 <= c < Cc and 0 <= r < R and rows[r][c] not in "#~^=%"
    out = []
    for gd in ([1, -1] if flip else [1]):
        for r in range(1, R - 1):
            # columns where you can stand at this row under this gravity
            stand = [c for c in range(Cc) if free(c, r) and solid(c, r + gd)]
            if not stand: continue
            reach_cols, cur = set(), None
            runs = []
            prev = None
            for c in stand:
                if prev is None or c - prev > SPAN + 1:
                    runs.append([c, c])
                else:
                    runs[-1][1] = c
                prev = c
            for a, b in runs:
                if a <= 2 and b >= Cc - 3:
                    out.append((r, gd, b - a))
    return out

print(f"{'SECTOR':16s}{'W':>4}  HIGHWAY")
bad = {}
for name, kit, rows, mp in load('/mnt/user-data/outputs/drift/src/levels.js'):
    L = lanes(rows, kit)
    if L:
        bad[name] = L
        desc = ", ".join(f"row {r}{' inverted' if gd<0 else ''}" for r, gd, _ in L[:3])
        print(f"  {name:14s}{len(rows[0]):4d}  {desc}")
    else:
        print(f"  {name:14s}{len(rows[0]):4d}  none")
print(f"\n{len(bad)} sectors have a lane running the full width")
json.dump({k: [[r, g] for r, g, _ in v] for k, v in bad.items()}, open('lanes.json', 'w'))

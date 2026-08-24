"""Search each sector for a legal secret pocket instead of guessing at one.

A carve is only accepted if, afterwards, the sector still passes every rule the
verifier enforces AND the hidden core is provably reachable. Anything that
breaks the level or hides a core behind geometry you cannot get to is rejected.
"""
import re, json
from collections import deque

def load(path):
    src=open(path).read()
    pat=re.compile(r'\{name:("(?:[^"\\]|\\.)*"),kit:("(?:[^"\\]|\\.)*"),par:\d+,teach:(?:true|false),'
                   r'hint:"(?:[^"\\]|\\.)*",rows:\[(.*?)\](?:,\n mp:\[(.*?)\])?\},',re.S)
    out=[]
    for m in pat.finditer(src):
        rows=re.findall(r'"((?:[^"\\]|\\.)*)"',m.group(3))
        out.append((json.loads(m.group(1)),json.loads(m.group(2)),rows,m.group(4)))
    return out

def reach(rows,mp,kit):
    R,Cc=len(rows),len(rows[0])
    UP,SPAN=(6,7) if "B" in kit else (3,4)
    flip="F" in kit
    plat=set()
    for m in re.finditer(r'"c":\s*(\d+),\s*"r":\s*(\d+),\s*"w":\s*(\d+),\s*"axis":\s*"(\w)",\s*"dist":\s*(\d+)',mp or ''):
        c,r,w,ax,d=int(m[1]),int(m[2]),int(m[3]),m[4],int(m[5])
        for k in range(d+1):
            for i in range(w): plat.add((c+i+(k if ax=='x' else 0), r+(k if ax=='y' else 0)))
    def T(c,r): return '#' if not(0<=c<Cc and 0<=r<R) else rows[r][c]
    def blk(c,r,ph):
        t=T(c,r); return t in '#~' or (t=='=' and ph==0) or (t=='%' and ph==1)
    def std(c,r,ph): return blk(c,r,ph) or T(c,r)=='-' or (c,r) in plat
    def fre(c,r,ph): return 0<=c<Cc and 0<=r<R and not blk(c,r,ph) and T(c,r)!='^'
    zg=lambda c,r: T(c,r)=='Z'
    def clr(c0,r0,c1,r1,ph):
        v=lambda c,a,b: all(fre(c,t,ph) for t in range(min(a,b),max(a,b)+1))
        h=lambda r,a,b: all(fre(t,r,ph) for t in range(min(a,b),max(a,b)+1))
        return (v(c0,r0,r1) and h(r1,c0,c1)) or (h(r0,c0,c1) and v(c1,r0,r1))
    st=None
    for r in range(R):
        for c in range(Cc):
            if rows[r][c]=='P': st=(c,r)
    if not st: return set(),set()
    S={(st[0],st[1],1,0)}; q=deque(S)
    while q:
        c,r,gd,ph=q.popleft()
        def add(n):
            if n in S or not fre(n[0],n[1],n[3]): return
            S.add(n); q.append(n)
        if T(c,r)=='T': add((c,r,gd,1-ph))
        if flip: add((c,r,-gd,ph))
        if zg(c,r):
            for dc,dr in((1,0),(-1,0),(0,1),(0,-1)): add((c+dc,r+dr,gd,ph))
            continue
        if not std(c,r+gd,ph):
            nr=r+gd
            while fre(c,nr,ph) and not std(c,nr,ph) and not zg(c,nr): nr+=gd
            add((c,nr,gd,ph)) if zg(c,nr) else add((c,nr-gd,gd,ph))
            continue
        add((c-1,r,gd,ph)); add((c+1,r,gd,ph))
        for dv in range(UP+1):
            for dh in range(-SPAN,SPAN+1):
                nc,nr=c+dh,r-dv*gd
                if fre(nc,nr,ph) and clr(c,r,nc,nr,ph): add((nc,nr,gd,ph))
    seen={(c,r) for c,r,_,_ in S}; ph={(c,r,p) for c,r,_,p in S}
    return seen,ph

def objectives_ok(rows,seen):
    R,Cc=len(rows),len(rows[0])
    for r in range(R):
        for c in range(Cc):
            if rows[r][c] in 'SBEAC' and (c,r) not in seen: return False
    return True

def carve(rows,r,c,dirn,n):
    step=-1 if dirn=='left' else 1
    g=[list(x) for x in rows]
    if not (0<=c+step*n<len(rows[0])): return None
    cells=[(r,c+step*i) for i in range(n+1)]
    if any(g[rr][cc]!='#' for rr,cc in cells): return None       # must be solid hull
    # the mouth must open onto somewhere the player could stand
    if g[r][c-step] in '#~': return None
    g[r][c]=':'
    for i in range(1,n+1): g[r][c+step*i]='.'
    g[r][c+step*n]='o'
    return ["".join(x) for x in g]

results={}
for name,kit,rows,mp in load('/mnt/user-data/outputs/drift/src/levels.js'):
    base_seen,_=reach(rows,mp,kit)
    if not objectives_ok(rows,base_seen):
        results[name]=None; continue
    best=None
    R,Cc=len(rows),len(rows[0])
    for r in range(1,R-1):
        for c in range(1,Cc-1):
            for dirn in ('right','left'):
                for n in (2,3):
                    cand=carve(rows,r,c,dirn,n)
                    if not cand: continue
                    seen,_=reach(cand,mp,kit)
                    if not objectives_ok(cand,seen): continue
                    core=(c+(1 if dirn=='right' else -1)*n, r)
                    if core not in seen: continue
                    # prefer deeper pockets, and ones far from the spawn
                    score=n*100 + c
                    if best is None or score>best[0]: best=(score,r,c,dirn,n)
    results[name]=best[1:] if best else None

ok=sum(1 for v in results.values() if v)
print(f"found a legal secret pocket in {ok} of {len(results)} sectors\n")
for k,v in results.items():
    print(f"  {k:15s} {v if v else 'none available — needs a hand-cut pocket'}")
json.dump({k:list(v) if v else None for k,v in results.items()},open('/home/claude/secrets.json','w'))

# ── fallback: sectors with no carvable hull get a core placed by position ──
# The best spot is the reachable tile furthest from the straight line between
# spawn and airlock: somewhere you must deliberately detour to, not somewhere
# you pass through on the way.
from math import hypot
fallback={}
for name,kit,rows,mp in load('/mnt/user-data/outputs/drift/src/levels.js'):
    if results.get(name): continue
    seen,_=reach(rows,mp,kit)
    R,Cc=len(rows),len(rows[0])
    P=E=None
    for r in range(R):
        for c in range(Cc):
            if rows[r][c]=='P': P=(c,r)
            if rows[r][c]=='E': E=(c,r)
    if not (P and E): continue
    def dist_to_route(c,r):
        (x1,y1),(x2,y2)=P,E
        dx,dy=x2-x1,y2-y1
        L=hypot(dx,dy) or 1
        return abs(dy*c-dx*r+x2*y1-y2*x1)/L
    best=None
    for (c,r) in seen:
        if rows[r][c]!='.': continue
        # must be a spot you can actually stop at, not mid-air
        below=rows[r+1][c] if r+1<R else '#'
        if below not in '#~-' and rows[r][c]!='Z' and 'Z' not in rows[r][c]: continue
        d=dist_to_route(c,r)+min(hypot(c-P[0],r-P[1]),hypot(c-E[0],r-E[1]))*.35
        if best is None or d>best[0]: best=(d,c,r)
    if best: fallback[name]=(best[2],best[1])   # (row, col)

print(f"\nplaced {len(fallback)} cores by position where no pocket was carvable:\n")
for k,v in fallback.items(): print(f"  {k:15s} row {v[0]:2d} col {v[1]:2d}")
json.dump(fallback,open('/home/claude/fallback.json','w'))

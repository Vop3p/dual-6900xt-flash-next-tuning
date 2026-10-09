# gaps.py <db>: decode 阶段每个 GPU 上相邻内核之间的空隙分布 + 每步内核数
import sqlite3, sys, collections
db=sys.argv[1]; c=sqlite3.connect(db)
rows=c.execute("""select k.kernel_name, d.agent_id, d.start, d.end from rocpd_kernel_dispatch d
                  join rocpd_info_kernel_symbol k on k.id=d.kernel_id order by d.agent_id, d.start""").fetchall()
import re
BIN=50_000_000; t0=min(r[2] for r in rows)
mmqbins=set((s-t0)//BIN for n,a,s,e in rows if re.search(r'mul_mat_q|mmq',n))
per=collections.defaultdict(list)
for n,a,s,e in rows:
    if (s-t0)//BIN not in mmqbins: per[a].append((s,e,n))
for a,L in sorted(per.items()):
    L.sort(); gaps=[]; prev_end=None; prev_n=None
    for s,e,n in L:
        if prev_end is not None: gaps.append((s-prev_end, prev_n, n))
        prev_end=max(prev_end or 0,e); prev_n=n
    gaps=[g for g in gaps if g[0]>=0]
    tot=sum(g for g,_,_ in gaps); busy=sum(e-s for s,e,_ in L)
    buckets=[(0,5e3),(5e3,20e3),(20e3,100e3),(100e3,1e6),(1e6,1e12)]
    print(f"agent{a}: decode 内核 {len(L)}  忙 {busy/1e9:.2f}s  空隙合计 {tot/1e9:.2f}s")
    for lo,hi in buckets:
        sel=[g for g,_,_ in gaps if lo<=g<hi]
        print(f"   gap {lo/1e3:>6.0f}–{hi/1e3:<8.0f}us: {len(sel):8d} 次  合计 {sum(sel)/1e9:6.2f}s")
    big=collections.Counter(); bigt=collections.Counter()
    for g,p,n in gaps:
        if g>=100e3: key=(p[:40],n[:40]); big[key]+=1; bigt[key]+=g
    print("   ≥100us 的空隙,按(前内核→后内核)前 6:")
    for k,v in bigt.most_common(6): print(f"     {v/1e9:5.2f}s {big[k]:6d}x  {k[0]} -> {k[1]}")

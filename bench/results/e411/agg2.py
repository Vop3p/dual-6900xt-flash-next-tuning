# agg2.py <db>: 按 50 ms 时间桶把 prefill(含 mul_mat_q)和 decode 分开,给 decode 的忙碌率与饼图
import sqlite3, sys, re, collections
sys.path.insert(0,'/home/ian/notes/bench/e377'); 
db=sys.argv[1]; c=sqlite3.connect(db)
rows=c.execute("""select k.kernel_name, d.agent_id, d.start, d.end from rocpd_kernel_dispatch d
                  join rocpd_info_kernel_symbol k on k.id=d.kernel_id order by d.start""").fetchall()
cats=[('MMVQ 4列(草稿验证批)', r'mul_mat_vec_q.*ELi4E'), ('MMVQ 1列', r'mul_mat_vec_q.*ELi1E'),('MMVQ 其它列', r'mul_mat_vec'),
      ('MMQ 矩阵乘', r'mul_mat_q|mmq'), ('激活量化', r'quantize'), ('注意力 FA', r'flash_attn|fattn'),
      ('DeltaNet/SSM', r'ssm|delta|gated|conv|cumsum|chunk'), ('RMSNorm', r'rms_norm|norm'), ('RoPE', r'rope'),
      ('通信 RCCL', r'nccl|rccl'), ('拷贝/转换', r'cpy|dup|cont|transpose|convert|to_fp|get_rows|set_rows|concat|pad|copyBuffer|fillBuffer'),
      ('逐元素', r'silu|swiglu|glu|mul_f32|add_f32|sub|scale|k_bin|binbcast|unary|sigmoid|exp|softmax|sum_rows|argmax|clamp|leaky|sqr|sqrt|op_')]
def cat(n):
    for name,pat in cats:
        if re.search(pat,n,re.I): return name
    return '其它'
BIN=50_000_000
t0=rows[0][2]; bins=collections.defaultdict(lambda: {'busy':collections.Counter(),'mmq':0,'n':0})
for n,a,s,e in rows:
    b=(s-t0)//BIN; d=bins[b]; d['busy'][a]+=e-s; d['n']+=1
    if re.search(r'mul_mat_q|mmq',n): d['mmq']+=1
agents=sorted({a for _,a,_,_ in rows})
# decode bins: no MMQ, and busy on each agent >= 20% of bin (exclude idle/http gaps)
dec=set(b for b,d in bins.items() if d['mmq']==0 and all(d['busy'][a]>=0.2*BIN for a in agents))
pre=set(b for b,d in bins.items() if d['mmq']>0)
print(f"bins total {len(bins)}  prefill {len(pre)}  decode {len(dec)}  (50 ms each; decode span {len(dec)*0.05:.1f} s)")
for name,S in (('prefill',pre),('decode',dec)):
    span=len(S)*BIN; busy={a:sum(bins[b]['busy'][a] for b in S) for a in agents}
    print(f"[{name}] span {span/1e9:.2f} s  GPU 忙碌率 " + ', '.join(f"a{a} {100*busy[a]/span:.1f}%" for a in agents))
tot=collections.Counter(); byk=collections.Counter(); calls=collections.Counter()
for n,a,s,e in rows:
    if (s-t0)//BIN in dec:
        tot[cat(n)]+=e-s; byk[n]+=e-s; calls[n]+=1
T=sum(tot.values()); print(f"[decode] 内核时间合计 {T/1e9:.2f} s(两卡)")
for k,v in tot.most_common(): print(f"  {k:18s} {100*v/T:5.1f}%")
print("  --- decode top 10")
for n,v in byk.most_common(10): print(f"  {100*v/T:5.1f}% {calls[n]:7d}x {v/calls[n]/1e3:7.1f}us {n[:90]}")

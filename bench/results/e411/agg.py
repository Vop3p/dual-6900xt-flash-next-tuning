import sqlite3, sys, re, collections
db=sys.argv[1]
c=sqlite3.connect(db)
rows=c.execute("""select k.kernel_name, d.agent_id, (d.end-d.start) from rocpd_kernel_dispatch d
                  join rocpd_info_kernel_symbol k on k.id=d.kernel_id""").fetchall()
cats=[('MMQ 矩阵乘', r'mul_mat_q|mmq'), ('MMVQ/其它矩阵乘', r'mul_mat_vec|gemm|gemv|Cijk|rocblas|dequantize_mul_mat'),
      ('激活量化', r'quantize'), ('注意力 FA', r'flash_attn|fattn'), ('DeltaNet/SSM', r'ssm|delta|gated|conv|cumsum|chunk'),
      ('RMSNorm', r'rms_norm|norm'), ('RoPE', r'rope'), ('通信 RCCL', r'nccl|rccl|ncclDevKernel|AllReduce|allreduce'),
      ('拷贝/转换', r'cpy|dup|cont|transpose|convert|to_fp|get_rows|set_rows|concat|pad'),
      ('逐元素', r'silu|swiglu|glu|mul_f32|add_f32|sub|scale|k_bin|binbcast|unary|sigmoid|exp|softmax|sum_rows|argmax|clamp|leaky|sqr|sqrt|op_'),
      ]
def cat(n):
    for name,pat in cats:
        if re.search(pat,n,re.I): return name
    return '其它'
tot=collections.Counter(); per=collections.Counter(); byk=collections.Counter(); calls=collections.Counter(); agents=collections.Counter()
for n,a,dt in rows:
    k=cat(n); tot[k]+=dt; per[(k,a)]+=dt; byk[n]+=dt; calls[n]+=1; agents[a]+=dt
T=sum(tot.values())
print(f"dispatches {len(rows)}  总内核时间 {T/1e9:.2f} s  各 GPU: " + ', '.join(f"agent{a} {v/1e9:.2f}s" for a,v in sorted(agents.items())))
for k,v in tot.most_common():
    print(f"{k:14s} {100*v/T:5.1f}%  " + '  '.join(f"a{a}:{100*per[(k,a)]/T:4.1f}%" for a in sorted(agents)))
print("--- top 14 kernels")
for n,v in byk.most_common(14):
    print(f"{100*v/T:5.1f}% {calls[n]:6d}x {v/calls[n]/1e3:8.1f}us  {n[:110]}")
print("--- 其它 里的前 8")
for n,v in [(n,v) for n,v in byk.most_common() if cat(n)=='其它'][:8]:
    print(f"{100*v/T:5.1f}% {calls[n]:6d}x {n[:110]}")

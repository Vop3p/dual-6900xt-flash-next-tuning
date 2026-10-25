# 时间线：2× RX 6900 XT 从 llama.cpp 到 Strata（2026-09-21 → 10-24）

[← README](../README.zh-CN.md) · [English](timeline.md)

| 日期 | 事件 | 效果（实测） |
| --- | --- | --- |
| 09-21/22 | llama.cpp 专家 cache（E140–E146）：cache 56、inserts 8、MTP n-max 2 | 120K 解码 10.9 → 13.0 t/s；cache 链 >4 token 在 MMQ 崩 |
| 09-26 | `GGML_OP_OFFLOAD_MIN_BATCH=136`；PLE 直读构建 build-pleds | 冷 8K prefill +13–18%，主缺页归零 |
| 09-27 | E165 专家拷贝分两条 x8 | 只 +1–4%，层串行是瓶颈；流水线并行需重写调度器，未做 |
| 09-29 | QSA gather（`LLAMA_QSA_GATHER=1`，冻结 flash-next-qsa-fe7c12b19） | 96K 每验证步 −9.6%；gather 只在 decode/MTP 生效 |
| 09-30 | 新 alias flash-next-iq3s（GSQ-RCO IQ3_S + 112 槽） | 解码 −19–20%/步、prefill +17–22%（vs UD-Q4），命中 77% |
| 10-01 | 官方 MTP vs 自家稠密 MTP；Vulkan | 无可分辨差异；Vulkan 慢 55–90%，否决 |
| 10-02 | 生产换 flash-next-mtp-410e94c34（137 槽，上游 159c651f5） | 每步比 112 槽快 10–18%；数值噪声地板 KLD ≈0.025 |
| **10-04** | **Strata 引擎到位**（E215/E216，HIP gfx1030） | 同 IQ3_S 5K 提示词解码：llama.cpp 26 → split 56–58 → helper 62–63；37K prefill 274 → 714 |
| 10-04 02:30 | 上线 strata-split / strata-helper（strata-132a522，HIP 优化：FP16 输出 GEMM、QSA S4） | 37K prefill split 1,433 / helper 978 |
| 10-04 17:00 | 升 0.1.39（strata-6add1a7）+ FP16 prompt 路径 → PR #835；#849/#854 | 9.9K split 906 t/s；helper 需 `--pcie-frac 0` |
| 10-04 21:00 | 读提示词第 1 层卡死可复现（~70%）→ 临时 `--adapt-every 100000` | 0/3 卡；根因追到 10-06 |
| 10-05 | 卡死根因链（E251–E264，issue #884）：MMQ + 主卡 adapt + SDMA 三者同时；CP 不放行 BARRIER_AND | 关任一不卡；单硬件队列 0 卡但 prompt −30% |
| 10-05 15:32 | 生产 strata-238abe8（0.1.39 + #835/#849/#854/#981 rocBLAS 表） | 50K prompt 1,495 → 1,705（+13–16%），解码不变 |
| 10-05 19:05 | `STRATA_IO_THREADS=128` + `--ple-io ram`（memlock 无限） | 首 chunk 等 PLE 568 → 10 ms，8K prompt −7.4% |
| 10-05 20:25 | 生产 strata-61c59fa（+#1007 select SGEMM） | 128K prompt +5% |
| 10-06 06:33 | **#884 最强线索：GFXOFF**（写 0 后 0/10 不卡）；knob 是引用计数（11:05 更正） | 之后用 gfxoff-guard，再换 kernel-copy |
| 10-06 09:42 | 0.1.40.1 基线（E335） | split prompt 745 → 1,455（F16），解码 58.6 → 64.5（SH_STREAM） |
| 10-06 18:04 | 生产 strata-341922e（0.1.40.1 + #1149/#1150/#1151 + rocBLAS 表，env SH_STREAM=1、PROMPT_F16=1） | 128K split 2,003 tok/s |
| 10-06 19:10 | `STRATA_HIP_ADAPT_KERNEL_COPY=1` 绕 128K 停转，撤 gfxoff-guard（省电） | 0/3 vs 3/3 停转，无速度代价 |
| 10-06 22:20 | split 两槽开图片（自编 HIP strata-vision） | 主卡缓存 −11%，32K prompt −3.6% |
| 10-07 16:54 | 生产 strata-4592281（0.1.40.2 + rocBLAS 解本机缓存） | 速度持平，选解不再随启动变化 |
| 10-07 晚 | #1151 改为 SIMT 打分核（上游 65ce329 移植） | 128K prompt +7.4%，逐字节一致 |
| 10-07 22:10 | 图片编码器挪到 HIP0（分层 0–26/27–47，主卡缓存 5,256 → 6,123 槽） | 32K prompt +2.8–3.8% |
| 10-08 | strata-ud-q4 槽（UD-Q4_K_XL，K-quant MMQ 在 HIP 跑通） | 解码 −38%、32K prompt −3% vs IQ3_S，只用于比质量 |
| 10-08 19:25 | 生产 strata-q8k-4592281：ggml 换 llama-q2k（MMQ q8_0/iq3_s 链头 VOP3P，E378） | iq3_s 内核 +2.6% → 32K prompt +1.4–1.5%，输出逐字相同 |
| 10-08 20:30 | E382 `--kv-resident` 32K → 16K | 专家槽只 +0.7%，32K 解码 −3%，否决 |
| 10-08 21:25 | **生产 strata-141-d14ca361**：上游 0.1.41 + 7 补丁 rebase（无冲突） | 12 条输出逐字相同、速度 ±0.5%、0 停转；json 加 `gpu_order: as_given` |
| 10-12 02:00 | `strata-ud-q4` 槽补上 E387 解码配置（`--spec 3 --spec-min-p 0.7 --pipeline-windows 2`；E387 上线时只改了 IQ3_S 两个槽，漏了它。E422 带图片编码器、E423 不带） | 解码 4K / 32K / 128K +13.5 / +9.6 / +5.2%（44.8 / 47.6 / 47.9 → 50.9 / 52.2 / 50.4），草稿接受 66 → 79%，prompt −0.3%；与 IQ3_S 同一机制，和专家格式无关；0 停转。UD-Q4 解码现比 IQ3_S 慢 32–36%（IQ3_S 76.6 / 81.9 / 74.5） |
| 10-11 01:57 | `strata-ud-q4` 槽 → 0.1.42 + 7 补丁 + `-DSTRATA_MMQ_KQUANTS=ON` + `STRATA_SPLIT_MTP_BATCH=1`（E415；社区报告 PR #1927） | 分层 4K / 32K / 128K 756 / 1,748 / 1,981，解码 45–51（旧槽 715 / 1,640，43–46）；原版 0.1.42 两种格式 prompt 一样（单卡 471–476 / 504–505 / 488–489：稠密 FP16 路径是上限）；UD-Q4 解码比 IQ3_S 慢 30–35% |
| 10-10 23:38 | E414：llama.cpp 的 RDNA2 MMQ 补丁放进 Strata，单卡 UD-Q4，对照 PR #1897 | tile / mad24、以及把 Q8_K 激活编进 `strata_mmq`（它原本就没定义 `GGML_CUDA_MMQ_Q8K`）都只有 prompt ±1%；Q8_K 让 8K 解码 −7%；专家 GEMM 只占 prompt 34%，等拷贝 1.6%。我们 x8 单卡 8K 1,085–1,093 / 16K 1,121–1,122，#1897 的 x16 是 1,036 / 1,104 |
| 10-10 14:33 | **生产升 0.1.42**（`strata-142-cd87f4d2`）+ `STRATA_SPLIT_MTP_BATCH=1`（E413/E413b） | 0.1.42 本身与 0.1.41 固定协议下逐字相同、速度持平；草稿 K/V 批量化：prompt +4.1 / +6.9 / +2.0%（4K/32K/128K，三轮同向），解码与接受率不变 |
| 10-10 13:40 | 0.1.42 其余 opt-in 逐个单变量（E413） | `STRATA_ROUTE_TAIL_SKIP=7`（HIP 要显式设）解码 +4 / +1%，在 ±6% 轮间噪声内且改答案；`STRATA_ROUTE_RESIDENT=0.5` 命中 96→98.7% 但解码 −1~−3.5%；`--aux-cpus auto` ±2%；`STRATA_MMQ_RESIDENT_SORT_NE` 要整层专家全常驻，本机永不触发；`STRATA_PF_FUSED` 只有 gfx11/12 |
| 10-09 上午 | flag 清单 K1：35 个开关/档位逐个单变量（E395–E401） | 单独没有一个超过噪声；17 个明确变慢（SPLIT_OWN / no-prefill-borrow 32K −35%，`--mtp-window 0` 解码 −30%）；六个噪声内的叠加解码 +1%，生产里测不出，归档 |
| 10-09 04:47 | E391–E394：四条外来线索全部否定 | `--prefill auto:16384`（#1640）32K −14%；短 prompt 切 2048（#1441 思路）4K −9%；#1123 FP32 SGEMM 在 F16 开着时零调用、F16 关时 +66/+73%（10-06 已测过同款，正文已引用）；相位计时 F16 在 hc/qsa proj 都快一倍，不合并 |
| 10-09 04:03 | E388a 0.1.41 单卡 / helper 六臂（补齐报告） | 单卡 PRs 976/1,174/1,147、解码 49–51；helper PRs 986/1,173/1,147、解码 72–75；stock 比 0.1.40.1 +3–6%，两开关 +5–13%，PRs +1–2%；0 停转 |
| 10-09 00:16 | **E387 配置上生产**（strata-split / -256k：`--spec 3 --spec-min-p 0.7 --pipeline-windows 2`，备份 *.bak-2026-10-09-before-e387） | 经 llama-swap 实发 7K 请求：确认行出现，分层 0–26/27–47，prompt 1,019、解码 73.4，草稿接受 92% |
| 10-09 00:13 | E388 0.1.41 社区报告（split 五臂，无图片编码器） | stock 0.1.41 比 0.1.40.1 stock prompt +4–6%（464/767/869），两开关 +5/+12/+12%（832/1,619/1,823），PRs 持平（968/1,714/2,029）；kernel-copy 无代价、stock 128K 不停转；E387 解码配置 +19/+20/+11%（77/82/76） |
| 10-08 23:42 | E387 `--spec 3 --spec-min-p 0.7 --pipeline-windows 2` | 解码 4K 66 → 73–77、32K 74 → 80–83（+8–16%，三轮），prompt 不变；输出跨启动不确定；候选 |
| 10-08 21:27 | E384 `--pipeline-windows 2` | 解码 +1–6% 但跨启动输出不确定（2/7 同），4K prompt −1–5%，否决 |
| 10-08 21:50 | E385/E385b `--spec`×`--spec-min-p` 16 点 | 只有 5/0.6 在 32K +2.5%（单轮），其余全负；4/0.5 保留 |
| 10-08 22:50 | 并发批槽评估 | 常驻专家 41% < 上游门槛 50%，槽里不带 MTP，不做 |
| 10-13 23:40 | 生产 → `strata-144-hcps-fb15a4e6`：#1151 加 #2071 的 `STRATA_SELECT_SIMT=2`（上游只在 CUDA 生效，HIP 静默退回）（E457） | prompt +1%；后来送 PR #3073 |
| 10-15 | 两三路并发（`"parallel": 2`，E463–E470）：A 单路保留 `--pipeline-windows`、B 长读在块边界让路、C 流水分组的槽位草稿（移植 davidbhoward） | 第二个请求首字 12 → 0.5 s，长读旁插短请求 37 → 8 s，两路 +6%；单路比独占配置 −2~6%；10-15 19:30 上生产；A 送 PR #3095 |
| 10-18 13:09 | 上游 0.1.45（E475）：原版缺 A，单路解码慢 11–16%；0.1.45 + A + C + SIMT=2 与旧生产打平 | 生产 `strata-145-acx-2e127c66` |
| 10-18 21:10 | 上游 #2985（`STRATA_PIPED_MTP=2`，JacobSussan）换掉我们的 C（E481） | 两路总吞吐 +13%，单路与交接不变，找针 14/14；生产 `strata-145-2985-3f53fb74` |
| 10-19 02:20 | `STRATA_PREFILL_STREAM_MIN=2048`（E482–E485）：低于全量搬运阈值的块只搬路由到的专家，<2K 的读有 43–54% 时间在等 PCIe | 真实文本 1,090–1,542 token −6~17%，779 token 续写 −7%，≥2048 不变；3072 在 2–3K 变慢。合成词表提示让 3072 看起来更好（E483）——路由相关的开关必须用真实文本测 |
| 10-19 17:40 | `STRATA_PREFILL_CPU_SHARE_BATCH=1`（我们的，E493/E494）：开 `--batch` 时上游直接关掉 CPU 分担 | <2048 token 的真实文本 −20~35%，455 token 续写 1.86 → 1.25 s，并发不变；生产 `strata-145-csb-de8b8636`；PR #3382 |
| 10-19 20:30 | `STRATA_PROMPT_ATTN_RDNA2=1`（我们的，E495–E498e）：gfx103x 读 prompt 的注意力借用解码内核（64 单元切块 + 合并）；改为每（查询，KV 头）一个 block、在线 softmax、加权阶段每线程 4 维 | 每 8,192 token 块注意力 500 → 355 ms，34K / 133K −3.5%；质量门（8 段对 FP64 注意力参照）不劣；生产 `strata-145-pa-a6572b34`；PR #3381 |
| 10-19 22:15 | SeqMoE 式专家预取先测上界（E499）：4 段真实 agent 对话的 26.6 万条路由记录回放 | 自适应缓存命中已 85.3 / 85.1%（高于全知静态集）；按现在的换入量，完美的 8 窗预测器也不更好——放弃；杠杆是每窗换入量（未测） |
| 10-20 | 补丁按上游新规在 0.2.0 main 上复测（E501–E503）：setup.py 构建、默认路径逐字节、ctest 对照 main、10 对交错冷启动、FP64 参照质量门、CUDA 13.2 编译 | RDNA2 注意力 31K / 119K −3.49%（各 10/10）；CPU 分担 <2048 −28.8%（10/10）；送 #3381 / #3382。#3073 在 0.2.0 上 119K −6.5%，#3095 单路解码 +12~16%（各 10/10，E503） |
| 10-20 16:40 | 生产 → 上游 0.2.1.3 + #2985 移植 + 我们的 5 个补丁（`strata-0213-40d9a2dc`，E516/E517） | 读 prompt −0.2~−0.8%、解码在噪声内，0 停转；KL 0.034 / 0.029 对旧 0.026（逐段看是重分布不是变差） |
| 10-21 10:17 | 两卡降压 −81 mV @245 W（E522/E523） | 37 轮 0 次翻转（card1 到 −88 就有翻转）；解码不随频率变（E507–E512） |
| 10-22 18:47 | 生产 → 0.2.2 合并（`strata-022-34cd8534`，E527） | KL 0.028 / 0.030 对 0.031，8 段里 7 段逐位相同；速度持平 |
| 10-23 13:27 | 生产 → 0.2.3 合并（`strata-023-b523b933`，E533），钉 `--conversation-cache-mib 0` | 0.2.3 默认开的会话缓存让单会话读 prompt −3% / −1.4%；钉住后 1,008 / 1,800 / 2,171，解码 75 / 79 / 78，与 0.2.2 持平 |
| 10-24 | 一张 RX 6900 XT 在 Windows 11 上（[Windows 笔记](windows-one-card.zh-CN.md)） | 官方包只改设置：16K 读 prompt 479 → 1,076、解码 28 → 42，12/12；PR [#4005](https://github.com/Niko1221/Strata/pull/4005)、[#4006](https://github.com/Niko1221/Strata/pull/4006)，报告 [#4012](https://github.com/Niko1221/Strata/pull/4012) |

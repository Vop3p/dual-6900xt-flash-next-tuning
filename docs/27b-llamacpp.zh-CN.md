# 稠密 Qwen3.8-27B（llama.cpp `qwen38-tp`）与 llama.cpp 补丁

[← README](../README.zh-CN.md) · [English](27b-llamacpp.md)

`patches/llama.cpp/` 是基于上游 `159c651f5` 的 8 个 llama.cpp 补丁：1–7 是时间线里 `q8k ggml` 那一步背后的 RDNA2 MMQ 工作（更宽的 tile、mad24 缩放、Q8_K 式激活、dot 链头 VOP3P），8 是 q8_0 K cache 的 int8 QK^T flash-attention tile 内核；编译选项和实测见[其 README](../patches/llama.cpp/README.md)（英文）；Strata 通过 `-DSTRATA_GGML_DIR` 吃到 MMQ 那几个。这些补丁都是在同一台机器用 llama.cpp 跑的稠密 **Qwen3.8-27B** 上做出来的，见下文。

同样两张卡还用 llama.cpp 跑稠密的 Qwen3.8-27B：`-sm tensor`（RCCL allreduce 走两条 x8 经主机）、q8_0 KV、196K 上下文、MTP 草稿（`--spec-draft-n-max 3`）、3 个槽。全注意力模型，Strata 那套专家缓存 / KV 流式都用不上；上面的 llama.cpp 补丁就是在它身上做的，补丁 8 只为它而存在。它不在交互式时间线页面里。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="q38-now-zh-dark.png">
  <img alt="27B 当前生产状态与速度" src="q38-now-zh-light.png" width="100%">
</picture>

**现状（10-09 15:10）**：生产二进制 = 上游 `159c651f5` + 补丁 1–8，env `GGML_FATTN_KQ8=1`。prompt 8K 以内 740–820 tok/s，32K 731，128K 512；解码短上下文 62 tok/s（MTP：每步约 51 ms 出 3.2 个 token），32K 深度 44，128K 25–28。KLD 对 bf16 0.003704，top-1 一致率 97.29%（同一量化用原版内核：0.003941 / 97.32%）。针 32K 8/8、128K 4/4。196K 上下文每卡显存 15.8 GB。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="q38-speed-zh-dark.png">
  <img alt="27B 各生产状态的 prompt 与解码速度，09-26 到 10-09" src="q38-speed-zh-light.png" width="100%">
</picture>

| 日期 | 这一步 | 实测效果 |
| --- | --- | --- |
| 09-26 | E157：选 v3 UD-Q5_K_XL 而不是 UD-Q4_K_XL（对 54 GB bf16 基准算 KLD，64×512 中英混合语料） | 0.0039 vs 0.0116；Q4 快 10.5%、每卡省 1.2 GiB；选了精度 |
| 09-27 | E152：在宿主上复现生产数字 | `--cache-ram 0` 会关掉空闲槽缓存，`-kvu` 下新请求慢 30–40%——差点得出四个假结论；复现必须逐项复制参数，包括缓存类 |
| 09-29 | 宿主二进制替代 docker 镜像；RDNA2 K-quant MMQ tile（补丁 2；扫描里 K512 变体快 1.9× 但真实形状算错，否决） | prefill 2.5K 617→683、9.8K 623→677、30K 566→600；逐位相同；解码不变 |
| 10-02 | mad24 缩放乘法（补丁 3） | prefill +8–9%，逐位相同，解码 −1% |
| 10-02 | E200b 分时，10K prefill：MMQ 64–67%、RCCL ≤13%、FA 5%、GDN 5% | K-quant MMQ 比 q8_0 慢约 40%，来源是每子块的浮点缩放 → 激活布局成为目标（10-08 做成） |
| 10-08 | Q8_K 式 MMQ 激活 + dot 链头 VOP3P（补丁 4–6） | prefill +4.6–6.1%（2K 774→812、8K 773→811、32K 674→705）；KLD 0.003941→0.003736；弯路：每 256 值一个缩放（KLD +25%）、k01 展开（>1000 VGPR）、q4_K/q5_K 上用 VOP3P 链头（−10%） |
| 10-08 | E377 内核级分时：MMQ 60–72%、allreduce 14–16%（BF16，每层 2 次，已是 PCIe 速度）、FA 2%@2K → 17%@32K、GDN 5–6% | FA 是长上下文的目标 |
| 10-08 | E381 FA tile 内核参数扫描（nbatch_fa、nbatch_K、占用率、线程数，10 个点） | 上游默认就是 gfx1030 上的局部最优，没有一点 >+3%；内核卡在 fp16 峰值的 35% 是结构（每 32 列 × 64 key 的 LDS 复用、half2 打包）不是参数 |
| 10-09 | **FA tile 内核 int8 QK^T**（补丁 8；E406–E410，一天） | 内核 16K/64K 1.31×；端到端 prefill 32K +3.3–3.9%、128K +11.1%、2K/8K 持平；解码/显存不变；KLD 0.003704；15:10 上生产 |
| 10-09 | E411 解码分时（短上下文，生产配置，rocprofv3；追踪工具本身拖慢 12%） | 饼图见下；MTP 值 2.1×（25.7 → 62 tok/s）；HIP 图在用但只值 2%（E411b） |
| 10-09 | E412 新旧二进制短上下文对照 | 解码两边都 62 ±1%，904 token prompt 持平——补丁 8 不碰解码 |

**短上下文一个解码步的时间去向（E411，每卡每步约 51 ms，3.2 个 token）：**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="q38-decode-zh-dark.png">
  <img alt="27B 短上下文一个解码步的分解：MMVQ 47%、发射间隙 23%、lm_head 10.6%、RCCL 8%、其余 11.4%" src="q38-decode-zh-light.png" width="100%">
</picture>

| 块 | 占比 | 离硬件上限 |
| --- | --- | --- |
| MMVQ，4 列验证批读 64 层权重（每卡约 9.3 GB） | 47% | 417 GB/s = 峰值带宽的 81% |
| 发射间隙（每步约 2,500 个内核 × 3–4 µs） | 23% | `-sm tensor` 的 meta 后端把每步切成约 130 个子图（每个 allreduce 一段），每张 HIP 图只装十几个内核——关掉图只慢 1.5–2% |
| lm_head（1.35 GB q8_0，按 K 维两卡各半；3 次草稿 + 1 次验证） | 10.6% | 每次都在峰值带宽；草稿那 3 次占 8% |
| RCCL allreduce（约 138 次 × 30 µs，每次 80 KB） | 8% | PCIe x8 经主机的延迟 |
| 量化（548 次 × 1.3 µs）、RMSNorm、拷贝、GDN、FA | 约 10% | 零碎小内核 |

没有一块既大又便宜：MMVQ 已到带宽墙；间隙要靠减少内核数（把 1–4 µs 的小内核融合，预期 +5–8%）或把 allreduce 做进图里整步一张图（后端改动，上限 +15–20%，未实测）；草稿的 lm_head 只能换更小的 `output.weight` 量化（动主模型）；allreduce 是 PCIe 延迟。

**27B 上已经关掉的方向（实测）**：SGLang 同位宽单路不比 llama.cpp 快（E174，之前的 +6–12% 是 Q4 vs Q5）；Vulkan；`-ub 2048`（prompt +4–8% 但上下文得降到 131K）；`-np 1`（单路无收益）；FA tile 参数空间（E381）；MMVQ（已到带宽 81%）；HIP 图开关（2%）。

**这条线上犯过的错：**

- 宿主复现时 `--cache-ram 0`（E152）差点出四个错结论；缓存类参数一个都不能漏。
- int8 原型前四版（1.04–1.11×）被当成思路的上限，其实是把 Q 的缩放放寄存器导致的溢出（256 VGPR + 31 次 spill）。判断一个内核思路之前先看 ISA / VGPR 数。
- int8 的精度爆炸（KLD 0.059、最大 20）在量化器里追了几小时（离群维度、旋转、SmoothQuant），真因是 `launch_fattn` 的 split-KV 合并路径——int8 内核的 LDS 占用把它触发了；上游 f16 内核强制走同一条路也掉精度。先读发射器，再动量化器。
- 两条实验链共用一个脚本和构建目录，产出的二进制和日志写的不是一回事（两组读数作废）；一次只跑一条链。
- 用 `sed` 叠加宏开关删掉了一个真正的 `#define`；宏变体应各自成提交。
- rocprofv3 下 `llama-server` 不响应 SIGINT/SIGTERM（追踪器的信号处理），追踪库其实早已落盘，白等 30 分钟。库出现后直接 SIGKILL。
- E411 的证伪条件（"内核时间 < 墙钟 60%"）满足了，却回答不了"切哪块"；条件应写成"最大块 ≥30% 且离硬件上限 ≥25%"。

## 仓库里的原始材料

`bench/results/e410`、`e411`、`e412`：补丁 8 的 P/F 冷启动交替 A/B（脚本、报告、KLD/perf 运行）、rocprofv3 解码饼图与间隙分析（脚本及其文本输出；300–800 MB 的追踪库不含）、新旧二进制短上下文对照。

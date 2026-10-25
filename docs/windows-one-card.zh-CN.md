# Windows 单卡（RX 6900 XT）

[← README](../README.zh-CN.md) · [English](windows-one-card.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="win1x-chart-zh-dark.png">
  <img alt="Windows 11 上一张 RX 6900 XT 一步步调优：4K / 16K 读 prompt 与 4K 解码，从默认设置到实测设置再到 #4005" src="win1x-chart-zh-light.png" width="100%">
</picture>

*Strata 标准基准（`strata bench run`，三次中位，每一步都 12/12），每一步一次完整运行，原始数据在 Strata PR [#4012](https://github.com/Niko1221/Strata/pull/4012)。前六步都是官方 `rdna2` 引擎包 0.1.48 原样；最后一点（虚线）是 `main` + [#4005](https://github.com/Niko1221/Strata/pull/4005) 在本机自编，同样 8,192 chunk（E559，12/12，#4012 里的 `…-9b72e2b1`）：4K 586 → 809、16K 1,076 → 1,125、解码 42 → 45.5。同一二进制用 auto chunk（6,144）时 16K 只有 979（#4012 里的 `…-c97e2108`）。*

第二台机器（IanLAB：i9-10900K，64 GB DDR4-3600，一张 RX 6900 XT 16 GB，PCIe 3.0 x16，Windows 11，同一个 IQ3_S 模型，64K 上下文），10-23 → 10-24。Strata 从 0.2.2 起在更新源里放了 RX 6000 的 Windows 引擎包（`windows-x86_64-hip-rdna2`），发布说明写"编了但没在真卡上试"；这里是它在真卡上的结果。**不用编译、照下面设置一键装好的脚本：[`windows-rx6000/`](../windows-rx6000/)**（官方 Terminal、官方包、存一个 `strata launch` 预设）。

**最后到了哪里（标准基准，官方包，只改设置）：**读 prompt 4K / 16K **452 / 479 → 586 / 1,076** tok/s，解码 **28 → 42** tok/s，短 prompt 首字 2.8 → 1.1 s，12/12。再加 #4005（本机自编，E559），4K / 16K 读到 809 / 1,125、解码 45.5。对比同型号卡在 Linux 上（E540，单卡）：Windows 原来读 prompt 582 / 811（4K / 32K）、解码 36.9，Linux 944 / 1,160、47.4；调完 32K 读到 1,163，Linux 是 1,165（8,192 chunk，带拷贝事件补丁和 #3381 / #3073 的本地构建），解码 43–47。

**测出来的东西，按影响大小排**

- **WDDM 下每次提交约 80–120 µs（E541）。**同一个 HIP 小程序在两个系统、同型号卡上跑：背靠背拷 2.79 MB 的块，Windows 并不慢（12.5 对 14.1 GB/s，每次固定开销 5.5 µs）；但拷贝流上每记一个事件多 79 µs（Linux 3），每次跨流等待多 43 µs（Linux 约 0），一次拷贝加回调通知端到端多约 120 µs；发了 kernel 不跟一次 query，它甚至不会下发到 GPU。能缩短这笔开销的"硬件加速 GPU 计划"在 RX 6000 驱动里是 `AlwaysOff`。下面每一条都是这笔开销在不同地方出现。
- **解码：PCIe 份额（E538、E545、E547）。**启动时的规则只按链路带宽定 PCIe 份额（12.6 GB/s → 0.35）。扫 0 / 0.1 / 0.2 / 0.3 / 0.35：0.2 是唯一的峰，解码 **+29%**。Strata 自带的运行时细化（`STRATA_PCIE_FRAC_DEFAULT=auto`，只在 gfx12 默认开）自己就收敛到 0.20，因为这台 CPU 算专家（29.4 GB/s）比链路搬得快；在 Linux 那台上它同样收敛到 0.20，解码 +1–2%。已在 [#4007](https://github.com/Niko1221/Strata/issues/4007) 提议 gfx103x 默认开。
- **长 prompt：chunk 大小（E543、E548）。**Windows HIP 上 `--prefill auto` 卡在 6,144，因为 8,192 在一张 RX 7900 XTX、262K 上下文下崩过（[#1630](https://github.com/Niko1221/Strata/issues/1630)）。这里 8,192 六次冷启动都没出问题，其中三次是 `--max-context 262144`、27K 和 100K 的 prompt；32K 读 prompt **+17%**（流式 6 遍变 4 遍）。
- **短 prompt：拷贝事件（E542、E544）。**读 prompt 路径每流一个专家就记一个事件、等一次释放事件，而消费端每 16 个专家一组只等一次。两个 opt-in 开关去掉其中 15/16：**4K +36.4%、32K +14.9%，10/10 对**；Linux 上输出逐字节相同、速度不变。PR [#4005](https://github.com/Niko1221/Strata/pull/4005)。
- **显存余量。**16 GB 卡上 Windows 默认留 2,560 MiB；加载后剩下的约等于保留值减 250–340 MiB，剩下不到约 1 GiB 的运行都换页了（700：12 题 0/12）。1,536 是最低的稳定值。再多留一些代价起初不大：每多 512 MiB 少约 265 个专家槽；2,048 读 prompt 慢 1%、解码在噪声内，2,560 的 32K 解码慢 6–8%，3,072 的 4K 解码慢 7%、32K 慢 9–13%（E553，每档两次）。
- **显示器。**两台 4K 显示器接在卡上时，桌面合成器占了 2.2 GB 显存；挪到核显后，同样的保留值下专家缓存从 3,121 槽涨到 3,672 槽，重启后卡上只剩引擎。测试时浏览器在放视频，解码掉了三分之一。
- **看图。**包里带图片编码器；CPU 版读一张测试图 4–5 s、全对。同一个包里的 GPU 版（`strata-vision-hip.exe`）只为 gfx1200 / gfx1201 编译：设 `gpu: true` 就报 `this GPU (gfx1030) is not in the picture reader's build (gfx1200,gfx1201)`（E554，手写配置、没配 CPU 后备）。用官方源码为 gfx1030 / gfx1031 自编后能在显卡上跑（E555/E556）：4/4 全对，大图按 1,059 个图像 token 读（CPU 版 300），占约 1.3 GB 显存、引擎自动从专家缓存让出（3,479 对 4,166 槽；4K 解码 44.4 对 44.5，各一次）。懒人包加了 `-Vision gpu` 选项（[windows-rx6000](../windows-rx6000/README.md#pictures-on-the-gpu--vision-gpu-optional)）。
- **没用的：**大页（64 GB 内存拿不出 47 GB 连续的 2 MB 页，错误 1450）；Linux 上调的 rocBLAS 表（Windows 运行时全部拒绝；在 Windows 上调的表只对 ~1K 以内的新 prompt 有用，−7.6%）；`STRATA_SH_STREAM`（Windows 上解码变慢，和 KV 流式一起用会让引擎停掉，[#3895](https://github.com/Niko1221/Strata/pull/3895)）；本机自编引擎（和官方包一样快，E537）。

**在这条线上犯过的错（留着，下次不再犯）**

- 把 `STRATA_PREFILL_TIMING` 的读数当真了一天：它自己每个专家记一个事件，在 Windows 上让 32K 读 prompt 慢 8%，还把约 3.3 s 的等拷贝记成了"dequant"。修正是 [#4006](https://github.com/Niko1221/Strata/pull/4006)；修之前"Windows 上 dequant 慢 3 倍"是测量工具造出来的。
- 猜 `--prefill auto` 卡在 6,144 是因为卡上槽太少借不出；引擎启动时就打印了原因（#1630）。解释一个数之前先读代码或日志。
- 先拿专家槽数解释解码差距（E535–E537），又说份额公式缺了 WDDM 延迟（E541）；实测答案是启动时的份额没看 CPU 有多快（E545）。
- 一组 A/B 里有三臂是在电脑上放视频时测的（解码 −33%）；现在开跑前先确认没人在用这台机器。
- 配 GPU 图片编码器时漏了 `gpu: true`，看它跑在 CPU 上就怪 16 GB 显存不够；编码器只有被要求才会用 GPU，要求之后才看到真正的限制：它根本没为 gfx1030 编译。

# dual-6900xt-flash-next-tuning（中文）

<img src="docs/cover-zh.webp" alt="Strata 社区榜 AMD 双卡第一：2× RX 6900 XT，128K 2,041 tok/s，解码 82" width="100%">

[English](README.md) · [交互版时间线](https://vop3p.github.io/dual-6900xt-flash-next-tuning/?lang=zh)（中文 / English） · 给 AI 助手看的：[`llms.txt`](llms.txt)、[`AGENTS.md`](AGENTS.md)

在 AMD RX 6900 XT（RDNA2，gfx1030）上用 [Strata](https://github.com/Niko1221/Strata) 引擎跑 **Qwen3.8-Flash-Next（IQ3_S）** 的实测调优，另有 llama.cpp 跑稠密 27B 的一条线。所有数字都是下面这些机器上实测的，推算的会单独标明。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/now-zh-dark.png">
  <img alt="当前生产状态与速度" src="docs/now-zh-light.png" width="100%">
</picture>

## 按你的情况选

| 你的机器 | 结果 | 看这里 |
|---|---|---|
| **2× RX 6900 XT，Linux**（Ryzen 5 5600X、128 GB、各 PCIe 4.0 x8） | 读 prompt **1,009 / 1,347 / 1,786** tok/s（4K / 8K / 32K，0.2.7 + 补丁，10-29），解码 **78–85**；标准基准 4K / 16K 1,024 / 1,516，比原版包快 24% / 12%；相对 llama.cpp：解码约 3 倍、32K 读 prompt 约 6.5 倍 | [docs/linux-dual-6900xt.zh-CN.md](docs/linux-dual-6900xt.zh-CN.md) |
| **一张 RX 6000，Windows**（6800 / 6800 XT / 6900 XT / 6950 XT / 6700 XT） | 官方包只改设置：16K 读 prompt **479 → 1,076**，解码 **28 → 42**；一个 PowerShell 脚本装好 | [windows-rx6000/](windows-rx6000/README.md)（懒人包，英文）· [docs/windows-one-card.zh-CN.md](docs/windows-one-card.zh-CN.md)（怎么调出来的） |
| **llama.cpp 跑稠密 Qwen3.8-27B**，双卡 | 32K 读 prompt 731，解码短上下文 62 / 32K 44；8 个 RDNA2 llama.cpp 补丁 | [docs/27b-llamacpp.zh-CN.md](docs/27b-llamacpp.zh-CN.md) · [patches/llama.cpp/](patches/llama.cpp/README.md) |

## 其他

- [docs/timeline.zh-CN.md](docs/timeline.zh-CN.md)：09-21 到 10-24 的每一步和实测效果。
- [docs/mechanisms.zh-CN.md](docs/mechanisms.zh-CN.md)：这几张卡上速度卡在哪里，以及我在这上面犯过的错。
- [data/](data/README.md)：每张图背后的数字（CSV）。
- [bench/](bench/)：A/B 脚本（`run_ab.sh`、`benchmark.py`、`ab_compare.py`、`monitor_amd.py`），以及按实验编号存放的原始结果（`bench/results/eNNN/`）。
- 这些机器发到上游的报告：Strata PR [#3426](https://github.com/Niko1221/Strata/pull/3426)（Linux，0.2.0-beta）、[#4012](https://github.com/Niko1221/Strata/pull/4012)（Windows，9 次标准运行）、#1927、#1657；引擎 PR #3073、#3095、#3381、#3382、#4005、#4006。

实验编号（E…）对应作者的实验日志（未公开）。

**许可**：`patches/` 和 `bench/` 里的脚本是 MIT（与 llama.cpp 相同）；文字、图和测量数据是 CC BY-NC 4.0。见 `LICENSE`；`CITATION.cff` 可直接引用。

Developed with an AI coding assistant; every number here was measured on the machines described.

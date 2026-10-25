# dual-6900xt-flash-next-tuning

<img src="docs/cover-en.webp" alt="#1 AMD dual-card in the Strata community index: 2x RX 6900 XT, 2,041 tok/s at 128K, 82 tok/s decode" width="100%">

[中文](README.zh-CN.md) · [Interactive timeline](https://vop3p.github.io/dual-6900xt-flash-next-tuning/?lang=en) (English / 中文) · For AI assistants: [`llms.txt`](llms.txt), [`AGENTS.md`](AGENTS.md)

Measured tuning of **Qwen3.8-Flash-Next (IQ3_S)** on AMD RX 6900 XT (RDNA2, gfx1030) cards with the [Strata](https://github.com/Niko1221/Strata) engine, plus a dense 27B on llama.cpp. Every number was measured on the machines below; estimates are marked.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/now-en-dark.png">
  <img alt="Production state and speed now" src="docs/now-en-light.png" width="100%">
</picture>

## Pick your path

| You have | Result | Read |
|---|---|---|
| **2x RX 6900 XT, Linux** (Ryzen 5 5600X, 128 GB, PCIe 4.0 x8 each) | prompt **1,008 / 1,800 / 2,171** tok/s at 4K / 32K / 128K, decode **75–79** tok/s; from llama.cpp: decode ≈3×, 32K prompt ≈6.5× | [docs/linux-dual-6900xt.md](docs/linux-dual-6900xt.md) |
| **One RX 6000 card, Windows** (6800 / 6800 XT / 6900 XT / 6950 XT / 6700 XT) | official package, settings only: 16K prompt **479 → 1,076** tok/s, decode **28 → 42**; one PowerShell script sets it up | [windows-rx6000/](windows-rx6000/README.md) (the lazy pack) · [docs/windows-one-card.md](docs/windows-one-card.md) (how it was found) |
| **The dense Qwen3.8-27B on llama.cpp**, two cards | prompt 731 tok/s at 32K, decode 62 short / 44 at 32K; eight RDNA2 llama.cpp patches | [docs/27b-llamacpp.md](docs/27b-llamacpp.md) · [patches/llama.cpp/](patches/llama.cpp/README.md) |

## More

- [docs/timeline.md](docs/timeline.md) — every step from 09-21 to 10-24 with its measured effect.
- [docs/mechanisms.md](docs/mechanisms.md) — what limits speed on these cards, and the mistakes made on the way.
- [data/](data/README.md) — the numbers behind every chart as CSV.
- [bench/](bench/) — the A/B scripts (`run_ab.sh`, `benchmark.py`, `ab_compare.py`, `monitor_amd.py`) and raw results per experiment (`bench/results/eNNN/`).
- Upstream reports from these machines: Strata PRs [#3426](https://github.com/Niko1221/Strata/pull/3426) (Linux, 0.2.0-beta), [#4012](https://github.com/Niko1221/Strata/pull/4012) (Windows, nine standard runs), #1927, #1657; engine PRs #3073, #3095, #3381, #3382, #4005, #4006.

Experiment numbers (E…) refer to the author's lab notebook (not public).

**License:** `patches/` and `bench/` scripts are MIT (as llama.cpp); text, figures and measurement data are CC BY-NC 4.0. See `LICENSE`; `CITATION.cff` has a citation entry.

Developed with an AI coding assistant; every number here was measured on the machines described.

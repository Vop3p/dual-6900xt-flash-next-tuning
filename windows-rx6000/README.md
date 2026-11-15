# Strata on an RX 6000 card under Windows, without compiling

For an **RX 6800 / 6800 XT / 6900 XT / 6950 XT (gfx1030)** or **RX 6700 XT (gfx1031)** on Windows 10/11, with
**64 GB of RAM** (see [Memory](#memory-55-gb-free)). One PowerShell script sets up the fastest configuration measured on
an RX 6900 XT and starts it.

```powershell
# in PowerShell, with the model files you already have:
powershell -ExecutionPolicy Bypass -File .\install-rx6000.ps1 -ModelPath D:\models\iq3_s
# or let Strata download Qwen3.8-Flash-Next IQ3_S (~70 GB):
powershell -ExecutionPolicy Bypass -File .\install-rx6000.ps1
# official Strata pieces only (no binary from this repository):
powershell -ExecutionPolicy Bypass -File .\install-rx6000.ps1 -ModelPath D:\models\iq3_s -Official
```

Next time, start it with `%LOCALAPPDATA%\Strata\rx6000-fast\0211fz-win-gfx103x\start-fast.bat` (the script prints the path);
stop it by closing that window. With `-Official`: `strata launch --preset rx6000-tuned` and
`strata launch --stop --preset rx6000-tuned`. Both serve an OpenAI-style API on `http://127.0.0.1:<port>/v1`
(the port `strata launch` picked; the script prints it).

## Two paths

| | the default (fast) | `-Official` |
|---|---|---|
| engine | **built by this repository** from Strata 0.2.11 + the patches in [`patches/strata/`](../patches/strata/) (the Linux production source, `strata-0211fz`), for gfx1030 and gfx1031 | the official signed `rdna2` package from Strata's update feed |
| download | the Terminal and the model as usual, plus one zip from [this repository's releases](https://github.com/Vop3p/dual-6900xt-flash-next-tuning/releases) (~150 MB), checked against the SHA-256 in the script | nothing beyond the official pieces |
| settings | 40 switches (below), a rocBLAS table tuned on Windows, `--prefill 8192` | 27 official switches, `--prefill 8192` |
| prompt 4K / 16K | 779 / **1,333** tok/s | **809** / 1,157 tok/s |
| decode short / 4K / 16K | **45.9 / 44.5 / 43.5** tok/s | 43.6 / 40.4 / 40.4 tok/s |

One RX 6900 XT 16 GB (PCIe 3.0 x16), i9-10900K, 64 GB DDR4, Windows 11, Qwen3.8-Flash-Next IQ3_S, 64K context, 8-bit KV.
Strata's standard benchmark (`strata bench run`, protocol `strata-qwen38-thinking-v1-draft.1`), medians of three,
12/12 sanity in every row, each one run after a fresh start with ≥53 GB of RAM free. Raw runs:
[`bench/results/e840/`](../bench/results/e840/) (the default: the released zip, installed with this script; a test picture read correctly through it as well),
[`bench/results/e838/`](../bench/results/e838/) (`-Official`, and the old settings).

For comparison, on the same PC:

| | prompt 4K / 16K | decode short / 4K / 16K |
|---|---|---|
| Strata's defaults (package 0.1.48, 2026-10) | 452 / 479 | 28.8 / 28.3 / 28.4 |
| this script until 2026-11-14 (official package, 8 switches) | 612 / 1,087 (0.1.48), 616 / 1,078 (0.1.59) | 43.8 / 42.4 / 42.5 |
| the default now | **779 / 1,333** | 45.9 / 44.5 / 43.5 |

The fast path reads long prompts faster (16K +15% over `-Official`) and decodes 5–10% faster, and on synthetic 32K prompts it read 2.9× the
package's default speed (E834). `-Official` reads 4K prompts slightly faster (809 against 779). **The gfx1031 (RX 6700 XT) code in the fast
engine was built but never run** (no such card here), and none of the settings were measured on a 12 GB card;
if it fails there, use `-Official`.

## What the script does

1. installs the Strata Terminal with the official one-liner (`irm https://github.com/Niko1221/Strata/releases/latest/download/install.ps1 | iex`), unless it is already installed;
2. runs `strata update --check`, stops unless Strata sees a gfx1030 / gfx1031 card, and installs the official `rdna2`
   engine package (with `STRATA_ENGINE_BACKEND=hip-rdna2` for that step only, so a PC with a second AMD GPU, such as a
   Ryzen APU's Radeon 760M / 780M, cannot end up with another card family's package);
3. sets the model up with `strata launch` and saves a preset (`rx6000-tuned`) with the official switches. This preset is
   what `-Official` runs, and the fallback of the fast path;
4. unless `-Official`: downloads the fast zip, stops if its SHA-256 differs, unpacks it to
   `%LOCALAPPDATA%\Strata\rx6000-fast\`, writes `fast-run.json` from the preset's run config (the same model, pack,
   drafter and expert-profile files; only the engine, its switches and a few arguments change) and `start-fast.bat`,
   which runs the zip's server with the Terminal's own Python. It warns when less than 55 GB of RAM is free, then starts it.

The zip holds `engine\` (`strata.exe`, `strata-device.exe`, and the ROCm 10.2.0a20260930 runtime DLLs, the same ROCm as the
official package), `src\` (the server of the same source), `rocblas\` (the tuned table), Strata's MIT `LICENSE` and a
`BUILD.txt` with the exact source, build options and SHA-256. It is not signed and not an official Strata release.
`-Stock` saves Strata's defaults instead of any of this.

## Memory: 55 GB free

The engine pins a ~47 GB expert arena in RAM. On a 64 GB PC that only fits if almost nothing else runs: **close browsers,
chat apps, game launchers and tray programs before starting** (Task Manager → Startup apps to keep them from coming back
after a restart). In one test, programs that started with Windows took 21 GB; the engine then read experts from the SSD and
ran at less than half speed (prompt 361 / 614, decode 28–31). `start-fast.bat` prints a warning when less than 55 GB is
free. The engine log line `… slices pinned` says how much of the arena Windows let it register: 46 is normal; starts right
after a previous engine exited sometimes got 0 or 13 and ran 25–30% slower, so wait until the RAM is free again.

## What the settings change

The fast path's switches are the Linux production set minus four that are slower under Windows, plus two from
[#4005](https://github.com/Niko1221/Strata/pull/4005) and PcieAuto. Each one was measured on this PC (E828–E836,
interleaved fresh starts, synthetic 4K / 32K prompts); the full list is `$FastEnv` in the script.

| change | measured |
|---|---|
| `STRATA_PCIE_FRAC_DEFAULT=auto` (PcieAuto: the decode miss split learned from the CPU pool's speed instead of the link alone) | decode **+15% (4K) / +13% (32K)**, 10 of 10 pairs; proposed as the gfx103x default in Strata [#5984](https://github.com/Niko1221/Strata/pull/5984) |
| #4005's copy events (`STRATA_PREFILL_COPY_EVENT_EVERY=16`, `STRATA_PREFILL_COPY_WAIT_DEDUPE=1`) | with the FP16 prompt switches: prompt 4K **+36%**, 32K +9%; without them nothing |
| the FP16 prompt path, GDN, PLE, slot and hc switches of the Linux set | prompts much faster, decode not slower |
| a rocBLAS table tuned on Windows (fast path only) | part of the fast path's 16K lead |
| `--prefill 8192` | 32K prompts +17% (`auto` stops at 6,144 on Windows because of [#1630](https://github.com/Niko1221/Strata/issues/1630); 8,192 ran clean here, also at 262K context) |
| `vram-reserve-mib=1536`, `kv-resident=32768` | the lowest stable VRAM reserve on a 16 GB card (700 gave 0/12); half the KV cache in RAM for more expert slots |
| **left out**: `STRATA_SIDE_MIXER=2`, `STRATA_SH_STREAM=1` | decode **−22%** and **−17 to −19%**: each adds a branch stream, and under Windows every cross-stream dependency is a costly submission |
| **left out**: `STRATA_HIP_ADAPT_KERNEL_COPY=1`, `STRATA_FUSE_WAIT=2` | −2.5% and −1% |

## Pictures on the GPU (`-Vision gpu`, optional)

Both paths read pictures with the CPU picture reader of the official package by default (the fast zip has no picture
reader of its own; `fast-run.json` keeps the preset's). `-Vision gpu` uses the official engine, not the fast one.

By default pictures are read by the package's CPU reader: a test image (an invoice number, an amount, two shapes) correct
in 4–5 s, big pictures cut to 300 image tokens. The package also carries a GPU reader (`strata-vision-hip.exe`), but its
code is for gfx1200 / gfx1201 only, so on an RX 6000 card it does not start ([#4017](https://github.com/Niko1221/Strata/issues/4017)).

```powershell
powershell -ExecutionPolicy Bypass -File .\install-rx6000.ps1 -ModelPath D:\models\iq3_s -Vision gpu
# later:
strata runtime start --profile rx6000-tuned-gpu
strata runtime stop  --profile rx6000-tuned-gpu
```

`-Vision gpu` sets everything up as above (the preset `rx6000-tuned`, pictures on the CPU), then:

1. downloads **one file that is not from the official feed**: [`strata-vision-hip-rx6000-0.1.48.zip`](https://github.com/Vop3p/dual-6900xt-flash-next-tuning/releases/tag/rx6000-vision-0.1.48)
   (18.7 MB), and stops unless its SHA-256 is the one in the script. It holds `strata-vision-hip.exe` built from the
   official source of the 0.1.48 engine (commit `6f8800aefe27`, `tools/vision` unmodified) for gfx1030 / gfx1031, with the
   same CMake line as `tools/hip/build_windows.bat` and the same ROCm (10.2.0a20260930) as the official package; its
   `BUILD-vision.txt` says how, and the two MIT licenses (Strata, llama.cpp) are beside it. It is not signed.
2. puts it in `%LOCALAPPDATA%\Strata\rx6000-vision\0.1.48\` with the HIP runtime DLLs copied from the official package
   (the engine folder is left as the updater installed it);
3. saves a copy of the preset's run config that uses it (with the CPU reader as its fallback) as the profile
   `rx6000-tuned-gpu`, and starts that with `strata runtime start`.

Measured on the RX 6900 XT above, the preset's settings, one cold start each (benchmark: two 4K prompts):

| | expert-cache slots | prompt 4K | decode 4K | small picture (first / again) | big picture (first / again) | answers |
|---|---|---|---|---|---|---|
| pictures off | 4,161 | 589 tok/s | 44.5 tok/s | | | |
| CPU reader (the preset) | 4,166 | not run | not run | 4.9 / 1.1 s ¹ | 7.0 / 2.2 s, 338 image tokens ¹ | all correct |
| GPU reader (`-Vision gpu`) | 3,479 | 582 tok/s | 44.4 tok/s | 3.5 / 1.1 s | 7.6 / 2.2 s, 1,059 image tokens | all correct |

¹ measured with `vram-reserve-mib=2048` instead of 1,536 (the CPU reader uses no VRAM, so the reserve does not touch it).

The GPU reader takes about 1.3 GB of VRAM, which the engine gives up from the expert cache by itself. Its gain is detail:
a big picture is read at up to 1,024 image tokens instead of 300. Check that it runs on the card: the engine log says
`strata-vision: warmed up at 1024 image tokens`; if it ever says `on the CPU`, the CPU fallback took over.
Building it yourself instead: `tools\hip\build_windows.bat` with `STRATA_HIP_ARCHS=gfx1030;gfx1031` (Visual Studio 2022
Build Tools, Python, git, ~7 GB of ROCm wheels), then pass the zip of `build-vision-hip-win\bin\strata-vision-hip.exe` you
made as `-GpuVisionZip` after putting its SHA-256 in the script.

## Before you judge the speed

- **Put the monitor on the CPU's graphics (iGPU) and restart.** Everything that draws on the RX card (the desktop
  compositor, browsers, the Radeon overlay) takes its memory from the model: with two 4K monitors on the card the
  desktop alone held 2.2 GB. With the monitor on the iGPU only the engine sits on the card.
- **Page file: fixed, about the size of your RAM** (64 GB here). The engine reserves the expert arena (~50 GB for IQ3_S)
  against Windows' commit limit; with a 2 GB page file it stopped at start with no message.
- **Model files on a local NVMe drive**, not a network drive (an iSCSI volume read at 7 MB/s).
- **No video or games while it answers**: a browser playing video cut decode by a third in one test.

## If it does not start

- `strata update --check --output json` shows what Strata detected (`hardware.gfx`, `hardware.gpu_names`) and why
  each engine package was not chosen (`engine.reasons`). Post that output when you ask for help.
- `--backend hip-rdna2` on the `strata update` command line does not pick the variant (it is read as a backend name);
  the environment variable `STRATA_ENGINE_BACKEND=hip-rdna2` does, for `strata update` only. `strata launch` refuses that
  value, so unset it before launching (the script does this).
- If `start-fast.bat` stops at once, read `engine.log` next to it. If the fast engine does not run on your card,
  `strata launch --preset rx6000-tuned` starts the official engine with the same model and settings.

## Not covered

- Only measured on one RX 6900 XT and one PC. Not run on an RX 6800 / 6800 XT / 6950 XT, nor on an RX 6700 XT (the fast
  engine's gfx1031 code was never executed, and a 12 GB card was never tried), nor on a fresh PC from zero: the Terminal
  (0.2.3.1, updated engine package 0.1.59) and the model were already installed when the script was tested (E839, E840).
- The fast engine is a fixed build (`strata-0211fz`, 2026-11-11 source). It does not update with `strata update`; the
  `-Official` preset does. When the official package catches up (#4005 is merged opt-in, PcieAuto for gfx103x is
  [#5984](https://github.com/Niko1221/Strata/pull/5984)), `-Official` will close part of the gap by itself.

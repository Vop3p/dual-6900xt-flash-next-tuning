# Strata on an RX 6000 card under Windows, without compiling

For an **RX 6800 / 6800 XT / 6900 XT / 6950 XT (gfx1030)** or **RX 6700 XT (gfx1031)** on Windows 10/11.
It uses only official Strata pieces: the Terminal's installer and the signed **`rdna2`** engine package from the update
feed (in the releases since 0.2.2). Nothing is compiled and no binary comes from this repository.

```powershell
# in PowerShell, with the model files you already have:
powershell -ExecutionPolicy Bypass -File .\install-rx6000.ps1 -ModelPath D:\models\iq3_s
# or let Strata download Qwen3.8-Flash-Next IQ3_S (~70 GB):
powershell -ExecutionPolicy Bypass -File .\install-rx6000.ps1
# later:
strata launch --preset rx6000-tuned
strata launch --stop --preset rx6000-tuned
```

What [`install-rx6000.ps1`](install-rx6000.ps1) does, in order:

1. installs the Strata Terminal with the official one-liner (`irm https://github.com/Niko1221/Strata/releases/latest/download/install.ps1 | iex`), unless it is already installed;
2. runs `strata update --check`, stops unless Strata sees a gfx1030 / gfx1031 card, and installs the official `rdna2`
   engine package (with `STRATA_ENGINE_BACKEND=hip-rdna2` for that step only, so a PC with a second AMD GPU, such as a
   Ryzen APU's Radeon 760M / 780M, cannot end up with another card family's package);
3. sets the model up with `strata launch` and saves a preset (`rx6000-tuned`) with the settings below, pictures on
   (the CPU picture reader that ships in the package);
4. starts it. Every setting is an official `strata launch --set` value; `-Stock` saves Strata's defaults instead.

## What the settings change

One RX 6900 XT 16 GB (PCIe 3.0 x16), i9-10900K, 64 GB DDR4, Windows 11, Qwen3.8-Flash-Next IQ3_S, 64K context, 8-bit KV,
the official `rdna2` package 0.1.48 unchanged. Strata's standard benchmark (`strata bench run`, protocol
`strata-qwen38-thinking-v1-draft.1`), medians of three:

| | prompt 4K | prompt 16K | decode short / 4K / 16K | first token (short) | sanity |
|---|---|---|---|---|---|
| Strata's defaults | 452 tok/s | 479 tok/s | 28.8 / 28.3 / 28.4 tok/s | 2.81 s | 12/12 |
| this preset | 586 tok/s | 1,076 tok/s | 44.5 / 42.3 / 41.3 tok/s | 1.11 s | 12/12 |

| setting | why | measured |
|---|---|---|
| `vram-reserve-mib=1536` | Windows keeps 2,560 MiB of a 16 GB card free by default. What is left after the load is about the reserve minus 340 MiB; below ~1 GiB Windows pages and answers go wrong (700 gave 0/12 sanity). | 1,536: ~1.2 GiB left, 12/12 |
| `kv-resident=32768` | half of the 64K KV cache in VRAM, the rest in pinned RAM, so the expert cache gets more slots | 3,672 → 3,908 expert-cache slots, same display state |
| `pcie-frac=0.2` | the share of missed experts the GPU reads over PCIe. The start-up rule only looks at the link (0.35 here); the CPU of this PC is faster than the link. Strata's own refinement (`STRATA_PCIE_FRAC_DEFAULT=auto`) arrives at the same 0.20 after ~48 answer steps. | decode +29% (0, 0.1, 0.2, 0.3, 0.35 swept) |
| `prefill=8192` | prompt chunk size. `auto` stops at 6,144 on Windows because 8,192 crashed a 7900 XTX ([#1630](https://github.com/Niko1221/Strata/issues/1630)). On this RX 6900 XT 8,192 ran clean in six cold starts: 6 × 60K and 6 × 32K prompts at 64K context, and 3 × 27K and 3 × 100K prompts at 262,144 context (the setting #1630 crashed at). | 32K prompts +17% |
| `STRATA_HIP_PROMPT_F16=1`, `STRATA_HIP_ADAPT_KERNEL_COPY=1`, `STRATA_PREFILL_CPU_SHARE=auto`, `STRATA_HC_PERSIST=1`, `STRATA_PIPED_CONCURRENT=1`, `STRATA_PREFILL_STREAM_MIN=2048`, `STRATA_IO_THREADS=128` | the documented opt-in prompt switches for gfx103x | prompt 4K / 16K 467 / 489 → 591 / 798 tok/s, first token (short) 2.4 → 1.1 s |
| (not `STRATA_SH_STREAM`) | on Windows it slows decode and, together with KV streaming, stopped the engine ([#3895](https://github.com/Niko1221/Strata/pull/3895)) | |

Pictures: the package's CPU reader answered a test image (an invoice number, an amount, two shapes) correctly in 4–5 s.
The package's GPU reader (`strata-vision-hip.exe`) is built for gfx1200 / gfx1201 only and refuses gfx1030 (`--vision gpu` stops the server), so the script uses the CPU reader.

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

## Not covered

- Only measured on one RX 6900 XT and one PC. Not run on an RX 6800 / 6700 XT, nor on a fresh PC from zero
  (the Terminal and the model were already installed when the script was tested; the picture file was already present).
- Two pending changes for this card are not in the official package yet: faster prompt reads on Windows
  ([#4005](https://github.com/Niko1221/Strata/pull/4005): 4K +36%, 32K +15%) and the PCIe-share refinement on by default
  ([#4007](https://github.com/Niko1221/Strata/issues/4007)).

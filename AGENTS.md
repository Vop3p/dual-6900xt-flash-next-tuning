# AGENTS.md

Notes for an AI assistant (or a person) who wants to reproduce or extend this work. The full story is in `docs/`;
this file is the short, actionable part. Numbers below are measurements from the docs; check the doc before quoting.

## Hardware and software this applies to

- **Linux box:** 2x AMD RX 6900 XT 16 GB (gfx1030, PCIe 4.0 x8 each), Ryzen 5 5600X, 128 GB DDR4-3200, Ubuntu, ROCm 10.0,
  Strata (engine 0.2.3 + patches as of 2026-10-23). Model: Qwen3.8-Flash-Next GSQ-RCO IQ3_S (two GGUF shards + Strata pack).
- **Windows PC:** one RX 6900 XT 16 GB, i9-10900K, 64 GB, Windows 11, Strata Terminal 0.2.3.1 with the official
  `windows-x86_64-hip-rdna2` engine package 0.1.48.
- Other RDNA2 cards (6800 / 6800 XT / 6950 XT = gfx1030, 6700 XT = gfx1031) were **not measured**; expect the same
  mechanisms, not the same numbers. RDNA3/RDNA4 differ (WMMA, other packages).

## Reproduce: one RX 6000 card on Windows (easiest)

Use `windows-rx6000/install-rx6000.ps1` (see its README). It only uses official Strata pieces and these settings:
`vram-reserve-mib=1536`, `kv-resident=32768`, `pcie-frac=0.2`, `prefill=8192`, and the env switches
`STRATA_HIP_PROMPT_F16=1 STRATA_HIP_ADAPT_KERNEL_COPY=1 STRATA_PREFILL_CPU_SHARE=auto STRATA_HC_PERSIST=1
STRATA_PIPED_CONCURRENT=1 STRATA_PREFILL_STREAM_MIN=2048 STRATA_IO_THREADS=128`. Expected with Strata's standard
benchmark: prompt 4K / 16K ≈ 586 / 1,076 tok/s, decode ≈ 42, 12/12 sanity. Check first: the monitor on the iGPU,
a fixed page file about the size of RAM, the model on local NVMe.

## Reproduce: two cards on Linux (the production configuration)

Engine arguments of the production slot (paths replaced by `<…>`):

```
--pack <iq3_s> --native <...IQ3_S-00001-of-00002.gguf> --ple-gguf <...IQ3_S-00002-of-00002.gguf>
--expert-profile <expert-profile.bin> --expert-cache auto --prefill auto --spec 3 --spec-min-p 0.7 --mtp <rt>
--max-context 262144 --kv int8 --kv-resident 32768 --ple-io ram --vision --vram-reserve-mib 700
--pipeline-windows 2 --batch-mtp --conversation-cache-mib 0
```

Run config: `"backend": "hip"`, `"gpu": [1, 0]`, `"layer_split": "auto"`, `"parallel": 2`, sampling temperature 0 and
presence penalty 0 (the pipelined decode needs greedy sampling; a model card's presence penalty silently turns it off - E528, logged as "decodes serially"; not written up in docs/).

Environment: `STRATA_HIP_PROMPT_F16=1 STRATA_HIP_ADAPT_KERNEL_COPY=1 STRATA_HC_PERSIST=1 STRATA_IO_THREADS=128
STRATA_PIPED_CONCURRENT=1 STRATA_PREFILL_CPU_SHARE=auto STRATA_PREFILL_STREAM_MIN=2048 STRATA_SH_STREAM=1
STRATA_SPLIT_MTP_BATCH=0 STRATA_ROCBLAS_TUNING=<dir with the gfx1030 table>`, plus switches that **only exist with
patches that were not merged upstream as of 2026-10-24**: `STRATA_PIPED_MTP=2` (#2985), `STRATA_PW_WITH_BATCH=1`
(#3095), `STRATA_SELECT_SIMT=2` on HIP (#3073), `STRATA_PREFILL_CPU_SHARE_BATCH=1` (#3382), `STRATA_PROMPT_ATTN_RDNA2=1`
(#3381). On a stock build these are ignored silently; confirm each from the engine log.

Expected (E533, `bench/benchmark.py` synthetic load, no vision encoder): prompt 1,008 / 1,800 / 2,171 tok/s at
4K / 32K / 128K, decode 75 / 79 / 78 for one request.

## Do not retry (measured, closed on this hardware)

- Decode knobs alone: `--kv-resident` shrink, `--pipeline-windows 2` alone, other `--spec` / `--spec-min-p` pairs
  (the combination `--spec 3 --spec-min-p 0.7 --pipeline-windows 2` is what works).
- MMQ tile / stream-K changes for IQ3_S experts; `--prefill` chunks other than 8192 on Linux; tensor parallel (+6%).
- PCIe x16+x4 instead of x8/x8 for long prompts (long prompts wait on PCIe only 0.2–0.7% of the time).
- GPU core / memory overclock (decode does not follow the clock, E507–E512); CPU and RAM speed (decode is GPU-bound: 6 → 4 CPU expert threads did not slow it, E524; not written up in docs/).
- Windows: `STRATA_SH_STREAM` (slower, and stops the engine with KV streaming), large pages (error 1450 with 64 GB),
  a rocBLAS table made under Linux (refused), a VRAM reserve below ~1 GiB left free (pages, answers go wrong).
- Full list with reasons: `docs/linux-dual-6900xt.md` ("Closed directions"), `docs/windows-one-card.md`,
  `docs/mechanisms.md` (mistakes).

## How measurements here were made (follow the same rules)

- One cold server start per arm; arms interleaved (A B B A …); at least two pairs in the same direction before calling
  a difference; the 32K case is the main criterion, 4K decode is noisy.
- Compare output text before speed: only identical outputs make decode speeds comparable (`bench/ab_compare.py`).
- Confirm every switch from the engine's own log line; a switch that is set is not a switch that is on.
- Report medians with the range, and name every non-default setting of a run.
- Scripts: `bench/run_ab.sh` (skeleton), `bench/benchmark.py` (4K/32K/128K prompts, fresh nonce each),
  `bench/monitor_amd.py` (telemetry). Paths in them are placeholders.

## Repository map

- `README.md` / `README.zh-CN.md` — overview. `docs/*.md` (English) and `docs/*.zh-CN.md` (Chinese) — the same content.
- `data/*.csv` — numbers behind the charts (`data/README.md` describes the columns).
- `patches/llama.cpp/` — eight patches on llama.cpp `159c651f5`; `bench/results/eNNN/` — raw results.
- `index.html` — interactive timeline (Chinese) and chart source; `tools/render_charts.py` renders `docs/*.png`.
- License: code MIT, text and data CC BY-NC 4.0.

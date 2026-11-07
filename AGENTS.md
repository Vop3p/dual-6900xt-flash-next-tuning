# AGENTS.md

Notes for an AI assistant (or a person) who wants to reproduce or extend this work. The full story is in `docs/`;
this file is the short, actionable part. Numbers below are measurements from the docs; check the doc before quoting.

## Hardware and software this applies to

- **Linux box:** 2x AMD RX 6900 XT 16 GB (gfx1030, PCIe 4.0 x8 each), Ryzen 5 5600X, 128 GB DDR4-3200, Ubuntu, ROCm 10.0,
  Strata (0.2.11 + patches + on-demand DP + MMQ activation reads as of 2026-11-06 09:40). Model: Qwen3.8-Flash-Next GSQ-RCO IQ3_S (two GGUF shards + Strata pack).
- **Windows PC:** one RX 6900 XT 16 GB, i9-10900K, 64 GB, Windows 11, Strata Terminal 0.2.3.1 with the official
  `windows-x86_64-hip-rdna2` engine package 0.1.48.
- Other RDNA2 cards (6800 / 6800 XT / 6950 XT = gfx1030, 6700 XT = gfx1031) were **not measured**; expect the same
  mechanisms, not the same numbers. RDNA3/RDNA4 differ (WMMA, other packages).

## Reproduce: one RX 6000 card on Windows (easiest)

Use `windows-rx6000/install-rx6000.ps1` (see its README). It only uses official Strata pieces and these settings:
`vram-reserve-mib=1536`, `kv-resident=32768`, `pcie-frac=0.2`, `prefill=8192`, and the env switches
`STRATA_HIP_PROMPT_F16=1 STRATA_HIP_ADAPT_KERNEL_COPY=1 STRATA_PREFILL_CPU_SHARE=auto STRATA_HC_PERSIST=1
STRATA_PIPED_CONCURRENT=1 STRATA_PREFILL_STREAM_MIN=2048 STRATA_IO_THREADS=128 STRATA_HOST_CORE=sibling`. Expected with Strata's
standard benchmark: prompt 4K / 16K ≈ 612 / 1,087 tok/s, decode ≈ 42, 12/12 sanity. Check first: the monitor on the iGPU,
a fixed page file about the size of RAM, the model on local NVMe.

## Reproduce: two cards on Linux (the production configuration)

Production since 2026-11-06 22:3x (`strata-0211wl2-1a996f63`): Strata upstream 0.2.11 + our patches + upstream PR #5002's DP prompt read + `patches/strata/0001`
+ the 11-06 kernel batch `patches/strata/0002` (applied as one diff against `4783921b`, which already contains 0001),
built against llama.cpp ggml with `patches/llama.cpp/` 0001–0006 + `extra-mmq-y-scalar-rdna2.diff` (`-DCMAKE_HIP_FLAGS=-DGGML_CUDA_MMQ_Y_SCALAR`).
Engine arguments of the production slot (paths replaced by `<…>`):

```
--pack <iq3_s> --native <...IQ3_S-00001-of-00002.gguf> --ple-gguf <...IQ3_S-00002-of-00002.gguf>
--expert-profile <expert-profile.bin> --expert-cache auto --prefill 16384 --spec 3 --spec-min-p 0.6 --mtp <rt>
--max-context 262144 --kv int8 --kv-resident 32768 --ple-io ram --vision --vram-reserve-mib 700
--pipeline-windows 2 --batch-mtp --conversation-cache-mib 0 --prefill-pipe 1600 --vram-reserve-later-mib 844 --mtp-q4 head
```

(`--vram-reserve-later-mib`: 0.2.11 reserves 256 MiB more on the later card; 444 + 256 = the old 700 keeps card 1's expert slots (E678), and the
int8 hc copies add 400 → 844.)

Run config: `"backend": "hip"`, `"gpu": [1, 0]`, `"layer_split": 27`, `"parallel": 2`, sampling temperature 0 and
presence penalty 0 (the pipelined decode needs greedy sampling; a model card's presence penalty silently turns it off - E528, logged as "decodes serially").

Environment (beyond the earlier set `STRATA_HIP_PROMPT_F16=1 STRATA_HIP_ADAPT_KERNEL_COPY=1 STRATA_HC_PERSIST=1 STRATA_IO_THREADS=128
STRATA_PIPED_CONCURRENT=1 STRATA_PREFILL_CPU_SHARE=auto STRATA_PREFILL_STREAM_MIN=2048 STRATA_SH_STREAM=1 STRATA_SPLIT_MTP_BATCH=0
STRATA_PIPED_MTP=2 STRATA_SELECT_SIMT=2 STRATA_PREFILL_CPU_SHARE_BATCH=1 STRATA_ROCBLAS_TUNING=<dir>`):
`STRATA_STAGE_TRIM=1 STRATA_PREFILL_PIPE_FLOOR=4096`, the GDN group `STRATA_GDN_HEAD=1 STRATA_GDN_PP=2 STRATA_GDN_CONVL2=1 STRATA_GDN_NOY=1`,
`STRATA_DEQUANT_WIDE=1`, the slot copy `STRATA_SLOT_COPY_DIRECT=1 STRATA_SLOT_COPY_BATCHSYNC=1 STRATA_SLOT_CKPT_MOVE=1`, `STRATA_SIDE_MIXER=2`,
and the DP read `STRATA_DP_PREFILL=1 STRATA_KV_HOST_DMA=1 STRATA_DP_MIN=12288 STRATA_DP_PEER_RES=0` (PR #5002 + its `dp-followups`) plus the switches
that only exist with `patches/strata/`: `STRATA_DP_BATCH=1 STRATA_DP_LAZY=1 STRATA_DP_STAGE_W=3 STRATA_DP_STAGE_MIN=0 STRATA_DP_MTP_ALL=1`. Local patches still
not upstream: `STRATA_PW_WITH_BATCH=1` (#3095), `STRATA_PROMPT_ATTN_RDNA2=1` (#3381). On a stock build unknown switches are ignored
silently; confirm each from the engine log. The full current list is in the production section of `docs/linux-dual-6900xt.md`.

Kernel-batch switches on top of the env above (they only exist with `patches/strata/0002` or 0.2.8+):
`STRATA_F16_NOWIDEN=1 STRATA_HC_PERSIST_Q8=2 STRATA_MMVQ_NW1=1 STRATA_EXP_TABLE=1 STRATA_SWIGLU_Q8=1 STRATA_ATTN_MERGE_V2=1 STRATA_FUSE_HITS=1
STRATA_IQ_STAGE_TABLES=1 STRATA_PLE_COMPACT=1 STRATA_PLE_COPY_STREAM=1`. `STRATA_HC_PERSIST_Q8=2` (int8 hc copies on Q8_0's grid, one fp16
scale per 32 values) is not bitwise: top-10 overlap with a double reference −0.7 points, KL within noise (E708); `=1` is a coarser grid (−1.3 points).
Card 0 then has ~430 MiB free after loading. On **one** card the copies take 641 MiB and the draft head did not fit in one of two cold starts
(E706): leave `STRATA_HC_PERSIST_Q8` off there, or free VRAM first.

Expected (this concurrent config): prompt 2,301 / 2,525 / 2,628 / 2,636 tok/s at 31K / 62K / 128.5K / 256K (E705, the E659 corpus), 5.6K 1,282;
decode whole-run +8.5% over the 09:40 build (E703); standard benchmark (parallel 1, E707) 4K / 16K 1,234 / 2,124, decode 80.7 / 85.5, 12/12.
Rollback build: `strata-0211scal` (no 0002, `--vram-reserve-later-mib 444`, no kernel-batch switches): 2,160 / 2,507 at 32K / 128K (E685).

**Card-to-card copies:** bidirectional P2P collapses to 3–4 GB/s a direction unless the cards are awake (display, or SMU deep sleep off)
*and* BIOS Preferred IO = Manual. It only matters for idle copy-only loads. Never write `/sys/.../pp_features` while the driver runs
(a full mask during GFXOFF hung the SMU and rebooted the box, E668).

## Do not retry (measured, closed on this hardware)

- Decode knobs alone: `--kv-resident` shrink, `--pipeline-windows 2` alone, other `--spec` / `--spec-min-p` pairs
  (the combination `--spec 3 --spec-min-p 0.7 --pipeline-windows 2` is what works).
- MMQ tile / stream-K changes for IQ3_S experts; `--prefill` chunks other than 8192 on Linux; tensor parallel (E234 +6%; E660–E664 decode 6–7% slower a window on 16 GB cards, cannot run beside `--parallel 2`); DFlash2 on two cards (E646/E647); draft-side switches under `--pipeline-windows 2` (the draft is off the critical path, E664).
- Kernel ideas closed on 11-06: prompt attention with dot2 scores (`STRATA_PROMPT_ATTN_RDNA2=2`, output error 3e-3 vs 2e-6, E702); MMQ IQ2_S / Q2_0 at
  fewer VGPRs (E700, no faster); the hc read without barriers (E691, an atomic barrier 22% slower); prefetch inside the int8 hc read (E693c, 0.4 µs);
  a second guess on the bonus token (E694b, +1.9 ms a row on card 0 eats the gain).
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
- Bandwidth only from kernel-level timing (not a profiled phase divided by bytes); a two-point fit only between points that differ in the one
  quantity fitted; decode differences below ~3% only from whole-run totals of real requests, with the baseline interleaved and interpolated.
- Scripts: `bench/run_ab.sh` (skeleton), `bench/benchmark.py` (4K/32K/128K prompts, fresh nonce each),
  `bench/monitor_amd.py` (telemetry). Paths in them are placeholders.

## Repository map

- `README.md` / `README.zh-CN.md` — overview. `docs/*.md` (English) and `docs/*.zh-CN.md` (Chinese) — the same content.
- `data/*.csv` — numbers behind the charts (`data/README.md` describes the columns).
- `patches/llama.cpp/` — eight patches on llama.cpp `159c651f5` plus `extra-mmq-y-scalar-rdna2.diff` (on 0001–0006); `patches/strata/` — the on-demand DP
  patch (0001) and the 11-06 kernel batch (0002); `bench/results/eNNN/` — raw results.
- `index.html` — interactive timeline (English and Chinese) and chart source; `tools/render_charts.py` renders `docs/*.png`.
- License: code MIT, text and data CC BY-NC 4.0.

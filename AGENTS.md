# AGENTS.md

Notes for an AI assistant (or a person) who wants to reproduce or extend this work. The full story is in `docs/`;
this file is the short, actionable part. Numbers below are measurements from the docs; check the doc before quoting.

## Hardware and software this applies to

- **Linux box:** 2x AMD RX 6900 XT 16 GB (gfx1030, PCIe 4.0 x8 each), Ryzen 5 5600X, 128 GB DDR4-3200, Ubuntu, ROCm 10.0,
  Strata (0.2.11 + patches + on-demand DP + MMQ activation reads + the 11-06 kernel batch, as of 2026-11-07). Model: Qwen3.8-Flash-Next GSQ-RCO IQ3_S (two GGUF shards + Strata pack).
- **Windows PC:** one RX 6900 XT 16 GB, i9-10900K, 64 GB, Windows 11, Strata Terminal 0.2.3.1 with the official
  `windows-x86_64-hip-rdna2` engine package 0.1.59 (release 0.2.13), and a local Windows build of `strata-0211fz`.
- Other RDNA2 cards (6800 / 6800 XT / 6950 XT = gfx1030, 6700 XT = gfx1031) were **not measured**; expect the same
  mechanisms, not the same numbers. RDNA3/RDNA4 differ (WMMA, other packages).

## Reproduce: one RX 6000 card on Windows (easiest)

Use `windows-rx6000/install-rx6000.ps1` (see its README). By default it installs a local build of the Linux production
source (`strata-0211fz`, for gfx1030 and gfx1031) from this repository's releases, checked against a SHA-256, with 40
switches (`$FastEnv` in the script), a rocBLAS table tuned on Windows, `--prefill 8192`, `--vram-reserve-mib 1536`,
`--kv-resident 32768`. Expected with Strata's standard benchmark on an RX 6900 XT: prompt 4K / 16K ≈ 779 / 1,333 tok/s,
decode ≈ 44–46, 12/12 sanity (E840; the released zip). `-Official` uses only the official package and 27 official switches: ≈ 809 / 1,157,
decode ≈ 40–44 (E838). Under Windows do **not** set `STRATA_SIDE_MIXER` (−22% decode), `STRATA_SH_STREAM` (−17 to −19%),
`STRATA_HIP_ADAPT_KERNEL_COPY` (−2.5%) or `STRATA_FUSE_WAIT` (−1%). Check first: ≥55 GB of RAM free before starting
(else the expert arena pages and everything runs at half speed or less), the monitor on the iGPU, a fixed page file about
the size of RAM, the model on local NVMe. The gfx1031 code and 12 GB cards were never run.

## Reproduce: two cards on Linux (the production configuration)

Production since 2026-11-11 22:3x (`strata-0211fz-72bb0be6`): Strata upstream 0.2.11 + our patches + upstream PR #5002's DP prompt read + `patches/strata/0001`
+ the 11-06 kernel batch `patches/strata/0002` (one diff against `4783921b`, which already contains 0001) + `0003` (slots, hc int8-only, VRAM calibration,
elastic pictures; `git diff 3076edaf d86d3ec6`) + `0004` (decode fusions; one diff against `d86d3ec6`),
built against llama.cpp ggml with `patches/llama.cpp/` 0001–0006 + `extra-mmq-y-scalar-rdna2.diff` (`-DCMAKE_HIP_FLAGS=-DGGML_CUDA_MMQ_Y_SCALAR`).
Engine arguments of the production slot (paths replaced by `<…>`):

```
--pack <iq3_s> --native <...IQ3_S-00001-of-00002.gguf> --ple-gguf <...IQ3_S-00002-of-00002.gguf>
--expert-profile <expert-profile.bin> --expert-cache auto --prefill 16384 --spec 3 --spec-min-p 0.6 --mtp <rt>
--max-context 262144 --kv int8 --kv-resident 32768 --ple-io ram --vision --vram-reserve-mib 340
--pipeline-windows 2 --batch-mtp --conversation-cache-mib 0 --prefill-pipe 1600 --vram-reserve-later-mib 564 --mtp-q4 head
```

(With `STRATA_VRAM_CALIB=1` the two reserves only apply to a start that has no calibration yet; afterwards each card keeps what it measured
after its cache plus 192 MiB free. Delete `~/.cache/strata/vram-calib/` after changing the build or the config by hand. A config with
`STRATA_HC_I8ONLY=1` and fixed reserves needs 340 / 564.)

Run config: `"backend": "hip"`, `"gpu": [1, 0]`, `"layer_split": 27`, `"parallel": 2`, `"vram_elastic": true`, vision `"elastic": true, "elastic_no_warmup": true, "cuda_device": 0`
with `vision.exe` pointing to a wrapper that runs `strata-vision` under `GPU_MAX_HW_QUEUES=1` (two lines: `export GPU_MAX_HW_QUEUES=1` and `exec <dir>/strata-vision "$@"`; without it the two processes oversubscribe the hardware queues of card 0 and a request with pictures can stall, #267), sampling temperature 0 and
presence penalty 0 (the pipelined decode needs greedy sampling; a model card's presence penalty silently turns it off - E528, logged as "decodes serially").

Environment (beyond the earlier set `STRATA_HIP_PROMPT_F16=1 STRATA_HIP_ADAPT_KERNEL_COPY=1 STRATA_HC_PERSIST=1 STRATA_IO_THREADS=128
STRATA_PIPED_CONCURRENT=1 STRATA_PREFILL_CPU_SHARE=auto STRATA_PREFILL_STREAM_MIN=2048 STRATA_SH_STREAM=1 STRATA_SPLIT_MTP_BATCH=0
STRATA_PIPED_MTP=2 STRATA_SELECT_SIMT=2 STRATA_PREFILL_CPU_SHARE_BATCH=1 STRATA_ROCBLAS_TUNING=<dir>`):
`STRATA_STAGE_TRIM=1 STRATA_PREFILL_PIPE_FLOOR=4096`, the GDN group `STRATA_GDN_HEAD=1 STRATA_GDN_PP=2 STRATA_GDN_CONVL2=1 STRATA_GDN_NOY=1`,
`STRATA_DEQUANT_WIDE=1`, the slot copy `STRATA_SLOT_COPY_DIRECT=1 STRATA_SLOT_COPY_BATCHSYNC=1 STRATA_SLOT_CKPT_MOVE=1`, `STRATA_SIDE_MIXER=2`,
and the DP read `STRATA_DP_PREFILL=1 STRATA_KV_HOST_DMA=1 STRATA_DP_MIN=9216 (12288 until 11-07; E712) STRATA_DP_PEER_RES=0` (PR #5002 + its `dp-followups`) plus the switches
that only exist with `patches/strata/`: `STRATA_DP_BATCH=1 STRATA_DP_LAZY=1 STRATA_DP_STAGE_W=3 STRATA_DP_STAGE_MIN=0 STRATA_DP_MTP_ALL=1`. Local patches still
not upstream: `STRATA_PW_WITH_BATCH=1` (#3095), `STRATA_PROMPT_ATTN_RDNA2=1` (#3381). On a stock build unknown switches are ignored
silently; confirm each from the engine log. The production json is the reference; `docs/linux-dual-6900xt.md` has the current state and `docs/linux-history.md` the reason for each switch.

Kernel-batch switches on top of the env above (they only exist with `patches/strata/0002` or 0.2.8+):
`STRATA_F16_NOWIDEN=1 STRATA_HC_PERSIST_Q8=2 STRATA_MMVQ_NW1=1 STRATA_EXP_TABLE=1 STRATA_SWIGLU_Q8=1 STRATA_ATTN_MERGE_V2=1 STRATA_FUSE_HITS=1
STRATA_IQ_STAGE_TABLES=1 STRATA_PLE_COMPACT=1 STRATA_PLE_COPY_STREAM=1`. `STRATA_HC_PERSIST_Q8=2` (int8 hc copies on Q8_0's grid, one fp16
scale per 32 values) is not bitwise: top-10 overlap with a double reference −0.7 points, KL within noise (E708); `=1` is a coarser grid (−1.3 points).
Card 0 then has ~430 MiB free after loading. On **one** card the copies take 641 MiB and the draft head did not fit in one of two cold starts
(E706): leave `STRATA_HC_PERSIST_Q8` off there, or free VRAM first.

Switches of `0003` / `0004` on top (11-07 – 11-11): `STRATA_SLOT_LAZY=1 STRATA_HC_I8ONLY=1 STRATA_VRAM_CALIB=1 STRATA_DP_YIELD=2 STRATA_DP_YIELD_SMALL=4096`
and the six decode fusions `STRATA_ROUTE_BELL=1 STRATA_HCP_Q81=1 STRATA_FUSE_WAIT=2 STRATA_FETCH_REBASE=1 STRATA_GU_SWIGLU=1 STRATA_GDN_Q81=1`.
Card 0 has ~300–380 MiB free after loading (the calibration's design: growth + 192 MiB).

Expected (this config): gate run 4K / 16K prompt 1,235 / 2,104 tok/s, 128K / 250K 2,652 / 2,645 with decode 82.9 / 84.4, 12/12 (E772);
`bench/benchmark.py` 4K / 32K, parallel 1, two runs each (E799, three cold starts): prompt 1,248–1,252 / 2,393–2,398, decode 93.6–98.6 / 102.7–108.3,
22.0–22.2 ms per verify window. The 11-07 numbers (0211wl2) are in `docs/linux-history.md`.
Rollback build: `strata-0211vx-006a704b` (no `0004`, no fusion switches): +1.3% per window (E772).

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
- Windows: `STRATA_SH_STREAM` and `STRATA_SIDE_MIXER` (decode −17 to −22%; the KV-streaming fault of 0.1.48 no longer reproduces on 0.1.59), large pages (error 1450 with 64 GB),
  a rocBLAS table made under Linux (refused), a VRAM reserve below ~1 GiB left free (pages, answers go wrong).
- Closed 11-09 – 11-13: engine `GPU_MAX_HW_QUEUES=5` (−4.1% per window, E799; 4 is best, 2 deadlocks with pictures); the draft model on the first card
  (`STRATA_MTP_STAGE0=1`, −13.4%, E798); MEC/SDMA firmware 0x86/0x58 against the #267 stall (still stalls, E797); KV window 8192 (E747);
  asynchronous refill after a prompt read (E751, PCIe is zero-sum); lending the draft model's experts to the prompt ring (`STRATA_MTP_ROOM_MIN`: two cards E661i, one card E822, no gain); the CPU activation quantised like the GPU's (`STRATA_CPU_ACT_Q81`, no end-to-end gain, E735–E737).
- Foresight swap space (`STRATA_FS_SLOTS`, upstream) - closed after E803–E820, see `docs/linux-history.md` (11-13). Two traps worth knowing even
  without FS: threads created after the host pins itself stay on the host's one CPU unless `STRATA_PIPED_CONCURRENT` is on (FS turns it off),
  and `STRATA_FS_VERIFY=1` deadlocks the pipelined decode.
- Full list with reasons: `docs/linux-history.md` ("Closed directions"), `docs/windows-one-card.md`,
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

- `README.md` / `README.zh-CN.md` — overview. `docs/linux-dual-6900xt.md` — current two-card state (short); `docs/linux-history.md` — every experiment, newest first. `docs/*.md` (English) and `docs/*.zh-CN.md` (Chinese) — the same content.
- `data/*.csv` — numbers behind the charts (`data/README.md` describes the columns).
- `patches/llama.cpp/` — eight patches on llama.cpp `159c651f5` plus `extra-mmq-y-scalar-rdna2.diff` (on 0001–0006); `patches/strata/` — the on-demand DP
  patch (0001) and the 11-06 kernel batch (0002); `bench/results/eNNN/` — raw results.
- `index.html` — interactive timeline (English and Chinese) and chart source; `tools/render_charts.py` renders `docs/*.png`.
- License: code MIT, text and data CC BY-NC 4.0.

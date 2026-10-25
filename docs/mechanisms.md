# Mechanisms learned, and mistakes made

[← README](../README.md) · [中文](mechanisms.zh-CN.md)

## What was learned about the mechanisms

- Strata's expert prompt GEMMs *are* llama.cpp's MMQ kernels (`moe_mmq.cu`), so llama.cpp-side MMQ changes can be carried into Strata through `STRATA_GGML_DIR`; the rocBLAS table and the SIMT scorer only cover the dense projections and QSA scoring.
- Decode: speed = accepted tokens per window ÷ window time. A verify window was ≈ 33 ms of fixed cost with the two cards' layer stages one after the other (10-08, `--pipeline-windows 1`); with two windows in flight (`--pipeline-windows 2`) it is ≈ 25–28 ms (E481, E499). Longer drafts or a lower min-p lower the acceptance rate, shorter drafts or a higher min-p cut the window short: 4/0.5 was the peak without the overlap (E385), 3/0.7 is with it (E387).
- Flash-Next's resident KV window is only ~100–200 MB; VRAM is dominated by the expert cache (6,123 slots on the primary card on 10-07 with the vision encoder there; 5,534 + 4,273 without it on 10-20), and both prompt and decode speed follow the slot count.
- Strata can stream KV from RAM because QSA attention is sparse (98.7% of block reads hit VRAM); a full-attention model (the dense 27B on the same box) has no such path.
- The GFXOFF ↔ ROCm CP-barrier interaction is the root of the stalls (#884, drm/amd #5945); the mitigation is kernel-copy, not the guard.
- The layer-split point is a decode knob on its own: without the vision encoder the second card has 1.7 GiB more free, the auto split moves from 0-26/27-47 to 0-24/25-47 and 32K decode drops 74 → 69 (−8%) while the hit rate goes up; with `--pipeline-windows 2` both splits reach 82 (E388). A manual `layer_split` sweep has not been done.
- A short prompt is a PCIe problem, a long one is not: below the full-streaming chunk size (`stream_all_min`) a chunk copies only its routed experts, and with ~10 of 512 experts per token a few hundred tokens touch most of them - 43–54% of a <2K read waits on PCIe (E482). Hence `STREAM_MIN=2048` and the CPU share for short reads (E485, E493).
- Routing-sensitive switches must be measured on real text: a repeated word-list prompt routes to few experts and made a setting look better than it is (E483 vs E484/E485).
- With batch slots upstream turns two things off silently for a lone request: `--pipeline-windows` (−11–16% decode) and the prompt's CPU share. Both came back as opt-ins (#3095, #3382).
- The expert cache is not prediction-limited (E499): replaying 266K real routing records, the adaptive cache (85%) beats the best static set and Radiance-style decayed LFU is within 1.4 points; foresight only helps when the swap budget per window grows.
- Kernel accuracy: an end-to-end KL "closer to the FP64 reference" does not mean a kernel is more accurate - it was within the run-to-run spread of equivalent FP32 paths; an operator-level FP64 test said the first version was 1.2–1.4x *less* accurate, and a blocked sum per chunk fixed it at +1.6% time (E498e, E502).

## Mistakes made along the way (kept so they are not repeated)

- Treated the `amdgpu_gfxoff` knob as a level when it is a refcount; every "default on" arm of E335–E338 was invalid (10-06).
- Misread the split timing lines: the "whole call" card's `embed+steps` includes waiting for the other card (E361).
- Assumed the resident KV window was a large share of VRAM and ran E382 before doing the arithmetic (+40 slots).
- Read an upstream PR's whole body and grep your own log for it and its predecessor before measuring it: three rounds on #1123 before noticing we had measured its predecessor #1006 on 10-06 and the PR cites our numbers (E392).
- Declared `--pipeline-windows 2` and the spec grid closed after one single-variable sweep each (E384/E385); the two knobs interact and the combination is +10–16% (E387).
- Expected +10–30% from `--pipeline-windows`; measured +1–6% with non-deterministic output — the estimate ignored that the guess rate is bounded by 2.3 accepted tokens per window.
- Upgraded to 0.1.39 without checking the old build's local patches one by one; helper decode fell to 39 tok/s (10-04 19:40).
- Built a comparison tree without diffing CMakeCache and lost a bisection to a missing `STRATA_PREFILL_MMQ=ON` (10-04).
- Wrote "our ggml patches will help #1897" into a draft comment from the 27B kernel numbers, before measuring them inside Strata; measured, they do nothing there (E414). Measure first, then write.
- A gh comment was not posted because the leak check `grep -c claude.ai` returns exit 1 on zero matches and cut the `&&` chain; use `! grep -q`.
- Built upstream 0.2.0 from the docs' minimal command, without setup.py's `STRATA_PREFILL_MMQ=ON`, and read a 1.75x slower prompt as a possible regression before diffing CMakeCache - the 10-04 mistake again (E501).
- Measured with a synthetic word-list prompt for a routing-sensitive switch and nearly put the wrong value in production (E483).
- Called a kernel "more accurate" from an end-to-end KL ranking; an FP64 unit test showed the opposite (E498e).
- Stopped an experiment script before its engine: the restore trap put production back while the test engine still held both cards (~12 s, no request came in). Stop the engine first, then the script; never `pgrep -f` a pattern that is in your own command line (E501).
- A first replay of an expert-cache upper bound treated every expert not needed within the window horizon as never needed again, and produced a "perfect foresight is worse than the real cache" number (E499); the instrumented dump had also been hooked on one of four code paths only.
- Wrote "the same failures as main" in a PR draft for a build whose tests had not been run; caught before posting.

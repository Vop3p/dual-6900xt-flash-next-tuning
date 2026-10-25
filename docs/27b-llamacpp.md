# The dense Qwen3.8-27B on llama.cpp (`qwen38-tp`) and the llama.cpp patches

[← README](../README.md) · [中文](27b-llamacpp.zh-CN.md)

**`patches/llama.cpp/`** — eight llama.cpp patches on upstream `159c651f5`: 1–7 are the RDNA2 MMQ work behind the `q8k ggml` step (wider tiles, mad24 scales, Q8_K-style activations, VOP3P dot-chain heads), 8 is an int8 QK^T flash-attention tile kernel for a q8_0 K cache; build flags and measured effects in [their README](../patches/llama.cpp/README.md). Strata picks the MMQ ones up through `-DSTRATA_GGML_DIR`. They were made on the dense **Qwen3.8-27B** that the same two cards serve through llama.cpp, below.

The same two cards also serve the dense Qwen3.8-27B through llama.cpp: `-sm tensor` (RCCL allreduce over the two x8 links through the host), q8_0 KV, 196K context, MTP draft (`--spec-draft-n-max 3`), three slots. Full attention, so none of Strata's expert/KV-streaming tricks apply; this is where the llama.cpp patches above were made, and patch 8 only exists for it. It is not on the interactive timeline page.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="q38-now-en-dark.png">
  <img alt="Production state and speed of the 27B now" src="q38-now-en-light.png" width="100%">
</picture>

**Where it stands (10-09 15:10):** production binary = upstream `159c651f5` + patches 1–8, env `GGML_FATTN_KQ8=1`. Prompt 740–820 tok/s up to 8K, 731 at 32K, 512 at 128K; decode 62 tok/s at short context (MTP: ~3.2 accepted tokens per 51 ms step), 44 at 32K depth, 25–28 at 128K. KLD vs bf16 0.003704, top-1 agreement 97.29% (stock kernels on the same quant: 0.003941 / 97.32%). Needles 8/8 at 32K, 4/4 at 128K. VRAM 15.8 GB per card at 196K.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="q38-speed-en-dark.png">
  <img alt="Prompt and decode speed of the 27B at each production state, 09-26 to 10-09" src="q38-speed-en-light.png" width="100%">
</picture>

| Date | Step | Measured effect |
| --- | --- | --- |
| 09-26 | E157: v3 UD-Q5_K_XL chosen over UD-Q4_K_XL (KLD vs a 54 GB bf16 reference, 64×512 mixed zh/en) | 0.0039 vs 0.0116; Q4 would be +10.5% faster and 1.2 GiB/card smaller; precision chosen |
| 09-27 | E152: reproducing the production numbers on the host | `--cache-ram 0` switches off idle-slot caching and, with `-kvu`, slows new requests 30–40% — nearly four false conclusions; copy every parameter, caches included |
| 09-29 | host binary instead of the docker image; RDNA2 K-quant MMQ tiles (patch 2; a K512 variant was 1.9× on the sweep and wrong on real shapes) | prefill 2.5K 617→683, 9.8K 623→677, 30K 566→600; bit-identical; decode unchanged |
| 10-02 | mad24 scale multiplies (patch 3) | prefill +8–9%, bit-identical, decode −1% |
| 10-02 | E200b phase timing, 10K prefill: MMQ 64–67%, RCCL ≤13%, FA 5%, GDN 5% | K-quant MMQ ~40% slower than q8_0 because of per-sub-block float scales → the activation layout became the target (done 10-08) |
| 10-08 | Q8_K-style MMQ activations + VOP3P dot-chain heads (patches 4–6) | prefill +4.6–6.1% (2K 774→812, 8K 773→811, 32K 674→705); KLD 0.003941→0.003736; dead ends: 256 values per scale (+25% KLD), k01 unroll (>1000 VGPR), VOP3P heads on q4_K/q5_K (−10%) |
| 10-08 | E377 kernel-level timing: MMQ 60–72%, allreduce 14–16% (BF16, 2 per layer, already at PCIe speed), FA 2% at 2K → 17% at 32K, GDN 5–6% | FA is the long-context target |
| 10-08 | E381 FA tile kernel sweep (nbatch_fa, nbatch_K, occupancy, threads; 10 points) | upstream defaults are the local optimum on gfx1030; no point >+3%; the kernel sits at 35% of fp16 peak by structure (LDS reuse per 32 columns × 64 keys, half2 packing), not by parameters |
| 10-09 | **int8 QK^T in the FA tile kernel** (patch 8; E406–E410, one day) | kernel 1.31× at 16K/64K; end to end prefill 32K +3.3–3.9%, 128K +11.1%, 2K/8K flat; decode/VRAM unchanged; KLD 0.003704; in production 15:10 |
| 10-09 | E411 decode phase timing (short context, production config, rocprofv3; the tracer itself costs 12%) | pie below; MTP is worth 2.1× (25.7 → 62 tok/s); HIP graphs are in use but worth only 2% (E411b) |
| 10-09 | E412 old vs new binary at short context | decode 62 ±1% both, 904-token prompt flat — patch 8 does not touch decode |

**Where a short-context decode step goes (E411, per card per ~51 ms step, 3.2 tokens):**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="q38-decode-en-dark.png">
  <img alt="Breakdown of one short-context decode step on the 27B: MMVQ 47%, launch gaps 23%, lm_head 10.6%, RCCL 8%, the rest 11.4%" src="q38-decode-en-light.png" width="100%">
</picture>

| Block | Share | Distance from the hardware |
| --- | --- | --- |
| MMVQ, 4-column verify batch over the 64 layers (~9.3 GB of weights per card) | 47% | 417 GB/s = 81% of peak bandwidth |
| Launch gaps (~2,500 kernels per step × 3–4 µs) | 23% | the `-sm tensor` meta backend splits each step into ~130 sub-graphs (one per allreduce), so each HIP graph holds a dozen kernels — disabling graphs costs only 1.5–2% |
| lm_head (1.35 GB q8_0, split by K across the cards; 3 draft passes + 1 verify pass) | 10.6% | each pass at peak bandwidth; the three draft passes are 8% |
| RCCL allreduce (~138 × 30 µs, 80 KB each) | 8% | latency-bound on PCIe x8 through the host |
| quantize (548 × 1.3 µs), RMSNorm, copies, GDN, FA | ~10% | small kernels |

No block is both large and cheap: MMVQ is at the bandwidth wall, the gaps need fewer kernels (fusion of the 1–4 µs kernels, +5–8% expected) or the allreduce inside the graph (a backend change, +15–20% at best, not measured), lm_head drafts would need a smaller `output.weight` quant (touches the main model), the allreduce is PCIe latency.

**Closed directions on the 27B (measured):** SGLang at the same bit width is not faster single-stream (E174, the earlier +6–12% was Q4 vs Q5); Vulkan; `-ub 2048` (+4–8% prompt but context must drop to 131K); `-np 1` (no single-stream gain); the FA tile parameter space (E381); MMVQ (at 81% of bandwidth); HIP graphs on/off (2%).

**Mistakes on this line:**

- `--cache-ram 0` in a host reproduction (E152) nearly produced four wrong conclusions; every cache parameter has to be copied.
- The int8 prototype's first four versions (1.04–1.11×) were read as the idea's ceiling; they were a register spill (256 VGPR + 31 spills) from keeping the Q scales in registers. Read the ISA/VGPR count before judging a kernel idea.
- The int8 precision blow-up (KLD 0.059, max 20) was chased for hours in the quantiser (outlier dims, rotations, SmoothQuant) — the cause was `launch_fattn`'s split-KV combine path, which the int8 kernel's LDS footprint had switched on; the upstream f16 kernel forced through the same path also loses precision. Read the launcher before touching the quantiser.
- Two experiment chains sharing one script and build directory produced binaries that were not what the log said (two readings thrown away); one chain at a time.
- Stacked `sed` macro edits deleted a real `#define`; macro variants belong in separate commits.
- Under rocprofv3, `llama-server` ignores SIGINT/SIGTERM (the tracer's handler); the trace database had already been written, and 30 minutes were spent waiting. SIGKILL after the database appears.
- E411's falsification criterion ("kernel time < 60% of wall time") was met and still did not answer "which block to cut"; the criterion should have been "largest block ≥30% and ≥25% from its hardware limit".

## Raw material in this repository

- `bench/results/e410`, `e411`, `e412` — the P/F cold-start A/B of patch 8 (scripts, report, KLD/perf run), the rocprofv3 decode pies and gap analysis (scripts and their text output; the 300–800 MB trace databases are not included), the old/new short-context check.

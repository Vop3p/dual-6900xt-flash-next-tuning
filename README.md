# dual-6900xt-flash-next-tuning

[中文](README.zh-CN.md) · Interactive timeline: `index.html` (GitHub Pages; Chinese)

Tuning log for **Qwen3.8-Flash-Next (GSQ-RCO IQ3_S)** on a home box with **2x AMD RX 6900 XT (gfx1030, PCIe 4.0 x8 each) / Ryzen 5 5600X / 128 GB DDR4**, ROCm 10.0 — from llama.cpp to [Strata](https://github.com/Niko1221/Strata), 2026-09-21 → 10-08. Experiment numbers (E…) refer to the author's lab notebook (not public). Every number is measured on this machine unless marked as an estimate.

## 0. Where it stands

- **Production (since 10-08 21:25):** Strata upstream 0.1.41 + 7 local patches (upstream PRs #1149 / #1151 / #1167 + a per-device rocBLAS solution cache) + a modified llama.cpp ggml (MMQ dot-chain heads in the VOP3P encoding on RDNA2). Two-card layer split, IQ3_S experts, int8 KV, MTP `--spec 4 --spec-min-p 0.5`.
- **Speed (production config):** prompt 4K ≈ 960–980 tok/s, 32K ≈ 1,710, 128K ≈ 1,950; decode 66–75 tok/s (one verify window ≈ 33 ms yielding 2.3 tokens).
- **Whole journey, same IQ3_S model:** decode 26 → 66–75 tok/s (≈2.7×), 37K/50K prompt 274 → ~1,700 tok/s (≈6×). The engine switch (llama.cpp → Strata) is most of it; the patches and configuration after that add about +50% prompt (714 → 1,433 → 1,705 → 1,711) and about +20% decode.
- **Closed directions (measured; do not retry on this box):** every decode-side configuration knob — `--kv-resident` shrink (E382), `--pipeline-windows 2` (E384, output becomes non-deterministic across starts), the 16-point `--spec` × `--spec-min-p` grid (E385, 4/0.5 is the peak of accepted tokens per window); batch slots (resident experts 41% < upstream's 50% gate, slots decode without MTP); MMQ tile / stream-K for IQ3_S (E279/E280); `--prefill` chunks other than 8192 (E296); tensor parallel (E234, +6%); and the upstream opt-ins that upstream itself measured as neutral or negative on small cards (chunked GDN, Foresight swap slots, pinned stage buffers).
- **What is left:** the PCIe topology (x16 + x4 would give ~1.5× on long prompts but breaks RCCL tensor parallel for the dense 27B model on the same box — a trade the owner has not made); and kernel-level work on the prompt side, where expert GEMM, GDN, QSA attention and the hc read each take 10–15% (≤10% each at best).

## 1. Timeline

| Date | Step | Measured effect |
| --- | --- | --- |
| 09-21/22 | llama.cpp expert cache (E140–E146): cache 56, inserts 8, MTP n-max 2 | 120K decode 10.9 → 13.0 tok/s; cache chains > 4 tokens crash in MMQ |
| 09-26 | `GGML_OP_OFFLOAD_MIN_BATCH=136`; PLE direct-read build | cold 8K prefill +13–18%, major page faults gone |
| 09-27 | E165 expert copies over both x8 links | only +1–4%: layers are serial; true pipelining needs a new scheduler (not done) |
| 09-29 | QSA gather (`LLAMA_QSA_GATHER=1`) | 96K: −9.6% per verify step; gather only applies to decode/MTP |
| 09-30 | new alias with GSQ-RCO IQ3_S + 112 cache slots | decode −19–20% per step, prefill +17–22% vs UD-Q4; 77% hit rate |
| 10-01 | upstream MTP vs our dense MTP; Vulkan | no measurable difference; Vulkan 55–90% slower, dropped |
| 10-02 | production llama.cpp build with 137 slots (upstream 159c651f5) | 10–18% faster per step than 112 slots; numerical noise floor KLD ≈ 0.025 |
| **10-04** | **Strata arrives** (E215/E216, HIP gfx1030) | same IQ3_S, 5K prompt: decode llama.cpp 26 → split 56–58 → helper 62–63; 37K prefill 274 → 714 |
| 10-04 02:30 | strata-split / strata-helper live (132a522; HIP: FP16 output GEMM, QSA S4) | 37K prefill split 1,433 / helper 978 |
| 10-04 17:00 | 0.1.39 (6add1a7) + FP16 prompt path → PR #835; #849 / #854 | 9.9K split 906 tok/s; helper needs `--pcie-frac 0` |
| 10-04 21:00 | prompt stall at layer 1 reproducible (~70%) → `--adapt-every 100000` | 0/3 stalls; root cause found 10-06 |
| 10-05 | stall root-cause chain (E251–E264, issue #884): MMQ + primary-card adapt + SDMA together; CP does not release a BARRIER_AND | disabling any one avoids it; one HW queue: 0 stalls but prompt −30% |
| 10-05 15:32 | production strata-238abe8 (0.1.39 + #835/#849/#854/#981 rocBLAS table) | 50K prompt 1,495 → 1,705 (+13–16%), decode unchanged |
| 10-05 19:05 | `STRATA_IO_THREADS=128` + `--ple-io ram` (memlock unlimited) | first-chunk PLE wait 568 → 10 ms, 8K prompt −7.4% latency |
| 10-05 20:25 | production strata-61c59fa (+#1007 select SGEMM) | 128K prompt +5% |
| 10-06 06:33 | **#884's strongest lead: GFXOFF** (0/10 stalls with it off); the knob is a refcount (corrected 11:05) | first a gfxoff guard, later kernel-copy |
| 10-06 09:42 | 0.1.40.1 baseline (E335) | split prompt 745 → 1,455 (F16), decode 58.6 → 64.5 (SH_STREAM) |
| 10-06 18:04 | production strata-341922e (0.1.40.1 + #1149/#1150/#1151 + rocBLAS table; env SH_STREAM=1, PROMPT_F16=1) | 128K split 2,003 tok/s |
| 10-06 19:10 | `STRATA_HIP_ADAPT_KERNEL_COPY=1` avoids the 128K split stall; gfxoff guard removed (power) | 0/3 vs 3/3 stalls, no speed cost |
| 10-06 22:20 | images on both split slots (self-built HIP strata-vision) | primary-card cache −11%, 32K prompt −3.6% |
| 10-07 16:54 | production strata-4592281 (0.1.40.2 + per-device rocBLAS solution cache) | speed flat; solutions no longer change between starts |
| 10-07 evening | #1151 reworked as the SIMT scorer (upstream 65ce329 ported to HIP) | 128K prompt +7.4%, byte-identical scores |
| 10-07 22:10 | vision encoder moved to HIP0 (split 0–26 / 27–47, primary cache 5,256 → 6,123 slots) | 32K prompt +2.8–3.8% |
| 10-08 | strata-ud-q4 slot (UD-Q4_K_XL, K-quant MMQ running on HIP) | decode −38%, 32K prompt −3% vs IQ3_S; kept only for quality comparison |
| 10-08 19:25 | production strata-q8k-4592281: ggml from the modified llama.cpp (MMQ q8_0 / iq3_s dot-chain heads in VOP3P, E378) | iq3_s kernel +2.6% → 32K prompt +1.4–1.5%, outputs byte-identical |
| 10-08 20:30 | E382 `--kv-resident` 32K → 16K | expert slots only +0.7%, 32K decode −3%, dropped |
| 10-08 21:25 | **production strata-141-d14ca361**: upstream 0.1.41 + the 7 patches rebased (clean) | 12 outputs byte-identical, speed ±0.5%, 0 stalls; json gets `gpu_order: as_given` |
| 10-08 21:27 | E384 `--pipeline-windows 2` | decode +1–6% but outputs differ between starts (2/7 same), 4K prompt −1–5%; dropped |
| 10-08 21:50 | E385 `--spec` × `--spec-min-p`, 16 points | only 5/0.6 at 32K +2.5% (single run); the rest negative; 4/0.5 kept |
| 10-08 22:50 | batch slots evaluated | resident experts 41% < upstream gate 50%; slots decode without MTP; not for this box |

## 2. What was learned about the mechanisms

- Strata's expert prompt GEMMs *are* llama.cpp's MMQ kernels (`moe_mmq.cu`), so llama.cpp-side MMQ changes can be carried into Strata through `STRATA_GGML_DIR`; the rocBLAS table and the SIMT scorer only cover the dense projections and QSA scoring.
- Decode: one verify window is ≈ 33 ms of fixed cost (the two cards' layer stages run one after the other), so speed = accepted tokens per window ÷ window time. Longer drafts or a lower min-p lower the acceptance rate; shorter drafts or a higher min-p cut the window short; 4/0.5 sits on the peak.
- Flash-Next's resident KV window is only ~100–200 MB; VRAM is dominated by the expert cache (6,123 slots on the primary card), and both prompt and decode speed follow the slot count.
- Strata can stream KV from RAM because QSA attention is sparse (98.7% of block reads hit VRAM); a full-attention model (the dense 27B on the same box) has no such path.
- The GFXOFF ↔ ROCm CP-barrier interaction is the root of the stalls (#884, drm/amd #5945); the mitigation is kernel-copy, not the guard.

## 3. Mistakes made along the way (kept so they are not repeated)

- Treated the `amdgpu_gfxoff` knob as a level when it is a refcount; every "default on" arm of E335–E338 was invalid (10-06).
- Misread the split timing lines: the "whole call" card's `embed+steps` includes waiting for the other card (E361).
- Assumed the resident KV window was a large share of VRAM and ran E382 before doing the arithmetic (+40 slots).
- Expected +10–30% from `--pipeline-windows`; measured +1–6% with non-deterministic output — the estimate ignored that the guess rate is bounded by 2.3 accepted tokens per window.
- Upgraded to 0.1.39 without checking the old build's local patches one by one; helper decode fell to 39 tok/s (10-04 19:40).
- Built a comparison tree without diffing CMakeCache and lost a bisection to a missing `STRATA_PREFILL_MMQ=ON` (10-04).

## 4. Repository contents

- `index.html` — the interactive timeline (speed chart of every production state + every step with reason and effect; Chinese).
- `bench/run_ab.sh` — A/B skeleton: one cold server per arm, full logs, confirmation lines; `benchmark.py` load generator (4K/32K/128K prompts, fresh nonce each), `ab_compare.py` pairwise text/speed comparison, `monitor_amd.py` telemetry sampler. Paths are placeholders.
- Upstream community reports from this box: Strata PR #927 and #1270.

Developed with an AI coding assistant; every number here was measured on 2x RX 6900 XT (gfx1030, PCIe 4.0 x8 each) / Ryzen 5 5600X, ROCm 10.0.

# llama.cpp patches (RDNA2 / gfx1030 MMQ)

Eight patches on top of upstream [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) `159c651f5` (2026-10-02). Patches 1–7 are the MMQ (prompt GEMM) work; patch 8 is the flash-attention tile kernel (int8 QK^T for a q8_0 K cache, opt-in). Apply with `git am`:

```bash
git clone https://github.com/ggml-org/llama.cpp && cd llama.cpp && git checkout 159c651f5
git am /path/to/patches/llama.cpp/*.patch   # 0001-0008
cmake -B build -DGGML_HIP=ON -DGGML_HIP_RCCL=ON -DAMDGPU_TARGETS=gfx1030 -DGGML_CUDA_MMQ_Q8K=ON -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_HIP_COMPILER=/opt/rocm/lib/llvm/bin/clang++
cmake --build build -j
```

| # | Patch | What it does | Measured on 2x RX 6900 XT |
|---|---|---|---|
| 1 | `common: recycled, non-zeroing buffers for context checkpoints` | server-side only: reuses checkpoint buffers instead of zeroing new ones | fewer page faults on long-context checkpoints; no kernel change |
| 2 | `RDNA2 MMQ J=80..128 tiles for Q4_K/Q5_K/Q6_K` | wider MMQ tiles for the RDNA2 register budget | prompt +7–11% on the tensor-parallel 27B (UD-Q5_K_XL), see timeline 09-29 |
| 3 | `full-rate 24-bit scale multiplies in the K-quant MMQ dot products on HIP` | `v_mul_lo_u32` → `mad24` where the operands fit 24 bits | prompt +8–9%, KLD unchanged (10-02) |
| 4 | `Q8_K style MMQ activations for K-quants on the dp4a path` (opt-in `GGML_CUDA_MMQ_Q8K`) | activations quantised with one fp32 scale per 128 values + int16 sub-block sums (`MMQ_Q8_1_DS_LAYOUT_DK`), integer accumulation | kernel: q4_K 25.9→27.8, q5_K 25.9→28.0, q6_K 25.3→28.9 TFLOPS (test-backend-ops 4096x512x14336) |
| 5 | `Q8_K MMQ activations at 128 values per scale; q6_K dot chains start as VOP3P` | `GGML_CUDA_MMQ_Q8K_BLOCK` default 128; `ggml_cuda_dp4a_z` (`v_dot4_i32_i8 d,a,b,0` instead of `v_mov 0` + `v_dot4c`) at the head of each q6_K dot chain | q6_K +4.7%; on q4_K/q5_K the same trick schedules 10% worse, so it is per type |
| 6 | `q8_0 dot chains start as VOP3P on RDNA2` | the same for `vec_dot_q8_0_q8_1_impl` | q8_0 33.8→35.0, iq3_s 30.9→31.7 TFLOPS |
| 7 | `the q8_0_16 dot chains (IQ2_XS, IQ2_S MMQ tiles) start as VOP3P on RDNA2` | the same for `vec_dot_q8_0_16_q8_1_impl`, the last MMQ dot product without it | iq2_s 26.3→28.5 (+9%), iq2_xs 26.9→29.1 (+8%); iq3_xxs unchanged. Note: in MMQ every IQ type except IQ2_XS/IQ2_S already goes through patch 6's function (Q8_0 tiles), so patches 6+7 cover all expert types of the IQ3_S pack (whose experts are a mix: gate/up IQ3_XXS/IQ3_S/IQ2_S/IQ4_XS, down IQ4_NL/Q2_0). End to end on Strata (2 cards, 32K): +0.6–1.1% |
| 8 | `int8 QK^T in the FA tile kernel for q8_0 K on RDNA2` (opt-in env `GGML_FATTN_KQ8=1`, D=256) | K rows repacked once per launch into 272-B rows (256 int8 + 8 half scales), Q quantised in the kernel prologue to int8 per 32 dims, QK^T in int32 via `v_dot4` with one fp32 fold per block; the int8 path stays off `launch_fattn`'s split-KV combine (that combine loses precision on its own: the upstream f16 kernel forced through it goes from max KLD 0.46 to 1.21). Prints a confirm line when engaged; without the env the kernel is unchanged. | FA kernel (256/256, 6 heads / 1 KV head, q8_0 KV): 16K 12.81→9.81 ms, 64K 52.93→40.8 ms (1.30–1.31×); 221 VGPR, no spills; 8/8 correctness. End to end on the 27B: prefill 2K/8K flat, 32K +3.3–3.9%, 128K +11.1% (460.5→511.6 tok/s); decode and VRAM unchanged; KLD 0.003736→0.003704, top-1 97.12→97.29%, max 0.456→0.558. Only instantiated on HIP builds; includes the test-backend-ops cases and two env-gated dump hooks used for the precision investigation. |

End to end (4–6 together, production `qwen38-tp`, Qwen3.8-27B UD-Q5_K_XL, two cards `-sm tensor`): prompt +4.6–6.1% across 4K–196K, KLD vs bf16 0.003941 → 0.003736 (top-1 agreement 97.32% → 97.12%, within the noise of the base quant). In [Strata](https://github.com/Niko1221/Strata), which takes its expert prompt GEMMs from this MMQ, building with `-DSTRATA_GGML_DIR=/path/to/this/llama.cpp` gives +1.5% at a 32K prompt with byte-identical output (iq3_s kernel +2.6%).

Only tested on gfx1030 (ROCm 10.0, HIP clang). The `asm` in patches 5–6 is guarded by `defined(GGML_USE_HIP) && defined(RDNA2)`; other targets compile the unchanged `ggml_cuda_dp4a`. `test-backend-ops -o MUL_MAT`: 1304/1304 pass.

## License

MIT (`LICENSE` in this directory), the same license as llama.cpp. The patches are derived works of [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT, Copyright (c) 2023-2026 The ggml authors); applying them with `git am` adds nothing that llama.cpp's own license does not already permit. Cite the repository (`CITATION.cff` at the top level) or the commit hashes in the patch files.

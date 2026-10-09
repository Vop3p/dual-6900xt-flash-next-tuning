# llama.cpp patches (RDNA2 / gfx1030 MMQ)

Six patches on top of upstream [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) `159c651f5` (2026-10-02). Apply with `git am`:

```bash
git clone https://github.com/ggml-org/llama.cpp && cd llama.cpp && git checkout 159c651f5
git am /path/to/patches/llama.cpp/*.patch
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

End to end (4–6 together, production `qwen38-tp`, Qwen3.8-27B UD-Q5_K_XL, two cards `-sm tensor`): prompt +4.6–6.1% across 4K–196K, KLD vs bf16 0.003941 → 0.003736 (top-1 agreement 97.32% → 97.12%, within the noise of the base quant). In [Strata](https://github.com/Niko1221/Strata), which takes its expert prompt GEMMs from this MMQ, building with `-DSTRATA_GGML_DIR=/path/to/this/llama.cpp` gives +1.5% at a 32K prompt with byte-identical output (iq3_s kernel +2.6%).

Only tested on gfx1030 (ROCm 10.0, HIP clang). The `asm` in patches 5–6 is guarded by `defined(GGML_USE_HIP) && defined(RDNA2)`; other targets compile the unchanged `ggml_cuda_dp4a`. `test-backend-ops -o MUL_MAT`: 1304/1304 pass.

## License

MIT (`LICENSE` in this directory), the same license as llama.cpp. The patches are derived works of [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT, Copyright (c) 2023-2026 The ggml authors); applying them with `git am` adds nothing that llama.cpp's own license does not already permit. Cite the repository (`CITATION.cff` at the top level) or the commit hashes in the patch files.

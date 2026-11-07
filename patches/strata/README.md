# Strata patches for 2x RX 6900 XT

[← README](../../README.md)

`0001-dp-ondemand-2x6900xt.patch` - one commit (`9b0e19d4` in the author's tree), MIT like the rest of `patches/`.

**Base:** Strata upstream PR [#5002](https://github.com/Niko1221/Strata/pull/5002) (data-parallel prompt read, `STRATA_DP_PREFILL`) plus
its two `dp-followups` commits (`STRATA_DP_PEER_RES`, DP with stage trim). Production runs it on v0.2.10 + the local patches
(`strata-0210dp-e6e76570`). `git apply --check` also passes on `rafatxf/dp-followups` at `b2b31f1d`; that combination was not built.

Every change is opt-in; with none of the switches set the engine behaves as the base.

| Switch | What it does | Measured here (E663–E676) |
|---|---|---|
| (always) `WeightTable::find` | the DP fallback looks only at the other table's own rows; before, a name neither table held recursed until SIGSEGV | the first DP read with stage trim crashed every time |
| `STRATA_DP_BATCH=1` | DP may start with `--batch` slots; the `STRATA_PIPED_CONCURRENT` read steps aside when the DP path takes the read (no slot decoding) | DP reached production's `--parallel 2` |
| `STRATA_DP_LAZY=1` | the DP foreign sessions live in the slots a DP read borrows (`Prefill::set_dp_room`), rebuilt at the start of each DP read | the 534 expert slots a card lost to resident sessions come back |
| `STRATA_DP_STAGE_W=N` | a ring of N per-layer slots; a foreign layer's rows (and the next N−1 layers') are `cudaMemcpyPeerAsync`'d on a side stream | N = 3: compute waited 0–1 ms per 128K read; N = 6 no change |
| `STRATA_DP_STAGE_MIN=<bytes>` | rows below this stay in place on the peer; `0` copies every row | 0: +4.4~5.9% (the small rows were stage trim's whole cost) |
| `STRATA_DP_MTP_ALL=1` | both paths' chunks reach the drafter in prompt order | tokens per window −4% → back to the layer-pipeline value |
| `STRATA_DP_STAGE_TIMING=1`, `STRATA_DP_TRACE=1` | diagnostics (copy/wait events; one line per DP decision) | - |

Production also sets `STRATA_DP_PEER_RES=0` (upstream switch, +4~6% here) and `--prefill 16384`. End-to-end:
prompt +8~10% (16K / 32K / 128K 1,858 / 2,094 / 2,425), decode unchanged, 12/12 - see
[docs/linux-history.md](../../docs/linux-history.md) and `data/linux-dp-0.2.10.csv`.

Limit: while a DP read runs, a request that arrives waits for it to finish.

## `0002-waitlist-0211-2x6900xt.patch` - the 11-06 kernel batch (production since 11-06 22:3x)

A plain `git diff` (apply with `git apply`, not `git am`) against the author's `prod-0211` tree at `4783921b`: Strata v0.2.11
merged into the local patch set *including* `0001` above (one conflict on the merge, both sides kept). Built as
`strata-0211wl2-1a996f63`, in production since 11-06 22:3x with `STRATA_HC_PERSIST_Q8=2` (E703/E704/E708).
Every change is opt-in.

| Switch | What it does | Measured here |
|---|---|---|
| `STRATA_F16_NOWIDEN=1` | the hyper-connection up projection and `attn_qkv` stay FP16 in the prompt path; the mixer and the GDN convolution read FP16 directly instead of a widened FP32 copy (`STRATA_F16_NOWIDEN_CHECK=N` / `_QKV_CHECK=N`: compare against the widening path for the first N calls) | bitwise equal (12/12 and 6/6 self-checks, E688/E688b); prompt 8K +1.3~2.7%, 32K +1.9~2.1% for the up projection alone |
| `STRATA_HC_PERSIST_Q8=2` (recommended; `=1` still works) | the verifier's persistent hc read (`STRATA_HC_PERSIST=1`) reads int8 copies of its weights, made once at start. `=2`: Q8_0's grid, one fp16 scale per 32 values (the grid upstream's `STRATA_HC_Q8` uses). `=1`: the older, coarser grid, down / inject one fp32 scale per (row, 128 columns), up one per 320-value row. A start-up check refuses copies whose relative error exceeds 2e-2 | decode +6.4% whole-run (E693b, `=1`), +8.5% with the rest of this patch (E703, `=1`); `=2` against `=1`: decode +0.3% (noise), self-check max relative difference 0.00497 vs 0.00705, top-10 overlap with a double reference −0.7 points from the unquantised read vs −1.3 for `=1` (upstream `STRATA_HC_Q8`: −0.4), KL within the chat-to-chat spread (E708); **not bitwise**; copies 360 / 280 MiB on the two cards (`=1`: 347 / 269), 641 MiB on one card |
| `STRATA_MMVQ_NW1=1` | dense decode GEMV (qkv / q / gate / shared expert) with T = 2–4 tokens uses a one-warp-per-row variant for inputs up to 4096 | kernel −6~42% at T = 2–4 (E698), bitwise |
| `STRATA_EXP_TABLE=1` | the decode expert kernels pick their layout per quant format (gate/up IQ2_S and IQ3_S → layout 8, down Q2_0 → layout 4, others unchanged) instead of one global `STRATA_EXP_MODE` | layer time −5~27% at G20T1 / G10T2 (E698/E699), bitwise; slower in the few-groups-many-tokens case (G6T3) |
| `STRATA_SWIGLU_Q8=1` | the existing fused SwiGLU + `quantize_mmq_q8_1` kernel is compiled and used on HIP as well (it was CUDA-only); `STRATA_SWIGLU_Q8_CHECK=N` compares bytes for the first N calls | 408/408 byte-identical (IQ4_NL and Q2_0 down, E701); estimated ≤+1% prompt (not measured alone) |
| `STRATA_PROMPT_ATTN_RDNA2=2` | **not used.** A dot2 score phase for the RDNA2 prompt attention: kernel −14% but its output error was 3e-3 against FP64 vs 2e-6 for mode 1 (E702), so it was rejected; the code is left in the diff, mode 1 is what production runs | - |

Together with upstream switches already in 0.2.8+ (`STRATA_ATTN_MERGE_V2 STRATA_FUSE_HITS STRATA_IQ_STAGE_TABLES STRATA_PLE_COMPACT
STRATA_PLE_COPY_STREAM`) and `--mtp-q4 head`, and `--vram-reserve-later-mib 844` (444 + 400 for the int8 copies), E703 measured on
this box: deterministic prompt 8K +4.3~4.5%, 32K +7.2~7.4%; decode whole-run +8.5% (three interpolated pairs +7.2 / +10.9 / +7.5%);
gate 12/12; 128K / 200K reads without OOM or stall. Cost: card 0 has ~430–450 MiB left after loading instead of 908 (its expert slots
do not shrink); on one card the 641 MiB of copies left too little for the draft head in one of two cold starts (E706), so on one card leave
`STRATA_HC_PERSIST_Q8` off or free VRAM first; E704's worst case (200K read + a picture + 32K concurrently, then two 120K reads at once, GPU vision on) ran 9/9
with 0 stalls and a VRAM peak of 16.3 GB without paging. See `docs/linux-history.md`.

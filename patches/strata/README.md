# Strata patch: on-demand DP prompt read on 2x RX 6900 XT

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
[docs/linux-dual-6900xt.md](../../docs/linux-dual-6900xt.md) and `data/linux-dp-0.2.10.csv`.

Limit: while a DP read runs, a request that arrives waits for it to finish.

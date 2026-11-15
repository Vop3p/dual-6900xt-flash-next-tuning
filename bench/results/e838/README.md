# E838: the lazy pack's settings on the official 0.2.13 package (2026-11-14)

One RX 6900 XT, Windows 11, i9-10900K, 64 GB. Official `rdna2` engine package 0.1.59 (release 0.2.13), unmodified. `strata bench run` with `--skip-model-hash` (so the runs say "nonconforming"; a full model hash had crashed the PC once that evening), 12/12 sanity in both.

| folder | settings | prompt 4K / 16K tok/s | decode short / 4K / 16K |
|---|---|---|---|
| `lazy-pack-old/` | the lazy pack until 11-14 (8 switches incl. `STRATA_HIP_ADAPT_KERNEL_COPY`, `STRATA_HOST_CORE=sibling`) | 615.8 / 1,077.6 | 44.6 / 40.4 / 43.6 |
| `lazy-pack-official-new/` | the new `-Official` preset (27 switches: + #4005 copy events, GDN / PLE / slot switches; no ADAPT_KERNEL_COPY; no rocBLAS table) | 809.4 / 1,156.6 | 43.6 / 40.4 / 40.4 |

Free RAM before each start was ≥53 GB. A repeat of the old settings read 612.2 / 1,075.0 (within 1%). The Windows user name in `config.json` is replaced by `<user>`.

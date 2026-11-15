# E837: Strata's standard benchmark on three setups (2026-11-14)

`strata bench run`, protocol `strata-qwen38-thinking-v1-draft.1`, client tree v0.2.13 (commit `d2f09647`). All three are complete runs with 12/12 sanity. The same files are in Strata PR [#5997](https://github.com/Niko1221/Strata/pull/5997).

| folder | machine | engine | prompt 4K / 16K tok/s | decode short / 4K / 16K |
|---|---|---|---|---|
| `L2x/` | 2x RX 6900 XT, Linux, Ryzen 5 5600X | production `strata-0211fz` (0.2.11 + patches), `--parallel 1` | 1,275.5 / 2,176.5 | 91.3 / 92.4 / 87.9 |
| `L1x/` | 1x RX 6900 XT, same Linux box | same build, one card | 1,074.0 / 1,473.0 | 51.6 / 47.9 / 52.7 |
| `Win1x/` | 1x RX 6900 XT, Windows 11, i9-10900K, 64 GB | local Windows build of `strata-0211fz`, 40 switches, rocBLAS table, `--prefill 8192` ("Ve") | 778 / 1,340 | 47.6 / 43.9 / 43.0 |

Paths in `config.json` are replaced by `<home>`.

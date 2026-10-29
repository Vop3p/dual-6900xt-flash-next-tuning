# data/

The numbers behind the charts, as CSV (UTF-8, comma-separated, empty cell = not measured). Measured on the machines in
the [README](../README.md); each row comes from the experiment named in the docs, under the conditions written there.
Text and data: CC BY-NC 4.0.

| File | Rows | Columns | Chart / source |
|---|---|---|---|
| `linux-speed-steps.csv` | each production state of the two-card Linux box, llama.cpp 10-02 → Strata 0.2.3 + patches 10-23 | `step`, `date` (MM-DD, 2026), prompt tok/s at 4K, at 32K–37K, at 128K, decode tok/s | `docs/speed-chart-*`; conditions differ between points (see the note under the chart in `index.html`) |
| `linux-breakdown-prompt-e505.csv` | 4K / 32K / 128K × stock (0.2.0-beta) / tuned (10-20 production) | ms per 1,000 prompt tokens per phase, total, tok/s | `docs/breakdown-prompt-*`; phases are estimates from the engine's timing switches, totals measured (E505) |
| `linux-breakdown-decode-e505.csv` | the same | ms per decoded token per phase, total, tok/s | `docs/breakdown-decode-*` (E505) |
| `linux-modes-0.1.41-32k.csv` | stock / two switches / PRs / E387 config × one card / expert helper / layer split | prompt and decode tok/s at 32K | `docs/modes-chart-*` (E388 / E388a, Strata 0.1.41) |
| `linux-standard-0.2.7.csv` | Strata's standard benchmark on 0.2.7 (E616): release package vs patched build, one card vs two, plus KVA on one card | prompt tok/s at 4K / 16K, decode at short / 4K / 16K (sampled, median of three), sanity | `docs/std-chart-*`; the runs are in `../bench/results/e616/` |
| `windows-steps.csv` | one RX 6900 XT, Windows 11, Strata's standard benchmark, step by step | `step` (zh), `step_en`, prompt tok/s at 4K and 16K, decode tok/s at 4K | `docs/win1x-chart-*`; the runs are in Strata PR #4012 |
| `timeline-steps.en.csv`, `timeline-steps.zh.csv` | every step on the interactive timeline (English / Chinese) | date, time, line of attack (`engine` / `prompt` / `decode` / `stable` / `drop`), step, why, effects (`[up]` / `[flat]` / `[down]`) | `index.html` |

Raw per-request data for many experiments is in `../bench/results/eNNN/`.

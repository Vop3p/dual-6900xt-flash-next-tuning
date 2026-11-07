# data/

The numbers behind the charts, as CSV (UTF-8, comma-separated, empty cell = not measured). Measured on the machines in
the [README](../README.md); each row comes from the experiment named in the docs, under the conditions written there.
Text and data: CC BY-NC 4.0.

| File | Rows | Columns | Chart / source |
|---|---|---|---|
| `linux-speed-steps.csv` | each production state of the two-card Linux box, llama.cpp 10-02 → Strata 0.2.8 + GDN group / wide dequant 10-30 | `step`, `date` (MM-DD, 2026), prompt tok/s at 4K, at 32K–37K, at 128K, decode tok/s | `docs/speed-chart-*`; conditions differ between points (see the note under the chart in `index.html`) |
| `linux-breakdown-prompt-e505.csv` | 4K / 32K / 128K × stock (0.2.0-beta) / tuned (10-20 production) | ms per 1,000 prompt tokens per phase, total, tok/s | `docs/breakdown-prompt-*`; phases are estimates from the engine's timing switches, totals measured (E505) |
| `linux-breakdown-decode-e505.csv` | the same | ms per decoded token per phase, total, tok/s | `docs/breakdown-decode-*` (E505) |
| `linux-modes-0.1.41-32k.csv` | stock / two switches / PRs / E387 config × one card / expert helper / layer split | prompt and decode tok/s at 32K | `docs/modes-chart-*` (E388 / E388a, Strata 0.1.41) |
| `linux-standard-0.2.7.csv` | Strata's standard benchmark on 0.2.7 (E616): release package vs patched build, one card vs two, plus KVA on one card | prompt tok/s at 4K / 16K, decode at short / 4K / 16K (sampled, median of three), sanity | `docs/std-chart-*`; the runs are in `../bench/results/e616/`; the trim row (E619) in `../bench/results/e619/` |
| `linux-standard-0.2.8-0.2.9.csv` | Strata's standard benchmark after each change 10-30 → 11-02 (E620–E642): 0.2.8, the GDN group + DEQUANT_WIDE, 0.2.9, UD-Q4, the concurrent config with and without slot copy / loop recovery, kernel 7.0.0-42 | prompt tok/s at 4K / 16K, decode at short / 4K / 16K (sampled, median of three, one run each), sanity, stalls | Linux doc, 10-30 – 11-02 section; the gate runs of E638 and E642 are in `../bench/results/e638/`, `../bench/results/e642/` |
| `linux-dp-0.2.10.csv` | the layer pipeline against the on-demand DP prompt read on 0.2.10 (E675/E676, production concurrent config, `bench/benchmark.py`, two interleaved runs) | prompt tok/s at 16K / 32K / 64K / 128K, decode tok/s at 4K / 32K | Linux doc, 11-03 – 11-06 section; `patches/strata/` |
| `linux-steps-0.2.11.csv` | the three steps of 11-06 in long format: 0.2.10dp → 0.2.11 (E678), → MMQ wave-uniform activation reads (E685), → the merged kernel batch (E703), its prompt curve against production and with DP off (E705/E705b), one card (E706), the standard benchmark (E707) and the Q8_0 hc grid (E708); one row per step × setup × metric, every run's value in its own column (`before_1..3`, `after_1..3`, blank when there was no such run) | prompt tok/s (1K–200K), decode tok/s, whole-run decode tok/ms and ms per window | Linux doc, 11-06 section; `patches/llama.cpp/extra-mmq-y-scalar-rdna2.diff`, `patches/strata/0002-*`. Rows marked "different sessions" are not same-session A/B pairs |
| `linux-dp-min-0.2.11.csv` | the 11-07 `STRATA_DP_MIN` sweep (E712): production binary `strata-0211wl2-1a996f63`, thresholds 12,288 / 8,448 / 9,728, six lengths 8.7K–12.3K, every request one row | prompt tok/s, decode tok/s, decode ms per window (decode ms ÷ (output tokens − accepted drafts)), accepted drafts | Linux doc, "DP threshold" section; production since 11-07 is 9,216 |
| `windows-steps.csv` | one RX 6900 XT, Windows 11, Strata's standard benchmark, step by step | `step` (zh), `step_en`, prompt tok/s at 4K and 16K, decode tok/s at 4K | `docs/win1x-chart-*`; the runs are in Strata PR #4012 |
| `timeline-steps.en.csv`, `timeline-steps.zh.csv` | every step on the interactive timeline (English / Chinese) | date, time, line of attack (`engine` / `prompt` / `decode` / `stable` / `drop`), step, why, effects (`[up]` / `[flat]` / `[down]`) | `index.html` |

Raw per-request data for many experiments is in `../bench/results/eNNN/`.

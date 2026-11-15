# E840: the released lazy-pack bundle (gfx1030 + gfx1031), installed and checked (2026-11-14)

The fast bundle rebuilt for both RX 6000 targets (`STRATA_HIP_ARCHS=gfx1030;gfx1031`, otherwise the same source and options as E839's gfx1030-only build): `strata-rx6000-fast-0211fz-win-gfx103x.zip`, 148.6 MB, SHA-256 `27ffeb429ec7281df3111bf52e8e1d7b8cbb526b42b6f7102238aa34b901079c`. This is the zip in the release.

Installed on the Windows PC (one RX 6900 XT, i9-10900K, 64 GB, 54 GB free at start) with `windows-rx6000/install-rx6000.ps1 -ModelPath … -FastZip <zip>` (`install.log`, user name replaced), then:

- a test picture through the default CPU picture reader, before and after the benchmark (`run.log`): invoice 7731, total 48.25 EUR, red rectangle, blue circle, both times correct (8.0 s / 7.2 s);
- Strata's standard benchmark (`--skip-model-hash`, so "nonconforming"): prompt 4K / 16K **778.9 / 1,332.6** tok/s, decode 45.9 / 44.5 / 43.5, **12/12** sanity (`standard/`).

Against E839 (gfx1030-only build, 798.6 / 1,342.5, decode 44.6 / 41.0 / 44.5) all within 3%. The gfx1031 code was never run (no such card here).

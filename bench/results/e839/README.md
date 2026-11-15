# E839: the new lazy pack, installed the way a user would (2026-11-14)

`windows-rx6000/install-rx6000.ps1 -ModelPath … -FastZip <the release zip>` on the Windows PC (one RX 6900 XT, i9-10900K, 64 GB): Terminal check → card check → official package and the `rx6000-tuned` preset → the fast pack (`strata-0211fz` Windows build, 40 switches, rocBLAS table) unpacked, `fast-run.json` written from the preset's run config, started with `start-fast.bat`. `install.log` is the PowerShell transcript (user name replaced).

Then Strata's standard benchmark on what the script started (`--skip-model-hash`): prompt 4K / 16K **798.6 / 1,342.5** tok/s, decode 44.6 / 41.0 / 44.5, 12/12 sanity (`standard/`).

The Terminal on that PC was 0.2.3.1; a fresh install gets a newer Terminal, which was not tried.

<#
.SYNOPSIS
  Strata on an RX 6800 / 6800 XT / 6900 XT / 6950 XT (gfx1030) or RX 6700 XT (gfx1031) under Windows, without compiling:
  the official Terminal and the official signed "rdna2" engine package, with settings measured on an RX 6900 XT.

.DESCRIPTION
  1. Installs the Strata Terminal with the official one-line installer (skipped when `strata` is already installed).
  2. Checks that Strata sees an RX 6000 card, and pins the engine choice to the official "rdna2" package
     (STRATA_ENGINE_BACKEND=hip-rdna2), so a PC with a second AMD GPU (an APU's Radeon 760M / 780M) cannot end up with
     another family's package.
  3. Sets up the model with `strata launch` and saves a preset with the tuned settings below, then starts it.

  Nothing here is built or downloaded from anywhere but the official Strata release and update feed.

.PARAMETER ModelPath
  A folder with model files you already have (the two .gguf shards of Qwen3.8-Flash-Next). Without it, `strata launch`
  downloads the model you name with -Model (about 70 GB for IQ3_S).

.PARAMETER Model
  The model size (default iq3_s). See `strata launch --help`.

.PARAMETER Context
  32k or 64k (default 64k). The settings below were measured at 64k on a 16 GB card.

.PARAMETER Vision
  on (default), gpu or off. On reads pictures with the CPU picture reader that ships in the package.
  gpu reads them on the card with a GPU picture reader built for gfx1030 / gfx1031 from the official source (the package's
  own GPU reader has code for gfx1200 / gfx1201 only): the one file this script downloads from this repository's releases,
  checked against its SHA-256. It takes ~1.3 GB of VRAM, so the expert cache gets fewer slots (3,479 instead of 4,166 here;
  decode 44.4 vs 44.5 tok/s at 4K in one run each); it reads big pictures at up to 1,024 image tokens instead of the CPU
  reader's 300.

.PARAMETER GpuVisionZip
  With -Vision gpu: a local copy of the GPU picture reader's zip instead of the download (same SHA-256 check).

.PARAMETER Preset
  The name of the saved preset (default rx6000-tuned). Start it again later with: strata launch --preset rx6000-tuned

.PARAMETER Stock
  Save the preset with Strata's default settings instead of the tuned ones (for a before/after comparison).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-rx6000.ps1 -ModelPath D:\models\iq3_s
#>
param(
    [string]$ModelPath = "",
    [string]$Model = "iq3_s",
    [ValidateSet("32k", "64k")][string]$Context = "64k",
    [ValidateSet("on", "gpu", "off")][string]$Vision = "on",
    [string]$Preset = "rx6000-tuned",
    [switch]$Stock,
    [string]$GpuVisionZip = ""
)
$ErrorActionPreference = "Stop"

# The GPU picture reader for -Vision gpu: strata-vision-hip.exe from the official source of the 0.1.48 engine (commit 6f8800aefe27,
# tools/vision, STRATA_VISION_HIP_ARCHS=gfx1030;gfx1031), against the same ROCm as the official rdna2 package.
$GpuVisionUrl    = "https://github.com/Vop3p/dual-6900xt-flash-next-tuning/releases/download/rx6000-vision-0.1.48/strata-vision-hip-rx6000-0.1.48.zip"
$GpuVisionSha256 = "d933a55c35c2e12ab1a1cf0c738da3cfc0c79bb95b1e5811a34ab64d3aad8c77"
$GpuVisionRocm   = "10.2.0a20260930"

function Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "[X] $text" -ForegroundColor Red; exit 1 }

# --- 1. the Terminal ------------------------------------------------------------------------------------------------
Step "1/4  the Strata Terminal"
$strata = (Get-Command strata -ErrorAction SilentlyContinue).Source
if (-not $strata) {
    $cmd = Join-Path $env:LOCALAPPDATA "Strata\terminal\current\bin\strata.cmd"
    if (Test-Path $cmd) { $strata = $cmd }
}
if (-not $strata) {
    Write-Host "Installing with the official installer: irm https://github.com/Niko1221/Strata/releases/latest/download/install.ps1 | iex"
    Invoke-RestMethod https://github.com/Niko1221/Strata/releases/latest/download/install.ps1 | Invoke-Expression
    $strata = Join-Path $env:LOCALAPPDATA "Strata\terminal\current\bin\strata.cmd"
    if (-not (Test-Path $strata)) { Fail "the installer finished but $strata is not there; open a new PowerShell window and run this script again" }
}
& $strata --version

# --- 2. the card and the engine package ----------------------------------------------------------------------------
Step "2/4  the graphics card and the engine package"
$env:STRATA_ENGINE_BACKEND = "hip-rdna2"
$check = & $strata update --check --no-control --output json 2>$null | Out-String
try { $plan = $check.Substring($check.IndexOf("{")) | ConvertFrom-Json } catch { Fail "strata update --check gave no answer:`n$check" }
$gfx = @($plan.hardware.gfx)
Write-Host ("Strata sees: " + (($plan.hardware.gpu_names) -join ", ") + "  (" + ($gfx -join ", ") + ")")
if ($gfx.Count -gt 0 -and -not ($gfx | Where-Object { $_ -in @("gfx1030", "gfx1031") })) {
    Fail "no RX 6000 card (gfx1030 / gfx1031) found. This script is only for those cards."
}
$offered = $plan.engine.offered
if (-not $offered -or $offered.variant -ne "rdna2") {
    Write-Host ($plan.engine.reasons -join "`n")
    Fail "the update feed offers no rdna2 engine package for this PC (see the reasons above)"
}
Write-Host "Engine package: $($offered.version) $($offered.variant) (code for $(@($offered.archs) -join ', '))"
& $strata update --no-control
if ($LASTEXITCODE -ne 0) { Fail "strata update could not install the engine package" }
# Only the updater reads "hip-<package>" here; `strata launch` accepts the plain backend names and starts the package just installed.
Remove-Item Env:STRATA_ENGINE_BACKEND -ErrorAction SilentlyContinue

# --- 3. the settings -----------------------------------------------------------------------------------------------
# Measured on one RX 6900 XT 16 GB, i9-10900K, 64 GB, Windows 11, Qwen3.8-Flash-Next IQ3_S, 64K context, the monitor on
# the iGPU (see README.md for every number). Each line says what it does.
$tuned = @(
    "vram-reserve-mib=1536",                 # Windows keeps 2,560 MiB free on a 16 GB card; 1,536 leaves ~1.2 GiB, enough not to page
    "kv-resident=32768",                     # half the 64K KV in VRAM, the rest in pinned RAM: more expert-cache slots, no measured cost
    "pcie-frac=0.2",                         # decode +29%: the start-up share (0.35 here) makes the GPU wait for its PCIe experts
    "prefill=8192",                          # 32K prompts +17%: auto stops at 6,144 on Windows (#1630); 8,192 ran clean here up to 262K context
    "STRATA_HIP_PROMPT_F16=1",               # the documented opt-in prompt switches (docs/AMD_HIP.md), measured together
    "STRATA_HIP_ADAPT_KERNEL_COPY=1",
    "STRATA_PREFILL_CPU_SHARE=auto",         # short prompts: first token 2.8 s -> 1.1 s
    "STRATA_HC_PERSIST=1",
    "STRATA_PIPED_CONCURRENT=1",
    "STRATA_PREFILL_STREAM_MIN=2048",
    "STRATA_IO_THREADS=128"
    # STRATA_SH_STREAM is left out on purpose: on Windows it slows decode and, with KV streaming, stopped the engine (#3895)
)
$setArgs = @()
if (-not $Stock) { foreach ($s in $tuned) { $setArgs += @("--set", $s) } }

# --- 4. set up, save and start -------------------------------------------------------------------------------------
Step "3/4  setting up the model and saving the preset '$Preset'"
$launch = @("launch", "--model", $Model, "--context", $Context, "--vision", $(if ($Vision -eq "off") { "off" } else { "cpu" }),
            "--tune", "skip", "--save-preset", $Preset, "--yes", "--no-tui") + $setArgs
if ($ModelPath) { $launch += @("--model-path", $ModelPath) }
Write-Host ("strata " + ($launch -join " "))
& $strata @launch
if ($LASTEXITCODE -ne 0) { Fail "strata launch stopped (its message is above)" }

if ($Vision -eq "gpu") {
    # The preset above reads pictures on the CPU. Stop it, put the GPU reader in a folder of its own (the engine folder stays as the
    # updater installed it), and save a copy of its run config that uses it, as a profile started with `strata runtime start`.
    Step "3b/4 the GPU picture reader"
    & $strata launch --stop --preset $Preset | Out-Host
    $runCfg = Join-Path $env:LOCALAPPDATA "Strata\launch\$Preset.json"
    if (-not (Test-Path $runCfg)) { Fail "the run config of '$Preset' is not at $runCfg" }
    $cfg = Get-Content $runCfg -Raw | ConvertFrom-Json
    if (-not $cfg.vision) { Fail "the run config of '$Preset' has no pictures section" }
    $engDir = Split-Path $cfg.vision.exe
    $build = Get-Content (Join-Path $engDir "BUILD.json") -Raw | ConvertFrom-Json
    if ($build.rocm -ne $GpuVisionRocm) {
        Fail "the engine package uses ROCm $($build.rocm); this GPU picture reader was built for $GpuVisionRocm. The preset '$Preset' (pictures on the CPU) is saved and works."
    }
    $zip = $GpuVisionZip
    if (-not $zip) {
        $zip = Join-Path $env:TEMP "strata-vision-hip-rx6000-0.1.48.zip"
        Write-Host "Downloading $GpuVisionUrl"
        Invoke-WebRequest $GpuVisionUrl -OutFile $zip -UseBasicParsing
    }
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $GpuVisionSha256) { Fail "the GPU picture reader's zip has SHA-256 $hash, expected ${GpuVisionSha256}: not used" }
    $vdir = Join-Path $env:LOCALAPPDATA "Strata\rx6000-vision\$($build.version)"
    New-Item -ItemType Directory -Force $vdir | Out-Null
    Expand-Archive -Force $zip $vdir
    # The HIP runtime and the C++ runtime beside the exe, from the official package (as there: before System32's)
    Get-ChildItem $engDir -Filter *.dll | Copy-Item -Destination $vdir -Force
    $vexe = Join-Path $vdir "strata-vision-hip.exe"
    if (-not (Test-Path $vexe)) { Fail "strata-vision-hip.exe is not in $zip" }
    $cpuExe = $cfg.vision.exe
    $cfg.vision.exe = $vexe
    $cfg.vision.gpu = $true
    $cfg.vision | Add-Member -Force cpu_exe $cpuExe          # the server falls back to the CPU reader if the GPU one does not start
    foreach ($k in "max_tokens", "threads") { $cfg.vision.PSObject.Properties.Remove($k) }  # the GPU reader's own defaults (up to 1,024 tokens)
    $gpuCfg = Join-Path $vdir "$Preset-gpu.json"
    $cfg | ConvertTo-Json -Depth 32 | Set-Content -Encoding UTF8 $gpuCfg
    $gpuProfile = "$Preset-gpu"
    $have = (& $strata profile list 2>$null | Out-String) -match "(?m)^$([regex]::Escape($gpuProfile))\s"
    if ($have) { & $strata profile use-config $gpuProfile --from-config $gpuCfg | Out-Host }
    else { & $strata profile create $gpuProfile --from-config $gpuCfg | Out-Host }
    if ($LASTEXITCODE -ne 0) { Fail "strata profile could not save '$gpuProfile'" }
    & $strata runtime start --profile $gpuProfile | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "strata runtime start --profile $gpuProfile stopped (its message is above)" }
    Step "4/4  done"
    Write-Host "The model is serving, pictures on the GPU. Next time start it with:   strata runtime start --profile $gpuProfile"
    Write-Host "Stop it with:                                                     strata runtime stop --profile $gpuProfile"
    Write-Host "Pictures on the CPU instead (more expert-cache slots):               strata launch --preset $Preset"
    Write-Host "Check that the GPU reader runs: the engine log says 'strata-vision: warmed up at ... image tokens'."
    Write-Host "Before you judge the speed: put your monitor on the CPU's graphics (iGPU) if you have one, and close games,"
    Write-Host "browsers with video and the Radeon overlay. They share the card's memory with the model (README.md)."
    exit 0
}

Step "4/4  done"
Write-Host "The model is serving. Next time start it with:   strata launch --preset $Preset"
Write-Host "Stop it with:                                  strata launch --stop --preset $Preset"
Write-Host "Before you judge the speed: put your monitor on the CPU's graphics (iGPU) if you have one, and close games,"
Write-Host "browsers with video and the Radeon overlay. They share the card's memory with the model (README.md)."

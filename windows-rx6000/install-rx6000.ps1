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
  on (default) or off. On reads pictures with the CPU picture reader.

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
    [ValidateSet("on", "off")][string]$Vision = "on",
    [string]$Preset = "rx6000-tuned",
    [switch]$Stock
)
$ErrorActionPreference = "Stop"

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
$launch = @("launch", "--model", $Model, "--context", $Context, "--vision", $(if ($Vision -eq "on") { "cpu" } else { "off" }),
            "--tune", "skip", "--save-preset", $Preset, "--yes", "--no-tui") + $setArgs
if ($ModelPath) { $launch += @("--model-path", $ModelPath) }
Write-Host ("strata " + ($launch -join " "))
& $strata @launch
if ($LASTEXITCODE -ne 0) { Fail "strata launch stopped (its message is above)" }

Step "4/4  done"
Write-Host "The model is serving. Next time start it with:   strata launch --preset $Preset"
Write-Host "Stop it with:                                  strata launch --stop --preset $Preset"
Write-Host "Before you judge the speed: put your monitor on the CPU's graphics (iGPU) if you have one, and close games,"
Write-Host "browsers with video and the Radeon overlay. They share the card's memory with the model (README.md)."

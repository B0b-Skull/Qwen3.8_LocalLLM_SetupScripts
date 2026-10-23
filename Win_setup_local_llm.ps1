#Requires -Version 5.1
<#
.SYNOPSIS
    Win_setup_local_llm.ps1 — Turnkey Single-Click Windows Local LLM & Agent CLI Installer

.DESCRIPTION
    Windows PowerShell equivalent of setup_local_llm.sh.
    Copy this single script onto any Windows workstation or laptop in your lab and run:
        powershell -ExecutionPolicy Bypass -File .\Win_setup_local_llm.ps1

    What it does automatically:
      1. Validates Windows prerequisites (PowerShell 5.1+, Python 3, curl.exe, tar.exe, disk space)
      2. Detects local hardware (CPU cores/threads, System RAM, NVIDIA GPU VRAM & CUDA version)
         and selects the appropriate Qwen3.8-27B and Qwen3.5-9B quantization for the local system
      3. Creates the folder structure:
           - bin\, models\, open-webui-data\
           - ObsidianVault\ (.obsidian, targets, commands, projects, knowledge)
           - Network_Isolation\ & Complimentary Scripts\
      4. Registers ObsidianVault automatically with your installed Windows Obsidian desktop app
         (%APPDATA%\obsidian\obsidian.json) for long-term memory storage and project tracking
      5. Generates all scripts, playbooks, and documentation:
           - manage-llm.ps1 & manage-llm.cmd (Service manager, hardware auto-tuner, model switcher)
           - agent-cli.py                    (Windows Local System Agent CLI + Obsidian Vault + Hardware/Serial tools)
           - docker-compose.yml              (Open WebUI Docker Desktop container config)
           - ReadMe.md, LocalLLM_RunCMDs.md & SetupReadMe.md
           - ObsidianVault\00_MEMORY_INDEX.md, curl_playbook.md, windows_serial_playbook.md,
             windows_hardware_playbook.md, tio_serial_playbook.md
           - Network_Isolation\ (LLM_NetworkIsolationSetup.ps1, LLM_IsolationOptions.md, NetworkIsolationReadMe.md)
           - Complimentary Scripts\ (serial_console.ps1, serial_watch.ps1)
      6. Downloads & extracts llama.cpp b11802 Windows binaries (CUDA 12.4 / 13.4 x64 + CUDA runtime
         if NVIDIA GPU is present, or CPU x64 build on CPU-only laptops) with fallback & verification
      7. Downloads Qwen3.8-27B-Uncensored (auto-selected quantization, default Q3_K_M 13.3 GB) and
         Qwen3.5-9B-Uncensored-Q4_K_M.gguf (5.24 GB) with resume + byte-size verification
#>

$ErrorActionPreference = "Stop"

$LLAMA_BUILD_TAG = "b11802"
$LLAMA_WIN_CUDA12_URL   = "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD_TAG/llama-$LLAMA_BUILD_TAG-bin-win-cuda-12.4-x64.zip"
$LLAMA_WIN_CUDART12_URL = "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD_TAG/cudart-llama-bin-win-cuda-12.4-x64.zip"
$LLAMA_WIN_CUDA13_URL   = "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD_TAG/llama-$LLAMA_BUILD_TAG-bin-win-cuda-13.4-x64.zip"
$LLAMA_WIN_CUDART13_URL = "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD_TAG/cudart-llama-bin-win-cuda-13.4-x64.zip"
$LLAMA_WIN_VULKAN_URL   = "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD_TAG/llama-$LLAMA_BUILD_TAG-bin-win-vulkan-x64.zip"
$LLAMA_WIN_CPU_URL      = "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD_TAG/llama-$LLAMA_BUILD_TAG-bin-win-cpu-x64.zip"

$QWEN38_REPO_BASE = "https://huggingface.co/0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF/resolve/main"
$QWEN35_REPO_BASE = "https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/resolve/main"

# Quantization catalog for Qwen3.8-27B (remote filename, local alias filename, minimum valid bytes, approx GB)
$QWEN38_QUANT_CATALOG = @{
    "IQ2_XS" = @{ Remote = "RVN-IQ2_XS-multilingual.gguf"; Local = "Qwen3.8-27B-Uncensored-IQ2_XS.gguf"; MinBytes = 8900000000L;  Desc = "8.47 GiB (Ultra-compact for 8-12 GB RAM)" }
    "Q2_K"   = @{ Remote = "RVN-Q2_K-multilingual.gguf";   Local = "Qwen3.8-27B-Uncensored-Q2_K.gguf";   MinBytes = 10500000000L; Desc = "9.98 GiB (Compact for 12-16 GB RAM)" }
    "Q3_K_S" = @{ Remote = "RVN-Q3_K_S-multilingual.gguf"; Local = "Qwen3.8-27B-Uncensored-Q3_K_S.gguf"; MinBytes = 11800000000L; Desc = "11.24 GiB (Light 3-bit for 16 GB RAM)" }
    "Q3_K_M" = @{ Remote = "RVN-Q3_K_M-multilingual.gguf"; Local = "Qwen3.8-27B-Uncensored-Q3_K_M.gguf"; MinBytes = 13000000000L; Desc = "12.39 GiB / 13.3 GB (Balanced Default for 16-32 GB RAM + 6-12 GB VRAM)" }
    "Q4_K_M" = @{ Remote = "RVN-Q4_K_M-multilingual.gguf"; Local = "Qwen3.8-27B-Uncensored-Q4_K_M.gguf"; MinBytes = 16200000000L; Desc = "15.41 GiB (High precision for 32-64 GB RAM + >=12 GB VRAM)" }
    "Q5_K_M" = @{ Remote = "RVN-Q5_K_M-multilingual.gguf"; Local = "Qwen3.8-27B-Uncensored-Q5_K_M.gguf"; MinBytes = 18900000000L; Desc = "17.91 GiB (Near-lossless for >=16-24 GB VRAM)" }
    "Q6_K"   = @{ Remote = "RVN-Q6_K-multilingual.gguf";   Local = "Qwen3.8-27B-Uncensored-Q6_K.gguf";   MinBytes = 21800000000L; Desc = "20.57 GiB (Workstation >=24 GB VRAM)" }
    "Q8_0"   = @{ Remote = "RVN-Q8_0-multilingual.gguf";   Local = "Qwen3.8-27B-Uncensored-Q8_0.gguf";   MinBytes = 28000000000L; Desc = "26.63 GiB (Max 8-bit for >=32 GB VRAM / 64+ GB RAM)" }
}

$QWEN35_URL       = "$QWEN35_REPO_BASE/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
$QWEN35_FILE      = "Qwen3.5-9B-Uncensored-Q4_K_M.gguf"
$QWEN35_MIN_BYTES = 5500000000L

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir  = Split-Path -Parent $ScriptPath
$FolderName = Split-Path -Leaf $ScriptDir

if ($env:INSTALL_DIR) {
    $BASE_DIR = [System.IO.Path]::GetFullPath($env:INSTALL_DIR)
} elseif ($FolderName -eq "LocalLLM" -or $FolderName -eq "Windows") {
    $BASE_DIR = $ScriptDir
} else {
    $BASE_DIR = Join-Path $ScriptDir "LocalLLM"
}

$DOWNLOAD_MODE    = "auto"   # auto | all | 3.8 | 3.5 | none
$QUANT_SELECT     = "auto"   # auto | IQ2_XS | Q2_K | Q3_K_S | Q3_K_M | Q4_K_M | Q5_K_M | Q6_K | Q8_0
$CUSTOM_VAULT_DIR = ""

function Show-Usage {
    Write-Host @"
Usage: powershell -ExecutionPolicy Bypass -File .\Win_setup_local_llm.ps1 [options]

Options:
  --all-models, -AllModels       Download both Qwen3.8-27B and Qwen3.5-9B (5.24 GB)
  --only-3.8,   -Only38          Download only Qwen3.8-27B-Uncensored
  --only-3.5,   -Only35          Download only Qwen3.5-9B-Uncensored-Q4_K_M.gguf
  --skip-models,-SkipModels      Create scripts/folders and install binaries without downloading models
  --quant,      -Quant <QUANT>   Select Qwen3.8 quantization: auto (default), IQ2_XS, Q2_K, Q3_K_S,
                                 Q3_K_M, Q4_K_M, Q5_K_M, Q6_K, or Q8_0
  --dir,        -Dir <PATH>      Target installation directory (default: current LocalLLM/Windows dir)
  --vault-dir,  -VaultDir <PATH> Custom Obsidian Vault path (default: <TargetDir>\ObsidianVault)
  -h, --help,   -Help            Show this help message
"@
}

$i = 0
while ($i -lt $args.Count) {
    $arg = [string]$args[$i]
    switch -Regex ($arg) {
        '^(--all-models|-AllModels)$'   { $DOWNLOAD_MODE = "all"; $i++; continue }
        '^(--only-3\.8|-Only38)$'       { $DOWNLOAD_MODE = "3.8"; $i++; continue }
        '^(--only-3\.5|-Only35)$'       { $DOWNLOAD_MODE = "3.5"; $i++; continue }
        '^(--skip-models|-SkipModels)$' { $DOWNLOAD_MODE = "none"; $i++; continue }
        '^(--quant|-Quant)$' {
            if (($i + 1) -ge $args.Count) { throw "Option $arg requires a quantization argument (e.g. auto, Q3_K_M, Q4_K_M)." }
            $QUANT_SELECT = [string]$args[$i + 1]
            $i += 2
            continue
        }
        '^--quant=(.+)$' {
            $QUANT_SELECT = $Matches[1]
            $i++; continue
        }
        '^(--dir|-Dir)$' {
            if (($i + 1) -ge $args.Count) { throw "Option $arg requires a target directory path." }
            $BASE_DIR = [System.IO.Path]::GetFullPath([string]$args[$i + 1])
            $i += 2
            continue
        }
        '^--dir=(.+)$' {
            $BASE_DIR = [System.IO.Path]::GetFullPath($Matches[1])
            $i++; continue
        }
        '^(--vault-dir|-VaultDir)$' {
            if (($i + 1) -ge $args.Count) { throw "Option $arg requires a directory path." }
            $CUSTOM_VAULT_DIR = [System.IO.Path]::GetFullPath([string]$args[$i + 1])
            $i += 2
            continue
        }
        '^(-h|--help|-Help|help)$' {
            Show-Usage
            exit 0
        }
        default {
            Write-Error "Unknown option: $arg"
            Show-Usage
            exit 2
        }
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Test-Prerequisites {
    $missing = @()
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pyCmd) { $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $pyCmd) {
        $missing += "python (Python 3.9+)"
    }
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        $missing += "curl.exe (Windows built-in curl)"
    }
    if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
        $missing += "tar.exe (Windows built-in tar)"
    }
    if ($missing.Count -gt 0) {
        Write-Host "[ERROR] Missing required Windows system utilities: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "Install Python 3 with: winget install -e --id Python.Python.3.11" -ForegroundColor Yellow
        exit 1
    }
}

function Get-HostHardwareSummary {
    $cpuObj = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $cpuName = if ($cpuObj -and $cpuObj.Name) { $cpuObj.Name.Trim() } else { "Unknown CPU" }
    $physCores = if ($cpuObj -and $cpuObj.NumberOfCores) { [int]$cpuObj.NumberOfCores } else { [Environment]::ProcessorCount / 2 }
    $logCores  = if ($cpuObj -and $cpuObj.NumberOfLogicalProcessors) { [int]$cpuObj.NumberOfLogicalProcessors } else { [Environment]::ProcessorCount }

    $osObj = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $totalRamMiB = if ($osObj -and $osObj.TotalVisibleMemorySize) { [int]([math]::Round($osObj.TotalVisibleMemorySize / 1024)) } else { 16384 }
    $availRamMiB = if ($osObj -and $osObj.FreePhysicalMemory) { [int]([math]::Round($osObj.FreePhysicalMemory / 1024)) } else { 8192 }

    $gpuDetected = $false
    $gpuName     = "None (CPU-only mode)"
    $gpuTotalMiB = 0
    $gpuFreeMiB  = 0
    $cudaVersion = 0.0

    $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvSmi) {
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $gpuLine = (& nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
            if ($gpuLine) {
                $parts = $gpuLine -split ','
                if ($parts.Count -ge 3) {
                    $gpuDetected = $true
                    $gpuName     = $parts[0].Trim()
                    $gpuTotalMiB = [int]$parts[1].Trim()
                    $gpuFreeMiB  = [int]$parts[2].Trim()
                }
            }
            $smiFull = (& nvidia-smi 2>$null | Out-String)
            if ($smiFull -match 'CUDA Version:\s*([0-9]+\.[0-9]+)') {
                $cudaVersion = [double]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
            }
        } catch {} finally {
            $ErrorActionPreference = $oldEap
        }
    }

    return [PSCustomObject]@{
        CpuName      = $cpuName
        PhysicalCores= $physCores
        LogicalCPUs  = $logCores
        TotalRamMiB  = $totalRamMiB
        AvailRamMiB  = $availRamMiB
        GpuDetected  = $gpuDetected
        GpuName      = $gpuName
        GpuTotalMiB  = $gpuTotalMiB
        GpuFreeMiB   = $gpuFreeMiB
        CudaVersion  = $cudaVersion
    }
}

function Select-OptimalQuantization {
    param(
        [PSCustomObject]$Hw,
        [string]$RequestedQuant
    )
    $req = $RequestedQuant.Trim().ToUpper()
    if ($req -ne "AUTO" -and $QWEN38_QUANT_CATALOG.ContainsKey($req)) {
        return $req
    }
    # Auto-select quantization appropriate for the local system's RAM & VRAM pool
    $totalPoolMiB = $Hw.TotalRamMiB + $Hw.GpuTotalMiB
    if ($Hw.TotalRamMiB -lt 12000) {
        return "IQ2_XS"
    } elseif ($Hw.TotalRamMiB -lt 15500) {
        return "Q2_K"
    } elseif ($Hw.GpuTotalMiB -ge 24000 -and $Hw.TotalRamMiB -ge 60000) {
        return "Q6_K"
    } elseif ($Hw.GpuTotalMiB -ge 16000 -and $Hw.TotalRamMiB -ge 48000) {
        return "Q4_K_M"
    } else {
        # Ideal balance for 16-32+ GB RAM laptops/desktops with 6-12 GB VRAM (e.g., RTX 3070 8GB + 32GB RAM)
        return "Q3_K_M"
    }
}

function Register-ObsidianVaultOnWindows {
    param([string]$VaultPath)
    $obsidianDir  = Join-Path $env:APPDATA "obsidian"
    $obsidianJson = Join-Path $obsidianDir "obsidian.json"

    try {
        if (-not (Test-Path -LiteralPath $obsidianDir)) {
            New-Item -ItemType Directory -Path $obsidianDir -Force | Out-Null
        }
        $vaultData = $null
        if (Test-Path -LiteralPath $obsidianJson) {
            $raw = Get-Content -LiteralPath $obsidianJson -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $vaultData = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
        }
        if (-not $vaultData) {
            $vaultData = [PSCustomObject]@{ vaults = [PSCustomObject]@{} }
        }
        if (-not $vaultData.PSObject.Properties["vaults"]) {
            $vaultData | Add-Member -MemberType NoteProperty -Name "vaults" -Value ([PSCustomObject]@{})
        }

        $normalizedTarget = [System.IO.Path]::GetFullPath($VaultPath).TrimEnd('\')
        $alreadyRegistered = $false
        foreach ($prop in $vaultData.vaults.PSObject.Properties) {
            $existingPath = [string]$prop.Value.path
            if ($existingPath -and ([System.IO.Path]::GetFullPath($existingPath).TrimEnd('\') -ieq $normalizedTarget)) {
                $alreadyRegistered = $true
                break
            }
        }

        if (-not $alreadyRegistered) {
            $md5 = [System.Security.Cryptography.MD5]::Create()
            $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedTarget.ToLowerInvariant()))
            $vaultId = ([System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()).Substring(0, 16)
            $ts = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            $entry = [PSCustomObject]@{
                path = $normalizedTarget
                ts   = $ts
            }
            $vaultData.vaults | Add-Member -MemberType NoteProperty -Name $vaultId -Value $entry -Force
            $jsonOut = $vaultData | ConvertTo-Json -Depth 10 -Compress
            Write-Utf8NoBom -Path $obsidianJson -Content $jsonOut
            Write-Host "  -> Registered ObsidianVault in Windows Obsidian ($obsidianJson) [ID: $vaultId]" -ForegroundColor Green
        } else {
            Write-Host "  -> ObsidianVault is already registered in Windows Obsidian ($obsidianJson)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [!] Note: Could not auto-update obsidian.json ($($_.Exception.Message)). You can open $VaultPath directly in Obsidian." -ForegroundColor Yellow
    }
}

Test-Prerequisites
$HW_INFO = Get-HostHardwareSummary
$SELECTED_QUANT = Select-OptimalQuantization -Hw $HW_INFO -RequestedQuant $QUANT_SELECT
$QUANT_META     = $QWEN38_QUANT_CATALOG[$SELECTED_QUANT]
$QWEN38_URL       = "$QWEN38_REPO_BASE/$($QUANT_META.Remote)"
$QWEN38_FILE      = "Qwen3.8-27B-Uncensored-Q3_K_M.gguf"
$QWEN38_ALT_FILE  = $QUANT_META.Local
$QWEN38_MIN_BYTES = [int64]$QUANT_META.MinBytes

$VAULT_DIR = if ($CUSTOM_VAULT_DIR) { $CUSTOM_VAULT_DIR } else { Join-Path $BASE_DIR "ObsidianVault" }

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Windows Local LLM + System Agent CLI Turnkey Installer" -ForegroundColor Cyan
Write-Host " Target Directory: $BASE_DIR"
Write-Host " Obsidian Vault:   $VAULT_DIR"
Write-Host " Detected CPU:     $($HW_INFO.CpuName) ($($HW_INFO.PhysicalCores)C / $($HW_INFO.LogicalCPUs)T)"
Write-Host " Detected RAM:     $($HW_INFO.TotalRamMiB) MiB total ($($HW_INFO.AvailRamMiB) MiB free)"
Write-Host " Detected GPU:     $($HW_INFO.GpuName) ($($HW_INFO.GpuTotalMiB) MiB VRAM, CUDA $($HW_INFO.CudaVersion))"
Write-Host " Selected Quant:   Qwen3.8-27B [$SELECTED_QUANT] -> $($QUANT_META.Desc)"
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Create folder structure
$FoldersToCreate = @(
    (Join-Path $BASE_DIR "bin"),
    (Join-Path $BASE_DIR "models"),
    (Join-Path $BASE_DIR "open-webui-data"),
    (Join-Path $VAULT_DIR ".obsidian"),
    (Join-Path $VAULT_DIR "targets"),
    (Join-Path $VAULT_DIR "commands"),
    (Join-Path $VAULT_DIR "projects"),
    (Join-Path $VAULT_DIR "knowledge"),
    (Join-Path $BASE_DIR "Network_Isolation"),
    (Join-Path $BASE_DIR "Complimentary Scripts")
)
foreach ($f in $FoldersToCreate) {
    if (-not (Test-Path -LiteralPath $f)) {
        New-Item -ItemType Directory -Path $f -Force | Out-Null
    }
}

# Seed existing notes from parent ..\ObsidianVault if installing into LocalLLM\Windows
$ParentVault = Join-Path (Split-Path -Parent $BASE_DIR) "ObsidianVault"
if ((Test-Path -LiteralPath $ParentVault) -and ($ParentVault -ne $VAULT_DIR)) {
    foreach ($sub in @("targets", "commands", "projects", "knowledge")) {
        $srcSub = Join-Path $ParentVault $sub
        $dstSub = Join-Path $VAULT_DIR $sub
        if (Test-Path -LiteralPath $srcSub) {
            Get-ChildItem -LiteralPath $srcSub -Filter "*.md" -ErrorAction SilentlyContinue | ForEach-Object {
                $destFile = Join-Path $dstSub $_.Name
                if (-not (Test-Path -LiteralPath $destFile)) {
                    Copy-Item -LiteralPath $_.FullName -Destination $destFile -Force
                }
            }
        }
    }
}

$AppJsonPath = Join-Path $VAULT_DIR ".obsidian\app.json"
if (-not (Test-Path -LiteralPath $AppJsonPath)) {
    Write-Utf8NoBom -Path $AppJsonPath -Content @'
{
  "alwaysUpdateLinks": true,
  "newFileLocation": "folder",
  "newFileFolderPath": "knowledge",
  "showUnsupportedFiles": false,
  "strictLineBreaks": false,
  "readableLineLength": true
}
'@
}

Write-Utf8NoBom -Path (Join-Path $VAULT_DIR "commands\curl_playbook.md") -Content @'
---
title: curl_playbook
category: commands
tags: [curl, http, api, scanning, windows]
updated: 2026-10-22
---
# Valid `curl.exe` Command Playbook (Windows & Cross-Platform)

Backlink: [[00_MEMORY_INDEX]]

## Best-Practice `curl.exe` Flags for Local Agent Execution on Windows
- On Windows PowerShell, always invoke `curl.exe` (or run inside `agent-cli.py` which automatically removes the PowerShell `Invoke-WebRequest` alias).
- Always include `-sS` (silent progress bar, but show errors), `-k` (allow self-signed lab certs), and `-L` (follow redirects).
- Use `--max-time 15` so unresponsive hosts never hang the agent.
- For headers only:
  ```powershell
  curl.exe -sS -k -L -I --max-time 15 "https://target/path"
  ```
- For JSON APIs (`GET`):
  ```powershell
  curl.exe -sS -k -L --max-time 15 -H "Accept: application/json" "https://target/api/v1/status"
  ```
- For JSON APIs (`POST`):
  ```powershell
  curl.exe -sS -k -L --max-time 15 -X POST -H "Content-Type: application/json" -d "{\"key\":\"value\"}" "https://target/api/v1/login"
  ```
- For Form Submissions (`application/x-www-form-urlencoded`):
  ```powershell
  curl.exe -sS -k -L --max-time 15 -X POST -d "username=admin&password=foo" "https://target/login"
  ```
'@

Write-Utf8NoBom -Path (Join-Path $VAULT_DIR "commands\windows_serial_playbook.md") -Content @'
---
title: windows_serial_playbook
category: commands
summary: Non-interactive Windows COM port serial console patterns using the built-in serial_console tool and Complimentary Scripts\serial_console.ps1
tags: [serial, com, console, hardware, login, windows]
updated: 2026-10-22
---
# Windows Serial Console Playbook (`COM1` / `COM3` / USB-Serial)

> **Summary:** Non-interactive Windows `COMx` serial communication using the Agent's built-in `serial_console` tool or `Complimentary Scripts\serial_console.ps1`
> **Backlink:** [[00_MEMORY_INDEX]]

## Critical Rules for LLM Agent Execution on Windows
1. **Prefer the built-in `serial_console` Agent Tool** for listing COM ports, probing consoles, logging in, and executing commands over USB-to-Serial adapters (`COM3`, `COM4`, etc.).
2. **Never run interactive serial terminals** (like plain `putty` or `plink` without non-interactive flags) inside `run_shell_command`, as they block waiting for interactive user input.
3. **Alternative CLI Script:** You can also execute `Complimentary Scripts\serial_console.ps1` via `run_shell_command`.

---

## 1. Discover Connected Windows COM Ports & USB Serial Hardware
Use the `serial_console` tool with `action="list"`, or run in PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File ".\Complimentary Scripts\serial_console.ps1" -Action list
```

---

## 2. Probe / Wake a Serial Console (See Current Prompt)
Use `serial_console` with `action="probe", port="COM3", baud=115200`, or via CLI:
```powershell
powershell -ExecutionPolicy Bypass -File ".\Complimentary Scripts\serial_console.ps1" -Action probe -Port COM3 -Baud 115200
```

---

## 3. Smart Auto-Login + Command Execution (`COMx`)
Use `serial_console` with `action="exec", port="COM3", baud=115200, username="admin", password="...", command="show version"`, or via CLI:
```powershell
powershell -ExecutionPolicy Bypass -File ".\Complimentary Scripts\serial_console.ps1" -Action exec -Port COM3 -Baud 115200 -Username "USERNAME" -Password "PASSWORD" -Command "show version"
```
'@

Write-Utf8NoBom -Path (Join-Path $VAULT_DIR "commands\windows_hardware_playbook.md") -Content @'
---
title: windows_hardware_playbook
category: commands
summary: PowerShell commands for inspecting and interacting with local Windows hardware, USB devices, COM ports, GPUs, and network interfaces
tags: [hardware, windows, usb, network, gpu, com, powershell]
updated: 2026-10-22
---
# Windows Local Hardware & Network Inspection Playbook

> **Summary:** Non-interactive PowerShell commands for local hardware interaction on Windows
> **Backlink:** [[00_MEMORY_INDEX]]

## 1. Network Interfaces, IP Addresses & ARP Table
```powershell
Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed | Format-Table -AutoSize
Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, IPAddress, PrefixLength | Format-Table -AutoSize
Get-NetNeighbor -AddressFamily IPv4 | Where-Object State -ne Unreachable | Format-Table InterfaceAlias, IPAddress, LinkLayerAddress, State -AutoSize
```

## 2. Connected USB Devices & Serial / COM Ports
```powershell
Get-PnpDevice -PresentOnly | Where-Object { $_.Class -in @('Ports','USB','Modem','Net') } | Select-Object Class, FriendlyName, InstanceId, Status | Format-Table -AutoSize
[System.IO.Ports.SerialPort]::GetPortNames()
```

## 3. GPU, CPU & Memory Telemetry
```powershell
nvidia-smi --query-gpu=name,driver_version,memory.used,memory.free,memory.total,utilization.gpu,temperature.gpu --format=csv
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
```
'@

Write-Utf8NoBom -Path (Join-Path $VAULT_DIR "commands\tio_serial_playbook.md") -Content @'
---
title: tio_serial_playbook
category: commands
summary: Non-interactive tio 3.9 Lua --script patterns for Linux/WSL /dev/ttyUSB0 (on native Windows use windows_serial_playbook instead)
tags: [tio, serial, ttyusb0, console, login]
updated: 2026-10-22
---
# `tio` Serial Console Playbook (Linux / WSL `/dev/ttyUSB0`)

> **Note for Windows:** On native Windows, serial ports are exposed as `COM1`, `COM3`, etc. Read [[commands/windows_serial_playbook]] and use the built-in `serial_console` tool! Use `tio` below only when running inside Linux or WSL with `usbipd` passthrough.
> **Backlink:** [[00_MEMORY_INDEX]]

## 1. Probe / Wake the Serial Console
```bash
tio -b 115200 --mute --script-run once --script '
write("\r")
read(4096, 1500)
exit(0)
' /dev/ttyUSB0
```
'@

$IndexFilePath = Join-Path $VAULT_DIR "00_MEMORY_INDEX.md"
if (-not (Test-Path -LiteralPath $IndexFilePath)) {
    Write-Utf8NoBom -Path $IndexFilePath -Content @"
# LLM Knowledge & Memory Index (``00_MEMORY_INDEX``)

> **Tier-1 Hot Memory:** Automatically loaded into Qwen 3.8 / 3.5 on every session. Keep entries concise; store detailed findings in topic notes under ``targets/``, ``commands/``, ``projects/``, or ``knowledge/`` and link them below with ``[[WikiLinks]]``.

## Core Facts & Environment
- LocalLLM Base Path: ``$BASE_DIR``
- Obsidian Vault Path: ``$VAULT_DIR``
- Host OS: Windows (PowerShell + native ``curl.exe`` + ``.NET SerialPort`` hardware access)
- Always use ``scan_target`` before crafting ``curl.exe`` requests against an unfamiliar URL or host.
- **Serial Console (``COMx``):** Use the built-in ``serial_console`` tool or ``Complimentary Scripts\serial_console.ps1`` (read ``[[commands/windows_serial_playbook]]`` first).
- When a working ``curl.exe`` command, serial sequence, endpoint, or solution is verified, save it to the vault with ``vault_save_note``.

## Verified Commands & Playbooks
- [[commands/curl_playbook]] — Standard ``curl.exe`` flags and patterns for reliable API/web probing without context bloat
- [[commands/windows_serial_playbook]] — Non-interactive Windows ``COMx`` serial console tool and PowerShell patterns
- [[commands/windows_hardware_playbook]] — PowerShell commands for inspecting USB devices, COM ports, NICs, ARP neighbors, and GPUs
- [[commands/tio_serial_playbook]] — Linux/WSL ``tio 3.9`` Lua ``--script`` patterns for ``/dev/ttyUSB0``

## Indexed Vault Notes
<!-- AUTO-INDEX-START -->
- [[commands/curl_playbook]] — Standard ``curl.exe`` flags (``-sS -k -L -i``) and patterns for clean HTTP/API requests (#curl #http #api #windows)
- [[commands/windows_serial_playbook]] — Non-interactive Windows ``COMx`` serial console probing, auto-login, and command execution (#serial #com #console #hardware #windows)
- [[commands/windows_hardware_playbook]] — PowerShell commands for local Windows hardware, USB devices, COM ports, GPUs, and network interfaces (#hardware #windows #usb #network #gpu)
- [[commands/tio_serial_playbook]] — Non-interactive ``tio 3.9`` Lua ``--script`` patterns for Linux/WSL ``/dev/ttyUSB0`` (#tio #serial #ttyusb0)
<!-- AUTO-INDEX-END -->
"@
}

# Register ObsidianVault in Windows Obsidian desktop app (%APPDATA%\obsidian\obsidian.json)
Register-ObsidianVaultOnWindows -VaultPath $VAULT_DIR

# Copy this installer into $BASE_DIR\Win_setup_local_llm.ps1 if run from outside
$TargetInstallerPath = Join-Path $BASE_DIR "Win_setup_local_llm.ps1"
if ([System.IO.Path]::GetFullPath($ScriptPath) -ine [System.IO.Path]::GetFullPath($TargetInstallerPath)) {
    Copy-Item -LiteralPath $ScriptPath -Destination $TargetInstallerPath -Force
}

# 2. Generate docker-compose.yml (Windows Docker Desktop compatible)
Write-Host "[1/6] Generating docker-compose.yml (Windows Docker Desktop compatible) ..." -ForegroundColor Cyan
Write-Utf8NoBom -Path (Join-Path $BASE_DIR "docker-compose.yml") -Content @'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: local-open-webui
    ports:
      - "127.0.0.1:3000:3000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - HOST=0.0.0.0
      - PORT=3000
      - ENABLE_OLLAMA_API=false
      - OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1
      - OPENAI_API_KEY=sk-local-llama-cpp
      - WEBUI_AUTH=false
      - DEFAULT_MODELS=${ACTIVE_MODEL_ALIAS:-Qwen3.8-27B-Uncensored-Q3_K_M}
      - TASK_MODEL=${ACTIVE_MODEL_ALIAS:-Qwen3.8-27B-Uncensored-Q3_K_M}
      - ENABLE_AUTOCOMPLETE_GENERATION=false
      - ENABLE_TAGS_GENERATION=false
      - ENABLE_SEARCH_QUERY_GENERATION=false
      - ENABLE_FOLLOW_UP_GENERATION=false
    volumes:
      - ./open-webui-data:/app/backend/data
    restart: unless-stopped
'@

# 3. Generate agent-cli.py
Write-Host "[2/6] Generating agent-cli.py (Windows Local System Agent CLI + Obsidian Vault + Hardware/Serial Tools) ..." -ForegroundColor Cyan
Write-Utf8NoBom -Path (Join-Path $BASE_DIR "agent-cli.py") -Content @'
#!/usr/bin/env python3
"""
Interactive Local System Agent CLI for Qwen3.8-27B & Qwen3.5-9B (via local llama-server)
with integrated two-tier Obsidian Knowledge Vault and Windows Local Hardware / Serial Tools.

Tools provided to the LLM:
  - project_tracker   : Create/update active project notes in ObsidianVault/projects/<project_name>.md
  - scan_target       : Scan a URL/API/host and auto-save the report to ObsidianVault/targets/
  - vault_save_note   : Save/update distilled knowledge, working curl/serial commands, or project notes
                        in ObsidianVault/ and auto-index them in 00_MEMORY_INDEX.md
  - vault_search      : Search across all Markdown notes in ObsidianVault/
  - vault_read_note   : Read a specific note from ObsidianVault/ on demand
  - serial_console    : List Windows COM/Serial ports, probe serial consoles, auto-login, and execute
                        commands on local hardware over COM ports (using .NET System.IO.Ports.SerialPort)
  - run_shell_command : Execute PowerShell / curl.exe / hardware commands on the local Windows system
  - write_file        : Create or overwrite documents/scripts/files
  - edit_file         : Replace text inside an existing file
  - read_file         : Read local files
  - list_directory    : List files and folders in a directory
"""
import ctypes
from datetime import datetime
import html
import json
import os
import platform
import re
import shutil
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

IS_WINDOWS = os.name == "nt"

# Enable UTF-8 console output and Windows ANSI Virtual Terminal escape sequences
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

if IS_WINDOWS:
    try:
        os.system("")  # Activates VT100 ANSI color codes in Windows conhost / PowerShell
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
        mode = ctypes.c_ulong()
        if kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            kernel32.SetConsoleMode(handle, mode.value | 0x0004)
    except Exception:
        pass

HAS_READLINE = False
try:
    import readline  # type: ignore
    HAS_READLINE = True
except ImportError:
    pass


def ansi_prompt(text: str) -> str:
    """Strip readline-only \001/\002 markers on Windows where readline is absent."""
    if HAS_READLINE:
        return text
    return text.replace("\001", "").replace("\002", "")


BASE_DIR = Path(__file__).resolve().parent
VAULT_DIR = Path(os.environ.get("OBSIDIAN_VAULT_DIR", str(BASE_DIR / "ObsidianVault"))).resolve()
INDEX_FILE = VAULT_DIR / "00_MEMORY_INDEX.md"

API_URL = os.environ.get("LLAMA_API_URL", "http://127.0.0.1:8080/v1/chat/completions")
MODEL_NAME = os.environ.get("MODEL_ALIAS", "Qwen3.8-27B-Uncensored-Q3_K_M")
SKIP_PERMISSIONS = os.environ.get("SKIP_PERMISSIONS", "0") == "1"
MAX_TOOL_OUTPUT_CHARS = int(os.environ.get("MAX_TOOL_OUTPUT_CHARS", "3500"))
MAX_HISTORY_CHARS = int(os.environ.get("MAX_HISTORY_CHARS", "24000"))
VALID_CATEGORIES = ("targets", "commands", "projects", "knowledge")
ACTIVE_PROJECT: str = ""
DOC_EXTENSIONS = {
    ".md", ".txt", ".rst", ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg",
    ".conf", ".csv", ".tsv", ".xml", ".html", ".htm", ".sh", ".ps1", ".cmd",
    ".bat", ".py", ".log", ".pdf",
}
_CACHED_HW_SUMMARY: str = ""


def ensure_vault_structure() -> None:
    for sub in (".obsidian", *VALID_CATEGORIES):
        (VAULT_DIR / sub).mkdir(parents=True, exist_ok=True)
    app_json = VAULT_DIR / ".obsidian" / "app.json"
    if not app_json.exists():
        app_json.write_text(
            json.dumps(
                {
                    "alwaysUpdateLinks": True,
                    "newFileLocation": "folder",
                    "newFileFolderPath": "knowledge",
                    "showUnsupportedFiles": False,
                    "strictLineBreaks": False,
                    "readableLineLength": True,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    if not INDEX_FILE.exists():
        INDEX_FILE.write_text(
            "# LLM Knowledge & Memory Index (`00_MEMORY_INDEX`)\n\n"
            "> **Tier-1 Hot Memory:** Automatically loaded into Qwen 3.8 / 3.5 on every session.\n\n"
            "## Core Facts & Environment\n"
            f"- LocalLLM Base Path: `{BASE_DIR}`\n"
            f"- Obsidian Vault Path: `{VAULT_DIR}`\n"
            "- Always use `scan_target` before crafting `curl.exe` requests against an unfamiliar URL or host.\n"
            "- For Windows COM/Serial consoles (`COM1`, `COM3`, etc.), use the `serial_console` tool and read `[[commands/windows_serial_playbook]]`.\n"
            "- Save verified working `curl.exe` commands, serial sequences, endpoints, and solutions using `vault_save_note`.\n\n"
            "## Indexed Vault Notes\n"
            "<!-- AUTO-INDEX-START -->\n"
            "<!-- AUTO-INDEX-END -->\n",
            encoding="utf-8",
        )


def slugify(name: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9_\-]+", "_", name.strip()).strip("_").lower()
    return s[:64] or "note"


def update_vault_index(wiki_link: str, summary: str, tags: list) -> None:
    ensure_vault_structure()
    text = INDEX_FILE.read_text(encoding="utf-8", errors="replace")
    tag_str = " ".join(f"#{t.lstrip('#')}" for t in tags if t.strip())
    entry_line = f"- [[{wiki_link}]] — {summary.strip()}" + (f" ({tag_str})" if tag_str else "")

    start_marker = "<!-- AUTO-INDEX-START -->"
    end_marker = "<!-- AUTO-INDEX-END -->"
    if start_marker in text and end_marker in text:
        before, rest = text.split(start_marker, 1)
        middle, after = rest.split(end_marker, 1)
        lines = [ln for ln in middle.strip().splitlines() if ln.strip()]
        updated = False
        for idx, ln in enumerate(lines):
            if f"[[{wiki_link}]]" in ln:
                lines[idx] = entry_line
                updated = True
                break
        if not updated:
            lines.append(entry_line)
        lines = lines[-35:]
        new_text = f"{before}{start_marker}\n" + "\n".join(lines) + f"\n{end_marker}{after}"
    else:
        new_text = text.rstrip() + f"\n\n## Indexed Vault Notes\n{start_marker}\n{entry_line}\n{end_marker}\n"

    INDEX_FILE.write_text(new_text, encoding="utf-8")


def save_note_to_vault(category: str, title: str, summary: str, content: str, tags: list = None) -> str:
    ensure_vault_structure()
    cat = category.strip().lower() if category else "knowledge"
    if cat not in VALID_CATEGORIES:
        cat = "knowledge"
    slug = slugify(title)
    tags = tags or [cat]
    clean_tags = [re.sub(r"[^a-zA-Z0-9_\-]", "", t.lstrip("#")).lower() for t in tags if t]
    clean_tags = [t for t in clean_tags if t] or [cat]

    note_path = VAULT_DIR / cat / f"{slug}.md"
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    frontmatter = (
        "---\n"
        f"title: {title}\n"
        f"category: {cat}\n"
        f"summary: {summary}\n"
        f"tags: [{', '.join(clean_tags)}]\n"
        f"updated: {now_str}\n"
        "---\n"
    )
    body = (
        f"# {title}\n\n"
        f"> **Summary:** {summary}  \n"
        f"> **Backlink:** [[00_MEMORY_INDEX]] | **Updated:** `{now_str}`\n\n"
        f"{content.strip()}\n"
    )
    note_path.write_text(frontmatter + body, encoding="utf-8")
    wiki_link = f"{cat}/{slug}"
    update_vault_index(wiki_link, summary, clean_tags)
    return f"Saved Obsidian note `[[{wiki_link}]]` ({note_path}) and updated `00_MEMORY_INDEX.md`."


def search_vault(query: str) -> str:
    ensure_vault_structure()
    q = query.strip().lower()
    tokens = [t for t in re.split(r"\s+", q) if t]
    results = []
    for md in sorted(VAULT_DIR.rglob("*.md")):
        if ".obsidian" in md.parts:
            continue
        rel = md.relative_to(VAULT_DIR).with_suffix("").as_posix()
        text = md.read_text(encoding="utf-8", errors="replace")
        haystack = f"{rel}\n{text}".lower()
        score = sum(1 for tok in tokens if tok in haystack)
        if not tokens or score > 0:
            matching_lines = []
            for ln in text.splitlines():
                if any(tok in ln.lower() for tok in tokens):
                    matching_lines.append(ln.strip())
                if len(matching_lines) >= 4:
                    break
            snippet = " | ".join(matching_lines) if matching_lines else text[:200].replace("\n", " ")
            results.append((score, rel, snippet[:300]))

    results.sort(key=lambda x: (-x[0], x[1]))
    if not results:
        return f"No notes in ObsidianVault matched '{query}'."
    out = [f"ObsidianVault search results for '{query}' (use `vault_read_note` to read full note):"]
    for score, rel, snip in results[:12]:
        out.append(f"  - [[{rel}]]: {snip}")
    return "\n".join(out)


def read_vault_note(note_ref: str) -> str:
    ensure_vault_structure()
    cleaned = note_ref.strip().strip("[]").replace("\\", "/")
    if not cleaned.endswith(".md"):
        cleaned_md = cleaned + ".md"
    else:
        cleaned_md = cleaned

    candidates = [
        VAULT_DIR / cleaned_md,
        VAULT_DIR / cleaned,
        *[VAULT_DIR / c / Path(cleaned_md).name for c in VALID_CATEGORIES],
    ]
    for cand in candidates:
        if cand.is_file():
            return compact_text(cand.read_text(encoding="utf-8", errors="replace"), MAX_TOOL_OUTPUT_CHARS)

    slug = slugify(Path(cleaned).stem)
    for md in VAULT_DIR.rglob("*.md"):
        if md.stem.lower() == slug:
            return compact_text(md.read_text(encoding="utf-8", errors="replace"), MAX_TOOL_OUTPUT_CHARS)

    return f"Note '{note_ref}' not found in {VAULT_DIR}. Try `vault_search` first."


def get_vault_context_for_prompt() -> str:
    ensure_vault_structure()
    index_text = INDEX_FILE.read_text(encoding="utf-8", errors="replace").strip()
    return compact_text(index_text, 1800)


def open_vault_in_obsidian() -> str:
    """Launch the installed Windows Obsidian desktop application directly to VAULT_DIR."""
    ensure_vault_structure()
    if IS_WINDOWS:
        encoded = urllib.parse.quote(str(VAULT_DIR), safe="")
        uri = f"obsidian://open?path={encoded}"
        try:
            os.startfile(uri)  # type: ignore[attr-defined]
            return f"Opened Obsidian Vault in Windows Obsidian desktop app: {VAULT_DIR}"
        except Exception:
            for candidate in [
                Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "obsidian" / "Obsidian.exe",
                Path(os.environ.get("ProgramFiles", "")) / "Obsidian" / "Obsidian.exe",
            ]:
                if candidate.is_file():
                    subprocess.Popen([str(candidate), uri], close_fds=True)
                    return f"Launched {candidate} with Vault: {VAULT_DIR}"
    return f"Obsidian Vault is ready at: {VAULT_DIR} (Open this folder as a Vault in Obsidian)."


def read_single_doc_file(path: Path, max_chars: int = 6000) -> str:
    if path.suffix.lower() == ".pdf":
        pdftotext_bin = shutil.which("pdftotext")
        if pdftotext_bin:
            try:
                out = subprocess.check_output(
                    [pdftotext_bin, str(path), "-"],
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    stderr=subprocess.DEVNULL,
                    timeout=15,
                )
                return compact_text(out.strip(), max_chars)
            except Exception as exc:
                return f"(Could not extract PDF text from {path.name}: {exc})"
        return f"(PDF file detected at {path}: install poppler/pdftotext or provide Markdown/text docs)"
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
        return compact_text(raw.strip(), max_chars)
    except Exception as exc:
        return f"(Could not read {path.name}: {exc})"


def load_documentation_source(doc_source: str, max_total_chars: int = 8000) -> tuple:
    src = doc_source.strip()
    if re.match(r"^https?://", src, re.I):
        derived = slugify(re.sub(r"^https?://", "", src))
        report = perform_target_scan(src)
        return derived, f"Documentation URL: {src}\n\n{compact_text(report, max_total_chars)}"

    p = Path(os.path.expanduser(src)).resolve()
    if not p.exists():
        raise FileNotFoundError(f"Documentation path not found: {p}")

    if p.is_file():
        derived = slugify(p.stem)
        content = read_single_doc_file(p, max_total_chars)
        return derived, f"### Documentation File: `{p}`\n\n{content}"

    derived = slugify(p.name)
    doc_files = []
    for candidate in sorted(p.rglob("*")):
        if candidate.is_file() and not any(part.startswith(".") for part in candidate.relative_to(p).parts):
            if candidate.suffix.lower() in DOC_EXTENSIONS or candidate.stat().st_size < 100_000:
                doc_files.append(candidate)
        if len(doc_files) >= 25:
            break

    if not doc_files:
        return derived, f"### Documentation Directory: `{p}`\n(No readable documentation files found)"

    per_file_budget = max(800, max_total_chars // max(1, min(len(doc_files), 8)))
    sections = [f"### Documentation Directory: `{p}` ({len(doc_files)} files discovered)"]
    used = 0
    for df in doc_files[:12]:
        rel = df.relative_to(p)
        snippet = read_single_doc_file(df, per_file_budget)
        block = f"\n#### File: `{rel}` ({df.stat().st_size} bytes)\n{snippet}\n"
        if used + len(block) > max_total_chars and len(sections) > 1:
            sections.append(f"\n*(Additional files in `{p}` omitted from initial digest; use `read_file` to inspect on demand)*")
            break
        sections.append(block)
        used += len(block)

    return derived, "\n".join(sections)


def list_vault_projects() -> str:
    ensure_vault_structure()
    proj_dir = VAULT_DIR / "projects"
    notes = sorted(proj_dir.glob("*.md"))
    if not notes:
        return "No projects exist yet in `ObsidianVault/projects/`. Start one with `/project <doc_path> [project_name]`."
    lines = [f"=== Obsidian Projects ({proj_dir}) ==="]
    for n in notes:
        active_marker = " [ACTIVE]" if n.stem == ACTIVE_PROJECT else ""
        text = n.read_text(encoding="utf-8", errors="replace")
        summary_match = re.search(r"^summary:\s*(.+)$", text, re.M)
        summary = summary_match.group(1).strip() if summary_match else "Project tracker note"
        lines.append(f"  - [[projects/{n.stem}]]{active_marker} — {summary}")
    return "\n".join(lines)


def get_windows_memory_status() -> str:
    if IS_WINDOWS:
        try:
            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]
            stat = MEMORYSTATUSEX()
            stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):
                total_gib = stat.ullTotalPhys / (1024 ** 3)
                avail_gib = stat.ullAvailPhys / (1024 ** 3)
                return f"{total_gib:.1f} GiB total, {avail_gib:.1f} GiB available"
        except Exception:
            pass
    try:
        out = subprocess.check_output(["free", "-h"], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if line.startswith("Mem:"):
                parts = line.split()
                return f"{parts[1]} total, {parts[6]} available"
    except Exception:
        pass
    return "Unknown RAM"


def get_live_hardware_summary(force_refresh: bool = False) -> str:
    global _CACHED_HW_SUMMARY
    cpu = os.environ.get("PROCESSOR_IDENTIFIER", "") or platform.processor() or "Unknown CPU"
    serial_ports_str = "None detected"

    if IS_WINDOWS and (not _CACHED_HW_SUMMARY or force_refresh):
        try:
            ps_hw = (
                "$c = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1; "
                "$ports = [System.IO.Ports.SerialPort]::GetPortNames() -join ', '; "
                "Write-Output \"CPU=$($c.Name.Trim()) ($($c.NumberOfCores) cores, $($c.NumberOfLogicalProcessors) threads)\"; "
                "Write-Output \"PORTS=$ports\""
            )
            out = subprocess.check_output(
                ["powershell", "-NoProfile", "-NonInteractive", "-Command", ps_hw],
                text=True,
                encoding="utf-8",
                errors="replace",
                stderr=subprocess.DEVNULL,
                timeout=8,
            )
            for ln in out.splitlines():
                if ln.startswith("CPU=") and len(ln) > 4:
                    cpu = ln[4:].strip()
                elif ln.startswith("PORTS="):
                    val = ln[6:].strip()
                    serial_ports_str = val if val else "None currently connected"
            _CACHED_HW_SUMMARY = f"{cpu}|||{serial_ports_str}"
        except Exception:
            pass
    elif _CACHED_HW_SUMMARY and "|||" in _CACHED_HW_SUMMARY:
        cpu, serial_ports_str = _CACHED_HW_SUMMARY.split("|||", 1)

    ram = get_windows_memory_status()

    gpu = "None"
    nv_bin = shutil.which("nvidia-smi")
    if nv_bin:
        try:
            out = subprocess.check_output(
                [nv_bin, "--query-gpu=name,memory.used,memory.total,temperature.gpu", "--format=csv,noheader"],
                text=True,
                encoding="utf-8",
                errors="replace",
                stderr=subprocess.DEVNULL,
                timeout=5,
            ).strip()
            if out:
                gpu = out.splitlines()[0]
        except Exception:
            pass

    user_name = os.environ.get("USERNAME") or os.environ.get("USER") or "user"
    return (
        f"- Hostname: {platform.node()}\n"
        f"- User: {user_name}\n"
        f"- OS: {platform.system()} {platform.release()} ({platform.version()}, {platform.machine()})\n"
        f"- CPU: {cpu}\n"
        f"- System RAM: {ram}\n"
        f"- GPU: {gpu}\n"
        f"- Serial / COM Ports: {serial_ports_str}\n"
        f"- Active Local LLM: {MODEL_NAME} (running locally on 127.0.0.1:8080 via llama.cpp)\n"
        f"- Obsidian Knowledge Vault: {VAULT_DIR}\n"
        f"- Current Working Directory: {os.getcwd()}"
    )


def build_system_prompt() -> str:
    hw = get_live_hardware_summary()
    vault_index = get_vault_context_for_prompt()
    active_proj_block = ""
    if ACTIVE_PROJECT:
        proj_note = read_vault_note(f"projects/{ACTIVE_PROJECT}")
        active_proj_block = (
            f"\nACTIVE OBSIDIAN PROJECT (`[[projects/{ACTIVE_PROJECT}]]`):\n"
            f"{compact_text(proj_note, 1600)}\n"
        )
    return (
        "You are a local AI system, hardware, networking & coding agent running directly on the user's Windows "
        "workstation (NOT on a cloud server). You have full, direct access to the user's local hardware, COM/serial "
        "ports, USB devices, network interfaces, operating system, filesystem, PowerShell console, and a persistent "
        "Obsidian Knowledge Vault (`ObsidianVault/`).\n\n"
        "YOUR BUILT-IN TOOLS:\n"
        "  1. `project_tracker`: Create, rename, or update an active project in `ObsidianVault/projects/<project_name>.md` "
        "(tracks documentation findings, verification questions, verified data, project plan milestones, and execution log).\n"
        "  2. `scan_target`: Inspect any URL/API/host (headers, status, endpoints, forms, JSON structure) AND "
        "auto-save the report into `ObsidianVault/targets/`. ALWAYS use `scan_target` or `vault_read_note` before "
        "crafting `curl.exe` commands.\n"
        "  3. `vault_save_note`: Save distilled findings, verified working `curl.exe` commands, serial sequences, endpoints, "
        "or project notes into `ObsidianVault/<category>/<title>.md` so you remember them across sessions without context bloat.\n"
        "  4. `vault_search`: Search your Obsidian Knowledge Vault for prior notes, targets, or commands.\n"
        "  5. `vault_read_note`: Read a specific note (e.g. `commands/curl_playbook`, `commands/windows_serial_playbook`, "
        "`commands/windows_hardware_playbook`, or `projects/...`) from the Vault.\n"
        "  6. `serial_console`: Non-interactive Windows COM/Serial port tool (`list`, `probe`, `exec`) for communicating "
        "directly with local hardware consoles over `COM1`, `COM3`, USB-Serial adapters, etc.\n"
        "  7. `run_shell_command`: Execute any Windows PowerShell or CLI command (including `curl.exe -sS -k -L ...`, "
        "`Get-NetAdapter`, `Get-PnpDevice`, `nvidia-smi`, `ipconfig`, `netsh`, etc.).\n"
        "  8. `write_file` / `edit_file` / `read_file` / `list_directory`: Full local filesystem access.\n\n"
        "PEAK PERFORMANCE & MEMORY RULES:\n"
        "- NEVER say you are a cloud AI or that you cannot access local files, network targets, COM ports, hardware, or commands.\n"
        "- Check the Obsidian Memory Index below first! If a target, playbook, or project is already in the Vault, read it "
        "with `vault_read_note` instead of guessing.\n"
        "- On Windows, use `serial_console` for COM port serial connections and `curl.exe` for HTTP requests.\n"
        "- When onboarding a project from documentation: first call `project_tracker` to create the project note under "
        "`ObsidianVault/projects/`, summarize what you learned from the docs, and ask the user targeted verification questions "
        "to confirm IPs, COM ports, credentials, interfaces, or goals. Whenever the user answers or a task completes, update "
        "the project note with `project_tracker`.\n\n"
        f"LIVE LOCAL SYSTEM SNAPSHOT:\n{hw}\n\n"
        f"OBSIDIAN VAULT MEMORY INDEX (Tier-1 Hot Memory):\n{vault_index}"
        f"{active_proj_block}"
    )


TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "project_tracker",
            "description": (
                "Create or update a project tracking note in ObsidianVault/projects/<project_name>.md, set it as the "
                "active project, and index it in 00_MEMORY_INDEX.md. Use this to record ingested documentation, "
                "verification questions, verified user answers, step-by-step project plans, and task progress."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "project_name": {
                        "type": "string",
                        "description": "Project name or slug (stored at ObsidianVault/projects/<project_name>.md).",
                    },
                    "summary": {
                        "type": "string",
                        "description": "One-line project status summary for 00_MEMORY_INDEX.md.",
                    },
                    "verified_data": {
                        "type": "string",
                        "description": "Markdown bullet list of key facts, targets, IPs, COM ports, and user-verified data.",
                    },
                    "questions": {
                        "type": "string",
                        "description": "Markdown bullet list of open verification/clarification questions for the user (or 'All verified').",
                    },
                    "plan_and_tasks": {
                        "type": "string",
                        "description": "Markdown checklist (- [ ] / - [x]) of project phases, planned tasks, and execution log.",
                    },
                },
                "required": ["project_name", "summary", "verified_data", "plan_and_tasks"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "scan_target",
            "description": (
                "Scan a URL, API endpoint, or host to discover HTTP response headers, status code, "
                "API routes/links, HTML forms/inputs, JSON keys, and clean readable content. "
                "Automatically saves the scan report to ObsidianVault/targets/."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "target": {
                        "type": "string",
                        "description": "The URL or hostname/IP to scan (e.g. 'https://example.com' or 'http://127.0.0.1:8080/health').",
                    }
                },
                "required": ["target"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "vault_save_note",
            "description": (
                "Save or update a structured Markdown note in the local Obsidian Knowledge Vault "
                "(ObsidianVault/<category>/<title>.md) and index it in 00_MEMORY_INDEX.md."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "category": {
                        "type": "string",
                        "enum": ["targets", "commands", "projects", "knowledge"],
                        "description": "Vault folder category.",
                    },
                    "title": {
                        "type": "string",
                        "description": "Short descriptive title for the note (e.g. 'local_api_curl_commands').",
                    },
                    "summary": {
                        "type": "string",
                        "description": "One-line summary for 00_MEMORY_INDEX.md.",
                    },
                    "content": {
                        "type": "string",
                        "description": "Distilled Markdown content (working commands, endpoints, findings).",
                    },
                    "tags": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Optional list of tags (e.g. ['curl', 'api']).",
                    },
                },
                "required": ["category", "title", "summary", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "vault_search",
            "description": "Search all Markdown notes in the local Obsidian Knowledge Vault by keyword or tag.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Keywords or tag to search for in ObsidianVault.",
                    }
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "vault_read_note",
            "description": "Read the full contents of a note from ObsidianVault (e.g. 'commands/windows_serial_playbook' or 'commands/curl_playbook').",
            "parameters": {
                "type": "object",
                "properties": {
                    "note": {
                        "type": "string",
                        "description": "WikiLink or relative path of the note (e.g. 'commands/windows_serial_playbook').",
                    }
                },
                "required": ["note"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "serial_console",
            "description": (
                "Interact with local hardware over Windows Serial / COM ports (e.g. COM1, COM3, USB-to-Serial adapters). "
                "Supports action='list' (discover all COM ports and PnP serial devices), action='probe' (send CR and "
                "capture current prompt), and action='exec' (optional smart login + command execution with output capture)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "enum": ["list", "probe", "exec"],
                        "description": "Operation to perform: 'list', 'probe', or 'exec'.",
                    },
                    "port": {
                        "type": "string",
                        "description": "Windows COM port name (e.g. 'COM3') when action is 'probe' or 'exec'.",
                    },
                    "baud": {
                        "type": "integer",
                        "description": "Baud rate (default: 115200).",
                    },
                    "command": {
                        "type": "string",
                        "description": "Command string to send over serial when action is 'exec' (e.g. 'show version').",
                    },
                    "username": {
                        "type": "string",
                        "description": "Optional login username if console is at a login: prompt.",
                    },
                    "password": {
                        "type": "string",
                        "description": "Optional login password if console prompts for Password:.",
                    },
                },
                "required": ["action"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_shell_command",
            "description": (
                "Execute a PowerShell or CLI command (such as curl.exe, Get-NetAdapter, Get-PnpDevice, ipconfig, "
                "nvidia-smi, etc.) on the local Windows system and return stdout/stderr."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The PowerShell / command line to execute.",
                    }
                },
                "required": ["command"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Create a new file or overwrite an existing file on the local filesystem.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File path (absolute or relative to current directory, ~ is expanded).",
                    },
                    "content": {
                        "type": "string",
                        "description": "Full text content to write to the file.",
                    },
                },
                "required": ["path", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "edit_file",
            "description": "Replace old_text with new_text inside an existing local file.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the file to edit."},
                    "old_text": {"type": "string", "description": "Exact existing text to replace."},
                    "new_text": {"type": "string", "description": "New replacement text."},
                },
                "required": ["path", "old_text", "new_text"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the contents of a local file.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the file to read."}
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_directory",
            "description": "List files and directories at the given path.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Directory path to list (defaults to current working directory).",
                    }
                },
                "required": [],
            },
        },
    },
]


def compact_text(text: str, limit: int = MAX_TOOL_OUTPUT_CHARS) -> str:
    if not text:
        return ""
    if "<html" in text.lower() or "<script" in text.lower() or "<style" in text.lower():
        text = re.sub(r"(?is)<(script|style|svg|noscript)\b.*?>.*?</\1>", " ", text)
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
    if len(text) <= limit:
        return text
    half = limit // 2
    omitted = len(text) - limit
    return f"{text[:half]}\n\n... [TRUNCATED {omitted} chars to fit context window] ...\n\n{text[-half:]}"


def perform_target_scan(target: str) -> str:
    url = target.strip()
    if not re.match(r"^https?://", url, re.I):
        url = "http://" + url

    curl_bin = shutil.which("curl.exe") if IS_WINDOWS else shutil.which("curl")
    curl_bin = curl_bin or "curl"

    hdr_cmd = [curl_bin, "-sS", "-k", "-L", "-I", "--max-time", "15", url]
    body_cmd = [curl_bin, "-sS", "-k", "-L", "--max-time", "20", url]

    headers_out = ""
    try:
        headers_out = subprocess.check_output(
            hdr_cmd, text=True, encoding="utf-8", errors="replace", stderr=subprocess.STDOUT, timeout=20
        ).strip()
    except Exception as exc:
        headers_out = f"(Header probe failed: {exc})"

    body_out = ""
    try:
        body_out = subprocess.check_output(
            body_cmd, text=True, encoding="utf-8", errors="replace", stderr=subprocess.STDOUT, timeout=25
        )
    except Exception as exc:
        # Fallback to urllib if curl failed
        try:
            ctx = ssl._create_unverified_context()
            req = urllib.request.Request(url, headers={"User-Agent": "LocalLLM-Agent/1.0"})
            with urllib.request.urlopen(req, context=ctx, timeout=15) as r:
                headers_out = f"HTTP {r.status} {r.reason}\n" + "\n".join(f"{k}: {v}" for k, v in r.headers.items())
                body_out = r.read().decode("utf-8", errors="replace")
        except Exception:
            body_out = f"(Body fetch failed: {exc})"

    summary = [f"=== Scan Report for {url} ==="]
    status_line = headers_out.splitlines()[0] if headers_out else "Unknown status"
    summary.append(f"\n[1] HTTP Response Headers:\n{headers_out[:1000]}")

    stripped = body_out.strip()
    if stripped.startswith("{") or stripped.startswith("["):
        try:
            parsed = json.loads(stripped)
            pretty = json.dumps(parsed, indent=2)
            summary.append(f"\n[2] JSON Payload Structure ({len(stripped)} bytes):\n{compact_text(pretty, 2000)}")
            report_text = "\n".join(summary)
            host_slug = slugify(re.sub(r"^https?://", "", url))
            save_note_to_vault(
                "targets",
                f"scan_{host_slug}",
                f"Target scan of {url} ({status_line}, JSON endpoint)",
                report_text,
                ["target", "scan", "json", "curl"],
            )
            return report_text
        except Exception:
            pass

    title_match = re.search(r"(?is)<title[^>]*>(.*?)</title>", body_out)
    page_title = html.unescape(title_match.group(1).strip()) if title_match else "No title"
    if title_match:
        summary.append(f"\n[2] Page Title: {page_title}")

    forms = re.findall(r"(?is)<form\b[^>]*>.*?</form>", body_out)
    if forms:
        form_summaries = []
        for idx, f in enumerate(forms[:5], 1):
            action = re.search(r'(?i)\baction=["\']?([^"\' >]+)', f)
            method = re.search(r'(?i)\bmethod=["\']?([^"\' >]+)', f)
            inputs = re.findall(r'(?i)<input\b[^>]*\bname=["\']?([^"\' >]+)', f)
            form_summaries.append(
                f"  - Form #{idx}: method={(method.group(1).upper() if method else 'GET')} "
                f"action={(action.group(1) if action else url)} inputs={inputs}"
            )
        summary.append("\n[3] Discovered HTML Forms:\n" + "\n".join(form_summaries))

    endpoints = sorted(
        set(
            re.findall(
                r'(?:href|src|action|url|fetch|axios\.\w+)\s*[\(="\']+\s*([/a-zA-Z0-9_.\-?:=&%]+)',
                body_out,
            )
        )
    )
    if endpoints:
        summary.append("\n[4] Discovered Links / Endpoints (up to 40):\n  " + ", ".join(endpoints[:40]))

    clean = re.sub(r"(?is)<(script|style|svg|noscript)\b.*?>.*?</\1>", " ", body_out)
    clean = re.sub(r"(?s)<[^>]+>", " ", clean)
    clean = html.unescape(re.sub(r"\s+", " ", clean)).strip()
    summary.append(f"\n[5] Page Content Preview ({len(body_out)} raw bytes):\n{clean[:1200]}")

    report_text = "\n".join(summary)
    host_slug = slugify(re.sub(r"^https?://", "", url))
    save_note_to_vault(
        "targets",
        f"scan_{host_slug}",
        f"Target scan of {url} ({status_line}, title: {page_title[:50]})",
        report_text,
        ["target", "scan", "curl"],
    )
    return report_text


def run_windows_serial_tool(args: dict) -> str:
    """Execute non-interactive Windows COM port operations via Complimentary Scripts/serial_console.ps1."""
    action = (args.get("action") or "list").strip().lower()
    port = (args.get("port") or "COM3").strip()
    baud = int(args.get("baud") or 115200)
    command = args.get("command") or ""
    username = args.get("username") or ""
    password = args.get("password") or ""

    script_path = BASE_DIR / "Complimentary Scripts" / "serial_console.ps1"
    if IS_WINDOWS and script_path.is_file():
        ps_args = [
            "powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-File", str(script_path),
            "-Action", action,
            "-Port", port,
            "-Baud", str(baud),
        ]
        if command:
            ps_args += ["-Command", command]
        if username:
            ps_args += ["-Username", username]
        if password:
            ps_args += ["-Password", password]
        try:
            proc = subprocess.run(
                ps_args,
                text=True,
                encoding="utf-8",
                errors="replace",
                capture_output=True,
                timeout=30,
            )
            out = (proc.stdout or "") + (proc.stderr or "")
            return compact_text(out.strip() or "(No output from serial console)", MAX_TOOL_OUTPUT_CHARS)
        except Exception as exc:
            return f"Serial console error ({action} on {port}): {exc}"

    return f"Serial helper script not found at {script_path}."


def confirm_action(action_desc: str) -> bool:
    global SKIP_PERMISSIONS
    if SKIP_PERMISSIONS:
        return True
    try:
        ans = input(ansi_prompt(f"\001\033[1;35m\002  Allow {action_desc}? [y/N/a (always)]: \001\033[0m\002")).strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        return False
    if ans in ("a", "always"):
        SKIP_PERMISSIONS = True
        print("  \033[1;33m-> Auto-run enabled for the remainder of this session.\033[0m")
        return True
    return ans in ("y", "yes")


def execute_tool(name: str, args: dict) -> str:
    global ACTIVE_PROJECT
    try:
        if name == "project_tracker":
            proj_name = args.get("project_name") or ACTIVE_PROJECT or "active_project"
            slug = slugify(proj_name)
            ACTIVE_PROJECT = slug
            summary = args.get("summary", f"Project tracker for {proj_name}")
            verified_data = args.get("verified_data", "- Pending verification")
            questions = args.get("questions", "- None")
            plan_and_tasks = args.get("plan_and_tasks", "- [ ] Initial documentation review")
            body = (
                "## 1. Verified Data & Architecture\n"
                f"{verified_data.strip()}\n\n"
                "## 2. Open Verification Questions\n"
                f"{questions.strip()}\n\n"
                "## 3. Project Plan & Task Tracking\n"
                f"{plan_and_tasks.strip()}\n"
            )
            print(
                f"\n\033[1;32m[Obsidian Project -> project_tracker]\033[0m [[projects/{slug}]] (Active Project)",
                flush=True,
            )
            return save_note_to_vault("projects", slug, summary, body, ["project", "plan", slug])

        elif name == "scan_target":
            target = args.get("target", "")
            print(f"\n\033[1;36m[Agent Tool -> scan_target]\033[0m {target} (auto-saving to ObsidianVault)", flush=True)
            return perform_target_scan(target)

        elif name == "vault_save_note":
            cat = args.get("category", "knowledge")
            title = args.get("title", "note")
            summary = args.get("summary", title)
            content = args.get("content", "")
            tags = args.get("tags") or [cat]
            print(f"\n\033[1;32m[Obsidian Vault -> save_note]\033[0m [[{cat}/{slugify(title)}]]", flush=True)
            return save_note_to_vault(cat, title, summary, content, tags)

        elif name == "vault_search":
            query = args.get("query", "")
            print(f"\n\033[1;36m[Obsidian Vault -> search]\033[0m '{query}'", flush=True)
            return search_vault(query)

        elif name == "vault_read_note":
            note_ref = args.get("note", "")
            print(f"\n\033[1;36m[Obsidian Vault -> read_note]\033[0m [[{note_ref}]]", flush=True)
            return read_vault_note(note_ref)

        elif name == "serial_console":
            action = args.get("action", "list")
            port = args.get("port", "")
            print(f"\n\033[1;33m[Agent Tool -> serial_console]\033[0m action={action} port={port}", flush=True)
            if action != "list" and not confirm_action(f"serial console `{action}` on `{port}`"):
                print("  \033[1;31m-> Denied by user.\033[0m", flush=True)
                return "Action denied by user: serial operation was not executed."
            return run_windows_serial_tool(args)

        elif name == "run_shell_command":
            cmd = args.get("command", "")
            print(f"\n\033[1;33m[Agent Tool -> run_shell_command]\033[0m PS> {cmd}", flush=True)
            if not confirm_action(f"shell command `{cmd}`"):
                print("  \033[1;31m-> Denied by user.\033[0m", flush=True)
                return "Action denied by user: shell command was not executed."
            if IS_WINDOWS:
                wrapped_cmd = (
                    "Remove-Item Alias:curl,Alias:wget -ErrorAction SilentlyContinue; "
                    "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; "
                    f"{cmd}"
                )
                proc = subprocess.run(
                    ["powershell", "-NoProfile", "-NonInteractive", "-Command", wrapped_cmd],
                    cwd=os.getcwd(),
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    capture_output=True,
                    timeout=60,
                )
            else:
                proc = subprocess.run(
                    cmd,
                    shell=True,
                    cwd=os.getcwd(),
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    capture_output=True,
                    timeout=60,
                )
            output = (proc.stdout or "") + (proc.stderr or "")
            if not output.strip():
                output = f"(Command completed with exit code {proc.returncode})"
            return compact_text(output, MAX_TOOL_OUTPUT_CHARS)

        elif name == "write_file":
            raw_path = args.get("path", "")
            content = args.get("content", "")
            p = Path(os.path.expanduser(raw_path)).resolve()
            print(f"\n\033[1;32m[Agent Tool -> write_file]\033[0m {p} ({len(content)} bytes)", flush=True)
            if not confirm_action(f"writing {len(content)} bytes to `{p}`"):
                print("  \033[1;31m-> Denied by user.\033[0m", flush=True)
                return f"Action denied by user: file {p} was not written."
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")
            return f"Successfully wrote {len(content)} bytes to {p}"

        elif name == "edit_file":
            raw_path = args.get("path", "")
            old_text = args.get("old_text", "")
            new_text = args.get("new_text", "")
            p = Path(os.path.expanduser(raw_path)).resolve()
            print(f"\n\033[1;32m[Agent Tool -> edit_file]\033[0m {p}", flush=True)
            if not confirm_action(f"editing `{p}`"):
                print("  \033[1;31m-> Denied by user.\033[0m", flush=True)
                return f"Action denied by user: file {p} was not modified."
            text = p.read_text(encoding="utf-8")
            if old_text not in text:
                return f"Error: old_text not found in {p}"
            p.write_text(text.replace(old_text, new_text, 1), encoding="utf-8")
            return f"Successfully updated {p}"

        elif name == "read_file":
            raw_path = args.get("path", "")
            p = Path(os.path.expanduser(raw_path)).resolve()
            print(f"\n\033[1;36m[Agent Tool -> read_file]\033[0m {p}", flush=True)
            content = p.read_text(encoding="utf-8", errors="replace")
            return compact_text(content, MAX_TOOL_OUTPUT_CHARS)

        elif name == "list_directory":
            raw_path = args.get("path") or "."
            p = Path(os.path.expanduser(raw_path)).resolve()
            print(f"\n\033[1;36m[Agent Tool -> list_directory]\033[0m {p}", flush=True)
            entries = sorted(os.listdir(p))
            formatted = []
            for e in entries[:200]:
                full = p / e
                suffix = "/" if full.is_dir() else f" ({full.stat().st_size} B)"
                formatted.append(f"{e}{suffix}")
            return "\n".join(formatted) if formatted else "(empty directory)"

        else:
            return f"Error: Unknown tool '{name}'"
    except Exception as exc:
        return f"Tool execution error ({name}): {exc}"


def trim_messages_to_fit(messages: list, max_chars: int = MAX_HISTORY_CHARS) -> None:
    if messages and messages[0].get("role") == "system":
        messages[0]["content"] = build_system_prompt()

    for m in messages[1:-2]:
        if m.get("role") == "tool" and isinstance(m.get("content"), str) and len(m["content"]) > 1200:
            m["content"] = compact_text(m["content"], 1200)

    while len(messages) > 3 and len(json.dumps(messages)) > max_chars:
        messages.pop(1)
        while len(messages) > 2 and messages[1].get("role") == "tool":
            messages.pop(1)


def chat_step(messages: list) -> dict:
    trim_messages_to_fit(messages)

    payload = {
        "model": MODEL_NAME,
        "messages": messages,
        "tools": TOOLS,
        "tool_choice": "auto",
        "stream": True,
        "temperature": 0.6,
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    content_parts = []
    tool_calls_by_index = {}
    printed_header = False

    try:
        resp_ctx = urllib.request.urlopen(req, timeout=300)
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", errors="replace")
        if "exceeds the available context size" in body and len(messages) > 3:
            print("\n\033[1;33m[Auto-Compacting Context Window and Retrying...]\033[0m", flush=True)
            trim_messages_to_fit(messages, max_chars=MAX_HISTORY_CHARS // 2)
            req = urllib.request.Request(
                API_URL,
                data=json.dumps({**payload, "messages": messages}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            resp_ctx = urllib.request.urlopen(req, timeout=300)
        else:
            raise urllib.error.HTTPError(err.url, err.code, body, err.headers, None)

    with resp_ctx as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line or not line.startswith("data: "):
                continue
            data_str = line[6:].strip()
            if data_str == "[DONE]":
                break
            try:
                chunk = json.loads(data_str)
            except json.JSONDecodeError:
                continue

            choices = chunk.get("choices") or []
            if not choices:
                continue
            delta = choices[0].get("delta") or {}

            c = delta.get("content")
            if c:
                if not printed_header:
                    print(f"\n\033[1;34m{MODEL_NAME}>\033[0m ", end="", flush=True)
                    printed_header = True
                print(c, end="", flush=True)
                content_parts.append(c)

            for tc in delta.get("tool_calls") or []:
                idx = tc.get("index", 0)
                entry = tool_calls_by_index.setdefault(
                    idx,
                    {
                        "id": tc.get("id") or f"call_{idx}",
                        "type": "function",
                        "function": {"name": "", "arguments": ""},
                    },
                )
                if tc.get("id"):
                    entry["id"] = tc["id"]
                fn = tc.get("function") or {}
                if fn.get("name"):
                    entry["function"]["name"] += fn["name"]
                if fn.get("arguments"):
                    entry["function"]["arguments"] += fn["arguments"]

    if printed_header:
        print("", flush=True)

    msg = {"role": "assistant", "content": "".join(content_parts) or None}
    if tool_calls_by_index:
        msg["tool_calls"] = [tool_calls_by_index[k] for k in sorted(tool_calls_by_index)]
    return msg


def run_turn(messages: list) -> None:
    try:
        for _ in range(8):
            assistant_msg = chat_step(messages)
            messages.append(assistant_msg)
            tool_calls = assistant_msg.get("tool_calls")
            if not tool_calls:
                break
            for tc in tool_calls:
                fn_name = tc["function"]["name"]
                raw_args = tc["function"]["arguments"] or "{}"
                try:
                    args = json.loads(raw_args)
                except json.JSONDecodeError:
                    args = {}
                result = execute_tool(fn_name, args)
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": tc["id"],
                        "name": fn_name,
                        "content": result,
                    }
                )
    except KeyboardInterrupt:
        while len(messages) > 1 and messages[-1].get("role") == "tool":
            messages.pop()
        if len(messages) > 1 and messages[-1].get("role") == "assistant" and messages[-1].get("tool_calls"):
            messages.pop()
        print("\n\033[1;33m[Interrupted by Ctrl+C — stopped current task. Ready for next prompt.]\033[0m")


def start_project_onboarding(doc_source: str, custom_name: str, messages: list) -> None:
    global ACTIVE_PROJECT
    derived_name, doc_digest = load_documentation_source(doc_source)
    proj_slug = slugify(custom_name) if custom_name else derived_name
    ACTIVE_PROJECT = proj_slug

    print(f"\n\033[1;36m[Project Onboarding]\033[0m Loaded documentation from: {doc_source}")
    print(f"\033[1;32m[Active Obsidian Project]\033[0m [[projects/{proj_slug}]] -> {VAULT_DIR / 'projects' / (proj_slug + '.md')}\n")

    onboarding_prompt = (
        f"I am starting/updating a project using documentation from `{doc_source}`.\n"
        f"Suggested project name: `{proj_slug}` (you may refine the project name in `project_tracker` if the "
        "documentation specifies a clearer official project/system name).\n\n"
        f"Here is the extracted documentation:\n\n{doc_digest}\n\n"
        "Please perform these exact steps right now:\n"
        "1. Call `project_tracker` to create the project note under `ObsidianVault/projects/` with:\n"
        "   - Key facts, IPs, COM ports, hardware/interfaces, credentials, and architecture extracted from the documentation.\n"
        "   - Specific verification questions to confirm any missing, ambiguous, or environment-specific details with me.\n"
        "   - An initial phased project plan with `- [ ]` checkboxes.\n"
        "2. Present a concise summary of what you learned from the documentation and ask me your verification questions "
        "so we can confirm the data and begin executing the plan."
    )
    messages.append({"role": "user", "content": onboarding_prompt})
    run_turn(messages)
    print()


def handle_project_command(arg_str: str, messages: list) -> None:
    global ACTIVE_PROJECT
    parts = arg_str.strip().split(maxsplit=1)
    if not parts or parts[0].lower() == "list":
        print("\n" + list_vault_projects() + "\n")
        return

    if parts[0].lower() in ("load", "switch", "open") and len(parts) > 1:
        slug = slugify(parts[1])
        note_path = VAULT_DIR / "projects" / f"{slug}.md"
        if not note_path.is_file():
            print(f"\n\033[1;31mProject `[[projects/{slug}]]` not found in {VAULT_DIR / 'projects'}.\033[0m\n")
            print(list_vault_projects() + "\n")
            return
        ACTIVE_PROJECT = slug
        content = read_vault_note(f"projects/{slug}")
        print(f"\n\033[1;32mSwitched active project to `[[projects/{slug}]]`:\033[0m\n{content}\n")
        messages.append(
            {
                "role": "user",
                "content": (
                    f"We have switched to existing project `[[projects/{slug}]]`. Here is the current project note:\n\n"
                    f"{content}\n\nSummarize current status, next uncompleted `- [ ]` tasks, and any open questions."
                ),
            }
        )
        run_turn(messages)
        print()
        return

    doc_source = parts[0]
    custom_name = parts[1].strip() if len(parts) > 1 else ""
    try:
        start_project_onboarding(doc_source, custom_name, messages)
    except Exception as exc:
        print(f"\n\033[1;31m[Project Error]\033[0m {exc}\n")


def main() -> None:
    global SKIP_PERMISSIONS, ACTIVE_PROJECT
    ensure_vault_structure()

    args = sys.argv[1:]
    filtered_args = []
    startup_project_doc = ""
    startup_project_name = ""
    idx = 0
    while idx < len(args):
        a = args[idx]
        if a in ("--dangerously-skip-permissions", "-DangerouslySkipPermissions"):
            SKIP_PERMISSIONS = True
            idx += 1
        elif a in ("--confirm", "-Confirm"):
            SKIP_PERMISSIONS = False
            idx += 1
        elif a in ("-P", "--project", "-Project"):
            if idx + 1 >= len(args):
                print("Error: --project requires a documentation file or directory path.", file=sys.stderr)
                sys.exit(2)
            startup_project_doc = args[idx + 1]
            idx += 2
            if idx < len(args) and not args[idx].startswith("-"):
                startup_project_name = args[idx]
                idx += 1
        elif a.startswith("--project="):
            startup_project_doc = a.split("=", 1)[1]
            idx += 1
        else:
            filtered_args.append(a)
            idx += 1

    messages = [{"role": "system", "content": build_system_prompt()}]

    if len(filtered_args) > 1 and filtered_args[0] in ("-p", "--prompt", "-Prompt"):
        prompt_text = " ".join(filtered_args[1:])
        messages.append({"role": "user", "content": prompt_text})
        run_turn(messages)
        return

    perm_status = (
        "\033[1;31mAUTO-RUN (--dangerously-skip-permissions enabled)\033[0m"
        if SKIP_PERMISSIONS
        else "\033[1;32mCONFIRM ON [y/N/a] (pass --dangerously-skip-permissions to auto-run)\033[0m"
    )

    print("\033[1;32m=== Windows Local System Agent CLI + Obsidian Vault ===\033[0m")
    print(f"  Active Model:   \033[1m{MODEL_NAME}\033[0m")
    print(f"  Obsidian Vault: \033[1;36m{VAULT_DIR}\033[0m")
    print(f"  Working Dir:    {os.getcwd()}")
    print(f"  Permissions:    {perm_status}")
    print("  Agent Tools:    \033[1;33mproject_tracker, scan_target, vault_save_note, vault_search, vault_read_note, serial_console, run_shell_command, write_file, edit_file, read_file, list_directory\033[0m")
    print("  Slash Commands: /project <doc_path> [name], /project list, /project load <name>, /obsidian, /com, /scan <url>, /vault, /remember <fact>, /search <query>, /permissions, /clear, /hw, /exit")
    print("=======================================================\n")

    if startup_project_doc:
        try:
            start_project_onboarding(startup_project_doc, startup_project_name, messages)
        except Exception as exc:
            print(f"\n\033[1;31m[Project Error]\033[0m {exc}\n")

    while True:
        try:
            user_input = input(ansi_prompt("\001\033[1;32m\002You>\001\033[0m\002 ")).strip()
        except (EOFError, KeyboardInterrupt):
            print("\nExiting...")
            break

        if not user_input:
            continue
        if user_input.lower() in ("/exit", "exit", "quit", "/quit"):
            print("Exiting...")
            break
        if user_input.lower() == "/clear":
            messages = [{"role": "system", "content": build_system_prompt()}]
            print("Conversation history cleared (Obsidian Vault memory remains active).\n")
            continue
        if user_input.lower() == "/hw":
            print("\n" + get_live_hardware_summary(force_refresh=True) + "\n")
            continue
        if user_input.lower() == "/com":
            print("\n" + run_windows_serial_tool({"action": "list"}) + "\n")
            continue
        if user_input.lower() == "/obsidian":
            print("\n\033[1;32m" + open_vault_in_obsidian() + "\033[0m\n")
            continue
        if user_input.lower() == "/vault":
            print(f"\n\033[1;36m=== Obsidian Vault ({VAULT_DIR}) ===\033[0m")
            print(INDEX_FILE.read_text(encoding="utf-8", errors="replace"))
            continue
        if user_input.lower().startswith("/remember "):
            fact = user_input[10:].strip()
            if fact:
                slug = slugify(fact[:40])
                msg = save_note_to_vault("knowledge", slug, fact[:90], fact, ["remembered", "fact"])
                print(f"\n\033[1;32m{msg}\033[0m\n")
            continue
        if user_input.lower().startswith("/search "):
            q = user_input[8:].strip()
            if q:
                print("\n" + search_vault(q) + "\n")
            continue
        if user_input.lower() == "/permissions":
            SKIP_PERMISSIONS = not SKIP_PERMISSIONS
            state = "AUTO-RUN (no confirmation)" if SKIP_PERMISSIONS else "CONFIRM ON ([y/N/a] before commands/writes)"
            print(f"Permissions mode set to: {state}\n")
            continue
        if user_input.lower() == "/project" or user_input.lower().startswith("/project "):
            arg_str = user_input[8:].strip()
            handle_project_command(arg_str, messages)
            continue
        if user_input.lower().startswith("/scan "):
            target = user_input[6:].strip()
            if target:
                report = perform_target_scan(target)
                print(f"\n\033[1;36m{report}\033[0m\n")
                messages.append(
                    {
                        "role": "user",
                        "content": (
                            f"I scanned `{target}` (auto-saved to ObsidianVault). Here is the scan report:\n\n{report}\n\n"
                            "Use this scan report to help me craft valid curl.exe commands or interact with this target."
                        ),
                    }
                )
                try:
                    run_turn(messages)
                    print()
                except Exception as exc:
                    print(f"\n\033[1;31m[Error]\033[0m {exc}\n")
            continue

        messages.append({"role": "user", "content": user_input})
        try:
            run_turn(messages)
            print()
        except urllib.error.HTTPError as err:
            print(f"\n\033[1;31m[Server Error {err.code}]\033[0m {err.reason}\n")
            messages.pop()
        except Exception as exc:
            print(f"\n\033[1;31m[Error]\033[0m {exc}\n")
            messages.pop()


if __name__ == "__main__":
    main()
'@

$pyBin = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $pyBin) { $pyBin = Get-Command python3 -ErrorAction SilentlyContinue }
& $pyBin.Source -m py_compile (Join-Path $BASE_DIR "agent-cli.py")
if ($LASTEXITCODE -ne 0) {
    throw "agent-cli.py failed Python syntax compilation."
}

# 4. Generate manage-llm.ps1 & manage-llm.cmd
Write-Host "[3/6] Generating manage-llm.ps1 & manage-llm.cmd (Windows Hardware Auto-Tuner & Service Manager) ..." -ForegroundColor Cyan
Write-Utf8NoBom -Path (Join-Path $BASE_DIR "manage-llm.ps1") -Content @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Manage the Windows local LLM server (llama.cpp CUDA/CPU) + Open WebUI + Local System Agent CLI + Obsidian Vault.
    Supports switching between:
      - qwen3.8 (DEFAULT): Qwen3.8-27B-Uncensored-Q3_K_M.gguf (13.3 GB / auto-selected quantization)
      - qwen3.5 (FAST):    Qwen3.5-9B-Uncensored-Q4_K_M.gguf (5.24 GB, HauhauCS-Aggressive)
    Dynamically auto-detects Windows CPU cores/threads, system RAM, and NVIDIA GPU VRAM
    to configure llama-server.exe and Agent CLI for peak efficiency.
#>

$ErrorActionPreference = "Stop"

$BASE_DIR          = Split-Path -Parent $MyInvocation.MyCommand.Path
$BIN_DIR           = Join-Path $BASE_DIR "bin"
$MODELS_DIR        = Join-Path $BASE_DIR "models"
$VAULT_DIR         = if ($env:OBSIDIAN_VAULT_DIR) { $env:OBSIDIAN_VAULT_DIR } else { Join-Path $BASE_DIR "ObsidianVault" }
$PID_FILE          = Join-Path $BASE_DIR "llama-server.pid"
$ACTIVE_MODEL_FILE = Join-Path $BASE_DIR "llama-server.model"
$LOG_FILE          = Join-Path $BASE_DIR "llama-server.log"
$ERR_LOG_FILE      = Join-Path $BASE_DIR "llama-server.err.log"

$HOST_ADDR  = if ($env:HOST) { $env:HOST } else { "127.0.0.1" }
$LLAMA_PORT = if ($env:LLAMA_PORT) { $env:LLAMA_PORT } else { "8080" }
$WEBUI_PORT = if ($env:WEBUI_PORT) { $env:WEBUI_PORT } else { "3000" }

$MODEL_SELECT     = if ($env:MODEL) { $env:MODEL } else { "qwen3.8" }
$AGENT_MODE       = if ($env:AGENT_MODE) { $env:AGENT_MODE } else { "on" }
$SPEC_TYPE        = if ($env:SPEC_TYPE) { $env:SPEC_TYPE } else { "ngram-mod" }
$REASONING_MODE   = if ($env:REASONING) { $env:REASONING } else { "off" }
$SKIP_PERMISSIONS = if ($env:SKIP_PERMISSIONS) { $env:SKIP_PERMISSIONS } else { "0" }

function Show-Usage {
    Write-Host @"
Usage: .\manage-llm.ps1 {start|stop|restart|status|models|tune|cli|logs|obsidian} [-m MODEL] [options...]

Commands:
  start     Start llama-server.exe (with Agent tools + auto-detected tuning) and Open WebUI (Docker)
  stop      Stop llama-server.exe and Open WebUI container
  restart   Restart both services (optionally switching models with -m)
  status    Show service status, active model, auto-detected hardware profile, and GPU VRAM usage
  models    List installed models and show which model is active / default
  tune      Display the auto-detected hardware profile and exact flags without starting
  cli       Launch the interactive Windows Local System Agent CLI with hardware, serial, shell & file tools
  logs      Tail llama-server.log output
  obsidian  Open ObsidianVault directly in the Windows Obsidian desktop application

Model Selection Switch (-m / --model or `$env:MODEL):
  -m qwen3.8 | 3.8 | 27b        Use Qwen3.8-27B-Uncensored-Q3_K_M.gguf [DEFAULT]
  -m qwen3.5 | 3.5 | 9b | fast  Use Qwen3.5-9B-Uncensored-Q4_K_M.gguf (HauhauCS-Aggressive)
  -m C:\path\to\model.gguf      Use a custom GGUF model file

Reasoning / Thinking Switch:
  --no-think                    Disable internal <think> monologue for instant answers [DEFAULT]
  --think                       Enable step-by-step <think> chain-of-thought reasoning

Permissions / Confirmation & Project Switches (Agent CLI):
  --confirm                              Prompt [y/N/a] before running shell commands or file writes [DEFAULT]
  --dangerously-skip-permissions         Auto-run all shell commands and file writes without confirming
  -P, --project <doc_path_or_dir> [name] Ingest documentation file/folder, verify data with user, and create/track
                                         an Obsidian project in ObsidianVault\projects\

Examples:
  .\manage-llm.ps1 start                                         # Starts default Qwen3.8-27B + Open WebUI
  .\manage-llm.ps1 start -m 3.5                                  # Starts faster Qwen3.5-9B model
  .\manage-llm.ps1 cli -m 3.5                                    # Agent CLI (confirm ON by default)
  .\manage-llm.ps1 cli -m 3.5 --dangerously-skip-permissions     # Agent CLI (auto-run all commands)
  .\manage-llm.ps1 cli -m 3.8 --dangerously-skip-permissions     # Default Qwen3.8 Agent CLI (auto-run)
  .\manage-llm.ps1 obsidian                                      # Open Vault in Windows Obsidian app
  .\manage-llm.ps1 models                                        # List installed models
"@
}

$ACTION     = "status"
$ACTION_SET = $false
$EXTRA_ARGS = @()

$idx = 0
while ($idx -lt $args.Count) {
    $a = [string]$args[$idx]
    switch -Regex ($a) {
        '^(start|stop|restart|status|models|tune|detect|cli|logs|obsidian|-h|--help|help)$' {
            if (-not $ACTION_SET) {
                $ACTION = $a.ToLower()
                $ACTION_SET = $true
            } else {
                $EXTRA_ARGS += $a
            }
            $idx++; continue
        }
        '^(-m|--model|-Model)$' {
            if (($idx + 1) -ge $args.Count) {
                Write-Error "Option $a requires a model argument (e.g. qwen3.8 or qwen3.5)"
                exit 2
            }
            $MODEL_SELECT = [string]$args[$idx + 1]
            $idx += 2; continue
        }
        '^--model=(.+)$' {
            $MODEL_SELECT = $Matches[1]
            $idx++; continue
        }
        '^(--think|-Think)$' {
            $REASONING_MODE = "on"
            $idx++; continue
        }
        '^(--no-think|-NoThink)$' {
            $REASONING_MODE = "off"
            $idx++; continue
        }
        '^(--dangerously-skip-permissions|-DangerouslySkipPermissions)$' {
            $SKIP_PERMISSIONS = "1"
            $idx++; continue
        }
        '^(--confirm|-Confirm)$' {
            $SKIP_PERMISSIONS = "0"
            $idx++; continue
        }
        default {
            $EXTRA_ARGS += $a
            $idx++; continue
        }
    }
}

function Resolve-ModelSelection {
    param([string]$Sel = $MODEL_SELECT)
    $selLower = $Sel.Trim().ToLower()
    $q38Default = Join-Path $MODELS_DIR "Qwen3.8-27B-Uncensored-Q3_K_M.gguf"
    $q35Default = Join-Path $MODELS_DIR "Qwen3.5-9B-Uncensored-Q4_K_M.gguf"
    $q35Alt     = Join-Path $MODELS_DIR "Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"

    # Also check any other Qwen3.8 quant files in models\
    $anyQ38 = Get-ChildItem -LiteralPath $MODELS_DIR -Filter "Qwen3.8-27B*.gguf" -ErrorAction SilentlyContinue | Select-Object -First 1

    switch -Regex ($selLower) {
        '^(qwen3\.8|3\.8|27b|qwen38|default|)$' {
            if (Test-Path -LiteralPath $q38Default) {
                $script:MODEL_KEY   = "qwen3.8"
                $script:MODEL_ALIAS = "Qwen3.8-27B-Uncensored-Q3_K_M"
                $script:MODEL_PATH  = $q38Default
            } elseif ($anyQ38) {
                $script:MODEL_KEY   = "qwen3.8"
                $script:MODEL_ALIAS = [System.IO.Path]::GetFileNameWithoutExtension($anyQ38.Name)
                $script:MODEL_PATH  = $anyQ38.FullName
            } elseif (Test-Path -LiteralPath $q35Default) {
                $script:MODEL_KEY   = "qwen3.5"
                $script:MODEL_ALIAS = "Qwen3.5-9B-Uncensored-Q4_K_M"
                $script:MODEL_PATH  = $q35Default
            } else {
                $script:MODEL_KEY   = "qwen3.8"
                $script:MODEL_ALIAS = "Qwen3.8-27B-Uncensored-Q3_K_M"
                $script:MODEL_PATH  = $q38Default
            }
        }
        '^(qwen3\.5|3\.5|9b|qwen35|fast|hauhaucs)$' {
            $script:MODEL_KEY   = "qwen3.5"
            $script:MODEL_ALIAS = "Qwen3.5-9B-Uncensored-Q4_K_M"
            if (Test-Path -LiteralPath $q35Default) {
                $script:MODEL_PATH = $q35Default
            } else {
                $script:MODEL_PATH = $q35Alt
            }
        }
        default {
            $cand1 = $Sel
            $cand2 = Join-Path $MODELS_DIR $Sel
            if (Test-Path -LiteralPath $cand1) {
                $script:MODEL_PATH = (Resolve-Path -LiteralPath $cand1).Path
            } elseif (Test-Path -LiteralPath $cand2) {
                $script:MODEL_PATH = (Resolve-Path -LiteralPath $cand2).Path
            } else {
                Write-Error "Unknown model selector '$Sel'. Use -m qwen3.8 (default) or -m qwen3.5."
                exit 2
            }
            $script:MODEL_ALIAS = [System.IO.Path]::GetFileNameWithoutExtension($script:MODEL_PATH)
            $script:MODEL_KEY   = $script:MODEL_ALIAS
        }
    }
}

function Get-HardwareAndTune {
    Resolve-ModelSelection $MODEL_SELECT

    $cpuObj = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:CPU_NAME       = if ($cpuObj -and $cpuObj.Name) { $cpuObj.Name.Trim() } else { "Unknown CPU" }
    $script:PHYSICAL_CORES = if ($cpuObj -and $cpuObj.NumberOfCores) { [int]$cpuObj.NumberOfCores } else { [Math]::Max(1, [int]([Environment]::ProcessorCount / 2)) }
    $script:LOGICAL_CPUS   = if ($cpuObj -and $cpuObj.NumberOfLogicalProcessors) { [int]$cpuObj.NumberOfLogicalProcessors } else { [Environment]::ProcessorCount }

    $autoThreads = [Math]::Max(1, [int][Math]::Floor(($script:PHYSICAL_CORES * 4 + 4) / 5))
    $autoThreadsBatch = $script:PHYSICAL_CORES

    $script:THREADS       = if ($env:THREADS) { [int]$env:THREADS } else { $autoThreads }
    $script:THREADS_BATCH = if ($env:THREADS_BATCH) { [int]$env:THREADS_BATCH } else { $autoThreadsBatch }

    $osObj = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $script:TOTAL_RAM_MIB = if ($osObj -and $osObj.TotalVisibleMemorySize) { [int]([Math]::Round($osObj.TotalVisibleMemorySize / 1024)) } else { 16384 }
    $script:AVAIL_RAM_MIB = if ($osObj -and $osObj.FreePhysicalMemory) { [int]([Math]::Round($osObj.FreePhysicalMemory / 1024)) } else { 8192 }

    if (Test-Path -LiteralPath $script:MODEL_PATH) {
        $script:MODEL_SIZE_MIB = [int]([Math]::Round((Get-Item -LiteralPath $script:MODEL_PATH).Length / 1MB))
    } else {
        $script:MODEL_SIZE_MIB = 5366
    }

    $script:GPU_DETECTED  = $false
    $script:GPU_NAME      = "None (CPU-only mode)"
    $script:GPU_TOTAL_MIB = 0
    $script:GPU_FREE_MIB  = 0

    $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvSmi) {
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $gpuLine = (& nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
            if ($gpuLine) {
                $parts = $gpuLine -split ','
                if ($parts.Count -ge 3) {
                    $script:GPU_DETECTED  = $true
                    $script:GPU_NAME      = $parts[0].Trim()
                    $script:GPU_TOTAL_MIB = [int]$parts[1].Trim()
                    $script:GPU_FREE_MIB  = [int]$parts[2].Trim()
                }
            }
        } catch {} finally {
            $ErrorActionPreference = $oldEap
        }
    }

    $script:KV_CACHE_TYPE = if ($env:KV_CACHE_TYPE) { $env:KV_CACHE_TYPE } else { "q8_0" }
    $script:GPU_ARGS      = @()

    if ($script:GPU_DETECTED -and $script:GPU_TOTAL_MIB -gt 0) {
        if ($script:MODEL_SIZE_MIB -le $script:GPU_TOTAL_MIB) {
            $autoFitTarget = 256
        } elseif ($script:GPU_TOTAL_MIB -le 8192) {
            $autoFitTarget = 384
        } elseif ($script:GPU_TOTAL_MIB -le 16384) {
            $autoFitTarget = 512
        } else {
            $autoFitTarget = 768
        }
        $script:FIT_TARGET  = if ($env:FIT_TARGET) { $env:FIT_TARGET } else { "$autoFitTarget" }
        $script:BATCH_SIZE  = if ($env:BATCH_SIZE) { $env:BATCH_SIZE } else { "2048" }
        $script:UBATCH_SIZE = if ($env:UBATCH_SIZE) { $env:UBATCH_SIZE } else { "512" }
        $script:GPU_ARGS    = @(
            "--fit", "on",
            "--fit-target", "$($script:FIT_TARGET)",
            "--flash-attn", "on",
            "--cache-type-k", "$($script:KV_CACHE_TYPE)",
            "--cache-type-v", "$($script:KV_CACHE_TYPE)"
        )
    } else {
        $script:FIT_TARGET  = "N/A"
        $script:BATCH_SIZE  = if ($env:BATCH_SIZE) { $env:BATCH_SIZE } else { "1024" }
        $script:UBATCH_SIZE = if ($env:UBATCH_SIZE) { $env:UBATCH_SIZE } else { "256" }
        $script:GPU_ARGS    = @(
            "--n-gpu-layers", "0",
            "--flash-attn", "on",
            "--cache-type-k", "$($script:KV_CACHE_TYPE)",
            "--cache-type-v", "$($script:KV_CACHE_TYPE)"
        )
    }

    $totalPoolMiB = $script:TOTAL_RAM_MIB + $script:GPU_TOTAL_MIB
    $headroomMiB  = $totalPoolMiB - $script:MODEL_SIZE_MIB
    if ($script:GPU_DETECTED -and ($script:MODEL_SIZE_MIB -le $script:GPU_TOTAL_MIB)) {
        $autoCtxSize = 8192
    } elseif ($headroomMiB -ge 18000) {
        $autoCtxSize = 16384
    } elseif ($headroomMiB -ge 10000) {
        $autoCtxSize = 8192
    } else {
        $autoCtxSize = 4096
    }
    $script:CTX_SIZE = if ($env:CTX_SIZE) { $env:CTX_SIZE } else { "$autoCtxSize" }

    $script:FEATURE_ARGS = @()
    if ($SPEC_TYPE -and $SPEC_TYPE -ne "none") {
        $script:FEATURE_ARGS += @("--spec-type", $SPEC_TYPE)
    }
    if ($REASONING_MODE -and $REASONING_MODE -ne "auto") {
        $script:FEATURE_ARGS += @("--reasoning", $REASONING_MODE)
    }

    $script:SERVER_AGENT_ARGS = @()
    if ($AGENT_MODE -in @("on", "true", "1")) {
        $script:SERVER_AGENT_ARGS += @("--agent", "--tools", "all")
    }
}

function Show-HardwareProfile {
    Get-HardwareAndTune
    Write-Host "=== Auto-Detected Windows Hardware & Tuning Profile ===" -ForegroundColor Cyan
    Write-Host ("  CPU:            {0} ({1} physical cores, {2} logical processors)" -f $script:CPU_NAME, $script:PHYSICAL_CORES, $script:LOGICAL_CPUS)
    Write-Host ("  System RAM:     {0} MiB total ({1} MiB available)" -f $script:TOTAL_RAM_MIB, $script:AVAIL_RAM_MIB)
    if ($script:GPU_DETECTED) {
        Write-Host ("  GPU:            {0} ({1} MiB total, {2} MiB free)" -f $script:GPU_NAME, $script:GPU_TOTAL_MIB, $script:GPU_FREE_MIB)
    } else {
        Write-Host ("  GPU:            {0}" -f $script:GPU_NAME)
    }
    Write-Host ("  Selected Model: {0} ({1} MiB -> {2})" -f $script:MODEL_ALIAS, $script:MODEL_SIZE_MIB, (Split-Path -Leaf $script:MODEL_PATH))
    Write-Host ("  Obsidian Vault: {0}" -f $VAULT_DIR)
    Write-Host ("  Reasoning Mode: {0} (default: off for instant answers; pass --think to enable <think>)" -f $REASONING_MODE)
    Write-Host ("  Agent Tools:    {0} (project_tracker, scan_target, vault_*, serial_console, run_shell_command, ...)" -f $AGENT_MODE)
    $tunedLine = "  Tuned Settings: --ctx-size $($script:CTX_SIZE) --reasoning $REASONING_MODE --threads $($script:THREADS) --threads-batch $($script:THREADS_BATCH) --batch-size $($script:BATCH_SIZE) --ubatch-size $($script:UBATCH_SIZE) --spec-type $SPEC_TYPE"
    if ($script:GPU_DETECTED) {
        $tunedLine += " --fit on --fit-target $($script:FIT_TARGET) --flash-attn on -ctk $($script:KV_CACHE_TYPE) -ctv $($script:KV_CACHE_TYPE)"
    } else {
        $tunedLine += " --n-gpu-layers 0 --flash-attn on -ctk $($script:KV_CACHE_TYPE) -ctv $($script:KV_CACHE_TYPE)"
    }
    Write-Host $tunedLine
    Write-Host "=======================================================" -ForegroundColor Cyan
}

function Test-LlamaRunning {
    if (Test-Path -LiteralPath $PID_FILE) {
        $rawPid = (Get-Content -LiteralPath $PID_FILE -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($rawPid -and ($rawPid.Trim() -match '^\d+$')) {
            $proc = Get-Process -Id ([int]$rawPid.Trim()) -ErrorAction SilentlyContinue
            if ($proc -and -not $proc.HasExited) {
                return $true
            }
        }
    }
    return $false
}

function Show-Models {
    Resolve-ModelSelection $MODEL_SELECT
    $runningModel = "NONE (stopped)"
    if ((Test-LlamaRunning) -and (Test-Path -LiteralPath $ACTIVE_MODEL_FILE)) {
        $runningModel = (Get-Content -LiteralPath $ACTIVE_MODEL_FILE -Raw).Trim()
    }
    Write-Host "=== Installed Local LLM Models ===" -ForegroundColor Cyan
    $q38Path = Join-Path $MODELS_DIR "Qwen3.8-27B-Uncensored-Q3_K_M.gguf"
    Write-Host "  1. [DEFAULT] qwen3.8 (-m 3.8) -> Qwen3.8-27B-Uncensored-Q3_K_M.gguf"
    if (Test-Path -LiteralPath $q38Path) {
        $sz38 = [Math]::Round((Get-Item -LiteralPath $q38Path).Length / 1GB, 2)
        Write-Host "     Status: Installed ($sz38 GiB)" -ForegroundColor Green
    } else {
        Write-Host "     Status: Missing" -ForegroundColor Yellow
    }

    $q35Path = Join-Path $MODELS_DIR "Qwen3.5-9B-Uncensored-Q4_K_M.gguf"
    Write-Host "  2. [FAST]    qwen3.5 (-m 3.5) -> Qwen3.5-9B-Uncensored-Q4_K_M.gguf (HauhauCS-Aggressive)"
    if (Test-Path -LiteralPath $q35Path) {
        $sz35 = [Math]::Round((Get-Item -LiteralPath $q35Path).Length / 1GB, 2)
        Write-Host "     Status: Installed ($sz35 GiB)" -ForegroundColor Green
    } else {
        Write-Host "     Status: Missing" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Currently Running: $runningModel"
    Write-Host "==================================" -ForegroundColor Cyan
}

function Start-LlamaProcess {
    $serverExe = Join-Path $BIN_DIR "llama-server.exe"
    if (-not (Test-Path -LiteralPath $serverExe)) {
        throw "llama-server.exe not found at $serverExe. Run .\Win_setup_local_llm.ps1 first."
    }
    $env:PATH = "$BIN_DIR;$env:PATH"
    $argList = @(
        "--model", "`"$($script:MODEL_PATH)`"",
        "--alias", "`"$($script:MODEL_ALIAS)`"",
        "--host", $HOST_ADDR,
        "--port", $LLAMA_PORT,
        "--ctx-size", $script:CTX_SIZE,
        "--parallel", "1",
        "--context-shift",
        "--no-reasoning-preserve"
    ) + $script:GPU_ARGS + $script:FEATURE_ARGS + $script:SERVER_AGENT_ARGS + @(
        "--threads", "$($script:THREADS)",
        "--threads-batch", "$($script:THREADS_BATCH)",
        "--batch-size", "$($script:BATCH_SIZE)",
        "--ubatch-size", "$($script:UBATCH_SIZE)",
        "--cont-batching",
        "--webui"
    )

    $proc = Start-Process -FilePath $serverExe `
        -ArgumentList $argList `
        -WorkingDirectory $BASE_DIR `
        -RedirectStandardOutput $LOG_FILE `
        -RedirectStandardError $ERR_LOG_FILE `
        -WindowStyle Hidden `
        -PassThru

    Set-Content -LiteralPath $PID_FILE -Value $proc.Id -Encoding ASCII
    Set-Content -LiteralPath $ACTIVE_MODEL_FILE -Value "$($script:MODEL_ALIAS) ($(Split-Path -Leaf $script:MODEL_PATH))" -Encoding UTF8
    return $proc.Id
}

function Test-DockerDaemonReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $false
    }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $null = & docker info *>$null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $oldEap
    }
}

function Start-AllServices {
    Get-HardwareAndTune
    if (-not (Test-Path -LiteralPath $script:MODEL_PATH)) {
        Write-Error "Model file not found at $($script:MODEL_PATH). Run .\Win_setup_local_llm.ps1 to download models."
        exit 1
    }

    Show-HardwareProfile

    if (Test-LlamaRunning) {
        $currPid = (Get-Content -LiteralPath $PID_FILE -Raw).Trim()
        $currMod = if (Test-Path -LiteralPath $ACTIVE_MODEL_FILE) { (Get-Content -LiteralPath $ACTIVE_MODEL_FILE -Raw).Trim() } else { "unknown" }
        Write-Host "llama-server.exe is already running (PID $currPid, Model: $currMod). Use '.\manage-llm.ps1 restart -m $($script:MODEL_KEY)' to switch models." -ForegroundColor Yellow
    } else {
        Write-Host "Starting llama-server.exe ($($script:MODEL_ALIAS)) on http://${HOST_ADDR}:${LLAMA_PORT} ..." -ForegroundColor Green
        $newPid = Start-LlamaProcess
        Write-Host "llama-server.exe started (PID $newPid, Model: $($script:MODEL_ALIAS)). Built-in WebUI: http://${HOST_ADDR}:${LLAMA_PORT}" -ForegroundColor Green
    }

    if (Get-Command docker -ErrorAction SilentlyContinue) {
        if (Test-DockerDaemonReady) {
            Write-Host "Starting Open WebUI Docker container on http://${HOST_ADDR}:${WEBUI_PORT} (Default Model: $($script:MODEL_ALIAS)) ..." -ForegroundColor Green
            Push-Location $BASE_DIR
            try {
                $env:ACTIVE_MODEL_ALIAS = $script:MODEL_ALIAS
                & docker compose up -d
            } finally {
                Pop-Location
            }
        } else {
            Write-Host "  [i] Docker Desktop engine is not currently running; skipping Open WebUI container." -ForegroundColor Yellow
            Write-Host "      (Note: llama-server's built-in fast WebUI is available right now at http://${HOST_ADDR}:${LLAMA_PORT})" -ForegroundColor Cyan
        }
    }
}

function Start-AgentCli {
    Get-HardwareAndTune
    if (-not (Test-Path -LiteralPath $script:MODEL_PATH)) {
        Write-Error "Model file not found at $($script:MODEL_PATH). Run .\Win_setup_local_llm.ps1 to download models."
        exit 1
    }

    $currentActive = ""
    if (Test-Path -LiteralPath $ACTIVE_MODEL_FILE) {
        $currentActive = (Get-Content -LiteralPath $ACTIVE_MODEL_FILE -Raw).Trim()
    }

    if ((-not (Test-LlamaRunning)) -or (-not $currentActive.StartsWith($script:MODEL_ALIAS))) {
        if (Test-LlamaRunning) {
            Write-Host "Switching running llama-server.exe to $($script:MODEL_ALIAS) ..." -ForegroundColor Yellow
            Stop-AllServices -OnlyLlama
            Start-Sleep -Seconds 1
        }
        Show-HardwareProfile
        Write-Host "Starting local llama-server.exe backend ($($script:MODEL_ALIAS)) on http://${HOST_ADDR}:${LLAMA_PORT} ..." -ForegroundColor Green
        $null = Start-LlamaProcess
    } else {
        Show-HardwareProfile
    }

    Write-Host -NoNewline "Waiting for $($script:MODEL_ALIAS) backend to become ready "
    $ready = $false
    for ($w = 1; $w -le 90; $w++) {
        if (-not (Test-LlamaRunning)) {
            Write-Host ""
            Write-Host "[ERROR] llama-server.exe exited during startup. Last log lines:" -ForegroundColor Red
            if (Test-Path -LiteralPath $ERR_LOG_FILE) { Get-Content -LiteralPath $ERR_LOG_FILE -Tail 20 }
            if (Test-Path -LiteralPath $LOG_FILE) { Get-Content -LiteralPath $LOG_FILE -Tail 20 }
            exit 1
        }
        try {
            $resp = Invoke-RestMethod -Uri "http://${HOST_ADDR}:${LLAMA_PORT}/health" -TimeoutSec 2 -ErrorAction Stop
            if ($resp.status -eq "ok") {
                $ready = $true
                break
            }
        } catch {}
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 1
    }
    Write-Host ""
    if (-not $ready) {
        Write-Error "Timed out waiting for llama-server.exe on http://${HOST_ADDR}:${LLAMA_PORT}"
        exit 1
    }

    $env:LLAMA_API_URL      = "http://${HOST_ADDR}:${LLAMA_PORT}/v1/chat/completions"
    $env:MODEL_ALIAS        = $script:MODEL_ALIAS
    $env:SKIP_PERMISSIONS   = $SKIP_PERMISSIONS
    $env:OBSIDIAN_VAULT_DIR = $VAULT_DIR

    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pyCmd) { $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue }
    & $pyCmd.Source (Join-Path $BASE_DIR "agent-cli.py") @EXTRA_ARGS
}

function Stop-AllServices {
    param([switch]$OnlyLlama)
    if (Test-LlamaRunning) {
        $currPid = [int](Get-Content -LiteralPath $PID_FILE -Raw).Trim()
        Write-Host "Stopping llama-server.exe (PID $currPid)..." -ForegroundColor Yellow
        Stop-Process -Id $currPid -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $PID_FILE, $ACTIVE_MODEL_FILE -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "llama-server.exe is not running."
        Remove-Item -LiteralPath $PID_FILE, $ACTIVE_MODEL_FILE -Force -ErrorAction SilentlyContinue
    }

    if ((-not $OnlyLlama) -and (Test-Path -LiteralPath (Join-Path $BASE_DIR "docker-compose.yml")) -and (Test-DockerDaemonReady)) {
        Write-Host "Stopping Open WebUI container..." -ForegroundColor Yellow
        Push-Location $BASE_DIR
        try {
            & docker compose down
        } finally {
            Pop-Location
        }
    }
}

function Show-ServiceStatus {
    Show-HardwareProfile
    Write-Host ""
    Write-Host "Service Status:" -ForegroundColor Cyan
    if (Test-LlamaRunning) {
        $currPid = (Get-Content -LiteralPath $PID_FILE -Raw).Trim()
        $activeMod = if (Test-Path -LiteralPath $ACTIVE_MODEL_FILE) { (Get-Content -LiteralPath $ACTIVE_MODEL_FILE -Raw).Trim() } else { $script:MODEL_ALIAS }
        Write-Host "  llama-server: RUNNING (PID $currPid)" -ForegroundColor Green
        Write-Host "  Active Model: $activeMod"
        Write-Host "  Agent WebUI:  http://${HOST_ADDR}:${LLAMA_PORT} (Built-in fast WebUI with host Agent tools & OpenAI API)"
    } else {
        Write-Host "  llama-server: STOPPED" -ForegroundColor Yellow
    }

    if (Get-Command docker -ErrorAction SilentlyContinue) {
        if (Test-DockerDaemonReady) {
            $runningContainer = (& docker ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "local-open-webui" })
            if ($runningContainer) {
                Write-Host "  Open WebUI:   RUNNING -> http://${HOST_ADDR}:${WEBUI_PORT}" -ForegroundColor Green
            } else {
                Write-Host "  Open WebUI:   STOPPED (Docker Ready)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Open WebUI:   STOPPED (Docker Desktop daemon not running)" -ForegroundColor DarkGray
        }
    }

    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "GPU Memory Usage:" -ForegroundColor Cyan
        & nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total,utilization.gpu --format=csv
    }
}

function Open-ObsidianVault {
    $uri = "obsidian://open?path=$([System.Uri]::EscapeDataString($VAULT_DIR))"
    Write-Host "Opening Obsidian Vault ($VAULT_DIR) in Windows Obsidian app..." -ForegroundColor Green
    Start-Process $uri
}

switch ($ACTION) {
    "start"    { Start-AllServices }
    "stop"     { Stop-AllServices }
    "restart"  { Stop-AllServices; Start-Sleep -Seconds 1; Start-AllServices }
    "status"   { Show-ServiceStatus }
    "models"   { Show-Models }
    "tune"     { Show-HardwareProfile }
    "detect"   { Show-HardwareProfile }
    "cli"      { Start-AgentCli }
    "obsidian" { Open-ObsidianVault }
    "logs" {
        if (Test-Path -LiteralPath $LOG_FILE) {
            Get-Content -LiteralPath $LOG_FILE -Tail 50 -Wait
        } elseif (Test-Path -LiteralPath $ERR_LOG_FILE) {
            Get-Content -LiteralPath $ERR_LOG_FILE -Tail 50 -Wait
        } else {
            Write-Host "No log file found yet at $LOG_FILE"
        }
    }
    default { Show-Usage }
}
'@

Write-Utf8NoBom -Path (Join-Path $BASE_DIR "manage-llm.cmd") -Content @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0manage-llm.ps1" %*
'@

# 5. Generate Documentation, Network_Isolation\, and Complimentary Scripts\
Write-Host "[4/6] Generating documentation, Network_Isolation\, and Complimentary Scripts\ ..." -ForegroundColor Cyan

Write-Utf8NoBom -Path (Join-Path $BASE_DIR "LocalLLM_RunCMDs.md") -Content @'
# Windows Local LLM Guide (`Qwen3.8-27B` [Default] & `Qwen3.5-9B` [Fast])

This setup runs your local uncensored GGUF models natively on Windows using **`llama-server.exe` (CUDA / CPU)**, **`agent-cli.py`**, **Obsidian Desktop Vault**, and **Open WebUI (Docker Desktop)**, with automatic hardware resource detection and **Windows Local System & Hardware Agent Tools** (`project_tracker`, `scan_target`, `vault_save_note`, `vault_search`, `vault_read_note`, `serial_console`, `run_shell_command`, `write_file`, `edit_file`, `read_file`, `list_directory`).

---

## 0. One-Click Lab Replication (`Win_setup_local_llm.ps1`)

To deploy this entire setup onto any Windows workstation or laptop in your lab, copy **`Win_setup_local_llm.ps1`** to the machine and run in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\Win_setup_local_llm.ps1
```

It automatically creates the folder structure (`bin\`, `models\`, `open-webui-data\`, `ObsidianVault\`, `Network_Isolation\`, `Complimentary Scripts\`), registers `ObsidianVault` inside your installed Windows Obsidian desktop application (`%APPDATA%\obsidian\obsidian.json`), generates `manage-llm.ps1`, `agent-cli.py`, and `docker-compose.yml`, downloads & verifies the `llama.cpp` Windows CUDA (or CPU) binaries, and downloads the appropriate `Qwen3.8-27B` quantization + `Qwen3.5-9B` for the local hardware.

---

## 1. Installed Models & Model Switch (`-m`)

Both models are stored side-by-side in `models\`. **If you do not specify `-m`, the script defaults to `Qwen3.8-27B-Uncensored-Q3_K_M`.**

| Selector (`-m`) | Model File | Size | Speed on RTX 3070 Laptop (8 GB) | Best For |
| :--- | :--- | :--- | :--- | :--- |
| **`-m 3.8`** *(Default)*<br>*(or `qwen3.8`, `27b`)* | `Qwen3.8-27B-Uncensored-Q3_K_M.gguf` | **13.3 GB** | ~8 – 14 t/s *(CPU+GPU hybrid + N-gram spec)* | Maximum coding, hardware analysis & deep reasoning |
| **`-m 3.5`** *(Fast)*<br>*(or `qwen3.5`, `9b`, `fast`)* | `Qwen3.5-9B-Uncensored-Q4_K_M.gguf`<br>*(HauhauCS-Aggressive)* | **5.24 GB** | **~45 – 65 t/s** *(100% in 8 GB GPU VRAM)* | Fast interactive coding, serial/hardware ops, and chat |

---

## 2. Quick Start / Switch / Stop / Status Commands (PowerShell)

```powershell
# Launch interactive Local System Agent CLI (CONFIRM ON by default):
.\manage-llm.ps1 cli -m 3.5
.\manage-llm.ps1 cli -m 3.8

# Launch Local System Agent CLI with AUTO-RUN enabled (no confirmation prompts):
.\manage-llm.ps1 cli -m 3.5 --dangerously-skip-permissions
.\manage-llm.ps1 cli --dangerously-skip-permissions

# Launch Agent CLI pointing at project documentation to ingest, verify, and track in ObsidianVault\projects\:
.\manage-llm.ps1 cli -m 3.5 --project C:\path\to\docs_or_file
.\manage-llm.ps1 cli -m 3.8 --project C:\path\to\docs_or_file my_project_name

# Open the Obsidian Knowledge Vault directly in the Windows Obsidian desktop app:
.\manage-llm.ps1 obsidian

# Start background server + Open WebUI (Docker) with DEFAULT model (Qwen3.8-27B):
.\manage-llm.ps1 start

# Start or switch background server to FAST model (Qwen3.5-9B):
.\manage-llm.ps1 restart -m 3.5

# List installed models and see which one is currently running:
.\manage-llm.ps1 models

# Check status, active model, auto-detected hardware profile, and GPU VRAM usage:
.\manage-llm.ps1 status

# Inspect auto-detected hardware resources & flags without starting (dry run):
.\manage-llm.ps1 tune
.\manage-llm.ps1 tune -m 3.5

# Stop all services and free all RAM/VRAM:
.\manage-llm.ps1 stop
```

---

## 3. Local System Agent CLI, Hardware & Serial Tools, and Obsidian Vault

When you run **`.\manage-llm.ps1 cli`**, [`agent-cli.py`](./agent-cli.py) injects a live Windows hardware/OS/COM-port snapshot and gives the LLM 11 local tools:
* **`project_tracker`:** Creates/updates an active project in `ObsidianVault\projects\<project_name>.md` and indexes it in `00_MEMORY_INDEX.md`.
* **`scan_target`:** Probes any URL/API/host using `curl.exe` and auto-saves the structured report into `ObsidianVault\targets\`.
* **`vault_save_note` / `vault_search` / `vault_read_note`:** Full two-tier long-term memory inside `ObsidianVault\`.
* **`serial_console`:** Non-interactive Windows COM/Serial port tool (`list`, `probe`, `exec`) using `.NET System.IO.Ports.SerialPort` to discover `COM1`/`COM3`/USB-Serial devices, auto-login, and run hardware console commands.
* **`run_shell_command`:** Executes PowerShell and Windows CLI commands (`curl.exe`, `Get-NetAdapter`, `Get-PnpDevice`, `nvidia-smi`, `ipconfig`, `netsh`, etc.) and returns `stdout`/`stderr`.
* **`write_file` / `edit_file` / `read_file` / `list_directory`:** Full local Windows filesystem access.
'@

Copy-Item -LiteralPath (Join-Path $BASE_DIR "LocalLLM_RunCMDs.md") -Destination (Join-Path $BASE_DIR "SetupReadMe.md") -Force

Write-Utf8NoBom -Path (Join-Path $BASE_DIR "Network_Isolation\LLM_IsolationOptions.md") -Content @'
# Windows LocalLLM Network Isolation Options (`LLM_IsolationOptions.md`)

To guarantee that your Windows LocalLLM setup (`llama-server.exe`, `agent-cli.py`, and Open WebUI) can never send or receive data over the public internet once installed—while still functioning normally on `127.0.0.1`, local lab Ethernet adapters, and USB/COM serial consoles—you can enforce isolation at three layers of Windows.

---

## 1. Loopback-Only Binding (Inbound Protection)
* **How it works:** `llama-server.exe` (`127.0.0.1:8080`) and Open WebUI (`127.0.0.1:3000`) bind strictly to the local loopback address (`127.0.0.1`) rather than `0.0.0.0`.
* **What it prevents:** Windows TCP/IP only accepts connections originating from inside your own workstation. Nothing on Wi-Fi, LAN, or WAN can connect inward to those ports.

---

## 2. Windows Defender Firewall Outbound Program & Subnet Isolation (`LLM_NetworkIsolationSetup.ps1`)
* **Implemented by:** [`LLM_NetworkIsolationSetup.ps1`](./LLM_NetworkIsolationSetup.ps1)
* **How it works:** Uses Windows Defender Firewall with Advanced Security (`New-NetFirewallRule`) to govern `llama-server.exe` (and optionally `python.exe` / `curl.exe`):
  * **Mode A (`-Mode LabOnly` [Default]):** Explicitly blocks outbound traffic from `llama-server.exe` over Wireless (`InterfaceType Wireless`) and public internet IP ranges, while allowing `127.0.0.1/8` (loopback) and RFC1918 / Link-Local lab subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`) on Wired Ethernet interfaces, plus full unrestricted access to local Windows `COMx` USB serial ports.
  * **Mode B (`-Mode AirGap`):** Blocks all outbound network traffic from `llama-server.exe` to any non-loopback address (`RemoteAddress` outside `127.0.0.1` / `::1`).

---

## 3. Docker Container Internal Bridge Isolation
* For `local-open-webui`, `docker-compose.yml` publishes `127.0.0.1:3000:3000` (loopback only) and communicates with `llama-server.exe` strictly over `host.docker.internal:8080`.
'@

Write-Utf8NoBom -Path (Join-Path $BASE_DIR "Network_Isolation\LLM_NetworkIsolationSetup.ps1") -Content @'
#Requires -Version 5.1
<#
.SYNOPSIS
    LLM_NetworkIsolationSetup.ps1 — Windows Defender Firewall & Serial Console Isolation for LocalLLM

.DESCRIPTION
    Configures Windows Defender Firewall outbound rules (`LLM_ISOLATION_*`) so LocalLLM processes
    can communicate over local loopback (127.0.0.1), wired lab Ethernet subnets, and local COM
    serial ports while blocking wireless/public internet access.

    Switches:
      --setup,  -Setup        Apply Windows Firewall outbound isolation rules (requires Administrator)
      --remove, -Remove       Remove all `LLM_ISOLATION_*` Windows Firewall rules (requires Administrator)
      --status, -Status       Show current firewall rules, network adapters, and connected COM serial ports
      --mode,   -Mode <MODE>  'LabOnly' (default: allow loopback + wired LAN subnets, block public internet/Wi-Fi)
                              or 'AirGap' (block all non-loopback traffic)
      -h, --help, -Help       Show this help message
#>

$ErrorActionPreference = "Stop"
$RULE_GROUP = "LocalLLM_Isolation"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$BASE_DIR   = Split-Path -Parent $SCRIPT_DIR
$LLAMA_EXE  = Join-Path $BASE_DIR "bin\llama-server.exe"

$ACTION = "status"
$MODE   = "LabOnly"

$i = 0
while ($i -lt $args.Count) {
    $a = [string]$args[$i]
    switch -Regex ($a) {
        '^(--setup|-Setup|setup)$'                 { $ACTION = "setup"; $i++; continue }
        '^(--remove|-Remove|--teardown|remove)$'   { $ACTION = "remove"; $i++; continue }
        '^(--status|-Status|status)$'              { $ACTION = "status"; $i++; continue }
        '^(--mode|-Mode)$' {
            if (($i + 1) -lt $args.Count) { $MODE = [string]$args[$i + 1]; $i += 2; continue }
            $i++; continue
        }
        '^(-h|--help|-Help|help)$'                 { $ACTION = "help"; $i++; continue }
        default                                    { $i++; continue }
    }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Help {
    Write-Host @"
Usage: .\LLM_NetworkIsolationSetup.ps1 {--setup|--remove|--status|--help} [-Mode LabOnly|AirGap]

Examples (Run in Administrator PowerShell for --setup / --remove):
  .\LLM_NetworkIsolationSetup.ps1 --setup
  .\LLM_NetworkIsolationSetup.ps1 --setup -Mode AirGap
  .\LLM_NetworkIsolationSetup.ps1 --status
  .\LLM_NetworkIsolationSetup.ps1 --remove
"@
}

function Set-IsolationRules {
    if (-not (Test-IsAdmin)) {
        Write-Error "Applying Windows Firewall rules requires an elevated (Administrator) PowerShell prompt."
        exit 1
    }
    Remove-IsolationRules -Silent

    Write-Host "=== Setting Up Windows Firewall Isolation ($MODE) ===" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $LLAMA_EXE)) {
        Write-Host "  [!] Warning: $LLAMA_EXE not found yet; creating rule for target path anyway." -ForegroundColor Yellow
    }

    if ($MODE -ieq "AirGap") {
        # Block all public/private/domain outbound except loopback for llama-server.exe
        New-NetFirewallRule -DisplayName "LLM_ISOLATION_Block_Wireless" `
            -Group $RULE_GROUP -Direction Outbound -Action Block `
            -Program $LLAMA_EXE -InterfaceType Wireless | Out-Null
        New-NetFirewallRule -DisplayName "LLM_ISOLATION_Block_Internet" `
            -Group $RULE_GROUP -Direction Outbound -Action Block `
            -Program $LLAMA_EXE -RemoteAddress Internet | Out-Null
        New-NetFirewallRule -DisplayName "LLM_ISOLATION_Block_LocalSubnet" `
            -Group $RULE_GROUP -Direction Outbound -Action Block `
            -Program $LLAMA_EXE -RemoteAddress LocalSubnet | Out-Null
        Write-Host "  [+] Applied AirGap outbound block rules for $LLAMA_EXE (Loopback 127.0.0.1 only)." -ForegroundColor Green
    } else {
        # LabOnly: Block Wi-Fi and public Internet, allow loopback + wired LocalSubnet
        New-NetFirewallRule -DisplayName "LLM_ISOLATION_Block_Wireless" `
            -Group $RULE_GROUP -Direction Outbound -Action Block `
            -Program $LLAMA_EXE -InterfaceType Wireless | Out-Null
        New-NetFirewallRule -DisplayName "LLM_ISOLATION_Block_Internet" `
            -Group $RULE_GROUP -Direction Outbound -Action Block `
            -Program $LLAMA_EXE -RemoteAddress Internet | Out-Null
        Write-Host "  [+] Applied LabOnly firewall rules: Blocked Wireless & public Internet; Allowed Loopback (127.0.0.1) & Wired Lab LAN." -ForegroundColor Green
    }
    Write-Host "=====================================================" -ForegroundColor Cyan
}

function Remove-IsolationRules {
    param([switch]$Silent)
    if (-not (Test-IsAdmin)) {
        Write-Error "Removing Windows Firewall rules requires an elevated (Administrator) PowerShell prompt."
        exit 1
    }
    $existing = Get-NetFirewallRule -Group $RULE_GROUP -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Remove-NetFirewallRule
        if (-not $Silent) {
            Write-Host "[-] Removed all Windows Firewall rules in group '$RULE_GROUP'." -ForegroundColor Green
        }
    } elseif (-not $Silent) {
        Write-Host "[=] No active '$RULE_GROUP' firewall rules found." -ForegroundColor Yellow
    }
}

function Show-IsolationStatus {
    Write-Host "=== Windows LocalLLM Network & Hardware Isolation Status ===" -ForegroundColor Cyan
    $rules = Get-NetFirewallRule -Group $RULE_GROUP -ErrorAction SilentlyContinue
    if ($rules) {
        Write-Host "  Firewall Isolation: ACTIVE ($($rules.Count) rules in group '$RULE_GROUP')" -ForegroundColor Green
        foreach ($r in $rules) {
            Write-Host "    - $($r.DisplayName): Enabled=$($r.Enabled) Action=$($r.Action) Direction=$($r.Direction)"
        }
    } else {
        Write-Host "  Firewall Isolation: NOT ACTIVE (Run '.\LLM_NetworkIsolationSetup.ps1 --setup' as Administrator)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Connected Serial / COM Ports:" -ForegroundColor Cyan
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports.Count -gt 0) {
        foreach ($p in $ports) { Write-Host "    [PRESENT] $p" -ForegroundColor Green }
    } else {
        Write-Host "    (No COM ports currently connected)"
    }

    Write-Host ""
    Write-Host "  Active Network Adapters:" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object Status -eq "Up" | ForEach-Object {
        Write-Host "    - $($_.Name) [$($_.InterfaceDescription)] ($($_.LinkSpeed))"
    }
    Write-Host "============================================================" -ForegroundColor Cyan
}

switch ($ACTION) {
    "setup"  { Set-IsolationRules }
    "remove" { Remove-IsolationRules }
    "status" { Show-IsolationStatus }
    default  { Show-Help }
}
'@

Write-Utf8NoBom -Path (Join-Path $BASE_DIR "Network_Isolation\NetworkIsolationReadMe.md") -Content @'
# Windows Network & Hardware Isolation Reference (`NetworkIsolationReadMe.md`)

1. **`LLM_IsolationOptions.md`**: Explains Loopback-Only Binding (`127.0.0.1:8080`), Windows Defender Firewall Outbound Program/Interface Filtering (`LabOnly` vs `AirGap`), and Docker Bridge Isolation.
2. **`LLM_NetworkIsolationSetup.ps1`**:
   - `.\LLM_NetworkIsolationSetup.ps1 --status` — Shows active firewall isolation rules, connected Windows `COMx` serial ports, and active network adapters.
   - `.\LLM_NetworkIsolationSetup.ps1 --setup` *(Run as Administrator)* — Blocks `llama-server.exe` on Wi-Fi (`Wireless`) and public `Internet` routes while preserving `127.0.0.1` loopback, wired lab subnets, and `COMx` serial ports.
   - `.\LLM_NetworkIsolationSetup.ps1 --setup -Mode AirGap` *(Run as Administrator)* — Blocks all non-loopback traffic.
   - `.\LLM_NetworkIsolationSetup.ps1 --remove` *(Run as Administrator)* — Removes all `LocalLLM_Isolation` firewall rules.
'@

Write-Utf8NoBom -Path (Join-Path $BASE_DIR "Complimentary Scripts\serial_console.ps1") -Content @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Non-interactive Windows COM Port Serial Console Helper for LocalLLM Agent CLI (`serial_console.ps1`)
    Uses built-in .NET System.IO.Ports.SerialPort (zero external dependencies required).

.DESCRIPTION
    Actions (-Action):
      list   : Enumerate all connected Windows COM ports and PnP serial devices
      probe  : Send CR (\r) to -Port and read current prompt/banner
      exec   : Optional smart auto-login (-Username / -Password) + send -Command and capture output
#>
param(
    [ValidateSet("list", "probe", "exec")]
    [string]$Action = "list",
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [string]$Command = "",
    [string]$Username = "",
    [string]$Password = "",
    [int]$TimeoutMs = 3000
)

$ErrorActionPreference = "Stop"

function Get-ComPortInventory {
    $portNames = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    $pnpPorts  = Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue
    Write-Host "=== Windows Serial / COM Port Inventory ==="
    if (-not $portNames -or $portNames.Count -eq 0) {
        Write-Host "No active COM ports detected on this machine."
        return
    }
    foreach ($pn in $portNames) {
        $match = $pnpPorts | Where-Object { $_.FriendlyName -match "\($pn\)" } | Select-Object -First 1
        $desc  = if ($match) { $match.FriendlyName } else { "Serial Port ($pn)" }
        Write-Host "  - $pn : $desc"
    }
}

function Read-SerialAvailable {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$WaitMs = 1500,
        [string]$StopRegex = ""
    )
    $sb = New-Object System.Text.StringBuilder
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $quietSw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.ElapsedMilliseconds -lt $WaitMs) {
        $bytesToRead = $Serial.BytesToRead
        if ($bytesToRead -gt 0) {
            $chunk = $Serial.ReadExisting()
            [void]$sb.Append($chunk)
            $quietSw.Restart()
            if ($StopRegex -and ($sb.ToString() -match $StopRegex)) {
                Start-Sleep -Milliseconds 150
                if ($Serial.BytesToRead -gt 0) {
                    [void]$sb.Append($Serial.ReadExisting())
                }
                break
            }
        } else {
            if ($sb.Length -gt 0 -and $quietSw.ElapsedMilliseconds -ge 450 -and (-not $StopRegex)) {
                break
            }
            Start-Sleep -Milliseconds 50
        }
    }
    return $sb.ToString()
}

if ($Action -eq "list") {
    Get-ComPortInventory
    exit 0
}

$sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.Handshake    = [System.IO.Ports.Handshake]::None
$sp.ReadTimeout  = 1000
$sp.WriteTimeout = 1000
$sp.DtrEnable    = $true
$sp.RtsEnable    = $true

try {
    $sp.Open()
} catch {
    Write-Error "Failed to open serial port $Port at $Baud baud: $($_.Exception.Message)"
    exit 1
}

try {
    $sp.Write("`r")
    $banner = Read-SerialAvailable -Serial $sp -WaitMs $TimeoutMs -StopRegex "([Ll]ogin:|[Uu]sername:|[Pp]assword:|#|>|\$)"

    if ($Action -eq "probe") {
        Write-Output $banner
        exit 0
    }

    # Smart auto-login if credentials provided and console is at login/password prompt
    if ($Username -and ($banner -match "(?i)(login|username):\s*$")) {
        $sp.Write("$Username`r")
        $banner += Read-SerialAvailable -Serial $sp -WaitMs $TimeoutMs -StopRegex "([Pp]assword:|#|>|\$)"
    }
    if ($Password -and ($banner -match "(?i)password:\s*$")) {
        $sp.Write("$Password`r")
        $banner += Read-SerialAvailable -Serial $sp -WaitMs 4000 -StopRegex "(#|>|\$)"
    }

    if ($Command) {
        $sp.Write("$Command`r")
        $cmdOut = Read-SerialAvailable -Serial $sp -WaitMs $TimeoutMs
        Write-Output ($banner + $cmdOut)
    } else {
        Write-Output $banner
    }
} finally {
    if ($sp.IsOpen) {
        $sp.Close()
    }
    $sp.Dispose()
}
'@

Write-Utf8NoBom -Path (Join-Path $BASE_DIR "Complimentary Scripts\serial_watch.ps1") -Content @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Inspect Windows COM/Serial devices and check which local processes have serial handles open.
#>
param([string]$Port = "")

Write-Host "=== Windows Serial / COM Port Status Monitor ===" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "serial_console.ps1") -Action list
Write-Host ""
Write-Host "Active Serial / Terminal Processes (putty, plink, python, tio, llama-server):" -ForegroundColor Cyan
Get-Process | Where-Object { $_.ProcessName -match "^(putty|plink|kitty|teraterm|python|llama-server|powershell)$" } |
    Select-Object Id, ProcessName, StartTime, Path | Format-Table -AutoSize
'@

# 6. Download & extract llama.cpp Windows binaries if not already installed
Write-Host "[5/6] Checking llama.cpp Windows binaries in $BASE_DIR\bin ..." -ForegroundColor Cyan
$BinDir    = Join-Path $BASE_DIR "bin"
$ServerExe = Join-Path $BinDir "llama-server.exe"

function Test-LlamaBinaryValid {
    if (-not (Test-Path -LiteralPath $ServerExe)) { return $false }
    if ($HW_INFO.GpuDetected -and -not (Test-Path -LiteralPath (Join-Path $BinDir "ggml-cuda.dll"))) { return $false }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $env:PATH = "$BinDir;$env:PATH"
        $null = & $ServerExe --version *>$null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $oldEap
    }
}

function Install-ZipToBin {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$DestBinDir,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $tmpZip = Join-Path $env:TEMP ("llama_dl_" + [Guid]::NewGuid().ToString("N") + ".zip")
    $tmpExt = Join-Path $env:TEMP ("llama_ext_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmpExt -Force | Out-Null

    try {
        Write-Host "  -> Downloading $Label ..." -ForegroundColor Cyan
        & curl.exe -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o $tmpZip $Url
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmpZip)) {
            throw "curl.exe failed to download $Url"
        }

        Write-Host "  -> Extracting $Label into $DestBinDir ..." -ForegroundColor Cyan
        & tar.exe -xf $tmpZip -C $tmpExt
        if ($LASTEXITCODE -ne 0) {
            Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpExt -Force
        }

        # Handle either flat archive or single top-level subfolder inside zip
        $topItems = Get-ChildItem -LiteralPath $tmpExt -Force
        $sourceRoot = $tmpExt
        if ($topItems.Count -eq 1 -and $topItems[0].PSIsContainer) {
            $sourceRoot = $topItems[0].FullName
        }

        Get-ChildItem -LiteralPath $sourceRoot -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $DestBinDir -Recurse -Force
        }
    } finally {
        Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpExt -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Test-LlamaBinaryValid) {
    Write-Host "  -> llama-server.exe binary already installed and verified." -ForegroundColor Green
} else {
    $installedOk = $false
    if ($HW_INFO.GpuDetected) {
        if ($HW_INFO.CudaVersion -ge 13.4) {
            $cudaUrl   = $LLAMA_WIN_CUDA13_URL
            $cudartUrl = $LLAMA_WIN_CUDART13_URL
            $cudaLabel = "CUDA 13.4 x64"
        } else {
            $cudaUrl   = $LLAMA_WIN_CUDA12_URL
            $cudartUrl = $LLAMA_WIN_CUDART12_URL
            $cudaLabel = "CUDA 12.4 x64 (compatible with CUDA 12.x+)"
        }
        Write-Host "  -> NVIDIA GPU detected ($($HW_INFO.GpuName), Driver CUDA $($HW_INFO.CudaVersion)). Installing llama.cpp $LLAMA_BUILD_TAG $cudaLabel binaries + CUDA runtime ..." -ForegroundColor Green
        try {
            Install-ZipToBin -Url $cudaUrl   -DestBinDir $BinDir -Label "llama.cpp $LLAMA_BUILD_TAG ($cudaLabel)"
            Install-ZipToBin -Url $cudartUrl -DestBinDir $BinDir -Label "CUDA Runtime DLLs ($cudaLabel)"
            if (Test-LlamaBinaryValid) {
                $installedOk = $true
            }
        } catch {
            Write-Host "  [!] Warning: CUDA binary download/verification failed ($($_.Exception.Message)); falling back to CPU x64 binaries..." -ForegroundColor Yellow
        }
    }

    if (-not $installedOk) {
        Write-Host "  -> Downloading llama.cpp $LLAMA_BUILD_TAG Windows CPU x64 binaries ..." -ForegroundColor Cyan
        Install-ZipToBin -Url $LLAMA_WIN_CPU_URL -DestBinDir $BinDir -Label "llama.cpp $LLAMA_BUILD_TAG (Windows CPU x64)"
        if (-not (Test-LlamaBinaryValid)) {
            throw "Error: llama-server.exe failed verification after extraction in $BinDir"
        }
    }
    Write-Host "  -> Windows llama.cpp binaries installed and verified." -ForegroundColor Green
}

# 7. Download LLM models (Qwen3.5-9B and Qwen3.8-27B at appropriate quantization)
Write-Host "[6/6] Checking & downloading LLM models in $BASE_DIR\models ..." -ForegroundColor Cyan

$WANT_35 = $false
$WANT_38 = $false

switch ($DOWNLOAD_MODE) {
    "all"  { $WANT_35 = $true;  $WANT_38 = $true }
    "3.8"  { $WANT_35 = $false; $WANT_38 = $true }
    "3.5"  { $WANT_35 = $true;  $WANT_38 = $false }
    "none" { $WANT_35 = $false; $WANT_38 = $false }
    "auto" {
        $WANT_35 = $true
        if ($HW_INFO.TotalRamMiB -ge 15000) {
            $WANT_38 = $true
        } else {
            Write-Host "  -> Host has $($HW_INFO.TotalRamMiB) MiB RAM (< 16 GiB): defaulting to Qwen3.5-9B (pass --all-models to force Qwen3.8-27B)." -ForegroundColor Yellow
        }
    }
}

function Invoke-ModelDownload {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$DestPath,
        [Parameter(Mandatory=$true)][int64]$MinBytes
    )
    # Check if model already exists in parent ..\models to avoid redundant 18 GB re-download
    $parentModelsDir = Join-Path (Split-Path -Parent $BASE_DIR) "models"
    $parentCandidate = Join-Path $parentModelsDir (Split-Path -Leaf $DestPath)
    if ((-not (Test-Path -LiteralPath $DestPath)) -and (Test-Path -LiteralPath $parentCandidate)) {
        $pLen = (Get-Item -LiteralPath $parentCandidate).Length
        if ($pLen -ge $MinBytes) {
            Write-Host "  -> Found existing verified model in $parentCandidate; linking into $DestPath ..." -ForegroundColor Green
            try {
                New-Item -ItemType HardLink -Path $DestPath -Target $parentCandidate -Force | Out-Null
            } catch {
                Copy-Item -LiteralPath $parentCandidate -Destination $DestPath -Force
            }
        }
    }

    if (Test-Path -LiteralPath $DestPath) {
        $actualBytes = (Get-Item -LiteralPath $DestPath).Length
        if ($actualBytes -ge $MinBytes) {
            $mib = [int]([Math]::Round($actualBytes / 1MB))
            Write-Host "  -> $Name already downloaded and verified ($mib MiB)." -ForegroundColor Green
            return
        }
        $mib = [int]([Math]::Round($actualBytes / 1MB))
        Write-Host "  -> $Name is incomplete ($mib MiB); resuming download..." -ForegroundColor Yellow
    } else {
        $driveRoot = [System.IO.Path]::GetPathRoot($DestPath)
        $driveInfo = New-Object System.IO.DriveInfo($driveRoot)
        $availMiB  = [int64]([Math]::Round($driveInfo.AvailableFreeSpace / 1MB))
        $neededMiB = [int64]([Math]::Round($MinBytes / 1MB) + 512)
        if ($availMiB -lt $neededMiB) {
            throw "Insufficient disk space on drive $driveRoot ($availMiB MiB free, need at least $neededMiB MiB for $Name)."
        }
        Write-Host "  -> Downloading $Name from $Url ..." -ForegroundColor Cyan
    }

    & curl.exe -fL --retry 5 --retry-delay 3 -C - -o $DestPath $Url
    if ($LASTEXITCODE -ne 0) {
        throw "curl.exe download failed for $Name (exit code $LASTEXITCODE). Re-run .\Win_setup_local_llm.ps1 to resume."
    }

    $finalBytes = (Get-Item -LiteralPath $DestPath).Length
    if ($finalBytes -lt $MinBytes) {
        throw "Downloaded file $DestPath is smaller than expected ($finalBytes bytes < $MinBytes bytes). Re-run .\Win_setup_local_llm.ps1 to resume."
    }
}

if ($WANT_35) {
    $dest35 = Join-Path $BASE_DIR "models\$QWEN35_FILE"
    Invoke-ModelDownload -Name "Qwen3.5-9B-Uncensored-Q4_K_M.gguf (5.24 GiB)" `
        -Url $QWEN35_URL -DestPath $dest35 -MinBytes $QWEN35_MIN_BYTES

    $alt35 = Join-Path $BASE_DIR "models\Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
    if (-not (Test-Path -LiteralPath $alt35)) {
        try {
            New-Item -ItemType HardLink -Path $alt35 -Target $dest35 -Force | Out-Null
        } catch {}
    }
}

if ($WANT_38) {
    $dest38 = Join-Path $BASE_DIR "models\$QWEN38_FILE"
    Invoke-ModelDownload -Name "Qwen3.8-27B-Uncensored [$SELECTED_QUANT] ($($QUANT_META.Desc))" `
        -Url $QWEN38_URL -DestPath $dest38 -MinBytes $QWEN38_MIN_BYTES

    if ($QWEN38_ALT_FILE -ne $QWEN38_FILE) {
        $alt38 = Join-Path $BASE_DIR "models\$QWEN38_ALT_FILE"
        if (-not (Test-Path -LiteralPath $alt38)) {
            try {
                New-Item -ItemType HardLink -Path $alt38 -Target $dest38 -Force | Out-Null
            } catch {}
        }
    }
}

# Ensure ReadMe.md exists in $BASE_DIR if not already written
$ReadMeTarget = Join-Path $BASE_DIR "ReadMe.md"
if (-not (Test-Path -LiteralPath $ReadMeTarget)) {
    Copy-Item -LiteralPath (Join-Path $BASE_DIR "LocalLLM_RunCMDs.md") -Destination $ReadMeTarget -Force
}

Write-Host ""
Write-Host "Setup complete! Verifying installed models and Windows hardware profile:" -ForegroundColor Green
Write-Host ""
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BASE_DIR "manage-llm.ps1") models
Write-Host ""
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BASE_DIR "manage-llm.ps1") tune
Write-Host ""
Write-Host "Quick Start Commands (PowerShell):" -ForegroundColor Cyan
Write-Host "  cd `"$BASE_DIR`""
Write-Host "  .\manage-llm.ps1 cli -m 3.5                                       # Fast Agent CLI (Confirm ON)"
Write-Host "  .\manage-llm.ps1 cli -m 3.5 --dangerously-skip-permissions        # Fast Agent CLI (Auto-run)"
Write-Host "  .\manage-llm.ps1 cli -m 3.5 --project C:\path\to\docs my_project  # Onboard & track a project in Obsidian"
Write-Host "  .\manage-llm.ps1 cli -m 3.8 --dangerously-skip-permissions        # Default Qwen3.8 Agent CLI (Auto-run)"
Write-Host "  .\manage-llm.ps1 obsidian                                         # Open ObsidianVault in Windows Obsidian"
Write-Host "  .\manage-llm.ps1 start                                            # Start llama-server + Open WebUI (Docker)"

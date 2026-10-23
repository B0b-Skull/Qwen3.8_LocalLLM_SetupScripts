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
| **`-m 3.8`** *(Default)*<br>*(or `qwen3.8`, `27b`)* | `Qwen3.8-27B-Uncensored-Q3_K_M.gguf` | **13.3 GB** | ~8 â€“ 14 t/s *(CPU+GPU hybrid + N-gram spec)* | Maximum coding, hardware analysis & deep reasoning |
| **`-m 3.5`** *(Fast)*<br>*(or `qwen3.5`, `9b`, `fast`)* | `Qwen3.5-9B-Uncensored-Q4_K_M.gguf`<br>*(HauhauCS-Aggressive)* | **5.24 GB** | **~45 â€“ 65 t/s** *(100% in 8 GB GPU VRAM)* | Fast interactive coding, serial/hardware ops, and chat |

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
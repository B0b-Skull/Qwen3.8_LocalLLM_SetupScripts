### How it works:
The entire custom Agent CLI (agent-cli.py) is embedded directly inside setup_local_llm.sh:126-574 and uses only
built-in Python 3 standard library modules (no pip install or virtual environments needed on the target machine).                                                                                                      
                                                                                                                 
# When you run bash setup_local_llm.sh on another laptop:                                                                                                                                                       
1. Auto-Generates & Wires agent-cli.py: Writes agent-cli.py, sets chmod +x, and links it to ./manage-llm.sh cli.
2. Dynamically Detects the New Laptop's System Info: On startup, get_live_hardware_summary() queries that machine's live hostname, $USER, OS/kernel, CPU (lscpu), RAM (free -h), GPU (nvidia-smi), and current working directory, and injects them into the LLM's system prompt.                                                      
3. Auto-Starts & Connects the Backend: Running ./manage-llm.sh cli (or ./manage-llm.sh cli -m 3.5 --dangerously-skip-permissions) automatically launches llama-server with the hardware-tuned flags for that laptop,	waits for http://127.0.0.1:8080/health to report ready, and connects the Agent CLI with all 5 host tools (run_shell_command, write_file, edit_file, read_file, list_directory) and the confirmation toggle ready to use.

# LocalLLM Setup & Operations Reference (`SetupReadMe.md`)

A compact reference for deploying, running, switching, and extending the LocalLLM + System Agent CLI stack across lab machines.

---

## 1. One-Click Lab Deployment (`setup_local_llm.sh`)

Copy `setup_local_llm.sh` to any Linux machine and run it. It creates `bin/`, `models/`, `open-webui-data/`, generates all scripts/configs (`manage-llm.sh`, `agent-cli.py`, `docker-compose.yml`, `README.md`, `SetupReadMe.md`), installs `llama.cpp` CUDA/CPU binaries, and downloads the models.

```bash
# Full automatic setup (detects GPU/RAM; downloads Qwen3.5-9B + Qwen3.8-27B if RAM >= 16 GiB)
bash setup_local_llm.sh

# Installer switches:
bash setup_local_llm.sh --all-models          # Force download of both Qwen3.8-27B and Qwen3.5-9B
bash setup_local_llm.sh --only-3.5            # Download only Qwen3.5-9B (5.24 GB, fast)
bash setup_local_llm.sh --only-3.8            # Download only Qwen3.8-27B (13.3 GB, max quality)
bash setup_local_llm.sh --skip-models         # Install scripts & llama.cpp binaries only
bash setup_local_llm.sh --dir /opt/LocalLLM   # Install into a custom target directory
```

---

## 2. Core Commands (`manage-llm.sh`)

| Command | Description |
| :--- | :--- |
| `./manage-llm.sh cli` | Launch the interactive **Local System Agent CLI** (auto-starts backend if needed) |
| `./manage-llm.sh start` | Start `llama-server` (`127.0.0.1:8080`) + Open WebUI (`127.0.0.1:3000`) |
| `./manage-llm.sh restart` | Restart services (use with `-m` to switch the active model) |
| `./manage-llm.sh stop` | Stop `llama-server` and Open WebUI; free all RAM and VRAM |
| `./manage-llm.sh status` | Show running state, active model, auto-detected hardware profile, and VRAM usage |
| `./manage-llm.sh models` | List installed models in `models/` and show which one is active |
| `./manage-llm.sh tune` | Dry-run hardware auto-detection and print computed `llama-server` flags |
| `./manage-llm.sh logs` | Tail live `llama-server.log` output |

---

## 3. All Switches & Environment Overrides

### CLI Switches (usable with `start`, `restart`, `cli`, `tune`)

| Switch | Values / Default | Purpose |
| :--- | :--- | :--- |
| **`-m`, `--model`** | `3.8` *(default)* \| `3.5` \| `<file.gguf>` | Select `Qwen3.8-27B` (`3.8`/`27b`), `Qwen3.5-9B` (`3.5`/`9b`/`fast`), or any `.gguf` file |
| **`--no-think`** | **Default (`on`)** | Disable `<think>` internal monologue so answers start immediately |
| **`--think`** | Optional | Enable step-by-step `<think>` chain-of-thought reasoning for hard problems |
| **`--confirm`** | **Default (`on`)** | Prompt `[y/N/a]` before executing shell commands or file writes in `cli` |
| **`--dangerously-skip-permissions`** | Optional | Auto-run all shell commands and file writes/edits without prompting |
| **`-P`, `--project`** | `<doc_path> [name]` *(with `cli`)* | Ingest documentation file/folder, verify data with user, and create/track an Obsidian project in `ObsidianVault/projects/` |
| **`-p`, `--prompt`** | `"<text>"` *(with `cli`)* | Run a single prompt in the Agent CLI and exit |

### Environment Variable Overrides

```bash
CTX_SIZE=32768 ./manage-llm.sh restart -m 3.5        # Override context window size
FIT_TARGET=512 ./manage-llm.sh restart -m 3.8        # Override GPU VRAM safety reserve (MiB)
THREADS=12 THREADS_BATCH=20 ./manage-llm.sh restart  # Override CPU thread counts
AGENT_MODE=off ./manage-llm.sh restart               # Disable built-in llama-server host tools
```

---

## 4. Local System Agent CLI + Obsidian Knowledge Vault (`./manage-llm.sh cli`)

The Agent CLI (`agent-cli.py`) includes a dedicated **two-tier Obsidian Knowledge Vault** at `~/Projects/LocalLLM/ObsidianVault`:
* **Tier-1 Hot Memory (`00_MEMORY_INDEX.md`):** Capped at ~450 tokens and automatically injected into the system prompt on every session so Qwen 3.8 & 3.5 immediately know what targets, working `curl` commands, and notes exist without burning context.
* **Tier-2 Deep Topic Notes (`targets/`, `commands/`, `projects/`, `knowledge/`):** Markdown notes with YAML frontmatter, `#tags`, and `[[WikiLinks]]` that can be opened directly as a Vault in the Obsidian desktop app and queried on demand by the LLM.

### Built-in Agent Tools (10 Host, Project & Vault Tools)
* `project_tracker` — Creates or updates an active project note in `ObsidianVault/projects/<project_name>.md` (tracks documentation findings, verification questions, verified data, and `- [ ]` / `- [x]` project plans) and indexes it in `00_MEMORY_INDEX.md`
* `scan_target` — Probes a URL/API/host (headers, status, endpoints, forms, JSON structure) and **auto-saves** the report into `ObsidianVault/targets/`
* `vault_save_note` — Saves distilled knowledge, verified working `curl` commands, or project notes into `ObsidianVault/<category>/<title>.md` and auto-updates `00_MEMORY_INDEX.md`
* `vault_search` — Searches all Markdown notes in `ObsidianVault/` by keyword or tag
* `vault_read_note` — Reads a specific note from `ObsidianVault/` into context on demand (including `commands/curl_playbook` and `commands/tio_serial_playbook`)
* `run_shell_command` — Runs bash/`curl`/`tio` commands and returns `stdout`/`stderr` (with automatic HTML/script stripping & context trimming)
* `write_file` / `edit_file` / `read_file` / `list_directory` — Full local filesystem access

### Agent CLI Examples

```bash
# 1. Fast Qwen3.5-9B with safety confirmation ON (default):
./manage-llm.sh cli -m 3.5

# 2. Fast Qwen3.5-9B with full auto-execution (no confirmation prompts):
./manage-llm.sh cli -m 3.5 --dangerously-skip-permissions

# 3. Onboard project documentation, verify data, and track in ObsidianVault/projects/:
./manage-llm.sh cli -m 3.5 --project /path/to/docs_or_file my_project

# 4. Scan a target URL/API (auto-saved to ObsidianVault) and craft valid curl commands:
./manage-llm.sh cli -m 3.5 --dangerously-skip-permissions -p "Scan http://127.0.0.1:8080 and save the working curl command to the vault"

# 5. Default Qwen3.8-27B (reads the exact same ObsidianVault notes):
./manage-llm.sh cli -m 3.8 --dangerously-skip-permissions
```

### In-Session Slash Commands (inside `./manage-llm.sh cli`)
* `/project <doc_path> [name]` — Ingest a file, directory of docs, or URL, ask verification questions, and create/track `ObsidianVault/projects/<name>.md`
* `/project list` (or `/project`) — List all projects in `ObsidianVault/projects/` and show the active project
* `/project load <name>` — Switch to and resume an existing project in `ObsidianVault/projects/`
* `/vault` — Display `00_MEMORY_INDEX.md` and indexed Obsidian notes
* `/remember <fact or command>` — Save a persistent note directly into `ObsidianVault/knowledge/` and `00_MEMORY_INDEX.md`
* `/search <keyword>` — Search across all notes in `ObsidianVault/`
* `/scan <url>` — Scan a target URL/host, auto-save to `ObsidianVault/targets/`, and ask the LLM to craft valid `curl` commands
* `/permissions` — Toggle between `CONFIRM ON ([y/N/a])` and `AUTO-RUN`
* `/hw` — Print live CPU, RAM, and GPU hardware status
* `/clear` — Clear active chat history while keeping Obsidian Vault memory active
* `/exit` (or `Ctrl+C`) — Exit the CLI

---

## 5. How to Add & Use Future Models (`.gguf`)

`manage-llm.sh` already supports loading **any GGUF model** out of the box and automatically recalculates VRAM fitting (`--fit-target`) and context window (`--ctx-size`) based on the new model's file size.

### Method A: Drop-in Usage (No Script Edits Required)

1. Download any `.gguf` file into `~/Projects/LocalLLM/models/`:
   ```bash
   wget -c -O ~/Projects/LocalLLM/models/NewModel-Q4_K_M.gguf "https://huggingface.co/<org>/<repo>/resolve/main/<file>.gguf"
   ```
2. Pass the filename (or full path) to `-m`:
   ```bash
   # Start Agent CLI with the new model:
   ./manage-llm.sh cli -m NewModel-Q4_K_M.gguf

   # Or start/switch the background server + Open WebUI to the new model:
   ./manage-llm.sh restart -m NewModel-Q4_K_M.gguf
   ```

### Method B: Add a Permanent Short Alias (Optional)

To add a permanent shorthand flag (e.g., `-m 4.0`) in `manage-llm.sh` (and `setup_local_llm.sh`):
1. Open `manage-llm.sh` and locate `resolve_model()`.
2. Add a new `case` branch under `case "$sel_lower" in`:
   ```bash
   qwen4.0|4.0)
     MODEL_KEY="qwen4.0"
     MODEL_ALIAS="Qwen4.0-Uncensored-Q4_K_M"
     MODEL_PATH="$MODELS_DIR/Qwen4.0-Uncensored-Q4_K_M.gguf"
     ;;
   ```
3. To make `Qwen4.0` the new default, change `MODEL_SELECT="${MODEL:-qwen3.8}"` at the top of `manage-llm.sh` to `MODEL_SELECT="${MODEL:-qwen4.0}"`.

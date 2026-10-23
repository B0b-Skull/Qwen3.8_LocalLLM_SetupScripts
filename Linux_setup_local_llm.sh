#!/usr/bin/env bash
# ==============================================================================
# setup_local_llm.sh — Turnkey Single-Click Local LLM & Agent CLI Installer
# ==============================================================================
# Copy this single script onto any Linux laptop in your lab and run:
#   bash setup_local_llm.sh
#
# What it does automatically:
#   1. Validates system prerequisites (bash, python3, curl/wget, tar, disk space)
#   2. Creates the folder structure:
#        - bin/, models/, open-webui-data/
#        - ObsidianVault/ (.obsidian, targets, commands, projects, knowledge)
#        - Network_Isolation/ & Complimentary Scripts/
#   3. Generates all scripts, playbooks, and documentation:
#        - manage-llm.sh      (Service manager, hardware auto-tuner, model switcher)
#        - agent-cli.py       (Local System Agent CLI + Obsidian Vault + --project tracker)
#        - docker-compose.yml (Open WebUI container config)
#        - LocalLLM_RunCMDs.md & SetupReadMe.md
#        - ObsidianVault/00_MEMORY_INDEX.md, curl_playbook.md, tio_serial_playbook.md
#        - Network_Isolation/ (LLM_NetworkIsolationSetup.sh, LLM_NetworkNamespaceSetup.sh, docs)
#        - Complimentary Scripts/serial_watch.sh
#   4. Downloads & extracts llama.cpp b11802 binaries (CUDA 12.8 if NVIDIA GPU
#      is present, or CPU x64 build on CPU-only laptops) with fallback & verification
#   5. Downloads Qwen3.8-27B-Uncensored-Q3_K_M.gguf (13.3 GB) and
#      Qwen3.5-9B-Uncensored-Q4_K_M.gguf (5.24 GB) with resume + byte-size verification
# ==============================================================================
set -Eeuo pipefail

on_error() {
  local line_no="$1"
  local cmd="$2"
  local exit_code="$3"
  printf '\n\033[1;31m[ERROR] setup_local_llm.sh failed at line %s (exit code %s):\033[0m\n  Command: %s\n' \
    "$line_no" "$exit_code" "$cmd" >&2
  exit "$exit_code"
}
trap 'on_error "$LINENO" "$BASH_COMMAND" "$?"' ERR

LLAMA_BUILD_TAG="b11802"
LLAMA_CUDA_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_BUILD_TAG}/llama-${LLAMA_BUILD_TAG}-bin-ubuntu-cuda-12.8-x64.tar.gz"
LLAMA_CUDART_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_BUILD_TAG}/cudart-llama-${LLAMA_BUILD_TAG}-bin-ubuntu-cuda-12.8-x64.tar.gz"
LLAMA_CPU_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_BUILD_TAG}/llama-${LLAMA_BUILD_TAG}-bin-ubuntu-x64.tar.gz"

QWEN38_URL="https://huggingface.co/0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF/resolve/main/RVN-Q3_K_M-multilingual.gguf"
QWEN38_FILE="Qwen3.8-27B-Uncensored-Q3_K_M.gguf"
QWEN38_MIN_BYTES=13000000000

QWEN35_URL="https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
QWEN35_FILE="Qwen3.5-9B-Uncensored-Q4_K_M.gguf"
QWEN35_MIN_BYTES=5500000000

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)
if [[ -n "${INSTALL_DIR:-}" ]]; then
  BASE_DIR=$(readlink -m "$INSTALL_DIR")
elif [[ "$(basename "$SCRIPT_DIR")" == "LocalLLM" ]]; then
  BASE_DIR="$SCRIPT_DIR"
else
  BASE_DIR="$SCRIPT_DIR/LocalLLM"
fi

DOWNLOAD_MODE="auto" # auto | all | 3.8 | 3.5 | none

usage() {
  cat <<'EOF'
Usage: bash setup_local_llm.sh [options]

Options:
  --all-models     Download both Qwen3.8-27B (13.3 GB) and Qwen3.5-9B (5.24 GB)
  --only-3.8       Download only Qwen3.8-27B-Uncensored-Q3_K_M.gguf
  --only-3.5       Download only Qwen3.5-9B-Uncensored-Q4_K_M.gguf
  --skip-models    Create scripts/folders and install binaries without downloading models
  --dir PATH       Target installation directory (default: ./LocalLLM or current dir)
  -h, --help       Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all-models)  DOWNLOAD_MODE="all"; shift ;;
    --only-3.8)    DOWNLOAD_MODE="3.8"; shift ;;
    --only-3.5)    DOWNLOAD_MODE="3.5"; shift ;;
    --skip-models) DOWNLOAD_MODE="none"; shift ;;
    --dir)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        printf 'Error: --dir requires a target directory path.\n' >&2
        exit 2
      fi
      BASE_DIR=$(readlink -m "$2")
      shift 2
      ;;
    --dir=*)
      BASE_DIR=$(readlink -m "${1#*=}")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

check_dependencies() {
  local missing=()
  for cmd in python3 tar awk stat sed grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing+=("curl (or wget)")
  fi
  if (( ${#missing[@]} > 0 )); then
    printf 'Error: Missing required system utilities: %s\n' "${missing[*]}" >&2
    printf 'Install them first with: sudo apt update && sudo apt install -y python3 curl wget tar coreutils gawk sed grep tio\n' >&2
    exit 1
  fi
}

fetch_stream_extract() {
  local url="$1"
  local dest_dir="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 "$url" | tar -xz --strip-components=1 -C "$dest_dir"
  else
    wget -qO- --tries=3 --timeout=20 "$url" | tar -xz --strip-components=1 -C "$dest_dir"
  fi
}

check_dependencies

printf '==============================================================\n'
printf ' Local LLM + System Agent CLI Turnkey Installer\n'
printf ' Target Directory: %s\n' "$BASE_DIR"
printf '==============================================================\n\n'

# 1. Create folder structure
mkdir -p "$BASE_DIR/bin" "$BASE_DIR/models" "$BASE_DIR/open-webui-data" \
  "$BASE_DIR/ObsidianVault/.obsidian" "$BASE_DIR/ObsidianVault/targets" \
  "$BASE_DIR/ObsidianVault/commands" "$BASE_DIR/ObsidianVault/projects" \
  "$BASE_DIR/ObsidianVault/knowledge" "$BASE_DIR/Network_Isolation" \
  "$BASE_DIR/Complimentary Scripts"

if [[ ! -f "$BASE_DIR/ObsidianVault/.obsidian/app.json" ]]; then
  cat <<'__EMBED_EOF__' > "$BASE_DIR/ObsidianVault/.obsidian/app.json"
{
  "alwaysUpdateLinks": true,
  "newFileLocation": "folder",
  "newFileFolderPath": "knowledge",
  "showUnsupportedFiles": false,
  "strictLineBreaks": false,
  "readableLineLength": true
}
__EMBED_EOF__
fi

cat <<'__EMBED_EOF__' > "$BASE_DIR/ObsidianVault/commands/curl_playbook.md"
---
title: curl_playbook
category: commands
tags: [curl, http, api, scanning]
updated: 2026-10-22
---
# Valid `curl` Command Playbook

Backlink: [[00_MEMORY_INDEX]]

## Best-Practice `curl` Flags for Local Agent Execution
- Always include `-sS` (silent progress bar, but show errors), `-k` (allow self-signed lab certs), and `-L` (follow redirects).
- Use `--max-time 15` so unresponsive hosts never hang the agent.
- For headers only:
  ```bash
  curl -sS -k -L -I --max-time 15 "https://target/path"
  ```
- For JSON APIs (`GET`):
  ```bash
  curl -sS -k -L --max-time 15 -H "Accept: application/json" "https://target/api/v1/status"
  ```
- For JSON APIs (`POST`):
  ```bash
  curl -sS -k -L --max-time 15 -X POST -H "Content-Type: application/json" -d '{"key":"value"}' "https://target/api/v1/login"
  ```
- For Form Submissions (`application/x-www-form-urlencoded`):
  ```bash
  curl -sS -k -L --max-time 15 -X POST -d "username=admin&password=foo" "https://target/login"
  ```
__EMBED_EOF__

cat <<'__EMBED_EOF__' > "$BASE_DIR/ObsidianVault/commands/tio_serial_playbook.md"
---
title: tio_serial_playbook
category: commands
summary: Non-interactive tio 3.9 Lua --script patterns for logging into and running commands on /dev/ttyUSB0 without Python scripts
tags: [tio, serial, ttyusb0, console, login]
updated: 2026-10-22
---
# `tio` Serial Console Playbook (`/dev/ttyUSB0`)

> **Summary:** Non-interactive `tio 3.9` Lua `--script` patterns for `/dev/ttyUSB0` & `/dev/ttyUSB1`  
> **Backlink:** [[00_MEMORY_INDEX]]

## Critical Rules for LLM Agent Execution
1. **NEVER write or run `python3` scripts for `/dev/ttyUSB0`.** Always use `tio`.
2. **Why plain `tio /dev/ttyUSB0` or `echo ... | tio /dev/ttyUSB0` fails in `run_shell_command`:**
   - When `stdin` is not a TTY, `tio 3.9` enters `Non-interactive mode` and exits **1 millisecond** after `stdin` hits `EOF`—before the serial device can send any reply.
3. **Solution — Always use `tio --mute --script-run once --script '<lua>' /dev/ttyUSB0`:**
   - `tio` runs the `--script` Lua commands (`write`, `expect`, `read`, `msleep`, `exit(0)`) synchronously while capturing all serial output to `stdout`, then exits cleanly when `exit(0)` is called.

---

## 1. Probe / Wake the Serial Console (See Current Prompt)
Check whether the console is at `login:`, `Password:`, or already logged in at a `#` / `>` / `$` prompt:
```bash
tio -b 115200 --mute --script-run once --script '
write("\r")
read(4096, 1500)
exit(0)
' /dev/ttyUSB0
```

---

## 2. Smart Auto-Login (Handles `login:`, Stuck `Password:`, or Already Logged In)
Note: Do **not** `expect("login:")` after sending the password, because the MOTD banner prints `Last login: ...` which contains `"login:"`. Wait for the shell prompt `(#|>|\\$)` instead:
```bash
tio -b 115200 --mute --script-run once --script '
write("\r")
local r, m = expect("([Ll]ogin:|[Uu]sername:|[Pp]assword:|#|>|\\$)", 3000)
if r == 1 and m and (string.find(m, "ogin") or string.find(m, "sername")) then
  write("USERNAME\r")
  r, m = expect("([Pp]assword:|#|>|\\$)", 3000)
end
if r == 1 and m and string.find(m, "assword") then
  write("PASSWORD\r")
  expect("(#|>|\\$)", 4000)
  while read(4096, 300) > 0 do end
end
exit(0)
' /dev/ttyUSB0
```

---

## 3. Run a Command on an Already-Logged-In Console
Send a command (always terminate with `\r`), wait for output, and drain until quiet:
```bash
tio -b 115200 --mute --script-run once --script '
write("show version\r")
while read(4096, 500) > 0 do end
exit(0)
' /dev/ttyUSB0
```

---

## 4. Login + Run Command in One Step
```bash
tio -b 115200 --mute --script-run once --script '
write("\r")
local r, m = expect("([Ll]ogin:|[Uu]sername:|[Pp]assword:|#|>|\\$)", 3000)
if r == 1 and m and (string.find(m, "ogin") or string.find(m, "sername")) then
  write("USERNAME\r")
  r, m = expect("([Pp]assword:|#|>|\\$)", 3000)
end
if r == 1 and m and string.find(m, "assword") then
  write("PASSWORD\r")
  expect("(#|>|\\$)", 4000)
  while read(4096, 300) > 0 do end
end
write("COMMAND_HERE\r")
while read(4096, 500) > 0 do end
exit(0)
' /dev/ttyUSB0
```

---

## `tio 3.9` Lua Script API Reference
- `write("text\r")` — Send string to serial port (use `\r` for Enter on serial consoles).
- `expect("regex", timeout_ms)` — Wait up to `timeout_ms` for regex match. Returns `1, matched_str` on match, `0` on timeout.
- `read(max_bytes, timeout_ms)` — Read up to `max_bytes` within `timeout_ms` (all read bytes are printed to `stdout`).
- `msleep(ms)` / `sleep(sec)` — Pause execution.
- `exit(0)` — Cleanly disconnect `tio` and return output to shell.
__EMBED_EOF__

if [[ ! -f "$BASE_DIR/ObsidianVault/00_MEMORY_INDEX.md" ]]; then
  cat <<EOF > "$BASE_DIR/ObsidianVault/00_MEMORY_INDEX.md"
# LLM Knowledge & Memory Index (\`00_MEMORY_INDEX\`)

> **Tier-1 Hot Memory:** Automatically loaded into Qwen 3.8 / 3.5 on every session. Keep entries concise; store detailed findings in topic notes under \`targets/\`, \`commands/\`, \`projects/\`, or \`knowledge/\` and link them below with \`[[WikiLinks]]\`.

## Core Facts & Environment
- LocalLLM Base Path: \`$BASE_DIR\`
- Obsidian Vault Path: \`$BASE_DIR/ObsidianVault\`
- Always use \`scan_target\` before crafting \`curl\` requests against an unfamiliar URL or host.
- **Serial Console (\`/dev/ttyUSB0\`):** NEVER use Python3 scripts for serial connections. Always use \`tio\` with \`--mute --script-run once --script '...' /dev/ttyUSB0\` (read \`[[commands/tio_serial_playbook]]\` first).
- When a working \`curl\` or \`tio\` command, endpoint, or solution is verified, save it to the vault with \`vault_save_note\`.

## Verified Commands & Playbooks
- [[commands/curl_playbook]] — Standard \`curl\` flags and patterns for reliable API/web probing without context bloat
- [[commands/tio_serial_playbook]] — Non-interactive \`tio 3.9\` Lua \`--script\` patterns for logging into and running commands on \`/dev/ttyUSB0\`

## Indexed Vault Notes
<!-- AUTO-INDEX-START -->
- [[commands/curl_playbook]] — Standard \`curl\` flags (\`-sS -k -L -i\`) and patterns for clean HTTP/API requests (#curl #http #api)
- [[commands/tio_serial_playbook]] — Non-interactive \`tio 3.9\` Lua \`--script\` patterns for logging into and running commands on \`/dev/ttyUSB0\` without Python scripts (#tio #serial #ttyusb0 #console #login)
<!-- AUTO-INDEX-END -->
EOF
fi

# Copy this installer into $BASE_DIR/setup_local_llm.sh if run from outside
if [[ "$(readlink -f "${BASH_SOURCE[0]}")" != "$BASE_DIR/setup_local_llm.sh" ]]; then
  cp -f "${BASH_SOURCE[0]}" "$BASE_DIR/setup_local_llm.sh"
  chmod +x "$BASE_DIR/setup_local_llm.sh"
fi

# 2. Generate docker-compose.yml
printf '[1/6] Generating docker-compose.yml ...\n'
cat <<'__EMBED_EOF__' > "$BASE_DIR/docker-compose.yml"
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: local-open-webui
    network_mode: host
    environment:
      - HOST=127.0.0.1
      - PORT=3000
      - ENABLE_OLLAMA_API=false
      - OPENAI_API_BASE_URL=http://127.0.0.1:8080/v1
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
__EMBED_EOF__

# 3. Generate agent-cli.py
printf '[2/6] Generating agent-cli.py (Local System Agent CLI + Obsidian Vault + Project Tracker) ...\n'
cat <<'__EMBED_EOF__' > "$BASE_DIR/agent-cli.py"
#!/usr/bin/env python3
"""
Interactive Local System Agent CLI for Qwen3.8-27B & Qwen3.5-9B (via local llama-server)
with integrated two-tier Obsidian Knowledge Vault (~/Projects/LocalLLM/ObsidianVault).

Tools provided to the LLM:
  - scan_target        : Scan a URL/API/host and auto-save the report to ObsidianVault/targets/
  - vault_save_note    : Save/update distilled knowledge, working curl commands, or project notes
                         in ObsidianVault/ and auto-index them in 00_MEMORY_INDEX.md
  - vault_search       : Search across all Markdown notes in ObsidianVault/
  - vault_read_note    : Read a specific note from ObsidianVault/ on demand
  - run_shell_command  : Execute bash/curl commands on the host system (with smart output compaction)
  - write_file         : Create or overwrite documents/scripts/files
  - edit_file          : Replace text inside an existing file
  - read_file          : Read local files
  - list_directory     : List files and folders in a directory
"""
from datetime import datetime
import html
import json
import os
import platform
import re
import readline  # Enables arrow-key history and line editing in input()
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

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
    ".conf", ".csv", ".tsv", ".xml", ".html", ".htm", ".sh", ".py", ".log", ".pdf",
}


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
            "- Always use `scan_target` before crafting `curl` requests against an unfamiliar URL or host.\n"
            "- Save verified working `curl` commands, endpoints, and solutions using `vault_save_note`.\n\n"
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
        # Replace existing line for same wiki_link or append
        updated = False
        for idx, ln in enumerate(lines):
            if f"[[{wiki_link}]]" in ln:
                lines[idx] = entry_line
                updated = True
                break
        if not updated:
            lines.append(entry_line)
        # Keep index compact (latest 35 entries)
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
        rel = md.relative_to(VAULT_DIR).with_suffix("")
        text = md.read_text(encoding="utf-8", errors="replace")
        haystack = f"{rel}\n{text}".lower()
        score = sum(1 for tok in tokens if tok in haystack)
        if not tokens or score > 0:
            # Find matching lines
            matching_lines = []
            for ln in text.splitlines():
                if any(tok in ln.lower() for tok in tokens):
                    matching_lines.append(ln.strip())
                if len(matching_lines) >= 4:
                    break
            snippet = " | ".join(matching_lines) if matching_lines else text[:200].replace("\n", " ")
            results.append((score, str(rel), snippet[:300]))

    results.sort(key=lambda x: (-x[0], x[1]))
    if not results:
        return f"No notes in ObsidianVault matched '{query}'."
    out = [f"ObsidianVault search results for '{query}' (use `vault_read_note` to read full note):"]
    for score, rel, snip in results[:12]:
        out.append(f"  - [[{rel}]]: {snip}")
    return "\n".join(out)


def read_vault_note(note_ref: str) -> str:
    ensure_vault_structure()
    cleaned = note_ref.strip().strip("[]")
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

    # Fuzzy filename match
    slug = slugify(Path(cleaned).stem)
    for md in VAULT_DIR.rglob("*.md"):
        if md.stem.lower() == slug:
            return compact_text(md.read_text(encoding="utf-8", errors="replace"), MAX_TOOL_OUTPUT_CHARS)

    return f"Note '{note_ref}' not found in {VAULT_DIR}. Try `vault_search` first."


def get_vault_context_for_prompt() -> str:
    ensure_vault_structure()
    index_text = INDEX_FILE.read_text(encoding="utf-8", errors="replace").strip()
    return compact_text(index_text, 1800)


def read_single_doc_file(path: Path, max_chars: int = 6000) -> str:
    if path.suffix.lower() == ".pdf":
        try:
            out = subprocess.check_output(
                ["pdftotext", str(path), "-"], text=True, stderr=subprocess.DEVNULL, timeout=15
            )
            return compact_text(out.strip(), max_chars)
        except Exception as exc:
            return f"(Could not extract PDF text from {path.name}: {exc})"
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
        return compact_text(raw.strip(), max_chars)
    except Exception as exc:
        return f"(Could not read {path.name}: {exc})"


def load_documentation_source(doc_source: str, max_total_chars: int = 8000) -> tuple[str, str]:
    """Load documentation from a local file, directory of files, or URL.
    Returns (derived_project_name, formatted_documentation_digest).
    """
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

    # Directory: gather readable documentation files
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


def get_live_hardware_summary() -> str:
    cpu = "Unknown CPU"
    try:
        out = subprocess.check_output(["lscpu"], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if "Model name:" in line:
                cpu = line.split(":", 1)[1].strip()
                break
    except Exception:
        pass

    ram = "Unknown RAM"
    try:
        out = subprocess.check_output(["free", "-h"], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if line.startswith("Mem:"):
                parts = line.split()
                ram = f"{parts[1]} total, {parts[6]} available"
                break
    except Exception:
        pass

    gpu = "None"
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,memory.used,memory.total,temperature.gpu", "--format=csv,noheader"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if out:
            gpu = out.splitlines()[0]
    except Exception:
        pass

    return (
        f"- Hostname: {platform.node()}\n"
        f"- User: {os.environ.get('USER', 'user')}\n"
        f"- OS: {platform.system()} {platform.release()} ({platform.machine()})\n"
        f"- CPU: {cpu}\n"
        f"- System RAM: {ram}\n"
        f"- GPU: {gpu}\n"
        f"- Active Local LLM: {MODEL_NAME} (running locally on 127.0.0.1:8080 via llama.cpp CUDA)\n"
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
        "You are a local AI system, networking & coding agent running directly on the user's Linux workstation "
        "(NOT on a cloud server). You have full, direct access to the user's hardware, operating system, "
        "network, filesystem, bash shell, and a persistent Obsidian Knowledge Vault (`ObsidianVault/`).\n\n"
        "YOUR BUILT-IN TOOLS:\n"
        "  1. `project_tracker`: Create, rename, or update an active project in `ObsidianVault/projects/<project_name>.md` "
        "(tracks documentation findings, verification questions, verified data, project plan milestones, and execution log).\n"
        "  2. `scan_target`: Inspect any URL/API/host (headers, status, endpoints, forms, JSON structure) AND "
        "auto-save the report into `ObsidianVault/targets/`. ALWAYS use `scan_target` or `vault_read_note` before "
        "crafting `curl` commands.\n"
        "  3. `vault_save_note`: Save distilled findings, verified working `curl` commands, endpoints, or project "
        "notes into `ObsidianVault/<category>/<title>.md` so you remember them across sessions without context bloat.\n"
        "  4. `vault_search`: Search your Obsidian Knowledge Vault for prior notes, targets, or commands.\n"
        "  5. `vault_read_note`: Read a specific note (e.g. `commands/curl_playbook`, `commands/tio_serial_playbook`, or `projects/...`) from the Vault.\n"
        "  6. `run_shell_command`: Execute any bash command (including `curl -sS -k -L ...` or `tio`).\n"
        "  7. `write_file` / `edit_file` / `read_file` / `list_directory`: Full local filesystem access.\n\n"
        "PEAK PERFORMANCE & MEMORY RULES:\n"
        "- NEVER say you are a cloud AI or that you cannot access local files, network targets, hardware, or commands.\n"
        "- Check the Obsidian Memory Index below first! If a target, playbook, or project is already in the Vault, read it "
        "with `vault_read_note` instead of guessing.\n"
        "- When onboarding a project from documentation: first call `project_tracker` to create the project note under "
        "`ObsidianVault/projects/`, summarize what you learned from the docs, and ask the user targeted verification questions "
        "to confirm IPs, credentials, interfaces, or goals. Whenever the user answers or a task completes, update the project "
        "note with `project_tracker`.\n\n"
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
                        "description": "Markdown bullet list of key facts, targets, IPs, ports, and user-verified data.",
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
            "description": "Read the full contents of a note from ObsidianVault (e.g. 'commands/curl_playbook' or 'targets/example_com').",
            "parameters": {
                "type": "object",
                "properties": {
                    "note": {
                        "type": "string",
                        "description": "WikiLink or relative path of the note (e.g. 'commands/curl_playbook').",
                    }
                },
                "required": ["note"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_shell_command",
            "description": "Execute a bash command (such as curl, ls, ps, etc.) on the local Linux system and return stdout/stderr.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The bash command line to execute.",
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
    """Strip bulky script/style blocks from HTML and cap length with head+tail preservation."""
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

    hdr_cmd = ["curl", "-sS", "-k", "-L", "-I", "--max-time", "15", url]
    body_cmd = ["curl", "-sS", "-k", "-L", "--max-time", "20", url]

    headers_out = ""
    try:
        headers_out = subprocess.check_output(hdr_cmd, text=True, stderr=subprocess.STDOUT, timeout=20).strip()
    except Exception as exc:
        headers_out = f"(Header probe failed: {exc})"

    body_out = ""
    try:
        body_out = subprocess.check_output(body_cmd, text=True, stderr=subprocess.STDOUT, timeout=25)
    except Exception as exc:
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


def confirm_action(action_desc: str) -> bool:
    global SKIP_PERMISSIONS
    if SKIP_PERMISSIONS:
        return True
    try:
        ans = input(f"\001\033[1;35m\002  Allow {action_desc}? [y/N/a (always)]: \001\033[0m\002").strip().lower()
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

        elif name == "run_shell_command":
            cmd = args.get("command", "")
            print(f"\n\033[1;33m[Agent Tool -> run_shell_command]\033[0m $ {cmd}", flush=True)
            if not confirm_action(f"shell command `{cmd}`"):
                print("  \033[1;31m-> Denied by user.\033[0m", flush=True)
                return "Action denied by user: shell command was not executed."
            proc = subprocess.run(
                cmd,
                shell=True,
                cwd=os.getcwd(),
                text=True,
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
    """Refresh system prompt with latest Obsidian Vault index and keep history within context budget."""
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
        # Clean up any incomplete assistant tool_calls so the next turn doesn't fail validation
        while len(messages) > 1 and messages[-1].get("role") == "tool":
            messages.pop()
        if len(messages) > 1 and messages[-1].get("role") == "assistant" and messages[-1].get("tool_calls"):
            messages.pop()
        print("\n\033[1;33m[Interrupted by Ctrl+C — stopped current task. Ready for next prompt.]\033[0m")


def start_project_onboarding(doc_source: str, custom_name: str, messages: list) -> None:
    """Read documentation from doc_source, initialize or select an Obsidian project, and trigger LLM onboarding."""
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
        "   - Key facts, IPs, hardware/interfaces, credentials, and architecture extracted from the documentation.\n"
        "   - Specific verification questions to confirm any missing, ambiguous, or environment-specific details with me.\n"
        "   - An initial phased project plan with `- [ ]` checkboxes.\n"
        "2. Present a concise summary of what you learned from the documentation and ask me your verification questions "
        "so we can confirm the data and begin executing the plan."
    )
    messages.append({"role": "user", "content": onboarding_prompt})
    run_turn(messages)
    print()


def handle_project_command(arg_str: str, messages: list) -> None:
    """Handle `/project ...` interactive commands."""
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

    # Otherwise: `/project <doc_path_or_dir> [optional_project_name]`
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
        if a == "--dangerously-skip-permissions":
            SKIP_PERMISSIONS = True
            idx += 1
        elif a == "--confirm":
            SKIP_PERMISSIONS = False
            idx += 1
        elif a in ("-P", "--project"):
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

    if len(filtered_args) > 1 and filtered_args[0] in ("-p", "--prompt"):
        prompt_text = " ".join(filtered_args[1:])
        messages.append({"role": "user", "content": prompt_text})
        run_turn(messages)
        return

    perm_status = (
        "\033[1;31mAUTO-RUN (--dangerously-skip-permissions enabled)\033[0m"
        if SKIP_PERMISSIONS
        else "\033[1;32mCONFIRM ON [y/N/a] (pass --dangerously-skip-permissions to auto-run)\033[0m"
    )

    print("\033[1;32m=== Local System Agent CLI + Obsidian Vault ===\033[0m")
    print(f"  Active Model:   \033[1m{MODEL_NAME}\033[0m")
    print(f"  Obsidian Vault: \033[1;36m{VAULT_DIR}\033[0m")
    print(f"  Working Dir:    {os.getcwd()}")
    print(f"  Permissions:    {perm_status}")
    print("  Agent Tools:    \033[1;33mproject_tracker, scan_target, vault_save_note, vault_search, vault_read_note, run_shell_command, write_file, edit_file, read_file, list_directory\033[0m")
    print("  Slash Commands: /project <doc_path> [name], /project list, /project load <name>, /scan <url>, /vault, /remember <fact>, /search <query>, /permissions, /clear, /hw, /exit")
    print("===============================================\n")

    if startup_project_doc:
        try:
            start_project_onboarding(startup_project_doc, startup_project_name, messages)
        except Exception as exc:
            print(f"\n\033[1;31m[Project Error]\033[0m {exc}\n")

    while True:
        try:
            user_input = input("\001\033[1;32m\002You>\001\033[0m\002 ").strip()
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
            print("\n" + get_live_hardware_summary() + "\n")
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
                            "Use this scan report to help me craft valid curl commands or interact with this target."
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
__EMBED_EOF__
chmod +x "$BASE_DIR/agent-cli.py"
python3 -m py_compile "$BASE_DIR/agent-cli.py"

# 4. Generate manage-llm.sh
printf '[3/6] Generating manage-llm.sh (Hardware Auto-Tuner & Service Manager) ...\n'
cat <<'__EMBED_EOF__' > "$BASE_DIR/manage-llm.sh"
#!/usr/bin/env bash
# Manage the local LLM server (llama.cpp CUDA) + Open WebUI + Local System Agent CLI.
# Supports switching between:
#   - qwen3.8 (DEFAULT): Qwen3.8-27B-Uncensored-Q3_K_M.gguf (13 GB)
#   - qwen3.5 (FAST):    Qwen3.5-9B-Uncensored-Q4_K_M.gguf (5.2 GB, HauhauCS-Aggressive)
# Dynamically auto-detects CPU topology (hybrid P/E cores), system RAM, and GPU VRAM
# to configure llama-server / Agent CLI for peak efficiency.
set -euo pipefail

BASE_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)
BIN_DIR="$BASE_DIR/bin"
MODELS_DIR="$BASE_DIR/models"
PID_FILE="$BASE_DIR/llama-server.pid"
ACTIVE_MODEL_FILE="$BASE_DIR/llama-server.model"
LOG_FILE="$BASE_DIR/llama-server.log"

HOST="${HOST:-127.0.0.1}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
WEBUI_PORT="${WEBUI_PORT:-3000}"

# Default model selection (defaults to qwen3.8 when not specified)
MODEL_SELECT="${MODEL:-qwen3.8}"
AGENT_MODE="${AGENT_MODE:-on}"
SPEC_TYPE="${SPEC_TYPE:-ngram-mod}"
# Default REASONING to 'off' so Qwen3.5/3.8 answers immediately instead of spending
# hundreds of tokens debating with itself in <think>...</think> blocks.
REASONING_MODE="${REASONING:-off}"
SKIP_PERMISSIONS="${SKIP_PERMISSIONS:-0}"

usage() {
  cat <<'EOT'
Usage: bash manage-llm.sh {start|stop|restart|status|models|tune|cli|logs} [-m MODEL] [options...]

Commands:
  start    Start llama-server (with Agent tools + auto-detected tuning) and Open WebUI
  stop     Stop llama-server and Open WebUI
  restart  Restart both services (optionally switching models with -m)
  status   Show service status, active model, auto-detected hardware profile, and GPU VRAM usage
  models   List installed models and show which model is active / default
  tune     Display the auto-detected hardware profile and exact flags without starting
  cli      Launch the interactive Local System Agent CLI with shell & file tools
  logs     Tail llama-server logs

Model Selection Switch (-m / --model or MODEL=...):
  -m qwen3.8 | 3.8 | 27b       Use Qwen3.8-27B-Uncensored-Q3_K_M.gguf [DEFAULT]
  -m qwen3.5 | 3.5 | 9b | fast Use Qwen3.5-9B-Uncensored-Q4_K_M.gguf (HauhauCS-Aggressive)
  -m /path/to/model.gguf       Use a custom GGUF model file

Reasoning / Thinking Switch:
  --no-think                       Disable internal <think> monologue for instant answers [DEFAULT]
  --think                          Enable step-by-step <think> chain-of-thought reasoning

Permissions / Confirmation & Project Switches (Agent CLI):
  --confirm                              Prompt [y/N/a] before running shell commands or file writes [DEFAULT]
  --dangerously-skip-permissions         Auto-run all shell commands and file writes without confirming
  -P, --project <doc_path_or_dir> [name] Ingest documentation file/folder, verify data with user, and create/track
                                         an Obsidian project in ObsidianVault/projects/

Environment Overrides (optional — auto-detected when omitted):
  MODEL          Model selector ('qwen3.8' [default] or 'qwen3.5')
  CTX_SIZE       Context window size in tokens (e.g. CTX_SIZE=32768)
  AGENT_MODE     Enable built-in system tools (write_file, edit_file, exec_shell_command, etc.): 'on' (default) or 'off'
  REASONING      Thinking mode: 'off' (default, instant output), 'on' (chain-of-thought), or 'auto'
  SPEC_TYPE      Speculative decoding mode (default: 'ngram-mod', set 'none' to disable)
  THREADS        Generation (decode) thread count
  THREADS_BATCH  Prompt processing (prefill) thread count
  FIT_TARGET     VRAM safety headroom in MiB per GPU (e.g. FIT_TARGET=384)

Examples:
  ./manage-llm.sh start                                           # Starts default Qwen3.8-27B
  ./manage-llm.sh start -m qwen3.5                                # Starts faster Qwen3.5-9B model
  ./manage-llm.sh cli -m 3.5                                      # Agent CLI (confirm ON by default)
  ./manage-llm.sh cli -m 3.5 --dangerously-skip-permissions       # Agent CLI (auto-run all commands)
  ./manage-llm.sh cli -m 3.8 --dangerously-skip-permissions       # Default Qwen3.8 Agent CLI (auto-run)
  ./manage-llm.sh models                                          # List installed models
EOT
}

ACTION="status"
ACTION_SET=0
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    start|stop|restart|status|models|tune|detect|cli|logs|-h|--help|help)
      if (( ACTION_SET == 0 )); then
        ACTION="$1"
        ACTION_SET=1
      else
        EXTRA_ARGS+=("$1")
      fi
      shift
      ;;
    -m|--model)
      if [[ $# -lt 2 ]]; then
        printf 'Error: %s requires a model argument (e.g. qwen3.8 or qwen3.5)\n' "$1" >&2
        exit 2
      fi
      MODEL_SELECT="$2"
      shift 2
      ;;
    --model=*)
      MODEL_SELECT="${1#*=}"
      shift
      ;;
    --think)
      REASONING_MODE="on"
      shift
      ;;
    --no-think)
      REASONING_MODE="off"
      shift
      ;;
    --dangerously-skip-permissions)
      SKIP_PERMISSIONS="1"
      shift
      ;;
    --confirm)
      SKIP_PERMISSIONS="0"
      shift
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

resolve_model() {
  local sel="${1:-$MODEL_SELECT}"
  local sel_lower
  sel_lower=$(printf '%s' "$sel" | tr '[:upper:]' '[:lower:]')

  case "$sel_lower" in
    qwen3.8|3.8|27b|qwen38|default|"")
      if [[ -f "$MODELS_DIR/Qwen3.8-27B-Uncensored-Q3_K_M.gguf" || ! -f "$MODELS_DIR/Qwen3.5-9B-Uncensored-Q4_K_M.gguf" ]]; then
        MODEL_KEY="qwen3.8"
        MODEL_ALIAS="Qwen3.8-27B-Uncensored-Q3_K_M"
        MODEL_PATH="${MODEL_PATH_OVERRIDE:-$MODELS_DIR/Qwen3.8-27B-Uncensored-Q3_K_M.gguf}"
      else
        # Fallback to 3.5 if only 3.5 is installed on a smaller laptop
        MODEL_KEY="qwen3.5"
        MODEL_ALIAS="Qwen3.5-9B-Uncensored-Q4_K_M"
        MODEL_PATH="$MODELS_DIR/Qwen3.5-9B-Uncensored-Q4_K_M.gguf"
      fi
      ;;
    qwen3.5|3.5|9b|qwen35|fast|hauhaucs)
      MODEL_KEY="qwen3.5"
      MODEL_ALIAS="Qwen3.5-9B-Uncensored-Q4_K_M"
      if [[ -f "$MODELS_DIR/Qwen3.5-9B-Uncensored-Q4_K_M.gguf" ]]; then
        MODEL_PATH="$MODELS_DIR/Qwen3.5-9B-Uncensored-Q4_K_M.gguf"
      else
        MODEL_PATH="$MODELS_DIR/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
      fi
      ;;
    *)
      if [[ -f "$sel" ]]; then
        MODEL_PATH=$(readlink -f "$sel")
      elif [[ -f "$MODELS_DIR/$sel" ]]; then
        MODEL_PATH=$(readlink -f "$MODELS_DIR/$sel")
      else
        printf 'Error: Unknown model selector "%s". Use -m qwen3.8 (default) or -m qwen3.5.\n' "$sel" >&2
        exit 2
      fi
      MODEL_ALIAS=$(basename "$MODEL_PATH" .gguf)
      MODEL_KEY="$MODEL_ALIAS"
      ;;
  esac
}

detect_hardware_and_tune() {
  resolve_model "$MODEL_SELECT"

  CPU_NAME=$(LC_ALL=C lscpu 2>/dev/null | awk -F: '/Model name:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
  CPU_NAME="${CPU_NAME:-Unknown CPU}"
  LOGICAL_CPUS=$(nproc --all 2>/dev/null || echo 4)

  if command -v lscpu >/dev/null 2>&1; then
    PHYSICAL_CORES=$(LC_ALL=C lscpu -p=CORE 2>/dev/null | grep -v '^#' | sort -u | wc -l)
    P_CORES=$(LC_ALL=C lscpu -p=CORE 2>/dev/null | grep -v '^#' | sort | uniq -c | awk '$1 > 1 {c++} END {print c+0}')
    E_CORES=$(( PHYSICAL_CORES - P_CORES ))
  else
    PHYSICAL_CORES=$(( LOGICAL_CPUS / 2 ))
    (( PHYSICAL_CORES < 1 )) && PHYSICAL_CORES=1
    P_CORES=$PHYSICAL_CORES
    E_CORES=0
  fi

  if (( P_CORES > 0 && E_CORES > 0 )); then
    AUTO_THREADS=$(( P_CORES + (E_CORES / 2) ))
  else
    AUTO_THREADS=$(( (PHYSICAL_CORES * 4 + 4) / 5 ))
  fi
  (( AUTO_THREADS < 1 )) && AUTO_THREADS=1
  AUTO_THREADS_BATCH=$PHYSICAL_CORES

  THREADS="${THREADS:-$AUTO_THREADS}"
  THREADS_BATCH="${THREADS_BATCH:-$AUTO_THREADS_BATCH}"

  TOTAL_RAM_MIB=$(awk '/MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 8192)
  AVAIL_RAM_MIB=$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 4096)
  if [[ -f "$MODEL_PATH" ]]; then
    MODEL_SIZE_MIB=$(( $(stat -Lc%s "$MODEL_PATH" 2>/dev/null || echo 0) / 1048576 ))
  else
    MODEL_SIZE_MIB=5366
  fi

  GPU_DETECTED=0
  GPU_NAME="None (CPU-only mode)"
  GPU_TOTAL_MIB=0
  GPU_FREE_MIB=0

  if command -v nvidia-smi >/dev/null 2>&1; then
    local gpu_line
    gpu_line=$(nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)
    if [[ -n "$gpu_line" ]]; then
      GPU_DETECTED=1
      GPU_NAME=$(printf '%s' "$gpu_line" | awk -F', ' '{print $1}')
      GPU_TOTAL_MIB=$(printf '%s' "$gpu_line" | awk -F', ' '{print int($2)}')
      GPU_FREE_MIB=$(printf '%s' "$gpu_line" | awk -F', ' '{print int($3)}')
    fi
  fi

  KV_CACHE_TYPE="${KV_CACHE_TYPE:-q8_0}"
  GPU_ARGS=()

  if (( GPU_DETECTED == 1 && GPU_TOTAL_MIB > 0 )); then
    if (( MODEL_SIZE_MIB <= GPU_TOTAL_MIB )); then
      AUTO_FIT_TARGET=256
    elif (( GPU_TOTAL_MIB <= 8192 )); then
      AUTO_FIT_TARGET=384
    elif (( GPU_TOTAL_MIB <= 16384 )); then
      AUTO_FIT_TARGET=512
    else
      AUTO_FIT_TARGET=768
    fi
    FIT_TARGET="${FIT_TARGET:-$AUTO_FIT_TARGET}"
    BATCH_SIZE="${BATCH_SIZE:-2048}"
    UBATCH_SIZE="${UBATCH_SIZE:-512}"
    GPU_ARGS=(
      --fit on
      --fit-target "$FIT_TARGET"
      --flash-attn on
      --cache-type-k "$KV_CACHE_TYPE"
      --cache-type-v "$KV_CACHE_TYPE"
    )
  else
    FIT_TARGET="N/A"
    BATCH_SIZE="${BATCH_SIZE:-1024}"
    UBATCH_SIZE="${UBATCH_SIZE:-256}"
    GPU_ARGS=(
      --n-gpu-layers 0
      --flash-attn on
      --cache-type-k "$KV_CACHE_TYPE"
      --cache-type-v "$KV_CACHE_TYPE"
    )
  fi

  TOTAL_POOL_MIB=$(( TOTAL_RAM_MIB + GPU_TOTAL_MIB ))
  HEADROOM_MIB=$(( TOTAL_POOL_MIB - MODEL_SIZE_MIB ))
  if (( GPU_DETECTED == 1 && MODEL_SIZE_MIB <= GPU_TOTAL_MIB )); then
    AUTO_CTX_SIZE=8192
  elif (( HEADROOM_MIB >= 18000 )); then
    AUTO_CTX_SIZE=16384
  elif (( HEADROOM_MIB >= 10000 )); then
    AUTO_CTX_SIZE=8192
  else
    AUTO_CTX_SIZE=4096
  fi
  CTX_SIZE="${CTX_SIZE:-$AUTO_CTX_SIZE}"

  FEATURE_ARGS=()
  if [[ "$SPEC_TYPE" != "none" && -n "$SPEC_TYPE" ]]; then
    FEATURE_ARGS+=(--spec-type "$SPEC_TYPE")
  fi
  if [[ "$REASONING_MODE" != "auto" && -n "$REASONING_MODE" ]]; then
    FEATURE_ARGS+=(--reasoning "$REASONING_MODE")
  fi

  SERVER_AGENT_ARGS=()
  if [[ "$AGENT_MODE" == "on" || "$AGENT_MODE" == "true" || "$AGENT_MODE" == "1" ]]; then
    SERVER_AGENT_ARGS+=(--agent --tools all)
  fi
}

print_hardware_profile() {
  detect_hardware_and_tune
  printf '=== Auto-Detected Hardware & Tuning Profile ===\n'
  if (( P_CORES > 0 && E_CORES > 0 )); then
    printf '  CPU:            %s (%d physical cores: %d P-cores + %d E-cores, %d threads)\n' \
      "$CPU_NAME" "$PHYSICAL_CORES" "$P_CORES" "$E_CORES" "$LOGICAL_CPUS"
  else
    printf '  CPU:            %s (%d physical cores, %d threads)\n' \
      "$CPU_NAME" "$PHYSICAL_CORES" "$LOGICAL_CPUS"
  fi
  printf '  System RAM:     %d MiB total (%d MiB available)\n' "$TOTAL_RAM_MIB" "$AVAIL_RAM_MIB"
  if (( GPU_DETECTED == 1 )); then
    printf '  GPU:            %s (%d MiB total, %d MiB free)\n' "$GPU_NAME" "$GPU_TOTAL_MIB" "$GPU_FREE_MIB"
  else
    printf '  GPU:            %s\n' "$GPU_NAME"
  fi
  printf '  Selected Model: %s (%d MiB -> %s)\n' "$MODEL_ALIAS" "$MODEL_SIZE_MIB" "$(basename "$MODEL_PATH")"
  printf '  Reasoning Mode: %s (default: off for instant answers; pass --think to enable <think>)\n' "$REASONING_MODE"
  printf '  Agent Tools:    %s (read_file, write_file, edit_file, exec_shell_command, grep_search, ...)\n' "$AGENT_MODE"
  printf '  Tuned Settings: --ctx-size %s --reasoning %s --threads %s --threads-batch %s --batch-size %s --ubatch-size %s --spec-type %s' \
    "$CTX_SIZE" "$REASONING_MODE" "$THREADS" "$THREADS_BATCH" "$BATCH_SIZE" "$UBATCH_SIZE" "$SPEC_TYPE"
  if (( GPU_DETECTED == 1 )); then
    printf ' --fit on --fit-target %s --flash-attn on -ctk %s -ctv %s\n' \
      "$FIT_TARGET" "$KV_CACHE_TYPE" "$KV_CACHE_TYPE"
  else
    printf ' --n-gpu-layers 0 --flash-attn on -ctk %s -ctv %s\n' \
      "$KV_CACHE_TYPE" "$KV_CACHE_TYPE"
  fi
  printf '===============================================\n'
}

is_llama_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(<"$PID_FILE")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

list_models() {
  resolve_model "$MODEL_SELECT"
  local running_model="NONE (stopped)"
  if is_llama_running && [[ -f "$ACTIVE_MODEL_FILE" ]]; then
    running_model=$(<"$ACTIVE_MODEL_FILE")
  fi
  printf '=== Installed Local LLM Models ===\n'
  printf '  1. [DEFAULT] qwen3.8 (-m 3.8) -> Qwen3.8-27B-Uncensored-Q3_K_M.gguf\n'
  if [[ -f "$MODELS_DIR/Qwen3.8-27B-Uncensored-Q3_K_M.gguf" ]]; then
    printf '     Status: Installed (%s)\n' "$(du -h "$MODELS_DIR/Qwen3.8-27B-Uncensored-Q3_K_M.gguf" | awk '{print $1}')"
  else
    printf '     Status: Missing\n'
  fi
  printf '  2. [FAST]    qwen3.5 (-m 3.5) -> Qwen3.5-9B-Uncensored-Q4_K_M.gguf (HauhauCS-Aggressive)\n'
  if [[ -f "$MODELS_DIR/Qwen3.5-9B-Uncensored-Q4_K_M.gguf" ]]; then
    printf '     Status: Installed (%s)\n' "$(du -Lh "$MODELS_DIR/Qwen3.5-9B-Uncensored-Q4_K_M.gguf" | awk '{print $1}')"
  else
    printf '     Status: Missing\n'
  fi
  printf '\n  Currently Running: %s\n' "$running_model"
  printf '==================================\n'
}

start_services() {
  detect_hardware_and_tune

  if [[ ! -f "$MODEL_PATH" ]]; then
    printf 'Error: Model file not found at %s\n' "$MODEL_PATH" >&2
    exit 1
  fi

  print_hardware_profile

  if is_llama_running; then
    printf 'llama-server is already running (PID %s, Model: %s). Use "./manage-llm.sh restart -m %s" to switch models.\n' \
      "$(<"$PID_FILE")" "$(cat "$ACTIVE_MODEL_FILE" 2>/dev/null || echo unknown)" "$MODEL_KEY"
  else
    printf 'Starting llama-server (%s) on http://%s:%s ...\n' "$MODEL_ALIAS" "$HOST" "$LLAMA_PORT"
    export LD_LIBRARY_PATH="$BIN_DIR:${LD_LIBRARY_PATH:-}"
    nohup "$BIN_DIR/llama-server" \
      --model "$MODEL_PATH" \
      --alias "$MODEL_ALIAS" \
      --host "$HOST" \
      --port "$LLAMA_PORT" \
      --ctx-size "$CTX_SIZE" \
      --parallel 1 \
      --context-shift \
      --no-reasoning-preserve \
      "${GPU_ARGS[@]}" \
      "${FEATURE_ARGS[@]}" \
      "${SERVER_AGENT_ARGS[@]}" \
      --threads "$THREADS" \
      --threads-batch "$THREADS_BATCH" \
      --batch-size "$BATCH_SIZE" \
      --ubatch-size "$UBATCH_SIZE" \
      --cont-batching \
      --webui \
      "${EXTRA_ARGS[@]}" \
      > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "$MODEL_ALIAS ($(basename "$MODEL_PATH"))" > "$ACTIVE_MODEL_FILE"
    printf 'llama-server started (PID %s, Model: %s). Waiting for model load...\n' "$(<"$PID_FILE")" "$MODEL_ALIAS"
  fi

  if command -v docker >/dev/null 2>&1; then
    printf 'Starting Open WebUI container on http://%s:%s (Default Model: %s) ...\n' "$HOST" "$WEBUI_PORT" "$MODEL_ALIAS"
    (cd "$BASE_DIR" && ACTIVE_MODEL_ALIAS="$MODEL_ALIAS" docker compose up -d)
  fi
}

run_cli() {
  detect_hardware_and_tune
  if [[ ! -f "$MODEL_PATH" ]]; then
    printf 'Error: Model file not found at %s\n' "$MODEL_PATH" >&2
    exit 1
  fi

  pkill -f "$BIN_DIR/llama-cli" 2>/dev/null || true

  local current_active=""
  if [[ -f "$ACTIVE_MODEL_FILE" ]]; then
    current_active=$(<"$ACTIVE_MODEL_FILE")
  fi

  if ! is_llama_running || [[ "$current_active" != "$MODEL_ALIAS"* ]]; then
    if is_llama_running; then
      printf 'Switching running llama-server to %s ...\n' "$MODEL_ALIAS"
      kill "$(<"$PID_FILE")" 2>/dev/null || true
      rm -f "$PID_FILE" "$ACTIVE_MODEL_FILE"
      sleep 1
    fi
    print_hardware_profile
    printf 'Starting local llama-server backend (%s) on http://%s:%s ...\n' "$MODEL_ALIAS" "$HOST" "$LLAMA_PORT"
    export LD_LIBRARY_PATH="$BIN_DIR:${LD_LIBRARY_PATH:-}"
    nohup "$BIN_DIR/llama-server" \
      --model "$MODEL_PATH" \
      --alias "$MODEL_ALIAS" \
      --host "$HOST" \
      --port "$LLAMA_PORT" \
      --ctx-size "$CTX_SIZE" \
      --parallel 1 \
      --context-shift \
      --no-reasoning-preserve \
      "${GPU_ARGS[@]}" \
      "${FEATURE_ARGS[@]}" \
      "${SERVER_AGENT_ARGS[@]}" \
      --threads "$THREADS" \
      --threads-batch "$THREADS_BATCH" \
      --batch-size "$BATCH_SIZE" \
      --ubatch-size "$UBATCH_SIZE" \
      --cont-batching \
      --webui \
      > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "$MODEL_ALIAS ($(basename "$MODEL_PATH"))" > "$ACTIVE_MODEL_FILE"
  else
    print_hardware_profile
  fi

  printf 'Waiting for %s backend to become ready ' "$MODEL_ALIAS"
  local ready=0
  for _ in {1..90}; do
    if ! is_llama_running; then
      printf '\nError: llama-server exited during startup. Last log lines:\n' >&2
      tail -n 20 "$LOG_FILE" >&2
      exit 1
    fi
    if curl -sf "http://$HOST:$LLAMA_PORT/health" 2>/dev/null | grep -q '"ok"'; then
      ready=1
      break
    fi
    printf '.'
    sleep 1
  done
  printf '\n'
  if (( ready == 0 )); then
    printf 'Error: Timed out waiting for llama-server on http://%s:%s\n' "$HOST" "$LLAMA_PORT" >&2
    exit 1
  fi

  export LLAMA_API_URL="http://$HOST:$LLAMA_PORT/v1/chat/completions"
  export MODEL_ALIAS="$MODEL_ALIAS"
  export SKIP_PERMISSIONS="$SKIP_PERMISSIONS"
  exec python3 "$BASE_DIR/agent-cli.py" "${EXTRA_ARGS[@]}"
}

stop_services() {
  if is_llama_running; then
    local pid
    pid=$(<"$PID_FILE")
    printf 'Stopping llama-server (PID %s)...\n' "$pid"
    kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE" "$ACTIVE_MODEL_FILE"
  else
    printf 'llama-server is not running.\n'
    rm -f "$PID_FILE" "$ACTIVE_MODEL_FILE"
  fi

  if command -v docker >/dev/null 2>&1 && [[ -f "$BASE_DIR/docker-compose.yml" ]]; then
    printf 'Stopping Open WebUI container...\n'
    (cd "$BASE_DIR" && docker compose down)
  fi
}

status_services() {
  print_hardware_profile
  printf '\nService Status:\n'
  if is_llama_running; then
    local active_mod
    active_mod=$(cat "$ACTIVE_MODEL_FILE" 2>/dev/null || echo "$MODEL_ALIAS")
    printf '  llama-server: RUNNING (PID %s)\n' "$(<"$PID_FILE")"
    printf '  Active Model: %s\n' "$active_mod"
    printf '  Agent WebUI:  http://%s:%s (Built-in fast WebUI with host Agent tools & OpenAI API)\n' "$HOST" "$LLAMA_PORT"
  else
    printf '  llama-server: STOPPED\n'
  fi
  if command -v docker >/dev/null 2>&1; then
    if docker ps --format '{{.Names}}' | grep -q '^local-open-webui$'; then
      printf '  Open WebUI:   RUNNING -> http://%s:%s\n' "$HOST" "$WEBUI_PORT"
    else
      printf '  Open WebUI:   STOPPED\n'
    fi
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    printf '\nGPU Memory Usage:\n'
    nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total,utilization.gpu --format=csv
  fi
}

case "$ACTION" in
  start)          start_services ;;
  stop)           stop_services ;;
  restart)        stop_services; sleep 1; start_services ;;
  status)         status_services ;;
  models)         list_models ;;
  tune|detect)    print_hardware_profile ;;
  cli)            run_cli ;;
  logs)           tail -n 50 -f "$LOG_FILE" ;;
  -h|--help|help) usage ;;
  *)              usage >&2; exit 2 ;;
esac
__EMBED_EOF__
chmod +x "$BASE_DIR/manage-llm.sh"
bash -n "$BASE_DIR/manage-llm.sh"

# 5. Generate Documentation, Network Isolation Scripts, and Complimentary Scripts
printf '[4/6] Generating documentation, Network_Isolation/, and Complimentary Scripts/ ...\n'
cat <<'__EMBED_EOF__' > "$BASE_DIR/LocalLLM_RunCMDs.md"
# Local LLM Guide (`Qwen3.8-27B` [Default] & `Qwen3.5-9B` [Fast])

This setup runs your local uncensored GGUF models using **`llama-server` (CUDA)**, **`agent-cli.py`**, and **Open WebUI**, with automatic hardware resource detection and **Local System Agent Tools** (`run_shell_command`, `write_file`, `edit_file`, `read_file`, `list_directory`) so the LLM can create documents, edit code, and interact directly with your system.

---

## 0. One-Click Lab Replication (`setup_local_llm.sh`)

To duplicate this entire setup onto another Linux laptop in your lab, copy **`setup_local_llm.sh`** to the new machine and run:

```bash
bash setup_local_llm.sh
```

It automatically creates the folder structure (`bin/`, `models/`, `open-webui-data/`), generates `manage-llm.sh`, `agent-cli.py`, `docker-compose.yml`, and `README.md`, downloads & extracts the `llama.cpp` CUDA (or CPU) binaries, and downloads both `Qwen3.8-27B` and `Qwen3.5-9B`.

---

## 1. Installed Models & Model Switch (`-m`)

Both models are stored side-by-side in `models/`. **If you do not specify `-m`, the script always defaults to `Qwen3.8-27B-Uncensored-Q3_K_M`.**

| Selector (`-m`) | Model File | Size | Speed on RTX A1000 (6 GB) | Best For |
| :--- | :--- | :--- | :--- | :--- |
| **`-m 3.8`** *(Default)*<br>*(or `qwen3.8`, `27b`)* | `Qwen3.8-27B-Uncensored-Q3_K_M.gguf` | **13 GB** | ~5 – 9 t/s *(CPU+GPU hybrid + N-gram spec)* | Maximum coding & deep reasoning quality |
| **`-m 3.5`** *(Fast)*<br>*(or `qwen3.5`, `9b`, `fast`)* | `Qwen3.5-9B-Uncensored-Q4_K_M.gguf`<br>*(HauhauCS-Aggressive)* | **5.24 GB** | **~35 – 55 t/s** *(~95–100% in GPU VRAM)* | Fast interactive coding, chat, and document creation |

---

## 2. Quick Start / Switch / Stop / Status Commands

```bash
cd ~/Projects/LocalLLM

# Launch interactive Local System Agent CLI (CONFIRM ON by default):
./manage-llm.sh cli -m 3.5
./manage-llm.sh cli -m 3.8

# Launch Local System Agent CLI with AUTO-RUN enabled (no confirmation prompts):
./manage-llm.sh cli -m 3.5 --dangerously-skip-permissions
./manage-llm.sh cli --dangerously-skip-permissions

# Launch Agent CLI pointing at project documentation to ingest, verify, and track in ObsidianVault/projects/:
./manage-llm.sh cli -m 3.5 --project /path/to/docs_or_file
./manage-llm.sh cli -m 3.8 --project /path/to/docs_or_file my_project_name

# Start background server + Open WebUI with DEFAULT model (Qwen3.8-27B):
./manage-llm.sh start

# Start or switch background server to FAST model (Qwen3.5-9B):
./manage-llm.sh restart -m 3.5

# List installed models and see which one is currently running:
./manage-llm.sh models

# Check status, active model, auto-detected hardware profile, and GPU VRAM usage:
./manage-llm.sh status

# Inspect auto-detected hardware resources & flags without starting (dry run):
./manage-llm.sh tune
./manage-llm.sh tune -m 3.5

# Stop all services and free all RAM/VRAM:
./manage-llm.sh stop
```

---

## 3. Local System Agent CLI & Permission Controls

When you run **`./manage-llm.sh cli`**, [`agent-cli.py`](./agent-cli.py) injects a live hardware/OS snapshot and gives the LLM 5 local tools:
* **`run_shell_command`:** Executes bash commands on your workstation and returns `stdout`/`stderr`.
* **`write_file`:** Creates new documents, scripts, or markdown files on disk.
* **`edit_file`:** Modifies existing files in place.
* **`read_file`:** Reads local files.
* **`list_directory`:** Lists files and folders in any directory.

### Confirmation Modes
* **Default (`--confirm`):** Prompts `Allow ...? [y/N/a (always)]:` before running any shell command or writing/editing files.
* **Auto-Run (`--dangerously-skip-permissions`):** Executes all shell commands and file operations automatically without prompting.
* **In-Session Toggle:** Type `/permissions` inside the CLI at any time to switch between `CONFIRM ON` and `AUTO-RUN`.

### Project Onboarding & Tracking (`--project` / `/project`)
* **Start from CLI:** `./manage-llm.sh cli -m 3.5 --project /path/to/doc_or_folder [optional_project_name]`
* **Start inside CLI:** `/project /path/to/doc_or_folder [optional_project_name]`
* **List or Resume Projects:** `/project list` or `/project load <project_name>`
* **How it works:** Reads the file, folder of docs (`.md`, `.txt`, `.json`, `.yaml`, `.pdf`, etc.), or URL, calls `project_tracker` to create `ObsidianVault/projects/<project_name>.md` (and indexes it in `00_MEMORY_INDEX.md`), summarizes the extracted data, asks you verification questions, and tracks the project plan (`- [ ]` / `- [x]`) as you work.

---

## 4. Reasoning / Thinking Mode (`--no-think` [Default] vs `--think`)

To ensure responses start **immediately** without a long internal `<think>...</think>` monologue, `manage-llm.sh` defaults to **`--reasoning off` (`--no-think`)**.
To enable step-by-step `<think>` reasoning for complex problems, pass `--think`:

```bash
./manage-llm.sh cli -m 3.5 --think
./manage-llm.sh restart -m 3.8 --think
```
__EMBED_EOF__
cp -f "$BASE_DIR/LocalLLM_RunCMDs.md" "$BASE_DIR/README.md"

cat <<'__EMBED_EOF__' > "$BASE_DIR/SetupReadMe.md"
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
__EMBED_EOF__

cat <<'__EMBED_EOF__' > "$BASE_DIR/Network_Isolation/LLM_IsolationOptions.md"
# LocalLLM Network Isolation Options (`LLM_IsolationOptions.md`)

To guarantee that your LocalLLM setup (`llama-server`, `agent-cli.py`, and Open WebUI) can never send or receive data over the broader internet once installed—while still functioning normally on your local machine or an isolated lab network—you can enforce isolation at four different layers of the Linux operating system.

---

## 1. Loopback-Only Binding (Inbound Protection)
* **How it works:** The LLM server (`127.0.0.1:8080`) and Open WebUI (`127.0.0.1:3000`) are bound strictly to the local loopback address (`127.0.0.1`) rather than all interfaces (`0.0.0.0`).
* **What it prevents:** The Linux kernel will only accept connections originating from inside your own laptop. Nothing on your Wi-Fi, LAN, or the internet can connect inward to those ports.
* **Limitation:** Binding to `127.0.0.1` stops *inbound* connections, but by itself it does not stop a local process (or a shell command triggered by the agent) from initiating an *outbound* connection to the internet. For outbound guarantees, use one of the kernel-level controls below.

---

## 2. Linux Network Namespaces (Total Air-Gap for the Process)
* **Implemented by:** [`LLM_NetworkNamespaceSetup.sh`](./LLM_NetworkNamespaceSetup.sh)
* **How it works:** Linux allows you to start the LLM server and CLI inside a private **network namespace** (`ip netns` / `unshare`). Inside this namespace, the only network adapter that exists by default is a virtual loopback interface (`lo` / `127.0.0.1`)—your Wi-Fi card, WAN interfaces, and default internet gateway are completely invisible to the LLM and any child shell commands it spawns.
* **Why it is ideal for Local LLMs:**
  * The CLI and `llama-server` can still communicate with each other over `127.0.0.1:8080`.
  * The LLM still has full access to your local filesystem, Obsidian Vault, USB serial consoles (`/dev/ttyUSB0`, `/dev/ttyUSB1`), CPU, and NVIDIA GPU (since GPU access happens through `/dev/nvidia*` device files, not the network stack).
  * Even if the LLM attempts to run `curl`, `wget`, or a Python script to reach an external IP address or DNS server, the kernel immediately returns `Network is unreachable` because no route to the internet exists in that namespace.

---

## 3. Host Firewall Filtering by Group & Interface (`iptables` / `ip6tables`)
* **Implemented by:** [`LLM_NetworkIsolationSetup.sh`](./LLM_NetworkIsolationSetup.sh)
* **How it works:** If you want the LLM Agent CLI to communicate **only** over specific local lab interfaces (`eth0`, `eth1`, `eth2`), local loopback (`lo`), and local USB serial consoles (`/dev/ttyUSB0`, `/dev/ttyUSB1` / `/dev/tty/usb0`, `/dev/tty/usb1`) while strictly blocking all internet-facing interfaces (such as Wi-Fi `wlan0`, WAN gateways, or VPN/tunnel interfaces):
  * **Group-Based Firewalling (`-m owner --gid-owner llm-local`):** A dedicated Linux group (`llm-local`) is created, and the LLM processes are launched under that primary group (`sg llm-local -c ...`).
  * **Strict Interface Whitelist:** In the Linux kernel firewall (`OUTPUT` chain), packets originating from `--gid-owner llm-local` are explicitly allowed **only** on `lo`, `eth0`, `eth1`, and `eth2`, and **rejected/dropped on all other interfaces** (both IPv4 and IPv6).
  * **USB Console Access:** The script also grants read/write ACLs on `/dev/ttyUSB0`, `/dev/ttyUSB1`, `/dev/tty/usb0`, and `/dev/tty/usb1` to the `llm-local` group so the LLM can interact with local serial consoles while remaining blocked from the internet.

---

## 4. Systemd Cgroup IP Sandboxing (`IPAddressDeny`)
* **How it works:** If you run the LLM service under `systemd`, `systemd` can attach a kernel eBPF socket filter to the service's control group (cgroup).
* **Configuration concept:** You set the service policy to **Deny All IP Addresses** (`IPAddressDeny=any`) and explicitly **Allow Only `localhost`** (and optionally your local lab subnet).
* **What it guarantees:** Every process inside that service—including `llama-server`, `agent-cli.py`, and any bash command spawned by the agent—is governed by the same cgroup filter. Any attempt to open a socket to a public internet IP is blocked inside the kernel before a single packet can be transmitted.

---

## Summary: Which Script to Use

| Script | Best Use Case | What Is Allowed | What Is Blocked |
| :--- | :--- | :--- | :--- |
| **[`LLM_NetworkIsolationSetup.sh`](./LLM_NetworkIsolationSetup.sh)** | Interacting with local lab hardware over `eth0`, `eth1`, `eth2` and USB serial consoles (`/dev/tty/usb0`, `/dev/tty/usb1`) | `lo` (`127.0.0.1`), `eth0`, `eth1`, `eth2`, `/dev/ttyUSB0..1` (`/dev/tty/usb0..1`), local files & GPU | Wi-Fi (`wlan0`/`wlp*`), WAN interfaces, VPNs, and all broader internet traffic |
| **[`LLM_NetworkNamespaceSetup.sh`](./LLM_NetworkNamespaceSetup.sh)** | Complete network air-gap (100% offline local coding, file analysis, and USB serial access) | `lo` (`127.0.0.1`), local files, GPU, and `/dev/*` devices | **All** external network interfaces (`Network is unreachable`) |
__EMBED_EOF__

cat <<'__EMBED_EOF__' > "$BASE_DIR/Network_Isolation/LLM_NetworkIsolationSetup.sh"
#!/usr/bin/env bash
# ==============================================================================
# LLM_NetworkIsolationSetup.sh — Group-Based Firewall & USB Console Isolation
# ==============================================================================
# Isolates the LocalLLM server and Agent CLI using Linux Group-Based Firewalling
# (iptables / ip6tables owner module) and udev/ACL device rules so that processes
# running under the `llm-local` group can ONLY communicate over:
#   - Loopback:     lo (127.0.0.1 / ::1 for local llama-server <-> CLI/WebUI)
#   - Lab Ethernet: eth0, eth1, eth2
#   - USB Consoles: /dev/tty/usb0, /dev/tty/usb1 (and /dev/ttyUSB0, /dev/ttyUSB1)
# All other interfaces (Wi-Fi wlan0/wlp*, WAN uplinks, VPNs, broader internet)
# are strictly blocked at the Linux kernel packet filter level.
#
# ------------------------------------------------------------------------------
# SWITCHES & OPTIONS:
#   --setup, setup       Create the `llm-local` group, add current user to
#                        `llm-local` & `dialout`, configure USB serial console
#                        permissions/udev rules (/dev/tty/usb0 & /dev/tty/usb1),
#                        and apply iptables/ip6tables OUTPUT rules restricting
#                        `llm-local` to lo, eth0, eth1, and eth2.
#
#   --remove, remove     Remove all `LLM_ISOLATION` iptables/ip6tables firewall
#                        rules and remove the USB console udev rule.
#
#   --status, status     Display current `llm-local` group membership, active
#                        `LLM_ISOLATION` firewall rules, and USB console device
#                        status.
#
#   --run, run <cmd...>  Execute a command (such as `./manage-llm.sh cli` or
#                        `./manage-llm.sh start`) inside the `llm-local` group
#                        so all LLM and child shell processes are bound by the
#                        firewall isolation rules.
#
#   -h, --help, help     Show this header documentation and exit.
#
# ------------------------------------------------------------------------------
# EXAMPLES:
#   1. Apply Group-Based Firewall & USB Console isolation (requires sudo):
#        sudo ./LLM_NetworkIsolationSetup.sh --setup
#
#   2. Check active firewall isolation rules and USB console permissions:
#        sudo ./LLM_NetworkIsolationSetup.sh --status
#
#   3. Launch the LocalLLM Agent CLI inside the isolated `llm-local` group:
#        ./LLM_NetworkIsolationSetup.sh --run ./manage-llm.sh cli -m 3.5
#        ./LLM_NetworkIsolationSetup.sh --run ./manage-llm.sh cli -m 3.8 --dangerously-skip-permissions
#
#   4. Test that internet access is blocked while local eth0/1/2 & lo work:
#        ./LLM_NetworkIsolationSetup.sh --run curl -I https://1.1.1.1
#        (Returns: curl: (7) Failed to connect ... Network is unreachable / Connection refused)
#
#   5. Remove all isolation firewall rules and restore normal access:
#        sudo ./LLM_NetworkIsolationSetup.sh --remove
# ==============================================================================
set -euo pipefail

LLM_GROUP="llm-local"
CHAIN_NAME="LLM_ISOLATION"
ALLOWED_IFACES=("lo" "eth0" "eth1" "eth2")
USB_DEVICES=("/dev/ttyUSB0" "/dev/ttyUSB1")
UDEV_RULE_FILE="/etc/udev/rules.d/99-llm-usb-console.rules"
TARGET_USER="${SUDO_USER:-$USER}"

show_help() {
  sed -n '2,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    printf 'Re-running with sudo for kernel firewall / group configuration...\n'
    exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
  fi
}

setup_isolation() {
  require_root "--setup"

  printf '=== Setting Up LocalLLM Group-Based Firewall & USB Isolation ===\n'

  # 1. Create dedicated group and add user
  if ! getent group "$LLM_GROUP" >/dev/null 2>&1; then
    groupadd -f "$LLM_GROUP"
    printf '  [+] Created group: %s\n' "$LLM_GROUP"
  else
    printf '  [=] Group already exists: %s\n' "$LLM_GROUP"
  fi

  usermod -aG "$LLM_GROUP" "$TARGET_USER"
  if getent group dialout >/dev/null 2>&1; then
    usermod -aG dialout "$TARGET_USER"
  fi
  printf '  [+] Added user "%s" to group "%s" (and "dialout")\n' "$TARGET_USER" "$LLM_GROUP"

  # 2. Configure USB Console permissions & udev rules (/dev/ttyUSB0, /dev/ttyUSB1)
  for dev in "${USB_DEVICES[@]}"; do
    if [[ -e "$dev" ]]; then
      chgrp "$LLM_GROUP" "$dev" 2>/dev/null || true
      chmod 0660 "$dev" 2>/dev/null || true
      if command -v setfacl >/dev/null 2>&1; then
        setfacl -m "g:${LLM_GROUP}:rw" "$dev" 2>/dev/null || true
        setfacl -m "u:${TARGET_USER}:rw" "$dev" 2>/dev/null || true
      fi
      printf '  [+] Granted %s & %s read/write access on USB console: %s\n' "$LLM_GROUP" "$TARGET_USER" "$dev"
    fi
  done

  cat <<EOF > "$UDEV_RULE_FILE"
# Grant llm-local group read/write access to USB serial consoles
KERNEL=="ttyUSB[01]", GROUP="${LLM_GROUP}", MODE="0666"
EOF
  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=tty 2>/dev/null || true
  fi
  printf '  [+] Installed persistent udev rule: %s\n' "$UDEV_RULE_FILE"

  # 3. Apply IPv4 iptables rules for group llm-local
  iptables -D OUTPUT -m owner --gid-owner "$LLM_GROUP" -j "$CHAIN_NAME" 2>/dev/null || true
  iptables -F "$CHAIN_NAME" 2>/dev/null || iptables -N "$CHAIN_NAME"

  for iface in "${ALLOWED_IFACES[@]}"; do
    iptables -A "$CHAIN_NAME" -o "$iface" -j ACCEPT
  done
  iptables -A "$CHAIN_NAME" -j REJECT --reject-with icmp-net-unreachable
  iptables -I OUTPUT 1 -m owner --gid-owner "$LLM_GROUP" -j "$CHAIN_NAME"
  printf '  [+] Applied IPv4 iptables OUTPUT rules (Allowed: %s | Blocked: all other interfaces)\n' "${ALLOWED_IFACES[*]}"

  # 4. Apply IPv6 ip6tables rules for group llm-local
  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -D OUTPUT -m owner --gid-owner "$LLM_GROUP" -j "$CHAIN_NAME" 2>/dev/null || true
    ip6tables -F "$CHAIN_NAME" 2>/dev/null || ip6tables -N "$CHAIN_NAME"

    for iface in "${ALLOWED_IFACES[@]}"; do
      ip6tables -A "$CHAIN_NAME" -o "$iface" -j ACCEPT
    done
    ip6tables -A "$CHAIN_NAME" -j REJECT --reject-with icmp6-no-route
    ip6tables -I OUTPUT 1 -m owner --gid-owner "$LLM_GROUP" -j "$CHAIN_NAME"
    printf '  [+] Applied IPv6 ip6tables OUTPUT rules (Allowed: %s | Blocked: all other interfaces)\n' "${ALLOWED_IFACES[*]}"
  fi

  printf '================================================================\n'
  printf 'Setup complete! Run LocalLLM inside the isolated group with:\n'
  printf '  ./LLM_NetworkIsolationSetup.sh --run ./manage-llm.sh cli -m 3.5\n'
}

remove_isolation() {
  require_root "--remove"

  printf '=== Removing LocalLLM Group-Based Firewall & USB Isolation ===\n'

  while iptables -D OUTPUT -m owner --gid-owner "$LLM_GROUP" -j "$CHAIN_NAME" 2>/dev/null; do :; done
  iptables -F "$CHAIN_NAME" 2>/dev/null || true
  iptables -X "$CHAIN_NAME" 2>/dev/null || true
  printf '  [-] Removed IPv4 iptables chain: %s\n' "$CHAIN_NAME"

  if command -v ip6tables >/dev/null 2>&1; then
    while ip6tables -D OUTPUT -m owner --gid-owner "$LLM_GROUP" -j "$CHAIN_NAME" 2>/dev/null; do :; done
    ip6tables -F "$CHAIN_NAME" 2>/dev/null || true
    ip6tables -X "$CHAIN_NAME" 2>/dev/null || true
    printf '  [-] Removed IPv6 ip6tables chain: %s\n' "$CHAIN_NAME"
  fi

  if [[ -f "$UDEV_RULE_FILE" ]]; then
    rm -f "$UDEV_RULE_FILE"
    if command -v udevadm >/dev/null 2>&1; then
      udevadm control --reload-rules 2>/dev/null || true
    fi
    printf '  [-] Removed udev rule: %s\n' "$UDEV_RULE_FILE"
  fi

  printf '==============================================================\n'
  printf 'Isolation rules removed.\n'
}

status_isolation() {
  printf '=== LocalLLM Group-Based Firewall Isolation Status ===\n'
  if getent group "$LLM_GROUP" >/dev/null 2>&1; then
    printf '  Group (%s): PRESENT (%s)\n' "$LLM_GROUP" "$(getent group "$LLM_GROUP")"
  else
    printf '  Group (%s): NOT CREATED\n' "$LLM_GROUP"
  fi

  printf '\n  USB Console Devices:\n'
  for dev in "${USB_DEVICES[@]}"; do
    if [[ -e "$dev" ]]; then
      printf '    [PRESENT] %s -> %s\n' "$dev" "$(ls -l "$dev")"
    else
      printf '    [ABSENT]  %s (will be auto-configured by udev when plugged in)\n' "$dev"
    fi
  done

  printf '\n  IPv4 Firewall Rules (%s):\n' "$CHAIN_NAME"
  if sudo -n iptables -L "$CHAIN_NAME" -n -v 2>/dev/null; then
    :
  elif [[ $EUID -eq 0 ]]; then
    iptables -L "$CHAIN_NAME" -n -v 2>/dev/null || printf '    (Chain %s is not active)\n' "$CHAIN_NAME"
  else
    printf '    (Run "sudo ./LLM_NetworkIsolationSetup.sh --status" to inspect kernel iptables counters)\n'
  fi
  printf '======================================================\n'
}

run_in_isolated_group() {
  if [[ $# -eq 0 ]]; then
    printf 'Error: --run requires a command (e.g. ./LLM_NetworkIsolationSetup.sh --run ./manage-llm.sh cli -m 3.5)\n' >&2
    exit 2
  fi
  if ! getent group "$LLM_GROUP" >/dev/null 2>&1; then
    printf 'Error: Group "%s" does not exist yet. Run "sudo ./LLM_NetworkIsolationSetup.sh --setup" first.\n' "$LLM_GROUP" >&2
    exit 1
  fi
  local quoted_cmd
  printf -v quoted_cmd '%q ' "$@"
  exec sg "$LLM_GROUP" -c "$quoted_cmd"
}

case "${1:---help}" in
  --setup|setup)
    setup_isolation
    ;;
  --remove|remove|--teardown|teardown)
    remove_isolation
    ;;
  --status|status)
    status_isolation
    ;;
  --run|run)
    shift
    run_in_isolated_group "$@"
    ;;
  -h|--help|help)
    show_help
    ;;
  *)
    printf 'Unknown switch: %s\n\n' "$1" >&2
    show_help >&2
    exit 2
    ;;
esac
__EMBED_EOF__
chmod +x "$BASE_DIR/Network_Isolation/LLM_NetworkIsolationSetup.sh"
bash -n "$BASE_DIR/Network_Isolation/LLM_NetworkIsolationSetup.sh"

cat <<'__EMBED_EOF__' > "$BASE_DIR/Network_Isolation/LLM_NetworkNamespaceSetup.sh"
#!/usr/bin/env bash
# ==============================================================================
# LLM_NetworkNamespaceSetup.sh — Air-Gapped Linux Network Namespace for LocalLLM
# ==============================================================================
# Creates and manages a dedicated Linux Network Namespace (`llm-isolated`) that
# contains ONLY a private virtual loopback adapter (`lo` -> 127.0.0.1).
#
# Inside this namespace:
#   - No Ethernet, Wi-Fi, WAN, or VPN network interfaces exist.
#   - No default gateway or external routing table exists.
#   - `llama-server` and `agent-cli.py` communicate normally over 127.0.0.1:8080.
#   - Full access to local files, ObsidianVault, CPU, NVIDIA GPU (/dev/nvidia*),
#     and local USB serial devices (/dev/ttyUSB*, /dev/tty/usb*) is preserved.
#   - Any outbound internet connection attempt immediately fails with:
#     "Network is unreachable".
#
# ------------------------------------------------------------------------------
# SWITCHES & OPTIONS:
#   --setup, setup       Create the persistent `llm-isolated` network namespace
#                        and bring up its internal loopback (`lo` 127.0.0.1)
#                        interface with zero external network interfaces.
#
#   --remove, remove     Terminate any processes still running inside
#                        `llm-isolated` and delete the network namespace.
#
#   --status, status     Show whether `llm-isolated` is active, inspect its
#                        interfaces/routes, and list any processes inside it.
#
#   --run, run <cmd...>  Execute a command (such as `./manage-llm.sh cli -m 3.5`)
#                        inside the air-gapped `llm-isolated` namespace as your
#                        normal user account.
#
#   --unshare <cmd...>   Run a command in an ephemeral rootless network namespace
#                        (`unshare -r -n`) without requiring sudo or prior setup.
#
#   -h, --help, help     Show this header documentation and exit.
#
# ------------------------------------------------------------------------------
# EXAMPLES:
#   1. Create and initialize the `llm-isolated` network namespace:
#        sudo ./LLM_NetworkNamespaceSetup.sh --setup
#
#   2. Check namespace status, interfaces, and running processes:
#        sudo ./LLM_NetworkNamespaceSetup.sh --status
#
#   3. Run the LocalLLM Agent CLI inside the air-gapped namespace:
#        sudo ./LLM_NetworkNamespaceSetup.sh --run ./manage-llm.sh cli -m 3.5
#        sudo ./LLM_NetworkNamespaceSetup.sh --run ./manage-llm.sh cli -m 3.8 --dangerously-skip-permissions
#
#   4. Verify that external internet access is completely unreachable:
#        sudo ./LLM_NetworkNamespaceSetup.sh --run curl -I https://1.1.1.1
#        (Output: curl: (7) Failed to connect to 1.1.1.1 port 443: Network is unreachable)
#
#   5. Tear down and remove the `llm-isolated` network namespace:
#        sudo ./LLM_NetworkNamespaceSetup.sh --remove
# ==============================================================================
set -euo pipefail

NS_NAME="llm-isolated"
TARGET_USER="${SUDO_USER:-$USER}"
BASE_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)

show_help() {
  sed -n '2,57p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    printf 'Re-running with sudo for Linux network namespace management...\n'
    exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
  fi
}

ns_exists() {
  ip netns list 2>/dev/null | awk '{print $1}' | grep -qx "$NS_NAME"
}

setup_namespace() {
  require_root "--setup"

  printf '=== Setting Up Air-Gapped Linux Network Namespace (%s) ===\n' "$NS_NAME"
  if ns_exists; then
    printf '  [=] Network namespace "%s" already exists.\n' "$NS_NAME"
  else
    ip netns add "$NS_NAME"
    printf '  [+] Created network namespace: %s\n' "$NS_NAME"
  fi

  # Bring up only the internal loopback interface (127.0.0.1 / ::1)
  ip netns exec "$NS_NAME" ip link set dev lo up
  printf '  [+] Activated internal loopback (lo -> 127.0.0.1) inside %s\n' "$NS_NAME"
  printf '  [+] External interfaces inside %s: NONE (100%% internet air-gap)\n' "$NS_NAME"
  printf '====================================================================\n'
  printf 'Namespace ready! Launch LocalLLM inside "%s" with:\n' "$NS_NAME"
  printf '  sudo ./LLM_NetworkNamespaceSetup.sh --run ./manage-llm.sh cli -m 3.5\n'
}

remove_namespace() {
  require_root "--remove"

  printf '=== Removing Linux Network Namespace (%s) ===\n' "$NS_NAME"
  if ! ns_exists; then
    printf '  [=] Namespace "%s" is not present.\n' "$NS_NAME"
    return 0
  fi

  # Stop any processes still running inside the namespace
  local pids
  pids=$(ip netns pids "$NS_NAME" 2>/dev/null || true)
  if [[ -n "$pids" ]]; then
    printf '  [-] Stopping processes inside %s: %s\n' "$NS_NAME" "$(echo "$pids" | tr '\n' ' ')"
    echo "$pids" | xargs -r kill 2>/dev/null || true
    sleep 1
    echo "$pids" | xargs -r kill -9 2>/dev/null || true
  fi

  ip netns delete "$NS_NAME"
  printf '  [-] Deleted network namespace: %s\n' "$NS_NAME"
  printf '=========================================================\n'
}

status_namespace() {
  printf '=== Linux Network Namespace (%s) Status ===\n' "$NS_NAME"
  if ! ns_exists; then
    printf '  Status: STOPPED / NOT CREATED\n'
    printf '  (Run "sudo ./LLM_NetworkNamespaceSetup.sh --setup" to create it)\n'
    printf '=====================================================\n'
    return 0
  fi

  printf '  Status: ACTIVE\n\n'
  if [[ $EUID -eq 0 ]]; then
    printf '  Interfaces inside %s:\n' "$NS_NAME"
    ip netns exec "$NS_NAME" ip -br addr | sed 's/^/    /'
    printf '\n  Routing table inside %s:\n' "$NS_NAME"
    local routes
    routes=$(ip netns exec "$NS_NAME" ip route 2>/dev/null || true)
    if [[ -n "$routes" ]]; then
      printf '%s\n' "$routes" | sed 's/^/    /'
    else
      printf '    (empty — no external routes, internet unreachable)\n'
    fi
    printf '\n  Processes running inside %s:\n' "$NS_NAME"
    local pids
    pids=$(ip netns pids "$NS_NAME" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
      ps -o pid,user,comm,args -p $(echo "$pids" | tr '\n' ',') | sed 's/^/    /'
    else
      printf '    (none)\n'
    fi
  else
    printf '  (Run "sudo ./LLM_NetworkNamespaceSetup.sh --status" to view internal interfaces & PIDs)\n'
  fi
  printf '=====================================================\n'
}

run_in_namespace() {
  if [[ $# -eq 0 ]]; then
    printf 'Error: --run requires a command (e.g. sudo ./LLM_NetworkNamespaceSetup.sh --run ./manage-llm.sh cli -m 3.5)\n' >&2
    exit 2
  fi
  require_root "--run" "$@"

  if ! ns_exists; then
    setup_namespace
  fi

  exec ip netns exec "$NS_NAME" sudo -E -u "$TARGET_USER" \
    env PATH="$PATH" HOME="$(eval echo "~$TARGET_USER")" USER="$TARGET_USER" \
    "$@"
}

run_unshare() {
  if [[ $# -eq 0 ]]; then
    printf 'Error: --unshare requires a command (e.g. ./LLM_NetworkNamespaceSetup.sh --unshare ./manage-llm.sh cli -m 3.5)\n' >&2
    exit 2
  fi
  local quoted_cmd
  printf -v quoted_cmd '%q ' "$@"
  exec unshare -r -n bash -c "ip link set dev lo up && exec $quoted_cmd"
}

case "${1:---help}" in
  --setup|setup)
    setup_namespace
    ;;
  --remove|remove|--teardown|teardown)
    remove_namespace
    ;;
  --status|status)
    status_namespace
    ;;
  --run|run)
    shift
    run_in_namespace "$@"
    ;;
  --unshare|unshare)
    shift
    run_unshare "$@"
    ;;
  -h|--help|help)
    show_help
    ;;
  *)
    printf 'Unknown switch: %s\n\n' "$1" >&2
    show_help >&2
    exit 2
    ;;
esac
__EMBED_EOF__
chmod +x "$BASE_DIR/Network_Isolation/LLM_NetworkNamespaceSetup.sh"
bash -n "$BASE_DIR/Network_Isolation/LLM_NetworkNamespaceSetup.sh"
ln -sf "Network_Isolation/LLM_NetworkNamespaceSetup.sh" "$BASE_DIR/Linux_Network_Namespace.sh"

cat <<'__EMBED_EOF__' > "$BASE_DIR/Network_Isolation/NetworkIsolationReadMe.md"
### 1. LLM_IsolationOptions.md                                                                                 
                                                                                                                 
Documents the four Linux isolation layers (Loopback-Only Binding, Linux Network Namespaces, Host Firewall      
Filtering by Group & Interface, and Systemd Cgroup IP Sandboxing) and compares when to use each script.        
  ──────                                                                                                         
### 2. LLM_NetworkIsolationSetup.sh (Group-Based Firewall + USB Consoles)                                      
                                                                                                                 
Includes full switch descriptions and examples in the script header (lines 1–55, viewable via                  
  ./LLM_NetworkIsolationSetup.sh --help):                                                                        
                                                                                                                 
  • --setup / setup:                                                                                             
      • Creates the llm-local group and adds your user to llm-local and dialout.                                 
      • Configures read/write permissions, symlinks, and a persistent udev rule (/etc/udev/rules.d/99-llm-usb-   
      console.rules) for /dev/tty/usb0, /dev/tty/usb1, /dev/ttyUSB0, and /dev/ttyUSB1.                           
      • Installs an iptables and ip6tables LLM_ISOLATION chain hooked into OUTPUT for -m owner --gid-owner llm-  
      local that only allows lo, eth0, eth1, and eth2 and rejects all traffic on any other interface (blocking   
      Wi-Fi, WAN gateways, and the internet).                                                                    
  • --remove / remove: Removes all LLM_ISOLATION firewall rules and the udev rule.                               
  • --status / status: Shows group status, USB console presence (note: /dev/ttyUSB0 was detected on your machine 
  right now), and active firewall rules.                                                                         
  • --run / run <cmd...>: Launches LocalLLM inside the llm-local group:                                          
    sudo ./LLM_NetworkIsolationSetup.sh --setup                                                                  
    ./LLM_NetworkIsolationSetup.sh --run ./manage-llm.sh cli -m 3.5                                              
                                                                                                                 
  ──────                                                                                                         
### 3. LLM_NetworkNamespaceSetup.sh (also linked as Linux_Network_Namespace.sh)                                
                                                                                                                 
  Includes full switch descriptions and examples in the script header (lines 1–57, viewable via                  
  ./LLM_NetworkNamespaceSetup.sh --help):                                                                        
                                                                                                                 
  • --setup / setup: Creates the persistent llm-isolated Linux network namespace and brings up only its internal 
  loopback (lo → 127.0.0.1) with zero external interfaces or routes.                                             
  • --remove / remove: Terminates any processes inside llm-isolated and deletes the namespace.                   
  • --status / status: Displays namespace status, internal interfaces, routing table, and active PIDs.           
  • --run / run <cmd...>: Runs LocalLLM inside the air-gapped llm-isolated namespace as your user:               
    sudo ./LLM_NetworkNamespaceSetup.sh --setup                                                                  
    sudo ./LLM_NetworkNamespaceSetup.sh --run ./manage-llm.sh cli -m 3.5                                         
                                                                                                                 
  • --unshare <cmd...>: Runs a command in an ephemeral rootless network namespace (unshare -r -n) without        
  requiring sudo.   
__EMBED_EOF__

cat <<'__EMBED_EOF__' > "$BASE_DIR/Complimentary Scripts/serial_watch.sh"
#!/usr/bin/env bash
# Observe an existing Linux serial connection in another terminal without opening the serial port.
# Requires software to be install: 
# sudo apt install -y strace psmisc coreutils 

set -euo pipefail

usage() {
    cat <<'HELP'
Usage: bash serial_watch.sh [DEVICE] [--hex]

Find every process using DEVICE and show its serial reads/writes here.
DEVICE defaults to /dev/ttyUSB0. Start your serial script first.

Examples:
  bash serial_watch.sh
  bash serial_watch.sh /dev/ttyUSB1
  bash serial_watch.sh /dev/ttyUSB0 --hex

write(...) = data sent to the console
read(...)  = data received from the console
\r = carriage return; \n = newline

Ctrl+C detaches the monitor; the separately running serial script continues.
No log file is created. Tracing adds overhead and can affect tight timing.
Requires: bash, strace, fuser (psmisc), readlink (coreutils), and sudo unless root.
Install on Kali/Debian: sudo apt install strace psmisc
HELP
}

device=/dev/ttyUSB0
device_given=false
hex_args=()
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        --hex) hex_args=(-xx) ;;
        -*) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
        *)
            if "$device_given"; then
                printf 'Specify only one serial device.\n' >&2
                exit 2
            fi
            device=$arg
            device_given=true
            ;;
    esac
done

for dependency in strace fuser readlink; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf 'Missing dependency: %s\n' "$dependency" >&2
        printf 'Install with: sudo apt install strace psmisc coreutils\n' >&2
        exit 1
    fi
done

if [[ ! -c "$device" ]]; then
    printf 'Serial device not found or not a character device: %s\n' "$device" >&2
    exit 1
fi
device=$(readlink -f -- "$device")

# Root can discover and trace processes owned by other users as well.
if (( EUID != 0 )); then
    if ! command -v sudo >/dev/null 2>&1; then
        printf 'Run this script as root; sudo is unavailable.\n' >&2
        exit 1
    fi
    script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
    exec sudo -- bash "$script_path" "$@"
fi

# fuser writes numeric PIDs to stdout and its device label to stderr.
# It does not open the serial port or consume any of the console bytes.
holders=$(fuser -- "$device" 2>/dev/null) || true
pids=()
read -r -a pids <<< "${holders//$'\n'/ }" || true
attach_args=()
for pid in "${pids[@]}"; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    attach_args+=(-p "$pid")
done

if (( ${#attach_args[@]} == 0 )); then
    printf 'No process is using %s. Start your serial script, then try again.\n' "$device" >&2
    exit 1
fi

printf 'Monitoring %s | PID(s): %s\n' "$device" "${pids[*]}"
printf 'write = SENT; read = RECEIVED. Ctrl+C stops this monitor.\n\n'
exec strace -f -tt -yy -s 0 \
    -e trace=read,write,readv,writev -e signal=none \
    -P "$device" "${hex_args[@]}" "${attach_args[@]}" 2>&1
__EMBED_EOF__
chmod +x "$BASE_DIR/Complimentary Scripts/serial_watch.sh"
bash -n "$BASE_DIR/Complimentary Scripts/serial_watch.sh"

# 6. Download & extract llama.cpp binaries if not already installed
printf '[5/6] Checking llama.cpp binaries in %s/bin ...\n' "$BASE_DIR"
if [[ -x "$BASE_DIR/bin/llama-server" ]] && LD_LIBRARY_PATH="$BASE_DIR/bin:${LD_LIBRARY_PATH:-}" "$BASE_DIR/bin/llama-server" --version >/dev/null 2>&1; then
  printf '  -> llama-server binary already installed and verified.\n'
else
  if command -v nvidia-smi >/dev/null 2>&1; then
    printf '  -> NVIDIA GPU detected. Downloading llama.cpp %s CUDA 12.8 binaries + CUDA runtime ...\n' "$LLAMA_BUILD_TAG"
    if ! (fetch_stream_extract "$LLAMA_CUDA_URL" "$BASE_DIR/bin" && fetch_stream_extract "$LLAMA_CUDART_URL" "$BASE_DIR/bin"); then
      printf '  [!] Warning: CUDA binary download failed; falling back to CPU x64 binaries...\n' >&2
      fetch_stream_extract "$LLAMA_CPU_URL" "$BASE_DIR/bin"
    fi
  else
    printf '  -> No NVIDIA GPU detected. Downloading llama.cpp %s CPU x64 binaries ...\n' "$LLAMA_BUILD_TAG"
    fetch_stream_extract "$LLAMA_CPU_URL" "$BASE_DIR/bin"
  fi
  chmod +x "$BASE_DIR/bin/llama-server" "$BASE_DIR/bin/llama-cli" 2>/dev/null || true
  if ! LD_LIBRARY_PATH="$BASE_DIR/bin:${LD_LIBRARY_PATH:-}" "$BASE_DIR/bin/llama-server" --version >/dev/null 2>&1; then
    printf 'Error: llama-server binary failed verification after extraction in %s/bin\n' "$BASE_DIR" >&2
    exit 1
  fi
  printf '  -> Binaries installed and verified.\n'
fi

# 7. Download LLM models (Qwen3.5-9B and Qwen3.8-27B as appropriate)
printf '[6/6] Checking & downloading LLM models in %s/models ...\n' "$BASE_DIR"

TOTAL_RAM_MIB=$(awk '/MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 16384)
WANT_35=0
WANT_38=0

case "$DOWNLOAD_MODE" in
  all)
    WANT_35=1
    WANT_38=1
    ;;
  3.8)
    WANT_38=1
    ;;
  3.5)
    WANT_35=1
    ;;
  none)
    WANT_35=0
    WANT_38=0
    ;;
  auto)
    WANT_35=1
    if (( TOTAL_RAM_MIB >= 15000 )); then
      WANT_38=1
    else
      printf '  -> Host has %d MiB RAM (< 16 GiB): defaulting to Qwen3.5-9B (pass --all-models to force Qwen3.8-27B).\n' "$TOTAL_RAM_MIB"
    fi
    ;;
esac

download_model() {
  local name="$1"
  local url="$2"
  local dest="$3"
  local min_bytes="$4"

  if [[ -f "$dest" ]]; then
    local actual_bytes
    actual_bytes=$(stat -Lc%s "$dest" 2>/dev/null || echo 0)
    if (( actual_bytes >= min_bytes )); then
      printf '  -> %s already downloaded (%d MiB).\n' "$name" "$(( actual_bytes / 1048576 ))"
      return 0
    fi
    printf '  -> %s is incomplete (%d MiB); resuming download...\n' "$name" "$(( actual_bytes / 1048576 ))"
  else
    local avail_mb
    avail_mb=$(df -Pm "$BASE_DIR/models" | awk 'NR==2 {print $4}' 2>/dev/null || echo 999999)
    local needed_mb=$(( min_bytes / 1048576 + 512 ))
    if (( avail_mb < needed_mb )); then
      printf 'Error: Insufficient disk space in %s/models (%d MiB free, need at least %d MiB for %s).\n' \
        "$BASE_DIR" "$avail_mb" "$needed_mb" "$name" >&2
      exit 1
    fi
    printf '  -> Downloading %s ...\n' "$name"
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -c --tries=5 --timeout=30 --progress=bar:force:noscroll -O "$dest" "$url"
  else
    curl -fL --retry 5 --retry-delay 3 -C - -o "$dest" "$url"
  fi

  local final_bytes
  final_bytes=$(stat -Lc%s "$dest" 2>/dev/null || echo 0)
  if (( final_bytes < min_bytes )); then
    printf 'Error: Downloaded file %s is smaller than expected (%d bytes < %d bytes). Re-run setup_local_llm.sh to resume.\n' \
      "$dest" "$final_bytes" "$min_bytes" >&2
    exit 1
  fi
}

if (( WANT_35 == 1 )); then
  download_model "Qwen3.5-9B-Uncensored-Q4_K_M.gguf (5.24 GB)" \
    "$QWEN35_URL" "$BASE_DIR/models/$QWEN35_FILE" "$QWEN35_MIN_BYTES"
  ln -sf "$QWEN35_FILE" "$BASE_DIR/models/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
fi

if (( WANT_38 == 1 )); then
  download_model "Qwen3.8-27B-Uncensored-Q3_K_M.gguf (13.3 GB)" \
    "$QWEN38_URL" "$BASE_DIR/models/$QWEN38_FILE" "$QWEN38_MIN_BYTES"
fi

printf '\nSetup complete! Verifying installed models and hardware profile:\n\n'
"$BASE_DIR/manage-llm.sh" models
printf '\n'
"$BASE_DIR/manage-llm.sh" tune
printf '\nQuick Start Commands:\n'
printf '  cd %s\n' "$BASE_DIR"
printf '  ./manage-llm.sh cli -m 3.5                                       # Fast Agent CLI (Confirm ON)\n'
printf '  ./manage-llm.sh cli -m 3.5 --dangerously-skip-permissions        # Fast Agent CLI (Auto-run)\n'
printf '  ./manage-llm.sh cli -m 3.5 --project /path/to/docs my_project    # Onboard & track a project in Obsidian\n'
printf '  ./manage-llm.sh cli -m 3.8 --dangerously-skip-permissions        # Default Qwen3.8 Agent CLI (Auto-run)\n'
printf '  ./manage-llm.sh start                                            # Start server + Open WebUI\n'

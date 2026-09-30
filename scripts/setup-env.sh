#!/usr/bin/env bash
# ==============================================================================
# Android Agent Kit - Interactive Developer Environment Doctor & Setup (macOS / Linux)
# ==============================================================================
# Verifies and configures:
#   1. Git submodules & git hooks
#   2. JDK 21 & JAVA_HOME
#   3. Android SDK, NDK 30.0.15729638, CMake 4.1.2, ANDROID_HOME & platform-tools
#   4. Connected Android devices/emulators via adb
#   5. Python 3.10+ and uv
#   6. GitHub CLI login and repo access
#   7. ARTEMIS clone, API key and MCP registration
#   8. ARTEMIS model: Gemini (local Qwen fallback) or local Qwen only, sized to your GPU
#      Non-interactive choice: ARTEMIS_MODEL=gemini|qwen bash scripts/setup-env.sh
#   9. ktfmt (fetched by scripts/ci-local.sh)
#  10. Links .agents/skills/ into .claude/skills/ so Claude Code finds the skills
# ==============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

issues_found=0

header() {
  echo ""
  echo -e "${CYAN}==================================================================${NC}"
  echo -e "${BOLD}  $1${NC}"
  echo -e "${CYAN}==================================================================${NC}"
}

pass() { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
info() { echo -e "  [INFO] $1"; }

prompt_fix() {
  echo ""
  read -r -p "  --> $1 (y/N): " response
  case "$response" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

OS_TYPE="$(uname -s)"
case "$OS_TYPE" in
  Darwin*)
    SHELL_PROFILE="$HOME/.zshrc"
    DEFAULT_ANDROID_HOME="$HOME/Library/Android/sdk"
    ;;
  Linux*)
    SHELL_PROFILE="$HOME/.bashrc"
    DEFAULT_ANDROID_HOME="$HOME/Android/Sdk"
    ;;
  *)
    SHELL_PROFILE="$HOME/.bashrc"
    DEFAULT_ANDROID_HOME="$HOME/Android/Sdk"
    ;;
esac

header "Android Agent Kit - Developer Setup Doctor ($OS_TYPE)"
info "Repository: $REPO_ROOT"
info "Target Shell Profile: $SHELL_PROFILE"

# -------------------------------------------------------------
# 1. Git & Submodules
# -------------------------------------------------------------
header "1. Git Configuration & Submodules"
if command -v git &>/dev/null; then
  pass "Git is installed: $(command -v git)"

  if [[ -f "$REPO_ROOT/.gitmodules" ]] && git submodule status | grep -q '^-'; then
    warn "git submodules are not initialized."
    if prompt_fix "Initialize git submodules now (git submodule update --init --recursive)?"; then
      git submodule update --init --recursive
    else
      info "Run manually: git submodule update --init --recursive"
      issues_found=$((issues_found + 1))
    fi
  fi

  CURRENT_HOOKS="$(git config core.hooksPath || true)"
  if [[ "$CURRENT_HOOKS" != ".githooks" ]]; then
    warn "Git hooks path is not set to .githooks (current: '$CURRENT_HOOKS')"
    if prompt_fix "Set git core.hooksPath to .githooks now?"; then
      git config core.hooksPath .githooks
      pass "Git hooks path set to .githooks"
    else
      info "Run manually: git config core.hooksPath .githooks"
    fi
  else
    pass "Git hooks configured (.githooks)."
  fi
else
  fail "Git is not installed."
  issues_found=$((issues_found + 1))
fi

# -------------------------------------------------------------
# 2. Java / JDK 21
# -------------------------------------------------------------
header "2. Java Development Kit (JDK 21)"
if command -v java &>/dev/null; then
  JAVA_VER="$(java -version 2>&1 | head -n 1)"
  pass "Java found: $JAVA_VER"
else
  fail "java command not found in PATH."
  issues_found=$((issues_found + 1))
fi

if [[ -n "${JAVA_HOME:-}" && -d "$JAVA_HOME" ]]; then
  pass "JAVA_HOME is set: $JAVA_HOME"
else
  warn "JAVA_HOME is not set or directory does not exist."
  info "Add JAVA_HOME to $SHELL_PROFILE:"
  echo -e "${YELLOW}    export JAVA_HOME=/path/to/jdk-21${NC}"
  echo -e "${YELLOW}    export PATH=\"\$JAVA_HOME/bin:\$PATH\"${NC}"
  issues_found=$((issues_found + 1))
fi

# -------------------------------------------------------------
# 3. Android SDK, NDK 30.0.15729638 & CMake 4.1.2
# -------------------------------------------------------------
header "3. Android SDK, NDK & CMake"
DETECTED_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$DETECTED_SDK" && -f "$REPO_ROOT/local.properties" ]]; then
  # Android Studio writes sdk.dir here, escaped (C\:\\Path on Windows).
  SDK_LINE="$(grep -E '^sdk\.dir=' "$REPO_ROOT/local.properties" | head -1 | tr -d '\r')"
  DETECTED_SDK="$(sed -e 's/^sdk\.dir=//' -e 's/\\:/:/g' -e 's/\\\\/\//g' <<<"$SDK_LINE")"
  command -v cygpath &>/dev/null && [[ -n "$DETECTED_SDK" ]] && DETECTED_SDK="$(cygpath -u "$DETECTED_SDK")"
fi
DETECTED_SDK="${DETECTED_SDK:-$DEFAULT_ANDROID_HOME}"

if [[ -d "$DETECTED_SDK" ]]; then
  pass "Android SDK found at: $DETECTED_SDK"

  if command -v adb &>/dev/null; then
    pass "adb found in PATH: $(command -v adb)"
  elif [[ -f "$DETECTED_SDK/platform-tools/adb" ]]; then
    warn "adb found at $DETECTED_SDK/platform-tools/adb but not in PATH."
    info "Add to $SHELL_PROFILE:"
    echo -e "${YELLOW}    export PATH=\"\$ANDROID_HOME/platform-tools:\$PATH\"${NC}"
  else
    fail "adb not found in platform-tools."
    issues_found=$((issues_found + 1))
  fi

  REQUIRED_NDK="30.0.15729638"
  if [[ -d "$DETECTED_SDK/ndk/$REQUIRED_NDK" ]]; then
    pass "Required Android NDK ($REQUIRED_NDK) found."
  else
    warn "Android NDK $REQUIRED_NDK not found at $DETECTED_SDK/ndk/$REQUIRED_NDK"
    info "Install via SDK Manager or CLI:"
    echo -e "${YELLOW}    \"\$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager\" \"ndk;$REQUIRED_NDK\"${NC}"
  fi
else
  fail "Android SDK not found."
  info "Install Android Studio and export ANDROID_HOME in $SHELL_PROFILE:"
  echo -e "${YELLOW}    export ANDROID_HOME=\"$DEFAULT_ANDROID_HOME\"${NC}"
  echo -e "${YELLOW}    export PATH=\"\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH\"${NC}"
  issues_found=$((issues_found + 1))
fi

# -------------------------------------------------------------
# 4. Connected Android Devices & Emulators
# -------------------------------------------------------------
header "4. Connected Android Devices"
if command -v adb &>/dev/null; then
  DEVICES="$(adb devices -l | grep -E '^\S+\s+(device|unauthorized|offline)' || true)"
  if [[ -n "$DEVICES" ]]; then
    pass "Connected device(s) found:"
    echo "$DEVICES" | while read -r line; do
      echo -e "    ${GREEN}$line${NC}"
    done
  else
    warn "No Android devices or emulators connected. Connect phone via USB/Wi-Fi or start an AVD."
  fi
fi

# -------------------------------------------------------------
# 5. Python 3.10+ & uv
# -------------------------------------------------------------
header "5. Python 3.10+ and uv Package Manager"
if command -v python3 &>/dev/null; then
  PY_VER="$(python3 --version)"
  pass "Python is installed: $PY_VER"
else
  warn "python3 not found in PATH."
fi

if command -v uv &>/dev/null; then
  pass "uv package manager installed: $(command -v uv)"
else
  warn "uv package manager not found."
  if prompt_fix "Install uv now (curl -LsSf https://astral.sh/uv/install.sh | sh)?"; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    pass "uv installed. You may need to source $SHELL_PROFILE."
  else
    info "Install manually: curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
fi

# -------------------------------------------------------------
# 6. GitHub CLI (issue -> PR workflow)
# -------------------------------------------------------------
header "6. GitHub CLI"
if ! command -v gh &>/dev/null; then
  fail "gh is not installed. The bug -> PR workflow uses it to read issues and open PRs."
  info "Install: https://cli.github.com (brew install gh / sudo apt install gh), then: gh auth login"
  issues_found=$((issues_found + 1))
else
  pass "gh is installed: $(command -v gh)"
  # 'gh auth status' also fails on a stale inactive account; test the active one instead.
  if ! GH_USER="$(gh api user -q .login 2>/dev/null)" || [[ -z "$GH_USER" ]]; then
    fail "gh is not logged in. Run: gh auth login"
    issues_found=$((issues_found + 1))
  else
    PERM="$(gh repo view --json viewerPermission -q .viewerPermission 2>/dev/null || true)"
    case "$PERM" in
      ADMIN|MAINTAIN|WRITE) pass "gh is logged in as $GH_USER with $PERM access to this repo." ;;
      *) warn "gh is logged in but has '$PERM' access here - you cannot push fix branches."
         info "Ask a maintainer for write access to the repository." ;;
    esac
  fi
fi

# -------------------------------------------------------------
# 7. ARTEMIS (on-device testing via MCP)
# -------------------------------------------------------------
header "7. ARTEMIS Mobile Testing"
ARTEMIS_HOME="${ARTEMIS_HOME:-$(dirname "$REPO_ROOT")/artemis}"
ARTEMIS_ENV="$ARTEMIS_HOME/.env"
if [[ ! -d "$ARTEMIS_HOME/mcp_server" ]]; then
  fail "ARTEMIS not found at $ARTEMIS_HOME (set ARTEMIS_HOME if it lives elsewhere)."
  if prompt_fix "Clone google/artemis to $ARTEMIS_HOME now?"; then
    git clone https://github.com/google/artemis.git "$ARTEMIS_HOME"
  fi
  info "Then: cd $ARTEMIS_HOME && ./start.sh && uv run artemis mcp --install claude"
  issues_found=$((issues_found + 1))
else
  pass "ARTEMIS found at $ARTEMIS_HOME"

  if [[ -d "$ARTEMIS_HOME/.venv" ]]; then
    pass "ARTEMIS virtualenv exists."
  else
    fail "ARTEMIS dependencies are not installed. Run: cd $ARTEMIS_HOME && ./start.sh"
    issues_found=$((issues_found + 1))
  fi

  if [[ -f "$ARTEMIS_ENV" ]] && grep -Eq '^\s*(GEMINI_API_KEY|GOOGLE_API_KEY)\s*=\s*\S+' "$ARTEMIS_ENV"; then
    pass "Gemini API key is set in $ARTEMIS_ENV"
  else
    fail "No GEMINI_API_KEY in $ARTEMIS_ENV"
    info "Get a key at https://aistudio.google.com/apikey and add: GEMINI_API_KEY=<key>"
    issues_found=$((issues_found + 1))
  fi

  if command -v claude &>/dev/null; then
    if claude mcp get artemis &>/dev/null; then
      pass "ARTEMIS MCP server is registered with Claude Code."
    else
      fail "ARTEMIS MCP server is not registered with Claude Code."
      info "Run: cd $ARTEMIS_HOME && uv run artemis mcp --install claude   (then restart Claude Code)"
      issues_found=$((issues_found + 1))
    fi
  else
    info "Claude Code CLI not found - register ARTEMIS with your agent: uv run artemis mcp --install <client>"
  fi
  info "Final check from your agent: mobile_diagnose  (verdict must be 'ready' or 'degraded')"
fi

# -------------------------------------------------------------
# 8. ARTEMIS model: Gemini (with local fallback) or local Qwen only
# -------------------------------------------------------------
header "8. ARTEMIS Model (Gemini / local Qwen)"
VRAM_GB=0
GPU_NAME="no supported GPU detected"
if [[ "$OS_TYPE" == Darwin* && "$(uname -m)" == "arm64" ]]; then
  # Apple Silicon shares memory with the GPU; ~2/3 of it is usable for a model.
  MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  VRAM_GB=$(( MEM_GB * 2 / 3 ))
  GPU_NAME="Apple Silicon (${MEM_GB} GB unified)"
elif command -v nvidia-smi &>/dev/null; then
  while IFS=, read -r name mib; do
    mib="${mib//[^0-9]/}"; gb=$(( ${mib:-0} / 1024 ))
    if (( gb > VRAM_GB )); then VRAM_GB=$gb; GPU_NAME="$name"; fi
  done < <(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null)
fi
info "Hardware: $GPU_NAME (~${VRAM_GB} GB usable for a model)"

# Instruct (non-thinking) variants: an agent loop needs short, predictable replies.
# num_ctx is capped so model + context fit in VRAM; Ollama's default (the model's full
# 256K window) spills to CPU and is ~10x slower.
BASE_MODEL=""; TIER=""; NUM_CTX=32768
if   (( VRAM_GB >= 24 )); then BASE_MODEL="qwen3-vl:30b-a3b-instruct"; TIER="30b"
elif (( VRAM_GB >= 10 )); then BASE_MODEL="qwen3-vl:8b-instruct"; TIER="8b"
elif (( VRAM_GB >= 6 ));  then BASE_MODEL="qwen3-vl:4b-instruct"; TIER="4b"; NUM_CTX=16384
fi
LOCAL_MODEL="${TIER:+qwen3-vl-artemis:$TIER}"
MODEL_SCRIPT="$REPO_ROOT/scripts/artemis_model.py"
HAVE_LOCAL=0

if [[ -z "$LOCAL_MODEL" ]]; then
  info "Under 6 GB usable: a local vision model is too slow for ARTEMIS; ARTEMIS stays on Gemini."
  info "For quota relief, add a second cloud key (e.g. OPEN_ROUTER_API_KEY) instead."
else
  pass "Local model for your hardware: $BASE_MODEL -> $LOCAL_MODEL (context $NUM_CTX)"
  if ! command -v ollama &>/dev/null; then
    info "Ollama not installed (optional). Get it from https://ollama.com/download"
  elif ! TAGS="$(curl -sf --max-time 3 http://localhost:11434/api/tags)"; then
    warn "Ollama is installed but not running. Start it (ollama serve &), then re-run."
  elif grep -q "\"$LOCAL_MODEL\"" <<<"$TAGS"; then
    pass "$LOCAL_MODEL is ready in Ollama."
    HAVE_LOCAL=1
  elif prompt_fix "Download $BASE_MODEL (several GB) and create $LOCAL_MODEL?"; then
    ollama pull "$BASE_MODEL"
    MF="$(mktemp)"
    printf 'FROM %s\nPARAMETER num_ctx %s\nPARAMETER temperature 0\n' "$BASE_MODEL" "$NUM_CTX" > "$MF"
    ollama create "$LOCAL_MODEL" -f "$MF" && HAVE_LOCAL=1
    rm -f "$MF"
  else
    info "Later: ollama pull $BASE_MODEL, then re-run this script to create $LOCAL_MODEL."
  fi
fi

if [[ -d "$ARTEMIS_HOME/mcp_server" ]] && (( HAVE_LOCAL )); then
  MODE="${ARTEMIS_MODEL:-}"
  if [[ -z "$MODE" ]]; then
    echo ""
    echo "  Which model should ARTEMIS drive the device with?"
    echo "    g) Gemini, with $LOCAL_MODEL taking over when the quota runs out  (recommended)"
    echo "    q) $LOCAL_MODEL only - no Gemini calls, no quota, slower and less capable"
    echo "    Enter) keep the current setting"
    read -r -p "  --> " answer
    case "$answer" in g|G) MODE=gemini ;; q|Q) MODE=qwen ;; esac
  fi
  if [[ -n "$MODE" ]]; then
    python3 "$MODEL_SCRIPT" "$MODE" --artemis-home "$ARTEMIS_HOME" --model "$LOCAL_MODEL"
  else
    info "$(python3 "$MODEL_SCRIPT" status --artemis-home "$ARTEMIS_HOME")"
  fi
  info "Switch any time: python3 scripts/artemis_model.py gemini|qwen|status"
fi

# -------------------------------------------------------------
# 8b. Local decision model for the agent hooks (Nimble or Laya)
# -------------------------------------------------------------
# Optional. The hooks (scripts/nimble.sh) ask it quick yes/no and pick-one questions and do
# nothing without it. Nimble (Ollama) reads long logs but needs ~9 GB of GPU memory while loaded.
# Laya (pip, ~1.3 GB) fits smaller machines but sees only the last ~512 tokens of a log.
header "8b. Local Decision Model for Agent Hooks (Nimble / Laya)"
if [[ "$OS_TYPE" == Darwin* ]]; then RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
else RAM_GB=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1048576 )); fi
DECISION=""
if (( VRAM_GB >= 12 )); then DECISION=nimble
elif (( VRAM_GB >= 4 || RAM_GB >= 16 )); then DECISION=laya; fi

if [[ -z "$DECISION" ]]; then
  info "Under 4 GB GPU memory and 16 GB RAM: no local decision model. The hooks stay off; nothing breaks."
elif [[ "$DECISION" == nimble ]]; then
  pass "Your hardware fits Nimble (~${VRAM_GB} GB usable; it needs ~9 GB while loaded)."
  if [[ -n "$LOCAL_MODEL" ]] && (( VRAM_GB < 18 )); then
    info "Nimble and $LOCAL_MODEL do not both fit; Ollama swaps them, so the first hook after an ARTEMIS run is slower."
  fi
  OLLAMA_VER="$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if ! command -v ollama &>/dev/null; then
    info "Ollama not installed (optional). Get 0.35.0 or later from https://ollama.com/download"
  elif [[ -n "$OLLAMA_VER" && "$(printf '%s\n0.35.0\n' "$OLLAMA_VER" | sort -V | head -1)" != "0.35.0" ]]; then
    warn "Ollama $OLLAMA_VER is too old for Nimble's /v1/systemone endpoint. Update to 0.35.0 or later."
  elif ! TAGS="$(curl -sf --max-time 3 http://localhost:11434/api/tags)"; then
    warn "Ollama is installed but not running. Start it (ollama serve &), then re-run."
  elif grep -qE '"nimble(:[^"]*)?"' <<<"$TAGS"; then
    pass "Nimble is ready in Ollama. The hooks use it at http://127.0.0.1:11434."
  elif prompt_fix "Download Nimble into Ollama (several GB)?"; then
    ollama pull nimble
  else
    info "Later: ollama pull nimble"
  fi
else
  LAYA_ENV="$HOME/laya-env"
  if command -v nvidia-smi &>/dev/null && (( VRAM_GB >= 4 )); then DEVICE=cuda
  elif [[ "$OS_TYPE" == Darwin* && "$(uname -m)" == "arm64" ]]; then DEVICE=mps
  else DEVICE=cpu; fi
  pass "Laya fits this machine ($GPU_NAME, ${RAM_GB} GB RAM; runs on $DEVICE)."
  [[ "$DEVICE" != cuda ]] && info "Laya on $DEVICE is untested here and may be slower than on CUDA."
  if [[ -x "$LAYA_ENV/bin/laya-serve" ]]; then
    pass "Laya is installed in $LAYA_ENV."
  elif prompt_fix "Create $LAYA_ENV and install Laya with PyTorch (~3 GB download)?"; then
    python3 -m venv "$LAYA_ENV"
    "$LAYA_ENV/bin/python" -m pip install --upgrade pip
    if [[ "$DEVICE" == cuda ]]; then
      "$LAYA_ENV/bin/python" -m pip install torch --index-url https://download.pytorch.org/whl/cu128
    else
      "$LAYA_ENV/bin/python" -m pip install torch
    fi
    "$LAYA_ENV/bin/python" -m pip install laya
  else
    info "Later: re-run this script and answer yes to install Laya."
  fi
  if [[ -x "$LAYA_ENV/bin/laya-serve" && ! -f "$LAYA_ENV/start-laya.sh" ]]; then
    cat > "$LAYA_ENV/start-laya.sh" <<EOF
#!/usr/bin/env bash
# Starts the Laya System One server on 127.0.0.1:8000 (loopback only), logs in laya-env/logs.
mkdir -p "$LAYA_ENV/logs"
LAYA_HOST=127.0.0.1 LAYA_PORT=8000 LAYA_MODELS=english LAYA_DEVICE=$DEVICE LAYA_PRELOAD=1 \\
  nohup "$LAYA_ENV/bin/laya-serve" >"$LAYA_ENV/logs/out.log" 2>"$LAYA_ENV/logs/err.log" &
EOF
    chmod +x "$LAYA_ENV/start-laya.sh"
    pass "Wrote $LAYA_ENV/start-laya.sh"
  fi
  # Point the hooks at Laya: same /v1/systemone API, but a 512-token window.
  if ! grep -q "NIMBLE_URL" "$SHELL_PROFILE" 2>/dev/null; then
    printf '\n# Agent hooks: local decision model = Laya\nexport NIMBLE_URL=http://127.0.0.1:8000 NIMBLE_MODEL=laya NIMBLE_MAX_BYTES=1800\n' >> "$SHELL_PROFILE"
  fi
  info "Hooks now use Laya (NIMBLE_URL, NIMBLE_MODEL, NIMBLE_MAX_BYTES in $SHELL_PROFILE; restart your agent)."
  info "Start it: $LAYA_ENV/start-laya.sh"
fi

# The `nimble` skill lets an agent in ANY project ask the model a yes/no or pick-one question
# about a long log instead of reading it. Installed per user, only when asked.
if [[ -n "$DECISION" ]]; then
  if [[ -f "$HOME/.claude/skills/nimble/SKILL.md" ]]; then
    pass "The nimble skill is installed globally (~/.claude/skills/nimble)."
  elif prompt_fix "Install the nimble skill globally (~/.claude/skills/nimble, for every project)?"; then
    mkdir -p "$HOME/.claude/skills/nimble" "$HOME/.claude/nimble"
    cp "$REPO_ROOT/tools/nimble-skill/SKILL.md" "$HOME/.claude/skills/nimble/SKILL.md"
    cp "$REPO_ROOT/tools/nimble-skill/nimble-ask" "$REPO_ROOT/scripts/nimble.sh" "$HOME/.claude/nimble/"
    chmod +x "$HOME/.claude/nimble/nimble-ask"
    pass "Installed. Restart your agent; check with: echo hi | ~/.claude/nimble/nimble-ask yesno \"Is this a greeting?\""
  else
    info "Skipped. The repo hooks still use the model; only other projects miss the skill."
  fi
fi

# -------------------------------------------------------------
# 9. Kotlin Formatting
# -------------------------------------------------------------
header "9. Kotlin Formatting (ktfmt)"
pass "Nothing to install: 'bash scripts/ci-local.sh --fix' downloads the ktfmt version CI uses."
if command -v ktfmt &>/dev/null; then
  warn "A ktfmt is on your PATH - don't use it for this repo; its version may disagree with CI."
fi

# -------------------------------------------------------------
# 10. Agent Skills for Claude Code
# -------------------------------------------------------------
# Skills live in .agents/skills/ (Gemini CLI reads it). Claude Code only reads .claude/skills/,
# so symlink each skill there.
header "10. Agent Skills for Claude Code"
mkdir -p .claude/skills
linked=0
for skill in .agents/skills/*/; do
  name="$(basename "$skill")"
  [ -e ".claude/skills/$name" ] && continue
  ln -s "../../.agents/skills/$name" ".claude/skills/$name"
  linked=$((linked + 1))
done
pass "Claude Code sees every skill in .agents/skills/ ($linked new link(s) in .claude/skills/)."

# -------------------------------------------------------------
# Environment Variables Guide
# -------------------------------------------------------------
header "Environment Variables Configuration for $SHELL_PROFILE"
echo -e "${BOLD}Add the following lines to your $SHELL_PROFILE:${NC}"
echo ""
echo -e "${YELLOW}# Java 21${NC}"
echo -e "${YELLOW}export JAVA_HOME=\"/path/to/jdk-21\"${NC}"
echo -e "${YELLOW}export PATH=\"\$JAVA_HOME/bin:\$PATH\"${NC}"
echo ""
echo -e "${YELLOW}# Android SDK & Tools${NC}"
echo -e "${YELLOW}export ANDROID_HOME=\"$DEFAULT_ANDROID_HOME\"${NC}"
echo -e "${YELLOW}export PATH=\"\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH\"${NC}"
echo ""
echo -e "After updating, reload with: ${BOLD}source $SHELL_PROFILE${NC}"
echo ""

header "Doctor Summary"
if [[ $issues_found -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}ALL ESSENTIAL PREREQUISITES MET! Ready to build.${NC}"
  echo -e "Commands to get started:"
  echo -e "  Build:   ${CYAN}./gradlew :${APP_MODULE#:}:assembleDebug${NC}"
  echo -e "  Test:    ${CYAN}./gradlew :${APP_MODULE#:}:testDebugUnitTest${NC}"
  echo -e "  Format:  ${CYAN}bash scripts/ci-local.sh --fix${NC}"
else
  echo -e "${YELLOW}${BOLD}Found $issues_found item(s) that need attention. See above logs.${NC}"
fi
echo ""

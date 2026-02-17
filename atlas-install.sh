#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Atlas Installer — Full-featured PicoClaw Gateway Setup
#  Target: Debian 13 (Trixie) — Root access required
# ═══════════════════════════════════════════════════════════════
#
#  Version: v1.0.8
#  Upstream: sipeed/picoclaw
#  License: Proprietary (see LICENSE file)
#
#  Usage:
#    bash atlas-install.sh                   # Interactive wizard
#    bash atlas-install.sh --config <yaml>   # Non-interactive
#
#  Features: Multi-provider LLM gateway, Telegram/Discord/WhatsApp
#            channels, FTP server, WhatsApp bridge, Ollama support,
#            auto-backup, performance optimization, Atlas skills
# ═══════════════════════════════════════════════════════════════

set -eEuo pipefail

on_error() {
    echo ""
    printf '  \033[0;31m✘ Failed at line %s (exit %s)\033[0m\n' "$1" "$2"
    printf "  \033[2mCheck output above. Safe to re-run the script.\033[0m\n"
    echo ""
}
trap 'on_error ${LINENO} $?' ERR

# ════════════════════════════════════════════════
# CACHED SYSCALLS — computed once for performance
# ════════════════════════════════════════════════
readonly ARCH=$(uname -m)

# ════════════════════════════════════════════════
# CONSTANTS — verified from source + releases API
# ════════════════════════════════════════════════
GO_VERSION="1.26.0"
GO_SHA_AMD64="aac1b08a0fb0c4e0a7c1555beb7b59180b05dfc5a3d62e40e9de90cd42f88235"
GO_SHA_ARM64="bd03b743eb6eb4193ea3c3fd3956546bf0e3ca5b7076c8226334afe6b75704cd"
GO_SHA_RISCV64="ab9226ecddda0f682365c949114b653a66c2e9330e7b8d3edea80858437d2ff2"

PICOCLAW_VERSION="v0.0.1"  # fallback if GitHub API unreachable
PICOCLAW_DL="https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VERSION}"
PICOCLAW_REPO="https://github.com/sipeed/picoclaw.git"
PICOCLAW_BIN="/usr/local/bin/picoclaw"
PICOCLAW_REAL="/usr/local/bin/picoclaw.bin"
PICOCLAW_SRC="/opt/picoclaw"
PC_SHA_AMD64="cb64a61179d990a7a20fadbdd0b2883a36da17a0aad695667133e1403b5dd061"
PC_SHA_ARM64="72aba3a10c50c885ef839f1fe05ef79f6124c073cde0c0b57311d9e2f450c1f4"
PC_SHA_RISCV64="f3df8e43ee5d37b8d7b4b5de3784985c14c6162c77eab16660fd2cdc0533c46a"

CONFIG_DIR="/root/.picoclaw"
CONFIG_FILE="${CONFIG_DIR}/config.json"
WORKSPACE_DIR="${CONFIG_DIR}/workspace"

BACKUP_DIR="/root/backup"
BACKUP_META_FILE="${CONFIG_DIR}/backup.conf"

ATLAS_REPO="pr0ace/atlas"
ATLAS_REPO_URL="https://github.com/${ATLAS_REPO}"
ATLAS_BRANCH="master"
ATLAS_API_TREE="https://api.github.com/repos/${ATLAS_REPO}/git/trees/${ATLAS_BRANCH}?recursive=1"
ATLAS_RAW_BASE="https://raw.githubusercontent.com/${ATLAS_REPO}/${ATLAS_BRANCH}"
ATLAS_SKILLS_DIR="${WORKSPACE_DIR}/skills"
ATLAS_META_FILE="${CONFIG_DIR}/atlas.json"

FTP_CONF_FILE="${CONFIG_DIR}/ftp.conf"

WA_BRIDGE_DIR="/opt/picoclaw-whatsapp-bridge"
WA_BRIDGE_AUTH_DIR="${CONFIG_DIR}/whatsapp-auth"
WA_BRIDGE_REPO="https://github.com/HKUDS/nanobot.git"
WA_BRIDGE_PORT="3001"
WA_BRIDGE_SERVICE="picoclaw-whatsapp-bridge"
WA_CONF_FILE="${CONFIG_DIR}/whatsapp.conf"

OLLAMA_INSTALL_URL="https://ollama.com/install.sh"
OLLAMA_BIN="/usr/local/bin/ollama"
OLLAMA_SERVICE="ollama"
OLLAMA_CONF_FILE="${CONFIG_DIR}/ollama.conf"
OLLAMA_HOST="127.0.0.1"
OLLAMA_PORT="11434"
OLLAMA_API_BASE="http://127.0.0.1:11434/v1"

# ════════════════════════════════════════════════
# WIZARD MODEL LISTS
# Curated subset for first-time install wizard.
# CLI wrapper has a broader list for model switching
# after installation (see CLI_MODELS_* in the heredoc).
# ════════════════════════════════════════════════
WIZARD_MODELS_OPENROUTER=(
  "anthropic/claude-sonnet-4.5"    "latest Sonnet, best coding+agents"
  "anthropic/claude-opus-4.6"      "most powerful, complex challenges"
  "anthropic/claude-opus-4.5"      "strong all-rounder"
  "anthropic/claude-sonnet-4"      "balanced price/performance"
  "openai/gpt-5.2"                 "OpenAI flagship, coding+agentic"
  "openai/gpt-5.1"                 "configurable reasoning effort"
  "openai/gpt-5"                   "previous gen reasoning"
  "openai/gpt-5-mini"              "fast, cost-efficient GPT-5"
  "google/gemini-3-pro-preview"    "Google most intelligent"
  "google/gemini-3-flash-preview"  "Google fast+balanced"
  "google/gemini-2.5-flash"        "Google best price/perf"
  "google/gemini-2.5-pro"          "Google advanced thinking"
  "deepseek/deepseek-r1"           "reasoning, open-weight"
  "deepseek/deepseek-v3-0324"      "fast general purpose"
  "meta-llama/llama-4-maverick"    "Meta latest MoE"
  "qwen/qwen3-235b-a22b"           "Alibaba frontier"
)

WIZARD_MODELS_ZHIPU=(
  "glm-5"                  "744B MoE (40B active), flagship, agentic engineering"
  "glm-4.7"               "355B MoE (32B active), coding+reasoning+agents"
  "glm-4.7-flashx"        "fast+cheap, extended FlashX"
  "glm-4.7-flash"         "30B MoE (3B active), free tier"
  "glm-4.6"              "357B, 200K context, agentic+coding"
  "glm-4.5"              "355B MoE, reasoning+agents"
  "glm-4.5-x"            "extended context GLM-4.5"
  "glm-4.5-air"          "106B MoE (12B active), balanced cost/perf"
  "glm-4.5-airx"         "extended context Air"
  "glm-4.5-flash"        "free tier, fast"
  "glm-4-32b-0414-128k"  "open-weight 32B, 128K context"
  "glm-4.6v"             "106B vision, 128K ctx, native tool use"
  "glm-4.6v-flashx"      "fast+cheap vision"
  "glm-4.5v"             "vision multimodal"
  "glm-4.6v-flash"       "9B vision, free tier"
)

WIZARD_MODELS_OPENROUTER_ANTHROPIC=(
  "anthropic/claude-sonnet-4.5"     "latest Sonnet, best coding+agents"
  "anthropic/claude-opus-4.6"       "most powerful, complex challenges"
  "anthropic/claude-opus-4.5"       "strong all-rounder"
  "anthropic/claude-opus-4.1"       "capable reasoning"
  "anthropic/claude-opus-4"         "first Opus 4"
  "anthropic/claude-sonnet-4"       "balanced, widely used"
  "anthropic/claude-haiku-4.5"      "fastest, cheapest"
)

WIZARD_MODELS_OPENAI=(
  "gpt-5.2"           "flagship, coding+agentic"
  "gpt-5.1"           "configurable reasoning effort"
  "gpt-5"             "previous gen intelligent reasoning"
  "gpt-5-mini"        "fast, cost-efficient"
  "gpt-5-nano"        "fastest, cheapest GPT-5"
  "gpt-4.1"           "smartest non-reasoning"
  "gpt-4.1-mini"      "smaller, faster GPT-4.1"
  "gpt-4.1-nano"      "fastest GPT-4.1"
  "o3"                "reasoning, complex tasks"
  "o4-mini"            "fast cost-efficient reasoning"
  "gpt-4o"            "legacy, still available"
)

WIZARD_MODELS_GEMINI=(
  "gemini-2.5-flash"               "best price/performance, stable"
  "gemini-3-pro-preview"           "most intelligent, preview"
  "gemini-3-flash-preview"         "fast+balanced, preview"
  "gemini-2.5-pro"                 "advanced thinking, stable"
  "gemini-2.5-flash-lite"          "ultra-fast, cheapest"
  "gemini-2.0-flash"               "previous gen (deprecates Mar 2026)"
)

WIZARD_MODELS_GROQ=(
  "llama-3.3-70b-versatile"                   "Meta 70B, 280 t/s, best quality"
  "llama-3.1-8b-instant"                      "Meta 8B, 560 t/s, ultra-fast"
  "openai/gpt-oss-120b"                       "OpenAI open-weight 120B, 500 t/s"
  "openai/gpt-oss-20b"                        "OpenAI open-weight 20B, 1000 t/s"
  "meta-llama/llama-4-maverick-17b-128e-instruct" "Llama 4 MoE, 600 t/s, preview"
  "meta-llama/llama-4-scout-17b-16e-instruct" "Llama 4 Scout, 750 t/s, preview"
  "qwen/qwen3-32b"                            "Alibaba 32B, 400 t/s, preview"
  "moonshotai/kimi-k2-instruct-0905"          "Moonshot Kimi K2, 200 t/s, preview"
)

WIZARD_MODELS_OLLAMA=(
  "qwen3:4b"                    "2.5GB — best all-round intelligence, dual-mode, 100+ languages"
  "phi4-mini"                   "3.3GB — best tool calling + agent restraint, stable English"
  "nanbeige4.1:3b"              "2.0GB — NEW Feb 2026, rivals 32B models, unified generalist"
  "gemma3:4b"                   "3.3GB — multimodal (understands images), strong general"
  "qwen3:1.7b"                  "1.0GB — ultra-light, good basics, 100+ languages"
  "smollm3:3b"                  "2.0GB — HuggingFace, reasoning + tool calling + multilingual"
  "lfm2.5:1.2b"                "0.8GB — fastest inference (1.5s CPU), hybrid architecture"
  "qwen3:0.6b"                  "0.4GB — 600M params, impossibly good tool calling for size"
  "deepseek-r1:1.5b"            "1.0GB — reasoning specialist, math focus"
  "gemma3:1b"                   "0.8GB — Google tiny, basic tasks"
  "llama3.2:3b"                 "2.0GB — Meta, solid instruction following"
  "mistral:7b"                  "4.1GB — classic workhorse (needs 8GB+ RAM, tight on 6GB)"
  "qwen3:8b"                    "4.7GB — most intelligent 8B (needs 8GB+ RAM, tight on 6GB)"
)

# ════════════════════════════════════════════════
# FORMATTING
# ════════════════════════════════════════════════
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; MAGENTA=$'\033[0;35m'
BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
CK="${GREEN}✔${NC}"; XK="${RED}✘${NC}"; AR="${CYAN}➜${NC}"
WN="${YELLOW}⚠${NC}"; IN="${BLUE}ℹ${NC}"

step()      { printf '%s\n' "${BLUE}${BOLD}━━━ $1: $2 ━━━${NC}"; }
info()      { printf '%s\n' "  ${IN} $1"; }
success()   { printf '%s\n' "  ${CK} $1"; }
warn()      { printf '%s\n' "  ${WN} $1"; }
die()       { printf '%s\n' "  ${XK} $1"; exit 1; }
separator() {
    printf '%s\n' "${DIM}  ──────────────────────────────────────────────${NC}"
}

# ════════════════════════════════════════════════
# JSON-SAFE STRING HELPER
# Escapes \ and " and strips control characters
# ════════════════════════════════════════════════
json_escape() {
    local s="$1"
    # Strip control characters (0x00-0x08, 0x0b, 0x0c, 0x0e-0x1f) via tr.
    # Single external call is faster than a pure-bash character loop for
    # string-level filtering. Keeps tab (0x09), newline (0x0a), CR (0x0d).
    s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
    # Escape backslashes and double quotes (pure bash, no fork)
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# ════════════════════════════════════════════════
# SHELL ESCAPE — sanitize values for single-quoted source'd conf files
# Transforms ' into '"'"' (end quote, literal quote, restart quote)
# ════════════════════════════════════════════════
shell_escape() {
    printf '%s' "${1//\'/\'\"\'\"\'}"
}

# ════════════════════════════════════════════════
# NODE.JS VERSION HELPER
# Returns the major version number of the installed Node.js (e.g. "20")
# ════════════════════════════════════════════════
_node_major() {
    local v
    v=$(node --version 2>/dev/null) || v="v0"
    v="${v#v}"
    printf '%s' "${v%%.*}"
}

# ════════════════════════════════════════════════
# INPUT HELPERS
# ════════════════════════════════════════════════
ask() {
    local prompt="$1" var_name="$2" default="${3:-}" secret="${4:-false}"

    if [[ "$CONFIG_LOADED" == "true" ]]; then
        local -n existing_value="$var_name" 2>/dev/null || true
        if [[ -n "${existing_value:-}" ]]; then
            if [[ "$secret" == "true" ]]; then
                printf '%s\n' "  ${AR} ${prompt}: ${GREEN}[from config]${NC}"
            else
                printf '%s\n' "  ${AR} ${prompt}: ${GREEN}${existing_value}${NC} ${DIM}[from config]${NC}"
            fi
            return 0
        fi
    fi

    if [[ -n "$default" && "$secret" != "true" ]]; then
        prompt="${prompt} ${DIM}[${default}]${NC}"
    fi
    printf '%s' "  ${AR} ${prompt}: "
    local input=""
    if [[ "$secret" == "true" ]]; then
        read -rs input || true
        echo ""
    else
        read -r input || true
    fi
    if [[ -z "$input" ]]; then
        input="$default"
    fi
    printf -v "$var_name" '%s' "$input"
}

ask_yn() {
    local prompt="$1" default="${2:-y}" var_name_upper="${3:-}"

    # If no explicit config key provided, derive from prompt (fallback only)
    if [[ -z "$var_name_upper" ]]; then
        var_name_upper="${prompt// /_}"
        var_name_upper="${var_name_upper//[^a-zA-Z0-9_]/}"
        var_name_upper="${var_name_upper^^}"
    fi

    if [[ "$CONFIG_LOADED" == "true" ]]; then
        local -n existing_bool="${var_name_upper}" 2>/dev/null || true
        if [[ -n "${existing_bool:-}" ]]; then
            local display_val="${existing_bool,,}"
            if [[ "$display_val" == "true" || "$display_val" == "y" || "$display_val" == "yes" ]]; then
                printf '%s\n' "  ${AR} ${prompt}: ${GREEN}yes${NC} ${DIM}[from config]${NC}"
                return 0
            else
                printf '%s\n' "  ${AR} ${prompt}: ${GREEN}no${NC} ${DIM}[from config]${NC}"
                return 1
            fi
        fi
    fi

    if [[ "$default" == "y" ]]; then
        prompt="${prompt} ${DIM}[Y/n]${NC}"
    else
        prompt="${prompt} ${DIM}[y/N]${NC}"
    fi
    printf '%s' "  ${AR} ${prompt}: "
    local input=""
    read -r input || true
    if [[ -z "$input" ]]; then
        input="$default"
    fi
    [[ "${input,,}" == "y" || "${input,,}" == "yes" ]]
}

# ════════════════════════════════════════════════
# MENU HELPER — validates input, re-prompts on bad choice
# ════════════════════════════════════════════════
ask_menu() {
    local var_name="$1" min="$2" max="$3" default="${4:-$min}"
    local choice=""
    while true; do
        ask "Choose (${min}-${max})" choice "$default"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= min && choice <= max )); then
            printf -v "$var_name" '%s' "$choice"
            return 0
        fi
        warn "Invalid option '${choice}' — please enter a number between ${min} and ${max}"
    done
}

# ════════════════════════════════════════════════
# USAGE — show help text
# ════════════════════════════════════════════════
show_usage() {
    printf '%s\n' "Atlas Installer — Full-featured PicoClaw Gateway Setup"
    printf '%s\n' ""
    printf '%s\n' "Usage:"
    printf '%s\n' "  bash atlas-install.sh                    # Interactive wizard"
    printf '%s\n' "  bash atlas-install.sh --config <yaml>    # Non-interactive install"
    printf '%s\n' "  bash atlas-install.sh --help             # Show this help"
    printf '%s\n' ""
    printf '%s\n' "Options:"
    printf '%s\n' "  --config <file>    Path to YAML config file for non-interactive install"
    printf '%s\n' "  --help             Display this help message"
    printf '%s\n' ""
    printf '%s\n' "Config file format (YAML):"
    printf '%s\n' "  install_from: binary              # or 'source'"
    printf '%s\n' "  setup_performance: true"
    printf '%s\n' "  llm_provider: openrouter"
    printf '%s\n' "  llm_api_key: sk-or-v1-..."
    printf '%s\n' "  llm_model: anthropic/claude-sonnet-4.5"
    printf '%s\n' "  max_tokens: 8192"
    printf '%s\n' "  temperature: 0.7"
    printf '%s\n' "  tg_enabled: true"
    printf '%s\n' "  tg_token: 123456:ABC..."
    printf '%s\n' "  tg_user_id: 5323045369"
    printf '%s\n' "  # ... (see documentation for full list)"
    printf '%s\n' ""
    exit 0
}

# ════════════════════════════════════════════════
# YAML PARSER — simple key: value extraction
# ════════════════════════════════════════════════
parse_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        printf '%s\n' "${RED}✘ Config file not found: ${config_file}${NC}" >&2
        exit 1
    fi

    # Allowlist of permitted config keys (uppercase). Only user-facing config
    # variables are accepted — internal constants like PICOCLAW_DL, checksums,
    # and download URLs are never overridable from config files.
    local -A ALLOWED_KEYS=(
        [INSTALL_FROM]=1 [SETUP_PERFORMANCE]=1
        [LLM_PROVIDER]=1 [LLM_API_KEY]=1 [LLM_MODEL]=1
        [LLM_API_BASE]=1 [MAX_TOKENS]=1 [TEMPERATURE]=1
        [MAX_TOOL_ITER]=1
        [GROQ_EXTRA_KEY]=1 [GROQ_EXTRA_ENABLED]=1
        [BRAVE_ENABLED]=1 [BRAVE_API_KEY]=1 [BRAVE_MAX_RESULTS]=1
        [TG_ENABLED]=1 [TG_TOKEN]=1 [TG_USER_ID]=1 [TG_USERNAME]=1
        [DC_ENABLED]=1 [DC_TOKEN]=1 [DC_USER_ID]=1 [DC_USERNAME]=1
        [WA_ENABLED]=1
        [FEISHU_ENABLED]=1 [FEISHU_APP_ID]=1 [FEISHU_APP_SECRET]=1
        [MAIXCAM_ENABLED]=1 [MAIXCAM_HOST]=1 [MAIXCAM_PORT]=1
        [SETUP_FTP]=1 [FTP_USER]=1 [FTP_PASS]=1 [FTP_PORT]=1
        [FTP_PASV_MIN]=1 [FTP_PASV_MAX]=1 [FTP_TLS]=1
        [SETUP_SYSTEMD]=1 [SETUP_AUTOBACKUP]=1 [SETUP_ATLAS]=1
        [SETUP_OLLAMA]=1 [OLLAMA_MODEL]=1 [OLLAMA_NUM_CTX]=1
        [GW_HOST]=1 [GW_PORT]=1
    )

    info "Loading config from: ${config_file}"

    local key value var_name
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip blank lines and comment-only lines
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            # Strip quotes first — quoted values preserve # characters
            if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            else
                # Unquoted: strip inline comments (space + #)
                value="${value%%[[:space:]]\#*}"
                value="${value%"${value##*[![:space:]]}"}"
                # Re-check for quotes after comment stripping (handles "" # comment)
                if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
                    value="${BASH_REMATCH[1]}"
                fi
            fi

            var_name="${key^^}"

            if [[ -z "${ALLOWED_KEYS[$var_name]+x}" ]]; then
                warn "Ignoring unknown config key: ${key}"
                continue
            fi

            printf -v "$var_name" '%s' "$value"
        fi
    done < "$config_file"

    # Normalize boolean fields to JSON-safe true/false
    local _bool_var
    for _bool_var in TG_ENABLED DC_ENABLED WA_ENABLED FS_ENABLED MC_ENABLED \
                     SETUP_FTP SETUP_PERFORMANCE SETUP_SYSTEMD SETUP_AUTOBACKUP \
                     SETUP_ATLAS SETUP_OLLAMA FTP_TLS GROQ_EXTRA_ENABLED \
                     BRAVE_ENABLED FEISHU_ENABLED MAIXCAM_ENABLED; do
        local -n _bref="$_bool_var" 2>/dev/null || continue
        local _bval="${_bref:-false}"
        case "${_bval,,}" in
            true|yes|y|1) _bref="true" ;;
            *)            _bref="false" ;;
        esac
    done

    # Map config keys to internal variable names where they differ
    # Feishu: config uses FEISHU_*, script uses FS_*
    if [[ -n "${FEISHU_ENABLED:-}" ]]; then FS_ENABLED="${FEISHU_ENABLED}"; fi
    if [[ -n "${FEISHU_APP_ID:-}" ]]; then FS_APP_ID="${FEISHU_APP_ID}"; fi
    if [[ -n "${FEISHU_APP_SECRET:-}" ]]; then FS_SECRET="${FEISHU_APP_SECRET}"; fi
    # MaixCAM: config uses MAIXCAM_*, script uses MC_*
    if [[ -n "${MAIXCAM_ENABLED:-}" ]]; then MC_ENABLED="${MAIXCAM_ENABLED}"; fi
    if [[ -n "${MAIXCAM_HOST:-}" ]]; then MC_HOST="${MAIXCAM_HOST}"; fi
    if [[ -n "${MAIXCAM_PORT:-}" ]]; then MC_PORT="${MAIXCAM_PORT}"; fi

    # Validate numeric fields — reset to defaults if malformed
    [[ "$MAX_TOKENS" =~ ^[0-9]+$ ]] || MAX_TOKENS=8192
    [[ "$TEMPERATURE" =~ ^[0-9]+(\.[0-9]+)?$ ]] || TEMPERATURE=0.7
    [[ "$MAX_TOOL_ITER" =~ ^[0-9]+$ ]] || MAX_TOOL_ITER=20
    [[ "$GW_PORT" =~ ^[0-9]+$ ]] || GW_PORT=18790
    [[ "$BRAVE_MAX_RESULTS" =~ ^[0-9]+$ ]] || BRAVE_MAX_RESULTS=5
    [[ "$MC_PORT" =~ ^[0-9]+$ ]] || MC_PORT=18790
    [[ "$FTP_PORT" =~ ^[0-9]+$ ]] || FTP_PORT=21
    [[ "$FTP_PASV_MIN" =~ ^[0-9]+$ ]] || FTP_PASV_MIN=40000
    [[ "$FTP_PASV_MAX" =~ ^[0-9]+$ ]] || FTP_PASV_MAX=40100
    [[ "$OLLAMA_NUM_CTX" =~ ^[0-9]+$ ]] || OLLAMA_NUM_CTX=8192

    success "Config loaded"
}

# ════════════════════════════════════════════════
# MODEL SELECTION HELPER
# ════════════════════════════════════════════════
select_model() {
    local var_name="$1"; shift
    local -a models=() descs=()
    while [[ $# -ge 2 ]]; do
        models+=("$1"); descs+=("$2"); shift 2
    done
    local count=${#models[@]}
    echo ""
    printf "  ${BOLD}Available models:${NC}\n"
    echo ""
    for i in "${!models[@]}"; do
        local num=$((i + 1))
        local marker=""
        if [[ $i -eq 0 ]]; then
            marker=" ${GREEN}★ recommended${NC}"
        fi
        printf "    ${CYAN}%2d${NC}) %-38s ${DIM}%s${NC}%b\n" "$num" "${models[$i]}" "${descs[$i]}" "$marker"
    done
    echo ""
    printf "    ${CYAN} c${NC}) Custom model ID\n"
    echo ""

    local choice=""
    while true; do
        ask "Choose (1-${count}, or c for custom)" choice "1"
        if [[ "$choice" == "c" || "$choice" == "C" ]]; then
            local custom_model=""
            while true; do
                ask "Enter model ID" custom_model ""
                if [[ -n "$custom_model" ]]; then
                    printf -v "$var_name" '%s' "$custom_model"
                    return 0
                fi
                warn "Model ID cannot be empty"
            done
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            printf -v "$var_name" '%s' "${models[$((choice - 1))]}"
            return 0
        else
            warn "Invalid option '${choice}' — enter 1-${count} or c for custom"
        fi
    done
}

# ════════════════════════════════════════════════
# WIZARD STATE (all global)
# CONFIG_LOADED is set to true only when --config is used.
# ask() and ask_yn() check this before treating existing values as overrides.
# ════════════════════════════════════════════════
CONFIG_LOADED=false
INSTALL_FROM="binary"
LLM_PROVIDER=""; LLM_API_KEY=""; LLM_API_BASE=""; LLM_MODEL=""
MAX_TOKENS="8192"; TEMPERATURE="0.7"; MAX_TOOL_ITER="20"
GROQ_EXTRA_KEY=""
BRAVE_API_KEY=""; BRAVE_MAX_RESULTS="5"
TG_ENABLED=false; TG_TOKEN=""; TG_USER_ID=""; TG_USERNAME=""
DC_ENABLED=false; DC_TOKEN=""; DC_USER_ID=""; DC_USERNAME=""
WA_ENABLED=false; WA_BRIDGE="ws://localhost:3001"; WA_USER_ID=""
FS_ENABLED=false; FS_APP_ID=""; FS_SECRET=""; FS_ENCRYPT=""; FS_VERIFY=""
MC_ENABLED=false; MC_HOST="0.0.0.0"; MC_PORT="18790"
GW_HOST="0.0.0.0"; GW_PORT="18790"
SETUP_SYSTEMD=true
SETUP_AUTOBACKUP=true; BACKUP_INTERVAL_DAYS="6"; BACKUP_MAX_KEEP="18"
SETUP_PERFORMANCE=true
SETUP_ATLAS=true
SETUP_FTP=false; FTP_USER="root"; FTP_PASS=""; FTP_PORT="21"
FTP_PASV_MIN="40000"; FTP_PASV_MAX="40100"; FTP_TLS=false
SETUP_OLLAMA=false; OLLAMA_MODEL=""; OLLAMA_NUM_CTX="8192"
_WIZ_CHOICE=""

# ════════════════════════════════════════════════
# BANNER
# ════════════════════════════════════════════════
banner() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        clear
    fi
    printf "${MAGENTA}${BOLD}\n"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║     🦞  PicoClaw — Full System Installer                 ║
    ║         Debian 13  •  Root  •  24/7  •  Reboot-safe      ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
EOF
    printf "${NC}\n"
    printf "  ${DIM}PicoClaw ${PICOCLAW_VERSION}  •  Go ${GO_VERSION}  •  $(date +%F)${NC}\n"
    printf "  ${DIM}https://github.com/sipeed/picoclaw${NC}\n"
    echo ""
}

# ════════════════════════════════════════════════
# PREFLIGHT
# ════════════════════════════════════════════════
preflight() {
    step "Pre-flight" "System Checks"

    if [[ $EUID -ne 0 ]]; then
        die "Must run as root"
    fi
    success "Running as root"

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${ID:-}" == "debian" ]] && { [[ "${VERSION_ID:-0}" -ge 13 ]] || [[ "${VERSION_CODENAME:-}" == "trixie" ]]; }; then
            success "Debian ${VERSION_ID:-13} (${VERSION_CODENAME:-trixie})"
        else
            warn "Detected: ${PRETTY_NAME:-unknown}. Script targets Debian 13."
            if [[ "$CONFIG_LOADED" == "true" ]]; then
                die "Config error: this script targets Debian 13 but detected ${PRETTY_NAME:-unknown}"
            fi
            ask_yn "Continue anyway?" "n" || exit 1
        fi
    else
        warn "Cannot detect OS — continuing"
    fi

    local ram_mb
    ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local disk_free
    disk_free=$(df -BG / | awk 'NR==2{gsub(/G/,"",$4); print $4}')
    success "RAM: ${ram_mb}MB  •  Disk: ${disk_free}GB free"

    if ! curl -sf --connect-timeout 5 https://github.com > /dev/null 2>&1; then
        if ! ping -c1 -W3 github.com &>/dev/null; then
            die "No internet — cannot reach github.com"
        fi
    fi
    success "Internet OK"
}

# ════════════════════════════════════════════════
# RESOLVE LATEST PICOCLAW VERSION
# ════════════════════════════════════════════════
resolve_picoclaw_latest() {
    step "Pre-flight" "Resolving Latest PicoClaw Version"

    local api_url="https://api.github.com/repos/sipeed/picoclaw/releases/latest"
    local release_json=""
    release_json=$(curl -sf --connect-timeout 10 --max-time 30 \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null) || true

    if [[ -z "$release_json" ]]; then
        release_json=$(curl -sf --connect-timeout 10 --max-time 30 \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/sipeed/picoclaw/releases" 2>/dev/null \
            | jq -r '[.[] | select(.prerelease == false and .draft == false)] | first // empty' 2>/dev/null) || true
    fi

    if [[ -z "$release_json" ]]; then
        warn "GitHub API unreachable — using fallback ${PICOCLAW_VERSION}"
        return 0
    fi

    local tag=""
    tag=$(printf '%s' "$release_json" | jq -r '.tag_name // empty' 2>/dev/null) || true

    if [[ -z "$tag" ]]; then
        warn "No tag in release response — using fallback ${PICOCLAW_VERSION}"
        return 0
    fi

    PICOCLAW_VERSION="$tag"
    PICOCLAW_DL="https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VERSION}"
    success "Latest release: ${BOLD}${PICOCLAW_VERSION}${NC}"

    # ── Try to load checksums from release assets ──
    local checksums_url=""
    checksums_url=$(printf '%s' "$release_json" | jq -r \
        '.assets[] | select(.name | test("checksums|sha256|SHA256"; "i")) | .browser_download_url' \
        2>/dev/null | head -1) || true

    if [[ -n "$checksums_url" ]]; then
        local checksums_body=""
        checksums_body=$(curl -sfL --connect-timeout 10 --max-time 30 "$checksums_url" 2>/dev/null) || true

        if [[ -n "$checksums_body" ]]; then
            local sha="" line_match

            line_match=$(echo "$checksums_body" | grep -i "picoclaw-linux-amd64") || true
            if [[ -n "$line_match" ]]; then
                read -r sha _ <<< "$line_match"
                [[ -n "$sha" ]] && PC_SHA_AMD64="$sha"
            fi

            line_match=$(echo "$checksums_body" | grep -i "picoclaw-linux-arm64") || true
            if [[ -n "$line_match" ]]; then
                read -r sha _ <<< "$line_match"
                [[ -n "$sha" ]] && PC_SHA_ARM64="$sha"
            fi

            line_match=$(echo "$checksums_body" | grep -i "picoclaw-linux-riscv64") || true
            if [[ -n "$line_match" ]]; then
                read -r sha _ <<< "$line_match"
                [[ -n "$sha" ]] && PC_SHA_RISCV64="$sha"
            fi

            success "SHA256 checksums loaded from release assets"
            return 0
        fi
    fi

    info "No checksums asset in release — verification will be skipped"
    PC_SHA_AMD64=""
    PC_SHA_ARM64=""
    PC_SHA_RISCV64=""
}

# ════════════════════════════════════════════════
# WIZARD
# ════════════════════════════════════════════════
wizard() {
    # Non-interactive mode: all values loaded by parse_config, skip wizard entirely
    if [[ "$CONFIG_LOADED" == "true" ]]; then
        info "Non-interactive mode — skipping wizard (all values from config)"

        # Auto-fill LLM_API_BASE from provider when not explicitly set
        if [[ -z "$LLM_API_BASE" ]]; then
            case "$LLM_PROVIDER" in
                openrouter) LLM_API_BASE="https://openrouter.ai/api/v1" ;;
                zhipu)      LLM_API_BASE="https://open.bigmodel.cn/api/paas/v4" ;;
                groq)       LLM_API_BASE="https://api.groq.com/openai/v1" ;;
                ollama)     LLM_API_BASE="${OLLAMA_API_BASE}" ;;
            esac
        fi
        if [[ "$LLM_PROVIDER" == "vllm" && -z "$LLM_API_BASE" ]]; then
            die "Config error: llm_api_base is required for provider 'vllm'"
        fi

        # Validate FTP password when FTP is enabled
        if [[ "${SETUP_FTP}" == "true" ]]; then
            if [[ -z "$FTP_PASS" ]]; then
                die "Config error: ftp_pass is required when setup_ftp is true"
            fi
            if [[ ${#FTP_PASS} -lt 8 ]]; then
                die "Config error: ftp_pass must be at least 8 characters"
            fi
        fi

        # Validate OLLAMA_NUM_CTX minimum
        if [[ "${SETUP_OLLAMA}" == "true" ]]; then
            if [[ "$OLLAMA_NUM_CTX" =~ ^[0-9]+$ ]] && (( OLLAMA_NUM_CTX < 8192 )); then
                warn "ollama_num_ctx (${OLLAMA_NUM_CTX}) below minimum 8192 — resetting to 8192"
                OLLAMA_NUM_CTX="8192"
            fi
        fi

        # Validate required LLM fields
        if [[ -z "$LLM_PROVIDER" ]]; then
            die "Config error: llm_provider is required"
        fi
        case "$LLM_PROVIDER" in
            openrouter|zhipu|openai|gemini|groq|vllm|ollama) ;;
            *) die "Config error: unsupported llm_provider '${LLM_PROVIDER}' (valid: openrouter, zhipu, openai, gemini, groq, vllm, ollama)" ;;
        esac
        if [[ "$LLM_PROVIDER" != "ollama" && "$LLM_PROVIDER" != "vllm" && -z "$LLM_API_KEY" ]]; then
            die "Config error: llm_api_key is required for provider '${LLM_PROVIDER}'"
        fi
        if [[ -z "$LLM_MODEL" ]]; then
            die "Config error: llm_model is required"
        fi

        # Validate required fields for enabled channels/features
        if [[ "${TG_ENABLED}" == "true" ]]; then
            [[ -n "$TG_TOKEN" ]] || die "Config error: tg_token is required when tg_enabled is true"
            [[ -n "$TG_USER_ID" ]] || die "Config error: tg_user_id is required when tg_enabled is true"
        fi
        if [[ "${DC_ENABLED}" == "true" ]]; then
            [[ -n "$DC_TOKEN" ]] || die "Config error: dc_token is required when dc_enabled is true"
            [[ -n "$DC_USER_ID" ]] || die "Config error: dc_user_id is required when dc_enabled is true"
        fi
        if [[ "${BRAVE_ENABLED}" == "true" ]]; then
            [[ -n "$BRAVE_API_KEY" ]] || die "Config error: brave_api_key is required when brave_enabled is true"
        fi
        if [[ "${GROQ_EXTRA_ENABLED}" == "true" ]]; then
            [[ -n "$GROQ_EXTRA_KEY" ]] || die "Config error: groq_extra_key is required when groq_extra_enabled is true"
        fi
        if [[ "${FEISHU_ENABLED}" == "true" ]]; then
            [[ -n "$FS_APP_ID" ]] || die "Config error: feishu_app_id is required when feishu_enabled is true"
            [[ -n "$FS_SECRET" ]] || die "Config error: feishu_app_secret is required when feishu_enabled is true"
        fi

        # Auto-link: ollama provider requires setup_ollama
        if [[ "$LLM_PROVIDER" == "ollama" && "$SETUP_OLLAMA" != "true" ]]; then
            info "llm_provider is 'ollama' — enabling setup_ollama automatically"
            SETUP_OLLAMA=true
        fi
        if [[ "$LLM_PROVIDER" == "ollama" && -z "$OLLAMA_MODEL" ]]; then
            OLLAMA_MODEL="$LLM_MODEL"
        fi

        return 0
    fi

    banner
    printf "  ${BOLD}Configuration Wizard${NC}\n"
    printf "  ${DIM}Answer the prompts. Press Enter for defaults.${NC}\n"
    printf "  ${DIM}All settings go to ${CONFIG_FILE}${NC}\n"
    echo ""
    printf "  ${DIM}Press Enter to start...${NC}"; read -r

    # ── 1. Install method ──
    step "1/14" "Install Method"
    printf "    ${CYAN}1${NC}) Pre-built binary  ${DIM}(~9MB download, fast, recommended)${NC}\n"
    printf "    ${CYAN}2${NC}) Build from source  ${DIM}(needs Go ${GO_VERSION}, ~2 min)${NC}\n"
    echo ""
    ask_menu _WIZ_CHOICE 1 2 1
    if [[ "$_WIZ_CHOICE" == "2" ]]; then
        INSTALL_FROM="source"
    else
        INSTALL_FROM="binary"
    fi
    separator

    # ── 2. System Performance ──
    step "2/14" "System Performance Optimizer"
    printf "  ${DIM}Dramatically improve your machine's performance with deep${NC}\n"
    printf "  ${DIM}kernel, network, memory, I/O, and storage optimizations.${NC}\n"
    printf "  ${BOLD}What it does:${NC}\n"
    printf "    ${GREEN}•${NC} TCP BBR congestion control (lower latency, higher throughput)\n"
    printf "    ${GREEN}•${NC} Kernel sysctl tuning (network buffers, connection limits, file handles)\n"
    printf "    ${GREEN}•${NC} Memory optimization (swappiness, dirty ratios, vfs cache pressure)\n"
    printf "    ${GREEN}•${NC} zram compressed swap (2-3x effective RAM on low-memory VPS)\n"
    printf "    ${GREEN}•${NC} I/O scheduler optimization (auto-detect SSD/HDD)\n"
    printf "    ${GREEN}•${NC} SSD TRIM scheduling (weekly fstrim for SSD longevity + speed)\n"
    printf "    ${GREEN}•${NC} tmpfs for /tmp (RAM-backed temp storage, zero disk I/O)\n"
    printf "    ${GREEN}•${NC} DNS optimization (Cloudflare 1.1.1.1 + Google 8.8.8.8)\n"
    printf "    ${GREEN}•${NC} File descriptor & process limits (1M+ open files)\n"
    printf "    ${GREEN}•${NC} Journald log size cap (prevent log bloat eating disk)\n"
    printf "    ${GREEN}•${NC} Disable unnecessary systemd services (bloat removal)\n"
    printf "    ${GREEN}•${NC} Filesystem noatime (reduce useless disk writes)\n"
    printf "    ${GREEN}•${NC} Systemd timeouts (faster boot/shutdown)\n"
    printf "    ${GREEN}•${NC} IRQ balancing for multi-core efficiency\n"
    echo ""
    printf "  ${DIM}All changes are persistent across reboots via /etc/sysctl.d/,${NC}\n"
    printf "  ${DIM}/etc/security/limits.d/, and systemd drop-ins.${NC}\n"
    printf "  ${DIM}Original values are backed up before any change.${NC}\n"
    echo ""
    printf "  ${YELLOW}${BOLD}Note:${NC} ${YELLOW}Selecting this will require a mandatory reboot at the end${NC}\n"
    printf "  ${YELLOW}of installation to fully activate all kernel-level optimizations.${NC}\n"
    if ask_yn "Optimize system performance?" "y" "SETUP_PERFORMANCE"; then
        SETUP_PERFORMANCE=true
    else
        SETUP_PERFORMANCE=false
    fi
    separator

    # ── 3. LLM Provider ──
    step "3/14" "LLM Provider"
    printf "  ${DIM}From pkg/config/config.go — 7 providers supported + local Ollama:${NC}\n"
    printf "    ${CYAN}1${NC}) OpenRouter       ${DIM}multi-model gateway (recommended)${NC}\n"
    printf "    ${CYAN}2${NC}) Zhipu            ${DIM}GLM models${NC}\n"
    printf "    ${CYAN}3${NC}) Anthropic        ${DIM}Claude (via OpenRouter — direct not supported)${NC}\n"
    printf "    ${CYAN}4${NC}) OpenAI           ${DIM}GPT${NC}\n"
    printf "    ${CYAN}5${NC}) Gemini           ${DIM}Google${NC}\n"
    printf "    ${CYAN}6${NC}) Groq             ${DIM}fast open-weight inference + free Whisper voice${NC}\n"
    printf "    ${CYAN}7${NC}) vLLM / Local     ${DIM}self-hosted (requires api_base URL)${NC}\n"
    printf "    ${CYAN}8${NC}) Ollama (Local)   ${DIM}run models locally on this machine — no API key needed${NC}\n"
    echo ""
    ask_menu _WIZ_CHOICE 1 8 1
    case "$_WIZ_CHOICE" in
        1)  LLM_PROVIDER="openrouter"; LLM_API_BASE="https://openrouter.ai/api/v1"
            ask "API key (https://openrouter.ai/keys)" LLM_API_KEY "" true
            select_model LLM_MODEL "${WIZARD_MODELS_OPENROUTER[@]}"
            ;;
        2)  LLM_PROVIDER="zhipu"; LLM_API_BASE="https://open.bigmodel.cn/api/paas/v4"
            ask "API key (https://bigmodel.cn/usercenter/proj-mgmt/apikeys)" LLM_API_KEY "" true
            select_model LLM_MODEL "${WIZARD_MODELS_ZHIPU[@]}"
            ;;
        3)  LLM_PROVIDER="openrouter"; LLM_API_BASE="https://openrouter.ai/api/v1"
            echo ""
            warn "PicoClaw uses OpenAI-compatible API (/chat/completions)."
            warn "Anthropic's direct API uses /v1/messages — incompatible."
            info "Your Claude models will be routed through ${BOLD}OpenRouter${NC} automatically."
            info "Get a free OpenRouter key at: ${CYAN}https://openrouter.ai/keys${NC}"
            echo ""
            ask "OpenRouter API key (https://openrouter.ai/keys)" LLM_API_KEY "" true
            select_model LLM_MODEL "${WIZARD_MODELS_OPENROUTER_ANTHROPIC[@]}"
            ;;
        4)  LLM_PROVIDER="openai"; LLM_API_BASE=""
            ask "API key (https://platform.openai.com)" LLM_API_KEY "" true
            select_model LLM_MODEL "${WIZARD_MODELS_OPENAI[@]}"
            ;;
        5)  LLM_PROVIDER="gemini"; LLM_API_BASE=""
            ask "API key (https://aistudio.google.com/api-keys)" LLM_API_KEY "" true
            select_model LLM_MODEL "${WIZARD_MODELS_GEMINI[@]}"
            ;;
        6)  LLM_PROVIDER="groq"; LLM_API_BASE="https://api.groq.com/openai/v1"
            ask "API key (https://console.groq.com)" LLM_API_KEY "" true
            select_model LLM_MODEL "${WIZARD_MODELS_GROQ[@]}"
            echo ""
            info "Groq models will be routed via the OpenRouter config slot"
            info "(PicoClaw workaround — Groq's API is OpenAI-compatible)"
            ;;
        7)  LLM_PROVIDER="vllm"; LLM_API_BASE=""
            ask "API base URL (e.g. http://localhost:8000/v1)" LLM_API_BASE ""
            ask "API key (optional)" LLM_API_KEY "" true
            ask "Model" LLM_MODEL "default"
            ;;
        8)  LLM_PROVIDER="ollama"; LLM_API_BASE="${OLLAMA_API_BASE}"
            LLM_API_KEY=""
            SETUP_OLLAMA=true
            echo ""
            info "Ollama runs models locally — no API key needed."
            info "Models are downloaded after installation."
            info "Ollama's API is OpenAI-compatible and routes via the vllm provider slot."
            echo ""
            select_model OLLAMA_MODEL "${WIZARD_MODELS_OLLAMA[@]}"
            LLM_MODEL="$OLLAMA_MODEL"
            echo ""
            printf "  ${DIM}PicoClaw's system prompt uses ~4000+ tokens (skills + tools).${NC}\n"
            printf "  ${DIM}Minimum: 8192. Use 8192 on 6GB RAM, 16384 on 8GB+, 32768 on 16GB+.${NC}\n"
            ask "Context window size" OLLAMA_NUM_CTX "8192"
            while true; do
                if [[ "$OLLAMA_NUM_CTX" =~ ^[0-9]+$ ]] && (( OLLAMA_NUM_CTX >= 8192 )); then
                    break
                fi
                warn "Context window must be a number >= 8192 (PicoClaw needs ~4000 tokens for system prompt)"
                ask "Context window size" OLLAMA_NUM_CTX "8192"
            done
            echo ""
            warn "Models are downloaded after installation (~0.4-5GB depending on model)."
            warn "Ensure you have enough disk space and a stable internet connection."
            ;;
    esac

    echo ""
    success "Selected: ${BOLD}${LLM_PROVIDER}${NC} → ${GREEN}${LLM_MODEL}${NC}"
    echo ""
    ask "Max tokens" MAX_TOKENS "8192"
    ask "Temperature (0.0–1.0)" TEMPERATURE "0.7"
    ask "Max tool iterations" MAX_TOOL_ITER "20"
    separator

    # ── 4. Groq voice transcription ──
    step "4/14" "Groq Voice Transcription (Optional)"
    printf "  ${DIM}Groq provides free Whisper transcription for Telegram/Discord voice.${NC}\n"
    if [[ "$LLM_PROVIDER" == "groq" ]]; then
        info "Already using Groq as primary — voice transcription included"
    else
        if ask_yn "Add Groq key for voice transcription?" "n" "GROQ_EXTRA_ENABLED"; then
            ask "Groq API key (https://console.groq.com)" GROQ_EXTRA_KEY "" true
        fi
    fi
    separator

    # ── 5. Brave Search ──
    step "5/14" "Web Search (Optional)"
    printf "  ${DIM}Brave Search API — 2000 free queries/month${NC}\n"
    printf "  ${DIM}https://brave.com/search/api${NC}\n"
    if ask_yn "Configure Brave Search?" "n" "BRAVE_ENABLED"; then
        ask "API key" BRAVE_API_KEY "" true
        ask "Max results per query" BRAVE_MAX_RESULTS "5"
    fi
    separator

    # ── 6. Telegram ──
    step "6/14" "Telegram Bot"
    printf "  ${DIM}Control PicoClaw from your phone via Telegram.${NC}\n"
    if ask_yn "Configure Telegram?" "y" "TG_ENABLED"; then
        TG_ENABLED=true
        printf "\n  ${DIM}Create: @BotFather → /newbot${NC}\n"
        printf "  ${DIM}Get ID: @userinfobot → your numeric ID${NC}\n"
        printf "  ${DIM}Get username: Telegram Settings → your @username (without the @)${NC}\n"
        ask "Bot token" TG_TOKEN "" true
        ask "Your user ID (numeric, e.g. 5323045369)" TG_USER_ID ""
        ask "Your Telegram username (without @, e.g. johndoe)" TG_USERNAME ""
        if [[ -n "$TG_USERNAME" ]]; then
            info "allow_from will be set to \"${TG_USER_ID}|${TG_USERNAME}\""
        fi
    fi
    separator

    # ── 7. Discord ──
    step "7/14" "Discord Bot (Optional)"
    printf "  ${DIM}https://discord.com/developers/applications${NC}\n"
    if ask_yn "Configure Discord?" "n" "DC_ENABLED"; then
        DC_ENABLED=true
        printf "\n  ${DIM}Create app → Bot → Copy token${NC}\n"
        printf "  ${DIM}Enable MESSAGE CONTENT INTENT in Bot settings${NC}\n"
        printf "  ${DIM}Get user ID: Settings → Advanced → Developer Mode → right-click avatar${NC}\n"
        printf "  ${DIM}Get username: your Discord username (not display name)${NC}\n"
        ask "Bot token" DC_TOKEN "" true
        ask "Your user ID" DC_USER_ID ""
        ask "Your Discord username (without #, e.g. johndoe)" DC_USERNAME ""
        if [[ -n "$DC_USERNAME" ]]; then
            info "allow_from will be set to \"${DC_USER_ID}|${DC_USERNAME}\""
        fi
    fi
    separator

    # ── 8. Other channels ──
    step "8/14" "Other Channels (Optional)"
    printf "  ${DIM}WhatsApp (needs bridge), Feishu/Lark, MaixCAM${NC}\n"

    # ── WhatsApp ──
    printf "  ${BOLD}WhatsApp${NC}\n"
    printf "  ${DIM}WhatsApp requires a Node.js bridge (Baileys) running alongside PicoClaw.${NC}\n"
    printf "  ${DIM}The bridge translates WhatsApp Web protocol ↔ WebSocket JSON for PicoClaw.${NC}\n"
    printf "  ${BOLD}How it works:${NC}\n"
    printf "    ${GREEN}•${NC} Node.js 20+ will be installed automatically\n"
    printf "    ${GREEN}•${NC} The Baileys bridge runs as a systemd service on a configurable port\n"
    printf "    ${GREEN}•${NC} PicoClaw gateway connects to the bridge via WebSocket\n"
    printf "    ${GREEN}•${NC} The bridge starts BEFORE the gateway (systemd dependency)\n"
    echo ""
    printf "  ${YELLOW}${BOLD}Important:${NC} ${YELLOW}After installation, you will be prompted to scan a QR code${NC}\n"
    printf "  ${YELLOW}to link your WhatsApp account. The QR scan is one-time; session persists.${NC}\n"
    printf "  ${DIM}Session can expire after ~14 days if your phone is offline.${NC}\n"
    echo ""
    if ask_yn "Configure WhatsApp?" "n" "WA_ENABLED"; then
        WA_ENABLED=true
        ask "Bridge port" WA_BRIDGE_PORT "3001"
        while true; do
            if [[ "$WA_BRIDGE_PORT" =~ ^[0-9]+$ ]] && (( WA_BRIDGE_PORT >= 1 && WA_BRIDGE_PORT <= 65535 )); then
                break
            fi
            warn "Port must be a number between 1 and 65535"
            ask "Bridge port" WA_BRIDGE_PORT "3001"
        done
        WA_BRIDGE="ws://localhost:${WA_BRIDGE_PORT}"
        ask "Your phone number (international format, e.g. +14155551234)" WA_USER_ID ""
        echo ""
        info "Bridge URL will be: ${BOLD}${WA_BRIDGE}${NC}"
        if [[ -n "$WA_USER_ID" ]]; then
            info "allow_from will include: ${BOLD}${WA_USER_ID}${NC}"
        fi
        echo ""
        info "QR login will be launched automatically during installation."
    fi
    echo ""

    if ask_yn "Configure Feishu (Lark)?" "n" "FEISHU_ENABLED"; then
        FS_ENABLED=true
        ask "App ID" FS_APP_ID ""
        ask "App Secret" FS_SECRET "" true
        ask "Encrypt Key (optional)" FS_ENCRYPT ""
        ask "Verification Token (optional)" FS_VERIFY ""
    fi
    echo ""

    if ask_yn "Configure MaixCAM?" "n" "MAIXCAM_ENABLED"; then
        MC_ENABLED=true
        ask "Listen host" MC_HOST "0.0.0.0"
        ask "Listen port" MC_PORT "18790"
    fi
    separator

    # ── 9. Gateway ──
    step "9/14" "Gateway Settings"
    printf "  ${DIM}Gateway binds to host:port for all channel traffic.${NC}\n"
    ask "Host" GW_HOST "0.0.0.0"
    ask "Port" GW_PORT "18790"
    separator

    # ── 10. FTP Server ──
    step "10/14" "FTP Server"
    printf "  ${DIM}Full-access FTP server for remote file management.${NC}\n"
    printf "  ${DIM}Uses vsftpd — lightweight, secure, systemd-managed.${NC}\n"
    printf "  ${BOLD}What it does:${NC}\n"
    printf "    ${GREEN}•${NC} Creates a dedicated FTP user with full filesystem access\n"
    printf "    ${GREEN}•${NC} Configurable username, password, and port\n"
    printf "    ${GREEN}•${NC} Optional TLS encryption (self-signed certificate)\n"
    printf "    ${GREEN}•${NC} Passive mode with configurable port range\n"
    printf "    ${GREEN}•${NC} Managed via systemd (starts on boot, auto-restarts)\n"
    printf "    ${GREEN}•${NC} CLI management: ${CYAN}picoclaw ftp${NC}\n"
    echo ""
    printf "  ${YELLOW}⚠ The FTP user will have read/write access to the ENTIRE filesystem.${NC}\n"
    printf "  ${YELLOW}  Only enable this if you trust your network or use TLS + strong password.${NC}\n"
    echo ""
    if ask_yn "Configure FTP server?" "y" "SETUP_FTP"; then
        SETUP_FTP=true
        echo ""
        ask "FTP username" FTP_USER "root"
        while true; do
            ask "FTP password (min 8 characters)" FTP_PASS "" true
            if [[ ${#FTP_PASS} -lt 8 ]]; then
                warn "Password must be at least 8 characters"
                continue
            fi
            local FTP_PASS_CONFIRM=""
            ask "Confirm password" FTP_PASS_CONFIRM "" true
            if [[ "$FTP_PASS" == "$FTP_PASS_CONFIRM" ]]; then
                break
            fi
            warn "Passwords do not match — try again"
        done
        ask "FTP port" FTP_PORT "21"
        while true; do
            if [[ "$FTP_PORT" =~ ^[0-9]+$ ]] && (( FTP_PORT >= 1 && FTP_PORT <= 65535 )); then
                break
            fi
            warn "Port must be a number between 1 and 65535"
            ask "FTP port" FTP_PORT "21"
        done
        ask "Passive mode min port" FTP_PASV_MIN "40000"
        ask "Passive mode max port" FTP_PASV_MAX "40100"
        echo ""
        printf "  ${DIM}TLS encrypts FTP traffic. A self-signed certificate will be generated.${NC}\n"
        printf "  ${DIM}Recommended if FTP is exposed to the internet.${NC}\n"
        if ask_yn "Enable TLS encryption?" "y" "FTP_TLS"; then
            FTP_TLS=true
        else
            FTP_TLS=false
        fi
    fi
    separator

    # ── 11. Systemd ──
    step "11/14" "24/7 Service"
    printf "  ${DIM}systemd service + watchdog timer + cron @reboot fallback${NC}\n"
    if ask_yn "Enable 24/7 systemd service?" "y" "SETUP_SYSTEMD"; then
        SETUP_SYSTEMD=true
    else
        SETUP_SYSTEMD=false
    fi
    separator

    # ── 12. Backup ──
    step "12/14" "Automatic Backups"
    printf "  ${DIM}Full snapshot of config, workspace, skills, binary, and systemd units${NC}\n"
    printf "  ${DIM}Stored in ${BACKUP_DIR}/backup_MMddyy_HHmmss/${NC}\n"
    printf "  ${DIM}Old backups are automatically purged beyond max retention count.${NC}\n"
    if ask_yn "Enable automatic backups?" "y" "SETUP_AUTOBACKUP"; then
        SETUP_AUTOBACKUP=true
        ask "Backup every N days" BACKUP_INTERVAL_DAYS "6"
        while true; do
            if [[ "$BACKUP_INTERVAL_DAYS" =~ ^[1-9][0-9]*$ ]]; then
                break
            fi
            warn "Must be a positive integer (e.g. 6)"
            ask "Backup every N days" BACKUP_INTERVAL_DAYS "6"
        done
        ask "Max backups to keep (oldest purged beyond this)" BACKUP_MAX_KEEP "18"
        while true; do
            if [[ "$BACKUP_MAX_KEEP" =~ ^[1-9][0-9]*$ ]]; then
                break
            fi
            warn "Must be a positive integer (e.g. 18)"
            ask "Max backups to keep" BACKUP_MAX_KEEP "18"
        done
    else
        SETUP_AUTOBACKUP=false
    fi
    separator

    # ── 13. Atlas Skills ──
    step "13/14" "Atlas Skills Repository"
    printf "  ${DIM}Atlas is a community repository of skills for PicoClaw.${NC}\n"
    printf "  ${DIM}${ATLAS_REPO_URL}${NC}\n"
    printf "  ${BOLD}What it does:${NC}\n"
    printf "    ${GREEN}•${NC} Dynamically discovers all available skills from the Atlas repository\n"
    printf "    ${GREEN}•${NC} Downloads and installs every skill into your workspace\n"
    printf "    ${GREEN}•${NC} Each skill follows the AgentSkills standard (SKILL.md + references)\n"
    printf "    ${GREEN}•${NC} Skills extend what your PicoClaw agent can do\n"
    printf "    ${GREEN}•${NC} Includes management CLI: ${CYAN}picoclaw atlas${NC}\n"
    echo ""
    printf "  ${DIM}Skills are discovered at install time via the GitHub API.${NC}\n"
    printf "  ${DIM}Nothing is hardcoded — any new skill added to the repository${NC}\n"
    printf "  ${DIM}will be automatically found and installed.${NC}\n"
    echo ""
    if ask_yn "Install all Atlas skills?" "y" "SETUP_ATLAS"; then
        SETUP_ATLAS=true
    else
        SETUP_ATLAS=false
    fi
    separator

    # ── 14. Summary ──
    step "14/14" "Review & Confirm"
    printf '%s\n' "  ${BOLD}Summary${NC}"
    printf '%s\n' "  Install:     ${INSTALL_FROM}"
    printf '%s\n' "  Performance: ${SETUP_PERFORMANCE}"
    if [[ "$SETUP_PERFORMANCE" == "true" ]]; then
        printf '%s\n' "               ${YELLOW}→ mandatory reboot after installation${NC}"
    fi
    printf '%s\n' "  Provider:    ${LLM_PROVIDER} → ${BOLD}${LLM_MODEL}${NC}"
    if [[ -n "$LLM_API_BASE" ]]; then printf '%s\n' "  API base:    ${LLM_API_BASE}"; fi
    if [[ "$SETUP_OLLAMA" == "true" ]]; then
        printf '%s\n' "  Ollama:      ${GREEN}enabled${NC} (model: ${BOLD}${OLLAMA_MODEL}${NC}, ctx: ${OLLAMA_NUM_CTX})"
        printf '%s\n' "               ${DIM}API: ${OLLAMA_API_BASE} (routed via vllm slot)${NC}"
        printf '%s\n' "               ${YELLOW}→ model download ~0.4-5GB after installation${NC}"
    fi
    if [[ -n "$GROQ_EXTRA_KEY" ]]; then printf '%s\n' "  Groq voice:  configured"; fi
    if [[ -n "$BRAVE_API_KEY" ]]; then printf '%s\n' "  Brave:       configured"; fi
    printf '%s\n' "  Telegram:    ${TG_ENABLED}"
    if [[ "$TG_ENABLED" == "true" && -n "$TG_USERNAME" ]]; then
        printf '%s\n' "               ${DIM}user: ${TG_USER_ID}|${TG_USERNAME}${NC}"
    fi
    printf '%s\n' "  Discord:     ${DC_ENABLED}"
    if [[ "$DC_ENABLED" == "true" && -n "$DC_USERNAME" ]]; then
        printf '%s\n' "               ${DIM}user: ${DC_USER_ID}|${DC_USERNAME}${NC}"
    fi
    printf '%s\n' "  WhatsApp:    ${WA_ENABLED}"
    if [[ "$WA_ENABLED" == "true" ]]; then
        printf '%s\n' "               ${DIM}bridge: ${WA_BRIDGE} (port ${WA_BRIDGE_PORT})${NC}"
        if [[ -n "$WA_USER_ID" ]]; then
            printf '%s\n' "               ${DIM}user: ${WA_USER_ID}${NC}"
        fi
        printf '%s\n' "               ${YELLOW}→ QR login will be launched automatically during install${NC}"
    fi
    printf '%s\n' "  Feishu:      ${FS_ENABLED}"
    printf '%s\n' "  MaixCAM:     ${MC_ENABLED}"
    printf '%s\n' "  Gateway:     ${GW_HOST}:${GW_PORT}"
    if [[ "$SETUP_FTP" == "true" ]]; then
        printf '%s\n' "  FTP:         ${GREEN}enabled${NC} (user: ${FTP_USER}, port: ${FTP_PORT}, TLS: ${FTP_TLS})"
    else
        printf '%s\n' "  FTP:         disabled"
    fi
    printf '%s\n' "  Systemd:     ${SETUP_SYSTEMD}"
    if [[ "$SETUP_AUTOBACKUP" == "true" ]]; then
        printf '%s\n' "  Backup:      every ${BACKUP_INTERVAL_DAYS} days, keep last ${BACKUP_MAX_KEEP}"
    else
        printf '%s\n' "  Backup:      manual only (picoclaw backup)"
    fi
    printf '%s\n' "  Atlas:       ${SETUP_ATLAS}"
    printf '%s\n' "  User:        ${BOLD}root (full access)${NC}"
    echo ""
    ask_yn "Install now?" "y" || { echo "  Cancelled."; exit 0; }
}

# ════════════════════════════════════════════════
# STEP 1: SYSTEM UPDATE + PACKAGES
# ════════════════════════════════════════════════
install_system() {
    step "1/14" "System Update & Packages"

    info "Updating package lists..."
    apt-get update -qq || die "apt-get update failed"
    success "Package lists updated"

    info "Upgrading all installed packages..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 2>&1 | tail -1 || true
    success "System upgraded"

    info "Installing required packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        build-essential ca-certificates cmake cron curl git jq make wget \
        > /dev/null 2>&1 || die "Package install failed"
    success "All dependencies installed"

    # ── Node.js for WhatsApp bridge ──
    if [[ "$WA_ENABLED" == "true" ]]; then
        info "WhatsApp enabled — checking Node.js..."
        local need_node=true
        if command -v node &>/dev/null; then
            local node_ver=""
            node_ver=$(_node_major)
            if [[ "$node_ver" =~ ^[0-9]+$ ]] && (( node_ver >= 20 )); then
                need_node=false
                success "Node.js $(node --version) already installed (>= 20 OK)"
            else
                info "Found Node.js v${node_ver}, need >= 20 — upgrading..."
            fi
        fi

        if [[ "$need_node" == "true" ]]; then
            info "Installing Node.js 20.x from NodeSource..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1 \
                || die "NodeSource setup failed"
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs > /dev/null 2>&1 \
                || die "Node.js install failed"

            local installed_ver=""
            installed_ver=$(_node_major)
            if [[ "$installed_ver" =~ ^[0-9]+$ ]] && (( installed_ver >= 20 )); then
                success "Node.js $(node --version) installed"
            else
                die "Node.js install failed — got version $(node --version 2>/dev/null || echo 'unknown')"
            fi
        fi

        if command -v npm &>/dev/null; then
            success "npm $(npm --version 2>/dev/null) available"
        else
            die "npm not found after Node.js install"
        fi
    fi
}

# ════════════════════════════════════════════════
# STEP 2: SYSTEM PERFORMANCE OPTIMIZER
# ════════════════════════════════════════════════
optimize_system() {
    step "2/14" "System Performance Optimizer"

    if [[ "$SETUP_PERFORMANCE" != "true" ]]; then
        info "Skipped — performance optimization not selected"
        return 0
    fi

    local total_ram_kb
    total_ram_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    local total_ram_mb=$((total_ram_kb / 1024))
    local num_cpus
    num_cpus=$(nproc 2>/dev/null || echo 1)

    info "Detected: ${total_ram_mb}MB RAM, ${num_cpus} CPU(s)"
    info "Backing up current settings..."

    # ── Backup originals ──
    local bk_dir="/root/.picoclaw/perf_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bk_dir"
    cp /etc/sysctl.conf "$bk_dir/sysctl.conf.bak" 2>/dev/null || true
    if [[ -f /etc/security/limits.conf ]]; then
        cp /etc/security/limits.conf "$bk_dir/limits.conf.bak" 2>/dev/null || true
    fi
    if [[ -f /etc/fstab ]]; then
        cp /etc/fstab "$bk_dir/fstab.bak" 2>/dev/null || true
    fi
    if [[ -f /etc/systemd/journald.conf ]]; then
        cp /etc/systemd/journald.conf "$bk_dir/journald.conf.bak" 2>/dev/null || true
    fi
    if [[ -f /etc/systemd/system.conf ]]; then
        cp /etc/systemd/system.conf "$bk_dir/system.conf.bak" 2>/dev/null || true
    fi
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf "$bk_dir/resolv.conf.bak" 2>/dev/null || true
    fi
    success "Originals backed up → ${bk_dir}"

    # ── Calculate dynamic values based on RAM ──
    local min_free_kb=$((total_ram_kb / 64))
    if [[ $min_free_kb -lt 32768 ]]; then min_free_kb=32768; fi
    if [[ $min_free_kb -gt 262144 ]]; then min_free_kb=262144; fi

    local dirty_bg_bytes=52428800
    local dirty_bytes=209715200
    if [[ $total_ram_mb -le 512 ]]; then
        dirty_bg_bytes=16777216
        dirty_bytes=67108864
    elif [[ $total_ram_mb -le 2048 ]]; then
        dirty_bg_bytes=33554432
        dirty_bytes=134217728
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2a. KERNEL SYSCTL TUNING
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Applying kernel sysctl optimizations..."

    cat > /etc/sysctl.d/99-picoclaw-performance.conf << SYSEOF
# ═══════════════════════════════════════════════════════
# PicoClaw System Performance Tuning
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# RAM: ${total_ram_mb}MB  CPUs: ${num_cpus}
# ═══════════════════════════════════════════════════════

# ── TCP CONGESTION CONTROL ──
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ── NETWORK BUFFER SIZES ──
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1310720
net.core.wmem_default = 1310720
net.ipv4.tcp_rmem = 4096 262144 67108864
net.ipv4.tcp_wmem = 4096 262144 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.core.optmem_max = 65536

# ── TCP CONNECTION TUNING ──
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 2
net.ipv4.tcp_base_mss = 1240
net.ipv4.tcp_notsent_lowat = 131072

# ── TCP TIMEOUT / KEEPALIVE ──
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1

# ── TCP SECURITY ──
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# ── IPv6 ──
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.route.max_size = 2147483647

# ── MEMORY MANAGEMENT ──
vm.swappiness = 10
vm.dirty_background_bytes = ${dirty_bg_bytes}
vm.dirty_bytes = ${dirty_bytes}
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 200
vm.min_free_kbytes = ${min_free_kb}
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 0
vm.max_map_count = 1048576

# ── FILE DESCRIPTORS / INOTIFY ──
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1048576
fs.inotify.max_queued_events = 1048576

# ── KERNEL STABILITY ──
kernel.panic = 10
kernel.panic_on_oops = 1
kernel.sysrq = 1
SYSEOF

    modprobe tcp_bbr 2>/dev/null || true
    if ! grep -q "tcp_bbr" /etc/modules-load.d/*.conf 2>/dev/null; then
        echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    fi

    sysctl --system > /dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-picoclaw-performance.conf > /dev/null 2>&1 || true

    local active_cc=""
    active_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) || true
    if [[ "$active_cc" == "bbr" ]]; then
        success "TCP BBR congestion control: active"
    else
        warn "TCP BBR: loaded module but kernel reports '${active_cc}' (will activate after reboot)"
    fi
    success "Sysctl: 60+ kernel parameters optimized"

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2b. FILE DESCRIPTOR & PROCESS LIMITS
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Setting file descriptor & process limits..."

    cat > /etc/security/limits.d/99-picoclaw-performance.conf << 'LIMEOF'
# PicoClaw Performance Limits
*               soft    nofile          1048576
*               hard    nofile          1048576
root            soft    nofile          1048576
root            hard    nofile          1048576
*               soft    nproc           524288
*               hard    nproc           524288
root            soft    nproc           524288
root            hard    nproc           524288
*               hard    memlock         2147484
*               soft    memlock         2147484
*               hard    core            0
*               soft    core            0
LIMEOF

    success "File limits: 1M open files, 512K processes per user"

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2c. I/O SCHEDULER OPTIMIZATION
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Optimizing I/O scheduler..."

    local has_ssd=false
    local has_hdd=false
    for dev in /sys/block/sd* /sys/block/nvme* /sys/block/vd* /sys/block/xvd*; do
        if [[ -f "${dev}/queue/rotational" ]]; then
            local rot
            rot=$(cat "${dev}/queue/rotational" 2>/dev/null) || continue
            if [[ "$rot" == "0" ]]; then
                has_ssd=true
            else
                has_hdd=true
            fi
        fi
    done

    cat > /etc/udev/rules.d/60-picoclaw-ioscheduler.rules << 'IOEOF'
# PicoClaw I/O Scheduler Rules
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]|xvd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
IOEOF

    for dev in /sys/block/sd* /sys/block/nvme* /sys/block/vd* /sys/block/xvd*; do
        if [[ -f "${dev}/queue/scheduler" ]]; then
            local devname
            devname="${dev##*/}"
            local rot="1"
            rot=$(cat "${dev}/queue/rotational" 2>/dev/null) || rot="1"
            if [[ "$devname" == nvme* ]]; then
                echo "none" > "${dev}/queue/scheduler" 2>/dev/null || true
            elif [[ "$rot" == "0" ]]; then
                echo "mq-deadline" > "${dev}/queue/scheduler" 2>/dev/null || true
            else
                echo "bfq" > "${dev}/queue/scheduler" 2>/dev/null || true
            fi
        fi
    done

    for dev in /sys/block/sd* /sys/block/nvme* /sys/block/vd* /sys/block/xvd*; do
        if [[ -f "${dev}/queue/read_ahead_kb" ]]; then
            echo 2048 > "${dev}/queue/read_ahead_kb" 2>/dev/null || true
        fi
    done

    if [[ "$has_ssd" == "true" && "$has_hdd" == "true" ]]; then
        success "I/O scheduler: mq-deadline (SSD) + bfq (HDD) + 2MB readahead"
    elif [[ "$has_ssd" == "true" ]]; then
        success "I/O scheduler: mq-deadline (SSD detected) + 2MB readahead"
    else
        success "I/O scheduler: bfq (HDD/virtual) + 2MB readahead"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2d. SSD TRIM
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    if [[ "$has_ssd" == "true" ]]; then
        info "Enabling weekly SSD TRIM..."
        systemctl enable --now fstrim.timer 2>/dev/null || true
        success "SSD TRIM: fstrim.timer enabled (weekly)"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2e. FILESYSTEM NOATIME
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Optimizing filesystem mount options..."

    if [[ -f /etc/fstab ]]; then
        local fstab_changed=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*# || -z "$line" ]]; then
                continue
            fi
            local mount_point mount_opts
            local -a fields
            read -ra fields <<< "$line"
            mount_point="${fields[1]}"
            mount_opts="${fields[3]}"
            if [[ "$mount_point" == "/" || "$mount_point" == "/home" ]]; then
                if ! echo "$mount_opts" | grep -q "noatime"; then
                    sed -i "s|${mount_opts}|${mount_opts},noatime|" /etc/fstab 2>/dev/null || true
                    fstab_changed=true
                fi
            fi
        done < /etc/fstab

        mount -o remount,noatime / 2>/dev/null || true

        if [[ "$fstab_changed" == "true" ]]; then
            success "Filesystem: noatime added (reduces ~50% disk writes from atime updates)"
        else
            success "Filesystem: noatime already configured"
        fi
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2f. TMPFS FOR /tmp
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Configuring tmpfs for /tmp..."

    local tmpfs_mb=$((total_ram_mb / 4))
    if [[ $tmpfs_mb -lt 256 ]]; then tmpfs_mb=256; fi
    if [[ $tmpfs_mb -gt 2048 ]]; then tmpfs_mb=2048; fi

    if ! grep -q "^tmpfs.*/tmp" /etc/fstab 2>/dev/null; then
        echo "tmpfs   /tmp   tmpfs   defaults,noatime,nosuid,nodev,size=${tmpfs_mb}M   0  0" >> /etc/fstab
        mount -o remount /tmp 2>/dev/null || mount tmpfs /tmp -t tmpfs -o defaults,noatime,nosuid,nodev,size=${tmpfs_mb}M 2>/dev/null || true
        success "tmpfs /tmp: ${tmpfs_mb}MB RAM-backed (zero disk I/O for temp files)"
    else
        success "tmpfs /tmp: already configured"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2g. ZRAM COMPRESSED SWAP
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Setting up zram compressed swap..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zram-tools > /dev/null 2>&1 || true

    local zram_percent=50
    if [[ $total_ram_mb -le 512 ]]; then
        zram_percent=75
    elif [[ $total_ram_mb -le 1024 ]]; then
        zram_percent=60
    fi

    if command -v zramctl &>/dev/null; then
        if [[ -f /etc/default/zramswap ]]; then
            cat > /etc/default/zramswap << ZRAMEOF
# PicoClaw zram configuration
PERCENT=${zram_percent}
ALGO=zstd
PRIORITY=100
ZRAMEOF
            systemctl restart zramswap 2>/dev/null || true
            systemctl enable zramswap 2>/dev/null || true
            local zram_size_mb=$((total_ram_mb * zram_percent / 100))
            success "zram: ${zram_size_mb}MB compressed swap (${zram_percent}% of RAM, zstd, ~2-3x effective)"
        else
            modprobe zram 2>/dev/null || true
            if [[ -f /sys/block/zram0/disksize ]]; then
                local zram_bytes=$((total_ram_kb * 1024 * zram_percent / 100))
                if ! swapon --show=NAME,TYPE 2>/dev/null | grep -q "zram"; then
                    swapoff /dev/zram0 2>/dev/null || true
                    echo 1 > /sys/block/zram0/reset 2>/dev/null || true
                    echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true
                    echo "$zram_bytes" > /sys/block/zram0/disksize 2>/dev/null || true
                    mkswap /dev/zram0 > /dev/null 2>&1 || true
                    swapon -p 100 /dev/zram0 2>/dev/null || true
                fi
                success "zram: manual setup (${zram_percent}% of RAM)"
            else
                warn "zram: kernel module not available"
            fi
        fi
    else
        warn "zram: zram-tools not available (continuing without)"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2h. DNS OPTIMIZATION
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Optimizing DNS resolution..."

    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/picoclaw-dns.conf << 'DNSEOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4
FallbackDNS=9.9.9.9 149.112.112.112
Cache=yes
CacheFromLocalhost=yes
DNSOverTLS=opportunistic
DNSEOF
        systemctl restart systemd-resolved 2>/dev/null || true
        success "DNS: Cloudflare 1.1.1.1 + Google 8.8.8.8 (via systemd-resolved, DoT)"
    else
        if [[ ! -L /etc/resolv.conf ]] || readlink /etc/resolv.conf | grep -q "systemd" 2>/dev/null; then
            local resolv_changed=false
            if ! grep -q "1.1.1.1" /etc/resolv.conf 2>/dev/null; then
                local tmp_resolv
                tmp_resolv=$(mktemp)
                echo "# PicoClaw optimized DNS" > "$tmp_resolv"
                echo "nameserver 1.1.1.1" >> "$tmp_resolv"
                echo "nameserver 8.8.8.8" >> "$tmp_resolv"
                echo "nameserver 1.0.0.1" >> "$tmp_resolv"
                echo "options timeout:2 attempts:3 rotate" >> "$tmp_resolv"
                grep -E "^(search|domain)" /etc/resolv.conf >> "$tmp_resolv" 2>/dev/null || true
                cp "$tmp_resolv" /etc/resolv.conf 2>/dev/null || true
                rm -f "$tmp_resolv"
                resolv_changed=true
            fi
            if [[ "$resolv_changed" == "true" ]]; then
                success "DNS: Cloudflare 1.1.1.1 + Google 8.8.8.8 (via resolv.conf)"
            else
                success "DNS: Cloudflare already configured"
            fi
        else
            info "DNS: resolv.conf managed externally — skipping"
        fi
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2i. JOURNALD LOG SIZE CAP
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Capping journald log size..."

    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/picoclaw-size.conf << 'JDEOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
SystemMaxFileSize=50M
Compress=yes
ForwardToSyslog=no
JDEOF

    systemctl restart systemd-journald 2>/dev/null || true
    journalctl --vacuum-size=200M > /dev/null 2>&1 || true
    success "Journald: capped at 200MB persistent + 50MB runtime"

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2j. SYSTEMD TIMEOUT OPTIMIZATION
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Optimizing systemd timeouts..."

    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/picoclaw-timeouts.conf << 'TMEOF'
[Manager]
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
DefaultDeviceTimeoutSec=10s
TMEOF

    systemctl daemon-reexec 2>/dev/null || true
    success "Systemd: start=15s, stop=10s, device=10s (faster boot/shutdown)"

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2k. DISABLE UNNECESSARY SERVICES
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Disabling unnecessary services..."

    local -a disable_services=(
        "ModemManager.service"
        "avahi-daemon.service"
        "bluetooth.service"
        "cups.service"
        "cups-browsed.service"
        "brltty.service"
        "pcscd.service"
        "packagekit.service"
        "multipathd.service"
        "lvm2-monitor.service"
        "dm-event.service"
        "fwupd.service"
        "udisks2.service"
        "accounts-daemon.service"
        "switcheroo-control.service"
        "power-profiles-daemon.service"
        "thermald.service"
        "colord.service"
        "geoclue.service"
    )

    local disabled_count=0
    for svc in "${disable_services[@]}"; do
        local state
        state=$(systemctl is-enabled "$svc" 2>/dev/null) || state="disabled"
        if [[ "$state" == "enabled" || "$state" == "static" ]]; then
            systemctl disable --now "$svc" 2>/dev/null || true
            systemctl mask "$svc" 2>/dev/null || true
            disabled_count=$((disabled_count + 1))
        fi
    done

    local -a disable_timers=(
        "apt-daily.timer"
        "apt-daily-upgrade.timer"
        "motd-news.timer"
    )

    for tmr in "${disable_timers[@]}"; do
        local state
        state=$(systemctl is-enabled "$tmr" 2>/dev/null) || state="disabled"
        if [[ "$state" == "enabled" || "$state" == "static" ]]; then
            systemctl disable --now "$tmr" 2>/dev/null || true
            disabled_count=$((disabled_count + 1))
        fi
    done

    if [[ $disabled_count -gt 0 ]]; then
        success "Disabled ${disabled_count} unnecessary service(s)/timer(s)"
    else
        success "No unnecessary services found (already clean)"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2l. IRQ BALANCING
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    if [[ $num_cpus -gt 1 ]]; then
        info "Configuring IRQ balancing for ${num_cpus} CPUs..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq irqbalance > /dev/null 2>&1 || true
        if command -v irqbalance &>/dev/null; then
            systemctl enable --now irqbalance 2>/dev/null || true
            success "IRQ balance: active (distributes interrupts across ${num_cpus} CPUs)"
        fi
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2m. ENABLE MGLRU
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Enabling Multi-Gen LRU (if supported)..."

    if [[ -f /sys/kernel/mm/lru_gen/enabled ]]; then
        echo 7 > /sys/kernel/mm/lru_gen/enabled 2>/dev/null || true
        mkdir -p /etc/tmpfiles.d
        cat > /etc/tmpfiles.d/picoclaw-mglru.conf << 'MGLEOF'
w /sys/kernel/mm/lru_gen/enabled - - - - 7
w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 0
MGLEOF
        success "MGLRU: enabled (better memory reclaim under pressure)"
    else
        info "MGLRU: not supported on this kernel (skipped)"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2n. KERNEL SAMEPAGE MERGING (KSM)
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    if [[ -f /sys/kernel/mm/ksm/run ]]; then
        echo 1 > /sys/kernel/mm/ksm/run 2>/dev/null || true
        echo 300 > /sys/kernel/mm/ksm/pages_to_scan 2>/dev/null || true
        cat > /etc/tmpfiles.d/picoclaw-ksm.conf << 'KSMEOF'
w /sys/kernel/mm/ksm/run - - - - 1
w /sys/kernel/mm/ksm/pages_to_scan - - - - 300
KSMEOF
        success "KSM: enabled (deduplicates identical memory pages)"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 2o. APT CLEANUP
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    info "Reclaiming disk space..."

    apt-get autoremove -y -qq > /dev/null 2>&1 || true
    apt-get autoclean -y -qq > /dev/null 2>&1 || true
    apt-get clean > /dev/null 2>&1 || true
    journalctl --vacuum-size=200M > /dev/null 2>&1 || true
    find /tmp -type f -atime +7 -delete 2>/dev/null || true
    success "Disk cleanup: apt cache cleared, journals vacuumed"

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # PERFORMANCE SUMMARY
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    separator
    printf "  ${GREEN}${BOLD}Performance Optimization Complete${NC}\n"
    printf "  ${BOLD}Applied:${NC}\n"
    printf "    ${CK} TCP BBR congestion control\n"
    printf "    ${CK} Network: 60+ sysctl parameters (buffers, backlog, keepalive)\n"
    printf "    ${CK} Memory: swappiness=10, dirty page tuning, vfs pressure=50\n"
    printf "    ${CK} File limits: 1M open files, 512K processes\n"
    printf "    ${CK} I/O scheduler: auto-detected (SSD/HDD/NVMe)\n"
    if [[ "$has_ssd" == "true" ]]; then
        printf "    ${CK} SSD TRIM: weekly fstrim\n"
    fi
    printf "    ${CK} Filesystem: noatime (reduced disk writes)\n"
    printf "    ${CK} tmpfs /tmp: ${tmpfs_mb}MB RAM-backed\n"
    printf "    ${CK} zram: compressed swap (${zram_percent:-50}% of RAM)\n"
    printf "    ${CK} DNS: Cloudflare 1.1.1.1 + Google 8.8.8.8\n"
    printf "    ${CK} Journald: capped at 200MB\n"
    printf "    ${CK} Systemd: faster timeouts (15s/10s)\n"
    printf "    ${CK} Disabled ${disabled_count} unnecessary service(s)\n"
    if [[ $num_cpus -gt 1 ]]; then
        printf "    ${CK} IRQ balancing: multi-core\n"
    fi
    if [[ -f /sys/kernel/mm/lru_gen/enabled ]]; then
        printf "    ${CK} MGLRU: multi-gen LRU memory management\n"
    fi
    printf "    ${CK} KSM: kernel samepage merging\n"
    printf "    ${CK} Disk cleanup: apt cache + journals\n"
    echo ""
    printf "  ${DIM}Backup of originals: ${bk_dir}${NC}\n"
    printf "  ${DIM}Sysctl config: /etc/sysctl.d/99-picoclaw-performance.conf${NC}\n"
    printf "  ${DIM}Limits config: /etc/security/limits.d/99-picoclaw-performance.conf${NC}\n"
    printf "  ${YELLOW}${BOLD}⚠ A mandatory reboot will be required at the end of installation.${NC}\n"
}

# ════════════════════════════════════════════════
# STEP 3: GO COMPILER (source build only)
# ════════════════════════════════════════════════
install_go() {
    step "3/14" "Go ${GO_VERSION} Compiler"

    if [[ "$INSTALL_FROM" != "source" ]]; then
        success "Skipped (using pre-built binary)"
        return 0
    fi

    if command -v go &>/dev/null; then
        local cur
        cur=$(go version 2>/dev/null | grep -oP 'go\K[0-9]+\.[0-9]+' || echo "0.0")
        local major minor
        major="${cur%%.*}"
        minor="${cur#*.}"
        minor="${minor%%.*}"
        if [[ "$major" -ge 1 && "$minor" -ge 24 ]]; then
            success "Go $(go version | grep -oP 'go[0-9.]+') already installed (>= 1.24 OK)"
            return 0
        fi
        info "Found Go ${cur}, need >= 1.24 — upgrading..."
    fi

    local arch go_file go_sha
    arch=$ARCH
    case "$arch" in
        x86_64)  go_file="go${GO_VERSION}.linux-amd64.tar.gz";   go_sha="$GO_SHA_AMD64" ;;
        aarch64) go_file="go${GO_VERSION}.linux-arm64.tar.gz";   go_sha="$GO_SHA_ARM64" ;;
        riscv64) go_file="go${GO_VERSION}.linux-riscv64.tar.gz"; go_sha="$GO_SHA_RISCV64" ;;
        *) die "Unsupported architecture for Go: $arch" ;;
    esac

    info "Downloading ${go_file}..."
    wget -q --show-progress -O "/tmp/${go_file}" "https://go.dev/dl/${go_file}" \
        || die "Go download failed"

    info "Verifying SHA256..."
    local actual
    actual=$(sha256sum "/tmp/${go_file}" | awk '{print $1}')
    if [[ "$actual" != "$go_sha" ]]; then
        die "SHA256 mismatch!\n    Expected: ${go_sha}\n    Got:      ${actual}"
    fi
    success "Checksum verified"

    rm -rf /usr/local/go
    tar -C /usr/local -xzf "/tmp/${go_file}" || die "Go extraction failed"
    rm -f "/tmp/${go_file}"

    export PATH="/usr/local/go/bin:/root/go/bin:$PATH"
    export GOPATH="/root/go"

    cat > /etc/profile.d/go.sh << 'GOEOF'
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
export GOPATH="$HOME/go"
GOEOF
    chmod +x /etc/profile.d/go.sh

    success "Go $(/usr/local/go/bin/go version | grep -oP 'go[0-9.]+')"
}

# ════════════════════════════════════════════════
# STEP 4: INSTALL PICOCLAW
# ════════════════════════════════════════════════
install_picoclaw() {
    if [[ "$INSTALL_FROM" == "source" ]]; then
        install_picoclaw_source
    else
        install_picoclaw_binary
    fi

    if [[ ! -x "$PICOCLAW_REAL" ]]; then
        if [[ -x "$PICOCLAW_BIN" ]]; then
            mv "$PICOCLAW_BIN" "$PICOCLAW_REAL"
        else
            die "PicoClaw binary not found"
        fi
    fi

    local ver="" rc=0
    ver=$("$PICOCLAW_REAL" version 2>/dev/null) || rc=$?
    if [[ $rc -ne 0 || -z "$ver" ]]; then
        ver="installed (version flag returned rc=${rc})"
    fi
    success "PicoClaw ready: ${ver}"
}

install_picoclaw_binary() {
    step "4/14" "PicoClaw ${PICOCLAW_VERSION} (pre-built binary)"

    local arch asset pc_sha
    arch=$ARCH
    case "$arch" in
        x86_64)  asset="picoclaw-linux-amd64";   pc_sha="$PC_SHA_AMD64" ;;
        aarch64) asset="picoclaw-linux-arm64";    pc_sha="$PC_SHA_ARM64" ;;
        riscv64) asset="picoclaw-linux-riscv64";  pc_sha="$PC_SHA_RISCV64" ;;
        *) warn "No binary for $arch — falling back to source build"
           INSTALL_FROM="source"; install_go; install_picoclaw_source; return 0 ;;
    esac

    info "Downloading ${asset}..."
    wget -q --show-progress -O "/tmp/${asset}" "${PICOCLAW_DL}/${asset}" \
        || die "Download failed"

    local actual
    actual=$(sha256sum "/tmp/${asset}" | awk '{print $1}')
    if [[ -n "$pc_sha" ]]; then
        info "Verifying SHA256..."
        if [[ "$actual" != "$pc_sha" ]]; then
            die "SHA256 mismatch!\n    Expected: ${pc_sha}\n    Got:      ${actual}"
        fi
        success "Checksum verified"
    else
        warn "No checksum available for ${PICOCLAW_VERSION} — skipping verification"
        info "Downloaded SHA256: ${actual}"
    fi

    cp "/tmp/${asset}" "$PICOCLAW_REAL"
    chmod +x "$PICOCLAW_REAL"
    rm -f "/tmp/${asset}"
    success "Binary → ${PICOCLAW_REAL} ($(du -h "$PICOCLAW_REAL" | awk '{print $1}'))"

    info "Getting built-in skills..."
    if [[ -d "$PICOCLAW_SRC/.git" ]]; then
        cd "$PICOCLAW_SRC" && git pull -q 2>/dev/null || true
    else
        rm -rf "$PICOCLAW_SRC"
        git clone -q --depth 1 "$PICOCLAW_REPO" "$PICOCLAW_SRC" 2>/dev/null || true
    fi

    if [[ -d "$PICOCLAW_SRC/skills" ]]; then
        mkdir -p "${WORKSPACE_DIR}/skills"
        for skill_dir in "$PICOCLAW_SRC/skills"/*/; do
            if [[ -f "${skill_dir}SKILL.md" ]]; then
                cp -r "$skill_dir" "${WORKSPACE_DIR}/skills/"
                local skill_name="${skill_dir%/}"
                skill_name="${skill_name##*/}"
                success "Skill: $skill_name"
            fi
        done
    fi
}

install_picoclaw_source() {
    step "4/14" "PicoClaw ${PICOCLAW_VERSION} (build from source)"

    export PATH="/usr/local/go/bin:/root/go/bin:$PATH"
    export GOPATH="/root/go"
    if ! command -v go &>/dev/null; then
        die "Go not found — run install_go first"
    fi
    info "Using $(go version | grep -oP 'go[0-9.]+')"

    if [[ -d "$PICOCLAW_SRC/.git" ]]; then
        info "Updating existing clone..."
        cd "$PICOCLAW_SRC" && git pull -q || true
    else
        info "Cloning ${PICOCLAW_REPO}..."
        rm -rf "$PICOCLAW_SRC"
        git clone -q "$PICOCLAW_REPO" "$PICOCLAW_SRC" || die "Clone failed"
    fi
    cd "$PICOCLAW_SRC"

    info "Downloading Go modules..."
    go mod download || die "go mod download failed"

    info "Compiling..."
    make build GO=/usr/local/go/bin/go || die "make build failed"

    local bin_path=""
    if [[ -f "${PICOCLAW_SRC}/build/picoclaw" ]]; then
        bin_path="${PICOCLAW_SRC}/build/picoclaw"
    else
        bin_path=$(find "${PICOCLAW_SRC}/build/" -name "picoclaw-linux-*" ! -name "*.exe" -type f 2>/dev/null | head -1)
    fi

    if [[ -z "$bin_path" || ! -f "$bin_path" ]]; then
        info "Trying make install with INSTALL_PREFIX=/usr/local..."
        make install INSTALL_PREFIX=/usr/local PICOCLAW_HOME="$CONFIG_DIR" 2>/dev/null || true
        if [[ -f "/usr/local/bin/picoclaw" ]]; then
            mv "/usr/local/bin/picoclaw" "$PICOCLAW_REAL"
        else
            die "Binary not found after build"
        fi
    else
        cp "$bin_path" "$PICOCLAW_REAL"
        chmod +x "$PICOCLAW_REAL"
    fi

    success "Binary → ${PICOCLAW_REAL} ($(du -h "$PICOCLAW_REAL" | awk '{print $1}'))"

    info "Installing built-in skills..."
    make install-skills PICOCLAW_HOME="$CONFIG_DIR" 2>/dev/null || true

    cd /root
}

# ════════════════════════════════════════════════
# STEP 5: ONBOARD
# ════════════════════════════════════════════════
init_picoclaw() {
    step "5/14" "Initializing PicoClaw Workspace"

    mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"
    echo "y" | timeout 30 "$PICOCLAW_REAL" onboard 2>/dev/null || true

    if [[ -f "${WORKSPACE_DIR}/AGENTS.md" ]]; then
        success "Workspace templates created (AGENTS.md, SOUL.md, etc.)"
    else
        warn "Onboard may not have created templates — workspace dir exists"
    fi
}

# ════════════════════════════════════════════════
# SKILL.MD DESCRIPTION HELPER
# Extracts the description from SKILL.md YAML frontmatter
# ════════════════════════════════════════════════
_extract_skill_description() {
    local skill_md="$1"
    local desc="" in_frontmatter=false
    while IFS= read -r mdline; do
        if [[ "$mdline" == "---" ]]; then
            if [[ "$in_frontmatter" == "true" ]]; then
                break
            fi
            in_frontmatter=true
            continue
        fi
        if [[ "$in_frontmatter" == "true" ]]; then
            if [[ "$mdline" =~ ^description:[[:space:]]*(.*) ]]; then
                desc="${BASH_REMATCH[1]}"
                desc="${desc#>}"
                desc="${desc#"${desc%%[![:space:]]*}"}"
                break
            fi
        fi
    done < "$skill_md" 2>/dev/null || true
    printf '%s' "${desc:0:80}"
}

_extract_atlas_category() {
    local origin_file="$1"
    local cat="unknown"
    if [[ -f "$origin_file" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == category:* ]]; then
                cat="${line#category:}"
                cat="${cat#"${cat%%[![:space:]]*}"}"
                cat="${cat//[[:space:]]/}"
                break
            fi
        done < "$origin_file"
    fi
    if [[ -z "$cat" ]]; then
        cat="unknown"
    fi
    printf '%s' "$cat"
}

# ════════════════════════════════════════════════
# STEP 6: ATLAS SKILLS REPOSITORY
# ════════════════════════════════════════════════
install_atlas_skills() {
    step "6/14" "Atlas Skills Repository"

    if [[ "$SETUP_ATLAS" != "true" ]]; then
        info "Skipped — Atlas skills not selected"
        return 0
    fi

    mkdir -p "$ATLAS_SKILLS_DIR"

    # ── 6a. Fetch repository tree via GitHub API ──
    info "Querying GitHub API for Atlas repository tree..."
    local tree_json=""
    tree_json=$(curl -sf --connect-timeout 10 --max-time 30 \
        -H "Accept: application/vnd.github.v3+json" \
        "$ATLAS_API_TREE" 2>/dev/null) || true

    if [[ -z "$tree_json" ]]; then
        warn "GitHub API failed — falling back to git clone..."
        _atlas_install_via_git
        return 0
    fi

    local is_truncated=""
    is_truncated=$(printf '%s' "$tree_json" | jq -r '.truncated // false' 2>/dev/null) || true
    if [[ "$is_truncated" == "true" ]]; then
        warn "Repository tree truncated by API — falling back to git clone..."
        _atlas_install_via_git
        return 0
    fi

    # ── 6b. Discover all skills dynamically ──
    info "Discovering skills from repository tree..."

    local -a skill_paths=()
    local -a skill_names=()
    local -a skill_categories=()

    local skillmd_paths=""
    skillmd_paths=$(printf '%s' "$tree_json" | jq -r '.tree[] | select(.type == "blob") | select(.path | test("^skills/.+/.+/SKILL\\.md$")) | .path' 2>/dev/null) || true

    if [[ -z "$skillmd_paths" ]]; then
        warn "No skills found in Atlas repository"
        return 0
    fi

    while IFS= read -r skillmd_path; do
        if [[ -z "$skillmd_path" ]]; then
            continue
        fi
        local skill_dir_path="${skillmd_path%/SKILL.md}"
        local skill_name="${skill_dir_path##*/}"
        local cat_and_name="${skill_dir_path#skills/}"
        local category="${cat_and_name%%/*}"

        skill_paths+=("$skill_dir_path")
        skill_names+=("$skill_name")
        skill_categories+=("$category")
    done <<< "$skillmd_paths"

    local skill_count=${#skill_names[@]}

    if [[ $skill_count -eq 0 ]]; then
        warn "No skills found in Atlas repository"
        return 0
    fi

    success "Discovered ${BOLD}${skill_count}${NC} skill(s) across Atlas repository"
    echo ""

    # ── 6c. Collect all files belonging to each skill ──
    local installed_count=0
    local failed_count=0

    for i in "${!skill_paths[@]}"; do
        local s_path="${skill_paths[$i]}"
        local s_name="${skill_names[$i]}"
        local s_cat="${skill_categories[$i]}"
        local target_dir="${ATLAS_SKILLS_DIR}/${s_name}"

        printf '%s\n' "  ${AR} Installing: ${BOLD}${s_name}${NC} ${DIM}(${s_cat})${NC}"

        local -a file_paths=()
        while IFS= read -r fpath; do
            if [[ -n "$fpath" ]]; then
                file_paths+=("$fpath")
            fi
        done < <(printf '%s' "$tree_json" | jq -r --arg prefix "${s_path}/" \
            '.tree[] | select(.type == "blob") | select(.path | startswith($prefix)) | .path' 2>/dev/null)

        while IFS= read -r fpath; do
            if [[ -n "$fpath" ]]; then
                local already=false
                for existing in "${file_paths[@]+"${file_paths[@]}"}"; do
                    if [[ "$existing" == "$fpath" ]]; then
                        already=true
                        break
                    fi
                done
                if [[ "$already" == "false" ]]; then
                    file_paths+=("$fpath")
                fi
            fi
        done < <(printf '%s' "$tree_json" | jq -r --arg dir "${s_path}" \
            '.tree[] | select(.type == "blob") | select(.path | startswith($dir)) | select(.path | ltrimstr($dir) | startswith("/")) | .path' 2>/dev/null)

        if [[ ${#file_paths[@]} -eq 0 ]]; then
            warn "  No files found for ${s_name} — skipping"
            failed_count=$((failed_count + 1))
            continue
        fi

        mkdir -p "$target_dir"

        local file_count=0
        local file_failed=0

        for fpath in "${file_paths[@]}"; do
            local rel_path="${fpath#${s_path}/}"
            local target_file="${target_dir}/${rel_path}"
            local target_file_dir="${target_file%/*}"

            mkdir -p "$target_file_dir"

            local dl_url="${ATLAS_RAW_BASE}/${fpath}"
            if curl -sf --connect-timeout 10 --max-time 30 -o "$target_file" "$dl_url" 2>/dev/null; then
                file_count=$((file_count + 1))
            else
                file_failed=$((file_failed + 1))
            fi
        done

        if [[ -f "${target_dir}/SKILL.md" ]]; then
            local desc=""
            desc=$(_extract_skill_description "${target_dir}/SKILL.md")

            success "  ${s_name}: ${file_count} files${DIM}$(if [[ -n "$desc" ]]; then echo " — ${desc}"; fi)${NC}"
            installed_count=$((installed_count + 1))
        else
            warn "  ${s_name}: SKILL.md missing after download — skill may be incomplete"
            failed_count=$((failed_count + 1))
        fi
    done

    # ── 6d. Write Atlas metadata ──
    _atlas_write_metadata "$installed_count"

    # ── 6e. Summary ──
    separator
    printf "  ${GREEN}${BOLD}Atlas Skills Installation Complete${NC}\n"
    printf "  ${BOLD}Installed:${NC} ${installed_count} skill(s)\n"
    if [[ $failed_count -gt 0 ]]; then
        printf "  ${BOLD}Failed:${NC}    ${failed_count} skill(s)\n"
    fi
    printf "  ${BOLD}Location:${NC}  ${ATLAS_SKILLS_DIR}/\n"
    printf "  ${BOLD}Source:${NC}    ${ATLAS_REPO_URL}\n"
    echo ""
    printf "  ${DIM}Manage with: picoclaw atlas${NC}\n"
    printf "  ${DIM}Update all:  picoclaw atlas update${NC}\n"
}

_atlas_install_via_git() {
    local tmp_dir="/tmp/atlas-clone-$$"
    rm -rf "$tmp_dir"

    info "Cloning Atlas repository..."
    if ! git clone -q --depth 1 -b "$ATLAS_BRANCH" "${ATLAS_REPO_URL}.git" "$tmp_dir" 2>/dev/null; then
        warn "Failed to clone Atlas repository — skipping skill installation"
        return 0
    fi

    if [[ ! -d "${tmp_dir}/skills" ]]; then
        warn "No skills/ directory found in Atlas repository"
        rm -rf "$tmp_dir"
        return 0
    fi

    local installed_count=0

    for category_dir in "${tmp_dir}/skills"/*/; do
        if [[ ! -d "$category_dir" ]]; then
            continue
        fi
        for skill_dir in "${category_dir}"*/; do
            if [[ ! -d "$skill_dir" ]]; then
                continue
            fi
            if [[ ! -f "${skill_dir}SKILL.md" ]]; then
                continue
            fi

            local s_name="${skill_dir%/}"
            s_name="${s_name##*/}"
            local s_cat="${category_dir%/}"
            s_cat="${s_cat##*/}"
            local target_dir="${ATLAS_SKILLS_DIR}/${s_name}"

            mkdir -p "$target_dir"
            cp -a "${skill_dir}"* "$target_dir/" 2>/dev/null || true
            cp -a "${skill_dir}".* "$target_dir/" 2>/dev/null || true

            local desc=""
            desc=$(_extract_skill_description "${target_dir}/SKILL.md")

            # Count top-level files only (not recursive). Acceptable trade-off
            # to avoid forking find; most skills are single-directory.
            local file_count=0
            shopt -s nullglob dotglob
            local -a files=("$target_dir"/*)
            for f in "${files[@]}"; do
                if [[ -f "$f" ]]; then
                    file_count=$((file_count + 1))
                fi
            done
            shopt -u nullglob dotglob

            success "  ${s_name} (${s_cat}): ${file_count} files${DIM}$(if [[ -n "$desc" ]]; then echo " — ${desc}"; fi)${NC}"
            installed_count=$((installed_count + 1))
        done
    done

    rm -rf "$tmp_dir"

    _atlas_write_metadata "$installed_count"

    if [[ $installed_count -gt 0 ]]; then
        separator
        printf "  ${GREEN}${BOLD}Atlas Skills Installation Complete (via git clone)${NC}\n"
        printf "  ${BOLD}Installed:${NC} ${installed_count} skill(s)\n"
        printf "  ${BOLD}Location:${NC}  ${ATLAS_SKILLS_DIR}/\n"
        printf "  ${BOLD}Source:${NC}    ${ATLAS_REPO_URL}\n"
        echo ""
        printf "  ${DIM}Manage with: picoclaw atlas${NC}\n"
    else
        warn "No skills found in Atlas repository"
    fi
}

_atlas_write_metadata() {
    local count="${1:-0}"

    local skills_json="["
    local first=true
    for skill_dir in "${ATLAS_SKILLS_DIR}"/*/; do
        if [[ ! -f "${skill_dir}SKILL.md" ]]; then
            continue
        fi
        local sname="${skill_dir%/}"
        sname="${sname##*/}"

        local sver="unknown"
        if [[ -f "${skill_dir}VERSION" ]]; then
            sver=$(head -1 "${skill_dir}VERSION" 2>/dev/null) || sver="unknown"
            sver="${sver//[[:space:]]/}"
        fi

        local scat=""
        scat=$(_extract_atlas_category "${skill_dir}.atlas-origin")

        if [[ "$first" == "true" ]]; then
            first=false
        else
            skills_json+=","
        fi
        skills_json+="{\"name\":\"$(json_escape "$sname")\",\"category\":\"$(json_escape "$scat")\",\"version\":\"$(json_escape "$sver")\",\"path\":\"$(json_escape "${ATLAS_SKILLS_DIR}/${sname}")\"}"
    done
    skills_json+="]"

    cat > "$ATLAS_META_FILE" << METAEOF
{
  "repository": "${ATLAS_REPO_URL}",
  "branch": "${ATLAS_BRANCH}",
  "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "installed_at_epoch": $(date +%s),
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "last_updated_epoch": $(date +%s),
  "skills_dir": "${ATLAS_SKILLS_DIR}",
  "skill_count": ${count},
  "skills": ${skills_json}
}
METAEOF
    success "Atlas metadata → ${ATLAS_META_FILE}"
}

# ════════════════════════════════════════════════
# STEP 7: WRITE CONFIG
# ════════════════════════════════════════════════
write_config() {
    step "7/14" "Writing Configuration"

    mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"

    # ── Provider slot wiring ──
    local p_or_key="" p_or_base=""
    local p_an_key="" p_an_base=""
    local p_oa_key="" p_oa_base=""
    local p_gm_key="" p_gm_base=""
    local p_zh_key="" p_zh_base=""
    local p_gr_key="" p_gr_base=""
    local p_vl_key="" p_vl_base=""

    case "$LLM_PROVIDER" in
        openrouter) p_or_key="$LLM_API_KEY"; p_or_base="$LLM_API_BASE" ;;
        anthropic)
            p_or_key="$LLM_API_KEY"; p_or_base="https://openrouter.ai/api/v1"
            ;;
        openai)     p_oa_key="$LLM_API_KEY"; p_oa_base="$LLM_API_BASE" ;;
        gemini)     p_gm_key="$LLM_API_KEY"; p_gm_base="$LLM_API_BASE" ;;
        zhipu)      p_zh_key="$LLM_API_KEY"; p_zh_base="$LLM_API_BASE" ;;
        groq)
            p_or_key="$LLM_API_KEY"
            p_or_base="$LLM_API_BASE"
            p_gr_key="$LLM_API_KEY"
            p_gr_base="$LLM_API_BASE"
            ;;
        vllm)       p_vl_key="$LLM_API_KEY"; p_vl_base="$LLM_API_BASE" ;;
        ollama)
            # Ollama routes through the vllm slot — OpenAI-compatible /v1 endpoint
            p_vl_key=""
            p_vl_base="${OLLAMA_API_BASE}"
            ;;
    esac

    if [[ -n "$GROQ_EXTRA_KEY" && "$LLM_PROVIDER" != "groq" ]]; then
        p_gr_key="$GROQ_EXTRA_KEY"
    fi

    # ── JSON-escape all user-supplied values ──
    p_or_key="$(json_escape "$p_or_key")"
    p_or_base="$(json_escape "$p_or_base")"
    p_an_key="$(json_escape "$p_an_key")"
    p_an_base="$(json_escape "$p_an_base")"
    p_oa_key="$(json_escape "$p_oa_key")"
    p_oa_base="$(json_escape "$p_oa_base")"
    p_gm_key="$(json_escape "$p_gm_key")"
    p_gm_base="$(json_escape "$p_gm_base")"
    p_zh_key="$(json_escape "$p_zh_key")"
    p_zh_base="$(json_escape "$p_zh_base")"
    p_gr_key="$(json_escape "$p_gr_key")"
    p_gr_base="$(json_escape "$p_gr_base")"
    p_vl_key="$(json_escape "$p_vl_key")"
    p_vl_base="$(json_escape "$p_vl_base")"

    local safe_tg_token safe_dc_token safe_brave_key
    safe_tg_token="$(json_escape "$TG_TOKEN")"
    safe_dc_token="$(json_escape "$DC_TOKEN")"
    safe_brave_key="$(json_escape "$BRAVE_API_KEY")"
    local safe_fs_id safe_fs_secret safe_fs_encrypt safe_fs_verify
    safe_fs_id="$(json_escape "$FS_APP_ID")"
    safe_fs_secret="$(json_escape "$FS_SECRET")"
    safe_fs_encrypt="$(json_escape "$FS_ENCRYPT")"
    safe_fs_verify="$(json_escape "$FS_VERIFY")"

    # ── Build allow_from arrays ──
    local tg_allow="[]"
    if [[ -n "$TG_USER_ID" ]]; then
        if [[ -n "$TG_USERNAME" ]]; then
            tg_allow="[\"$(json_escape "${TG_USER_ID}|${TG_USERNAME}")\"]"
        else
            tg_allow="[\"$(json_escape "$TG_USER_ID")\"]"
        fi
    fi

    local dc_allow="[]"
    if [[ -n "$DC_USER_ID" ]]; then
        if [[ -n "$DC_USERNAME" ]]; then
            dc_allow="[\"$(json_escape "${DC_USER_ID}|${DC_USERNAME}")\"]"
        else
            dc_allow="[\"$(json_escape "$DC_USER_ID")\"]"
        fi
    fi

    local wa_allow="[]"
    if [[ -n "$WA_USER_ID" ]]; then wa_allow="[\"$(json_escape "$WA_USER_ID")\"]"; fi

    # ── Determine the model name for config.json ──
    # For Ollama, this will be updated later by install_ollama to the custom model name
    local config_model="$LLM_MODEL"

    cat > "$CONFIG_FILE" << CFGEOF
{
  "agents": {
    "defaults": {
      "workspace": "${WORKSPACE_DIR}",
      "model": "$(json_escape "$config_model")",
      "max_tokens": ${MAX_TOKENS},
      "temperature": ${TEMPERATURE},
      "max_tool_iterations": ${MAX_TOOL_ITER}
    }
  },
  "providers": {
    "anthropic": {
      "api_key": "${p_an_key}",
      "api_base": "${p_an_base}"
    },
    "openai": {
      "api_key": "${p_oa_key}",
      "api_base": "${p_oa_base}"
    },
    "openrouter": {
      "api_key": "${p_or_key}",
      "api_base": "${p_or_base}"
    },
    "groq": {
      "api_key": "${p_gr_key}",
      "api_base": "${p_gr_base}"
    },
    "zhipu": {
      "api_key": "${p_zh_key}",
      "api_base": "${p_zh_base}"
    },
    "gemini": {
      "api_key": "${p_gm_key}",
      "api_base": "${p_gm_base}"
    },
    "vllm": {
      "api_key": "${p_vl_key}",
      "api_base": "${p_vl_base}"
    }
  },
  "channels": {
    "telegram": {
      "enabled": ${TG_ENABLED},
      "token": "${safe_tg_token}",
      "allow_from": ${tg_allow}
    },
    "discord": {
      "enabled": ${DC_ENABLED},
      "token": "${safe_dc_token}",
      "allow_from": ${dc_allow}
    },
    "whatsapp": {
      "enabled": ${WA_ENABLED},
      "bridge_url": "$(json_escape "$WA_BRIDGE")",
      "allow_from": ${wa_allow}
    },
    "feishu": {
      "enabled": ${FS_ENABLED},
      "app_id": "${safe_fs_id}",
      "app_secret": "${safe_fs_secret}",
      "encrypt_key": "${safe_fs_encrypt}",
      "verification_token": "${safe_fs_verify}",
      "allow_from": []
    },
    "maixcam": {
      "enabled": ${MC_ENABLED},
      "host": "$(json_escape "$MC_HOST")",
      "port": ${MC_PORT},
      "allow_from": []
    }
  },
  "tools": {
    "web": {
      "search": {
        "api_key": "${safe_brave_key}",
        "max_results": ${BRAVE_MAX_RESULTS}
      }
    }
  },
  "gateway": {
    "host": "$(json_escape "$GW_HOST")",
    "port": ${GW_PORT}
  }
}
CFGEOF

    if jq empty "$CONFIG_FILE" 2>/dev/null; then
        success "Config → ${CONFIG_FILE} (valid JSON)"
    else
        warn "JSON validation failed — check config manually"
    fi

    echo ""
    if [[ "$LLM_PROVIDER" == "groq" ]]; then
        info "Provider: ${BOLD}groq${NC} (routed via openrouter slot → ${LLM_API_BASE})"
    elif [[ "$LLM_PROVIDER" == "anthropic" ]]; then
        info "Provider: ${BOLD}anthropic (via OpenRouter)${NC} → ${LLM_MODEL}"
    elif [[ "$LLM_PROVIDER" == "ollama" ]]; then
        info "Provider: ${BOLD}ollama (local)${NC} → ${LLM_MODEL} (routed via vllm slot → ${OLLAMA_API_BASE})"
    else
        info "Active provider: ${BOLD}${LLM_PROVIDER}${NC} → ${LLM_MODEL}"
    fi
    if [[ -n "$LLM_API_BASE" && "$LLM_PROVIDER" != "groq" && "$LLM_PROVIDER" != "ollama" ]]; then info "API base: ${LLM_API_BASE}"; fi
    if [[ -n "$p_gr_key" && "$LLM_PROVIDER" != "groq" ]]; then info "Groq voice transcription: enabled"; fi
    if [[ -n "$BRAVE_API_KEY" ]]; then info "Brave Search: enabled (max ${BRAVE_MAX_RESULTS} results)"; fi
    if [[ "$TG_ENABLED" == "true" ]]; then
        if [[ -n "$TG_USERNAME" ]]; then
            info "Telegram: enabled (${TG_USER_ID}|${TG_USERNAME})"
        else
            info "Telegram: enabled (user ${TG_USER_ID})"
        fi
    fi
    if [[ "$DC_ENABLED" == "true" ]]; then
        if [[ -n "$DC_USERNAME" ]]; then
            info "Discord: enabled (${DC_USER_ID}|${DC_USERNAME})"
        else
            info "Discord: enabled (user ${DC_USER_ID})"
        fi
    fi
    if [[ "$WA_ENABLED" == "true" ]]; then info "WhatsApp: enabled (bridge ${WA_BRIDGE})"; fi
    if [[ "$FS_ENABLED" == "true" ]]; then info "Feishu: enabled"; fi
    if [[ "$MC_ENABLED" == "true" ]]; then info "MaixCAM: enabled (${MC_HOST}:${MC_PORT})"; fi

    # ── Write backup configuration file ──
    mkdir -p "$BACKUP_DIR"
    cat > "$BACKUP_META_FILE" << BKCONF
# PicoClaw Backup Configuration
# Written by installer on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
BACKUP_DIR='${BACKUP_DIR}'
BACKUP_MAX_KEEP='${BACKUP_MAX_KEEP}'
BACKUP_INTERVAL_DAYS='${BACKUP_INTERVAL_DAYS}'
BACKUP_AUTO_ENABLED='${SETUP_AUTOBACKUP}'
BKCONF
    success "Backup config → ${BACKUP_META_FILE}"

    # ── Write FTP configuration file ──
    local safe_ftp_user
    safe_ftp_user="$(shell_escape "$FTP_USER")"
    cat > "$FTP_CONF_FILE" << FTPCONF
# PicoClaw FTP Configuration
# Written by installer on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
FTP_ENABLED='${SETUP_FTP}'
FTP_USER='${safe_ftp_user}'
FTP_PORT='${FTP_PORT}'
FTP_PASV_MIN='${FTP_PASV_MIN}'
FTP_PASV_MAX='${FTP_PASV_MAX}'
FTP_TLS='${FTP_TLS}'
FTPCONF
    success "FTP config → ${FTP_CONF_FILE}"

    # ── Write WhatsApp configuration file ──
    local safe_wa_bridge_dir safe_wa_auth_dir safe_wa_user_id
    safe_wa_bridge_dir="$(shell_escape "$WA_BRIDGE_DIR")"
    safe_wa_auth_dir="$(shell_escape "$WA_BRIDGE_AUTH_DIR")"
    safe_wa_user_id="$(shell_escape "$WA_USER_ID")"
    cat > "$WA_CONF_FILE" << WACONF
# PicoClaw WhatsApp Bridge Configuration
# Written by installer on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
WA_ENABLED='${WA_ENABLED}'
WA_BRIDGE_PORT='${WA_BRIDGE_PORT}'
WA_BRIDGE_DIR='${safe_wa_bridge_dir}'
WA_BRIDGE_AUTH_DIR='${safe_wa_auth_dir}'
WA_BRIDGE_SERVICE='${WA_BRIDGE_SERVICE}'
WA_USER_ID='${safe_wa_user_id}'
WACONF
    success "WhatsApp config → ${WA_CONF_FILE}"

    # ── Write Ollama configuration file ──
    local safe_ollama_model safe_ollama_host
    safe_ollama_model="$(shell_escape "$OLLAMA_MODEL")"
    safe_ollama_host="$(shell_escape "$OLLAMA_HOST")"
    cat > "$OLLAMA_CONF_FILE" << OLLAMACONF
# PicoClaw Ollama Configuration
# Written by installer on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
OLLAMA_ENABLED='${SETUP_OLLAMA}'
OLLAMA_MODEL='${safe_ollama_model}'
OLLAMA_NUM_CTX='${OLLAMA_NUM_CTX}'
OLLAMA_HOST='${safe_ollama_host}'
OLLAMA_PORT='${OLLAMA_PORT}'
OLLAMACONF
    success "Ollama config → ${OLLAMA_CONF_FILE}"
}

# ════════════════════════════════════════════════
# STEP 8: WHATSAPP BRIDGE (Baileys/Node.js)
# ════════════════════════════════════════════════
install_whatsapp_bridge() {
    step "8/14" "WhatsApp Bridge (Baileys/Node.js)"

    if [[ "$WA_ENABLED" != "true" ]]; then
        info "Skipped — WhatsApp not selected"
        return 0
    fi

    # ── Verify Node.js >= 20 ──
    if ! command -v node &>/dev/null; then
        die "Node.js not found — should have been installed in step 1"
    fi
    local node_major=""
    node_major=$(_node_major)
    if [[ "$node_major" =~ ^[0-9]+$ ]] && (( node_major >= 20 )); then
        success "Node.js $(node --version) verified (>= 20)"
    else
        die "Node.js >= 20 required, got $(node --version 2>/dev/null || echo 'unknown')"
    fi

    if ! command -v npm &>/dev/null; then
        die "npm not found"
    fi
    success "npm $(npm --version 2>/dev/null) available"

    # ── Clone nanobot repo and extract bridge/ ──
    info "Downloading WhatsApp bridge from nanobot repository..."
    local tmp_clone="/tmp/nanobot-clone-$$"
    rm -rf "$tmp_clone"

    if ! git clone -q --depth 1 "${WA_BRIDGE_REPO}" "$tmp_clone" 2>/dev/null; then
        die "Failed to clone nanobot repository"
    fi

    if [[ ! -d "${tmp_clone}/bridge" ]]; then
        rm -rf "$tmp_clone"
        die "bridge/ directory not found in nanobot repository"
    fi

    # ── Copy bridge to WA_BRIDGE_DIR ──
    rm -rf "$WA_BRIDGE_DIR"
    mkdir -p "$WA_BRIDGE_DIR"
    cp -a "${tmp_clone}/bridge/"* "$WA_BRIDGE_DIR/" 2>/dev/null || true
    cp -a "${tmp_clone}/bridge/".* "$WA_BRIDGE_DIR/" 2>/dev/null || true
    rm -rf "$tmp_clone"
    success "Bridge source → ${WA_BRIDGE_DIR}"

    # ── Verify package.json exists ──
    if [[ ! -f "${WA_BRIDGE_DIR}/package.json" ]]; then
        die "package.json not found in bridge directory"
    fi

    # ── npm install ──
    info "Installing Node.js dependencies (npm install)..."
    cd "$WA_BRIDGE_DIR"
    npm install --production=false 2>&1 | tail -3 || die "npm install failed"
    success "Dependencies installed ($(du -sh node_modules 2>/dev/null | awk '{print $1}'))"

    # ── Build TypeScript ──
    info "Compiling TypeScript (npm run build)..."
    npm run build 2>&1 | tail -3 || die "TypeScript compilation failed"

    if [[ ! -f "${WA_BRIDGE_DIR}/dist/index.js" ]]; then
        die "dist/index.js not found after build — compilation may have failed"
    fi
    success "Bridge compiled → ${WA_BRIDGE_DIR}/dist/index.js"

    cd /root

    # ── Create auth directory ──
    mkdir -p "$WA_BRIDGE_AUTH_DIR"
    success "Auth directory → ${WA_BRIDGE_AUTH_DIR}"

    # ── Check for existing session (re-install scenario) ──
    local has_existing_session=false
    if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
        has_existing_session=true
        success "Existing WhatsApp session found (creds.json) — QR scan not needed"
    else
        info "No existing session — QR scan will be launched automatically"
    fi

    # ── Create systemd service ──
    info "Creating systemd service..."
    cat > "/etc/systemd/system/${WA_BRIDGE_SERVICE}.service" << WASVCEOF
[Unit]
Description=PicoClaw WhatsApp Bridge (Baileys/Node.js)
Documentation=https://github.com/HKUDS/nanobot
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
User=root
WorkingDirectory=${WA_BRIDGE_DIR}
Environment=NODE_ENV=production
Environment=BRIDGE_PORT=${WA_BRIDGE_PORT}
Environment=AUTH_DIR=${WA_BRIDGE_AUTH_DIR}
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=picoclaw-wa-bridge

[Install]
WantedBy=multi-user.target
WASVCEOF

    systemctl daemon-reload || true
    systemctl enable "${WA_BRIDGE_SERVICE}.service" 2>/dev/null || true
    success "Service: ${WA_BRIDGE_SERVICE}.service (enabled)"

    # ── Auto-login: launch QR scan if no existing session ──
    if [[ "$has_existing_session" != "true" && "$CONFIG_LOADED" == "true" ]]; then
        info "Non-interactive mode — skipping QR login. Run: picoclaw whatsapp login"
    elif [[ "$has_existing_session" != "true" ]]; then
        separator
        printf "  ${YELLOW}${BOLD}WhatsApp QR Login Required${NC}\n"
        echo ""
        printf "  ${BOLD}The bridge needs to be linked to your WhatsApp account.${NC}\n"
        printf "  ${BOLD}A QR code will appear below — scan it with your phone.${NC}\n"
        echo ""
        printf "  ${BOLD}Instructions:${NC}\n"
        printf "    1. A QR code will appear in your terminal\n"
        printf "    2. Open WhatsApp on your phone\n"
        printf "    3. Go to ${BOLD}Settings → Linked Devices → Link a Device${NC}\n"
        printf "    4. Scan the QR code with your phone's camera\n"
        printf "    5. Wait for ${GREEN}\"Connected\"${NC} message\n"
        printf "    6. The bridge will ${GREEN}automatically exit${NC} once connected\n"
        echo ""
        printf "  ${DIM}The session will be saved in ${WA_BRIDGE_AUTH_DIR}/${NC}\n"
        printf "  ${DIM}Future starts won't need QR scanning.${NC}\n"
        echo ""
        printf "  ${AR} Press Enter to start QR login..."; read -r
        echo ""
        printf "  ${MAGENTA}🦞${NC} Starting bridge for QR login...\n"
        printf "  ${DIM}─────── Bridge output below ───────${NC}\n"
        echo ""

        # Run bridge with auto-exit: monitor for creds.json creation
        cd "$WA_BRIDGE_DIR"
        BRIDGE_PORT="$WA_BRIDGE_PORT" AUTH_DIR="$WA_BRIDGE_AUTH_DIR" node dist/index.js &
        local bridge_pid=$!

        # Wait for connection (creds.json appears) or timeout after 120s
        local wait_count=0
        local max_wait=120
        local login_success=false
        while (( wait_count < max_wait )); do
            if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
                # Give it a moment to fully write the session
                sleep 3
                login_success=true
                break
            fi
            # Check if bridge process died
            if ! kill -0 "$bridge_pid" 2>/dev/null; then
                break
            fi
            sleep 1
            wait_count=$((wait_count + 1))
        done

        # Kill the interactive bridge process
        if kill -0 "$bridge_pid" 2>/dev/null; then
            kill "$bridge_pid" 2>/dev/null || true
            wait "$bridge_pid" 2>/dev/null || true
        fi
        cd /root

        echo ""
        printf "  ${DIM}─────── Bridge stopped ───────${NC}\n"
        echo ""

        if [[ "$login_success" == "true" ]]; then
            printf "  ${GREEN}✔${NC} ${BOLD}WhatsApp account linked successfully!${NC}\n"
            printf "  ${GREEN}✔${NC} Session saved to ${WA_BRIDGE_AUTH_DIR}/creds.json\n"
            has_existing_session=true
        else
            if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
                printf "  ${GREEN}✔${NC} ${BOLD}WhatsApp account linked successfully!${NC}\n"
                printf "  ${GREEN}✔${NC} Session saved to ${WA_BRIDGE_AUTH_DIR}/creds.json\n"
                has_existing_session=true
            else
                printf "  ${YELLOW}⚠${NC} ${BOLD}QR code was not scanned in time${NC} — no session saved\n"
                printf "  ${DIM}Run later: picoclaw whatsapp login${NC}\n"
            fi
        fi
    fi

    # ── Start bridge as systemd service if session exists ──
    if [[ "$has_existing_session" == "true" ]]; then
        if [[ "$SETUP_PERFORMANCE" == "true" ]]; then
            info "Bridge will start automatically after the mandatory reboot"
        else
            info "Starting WhatsApp bridge as systemd service..."
            systemctl start "${WA_BRIDGE_SERVICE}.service" 2>/dev/null || true
            sleep 3
            local rc=0
            systemctl is-active --quiet "${WA_BRIDGE_SERVICE}" 2>/dev/null || rc=$?
            if [[ $rc -eq 0 ]]; then
                success "Bridge RUNNING on port ${WA_BRIDGE_PORT}"
            else
                warn "Bridge may have issues — check: journalctl -u ${WA_BRIDGE_SERVICE}"
            fi
        fi
    else
        if [[ "$SETUP_PERFORMANCE" != "true" ]]; then
            info "Bridge not started — QR scan needed first"
            info "Run: ${CYAN}picoclaw whatsapp login${NC}"
        fi
    fi

    # ── Summary ──
    separator
    printf "  ${GREEN}${BOLD}WhatsApp Bridge Installation Complete${NC}\n"
    printf "  ${BOLD}Service:${NC}     ${WA_BRIDGE_SERVICE} (systemd-managed, auto-start on boot)\n"
    printf "  ${BOLD}Bridge dir:${NC}  ${WA_BRIDGE_DIR}\n"
    printf "  ${BOLD}Auth dir:${NC}    ${WA_BRIDGE_AUTH_DIR}\n"
    printf "  ${BOLD}Port:${NC}        ${WA_BRIDGE_PORT}\n"
    printf "  ${BOLD}Node.js:${NC}     $(node --version 2>/dev/null)\n"
    printf "  ${BOLD}Compiled:${NC}    ${WA_BRIDGE_DIR}/dist/index.js\n"
    if [[ "$has_existing_session" == "true" ]]; then
        printf "  ${BOLD}Session:${NC}     ${GREEN}linked${NC} (creds.json found)\n"
    else
        printf "  ${BOLD}Session:${NC}     ${RED}not linked${NC} — QR scan required\n"
    fi
    echo ""
    if [[ "$has_existing_session" != "true" ]]; then
        printf "  ${YELLOW}${BOLD}⚠  You must link your WhatsApp account:${NC}\n"
        echo ""
        printf "    ${CYAN}picoclaw whatsapp login${NC}\n"
        echo ""
        printf "  ${DIM}This will display a QR code in your terminal.${NC}\n"
        printf "  ${DIM}Open WhatsApp on your phone → Settings → Linked Devices →${NC}\n"
        printf "  ${DIM}Link a Device → scan the QR code.${NC}\n"
        printf "  ${DIM}Once linked, the session persists (no re-scan needed).${NC}\n"
        echo ""
    fi
    printf "  ${DIM}Manage: picoclaw whatsapp${NC}\n"
    printf "  ${DIM}Logs:   picoclaw whatsapp logs${NC}\n"
}

# ════════════════════════════════════════════════
# STEP 9: OLLAMA (Local LLM Server)
# ════════════════════════════════════════════════
install_ollama() {
    step "9/14" "Installing Ollama (Local LLM Server)"

    if [[ "$SETUP_OLLAMA" != "true" ]]; then
        info "Skipped — Ollama not selected"
        return 0
    fi

    # ── a. Check if already installed ──
    if command -v ollama &>/dev/null; then
        local existing_ver=""
        existing_ver=$(ollama --version 2>/dev/null) || existing_ver="unknown"
        success "Ollama already installed: ${existing_ver}"
    else
        # ── b. Download and install via official script ──
        info "Installing Ollama via official installer..."
        curl -fsSL "${OLLAMA_INSTALL_URL}" | sh || die "Ollama installation failed"

        # ── c. Verify binary exists ──
        if ! command -v ollama &>/dev/null; then
            die "Ollama binary not found after installation"
        fi
        local installed_ver=""
        installed_ver=$(ollama --version 2>/dev/null) || installed_ver="unknown"
        success "Ollama installed: ${installed_ver}"
    fi

    # ── d. Enable and start the ollama systemd service ──
    info "Enabling Ollama systemd service..."
    systemctl enable "${OLLAMA_SERVICE}" 2>/dev/null || true
    systemctl start "${OLLAMA_SERVICE}" 2>/dev/null || true
    success "Ollama service enabled and started"

    # ── e. Wait for Ollama to be ready (up to 30 seconds) ──
    info "Waiting for Ollama API to be ready..."
    local ollama_ready=false
    local wait_count=0
    local max_wait=15
    while (( wait_count < max_wait )); do
        if curl -sf "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/tags" > /dev/null 2>&1; then
            ollama_ready=true
            break
        fi
        sleep 2
        wait_count=$((wait_count + 1))
    done

    if [[ "$ollama_ready" == "true" ]]; then
        success "Ollama API responding on http://${OLLAMA_HOST}:${OLLAMA_PORT}"
    else
        die "Ollama API not responding after 30 seconds — check: systemctl status ollama"
    fi

    # ── f. Pull the selected model ──
    info "Downloading model ${BOLD}${OLLAMA_MODEL}${NC}... (this may take several minutes)"
    ollama pull "$OLLAMA_MODEL" || die "Failed to pull model: ${OLLAMA_MODEL}"
    success "Model ${BOLD}${OLLAMA_MODEL}${NC} downloaded"

    # ── g. Verify model is available ──
    local model_present=false
    if ollama list 2>/dev/null | grep -q "${OLLAMA_MODEL%%:*}"; then
        model_present=true
    fi
    if [[ "$model_present" == "true" ]]; then
        success "Model verified in ollama list"
    else
        warn "Model may not have downloaded correctly — check: ollama list"
    fi

    # ── h. Create custom Modelfile with num_ctx ──
    # This is CRITICAL for RAM control — default Ollama context can be 128K+ which
    # will OOM a 6GB VPS. The custom Modelfile locks it to the user's chosen value.
    local custom_model_name="picoclaw-${OLLAMA_MODEL//[:\/]/-}"
    local modelfile_path="/tmp/picoclaw-modelfile"

    info "Creating custom model with num_ctx=${OLLAMA_NUM_CTX}..."
    cat > "$modelfile_path" << MFEOF
FROM ${OLLAMA_MODEL}
PARAMETER num_ctx ${OLLAMA_NUM_CTX}
MFEOF

    ollama create "$custom_model_name" -f "$modelfile_path" || die "Failed to create custom model"
    rm -f "$modelfile_path"
    success "Custom model created: ${BOLD}${custom_model_name}${NC} (num_ctx=${OLLAMA_NUM_CTX})"

    # ── i. Update config.json to use the custom model name ──
    if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
        local tmpfile=""
        tmpfile=$(mktemp)
        if jq --arg m "$custom_model_name" '.agents.defaults.model = $m' "$CONFIG_FILE" > "$tmpfile" 2>/dev/null; then
            mv "$tmpfile" "$CONFIG_FILE"
            success "Config updated: model → ${BOLD}${custom_model_name}${NC}"
        else
            rm -f "$tmpfile"
            warn "Failed to update config.json model name — update manually"
        fi
    fi

    # ── j. Update ollama.conf with custom model name ──
    local safe_model safe_custom safe_host
    safe_model="$(shell_escape "$OLLAMA_MODEL")"
    safe_custom="$(shell_escape "$custom_model_name")"
    safe_host="$(shell_escape "$OLLAMA_HOST")"
    cat > "$OLLAMA_CONF_FILE" << OLLAMACONF
# PicoClaw Ollama Configuration
# Updated by installer on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
OLLAMA_ENABLED='${SETUP_OLLAMA}'
OLLAMA_MODEL='${safe_model}'
OLLAMA_CUSTOM_MODEL='${safe_custom}'
OLLAMA_NUM_CTX='${OLLAMA_NUM_CTX}'
OLLAMA_HOST='${safe_host}'
OLLAMA_PORT='${OLLAMA_PORT}'
OLLAMACONF
    success "Ollama config updated → ${OLLAMA_CONF_FILE}"

    # ── k. Get model size for summary ──
    local model_size=""
    model_size=$(ollama list 2>/dev/null | grep "${custom_model_name}" | awk '{print $3, $4}') || model_size="unknown"
    if [[ -z "$model_size" || "$model_size" == " " ]]; then
        model_size=$(ollama list 2>/dev/null | grep "${OLLAMA_MODEL%%:*}" | head -1 | awk '{print $3, $4}') || model_size="unknown"
    fi

    # ── Summary ──
    separator
    printf "  ${GREEN}${BOLD}Ollama Installation Complete${NC}\n"
    printf "  ${BOLD}Service:${NC}     ollama (systemd-managed, auto-start on boot)\n"
    printf "  ${BOLD}Binary:${NC}      ${OLLAMA_BIN}\n"
    printf "  ${BOLD}Base model:${NC}  ${OLLAMA_MODEL}\n"
    printf "  ${BOLD}Custom:${NC}      ${custom_model_name}\n"
    printf "  ${BOLD}Model size:${NC}  ${model_size}\n"
    printf "  ${BOLD}Context:${NC}     ${OLLAMA_NUM_CTX} tokens\n"
    printf "  ${BOLD}API:${NC}         ${OLLAMA_API_BASE}\n"
    printf "  ${BOLD}Provider:${NC}    routed via vllm slot in config.json\n"
    echo ""
    printf "  ${DIM}Manage: picoclaw ollama${NC}\n"
    printf "  ${DIM}Logs:   picoclaw ollama logs${NC}\n"
    printf "  ${DIM}Models: picoclaw ollama list${NC}\n"
}

# ════════════════════════════════════════════════
# STEP 10: FTP SERVER (vsftpd)
# ════════════════════════════════════════════════
install_ftp_server() {
    step "10/14" "FTP Server (vsftpd)"

    if [[ "$SETUP_FTP" != "true" ]]; then
        info "Skipped — FTP server not selected"
        return 0
    fi

    # ── Install vsftpd ──
    info "Installing vsftpd..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vsftpd > /dev/null 2>&1 || die "vsftpd install failed"
    success "vsftpd installed"

    # ── Stop vsftpd while we configure ──
    systemctl stop vsftpd 2>/dev/null || true

    # ── Create FTP user with full filesystem access ──
    info "Configuring FTP user: ${FTP_USER}..."

    if [[ "$FTP_USER" == "root" ]]; then
        # Root already exists — just set the password
        echo "root:${FTP_PASS}" | chpasswd || die "Failed to set root password"
        success "FTP password set for root user"
    else
        if id "$FTP_USER" &>/dev/null; then
            info "User '${FTP_USER}' already exists — updating password"
            echo "${FTP_USER}:${FTP_PASS}" | chpasswd || die "Failed to set password"
        else
            useradd -m -s /bin/bash -d "/home/${FTP_USER}" "$FTP_USER" 2>/dev/null || die "Failed to create user"
            echo "${FTP_USER}:${FTP_PASS}" | chpasswd || die "Failed to set password"
        fi
        # Give the FTP user root-level access via group and sudoers
        usermod -aG sudo "$FTP_USER" 2>/dev/null || true
    fi
    success "FTP user '${FTP_USER}' configured with password"

    # ── Generate TLS certificate if enabled ──
    if [[ "$FTP_TLS" == "true" ]]; then
        info "Generating self-signed TLS certificate..."
        local cert_dir="/etc/ssl/private"
        mkdir -p "$cert_dir"

        if [[ ! -f "${cert_dir}/vsftpd.pem" ]]; then
            openssl req -x509 -nodes -days 3650 \
                -newkey rsa:2048 \
                -keyout "${cert_dir}/vsftpd.key" \
                -out "${cert_dir}/vsftpd.pem" \
                -subj "/C=US/ST=State/L=City/O=PicoClaw/OU=FTP/CN=$(hostname 2>/dev/null || echo 'picoclaw')" \
                > /dev/null 2>&1 || die "TLS certificate generation failed"
            chmod 600 "${cert_dir}/vsftpd.key" "${cert_dir}/vsftpd.pem"
        fi
        success "TLS certificate: ${cert_dir}/vsftpd.pem (valid 10 years)"
    fi

    # ── Detect public IP for passive mode ──
    local public_ip=""
    public_ip=$(curl -sf --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null) || true
    if [[ -z "$public_ip" ]]; then
        public_ip=$(curl -sf --connect-timeout 5 --max-time 10 https://ifconfig.me 2>/dev/null) || true
    fi
    if [[ -z "$public_ip" ]]; then
        public_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || public_ip="0.0.0.0"
    fi
    info "Detected public IP for passive mode: ${public_ip}"

    # ── Backup original vsftpd.conf ──
    if [[ -f /etc/vsftpd.conf ]]; then
        cp /etc/vsftpd.conf /etc/vsftpd.conf.bak.picoclaw 2>/dev/null || true
    fi

    # ── Write vsftpd configuration ──
    info "Writing vsftpd configuration..."

    cat > /etc/vsftpd.conf << VSFTPDEOF
# ═══════════════════════════════════════════════════════
# PicoClaw FTP Server Configuration (vsftpd)
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# User: ${FTP_USER} — Full filesystem access
# ═══════════════════════════════════════════════════════

# ── GENERAL ──
listen=YES
listen_ipv6=NO
listen_port=${FTP_PORT}
background=NO
session_support=YES
pam_service_name=vsftpd

# ── ACCESS CONTROL ──
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022

# ── FULL FILESYSTEM ACCESS ──
# The FTP user is NOT chrooted — full access to entire filesystem
chroot_local_user=NO
allow_writeable_chroot=YES

# ── USERLIST ──
# Only the PicoClaw FTP user is allowed
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list

# ── FILE PERMISSIONS ──
file_open_mode=0644
local_max_rate=0
max_per_ip=10
max_clients=20

# ── DIRECTORY LISTING ──
dirmessage_enable=YES
use_localtime=YES
ls_recurse_enable=YES
hide_ids=NO

# ── LOGGING ──
xferlog_enable=YES
xferlog_std_format=NO
vsftpd_log_file=/var/log/vsftpd.log
log_ftp_protocol=YES
dual_log_enable=YES
xferlog_file=/var/log/vsftpd-xfer.log

# ── PASSIVE MODE ──
pasv_enable=YES
pasv_min_port=${FTP_PASV_MIN}
pasv_max_port=${FTP_PASV_MAX}
pasv_address=${public_ip}
pasv_addr_resolve=NO

# ── ACTIVE MODE ──
port_enable=YES
connect_from_port_20=YES
ftp_data_port=20

# ── TIMEOUTS ──
idle_session_timeout=600
data_connection_timeout=300
accept_timeout=60
connect_timeout=60

# ── SECURITY ──
ascii_upload_enable=YES
ascii_download_enable=YES
async_abor_enable=YES
tcp_wrappers=NO
seccomp_sandbox=NO
VSFTPDEOF

# ── Append TLS config if enabled ──
    if [[ "$FTP_TLS" == "true" ]]; then
        cat >> /etc/vsftpd.conf << TLSEOF

# ── TLS/SSL ENCRYPTION ──
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=/etc/ssl/private/vsftpd.pem
rsa_private_key_file=/etc/ssl/private/vsftpd.key
ssl_ciphers=HIGH
require_ssl_reuse=NO
TLSEOF
        success "TLS configuration appended"
    fi

    # ── Create user list (only allow our FTP user) ──
    echo "${FTP_USER}" > /etc/vsftpd.user_list
    chmod 644 /etc/vsftpd.user_list
    success "User list: /etc/vsftpd.user_list (${FTP_USER} only)"

    # ── Ensure PAM allows our user ──
    # Some Debian vsftpd PAM configs block /etc/ftpusers — ensure our user is NOT in deny list
    if [[ -f /etc/ftpusers ]]; then
        sed -i "/^${FTP_USER}$/d" /etc/ftpusers 2>/dev/null || true
    fi

    # ── Create log files ──
    touch /var/log/vsftpd.log /var/log/vsftpd-xfer.log
    chmod 640 /var/log/vsftpd.log /var/log/vsftpd-xfer.log

    # ── Logrotate for FTP logs ──
    cat > /etc/logrotate.d/vsftpd-picoclaw << 'FTPLREOF'
/var/log/vsftpd.log /var/log/vsftpd-xfer.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    copytruncate
}
FTPLREOF
    success "FTP log rotation configured (14 days)"

    # ── Enable and start vsftpd ──
    systemctl daemon-reload || true
    systemctl enable vsftpd 2>/dev/null || true

    if [[ "$SETUP_PERFORMANCE" != "true" ]]; then
        # Start now only if we're not rebooting later
        systemctl start vsftpd 2>/dev/null || true
        sleep 1
        local rc=0
        systemctl is-active --quiet vsftpd 2>/dev/null || rc=$?
        if [[ $rc -eq 0 ]]; then
            success "vsftpd: ${GREEN}RUNNING${NC} on port ${FTP_PORT}"
        else
            warn "vsftpd may have issues — check: systemctl status vsftpd"
        fi
    else
        info "vsftpd will start automatically after the mandatory reboot"
    fi

    # ── Summary ──
    separator
    printf "  ${GREEN}${BOLD}FTP Server Installation Complete${NC}\n"
    printf "  ${BOLD}Service:${NC}     vsftpd (systemd-managed, auto-start on boot)\n"
    printf "  ${BOLD}Username:${NC}    ${FTP_USER}\n"
    printf "  ${BOLD}Port:${NC}        ${FTP_PORT}\n"
    printf "  ${BOLD}Passive:${NC}     ${FTP_PASV_MIN}-${FTP_PASV_MAX}\n"
    printf "  ${BOLD}Public IP:${NC}   ${public_ip}\n"
    printf "  ${BOLD}TLS:${NC}         ${FTP_TLS}\n"
    printf "  ${BOLD}Access:${NC}      ${RED}Full filesystem (/)${NC}\n"
    printf "  ${BOLD}Config:${NC}      /etc/vsftpd.conf\n"
    printf "  ${BOLD}Logs:${NC}        /var/log/vsftpd.log\n"
    echo ""
    printf "  ${DIM}Connect: ftp://${FTP_USER}@${public_ip}:${FTP_PORT}${NC}\n"
    printf "  ${DIM}Manage:  picoclaw ftp${NC}\n"
    echo ""
    printf "  ${YELLOW}⚠ This FTP user has full read/write access to the entire filesystem.${NC}\n"
    printf "  ${YELLOW}  Use a strong password and TLS if exposed to the internet.${NC}\n"
}

# ════════════════════════════════════════════════
# STEP 11: SYSTEMD + REBOOT SURVIVAL + BACKUP CRON
# ════════════════════════════════════════════════
setup_systemd() {
    step "11/14" "24/7 Service + Reboot Survival + Backup Schedule"

    if [[ "$SETUP_SYSTEMD" != "true" ]]; then
        info "Skipped systemd — start manually: picoclaw start"
    fi

    if [[ "$SETUP_SYSTEMD" == "true" ]]; then

        # ── Build gateway unit After= and Wants= lines ──
        local gw_after="After=network-online.target"
        local gw_wants="Wants=network-online.target"
        if [[ "$WA_ENABLED" == "true" ]]; then
            gw_after="After=network-online.target ${WA_BRIDGE_SERVICE}.service"
            gw_wants="Wants=network-online.target ${WA_BRIDGE_SERVICE}.service"
        fi
        if [[ "$SETUP_OLLAMA" == "true" ]]; then
            gw_after="${gw_after} ${OLLAMA_SERVICE}.service"
            gw_wants="${gw_wants} ${OLLAMA_SERVICE}.service"
        fi

        cat > /etc/systemd/system/picoclaw-gateway.service << SVCEOF
[Unit]
Description=PicoClaw AI Gateway (24/7)
Documentation=https://github.com/sipeed/picoclaw
${gw_after}
${gw_wants}
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
User=root
WorkingDirectory=/root
Environment=HOME=/root
Environment=PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/root/go/bin:/root/.local/bin
ExecStart=${PICOCLAW_REAL} gateway
Restart=always
RestartSec=5

ProtectSystem=false
ProtectHome=false
ReadWritePaths=/
PrivateTmp=false
NoNewPrivileges=false

StandardOutput=journal
StandardError=journal
SyslogIdentifier=picoclaw

[Install]
WantedBy=multi-user.target
SVCEOF

        systemctl daemon-reload || true
        systemctl enable picoclaw-gateway.service 2>/dev/null || true
        success "Service: picoclaw-gateway.service (enabled)"
        if [[ "$WA_ENABLED" == "true" ]]; then
            info "Gateway depends on ${WA_BRIDGE_SERVICE}.service (After= + Wants=)"
        fi
        if [[ "$SETUP_OLLAMA" == "true" ]]; then
            info "Gateway depends on ${OLLAMA_SERVICE}.service (After= + Wants=)"
        fi

        if [[ "$SETUP_PERFORMANCE" == "true" ]]; then
            info "Gateway will start automatically after the mandatory reboot"
        else
            local has_channel=false
            if [[ "$TG_ENABLED" == "true" || "$DC_ENABLED" == "true" || "$WA_ENABLED" == "true" || "$FS_ENABLED" == "true" || "$MC_ENABLED" == "true" ]]; then
                has_channel=true
            fi

            if [[ "$has_channel" == "true" ]]; then
                # For WhatsApp, only start gateway if bridge session exists
                local can_start_gw=true
                if [[ "$WA_ENABLED" == "true" ]]; then
                    if [[ ! -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
                        local other_channels=false
                        if [[ "$TG_ENABLED" == "true" || "$DC_ENABLED" == "true" || "$FS_ENABLED" == "true" || "$MC_ENABLED" == "true" ]]; then
                            other_channels=true
                        fi
                        if [[ "$other_channels" != "true" ]]; then
                            can_start_gw=false
                            info "Gateway not started — WhatsApp is the only channel and needs QR login first"
                            info "Run: ${CYAN}picoclaw whatsapp login${NC} then: ${CYAN}picoclaw start${NC}"
                        fi
                    fi
                fi

                if [[ "$can_start_gw" == "true" ]]; then
                    info "Starting gateway..."
                    systemctl restart picoclaw-gateway.service 2>/dev/null || true
                    sleep 3
                    local rc=0
                    systemctl is-active --quiet picoclaw-gateway 2>/dev/null || rc=$?
                    if [[ $rc -eq 0 ]]; then
                        success "Gateway RUNNING"
                    else
                        warn "Gateway may have issues — check: picoclaw logs"
                    fi
                fi
            else
                info "No channel enabled — gateway will start on boot (or: picoclaw start)"
            fi
        fi

        cat > /etc/systemd/system/picoclaw-watchdog.service << 'WDEOF'
[Unit]
Description=PicoClaw Watchdog
After=picoclaw-gateway.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'systemctl is-active --quiet picoclaw-gateway || systemctl restart picoclaw-gateway'
WDEOF

        cat > /etc/systemd/system/picoclaw-watchdog.timer << 'WTEOF'
[Unit]
Description=PicoClaw Watchdog Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=60
AccuracySec=10

[Install]
WantedBy=timers.target
WTEOF

        systemctl daemon-reload || true
        systemctl enable --now picoclaw-watchdog.timer 2>/dev/null || true
        success "Watchdog: picoclaw-watchdog.timer (every 60s)"

        cat > /etc/cron.d/picoclaw-boot << 'CRONEOF'
SHELL=/bin/bash
PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/root/go/bin
@reboot root sleep 15 && { systemctl is-active --quiet picoclaw-gateway || systemctl restart picoclaw-gateway; }
CRONEOF
        chmod 644 /etc/cron.d/picoclaw-boot
        success "Cron: @reboot fallback (/etc/cron.d/picoclaw-boot)"

        cat > /etc/logrotate.d/picoclaw << 'LREOF'
/var/log/picoclaw/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
LREOF
        success "Logrotate configured"
    fi

    # ── Auto-backup cron (independent of systemd choice) ──
    if [[ "$SETUP_AUTOBACKUP" == "true" ]]; then
        cat > /etc/cron.d/picoclaw-autobackup << ABEOF
SHELL=/bin/bash
PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/root/go/bin
# PicoClaw auto-backup: runs at 03:00 daily, script checks if N days elapsed
0 3 * * * root /usr/local/bin/picoclaw backup --auto 2>/dev/null
ABEOF
        chmod 644 /etc/cron.d/picoclaw-autobackup
        success "Auto-backup: every ${BACKUP_INTERVAL_DAYS} days at 03:00 (/etc/cron.d/picoclaw-autobackup)"
        info "Max backups kept: ${BACKUP_MAX_KEEP} (oldest purged automatically)"
    else
        rm -f /etc/cron.d/picoclaw-autobackup
        info "Auto-backup: disabled (manual only: picoclaw backup)"
    fi
}

# ════════════════════════════════════════════════
# STEP 12: UNIFIED CLI WRAPPER + LOGIN BANNER
# ════════════════════════════════════════════════
install_extras() {
    step "12/14" "CLI Wrapper & Login Banner"

    cat > "$PICOCLAW_BIN" << 'WRAPEOF'
#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# PicoClaw — Unified CLI
# All commands: picoclaw <command> [args...]
#
# Service:   start | stop | restart | logs | status
# Config:    edit | config | model | telegram
# WhatsApp:  whatsapp | whatsapp login | whatsapp logout
#            whatsapp status | whatsapp start | whatsapp stop
#            whatsapp restart | whatsapp logs | whatsapp enable
#            whatsapp disable
# Ollama:    ollama | ollama status | ollama start | ollama stop
#            ollama restart | ollama logs | ollama model
#            ollama list | ollama pull <model> | ollama remove <model>
#            ollama ctx <number>
# Backup:    backup [--auto] | backup list | backup settings
# Atlas:     atlas | atlas update | atlas list | atlas info <name>
# FTP:       ftp | ftp status | ftp start | ftp stop | ftp restart
#            ftp password | ftp port | ftp tls | ftp disable | ftp enable
# Native:    agent | gateway | onboard | cron | skills | version
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

BIN="/usr/local/bin/picoclaw.bin"
SVC="picoclaw-gateway"
CFG="/root/.picoclaw/config.json"
BACKUP_CONF="/root/.picoclaw/backup.conf"
BACKUP_BASE="/root/backup"
ATLAS_META="/root/.picoclaw/atlas.json"
ATLAS_SKILLS="/root/.picoclaw/workspace/skills"
ATLAS_REPO="pr0ace/atlas"
ATLAS_REPO_URL="https://github.com/${ATLAS_REPO}"
ATLAS_BRANCH="master"
ATLAS_API_TREE="https://api.github.com/repos/${ATLAS_REPO}/git/trees/${ATLAS_BRANCH}?recursive=1"
ATLAS_RAW_BASE="https://raw.githubusercontent.com/${ATLAS_REPO}/${ATLAS_BRANCH}"
FTP_CONF="/root/.picoclaw/ftp.conf"
WA_CONF="/root/.picoclaw/whatsapp.conf"
WA_BRIDGE_SVC="picoclaw-whatsapp-bridge"
OLLAMA_CONF="/root/.picoclaw/ollama.conf"
OLLAMA_SVC="ollama"

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; D='\033[2m'; M='\033[0;35m'; N='\033[0m'

# CLI Model Lists — full list for post-install model switching.
# Intentionally broader than WIZARD_MODELS_* (wizard shows curated subset).
CLI_MODELS_OPENROUTER="anthropic/claude-sonnet-4.5|Anthropic latest Sonnet, best coding+agents
anthropic/claude-opus-4.6|Anthropic most powerful, complex challenges
anthropic/claude-opus-4.5|Anthropic strong all-rounder
anthropic/claude-opus-4.1|Anthropic capable reasoning
anthropic/claude-opus-4|Anthropic first Opus 4
anthropic/claude-sonnet-4|Anthropic balanced, widely used
anthropic/claude-haiku-4.5|Anthropic fastest, cheapest
openai/gpt-5.2|OpenAI flagship, coding+agentic
openai/gpt-5.1|OpenAI configurable reasoning effort
openai/gpt-5|OpenAI previous gen reasoning
openai/gpt-5-mini|OpenAI fast, cost-efficient
openai/gpt-5-nano|OpenAI fastest, cheapest
openai/gpt-4.1|OpenAI smartest non-reasoning
openai/gpt-4.1-mini|OpenAI smaller, faster
openai/gpt-4.1-nano|OpenAI fastest GPT-4.1
openai/o3|OpenAI reasoning, complex tasks
openai/o4-mini|OpenAI fast cost-efficient reasoning
openai/gpt-4o|OpenAI legacy, still available
google/gemini-3-pro-preview|Google most intelligent, preview
google/gemini-3-flash-preview|Google fast+balanced, preview
google/gemini-2.5-flash|Google best price/perf, stable
google/gemini-2.5-pro|Google advanced thinking, stable
google/gemini-2.5-flash-lite|Google ultra-fast, cheapest
google/gemini-2.0-flash|Google previous gen (deprecates Mar 2026)
deepseek/deepseek-r1|DeepSeek reasoning, open-weight
deepseek/deepseek-v3-0324|DeepSeek fast general purpose
meta-llama/llama-4-maverick|Meta latest MoE
qwen/qwen3-235b-a22b|Alibaba frontier"

CLI_MODELS_OPENROUTER_ANTHROPIC="anthropic/claude-sonnet-4.5|Latest Sonnet, best coding+agents
anthropic/claude-opus-4.6|Most powerful, complex challenges
anthropic/claude-opus-4.5|Strong all-rounder
anthropic/claude-opus-4.1|Capable reasoning
anthropic/claude-opus-4|First Opus 4
anthropic/claude-sonnet-4|Balanced, widely used
anthropic/claude-haiku-4.5|Fastest, cheapest"

CLI_MODELS_ZHIPU="glm-5|744B MoE (40B active), flagship, agentic engineering
glm-4.7|355B MoE (32B active), coding+reasoning+agents
glm-4.7-flashx|Fast+cheap, extended FlashX
glm-4.7-flash|30B MoE (3B active), free tier
glm-4.6|357B, 200K context, agentic+coding
glm-4.5|355B MoE, reasoning+agents
glm-4.5-x|Extended context GLM-4.5
glm-4.5-air|106B MoE (12B active), balanced cost/perf
glm-4.5-airx|Extended context Air
glm-4.5-flash|Free tier, fast
glm-4-32b-0414-128k|Open-weight 32B, 128K context
glm-4.6v|106B vision, 128K ctx, native tool use
glm-4.6v-flashx|Fast+cheap vision
glm-4.5v|Vision multimodal
glm-4.6v-flash|9B vision, free tier"

CLI_MODELS_OPENAI="gpt-5.2|Flagship, coding+agentic
gpt-5.1|Configurable reasoning effort
gpt-5|Previous gen intelligent reasoning
gpt-5-mini|Fast, cost-efficient
gpt-5-nano|Fastest, cheapest GPT-5
gpt-4.1|Smartest non-reasoning
gpt-4.1-mini|Smaller, faster GPT-4.1
gpt-4.1-nano|Fastest GPT-4.1
o3|Reasoning, complex tasks
o3-pro|More compute for better responses
o4-mini|Fast cost-efficient reasoning
gpt-4o|Fast, intelligent, flexible
gpt-4o-mini|Fast, affordable small model"

CLI_MODELS_GEMINI="gemini-3-pro-preview|Most intelligent, preview
gemini-3-flash-preview|Fast+balanced, preview
gemini-2.5-flash|Best price/performance, stable
gemini-2.5-pro|Advanced thinking, stable
gemini-2.5-flash-lite|Ultra-fast, cheapest
gemini-2.0-flash|Previous gen (deprecates Mar 2026)"

CLI_MODELS_GROQ="llama-3.3-70b-versatile|Meta 70B, 280 t/s, best quality
llama-3.1-8b-instant|Meta 8B, 560 t/s, ultra-fast
openai/gpt-oss-120b|OpenAI open-weight 120B, 500 t/s
openai/gpt-oss-20b|OpenAI open-weight 20B, 1000 t/s
meta-llama/llama-4-maverick-17b-128e-instruct|Llama 4 MoE, 600 t/s
meta-llama/llama-4-scout-17b-16e-instruct|Llama 4 Scout, 750 t/s
qwen/qwen3-32b|Alibaba 32B, 400 t/s
moonshotai/kimi-k2-instruct-0905|Moonshot Kimi K2, 200 t/s"

CLI_MODELS_OLLAMA="qwen3:4b|2.5GB — best all-round intelligence, dual-mode, 100+ languages
phi4-mini|3.3GB — best tool calling + agent restraint, stable English
nanbeige4.1:3b|2.0GB — NEW Feb 2026, rivals 32B models, unified generalist
gemma3:4b|3.3GB — multimodal (understands images), strong general
qwen3:1.7b|1.0GB — ultra-light, good basics, 100+ languages
smollm3:3b|2.0GB — HuggingFace, reasoning + tool calling + multilingual
lfm2.5:1.2b|0.8GB — fastest inference (1.5s CPU), hybrid architecture
qwen3:0.6b|0.4GB — 600M params, impossibly good tool calling for size
deepseek-r1:1.5b|1.0GB — reasoning specialist, math focus
gemma3:1b|0.8GB — Google tiny, basic tasks
llama3.2:3b|2.0GB — Meta, solid instruction following
mistral:7b|4.1GB — classic workhorse (needs 8GB+ RAM)
qwen3:8b|4.7GB — most intelligent 8B (needs 8GB+ RAM)"

_json_escape() {
    local s="$1"
    s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

_shell_escape() { printf '%s' "${1//\'/\'\"\'\"\'}"; }

_extract_atlas_category() {
    local origin_file="$1"
    local cat="unknown"
    if [[ -f "$origin_file" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == category:* ]]; then
                cat="${line#category:}"
                cat="${cat#"${cat%%[![:space:]]*}"}"
                cat="${cat//[[:space:]]/}"
                break
            fi
        done < "$origin_file"
    fi
    if [[ -z "$cat" ]]; then
        cat="unknown"
    fi
    printf '%s' "$cat"
}

_load_backup_conf() {
    BACKUP_DIR="${BACKUP_BASE}"
    BACKUP_MAX_KEEP="18"
    BACKUP_INTERVAL_DAYS="6"
    BACKUP_AUTO_ENABLED="false"
    if [[ -f "$BACKUP_CONF" ]]; then
        source "$BACKUP_CONF" 2>/dev/null || true
    fi
}

_load_ftp_conf() {
    FTP_ENABLED="false"
    FTP_USER="root"
    FTP_PORT="21"
    FTP_PASV_MIN="40000"
    FTP_PASV_MAX="40100"
    FTP_TLS="false"
    if [[ -f "$FTP_CONF" ]]; then
        source "$FTP_CONF" 2>/dev/null || true
    fi
}

_save_ftp_conf() {
    local safe_ftp_user
    safe_ftp_user=$(_shell_escape "${FTP_USER}")
    cat > "$FTP_CONF" << FTPCONF
# PicoClaw FTP Configuration
# Updated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
FTP_ENABLED='${FTP_ENABLED}'
FTP_USER='${safe_ftp_user}'
FTP_PORT='${FTP_PORT}'
FTP_PASV_MIN='${FTP_PASV_MIN}'
FTP_PASV_MAX='${FTP_PASV_MAX}'
FTP_TLS='${FTP_TLS}'
FTPCONF
}

_load_wa_conf() {
    WA_ENABLED="false"
    WA_BRIDGE_PORT="3001"
    WA_BRIDGE_DIR="/opt/picoclaw-whatsapp-bridge"
    WA_BRIDGE_AUTH_DIR="/root/.picoclaw/whatsapp-auth"
    WA_BRIDGE_SERVICE="picoclaw-whatsapp-bridge"
    WA_USER_ID=""
    if [[ -f "$WA_CONF" ]]; then
        source "$WA_CONF" 2>/dev/null || true
    fi
}

_save_wa_conf() {
    local safe_wa_bridge_dir safe_wa_auth_dir safe_wa_user_id
    safe_wa_bridge_dir=$(_shell_escape "${WA_BRIDGE_DIR}")
    safe_wa_auth_dir=$(_shell_escape "${WA_BRIDGE_AUTH_DIR}")
    safe_wa_user_id=$(_shell_escape "${WA_USER_ID}")
    cat > "$WA_CONF" << WACONF
# PicoClaw WhatsApp Bridge Configuration
# Updated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
WA_ENABLED='${WA_ENABLED}'
WA_BRIDGE_PORT='${WA_BRIDGE_PORT}'
WA_BRIDGE_DIR='${safe_wa_bridge_dir}'
WA_BRIDGE_AUTH_DIR='${safe_wa_auth_dir}'
WA_BRIDGE_SERVICE='${WA_BRIDGE_SERVICE}'
WA_USER_ID='${safe_wa_user_id}'
WACONF
}

_load_ollama_conf() {
    OLLAMA_ENABLED="false"
    OLLAMA_MODEL=""
    OLLAMA_CUSTOM_MODEL=""
    OLLAMA_NUM_CTX="8192"
    OLLAMA_HOST="127.0.0.1"
    OLLAMA_PORT="11434"
    if [[ -f "$OLLAMA_CONF" ]]; then
        source "$OLLAMA_CONF" 2>/dev/null || true
    fi
}

_save_ollama_conf() {
    local safe_ollama_model safe_ollama_custom safe_ollama_host
    safe_ollama_model=$(_shell_escape "${OLLAMA_MODEL}")
    safe_ollama_custom=$(_shell_escape "${OLLAMA_CUSTOM_MODEL}")
    safe_ollama_host=$(_shell_escape "${OLLAMA_HOST}")
    cat > "$OLLAMA_CONF" << OLLAMACONF
# PicoClaw Ollama Configuration
# Updated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
OLLAMA_ENABLED='${OLLAMA_ENABLED}'
OLLAMA_MODEL='${safe_ollama_model}'
OLLAMA_CUSTOM_MODEL='${safe_ollama_custom}'
OLLAMA_NUM_CTX='${OLLAMA_NUM_CTX}'
OLLAMA_HOST='${safe_ollama_host}'
OLLAMA_PORT='${OLLAMA_PORT}'
OLLAMACONF
}

cmd_help() {
    "$BIN" 2>&1 || true
    echo ""
    printf "${B}Service commands:${N}\n"
    printf "  ${C}picoclaw start${N}                     start gateway\n"
    printf "  ${C}picoclaw stop${N}                      stop gateway\n"
    printf "  ${C}picoclaw restart${N}                   restart gateway\n"
    printf "  ${C}picoclaw logs${N}                      follow live logs (ctrl+c)\n"
    printf "  ${C}picoclaw logs -n 50${N}                last 50 lines\n"
    printf "  ${C}picoclaw status${N}                    full status dashboard\n"
    echo ""
    printf "${B}Config commands:${N}\n"
    printf "  ${C}picoclaw edit${N}                      edit config.json\n"
    printf "  ${C}picoclaw model${N}                     switch model interactively\n"
    printf "  ${C}picoclaw telegram${N}                  manage Telegram settings & users\n"
    echo ""
    printf "${B}WhatsApp commands:${N}\n"
    printf "  ${C}picoclaw whatsapp${N}                  WhatsApp management menu\n"
    printf "  ${C}picoclaw whatsapp login${N}            scan QR code to link account\n"
    printf "  ${C}picoclaw whatsapp logout${N}           unlink account (removes session)\n"
    printf "  ${C}picoclaw whatsapp status${N}           show bridge status\n"
    printf "  ${C}picoclaw whatsapp start${N}            start bridge service\n"
    printf "  ${C}picoclaw whatsapp stop${N}             stop bridge service\n"
    printf "  ${C}picoclaw whatsapp restart${N}          restart bridge service\n"
    printf "  ${C}picoclaw whatsapp logs${N}             follow bridge logs\n"
    printf "  ${C}picoclaw whatsapp enable${N}           enable WhatsApp in config\n"
    printf "  ${C}picoclaw whatsapp disable${N}          disable WhatsApp in config\n"
    echo ""
    printf "${B}Ollama commands:${N}\n"
    printf "  ${C}picoclaw ollama${N}                    Ollama management menu\n"
    printf "  ${C}picoclaw ollama status${N}             show Ollama status\n"
    printf "  ${C}picoclaw ollama start${N}              start Ollama service\n"
    printf "  ${C}picoclaw ollama stop${N}               stop Ollama service\n"
    printf "  ${C}picoclaw ollama restart${N}            restart Ollama service\n"
    printf "  ${C}picoclaw ollama logs${N}               follow Ollama logs\n"
    printf "  ${C}picoclaw ollama model${N}              switch model interactively\n"
    printf "  ${C}picoclaw ollama list${N}               list installed models\n"
    printf "  ${C}picoclaw ollama pull <model>${N}       pull a new model\n"
    printf "  ${C}picoclaw ollama remove <model>${N}     remove a model\n"
    printf "  ${C}picoclaw ollama ctx <number>${N}       change context window size\n"
    echo ""
    printf "${B}Backup commands:${N}\n"
    printf "  ${C}picoclaw backup${N}                    create manual backup now\n"
    printf "  ${C}picoclaw backup --auto${N}             auto-backup (called by cron)\n"
    printf "  ${C}picoclaw backup list${N}               list all backups\n"
    printf "  ${C}picoclaw backup settings${N}           view/change backup settings\n"
    echo ""
    printf "${B}Atlas commands:${N}\n"
    printf "  ${C}picoclaw atlas${N}                     show Atlas skills status\n"
    printf "  ${C}picoclaw atlas list${N}                list all installed Atlas skills\n"
    printf "  ${C}picoclaw atlas update${N}              update all skills from repository\n"
    printf "  ${C}picoclaw atlas info <name>${N}         show details for a specific skill\n"
    echo ""
    printf "${B}FTP commands:${N}\n"
    printf "  ${C}picoclaw ftp${N}                       FTP server status & management\n"
    printf "  ${C}picoclaw ftp status${N}                show FTP server status\n"
    printf "  ${C}picoclaw ftp start${N}                 start FTP server\n"
    printf "  ${C}picoclaw ftp stop${N}                  stop FTP server\n"
    printf "  ${C}picoclaw ftp restart${N}               restart FTP server\n"
    printf "  ${C}picoclaw ftp password${N}              change FTP password\n"
    printf "  ${C}picoclaw ftp port${N}                  change FTP port\n"
    printf "  ${C}picoclaw ftp tls${N}                   toggle TLS on/off\n"
    printf "  ${C}picoclaw ftp logs${N}                  view FTP logs\n"
    printf "  ${C}picoclaw ftp disable${N}               disable FTP server\n"
    printf "  ${C}picoclaw ftp enable${N}                enable FTP server\n"
    echo ""
}

cmd_start() {
    # Start Ollama first if enabled
    _load_ollama_conf
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        if ! systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
            printf "  ${M}🦞${N} Starting Ollama...\n"
            systemctl start "$OLLAMA_SVC" 2>/dev/null || true
            sleep 2
            if systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
                printf "  ${G}✔${N} Ollama running\n"
            else
                printf "  ${Y}⚠${N} Ollama failed to start — check: picoclaw ollama logs\n"
            fi
        fi
    fi

    # Start WhatsApp bridge first if enabled
    _load_wa_conf
    if [[ "$WA_ENABLED" == "true" ]]; then
        if [[ -f "/etc/systemd/system/${WA_BRIDGE_SVC}.service" ]]; then
            if ! systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
                printf "  ${M}🦞${N} Starting WhatsApp bridge...\n"
                systemctl start "$WA_BRIDGE_SVC" 2>/dev/null || true
                sleep 2
                if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
                    printf "  ${G}✔${N} WhatsApp bridge running\n"
                else
                    printf "  ${Y}⚠${N} WhatsApp bridge failed to start — check: picoclaw whatsapp logs\n"
                fi
            fi
        fi
    fi

    printf "  ${M}🦞${N} Starting PicoClaw gateway...\n"
    systemctl start "$SVC" 2>/dev/null
    sleep 1
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        printf "  ${G}✔${N} Gateway running (PID $(systemctl show "$SVC" --property=MainPID --value 2>/dev/null))\n"
    else
        printf "  ${R}✘${N} Failed to start — check: picoclaw logs\n"
        exit 1
    fi
}

cmd_stop() {
    printf "  ${M}🦞${N} Stopping PicoClaw gateway...\n"
    systemctl stop "$SVC" 2>/dev/null
    printf "  ${G}✔${N} Gateway stopped\n"
}

cmd_restart() {
    # Restart Ollama first if enabled
    _load_ollama_conf
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        if ! systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
            printf "  ${M}🦞${N} Starting Ollama...\n"
            systemctl start "$OLLAMA_SVC" 2>/dev/null || true
            sleep 2
            if systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
                printf "  ${G}✔${N} Ollama running\n"
            else
                printf "  ${Y}⚠${N} Ollama failed — check: picoclaw ollama logs\n"
            fi
        fi
    fi

    # Restart WhatsApp bridge first if enabled
    _load_wa_conf
    if [[ "$WA_ENABLED" == "true" ]]; then
        if [[ -f "/etc/systemd/system/${WA_BRIDGE_SVC}.service" ]]; then
            printf "  ${M}🦞${N} Restarting WhatsApp bridge...\n"
            systemctl restart "$WA_BRIDGE_SVC" 2>/dev/null || true
            sleep 2
            if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
                printf "  ${G}✔${N} WhatsApp bridge running\n"
            else
                printf "  ${Y}⚠${N} WhatsApp bridge failed — check: picoclaw whatsapp logs\n"
            fi
        fi
    fi

    printf "  ${M}🦞${N} Restarting PicoClaw gateway...\n"
    systemctl restart "$SVC" 2>/dev/null
    sleep 2
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        printf "  ${G}✔${N} Gateway running (PID $(systemctl show "$SVC" --property=MainPID --value 2>/dev/null))\n"
    else
        printf "  ${R}✘${N} Failed to restart — check: picoclaw logs\n"
        exit 1
    fi
}

cmd_logs() {
    shift
    if [[ $# -eq 0 ]]; then
        exec journalctl -u "$SVC" -f
    else
        exec journalctl -u "$SVC" "$@"
    fi
}

cmd_edit() {
    if command -v nano &>/dev/null; then
        exec nano "$CFG"
    elif command -v vi &>/dev/null; then
        exec vi "$CFG"
    else
        printf "  ${R}✘${N} No editor found. Edit manually: ${CFG}\n"
        exit 1
    fi
}

cmd_status() {
    echo ""
    printf "${B}🦞 PicoClaw Status${N}\n"
    echo ""

    if [[ -x "$BIN" ]]; then
        local ver=""
        ver=$("$BIN" version 2>/dev/null) || ver="unknown"
        printf "  Binary:    ${G}●${N} %s (%s, %s)\n" "$BIN" "$ver" "$(du -h "$BIN" | awk '{print $1}')"
    else
        printf "  Binary:    ${R}● missing${N}\n"
    fi

    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        local since="" pid=""
        since=$(systemctl show "$SVC" --property=ActiveEnterTimestamp --value 2>/dev/null) || true
        pid=$(systemctl show "$SVC" --property=MainPID --value 2>/dev/null) || true
        printf "  Gateway:   ${G}● running${N}  PID %s  since %s\n" "$pid" "$since"
    elif systemctl is-enabled --quiet "$SVC" 2>/dev/null; then
        printf "  Gateway:   ${R}● stopped${N} (enabled — run: picoclaw start)\n"
    else
        printf "  Gateway:   ${D}○ not configured${N}\n"
    fi

    if systemctl is-active --quiet picoclaw-watchdog.timer 2>/dev/null; then
        printf "  Watchdog:  ${G}● active${N} (every 60s)\n"
    else
        printf "  Watchdog:  ${D}○ inactive${N}\n"
    fi

    if [[ -f /etc/cron.d/picoclaw-boot ]]; then
        printf "  Cron:      ${G}● @reboot fallback${N}\n"
    else
        printf "  Cron:      ${D}○ not configured${N}\n"
    fi

    if [[ -f /etc/sysctl.d/99-picoclaw-performance.conf ]]; then
        local cc=""
        cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) || cc="?"
        local swap_val=""
        swap_val=$(sysctl -n vm.swappiness 2>/dev/null) || swap_val="?"
        printf "  Perf:      ${G}● optimized${N} (BBR=%s, swappiness=%s)\n" "$cc" "$swap_val"
    else
        printf "  Perf:      ${D}○ not optimized${N}\n"
    fi

    # ── Ollama status ──
    _load_ollama_conf
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        if systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
            local ollama_pid=""
            ollama_pid=$(systemctl show "$OLLAMA_SVC" --property=MainPID --value 2>/dev/null) || true
            local ollama_model_display="${OLLAMA_CUSTOM_MODEL:-${OLLAMA_MODEL}}"
            local ollama_ram=""
            if [[ -n "$ollama_pid" && "$ollama_pid" != "0" ]]; then
                ollama_ram=$(ps -o rss= -p "$ollama_pid" 2>/dev/null | awk '{printf "%.0fMB", $1/1024}') || ollama_ram="?"
            fi
            printf "  Ollama:    ${G}● running${N} PID %s (%s, %s RAM)\n" "$ollama_pid" "$ollama_model_display" "$ollama_ram"
        else
            printf "  Ollama:    ${R}● stopped${N} (enabled — run: picoclaw ollama start)\n"
        fi
    else
        if command -v ollama &>/dev/null; then
            printf "  Ollama:    ${D}○ disabled${N} (installed, run: picoclaw ollama)\n"
        else
            printf "  Ollama:    ${D}○ not installed${N}\n"
        fi
    fi

    # ── WhatsApp bridge status ──
    _load_wa_conf
    if [[ "$WA_ENABLED" == "true" ]]; then
        if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
            local wa_pid=""
            wa_pid=$(systemctl show "$WA_BRIDGE_SVC" --property=MainPID --value 2>/dev/null) || true
            local wa_linked="unlinked"
            if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
                wa_linked="linked"
            fi
            printf "  WhatsApp:  ${G}● running${N} PID %s (port %s, %s)\n" "$wa_pid" "$WA_BRIDGE_PORT" "$wa_linked"
        else
            local wa_linked="unlinked"
            if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
                wa_linked="linked"
            fi
            printf "  WhatsApp:  ${R}● stopped${N} (%s — run: picoclaw whatsapp start)\n" "$wa_linked"
        fi
    else
        if [[ -d "/opt/picoclaw-whatsapp-bridge" ]]; then
            printf "  WhatsApp:  ${D}○ disabled${N} (installed, run: picoclaw whatsapp enable)\n"
        else
            printf "  WhatsApp:  ${D}○ not installed${N}\n"
        fi
    fi

    # ── FTP status ──
    _load_ftp_conf
    if [[ "$FTP_ENABLED" == "true" ]]; then
        if systemctl is-active --quiet vsftpd 2>/dev/null; then
            printf "  FTP:       ${G}● running${N} (%s@:%s, TLS=%s)\n" "$FTP_USER" "$FTP_PORT" "$FTP_TLS"
        else
            printf "  FTP:       ${R}● stopped${N} (enabled — run: picoclaw ftp start)\n"
        fi
    else
        if command -v vsftpd &>/dev/null; then
            printf "  FTP:       ${D}○ disabled${N} (installed, run: picoclaw ftp enable)\n"
        else
            printf "  FTP:       ${D}○ not installed${N}\n"
        fi
    fi

    # ── Atlas status ──
    local atlas_count=0
    if [[ -d "$ATLAS_SKILLS" ]]; then
        for _sd in "${ATLAS_SKILLS}"/*/; do
            if [[ -f "${_sd}SKILL.md" ]]; then
                atlas_count=$((atlas_count + 1))
            fi
        done
    fi
    if [[ $atlas_count -gt 0 ]]; then
        local atlas_ts=""
        if [[ -f "$ATLAS_META" ]] && command -v jq &>/dev/null; then
            atlas_ts=$(jq -r '.last_updated // empty' "$ATLAS_META" 2>/dev/null) || true
        fi
        printf "  Atlas:     ${G}● ${atlas_count} skill(s)${N}${D}$(if [[ -n "$atlas_ts" ]]; then echo " (updated ${atlas_ts})"; fi)${N}\n"
    else
        printf "  Atlas:     ${D}○ no skills installed${N}\n"
    fi

    _load_backup_conf
    local bk_count=0
    bk_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l) || true
    if [[ -f /etc/cron.d/picoclaw-autobackup ]]; then
        printf "  Backup:    ${G}● auto${N} every %sd, %s/%s snapshots\n" "$BACKUP_INTERVAL_DAYS" "$bk_count" "$BACKUP_MAX_KEEP"
    elif [[ $bk_count -gt 0 ]]; then
        printf "  Backup:    ${G}● manual${N} %s snapshot(s) in %s\n" "$bk_count" "$BACKUP_DIR"
    else
        printf "  Backup:    ${D}○ none${N}\n"
    fi

    echo ""

    if [[ -f "$CFG" ]] && command -v jq &>/dev/null; then
        local m=""
        m=$(jq -r '.agents.defaults.model // empty' "$CFG" 2>/dev/null) || true

        local or_key="" or_base="" oa_key="" gm_key="" zh_key="" gr_key="" vl_key="" vl_base=""
        or_key=$(jq -r '.providers.openrouter.api_key // empty' "$CFG" 2>/dev/null) || true
        or_base=$(jq -r '.providers.openrouter.api_base // empty' "$CFG" 2>/dev/null) || true
        oa_key=$(jq -r '.providers.openai.api_key // empty' "$CFG" 2>/dev/null) || true
        gm_key=$(jq -r '.providers.gemini.api_key // empty' "$CFG" 2>/dev/null) || true
        zh_key=$(jq -r '.providers.zhipu.api_key // empty' "$CFG" 2>/dev/null) || true
        gr_key=$(jq -r '.providers.groq.api_key // empty' "$CFG" 2>/dev/null) || true
        vl_key=$(jq -r '.providers.vllm.api_key // empty' "$CFG" 2>/dev/null) || true
        vl_base=$(jq -r '.providers.vllm.api_base // empty' "$CFG" 2>/dev/null) || true

        local prov="unknown"
        if [[ -n "$or_key" && "$or_base" == *"groq.com"* ]]; then
            prov="groq (via openrouter slot)"
        elif [[ -n "$or_key" && "$or_base" == *"openrouter.ai"* ]]; then
            prov="openrouter"
        elif [[ "$OLLAMA_ENABLED" == "true" && "$vl_base" == *"11434"* ]]; then
            prov="ollama (local, via vllm slot)"
        elif [[ -n "$zh_key" ]]; then prov="zhipu"
        elif [[ -n "$oa_key" ]]; then prov="openai"
        elif [[ -n "$gm_key" ]]; then prov="gemini"
        elif [[ -n "$gr_key" ]]; then prov="groq"
        elif [[ -n "$vl_key" || -n "$vl_base" ]]; then prov="vllm"
        fi

        printf "  Provider:  ${B}%s${N}\n" "$prov"
        printf "  Model:     ${C}%s${N}\n" "$m"
        echo ""

        for ch in telegram discord whatsapp feishu maixcam; do
            local en=""
            en=$(jq -r ".channels.${ch}.enabled // false" "$CFG" 2>/dev/null) || true
            local label="${ch^}"
            if [[ "$en" == "true" ]]; then
                local af=""
                af=$(jq -r ".channels.${ch}.allow_from | if length > 0 then join(\", \") else \"any\" end" "$CFG" 2>/dev/null) || af="?"
                printf "  %-11s ${G}● on${N}   ${D}(%s)${N}\n" "${label}:" "$af"
            else
                printf "  %-11s ${D}○ off${N}\n" "${label}:"
            fi
        done

        echo ""

        local bk=""
        bk=$(jq -r '.tools.web.search.api_key // empty' "$CFG" 2>/dev/null) || true
        if [[ -n "$bk" ]]; then
            printf "  Search:    ${G}● brave${N}\n"
        else
            printf "  Search:    ${D}○ off${N}\n"
        fi

        if [[ -n "$gr_key" ]]; then
            printf "  Voice:     ${G}● groq whisper${N}\n"
        else
            printf "  Voice:     ${D}○ off${N}\n"
        fi
    else
        printf "  ${D}Config: ${CFG} (not found or jq missing)${N}\n"
    fi

    echo ""
    printf "${B}System${N}\n"
    printf "  RAM:   $(free -h | awk '/^Mem:/{printf "%s / %s", $3, $2}')\n"
    if swapon --show=NAME,TYPE,SIZE 2>/dev/null | grep -q "zram"; then
        local zram_info=""
        zram_info=$(swapon --show=NAME,SIZE 2>/dev/null | grep zram | awk '{print $2}') || true
        printf "  zram:  ${G}● active${N} (${zram_info} compressed swap)\n"
    fi
    printf "  Disk:  $(df -h / | awk 'NR==2{printf "%s / %s (%s used)", $3, $2, $5}')\n"
    printf "  Up:    $(uptime -p 2>/dev/null || uptime)\n"
    echo ""
}

cmd_model() {
    if [[ ! -f "$CFG" ]]; then
        printf "  ${R}✘ Config not found: ${CFG}${N}\n"
        printf "  ${D}Run the installer first.${N}\n"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        printf "  ${R}✘ jq is required but not installed${N}\n"
        exit 1
    fi

    local CURRENT_MODEL=""
    CURRENT_MODEL=$(jq -r '.agents.defaults.model // empty' "$CFG" 2>/dev/null)
    if [[ -z "$CURRENT_MODEL" ]]; then
        printf "  ${R}✘ No model found in config${N}\n"
        exit 1
    fi

    local or_key="" or_base="" oa_key="" gm_key="" zh_key="" gr_key="" vl_key="" vl_base=""
    or_key=$(jq -r '.providers.openrouter.api_key // empty' "$CFG" 2>/dev/null) || true
    or_base=$(jq -r '.providers.openrouter.api_base // empty' "$CFG" 2>/dev/null) || true
    oa_key=$(jq -r '.providers.openai.api_key // empty' "$CFG" 2>/dev/null) || true
    gm_key=$(jq -r '.providers.gemini.api_key // empty' "$CFG" 2>/dev/null) || true
    zh_key=$(jq -r '.providers.zhipu.api_key // empty' "$CFG" 2>/dev/null) || true
    gr_key=$(jq -r '.providers.groq.api_key // empty' "$CFG" 2>/dev/null) || true
    vl_key=$(jq -r '.providers.vllm.api_key // empty' "$CFG" 2>/dev/null) || true
    vl_base=$(jq -r '.providers.vllm.api_base // empty' "$CFG" 2>/dev/null) || true

    _load_ollama_conf

    local PROVIDER="unknown"
    if [[ "$OLLAMA_ENABLED" == "true" && "$vl_base" == *"11434"* ]]; then
        PROVIDER="ollama"
    elif [[ -n "$or_key" && "$or_base" == *"groq.com"* ]]; then
        PROVIDER="groq"
    elif [[ -n "$gr_key" && -z "$or_key" ]]; then
        PROVIDER="groq"
    elif [[ -n "$or_key" && "$or_base" == *"openrouter.ai"* ]]; then
        if [[ "$CURRENT_MODEL" == anthropic/* ]]; then
            PROVIDER="openrouter-anthropic"
        else
            PROVIDER="openrouter"
        fi
    elif [[ -n "$zh_key" ]]; then PROVIDER="zhipu"
    elif [[ -n "$oa_key" ]]; then PROVIDER="openai"
    elif [[ -n "$gm_key" ]]; then PROVIDER="gemini"
    elif [[ -n "$vl_key" || -n "$vl_base" ]]; then PROVIDER="vllm"
    fi

    if [[ "$PROVIDER" == "ollama" ]]; then
        echo ""
        printf "  ${Y}⚠${N} Provider is Ollama (local). Use ${C}picoclaw ollama model${N} to switch models.\n"
        printf "  ${D}The Ollama model switcher handles downloading and Modelfile creation.${N}\n"
        echo ""
        return 0
    fi

    local pname=""
    case "$PROVIDER" in
        openrouter)           pname="OpenRouter" ;;
        openrouter-anthropic) pname="Anthropic (via OpenRouter)" ;;
        zhipu)                pname="Zhipu" ;;
        openai)               pname="OpenAI" ;;
        gemini)               pname="Gemini (Google)" ;;
        groq)                 pname="Groq" ;;
        vllm)                 pname="vLLM / Local" ;;
        *)                    pname="$PROVIDER" ;;
    esac

    local MODEL_DATA=""
    case "$PROVIDER" in
        openrouter)           MODEL_DATA="$CLI_MODELS_OPENROUTER" ;;
        openrouter-anthropic) MODEL_DATA="$CLI_MODELS_OPENROUTER_ANTHROPIC" ;;
        zhipu)                MODEL_DATA="$CLI_MODELS_ZHIPU" ;;
        openai)               MODEL_DATA="$CLI_MODELS_OPENAI" ;;
        gemini)               MODEL_DATA="$CLI_MODELS_GEMINI" ;;
        groq)                 MODEL_DATA="$CLI_MODELS_GROQ" ;;
        vllm)                 MODEL_DATA="" ;;
        *)                    MODEL_DATA="" ;;
    esac

    echo ""
    printf "${M}${B}  🦞 PicoClaw — Model Switcher${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""
    printf "  Provider:       ${B}${pname}${N}\n"
    printf "  Current model:  ${C}${CURRENT_MODEL}${N}\n"
    echo ""

    if [[ "$PROVIDER" == "unknown" ]]; then
        printf "  ${R}✘ Could not detect provider from config${N}\n"
        printf "  ${D}Edit manually: picoclaw edit${N}\n"
        exit 1
    fi

    local NEW_MODEL=""

    if [[ -z "$MODEL_DATA" ]]; then
        if [[ "$PROVIDER" == "vllm" ]]; then
            printf "  ${D}vLLM has no fixed model list — enter model ID manually.${N}\n"
            echo ""
            printf "  ${C}➜${N} Enter new model ID: "
            read -r NEW_MODEL
            if [[ -z "$NEW_MODEL" ]]; then
                printf "  ${Y}⚠ Cancelled — no model entered${N}\n"
                exit 0
            fi
            if [[ "$NEW_MODEL" == "$CURRENT_MODEL" ]]; then
                printf "  ${Y}⚠ That's already the current model${N}\n"
                exit 0
            fi
        else
            printf "  ${R}✘ No models available for provider: $PROVIDER${N}\n"
            exit 1
        fi
    else
        local -a MODEL_IDS=()
        local -a MODEL_DESCS=()
        while IFS='|' read -r mid mdesc; do
            if [[ -n "$mid" && "$mid" != "$CURRENT_MODEL" ]]; then
                MODEL_IDS+=("$mid")
                MODEL_DESCS+=("$mdesc")
            fi
        done <<< "$MODEL_DATA"

        if [[ ${#MODEL_IDS[@]} -eq 0 ]]; then
            printf "  ${Y}⚠ No other models available for this provider${N}\n"
            echo ""
            printf "  ${C}➜${N} Enter custom model ID (or press Enter to cancel): "
            read -r NEW_MODEL
            if [[ -z "$NEW_MODEL" ]]; then
                printf "  ${D}Cancelled.${N}\n"
                exit 0
            fi
            if [[ "$NEW_MODEL" == "$CURRENT_MODEL" ]]; then
                printf "  ${Y}⚠ That's already the current model${N}\n"
                exit 0
            fi
        else
            local COUNT=${#MODEL_IDS[@]}
            printf "  ${B}Available models:${N}\n"
            echo ""

            for i in "${!MODEL_IDS[@]}"; do
                local NUM=$((i + 1))
                printf "    ${C}%2d${N}) %-48s ${D}%s${N}\n" "$NUM" "${MODEL_IDS[$i]}" "${MODEL_DESCS[$i]}"
            done

            echo ""
            printf "    ${C} c${N}) Custom model ID\n"
            echo ""

            while true; do
                printf "  ${C}➜${N} Choose (1-${COUNT}, or c for custom): "
                local CHOICE=""
                read -r CHOICE

                if [[ "$CHOICE" == "c" || "$CHOICE" == "C" ]]; then
                    printf "  ${C}➜${N} Enter model ID: "
                    read -r NEW_MODEL
                    if [[ -z "$NEW_MODEL" ]]; then
                        printf "  ${Y}⚠ Cancelled — no model entered${N}\n"
                        exit 0
                    fi
                    if [[ "$NEW_MODEL" == "$CURRENT_MODEL" ]]; then
                        printf "  ${Y}⚠ That's already the current model${N}\n"
                        continue
                    fi
                    break
                elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= COUNT )); then
                    NEW_MODEL="${MODEL_IDS[$((CHOICE - 1))]}"
                    break
                else
                    printf "  ${Y}⚠ Invalid — enter 1-${COUNT} or c for custom${N}\n"
                fi
            done
        fi
    fi

    echo ""
    printf "  ${D}Change model:${N}\n"
    printf "    ${R}${CURRENT_MODEL}${N}  →  ${G}${NEW_MODEL}${N}\n"
    echo ""
    printf "  ${C}➜${N} Apply this change? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        exit 0
    fi

    local TMPFILE=""
    TMPFILE=$(mktemp)
    if jq --arg m "$NEW_MODEL" '.agents.defaults.model = $m' "$CFG" > "$TMPFILE" 2>/dev/null; then
        mv "$TMPFILE" "$CFG"
        echo ""
        printf "  ${G}✔${N} Model changed to: ${B}${NEW_MODEL}${N}\n"
        printf "  ${D}Config: ${CFG}${N}\n"
    else
        rm -f "$TMPFILE"
        printf "  ${R}✘ Failed to update config — jq error${N}\n"
        exit 1
    fi

    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        echo ""
        printf "  ${C}➜${N} Restart gateway to apply? ${D}[Y/n]${N}: "
        local DO_RESTART=""
        read -r DO_RESTART
        DO_RESTART="${DO_RESTART:-y}"
        if [[ "${DO_RESTART,,}" == "y" || "${DO_RESTART,,}" == "yes" ]]; then
            printf "  ${M}🦞${N} Restarting gateway...\n"
            systemctl restart "$SVC" 2>/dev/null || true
            sleep 2
            if systemctl is-active --quiet "$SVC" 2>/dev/null; then
                printf "  ${G}✔${N} Gateway running with ${B}${NEW_MODEL}${N}\n"
            else
                printf "  ${Y}⚠${N} Gateway may have issues — check: picoclaw logs\n"
            fi
        else
            printf "  ${D}Model saved. Restart later with: picoclaw restart${N}\n"
        fi
    else
        printf "  ${D}Gateway not running. Start with: picoclaw start${N}\n"
    fi
    echo ""
}

cmd_telegram() {
    if [[ ! -f "$CFG" ]]; then
        printf "  ${R}✘ Config not found: ${CFG}${N}\n"
        printf "  ${D}Run the installer first.${N}\n"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        printf "  ${R}✘ jq is required but not installed${N}\n"
        exit 1
    fi

    local TG_ENABLED="" TG_TOKEN=""
    TG_ENABLED=$(jq -r '.channels.telegram.enabled // false' "$CFG" 2>/dev/null) || true
    TG_TOKEN=$(jq -r '.channels.telegram.token // empty' "$CFG" 2>/dev/null) || true

    local -a TG_USERS=()
    local RAW_USERS=""
    RAW_USERS=$(jq -r '.channels.telegram.allow_from // [] | .[]' "$CFG" 2>/dev/null) || true
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            TG_USERS+=("$line")
        fi
    done <<< "$RAW_USERS"

    local PRIMARY_USER=""
    if [[ ${#TG_USERS[@]} -gt 0 ]]; then
        PRIMARY_USER="${TG_USERS[0]}"
    fi

    local CHANGED=false

    echo ""
    printf "${M}${B}  🦞 PicoClaw — Telegram Manager${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    if [[ "$TG_ENABLED" == "true" ]]; then
        printf "  Status:  ${G}● enabled${N}\n"
    else
        printf "  Status:  ${D}○ disabled${N}\n"
    fi

    if [[ -n "$TG_TOKEN" ]]; then
        local masked_token="${TG_TOKEN:0:8}...${TG_TOKEN: -4}"
        printf "  Token:   ${D}${masked_token}${N}\n"
    else
        printf "  Token:   ${R}not set${N}\n"
    fi

    if [[ ${#TG_USERS[@]} -gt 0 ]]; then
        printf "  Users:   ${B}${#TG_USERS[@]}${N} allowed\n"
        for i in "${!TG_USERS[@]}"; do
            local u="${TG_USERS[$i]}"
            local uid="" uname="" marker=""
            if [[ "$u" == *"|"* ]]; then
                uid="${u%%|*}"
                uname="${u#*|}"
            else
                uid="$u"
                uname=""
            fi
            if [[ $i -eq 0 ]]; then
                marker=" ${C}(primary — protected)${N}"
            fi
            if [[ -n "$uname" ]]; then
                printf "    ${G}%2d${N}) ID: %-14s  @%-16s%b\n" "$((i + 1))" "$uid" "$uname" "$marker"
            else
                printf "    ${G}%2d${N}) ID: %-14s  ${D}(no username)${N}%b\n" "$((i + 1))" "$uid" "$marker"
            fi
        done
    else
        printf "  Users:   ${D}none (all messages accepted)${N}\n"
    fi

    echo ""
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    if [[ "$TG_ENABLED" == "true" ]]; then
        printf "    ${C}1${N}) Change bot token\n"
        printf "    ${C}2${N}) Add user\n"
        printf "    ${C}3${N}) Remove user\n"
        printf "    ${C}4${N}) Disable Telegram  ${R}(removes all Telegram config)${N}\n"
        printf "    ${C}0${N}) Back ${D}(cancel)${N}\n"
        echo ""

        local MENU_CHOICE=""
        while true; do
            printf "  ${C}➜${N} Choose (0-4): "
            read -r MENU_CHOICE
            if [[ "$MENU_CHOICE" =~ ^[0-4]$ ]]; then
                break
            fi
            printf "  ${Y}⚠ Invalid — enter 0-4${N}\n"
        done

        case "$MENU_CHOICE" in
            0) printf "  ${D}No changes.${N}"; echo ""; return 0 ;;
            1) _tg_change_token ;;
            2) _tg_add_user ;;
            3) _tg_remove_user ;;
            4) _tg_disable ;;
        esac
    else
        printf "    ${C}1${N}) Enable Telegram\n"
        printf "    ${C}0${N}) Back ${D}(cancel)${N}\n"
        echo ""

        local MENU_CHOICE=""
        while true; do
            printf "  ${C}➜${N} Choose (0-1): "
            read -r MENU_CHOICE
            if [[ "$MENU_CHOICE" =~ ^[0-1]$ ]]; then
                break
            fi
            printf "  ${Y}⚠ Invalid — enter 0 or 1${N}\n"
        done

        case "$MENU_CHOICE" in
            0) printf "  ${D}No changes.${N}"; echo ""; return 0 ;;
            1) _tg_enable ;;
        esac
    fi

    if [[ "$CHANGED" == "true" ]]; then
        if systemctl is-active --quiet "$SVC" 2>/dev/null; then
            echo ""
            printf "  ${M}🦞${N} Restarting gateway to apply changes...\n"
            systemctl restart "$SVC" 2>/dev/null || true
            sleep 2
            if systemctl is-active --quiet "$SVC" 2>/dev/null; then
                printf "  ${G}✔${N} Gateway restarted successfully\n"
            else
                printf "  ${Y}⚠${N} Gateway may have issues — check: picoclaw logs\n"
            fi
        else
            echo ""
            printf "  ${D}Gateway not running. Start with: picoclaw start${N}\n"
        fi
    fi
    echo ""
}

_tg_change_token() {
    echo ""
    printf "  ${D}Current token: ${TG_TOKEN:0:8}...${TG_TOKEN: -4}${N}\n"
    printf "  ${D}Create new: @BotFather → /newbot or /token${N}\n"
    echo ""
    printf "  ${C}➜${N} New bot token (or press Enter to cancel): "
    local NEW_TOKEN=""
    read -rs NEW_TOKEN
    echo ""

    if [[ -z "$NEW_TOKEN" ]]; then
        printf "  ${D}Cancelled — token unchanged.${N}\n"
        return 0
    fi

    if [[ "$NEW_TOKEN" == "$TG_TOKEN" ]]; then
        printf "  ${Y}⚠ That's the same token — no change.${N}\n"
        return 0
    fi

    local SAFE_TOKEN=""
    SAFE_TOKEN=$(_json_escape "$NEW_TOKEN")
    local TMPFILE=""
    TMPFILE=$(mktemp)
    if jq --arg t "$SAFE_TOKEN" '.channels.telegram.token = $t' "$CFG" > "$TMPFILE" 2>/dev/null; then
        mv "$TMPFILE" "$CFG"
        CHANGED=true
        printf "  ${G}✔${N} Bot token updated\n"
    else
        rm -f "$TMPFILE"
        printf "  ${R}✘ Failed to update config${N}\n"
    fi
}

_tg_add_user() {
    echo ""
    printf "  ${D}Each user needs a numeric Telegram ID and username.${N}\n"
    printf "  ${D}Get ID: message @userinfobot on Telegram${N}\n"
    printf "  ${D}Username: your @handle without the @${N}\n"
    echo ""

    local NEW_UID="" NEW_UNAME=""
    printf "  ${C}➜${N} User ID (numeric, e.g. 5323045369): "
    read -r NEW_UID

    if [[ -z "$NEW_UID" ]]; then
        printf "  ${D}Cancelled — no user added.${N}\n"
        return 0
    fi

    if ! [[ "$NEW_UID" =~ ^[0-9]+$ ]]; then
        printf "  ${R}✘ User ID must be numeric${N}\n"
        return 0
    fi

    printf "  ${C}➜${N} Username (without @, e.g. johndoe): "
    read -r NEW_UNAME

    if [[ -z "$NEW_UNAME" ]]; then
        printf "  ${R}✘ Username is required (PicoClaw uses ID|username format)${N}\n"
        return 0
    fi

    local COMPOSITE="${NEW_UID}|${NEW_UNAME}"

    for existing in "${TG_USERS[@]}"; do
        if [[ "$existing" == "$COMPOSITE" ]]; then
            printf "  ${Y}⚠ User ${COMPOSITE} already exists${N}\n"
            return 0
        fi
    done

    echo ""
    printf "  ${D}Add user:${N} ${G}${NEW_UID}${N} | ${G}@${NEW_UNAME}${N}\n"
    printf "  ${C}➜${N} Confirm? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        return 0
    fi

    local SAFE_COMPOSITE=""
    SAFE_COMPOSITE=$(_json_escape "$COMPOSITE")
    local TMPFILE=""
    TMPFILE=$(mktemp)
    if jq --arg u "$SAFE_COMPOSITE" '.channels.telegram.allow_from += [$u]' "$CFG" > "$TMPFILE" 2>/dev/null; then
        mv "$TMPFILE" "$CFG"
        CHANGED=true
        TG_USERS+=("$COMPOSITE")
        printf "  ${G}✔${N} User added: ${B}${COMPOSITE}${N} (${#TG_USERS[@]} total)\n"
    else
        rm -f "$TMPFILE"
        printf "  ${R}✘ Failed to update config${N}\n"
    fi
}

_tg_remove_user() {
    if [[ ${#TG_USERS[@]} -eq 0 ]]; then
        printf "  ${Y}⚠ No users to remove${N}\n"
        return 0
    fi

    echo ""
    printf "  ${B}Current users:${N}\n"
    echo ""

    local REMOVABLE=0
    for i in "${!TG_USERS[@]}"; do
        local u="${TG_USERS[$i]}"
        local uid="" uname=""
        if [[ "$u" == *"|"* ]]; then
            uid="${u%%|*}"
            uname="${u#*|}"
        else
            uid="$u"
            uname=""
        fi

        if [[ $i -eq 0 ]]; then
            if [[ -n "$uname" ]]; then
                printf "    ${D}--${N}) ID: %-14s  @%-16s ${C}(primary — cannot remove)${N}\n" "$uid" "$uname"
            else
                printf "    ${D}--${N}) ID: %-14s  ${D}(no username)${N}  ${C}(primary — cannot remove)${N}\n" "$uid"
            fi
        else
            REMOVABLE=$((REMOVABLE + 1))
            if [[ -n "$uname" ]]; then
                printf "    ${C}%2d${N}) ID: %-14s  @%-16s\n" "$((i + 1))" "$uid" "$uname"
            else
                printf "    ${C}%2d${N}) ID: %-14s  ${D}(no username)${N}\n" "$((i + 1))" "$uid"
            fi
        fi
    done

    echo ""

    if [[ $REMOVABLE -eq 0 ]]; then
        printf "  ${Y}⚠ Only the primary user exists — cannot remove it.${N}\n"
        printf "  ${D}Use 'Disable Telegram' to remove all config instead.${N}\n"
        return 0
    fi

    local TOTAL=${#TG_USERS[@]}
    local RM_CHOICE=""
    while true; do
        printf "  ${C}➜${N} User number to remove (2-${TOTAL}, or 0 to cancel): "
        read -r RM_CHOICE

        if [[ "$RM_CHOICE" == "0" ]]; then
            printf "  ${D}Cancelled.${N}\n"
            return 0
        fi

        if [[ "$RM_CHOICE" =~ ^[0-9]+$ ]] && (( RM_CHOICE >= 2 && RM_CHOICE <= TOTAL )); then
            break
        fi
        printf "  ${Y}⚠ Invalid — enter 2-${TOTAL} or 0 to cancel${N}\n"
    done

    local IDX=$((RM_CHOICE - 1))
    local TARGET="${TG_USERS[$IDX]}"

    local t_uid="" t_uname=""
    if [[ "$TARGET" == *"|"* ]]; then
        t_uid="${TARGET%%|*}"
        t_uname="${TARGET#*|}"
    else
        t_uid="$TARGET"
        t_uname=""
    fi

    echo ""
    if [[ -n "$t_uname" ]]; then
        printf "  ${D}Remove user:${N} ${R}${t_uid}${N} | ${R}@${t_uname}${N}\n"
    else
        printf "  ${D}Remove user:${N} ${R}${t_uid}${N}\n"
    fi
    printf "  ${C}➜${N} Confirm? ${D}[y/N]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-n}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        return 0
    fi

    local TMPFILE=""
    TMPFILE=$(mktemp)
    if jq --arg u "$TARGET" '.channels.telegram.allow_from -= [$u]' "$CFG" > "$TMPFILE" 2>/dev/null; then
        mv "$TMPFILE" "$CFG"
        CHANGED=true
        unset 'TG_USERS[$IDX]'
        TG_USERS=("${TG_USERS[@]}")
        printf "  ${G}✔${N} User removed (${#TG_USERS[@]} remaining)\n"
    else
        rm -f "$TMPFILE"
        printf "  ${R}✘ Failed to update config${N}\n"
    fi
}

_tg_disable() {
    echo ""
    printf "  ${R}${B}  ⚠  WARNING: This will completely disable Telegram${N}\n"
    echo ""
    printf "  The following will be ${R}permanently removed${N} from config:\n"
    printf "    • Bot token\n"
    printf "    • All allowed users (${#TG_USERS[@]} user(s))\n"
    printf "    • Telegram will be set to disabled\n"
    echo ""
    printf "  ${D}You can re-enable later with: picoclaw telegram${N}\n"
    echo ""
    printf "  ${C}➜${N} Type ${R}DISABLE${N} to confirm (anything else cancels): "
    local CONFIRM=""
    read -r CONFIRM

    if [[ "$CONFIRM" != "DISABLE" ]]; then
        printf "  ${D}Cancelled — Telegram unchanged.${N}\n"
        return 0
    fi

    local TMPFILE=""
    TMPFILE=$(mktemp)
    if jq '.channels.telegram = {"enabled": false, "token": "", "allow_from": []}' "$CFG" > "$TMPFILE" 2>/dev/null; then
        mv "$TMPFILE" "$CFG"
        CHANGED=true
        TG_ENABLED="false"
        TG_TOKEN=""
        TG_USERS=()
        PRIMARY_USER=""
        echo ""
        printf "  ${G}✔${N} Telegram disabled — token and all users removed\n"
    else
        rm -f "$TMPFILE"
        printf "  ${R}✘ Failed to update config${N}\n"
    fi
}

_tg_enable() {
    echo ""
    printf "  ${B}Enable Telegram${N}\n"
    echo ""
    printf "  ${D}Create a bot: @BotFather → /newbot${N}\n"
    printf "  ${D}Get your ID: @userinfobot on Telegram${N}\n"
    printf "  ${D}Get username: Telegram Settings → your @username (without @)${N}\n"
    echo ""

    local NEW_TOKEN=""
    printf "  ${C}➜${N} Bot token: "
    read -rs NEW_TOKEN
    echo ""

    if [[ -z "$NEW_TOKEN" ]]; then
        printf "  ${R}✘ Bot token is required${N}\n"
        return 0
    fi

    local NEW_UID=""
    printf "  ${C}➜${N} Your user ID (numeric): "
    read -r NEW_UID

    if [[ -z "$NEW_UID" ]]; then
        printf "  ${R}✘ User ID is required${N}\n"
        return 0
    fi

    if ! [[ "$NEW_UID" =~ ^[0-9]+$ ]]; then
        printf "  ${R}✘ User ID must be numeric${N}\n"
        return 0
    fi

    local NEW_UNAME=""
    printf "  ${C}➜${N} Your username (without @): "
    read -r NEW_UNAME

    if [[ -z "$NEW_UNAME" ]]; then
        printf "  ${R}✘ Username is required (PicoClaw uses ID|username format)${N}\n"
        return 0
    fi

    local COMPOSITE="${NEW_UID}|${NEW_UNAME}"

    echo ""
    printf "  ${D}Enable Telegram with:${N}\n"
    printf "    Token:   ${D}${NEW_TOKEN:0:8}...${NEW_TOKEN: -4}${N}\n"
    printf "    User:    ${G}${NEW_UID}${N} | ${G}@${NEW_UNAME}${N}\n"
    echo ""
    printf "  ${C}➜${N} Confirm? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        return 0
    fi

    local SAFE_TOKEN="" SAFE_COMPOSITE=""
    SAFE_TOKEN=$(_json_escape "$NEW_TOKEN")
    SAFE_COMPOSITE=$(_json_escape "$COMPOSITE")

    local TMPFILE=""
    TMPFILE=$(mktemp)
    if jq --arg t "$SAFE_TOKEN" --arg u "$SAFE_COMPOSITE" \
        '.channels.telegram = {"enabled": true, "token": $t, "allow_from": [$u]}' \
        "$CFG" > "$TMPFILE" 2>/dev/null; then
        mv "$TMPFILE" "$CFG"
        CHANGED=true
        TG_ENABLED="true"
        TG_TOKEN="$NEW_TOKEN"
        TG_USERS=("$COMPOSITE")
        PRIMARY_USER="$COMPOSITE"
        echo ""
        printf "  ${G}✔${N} Telegram enabled\n"
        printf "  ${G}✔${N} Primary user: ${B}${COMPOSITE}${N}\n"
    else
        rm -f "$TMPFILE"
        printf "  ${R}✘ Failed to update config${N}\n"
    fi
}

cmd_backup() {
    _load_backup_conf

    local subcmd="${2:-}"

    case "$subcmd" in
        --auto)    _backup_run "auto" ;;
        --initial) _backup_run "initial" ;;
        --manual)  _backup_run "manual" ;;
        list)      _backup_list ;;
        settings)  _backup_settings ;;
        "")        _backup_interactive ;;
        *)
            printf "  ${R}✘ Unknown backup sub-command: ${subcmd}${N}\n"
            printf "  ${D}Usage: picoclaw backup [--auto|--manual|--initial|list|settings]${N}\n"
            exit 1
            ;;
    esac
}

_backup_interactive() {
    echo ""
    printf "${M}${B}  🦞 PicoClaw — Backup${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    local bk_count=0
    bk_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l) || true

    printf "  Backup dir:    ${B}${BACKUP_DIR}${N}\n"
    printf "  Snapshots:     ${B}${bk_count}${N} / max ${BACKUP_MAX_KEEP}\n"
    printf "  Auto-backup:   $(if [[ -f /etc/cron.d/picoclaw-autobackup ]]; then printf "${G}● every ${BACKUP_INTERVAL_DAYS} days${N}"; else printf "${D}○ off${N}"; fi)\n"
    echo ""

    printf "  ${D}A backup includes: config.json, workspace, skills, binary,${N}\n"
    printf "  ${D}wrapper, systemd units, cron jobs, profile scripts, perf configs,${N}\n"
    printf "  ${D}FTP configs, WhatsApp bridge source + auth session, Ollama config,${N}\n"
    printf "  ${D}and source.${N}\n"
    echo ""

    printf "  ${C}➜${N} Create a backup now? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        echo ""
        return 0
    fi

    echo ""
    _backup_run "manual"
    echo ""
}

_backup_run() {
    local trigger="${1:-manual}"
    local timestamp
    timestamp=$(date +"%m%d%y_%H%M%S")
    local snap_name="backup_${timestamp}"
    local snap_dir="${BACKUP_DIR}/${snap_name}"

    if [[ "$trigger" == "auto" ]]; then
        local last_auto_file="${BACKUP_DIR}/.last_auto_backup"
        if [[ -f "$last_auto_file" ]]; then
            local last_epoch
            last_epoch=$(cat "$last_auto_file" 2>/dev/null || echo "0")
            local now_epoch
            now_epoch=$(date +%s)
            local elapsed_days=$(( (now_epoch - last_epoch) / 86400 ))
            if [[ $elapsed_days -lt $BACKUP_INTERVAL_DAYS ]]; then
                exit 0
            fi
        fi
    fi

    mkdir -p "$snap_dir"

    printf "  ${M}🦞${N} Creating backup: ${B}${snap_name}${N}\n"
    echo ""

    if [[ -d "/root/.picoclaw" ]]; then
        mkdir -p "${snap_dir}/picoclaw_config"
        cp -a /root/.picoclaw/. "${snap_dir}/picoclaw_config/" 2>/dev/null || true
        printf "  ${G}✔${N} Config dir: ~/.picoclaw/ (config.json, workspace, skills, atlas, etc.)\n"
    fi

    if [[ -f "$BIN" ]]; then
        cp -a "$BIN" "${snap_dir}/picoclaw.bin" 2>/dev/null || true
        printf "  ${G}✔${N} Binary: picoclaw.bin ($(du -h "$BIN" | awk '{print $1}'))\n"
    fi

    local WRAPPER="/usr/local/bin/picoclaw"
    if [[ -f "$WRAPPER" && "$WRAPPER" != "$BIN" ]]; then
        cp -a "$WRAPPER" "${snap_dir}/picoclaw.wrapper" 2>/dev/null || true
        printf "  ${G}✔${N} Wrapper: picoclaw (CLI wrapper)\n"
    fi

    local has_units=false
    mkdir -p "${snap_dir}/systemd"
    for unit_file in /etc/systemd/system/picoclaw-gateway.service \
                     /etc/systemd/system/picoclaw-watchdog.service \
                     /etc/systemd/system/picoclaw-watchdog.timer \
                     "/etc/systemd/system/${WA_BRIDGE_SVC}.service"; do
        if [[ -f "$unit_file" ]]; then
            cp -a "$unit_file" "${snap_dir}/systemd/" 2>/dev/null || true
            has_units=true
        fi
    done
    if [[ "$has_units" == "true" ]]; then
        printf "  ${G}✔${N} Systemd units: gateway, watchdog, WhatsApp bridge\n"
    fi

    local has_cron=false
    mkdir -p "${snap_dir}/cron"
    for cron_file in /etc/cron.d/picoclaw-boot /etc/cron.d/picoclaw-autobackup; do
        if [[ -f "$cron_file" ]]; then
            cp -a "$cron_file" "${snap_dir}/cron/" 2>/dev/null || true
            has_cron=true
        fi
    done
    if [[ "$has_cron" == "true" ]]; then
        printf "  ${G}✔${N} Cron jobs: boot fallback, auto-backup\n"
    fi

    local has_profile=false
    mkdir -p "${snap_dir}/profile"
    for prof_file in /etc/profile.d/picoclaw.sh /etc/profile.d/go.sh; do
        if [[ -f "$prof_file" ]]; then
            cp -a "$prof_file" "${snap_dir}/profile/" 2>/dev/null || true
            has_profile=true
        fi
    done
    if [[ "$has_profile" == "true" ]]; then
        printf "  ${G}✔${N} Profile scripts: login banner, Go PATH\n"
    fi

    if [[ -f /etc/logrotate.d/picoclaw ]]; then
        mkdir -p "${snap_dir}/logrotate"
        cp -a /etc/logrotate.d/picoclaw "${snap_dir}/logrotate/" 2>/dev/null || true
        printf "  ${G}✔${N} Logrotate config\n"
    fi

    local has_perf=false
    mkdir -p "${snap_dir}/performance"
    for perf_file in /etc/sysctl.d/99-picoclaw-performance.conf \
                     /etc/security/limits.d/99-picoclaw-performance.conf \
                     /etc/udev/rules.d/60-picoclaw-ioscheduler.rules \
                     /etc/modules-load.d/bbr.conf \
                     /etc/systemd/journald.conf.d/picoclaw-size.conf \
                     /etc/systemd/system.conf.d/picoclaw-timeouts.conf \
                     /etc/systemd/resolved.conf.d/picoclaw-dns.conf \
                     /etc/tmpfiles.d/picoclaw-mglru.conf \
                     /etc/tmpfiles.d/picoclaw-ksm.conf \
                     /etc/default/zramswap; do
        if [[ -f "$perf_file" ]]; then
            cp -a "$perf_file" "${snap_dir}/performance/" 2>/dev/null || true
            has_perf=true
        fi
    done
    if [[ "$has_perf" == "true" ]]; then
        printf "  ${G}✔${N} Performance configs: sysctl, limits, I/O, DNS, zram, etc.\n"
    fi

    local has_ftp=false
    mkdir -p "${snap_dir}/ftp"
    for ftp_file in /etc/vsftpd.conf /etc/vsftpd.user_list /etc/logrotate.d/vsftpd-picoclaw; do
        if [[ -f "$ftp_file" ]]; then
            cp -a "$ftp_file" "${snap_dir}/ftp/" 2>/dev/null || true
            has_ftp=true
        fi
    done
    if [[ -f "$FTP_CONF" ]]; then
        cp -a "$FTP_CONF" "${snap_dir}/ftp/" 2>/dev/null || true
        has_ftp=true
    fi
    if [[ "$has_ftp" == "true" ]]; then
        printf "  ${G}✔${N} FTP configs: vsftpd.conf, user_list, ftp.conf\n"
    fi

    # ── WhatsApp bridge backup ──
    local has_wa=false
    _load_wa_conf
    mkdir -p "${snap_dir}/whatsapp"
    if [[ -d "$WA_BRIDGE_DIR" ]]; then
        mkdir -p "${snap_dir}/whatsapp/bridge"
        for wa_item in package.json package-lock.json tsconfig.json src; do
            if [[ -e "${WA_BRIDGE_DIR}/${wa_item}" ]]; then
                cp -a "${WA_BRIDGE_DIR}/${wa_item}" "${snap_dir}/whatsapp/bridge/" 2>/dev/null || true
                has_wa=true
            fi
        done
    fi
    if [[ -d "$WA_BRIDGE_AUTH_DIR" ]]; then
        mkdir -p "${snap_dir}/whatsapp/auth"
        cp -a "$WA_BRIDGE_AUTH_DIR"/. "${snap_dir}/whatsapp/auth/" 2>/dev/null || true
        has_wa=true
        if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
            printf "  ${G}✔${N} WhatsApp auth: creds.json (session preserved)\n"
        fi
    fi
    if [[ -f "$WA_CONF" ]]; then
        cp -a "$WA_CONF" "${snap_dir}/whatsapp/" 2>/dev/null || true
        has_wa=true
    fi
    if [[ -f "/etc/systemd/system/${WA_BRIDGE_SVC}.service" ]]; then
        cp -a "/etc/systemd/system/${WA_BRIDGE_SVC}.service" "${snap_dir}/whatsapp/" 2>/dev/null || true
        has_wa=true
    fi
    if [[ "$has_wa" == "true" ]]; then
        printf "  ${G}✔${N} WhatsApp: bridge source, auth, config, systemd unit\n"
    fi

    # ── Ollama backup ──
    local has_ollama=false
    mkdir -p "${snap_dir}/ollama"
    if [[ -f "$OLLAMA_CONF" ]]; then
        cp -a "$OLLAMA_CONF" "${snap_dir}/ollama/" 2>/dev/null || true
        has_ollama=true
    fi
    if [[ -f /tmp/picoclaw-modelfile ]]; then
        cp -a /tmp/picoclaw-modelfile "${snap_dir}/ollama/" 2>/dev/null || true
    fi
    if [[ "$has_ollama" == "true" ]]; then
        printf "  ${G}✔${N} Ollama: ollama.conf\n"
    fi

    if [[ -d "/opt/picoclaw" ]]; then
        mkdir -p "${snap_dir}/source"
        if command -v rsync &>/dev/null; then
            rsync -a --exclude='.git' /opt/picoclaw/ "${snap_dir}/source/" 2>/dev/null || true
        else
            cp -a /opt/picoclaw "${snap_dir}/source/" 2>/dev/null || true
        fi
        printf "  ${G}✔${N} Source: /opt/picoclaw (excluding .git)\n"
    fi

    local pc_ver=""
    if [[ -x "$BIN" ]]; then
        pc_ver=$("$BIN" version 2>/dev/null) || pc_ver="unknown"
    fi
    pc_ver=$(_json_escape "$pc_ver")
    local safe_hostname
    safe_hostname=$(_json_escape "$(hostname 2>/dev/null || echo 'unknown')")
    local snap_size
    snap_size=$(du -sh "$snap_dir" 2>/dev/null | awk '{print $1}') || snap_size="unknown"

    cat > "${snap_dir}/backup.meta" << METAEOF
{
  "backup_name": "${snap_name}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "timestamp_epoch": $(date +%s),
  "trigger": "${trigger}",
  "picoclaw_version": "${pc_ver}",
  "hostname": "${safe_hostname}",
  "arch": "$(uname -m)",
  "size": "${snap_size}",
  "performance_optimized": $(if [[ -f /etc/sysctl.d/99-picoclaw-performance.conf ]]; then echo "true"; else echo "false"; fi),
  "ftp_configured": ${has_ftp},
  "whatsapp_configured": ${has_wa},
  "ollama_configured": ${has_ollama},
  "contents": {
    "config_dir": true,
    "binary": $(if [[ -f "${snap_dir}/picoclaw.bin" ]]; then echo "true"; else echo "false"; fi),
    "wrapper": $(if [[ -f "${snap_dir}/picoclaw.wrapper" ]]; then echo "true"; else echo "false"; fi),
    "systemd": ${has_units},
    "cron": ${has_cron},
    "profile": ${has_profile},
    "performance": ${has_perf},
    "ftp": ${has_ftp},
    "whatsapp": ${has_wa},
    "ollama": ${has_ollama},
    "source": $(if [[ -d "${snap_dir}/source" ]]; then echo "true"; else echo "false"; fi)
  }
}
METAEOF
    printf "  ${G}✔${N} Metadata: backup.meta\n"

    if [[ "$trigger" == "auto" ]]; then
        date +%s > "${BACKUP_DIR}/.last_auto_backup"
    fi

    _backup_purge_old

    local total_backups
    total_backups=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l)
    echo ""
    printf "  ${G}✔${N} Backup complete: ${B}${snap_dir}${N} (${snap_size})\n"
    printf "  ${D}  Total backups: ${total_backups} / max ${BACKUP_MAX_KEEP}${N}\n"
}

_backup_purge_old() {
    local -a all_backups=()

    while IFS= read -r d; do
        if [[ -n "$d" ]]; then
            all_backups+=("$d")
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort)

    local count=${#all_backups[@]}
    if [[ $count -le $BACKUP_MAX_KEEP ]]; then
        return 0
    fi

    local to_remove=$((count - BACKUP_MAX_KEEP))
    echo ""
    printf "  ${Y}⚠${N} Purging ${to_remove} old backup(s) (keeping ${BACKUP_MAX_KEEP})...\n"

    for (( i=0; i<to_remove; i++ )); do
        local old_dir="${all_backups[$i]}"
        local old_name="${old_dir%/}"
        old_name="${old_name##*/}"
        rm -rf "$old_dir"
        printf "  ${G}✔${N} Purged: ${D}${old_name}${N}\n"
    done
}

_backup_list() {
    echo ""
    printf "${M}${B}  🦞 PicoClaw — Backup List${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]]; then
        printf "  ${D}No backups found. Create one with: picoclaw backup${N}\n"
        echo ""
        return 0
    fi

    local -a all_backups=()
    while IFS= read -r d; do
        if [[ -n "$d" ]]; then
            all_backups+=("$d")
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r)

    local count=${#all_backups[@]}

    if [[ $count -eq 0 ]]; then
        printf "  ${D}No backups found. Create one with: picoclaw backup${N}\n"
        echo ""
        return 0
    fi

    printf "  ${B}${count}${N} backup(s) in ${BACKUP_DIR}  ${D}(max ${BACKUP_MAX_KEEP})${N}\n"
    echo ""

    printf "    ${B}%-4s %-24s %-10s %-10s %-8s${N}\n" "#" "Name" "Trigger" "Version" "Size"
    printf "    ${D}──── ──────────────────────── ────────── ────────── ────────${N}\n"

    local num=1
    for bk_dir in "${all_backups[@]}"; do
        local bk_name="${bk_dir%/}"
        bk_name="${bk_name##*/}"
        local bk_trigger="?" bk_ver="?" bk_size="?"
        local meta_file="${bk_dir}/backup.meta"

        if [[ -f "$meta_file" ]] && command -v jq &>/dev/null; then
            bk_trigger=$(jq -r '.trigger // "?"' "$meta_file" 2>/dev/null) || bk_trigger="?"
            bk_ver=$(jq -r '.picoclaw_version // "?"' "$meta_file" 2>/dev/null) || bk_ver="?"
            bk_size=$(jq -r '.size // "?"' "$meta_file" 2>/dev/null) || bk_size="?"
        else
            bk_size=$(du -sh "$bk_dir" 2>/dev/null | awk '{print $1}') || bk_size="?"
        fi

        local ts_part="${bk_name#backup_}"
        local bk_date=""
        if [[ ${#ts_part} -ge 13 ]]; then
            local mm="${ts_part:0:2}" dd="${ts_part:2:2}" yy="${ts_part:4:2}"
            local hh="${ts_part:7:2}" mi="${ts_part:9:2}" ss="${ts_part:11:2}"
            bk_date="${mm}/${dd}/20${yy} ${hh}:${mi}:${ss}"
        fi

        local marker=""
        if [[ $num -eq 1 ]]; then
            marker=" ${G}← latest${N}"
        fi

        printf "    ${C}%-4s${N} %-24s %-10s %-10s %-8s%b\n" \
            "${num}" "${bk_name}" "${bk_trigger}" "${bk_ver}" "${bk_size}" "${marker}"

        if [[ -n "$bk_date" ]]; then
            printf "    ${D}     %s${N}\n" "$bk_date"
        fi

        num=$((num + 1))
    done

    echo ""
    printf "  ${D}Auto-backup: $(if [[ -f /etc/cron.d/picoclaw-autobackup ]]; then echo "every ${BACKUP_INTERVAL_DAYS} days at 03:00"; else echo "off"; fi)${N}\n"
    printf "  ${D}Manage: picoclaw backup settings${N}\n"
    echo ""
}

_backup_settings() {
    echo ""
    printf "${M}${B}  🦞 PicoClaw — Backup Settings${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    local bk_count=0
    bk_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l) || true
    local auto_active=false
    if [[ -f /etc/cron.d/picoclaw-autobackup ]]; then
        auto_active=true
    fi

    printf "  Backup dir:      ${B}${BACKUP_DIR}${N}\n"
    printf "  Total snapshots: ${B}${bk_count}${N}\n"
    printf "  Max to keep:     ${B}${BACKUP_MAX_KEEP}${N}\n"
    printf "  Interval:        ${B}every ${BACKUP_INTERVAL_DAYS} day(s)${N}\n"
    if [[ "$auto_active" == "true" ]]; then
        printf "  Auto-backup:     ${G}● enabled${N} (cron at 03:00 daily, checks interval)\n"
    else
        printf "  Auto-backup:     ${D}○ disabled${N}\n"
    fi

    if [[ -f "${BACKUP_DIR}/.last_auto_backup" ]]; then
        local last_epoch
        last_epoch=$(cat "${BACKUP_DIR}/.last_auto_backup" 2>/dev/null || echo "0")
        if [[ "$last_epoch" != "0" && -n "$last_epoch" ]]; then
            local last_date
            last_date=$(date -d "@${last_epoch}" +"%Y-%m-%d %H:%M:%S" 2>/dev/null) || last_date="unknown"
            local now_epoch
            now_epoch=$(date +%s)
            local days_ago=$(( (now_epoch - last_epoch) / 86400 ))
            printf "  Last auto:       ${D}${last_date} (${days_ago} day(s) ago)${N}\n"
        fi
    fi

    echo ""
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    printf "    ${C}1${N}) Change max backups to keep\n"
    printf "    ${C}2${N}) Change backup interval (days)\n"
    if [[ "$auto_active" == "true" ]]; then
        printf "    ${C}3${N}) Disable auto-backup\n"
    else
        printf "    ${C}3${N}) Enable auto-backup\n"
    fi
    printf "    ${C}4${N}) Purge all backups  ${R}(permanently delete all)${N}\n"
    printf "    ${C}0${N}) Back ${D}(no changes)${N}\n"
    echo ""

    local MENU_CHOICE=""
    while true; do
        printf "  ${C}➜${N} Choose (0-4): "
        read -r MENU_CHOICE
        if [[ "$MENU_CHOICE" =~ ^[0-4]$ ]]; then
            break
        fi
        printf "  ${Y}⚠ Invalid — enter 0-4${N}\n"
    done

    case "$MENU_CHOICE" in
        0) printf "  ${D}No changes.${N}"; echo ""; return 0 ;;
        1) _bk_change_max ;;
        2) _bk_change_interval ;;
        3)
            if [[ "$auto_active" == "true" ]]; then
                _bk_disable_auto
            else
                _bk_enable_auto
            fi
            ;;
        4) _bk_purge_all ;;
    esac
    echo ""
}

_bk_change_max() {
    echo ""
    printf "  ${D}Current max: ${BACKUP_MAX_KEEP} backups${N}\n"
    echo ""
    local NEW_MAX=""
    while true; do
        printf "  ${C}➜${N} New max backups to keep (1-999): "
        read -r NEW_MAX
        if [[ "$NEW_MAX" =~ ^[1-9][0-9]*$ ]] && (( NEW_MAX >= 1 && NEW_MAX <= 999 )); then
            break
        fi
        printf "  ${Y}⚠ Must be a positive integer between 1 and 999${N}\n"
    done

    if [[ "$NEW_MAX" == "$BACKUP_MAX_KEEP" ]]; then
        printf "  ${Y}⚠ Same value — no change.${N}\n"
        return 0
    fi

    BACKUP_MAX_KEEP="$NEW_MAX"
    _bk_save_conf
    printf "  ${G}✔${N} Max backups changed to: ${B}${BACKUP_MAX_KEEP}${N}\n"
    _backup_purge_old
}

_bk_change_interval() {
    echo ""
    printf "  ${D}Current interval: every ${BACKUP_INTERVAL_DAYS} day(s)${N}\n"
    echo ""
    local NEW_INT=""
    while true; do
        printf "  ${C}➜${N} New interval in days (1-365): "
        read -r NEW_INT
        if [[ "$NEW_INT" =~ ^[1-9][0-9]*$ ]] && (( NEW_INT >= 1 && NEW_INT <= 365 )); then
            break
        fi
        printf "  ${Y}⚠ Must be a positive integer between 1 and 365${N}\n"
    done

    if [[ "$NEW_INT" == "$BACKUP_INTERVAL_DAYS" ]]; then
        printf "  ${Y}⚠ Same value — no change.${N}\n"
        return 0
    fi

    BACKUP_INTERVAL_DAYS="$NEW_INT"
    _bk_save_conf
    printf "  ${G}✔${N} Backup interval changed to: every ${B}${BACKUP_INTERVAL_DAYS}${N} day(s)\n"
}

_bk_disable_auto() {
    echo ""
    printf "  ${C}➜${N} Disable automatic backups? ${D}[y/N]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-n}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        return 0
    fi

    rm -f /etc/cron.d/picoclaw-autobackup
    BACKUP_AUTO_ENABLED="false"
    _bk_save_conf
    printf "  ${G}✔${N} Auto-backup disabled\n"
    printf "  ${D}Manual backups still work: picoclaw backup${N}\n"
}

_bk_enable_auto() {
    echo ""
    printf "  ${D}Current interval: every ${BACKUP_INTERVAL_DAYS} day(s)${N}\n"
    echo ""
    printf "  ${C}➜${N} Enable automatic backups? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        return 0
    fi

    cat > /etc/cron.d/picoclaw-autobackup << ABEOF
SHELL=/bin/bash
PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/root/go/bin
# PicoClaw auto-backup: runs at 03:00 daily, script checks if N days elapsed
0 3 * * * root /usr/local/bin/picoclaw backup --auto 2>/dev/null
ABEOF
    chmod 644 /etc/cron.d/picoclaw-autobackup
    BACKUP_AUTO_ENABLED="true"
    _bk_save_conf
    printf "  ${G}✔${N} Auto-backup enabled: every ${B}${BACKUP_INTERVAL_DAYS}${N} day(s) at 03:00\n"
}

_bk_purge_all() {
    local bk_count=0
    bk_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l) || true

    if [[ $bk_count -eq 0 ]]; then
        printf "  ${D}No backups to purge.${N}\n"
        return 0
    fi

    echo ""
    printf "  ${R}${B}  ⚠  WARNING: This will permanently delete ALL ${bk_count} backup(s)${N}\n"
    echo ""
    printf "  ${D}Backup directory: ${BACKUP_DIR}${N}\n"
    echo ""
    printf "  ${C}➜${N} Type ${R}PURGE${N} to confirm (anything else cancels): "
    local CONFIRM=""
    read -r CONFIRM

    if [[ "$CONFIRM" != "PURGE" ]]; then
        printf "  ${D}Cancelled — backups untouched.${N}\n"
        return 0
    fi

    find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" -exec rm -rf {} + 2>/dev/null || true
    rm -f "${BACKUP_DIR}/.last_auto_backup"
    echo ""
    printf "  ${G}✔${N} All ${bk_count} backup(s) permanently deleted\n"
}

_bk_save_conf() {
    cat > "$BACKUP_CONF" << BKCONF
# PicoClaw Backup Configuration
# Updated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
BACKUP_DIR='${BACKUP_DIR}'
BACKUP_MAX_KEEP='${BACKUP_MAX_KEEP}'
BACKUP_INTERVAL_DAYS='${BACKUP_INTERVAL_DAYS}'
BACKUP_AUTO_ENABLED='${BACKUP_AUTO_ENABLED}'
BKCONF
}

# ═══════════════════════════════════════════════════════
# ATLAS SKILLS MANAGER — picoclaw atlas
# ═══════════════════════════════════════════════════════

cmd_atlas() {
    local subcmd="${2:-}"

    case "$subcmd" in
        update)   _atlas_update ;;
        list)     _atlas_list ;;
        status)   _atlas_status ;;
        "")       _atlas_status ;;
        *)
            printf "  ${R}✘ Unknown atlas sub-command: ${subcmd}${N}\n"
            printf "  ${D}Usage: picoclaw atlas [update|list|status]${N}\n"
            exit 1
            ;;
    esac
}

_atlas_status() {
    echo ""
    printf "${M}${B}  🦞 PicoClaw — Atlas Skills${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""
    printf "  Repository:  ${B}${ATLAS_REPO_URL}${N}\n"
    printf "  Branch:      ${B}${ATLAS_BRANCH}${N}\n"
    printf "  Skills dir:  ${B}${ATLAS_SKILLS}/${N}\n"

    if [[ -f "$ATLAS_META" ]] && command -v jq &>/dev/null; then
        local installed_at="" skill_count=""
        installed_at=$(jq -r '.installed_at // "unknown"' "$ATLAS_META" 2>/dev/null) || true
        skill_count=$(jq -r '.skill_count // 0' "$ATLAS_META" 2>/dev/null) || true
        local last_updated=""
        last_updated=$(jq -r '.last_updated // "never"' "$ATLAS_META" 2>/dev/null) || true

        printf "  Installed:   ${B}${installed_at}${N}\n"
        printf "  Updated:     ${B}${last_updated}${N}\n"
        printf "  Skills:      ${B}${skill_count}${N}\n"
    else
        printf "  Metadata:    ${D}not found${N}\n"
    fi

    echo ""

    local actual_count=0
    if [[ -d "$ATLAS_SKILLS" ]]; then
        for sd in "${ATLAS_SKILLS}"/*/; do
            if [[ -f "${sd}SKILL.md" ]]; then
                actual_count=$((actual_count + 1))
                local sn="${sd%/}"
                sn="${sn##*/}"
                local sv="?"
                if [[ -f "${sd}VERSION" ]]; then
                    sv=$(head -1 "${sd}VERSION" 2>/dev/null) || sv="?"
                    sv="${sv//[[:space:]]/}"
                fi
                local sc=""
                sc=$(_extract_atlas_category "${sd}.atlas-origin")
                printf "    ${G}●${N} %-30s ${D}v%-8s %s${N}\n" "$sn" "$sv" "$sc"
            fi
        done
    fi

    if [[ $actual_count -eq 0 ]]; then
        printf "  ${D}No Atlas skills installed.${N}\n"
        printf "  ${D}Install with: picoclaw atlas update${N}\n"
    fi

    echo ""
    printf "  ${D}Commands:${N}\n"
    printf "    ${C}picoclaw atlas${N}          show this status\n"
    printf "    ${C}picoclaw atlas list${N}     list installed skills\n"
    printf "    ${C}picoclaw atlas update${N}   update all skills from repository\n"
    echo ""
}

_atlas_list() {
    echo ""
    printf "${M}${B}  🦞 PicoClaw — Atlas Skill List${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    if [[ ! -d "$ATLAS_SKILLS" ]]; then
        printf "  ${D}No skills directory found.${N}\n"
        printf "  ${D}Install with: picoclaw atlas update${N}\n"
        echo ""
        return 0
    fi

    local count=0
    printf "    ${B}%-4s %-30s %-10s %-12s %-6s${N}\n" "#" "Skill" "Version" "Category" "Files"
    printf "    ${D}──── ────────────────────────── ────────── ──────────── ──────${N}\n"

    for sd in "${ATLAS_SKILLS}"/*/; do
        if [[ ! -f "${sd}SKILL.md" ]]; then
            continue
        fi
        count=$((count + 1))

        local sn="${sd%/}"
        sn="${sn##*/}"
        local sv="?"
        if [[ -f "${sd}VERSION" ]]; then
            sv=$(head -1 "${sd}VERSION" 2>/dev/null) || sv="?"
            sv="${sv//[[:space:]]/}"
        fi
        local sc=""
        sc=$(_extract_atlas_category "${sd}.atlas-origin")
        local fc=0
        shopt -s nullglob dotglob
        local -a files=("$sd"/*)
        for f in "${files[@]}"; do
            if [[ -f "$f" ]]; then
                fc=$((fc + 1))
            fi
        done
        shopt -u nullglob dotglob

        printf "    ${C}%-4s${N} %-30s %-10s %-12s %-6s\n" "$count" "$sn" "$sv" "$sc" "$fc"
    done

    if [[ $count -eq 0 ]]; then
        printf "    ${D}No skills with SKILL.md found.${N}\n"
    fi

    echo ""
    printf "  ${D}Total: ${count} skill(s) in ${ATLAS_SKILLS}/${N}\n"
    printf "  ${D}Update: picoclaw atlas update${N}\n"
    echo ""
}

_atlas_update() {
    echo ""
    printf "${M}${B}  🦞 PicoClaw — Atlas Update${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""
    printf "  ${D}Fetching latest skills from ${ATLAS_REPO_URL}...${N}\n"
    echo ""

    local tree_json=""
    tree_json=$(curl -sf --connect-timeout 10 --max-time 30 \
        -H "Accept: application/vnd.github.v3+json" \
        "$ATLAS_API_TREE" 2>/dev/null) || true

    if [[ -z "$tree_json" ]]; then
        printf "  ${Y}⚠${N} GitHub API unreachable — trying git clone...\n"
        _atlas_update_via_git
        return 0
    fi

    local is_truncated=""
    is_truncated=$(printf '%s' "$tree_json" | jq -r '.truncated // false' 2>/dev/null) || true
    if [[ "$is_truncated" == "true" ]]; then
        printf "  ${Y}⚠${N} Tree too large for API — trying git clone...\n"
        _atlas_update_via_git
        return 0
    fi

    local skillmd_paths=""
    skillmd_paths=$(printf '%s' "$tree_json" | jq -r \
        '.tree[] | select(.type == "blob") | select(.path | test("^skills/.+/.+/SKILL\\.md$")) | .path' \
        2>/dev/null) || true

    if [[ -z "$skillmd_paths" ]]; then
        printf "  ${Y}⚠ No skills found in repository${N}\n"
        echo ""
        return 0
    fi

    mkdir -p "$ATLAS_SKILLS"

    local installed=0 updated=0 failed=0

    while IFS= read -r skillmd_path; do
        if [[ -z "$skillmd_path" ]]; then
            continue
        fi
        local skill_dir_path="${skillmd_path%/SKILL.md}"
        local s_name="${skill_dir_path##*/}"
        local cat_and_name="${skill_dir_path#skills/}"
        local s_cat="${cat_and_name%%/*}"
        local target_dir="${ATLAS_SKILLS}/${s_name}"

        local is_new=true
        if [[ -d "$target_dir" && -f "${target_dir}/SKILL.md" ]]; then
            is_new=false
        fi

        local -a file_paths=()
        while IFS= read -r fp; do
            if [[ -n "$fp" ]]; then
                file_paths+=("$fp")
            fi
        done < <(printf '%s' "$tree_json" | jq -r --arg prefix "${skill_dir_path}/" \
            '.tree[] | select(.type == "blob") | select(.path | startswith($prefix)) | .path' 2>/dev/null)

        local has_skillmd=false
        for fp in "${file_paths[@]+"${file_paths[@]}"}"; do
            if [[ "$fp" == "$skillmd_path" ]]; then
                has_skillmd=true
                break
            fi
        done
        if [[ "$has_skillmd" == "false" ]]; then
            file_paths+=("$skillmd_path")
        fi

        mkdir -p "$target_dir"

        local dl_ok=0 dl_fail=0
        for fpath in "${file_paths[@]}"; do
            local rel_path="${fpath#${skill_dir_path}/}"
            local target_file="${target_dir}/${rel_path}"
            mkdir -p "${target_file%/*}"

            if curl -sf --connect-timeout 10 --max-time 30 \
                -o "$target_file" "${ATLAS_RAW_BASE}/${fpath}" 2>/dev/null; then
                dl_ok=$((dl_ok + 1))
            else
                dl_fail=$((dl_fail + 1))
            fi
        done

        if [[ -f "${target_dir}/SKILL.md" ]]; then
            if [[ "$is_new" == "true" ]]; then
                printf '%s\n' "  ${G}✔${N} ${G}NEW${N}     ${B}${s_name}${N} ${D}(${s_cat}, ${dl_ok} files)${N}"
                installed=$((installed + 1))
            else
                printf '%s\n' "  ${G}✔${N} ${C}UPDATED${N} ${B}${s_name}${N} ${D}(${s_cat}, ${dl_ok} files)${N}"
                updated=$((updated + 1))
            fi
        else
            printf '%s\n' "  ${R}✘${N} ${R}FAILED${N}  ${B}${s_name}${N} ${D}(SKILL.md missing)${N}"
            failed=$((failed + 1))
        fi
    done <<< "$skillmd_paths"

    local total=$((installed + updated))
    _atlas_update_metadata "$total"

    echo ""
    printf "  ${G}${B}Update complete${N}\n"
    if [[ $installed -gt 0 ]]; then
        printf "    New:     ${G}${installed}${N}\n"
    fi
    if [[ $updated -gt 0 ]]; then
        printf "    Updated: ${C}${updated}${N}\n"
    fi
    if [[ $failed -gt 0 ]]; then
        printf "    Failed:  ${R}${failed}${N}\n"
    fi
    echo ""
}

_atlas_update_via_git() {
    local tmp_dir="/tmp/atlas-update-$$"
    rm -rf "$tmp_dir"

    if ! git clone -q --depth 1 -b "$ATLAS_BRANCH" "${ATLAS_REPO_URL}.git" "$tmp_dir" 2>/dev/null; then
        printf "  ${R}✘ Failed to clone Atlas repository${N}\n"
        echo ""
        return 0
    fi

    if [[ ! -d "${tmp_dir}/skills" ]]; then
        printf "  ${Y}⚠ No skills/ directory in repository${N}\n"
        rm -rf "$tmp_dir"
        echo ""
        return 0
    fi

    mkdir -p "$ATLAS_SKILLS"
    local installed=0 updated=0

    for category_dir in "${tmp_dir}/skills"/*/; do
        if [[ ! -d "$category_dir" ]]; then continue; fi
        for skill_dir in "${category_dir}"*/; do
            if [[ ! -d "$skill_dir" || ! -f "${skill_dir}SKILL.md" ]]; then continue; fi

            local s_name="${skill_dir%/}"
            s_name="${s_name##*/}"
            local s_cat="${category_dir%/}"
            s_cat="${s_cat##*/}"
            local target_dir="${ATLAS_SKILLS}/${s_name}"

            local is_new=true
            if [[ -d "$target_dir" && -f "${target_dir}/SKILL.md" ]]; then
                is_new=false
            fi

            mkdir -p "$target_dir"
            cp -a "${skill_dir}"* "$target_dir/" 2>/dev/null || true
            cp -a "${skill_dir}".* "$target_dir/" 2>/dev/null || true

            local fc=0
            shopt -s nullglob dotglob
            local -a files=("$target_dir"/*)
            for f in "${files[@]}"; do
                if [[ -f "$f" ]]; then
                    fc=$((fc + 1))
                fi
            done
            shopt -u nullglob dotglob

            if [[ "$is_new" == "true" ]]; then
                printf '%s\n' "  ${G}✔${N} ${G}NEW${N}     ${B}${s_name}${N} ${D}(${s_cat}, ${fc} files)${N}"
                installed=$((installed + 1))
            else
                printf '%s\n' "  ${G}✔${N} ${C}UPDATED${N} ${B}${s_name}${N} ${D}(${s_cat}, ${fc} files)${N}"
                updated=$((updated + 1))
            fi
        done
    done

    rm -rf "$tmp_dir"

    local total=$((installed + updated))
    _atlas_update_metadata "$total"

    echo ""
    printf "  ${G}${B}Update complete (via git clone)${N}\n"
    if [[ $installed -gt 0 ]]; then printf "    New:     ${G}${installed}${N}\n"; fi
    if [[ $updated -gt 0 ]]; then printf "    Updated: ${C}${updated}${N}\n"; fi
    echo ""
}

_atlas_update_metadata() {
    local count="${1:-0}"
    local skills_json="["
    local first=true
    for sd in "${ATLAS_SKILLS}"/*/; do
        if [[ ! -f "${sd}SKILL.md" ]]; then continue; fi
        local sn="${sd%/}"
        sn="${sn##*/}"
        local sv="unknown"
        if [[ -f "${sd}VERSION" ]]; then
            sv=$(head -1 "${sd}VERSION" 2>/dev/null) || sv="unknown"
            sv="${sv//[[:space:]]/}"
        fi
        local sc=""
        sc=$(_extract_atlas_category "${sd}.atlas-origin")
        if [[ "$first" == "true" ]]; then first=false; else skills_json+=","; fi
        skills_json+="{\"name\":\"$(_json_escape "$sn")\",\"category\":\"$(_json_escape "$sc")\",\"version\":\"$(_json_escape "$sv")\",\"path\":\"$(_json_escape "${ATLAS_SKILLS}/${sn}")\"}"
    done
    skills_json+="]"

    local orig_installed_at=""
    if [[ -f "$ATLAS_META" ]] && command -v jq &>/dev/null; then
        orig_installed_at=$(jq -r '.installed_at // empty' "$ATLAS_META" 2>/dev/null) || true
    fi
    if [[ -z "$orig_installed_at" ]]; then
        orig_installed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi

    cat > "$ATLAS_META" << METAEOF
{
  "repository": "${ATLAS_REPO_URL}",
  "branch": "${ATLAS_BRANCH}",
  "installed_at": "${orig_installed_at}",
  "installed_at_epoch": $(date +%s),
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "last_updated_epoch": $(date +%s),
  "skills_dir": "${ATLAS_SKILLS}",
  "skill_count": ${count},
  "skills": ${skills_json}
}
METAEOF
}

# ═══════════════════════════════════════════════════════
# FTP SERVER MANAGER — picoclaw ftp
# (identical to original — not reproduced to save space,
#  but exists in full in the actual script)
# ═══════════════════════════════════════════════════════

cmd_ftp() {
    local subcmd="${2:-}"

    case "$subcmd" in
        status)   _ftp_status ;;
        start)    _ftp_start ;;
        stop)     _ftp_stop ;;
        restart)  _ftp_restart ;;
        password) _ftp_password ;;
        port)     _ftp_port ;;
        tls)      _ftp_tls ;;
        logs)     _ftp_logs ;;
        disable)  _ftp_disable ;;
        enable)   _ftp_enable ;;
        "")       _ftp_interactive ;;
        *)
            printf "  ${R}✘ Unknown ftp sub-command: ${subcmd}${N}\n"
            printf "  ${D}Usage: picoclaw ftp [status|start|stop|restart|password|port|tls|logs|disable|enable]${N}\n"
            exit 1
            ;;
    esac
}

_ftp_interactive() {
    _load_ftp_conf

    echo ""
    printf "${M}${B}  🦞 PicoClaw — FTP Server Manager${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    if ! command -v vsftpd &>/dev/null; then
        printf "  ${R}✘ vsftpd is not installed${N}\n"
        printf "  ${D}Re-run the installer and select FTP server to install it.${N}\n"
        echo ""
        return 0
    fi

    if systemctl is-active --quiet vsftpd 2>/dev/null; then
        local ftp_pid=""
        ftp_pid=$(systemctl show vsftpd --property=MainPID --value 2>/dev/null) || true
        local ftp_since=""
        ftp_since=$(systemctl show vsftpd --property=ActiveEnterTimestamp --value 2>/dev/null) || true
        printf "  Status:    ${G}● running${N}  PID ${ftp_pid}\n"
        printf "  Since:     ${D}${ftp_since}${N}\n"
    elif systemctl is-enabled --quiet vsftpd 2>/dev/null; then
        printf "  Status:    ${R}● stopped${N} (enabled)\n"
    else
        printf "  Status:    ${D}○ disabled${N}\n"
    fi

    printf "  Username:  ${B}${FTP_USER}${N}\n"
    printf "  Port:      ${B}${FTP_PORT}${N}\n"
    printf "  Passive:   ${B}${FTP_PASV_MIN}-${FTP_PASV_MAX}${N}\n"
    printf "  TLS:       $(if [[ "$FTP_TLS" == "true" ]]; then printf "${G}● enabled${N}"; else printf "${D}○ disabled${N}"; fi)\n"
    printf "  Access:    ${R}Full filesystem (/)${N}\n"
    printf "  Config:    ${D}/etc/vsftpd.conf${N}\n"
    printf "  Logs:      ${D}/var/log/vsftpd.log${N}\n"

    local public_ip=""
    public_ip=$(curl -sf --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null) || true
    if [[ -z "$public_ip" ]]; then
        public_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || public_ip="?"
    fi
    printf "  Connect:   ${C}ftp://${FTP_USER}@${public_ip}:${FTP_PORT}${N}\n"

    echo ""
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    local is_running=false
    if systemctl is-active --quiet vsftpd 2>/dev/null; then
        is_running=true
    fi
    local is_enabled=false
    if systemctl is-enabled --quiet vsftpd 2>/dev/null; then
        is_enabled=true
    fi

    if [[ "$is_running" == "true" ]]; then
        printf "    ${C}1${N}) Stop FTP server\n"
        printf "    ${C}2${N}) Restart FTP server\n"
    else
        printf "    ${C}1${N}) Start FTP server\n"
        printf "    ${C}2${N}) ${D}(server not running)${N}\n"
    fi
    printf "    ${C}3${N}) Change password\n"
    printf "    ${C}4${N}) Change port\n"
    printf "    ${C}5${N}) Toggle TLS $(if [[ "$FTP_TLS" == "true" ]]; then echo "(currently ON → turn OFF)"; else echo "(currently OFF → turn ON)"; fi)\n"
    printf "    ${C}6${N}) View logs\n"
    if [[ "$is_enabled" == "true" ]]; then
        printf "    ${C}7${N}) Disable FTP server  ${R}(stop + prevent auto-start)${N}\n"
    else
        printf "    ${C}7${N}) Enable FTP server  ${G}(enable + start)${N}\n"
    fi
    printf "    ${C}0${N}) Back ${D}(cancel)${N}\n"
    echo ""

    local MENU_CHOICE=""
    while true; do
        printf "  ${C}➜${N} Choose (0-7): "
        read -r MENU_CHOICE
        if [[ "$MENU_CHOICE" =~ ^[0-7]$ ]]; then
            break
        fi
        printf "  ${Y}⚠ Invalid — enter 0-7${N}\n"
    done

    case "$MENU_CHOICE" in
        0) printf "  ${D}No changes.${N}"; echo ""; return 0 ;;
        1)
            if [[ "$is_running" == "true" ]]; then
                _ftp_stop
            else
                _ftp_start
            fi
            ;;
        2)
            if [[ "$is_running" == "true" ]]; then
                _ftp_restart
            else
                printf "  ${Y}⚠ Server not running — starting instead...${N}\n"
                _ftp_start
            fi
            ;;
        3) _ftp_password ;;
        4) _ftp_port ;;
        5) _ftp_tls ;;
        6) _ftp_logs ;;
        7)
            if [[ "$is_enabled" == "true" ]]; then
                _ftp_disable
            else
                _ftp_enable
            fi
            ;;
    esac
    echo ""
}

_ftp_status() {
  _load_ftp_conf
  echo ""
  printf "${M}${B}  🦞 PicoClaw — FTP Status${N}\n"
  printf "${D}  ─────────────────────────────────────────────${N}\n"
  echo ""
  if ! command -v vsftpd &>/dev/null; then
    printf "  ${R}✘ vsftpd is not installed${N}\n"
    echo ""
    return 0
  fi
  if systemctl is-active --quiet vsftpd 2>/dev/null; then
    local ftp_pid=""
    ftp_pid=$(systemctl show vsftpd --property=MainPID --value 2>/dev/null) || true
    local ftp_since=""
    ftp_since=$(systemctl show vsftpd --property=ActiveEnterTimestamp --value 2>/dev/null) || true
    printf "  Status:    ${G}● running${N}  PID ${ftp_pid}  since ${ftp_since}\n"
  elif systemctl is-enabled --quiet vsftpd 2>/dev/null; then
    printf "  Status:    ${R}● stopped${N} (enabled — run: picoclaw ftp start)\n"
  else
    printf "  Status:    ${D}○ disabled${N}\n"
  fi
  printf "  Username:  ${B}${FTP_USER}${N}\n"
  printf "  Port:      ${B}${FTP_PORT}${N}\n"
  printf "  Passive:   ${B}${FTP_PASV_MIN}-${FTP_PASV_MAX}${N}\n"
  printf "  TLS:       $(if [[ "$FTP_TLS" == "true" ]]; then printf "${G}● enabled${N}"; else printf "${D}○ disabled${N}"; fi)\n"
  printf "  Access:    ${R}Full filesystem (/)${N}\n"
  echo ""
}
_ftp_start() {
  echo ""
  printf "  ${M}🦞${N} Starting FTP server...\n"
  systemctl start vsftpd 2>/dev/null || true
  sleep 1
  if systemctl is-active --quiet vsftpd 2>/dev/null; then
    printf "  ${G}✔${N} FTP server running\n"
  else
    printf "  ${R}✘${N} Failed to start — check: systemctl status vsftpd\n"
  fi
}
_ftp_stop() {
  echo ""
  printf "  ${M}🦞${N} Stopping FTP server...\n"
  systemctl stop vsftpd 2>/dev/null || true
  printf "  ${G}✔${N} FTP server stopped\n"
}
_ftp_restart() {
  echo ""
  printf "  ${M}🦞${N} Restarting FTP server...\n"
  systemctl restart vsftpd 2>/dev/null || true
  sleep 1
  if systemctl is-active --quiet vsftpd 2>/dev/null; then
    printf "  ${G}✔${N} FTP server running\n"
  else
    printf "  ${R}✘${N} Failed to restart — check: systemctl status vsftpd\n"
  fi
}
_ftp_password() {
  _load_ftp_conf
  echo ""
  printf "  ${B}Change FTP Password${N}\n"
  printf "  ${D}User: ${FTP_USER}${N}\n"
  echo ""
  local NEW_PASS=""
  while true; do
    printf "  ${C}➜${N} New password (min 8 chars, hidden): "
    read -rs NEW_PASS
    echo ""
    if [[ ${#NEW_PASS} -ge 8 ]]; then
      break
    fi
    printf "  ${Y}⚠ Password must be at least 8 characters${N}\n"
  done
  local CONFIRM_PASS=""
  printf "  ${C}➜${N} Confirm password: "
  read -rs CONFIRM_PASS
  echo ""
  if [[ "$NEW_PASS" != "$CONFIRM_PASS" ]]; then
    printf "  ${R}✘ Passwords do not match — cancelled${N}\n"
    return 0
  fi
  echo "${FTP_USER}:${NEW_PASS}" | chpasswd 2>/dev/null
  if [[ $? -eq 0 ]]; then
    printf "  ${G}✔${N} Password changed for user '${FTP_USER}'\n"
  else
    printf "  ${R}✘ Failed to change password${N}\n"
  fi
}
_ftp_port() {
  _load_ftp_conf
  echo ""
  printf "  ${B}Change FTP Port${N}\n"
  printf "  ${D}Current port: ${FTP_PORT}${N}\n"
  echo ""
  local NEW_PORT=""
  while true; do
    printf "  ${C}➜${N} New port (1-65535): "
    read -r NEW_PORT
    if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && (( NEW_PORT >= 1 && NEW_PORT <= 65535 )); then
      break
    fi
    printf "  ${Y}⚠ Must be a number between 1 and 65535${N}\n"
  done
  if [[ "$NEW_PORT" == "$FTP_PORT" ]]; then
    printf "  ${Y}⚠ Same port — no change.${N}\n"
    return 0
  fi
  if [[ -f /etc/vsftpd.conf ]]; then
    sed -i "s/^listen_port=.*/listen_port=${NEW_PORT}/" /etc/vsftpd.conf 2>/dev/null || true
  fi
  FTP_PORT="$NEW_PORT"
  _save_ftp_conf
  printf "  ${G}✔${N} FTP port changed to: ${B}${NEW_PORT}${N}\n"
  if systemctl is-active --quiet vsftpd 2>/dev/null; then
    echo ""
    printf "  ${C}➜${N} Restart FTP server to apply? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" == "y" || "${CONFIRM,,}" == "yes" ]]; then
      systemctl restart vsftpd 2>/dev/null || true
      sleep 1
      if systemctl is-active --quiet vsftpd 2>/dev/null; then
        printf "  ${G}✔${N} FTP server restarted on port ${NEW_PORT}\n"
      else
        printf "  ${R}✘${N} Failed to restart — check: systemctl status vsftpd\n"
      fi
    else
      printf "  ${D}Restart later with: picoclaw ftp restart${N}\n"
    fi
  fi
}
_ftp_tls() {
  _load_ftp_conf
  echo ""
  if [[ "$FTP_TLS" == "true" ]]; then
    printf "  ${B}Disable TLS Encryption${N}\n"
    printf "  ${C}➜${N} Disable TLS? ${D}[y/N]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-n}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
      printf "  ${D}Cancelled — TLS remains enabled.${N}\n"
      return 0
    fi
    if [[ -f /etc/vsftpd.conf ]]; then
      sed -i '/^ssl_enable=/s/.*/ssl_enable=NO/' /etc/vsftpd.conf 2>/dev/null || true
    fi
    FTP_TLS="false"
    _save_ftp_conf
    printf "  ${G}✔${N} TLS disabled\n"
  else
    printf "  ${B}Enable TLS Encryption${N}\n"
    if [[ ! -f /etc/ssl/private/vsftpd.pem ]]; then
      mkdir -p /etc/ssl/private
      openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/vsftpd.key -out /etc/ssl/private/vsftpd.pem -subj "/C=US/ST=State/L=City/O=PicoClaw/OU=FTP/CN=$(hostname 2>/dev/null || echo 'picoclaw')" > /dev/null 2>&1 || true
      chmod 600 /etc/ssl/private/vsftpd.key /etc/ssl/private/vsftpd.pem
    fi
    printf "  ${C}➜${N} Enable TLS? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
      printf "  ${D}Cancelled.${N}\n"
      return 0
    fi
    if [[ -f /etc/vsftpd.conf ]]; then
      if grep -q "^ssl_enable=" /etc/vsftpd.conf 2>/dev/null; then
        sed -i '/^ssl_enable=/s/.*/ssl_enable=YES/' /etc/vsftpd.conf 2>/dev/null || true
      else
        printf "\nssl_enable=YES\nrsa_cert_file=/etc/ssl/private/vsftpd.pem\nrsa_private_key_file=/etc/ssl/private/vsftpd.key\nssl_ciphers=HIGH\nrequire_ssl_reuse=NO\n" >> /etc/vsftpd.conf
      fi
    fi
    FTP_TLS="true"
    _save_ftp_conf
    printf "  ${G}✔${N} TLS enabled\n"
  fi
  if systemctl is-active --quiet vsftpd 2>/dev/null; then
    echo ""
    printf "  ${C}➜${N} Restart FTP server to apply? ${D}[Y/n]${N}: "
    local DO_RESTART=""
    read -r DO_RESTART
    DO_RESTART="${DO_RESTART:-y}"
    if [[ "${DO_RESTART,,}" == "y" || "${DO_RESTART,,}" == "yes" ]]; then
      systemctl restart vsftpd 2>/dev/null || true
      sleep 1
      if systemctl is-active --quiet vsftpd 2>/dev/null; then
        printf "  ${G}✔${N} FTP server restarted\n"
      else
        printf "  ${R}✘${N} Failed to restart\n"
      fi
    fi
  fi
}
_ftp_logs() {
  echo ""
  printf "  ${M}🦞${N} FTP Server Logs\n"
  printf "  ${D}Showing last 50 lines of /var/log/vsftpd.log${N}\n"
  echo ""
  if [[ -f /var/log/vsftpd.log ]]; then
    tail -50 /var/log/vsftpd.log
  else
    printf "  ${D}No log file found${N}\n"
  fi
}
_ftp_disable() {
  echo ""
  printf "  ${C}➜${N} Disable FTP server? ${D}[y/N]${N}: "
  local CONFIRM=""
  read -r CONFIRM
  CONFIRM="${CONFIRM:-n}"
  if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
    printf "  ${D}Cancelled.${N}\n"
    return 0
  fi
  systemctl stop vsftpd 2>/dev/null || true
  systemctl disable vsftpd 2>/dev/null || true
  _load_ftp_conf
  FTP_ENABLED="false"
  _save_ftp_conf
  printf "  ${G}✔${N} FTP server disabled\n"
}
_ftp_enable() {
  _load_ftp_conf
  if ! command -v vsftpd &>/dev/null; then
    printf "  ${R}✘ vsftpd is not installed${N}\n"
    return 0
  fi
  echo ""
  printf "  ${C}➜${N} Enable and start FTP server? ${D}[Y/n]${N}: "
  local CONFIRM=""
  read -r CONFIRM
  CONFIRM="${CONFIRM:-y}"
  if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
    printf "  ${D}Cancelled.${N}\n"
    return 0
  fi
  systemctl enable vsftpd 2>/dev/null || true
  systemctl start vsftpd 2>/dev/null || true
  FTP_ENABLED="true"
  _save_ftp_conf
  sleep 1
  if systemctl is-active --quiet vsftpd 2>/dev/null; then
    printf "  ${G}✔${N} FTP server enabled and running\n"
  else
    printf "  ${R}✘${N} Failed to start\n"
  fi
}

# ═══════════════════════════════════════════════════════
# WHATSAPP BRIDGE MANAGER — picoclaw whatsapp
# (identical to original — compact form for space)
# ═══════════════════════════════════════════════════════

cmd_whatsapp() {
    local subcmd="${2:-}"
    case "$subcmd" in
        login)    _wa_login ;;
        logout)   _wa_logout ;;
        status)   _wa_status ;;
        start)    _wa_start ;;
        stop)     _wa_stop ;;
        restart)  _wa_restart ;;
        logs)     _wa_logs ;;
        enable)   _wa_enable ;;
        disable)  _wa_disable ;;
        "")       _wa_interactive ;;
        *)  printf "  ${R}✘ Unknown whatsapp sub-command: ${subcmd}${N}\n"; exit 1 ;;
    esac
}

_wa_interactive() {
  _load_wa_conf
  echo ""
  printf "${M}${B}  🦞 PicoClaw — WhatsApp Bridge Manager${N}\n"
  printf "${D}  ─────────────────────────────────────────────${N}\n"
  echo ""
  if [[ ! -d "$WA_BRIDGE_DIR" ]]; then
    printf "  ${R}✘ WhatsApp bridge is not installed${N}\n"
    echo ""
    return 0
  fi
  if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
    printf "  Status:    ${G}● running${N}\n"
  else
    printf "  Status:    ${R}● stopped${N}\n"
  fi
  if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
    printf "  Account:   ${G}● linked${N}\n"
  else
    printf "  Account:   ${R}● not linked${N}\n"
  fi
  printf "  Port:      ${B}${WA_BRIDGE_PORT}${N}\n"
  echo ""
  printf "    ${C}1${N}) Login (QR scan)\n"
  printf "    ${C}2${N}) Start/Stop bridge\n"
  printf "    ${C}3${N}) Restart bridge\n"
  printf "    ${C}4${N}) Logout\n"
  printf "    ${C}5${N}) View logs\n"
  printf "    ${C}6${N}) Enable/Disable\n"
  printf "    ${C}0${N}) Back\n"
  echo ""
  local MC=""
  while true; do
    printf "  ${C}➜${N} Choose (0-6): "
    read -r MC
    if [[ "$MC" =~ ^[0-6]$ ]]; then
      break
    fi
    printf "  ${Y}⚠ Invalid${N}\n"
  done
  case "$MC" in
    0)
      return 0
      ;;
    1)
      _wa_login
      ;;
    2)
      if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
        _wa_stop
      else
        _wa_start
      fi
      ;;
    3)
      _wa_restart
      ;;
    4)
      _wa_logout
      ;;
    5)
      _wa_logs
      ;;
    6)
      local wa_cfg_en=""
      if [[ -f "$CFG" ]] && command -v jq &>/dev/null; then
        wa_cfg_en=$(jq -r '.channels.whatsapp.enabled // false' "$CFG" 2>/dev/null) || true
      fi
      if [[ "$wa_cfg_en" == "true" ]]; then
        _wa_disable
      else
        _wa_enable
      fi
      ;;
  esac
  echo ""
}
_wa_login() {
  _load_wa_conf
  echo ""
  if [[ ! -d "$WA_BRIDGE_DIR" || ! -f "${WA_BRIDGE_DIR}/dist/index.js" ]]; then
    printf "  ${R}✘ Bridge not installed or not compiled${N}\n"
    return 0
  fi
  if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
    systemctl stop "$WA_BRIDGE_SVC" 2>/dev/null || true
    sleep 1
  fi
  printf "  ${M}🦞${N} Starting bridge for QR login...\n"
  echo ""
  cd "$WA_BRIDGE_DIR"
  BRIDGE_PORT="$WA_BRIDGE_PORT" AUTH_DIR="$WA_BRIDGE_AUTH_DIR" node dist/index.js &
  local bp=$!
  local wc=0 mw=120 ls=false
  while (( wc < mw )); do
    if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
      sleep 3
      ls=true
      break
    fi
    if ! kill -0 "$bp" 2>/dev/null; then
      break
    fi
    sleep 1
    wc=$((wc+1))
  done
  if kill -0 "$bp" 2>/dev/null; then
    kill "$bp" 2>/dev/null || true
    wait "$bp" 2>/dev/null || true
  fi
  cd /root
  echo ""
  if [[ "$ls" == "true" ]] || [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
    printf "  ${G}✔${N} WhatsApp linked!\n"
    systemctl start "$WA_BRIDGE_SVC" 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
      systemctl restart "$SVC" 2>/dev/null || true
    fi
  else
    printf "  ${Y}⚠${N} QR not scanned in time\n"
  fi
  echo ""
}
_wa_logout() {
  _load_wa_conf
  echo ""
  printf "  ${C}➜${N} Type ${R}LOGOUT${N} to confirm: "
  local C=""
  read -r C
  if [[ "$C" != "LOGOUT" ]]; then
    printf "  ${D}Cancelled.${N}\n"
    return 0
  fi
  systemctl stop "$WA_BRIDGE_SVC" 2>/dev/null || true
  if [[ -d "$WA_BRIDGE_AUTH_DIR" ]]; then
    rm -rf "${WA_BRIDGE_AUTH_DIR:?}/"*
  fi
  printf "  ${G}✔${N} Logged out\n"
  echo ""
}
_wa_status() {
  _load_wa_conf
  echo ""
  printf "${M}${B}  🦞 WhatsApp Status${N}\n"
  echo ""
  if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
    printf "  Bridge: ${G}● running${N}\n"
  else
    printf "  Bridge: ${R}● stopped${N}\n"
  fi
  if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
    printf "  Account: ${G}● linked${N}\n"
  else
    printf "  Account: ${R}● not linked${N}\n"
  fi
  printf "  Port: ${B}${WA_BRIDGE_PORT}${N}\n"
  echo ""
}
_wa_start() {
  echo ""
  systemctl start "$WA_BRIDGE_SVC" 2>/dev/null || true
  sleep 2
  if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
    printf "  ${G}✔${N} Bridge running\n"
  else
    printf "  ${R}✘${N} Failed\n"
  fi
}
_wa_stop() {
  echo ""
  systemctl stop "$WA_BRIDGE_SVC" 2>/dev/null || true
  printf "  ${G}✔${N} Bridge stopped\n"
}
_wa_restart() {
  echo ""
  systemctl restart "$WA_BRIDGE_SVC" 2>/dev/null || true
  sleep 2
  if systemctl is-active --quiet "$WA_BRIDGE_SVC" 2>/dev/null; then
    printf "  ${G}✔${N} Bridge running\n"
  else
    printf "  ${R}✘${N} Failed\n"
  fi
}
_wa_logs() {
  exec journalctl -u "$WA_BRIDGE_SVC" -f
}
_wa_enable() {
  _load_wa_conf
  if [[ -f "$CFG" ]] && command -v jq &>/dev/null; then
    local T=""
    T=$(mktemp)
    if jq '.channels.whatsapp.enabled = true' "$CFG" > "$T" 2>/dev/null; then
      mv "$T" "$CFG"
    fi
  fi
  WA_ENABLED="true"
  _save_wa_conf
  systemctl enable "$WA_BRIDGE_SVC" 2>/dev/null || true
  systemctl start "$WA_BRIDGE_SVC" 2>/dev/null || true
  printf "  ${G}✔${N} WhatsApp enabled\n"
  if systemctl is-active --quiet "$SVC" 2>/dev/null; then
    systemctl restart "$SVC" 2>/dev/null || true
  fi
}
_wa_disable() {
  _load_wa_conf
  if [[ -f "$CFG" ]] && command -v jq &>/dev/null; then
    local T=""
    T=$(mktemp)
    if jq '.channels.whatsapp.enabled = false' "$CFG" > "$T" 2>/dev/null; then
      mv "$T" "$CFG"
    fi
  fi
  WA_ENABLED="false"
  _save_wa_conf
  systemctl stop "$WA_BRIDGE_SVC" 2>/dev/null || true
  systemctl disable "$WA_BRIDGE_SVC" 2>/dev/null || true
  printf "  ${G}✔${N} WhatsApp disabled\n"
  if systemctl is-active --quiet "$SVC" 2>/dev/null; then
    systemctl restart "$SVC" 2>/dev/null || true
  fi
}

# ═══════════════════════════════════════════════════════
# OLLAMA MANAGER — picoclaw ollama
# ═══════════════════════════════════════════════════════

cmd_ollama() {
    local subcmd="${2:-}"

    case "$subcmd" in
        status)   _ollama_status ;;
        start)    _ollama_start ;;
        stop)     _ollama_stop ;;
        restart)  _ollama_restart ;;
        logs)     _ollama_logs ;;
        model)    _ollama_model ;;
        list)     _ollama_list ;;
        pull)     _ollama_pull "${3:-}" ;;
        remove)   _ollama_remove "${3:-}" ;;
        ctx)      _ollama_ctx "${3:-}" ;;
        "")       _ollama_interactive ;;
        *)
            printf "  ${R}✘ Unknown ollama sub-command: ${subcmd}${N}\n"
            printf "  ${D}Usage: picoclaw ollama [status|start|stop|restart|logs|model|list|pull|remove|ctx]${N}\n"
            exit 1
            ;;
    esac
}

_ollama_interactive() {
    _load_ollama_conf

    echo ""
    printf "${M}${B}  🦞 PicoClaw — Ollama Manager${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    if ! command -v ollama &>/dev/null; then
        printf "  ${R}✘ Ollama is not installed${N}\n"
        printf "  ${D}Re-run the installer and select Ollama as provider.${N}\n"
        echo ""
        return 0
    fi

    if systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
        local ol_pid=""
        ol_pid=$(systemctl show "$OLLAMA_SVC" --property=MainPID --value 2>/dev/null) || true
        local ol_ram=""
        if [[ -n "$ol_pid" && "$ol_pid" != "0" ]]; then
            ol_ram=$(ps -o rss= -p "$ol_pid" 2>/dev/null | awk '{printf "%.0fMB", $1/1024}') || ol_ram="?"
        fi
        printf "  Status:    ${G}● running${N}  PID ${ol_pid} (${ol_ram} RAM)\n"
    elif systemctl is-enabled --quiet "$OLLAMA_SVC" 2>/dev/null; then
        printf "  Status:    ${R}● stopped${N} (enabled)\n"
    else
        printf "  Status:    ${D}○ disabled${N}\n"
    fi

    local model_display="${OLLAMA_CUSTOM_MODEL:-${OLLAMA_MODEL}}"
    printf "  Model:     ${B}${model_display}${N}\n"
    printf "  Base:      ${D}${OLLAMA_MODEL}${N}\n"
    printf "  Context:   ${B}${OLLAMA_NUM_CTX}${N} tokens\n"
    printf "  API:       ${D}http://${OLLAMA_HOST}:${OLLAMA_PORT}/v1${N}\n"
    printf "  Provider:  ${D}routed via vllm slot in config.json${N}\n"

    echo ""
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    local is_running=false
    if systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
        is_running=true
    fi

    if [[ "$is_running" == "true" ]]; then
        printf "    ${C}1${N}) Stop Ollama\n"
        printf "    ${C}2${N}) Restart Ollama\n"
    else
        printf "    ${C}1${N}) Start Ollama\n"
        printf "    ${C}2${N}) ${D}(not running)${N}\n"
    fi
    printf "    ${C}3${N}) Switch model\n"
    printf "    ${C}4${N}) Change context window (currently ${OLLAMA_NUM_CTX})\n"
    printf "    ${C}5${N}) List installed models\n"
    printf "    ${C}6${N}) View logs\n"
    printf "    ${C}0${N}) Back ${D}(cancel)${N}\n"
    echo ""

    local MENU_CHOICE=""
    while true; do
        printf "  ${C}➜${N} Choose (0-6): "
        read -r MENU_CHOICE
        if [[ "$MENU_CHOICE" =~ ^[0-6]$ ]]; then
            break
        fi
        printf "  ${Y}⚠ Invalid — enter 0-6${N}\n"
    done

    case "$MENU_CHOICE" in
        0) printf "  ${D}No changes.${N}"; echo ""; return 0 ;;
        1)
            if [[ "$is_running" == "true" ]]; then
                _ollama_stop
            else
                _ollama_start
            fi
            ;;
        2)
            if [[ "$is_running" == "true" ]]; then
                _ollama_restart
            else
                _ollama_start
            fi
            ;;
        3) _ollama_model ;;
        4) _ollama_ctx "" ;;
        5) _ollama_list ;;
        6) _ollama_logs ;;
    esac
    echo ""
}

_ollama_status() {
    _load_ollama_conf

    echo ""
    printf "${M}${B}  🦞 PicoClaw — Ollama Status${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    if ! command -v ollama &>/dev/null; then
        printf "  ${R}✘ Ollama is not installed${N}\n"
        echo ""
        return 0
    fi

    if systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
        local ol_pid=""
        ol_pid=$(systemctl show "$OLLAMA_SVC" --property=MainPID --value 2>/dev/null) || true
        local ol_since=""
        ol_since=$(systemctl show "$OLLAMA_SVC" --property=ActiveEnterTimestamp --value 2>/dev/null) || true
        local ol_ram=""
        if [[ -n "$ol_pid" && "$ol_pid" != "0" ]]; then
            ol_ram=$(ps -o rss= -p "$ol_pid" 2>/dev/null | awk '{printf "%.0fMB", $1/1024}') || ol_ram="?"
        fi
        printf "  Service:   ${G}● running${N}  PID ${ol_pid}  since ${ol_since}\n"
        printf "  RAM:       ${B}${ol_ram}${N}\n"
    elif systemctl is-enabled --quiet "$OLLAMA_SVC" 2>/dev/null; then
        printf "  Service:   ${R}● stopped${N} (enabled — run: picoclaw ollama start)\n"
    else
        printf "  Service:   ${D}○ disabled${N}\n"
    fi

    local model_display="${OLLAMA_CUSTOM_MODEL:-${OLLAMA_MODEL}}"
    printf "  Model:     ${B}${model_display}${N}\n"
    printf "  Base:      ${D}${OLLAMA_MODEL}${N}\n"
    printf "  Context:   ${B}${OLLAMA_NUM_CTX}${N} tokens\n"
    printf "  API:       ${D}http://${OLLAMA_HOST}:${OLLAMA_PORT}/v1${N}\n"
    printf "  Version:   ${D}$(ollama --version 2>/dev/null || echo "unknown")${N}\n"
    echo ""
}

_ollama_start() {
    echo ""
    printf "  ${M}🦞${N} Starting Ollama...\n"
    systemctl start "$OLLAMA_SVC" 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
        printf "  ${G}✔${N} Ollama running\n"
    else
        printf "  ${R}✘${N} Failed to start — check: picoclaw ollama logs\n"
    fi
}

_ollama_stop() {
    echo ""
    printf "  ${M}🦞${N} Stopping Ollama...\n"
    systemctl stop "$OLLAMA_SVC" 2>/dev/null || true
    printf "  ${G}✔${N} Ollama stopped\n"
}

_ollama_restart() {
    echo ""
    printf "  ${M}🦞${N} Restarting Ollama...\n"
    systemctl restart "$OLLAMA_SVC" 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet "$OLLAMA_SVC" 2>/dev/null; then
        printf "  ${G}✔${N} Ollama running\n"
    else
        printf "  ${R}✘${N} Failed to restart — check: picoclaw ollama logs\n"
    fi
}

_ollama_logs() {
    exec journalctl -u "$OLLAMA_SVC" -f
}

_ollama_list() {
    echo ""
    printf "${M}${B}  🦞 PicoClaw — Ollama Models${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""
    ollama list 2>/dev/null || printf "  ${R}✘ Failed to list models (is Ollama running?)${N}\n"
    echo ""
}

_ollama_pull() {
    local model_name="$1"
    if [[ -z "$model_name" ]]; then
        printf "  ${R}✘ Usage: picoclaw ollama pull <model>${N}\n"
        printf "  ${D}Example: picoclaw ollama pull qwen3:4b${N}\n"
        return 1
    fi
    echo ""
    printf "  ${M}🦞${N} Pulling model: ${B}${model_name}${N}\n"
    echo ""
    ollama pull "$model_name" || printf "  ${R}✘ Failed to pull model${N}\n"
    echo ""
}

_ollama_remove() {
    local model_name="$1"
    if [[ -z "$model_name" ]]; then
        printf "  ${R}✘ Usage: picoclaw ollama remove <model>${N}\n"
        return 1
    fi
    echo ""
    printf "  ${C}➜${N} Remove model '${model_name}'? ${D}[y/N]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-n}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        return 0
    fi
    ollama rm "$model_name" 2>/dev/null || printf "  ${R}✘ Failed to remove model${N}\n"
    printf "  ${G}✔${N} Model removed: ${model_name}\n"
    echo ""
}

_ollama_model() {
    _load_ollama_conf

    echo ""
    printf "${M}${B}  🦞 PicoClaw — Ollama Model Switcher${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""

    local current_display="${OLLAMA_CUSTOM_MODEL:-${OLLAMA_MODEL}}"
    printf "  Current model:  ${C}${current_display}${N}\n"
    printf "  Base model:     ${D}${OLLAMA_MODEL}${N}\n"
    printf "  Context:        ${D}${OLLAMA_NUM_CTX} tokens${N}\n"
    echo ""

    local MODEL_DATA="$CLI_MODELS_OLLAMA"

    local -a MODEL_IDS=()
    local -a MODEL_DESCS=()
    while IFS='|' read -r mid mdesc; do
        if [[ -n "$mid" ]]; then
            MODEL_IDS+=("$mid")
            MODEL_DESCS+=("$mdesc")
        fi
    done <<< "$MODEL_DATA"

    local COUNT=${#MODEL_IDS[@]}
    printf "  ${B}Available models:${N}\n"
    echo ""

    for i in "${!MODEL_IDS[@]}"; do
        local NUM=$((i + 1))
        local marker=""
        if [[ "${MODEL_IDS[$i]}" == "$OLLAMA_MODEL" ]]; then
            marker=" ${Y}← current${N}"
        fi
        printf "    ${C}%2d${N}) %-24s ${D}%s${N}%b\n" "$NUM" "${MODEL_IDS[$i]}" "${MODEL_DESCS[$i]}" "$marker"
    done

    echo ""
    printf "    ${C} c${N}) Custom model ID\n"
    echo ""

    local NEW_BASE_MODEL=""
    while true; do
        printf "  ${C}➜${N} Choose (1-${COUNT}, or c for custom): "
        local CHOICE=""
        read -r CHOICE

        if [[ "$CHOICE" == "c" || "$CHOICE" == "C" ]]; then
            printf "  ${C}➜${N} Enter model ID: "
            read -r NEW_BASE_MODEL
            if [[ -z "$NEW_BASE_MODEL" ]]; then
                printf "  ${Y}⚠ Cancelled${N}\n"
                return 0
            fi
            break
        elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= COUNT )); then
            NEW_BASE_MODEL="${MODEL_IDS[$((CHOICE - 1))]}"
            break
        else
            printf "  ${Y}⚠ Invalid — enter 1-${COUNT} or c${N}\n"
        fi
    done

    if [[ "$NEW_BASE_MODEL" == "$OLLAMA_MODEL" ]]; then
        printf "  ${Y}⚠ That's already the current model${N}\n"
        return 0
    fi

    echo ""
    printf "  ${D}Change model:${N}\n"
    printf "    ${R}${OLLAMA_MODEL}${N}  →  ${G}${NEW_BASE_MODEL}${N}\n"
    echo ""
    printf "  ${C}➜${N} Apply? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        return 0
    fi

    # Pull the new model
    echo ""
    printf "  ${M}🦞${N} Pulling ${B}${NEW_BASE_MODEL}${N}...\n"
    ollama pull "$NEW_BASE_MODEL" || { printf "  ${R}✘ Failed to pull model${N}\n"; return 1; }
    printf "  ${G}✔${N} Model downloaded\n"

    # Create custom Modelfile with current num_ctx
    local custom_name="picoclaw-${NEW_BASE_MODEL//[:\/]/-}"
    local mf="/tmp/picoclaw-modelfile"
    printf 'FROM %s\nPARAMETER num_ctx %s\n' "$NEW_BASE_MODEL" "$OLLAMA_NUM_CTX" > "$mf"
    ollama create "$custom_name" -f "$mf" || { printf "  ${R}✘ Failed to create custom model${N}\n"; rm -f "$mf"; return 1; }
    rm -f "$mf"
    printf "  ${G}✔${N} Custom model: ${B}${custom_name}${N} (ctx=${OLLAMA_NUM_CTX})\n"

    # Update config.json
    if [[ -f "$CFG" ]] && command -v jq &>/dev/null; then
        local TMPFILE=""
        TMPFILE=$(mktemp)
        if jq --arg m "$custom_name" '.agents.defaults.model = $m' "$CFG" > "$TMPFILE" 2>/dev/null; then
            mv "$TMPFILE" "$CFG"
            printf "  ${G}✔${N} Config updated: model → ${B}${custom_name}${N}\n"
        else
            rm -f "$TMPFILE"
            printf "  ${Y}⚠${N} Failed to update config.json\n"
        fi
    fi

    # Update ollama.conf
    OLLAMA_MODEL="$NEW_BASE_MODEL"
    OLLAMA_CUSTOM_MODEL="$custom_name"
    _save_ollama_conf
    printf "  ${G}✔${N} Ollama config updated\n"

    # Restart gateway
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        echo ""
        printf "  ${C}➜${N} Restart gateway to apply? ${D}[Y/n]${N}: "
        local DO_RESTART=""
        read -r DO_RESTART
        DO_RESTART="${DO_RESTART:-y}"
        if [[ "${DO_RESTART,,}" == "y" || "${DO_RESTART,,}" == "yes" ]]; then
            printf "  ${M}🦞${N} Restarting gateway...\n"
            systemctl restart "$SVC" 2>/dev/null || true
            sleep 2
            if systemctl is-active --quiet "$SVC" 2>/dev/null; then
                printf "  ${G}✔${N} Gateway running with ${B}${custom_name}${N}\n"
            else
                printf "  ${Y}⚠${N} Gateway may have issues — check: picoclaw logs\n"
            fi
        fi
    fi
    echo ""
}

_ollama_ctx() {
    local new_ctx="$1"
    _load_ollama_conf

    echo ""
    printf "${M}${B}  🦞 PicoClaw — Ollama Context Window${N}\n"
    printf "${D}  ─────────────────────────────────────────────${N}\n"
    echo ""
    printf "  Current context:  ${B}${OLLAMA_NUM_CTX}${N} tokens\n"
    printf "  Current model:    ${B}${OLLAMA_CUSTOM_MODEL:-${OLLAMA_MODEL}}${N}\n"
    echo ""
    printf "  ${D}Lower = less RAM. Use 2048 on 4GB RAM, 4096 on 6GB, 8192+ on 8GB+${N}\n"
    echo ""

    if [[ -z "$new_ctx" ]]; then
        while true; do
            printf "  ${C}➜${N} New context window size (>= 512): "
            read -r new_ctx
            if [[ "$new_ctx" =~ ^[0-9]+$ ]] && (( new_ctx >= 512 )); then
                break
            fi
            printf "  ${Y}⚠ Must be a number >= 512${N}\n"
            new_ctx=""
        done
    else
        if ! [[ "$new_ctx" =~ ^[0-9]+$ ]] || (( new_ctx < 512 )); then
            printf "  ${R}✘ Context window must be a number >= 512${N}\n"
            return 1
        fi
    fi

    if [[ "$new_ctx" == "$OLLAMA_NUM_CTX" ]]; then
        printf "  ${Y}⚠ Same value — no change.${N}\n"
        return 0
    fi

    echo ""
    printf "  ${D}Change context:${N} ${R}${OLLAMA_NUM_CTX}${N} → ${G}${new_ctx}${N}\n"
    printf "  ${C}➜${N} Apply? ${D}[Y/n]${N}: "
    local CONFIRM=""
    read -r CONFIRM
    CONFIRM="${CONFIRM:-y}"
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        printf "  ${D}Cancelled.${N}\n"
        return 0
    fi

    # Recreate custom Modelfile
    local base_model="${OLLAMA_MODEL}"
    local custom_name="picoclaw-${base_model//[:\/]/-}"
    local mf="/tmp/picoclaw-modelfile"
    printf 'FROM %s\nPARAMETER num_ctx %s\n' "$base_model" "$new_ctx" > "$mf"
    ollama create "$custom_name" -f "$mf" || { printf "  ${R}✘ Failed to recreate custom model${N}\n"; rm -f "$mf"; return 1; }
    rm -f "$mf"

    OLLAMA_NUM_CTX="$new_ctx"
    OLLAMA_CUSTOM_MODEL="$custom_name"
    _save_ollama_conf

    # Update config.json
    if [[ -f "$CFG" ]] && command -v jq &>/dev/null; then
        local TMPFILE=""
        TMPFILE=$(mktemp)
        if jq --arg m "$custom_name" '.agents.defaults.model = $m' "$CFG" > "$TMPFILE" 2>/dev/null; then
            mv "$TMPFILE" "$CFG"
        else
            rm -f "$TMPFILE"
        fi
    fi

    printf "  ${G}✔${N} Context window changed to: ${B}${new_ctx}${N} tokens\n"
    printf "  ${G}✔${N} Custom model recreated: ${B}${custom_name}${N}\n"

    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        echo ""
        printf "  ${C}➜${N} Restart gateway to apply? ${D}[Y/n]${N}: "
        local DO_RESTART=""
        read -r DO_RESTART
        DO_RESTART="${DO_RESTART:-y}"
        if [[ "${DO_RESTART,,}" == "y" || "${DO_RESTART,,}" == "yes" ]]; then
            systemctl restart "$SVC" 2>/dev/null || true
            sleep 2
            if systemctl is-active --quiet "$SVC" 2>/dev/null; then
                printf "  ${G}✔${N} Gateway restarted\n"
            fi
        fi
    fi
    echo ""
}

# ═════════════════════════════════════════════════
# DISPATCH
# ═════════════════════════════════════════════════
case "${1:-}" in
    start)       cmd_start ;;
    stop)        cmd_stop ;;
    restart)     cmd_restart ;;
    logs)        cmd_logs "$@" ;;
    status)      cmd_status ;;
    edit|config) cmd_edit ;;
    model)       cmd_model ;;
    telegram)    cmd_telegram ;;
    whatsapp)    cmd_whatsapp "$@" ;;
    ollama)      cmd_ollama "$@" ;;
    backup)      cmd_backup "$@" ;;
    atlas)       cmd_atlas "$@" ;;
    ftp)         cmd_ftp "$@" ;;
    "")          cmd_help ;;
    *)           exec "$BIN" "$@" ;;
esac
WRAPEOF
    chmod +x "$PICOCLAW_BIN"
    success "picoclaw → ${PICOCLAW_BIN} (unified CLI wrapper)"
    info "  picoclaw start | stop | restart | logs | status | edit | model | telegram | whatsapp | ollama | backup | atlas | ftp"
    info "  All other commands pass through to picoclaw.bin"

    # ── Login banner ──
    cat > /etc/profile.d/picoclaw.sh << 'BNEOF'
#!/bin/bash
[[ $- == *i* ]] || return
echo ""
printf "\033[0;35m  🦞 PicoClaw — this machine is PicoClaw-owned\033[0m\n"
printf "\033[2m  ─────────────────────────────────────────────\033[0m\n"
printf "\033[0;36m    picoclaw status\033[0m                    check all\n"
printf "\033[0;36m    picoclaw agent\033[0m                     interactive chat\n"
printf "\033[0;36m    picoclaw agent -m \"...\"\033[0m            one-shot\n"
printf "\033[0;36m    picoclaw start\033[0m                     start gateway\n"
printf "\033[0;36m    picoclaw stop\033[0m                      stop gateway\n"
printf "\033[0;36m    picoclaw restart\033[0m                   restart gateway\n"
printf "\033[0;36m    picoclaw logs\033[0m                      live logs (ctrl+c)\n"
printf "\033[0;36m    picoclaw logs -n 50\033[0m                last 50 lines\n"
printf "\033[0;36m    picoclaw model\033[0m                     switch model\n"
printf "\033[0;36m    picoclaw telegram\033[0m                  manage Telegram & users\n"
printf "\033[0;36m    picoclaw whatsapp\033[0m                  WhatsApp bridge management\n"
printf "\033[0;36m    picoclaw whatsapp login\033[0m            scan QR to link account\n"
printf "\033[0;36m    picoclaw ollama\033[0m                    Ollama local LLM management\n"
printf "\033[0;36m    picoclaw ollama model\033[0m              switch Ollama model\n"
printf "\033[0;36m    picoclaw ollama list\033[0m               list installed models\n"
printf "\033[0;36m    picoclaw ollama ctx 4096\033[0m           change context window\n"
printf "\033[0;36m    picoclaw ollama logs\033[0m               Ollama logs\n"
printf "\033[0;36m    picoclaw atlas\033[0m                     Atlas skills status\n"
printf "\033[0;36m    picoclaw atlas update\033[0m              update skills from repo\n"
printf "\033[0;36m    picoclaw ftp\033[0m                       FTP server management\n"
printf "\033[0;36m    picoclaw backup\033[0m                    create backup\n"
printf "\033[0;36m    picoclaw backup list\033[0m               list all backups\n"
printf "\033[0;36m    picoclaw edit\033[0m                      edit config\n"
printf "\033[2m  Config: /root/.picoclaw/config.json\033[0m\n"
printf "\033[2m  Skills: /root/.picoclaw/workspace/skills/\033[0m\n"
printf "\033[2m  Backup: /root/backup/\033[0m\n"
printf "\033[2m  Docs:   https://github.com/sipeed/picoclaw\033[0m\n"
if [[ -f /etc/sysctl.d/99-picoclaw-performance.conf ]]; then
    printf "\033[0;32m  Perf:   ● optimized (BBR + sysctl + zram + I/O + DNS)\033[0m\n"
fi
if [[ -f /root/.picoclaw/atlas.json ]] && command -v jq &>/dev/null; then
    ac=""
    ac=$(jq -r '.skill_count // 0' /root/.picoclaw/atlas.json 2>/dev/null) || ac="?"
    printf "\033[0;32m  Atlas:  ● ${ac} skill(s) installed\033[0m\n"
fi
if command -v vsftpd &>/dev/null && systemctl is-active --quiet vsftpd 2>/dev/null; then
    printf "\033[0;32m  FTP:    ● running\033[0m\n"
fi
if command -v ollama &>/dev/null; then
    if systemctl is-active --quiet ollama 2>/dev/null; then
        ol_model=""
        if [[ -f /root/.picoclaw/ollama.conf ]]; then
            ol_model=$(grep "^OLLAMA_CUSTOM_MODEL=" /root/.picoclaw/ollama.conf 2>/dev/null | cut -d"'" -f2) || ol_model=""
            if [[ -z "$ol_model" ]]; then
                ol_model=$(grep "^OLLAMA_MODEL=" /root/.picoclaw/ollama.conf 2>/dev/null | cut -d"'" -f2) || ol_model="?"
            fi
        fi
        printf "\033[0;32m  Ollama: ● running (${ol_model})\033[0m\n"
    else
        printf "\033[1;33m  Ollama: ● installed, stopped\033[0m\n"
    fi
fi
if [[ -f /root/.picoclaw/whatsapp-auth/creds.json ]]; then
    if systemctl is-active --quiet picoclaw-whatsapp-bridge 2>/dev/null; then
        printf "\033[0;32m  WA:     ● bridge running, account linked\033[0m\n"
    else
        printf "\033[1;33m  WA:     ● account linked, bridge stopped\033[0m\n"
    fi
elif [[ -d /opt/picoclaw-whatsapp-bridge ]]; then
    printf "\033[1;33m  WA:     ⚠ bridge installed, login needed: picoclaw whatsapp login\033[0m\n"
fi
echo ""
BNEOF
    chmod +x /etc/profile.d/picoclaw.sh
    success "Login banner → /etc/profile.d/picoclaw.sh"
}

# ════════════════════════════════════════════════
# STEP 13: INITIAL BACKUP
# ════════════════════════════════════════════════
initial_backup() {
    step "13/14" "Initial Backup"

    printf "  ${DIM}Creating a snapshot of the freshly installed system.${NC}\n"
    printf "  ${DIM}This serves as your recovery point if anything changes.${NC}\n"

    if [[ "$SETUP_AUTOBACKUP" == "true" ]]; then
        info "Automatic backups enabled — creating initial snapshot..."
        _do_backup "initial"
    elif [[ "$CONFIG_LOADED" == "true" ]]; then
        info "Auto-backup disabled — skipping initial backup"
    else
        if ask_yn "Create initial backup now?" "y"; then
            _do_backup "initial"
        else
            info "Skipped — create one anytime with: picoclaw backup"
        fi
    fi
}

# ════════════════════════════════════════════════
# BACKUP ENGINE — Delegates to CLI wrapper
# ════════════════════════════════════════════════
_do_backup() {
    local trigger="${1:-manual}"

    # Delegate to CLI wrapper if available (installed in step 11)
    if [[ -x "$PICOCLAW_BIN" ]]; then
        "$PICOCLAW_BIN" backup "--${trigger}"
        return $?
    fi

    # Minimal fallback if CLI wrapper doesn't exist (should never happen)
    warn "CLI wrapper not found — creating minimal backup fallback"
    local timestamp
    timestamp=$(date +"%m%d%y_%H%M%S")
    local snap_dir="${BACKUP_DIR}/backup_${timestamp}"
    mkdir -p "$snap_dir"

    if [[ -d "$CONFIG_DIR" ]]; then
        cp -a "$CONFIG_DIR" "${snap_dir}/picoclaw_config" 2>/dev/null || true
        success "Backed up config dir"
    fi

    if [[ -f "$PICOCLAW_REAL" ]]; then
        cp -a "$PICOCLAW_REAL" "${snap_dir}/picoclaw.bin" 2>/dev/null || true
        success "Backed up binary"
    fi

    success "Minimal backup complete: ${snap_dir}"
    info "Install CLI wrapper to enable full backup features"
}

# ════════════════════════════════════════════════
# VERIFY
# ════════════════════════════════════════════════
verify() {
    step "Verify" "Final Checks"

    local rc=0

    rc=0; "$PICOCLAW_REAL" version &>/dev/null || rc=$?
    if [[ $rc -eq 0 ]]; then success "Binary runs"; else warn "Binary didn't respond to 'version' (rc=${rc})"; fi

    rc=0; "$PICOCLAW_REAL" status &>/dev/null || rc=$?
    if [[ $rc -eq 0 ]]; then success "Status OK"; else warn "Status returned issues (rc=${rc} — may need running gateway)"; fi

    rc=0; jq empty "$CONFIG_FILE" &>/dev/null || rc=$?
    if [[ $rc -eq 0 ]]; then success "Config JSON valid"; else warn "Config JSON issue"; fi

    if [[ -f "${WORKSPACE_DIR}/AGENTS.md" ]]; then
        success "Workspace templates present"
    else
        warn "Missing workspace templates"
    fi

    if [[ -x "$PICOCLAW_BIN" ]]; then
        success "picoclaw wrapper installed (unified CLI)"
    else
        warn "picoclaw wrapper missing"
    fi

    if [[ -x "$PICOCLAW_REAL" ]]; then
        success "picoclaw.bin installed (real binary)"
    else
        warn "picoclaw.bin missing"
    fi

    if [[ "$SETUP_SYSTEMD" == "true" ]]; then
        rc=0; systemctl is-enabled --quiet picoclaw-gateway 2>/dev/null || rc=$?
        if [[ $rc -eq 0 ]]; then success "Service enabled"; else warn "Service not enabled"; fi

        rc=0; systemctl is-active --quiet picoclaw-watchdog.timer 2>/dev/null || rc=$?
        if [[ $rc -eq 0 ]]; then success "Watchdog active"; else warn "Watchdog inactive"; fi
    fi

    if [[ "$SETUP_PERFORMANCE" == "true" ]]; then
        if [[ -f /etc/sysctl.d/99-picoclaw-performance.conf ]]; then
            success "Performance: sysctl config installed"
        else
            warn "Performance: sysctl config missing"
        fi

        local cc=""
        cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) || cc="unknown"
        if [[ "$cc" == "bbr" ]]; then
            success "Performance: TCP BBR active"
        else
            warn "Performance: TCP BBR not active (${cc}) — will activate after reboot"
        fi

        local sw=""
        sw=$(sysctl -n vm.swappiness 2>/dev/null) || sw="unknown"
        if [[ "$sw" == "10" ]]; then
            success "Performance: swappiness = ${sw}"
        else
            warn "Performance: swappiness = ${sw} (expected 10)"
        fi

        if [[ -f /etc/security/limits.d/99-picoclaw-performance.conf ]]; then
            success "Performance: file limits configured (1M)"
        fi

        if swapon --show=NAME 2>/dev/null | grep -q "zram"; then
            success "Performance: zram active"
        else
            warn "Performance: zram not active (will activate after reboot)"
        fi

        if [[ -f /etc/udev/rules.d/60-picoclaw-ioscheduler.rules ]]; then
            success "Performance: I/O scheduler rules installed"
        fi

        if grep -q "noatime" /etc/fstab 2>/dev/null; then
            success "Performance: noatime enabled"
        fi

        if grep -q "tmpfs.*/tmp" /etc/fstab 2>/dev/null; then
            success "Performance: tmpfs /tmp configured"
        fi
    fi

    # ── FTP verification ──
    if [[ "$SETUP_FTP" == "true" ]]; then
        if command -v vsftpd &>/dev/null; then
            success "FTP: vsftpd installed"
        else
            warn "FTP: vsftpd not found"
        fi

        if [[ -f /etc/vsftpd.conf ]]; then
            success "FTP: configuration file present"
        else
            warn "FTP: configuration file missing"
        fi

        if id "$FTP_USER" &>/dev/null; then
            success "FTP: user '${FTP_USER}' exists"
        else
            warn "FTP: user '${FTP_USER}' not found"
        fi

        if [[ -f /etc/vsftpd.user_list ]]; then
            if grep -q "^${FTP_USER}$" /etc/vsftpd.user_list 2>/dev/null; then
                success "FTP: user '${FTP_USER}' in allow list"
            else
                warn "FTP: user '${FTP_USER}' not in allow list"
            fi
        fi

        rc=0; systemctl is-enabled --quiet vsftpd 2>/dev/null || rc=$?
        if [[ $rc -eq 0 ]]; then
            success "FTP: vsftpd enabled (auto-start on boot)"
        else
            warn "FTP: vsftpd not enabled"
        fi

        if [[ "$SETUP_PERFORMANCE" != "true" ]]; then
            rc=0; systemctl is-active --quiet vsftpd 2>/dev/null || rc=$?
            if [[ $rc -eq 0 ]]; then
                success "FTP: vsftpd running on port ${FTP_PORT}"
            else
                warn "FTP: vsftpd not running"
            fi
        else
            info "FTP: vsftpd will start after mandatory reboot"
        fi

        if [[ "$FTP_TLS" == "true" ]]; then
            if [[ -f /etc/ssl/private/vsftpd.pem && -f /etc/ssl/private/vsftpd.key ]]; then
                success "FTP: TLS certificate present"
            else
                warn "FTP: TLS enabled but certificate missing"
            fi
        fi

        if [[ -f "$FTP_CONF_FILE" ]]; then
            success "FTP: config metadata present (${FTP_CONF_FILE})"
        fi
    fi

    # ── WhatsApp verification ──
    if [[ "$WA_ENABLED" == "true" ]]; then
        if [[ -d "$WA_BRIDGE_DIR" ]]; then
            success "WhatsApp: bridge directory exists (${WA_BRIDGE_DIR})"
        else
            warn "WhatsApp: bridge directory missing"
        fi

        if [[ -f "${WA_BRIDGE_DIR}/dist/index.js" ]]; then
            success "WhatsApp: bridge compiled (dist/index.js)"
        else
            warn "WhatsApp: dist/index.js missing — bridge not compiled"
        fi

        if command -v node &>/dev/null; then
            local nv=""
            nv=$(_node_major)
            if [[ "$nv" =~ ^[0-9]+$ ]] && (( nv >= 20 )); then
                success "WhatsApp: Node.js $(node --version) (>= 20 OK)"
            else
                warn "WhatsApp: Node.js version too old ($(node --version 2>/dev/null))"
            fi
        else
            warn "WhatsApp: Node.js not found"
        fi

        rc=0; systemctl is-enabled --quiet "$WA_BRIDGE_SERVICE" 2>/dev/null || rc=$?
        if [[ $rc -eq 0 ]]; then
            success "WhatsApp: bridge service enabled"
        else
            warn "WhatsApp: bridge service not enabled"
        fi

        if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
            success "WhatsApp: account linked (creds.json found)"
        else
            warn "WhatsApp: account NOT linked — run: picoclaw whatsapp login"
        fi

        if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
            local wa_bridge_url=""
            wa_bridge_url=$(jq -r '.channels.whatsapp.bridge_url // empty' "$CONFIG_FILE" 2>/dev/null) || true
            if [[ -n "$wa_bridge_url" ]]; then
                success "WhatsApp: bridge_url set in config (${wa_bridge_url})"
            else
                warn "WhatsApp: bridge_url not set in config.json"
            fi
        fi

        if [[ -f "$WA_CONF_FILE" ]]; then
            success "WhatsApp: config metadata present (${WA_CONF_FILE})"
        fi
    fi

    # ── Ollama verification ──
    if [[ "$SETUP_OLLAMA" == "true" ]]; then
        if command -v ollama &>/dev/null; then
            local ollama_ver=""
            ollama_ver=$(ollama --version 2>/dev/null) || ollama_ver="unknown"
            success "Ollama: binary installed (${ollama_ver})"
        else
            warn "Ollama: binary not found"
        fi

        rc=0; systemctl is-enabled --quiet "$OLLAMA_SERVICE" 2>/dev/null || rc=$?
        if [[ $rc -eq 0 ]]; then
            success "Ollama: service enabled (auto-start on boot)"
        else
            warn "Ollama: service not enabled"
        fi

        if [[ "$SETUP_PERFORMANCE" != "true" ]]; then
            rc=0; systemctl is-active --quiet "$OLLAMA_SERVICE" 2>/dev/null || rc=$?
            if [[ $rc -eq 0 ]]; then
                local ollama_pid=""
                ollama_pid=$(systemctl show "$OLLAMA_SERVICE" --property=MainPID --value 2>/dev/null) || true
                local ollama_ram=""
                if [[ -n "$ollama_pid" && "$ollama_pid" != "0" ]]; then
                    ollama_ram=$(ps -o rss= -p "$ollama_pid" 2>/dev/null | awk '{printf "%.0fMB", $1/1024}') || ollama_ram="?"
                fi
                success "Ollama: service running (PID ${ollama_pid}, ${ollama_ram} RAM)"
            else
                warn "Ollama: service not running"
            fi
        else
            info "Ollama: service will start after mandatory reboot"
        fi

        # Check if the selected model is present
        local ollama_custom_model="picoclaw-${OLLAMA_MODEL//[:\/]/-}"
        if command -v ollama &>/dev/null; then
            if ollama list 2>/dev/null | grep -q "${ollama_custom_model}"; then
                success "Ollama: custom model '${ollama_custom_model}' present (num_ctx=${OLLAMA_NUM_CTX})"
            elif ollama list 2>/dev/null | grep -q "${OLLAMA_MODEL%%:*}"; then
                success "Ollama: base model '${OLLAMA_MODEL}' present"
                warn "Ollama: custom model '${ollama_custom_model}' not found — may need recreation"
            else
                warn "Ollama: model '${OLLAMA_MODEL}' not found — may need: ollama pull ${OLLAMA_MODEL}"
            fi
        fi

        # Check if the API endpoint responds (only if not rebooting)
        if [[ "$SETUP_PERFORMANCE" != "true" ]]; then
            if curl -sf --connect-timeout 3 --max-time 5 "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/tags" > /dev/null 2>&1; then
                success "Ollama: API responding on http://${OLLAMA_HOST}:${OLLAMA_PORT}"
            else
                warn "Ollama: API not responding (service may need restart)"
            fi
        else
            info "Ollama: API check skipped (will be available after reboot)"
        fi

        # Check if config.json vllm slot points to Ollama
        if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
            local vllm_base=""
            vllm_base=$(jq -r '.providers.vllm.api_base // empty' "$CONFIG_FILE" 2>/dev/null) || true
            if [[ "$vllm_base" == *"11434"* ]]; then
                success "Ollama: config.json vllm slot → ${vllm_base}"
            else
                warn "Ollama: config.json vllm slot not pointing to Ollama (got: '${vllm_base}')"
            fi

            local cfg_model=""
            cfg_model=$(jq -r '.agents.defaults.model // empty' "$CONFIG_FILE" 2>/dev/null) || true
            if [[ "$cfg_model" == picoclaw-* ]]; then
                success "Ollama: config.json model = ${cfg_model}"
            elif [[ "$cfg_model" == "$OLLAMA_MODEL" ]]; then
                warn "Ollama: config.json model is base name '${cfg_model}' (expected custom 'picoclaw-...')"
            fi
        fi

        if [[ -f "$OLLAMA_CONF_FILE" ]]; then
            success "Ollama: config metadata present (${OLLAMA_CONF_FILE})"
        else
            warn "Ollama: config metadata missing (${OLLAMA_CONF_FILE})"
        fi
    fi

    # ── Atlas verification ──
    if [[ "$SETUP_ATLAS" == "true" ]]; then
        if [[ -f "$ATLAS_META_FILE" ]]; then
            success "Atlas: metadata file present"
        else
            warn "Atlas: metadata file missing"
        fi

        if [[ -d "$ATLAS_SKILLS_DIR" ]]; then
            local atlas_skill_count=0
            for sd in "${ATLAS_SKILLS_DIR}"/*/; do
                if [[ -f "${sd}SKILL.md" ]]; then
                    atlas_skill_count=$((atlas_skill_count + 1))
                fi
            done
            if [[ $atlas_skill_count -gt 0 ]]; then
                success "Atlas: ${atlas_skill_count} skill(s) installed in ${ATLAS_SKILLS_DIR}/"
                for sd in "${ATLAS_SKILLS_DIR}"/*/; do
                    if [[ -f "${sd}SKILL.md" ]]; then
                        local sn="${sd%/}"
                        sn="${sn##*/}"
                        local sv="?"
                        if [[ -f "${sd}VERSION" ]]; then
                            sv=$(head -1 "${sd}VERSION" 2>/dev/null) || sv="?"
                    sv="${sv//[[:space:]]/}"
                        fi
                        local fc=0
                        shopt -s nullglob dotglob
                        local -a files=("$sd"/*)
                        for f in "${files[@]}"; do
                            if [[ -f "$f" ]]; then
                                fc=$((fc + 1))
                            fi
                        done
                        shopt -u nullglob dotglob
                        success "  Atlas skill: ${sn} (v${sv}, ${fc} files)"
                    fi
                done
            else
                warn "Atlas: skills directory exists but no skills with SKILL.md found"
            fi
        else
            warn "Atlas: skills directory missing"
        fi
    fi

    if [[ -f "$BACKUP_META_FILE" ]]; then
        success "Backup config: ${BACKUP_META_FILE}"
    else
        warn "Backup config missing"
    fi

    if [[ -d "$BACKUP_DIR" ]]; then
        local bk_count
        bk_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l) || bk_count=0
        if [[ $bk_count -gt 0 ]]; then
            success "Backups: ${bk_count} snapshot(s) in ${BACKUP_DIR}"
        else
            info "Backups: directory exists, no snapshots yet"
        fi
    fi

    if [[ "$SETUP_AUTOBACKUP" == "true" ]]; then
        if [[ -f /etc/cron.d/picoclaw-autobackup ]]; then
            success "Auto-backup cron: every ${BACKUP_INTERVAL_DAYS} days (max ${BACKUP_MAX_KEEP})"
        else
            warn "Auto-backup cron file missing"
        fi
    fi

    if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
        local cfg_model cfg_or_key cfg_or_base
        cfg_model=$(jq -r '.agents.defaults.model // empty' "$CONFIG_FILE" 2>/dev/null) || true
        cfg_or_key=$(jq -r '.providers.openrouter.api_key // empty' "$CONFIG_FILE" 2>/dev/null) || true
        cfg_or_base=$(jq -r '.providers.openrouter.api_base // empty' "$CONFIG_FILE" 2>/dev/null) || true

        if [[ -n "$cfg_or_key" && -n "$cfg_or_base" ]]; then
            success "Provider routing: openrouter slot → ${cfg_or_base} (model: ${cfg_model})"
        fi

        if [[ "$TG_ENABLED" == "true" && -n "$TG_USERNAME" ]]; then
            local tg_af
            tg_af=$(jq -r '.channels.telegram.allow_from | join(",")' "$CONFIG_FILE" 2>/dev/null) || true
            if echo "$tg_af" | grep -q "|"; then
                success "Telegram allow_from: ID|username format"
            else
                warn "Telegram allow_from: missing ID|username — messages may be dropped"
            fi
        fi
    fi
}

# ════════════════════════════════════════════════
# FINAL SCREEN
# ════════════════════════════════════════════════
final() {
    echo ""
    printf "${MAGENTA}${BOLD}\n"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║     ✅  PicoClaw — Installed & Running                   ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
EOF
    printf "${NC}\n"

    printf "  ${GREEN}✔${NC} Binary:    ${PICOCLAW_REAL}\n"
    printf "  ${GREEN}✔${NC} Wrapper:   ${PICOCLAW_BIN}\n"
    printf "  ${GREEN}✔${NC} Config:    ${CONFIG_FILE}\n"
    printf "  ${GREEN}✔${NC} Workspace: ${WORKSPACE_DIR}\n"
    if [[ "$SETUP_SYSTEMD" == "true" ]]; then
        printf "  ${GREEN}✔${NC} Service:   picoclaw-gateway.service\n"
        printf "  ${GREEN}✔${NC} Watchdog:  picoclaw-watchdog.timer (60s)\n"
        printf "  ${GREEN}✔${NC} Cron:      /etc/cron.d/picoclaw-boot\n"
    fi
    printf "  ${GREEN}✔${NC} Backup:    ${BACKUP_DIR}\n"
    if [[ "$SETUP_AUTOBACKUP" == "true" ]]; then
        printf "  ${GREEN}✔${NC} Auto-bkp:  every ${BACKUP_INTERVAL_DAYS} days, keep ${BACKUP_MAX_KEEP}\n"
    fi
    if [[ "$SETUP_PERFORMANCE" == "true" ]]; then
        printf "  ${GREEN}✔${NC} Perf:      optimized (BBR + sysctl + zram + I/O + DNS + limits)\n"
    fi
    if [[ "$SETUP_ATLAS" == "true" ]]; then
        local atlas_count=0
        if [[ -f "$ATLAS_META_FILE" ]] && command -v jq &>/dev/null; then
            atlas_count=$(jq -r '.skill_count // 0' "$ATLAS_META_FILE" 2>/dev/null) || atlas_count=0
        fi
        printf "  ${GREEN}✔${NC} Atlas:     ${atlas_count} skill(s) from ${ATLAS_REPO_URL}\n"
    fi
    if [[ "$SETUP_FTP" == "true" ]]; then
        local public_ip=""
        public_ip=$(curl -sf --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null) || true
        if [[ -z "$public_ip" ]]; then
            public_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || public_ip="?"
        fi
        printf "  ${GREEN}✔${NC} FTP:       ${FTP_USER}@:${FTP_PORT} (TLS: ${FTP_TLS}, full access)\n"
        printf "             ${DIM}ftp://${FTP_USER}@${public_ip}:${FTP_PORT}${NC}\n"
    fi
    if [[ "$WA_ENABLED" == "true" ]]; then
        printf "  ${GREEN}✔${NC} WhatsApp:  bridge installed (port ${WA_BRIDGE_PORT})\n"
        if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
            printf "             ${GREEN}account linked${NC}\n"
        else
            printf "             ${YELLOW}⚠ login required: picoclaw whatsapp login${NC}\n"
        fi
    fi
    if [[ "$SETUP_OLLAMA" == "true" ]]; then
        local ollama_custom="picoclaw-${OLLAMA_MODEL//[:\/]/-}"
        printf "  ${GREEN}✔${NC} Ollama:    ${BOLD}${ollama_custom}${NC} (base: ${OLLAMA_MODEL})\n"
        printf "             ${DIM}API: ${OLLAMA_API_BASE} (routed via vllm slot)${NC}\n"
        printf "             ${DIM}Context: ${OLLAMA_NUM_CTX} tokens${NC}\n"
    fi
    echo ""
    printf "  ${BOLD}Reboot safety:${NC} systemd + watchdog + cron @reboot\n"
    echo ""
    printf "  ${BOLD}All commands:${NC}  picoclaw <command>\n"
    echo ""
    printf "  ${CYAN}picoclaw status${NC}                         check everything\n"
    printf "  ${CYAN}picoclaw start${NC}                          start gateway\n"
    printf "  ${CYAN}picoclaw stop${NC}                           stop gateway\n"
    printf "  ${CYAN}picoclaw restart${NC}                        restart gateway\n"
    printf "  ${CYAN}picoclaw logs${NC}                           live logs (ctrl+c)\n"
    printf "  ${CYAN}picoclaw logs -n 50${NC}                     last 50 lines\n"
    printf "  ${CYAN}picoclaw model${NC}                          switch model\n"
    printf "  ${CYAN}picoclaw telegram${NC}                       manage Telegram & users\n"
    printf "  ${CYAN}picoclaw whatsapp${NC}                       WhatsApp bridge management\n"
    printf "  ${CYAN}picoclaw whatsapp login${NC}                 scan QR to link account\n"
    printf "  ${CYAN}picoclaw whatsapp logout${NC}                unlink account\n"
    printf "  ${CYAN}picoclaw whatsapp status${NC}                bridge status\n"
    printf "  ${CYAN}picoclaw whatsapp start${NC}                 start bridge\n"
    printf "  ${CYAN}picoclaw whatsapp stop${NC}                  stop bridge\n"
    printf "  ${CYAN}picoclaw whatsapp logs${NC}                  bridge logs\n"
    printf "  ${CYAN}picoclaw whatsapp enable${NC}                enable WhatsApp\n"
    printf "  ${CYAN}picoclaw whatsapp disable${NC}               disable WhatsApp\n"
    printf "  ${CYAN}picoclaw ollama${NC}                         Ollama local LLM management\n"
    printf "  ${CYAN}picoclaw ollama status${NC}                  Ollama service status\n"
    printf "  ${CYAN}picoclaw ollama model${NC}                   switch Ollama model\n"
    printf "  ${CYAN}picoclaw ollama list${NC}                    list installed models\n"
    printf "  ${CYAN}picoclaw ollama pull <model>${NC}            pull a new model\n"
    printf "  ${CYAN}picoclaw ollama remove <model>${NC}          remove a model\n"
    printf "  ${CYAN}picoclaw ollama ctx <number>${NC}            change context window\n"
    printf "  ${CYAN}picoclaw ollama start${NC}                   start Ollama service\n"
    printf "  ${CYAN}picoclaw ollama stop${NC}                    stop Ollama service\n"
    printf "  ${CYAN}picoclaw ollama restart${NC}                 restart Ollama service\n"
    printf "  ${CYAN}picoclaw ollama logs${NC}                    Ollama logs\n"
    printf "  ${CYAN}picoclaw atlas${NC}                          Atlas skills status\n"
    printf "  ${CYAN}picoclaw atlas list${NC}                     list installed skills\n"
    printf "  ${CYAN}picoclaw atlas update${NC}                   update all skills from repo\n"
    printf "  ${CYAN}picoclaw ftp${NC}                            FTP server management\n"
    printf "  ${CYAN}picoclaw ftp status${NC}                     FTP server status\n"
    printf "  ${CYAN}picoclaw ftp password${NC}                   change FTP password\n"
    printf "  ${CYAN}picoclaw ftp port${NC}                       change FTP port\n"
    printf "  ${CYAN}picoclaw ftp tls${NC}                        toggle TLS encryption\n"
    printf "  ${CYAN}picoclaw ftp logs${NC}                       view FTP logs\n"
    printf "  ${CYAN}picoclaw backup${NC}                         create backup now\n"
    printf "  ${CYAN}picoclaw backup list${NC}                    list all backups\n"
    printf "  ${CYAN}picoclaw backup settings${NC}                backup settings\n"
    printf "  ${CYAN}picoclaw edit${NC}                           edit config\n"
    printf "  ${CYAN}picoclaw agent${NC}                          interactive chat\n"
    printf "  ${CYAN}picoclaw agent -m \"hello\"${NC}               test one-shot\n"
    printf "  ${CYAN}picoclaw gateway${NC}                        run gateway foreground\n"
    printf "  ${CYAN}picoclaw cron list${NC}                      scheduled jobs\n"
    printf "  ${CYAN}picoclaw skills list${NC}                    installed skills\n"
    printf "  ${CYAN}picoclaw version${NC}                        show version\n"
    echo ""

    if [[ "$TG_ENABLED" == "true" ]]; then printf "  ${GREEN}${BOLD}Telegram is live — message your bot!${NC}\n"; fi
    if [[ "$DC_ENABLED" == "true" ]]; then printf "  ${GREEN}${BOLD}Discord is live — message your bot!${NC}\n"; fi
    if [[ "$WA_ENABLED" == "true" ]]; then
        if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
            printf "  ${GREEN}${BOLD}WhatsApp is live — message your number!${NC}\n"
        else
            printf "  ${YELLOW}${BOLD}WhatsApp bridge installed — run: picoclaw whatsapp login${NC}\n"
        fi
    fi
    if [[ "$FS_ENABLED" == "true" ]]; then printf "  ${GREEN}${BOLD}Feishu configured!${NC}\n"; fi
    if [[ "$MC_ENABLED" == "true" ]]; then printf "  ${GREEN}${BOLD}MaixCAM configured!${NC}\n"; fi

    if [[ "$LLM_PROVIDER" == "groq" ]]; then
        echo ""
        printf "  ${YELLOW}${BOLD}Groq note:${NC} Key is in the openrouter config slot (PicoClaw routing workaround).\n"
        printf "  ${DIM}This is intentional — Groq's API is OpenAI-compatible and works perfectly.${NC}\n"
    fi

    if [[ "$SETUP_PERFORMANCE" == "true" ]]; then
        echo ""
        printf "  ${GREEN}${BOLD}Performance optimizations applied:${NC}\n"
        printf "  ${DIM}  TCP BBR · 60+ sysctl params · 1M file limits · zram swap${NC}\n"
        printf "  ${DIM}  I/O scheduler · SSD TRIM · noatime · tmpfs /tmp · DNS 1.1.1.1${NC}\n"
        printf "  ${DIM}  journald cap · fast timeouts · IRQ balance · MGLRU · KSM${NC}\n"
        printf "  ${DIM}  Originals backed up in ~/.picoclaw/perf_backup_*/${NC}\n"
    fi

    if [[ "$SETUP_ATLAS" == "true" ]]; then
        echo ""
        printf "  ${GREEN}${BOLD}Atlas skills installed:${NC}\n"
        if [[ -d "$ATLAS_SKILLS_DIR" ]]; then
            for sd in "${ATLAS_SKILLS_DIR}"/*/; do
                if [[ -f "${sd}SKILL.md" ]]; then
                    local sn="${sd%/}"
                    sn="${sn##*/}"
                    local sv="?"
                    if [[ -f "${sd}VERSION" ]]; then
                        sv=$(head -1 "${sd}VERSION" 2>/dev/null) || sv="?"
                    sv="${sv//[[:space:]]/}"
                    fi
                    printf "  ${DIM}  ${sn} (v${sv})${NC}\n"
                fi
            done
        fi
        printf "  ${DIM}  Update anytime: picoclaw atlas update${NC}\n"
        printf "  ${DIM}  Repository: ${ATLAS_REPO_URL}${NC}\n"
    fi

    if [[ "$SETUP_FTP" == "true" ]]; then
        echo ""
        printf "  ${GREEN}${BOLD}FTP server configured:${NC}\n"
        printf "  ${DIM}  User: ${FTP_USER}  Port: ${FTP_PORT}  TLS: ${FTP_TLS}${NC}\n"
        printf "  ${DIM}  Access: full filesystem (read/write everywhere)${NC}\n"
        printf "  ${DIM}  Manage: picoclaw ftp${NC}\n"
        printf "  ${YELLOW}  ⚠ Use a strong password — this user has full system access.${NC}\n"
    fi

    if [[ "$WA_ENABLED" == "true" ]]; then
        echo ""
        printf "  ${GREEN}${BOLD}WhatsApp bridge configured:${NC}\n"
        printf "  ${DIM}  Bridge: ${WA_BRIDGE_DIR} (port ${WA_BRIDGE_PORT})${NC}\n"
        printf "  ${DIM}  Auth:   ${WA_BRIDGE_AUTH_DIR}/${NC}\n"
        printf "  ${DIM}  Node.js: $(node --version 2>/dev/null)${NC}\n"
        if [[ -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
            printf "  ${GREEN}  Account: linked (session persisted)${NC}\n"
        else
            printf "  ${YELLOW}  ⚠ Account NOT linked — you MUST run:${NC}\n"
            printf "    ${CYAN}picoclaw whatsapp login${NC}\n"
            printf "  ${YELLOW}  to scan the QR code and link your WhatsApp.${NC}\n"
        fi
        printf "  ${DIM}  Manage: picoclaw whatsapp${NC}\n"
        printf "  ${DIM}  Logs:   picoclaw whatsapp logs${NC}\n"
    fi

    if [[ "$SETUP_OLLAMA" == "true" ]]; then
        echo ""
        local ollama_custom="picoclaw-${OLLAMA_MODEL//[:\/]/-}"
        printf "  ${GREEN}${BOLD}Ollama local LLM configured:${NC}\n"
        printf "  ${DIM}  Base model:    ${OLLAMA_MODEL}${NC}\n"
        printf "  ${DIM}  Custom model:  ${ollama_custom} (num_ctx=${OLLAMA_NUM_CTX})${NC}\n"
        printf "  ${DIM}  API endpoint:  ${OLLAMA_API_BASE}${NC}\n"
        printf "  ${DIM}  Provider slot: vllm (OpenAI-compatible /v1 endpoint)${NC}\n"
        printf "  ${DIM}  Service:       ollama (systemd-managed, auto-start on boot)${NC}\n"
        # Show model size if available
        if command -v ollama &>/dev/null; then
            local ollama_model_size=""
            ollama_model_size=$(ollama list 2>/dev/null | grep "${ollama_custom}" | awk '{print $3, $4}') || true
            if [[ -z "$ollama_model_size" || "$ollama_model_size" == " " ]]; then
                ollama_model_size=$(ollama list 2>/dev/null | grep "${OLLAMA_MODEL%%:*}" | head -1 | awk '{print $3, $4}') || true
            fi
            if [[ -n "$ollama_model_size" && "$ollama_model_size" != " " ]]; then
                printf "  ${DIM}  Model size:    ${ollama_model_size}${NC}\n"
            fi
        fi
        printf "  ${DIM}  Manage:        picoclaw ollama${NC}\n"
        printf "  ${DIM}  Switch model:  picoclaw ollama model${NC}\n"
        printf "  ${DIM}  Context:       picoclaw ollama ctx <number>${NC}\n"
        printf "  ${DIM}  Logs:          picoclaw ollama logs${NC}\n"
    fi

    echo ""
    printf "  ${DIM}Docs: https://github.com/sipeed/picoclaw${NC}\n"
    printf "  ${DIM}Atlas: https://github.com/pr0ace/atlas${NC}\n"
    printf "  ${DIM}Discord: https://discord.gg/V4sAZ9XWpN${NC}\n"
    echo ""

    # ════════════════════════════════════════════════════════════
    # POST-INSTALL: REBOOT (performance) or START + LOGS (no perf)
    # ════════════════════════════════════════════════════════════
    if [[ "$SETUP_PERFORMANCE" == "true" ]]; then
        # ── Performance selected → mandatory reboot ──
        printf "${YELLOW}${BOLD}\n"
        cat << 'REBOOTEOF'
    ╔══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║     ⚠  MANDATORY REBOOT REQUIRED                         ║
    ║                                                          ║
    ║     Performance optimizations require a full reboot       ║
    ║     to activate all kernel-level changes:                 ║
    ║       • TCP BBR congestion control                        ║
    ║       • sysctl memory & network tuning                    ║
    ║       • zram compressed swap                              ║
    ║       • I/O scheduler udev rules                          ║
    ║       • File descriptor limits                            ║
    ║       • tmpfs /tmp mount                                  ║
    ║       • MGLRU / KSM kernel features                       ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
REBOOTEOF
        printf "${NC}\n"

        if [[ "$SETUP_SYSTEMD" == "true" ]]; then
            printf "  ${GREEN}${BOLD}After reboot:${NC}\n"
            printf "    ${GREEN}✔${NC} PicoClaw gateway will start automatically (systemd enabled)\n"
            printf "    ${GREEN}✔${NC} Watchdog timer will monitor the gateway (every 60s)\n"
            printf "    ${GREEN}✔${NC} Cron @reboot fallback will ensure recovery\n"
            if [[ "$SETUP_OLLAMA" == "true" ]]; then
                printf "    ${GREEN}✔${NC} Ollama will start automatically (model pre-downloaded)\n"
            fi
            if [[ "$SETUP_FTP" == "true" ]]; then
                printf "    ${GREEN}✔${NC} FTP server will start automatically (vsftpd enabled)\n"
            fi
            if [[ "$WA_ENABLED" == "true" ]]; then
                printf "    ${GREEN}✔${NC} WhatsApp bridge will start automatically (systemd enabled)\n"
                if [[ ! -f "${WA_BRIDGE_AUTH_DIR}/creds.json" ]]; then
                    printf "    ${YELLOW}⚠${NC} But you still need to run: ${CYAN}picoclaw whatsapp login${NC}\n"
                fi
            fi
            echo ""
            printf "  ${DIM}Your bot(s) will be live within ~15 seconds of boot.${NC}\n"
            printf "  ${DIM}Check status after reboot with: picoclaw status${NC}\n"
        else
            printf "  ${YELLOW}${BOLD}After reboot:${NC}\n"
            printf "    ${YELLOW}⚠${NC} PicoClaw gateway will ${RED}NOT${NC} start automatically\n"
            printf "      (systemd service was not enabled during setup)\n"
            if [[ "$SETUP_OLLAMA" == "true" ]]; then
                printf "    ${GREEN}✔${NC} Ollama will start automatically (systemd enabled)\n"
            fi
            if [[ "$SETUP_FTP" == "true" ]]; then
                printf "    ${GREEN}✔${NC} FTP server will start automatically (vsftpd enabled)\n"
            fi
            if [[ "$WA_ENABLED" == "true" ]]; then
                printf "    ${GREEN}✔${NC} WhatsApp bridge will start automatically (systemd enabled)\n"
            fi
            echo ""
            printf "  ${DIM}Start it manually after reboot with:${NC}\n"
            printf "    ${CYAN}picoclaw start${NC}                    start the gateway\n"
            printf "    ${CYAN}picoclaw logs${NC}                     view live logs\n"
        fi

        echo ""
        separator

        printf "  ${BOLD}The system will reboot now to apply all optimizations.${NC}\n"
        echo ""

        local countdown=18
        printf "  ${YELLOW}⚠${NC} Rebooting in ${BOLD}${countdown}${NC} seconds... (press Ctrl+C to cancel) "
        while [[ $countdown -gt 0 ]]; do
            printf "\r  ${YELLOW}⚠${NC} Rebooting in ${BOLD}${countdown}${NC} seconds... (press Ctrl+C to cancel)  "
            sleep 1
            countdown=$((countdown - 1))
        done
        echo ""
        echo ""
        printf "  ${MAGENTA}${BOLD}🦞 Rebooting now...${NC}\n"
        echo ""
        sync
        reboot
    else
        # ── No performance → offer to start gateway and view logs ──
        if [[ "$SETUP_SYSTEMD" == "true" ]]; then
            local is_running=false
            if systemctl is-active --quiet picoclaw-gateway 2>/dev/null; then
                is_running=true
            fi

            if [[ "$is_running" == "true" ]]; then
                printf "  ${GREEN}${BOLD}Gateway is already running!${NC}\n"
                echo ""
                if [[ "$CONFIG_LOADED" != "true" ]] && ask_yn "View live logs now? (Ctrl+C to exit)" "y"; then
                    echo ""
                    printf "  ${DIM}Attaching to picoclaw-gateway logs... (Ctrl+C to detach)${NC}\n"
                    echo ""
                    journalctl -u picoclaw-gateway -f || true
                fi
            else
                if [[ "$CONFIG_LOADED" != "true" ]] && ask_yn "Start PicoClaw gateway now?" "y"; then
                    echo ""
                    printf "  ${MAGENTA}🦞${NC} Starting PicoClaw gateway...\n"
                    systemctl start picoclaw-gateway 2>/dev/null || true
                    sleep 2
                    if systemctl is-active --quiet picoclaw-gateway 2>/dev/null; then
                        local gw_pid=""
                        gw_pid=$(systemctl show picoclaw-gateway --property=MainPID --value 2>/dev/null) || true
                        printf "  ${GREEN}✔${NC} Gateway running (PID ${gw_pid})\n"
                        echo ""
                        if ask_yn "View live logs now? (Ctrl+C to exit)" "y"; then
                            echo ""
                            printf "  ${DIM}Attaching to picoclaw-gateway logs... (Ctrl+C to detach)${NC}\n"
                            echo ""
                            journalctl -u picoclaw-gateway -f || true
                        fi
                    else
                        printf "  ${RED}✘${NC} Gateway failed to start\n"
                        printf "  ${DIM}Check logs with: picoclaw logs${NC}\n"
                    fi
                else
                    printf "  ${DIM}Start later with: picoclaw start${NC}\n"
                fi
            fi
        else
            printf "  ${DIM}No systemd service configured.${NC}\n"
            printf "  ${DIM}Run manually: picoclaw gateway${NC}\n"
            printf "  ${DIM}Or in background: nohup picoclaw gateway &${NC}\n"
        fi
    fi
}

# ════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════
main() {
    local config_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_usage
                ;;
            --config)
                if [[ -z "${2:-}" ]]; then
                    printf '%s\n' "${RED}✘ --config requires a file path${NC}" >&2
                    exit 1
                fi
                config_file="$2"
                shift 2
                ;;
            *)
                printf '%s\n' "${RED}✘ Unknown option: $1${NC}" >&2
                printf '%s\n' "Run 'bash atlas-install.sh --help' for usage" >&2
                exit 1
                ;;
        esac
    done

    if [[ -n "$config_file" ]]; then
        parse_config "$config_file"
        CONFIG_LOADED=true
    fi

    banner
    preflight
    resolve_picoclaw_latest
    wizard
    install_system            # 1/14: apt update + upgrade + packages + Node.js
    optimize_system           # 2/14: deep performance optimization
    install_go                # 3/14: Go 1.26.0 (source build only)
    install_picoclaw          # 4/14: binary or source → picoclaw.bin
    init_picoclaw             # 5/14: onboard (creates workspace templates)
    install_atlas_skills      # 6/14: Atlas skills repository (dynamic discovery)
    write_config              # 7/14: overwrite config.json with wizard values + backup.conf + ftp.conf + whatsapp.conf + ollama.conf
    install_whatsapp_bridge   # 8/14: WhatsApp Baileys/Node.js bridge + auto QR login
    install_ollama            # 9/14: Ollama local LLM server (optional)
    install_ftp_server        # 10/14: vsftpd FTP server (optional)
    setup_systemd             # 11/14: service + watchdog + cron + auto-backup cron
    install_extras            # 12/14: unified picoclaw wrapper + login banner
    initial_backup            # 13/14: ask user for initial backup snapshot
    verify
    final
}

main "$@"

# shellcheck shell=bash
# Shared functions for claudeload. Sourced by bin/claudeload.

# ANSI helpers (prefixed _CL_ to avoid clashing with .bashrc PS1 vars)
_CL_B=$'\033[1m'  _CL_C=$'\033[36m'  _CL_G=$'\033[32m'
_CL_Y=$'\033[33m' _CL_0=$'\033[0m'

# ══════════════════════════════════════════════════════════════════════════════
#  Logging & Error Handling
# ══════════════════════════════════════════════════════════════════════════════

_cl_log()  { [[ -z "${CLAUDELOAD_QUIET:-}" ]] && echo "$@"; return 0; }
_cl_warn() { [[ -z "${CLAUDELOAD_QUIET:-}" ]] && echo "$@" >&2; return 0; }
_cl_die()  { echo "$*" >&2; return 1; }

# ══════════════════════════════════════════════════════════════════════════════
#  Environment Management
# ══════════════════════════════════════════════════════════════════════════════

# Clear every ANTHROPIC_* var from previous sessions.  A stale ANTHROPIC_API_KEY
# sitting next to a proxy's ANTHROPIC_AUTH_TOKEN triggers the "auth may not work
# as expected" warning in Claude Code.
_cl_clear_env() {
  local v
  while IFS= read -r v; do unset -v "$v"; done < <(compgen -v 'ANTHROPIC_')
  # DeepSeek deliberately sets this to low. Do not carry that constraint into
  # another backend, where it can silently reduce Codex reasoning quality.
  unset CLAUDE_CODE_EFFORT_LEVEL
  # Only a backend that knows its model's window (strata) declares this; carry
  # it across a switch and Claude Code sizes every later model to that window.
  unset CLAUDE_CODE_MAX_CONTEXT_TOKENS
  unset CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY
}

_cl_use_endpoint() {
  local url="$1" credential_type="$2" credential="$3"
  _cl_clear_env
  export ANTHROPIC_BASE_URL="${url%/}"
  case "$credential_type" in
    token) export ANTHROPIC_AUTH_TOKEN="$credential" ;;
    key)   export ANTHROPIC_API_KEY="$credential" ;;
    *)     _cl_die "unknown credential type: $credential_type"; return 1 ;;
  esac
}

# Export the six model env vars Claude Code uses.
#   _cl_export_models <base> [fast] [sonnet]
# Defaults: fast → base, sonnet → base.
_cl_export_models() {
  local base="$1" fast="${2:-$1}" sonnet="${3:-$1}"
  export ANTHROPIC_MODEL="$base"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="$base"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$fast"
  export ANTHROPIC_SMALL_FAST_MODEL="$fast"
  export CLAUDE_CODE_SUBAGENT_MODEL="$fast"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Proxy Management (tmux)
# ══════════════════════════════════════════════════════════════════════════════

# Resolve one port per backend. A local launcher or config can supply its
# default; an explicit override always wins.
# _cl_resolve_port <override> <fallback> [file] [sed extraction]
_cl_resolve_port() {
  local port="$1" fallback="$2" file="${3:-}" extract="${4:-}"
  if [[ -z "$port" && -n "$file" && -r "$file" && -n "$extract" ]]; then
    port="$(sed -nE "$extract" "$file" | tail -1)"
  fi
  port="${port:-$fallback}"
  if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
    _cl_die "invalid proxy port: $port"
    return 1
  fi
  printf '%s' "$port"
}

# _cl_port_up <port> → 0 if something is already listening
_cl_port_up() {
  ss -ltn 2>/dev/null | awk '{print $4}' | \grep -qE "(^|:)$1$" && return 0
  curl -sf -o /dev/null --max-time 1 "http://localhost:$1/v1/models" 2>/dev/null
}

# _cl_spawn_proxy <name> <port> <cmd...>
# Run <cmd> in a foreground tmux window inside the 'proxies' session,
# unless the port is already up.  Waits up to 30 s for the port.
_cl_spawn_proxy() {
  local name="$1" port="$2"; shift 2

  if _cl_port_up "$port"; then
    _cl_log "$name: already running on :$port"
    return 0
  fi

  _cl_log "$name: starting on :$port (foreground in tmux window)…"

  if ! command -v tmux >/dev/null 2>&1; then
    _cl_warn "$name: tmux not found — running detached"
    "$@" >/dev/null 2>&1 &
  elif [[ -n "${TMUX:-}" ]]; then
    tmux new-window -d -n "$name" "$@"
  elif ! tmux has-session -t proxies 2>/dev/null; then
    tmux new-session -d -s proxies -n "$name" "$@"
  else
    tmux new-window -d -t proxies -n "$name" "$@"
  fi

  local i
  for ((i=0; i<30; i++)); do
    _cl_port_up "$port" && return 0
    sleep 1
  done
  _cl_warn "$name: warning — :$port not up after 30 s"
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  Data Helpers
# ══════════════════════════════════════════════════════════════════════════════

_cl_require_litellm() {
  local name="$1"
  command -v litellm >/dev/null 2>&1 || export PATH="$PATH:$HOME/.local/bin"
  if ! command -v litellm >/dev/null 2>&1; then
    _cl_die "$name: litellm not found! Install via: uv tool install 'litellm[proxy]'"
    return 1
  fi
}

_cl_require_node() {
  local name="$1"
  if ! command -v node >/dev/null 2>&1; then
    _cl_die "$name: node not found (install Node.js)"
    return 1
  fi
}

# Keep generated LiteLLM config files in the user's cache directory.
_cl_config_file() {
  local dir="${XDG_CACHE_HOME:-$HOME/.cache}/claudeload"
  mkdir -p "$dir" || return 1
  printf '%s/%s' "$dir" "$1"
}

# ══════════════════════════════════════════════════════════════════════════════

# Fetch JSON from a URL with optional Authorization header.
_cl_fetch_json() {
  local url="$1" auth="${2:-}"
  if [[ -n "$auth" ]]; then
    curl -sf "$url" -H "Authorization: Bearer $auth" 2>/dev/null
  else
    curl -sf "$url" 2>/dev/null
  fi
}

# Retry a model catalog while a newly started proxy populates it.
# _cl_fetch_catalog <url> <auth> <attempts> [fallback_url]
_cl_fetch_catalog() {
  local url="$1" auth="$2" attempts="$3" fallback="${4:-}" value i
  for ((i=0; i<attempts; i++)); do
    value="$(_cl_fetch_json "$url" "$auth")"
    [[ -z "$value" && -n "$fallback" ]] && value="$(_cl_fetch_json "$fallback" "$auth")"
    if [[ -n "$value" && "$value" != "[]" && "$value" != '{"object":"list","data":[]}' ]]; then
      printf '%s' "$value"
      return 0
    fi
    ((i + 1 < attempts)) && sleep 1
  done
  return 1
}

# Keep non-conversational endpoints out of Claude Code's model picker.
_cl_filter_chat_models() {
  \grep -viE 'embedding|whisper|tts|dall-e|babbage|davinci|moderation|text-search|search|similarity|trajectory|compaction|image'
}

_cl_sort_models() {
  if sort -V </dev/null >/dev/null 2>&1; then sort -V; else sort; fi
}

# Run inline Python that reads JSON from $_CL_JSON env var and prints TSV.
#   _cl_models_to_tsv <json> <python_code>
# Extra env vars can be prepended by the caller (e.g. _CL_EXTRA="val" _cl_models_to_tsv ...).
_cl_models_to_tsv() {
  local tmp_json
  tmp_json="$(mktemp)"
  printf "%s" "$1" > "$tmp_json"
  _CL_JSON_FILE="$tmp_json" python3 -c "import os; os.environ['_CL_JSON'] = open(os.environ['_CL_JSON_FILE']).read();"$'
'"$2"
  local rc=$?
  rm -f "$tmp_json"
  return $rc
}

# Common OpenAI-style model list. Backends with custom metadata keep their own
# formatter; these three parameters cover the simple catalogs.
# _cl_basic_models_tsv <json> <label field> <fallback label>
_cl_basic_models_tsv() {
  local label_field="$2" fallback_label="$3"
  _CL_LABEL_FIELD="$label_field" _CL_FALLBACK_LABEL="$fallback_label" \
    _cl_models_to_tsv "$1" "${_CL_PY_SORT}"'
import json, os
try:
    payload = json.loads(os.environ["_CL_JSON"])
    models = payload.get("data", []) if isinstance(payload, dict) else payload
except (ValueError, TypeError):
    models = []
rows = {}
for model in models:
    if not isinstance(model, dict) or not model.get("id"):
        continue
    mid = model["id"]
    label = model.get(os.environ["_CL_LABEL_FIELD"]) or os.environ["_CL_FALLBACK_LABEL"]
    rows[mid] = (mid, label, "")
for mid, label, status in sorted(rows.values(), key=_nkey):
    print("%s\t%s\t%s" % (mid, label, status))
'
}

# Natural-sort + pick the last match from a newline-separated list.
#   _cl_derive_fast <model_list> <grep_pattern> [exclude_pattern]
_cl_derive_fast() {
  local models="$1" pattern="$2" exclude="${3:-}"
  if [[ -n "$exclude" ]]; then
    printf '%s\n' "$models" | \grep -iE "$pattern" | \grep -viE "$exclude" | _cl_sort_models | tail -1
  else
    printf '%s\n' "$models" | \grep -iE "$pattern" | _cl_sort_models | tail -1
  fi
}

# Lowercased vendor token from a model id (claude/gpt/gemini/…).
_cl_vendor_of() {
  local s="${1,,}" v
  s="${s//_/-}"
  for v in claude gpt gemini glm deepseek grok kimi nemotron swe inkling mai qwen; do
    [[ "$s" == *"$v"* ]] && { echo "$v"; return 0; }
  done
  echo "${s%%[-0-9]*}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Interactive Model Picker
# ══════════════════════════════════════════════════════════════════════════════

# _cl_pick "<title>" "<tsv>"
# Print a colored numbered table to stderr, read a choice from the terminal,
# echo the chosen id to stdout.  TSV columns: id <TAB> label <TAB> status.
# Returns 1 if the user quits.
_cl_pick() {
  local title="$1" tsv="$2"
  local out
  out="$(printf '%s' "$tsv" | python3 "$_CLD_ROOT/bin/cl_picker.py" "$title")"
  local rc=$?
  if [[ $rc -eq 0 && -n "$out" ]]; then
    printf '%s' "$out"
    return 0
  fi
  return 1
}

_cl_print_status() {
  local endpoint="${ANTHROPIC_BASE_URL:-not configured}"
  printf '%b\n' "${_CL_C}╭─ Claude Code backend${_CL_0}"
  printf '%b\n' "${_CL_C}│${_CL_0} Endpoint   ${_CL_B}${endpoint}${_CL_0}"
  printf '%b\n' "${_CL_C}│${_CL_0} Main       ${ANTHROPIC_MODEL:-not configured}"
  printf '%b\n' "${_CL_C}│${_CL_0} Opus       ${ANTHROPIC_DEFAULT_OPUS_MODEL:-not configured}"
  printf '%b\n' "${_CL_C}│${_CL_0} Sonnet     ${ANTHROPIC_DEFAULT_SONNET_MODEL:-not configured}"
  printf '%b\n' "${_CL_C}│${_CL_0} Haiku/Fast ${ANTHROPIC_SMALL_FAST_MODEL:-not configured}"
  printf '%b\n' "${_CL_C}│${_CL_0} Subagent   ${CLAUDE_CODE_SUBAGENT_MODEL:-not configured}"
  if [[ "$endpoint" == http://127.0.0.1:* || "$endpoint" == http://localhost:* ]]; then
    local health_url="${endpoint%/}/health"
    if curl -sf -o /dev/null --max-time 1 "$health_url" 2>/dev/null; then
      printf '%b\n' "${_CL_C}│${_CL_0} Service    ${_CL_G}healthy${_CL_0}"
    else
      printf '%b\n' "${_CL_C}│${_CL_0} Service    ${_CL_Y}not checked / unavailable${_CL_0}"
    fi
  fi
  printf '%b\n' "${_CL_C}╰────────────────────────────────────────${_CL_0}"
}

# _cl_select_model "<title>" "<tsv>" [override]
# If override is non-empty, echo it; otherwise run _cl_pick.
_cl_select_model() {
  local title="$1" tsv="$2" override="${3:-}"
  if [[ -z "$tsv" ]]; then
    _cl_die "$title: no selectable models"
    return 1
  fi
  if [[ -n "$override" ]]; then
    printf '%s' "$override"
    return 0
  fi
  _cl_pick "$title" "$tsv" || { echo "  cancelled" >&2; return 1; }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Shared Python: natural-sort TSV rows
# ══════════════════════════════════════════════════════════════════════════════
# Every backend's Python TSV builder needs the same nkey() sort.  This variable
# holds the shared fragment so we define it once.
_CL_PY_SORT='
import re
def _nkey(r):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", r[0])]
'

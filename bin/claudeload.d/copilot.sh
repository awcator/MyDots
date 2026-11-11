# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: Copilot  (port 4141, copilot-api)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"
  local port
  port="$(_cl_resolve_port "" 4141)" || return 1
  local base_url="${COPILOT_BASE_URL:-http://localhost:$port}"
  base_url="${base_url%/}"

  _cl_use_endpoint "$base_url" token "${COPILOT_AUTH_TOKEN:-dummy}" || return 1

  if [[ -z "${COPILOT_BASE_URL:-}" ]]; then
    if ! _cl_port_up "$port" && ! command -v npx >/dev/null 2>&1; then
      _cl_die "copilot: npx not found (install Node.js and npm)"
      return 1
    fi
    _cl_spawn_proxy copilot "$port" \
      npx -y copilot-api@latest start --port "$port" --account-type "${COPILOT_ACCOUNT_TYPE:-business}" || return 1
  fi

  local models_json tsv all base
  models_json="$(_cl_fetch_json "$base_url/v1/models" "${COPILOT_AUTH_TOKEN:-}")"
  tsv="$(_cl_basic_models_tsv "$models_json" "" "" | _cl_filter_chat_models)"
  if [[ -z "$tsv" ]]; then
    _cl_die "copilot: couldn't fetch models from $base_url"
    return 1
  fi

  all="$(printf '%s\n' "$tsv" | cut -f1)"
  base="$(_cl_select_model "Copilot models ($base_url)" "$tsv" "$model_override")" \
    || return 1

  # Dynamically derive sonnet (mid-tier) and fast (lightest) from same vendor
  local vendor sonnet fast
  vendor="$(_cl_vendor_of "$base")"
  # Mid-tier: same vendor, prefer "sonnet" variant, else largest capable non-base
  sonnet="$(_cl_derive_fast "$all" "^${vendor}.*sonnet")"
  [[ -z "$sonnet" ]] && sonnet="$(printf '%s\n' "$all" \
    | \grep -iE "^${vendor}" \
    | \grep -viE 'mini|lite|haiku|flash|embed|compaction|trajectory|codex|copilot' \
    | \grep -Fxv "$base" | _cl_sort_models | tail -1)"
  # Fast: same vendor, prefer mini/haiku/flash/lite variant
  fast="$(_cl_derive_fast "$all" "^${vendor}.*(mini|haiku|flash|lite)")"
  [[ -z "$fast" ]] && fast="$(printf '%s\n' "$all" \
    | \grep -iE "^${vendor}" | _cl_sort_models | head -1)"
  : "${sonnet:=$base}" "${fast:=$base}"

  _cl_export_models "$base" "$fast" "$sonnet"
  _cl_log "Loaded: $ANTHROPIC_MODEL (copilot, $base_url)" \
          "— sonnet: $ANTHROPIC_DEFAULT_SONNET_MODEL," \
          "haiku: $ANTHROPIC_SMALL_FAST_MODEL"
}

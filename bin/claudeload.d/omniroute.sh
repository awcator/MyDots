# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: OmniRoute  (port 20128, omniroute serve)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"
  local port
  port="$(_cl_resolve_port "" 20128)" || return 1
  local base_url="${OMNIROUTE_BASE_URL:-http://localhost:$port/v1}"
  base_url="${base_url%/}"

  if [[ -z "${OMNIROUTE_KEY:-}" ]]; then
    _cl_warn "omniroute: OMNIROUTE_KEY not found in env (continuing anyway)"
  fi

  _cl_use_endpoint "$base_url" key "${OMNIROUTE_KEY:-sk-dummy}" || return 1
  export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1

  if [[ -z "${OMNIROUTE_BASE_URL:-}" ]]; then
    if ! _cl_port_up "$port" && ! command -v omniroute >/dev/null 2>&1; then
      _cl_die "omniroute: command not found (install it or set OMNIROUTE_BASE_URL)"
      return 1
    fi
    _cl_spawn_proxy omniroute "$port" omniroute serve --port "$port" --log --no-open || return 1
  fi

  local models_json active_providers
  models_json="$(_cl_fetch_catalog "$base_url/models" "$ANTHROPIC_API_KEY" 15)" || {
    _cl_die "omniroute: couldn't fetch models from $base_url"
    return 1
  }
  # A local OmniRoute install can identify which catalog providers are active.
  if [[ -z "${OMNIROUTE_BASE_URL:-}" ]] && command -v omniroute >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    active_providers="$(omniroute providers list | awk '/active/{print $2}' | paste -sd "," -)"
    if [[ -n "$active_providers" ]]; then
      models_json="$(printf '%s' "$models_json" | jq --arg providers "$active_providers" '.data = [.data[] | select(.owned_by as $o | ($providers | contains($o)) and (.id | test("-low$|-medium$|-high$|-xhigh$|-tiered$|^auto/|/auto$|^kiro/|^gemini-web/") | not))]')"
    fi
  fi

  local tsv
  tsv="$(_cl_basic_models_tsv "$models_json" name "")"

  local base
  base="$(_cl_select_model "OmniRoute models ($base_url)" "$tsv" "$model_override")" \
    || return 1

  local all fast sonnet
  all="$(echo "$tsv" | cut -f1)"
  sonnet="$(printf '%s\n' "$all" | \grep -i 'sonnet' | head -1)"
  fast="$(printf '%s\n' "$all" | \grep -iE 'haiku|mini|flash|lite' | head -1)"
  : "${fast:=$base}" "${sonnet:=$base}"

  _cl_export_models "$base" "$fast" "$sonnet"
  _cl_log "Loaded: $ANTHROPIC_MODEL (omniroute, $base_url)" \
          "— sonnet: $ANTHROPIC_DEFAULT_SONNET_MODEL," \
          "haiku/subagent: $ANTHROPIC_SMALL_FAST_MODEL"
}

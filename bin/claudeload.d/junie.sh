# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: Junie API  (default port 4143)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"
  local port
  port="$(_cl_resolve_port "${JUNIE_PORT:-}" 4143)" || return 1
  local repo_dir="${JUNIE_REPO:-$_CLD_SIBLINGS/junie-api}"

  _cl_use_endpoint "http://localhost:$port" token "${JUNIE_AUTH_TOKEN:-dummy}" || return 1

  if ! _cl_port_up "$port"; then
    _cl_require_node "junie" || return 1
    local key="${JUNIE_API_KEY:-}"
    if [[ -z "$key" ]]; then
      _cl_die "junie: JUNIE_API_KEY not found in environment"
      return 1
    fi
    if [[ ! -f "$repo_dir/dist/main.js" ]]; then
      _cl_die "junie: proxy checkout not found at $repo_dir (set JUNIE_REPO)"
      return 1
    fi
    _cl_spawn_proxy junie "$port" \
      node "$repo_dir/dist/main.js" start --auth-token "$key" --port "$port" || return 1
  fi

  local models_json
  models_json="$(_cl_fetch_catalog "http://localhost:$port/v1/models" "${JUNIE_AUTH_TOKEN:-}" 20)" || {
    _cl_die "junie: couldn't fetch models from :$port"
    return 1
  }

  local tsv
  tsv="$(_cl_basic_models_tsv "$models_json" owned_by "Junie model")"

  local base
  base="$(_cl_select_model "Junie models (:$port)" "$tsv" "$model_override")" \
    || return 1

  local all fast sonnet
  all="$(echo "$tsv" | cut -f1)"
  sonnet="$(printf '%s\n' "$all" | \grep -i 'sonnet' | head -1)"
  fast="$(printf '%s\n' "$all" | \grep -iE 'haiku|mini|flash|lite' | head -1)"
  # If base is a Claude model, keep all companion roles on Claude to avoid
  # cross-provider routing that can fail with upstream auth on some IDs.
  if [[ "$base" == claude-* ]]; then
    sonnet="$base"
    fast="$base"
  fi
  : "${fast:=$base}" "${sonnet:=$base}"

  _cl_export_models "$base" "$fast" "$sonnet"
  _cl_log "Loaded: $ANTHROPIC_MODEL (junie, :$port)" \
          "— sonnet: $ANTHROPIC_DEFAULT_SONNET_MODEL," \
          "haiku/subagent: $ANTHROPIC_SMALL_FAST_MODEL"
}

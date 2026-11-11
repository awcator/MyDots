# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: Strata  (run-uncensored.sh)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"
  local repo_dir="${STRATA_REPO:-$_CLD_SIBLINGS/Strata}"
  local launcher="$repo_dir/run-uncensored.sh"
  local port
  port="$(_cl_resolve_port "${STRATA_PORT:-}" 8090 "$launcher" 's/.*--port[[:space:]]+([0-9]+).*/\1/p')" || return 1
  local base_url="${STRATA_BASE_URL:-http://127.0.0.1:$port}"
  base_url="${base_url%/}"

  _cl_use_endpoint "$base_url" token "${STRATA_AUTH_TOKEN:-test}" || return 1

  if [[ -z "${STRATA_BASE_URL:-}" ]]; then
    if ! _cl_port_up "$port" && [[ ! -f "$launcher" ]]; then
      _cl_die "strata: proxy checkout not found at $repo_dir (set STRATA_REPO)"
      return 1
    fi
    _cl_spawn_proxy strata "$port" \
      bash -c 'cd "$1" && exec ./run-uncensored.sh --port "$2"' _ "$repo_dir" "$port" || return 1
  fi

  local models_json
  models_json="$(_cl_fetch_catalog "$base_url/v1/models" "${STRATA_AUTH_TOKEN:-}" 15)" || {
    _cl_die "strata: couldn't fetch models from $base_url"
    return 1
  }

  local tsv
  tsv="$(_cl_basic_models_tsv "$models_json" "" "Strata local model")"

  local base
  base="$(_cl_select_model "Strata models ($base_url)" "$tsv" "$model_override")" \
    || return 1

  _cl_export_models "$base"

  # Claude Code never asks a gateway for the window: an unrecognised model ID
  # is assumed to be 200k.  Declare the engine's real one, so the context meter
  # and proactive auto-compaction both use it.  Keep this equal to the config's
  # --max-context (strata-uncensored-ud-q4_k_xl.json).
  export CLAUDE_CODE_MAX_CONTEXT_TOKENS="${STRATA_CONTEXT_TOKENS:-131072}"

  _cl_log "Loaded: $ANTHROPIC_MODEL (strata, $base_url)" \
          "— context: $CLAUDE_CODE_MAX_CONTEXT_TOKENS (declared)"
}

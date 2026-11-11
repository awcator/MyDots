# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: Devin proxy (port 3003, this repository)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"
  local repo_dir="${DEVIN_PROXY_DIR:-$_CLD_SIBLINGS/WindsurfAPI}"
  local port
  port="$(_cl_resolve_port "${DEVIN_PROXY_PORT:-}" 3003 "$repo_dir/.env" 's/^PORT=([0-9]+).*/\1/p')" || return 1
  local base_url="${DEVIN_PROXY_BASE_URL:-http://127.0.0.1:$port}"
  base_url="${base_url%/}"

  # Claude Code requires a token even when the local proxy allows anonymous use.
  local gateway_key="${DEVIN_PROXY_API_KEY:-${API_KEY:-}}"
  if [[ -z "$gateway_key" && -f "$repo_dir/.env" ]]; then
    gateway_key="$(sed -n 's/^API_KEY=//p' "$repo_dir/.env" | tail -1)"
    case "$gateway_key" in
      \"*\"|\'*\') gateway_key="${gateway_key:1:-1}" ;;
    esac
  fi
  _cl_use_endpoint "$base_url" token "${gateway_key:-dummy}" || return 1

  if [[ -z "${DEVIN_PROXY_BASE_URL:-}" ]] && ! _cl_port_up "$port"; then
    _cl_require_node "devin" || return 1
    if [[ ! -f "$repo_dir/src/index.js" ]]; then
      _cl_die "devin: proxy checkout not found at $repo_dir (set DEVIN_PROXY_DIR or DEVIN_PROXY_BASE_URL)"
      return 1
    fi
    _cl_spawn_proxy devinproxy "$port" \
      bash -c 'cd "$1" && exec env PORT="$2" node src/index.js' _ "$repo_dir" "$port" || return 1
  fi

  local models_json tsv
  models_json="$(_cl_fetch_json "$base_url/v1/models" "$gateway_key")"
  [[ -z "$models_json" ]] && { _cl_die "devin: couldn't fetch models from $base_url"; return 1; }
  tsv="$(_cl_basic_models_tsv "$models_json" owned_by "")"
  [[ -z "$tsv" ]] && { _cl_die "devin: proxy returned no selectable models"; return 1; }

  local base
  base="$(_cl_select_model "Devin models ($base_url)" "$tsv" "$model_override")" \
    || return 1

  _cl_export_models "$base"
  _cl_log "Loaded: $ANTHROPIC_MODEL (devinproxy, $base_url)"
}

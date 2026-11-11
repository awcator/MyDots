# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: Codex Proxy  (port 8081, Docker)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"
  local port
  port="$(_cl_resolve_port "" 8081)" || return 1
  local base_url="${CODEX_PROXY_BASE_URL:-http://127.0.0.1:$port}"
  base_url="${base_url%/}"
  local key="${CODEX_PROXY_API_KEY:-}"
  local compose_dir="${CODEX_PROXY_DIR:-$_CLD_SIBLINGS/codex-proxy}"
  local key_file="${CODEX_PROXY_CONFIG:-$compose_dir/data/local.yaml}"

  # Prefer an explicitly supplied key.  The Docker setup stores its generated
  # local key in data/local.yaml; read it only when no override was supplied.
  if [[ -z "$key" && -r "$key_file" ]]; then
    key="$(sed -n 's/^[[:space:]]*proxy_api_key:[[:space:]]*//p' "$key_file" | head -n 1)"
    key="${key%%[[:space:]]#*}"
    key="${key#\"}"; key="${key%\"}"
    key="${key#\'}"; key="${key%\'}"
  fi
  if [[ -z "$key" || "$key" == "null" ]]; then
    _cl_die "codexproxy: API key unavailable — set CODEX_PROXY_API_KEY or log in to the local dashboard"
    return 1
  fi

  # Start only the known local default. Custom URLs point to existing services.
  if [[ "$base_url" == "http://127.0.0.1:$port" || "$base_url" == "http://localhost:$port" ]] && ! _cl_port_up "$port"; then
    if ! command -v docker >/dev/null 2>&1 || [[ ! -f "$compose_dir/docker-compose.yml" ]]; then
      _cl_die "codexproxy: Docker Compose setup not found at $compose_dir"
      return 1
    fi
    _cl_spawn_proxy codexproxy "$port" \
      bash -c 'cd "$1" && exec docker compose up' _ "$compose_dir" || return 1
    if ! _cl_port_up "$port"; then
      _cl_die "codexproxy: :$port did not become ready after 30 seconds"
      return 1
    fi
  fi

  _cl_use_endpoint "$base_url" key "$key" || return 1

  # Fetch the extended catalog for useful labels and availability metadata.
  # Fall back to the standard OpenAI model list if the extended endpoint is
  # unavailable on an older Codex Proxy image. After an on-demand Docker
  # start, allow time for the authenticated account's catalog refresh.
  local models_json
  models_json="$(_cl_fetch_catalog "$base_url/v1/models/catalog" "$key" 15 "$base_url/v1/models")" || {
    _cl_die "codexproxy: no models available — log in to the dashboard, then restart the Docker container"
    return 1
  }

  local tsv
  tsv="$(_cl_models_to_tsv "$models_json" "${_CL_PY_SORT}"'
import json, os
payload = json.loads(os.environ["_CL_JSON"])
models = payload.get("data", []) if isinstance(payload, dict) else payload
rows = []
for m in models:
    mid = m.get("id", "")
    if not mid:
        continue
    desc = m.get("displayName") or m.get("description") or "Codex model"
    upgrade = m.get("upgrade") or {}
    status = ("upgrade → %s" % upgrade.get("model")) if upgrade.get("model") else ""
    rows.append((mid, desc, status))
rows.sort(key=_nkey)
for mid, desc, status in rows:
    print("%s\t%s\t%s" % (mid, desc, status))
')"

  local base
  base="$(_cl_select_model "Codex Proxy models ($base_url)" "$tsv" "$model_override")" \
    || return 1

  # Derive companion roles from the live catalog. Prefer current, stable Codex
  # families: Terra for balanced work and Luna for inexpensive parallel work.
  # Preview-only models are fallback choices, not the default subagent tier.
  local all fast sonnet
  all="$(echo "$tsv" | cut -f1)"
  sonnet="$(printf '%s\n' "$all" | \grep -x 'gpt-5.6-terra' | head -1)"
  [[ -z "$sonnet" ]] && sonnet="$(printf '%s\n' "$all" | \grep -i 'terra' | head -1)"
  fast="$(printf '%s\n' "$all" | \grep -x 'gpt-5.6-luna' | head -1)"
  [[ -z "$fast" ]] && fast="$(printf '%s\n' "$all" | \grep -iE 'luna|mini' | \grep -vi 'preview' | head -1)"
  [[ -z "$fast" ]] && fast="$(printf '%s\n' "$all" | \grep -i 'spark' | head -1)"
  : "${fast:=$base}" "${sonnet:=$base}"

  _cl_export_models "$base" "$fast" "$sonnet"
  _cl_log "Loaded: $ANTHROPIC_MODEL (codexproxy, $base_url)" \
          "— sonnet: $ANTHROPIC_DEFAULT_SONNET_MODEL," \
          "haiku/subagent: $ANTHROPIC_SMALL_FAST_MODEL"
}

# ══════════════════════════════════════════════════════════════════════════════

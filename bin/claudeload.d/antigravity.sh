# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: Antigravity  (port 9080, local clone of antigravity-claude-proxy)
# ══════════════════════════════════════════════════════════════════════════════

# Run the locally patched clone, not the published `acc` bin. The released
# build ordered the dead cloudcode-pa prod endpoint first and lacks the
# signature-scrubbing and Claude max-token fixes, so `acc start` fails with a
# misleading 429 "quota exhausted" on every account.
# Models the quota API advertises but that do not actually serve. Verified
# 2026-09-17 by querying the Cloud Code API directly with a minted token:
#   gemini-2.5-pro      503 "No capacity available for model" — retired upstream
#   gemini-3.1-pro-high 400 INVALID_ARGUMENT under every request shape tried
#                       (no generationConfig; maxOutputTokens 16k and 65k;
#                       thinking budgets 128 and 10001). Its sibling
#                       gemini-3.1-pro-low answers fine, so it is the id that is
#                       dead, not the request. Picking it costs a ~2 min retry
#                       ladder before it gives up.
# Both are still listed by every proxy endpoint, so filter them here. Override to
# re-test, and prune entries that start working again:
#   AG_DEAD_MODELS="gemini-2.5-pro" source claudeload antigravity
_cl_backend_run() {
  local model_override="${1:-}"
  local repo_dir="${AG_REPO:-$_CLD_SIBLINGS/antigravity-claude-proxy}"
  local port
  port="$(_cl_resolve_port "${AG_PORT:-}" 9080)" || return 1
  local dead_models="${AG_DEAD_MODELS:-gemini-2.5-pro gemini-3.1-pro-high}"
  local base_url="${AG_BASE_URL:-http://localhost:$port}"
  base_url="${base_url%/}"

  if [[ -z "${AG_BASE_URL:-}" ]] && ! _cl_port_up "$port" && [[ ! -f "$repo_dir/src/index.js" ]]; then
    _cl_die "antigravity: no clone at $repo_dir (set AG_REPO to the repo path)"
    return 1
  fi

  _cl_use_endpoint "$base_url" token "${AG_AUTH_TOKEN:-test}" || return 1

  if [[ -z "${AG_BASE_URL:-}" ]]; then
    if ! _cl_port_up "$port"; then
      _cl_require_node "antigravity" || return 1
    fi
    _cl_spawn_proxy antigravity "$port" \
      bash -c 'cd "$1" && exec env PORT="$2" node src/index.js' _ "$repo_dir" "$port" || return 1
  fi

  local models_json accounts_json health_json
  models_json="$(_cl_fetch_json "$base_url/v1/models" "${AG_AUTH_TOKEN:-}")"

  accounts_json="$(_cl_fetch_json "$base_url/api/accounts" "${AG_AUTH_TOKEN:-}")"
  health_json="$(_cl_fetch_json "$base_url/health" "${AG_AUTH_TOKEN:-}")"

  if [[ -z "$models_json" ]]; then
    _cl_die "antigravity: couldn't fetch models from $ANTHROPIC_BASE_URL (is the proxy + account working?)"
    return 1
  fi

  # Build the catalog of record from the proxy's own view of the account pool.
  #
  # /v1/models is not a full catalog: upstream hides every Gemini id below 3.5
  # ("curate /v1/models listing"), yet most of those still serve — only retired
  # ones 503. /api/accounts is worse: it exposes modelRateLimits, i.e. only the
  # models that have *already* hit a rate limit, so it is empty on a fresh proxy
  # or after any cooldown reset, and it can never list a healthy model. /health
  # reports the full per-account quota set, so use that as the source of truth
  # and fold in the listing for anything it doesn't cover.
  local catalog_json
  catalog_json="$(_AG_HEALTH="$health_json" _AG_MODELS="$models_json" \
                  _AG_DEAD="$dead_models" python3 -c '
import json, os
seen, ids, descs = set(), [], []
dead = set((os.environ.get("_AG_DEAD") or "").split())

def add(mid, desc=""):
    if mid and mid not in seen and mid not in dead:
        seen.add(mid)
        ids.append(mid)
        descs.append(desc)

try:
    for m in json.loads(os.environ.get("_AG_MODELS") or "{}").get("data", []):
        add(m.get("id"), m.get("description") or "")
except Exception:
    pass
try:
    for a in json.loads(os.environ.get("_AG_HEALTH") or "{}").get("accounts", []):
        for mid in (a.get("models") or {}):
            add(mid)
except Exception:
    pass

print(json.dumps({"object": "list",
                  "data": [{"id": i, "description": d} for i, d in zip(ids, descs)]}))
')"

  if [[ -z "$catalog_json" || "$catalog_json" == '{"object": "list", "data": []}' ]]; then
    _cl_die "antigravity: proxy reported no models (is an account healthy?)"
    return 1
  fi

  local tsv
  tsv="$(python3 "$_CLD_ROOT/bin/ag_format.py" "$catalog_json" "$accounts_json")"

  local base
  base="$(_cl_select_model "Antigravity models ($base_url)" "$tsv" "$model_override")" \
    || return 1

  # Use selected base model for fast/subagent companion to guarantee zero rate-limit collisions
  local fast="$base"

  if [[ "$base" == *claude* ]]; then
    # Cloud Code rejects streamGenerateContent for Claude models above 64000
    # (400 INVALID_ARGUMENT). Measured: 64000 passes, 100000 fails. The limit
    # only bites the streaming path, which is the only one Claude Code uses, so
    # an uncapped value here looks like a random hard failure.
    export CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000
  else
    # Gemini: the proxy caps this to its own GEMINI_MAX_OUTPUT_TOKENS (16384).
    export CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000
  fi

  _cl_export_models "$base" "$fast"
  _cl_log "Loaded: $ANTHROPIC_MODEL (antigravity, $base_url)" \
          "— fast/subagent: $ANTHROPIC_SMALL_FAST_MODEL"
}

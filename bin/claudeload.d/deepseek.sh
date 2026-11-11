# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: DeepSeek  (api.deepseek.com, direct API)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"

  _cl_use_endpoint https://api.deepseek.com/anthropic key "${DEEPSEEK_KEY:-}" || return 1

  local models_json
  models_json="$(_cl_fetch_json "https://api.deepseek.com/models" "$ANTHROPIC_API_KEY")"

  if [[ -z "$models_json" ]]; then
    _cl_die "deepseek: couldn't fetch models from API (is DEEPSEEK_KEY set?)"
    return 1
  fi

  local tsv
  tsv="$(_cl_models_to_tsv "$models_json" "${_CL_PY_SORT}"'
import json, os
models = json.loads(os.environ["_CL_JSON"])
rows = []
for m in models.get("data", []):
    mid = m.get("id", "")
    desc = "DeepSeek Reasoning Model" if "pro" in mid or "reasoner" in mid else "DeepSeek Standard Model"
    rows.append((mid, desc, ""))
rows.sort(key=_nkey)
for mid, desc, status in rows:
    print("%s\t%s\t%s" % (mid, desc, status))
')"

  local base
  base="$(_cl_select_model "DeepSeek models (api.deepseek.com)" "$tsv" "$model_override")" \
    || return 1

  local fast
  fast="$(echo "$tsv" | cut -f1 | \grep -i flash | head -1)"
  : "${fast:=$base}"

  _cl_export_models "$base" "$fast"
  export CLAUDE_CODE_EFFORT_LEVEL=low

  # Show remaining API balance
  local bal
  bal="$(_cl_fetch_json "https://api.deepseek.com/user/balance" "$ANTHROPIC_API_KEY" \
    | \grep -o '"total_balance":"[^"]*"' | cut -d'"' -f4)"
  [[ -n "$bal" ]] && _cl_log "Balance: \$$bal (deepseek)"
  _cl_log "Loaded: $ANTHROPIC_MODEL (api.deepseek.com)" \
          "— fast/subagent: $CLAUDE_CODE_SUBAGENT_MODEL"
}

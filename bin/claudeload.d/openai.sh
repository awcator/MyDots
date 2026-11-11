# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: OpenAI  (port 9084, litellm proxy)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"
  local port
  port="$(_cl_resolve_port "${OPENAI_PROXY_PORT:-}" 9084)" || return 1

  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    _cl_die "openai: OPENAI_API_KEY not found in env"
    return 1
  fi

  _cl_require_litellm "openai" || return 1
  _cl_use_endpoint "http://localhost:$port" key dummy || return 1

  local models_json
  models_json="$(_cl_fetch_json "https://api.openai.com/v1/models" "$OPENAI_API_KEY")"

  if [[ -z "$models_json" ]]; then
    _cl_die "openai: couldn't fetch models from API (is OPENAI_API_KEY valid?)"
    return 1
  fi

  # Generate litellm config from the live model catalog
  local config
  config="$(_cl_config_file "openai-$port-litellm.yaml")" || return 1
  python3 -c '
import json, sys
models = json.load(sys.stdin).get("data", [])
print("model_list:")
for m in models:
    mid = m.get("id", "")
    if any(x in mid for x in ["embedding", "whisper", "tts", "dall-e", "babbage", "davinci", "moderation", "text-search", "ada", "curie", "search", "similarity", "edit", "-transcribe", "image"]):
        continue
    print(f"  - model_name: {mid}")
    print(f"    litellm_params:")
    print(f"      model: openai/{mid}")
    print(f"      api_key: os.environ/OPENAI_API_KEY")
' <<< "$models_json" > "$config"

  _cl_spawn_proxy openai "$port" env OPENAI_API_KEY="$OPENAI_API_KEY" litellm --config "$config" --port "$port" || return 1

  local tsv
  tsv="$(_cl_models_to_tsv "$models_json" "${_CL_PY_SORT}"'
import json, os
models = json.loads(os.environ["_CL_JSON"]).get("data", [])
rows = []
for m in models:
    mid = m.get("id", "")
    if any(x in mid for x in ["embedding", "whisper", "tts", "dall-e", "babbage", "davinci", "moderation", "text-search", "ada", "curie", "search", "similarity", "edit", "-transcribe", "image"]):
        continue
    desc = "OpenAI Reasoning Model" if mid.startswith("o") else "OpenAI Model"
    rows.append((mid, desc, ""))
rows.sort(key=_nkey)
for mid, desc, status in rows:
    print("%s\t%s\t%s" % (mid, desc, status))
')"

  local base
  base="$(_cl_select_model "OpenAI models (:$port)" "$tsv" "$model_override")" \
    || return 1

  local fast
  fast="$(echo "$tsv" | cut -f1 | \grep -iE "mini|nano|flash|lite" | tail -1)"
  : "${fast:=$base}"

  _cl_export_models "$base" "$fast"
  _cl_log "Loaded: $ANTHROPIC_MODEL (openai, :$port)" \
          "— fast/subagent: $ANTHROPIC_SMALL_FAST_MODEL"
}

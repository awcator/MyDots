# shellcheck shell=bash
# Backend module for claudeload. Sourced by bin/claudeload.

# ══════════════════════════════════════════════════════════════════════════════
#  Backend: AI Studio  (port 9083, litellm proxy)
# ══════════════════════════════════════════════════════════════════════════════

_cl_backend_run() {
  local model_override="${1:-}"
  local port
  port="$(_cl_resolve_port "${AISTUDIO_PORT:-}" 9083)" || return 1

  if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    _cl_die "aistudio: GEMINI_API_KEY not found in env"
    return 1
  fi

  _cl_require_litellm "aistudio" || return 1
  _cl_use_endpoint "http://localhost:$port" key dummy || return 1

  local models_json
  models_json="$(_cl_fetch_json \
    "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY")"
  if [[ -z "$models_json" ]]; then
    _cl_die "aistudio: couldn't fetch models from API (is GEMINI_API_KEY valid?)"
    return 1
  fi

  # Generate litellm config from the live model catalog
  local config
  config="$(_cl_config_file "aistudio-$port-litellm.yaml")" || return 1
  python3 -c '
import json, sys
models = json.load(sys.stdin).get("models", [])
print("model_list:")
for m in models:
    name = m.get("name", "").replace("models/", "")
    print(f"  - model_name: {name}")
    print(f"    litellm_params:")
    print(f"      model: gemini/{name}")
    print(f"      api_key: os.environ/GEMINI_API_KEY")
' <<< "$models_json" > "$config"

  _cl_spawn_proxy aistudio "$port" litellm --config "$config" --port "$port" || return 1

  local tsv
  tsv="$(_cl_models_to_tsv "$models_json" "${_CL_PY_SORT}"'
import json, os
models = json.loads(os.environ["_CL_JSON"]).get("models", [])
rows = []
for m in models:
    mid = m.get("name", "").replace("models/", "")
    desc = m.get("displayName", "")
    if "generateContent" not in m.get("supportedGenerationMethods", []):
        continue
    rows.append((mid, desc, ""))
rows.sort(key=_nkey)
for mid, desc, status in rows:
    print("%s\t%s\t%s" % (mid, desc, status))
')"

  local base
  base="$(_cl_select_model "Google AI Studio models (:$port)" "$tsv" "$model_override")" \
    || return 1

  local fast
  fast="$(echo "$tsv" | cut -f1 \
    | \grep -i flash | \grep -viE 'preview|lite|tts|image|transcribe|omni|latest|robotics' | tail -1)"
  : "${fast:=$base}"

  _cl_export_models "$base" "$fast"
  _cl_log "Loaded: $ANTHROPIC_MODEL (aistudio, :$port)" \
          "— fast/subagent: $ANTHROPIC_SMALL_FAST_MODEL"
}

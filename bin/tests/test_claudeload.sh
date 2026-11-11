#!/bin/bash
# test_claudeload.sh — exhaustively test all backend × model combinations
# Outputs TSV: backend, base_model, OPUS, SONNET, HAIKU, FAST, SUBAGENT, effort, verdict

CL="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../claudeload"
OUT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/model_combinations.tsv"
MYDOTS_ROOT="$(dirname "$(dirname "$(readlink -f "$CL")")")"

printf "BACKEND\tBASE\tOPUS\tSONNET\tHAIKU\tFAST\tSUBAGENT\tEFFORT\tVERDICT\n" > "$OUT"

test_combo() {
  local backend="$1" model="$2"

  # Run in a subshell so exports don't leak back, capture the pipe-delimited output
  local result
  result="$(
    export CLAUDELOAD_QUIET=1
    # Simulate a prior DeepSeek selection. Profiles must not inherit its
    # low-effort setting unless they explicitly choose it themselves.
    export CLAUDE_CODE_EFFORT_LEVEL=low
    source "$CL" "$backend" "$model" 2>/dev/null
    printf '%s|%s|%s|%s|%s|%s|%s' \
      "$ANTHROPIC_MODEL" \
      "$ANTHROPIC_DEFAULT_OPUS_MODEL" \
      "$ANTHROPIC_DEFAULT_SONNET_MODEL" \
      "$ANTHROPIC_DEFAULT_HAIKU_MODEL" \
      "$ANTHROPIC_SMALL_FAST_MODEL" \
      "$CLAUDE_CODE_SUBAGENT_MODEL" \
      "${CLAUDE_CODE_EFFORT_LEVEL:-}"
  )"

  local base opus sonnet haiku fast subagent effort
  IFS='|' read -r base opus sonnet haiku fast subagent effort <<< "$result"

  # Verdict logic
  local verdict="OK"
  if [[ -z "$base" ]]; then
    verdict="FAIL:no_base"
  elif [[ "$base" != "$model" ]]; then
    verdict="FAIL:base_mismatch($base)"
  elif [[ "$haiku" == "$base" && ( "$base" == *opus* || "$base" == *pro* ) ]]; then
    verdict="WARN:haiku=expensive_base"
  elif [[ "$sonnet" == *copilot* ]]; then
    verdict="WARN:sonnet_is_copilot"
  elif [[ "$haiku" == *omni* ]]; then
    verdict="WARN:haiku_is_omni"
  elif [[ "$haiku" == *embed* || "$haiku" == *trajectory* ]]; then
    verdict="FAIL:haiku_not_gen_model"
  elif [[ "$subagent" != "$fast" ]]; then
    verdict="WARN:subagent≠fast"
  elif [[ "$backend" == "codexproxy" && "$sonnet" != "gpt-5.6-terra" ]]; then
    verdict="FAIL:codex_sonnet_not_terra($sonnet)"
  elif [[ "$backend" == "codexproxy" && "$fast" != "gpt-5.6-luna" ]]; then
    verdict="FAIL:codex_fast_not_luna($fast)"
  elif [[ "$backend" == "codexproxy" && -n "$effort" ]]; then
    verdict="FAIL:codex_inherited_effort($effort)"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$backend" "$model" "$opus" "$sonnet" "$haiku" "$fast" "$subagent" "$effort" "$verdict" >> "$OUT"

  # One-line terminal output
  local icon="✅"
  [[ "$verdict" == WARN* ]] && icon="⚠️"
  [[ "$verdict" == FAIL* ]] && icon="❌"
  printf "  %s %-12s %-38s son=%-28s hku=%-28s %s\n" \
    "$icon" "$backend" "$model" "$sonnet" "$haiku" "$verdict"
}

echo "═══ Gathering live model lists ═══"
echo ""

# ── Copilot (:4141) ──
if curl -sf http://localhost:4141/v1/models >/dev/null 2>&1; then
  echo "▶ COPILOT (:4141)"
  mapfile -t MODELS < <(curl -sf http://localhost:4141/v1/models 2>/dev/null \
    | grep -o '"id":"[^"]*"' | cut -d'"' -f4 \
    | sort -u -V)
  echo "  ${#MODELS[@]} models"
  for m in "${MODELS[@]}"; do test_combo copilot "$m"; done
  echo ""
else
  echo "⏭ COPILOT: port 4141 down"
fi

# ── DeepSeek (API) ──
if [[ -n "${DEEPSEEK_KEY:-}" ]]; then
  echo "▶ DEEPSEEK (api.deepseek.com)"
  mapfile -t MODELS < <(curl -sf https://api.deepseek.com/models \
    -H "Authorization: Bearer $DEEPSEEK_KEY" 2>/dev/null \
    | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sort -u -V)
  echo "  ${#MODELS[@]} models"
  for m in "${MODELS[@]}"; do test_combo deepseek "$m"; done
  echo ""
else
  echo "⏭ DEEPSEEK: DEEPSEEK_KEY not set"
fi

# ── Antigravity (:9080) ──
if curl -sf http://localhost:9080/v1/models >/dev/null 2>&1; then
  echo "▶ ANTIGRAVITY (:9080)"
  mapfile -t MODELS < <(curl -sf http://localhost:9080/v1/models 2>/dev/null \
    | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sort -u -V)
  echo "  ${#MODELS[@]} models"
  for m in "${MODELS[@]}"; do test_combo antigravity "$m"; done
  echo ""
else
  echo "⏭ ANTIGRAVITY: port 9080 down"
fi

# ── Devin proxy ──
DEVIN_TEST_URL="${DEVIN_PROXY_BASE_URL:-http://127.0.0.1:${DEVIN_PROXY_PORT:-3003}}"
DEVIN_TEST_KEY="${DEVIN_PROXY_API_KEY:-${API_KEY:-dummy}}"
if curl -sf -H "Authorization: Bearer $DEVIN_TEST_KEY" "$DEVIN_TEST_URL/v1/models" >/dev/null 2>&1; then
  echo "▶ DEVIN ($DEVIN_TEST_URL)"
  mapfile -t MODELS < <(curl -sf -H "Authorization: Bearer $DEVIN_TEST_KEY" "$DEVIN_TEST_URL/v1/models" \
    | python3 -c 'import json,sys
for model in json.load(sys.stdin).get("data", []):
    if model.get("id"): print(model["id"])
' | sort -u -V)
  echo "  ${#MODELS[@]} models"
  for m in "${MODELS[@]}"; do test_combo devin "$m"; done
  echo ""
else
  echo "⏭ DEVIN: proxy unavailable at $DEVIN_TEST_URL"
fi

# ── Codex Proxy (:8081) ──
CODEX_PROXY_BASE_URL="${CODEX_PROXY_BASE_URL:-http://127.0.0.1:${CODEX_PROXY_PORT:-8081}}"
CODEX_PROXY_KEY="${CODEX_PROXY_API_KEY:-}"
CODEX_PROXY_CONFIG="${CODEX_PROXY_CONFIG:-$(dirname "$MYDOTS_ROOT")/codex-proxy/data/local.yaml}"
if [[ -z "$CODEX_PROXY_KEY" && -r "$CODEX_PROXY_CONFIG" ]]; then
  CODEX_PROXY_KEY="$(sed -n 's/^[[:space:]]*proxy_api_key:[[:space:]]*//p' "$CODEX_PROXY_CONFIG" | head -n 1)"
  CODEX_PROXY_KEY="${CODEX_PROXY_KEY#\"}"; CODEX_PROXY_KEY="${CODEX_PROXY_KEY%\"}"
  CODEX_PROXY_KEY="${CODEX_PROXY_KEY#\'}"; CODEX_PROXY_KEY="${CODEX_PROXY_KEY%\'}"
fi
if [[ -n "$CODEX_PROXY_KEY" ]] && curl -sf -H "Authorization: Bearer $CODEX_PROXY_KEY" "$CODEX_PROXY_BASE_URL/v1/models" >/dev/null 2>&1; then
  echo "▶ CODEX PROXY ($CODEX_PROXY_BASE_URL)"
  mapfile -t MODELS < <(curl -sf -H "Authorization: Bearer $CODEX_PROXY_KEY" "$CODEX_PROXY_BASE_URL/v1/models" 2>/dev/null \
    | python3 -c 'import json,sys
for model in json.load(sys.stdin).get("data", []):
    if model.get("id"): print(model["id"])
' | sort -u -V)
  echo "  ${#MODELS[@]} models"
  for m in "${MODELS[@]}"; do test_combo codexproxy "$m"; done
  echo ""
else
  echo "⏭ CODEX PROXY: unavailable at $CODEX_PROXY_BASE_URL or API key not configured"
fi

echo ""
echo "═══ Results: $OUT ═══"

# Summary
total=$(tail -n +2 "$OUT" | wc -l)
ok=$(grep -cP '\tOK$' "$OUT" || true)
warn=$(grep -c 'WARN' "$OUT" || true)
fail=$(grep -c 'FAIL' "$OUT" || true)
echo "Total: $total | ✅ OK: $ok | ⚠ WARN: $warn | ❌ FAIL: $fail"

if [[ $warn -gt 0 || $fail -gt 0 ]]; then
  echo ""
  echo "═══ Issues ═══"
  awk -F '\t' '$9 ~ /WARN|FAIL/ { printf "  %-12s %-38s → %s\n", $1, $2, $9 }' "$OUT"
fi

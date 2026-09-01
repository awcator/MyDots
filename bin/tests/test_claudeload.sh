#!/bin/bash
# test_claudeload.sh — exhaustively test all backend × model combinations
# Outputs TSV: backend, base_model, OPUS, SONNET, HAIKU, FAST, SUBAGENT, verdict

CL="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../claudeload"
OUT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/model_combinations.tsv"

printf "BACKEND\tBASE\tOPUS\tSONNET\tHAIKU\tFAST\tSUBAGENT\tVERDICT\n" > "$OUT"

test_combo() {
  local backend="$1" model="$2"

  # Run in a subshell so exports don't leak back, capture the pipe-delimited output
  local result
  result="$(
    export CLAUDELOAD_QUIET=1
    source "$CL" "$backend" "$model" 2>/dev/null
    printf '%s|%s|%s|%s|%s|%s' \
      "$ANTHROPIC_MODEL" \
      "$ANTHROPIC_DEFAULT_OPUS_MODEL" \
      "$ANTHROPIC_DEFAULT_SONNET_MODEL" \
      "$ANTHROPIC_DEFAULT_HAIKU_MODEL" \
      "$ANTHROPIC_SMALL_FAST_MODEL" \
      "$CLAUDE_CODE_SUBAGENT_MODEL"
  )"

  local base opus sonnet haiku fast subagent
  IFS='|' read -r base opus sonnet haiku fast subagent <<< "$result"

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
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$backend" "$model" "$opus" "$sonnet" "$haiku" "$fast" "$subagent" "$verdict" >> "$OUT"

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
    | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sort -u -V)
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

# ── AI Studio (:9083) ──
if curl -sf http://localhost:9083/health >/dev/null 2>&1 || curl -sf http://localhost:9083/v1/models >/dev/null 2>&1; then
  echo "▶ AI STUDIO (:9083)"
  mapfile -t MODELS < <(curl -sf "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY" 2>/dev/null \
    | python3 -c 'import json,sys
for m in json.load(sys.stdin).get("models",[]):
    mid=m["name"].replace("models/","")
    if "generateContent" in m.get("supportedGenerationMethods",[]):
        print(mid)
' 2>/dev/null | sort -V)
  echo "  ${#MODELS[@]} generation models"
  for m in "${MODELS[@]}"; do test_combo aistudio "$m"; done
  echo ""
else
  echo "⏭ AI STUDIO: port 9083 down"
fi

# ── Windsurf (:4142) ──
if curl -sf http://localhost:4142/v1/models >/dev/null 2>&1; then
  echo "▶ WINDSURF (:4142)"
  if command -v claudecredits >/dev/null 2>&1; then
    mapfile -t MODELS < <(claudecredits --raw 2>/dev/null | grep $'\t' | cut -f1)
    echo "  ${#MODELS[@]} models"
    for m in "${MODELS[@]}"; do test_combo windsurf "$m"; done
  fi
  echo ""
else
  echo "⏭ WINDSURF: port 4142 down"
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
  grep -E 'WARN|FAIL' "$OUT" | while IFS=$'\t' read -r be ba op so ha fa su ve; do
    printf "  %-12s %-38s → %s\n" "$be" "$ba" "$ve"
  done
fi

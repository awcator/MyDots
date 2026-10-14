#!/bin/sh
set -e
DATA_DIR="/run/media/awcator/Lindos/Strata-data"
MODELS_DIR="$DATA_DIR/models/uncensored-ud-q4_k_xl"
PACKS_DIR="$DATA_DIR/packs/uncensored-ud-q4_k_xl"

echo "=== Running Strata setup for Uncensored UD-Q4_K_XL ==="
./setup.sh \
  --data-dir "$DATA_DIR" \
  --gguf-dir "$MODELS_DIR" \
  --family unsloth \
  --model UD-Q4_K_XL \
  --context 200000 \
  --vision cpu \
  --vision-tokens 16384 \
  --kv-streaming auto \
  --parallel 1 \
  --build \
  --yes \
  --no-start

echo "=== Generating 5-shard pack with iq_pack.py ==="
.venv/bin/python tools/iq_pack.py \
  --gguf "$MODELS_DIR/Qwen3.8-Flash-Next-Uncensored-Gufo-00001-of-00005.gguf" \
  --out "$PACKS_DIR" \
  --compat-bf16

echo "=== Done! Start server with: ==="
echo ".venv/bin/python serve/server.py --engine strata --config strata-uncensored-ud-q4_k_xl.json --port 8090"

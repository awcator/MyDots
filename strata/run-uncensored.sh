#!/bin/sh
cd "$(dirname "$0")"
exec .venv/bin/python serve/server.py --engine strata --config strata-uncensored-ud-q4_k_xl.json --port 8090 "$@"

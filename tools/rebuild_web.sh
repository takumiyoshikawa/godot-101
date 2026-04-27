#!/usr/bin/env bash
# Re-run the full headless pipeline: smoke -> tests -> web export.
# Usage: tools/rebuild_web.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p logs build/web

echo "==> smoke"
godot --headless --path . --quit-after 60 2>&1 | tee logs/smoke.log

echo "==> tests"
godot --headless --path . --script res://tools/tests/run_tests.gd 2>&1 | tee logs/tests.log

echo "==> export Web"
godot --headless --path . --export-release "Web" build/web/index.html 2>&1 | tee logs/export_web.log

echo "==> done. open build/web/index.html via:"
echo "   python3 -m http.server --directory build/web 8000"

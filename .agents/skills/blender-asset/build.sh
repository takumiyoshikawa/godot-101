#!/usr/bin/env bash
# Headless Blender asset build.
#
# Run from the project root:
#   .agents/skills/blender-asset/build.sh assets/modeling/<name>.py [extra args]
#
# Output GLB: <project>/assets/models/<basename>.glb
# Log:        <project>/logs/build_asset_<basename>.log

set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: .agents/skills/blender-asset/build.sh <script-path> [extra args]" >&2
	exit 64
fi

SCRIPT_PATH="$1"
shift

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SCRIPTS="$SKILL_DIR/scripts"

PROJECT_DIR="$(pwd)"
if [ ! -d "$PROJECT_DIR/assets/modeling" ]; then
	echo "ERROR: must run from project root ('assets/modeling/' not found in PWD: $PROJECT_DIR)" >&2
	exit 1
fi

if [[ "$SCRIPT_PATH" != /* ]]; then
	SCRIPT_PATH="$PROJECT_DIR/$SCRIPT_PATH"
fi
if [ ! -f "$SCRIPT_PATH" ]; then
	echo "ERROR: script not found: $SCRIPT_PATH" >&2
	exit 1
fi

if ! command -v blender >/dev/null 2>&1; then
	echo "ERROR: 'blender' not found in PATH" >&2
	exit 1
fi

NAME="$(basename "$SCRIPT_PATH" .py)"
OUT_PATH="$PROJECT_DIR/assets/models/$NAME.glb"
LOG="$PROJECT_DIR/logs/build_asset_$NAME.log"

mkdir -p "$PROJECT_DIR/assets/models" "$PROJECT_DIR/logs"

echo "==> blender-asset: $NAME -> assets/models/$NAME.glb"

blender --background \
	--python-expr "import sys; sys.path.insert(0, r'$SKILL_SCRIPTS')" \
	--python "$SCRIPT_PATH" \
	-- --out "$OUT_PATH" "$@" \
	2>&1 | tee "$LOG"

if [ ! -f "$OUT_PATH" ]; then
	echo "ERROR: expected output not produced: $OUT_PATH" >&2
	exit 1
fi

SIZE="$(du -h "$OUT_PATH" | cut -f1)"
echo "==> wrote $OUT_PATH ($SIZE)"

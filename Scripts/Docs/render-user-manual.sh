#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON_BIN="${BATTMAN_DOCS_PYTHON:-python3}"
OUTPUT_DIR="${1:-}"
DOCS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/battman-user-manual.XXXXXX")"
trap 'rm -rf "$DOCS_TMP"' EXIT

if [[ -z "$OUTPUT_DIR" ]]; then
	OUTPUT_DIR="$DOCS_TMP/site"
elif [[ -e "$OUTPUT_DIR" ]]; then
	echo "The manual output must be a new path: $OUTPUT_DIR" >&2
	exit 1
fi

"$PYTHON_BIN" -m venv "$DOCS_TMP/venv"
"$DOCS_TMP/venv/bin/python" -m pip install --disable-pip-version-check --quiet \
	--require-hashes -r "$REPO_ROOT/Requirements/docs.txt"
"$DOCS_TMP/venv/bin/python" -m pip install --disable-pip-version-check --quiet \
	--no-deps "$REPO_ROOT/docs/battman-user-manuals"
"$DOCS_TMP/venv/bin/mkdocs" build --strict --clean \
	-f "$REPO_ROOT/docs/battman-user-manuals/mkdocs.yml" -d "$OUTPUT_DIR"

for relative in \
	index.html \
	features/analytics/index.html \
	features/plugins/index.html \
	zh/features/analytics/index.html \
	zh/features/plugins/index.html \
	zh_TW/features/analytics/index.html \
	zh_TW/features/plugins/index.html \
	search/search_index.json; do
	test -s "$OUTPUT_DIR/$relative"
done

grep -q 'Diagnostics and support' "$OUTPUT_DIR/features/plugins/index.html"
grep -q '诊断与支持' "$OUTPUT_DIR/zh/features/plugins/index.html"
grep -q '診斷與支援' "$OUTPUT_DIR/zh_TW/features/plugins/index.html"

printf '%s\n' "Rendered multilingual Battman user manual: $OUTPUT_DIR"

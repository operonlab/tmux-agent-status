#!/usr/bin/env bash
# classify.sh — unit test for scripts/classify.awk.
#
# Feeds each fixture footer to classify.awk on stdin with AISTATUS_CMD /
# AISTATUS_TITLE supplied via the environment (exactly how status.sh calls it),
# and asserts the three-state output. This test is platform-neutral: it only
# needs awk + LC_ALL=C byte matching, so it runs on both macOS and Linux.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
AWK_FILE="${REPO_DIR}/scripts/classify.awk"
FIX="${SCRIPT_DIR}/fixtures"
AWK_BIN="$(command -v awk 2>/dev/null || echo /usr/bin/awk)"

FAILS=0
classify() {
	# classify <cmd> <title> <fixture-file> -> BUSY|WAIT|IDLE|""
	AISTATUS_CMD="$1" AISTATUS_TITLE="$2" LC_ALL=C "$AWK_BIN" -f "$AWK_FILE" < "$3"
}
expect() {
	# expect <label> <expected> <cmd> <title> <fixture>
	got=$(classify "$3" "$4" "$5")
	if [ "$got" = "$2" ]; then
		echo "  PASS: $1 -> $got"
	else
		echo "  FAIL: $1 — expected [$2] got [$got]"
		FAILS=$((FAILS + 1))
	fi
}

echo "classify.awk three-state assertions (awk: $AWK_BIN)"
expect "claude busy footer (esc to interrupt)" BUSY claude "" "${FIX}/claude-busy.txt"
expect "claude idle footer (empty prompt)"     IDLE claude "" "${FIX}/claude-idle.txt"
expect "claude wait footer (permission menu)"  WAIT claude "" "${FIX}/claude-wait.txt"

# a non-agent command must never light the capsule (empty output).
expect "non-agent command yields nothing"      "" bash "" "${FIX}/claude-busy.txt"

# the OSC title alone drives node/bun/deno and generic agents.
BRAILLE_TITLE=$(printf '\342\240\213 building')   # braille-prefixed spinner title
expect "node host-runtime, braille title = busy" BUSY node "$BRAILLE_TITLE" "${FIX}/claude-idle.txt"

echo ""
if [ "$FAILS" -eq 0 ]; then
	echo "ALL CLASSIFY CHECKS PASSED"
	exit 0
else
	echo "CLASSIFY FAILURES: $FAILS"
	exit 1
fi

#!/usr/bin/env bash
# debounce.sh — proves the two execution-discipline additions in status.sh:
#   1. DEBOUNCE  — an unchanged pane situation serves the cached capsule and
#                  skips the capture+classify pass (asserted with a side-effect
#                  counter, never by timing); a changed situation recomputes.
#   2. FAIL-SOFT — a failed probe keeps the last-good capsule instead of
#                  blanking it.
#
# HARD RULE (same as smoke.sh): never touch the caller's live tmux server. We
# `unset TMUX` up front and drive a private `-L <unique-socket>` server through a
# PATH shim that status.sh sees as TMUX_BIN. The socket is killed and every temp
# path removed on exit.

set -u
unset TMUX   # detach from any inherited server before we touch tmux at all

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATUS="${REPO_DIR}/scripts/status.sh"

REAL_TMUX="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
SOCK="tasdeb_$$"

SHIMDIR="$(mktemp -d "${TMPDIR:-/tmp}/tas-debounce.XXXXXX")"
# good shim: pin the private socket. broken shim: always fail (forces a probe
# error so we can exercise the fail-soft path without killing the real server).
printf '#!/bin/sh\nexec "%s" -L "%s" "$@"\n' "$REAL_TMUX" "$SOCK" > "${SHIMDIR}/tmux"
printf '#!/bin/sh\nexit 1\n' > "${SHIMDIR}/brokentmux"
chmod +x "${SHIMDIR}/tmux" "${SHIMDIR}/brokentmux"

GOOD_TMUX="${SHIMDIR}/tmux"
BROKEN_TMUX="${SHIMDIR}/brokentmux"
export TMUX_BIN="$GOOD_TMUX"

STATE_DIR="${TMUX_TMPDIR:-/tmp}/tmux-agent-status-$(id -u 2>/dev/null || echo 0)"
CACHE="${STATE_DIR}/status.txt"
SOCK_PATH="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u 2>/dev/null || echo 0)/${SOCK}"
COUNTER="${SHIMDIR}/scan.count"

FAILS=0
cleanup() {
	"$GOOD_TMUX" kill-server 2>/dev/null || true
	rm -f "$SOCK_PATH" 2>/dev/null || true
	rm -rf "$SHIMDIR" 2>/dev/null || true
	# specific per-uid subpath only (never a bare /tmp or wildcard)
	rm -rf "$STATE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

check() {
	# check <label> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "  PASS: $1 (= $3)"
	else
		echo "  FAIL: $1 — expected [$2] got [$3]"
		FAILS=$((FAILS + 1))
	fi
}
check_contains() {
	case "$3" in
		*"$2"*) echo "  PASS: $1 (contains [$2])" ;;
		*) echo "  FAIL: $1 — [$3] does not contain [$2]"; FAILS=$((FAILS + 1)) ;;
	esac
}
count() { wc -c < "$COUNTER" 2>/dev/null | tr -d ' '; }

echo "tmux version: $("$GOOD_TMUX" -V)"
rm -rf "$STATE_DIR" 2>/dev/null || true

# Static pane situation: a holding `sleep` so nothing (command/path/title)
# mutates between refreshes and the signature is deterministic.
"$GOOD_TMUX" -f /dev/null new-session -d -s main -x 120 -y 24 "exec sleep 1000000"
sleep 0.3
"$GOOD_TMUX" set-option -g @agent-status-provider ''   # force the local (debounced) path
"$GOOD_TMUX" set-option -g @agent-status-icons nerd

: > "$COUNTER"
export AISTATUS_SCAN_COUNTER="$COUNTER"

# ══════════ Debounce ══════════
echo "── Debounce: unchanged situation serves cache; a change recomputes"
"$STATUS" __refresh__                       # situation is new (no cache) -> scan
check "first refresh runs the scan" "1" "$(count)"

"$STATUS" __refresh__                       # identical situation -> debounced
check "unchanged situation is debounced (no re-classify)" "1" "$(count)"

"$GOOD_TMUX" new-window -d -t main: "exec sleep 1000000"   # add a pane -> new sig
sleep 0.3
"$STATUS" __refresh__                        # situation changed -> recompute
check "changed situation recomputes" "2" "$(count)"

"$STATUS" __refresh__                        # identical again -> debounced
check "unchanged-again situation is debounced" "2" "$(count)"

# ══════════ Fail-soft ══════════
echo "── Fail-soft: a failed probe keeps the last-good capsule"
unset AISTATUS_SCAN_COUNTER
# seed a known-good capsule via the provider path (compiler-independent).
"$GOOD_TMUX" set-option -g @agent-status-provider 'printf "{\"busy\":7,\"wait\":0,\"idle\":0}"'
"$STATUS" __refresh__
last_good=$(cat "$CACHE" 2>/dev/null)
check_contains "seeded last-good capsule carries busy 7" "7" "$last_good"

# clear the provider, then force the probe to fail by pointing at the broken tmux.
"$GOOD_TMUX" set-option -g @agent-status-provider ''
export TMUX_BIN="$BROKEN_TMUX"
"$STATUS" __refresh__                         # list-panes fails -> must NOT write
after=$(cat "$CACHE" 2>/dev/null)
export TMUX_BIN="$GOOD_TMUX"
check "failed probe retains last-good (not blanked)" "$last_good" "$after"

echo ""
if [ "$FAILS" -eq 0 ]; then
	echo "ALL DEBOUNCE CHECKS PASSED"
	exit 0
else
	echo "DEBOUNCE FAILURES: $FAILS"
	exit 1
fi

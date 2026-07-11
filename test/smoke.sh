#!/usr/bin/env bash
# smoke.sh — headless functional test for tmux-agent-status (macOS).
#
# HARD RULE: never touches the default tmux server. Every tmux command runs
# through a PATH shim that pins a private `-L` socket, and the shim is what
# status.sh sees as TMUX_BIN. The socket is killed and the shim removed on exit.
#
# Scenario A builds a REAL pane whose pane_current_command reads `claude`. On
# macOS a copied system binary is SIGKILLed (broken signature) and a symlink
# resolves comm to its target, so the only faithful way to forge the command
# name is a tiny locally-compiled binary (a fresh compile gets a valid adhoc
# signature). When no C compiler is present that one scenario is SKIPPED, never
# failed — the non-blocking contract (the SPEC-critical part) is proven
# separately in Scenario B via the provider path, which needs no compiler.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATUS="${REPO_DIR}/scripts/status.sh"
FIX="${SCRIPT_DIR}/fixtures"

# timing budget for the non-blocking assertions; override on a loaded CI runner.
SMOKE_MAX_MS="${SMOKE_MAX_MS:-100}"

# Locate the real tmux BEFORE we shadow it on PATH.
REAL_TMUX="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
SOCK="tasplug_$$"

SHIMDIR="$(mktemp -d "${TMPDIR:-/tmp}/tas-smoke.XXXXXX")"
# tmux shim: force the private socket.
printf '#!/bin/sh\nexec "%s" -L "%s" "$@"\n' "$REAL_TMUX" "$SOCK" > "${SHIMDIR}/tmux"
chmod +x "${SHIMDIR}/tmux"

export TMUX_BIN="${SHIMDIR}/tmux"
TM="${SHIMDIR}/tmux"

# private state dir status.sh will use (kept isolated per-uid under tmp).
STATE_DIR="${TMUX_TMPDIR:-/tmp}/tmux-agent-status-$(id -u 2>/dev/null || echo 0)"

# ── a genuinely-named agent binary (see the header note on why) ──────────────
CC="$(command -v cc 2>/dev/null || command -v clang 2>/dev/null || true)"
compile_agent() {
	# compile_agent <name> — build a native binary that prints its file arg
	# then blocks in pause() (a single process, so pane_current_command stays
	# <name> instead of dropping to a `sleep`/`sh` child). Returns non-zero
	# when no compiler is available.
	[ -n "$CC" ] || return 1
	if [ ! -f "${SHIMDIR}/agent.c" ]; then
		cat > "${SHIMDIR}/agent.c" <<'C'
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
	if (argc > 1) {
		FILE *f = fopen(argv[1], "r");
		char b[4096];
		size_t k;
		if (f) {
			while ((k = fread(b, 1, sizeof b, f)) > 0) fwrite(b, 1, k, stdout);
			fclose(f);
		}
		fflush(stdout);
	}
	for (;;) pause();
	return 0;
}
C
	fi
	"$CC" -o "${SHIMDIR}/$1" "${SHIMDIR}/agent.c" 2>/dev/null
}

FAILS=0
# where tmux -L places the private socket, so cleanup can unlink the dead inode
# kill-server may leave behind (leaving no socket cruft in the shared tmpdir).
SOCK_PATH="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u 2>/dev/null || echo 0)/${SOCK}"
cleanup() {
	"$TM" kill-server 2>/dev/null || true
	rm -f "$SOCK_PATH" 2>/dev/null || true
	rm -rf "$SHIMDIR" 2>/dev/null || true
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
	# check_contains <label> <needle> <haystack>
	case "$3" in
		*"$2"*) echo "  PASS: $1 (contains [$2])" ;;
		*) echo "  FAIL: $1 — [$3] does not contain [$2]"; FAILS=$((FAILS + 1)) ;;
	esac
}
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000' 2>/dev/null || echo 0; }

BUSY_GLYPH=$(printf '\357\201\213')

echo "tmux version: $("$TM" -V)"
# Short pane on purpose: local_scan captures `... | tail -30`, mirroring how a
# real agent's footer sits at the bottom of the screen. A 24-row pane keeps the
# fixture footer inside that 30-line capture window.
"$TM" -f /dev/null new-session -d -s main -x 120 -y 24
sleep 0.2

# ══════════ Scenario A: local scan classifies a real busy claude pane ══════════
echo "── Scenario A: local fallback scan sees one busy claude pane"
if compile_agent claude; then
	"$TM" new-window -d -t main:1 "exec '${SHIMDIR}/claude' '${FIX}/claude-busy.txt'"
	sleep 0.6
	scanned_cmd=$("$TM" list-panes -a -F '#{pane_current_command}' | grep -c '^claude$')
	check "a claude pane exists (pane_current_command)" "1" "$scanned_cmd"
	"$STATUS" __refresh__          # synchronous refresh -> deterministic cache
	cache_content=$(cat "${STATE_DIR}/status.txt" 2>/dev/null)
	check_contains "cache shows a busy count of 1" "1" "$cache_content"
	check_contains "cache carries the nerd busy glyph" "$BUSY_GLYPH" "$cache_content"
	HAVE_BUSY_PANE=1
else
	echo "  SKIP: no C compiler found — cannot forge pane_current_command=claude"
	HAVE_BUSY_PANE=0
fi

# ══════════ Scenario B: non-blocking contract (cold + warm) ══════════
echo "── Scenario B: #() stays non-blocking (<${SMOKE_MAX_MS}ms) cold and warm"
rm -f "${STATE_DIR}/status.txt"    # cold cache
t0=$(now_ms); "$STATUS" >/dev/null 2>&1; t1=$(now_ms)
cold_ms=$((t1 - t0))
check "cold call under ${SMOKE_MAX_MS}ms" "yes" "$([ "$cold_ms" -lt "$SMOKE_MAX_MS" ] && echo yes || echo "no(${cold_ms}ms)")"
# warm the cache deterministically via the provider path (compiler-independent).
"$TM" set-option -g @agent-status-provider 'printf "{\"busy\":1,\"wait\":0,\"idle\":0}"'
"$STATUS" __refresh__
check "cache file was generated" "yes" "$([ -f "${STATE_DIR}/status.txt" ] && echo yes || echo no)"
t0=$(now_ms); out2=$("$STATUS" 2>/dev/null); t1=$(now_ms)
warm_ms=$((t1 - t0))
check "warm second call under ${SMOKE_MAX_MS}ms" "yes" "$([ "$warm_ms" -lt "$SMOKE_MAX_MS" ] && echo yes || echo "no(${warm_ms}ms)")"
check_contains "warm call output matches cache (busy 1)" "1" "$out2"
"$TM" set-option -g @agent-status-provider ''    # reset for later scenarios
echo "     (cold=${cold_ms}ms warm=${warm_ms}ms)"

# ══════════ Scenario C: provider is trusted over local scan ══════════
echo "── Scenario C: @agent-status-provider output is trusted"
"$TM" set-option -g @agent-status-provider 'printf "{\"busy\":2,\"wait\":1,\"idle\":3}"'
"$STATUS" __refresh__
prov_content=$(cat "${STATE_DIR}/status.txt" 2>/dev/null)
check_contains "provider busy count (2) rendered" "2" "$prov_content"
check_contains "provider wait count (1) rendered" "1" "$prov_content"
check_contains "provider idle count (3) rendered" "3" "$prov_content"

# ══════════ Scenario D: ascii icons ══════════
echo "── Scenario D: @agent-status-icons ascii uses [B]/[W]/[I]"
"$TM" set-option -g @agent-status-icons ascii
"$STATUS" __refresh__
ascii_content=$(cat "${STATE_DIR}/status.txt" 2>/dev/null)
check_contains "ascii busy marker" "[B]" "$ascii_content"
check_contains "ascii wait marker" "[W]" "$ascii_content"
check_contains "ascii idle marker" "[I]" "$ascii_content"
"$TM" set-option -g @agent-status-icons nerd

# ══════════ Scenario E: provider zero counts -> empty capsule ══════════
echo "── Scenario E: all-zero counts collapse the capsule to empty"
"$TM" set-option -g @agent-status-provider 'printf "{\"busy\":0,\"wait\":0,\"idle\":0}"'
"$STATUS" __refresh__
zero_content=$(cat "${STATE_DIR}/status.txt" 2>/dev/null)
check "empty capsule when nothing is running" "" "$zero_content"

# ══════════ Scenario F: entrypoint interpolates, teardown restores ══════════
echo "── Scenario F: agent-status.tmux interpolates #{agent_status}, teardown restores it"
"$TM" set-option -g @agent-status-provider ''    # clear provider for clarity
"$TM" set-option -g status-right ' cpu #{agent_status} clock '
"$TM" run-shell "'${REPO_DIR}/agent-status.tmux'"
sleep 0.2
sr_after=$("$TM" show-option -gqv status-right)
check_contains "placeholder replaced by status.sh call" "status.sh)" "$sr_after"
case "$sr_after" in
	*'#{agent_status}'*) echo "  FAIL: placeholder still present after interpolation"; FAILS=$((FAILS + 1)) ;;
	*) echo "  PASS: raw placeholder consumed" ;;
esac
"$TM" run-shell "'${REPO_DIR}/scripts/teardown.sh'"
sleep 0.2
sr_restored=$("$TM" show-option -gqv status-right)
check_contains "teardown restores #{agent_status}" '#{agent_status}' "$sr_restored"
check "teardown removes the state dir" "gone" "$([ -d "$STATE_DIR" ] && echo present || echo gone)"

echo ""
[ "$HAVE_BUSY_PANE" -eq 0 ] && echo "(note: Scenario A skipped — no compiler)"
if [ "$FAILS" -eq 0 ]; then
	echo "ALL SMOKE CHECKS PASSED"
	exit 0
else
	echo "SMOKE FAILURES: $FAILS"
	exit 1
fi

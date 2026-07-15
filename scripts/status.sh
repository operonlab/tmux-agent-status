#!/usr/bin/env bash
# status.sh — tmux status-line capsule showing how many local AI-CLI panes are
# busy / blocked / idle. Designed to be called from a status `#()`.
#
# NON-BLOCKING CONTRACT (the whole point): a status `#()` runs on every redraw,
# so it MUST return instantly. The foreground only reads a cache file. When the
# cache is older than the refresh interval it spawns ONE fully-detached
# background refresh (all three fds redirected, per the $() detach trap) and
# still returns the old cached value immediately. The capsule therefore lags by
# at most one interval and never stalls the status line. This is the exact
# range of the private origin script (ai-status.sh lines 164-219).
#
# It intentionally does NOT `set -e`: tmux treats any non-zero exit from a
# status `#()` as an error, and every helper here degrades to an empty string.

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CLASSIFY_AWK="${CURRENT_DIR}/classify.awk"
TAB=$(printf '\t')

# tmux binary. Default: whatever `tmux` resolves to — inside a status `#()` the
# TMUX env var is set, so a bare `tmux` talks to the right server. Override with
# TMUX_BIN for isolated testing against a private `-L` socket (a PATH shim).
# NB: never call this TMUX — that is tmux's own reserved server-locator var;
# overwriting it makes list-panes / capture-pane fail to find the server.
TMUX_BIN="${TMUX_BIN:-$(command -v tmux 2>/dev/null || echo tmux)}"

# State lives under a private, 0700, per-uid dir. We refuse to write through a
# symlink so a pre-planted symlink cannot redirect our writes.
STATE_DIR="${TMUX_TMPDIR:-/tmp}/tmux-agent-status-$(/usr/bin/id -u 2>/dev/null || echo 0)"
CACHE="${STATE_DIR}/status.txt"
LOCK="${STATE_DIR}/refresh.lock"
SIGFILE="${STATE_DIR}/situation.sig"

# ── option reader (bound to TMUX_BIN so isolated tests read the right server) ──
opt() {
	v=$("$TMUX_BIN" show-option -gqv "$1" 2>/dev/null)
	if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

file_mtime() {
	/usr/bin/stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# classify_one: printf '%s' "$text" | classify_one "$cmd" "$title" -> BUSY|WAIT|IDLE|""
# cmd/title go through the environment (ENVIRON in classify.awk); text via stdin.
# LC_ALL=C forces byte-wise substr/index so the UTF-8 octal patterns match.
classify_one() {
	AISTATUS_CMD="$1" AISTATUS_TITLE="$2" LC_ALL=C /usr/bin/awk -f "$CLASSIFY_AWK"
}

# ── local fallback scan: per pane capture footer -> classify -> tally ─────────
# NB: accumulate scan_* inside this same shell (no `list-panes | while … case`)
# — macOS /bin/sh is bash 3.2 and its $() parser mis-reads a `case` inside a
# command substitution as a syntax error. Kept as a plain for-loop on purpose.
local_scan() {
	# Test seam (mirrors the __refresh__ / TMUX_BIN seams already used by the
	# suite): when AISTATUS_SCAN_COUNTER names a file we append a byte each time
	# the expensive capture+classify pass actually runs, so a test can prove the
	# debounce short-circuit skipped it without resorting to timing.
	[ -n "${AISTATUS_SCAN_COUNTER:-}" ] && printf 'x' >> "$AISTATUS_SCAN_COUNTER" 2>/dev/null
	scan_busy=0; scan_wait=0; scan_idle=0
	# A failed list-panes (tmux gone / unreachable) returns non-zero so the
	# caller can tell a genuine "no agents => 0" apart from a probe failure and
	# keep the last-good capsule instead of blanking it (fail-soft).
	panes=$("$TMUX_BIN" list-panes -a -F "#{pane_id}${TAB}#{pane_current_command}${TAB}#{pane_title}" 2>/dev/null) || return 1
	OLDIFS=$IFS
	IFS='
'
	for line in $panes; do
		pid=${line%%"$TAB"*}
		rest=${line#*"$TAB"}
		cmd=${rest%%"$TAB"*}
		title=${rest#*"$TAB"}
		case "$cmd" in
			node|bun|deno)
				# host runtime: trust the OSC title only, never capture screen
				# text (a dev server's log must not light the agent capsule).
				text='' ;;
			claude|claude-code|codex|codex-*|gemini|aider|cursor|cursor-agent|agy|copilot|opencode|amp|droid|qwen|kimi|hermes|pi|grok|grok-*|[0-9]*.[0-9]*.[0-9]*)
				text=$("$TMUX_BIN" capture-pane -p -t "$pid" 2>/dev/null | /usr/bin/tail -30) ;;
			*) continue ;;
		esac
		v=$(printf '%s' "$text" | classify_one "$cmd" "$title")
		if [ "$v" = BUSY ]; then scan_busy=$((scan_busy + 1))
		elif [ "$v" = WAIT ]; then scan_wait=$((scan_wait + 1))
		elif [ "$v" = IDLE ]; then scan_idle=$((scan_idle + 1)); fi
	done
	IFS=$OLDIFS
	return 0
}

# ── provider: a user-configured external command (see @agent-status-provider) ──
# WARNING: this runs a command from your tmux.conf. Only set it to something you
# trust. Contract: it prints a single JSON object {"busy":N,"wait":N,"idle":N}
# to stdout. We bound it with `timeout` when available so a hung provider cannot
# pile up background refreshes; on timeout / failure we fall back to local_scan.
run_provider() {
	cmd="$1"
	if command -v timeout >/dev/null 2>&1; then
		timeout 3 /bin/sh -c "$cmd" 2>/dev/null
	elif command -v gtimeout >/dev/null 2>&1; then
		gtimeout 3 /bin/sh -c "$cmd" 2>/dev/null
	else
		/bin/sh -c "$cmd" 2>/dev/null
	fi
}

# parse_counts <json> -> "busy wait idle" (missing keys -> 0)
parse_counts() {
	printf '%s' "$1" | LC_ALL=C /usr/bin/awk '
	function ji(j,k,   re,m){re="\""k"\"[ \t]*:[ \t]*[0-9]+";if(match(j,re)){m=substr(j,RSTART,RLENGTH);sub(/^.*:[ \t]*/,"",m);return m+0}return 0}
	{ j=j $0 }
	END{ printf "%d %d %d\n", ji(j,"busy"), ji(j,"wait"), ji(j,"idle") }
	'
}

# render <busy> <wait> <idle> -> capsule string (empty when all zero)
render() {
	b=$1; w=$2; i=$3
	if [ "$b" -le 0 ] && [ "$w" -le 0 ] && [ "$i" -le 0 ]; then
		return 0
	fi

	icons=$(opt "@agent-status-icons" "nerd")
	if [ "$icons" = "ascii" ]; then
		IBUSY='[B]'; IBLOCK='[W]'; IIDLE='[I]'
	else
		IBUSY=$(printf '\357\201\213')   # F04B play  = busy   (burning tokens)
		IBLOCK=$(printf '\357\211\226')  # F256 hand  = blocked (needs a human)
		IIDLE=$(printf '\357\201\214')   # F04C pause = idle    (empty prompt)
	fi

	fmt=$(opt "@agent-status-format" "")
	if [ -n "$fmt" ]; then
		# advanced: substitute %B/%W/%I (icons) and %b/%w/%i (counts) verbatim.
		out=$fmt
		out=${out//%B/$IBUSY}; out=${out//%W/$IBLOCK}; out=${out//%I/$IIDLE}
		out=${out//%b/$b};     out=${out//%w/$w};      out=${out//%i/$i}
		printf '%s' "$out"
		return 0
	fi

	# default: show only the non-zero states, icon + count, joined by two spaces.
	val=''
	[ "$b" -gt 0 ] && val="$IBUSY  $b"
	[ "$w" -gt 0 ] && val="${val:+$val  }$IBLOCK  $w"
	[ "$i" -gt 0 ] && val="${val:+$val  }$IIDLE  $i"
	printf '%s' "$val"
}

# ── family execution-discipline template (borrowed & source-verified from
#    ndom91/tmux-ai-window-name) ────────────────────────────────────────────
# Model-agnostic plumbing for "don't block tmux redraws, don't recompute
# needlessly". This plugin already carries most of the recipe: the expensive
# scan runs OFF the redraw path (status `#()` reads a cache; refresh_async spawns
# a fully-detached, single-flighted background refresh) and each pane is probed
# by its explicit #{pane_id} (no pane-switch race). The two pieces added here:
#
#   DEBOUNCE  — situation_signature() hashes everything the capsule depends on
#               (each pane's id/command/path/title + the icon/format options),
#               deliberately excluding size/cursor so a redraw or resize never
#               invalidates it. When the signature is unchanged we serve the
#               last-good cache and skip the whole capture+classify pass.
#   FAIL-SOFT — a failed probe (tmux gone, provider timeout) keeps the last-good
#               capsule; we only overwrite the cache on a real result, so a
#               transient error can never blank the status line. (The hard
#               timeout that stops a wedged probe from freezing tmux already
#               lives in run_provider + the detached, lock-guarded refresh_async.)

# situation_signature: cheap, stable hash of the current situation. Empty when a
# provider is configured (its output is not a pane situation, so it is never
# debounced) or when tmux is unreachable (which disables the short-circuit and
# lets fail-soft keep the last-good value).
# ponytail: hashes ALL panes, not only agent panes — a churning non-agent pane
# (e.g. a scrolling log) can still force a recompute; narrow it to the agent
# command set if that ever shows up as measurable needless refreshes.
situation_signature() {
	[ -n "$(opt "@agent-status-provider" "")" ] && return 0
	rows=$("$TMUX_BIN" list-panes -a \
		-F "#{pane_id}${TAB}#{pane_current_command}${TAB}#{pane_current_path}${TAB}#{pane_title}" \
		2>/dev/null) || return 0
	printf '%s\n%s\n%s' \
		"$(opt "@agent-status-icons" "nerd")" \
		"$(opt "@agent-status-format" "")" \
		"$rows" | /usr/bin/cksum 2>/dev/null | /usr/bin/awk '{print $1"-"$2}'
}

# refresh_now: gather counts (provider first, else local scan) and atomically
# rewrite the cache. Runs in the detached refresh subshell (or the __refresh__
# test seam). Debounced and fail-soft per the template note above.
refresh_now() {
	busy=0; waiting=0; idle=0; have_result=0
	provider=$(opt "@agent-status-provider" "")
	if [ -n "$provider" ]; then
		json=$(run_provider "$provider")
		if [ -n "$json" ]; then
			IFS=' ' read -r busy waiting idle <<EOF
$(parse_counts "$json")
EOF
			have_result=1
		fi
	fi

	# DEBOUNCE: on the local path, short-circuit when the situation is unchanged.
	sig=''
	if [ "$have_result" -eq 0 ] && [ -z "$provider" ]; then
		sig=$(situation_signature)
		if [ -n "$sig" ] && [ -f "$CACHE" ] && [ "$sig" = "$(/bin/cat "$SIGFILE" 2>/dev/null)" ]; then
			return 0
		fi
	fi

	if [ "$have_result" -eq 0 ]; then
		if local_scan; then
			busy=$scan_busy; waiting=$scan_wait; idle=$scan_idle; have_result=1
		fi
	fi

	# FAIL-SOFT: no real result (probe failed) -> keep the last-good cache.
	if [ "$have_result" -eq 0 ]; then
		return 0
	fi

	out=$(render "$busy" "$waiting" "$idle")
	printf '%s' "$out" > "${CACHE}.new" 2>/dev/null && /bin/mv "${CACHE}.new" "$CACHE" 2>/dev/null
	# Record the situation only after a successful local recompute.
	if [ -n "$sig" ]; then
		printf '%s' "$sig" > "${SIGFILE}.new" 2>/dev/null && /bin/mv "${SIGFILE}.new" "$SIGFILE" 2>/dev/null
	fi
}

ensure_state_dir() {
	if [ ! -d "$STATE_DIR" ]; then
		parent=$(dirname "$STATE_DIR")
		[ -d "$parent" ] || /bin/mkdir -p "$parent" 2>/dev/null
		# create our dir atomically at 0700 (no -p, so -m applies to it)
		/bin/mkdir -m 700 "$STATE_DIR" 2>/dev/null
	fi
	[ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ]
}

# refresh_async: single-flight, fully-detached background refresh.
refresh_async() {
	ensure_state_dir || return 0
	# single-flight lock via atomic mkdir. Skip while a fresh refresh is in
	# flight; steal a stale lock left by a crashed refresh.
	# ponytail: 30s stale-steal window, tighten if refreshes ever run long.
	if ! /bin/mkdir "$LOCK" 2>/dev/null; then
		lm=$(file_mtime "$LOCK")
		if [ $((now - lm)) -lt 30 ]; then return 0; fi
		/bin/rmdir "$LOCK" 2>/dev/null
		/bin/mkdir "$LOCK" 2>/dev/null || return 0
	fi
	# fully detached: redirect all three fds so tmux's #() capture never waits
	# on this child (it only waits for the foreground `cat` below to hit EOF).
	(
		refresh_now
		/bin/rmdir "$LOCK" 2>/dev/null
	) </dev/null >/dev/null 2>&1 &
}

# ── test seams (fixture harness) ─────────────────────────────────────────────
case "${1:-}" in
	__classify__)
		# printf '%s' "$text" | AISTATUS_CMD=.. AISTATUS_TITLE=.. status.sh __classify__
		classify_one "${AISTATUS_CMD:-}" "${AISTATUS_TITLE:-}"
		exit 0 ;;
	__refresh__)
		# synchronous refresh (deterministic cache generation for tests)
		now=$(/bin/date +%s)
		ensure_state_dir || exit 0
		refresh_now
		exit 0 ;;
esac

# ── main: read cache; refresh in the background when stale; never block ───────
interval=$(opt "@agent-status-interval" 5)
case "$interval" in ''|*[!0-9]*) interval=5 ;; esac

now=$(/bin/date +%s)
mtime=$(file_mtime "$CACHE")
case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac

if [ $((now - mtime)) -gt "$interval" ]; then
	refresh_async
fi

/bin/cat "$CACHE" 2>/dev/null
exit 0

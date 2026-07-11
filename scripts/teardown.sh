#!/usr/bin/env bash
# teardown.sh — cleanly remove tmux-agent-status from a running server.
#
# Reverses the interpolation (turns the `#(scripts/status.sh)` call in
# status-left / status-right back into the `#{agent_status}` placeholder) and
# removes the private state directory. Safe to run more than once.

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "${CURRENT_DIR}/helpers.sh"

STATUS_SCRIPT="${CURRENT_DIR}/status.sh"
placeholder="#{agent_status}"
command_call="#(${STATUS_SCRIPT})"

restore_option() {
	option="$1"
	value=$(get_tmux_option "$option" "")
	new_value=${value//$command_call/$placeholder}
	tmux set-option -g "$option" "$new_value" 2>/dev/null || true
}

restore_option "status-right"
restore_option "status-left"

# Remove the private per-uid state dir (cache + lock). Specific subpath only.
STATE_DIR="${TMUX_TMPDIR:-/tmp}/tmux-agent-status-$(id -u 2>/dev/null || echo 0)"
if [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ]; then
	rm -rf "$STATE_DIR" 2>/dev/null || true
fi

tmux display-message "tmux-agent-status removed (placeholder restored, state cleared)" 2>/dev/null || true

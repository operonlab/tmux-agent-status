#!/usr/bin/env bash
# agent-status.tmux — TPM entry point for tmux-agent-status.
#
# TPM sources this once at tmux start. Following the tmux-cpu interpolation
# model, it reads the user's existing status-left / status-right and replaces
# the literal placeholder `#{agent_status}` with a `#(scripts/status.sh)` call,
# then writes the option back. Put `#{agent_status}` wherever you want the
# capsule in your status line.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "${CURRENT_DIR}/scripts/helpers.sh"

STATUS_SCRIPT="${CURRENT_DIR}/scripts/status.sh"

placeholder="#{agent_status}"
command_call="#(${STATUS_SCRIPT})"

do_interpolation() {
	interpolated="$1"
	interpolated=${interpolated//$placeholder/$command_call}
	printf '%s' "$interpolated"
}

update_tmux_option() {
	option="$1"
	value=$(get_tmux_option "$option" "")
	new_value=$(do_interpolation "$value")
	tmux set-option -g "$option" "$new_value"
}

update_tmux_option "status-right"
update_tmux_option "status-left"

# tmux-agent-status demo — recorded with vhs (https://github.com/charmbracelet/vhs)
#   cd tmux-agent-status && vhs docs/demo.tape
#
# Runs in a throwaway, isolated tmux server (-L vhsdemo-agent-status,
# -f /dev/null) so it never touches your real tmux. To keep the demo
# self-contained and deterministic it drives the capsule from an inline
# @agent-status-provider (a fixed JSON count) instead of live panes — the
# same provider contract documented in the README. The count changes once
# to show the capsule tracking state.

Output "docs/demo.gif"
Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 15
Set Width 1200
Set Height 660
Set Padding 12
Set TypingSpeed 40ms

Hide
Type `tmux -L vhsdemo-agent-status -f /dev/null new-session -d -s demo 'bash --norc -i'`
Enter
Type `tmux -L vhsdemo-agent-status attach -t demo`
Enter
Sleep 800ms
Type `PS1='❯ '; clear`
Enter
Type `tmux -L vhsdemo-agent-status set -g status-interval 1 \; set -g status-right-length 200`
Enter
Type `tmux -L vhsdemo-agent-status set -g @agent-status-interval 1`
Enter
Type `tmux -L vhsdemo-agent-status set -g status-right ' AI #{agent_status} '`
Enter
Type `tmux -L vhsdemo-agent-status set -g @agent-status-provider "printf '%s' '{\"busy\":2,\"wait\":1,\"idle\":3}'"`
Enter
Type `./agent-status.tmux`
Enter
Type "clear"
Enter
Sleep 3s
Show
Type "# tmux-agent-status: busy / blocked / idle AI panes at a glance"
Enter
Sleep 3.5s
Hide
Type `tmux -L vhsdemo-agent-status set -g @agent-status-provider "printf '%s' '{\"busy\":1,\"wait\":2,\"idle\":2}'"`
Enter
Type "clear"
Enter
Sleep 1.5s
Show
Type "# one finished, another is now blocked waiting on you"
Enter
Sleep 4s
Hide
Type `tmux -L vhsdemo-agent-status kill-server`
Enter
Sleep 500ms

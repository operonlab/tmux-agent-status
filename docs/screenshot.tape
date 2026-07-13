# tmux-agent-status hero screenshot -- recorded with vhs (charmbracelet/vhs)
#   cd tmux-agent-status && vhs docs/screenshot.tape
#
# Runs in a throwaway, isolated tmux server (-L shot-agent-status, -f /dev/null)
# so it never touches your real tmux. The capsule is driven by a fixed-count
# inline @agent-status-provider (the documented provider contract) so the shot
# is deterministic -- 2 busy, 1 blocked, 3 idle. No real AI CLI is launched.

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 1600
Set Height 420
Set Padding 20

Hide
Type `tmux -L shot-agent-status -f /dev/null new-session -d -s dev 'bash --norc -i'`
Enter
Type `tmux -L shot-agent-status attach -t dev`
Enter
Sleep 600ms
Type `PS1='❯ '; clear`
Enter
Type `tmux -L shot-agent-status set -g status-interval 1 \; set -g status-left-length 20 \; set -g status-right-length 200`
Enter
Type `tmux -L shot-agent-status set -g @agent-status-interval 1`
Enter
Type `tmux -L shot-agent-status set -g status-right ' AI  #{agent_status} '`
Enter
Type `tmux -L shot-agent-status set -g @agent-status-provider "printf '%s' '{\"busy\":2,\"wait\":1,\"idle\":3}'"`
Enter
Type `./agent-status.tmux`
Enter
Type "clear"
Enter
Sleep 3s
Show
Type "# tmux-agent-status  --  count your AI CLIs live, right on the status bar"
Enter
Type "#"
Enter
Type "#     busy      2   working, burning tokens"
Enter
Type "#     blocked   1   waiting on you  (permission prompt)"
Enter
Type "#     idle      3   empty prompt, ready for the next task"
Enter
Type "#"
Enter
Type "#    the capsule down on the status line keeps this tally, live  -->"
Enter
Sleep 1200ms
Screenshot "docs/screenshot.png"
Sleep 300ms
Hide
Type `tmux -L shot-agent-status kill-server`
Enter
Sleep 500ms

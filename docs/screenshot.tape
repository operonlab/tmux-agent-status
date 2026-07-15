# tmux-agent-status HERO screenshot -- recorded with vhs (charmbracelet/vhs)
#   cd tmux-agent-status && vhs docs/screenshot.tape
#
# Same self-contained stage as docs/demo.tape: docs/demo-setup.sh builds an
# anonymous Starship-clone shell and a catppuccin-mocha ISOLATED tmux server
# (socket as-demo, session demo) and wires THIS plugin's real scripts/status.sh
# reader into the CLUSTER capsule (Row 1 centre) via a fixed demo provider.
# The cockpit owns both status rows so nothing leaks. Money shot = the AI
# busy / blocked / idle capsule in the cluster. Framed tight: a short narration
# above the two-row pill cockpit, no dead space.

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 2496
Set Height 360
Set Padding 20
Set TypingSpeed 20ms

Hide
Type "bash docs/demo-setup.sh"
Enter
Sleep 3s
Type "clear; tmux -L as-demo attach -t demo"
Enter
Sleep 2500ms
Type "clear"
Enter
Sleep 800ms
Show

# borrow the demo narration + the busy/blocked/idle breakdown, pointing at the capsule
Type "# tmux-agent-status  --  busy / blocked / idle AI panes, live on the status bar"
Enter
Type "#   busy 2  ·  blocked 1  ·  idle 3   -->  the robot CLUSTER capsule keeps this tally"
Enter
Sleep 1500ms
Screenshot "docs/screenshot.png"
Sleep 300ms

Hide
Type "tmux -L as-demo kill-server"
Enter
Sleep 500ms

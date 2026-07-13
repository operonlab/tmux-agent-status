# tmux-agent-status demo — busy / blocked / idle AI panes at a glance, in a
# cockpit status bar. Fully self-contained: docs/demo-setup.sh stages an
# anonymous shell and a catppuccin-mocha ISOLATED tmux server (socket as-demo),
# then loads the plugin so the #{agent_status} token renders a live capsule from
# a fixed demo provider (a JSON file). The theme owns status-left AND status-right
# (the default status-right leaks the hostname); the capsule sits at the tail,
# behind the clock. The provider file is flipped once, off camera, so the capsule
# visibly tracks state. No real agent panes are ever scanned.
# Re-record from the repo root with:  vhs docs/demo.tape
Output "docs/demo.gif"
Require tmux

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 1600
Set Height 480
Set Padding 20
Set TypingSpeed 35ms

Hide
Type "bash docs/demo-setup.sh"
Enter
Sleep 3s
Type "clear; tmux -L as-demo attach -t demo"
Enter
Sleep 2s
Show

# the cockpit: clock capsule, then the AI capsule — 2 busy, 1 blocked, 3 idle
Sleep 3s
Type "# tmux-agent-status: busy / blocked / idle AI panes, at a glance"
Enter
Sleep 2500ms

# off camera: one agent finished and another is now blocked -> flip the provider
Hide
Type `printf '%s' '{"busy":1,"wait":2,"idle":2}' > /tmp/vhs-agent-status-demo/counts.json`
Enter
Sleep 2500ms
Type "clear"
Enter
Show

# the capsule now reads 1 busy, 2 blocked, 2 idle
Sleep 1s
Type "# one finished; another is now blocked, waiting on you"
Enter
Sleep 4s

Hide
Ctrl+B
Type "d"
Sleep 400ms
Type "tmux -L as-demo kill-server"
Enter
Sleep 500ms

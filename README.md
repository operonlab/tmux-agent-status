# tmux-agent-status

> 中文說明請見 [docs/zh.md](docs/zh.md)

![platform: macOS](https://img.shields.io/badge/platform-macOS-black)
![shell: POSIX sh](https://img.shields.io/badge/shell-POSIX%20sh-89e051)
![license: MIT](https://img.shields.io/badge/license-MIT-blue)

A tiny tmux status-line capsule that tells you, at a glance, how many AI coding
assistants (Claude Code, Codex, Gemini, Aider, and friends) are running in your
panes right now — and which of them need you.

**macOS is the primary, tested platform.** The content-matching logic is
platform-neutral, but it has only been exercised on macOS. See
[Compatibility](#compatibility).

## What is this?

If you run more than one AI CLI at a time — one crunching a refactor, one
paused on a "may I run this command?" prompt, one just sitting at an empty
prompt waiting for you — it is hard to tell from a wall of panes which is which.

This plugin adds one small capsule to your tmux status line that counts them in
three states:

- **busy** — actively working (burning tokens)
- **blocked** — stuck on a permission prompt or a menu, *waiting on you*
- **idle** — sitting at an empty prompt, ready for the next instruction

When nothing is running, the capsule disappears entirely. It reads a cache and
returns instantly on every redraw, so it never slows your status line down (see
[How it stays fast](#how-it-stays-fast)).

## Quickstart

> New to tmux? `prefix` means the tmux leader key — by default **Ctrl-b**. So
> "press `prefix` + `I`" means press Ctrl-b, release, then press `I`.

Put the placeholder `#{agent_status}` anywhere in your `status-left` or
`status-right`, then load the plugin one of two ways.

### Option A — with [TPM](https://github.com/tmux-plugins/tpm) (recommended)

Add these two lines to `~/.tmux.conf`:

```tmux
set -g status-right ' #{agent_status} %H:%M '
set -g @plugin 'operonlab/tmux-agent-status'
```

Then reload and install:

```tmux
# reload the config, then press prefix + I to fetch the plugin
tmux source-file ~/.tmux.conf
```

Press `prefix` + `I` (capital i) to have TPM clone and source it.

### Option B — without TPM (plain `run-shell`)

Clone the repo, then point tmux at the entry script in `~/.tmux.conf`:

```tmux
set -g status-right ' #{agent_status} %H:%M '
run-shell '~/clones/tmux-agent-status/agent-status.tmux'
```

```sh
git clone https://github.com/operonlab/tmux-agent-status ~/clones/tmux-agent-status
tmux source-file ~/.tmux.conf
```

Either way, the entry script rewrites the literal `#{agent_status}` in your
status option into a call to `scripts/status.sh` — so the placeholder is where
you decide the capsule appears.

## Demo

*Demo GIF coming soon.*

A busy Claude pane, a Codex pane blocked on a permission prompt, and an idle
Gemini pane render (with the default Nerd Font icons) as roughly:

```
 2   1   1
```

…which reads "2 busy, 1 blocked, 1 idle". With `@agent-status-icons ascii` the
same state reads `[B] 2  [W] 1  [I] 1`.

## Options

Set any of these in `~/.tmux.conf` **before** the plugin loads.

| Option | Default | Description |
| --- | --- | --- |
| `@agent-status-provider` | `""` (empty) | External command that reports the counts. Empty = scan local panes. **See the warning below.** |
| `@agent-status-interval` | `5` | Seconds before the cache is considered stale and a background refresh is spawned. |
| `@agent-status-icons` | `nerd` | `nerd` uses Nerd Font glyphs (play / hand / pause); `ascii` uses `[B]` / `[W]` / `[I]` for terminals without a Nerd Font. |
| `@agent-status-format` | `""` (empty) | Advanced custom template — see [Custom format](#custom-format). Empty = built-in layout. |

```tmux
set -g @agent-status-icons 'ascii'
set -g @agent-status-interval '3'
```

### `@agent-status-provider` (runs a command you supply)

> **Warning: this option executes code.** The value is run as a shell command on
> every refresh. Only set it in a `tmux.conf` you trust — never paste a provider
> command from an untrusted source.

By default the plugin scans your local tmux panes (see
[docs/detection-matrix.md](docs/detection-matrix.md) for exactly how each CLI is
classified). If you already have an authoritative source of agent state — a
daemon, a registry, a cross-machine aggregator — point the provider at it
instead. **When a provider is set it is trusted; the plugin only falls back to
the local scan if the provider outputs nothing, times out, or fails.**

The provider contract is one line of JSON on stdout:

```json
{"busy": 2, "wait": 1, "idle": 3}
```

- `busy`, `wait`, `idle` are integers (missing keys are treated as `0`).
- `wait` is the "blocked / needs-a-human" bucket.
- The command is bounded by a `timeout` (3s) when `timeout`/`gtimeout` is
  available, so a hung provider cannot pile up background refreshes.

Example — a provider that reads a hypothetical daemon:

```tmux
set -g @agent-status-provider 'curl -sf --max-time 1 http://127.0.0.1:9000/agents.json'
```

### Custom format

`@agent-status-format`, when non-empty, replaces the built-in layout. It is a
template with these substitutions:

| Token | Expands to |
| --- | --- |
| `%B` / `%W` / `%I` | the busy / blocked / idle **icon** (respecting `@agent-status-icons`) |
| `%b` / `%w` / `%i` | the busy / blocked / idle **count** |

```tmux
set -g @agent-status-format 'A:%b B:%w Z:%i'
```

Note: unlike the built-in layout, a custom format is emitted verbatim, so it
does not auto-hide the zero states — write your template accordingly.

## Uninstall

Run the teardown script (restores the `#{agent_status}` placeholder and clears
the runtime cache), then drop the two config lines:

```sh
tmux run-shell '~/clones/tmux-agent-status/scripts/teardown.sh'   # (TPM path: ~/.tmux/plugins/tmux-agent-status/scripts/teardown.sh)
# then remove the @plugin / run-shell line and the #{agent_status} token from ~/.tmux.conf
```

## Troubleshooting / FAQ

**The capsule never appears.**
It is empty by design when no AI CLI is running. Start an agent, wait one
refresh interval (default 5s), and it should show. If it still never appears,
confirm the placeholder made it into the option: `tmux show-option -gv
status-right` should contain `scripts/status.sh`, not a literal
`#{agent_status}`. If it still shows the literal token, the entry script did not
run — re-run `tmux source-file ~/.tmux.conf` (TPM) or the `run-shell` line.

**I see boxes / `?` instead of icons.**
Your terminal font is not a Nerd Font. Either install one (and set it as your
terminal font) or switch to ASCII markers:
`set -g @agent-status-icons 'ascii'`.

**A pane shows busy/idle but I expected the other (or nothing).**
Detection reads each CLI's on-screen output, which upstreams change over time —
see the [detection matrix](docs/detection-matrix.md) and its best-effort
disclaimer. For authoritative state, wire up an `@agent-status-provider`. If a
non-agent process (a plain `node`/`bun`/`deno` dev server) is lighting the
capsule, note that those are matched by their window title only and never by
screen text — check whether that process is setting a spinner in its OSC title.

**Does it talk to my agents or read my code?**
No. It only reads tmux pane metadata and the last ~30 captured lines of each
agent pane's screen to classify state locally. Nothing leaves your machine
unless *you* configure a provider that makes a network call.

**Where does it store state?**
One cache file and a lock under
`${TMUX_TMPDIR:-/tmp}/tmux-agent-status-<your-uid>/`, created `0700`. Nothing is
written inside the repo. `teardown.sh` removes it.

## How it stays fast

A tmux `#()` command runs on *every* status-line redraw, so it must return
instantly. This plugin's foreground path only reads a cache file and prints it.
When the cache is older than `@agent-status-interval`, it spawns **one**
fully-detached, lock-guarded background refresh (all three file descriptors
redirected so tmux never waits on it) and still returns the old value
immediately. The capsule therefore lags by at most one interval and never
stalls your status line, even if a provider or a pane scan is slow.

## Compatibility

- **Requires tmux ≥ 2.1.** The tmux features this plugin uses land early per the
  official tmux `CHANGES`: `@`-prefixed user options, `capture-pane -p`, and
  `show-options -q` in **1.8**; the `#{pane_current_command}` format in **1.9**.
  The 2.1 floor is a deliberately conservative, verified-safe minimum above
  those introductions.
- **Tested on:** tmux `next-3.8` on macOS. Older tmux versions are inferred from
  the `CHANGES` feature history, not exercised on real old binaries — if you hit
  a problem on an older tmux, please open an issue (and consider upgrading).
- **Platform:** macOS is the primary, tested platform. The classifier
  (`classify.awk`) is pure byte-wise content matching and is platform-neutral —
  its unit test runs on Linux in CI — but the full pane-scan integration has
  only been tested on macOS. Argv-level *presence* detection is portable; only
  the busy/blocked/idle TUI refinement is tuned against the macOS builds of each
  CLI.

## Credits / License

The three-state classifier is ported from the author's private tmux status
script, itself distilled from an already-verified cross-CLI agent-state rule
table. The TPM interpolation pattern (rewriting a placeholder token inside an
existing `status-left`/`status-right`) follows the approach popularised by
[tmux-cpu](https://github.com/tmux-plugins/tmux-cpu).

MIT — see [LICENSE](LICENSE).

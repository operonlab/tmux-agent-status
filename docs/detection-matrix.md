# Detection matrix

How the local fallback scanner decides whether an AI-CLI pane is **busy**,
**blocked** (`wait`), or **idle**. This is the exact behaviour encoded in
[`scripts/classify.awk`](../scripts/classify.awk); this page is the
human-readable version of those rules.

> **Rules version:** 1 · **Verified:** 2026-07
>
> **Best-effort disclaimer.** These rules key on the *on-screen TUI output* of
> each CLI (footer hints, spinner glyphs, OSC window titles). CLI vendors change
> their TUIs without notice, so a rule that is accurate today can drift when an
> upstream release rewords a prompt or swaps a spinner. The one thing that does
> **not** drift is the argv-level *presence* detection (does a pane run an
> agent at all) — that keeps working regardless of TUI changes; only the
> busy/blocked/idle *refinement* can go stale. When in doubt, wire up an
> `@agent-status-provider` (see the README) that reports authoritative state.

## How a pane is matched

The scanner reads three fields per pane — `pane_current_command` (the running
process's command name), `pane_title` (the OSC window title, which many CLIs use
to broadcast a spinner), and, for real agents, the captured footer (last ~30
lines). The command name selects which rule set runs:

| `pane_current_command` | Rule set | Screen text scanned? |
| --- | --- | --- |
| `claude`, `claude-code`, or a bare `X.Y.Z` version string | Claude rules | Yes (footer) |
| `codex`, `codex-*` (e.g. `codex-aarch64-…`) | Codex rules | Yes (footer) |
| `gemini`, `aider`, `cursor`, `cursor-agent`, `agy`, `copilot`, `opencode`, `amp`, `droid`, `qwen`, `kimi`, `hermes`, `pi` | Generic-agent rules | No — OSC title only |
| `node`, `bun`, `deno` | Host-runtime rules | **No** — OSC title only |
| anything else | *(ignored — never counted)* | No |

Why `node`/`bun`/`deno` and the "generic agent" group are **title-only:** a
dev server or a non-agent Node process would otherwise have its log text
misread as agent activity. Trusting only the OSC title (which the agent itself
sets) is the architectural fix for that false-positive class.

## Signals per rule set

### Claude rules (`claude`, `claude-code`, `X.Y.Z`)

| Screen / title signal | State |
| --- | --- |
| OSC title starts with a braille spinner glyph (`⠋`, `⠙`, …) | busy |
| Bottom lines contain `esc to interrupt`, `thinking`, `processing`, or a `✳/✶/✳`-family spinner | busy |
| A selectable menu (`enter to select` + a `❯ …` cursor row) not inside the composer box | blocked |
| `run a dynamic workflow?` together with `esc to cancel` | blocked |
| `do you want to proceed?` for a bash command, with a `1. Yes / 2. No` choice | blocked |
| A permission question (`do you want to make this edit`, `… to create`, `… to proceed?`) after the last rule line, with a yes/no choice | blocked |
| Legacy permission phrasings (`waiting for permission`, `do you want to allow this connection?`, `review your answers`, …) | blocked |
| Composer box present with no active `esc to interrupt` outside it | idle |
| An empty `❯` prompt at the bottom (and no menu/choice/"navigate" hint) | idle |
| OSC title starts with `✳ ` (star, no spinner) | idle |
| none of the above | *(no state — not counted)* |

### Codex rules (`codex`, `codex-*`)

| Screen / title signal | State |
| --- | --- |
| OSC title contains `action required` | blocked |
| OSC title starts with a braille spinner glyph | busy |
| `press enter to confirm or esc to cancel`, `allow command?`, `enter to submit answer`, or `enter to submit all` | blocked |
| Not currently working, and `[y/n]` / `yes (y)` / `do you want to …` with a yes-or-`❯` choice | blocked |
| Bottom lines contain `esc to interrupt` or a braille spinner | busy |
| none of the above | *(no state — not counted)* |

### Generic-agent rules (`gemini`, `aider`, `cursor`, `agy`, `copilot`, `opencode`, `amp`, `droid`, `qwen`, `kimi`, `hermes`, `pi`, …)

| Title signal | State |
| --- | --- |
| OSC title starts with a braille spinner glyph | busy |
| OSC title starts with `✳ ` | idle |
| none of the above | *(no state — not counted)* |

These CLIs are recognised by presence but only refined via their OSC title, so a
value shows up only when the CLI advertises one. If a particular CLI you use
sets a richer title or a distinctive footer, an `@agent-status-provider` is the
clean way to add precise detection without patching the classifier.

### Host runtimes (`node`, `bun`, `deno`)

| Title signal | State |
| --- | --- |
| OSC title starts with a braille spinner glyph | busy |
| none of the above | *(no state — screen text is never scanned)* |

## Anti-pollution design (why this isn't just "grep the screen")

Every "working" signal is anchored to the **bottom-N non-empty lines**, the OSC
title, or the composer box — never a bare whole-screen match. A running-agent
transcript quoted in the scrollback, an example in a README open in the pane, or
an old prompt higher up the buffer will therefore **not** light the capsule.
The NOT-gates (empty-`❯` veto, "box present ⇒ idle", "bottom-zone live-working
veto") exist specifically to stop a live-looking artifact above the fold from
being read as the current state. See the comment block at the top of
`scripts/classify.awk` for the full rationale.

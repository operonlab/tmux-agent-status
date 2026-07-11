# Changelog

All notable changes to tmux-agent-status are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-11

Initial release.

### Added

- A single status-line placeholder — `#{agent_status}` — placeable anywhere in
  `status-left` / `status-right`. It renders a three-state capsule counting the
  local AI-CLI panes that are **busy** (burning tokens), **blocked** (stuck on a
  permission prompt / menu — needs a human), and **idle** (empty prompt). When
  nothing is running the capsule collapses to an empty string and disappears.
- `scripts/classify.awk` — a byte-wise (`LC_ALL=C`) footer classifier ported
  from a private origin script. It keeps the region-convergence + NOT-gate
  design that anchors every "working" signal to the bottom-N lines / OSC title /
  composer box, so a running-agent transcript in the scrollback cannot light the
  capsule up.
- Strict **non-blocking** status contract: `scripts/status.sh` only reads a
  cache file and returns immediately; a stale cache triggers one fully-detached,
  lock-guarded background refresh, and a slow/hung provider keeps showing the
  last value.
- **Provider contract** — the `@agent-status-provider` option runs an external
  command that prints `{"busy":N,"wait":N,"idle":N}` on stdout. When set it is
  trusted; on empty output / timeout / failure the plugin falls back to a local
  pane scan. Documented in `docs/detection-matrix.md`.
- Options: `@agent-status-provider` (default empty = local scan),
  `@agent-status-interval` (default `5`), `@agent-status-icons`
  (`nerd` | `ascii`, default `nerd`), `@agent-status-format` (advanced custom
  template).
- `scripts/teardown.sh` — restores the `#{agent_status}` placeholder in the
  status options and removes the runtime state directory.
- Per-user runtime directory under
  `${TMUX_TMPDIR:-/tmp}/tmux-agent-status-<uid>/`, created mode `0700` with a
  symlink-pre-plant guard.
- CI: `shellcheck -S warning` across all shell files, a platform-neutral
  `classify.awk` unit test, and a macOS functional smoke suite that runs the
  plugin on a private `tmux -L` socket against a real AI-CLI-named pane.

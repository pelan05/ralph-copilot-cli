# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-01-10

### Added
- Optional PRD attachment via `--prd` (only attached when explicitly provided).
- Mandatory prompt selection via `--prompt` (no implicit default in runners).
- Prompt harness runs each prompt in an isolated git worktree and captures Copilot output via pseudo-TTY transcript.
- `prompts/pest-coverage.txt` prompt file and harness support for running it without a PRD.

### Changed
- Normalized shell tool allow/deny specs to the pattern form `shell(cmd:*)`.
- Prevented emitting empty tool spec arguments (avoids `--allow-tool ''` / `--deny-tool ''`).

### Documentation
- Updated README usage/examples to reflect `--prompt` required and `--prd` optional.
- Added per-prompt examples in `prompts/README.md`.

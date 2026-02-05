# Ralph (Copilot CLI Runner)

> Let AI implement your features while you sleep.

Ralph runs **GitHub Copilot CLI** in a loop, implementing one feature at a time until your PRD is complete.

[Quick Start](#quick-start) · [How It Works](#how-it-works) · [PRD Formats](#prd-formats) · [Configuration](#configuration) · [Command Reference](#command-reference)

---

## Quick Start

```bash
# Clone and enter the repo
git clone https://github.com/pelan05/ralph-copilot-cli
cd ralph-copilot-cli

# Add your work items to plans/prd.json (or use Markdown/YAML/GitHub Issues)

# Test with a single run
./ralph-once.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe

# Run multiple iterations
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe 10

# With feature branches and auto PRs
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \
  --branch-per-task --create-pr 10
```

Check `progress.txt` for a log of what was done.

---

## How It Works

Ralph implements the ["Ralph Wiggum" technique](https://www.humanlayer.dev/blog/brief-history-of-ralph):

1. **Read** — Copilot reads your PRD (JSON, Markdown, YAML, or GitHub Issues) and progress file
2. **Pick** — It chooses the highest-priority incomplete item
3. **Implement** — It writes code for that one feature
4. **Verify** — It runs your tests (`pnpm typecheck`, `pnpm test`)
5. **Update** — It marks the item complete and logs progress
6. **Commit** — It commits the changes (optionally to a feature branch)
7. **PR** — Optionally creates a pull request
8. **Repeat** — Until all items pass or it signals completion

### Learn More

- [Matt Pocock's thread](https://x.com/mattpocockuk/status/2007924876548637089)
- [Ship working code while you sleep (video)](https://www.youtube.com/watch?v=_IK18goX4X8)
- [11 Tips For AI Coding With Ralph Wiggum](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum)
- [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

---

## PRD Formats

Ralph supports multiple formats for defining your work items:

### JSON Array (Original Format)

```bash
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe 10
```

```json
[
  {
    "category": "functional",
    "description": "User can send a message and see it in the conversation",
    "steps": ["Open chat", "Type message", "Click Send", "Verify it appears"],
    "passes": false
  }
]
```

### JSON with User Stories (Amp-style)

Supports priorities, IDs, and branch names:

```json
{
  "project": "MyApp",
  "branchName": "ralph/task-priority",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "description": "As a developer, I need to store task priority...",
      "acceptanceCriteria": ["Add priority column", "Run migration"],
      "priority": 1,
      "passes": false
    }
  ]
}
```

### Markdown Checkboxes

```bash
./ralph.sh --prompt prompts/default.txt --markdown PRD.md --allow-profile safe 10
```

```markdown
# My Project

## Tasks
- [ ] Create user authentication
- [ ] Add dashboard page
- [x] Setup database (completed)
```

### YAML Tasks

```bash
./ralph.sh --prompt prompts/default.txt --yaml tasks.yaml --allow-profile safe 10
```

```yaml
tasks:
  - title: Create user authentication
    completed: false
  - title: Add dashboard page
    completed: false
```

Requires `yq` (`brew install yq`).

### GitHub Issues

```bash
./ralph.sh --prompt prompts/default.txt --github owner/repo --allow-profile safe 10
./ralph.sh --prompt prompts/default.txt --github owner/repo --github-label "ready" --allow-profile safe 10
```

Fetches open issues from GitHub. Issues are closed when tasks complete.

Requires `gh` CLI (`brew install gh`).

---

## Configuration

### Choose a Model

Set the `MODEL` environment variable (default: `gpt-5.2`):

```bash
MODEL=claude-opus-4.5 ./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe 10
```

### Use Custom Prompts

Prompts are required. Use any prompt file:

```bash
./ralph.sh --prompt prompts/my-prompt.txt --allow-profile safe 10
```

> **Note:** Custom prompts require `--allow-profile` or `--allow-tools`.

---

## Command Reference

### `ralph.sh` — Looped Runner

Runs Copilot up to N iterations. Stops early on `<promise>COMPLETE</promise>`.

```bash
./ralph.sh [options] <iterations>
```

**Examples:**

```bash
# Basic usage
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe 10

# With feature branches
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \
  --branch-per-task 10

# With auto PRs
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \
  --branch-per-task --create-pr 10

# Fast mode (skip tests/lint)
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe --fast 10

# From GitHub issues
./ralph.sh --prompt prompts/default.txt --github owner/repo --allow-profile safe 10

# With retries
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \
  --max-retries 3 --retry-delay 10 10

# Dry run (preview without executing)
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe --dry-run 10
```

### `ralph-once.sh` — Single Run

Runs Copilot once. Great for testing.

```bash
./ralph-once.sh [options]
```

**Examples:**

```bash
./ralph-once.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe
./ralph-once.sh --prompt prompts/default.txt --markdown PRD.md --allow-profile locked
```

---

## Options

### PRD Source Options

| Option | Description |
|--------|-------------|
| `--prd <file>` | JSON PRD file (default format) |
| `--markdown <file>` | Markdown PRD with checkboxes |
| `--yaml <file>` | YAML task file (requires `yq`) |
| `--github <owner/repo>` | Fetch tasks from GitHub issues |
| `--github-label <label>` | Filter GitHub issues by label |

### Permission Options

| Option | Description | Default |
|--------|-------------|---------|
| `--allow-profile <name>` | Permission profile (see below) | — |
| `--allow-tools <spec>` | Allow specific tool (repeatable) | — |
| `--deny-tools <spec>` | Deny specific tool (repeatable) | — |

### Git Branch Options

| Option | Description |
|--------|-------------|
| `--branch-per-task` | Create a new git branch for each task |
| `--base-branch <name>` | Base branch to create task branches from |
| `--create-pr` | Create a pull request after each task (requires `gh`) |
| `--draft-pr` | Create PRs as drafts |

### Workflow Options

| Option | Description |
|--------|-------------|
| `--no-tests` | Skip running tests (passed to prompt) |
| `--no-lint` | Skip linting (passed to prompt) |
| `--fast` | Skip both tests and linting |
| `--skill <a[,b,...]>` | Prepend skills from `skills/<name>/SKILL.md` |

### Execution Options

| Option | Description | Default |
|--------|-------------|---------|
| `--max-retries <n>` | Max retries per iteration on failure | 0 |
| `--retry-delay <n>` | Seconds between retries | 5 |
| `--dry-run` | Show what would be done without executing | — |
| `-v, --verbose` | Show debug output | — |
| `-h, --help` | Show help | — |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MODEL` | Model to use | `gpt-5.2` |

---

## Permission Profiles

| Profile | Allows | Use Case |
|---------|--------|----------|
| `locked` | `write` only | File edits, no shell |
| `safe` | `write`, `shell(pnpm:*)`, `shell(git:*)` | Normal dev workflow |
| `dev` | All tools | Broad shell access |

**Always denied:** `shell(rm)`, `shell(git push)`

**Custom tools:** If you pass `--allow-tools`, it replaces the profile defaults:

```bash
./ralph.sh --prompt prompts/wp.txt --allow-tools write --allow-tools 'shell(composer:*)' 10
```

---

## Feature Branch Workflow

Create isolated branches for each task with optional auto-PR:

```bash
# Create feature branches, merge after each task
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \
  --branch-per-task 10

# Create feature branches with pull requests
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \
  --branch-per-task --create-pr 10

# Create draft PRs
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \
  --branch-per-task --create-pr --draft-pr 10

# Specify base branch
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \
  --branch-per-task --base-branch main 10
```

Branch naming: `ralph/<task-name-slug>`

---

## Project Structure

```
.
├── plans/prd.json        # Your work items (JSON)
├── prompts/default.txt   # Default prompt with full instructions
├── progress.txt          # Running log of completed work
├── ralph.sh              # Looped runner (v2.0.0)
├── ralph-once.sh         # Single-run script
├── skills/               # Reusable skill definitions
└── test/run-prompts.sh   # Test harness
```

---

## Progress File & Learnings

Ralph maintains `progress.txt` with two key sections:

### Codebase Patterns (Top of File)

Reusable patterns discovered during implementation:

```markdown
## Codebase Patterns
- Use `sql<T>` template for all database queries
- Always add `IF NOT EXISTS` to migrations
- Export types from actions.ts for UI components
```

### Iteration Logs

Details from each completed task:

```markdown
## 2026-02-05 - US-001: Add user authentication
- Implemented login/logout flow
- Files changed: auth.ts, login.tsx
- **Learnings:**
  - Session tokens stored in cookies
  - Use bcrypt for password hashing
---
```

---

## Install Copilot CLI

```bash
# Check version
copilot --version

# Homebrew
brew update && brew upgrade copilot

# npm
npm i -g @github/copilot

# Windows
winget upgrade GitHub.Copilot
```

---

## Optional Dependencies

| Tool | Required For | Install |
|------|--------------|---------|
| `yq` | YAML PRD format | `brew install yq` |
| `gh` | GitHub Issues / PRs | `brew install gh` |
| `jq` | JSON parsing (usually pre-installed) | `brew install jq` |

---

## Demo

Try Ralph in a safe sandbox:

```bash
# Setup
git clone https://github.com/pelan05/ralph-copilot-cli && cd ralph-copilot-cli
git worktree add ../ralph-demo -b ralph-demo
cd ../ralph-demo

# Run
./ralph-once.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe 10

# Inspect
git log --oneline -20
cat progress.txt

# Cleanup
cd .. && git worktree remove ralph-demo && git branch -D ralph-demo
```

---

## Changelog

### v2.0.0

- **Multiple PRD formats**: JSON, Markdown, YAML, GitHub Issues
- **Enhanced JSON format**: Support for userStories with IDs, priorities, acceptance criteria
- **Git branch workflow**: `--branch-per-task`, `--base-branch`
- **Auto PR creation**: `--create-pr`, `--draft-pr`
- **Retry logic**: `--max-retries`, `--retry-delay`
- **Workflow flags**: `--no-tests`, `--no-lint`, `--fast`
- **Execution control**: `--dry-run`, `--verbose`
- **Colored output**: Progress indicators with color coding
- **Enhanced prompt**: AGENTS.md updates, codebase patterns, learnings

### v1.1.0

- Initial release with basic JSON PRD support
- Skills system
- Permission profiles

---

## Credits

Inspired by:
- [Ralph (Amp-based)](https://github.com/snarktank/ralph) - The original Amp implementation
- [Ralphy](https://github.com/yourusername/ralphy) - Claude Code/OpenCode implementation with parallel execution
- [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/)

---

## License

MIT — see [LICENSE](LICENSE).

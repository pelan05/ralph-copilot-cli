# Ralph PRD Formats

This directory contains your Product Requirements Documents (PRDs) that Ralph uses to determine what features to implement.

## Supported Formats

Ralph v2.0 supports multiple PRD formats.

### 1. JSON Array (Original)

**File:** `prd.json`

```json
[
  {
    "category": "functional",
    "description": "User can send a message",
    "steps": ["Open chat", "Type message", "Click Send"],
    "passes": false
  }
]
```

**Usage:**
```bash
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe 10
```

### 2. JSON with User Stories (Amp-style)

**File:** `prd-user-stories.json.example`

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-x",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field",
      "acceptanceCriteria": ["..."],
      "priority": 1,
      "passes": false
    }
  ]
}
```

**Benefits:**
- Story IDs for tracking
- Priority ordering
- Acceptance criteria
- Branch name suggestion

### 3. Markdown Checkboxes

**File:** `PRD.md.example`

```markdown
## Tasks
- [ ] Uncompleted task
- [x] Completed task
```

**Usage:**
```bash
./ralph.sh --prompt prompts/default.txt --markdown plans/PRD.md --allow-profile safe 10
```

### 4. YAML Tasks

```yaml
tasks:
  - title: Create user model
    completed: false
```

**Usage:**
```bash
./ralph.sh --prompt prompts/default.txt --yaml plans/tasks.yaml --allow-profile safe 10
```

### 5. GitHub Issues

**Usage:**
```bash
./ralph.sh --prompt prompts/default.txt --github owner/repo --allow-profile safe 10
```

## Best Practices

- **Keep tasks small** — one feature per agent iteration
- **Be specific** — clear acceptance criteria help the agent
- **Include acceptance criteria** — makes it clear when done
- **Order by priority** — use priority numbers or list order
- **One feature per task** — don't bundle unrelated changes

## Example Files

The included `prd.json` is a template (chat-app stories). Replace with your own requirements.

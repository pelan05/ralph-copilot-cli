#!/usr/bin/env bash
set -euo pipefail

RALPH_VERSION="2.0.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# COLORS (detect if terminal supports colors)
# ============================================
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  CYAN=$(tput setaf 6)
  BOLD=$(tput bold)
  DIM=$(tput dim)
  RESET=$(tput sgr0)
else
  RED="" GREEN="" YELLOW="" BLUE="" CYAN="" BOLD="" DIM="" RESET=""
fi

# ============================================
# CONFIGURATION & DEFAULTS
# ============================================
prompt_file=""
prd_file=""
skills_csv=""
allow_profile=""
declare -a allow_tools
declare -a deny_tools
allow_tools=()
deny_tools=()

# New features
BRANCH_PER_TASK=false
BASE_BRANCH=""
CREATE_PR=false
PR_DRAFT=false
DRY_RUN=false
VERBOSE=false
MAX_RETRIES=0
RETRY_DELAY=5
SKIP_TESTS=false
SKIP_LINT=false

# PRD source options
PRD_SOURCE="json"  # json, markdown, yaml, github
GITHUB_REPO=""
GITHUB_LABEL=""

# Global state
declare -a task_branches=()

# ============================================
# LOGGING FUNCTIONS
# ============================================
log_info() {
  echo "${BLUE}[INFO]${RESET} $*"
}

log_success() {
  echo "${GREEN}[OK]${RESET} $*"
}

log_warn() {
  echo "${YELLOW}[WARN]${RESET} $*"
}

log_error() {
  echo "${RED}[ERROR]${RESET} $*" >&2
}

log_debug() {
  if [[ "$VERBOSE" == true ]]; then
    echo "${DIM}[DEBUG] $*${RESET}"
  fi
}

# ============================================
# UTILITY FUNCTIONS
# ============================================
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-|-$//g' | cut -c1-50
}

# ============================================
# USAGE
# ============================================
usage() {
  cat <<USAGE
${BOLD}Ralph${RESET} - Autonomous Copilot CLI Runner (v${RALPH_VERSION})

${BOLD}USAGE:${RESET}
  $0 --prompt <file> [options] <iterations>

${BOLD}REQUIRED:${RESET}
  --prompt <file>           Load prompt text from file

${BOLD}PRD SOURCE OPTIONS:${RESET}
  --prd <file>              JSON PRD file (default format)
  --markdown <file>         Markdown PRD with checkboxes (- [ ] task)
  --yaml <file>             YAML task file
  --github <owner/repo>     Fetch tasks from GitHub issues
  --github-label <label>    Filter GitHub issues by label

${BOLD}PERMISSION OPTIONS:${RESET}
  --allow-profile <name>    Tool permission profile: safe | dev | locked
  --allow-tools <toolSpec>  Allow a specific tool (repeatable)
  --deny-tools <toolSpec>   Deny a specific tool (repeatable)

${BOLD}SKILL OPTIONS:${RESET}
  --skill <a[,b,...]>       Prepend skills from skills/<name>/SKILL.md

${BOLD}GIT BRANCH OPTIONS:${RESET}
  --branch-per-task         Create a new git branch for each task
  --base-branch <name>      Base branch to create task branches from
  --create-pr               Create a pull request after each task (requires gh)
  --draft-pr                Create PRs as drafts

${BOLD}WORKFLOW OPTIONS:${RESET}
  --no-tests                Skip running tests (pass to prompt)
  --no-lint                 Skip linting (pass to prompt)
  --fast                    Skip both tests and linting

${BOLD}EXECUTION OPTIONS:${RESET}
  --max-retries <n>         Max retries per iteration on failure (default: 0)
  --retry-delay <n>         Seconds between retries (default: 5)
  --dry-run                 Show what would be done without executing
  -v, --verbose             Show debug output
  -h, --help                Show this help

${BOLD}ENVIRONMENT:${RESET}
  MODEL                     Model to use (default: gpt-5.2)

${BOLD}EXAMPLES:${RESET}
  # Basic usage
  $0 --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe 10

  # With branch per task and PRs
  $0 --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe \\
     --branch-per-task --create-pr 10

  # From markdown PRD
  $0 --prompt prompts/default.txt --markdown PRD.md --allow-profile safe 10

  # From GitHub issues
  $0 --prompt prompts/default.txt --github owner/repo --allow-profile safe 10

  # Fast mode (skip tests/lint)
  $0 --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe --fast 10
USAGE
}

# ============================================
# ARGUMENT PARSING
# ============================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--prompt requires a file path"; usage; exit 1; }
      prompt_file="$1"
      shift
      ;;
    --prd)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--prd requires a file path"; usage; exit 1; }
      prd_file="$1"
      PRD_SOURCE="json"
      shift
      ;;
    --prd=*)
      prd_file="${1#--prd=}"
      PRD_SOURCE="json"
      [[ -z "$prd_file" ]] && { log_error "--prd requires a file path"; usage; exit 1; }
      shift
      ;;
    --markdown)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--markdown requires a file path"; usage; exit 1; }
      prd_file="$1"
      PRD_SOURCE="markdown"
      shift
      ;;
    --yaml)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--yaml requires a file path"; usage; exit 1; }
      prd_file="$1"
      PRD_SOURCE="yaml"
      shift
      ;;
    --github)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--github requires owner/repo"; usage; exit 1; }
      GITHUB_REPO="$1"
      PRD_SOURCE="github"
      shift
      ;;
    --github-label)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--github-label requires a label"; usage; exit 1; }
      GITHUB_LABEL="$1"
      shift
      ;;
    --skill)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--skill requires a value"; usage; exit 1; }
      [[ -n "$skills_csv" ]] && skills_csv+=",$1" || skills_csv="$1"
      shift
      ;;
    --skill=*)
      v="${1#--skill=}"
      [[ -z "$v" ]] && { log_error "--skill requires a value"; usage; exit 1; }
      [[ -n "$skills_csv" ]] && skills_csv+=",$v" || skills_csv="$v"
      shift
      ;;
    --allow-profile)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--allow-profile requires a value"; usage; exit 1; }
      allow_profile="$1"
      shift
      ;;
    --allow-tools)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--allow-tools requires a tool spec"; usage; exit 1; }
      allow_tools+=("$1")
      shift
      ;;
    --deny-tools)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--deny-tools requires a tool spec"; usage; exit 1; }
      deny_tools+=("$1")
      shift
      ;;
    --branch-per-task)
      BRANCH_PER_TASK=true
      shift
      ;;
    --base-branch)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--base-branch requires a branch name"; usage; exit 1; }
      BASE_BRANCH="$1"
      shift
      ;;
    --create-pr)
      CREATE_PR=true
      shift
      ;;
    --draft-pr)
      PR_DRAFT=true
      shift
      ;;
    --no-tests)
      SKIP_TESTS=true
      shift
      ;;
    --no-lint)
      SKIP_LINT=true
      shift
      ;;
    --fast)
      SKIP_TESTS=true
      SKIP_LINT=true
      shift
      ;;
    --max-retries)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--max-retries requires a number"; usage; exit 1; }
      MAX_RETRIES="$1"
      shift
      ;;
    --retry-delay)
      shift
      [[ $# -lt 1 || -z "${1:-}" ]] && { log_error "--retry-delay requires a number"; usage; exit 1; }
      RETRY_DELAY="$1"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      log_error "unknown option: $1"
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# ============================================
# VALIDATION
# ============================================
if [[ $# -lt 1 || -z "${1:-}" ]]; then
  log_error "missing <iterations>"
  usage
  exit 1
fi

if ! [[ "$1" =~ ^[0-9]+$ ]] || [[ "$1" -lt 1 ]]; then
  log_error "<iterations> must be a positive integer"
  usage
  exit 1
fi

iterations="$1"

MODEL="${MODEL:-gpt-5.2}"

if [[ -z "$prompt_file" ]]; then
  log_error "--prompt is required"
  usage
  exit 1
fi

if [[ ! -r "$prompt_file" ]]; then
  log_error "prompt file not readable: $prompt_file"
  exit 1
fi

# Validate PRD source
case "$PRD_SOURCE" in
  json)
    if [[ -n "$prd_file" ]] && [[ ! -r "$prd_file" ]]; then
      log_error "PRD file not readable: $prd_file"
      exit 1
    fi
    ;;
  markdown)
    if [[ ! -r "$prd_file" ]]; then
      log_error "Markdown PRD file not readable: $prd_file"
      exit 1
    fi
    ;;
  yaml)
    if [[ ! -r "$prd_file" ]]; then
      log_error "YAML PRD file not readable: $prd_file"
      exit 1
    fi
    if ! command -v yq &>/dev/null; then
      log_error "yq is required for YAML parsing. Install: brew install yq"
      exit 1
    fi
    ;;
  github)
    if [[ -z "$GITHUB_REPO" ]]; then
      log_error "GitHub repository not specified"
      exit 1
    fi
    if ! command -v gh &>/dev/null; then
      log_error "GitHub CLI (gh) required. Install: brew install gh"
      exit 1
    fi
    ;;
esac

progress_file="progress.txt"
if [[ ! -f "$progress_file" ]]; then
  log_warn "progress.txt not found, creating it..."
  touch "$progress_file"
fi

declare -a skills
skills=()
if [[ -n "$skills_csv" ]]; then
  IFS=',' read -r -a skills <<<"$skills_csv"
fi

if [[ -z "$allow_profile" ]] && [[ ${#allow_tools[@]} -eq 0 ]]; then
  log_error "you must specify --allow-profile or at least one --allow-tools"
  usage
  exit 1
fi

# Set base branch if not specified
if [[ "$BRANCH_PER_TASK" == true ]] && [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  log_debug "Using base branch: $BASE_BRANCH"
fi

# Check gh CLI for PR creation
if [[ "$CREATE_PR" == true ]] && ! command -v gh &>/dev/null; then
  log_error "GitHub CLI (gh) required for --create-pr. Install: brew install gh"
  exit 1
fi

# ============================================
# PRD SOURCE FUNCTIONS
# ============================================

# Get next task from JSON PRD (supports both array and userStories format)
get_next_task_json() {
  if [[ -z "$prd_file" ]]; then
    echo ""
    return
  fi
  
  # Check if it's array format or userStories format
  local is_array
  is_array=$(jq -r 'if type == "array" then "true" else "false" end' "$prd_file" 2>/dev/null || echo "true")
  
  if [[ "$is_array" == "true" ]]; then
    # Array format: find first with passes: false
    jq -r '[.[] | select(.passes == false)] | first | .description // empty' "$prd_file" 2>/dev/null || echo ""
  else
    # userStories format: find first with passes: false, sorted by priority
    jq -r '.userStories | sort_by(.priority) | [.[] | select(.passes == false)] | first | "\(.id // ""): \(.title // .description // "")"' "$prd_file" 2>/dev/null | sed 's/^: //' || echo ""
  fi
}

get_branch_name_json() {
  if [[ -z "$prd_file" ]]; then
    echo ""
    return
  fi
  jq -r '.branchName // empty' "$prd_file" 2>/dev/null || echo ""
}

count_remaining_json() {
  if [[ -z "$prd_file" ]]; then
    echo "0"
    return
  fi
  
  local is_array
  is_array=$(jq -r 'if type == "array" then "true" else "false" end' "$prd_file" 2>/dev/null || echo "true")
  
  if [[ "$is_array" == "true" ]]; then
    jq -r '[.[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "0"
  else
    jq -r '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "0"
  fi
}

# Markdown PRD functions
get_next_task_markdown() {
  grep -m1 '^\- \[ \]' "$prd_file" 2>/dev/null | sed 's/^- \[ \] //' | cut -c1-100 || echo ""
}

count_remaining_markdown() {
  grep -c '^\- \[ \]' "$prd_file" 2>/dev/null || echo "0"
}

mark_task_complete_markdown() {
  local task=$1
  local escaped_task
  escaped_task=$(printf '%s\n' "$task" | sed 's/[[\.*^$/]/\\&/g')
  sed -i.bak "s/^- \[ \] ${escaped_task}/- [x] ${escaped_task}/" "$prd_file"
  rm -f "${prd_file}.bak"
}

# YAML PRD functions
get_next_task_yaml() {
  yq -r '.tasks[] | select(.completed != true) | .title' "$prd_file" 2>/dev/null | head -1 | cut -c1-100 || echo ""
}

count_remaining_yaml() {
  yq -r '[.tasks[] | select(.completed != true)] | length' "$prd_file" 2>/dev/null || echo "0"
}

# GitHub Issues functions
get_next_task_github() {
  local label_filter=""
  [[ -n "$GITHUB_LABEL" ]] && label_filter="--label $GITHUB_LABEL"
  
  gh issue list --repo "$GITHUB_REPO" --state open $label_filter --limit 1 --json number,title \
    --jq '.[0] | "#\(.number): \(.title)"' 2>/dev/null || echo ""
}

count_remaining_github() {
  local label_filter=""
  [[ -n "$GITHUB_LABEL" ]] && label_filter="--label $GITHUB_LABEL"
  
  gh issue list --repo "$GITHUB_REPO" --state open $label_filter --json number \
    --jq 'length' 2>/dev/null || echo "0"
}

# Unified interface
get_next_task() {
  case "$PRD_SOURCE" in
    json) get_next_task_json ;;
    markdown) get_next_task_markdown ;;
    yaml) get_next_task_yaml ;;
    github) get_next_task_github ;;
  esac
}

count_remaining_tasks() {
  case "$PRD_SOURCE" in
    json) count_remaining_json ;;
    markdown) count_remaining_markdown ;;
    yaml) count_remaining_yaml ;;
    github) count_remaining_github ;;
  esac
}

# ============================================
# GIT BRANCH FUNCTIONS
# ============================================
create_task_branch() {
  local task=$1
  local branch_name="ralph/$(slugify "$task")"
  
  log_debug "Creating branch: $branch_name from $BASE_BRANCH"
  
  # Stash any changes
  git stash push -m "ralph-autostash" 2>/dev/null || true
  
  # Create and checkout new branch
  git checkout "$BASE_BRANCH" 2>/dev/null || true
  git pull origin "$BASE_BRANCH" 2>/dev/null || true
  git checkout -b "$branch_name" 2>/dev/null || {
    git checkout "$branch_name" 2>/dev/null || true
  }
  
  # Pop stash if we stashed
  git stash pop 2>/dev/null || true
  
  task_branches+=("$branch_name")
  echo "$branch_name"
}

create_pull_request() {
  local branch=$1
  local task=$2
  
  log_info "Creating pull request for: $task"
  
  local pr_args=("--base" "$BASE_BRANCH" "--head" "$branch" "--title" "feat: $task")
  [[ "$PR_DRAFT" == true ]] && pr_args+=("--draft")
  
  gh pr create "${pr_args[@]}" --body "Automated PR created by Ralph

## Task
$task

## Changes
See commits for details.
" 2>/dev/null || log_warn "Failed to create PR for $branch"
}

merge_task_branch() {
  local branch=$1
  
  log_debug "Merging branch: $branch into $BASE_BRANCH"
  
  git checkout "$BASE_BRANCH" 2>/dev/null || true
  git merge "$branch" --no-edit 2>/dev/null || {
    log_warn "Merge conflict detected, attempting auto-resolution..."
    git merge --abort 2>/dev/null || true
  }
}

# ============================================
# BUILD TOOL PERMISSIONS
# ============================================
declare -a copilot_tool_args

# Always deny dangerous commands
copilot_tool_args+=(--deny-tool 'shell(rm)')
copilot_tool_args+=(--deny-tool 'shell(git push)')

if [[ ${#allow_tools[@]} -eq 0 ]]; then
  if [[ -n "$allow_profile" ]]; then
    case "$allow_profile" in
      dev)
        copilot_tool_args+=(--allow-all-tools)
        copilot_tool_args+=(--allow-tool 'write')
        copilot_tool_args+=(--allow-tool 'shell(pnpm:*)')
        copilot_tool_args+=(--allow-tool 'shell(git:*)')
        ;;
      safe)
        copilot_tool_args+=(--allow-tool 'write')
        copilot_tool_args+=(--allow-tool 'shell(pnpm:*)')
        copilot_tool_args+=(--allow-tool 'shell(git:*)')
        ;;
      locked)
        copilot_tool_args+=(--allow-tool 'write')
        ;;
      *)
        log_error "unknown --allow-profile: $allow_profile"
        usage
        exit 1
        ;;
    esac
  fi
fi

for tool in "${allow_tools[@]+"${allow_tools[@]}"}"; do
  copilot_tool_args+=(--allow-tool "$tool")
done

for tool in "${deny_tools[@]+"${deny_tools[@]}"}"; do
  copilot_tool_args+=(--deny-tool "$tool")
done

# ============================================
# DRY RUN PREVIEW
# ============================================
if [[ "$DRY_RUN" == true ]]; then
  echo ""
  log_info "${BOLD}Dry Run Preview${RESET}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Iterations:      $iterations"
  echo "Model:           $MODEL"
  echo "Prompt:          $prompt_file"
  echo "PRD Source:      $PRD_SOURCE"
  [[ -n "$prd_file" ]] && echo "PRD File:        $prd_file"
  [[ -n "$GITHUB_REPO" ]] && echo "GitHub Repo:     $GITHUB_REPO"
  echo "Branch per task: $BRANCH_PER_TASK"
  echo "Create PR:       $CREATE_PR"
  echo "Skip tests:      $SKIP_TESTS"
  echo "Skip lint:       $SKIP_LINT"
  echo "Max retries:     $MAX_RETRIES"
  echo ""
  echo "Tasks remaining: $(count_remaining_tasks)"
  next_task=$(get_next_task)
  [[ -n "$next_task" ]] && echo "Next task:       $next_task"
  echo ""
  echo "Tool args:       ${copilot_tool_args[*]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

# ============================================
# MAIN LOOP
# ============================================
log_info "Starting Ralph v${RALPH_VERSION}"
log_info "Model: $MODEL | Iterations: $iterations | PRD: $PRD_SOURCE"
[[ "$VERBOSE" == true ]] && log_debug "Verbose mode enabled"

for ((i=1; i<=iterations; i++)); do
  echo ""
  echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  log_info "Iteration $i of $iterations"
  
  # Show current task
  next_task=$(get_next_task)
  remaining=$(count_remaining_tasks)
  [[ -n "$next_task" ]] && log_info "Next task: ${CYAN}$next_task${RESET}"
  log_info "Tasks remaining: $remaining"
  
  # Create task branch if enabled
  current_branch=""
  if [[ "$BRANCH_PER_TASK" == true ]] && [[ -n "$next_task" ]]; then
    current_branch=$(create_task_branch "$next_task")
    log_info "Working on branch: ${CYAN}$current_branch${RESET}"
  fi
  
  # Build context file
  context_file="$(mktemp ".ralph-context.${i}.XXXXXX")"
  {
    echo "# Context"
    echo
    if [[ ${#skills[@]} -gt 0 ]]; then
      echo "## Skills"
      for raw in "${skills[@]}"; do
        skill="$(trim "$raw")"
        [[ -z "$skill" ]] && continue
        skill_file="skills/$skill/SKILL.md"
        if [[ ! -r "$skill_file" ]]; then
          log_error "skill not found/readable: $skill_file"
          exit 1
        fi
        echo
        echo "### $skill"
        echo
        cat "$skill_file"
      done
      echo
    fi
    if [[ -n "$prd_file" ]] && [[ -r "$prd_file" ]]; then
      echo "## PRD ($prd_file)"
      cat "$prd_file"
      echo
    fi
    if [[ "$PRD_SOURCE" == "github" ]]; then
      echo "## GitHub Issues ($GITHUB_REPO)"
      echo "Tasks are fetched from GitHub issues. Mark issues as closed when complete."
      echo
    fi
    echo "## progress.txt"
    cat "$progress_file"
    echo
    # Add workflow flags
    if [[ "$SKIP_TESTS" == true ]] || [[ "$SKIP_LINT" == true ]]; then
      echo "## Workflow Flags"
      [[ "$SKIP_TESTS" == true ]] && echo "- SKIP_TESTS=true (do not run tests)"
      [[ "$SKIP_LINT" == true ]] && echo "- SKIP_LINT=true (do not run linting)"
      echo
    fi
  } >"$context_file"

  # Build combined prompt
  combined_prompt_file="$(mktemp ".ralph-prompt.${i}.XXXXXX")"
  {
    cat "$context_file"
    echo
    echo "# Prompt"
    echo
    cat "$prompt_file"
    echo
  } >"$combined_prompt_file"

  # Execute with retry logic
  retry_count=0
  success=false
  
  while [[ $retry_count -le $MAX_RETRIES ]]; do
    if [[ $retry_count -gt 0 ]]; then
      log_warn "Retry $retry_count of $MAX_RETRIES (waiting ${RETRY_DELAY}s)..."
      sleep "$RETRY_DELAY"
    fi
    
    set +e
    if command -v script >/dev/null 2>&1; then
      transcript_file="$(mktemp -t ralph-copilot.XXXXXX)"
      script -q -F "$transcript_file" \
        copilot --add-dir "$PWD" --model "$MODEL" \
          --no-color --stream off --silent \
          -p "@$combined_prompt_file Follow the attached prompt." \
          "${copilot_tool_args[@]}" \
        >/dev/null 2>&1
      status=$?
      result="$(cat "$transcript_file" 2>/dev/null || true)"
      rm -f "$transcript_file" >/dev/null 2>&1 || true
    else
      result=$(
        copilot --add-dir "$PWD" --model "$MODEL" \
          --no-color --stream off --silent \
          -p "@$combined_prompt_file Follow the attached prompt." \
          "${copilot_tool_args[@]}" \
          2>&1
      )
      status=$?
    fi
    set -e

    if [[ $status -eq 0 ]]; then
      success=true
      break
    fi
    
    ((retry_count++))
  done

  rm -f "$context_file" >/dev/null 2>&1 || true
  rm -f "$combined_prompt_file" >/dev/null 2>&1 || true

  echo "$result"

  if [[ "$success" == false ]]; then
    log_warn "Copilot exited with status $status after $((retry_count)) retries; continuing to next iteration."
    continue
  fi

  # Handle branch workflow
  if [[ "$BRANCH_PER_TASK" == true ]] && [[ -n "$current_branch" ]]; then
    if [[ "$CREATE_PR" == true ]]; then
      create_pull_request "$current_branch" "$next_task"
    else
      merge_task_branch "$current_branch"
    fi
  fi

  # Check for completion signal
  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo ""
    log_success "PRD complete after $i iterations! 🎉"
    
    # Show branches created
    if [[ ${#task_branches[@]} -gt 0 ]]; then
      log_info "Branches created: ${task_branches[*]}"
    fi
    
    # Desktop notification
    if command -v tt >/dev/null 2>&1; then
      tt notify "PRD complete after $i iterations"
    elif command -v osascript >/dev/null 2>&1; then
      osascript -e "display notification \"PRD complete after $i iterations\" with title \"Ralph\""
    fi
    
    exit 0
  fi
done

echo ""
log_warn "Finished $iterations iterations without receiving the completion signal."

# Show branches created
if [[ ${#task_branches[@]} -gt 0 ]]; then
  log_info "Branches created: ${task_branches[*]}"
fi

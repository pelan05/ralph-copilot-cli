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
DRY_RUN=false
VERBOSE=false
SKIP_TESTS=false
SKIP_LINT=false

# PRD source options
PRD_SOURCE="json"  # json, markdown, yaml, github
GITHUB_REPO=""
GITHUB_LABEL=""

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

# ============================================
# USAGE
# ============================================
usage() {
  cat <<USAGE
${BOLD}Ralph (Single Run)${RESET} - Run Copilot CLI Once (v${RALPH_VERSION})

${BOLD}USAGE:${RESET}
  $0 --prompt <file> [options]

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

${BOLD}WORKFLOW OPTIONS:${RESET}
  --no-tests                Skip running tests (pass to prompt)
  --no-lint                 Skip linting (pass to prompt)
  --fast                    Skip both tests and linting

${BOLD}OTHER OPTIONS:${RESET}
  --dry-run                 Show what would be done without executing
  -v, --verbose             Show debug output
  -h, --help                Show this help

${BOLD}ENVIRONMENT:${RESET}
  MODEL                     Model to use (default: gpt-5.2)

${BOLD}EXAMPLES:${RESET}
  # Basic usage
  $0 --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe

  # From markdown PRD
  $0 --prompt prompts/default.txt --markdown PRD.md --allow-profile safe

  # Fast mode (skip tests/lint)
  $0 --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe --fast
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

PROMPT="$(cat "$prompt_file")"

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
  echo "Model:           $MODEL"
  echo "Prompt:          $prompt_file"
  echo "PRD Source:      $PRD_SOURCE"
  [[ -n "$prd_file" ]] && echo "PRD File:        $prd_file"
  [[ -n "$GITHUB_REPO" ]] && echo "GitHub Repo:     $GITHUB_REPO"
  echo "Skip tests:      $SKIP_TESTS"
  echo "Skip lint:       $SKIP_LINT"
  echo ""
  echo "Tool args:       ${copilot_tool_args[*]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

# ============================================
# MAIN EXECUTION
# ============================================
log_info "Starting Ralph v${RALPH_VERSION} (single run)"
log_info "Model: $MODEL | PRD: $PRD_SOURCE"

# Build context file
context_file="$(mktemp .ralph-context.XXXXXX)"
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

combined_prompt_file="$(mktemp .ralph-prompt.XXXXXX)"
{
  cat "$context_file"
  echo
  echo "# Prompt"
  echo
  cat "$prompt_file"
  echo
} >"$combined_prompt_file"

# Execute
set +e
result=$(
  copilot --add-dir "$PWD" --model "$MODEL" \
    --no-color --stream off --silent \
    -p "@$combined_prompt_file Follow the attached prompt." \
    "${copilot_tool_args[@]}" \
    2>&1
)
status=$?

# Fallback to script(1) if empty output
if [[ -z "${result//$'\n'/}" ]] && command -v script >/dev/null 2>&1; then
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
fi

rm -f "$context_file" >/dev/null 2>&1 || true
rm -f "$combined_prompt_file" >/dev/null 2>&1 || true
set -e

echo "$result"
exit "$status"

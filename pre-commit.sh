#!/bin/sh
# POSIX-compliant pre-commit hook for Java AI code review (macOS/Linux)
# Requires: GitHub CLI with Copilot extension installed and authenticated
# Usage: Run install.sh to set up, or manually copy to .git/hooks/pre-commit and make executable
#
# NOTE: Windows users should use the PowerShell version (pre-commit.ps1) instead.
#       The install.ps1 script will set this up automatically.

set -e

# Configuration
AI_DIR=".ai"
CHECKLIST_FILE="$AI_DIR/java_code_review_checklist.yaml"
PROMPT_FILE="$AI_DIR/java_review_prompt.txt"
LAST_REVIEW_FILE="$AI_DIR/last_review.json"
MAX_DIFF_SIZE=20000 # bytes

# Use temporary directory
if [ -n "$TMPDIR" ]; then
  TEMP_DIR="$TMPDIR"
elif [ -d "/tmp" ]; then
  TEMP_DIR="/tmp"
else
  TEMP_DIR="$AI_DIR/temp"
  mkdir -p "$TEMP_DIR"
fi

DIFF_FILE="$TEMP_DIR/java_review_diff_$$.patch"

# Color codes for output
if [ -t 1 ]; then
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  RED=''
  YELLOW=''
  GREEN=''
  BLUE=''
  NC=''
fi

# Cleanup function
cleanup() {
  rm -f "$DIFF_FILE"
}
trap cleanup EXIT

# =============================================================================
# MULTI-AGENT HELPER FUNCTIONS
# =============================================================================

# Run a specialized agent (security, naming, quality)
# Args: $1 = agent_name, $2 = diff_content
run_agent() {
  local AGENT_NAME="$1"
  local DIFF_CONTENT="$2"
  local AGENT_DIR="$AI_DIR/agents/$AGENT_NAME"
  local AGENT_CHECKLIST="$AGENT_DIR/checklist.yaml"
  local AGENT_PROMPT="$AGENT_DIR/prompt.txt"
  local AGENT_OUTPUT="$AGENT_DIR/review.json"
  
  # Check if agent files exist
  if [ ! -f "$AGENT_CHECKLIST" ] || [ ! -f "$AGENT_PROMPT" ]; then
    echo "${RED}[AI Review] Error: Agent '$AGENT_NAME' configuration not found${NC}" >&2
    echo '{"agent":"'$AGENT_NAME'","issues":[],"summary":"Configuration error"}' > "$AGENT_OUTPUT"
    return 1
  fi
  
  # Load checklist and compose prompt
  local CHECKLIST_CONTENT=$(cat "$AGENT_CHECKLIST")
  local AGENT_FULL_PROMPT=$(awk -v checklist="$CHECKLIST_CONTENT" -v diff="$DIFF_CONTENT" '
    /\{checklist\}/ {
      print checklist;
      next;
    }
    /\{diff\}/ {
      print diff;
      next;
    }
    { print }
  ' "$AGENT_PROMPT")
  
  # Call Copilot CLI directly
  REVIEW_OUTPUT=$(copilot -p "$AGENT_FULL_PROMPT" --silent --allow-all-tools --no-color 2>&1 || echo "# Error

Agent failed to execute")
  
  # Save agent output as markdown (no JSON extraction needed)
  mkdir -p "$AGENT_DIR"
  echo "$REVIEW_OUTPUT" > "$AGENT_OUTPUT"
}

# Run summarizer agent to aggregate all results
# Args: $1 = security_json, $2 = naming_json, $3 = quality_json
run_summarizer_agent() {
  local SECURITY_JSON="$1"
  local NAMING_JSON="$2"
  local QUALITY_JSON="$3"
  local SUMMARIZER_PROMPT="$AI_DIR/agents/summarizer/prompt.txt"
  
  if [ ! -f "$SUMMARIZER_PROMPT" ]; then
    echo "${RED}[AI Review] Error: Summarizer prompt not found${NC}" >&2
    return 1
  fi
  
  # Compose summarizer prompt
  local SUMMARIZER_FULL_PROMPT=$(awk -v sec="$SECURITY_JSON" -v nam="$NAMING_JSON" -v qual="$QUALITY_JSON" '
    /\{security_report\}/ {
      print sec;
      next;
    }
    /\{naming_report\}/ {
      print nam;
      next;
    }
    /\{quality_report\}/ {
      print qual;
      next;
    }
    { print }
  ' "$SUMMARIZER_PROMPT")
  
  # Call Copilot CLI
  local FULL_PROMPT="$SUMMARIZER_FULL_PROMPT

CRITICAL: Output ONLY valid JSON."
  SUMMARIZER_OUTPUT=$(copilot -p "$FULL_PROMPT" --silent --allow-all-tools --no-color 2>&1 || echo '{"agent":"summarizer","issues":[],"summary":"API error","recommendation":"ALLOW_COMMIT"}')
  
  # Extract JSON
  local SUMMARIZER_JSON=$(echo "$SUMMARIZER_OUTPUT" | sed -n '/```json/,/```/p' | sed '1d;$d' | tr -d '\n' || echo "")
  if [ -z "$SUMMARIZER_JSON" ]; then
    SUMMARIZER_JSON=$(echo "$SUMMARIZER_OUTPUT" | grep -o '{.*}' | head -1 || echo '{"agent":"summarizer","issues":[],"summary":"Parse error","recommendation":"ALLOW_COMMIT"}')
  fi
  
  # Save final review
  echo "$SUMMARIZER_JSON" > "$LAST_REVIEW_FILE"
  echo "$SUMMARIZER_JSON"
}

# Display agent results summary
# Args: $1 = agent_report (markdown), $2 = agent_name, $3 = agent_display_name
display_agent_results() {
  local AGENT_REPORT="$1"
  local AGENT_NAME="$2"
  local AGENT_DISPLAY="$3"
  
  # Count issues from markdown format (### [SEVERITY])
  local ISSUE_COUNT=$(echo "$AGENT_REPORT" | grep -c '^\### \[' 2>/dev/null || echo "0")
  
  # Extract summary from markdown (first paragraph after ## Summary)
  local SUMMARY=$(echo "$AGENT_REPORT" | sed -n '/^## Summary/,/^##/p' | sed '1d;$d' | head -1 || echo "No summary available")
  if [ -z "$SUMMARY" ] || [ "$SUMMARY" = "No summary available" ]; then
    SUMMARY=$(echo "$AGENT_REPORT" | sed -n '/^## Overall Summary/,/^##/p' | sed '1d;$d' | head -1 || echo "No summary available")
  fi
  
  echo ""
  echo "${BLUE}============================================${NC}"
  echo "${BLUE}$AGENT_DISPLAY Agent Results${NC}"
  echo "${BLUE}============================================${NC}"
  echo "  Summary: $SUMMARY"
  echo "  Issues found: $ISSUE_COUNT"
  
  if [ "$ISSUE_COUNT" -gt 0 ]; then
    echo ""
    # Display issues from markdown (simplified - shows first few lines of each issue)
    echo "$AGENT_REPORT" | grep -A 2 '^\### \[' | head -20
  fi
}

# Check if AI review is enabled (can be disabled with environment variable)
if [ "$AI_REVIEW_ENABLED" = "false" ]; then
  echo "${BLUE}[AI Review]${NC} Skipped (AI_REVIEW_ENABLED=false)"
  exit 0
fi

# Get list of staged Java files FIRST (before expensive dependency checks)
STAGED_JAVA_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.java$' || true)

if [ -z "$STAGED_JAVA_FILES" ]; then
  echo "${BLUE}[AI Review]${NC} No Java files staged, skipping review."
  exit 0
fi

echo "${BLUE}[AI Review]${NC} Found Java files to review:"
echo "$STAGED_JAVA_FILES" | sed 's/^/  - /'

# Dependency checks (only if we have Java files to review)
check_dependency() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "${RED}[AI Review] Error: Required command '$1' not found.${NC}"
    echo ""
    case "$1" in
      copilot)
        echo "GitHub Copilot CLI is required. Install it:"
        echo "  npm install -g @githubnext/github-copilot-cli"
        echo ""
        echo "After installation, authenticate with: copilot auth"
        ;;
    esac
    echo ""
    echo "To bypass this check temporarily, use: git commit --no-verify"
    return 1
  fi
  return 0
}

echo "${BLUE}[AI Review]${NC} Checking dependencies..."

# Check for copilot
if ! check_dependency "copilot"; then
  exit 1
fi
echo "${BLUE}[AI Review]${NC} Found copilot"

# Note: jq is no longer required since we switched to markdown output parsing

# Check if required files exist
if [ ! -f "$CHECKLIST_FILE" ]; then
  echo "${RED}[AI Review] Error: Checklist file not found: $CHECKLIST_FILE${NC}"
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "${RED}[AI Review] Error: Prompt file not found: $PROMPT_FILE${NC}"
  exit 1
fi

# Extract staged diff for Java files only
# Use printf to properly handle filenames with spaces
if [ -n "$STAGED_JAVA_FILES" ]; then
  # Convert newline-separated list to null-separated for proper handling
  printf "%s\n" "$STAGED_JAVA_FILES" | while IFS= read -r file; do
    git diff --cached -- "$file"
  done > "$DIFF_FILE"
else
  touch "$DIFF_FILE"
fi

if [ ! -f "$DIFF_FILE" ]; then
  echo "${RED}[AI Review] Failed to extract staged diff. Aborting commit.${NC}"
  exit 1
fi

# Check if diff is empty
if [ ! -s "$DIFF_FILE" ]; then
  echo "${BLUE}[AI Review]${NC} No changes to review."
  exit 0
fi

# Truncate diff if too large
DIFF_SIZE=$(wc -c < "$DIFF_FILE" | tr -d ' ')
if [ "$DIFF_SIZE" -gt "$MAX_DIFF_SIZE" ]; then
  head -c "$MAX_DIFF_SIZE" "$DIFF_FILE" > "$DIFF_FILE.trunc"
  mv "$DIFF_FILE.trunc" "$DIFF_FILE"
  echo "${YELLOW}[AI Review] Warning: Diff truncated to $MAX_DIFF_SIZE bytes for review.${NC}"
fi

# Security check: Warn if diff may contain sensitive data
# Skip this check if SKIP_SENSITIVE_CHECK=true
if [ "$SKIP_SENSITIVE_CHECK" != "true" ]; then
  if grep -qiE "(password\s*=|secret\s*=|api[_-]?key\s*=|token\s*=|credential|private[_-]?key)" "$DIFF_FILE"; then
    echo ""
    echo "${YELLOW}???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????${NC}"
    echo "${YELLOW}???  SECURITY WARNING: Potential sensitive data detected      ???${NC}"
    echo "${YELLOW}??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????${NC}"
    echo ""
    echo "Your staged code may contain sensitive keywords (password, secret, api_key, etc.)."
    echo "This code will be sent to an external AI service for review."
    echo ""
    echo "Options:"
    echo "  1. Review your staged changes: git diff --cached"
    echo "  2. Use environment variables instead of hardcoded values"
    echo "  3. Skip this check: SKIP_SENSITIVE_CHECK=true git commit ..."
    echo "  4. Skip AI review entirely: git commit --no-verify"
    echo ""
    printf "Continue with AI review? (y/n): "
    read -r response
    if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
      echo "${BLUE}[AI Review]${NC} Commit aborted by user. Review your code for sensitive data."
      exit 1
    fi
  fi
fi

DIFF_CONTENT=$(cat "$DIFF_FILE")

# =============================================================================
# MULTI-AGENT CODE REVIEW
# =============================================================================

echo ""
echo "${BLUE}============================================${NC}"
echo "${BLUE}Multi-Agent Code Review System${NC}"
echo "${BLUE}============================================${NC}"
echo ""
echo "${BLUE}[AI Review]${NC} Launching specialized agents in parallel..."
echo "  ?? Security Agent (checking OWASP vulnerabilities, hardcoded secrets, injection attacks)"
echo "  ?? Naming Agent (checking Java conventions: PascalCase, camelCase, UPPER_SNAKE_CASE)"
echo "  ? Code Quality Agent (checking correctness, thread safety, exception handling)"
echo ""

# Run agents in parallel
echo "${BLUE}[AI Review]${NC} ??? Security Agent: Running..."
run_agent "security" "$DIFF_CONTENT" &
SECURITY_PID=$!

echo "${BLUE}[AI Review]${NC} ??? Naming Agent: Running..."
run_agent "naming" "$DIFF_CONTENT" &
NAMING_PID=$!

echo "${BLUE}[AI Review]${NC} ?? Code Quality Agent: Running..."
run_agent "quality" "$DIFF_CONTENT" &
QUALITY_PID=$!

# Wait for all agents to complete
wait $SECURITY_PID
SECURITY_EXIT=$?
wait $NAMING_PID
NAMING_EXIT=$?
wait $QUALITY_PID
QUALITY_EXIT=$?

# Check if agents completed successfully
if [ $SECURITY_EXIT -ne 0 ] && [ $NAMING_EXIT -ne 0 ] && [ $QUALITY_EXIT -ne 0 ]; then
  echo ""
  printf "${YELLOW}???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????${NC}\n"
  printf "${YELLOW}???  Multi-Agent Review: NOT AVAILABLE                         ???${NC}\n"
  printf "${YELLOW}??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????${NC}\n"
  echo ""
  printf "${GREEN}[AI Review]${NC} Allowing commit (AI service unavailable - manual review recommended)\n"
  echo ""
  exit 0
fi

# Read agent results
SECURITY_REPORT=$(cat "$AI_DIR/agents/security/review.json" 2>/dev/null || echo "Error reading security report")
NAMING_REPORT=$(cat "$AI_DIR/agents/naming/review.json" 2>/dev/null || echo "Error reading naming report")
QUALITY_REPORT=$(cat "$AI_DIR/agents/quality/review.json" 2>/dev/null || echo "Error reading quality report")

# Count issues per agent - try markdown format first, then JSON
SECURITY_COUNT=$(echo "$SECURITY_REPORT" | grep -c '^\### \[' 2>/dev/null)
if [ "$SECURITY_COUNT" = "0" ]; then
  SECURITY_COUNT=$(echo "$SECURITY_REPORT" | grep -c '"severity"' 2>/dev/null || echo "0")
fi

NAMING_COUNT=$(echo "$NAMING_REPORT" | grep -c '^\### \[' 2>/dev/null)
if [ "$NAMING_COUNT" = "0" ]; then
  NAMING_COUNT=$(echo "$NAMING_REPORT" | grep -c '"severity"' 2>/dev/null || echo "0")
fi

QUALITY_COUNT=$(echo "$QUALITY_REPORT" | grep -c '^\### \[' 2>/dev/null)
if [ "$QUALITY_COUNT" = "0" ]; then
  QUALITY_COUNT=$(echo "$QUALITY_REPORT" | grep -c '"severity"' 2>/dev/null || echo "0")
fi

echo "${BLUE}[AI Review]${NC} ??? Security Agent: Complete (found $SECURITY_COUNT issues)"
echo "${BLUE}[AI Review]${NC} ??? Naming Agent: Complete (found $NAMING_COUNT issues)"
echo "${BLUE}[AI Review]${NC} ?? Code Quality Agent: Complete (found $QUALITY_COUNT issues)"

# Run summarizer to aggregate results
echo ""
echo "${BLUE}[AI Review]${NC} Aggregating results from all agents..."
echo "${BLUE}[AI Review]${NC} ? Summarizer Agent: Deduplicating and prioritizing findings..."

FINAL_REPORT=$(run_summarizer_agent "$SECURITY_REPORT" "$NAMING_REPORT" "$QUALITY_REPORT")

echo "${BLUE}[AI Review]${NC} ? Summarizer Agent: Complete"

# Display per-agent results
echo ""
echo "${BLUE}============================================${NC}"
echo "${BLUE}Review Results by Agent${NC}"
echo "${BLUE}============================================${NC}"

display_agent_results "$SECURITY_REPORT" "security" "Security"
display_agent_results "$NAMING_REPORT" "naming" "Naming"
display_agent_results "$QUALITY_REPORT" "quality" "Code Quality"

# Display final summary
echo ""
echo "${BLUE}============================================${NC}"
echo "${BLUE}Final Summary${NC}"
echo "${BLUE}============================================${NC}"
echo ""
# Extract summary from markdown (look for "## Overall Summary" or "## Summary" section)
FINAL_SUMMARY=$(echo "$FINAL_REPORT" | sed -n '/^## Overall Summary/,/^##/p' | sed '1d;$d' | head -1 || echo "Review complete")
if [ -z "$FINAL_SUMMARY" ]; then
  FINAL_SUMMARY=$(echo "$FINAL_REPORT" | sed -n '/^## Summary/,/^##/p' | sed '1d;$d' | head -1 || echo "Review complete")
fi
echo "${BLUE}[AI Review]${NC} $FINAL_SUMMARY"

# Count BLOCK/CRITICAL issues - try markdown first, then JSON
BLOCK_COUNT=$(echo "$FINAL_REPORT" | grep -c '^\### \[BLOCK\]\|^\### \[CRITICAL\]' 2>/dev/null)
if [ "$BLOCK_COUNT" = "0" ]; then
  BLOCK_COUNT=$(echo "$FINAL_REPORT" | grep -ci '"severity".*"critical"\|"severity".*"block"' 2>/dev/null || echo "0")
fi

echo ""

# Make commit decision based on BLOCK issues
if [ "$BLOCK_COUNT" -gt 0 ]; then
  echo ""
  echo "${RED}???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????${NC}"
  echo "${RED}???  AI REVIEW: COMMIT BLOCKED                                ???${NC}"
  echo "${RED}??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????${NC}"
  echo ""
  echo "Found $BLOCK_COUNT critical issue(s):"
  echo ""
  # Display BLOCK issues from final summary
  echo "$FINAL_REPORT" | grep -B 1 -A 5 '^\### \[BLOCK\]\|^\### \[CRITICAL\]'
  echo "${YELLOW}Fix these issues or use 'git commit --no-verify' to bypass.${NC}"
  echo "Review details saved to: $LAST_REVIEW_FILE"
  echo ""
  exit 1
fi

# Show warnings and info (support various severity levels)
WARN_COUNT=$(echo "$FINAL_REPORT" | grep -c '^\### \[WARN\]\|^\### \[WARNING\]' 2>/dev/null)
if [ "$WARN_COUNT" = "0" ]; then
  WARN_COUNT=$(echo "$FINAL_REPORT" | grep -ci '"severity".*"warn"\|"severity".*"medium"\|"severity".*"high"' 2>/dev/null || echo "0")
fi

INFO_COUNT=$(echo "$FINAL_REPORT" | grep -c '^\### \[INFO\]' 2>/dev/null)
if [ "$INFO_COUNT" = "0" ]; then
  INFO_COUNT=$(echo "$FINAL_REPORT" | grep -ci '"severity".*"info"\|"severity".*"low"' 2>/dev/null || echo "0")
fi

if [ "$WARN_COUNT" -gt 0 ] || [ "$INFO_COUNT" -gt 0 ]; then
  echo ""
  echo "${YELLOW}[AI Review] Found $WARN_COUNT warning(s) and $INFO_COUNT info message(s):${NC}"
  echo ""
  if [ "$WARN_COUNT" -gt 0 ]; then
    echo "$FINAL_REPORT" | grep -B 1 -A 5 '^\### \[WARN\]\|^\### \[WARNING\]'
  fi
  if [ "$INFO_COUNT" -gt 0 ]; then
    echo "$FINAL_REPORT" | grep -B 1 -A 5 '^\### \[INFO\]'
  fi
fi

echo ""
echo "${GREEN}[AI Review] ??? Review complete. Allowing commit.${NC}"
echo "Review details saved to: $LAST_REVIEW_FILE"
echo ""
exit 0

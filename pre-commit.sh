#!/bin/sh
# POSIX-compliant pre-commit hook for Java AI code review
# Requires: GitHub CLI with Copilot extension installed and authenticated
# Usage: Run install.sh to set up, or manually copy to .git/hooks/pre-commit and make executable

set -e

# Configuration
AI_DIR=".ai"
CHECKLIST_FILE="$AI_DIR/java_code_review_checklist.yaml"
PROMPT_FILE="$AI_DIR/java_review_prompt.txt"
LAST_REVIEW_FILE="$AI_DIR/last_review.json"
MAX_DIFF_SIZE=20000 # bytes

# Use temporary directory that works across platforms
if [ -n "$TMPDIR" ]; then
  TEMP_DIR="$TMPDIR"
elif [ -d "/tmp" ]; then
  TEMP_DIR="/tmp"
else
  # Fallback for Windows/systems without /tmp
  TEMP_DIR="$AI_DIR/temp"
  mkdir -p "$TEMP_DIR"
fi

DIFF_FILE="$TEMP_DIR/java_review_diff_$$.patch"

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
  rm -f "$DIFF_FILE"
}
trap cleanup EXIT

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
      gh)
        echo "GitHub CLI is required. Install it:"
        echo "  - Windows: winget install --id GitHub.cli"
        echo "  - macOS: brew install gh"
        echo "  - Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
        echo ""
        echo "After installation, authenticate with: gh auth login"
        echo "Then install Copilot: gh extension install github/gh-copilot"
        ;;
      jq)
        echo "jq is required for JSON parsing. Install it:"
        echo "  - Windows: winget install jqlang.jq"
        echo "  - macOS: brew install jq"
        echo "  - Linux: apt install jq (or equivalent)"
        ;;
    esac
    echo ""
    echo "To bypass this check temporarily, use: git commit --no-verify"
    return 1
  fi
  return 0
}

echo "${BLUE}[AI Review]${NC} Checking dependencies..."
if ! check_dependency "gh"; then
  exit 1
fi

if ! check_dependency "jq"; then
  exit 1
fi

# Check if gh copilot extension is installed
if ! gh extension list | grep -q "github/gh-copilot"; then
  echo "${RED}[AI Review] Error: GitHub Copilot CLI extension not installed.${NC}"
  echo ""
  echo "Install it with: gh extension install github/gh-copilot"
  echo "Then authenticate if needed: gh auth login"
  echo ""
  echo "To bypass this check temporarily, use: git commit --no-verify"
  exit 1
fi

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
if ! git diff --cached -- $STAGED_JAVA_FILES > "$DIFF_FILE"; then
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

DIFF_CONTENT=$(cat "$DIFF_FILE")
CHECKLIST_CONTENT=$(cat "$CHECKLIST_FILE")

# Compose prompt for GitHub Copilot using awk for proper substitution
REVIEW_PROMPT=$(awk -v checklist="$CHECKLIST_CONTENT" -v diff="$DIFF_CONTENT" '
  /\{checklist\}/ {
    print checklist;
    next;
  }
  /\{diff\}/ {
    print diff;
    next;
  }
  { print }
' "$PROMPT_FILE")

echo "${BLUE}[AI Review]${NC} Analyzing code with GitHub Copilot..."

# Call GitHub Copilot CLI
# Note: gh copilot explain/suggest don't support custom prompts well
# We'll use a workaround by creating a temp script
COPILOT_SCRIPT="$TEMP_DIR/copilot_query_$$.txt"
echo "$REVIEW_PROMPT" > "$COPILOT_SCRIPT"

# Try to get JSON response from Copilot
# Since gh copilot doesn't have a direct JSON API mode, we'll use suggest with special formatting
REVIEW_OUTPUT=$(cat "$COPILOT_SCRIPT" | gh copilot suggest --target shell 2>/dev/null || echo "")
RETCODE=$?

# If that doesn't work, try explain mode
if [ $RETCODE -ne 0 ] || [ -z "$REVIEW_OUTPUT" ]; then
  echo "${YELLOW}[AI Review] Trying alternative Copilot API...${NC}"
  # For demonstration, we'll create a mock response structure
  # In production, this would integrate with the actual Copilot API
  REVIEW_JSON='{"summary": "AI review unavailable - GitHub Copilot CLI integration pending", "issues": []}'
  
  echo "${YELLOW}[AI Review] Warning: Could not connect to GitHub Copilot.${NC}"
  echo "${YELLOW}Note: This is a demonstration project. For production use, integrate with:${NC}"
  echo "  - GitHub Copilot API (when available)"
  echo "  - OpenAI API"
  echo "  - Azure OpenAI"
  echo "  - Other LLM providers"
  echo ""
  echo "${GREEN}[AI Review] Allowing commit (no AI service configured).${NC}"
  exit 0
fi

rm -f "$COPILOT_SCRIPT"

# Try to extract JSON from the response
# The response might be wrapped in markdown or have explanatory text
REVIEW_JSON=$(echo "$REVIEW_OUTPUT" | grep -o '{.*}' | head -1 || echo '{"summary": "Parse error", "issues": []}')

# Save review output
mkdir -p "$AI_DIR"
echo "$REVIEW_JSON" > "$LAST_REVIEW_FILE"

# Validate JSON structure
if ! echo "$REVIEW_JSON" | jq -e . >/dev/null 2>&1; then
  echo "${YELLOW}[AI Review] Warning: Could not parse AI response as JSON.${NC}"
  echo "Response saved to: $LAST_REVIEW_FILE"
  echo ""
  echo "${GREEN}[AI Review] Allowing commit (parse error).${NC}"
  exit 0
fi

# Parse JSON for BLOCK issues
BLOCK_ISSUES=$(echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="BLOCK")')
BLOCK_COUNT=$(echo "$REVIEW_JSON" | jq -r '[.issues[] | select(.severity=="BLOCK")] | length')

if [ "$BLOCK_COUNT" -gt 0 ]; then
  echo ""
  echo "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo "${RED}║  AI REVIEW: COMMIT BLOCKED                                ║${NC}"
  echo "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "Found $BLOCK_COUNT critical issue(s):"
  echo ""
  echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="BLOCK") | "  ❌ [\(.severity)] \(.file):\(.line)\n     \(.message)\n"'
  echo "${YELLOW}Fix these issues or use 'git commit --no-verify' to bypass.${NC}"
  echo "Review details saved to: $LAST_REVIEW_FILE"
  echo ""
  exit 1
fi

# Show warnings and info
WARN_COUNT=$(echo "$REVIEW_JSON" | jq -r '[.issues[] | select(.severity=="WARN")] | length')
INFO_COUNT=$(echo "$REVIEW_JSON" | jq -r '[.issues[] | select(.severity=="INFO")] | length')

if [ "$WARN_COUNT" -gt 0 ] || [ "$INFO_COUNT" -gt 0 ]; then
  echo ""
  echo "${YELLOW}[AI Review] Found $WARN_COUNT warning(s) and $INFO_COUNT info message(s):${NC}"
  echo ""
  if [ "$WARN_COUNT" -gt 0 ]; then
    echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="WARN") | "  ⚠️  [\(.severity)] \(.file):\(.line)\n     \(.message)\n"'
  fi
  if [ "$INFO_COUNT" -gt 0 ]; then
    echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="INFO") | "  ℹ️  [\(.severity)] \(.file):\(.line)\n     \(.message)\n"'
  fi
fi

# Show summary
SUMMARY=$(echo "$REVIEW_JSON" | jq -r '.summary')
if [ -n "$SUMMARY" ] && [ "$SUMMARY" != "null" ]; then
  echo "${GREEN}[AI Review] ${SUMMARY}${NC}"
fi

echo "${GREEN}[AI Review] ✓ Review complete. Allowing commit.${NC}"
echo ""
exit 0

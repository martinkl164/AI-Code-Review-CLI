#!/bin/sh
# POSIX-compliant pre-commit hook for Java AI code review
# Requires: GitHub CLI with Copilot extension installed and authenticated
# Usage: Run install.sh to set up, or manually copy to .git/hooks/pre-commit and make executable

set -e

# Add common Windows paths for tools (PowerShell/npm installed tools)
COPILOT_FULL_PATH=""
JQ_FULL_PATH=""

if [ -d "/c/Users" ]; then
  # Running on Windows with Git Bash
  USER_HOME=$(echo ~)
  APPDATA=$(cmd.exe //c "echo %APPDATA%" 2>/dev/null | tr -d '\r')
  LOCALAPPDATA=$(cmd.exe //c "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')
  
  # Find copilot.cmd (convert Windows path to Git Bash path)
  if [ -d "$APPDATA/npm" ]; then
    if [ -f "$APPDATA/npm/copilot.cmd" ]; then
      COPILOT_FULL_PATH="$APPDATA/npm/copilot.cmd"
      export PATH="$APPDATA/npm:$PATH"
    fi
  fi
  
  # Find jq.exe
  if [ -d "$LOCALAPPDATA/Microsoft/WinGet/Packages" ]; then
    JQ_FULL_PATH=$(find "$LOCALAPPDATA/Microsoft/WinGet/Packages" -name "jq.exe" 2>/dev/null | head -1)
    if [ -n "$JQ_FULL_PATH" ]; then
      export PATH="$(dirname "$JQ_FULL_PATH"):$PATH"
    fi
  fi
fi

# Configuration
AI_DIR=".ai"
CHECKLIST_FILE="$AI_DIR/java_code_review_checklist.yaml"
PROMPT_FILE="$AI_DIR/java_review_prompt.txt"
LAST_REVIEW_FILE="$AI_DIR/last_review.json"
MAX_DIFF_SIZE=20000 # bytes

# Use temporary directory that works across platforms
# On Windows, use .ai/temp to avoid path issues
if [ -d "/c/Users" ]; then
  TEMP_DIR="$AI_DIR/temp"
  mkdir -p "$TEMP_DIR"
elif [ -n "$TMPDIR" ]; then
  TEMP_DIR="$TMPDIR"
elif [ -d "/tmp" ]; then
  TEMP_DIR="/tmp"
else
  TEMP_DIR="$AI_DIR/temp"
  mkdir -p "$TEMP_DIR"
fi

DIFF_FILE="$TEMP_DIR/java_review_diff_$$.patch"

# Color codes for output (disabled on Windows by default for better compatibility)
# Set FORCE_COLOR=true to enable colors
if [ "$FORCE_COLOR" = "true" ] && [ -t 1 ]; then
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

# Check for copilot
if [ -d "/c/Users" ]; then
  # On Windows, use PowerShell to check for copilot
  if powershell.exe -Command "Get-Command copilot -ErrorAction SilentlyContinue" >/dev/null 2>&1; then
    echo "${BLUE}[AI Review]${NC} Found copilot (via PowerShell)"
  else
    echo "${RED}[AI Review] Error: Required command 'copilot' not found.${NC}"
    echo ""
    echo "GitHub Copilot CLI is required. Install it:"
    echo "  - npm: npm install -g @githubnext/github-copilot-cli"
    echo ""
    echo "After installation, authenticate with: copilot auth"
    echo ""
    echo "To bypass this check temporarily, use: git commit --no-verify"
    exit 1
  fi
else
  # On Unix, check directly
  if ! check_dependency "copilot"; then
    exit 1
  fi
fi

if ! check_dependency "jq"; then
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

# Security check: Warn if diff may contain sensitive data
# Skip this check if SKIP_SENSITIVE_CHECK=true
if [ "$SKIP_SENSITIVE_CHECK" != "true" ]; then
  if grep -qiE "(password\s*=|secret\s*=|api[_-]?key\s*=|token\s*=|credential|private[_-]?key)" "$DIFF_FILE"; then
    echo ""
    echo "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo "${YELLOW}║  SECURITY WARNING: Potential sensitive data detected      ║${NC}"
    echo "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
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

printf "${BLUE}[AI Review]${NC} Sending code to Copilot CLI for analysis...\n"

# Call Standalone Copilot CLI

# On Windows (Git Bash), use PowerShell script
if [ -d "/c/Users" ]; then
  mkdir -p "$AI_DIR/temp"
  
  # Save diff to file  
  DIFF_FILE_PS="$AI_DIR/temp/review_diff_$$.txt"
  echo "$DIFF_CONTENT" > "$DIFF_FILE_PS"
  
  # Create a self-contained PowerShell script that does everything
  PS_RUNNER="$AI_DIR/temp/run_review_$$.ps1"
  cat > "$PS_RUNNER" << 'PSEOF'
param([string]$DiffFile)

$diffContent = Get-Content -LiteralPath $DiffFile -Raw -ErrorAction SilentlyContinue
if (-not $diffContent) { Write-Output "Error: Could not read diff file"; exit 1 }

# Escape special characters and build a clean single-line prompt  
$cleanDiff = $diffContent -replace "`r`n", " " -replace "`n", " " -replace '"', "'" -replace '\s+', ' '
$cleanDiff = $cleanDiff.Substring(0, [Math]::Min(2000, $cleanDiff.Length))

$prompt = "Review this Java code for security issues. Return JSON: {issues:[{severity:CRITICAL,type:string,description:string}]}. Code: $cleanDiff"

# Call copilot with properly escaped argument using --% to stop parsing
try {
    $argList = @('-p', $prompt, '--silent', '--allow-all-tools', '--no-color')
    $result = & copilot @argList 2>&1
    Write-Output $result
} catch {
    Write-Output "Error: $_"
}
PSEOF

  # Get Windows paths
  WIN_DIFF=$(powershell.exe -NoProfile -Command "(Resolve-Path '$DIFF_FILE_PS').Path" 2>/dev/null | tr -d '\r\n')
  WIN_RUNNER=$(powershell.exe -NoProfile -Command "(Resolve-Path '$PS_RUNNER').Path" 2>/dev/null | tr -d '\r\n')
  
  # Run the PowerShell script
  REVIEW_OUTPUT=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_RUNNER" -DiffFile "$WIN_DIFF" 2>&1)
  RETCODE=$?
  
  rm -f "$DIFF_FILE_PS" "$PS_RUNNER"
else
  # On Unix, call copilot directly
  FULL_PROMPT="$REVIEW_PROMPT

CRITICAL: Output ONLY valid JSON."
  REVIEW_OUTPUT=$(copilot -p "$FULL_PROMPT" --silent --allow-all-tools --no-color 2>&1 || echo "")
  RETCODE=$?
fi

# Check API availability and response
if [ $RETCODE -ne 0 ] || [ -z "$REVIEW_OUTPUT" ]; then
  echo ""
  printf "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}\n"
  printf "${YELLOW}║  GitHub Copilot CLI: NOT AVAILABLE                        ║${NC}\n"
  printf "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}\n"
  echo ""
  echo "API Status:"
  echo "  • Standalone GitHub Copilot CLI: NOT RESPONDING"
  echo "  • Command: copilot -p <prompt> --silent --allow-all-tools"
  echo "  • Exit code: $RETCODE"
  echo ""
  echo "Possible reasons:"
  echo "  1. GitHub Copilot subscription not active"
  echo "  2. Copilot CLI not authenticated (run: copilot auth or copilot)"
  echo "  3. Network connectivity issues"
  echo "  4. CLI version outdated (run: copilot update)"
  echo ""
  echo "Alternative AI Review APIs:"
  echo "  • OpenAI GPT-4: https://platform.openai.com/docs"
  echo "  • Azure OpenAI: https://azure.microsoft.com/products/ai-services/openai-service"
  echo "  • Claude (Anthropic): https://www.anthropic.com/api"
  echo "  • Local LLM (Ollama): https://ollama.ai"
  echo ""
  printf "${GREEN}[AI Review]${NC} Allowing commit (AI service unavailable - manual review recommended)\n"
  echo ""
  exit 0
fi

# Response received, process it

# Save raw output for debugging
echo "$REVIEW_OUTPUT" > "$AI_DIR/last_review_raw.txt"

# Try to extract JSON from the response
# Copilot often wraps JSON in markdown code blocks: ```json ... ```
# Method 1: Try to extract from markdown code block
REVIEW_JSON=$(echo "$REVIEW_OUTPUT" | sed -n '/```json/,/```/p' | sed '1d;$d' | tr -d '\n' || echo "")

# Method 2: If that fails, try simple grep for JSON object
if [ -z "$REVIEW_JSON" ] || [ "$REVIEW_JSON" = "" ]; then
  REVIEW_JSON=$(echo "$REVIEW_OUTPUT" | grep -o '{.*}' | head -1 || echo '{"summary": "Parse error", "issues": []}')
fi

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

# Parse JSON for BLOCK issues (support both BLOCK and CRITICAL severity)
BLOCK_ISSUES=$(echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="BLOCK" or .severity=="CRITICAL")' 2>/dev/null)
BLOCK_COUNT=$(echo "$REVIEW_JSON" | jq -r '[.issues[] | select(.severity=="BLOCK" or .severity=="CRITICAL")] | length' 2>/dev/null)

if [ "$BLOCK_COUNT" -gt 0 ]; then
  echo ""
  echo "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo "${RED}║  AI REVIEW: COMMIT BLOCKED                                ║${NC}"
  echo "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "Found $BLOCK_COUNT critical issue(s):"
  echo ""
  # Display issues - description includes file:line info from Copilot
  echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="BLOCK" or .severity=="CRITICAL") | 
    "  ❌ [\(.severity)] \(.type // "Issue")\n     \(.description // .message // "No details")\n"' 2>/dev/null
  echo "${YELLOW}Fix these issues or use 'git commit --no-verify' to bypass.${NC}"
  echo "Review details saved to: $LAST_REVIEW_FILE"
  echo ""
  exit 1
fi

# Show warnings and info (support various severity levels)
WARN_COUNT=$(echo "$REVIEW_JSON" | jq -r '[.issues[] | select(.severity=="WARN" or .severity=="WARNING" or .severity=="ERROR" or .severity=="HIGH")] | length' 2>/dev/null)
INFO_COUNT=$(echo "$REVIEW_JSON" | jq -r '[.issues[] | select(.severity=="INFO" or .severity=="LOW")] | length' 2>/dev/null)

if [ "$WARN_COUNT" -gt 0 ] || [ "$INFO_COUNT" -gt 0 ]; then
  echo ""
  echo "${YELLOW}[AI Review] Found $WARN_COUNT warning(s) and $INFO_COUNT info message(s):${NC}"
  echo ""
  if [ "$WARN_COUNT" -gt 0 ]; then
    echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="WARN" or .severity=="WARNING" or .severity=="ERROR" or .severity=="HIGH") | 
      "  ⚠️  [\(.severity)] \(.type // "Warning")\n     \(.description // .message // "No details")\n"' 2>/dev/null
  fi
  if [ "$INFO_COUNT" -gt 0 ]; then
    echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="INFO" or .severity=="LOW") | 
      "  ℹ️  [\(.severity)] \(.type // "Info")\n     \(.description // .message // "No details")\n"' 2>/dev/null
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

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
  
  # Call Copilot CLI based on platform
  if [ -d "/c/Users" ]; then
    # Windows (Git Bash) - use PowerShell
    mkdir -p "$AI_DIR/temp"
    local DIFF_FILE_PS="$AI_DIR/temp/${AGENT_NAME}_diff_$$.txt"
    echo "$DIFF_CONTENT" > "$DIFF_FILE_PS"
    
    local PS_RUNNER="$AI_DIR/temp/${AGENT_NAME}_runner_$$.ps1"
    cat > "$PS_RUNNER" << 'PSEOF'
param([string]$DiffFile, [string]$AgentName)

$diffContent = Get-Content -LiteralPath $DiffFile -Raw -ErrorAction SilentlyContinue
if (-not $diffContent) { Write-Output '{"agent":"'+$AgentName+'","issues":[],"summary":"Error reading diff"}'; exit 1 }

$cleanDiff = $diffContent -replace "`r`n", " " -replace "`n", " " -replace '"', "'" -replace '\s+', ' '
$cleanDiff = $cleanDiff.Substring(0, [Math]::Min(2000, $cleanDiff.Length))

$prompt = "Review this Java code as $AgentName agent. Return JSON: {agent:'$AgentName',issues:[{severity:string,type:string,description:string}]}. Code: $cleanDiff"

try {
    $argList = @('-p', $prompt, '--silent', '--allow-all-tools', '--no-color')
    $result = & copilot @argList 2>&1
    Write-Output $result
} catch {
    Write-Output '{"agent":"'+$AgentName+'","issues":[],"summary":"API error"}'
}
PSEOF
    
    local WIN_DIFF=$(powershell.exe -NoProfile -Command "(Resolve-Path '$DIFF_FILE_PS').Path" 2>/dev/null | tr -d '\r\n')
    local WIN_RUNNER=$(powershell.exe -NoProfile -Command "(Resolve-Path '$PS_RUNNER').Path" 2>/dev/null | tr -d '\r\n')
    
    local REVIEW_OUTPUT=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_RUNNER" -DiffFile "$WIN_DIFF" -AgentName "$AGENT_NAME" 2>&1)
    
    rm -f "$DIFF_FILE_PS" "$PS_RUNNER"
  else
    # Unix - call copilot directly
    local FULL_PROMPT="$AGENT_FULL_PROMPT

CRITICAL: Output ONLY valid JSON."
    REVIEW_OUTPUT=$(copilot -p "$FULL_PROMPT" --silent --allow-all-tools --no-color 2>&1 || echo '{"agent":"'$AGENT_NAME'","issues":[],"summary":"API error"}')
  fi
  
  # Extract JSON from response
  local REVIEW_JSON=$(echo "$REVIEW_OUTPUT" | sed -n '/```json/,/```/p' | sed '1d;$d' | tr -d '\n' || echo "")
  if [ -z "$REVIEW_JSON" ]; then
    REVIEW_JSON=$(echo "$REVIEW_OUTPUT" | grep -o '{.*}' | head -1 || echo '{"agent":"'$AGENT_NAME'","issues":[],"summary":"Parse error"}')
  fi
  
  # Save agent output
  mkdir -p "$AGENT_DIR"
  echo "$REVIEW_JSON" > "$AGENT_OUTPUT"
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
  if [ -d "/c/Users" ]; then
    # Windows PowerShell
    mkdir -p "$AI_DIR/temp"
    local PS_RUNNER="$AI_DIR/temp/summarizer_runner_$$.ps1"
    cat > "$PS_RUNNER" << 'PSEOF'
param([string]$Prompt)
try {
    $argList = @('-p', $Prompt, '--silent', '--allow-all-tools', '--no-color')
    $result = & copilot @argList 2>&1
    Write-Output $result
} catch {
    Write-Output '{"agent":"summarizer","issues":[],"summary":"API error","recommendation":"ALLOW_COMMIT"}'
}
PSEOF
    
    local WIN_RUNNER=$(powershell.exe -NoProfile -Command "(Resolve-Path '$PS_RUNNER').Path" 2>/dev/null | tr -d '\r\n')
    SUMMARIZER_OUTPUT=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_RUNNER" -Prompt "$SUMMARIZER_FULL_PROMPT" 2>&1)
    rm -f "$PS_RUNNER"
  else
    # Unix
    local FULL_PROMPT="$SUMMARIZER_FULL_PROMPT

CRITICAL: Output ONLY valid JSON."
    SUMMARIZER_OUTPUT=$(copilot -p "$FULL_PROMPT" --silent --allow-all-tools --no-color 2>&1 || echo '{"agent":"summarizer","issues":[],"summary":"API error","recommendation":"ALLOW_COMMIT"}')
  fi
  
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
# Args: $1 = agent_json, $2 = agent_name, $3 = agent_display_name
display_agent_results() {
  local AGENT_JSON="$1"
  local AGENT_NAME="$2"
  local AGENT_DISPLAY="$3"
  
  local ISSUE_COUNT=$(echo "$AGENT_JSON" | jq -r '.issues | length' 2>/dev/null || echo "0")
  local SUMMARY=$(echo "$AGENT_JSON" | jq -r '.summary' 2>/dev/null || echo "No summary")
  
  echo ""
  echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo "${BLUE}$AGENT_DISPLAY Agent Results${NC}"
  echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo "  Summary: $SUMMARY"
  echo "  Issues found: $ISSUE_COUNT"
  
  if [ "$ISSUE_COUNT" -gt 0 ]; then
    echo ""
    echo "$AGENT_JSON" | jq -r '.issues[] | 
      "  [\(.severity)] \(.file):\(.line)\n    → \(.message)\n"' 2>/dev/null || echo "  (Unable to parse issues)"
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
    echo "${YELLOW}ΓòöΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòù${NC}"
    echo "${YELLOW}Γòæ  SECURITY WARNING: Potential sensitive data detected      Γòæ${NC}"
    echo "${YELLOW}ΓòÜΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓò¥${NC}"
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
echo "  → Security Agent (checking OWASP vulnerabilities, hardcoded secrets, injection attacks)"
echo "  → Naming Agent (checking Java conventions: PascalCase, camelCase, UPPER_SNAKE_CASE)"
echo "  → Code Quality Agent (checking correctness, thread safety, exception handling)"
echo ""

# Run agents in parallel
echo "${BLUE}[AI Review]${NC} ⏳ Security Agent: Running..."
run_agent "security" "$DIFF_CONTENT" &
SECURITY_PID=$!

echo "${BLUE}[AI Review]${NC} ⏳ Naming Agent: Running..."
run_agent "naming" "$DIFF_CONTENT" &
NAMING_PID=$!

echo "${BLUE}[AI Review]${NC} ⏳ Code Quality Agent: Running..."
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
  printf "${YELLOW}ΓòöΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòù${NC}\n"
  printf "${YELLOW}Γòæ  Multi-Agent Review: NOT AVAILABLE                         Γòæ${NC}\n"
  printf "${YELLOW}ΓòÜΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓò¥${NC}\n"
  echo ""
  printf "${GREEN}[AI Review]${NC} Allowing commit (AI service unavailable - manual review recommended)\n"
  echo ""
  exit 0
fi

# Read agent results
SECURITY_JSON=$(cat "$AI_DIR/agents/security/review.json" 2>/dev/null || echo '{"agent":"security","issues":[],"summary":"Error"}')
NAMING_JSON=$(cat "$AI_DIR/agents/naming/review.json" 2>/dev/null || echo '{"agent":"naming","issues":[],"summary":"Error"}')
QUALITY_JSON=$(cat "$AI_DIR/agents/quality/review.json" 2>/dev/null || echo '{"agent":"quality","issues":[],"summary":"Error"}')

# Count issues per agent
SECURITY_COUNT=$(echo "$SECURITY_JSON" | jq -r '.issues | length' 2>/dev/null || echo "0")
NAMING_COUNT=$(echo "$NAMING_JSON" | jq -r '.issues | length' 2>/dev/null || echo "0")
QUALITY_COUNT=$(echo "$QUALITY_JSON" | jq -r '.issues | length' 2>/dev/null || echo "0")

echo "${BLUE}[AI Review]${NC} ✓ Security Agent: Complete (found $SECURITY_COUNT issues)"
echo "${BLUE}[AI Review]${NC} ✓ Naming Agent: Complete (found $NAMING_COUNT issues)"
echo "${BLUE}[AI Review]${NC} ✓ Code Quality Agent: Complete (found $QUALITY_COUNT issues)"

# Run summarizer to aggregate results
echo ""
echo "${BLUE}[AI Review]${NC} Aggregating results from all agents..."
echo "${BLUE}[AI Review]${NC} ⏳ Summarizer Agent: Deduplicating and prioritizing findings..."

FINAL_JSON=$(run_summarizer_agent "$SECURITY_JSON" "$NAMING_JSON" "$QUALITY_JSON")

# Validate final JSON
if ! echo "$FINAL_JSON" | jq -e . >/dev/null 2>&1; then
  echo "${YELLOW}[AI Review] Warning: Could not parse summarizer response as JSON.${NC}"
  echo ""
  echo "${GREEN}[AI Review] Allowing commit (parse error).${NC}"
  exit 0
fi

echo "${BLUE}[AI Review]${NC} ✓ Summarizer Agent: Complete"

# Display per-agent results
echo ""
echo "${BLUE}============================================${NC}"
echo "${BLUE}Review Results by Agent${NC}"
echo "${BLUE}============================================${NC}"

display_agent_results "$SECURITY_JSON" "security" "Security"
display_agent_results "$NAMING_JSON" "naming" "Naming"
display_agent_results "$QUALITY_JSON" "quality" "Code Quality"

# Display final summary
echo ""
echo "${BLUE}============================================${NC}"
echo "${BLUE}Final Summary${NC}"
echo "${BLUE}============================================${NC}"
echo ""
FINAL_SUMMARY=$(echo "$FINAL_JSON" | jq -r '.summary' 2>/dev/null || echo "No summary")
echo "${BLUE}[AI Review]${NC} $FINAL_SUMMARY"

# Parse JSON for BLOCK issues
BLOCK_COUNT=$(echo "$FINAL_JSON" | jq -r '[.issues[] | select(.severity=="BLOCK" or .severity=="CRITICAL")] | length' 2>/dev/null || echo "0")

echo ""

# Make commit decision based on BLOCK issues
if [ "$BLOCK_COUNT" -gt 0 ]; then
  echo ""
  echo "${RED}ΓòöΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòù${NC}"
  echo "${RED}Γòæ  AI REVIEW: COMMIT BLOCKED                                Γòæ${NC}"
  echo "${RED}ΓòÜΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓò¥${NC}"
  echo ""
  echo "Found $BLOCK_COUNT critical issue(s):"
  echo ""
  # Display BLOCK issues from final summary
  echo "$FINAL_JSON" | jq -r '.issues[] | select(.severity=="BLOCK" or .severity=="CRITICAL") | 
    "  Γ¥î [\(.severity)] [\(.agent)] \(.file):\(.line)\n     \(.message)\n"' 2>/dev/null
  echo "${YELLOW}Fix these issues or use 'git commit --no-verify' to bypass.${NC}"
  echo "Review details saved to: $LAST_REVIEW_FILE"
  echo ""
  exit 1
fi

# Show warnings and info (support various severity levels)
WARN_COUNT=$(echo "$FINAL_JSON" | jq -r '[.issues[] | select(.severity=="WARN" or .severity=="WARNING")] | length' 2>/dev/null || echo "0")
INFO_COUNT=$(echo "$FINAL_JSON" | jq -r '[.issues[] | select(.severity=="INFO")] | length' 2>/dev/null || echo "0")

if [ "$WARN_COUNT" -gt 0 ] || [ "$INFO_COUNT" -gt 0 ]; then
  echo ""
  echo "${YELLOW}[AI Review] Found $WARN_COUNT warning(s) and $INFO_COUNT info message(s):${NC}"
  echo ""
  if [ "$WARN_COUNT" -gt 0 ]; then
    echo "$FINAL_JSON" | jq -r '.issues[] | select(.severity=="WARN" or .severity=="WARNING") | 
      "  ΓÜá∩╕Å  [\(.severity)] [\(.agent)] \(.file):\(.line)\n     \(.message)\n"' 2>/dev/null
  fi
  if [ "$INFO_COUNT" -gt 0 ]; then
    echo "$FINAL_JSON" | jq -r '.issues[] | select(.severity=="INFO") | 
      "  Γä╣∩╕Å  [\(.severity)] [\(.agent)] \(.file):\(.line)\n     \(.message)\n"' 2>/dev/null
  fi
fi

echo ""
echo "${GREEN}[AI Review] Γ£ô Review complete. Allowing commit.${NC}"
echo "Review details saved to: $LAST_REVIEW_FILE"
echo ""
exit 0

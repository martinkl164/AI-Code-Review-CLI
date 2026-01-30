# Multi-Agent Code Review System

## Overview

This directory contains the configuration for a multi-agent code review system that runs specialized AI agents in parallel to analyze code from different perspectives.

## Architecture

```
┌─────────────────┐
│  Git Commit     │
└────────┬────────┘
         │
         ├──────────────────┬──────────────────┬──────────────────┐
         │                  │                  │                  │
         v                  v                  v                  v
┌────────────────┐  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ Security Agent │  │ Naming Agent   │  │ Quality Agent  │  │                │
│ - OWASP Top 10 │  │ - PascalCase   │  │ - NPE Risks    │  │                │
│ - Secrets      │  │ - camelCase    │  │ - Thread Safe  │  │                │
│ - SQL Injection│  │ - UPPER_SNAKE  │  │ - Exceptions   │  │                │
└───────┬────────┘  └───────┬────────┘  └───────┬────────┘  │                │
        │                   │                   │             │                │
        │                   │                   │             │                │
        v                   v                   v             v                v
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ security/      │  │ naming/        │  │ quality/       │
│ review.md      │  │ review.md      │  │ review.md      │
└───────┬────────┘  └───────┬────────┘  └───────┬────────┘
        │                   │                   │
        └───────────────────┴───────────────────┘
                            │
                            v
                   ┌────────────────┐
                   │ Summarizer     │
                   │ Agent          │
                   │ - Aggregates   │
                   │ - Deduplicates │
                   │ - Prioritizes  │
                   └────────┬───────┘
                            │
                            v
                   ┌────────────────┐
                   │ Final Decision │
                   │ BLOCK/ALLOW    │
                   └────────────────┘
```

## Agents

### 1. Security Agent (`security/`)
**Focus**: OWASP Top 10 security vulnerabilities

**Checks**:
- Hardcoded secrets, passwords, API keys
- SQL injection vulnerabilities
- Command injection (Runtime.exec, ProcessBuilder)
- Path traversal attacks
- XXE vulnerabilities
- Unsafe deserialization
- Insecure random number generation
- Logging sensitive data

**Severity**: All issues are BLOCK (prevents commit)

**Files**:
- `checklist.yaml` - Security rules
- `prompt.txt` - Security-focused prompt
- `review.md` - Generated results (gitignored)

### 2. Naming Agent (`naming/`)
**Focus**: Java naming conventions and code style

**Checks**:
- Class names: PascalCase
- Method names: camelCase
- Variable names: camelCase
- Constants: UPPER_SNAKE_CASE
- Package names: lowercase.with.dots
- Avoid Hungarian notation, underscores, single letters

**Severity**: All issues are INFO (allows commit with suggestions)

**Files**:
- `checklist.yaml` - Naming convention rules
- `prompt.txt` - Naming-focused prompt
- `review.md` - Generated results (gitignored)

### 3. Code Quality Agent (`quality/`)
**Focus**: Code correctness, thread safety, best practices

**Checks**:
- NullPointerException risks (BLOCK)
- Thread safety issues (BLOCK)
- Exception handling (WARN)
- Performance issues (WARN)
- Resource leaks (WARN)
- Missing input validation (WARN)
- Missing tests (WARN)

**Severity**: BLOCK for critical issues, WARN for quality issues

**Files**:
- `checklist.yaml` - Quality rules
- `prompt.txt` - Quality-focused prompt
- `review.md` - Generated results (gitignored)

### 4. Summarizer Agent (`summarizer/`)
**Focus**: Aggregating and prioritizing findings

**Responsibilities**:
1. Collect results from all 3 specialized agents
2. Deduplicate similar findings (same file/line)
3. Prioritize issues by severity and impact
4. Generate final commit decision (BLOCK/ALLOW)
5. Provide overall code quality summary

**Files**:
- `prompt.txt` - Summarizer prompt
- Final results saved to `.ai/last_review.json`

## Parallel Execution

### Windows (PowerShell)

Agents run in parallel using PowerShell jobs:

```powershell
$SecurityJob = Start-Job -ScriptBlock { ... } -ArgumentList $args
$NamingJob = Start-Job -ScriptBlock { ... } -ArgumentList $args
$QualityJob = Start-Job -ScriptBlock { ... } -ArgumentList $args

Wait-Job -Job @($SecurityJob, $NamingJob, $QualityJob) -Timeout 120
```

### macOS/Linux (bash)

Agents run in parallel using background jobs:

```bash
run_agent "security" "$DIFF_CONTENT" &
run_agent "naming" "$DIFF_CONTENT" &
run_agent "quality" "$DIFF_CONTENT" &
wait
```

This provides **~3x faster** reviews compared to sequential execution.

## Output Format

Each agent produces **markdown output** (saved with `.json` extension for historical reasons):

```markdown
## Summary
Brief summary of findings

## Issues

### [BLOCK] Hardcoded Secret
- **File**: path/to/File.java
- **Line**: 42
- **Message**: Clear, actionable explanation

### [WARN] Poor Exception Handling
- **File**: path/to/File.java
- **Line**: 55
- **Message**: Empty catch block detected
```

**Note**: Despite the `.json` file extension, agent outputs are in markdown format for easier parsing without external tools like `jq`.

## Gitignore

Generated review files are excluded from version control:

```gitignore
.ai/agents/*/review.md
.ai/agents/security/review.md
.ai/agents/naming/review.md
.ai/agents/quality/review.md
```

Configuration files (checklist.yaml, prompt.txt) **are committed**.

## Extending the System

### Adding a New Agent

1. Create agent directory:
   ```powershell
   # Windows
   New-Item -ItemType Directory -Path .ai/agents/performance
   ```
   ```bash
   # macOS/Linux
   mkdir .ai/agents/performance
   ```

2. Create `checklist.yaml`:
   ```yaml
   metadata:
     version: "1.0.0"
     agent: "performance"
     focus: "Performance optimization"
   rules:
     - id: performance-issue-1
       description: "..."
       severity: WARN
   ```

3. Create `prompt.txt`:
   ```
   You are a performance optimization expert...
   {checklist}
   {diff}
   ```

4. Update `pre-commit.ps1` (Windows) or `pre-commit.sh` (macOS/Linux):
   
   **PowerShell:**
   ```powershell
   $PerformanceJob = Start-Job -ScriptBlock { ... } -ArgumentList $args
   Wait-Job -Job @($SecurityJob, $NamingJob, $QualityJob, $PerformanceJob)
   ```
   
   **Bash:**
   ```bash
   run_agent "performance" "$DIFF_CONTENT" &
   PERFORMANCE_PID=$!
   wait $PERFORMANCE_PID
   ```

5. Update `.gitignore`:
   ```gitignore
   .ai/agents/performance/review.md
   ```

### Customizing Rules

Edit `checklist.yaml` in any agent directory:

```yaml
rules:
  - id: custom-rule-001
    category: security
    description: "Check for deprecated crypto algorithms"
    severity: BLOCK
```

### Customizing Prompts

Edit `prompt.txt` in any agent directory to adjust AI instructions.

## Testing

Test the multi-agent system:

**Windows (PowerShell):**
```powershell
# Stage file with known issues
git add examples/BadClass.java

# Skip sensitive data check for testing
$env:SKIP_SENSITIVE_CHECK = 'true'
git commit -m "Test"
```

**macOS/Linux:**
```bash
# Stage file with known issues
git add examples/BadClass.java

# Skip sensitive data check for testing
SKIP_SENSITIVE_CHECK=true git commit -m "Test"
```

Expected output:
```
============================================
Multi-Agent Code Review System
============================================

[AI Review] Launching specialized agents in parallel...
  -> Security Agent (checking OWASP vulnerabilities...)
  -> Naming Agent (checking Java conventions...)
  -> Code Quality Agent (checking correctness...)

[AI Review] -> Security Agent: Complete (found 4 issues)
[AI Review] -> Naming Agent: Complete (found 10 issues)
[AI Review] -> Code Quality Agent: Complete (found 11 issues)

[AI Review] Aggregating results from all agents...
[AI Review] -> Summarizer Agent: Complete

============================================
Review Results by Agent
============================================
[Security, Naming, Quality results displayed]

============================================
Final Summary
============================================
[AI Review] Found 2 critical security issues...

AI REVIEW: COMMIT BLOCKED
```

## Troubleshooting

### Agent not running
- Check agent configuration exists:
  ```powershell
  # Windows
  Test-Path .ai/agents/security
  Get-ChildItem .ai/agents/security
  ```
  ```bash
  # macOS/Linux
  ls .ai/agents/security/
  ```
- Verify checklist.yaml and prompt.txt exist
- Check copilot CLI is installed: `copilot --version`

### Parse error in results
- Check agent output:
  ```powershell
  Get-Content .ai/agents/security/review.md
  ```
- Output is in markdown format (despite .json extension)

### Review files appearing in git status
- Verify .gitignore:
  ```powershell
  git check-ignore -v .ai/agents/security/review.md
  ```

## Performance

**Single-Agent (Old)**:
- Sequential execution
- ~30-45 seconds per commit

**Multi-Agent (New)**:
- Parallel execution (3 agents)
- ~10-15 seconds per commit
- **~3x faster!**

## Security

All agents receive the same diff content. No sensitive data is stored in review.md files (they're gitignored).

Agents never echo back hardcoded secrets - they reference them as "[REDACTED]" or describe their location.

## Demo Mode

Original single-agent files kept for demonstration:
- `.ai/java_code_review_checklist.yaml`
- `.ai/java_review_prompt.txt`

These show the "before" state and can be used for comparison.

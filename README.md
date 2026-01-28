# CLI-Based AI Java Code Review (Pre-Commit Hook)

A portable, CLI-only AI code review system for Java projects using GitHub Copilot and a YAML-driven checklist. Blocks commits on critical issues, reviews only staged diffs, and outputs strict JSON. IDE-agnostic and works in any terminal, CI, or editor.

---

## Features
- **Java-focused checklist** (YAML, easily extendable)
- **Pre-commit hook**: reviews only staged Java changes
- **AI-powered**: uses GitHub CLI with Copilot extension
- **Blocks commit** on security/correctness issues (BLOCK severity)
- **Strict JSON output** for automation/CI
- **No IDE dependencies**
- **Cross-platform**: Works on Windows (Git Bash/WSL), macOS, and Linux
- **Smart filtering**: Only reviews `.java` files
- **Dependency validation**: Checks for required tools before running

---

## Quick Start

### 1. Prerequisites

Install these tools before proceeding:

#### GitHub CLI with Copilot Extension
```sh
# Install GitHub CLI
# Windows:
winget install --id GitHub.cli

# macOS:
brew install gh

# Linux:
# See https://github.com/cli/cli/blob/trunk/docs/install_linux.md

# Authenticate
gh auth login

# Install Copilot extension
gh extension install github/gh-copilot
```

#### jq (JSON parser)
```sh
# Windows:
winget install jqlang.jq

# macOS:
brew install jq

# Linux (Debian/Ubuntu):
sudo apt install jq
```

### 2. Installation

**Option A: Automated Installation (Recommended)**
```sh
# Run the installation script
./install.sh
```

The script will:
- Check all dependencies
- Optionally install the Copilot extension
- Copy the pre-commit hook to `.git/hooks/`
- Make it executable
- Verify the installation

**Option B: Manual Installation**
```sh
# Copy the pre-commit hook
cp pre-commit.sh .git/hooks/pre-commit

# Make it executable
chmod +x .git/hooks/pre-commit
```

### 3. Usage

#### Normal Workflow
```sh
# Stage your Java changes
git add src/main/java/MyClass.java

# Commit as usual
git commit -m "Add new feature"
```

The AI review runs automatically!

#### Example: Commit Blocked

```
[AI Review] Checking dependencies...
[AI Review] Found Java files to review:
  - src/main/java/UserService.java
[AI Review] Analyzing code with GitHub Copilot...

╔═══════════════════════════════════════════════════════════╗
║  AI REVIEW: COMMIT BLOCKED                                ║
╚═══════════════════════════════════════════════════════════╝

Found 2 critical issue(s):

  ❌ [BLOCK] src/main/java/UserService.java:42
     Hardcoded database password detected. Use environment 
     variables or a secure configuration management system.

  ❌ [BLOCK] src/main/java/UserService.java:89
     SQL injection vulnerability: query concatenates user input
     directly. Use PreparedStatement with parameterized queries.

Fix these issues or use 'git commit --no-verify' to bypass.
Review details saved to: .ai/last_review.json
```

#### Example: Commit Allowed with Warnings

```
[AI Review] Found Java files to review:
  - src/main/java/OrderProcessor.java
[AI Review] Analyzing code with GitHub Copilot...

[AI Review] Found 1 warning(s) and 1 info message(s):

  ⚠️  [WARN] src/main/java/OrderProcessor.java:156
     Empty catch block swallows exception. Consider logging
     or rethrowing as a runtime exception.

  ℹ️  [INFO] src/main/java/OrderProcessor.java:23
     Variable name 'temp' doesn't follow Java naming conventions.
     Consider using a more descriptive name.

[AI Review] Code review complete. No critical issues found.
[AI Review] ✓ Review complete. Allowing commit.
```

### 4. Configuration

#### Disable Review Temporarily
```sh
# For a single commit
git commit --no-verify -m "Emergency hotfix"
```

#### Disable Review Permanently
```sh
# Set environment variable
export AI_REVIEW_ENABLED=false

# Or remove the hook
rm .git/hooks/pre-commit
```

#### Customize Checklist
Edit `.ai/java_code_review_checklist.yaml` to add/modify rules:
```yaml
rules:
  - id: your-custom-rule
    description: "Check for your specific pattern"
    severity: BLOCK  # or WARN or INFO
```

---

## Workflows

### Workflow 1: Commit → Review → Fix → Commit

This is the most common workflow when violations are found.

#### Step 1: Make Changes and Attempt Commit
```sh
# Edit your Java files
vim src/main/java/UserService.java

# Stage changes
git add src/main/java/UserService.java

# Try to commit
git commit -m "Add user authentication"
```

#### Step 2: Review Violations
The pre-commit hook runs and may block your commit:

```
[AI Review] Found Java files to review:
  - src/main/java/UserService.java
[AI Review] Analyzing code with GitHub Copilot...

╔═══════════════════════════════════════════════════════════╗
║  AI REVIEW: COMMIT BLOCKED                                ║
╚═══════════════════════════════════════════════════════════╝

Found 2 critical issue(s):

  ❌ [BLOCK] src/main/java/UserService.java:23
     Hardcoded database password detected. Use environment 
     variables or a secure configuration management system.

  ❌ [BLOCK] src/main/java/UserService.java:45
     SQL injection vulnerability: query concatenates user input
     directly. Use PreparedStatement with parameterized queries.

Fix these issues or use 'git commit --no-verify' to bypass.
Review details saved to: .ai/last_review.json
```

#### Step 3: Get AI-Assisted Fixes

**Option A: Use GitHub Copilot in Your Editor**

If you have GitHub Copilot installed in your IDE (VS Code, IntelliJ, etc.):

1. Open the file with violations: `src/main/java/UserService.java`
2. Navigate to the problematic line (e.g., line 23)
3. Select the problematic code
4. Ask Copilot: "Fix this hardcoded password issue using environment variables"
5. Accept Copilot's suggestion

**Option B: Use GitHub Copilot CLI**

Use the CLI to get fix recommendations directly in your terminal:

```sh
# Read the last review results
cat .ai/last_review.json | jq '.issues[] | select(.severity=="BLOCK")'

# Ask Copilot for a fix (example for the hardcoded password issue)
gh copilot suggest "How do I fix this Java code that has a hardcoded password: 
String password = \"admin123\"; 
I need to use environment variables instead"
```

**Option C: Use Any AI Tool**

Copy the violation details and paste into any AI tool (ChatGPT, Claude, etc.):

```
Prompt: "I have this Java code with a hardcoded password at line 23:
private static final String DB_PASSWORD = \"admin123\";

The code review flagged: 'Hardcoded database password detected. 
Use environment variables or a secure configuration management system.'

How should I fix this?"
```

#### Step 4: Apply the Fix

Based on AI recommendations, fix the issue:

```java
// Before (BLOCKED):
private static final String DB_PASSWORD = "admin123";

// After (GOOD):
private static final String DB_PASSWORD = System.getenv("DB_PASSWORD");

// Add null check
if (DB_PASSWORD == null) {
    throw new IllegalStateException("DB_PASSWORD environment variable not set");
}
```

#### Step 5: Commit Again
```sh
# Stage the fixed file
git add src/main/java/UserService.java

# Try commit again
git commit -m "Add user authentication with secure password handling"
```

This time, the review passes! ✅

```
[AI Review] Found Java files to review:
  - src/main/java/UserService.java
[AI Review] Analyzing code with GitHub Copilot...
[AI Review] Code review complete. No critical issues found.
[AI Review] ✓ Review complete. Allowing commit.

[master a1b2c3d] Add user authentication with secure password handling
 1 file changed, 10 insertions(+), 2 deletions(-)
```

---

### Workflow 2: Review Past Results

Check the details of the last review anytime:

```sh
# View full review JSON
cat .ai/last_review.json

# Pretty print with jq
cat .ai/last_review.json | jq '.'

# View only BLOCK issues
cat .ai/last_review.json | jq '.issues[] | select(.severity=="BLOCK")'

# View summary
cat .ai/last_review.json | jq '.summary'

# Count issues by severity
echo "BLOCK: $(cat .ai/last_review.json | jq '[.issues[] | select(.severity=="BLOCK")] | length')"
echo "WARN: $(cat .ai/last_review.json | jq '[.issues[] | select(.severity=="WARN")] | length')"
echo "INFO: $(cat .ai/last_review.json | jq '[.issues[] | select(.severity=="INFO")] | length')"
```

---

### Workflow 3: Emergency Bypass

When you need to commit urgently (hotfix, emergency):

```sh
# Bypass the pre-commit hook
git commit --no-verify -m "Emergency hotfix for production issue"
```

**⚠️ Warning**: Use `--no-verify` sparingly! It skips the security checks.

**Best Practice**: Create a follow-up task to fix the issues:
```sh
# After the emergency commit, create a reminder
echo "TODO: Fix security issues in commit $(git rev-parse HEAD)" >> SECURITY_DEBT.md
git add SECURITY_DEBT.md
git commit -m "Track security debt from emergency commit"
```

---

### Workflow 4: Interactive Fix with Copilot Chat

For complex issues, use GitHub Copilot's interactive chat:

```sh
# Start an interactive Copilot session with context
gh copilot explain "$(cat .ai/last_review.json)"

# Or ask for specific guidance
gh copilot suggest "I have these code review issues: $(cat .ai/last_review.json | jq -r '.issues[] | .message'). Show me how to fix them."
```

Then follow Copilot's step-by-step guidance in your terminal.

---

### Workflow 5: Batch Fix Multiple Issues

When you have multiple files with issues:

```sh
# 1. See all violations
cat .ai/last_review.json | jq -r '.issues[] | "\(.file):\(.line) - \(.message)"'

# 2. Fix issues file by file
for file in $(cat .ai/last_review.json | jq -r '.issues[].file' | sort -u); do
  echo "Fixing $file..."
  # Open in your editor
  code "$file"  # or vim, nano, etc.
  # Fix issues, then continue
  read -p "Press enter when done with $file..."
done

# 3. Stage all fixed files
git add -u

# 4. Commit with detailed message
git commit -m "Security fixes: resolve hardcoded secrets and SQL injection issues

- Moved credentials to environment variables
- Converted string concatenation to PreparedStatements
- Added null checks for user inputs

Addresses issues found in AI code review."
```

---

### Workflow 6: CI/CD Integration

Use the review results in your CI/CD pipeline:

```sh
# In your CI script (e.g., .github/workflows/pr-check.yml)

# Get staged changes
git diff origin/main...HEAD --name-only | grep '\.java$' > changed_files.txt

# Run review on changed files
for file in $(cat changed_files.txt); do
  git add "$file"
done

# The pre-commit hook runs automatically
# Or manually trigger the review script

# Check exit code
if [ $? -ne 0 ]; then
  echo "❌ Code review failed. Check .ai/last_review.json"
  cat .ai/last_review.json | jq '.issues[]'
  exit 1
fi

echo "✅ Code review passed"
```

---

## Project Structure

```
.
├── pre-commit.sh                          # Pre-commit hook template
├── install.sh                             # Automated installation script
├── .ai/
│   ├── java_code_review_checklist.yaml   # Review rules (YAML)
│   ├── java_review_prompt.txt            # AI prompt template
│   └── last_review.json                  # Last review results (generated)
├── examples/
│   └── test.java                         # Example file with issues
└── README.md                             # This file
```

---

## How It Works

1. **Pre-commit Hook Triggered**: When you run `git commit`, the hook intercepts
2. **Filter Java Files**: Only `.java` files in the staged changes are reviewed
3. **Extract Diff**: Gets the actual changes (not entire files)
4. **AI Analysis**: Sends diff + checklist to GitHub Copilot
5. **Parse Response**: Extracts issues from JSON response
6. **Decision**:
   - If BLOCK issues found → Commit rejected, issues displayed
   - If only WARN/INFO → Commit allowed, warnings displayed
   - If no issues → Commit allowed silently

---

## Checklist Rules

The `.ai/java_code_review_checklist.yaml` includes these checks:

### BLOCK Severity (Prevents Commit)
- Hardcoded secrets, passwords, API keys
- SQL injection vulnerabilities
- NullPointerException risks
- Unsafe deserialization
- Thread safety issues

### WARN Severity (Allows Commit)
- Poor exception handling
- Performance issues with collections
- Missing tests for new logic

### INFO Severity (Allows Commit)
- Naming convention violations

---

## Troubleshooting

### "GitHub CLI (gh) not found"
**Solution**: Install GitHub CLI:
```sh
# Windows
winget install --id GitHub.cli

# macOS
brew install gh

# Linux
# See https://github.com/cli/cli/blob/trunk/docs/install_linux.md
```

### "jq not found"
**Solution**: Install jq:
```sh
# Windows
winget install jqlang.jq

# macOS
brew install jq

# Linux
sudo apt install jq
```

### "GitHub Copilot CLI extension not installed"
**Solution**: Install the extension:
```sh
gh extension install github/gh-copilot
```

### "Could not connect to GitHub Copilot"
**Solutions**:
1. Ensure you're authenticated: `gh auth login`
2. Check your GitHub Copilot subscription
3. Verify the extension is installed: `gh extension list`

### Windows Compatibility
- Use Git Bash, WSL, or PowerShell with Git for Windows
- The script automatically handles temp directory differences

### Hook Not Running
**Check if it's executable**:
```sh
ls -la .git/hooks/pre-commit
# Should show -rwxr-xr-x (executable)

# If not, make it executable
chmod +x .git/hooks/pre-commit
```

### Review Takes Too Long
- The hook truncates large diffs (>20KB) automatically
- Consider reviewing smaller commits
- Or bypass for large refactors: `git commit --no-verify`

---

## Limitations & Future Enhancements

### Current Limitations
- Requires GitHub Copilot subscription
- GitHub CLI integration is still evolving
- Large diffs (>20KB) are truncated

### Future Enhancements
- Support for other AI providers (OpenAI, Azure OpenAI, local models)
- CI/CD integration examples
- Multi-language support (Python, TypeScript, etc.)
- Configurable severity thresholds
- Integration with code review platforms

---

## Contributing

Contributions welcome! This is a demonstration project showing how CLI-based AI code review can work.

Ideas for contributions:
- Additional checklist rules
- Support for other programming languages
- Integration with other AI providers
- CI/CD pipeline examples
- Performance improvements

---

## License

MIT - See [LICENSE](LICENSE) file for details

# Examples


This directory contains example files to demonstrate the **multi-agent AI code review system** with parallel execution.

## What Makes This Special?

This system uses **4 specialized AI agents** working together:

- **3 Agents Running in Parallel** (Security, Naming, Code Quality)
- **1 Summarizer Agent** (Aggregates and deduplicates findings)
- **3x Faster** than sequential execution (~15s vs ~45s)
- **Cross-Platform** (Windows PowerShell Jobs, Unix background processes)

Want to dive deeper? Check out the [Multi-Agent Implementation Guide](../MULTI_AGENT_IMPLEMENTATION.md) and [Architecture Documentation](../docs/ARCHITECTURE.md).

## Files

### `FlawedExample.java`
The primary example file with intentional flaws for testing:

- **BLOCK Issues (5)**: 
  - Hardcoded database password
  - Hardcoded API key
  - SQL injection vulnerability
  - NullPointerException risk
  - Thread safety issue

- **WARN Issues (2)**:
  - Poor exception handling (empty catch block)
  - Inefficient string comparison

- **INFO Issues (1)**:
  - Java naming convention violations

### `TestFlawedCode.java`
Additional test file with comprehensive issues including:

- **BLOCK Severity**: Hardcoded secrets, SQL injection, NPE risks, thread safety
- **WARN Severity**: Empty catch blocks
- **INFO Severity**: Naming convention violations (class, method, variable names)

Features a multi-class file with package declaration for more complex testing scenarios.

### `NewFlawedTest.java`
Compact test file focusing on common issues:

- Hardcoded GitHub token
- SQL injection vulnerability
- Thread-unsafe static counter
- Null pointer exception risks
- Empty exception handling
- Naming convention violations

Ideal for quick smoke tests of the review system.

### `example_review_output.json`
Example output from the AI code review showing what the pre-commit hook generates when it finds issues.

## Testing the Hook

To test the pre-commit hook with any of these examples:

### Windows (PowerShell)

```powershell
# 1. Make sure the hook is installed
.\install.ps1

# 2. Copy a test file to your source directory (choose any example)
New-Item -ItemType Directory -Path src/main/java -Force
Copy-Item examples/FlawedExample.java -Destination src/main/java/TestFile.java
# Or try: examples/TestFlawedCode.java or examples/NewFlawedTest.java

# 3. Stage the file
git add src/main/java/TestFile.java

# 4. Try to commit
git commit -m "Test commit"
```

### macOS/Linux (bash)

```bash
# 1. Make sure the hook is installed
./install.sh

# 2. Copy a test file to your source directory (choose any example)
mkdir -p src/main/java
cp examples/FlawedExample.java src/main/java/TestFile.java
# Or try: examples/TestFlawedCode.java or examples/NewFlawedTest.java

# 3. Stage the file
git add src/main/java/TestFile.java

# 4. Try to commit
git commit -m "Test commit"
```

The commit should be **blocked** because of the BLOCK severity issues!

## Expected Output

The review process takes approximately **15 seconds** - this is normal for AI-powered analysis. Here's what you'll see:

```
[AI Review] ℹ Found Java files to review:
  - CommitTestBlocked.java

[AI Review] ⏳ Checking dependencies (GitHub Copilot CLI required for AI analysis)...
[AI Review] ✓ GitHub Copilot CLI detected and ready

[AI Review] ⏳ Running analysis with 3 specialized agents in parallel (model: gpt-4.1)...
  ⏳ Security Agent - Checking OWASP vulnerabilities, secrets, injection attacks
  ⏳ Naming Agent - Validating Java naming conventions
  ⏳ Quality Agent - Analyzing code correctness, performance, best practices

[AI Review] ✓ Security: 5 issues | Naming: 0 issues | Quality: 1 issues
[AI Review] ⏳ Aggregating results from all agents (deduplicating and prioritizing)...

====================================================
  COMMIT BLOCKED - 5 Critical Issue(s) Found
====================================================

❌ BLOCKING ISSUES (5):
  [BLOCK] CommitTestBlocked.java:9
     Hardcoded password detected. Use environment variables or a secure vault.

  [BLOCK] CommitTestBlocked.java:10
     Hardcoded API key detected. Use environment variables or a secure vault.

  [BLOCK] CommitTestBlocked.java:14
     SQL injection vulnerability: query concatenates user input directly. Use PreparedStatement with parameterized queries.

  [BLOCK] CommitTestBlocked.java:19
     Unsafe deserialization of untrusted data detected. Validate and sanitize input before deserialization.

  [BLOCK] CommitTestBlocked.java:25
     Logging of sensitive data (API key, password) detected. Do not log secrets or credentials.

⚠️ WARNINGS (1):
  [WARN] CommitTestBlocked.java:19
     ObjectInputStream is not closed after use. Use try-with-resources to prevent resource leaks.

To bypass: git commit --no-verify -m "message"
```

## Performance Expectations

The multi-agent review system typically takes **~15 seconds** to complete. Here's why:

- **Parallel Execution**: 3 agents run simultaneously (Security, Naming, Quality)
- **AI Analysis**: Each agent uses GitHub Copilot CLI for intelligent code review
- **Aggregation**: Summarizer deduplicates and prioritizes findings from all agents

**This is 3x faster than sequential execution** (~15s vs ~45s) thanks to parallel processing!

The CLI may feel a bit slow during review - this is completely normal for AI-powered analysis. The thoroughness of catching security vulnerabilities, naming issues, and quality problems is worth the wait.

### What's Happening Behind the Scenes

- **Windows**: PowerShell Jobs (`Start-Job`) run agents in parallel
- **Unix**: Background processes (`&`) run agents concurrently
- **Cross-Platform**: Same experience on Windows, macOS, and Linux

## Viewing Review Results

### Windows (PowerShell)

```powershell
# View full review
Get-Content .ai/last_review.json

# View individual agent reports
Get-Content .ai/agents/security/review.md
Get-Content .ai/agents/naming/review.md
Get-Content .ai/agents/quality/review.md

# Find BLOCK issues
Select-String -Path .ai/last_review.json -Pattern "\[BLOCK\]"
```

### macOS/Linux (bash)

```bash
# View full review
cat .ai/last_review.json

# View only BLOCK/CRITICAL issues
grep -A 2 '\[BLOCK\]\|\[CRITICAL\]' .ai/last_review.json

# Count issues by severity
echo "BLOCK: $(grep -c '\[BLOCK\]' .ai/last_review.json)"
echo "WARN: $(grep -c '\[WARN\]' .ai/last_review.json)"
echo "INFO: $(grep -c '\[INFO\]' .ai/last_review.json)"
```

## Fixing the Issues

To see the hook allow a commit, fix all BLOCK issues:

```java
public class GoodCodeExample {
    
    // ✅ Use environment variables
    private static final String DB_PASSWORD = System.getenv("DB_PASSWORD");
    private static final String API_KEY = System.getenv("API_KEY");
    
    // ✅ Use PreparedStatement
    public void getUserByName(String username) throws Exception {
        String query = "SELECT * FROM users WHERE username = ?";
        PreparedStatement ps = connection.prepareStatement(query);
        ps.setString(1, username);
    }
    
    // ✅ Add null checks
    public String processUser(User user) {
        if (user == null || user.getName() == null) {
            throw new IllegalArgumentException("User and name cannot be null");
        }
        return user.getName().toUpperCase();
    }
    
    // ✅ Log exceptions
    public void readFile(String path) {
        try {
            // file reading logic
        } catch (Exception e) {
            logger.error("Failed to read file: " + path, e);
            throw new RuntimeException("File read failed", e);
        }
    }
    
    // ✅ Use AtomicInteger for thread safety
    private static final AtomicInteger counter = new AtomicInteger(0);
    public void incrementCounter() {
        counter.incrementAndGet();
    }
}
```

## Skip Sensitive Data Check (Testing)

When testing with files containing intentional security issues, skip the sensitive data warning:

### Windows (PowerShell)
```powershell
$env:SKIP_SENSITIVE_CHECK = 'true'
git commit -m "Test commit"
```

### macOS/Linux (bash)
```bash
SKIP_SENSITIVE_CHECK=true git commit -m "Test commit"
```

## Bypass AI Review (Emergency)

To bypass the AI review entirely:

```powershell
git commit --no-verify -m "Emergency fix"
```

⚠️ **Use sparingly!** This should only be used for genuine emergencies.

## Learn More

### Architecture & Implementation

- **[Multi-Agent Implementation Guide](../MULTI_AGENT_IMPLEMENTATION.md)** - Detailed technical implementation, performance metrics, and testing results
- **[Architecture Documentation](../docs/ARCHITECTURE.md)** - System design, data flow, and multi-agent architecture diagrams
- **[Main README](../README.md)** - Quick start guide and overview

### Agent Configuration

Each agent has its own configuration:

- `.ai/agents/security/` - Security agent (OWASP vulnerabilities, secrets)
- `.ai/agents/naming/` - Naming agent (Java conventions)
- `.ai/agents/quality/` - Quality agent (thread safety, NPE risks)
- `.ai/agents/summarizer/` - Aggregation and deduplication logic

Want to customize the agents? Edit the `checklist.yaml` and `prompt.txt` files in each agent directory!

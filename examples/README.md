# Examples

This directory contains example files to demonstrate the AI code review system.

## Files

### `BadClass.java`
A deliberately flawed Java file containing various issues that the AI reviewer should catch:

- **BLOCK Issues (5)**: 
  - Hardcoded database password
  - Hardcoded API key
  - SQL injection vulnerability
  - NullPointerException risk
  - Thread safety issue

- **WARN Issues (2)**:
  - Poor exception handling (empty catch block)
  - Inefficient collection usage

- **INFO Issues (1)**:
  - Java naming convention violations

### `example_review_output.json`
Example output from the AI code review showing what the pre-commit hook generates when it finds issues.

## Testing the Hook

To test the pre-commit hook with this example:

### Windows (PowerShell)

```powershell
# 1. Make sure the hook is installed
.\install.ps1

# 2. Copy the test file to your source directory
New-Item -ItemType Directory -Path src/main/java -Force
Copy-Item examples/BadClass.java -Destination src/main/java/TestFile.java

# 3. Stage the file
git add src/main/java/TestFile.java

# 4. Try to commit
git commit -m "Test commit"
```

### macOS/Linux (bash)

```bash
# 1. Make sure the hook is installed
./install.sh

# 2. Copy the test file to your source directory
mkdir -p src/main/java
cp examples/BadClass.java src/main/java/TestFile.java

# 3. Stage the file
git add src/main/java/TestFile.java

# 4. Try to commit
git commit -m "Test commit"
```

The commit should be **blocked** because of the BLOCK severity issues!

## Expected Output

```
[AI Review] Checking dependencies...
[AI Review] Found Java files to review:
  - src/main/java/TestFile.java
[AI Review] Launching specialized agents in parallel...

============================================
Multi-Agent Code Review System
============================================

[AI Review] -> Security Agent: Complete (found 4 issues)
[AI Review] -> Naming Agent: Complete (found 5 issues)
[AI Review] -> Code Quality Agent: Complete (found 6 issues)

========================================================
  AI REVIEW: COMMIT BLOCKED
========================================================

Found 5 critical issue(s):

  [BLOCK] src/main/java/TestFile.java:4
     Hardcoded database password 'admin123' detected. Store 
     credentials in environment variables...

  [BLOCK] src/main/java/TestFile.java:5
     Hardcoded API key detected. API keys should be stored 
     securely...

  [BLOCK] src/main/java/TestFile.java:9
     SQL injection vulnerability: query concatenates user input
     directly. Use PreparedStatement...

  [BLOCK] src/main/java/TestFile.java:14
     NullPointerException risk: 'user' parameter is dereferenced
     without null check...

  [BLOCK] src/main/java/TestFile.java:26
     Thread safety issue: static mutable field 'counter' is 
     modified without synchronization...

Fix these issues or use 'git commit --no-verify' to bypass.
Review details saved to: .ai/last_review.json
```

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

<div align="center">

# 🛡️ AI Code Review CLI

### Catch Security Vulnerabilities Before They Ship

**A portable, CLI-based AI code review system that blocks commits with critical issues—powered by GitHub Copilot.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)](https://github.com)
[![GitHub Copilot](https://img.shields.io/badge/Powered%20by-GitHub%20Copilot-8A2BE2)](https://github.com/features/copilot)

<br />

[Quick Start](#-quick-start) • [Features](#-features) • [Workflows](#-workflows) • [Customization](#-configuration) • [Troubleshooting](#-troubleshooting)

<br />

---

</div>

## 💡 The Problem

You're about to commit code with a hardcoded password. Or a SQL injection vulnerability. Or a null pointer exception waiting to happen.

**Traditional code reviews catch these issues—days later.** By then, they're already in your codebase, possibly in production.

## ✅ The Solution

This tool intercepts your commits **before they happen**, analyzes your staged changes with AI, and **blocks commits that contain critical security or correctness issues**.

```
$ git commit -m "Add user authentication"

╔═══════════════════════════════════════════════════════════╗
║  ❌ AI REVIEW: COMMIT BLOCKED                             ║
╚═══════════════════════════════════════════════════════════╝

Found 2 critical issue(s):

  ❌ [BLOCK] src/main/java/UserService.java:42
     Hardcoded database password detected. Use environment 
     variables or a secure configuration management system.

  ❌ [BLOCK] src/main/java/UserService.java:89
     SQL injection vulnerability: query concatenates user input
     directly. Use PreparedStatement with parameterized queries.

Fix these issues or use 'git commit --no-verify' to bypass.
```

**Fix the issue. Commit again. Ship secure code.**

---

## 🎯 Features

| Feature | Description |
|---------|-------------|
| 🔒 **Blocks Critical Issues** | Prevents commits with security vulnerabilities, hardcoded secrets, or correctness bugs |
| 🎯 **Java-Focused Checklist** | YAML-driven rules covering OWASP security guidelines |
| ⚡ **Reviews Only Changes** | Analyzes staged diffs, not entire files—fast and focused |
| 🤖 **AI-Powered Analysis** | Leverages GitHub Copilot for intelligent code understanding |
| 📋 **Strict JSON Output** | Machine-readable results for CI/CD integration |
| 🖥️ **Cross-Platform** | Works on Windows (Git Bash/WSL), macOS, and Linux |
| 🔧 **IDE-Agnostic** | No IDE dependencies—works in any terminal |
| ✏️ **Fully Customizable** | Extend the YAML checklist with your own rules |

---

## 🚀 Quick Start

### Prerequisites

<details>
<summary><strong>1. Install GitHub CLI</strong></summary>

```sh
# Windows
winget install --id GitHub.cli

# macOS
brew install gh

# Linux
# See https://github.com/cli/cli/blob/trunk/docs/install_linux.md

# Then authenticate
gh auth login
```
</details>

<details>
<summary><strong>2. Install Copilot Extension</strong></summary>

```sh
gh extension install github/gh-copilot
```
</details>

<details>
<summary><strong>3. Install jq (JSON parser)</strong></summary>

```sh
# Windows
winget install jqlang.jq

# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt install jq
```
</details>

### Installation

**Option A: Automated (Recommended)**
```sh
./install.sh
```

The script checks dependencies, installs the pre-commit hook, and verifies everything works.

**Option B: Manual**
```sh
cp pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### That's It!

Now every `git commit` triggers an automatic AI review:

```sh
git add src/main/java/MyClass.java
git commit -m "Add new feature"
# AI review runs automatically ✨
```

---

## 🔐 Security & Privacy

> **⚠️ Important:** This tool sends your code to external AI services. Understand the data implications before using.

```mermaid
flowchart LR
    A[Your Code] --> B[git diff]
    B --> C[Pre-commit Hook]
    C --> D[GitHub Copilot API]
    D --> E[AI Analysis]
    E --> F[JSON Response]
    F --> G[Block/Allow Decision]
```

### Enterprise vs. Consumer AI Plans

| Aspect | Enterprise/Business Plans | Individual/Free Plans |
|--------|---------------------------|----------------------|
| **Data Retention** | ✅ Prompts discarded immediately after response | ⚠️ May be retained for service improvement |
| **Training Usage** | ✅ Your code is **NOT** used for AI training | ⚠️ May be used to train/improve models |
| **Contractual Protection** | ✅ Data Processing Agreement (DPA), GDPR compliance | ⚠️ Standard consumer terms only |
| **IP Indemnification** | ✅ Often includes IP infringement protection | ❌ Typically not included |

#### ✅ Safe for Corporate Use: Enterprise Plans

**GitHub Copilot Business/Enterprise** and similar enterprise AI offerings:
- Your prompts (code) are **discarded immediately** after generating a response
- Your code is **never used to train** the AI model
- GitHub acts as a **data processor** with contractual obligations
- Suitable for proprietary codebases (verify with your legal/security team)

#### ⚠️ Caution: Free/Consumer AI Tiers

**Free tiers of AI services** (e.g., free ChatGPT, free Copilot trials, consumer plans):
- Your code **may be retained** and used to improve the model
- **No contractual data protection** guarantees
- Not recommended for proprietary, confidential, or sensitive code
- Check each provider's terms—policies vary and change frequently

> **Bottom line:** If you're working on proprietary code, use an enterprise-tier AI service with clear data protection terms, or consider local models (Ollama, CodeLlama) that never send data externally.

### What NOT to Send (Any AI Service)

Regardless of which tier you use, never send:

- ❌ Hardcoded secrets, API keys, or passwords
- ❌ Proprietary algorithms or trade secrets  
- ❌ Customer PII or HIPAA/GDPR protected data
- ❌ Internal infrastructure details (IPs, hostnames, internal URLs)

### Mitigation Strategies

1. **Use Enterprise AI** for corporate/proprietary codebases
2. Use `.gitignore` to exclude sensitive files
3. Use environment variables for all secrets
4. Review staged files before committing: `git diff --cached`
5. Consider **local LLMs** (Ollama, CodeLlama) for highly sensitive codebases
6. Set `AI_REVIEW_ENABLED=false` for sensitive commits

📖 **[Full Security Guide →](docs/SECURITY.md)**

---

## 📖 Workflows

### Workflow 1: The Standard Loop

> **Commit → Review → Fix → Commit**

<details>
<summary><strong>See full workflow</strong></summary>

#### Step 1: Attempt Commit
```sh
git add src/main/java/UserService.java
git commit -m "Add user authentication"
```

#### Step 2: Review Blocked
```
╔═══════════════════════════════════════════════════════════╗
║  AI REVIEW: COMMIT BLOCKED                                ║
╚═══════════════════════════════════════════════════════════╝

  ❌ [BLOCK] src/main/java/UserService.java:23
     Hardcoded database password detected.
```

#### Step 3: Get AI-Assisted Fix

**In your IDE (VS Code, IntelliJ):**
- Open the file, select the problematic code
- Ask Copilot: *"Fix this hardcoded password using environment variables"*

**Or via CLI:**
```sh
gh copilot suggest "How do I fix hardcoded passwords in Java using environment variables?"
```

#### Step 4: Apply the Fix
```java
// ❌ Before (BLOCKED):
private static final String DB_PASSWORD = "admin123";

// ✅ After (GOOD):
private static final String DB_PASSWORD = System.getenv("DB_PASSWORD");
```

#### Step 5: Commit Again
```sh
git add src/main/java/UserService.java
git commit -m "Add user authentication with secure password handling"
# ✅ Review passes!
```

</details>

---

### Workflow 2: Review Past Results

```sh
# View full review
cat .ai/last_review.json | jq '.'

# View only BLOCK issues
cat .ai/last_review.json | jq '.issues[] | select(.severity=="BLOCK")'

# Count by severity
cat .ai/last_review.json | jq '[.issues[] | .severity] | group_by(.) | map({severity: .[0], count: length})'
```

---

### Workflow 3: Emergency Bypass

When you absolutely must commit immediately:

```sh
git commit --no-verify -m "Emergency hotfix for production"
```

> ⚠️ **Use sparingly!** Always track bypassed security debt:
> ```sh
> echo "TODO: Fix issues from $(git rev-parse HEAD)" >> SECURITY_DEBT.md
> ```

---

### Workflow 4: CI/CD Integration

```yaml
# .github/workflows/pr-check.yml
- name: Run AI Code Review
  run: |
    if ! ./pre-commit.sh; then
      echo "❌ Code review failed"
      cat .ai/last_review.json | jq '.issues[]'
      exit 1
    fi
```

---

## ⚙️ Configuration

### Disable Review

```sh
# Single commit
git commit --no-verify -m "Skip review for this commit"

# Permanently
export AI_REVIEW_ENABLED=false
# or
rm .git/hooks/pre-commit
```

### Customize Checklist

Edit `.ai/java_code_review_checklist.yaml`:

```yaml
rules:
  - id: custom-rule-001
    description: "Check for deprecated API usage"
    severity: WARN  # BLOCK | WARN | INFO
```

### Severity Levels

| Severity | Effect | Example Issues |
|----------|--------|----------------|
| `BLOCK` | ❌ Prevents commit | Hardcoded secrets, SQL injection, null pointer risks |
| `WARN` | ⚠️ Allows commit, shows warning | Poor exception handling, performance issues |
| `INFO` | ℹ️ Allows commit, shows info | Naming convention violations |

---

## 📁 Project Structure

```
.
├── pre-commit.sh                          # Pre-commit hook template
├── install.sh                             # Automated installation
├── .ai/
│   ├── java_code_review_checklist.yaml   # Review rules (YAML)
│   ├── java_review_prompt.txt            # AI prompt template
│   └── last_review.json                  # Last review results
├── docs/
│   ├── ARCHITECTURE.md                   # System design
│   ├── SECURITY.md                       # Security guide
│   └── CUSTOMIZATION.md                  # Extension guide
├── examples/
│   ├── test.java                         # Example with issues
│   └── example_review_output.json        # Sample output
└── README.md
```

---

## 🔍 Troubleshooting

<details>
<summary><strong>"GitHub CLI (gh) not found"</strong></summary>

Install GitHub CLI for your platform:
```sh
# Windows
winget install --id GitHub.cli

# macOS
brew install gh

# Linux
# See https://github.com/cli/cli/blob/trunk/docs/install_linux.md
```
</details>

<details>
<summary><strong>"jq not found"</strong></summary>

```sh
# Windows
winget install jqlang.jq

# macOS
brew install jq

# Linux
sudo apt install jq
```
</details>

<details>
<summary><strong>"GitHub Copilot CLI extension not installed"</strong></summary>

```sh
gh extension install github/gh-copilot
```
</details>

<details>
<summary><strong>"Could not connect to GitHub Copilot"</strong></summary>

1. Ensure you're authenticated: `gh auth login`
2. Check your GitHub Copilot subscription
3. Verify extension: `gh extension list`
</details>

<details>
<summary><strong>Hook not running</strong></summary>

```sh
# Check if executable
ls -la .git/hooks/pre-commit

# Make executable
chmod +x .git/hooks/pre-commit
```
</details>

<details>
<summary><strong>Review takes too long</strong></summary>

- Large diffs (>20KB) are automatically truncated
- Consider smaller, focused commits
- Bypass for large refactors: `git commit --no-verify`
</details>

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---



<div align="center">

# 🛡️ AI Code Review CLI

### Catch Security, Bugs & Quality Issues Before They Ship

**A portable, CLI-based AI code review system that performs comprehensive reviews at commit time—powered by GitHub Copilot.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)](https://github.com)
[![GitHub Copilot](https://img.shields.io/badge/Powered%20by-GitHub%20Copilot-8A2BE2)](https://github.com/features/copilot)

<div align="center">

![AI Code Review CLI](./docs/linked_image.png)

</div>

<br />

[Quick Start](#-quick-start) • [Features](#-features) • [Workflows](#-workflows) • [Configuration](#-configuration) • [Troubleshooting](#-troubleshooting)

<br />

---

</div>

## 💡 The Problem

You're about to commit code with a hardcoded password. Or a SQL injection vulnerability. Or an empty catch block. Or naming convention violations.

**Traditional code reviews catch these issues—days later.** By then, they're already in your codebase, possibly in production.

## ✅ The Solution

This tool intercepts your commits **before they happen**, analyzes your staged changes with AI, and **blocks commits that contain critical security, correctness, or quality issues**.

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

## 🔍 What Gets Reviewed

This isn't just a security tool—it's a comprehensive AI code reviewer using a **multi-agent architecture** where specialized agents work in parallel to analyze different aspects of your code:

**Multi-Agent System:**
- 🔒 **Security Agent**: Focuses on vulnerabilities, secrets, and security patterns
- 📝 **Naming Agent**: Checks Java naming conventions and code style
- ✅ **Quality Agent**: Reviews correctness, performance, and best practices
- 🤖 **Summarizer Agent**: Aggregates results and eliminates duplicates

**Review Categories:**

| Category | Severity | Examples |
|----------|----------|----------|
| 🔒 **Security** | BLOCK | Hardcoded secrets, SQL injection, unsafe deserialization |
| 🐛 **Correctness** | BLOCK | Null pointer risks, thread safety issues |
| ⚡ **Performance** | WARN | Inefficient collections, O(n) when O(1) available |
| 📝 **Code Quality** | WARN | Empty catch blocks, poor exception handling |
| 🎯 **Best Practices** | INFO | Naming conventions, Java code standards |

**Severity Levels:**
- **BLOCK**: Commit rejected (security & critical bugs)
- **WARN**: Commit allowed with warnings (quality issues)
- **INFO**: Commit allowed with suggestions (style & conventions)

---

## 🎯 Features

| Feature | Description |
|---------|-------------|
| 🔒 **Comprehensive Reviews** | Checks security, correctness, performance, quality, and best practices |
| 🤖 **Multi-Agent Architecture** | Specialized agents (Security, Naming, Quality) run in parallel for faster reviews |
| 🎯 **Java-Focused Checklist** | YAML-driven rules covering OWASP security + code quality standards |
| ⚡ **Reviews Only Changes** | Analyzes staged diffs, not entire files—fast and focused |
| 🧠 **AI-Powered Analysis** | Leverages GitHub Copilot for intelligent code understanding |
| 🚫 **Smart Blocking** | Only blocks BLOCK-severity issues (security/bugs), allows WARN/INFO |
| 📋 **Structured Markdown Output** | Human-readable results parsed with native bash tools (no jq required) |
| 🖥️ **Cross-Platform** | Works on Windows (WSL 2 recommended), macOS, and Linux |
| 💻 **WSL 2 Auto-Delegation** | Windows users keep their workflow - hook auto-delegates to WSL for compatibility |
| 🔧 **IDE-Compatible** | Works with IntelliJ IDEA, VS Code, PyCharm, WebStorm, and any git client |
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

## 💻 Windows Users: Why Use WSL 2?

> **💡 Works with Your IDE!** WSL 2 is fully compatible with IntelliJ IDEA, VS Code, PyCharm, WebStorm, and other popular IDEs. You can commit directly from your IDE and the AI review will work perfectly. See [IDE setup instructions](#using-with-ides-intellij-vs-code-etc) below.

### The Problem with Git Bash

Git Bash on Windows encounters a critical limitation when running this AI code review system:

**Technical Issue: PowerShell Command-Line Length Limits**

The GitHub Copilot CLI is installed as a **GitHub CLI extension** (via `gh extension install github/gh-copilot`). On Windows, when Git Bash invokes the `copilot` command, it goes through the GitHub CLI's Windows launcher which uses PowerShell for command execution. This creates a chain: Git Bash → Windows gh.exe → PowerShell → copilot extension.

When the pre-commit hook passes the entire review prompt (checklist rules + code diff) as a command-line argument through this chain, PowerShell's argument length restrictions cause failures.

**The Error:**
```
error: too many arguments. Expected 0 arguments but got 130.
```

This happens because:
1. The AI review prompts are comprehensive (500-1000+ characters including checklist rules)
2. PowerShell has a limit on argument length (~8000 characters, but the execution chain is more restrictive)
3. Git Bash must escape and pass the entire prompt through the Windows gh.exe launcher to PowerShell
4. Special characters in code diffs (quotes, backticks, newlines) make escaping complex
5. The GitHub CLI Windows launcher has additional argument parsing limitations

### Why WSL 2 Solves This

Windows Subsystem for Linux 2 (WSL 2) provides a **native Linux environment with a real Linux kernel** running directly on Windows:

> **💡 Why WSL 2?** WSL 2 uses a real Linux kernel (unlike WSL 1 which was a translation layer), providing full system call compatibility, better performance, and native tool support.

| Aspect | Git Bash | WSL 2 |
| ------ | -------- | ----- |
| **Environment** | Windows with Unix-like shell | Full Linux kernel (real) |
| **Copilot CLI** | GitHub CLI extension via Windows launcher | GitHub CLI extension (native) |
| **Command Limits** | PowerShell restrictions (~8K chars) | Linux limits (>2MB arguments) |
| **Path Translation** | `/c/Users` requires translation | Native `/mnt/c/Users` |
| **Emoji Support** | Poor (encoding issues) | Excellent (native UTF-8) |
| **Performance** | Slow (PowerShell overhead) | Fast (native) |
| **Script Compatibility** | Requires workarounds | Native bash support |

### Benefits You'll Get

1. **No More Argument Errors**: Native Linux execution bypasses Windows launcher and PowerShell chain entirely
2. **Better Performance**: ~30% faster execution without Windows CLI wrapper overhead
3. **Proper Emoji Display**: See 🔒⏳ ✅✓ icons correctly instead of `??`
4. **More Reliable**: Native bash environment without Windows path translation issues
5. **IDE Compatible**: Works seamlessly with IntelliJ, VS Code, and other IDEs
6. **Better Integration**: Access Windows files via `/mnt/c/` while using Linux tools

### Supported Workflows

| Workflow | Windows Git | Pure WSL 2 | Hybrid Mode |
| -------- | ----------- | ---------- | ----------- |
| **PowerShell commits** | ❌ Fails | ✅ Works | ✅ Auto-delegates |
| **CMD commits** | ❌ Fails | ✅ Works | ✅ Auto-delegates |
| **Git Bash commits** | ❌ Fails | ✅ Works | ✅ Auto-delegates |
| **IntelliJ commits** | ❌ Fails | ✅ Config | ✅ Keep Windows git |
| **VS Code commits** | ❌ Fails | ✅ Extension | ✅ Keep Windows git |
| **GitHub Desktop** | ❌ Fails | ✅ Works | ✅ Auto-delegates |
| **Emoji display** | ⚠️ `??` | ✅ UTF-8 | ✅ UTF-8 (via WSL) |
| **Setup effort** | N/A | Medium | Low (one-time) |

**💡 Recommendation**: Use **Hybrid Mode** - keep your existing workflow (PowerShell, CMD, IntelliJ with Windows git) and let the hook automatically delegate AI review to WSL 2.

---

## Two Setup Approaches

### Approach 1: Hybrid Mode (RECOMMENDED for Most Users)

**Best for:** Developers who want to keep their current workflow (PowerShell, CMD, IntelliJ with Windows git, etc.)

**How it works:**
1. You continue using Windows git from wherever you prefer (PowerShell, CMD, IntelliJ, VS Code, etc.)
2. When you commit, Windows git triggers the pre-commit hook
3. The hook **auto-detects** it's running in Windows and **delegates** to WSL 2 for AI review
4. AI review runs in WSL 2 (where Copilot CLI works), then returns control to Windows git
5. Your commit succeeds or fails based on the review

**Advantages:**
- ✅ No change to your existing workflow
- ✅ Keep using your IDE's built-in git
- ✅ Works from PowerShell, CMD, Git Bash, IntelliJ, VS Code, etc.
- ✅ Minimal setup (just install WSL 2 dependencies)

**Setup Steps:**

**Step 1: Install WSL 2** (one-time)

> **⚠️ Requirements**: 
> - Windows 10 version 2004+ (Build 19041+) or Windows 11
> - WSL 2 is required (not WSL 1) for full compatibility and performance

```powershell
# In PowerShell (as Administrator)
wsl --install
# This installs WSL 2 by default
```

Verify WSL 2 is installed:
```powershell
wsl --list --verbose
# Should show "VERSION 2" for your distro
```

**Step 2: Install Ubuntu** (one-time)

```powershell
wsl --install -d Ubuntu
# Or choose another distro: wsl --list --online
```

**Step 3: Install Dependencies in WSL 2** (one-time)

```bash
# Open WSL terminal and run:
sudo apt update
sudo apt install gh

# Authenticate GitHub CLI
gh auth login

# Install Copilot extension
gh extension install github/gh-copilot
```

**Step 4: Run the Installer** (from your project in Windows)

```bash
# In PowerShell, CMD, or Git Bash:
cd C:\workspace\your-project
./install.sh
```

The installer will detect WSL 2 and configure the hook to auto-delegate.

**Step 5: Commit as usual!**

From **PowerShell**:
```powershell
cd C:\workspace\your-project
git add MyFile.java
git commit -m "Add new feature"
# Hook automatically runs in WSL 2! ✅
```

From **CMD**:
```cmd
cd C:\workspace\your-project
git add MyFile.java
git commit -m "Add new feature"
# Hook automatically runs in WSL 2! ✅
```

From **IntelliJ** (keep using Windows git):
1. No configuration needed - keep using `git.exe`
2. Use the commit dialog (Ctrl+K) as normal
3. Hook automatically delegates to WSL 2! ✅

From **VS Code** (keep using Windows git):
1. No configuration needed
2. Use Source Control panel as normal
3. Hook automatically delegates to WSL 2! ✅

---

### Approach 2: Pure WSL 2 Mode

**Best for:** Developers who want the purest Linux experience or are already comfortable with WSL 2

**How it works:**
1. You switch to using WSL 2's native git
2. All git operations run in WSL 2 environment
3. No delegation needed - everything is native Linux

**Advantages:**
- ✅ Fastest performance (no delegation overhead)
- ✅ Best emoji/UTF-8 support
- ✅ Pure Linux environment

**Disadvantages:**
- ⚠️ Requires configuring IDE to use WSL 2 git
- ⚠️ Requires learning WSL 2 paths (`/mnt/c/...`)

**Setup Steps:**

**Step 1: Install WSL 2**

> **⚠️ Requirements**:
> - Windows 10 version 2004+ (Build 19041+) or Windows 11
> - WSL 2 is required (not WSL 1) - provides real Linux kernel for full compatibility

```powershell
# In PowerShell (as Administrator)
wsl --install
# This installs WSL 2 by default
```

Verify WSL 2 is installed:
```powershell
wsl --list --verbose
# Should show "VERSION 2"
```

If you have WSL 1, upgrade to WSL 2:
```powershell
wsl --set-version Ubuntu 2
```

**Step 2: Install Ubuntu** (or your preferred distro)

```powershell
wsl --install -d Ubuntu
# Or choose another distro: wsl --list --online
```

**Step 3: Inside WSL 2, Install Dependencies**

```bash
# Update package list
sudo apt update

# Install GitHub CLI
sudo apt install gh

# Authenticate with GitHub
gh auth login

# Install Copilot extension
gh extension install github/gh-copilot
```

**Step 4: Navigate to Your Project**

```bash
# Windows drives are mounted at /mnt/
cd /mnt/c/workspace/your-project
```

**Step 5: Run the Installer**

```bash
./install.sh
```

**Step 6: Make Commits from WSL 2**

```bash
git add YourFile.java
git commit -m "Your commit message"
# AI review runs automatically!
```

### Can I Still Use Git Bash?

Yes, but with limitations:
- ✅ Simple git operations work fine
- ⚠️ AI code review will fail with "too many arguments" error
- 💡 **Recommendation**: Use WSL 2 for commits, Git Bash for other git operations

### Using with IDEs (IntelliJ, VS Code, etc.)

> **🎯 With Hybrid Mode, NO IDE configuration is needed!** Keep using your IDE's default Windows git. The hook will auto-detect and delegate to WSL 2.

Most developers commit from within their IDE. With Hybrid Mode, this just works:

#### Hybrid Mode (No Configuration Needed)

**IntelliJ IDEA / PyCharm / WebStorm:**
1. Keep using Windows git (no settings change needed)
2. Commit via IDE dialog (Ctrl+K) as normal
3. Hook auto-detects Windows environment and delegates to WSL 2 ✅
4. Review output appears in IDE's console

**VS Code:**
1. Keep using Windows git (no settings change needed)
2. Commit via Source Control panel as normal
3. Hook auto-detects Windows environment and delegates to WSL 2 ✅
4. Review output appears in integrated terminal

**Any other IDE (WebStorm, Rider, Eclipse, etc.):**
1. Keep using Windows git
2. Commit as you normally would
3. Hook auto-delegates to WSL 2 ✅

#### Pure WSL 2 Mode (Requires IDE Configuration)

If you prefer Pure WSL 2 Mode for maximum performance:

**IntelliJ IDEA / PyCharm / WebStorm:**
1. Go to **Settings** → **Version Control** → **Git**
2. Set **Path to Git executable** to: `\\wsl$\Ubuntu\usr\bin\git`
3. Click **Test** to verify
4. When you commit via IDE, everything runs natively in WSL 2 ✅

**VS Code:**
1. Install the **Remote - WSL** extension
2. Click green button in bottom-left → **New WSL Window**
3. Open your project folder (VS Code accesses via `/mnt/c/...`)
4. Commit via Source Control panel - runs natively in WSL 2 ✅

---

## 🔐 Security & Privacy

> **⚠️ Critical:** This tool sends your code to AI services. For proprietary/corporate code, you **MUST** use GitHub Copilot Business/Enterprise, Azure OpenAI, or local LLMs (Ollama). **Do NOT use free/consumer AI tiers** for confidential code.

```mermaid
flowchart LR
    A[Your Code] --> B[git diff]
    B --> C[Pre-commit Hook]
    C --> D[GitHub Copilot API]
    D --> E[AI Analysis]
    E --> F[Markdown Response]
    F --> G[Block/Allow Decision]
```

### Enterprise vs. Consumer AI Plans

| Aspect | Enterprise/Business Plans | Individual/Free Plans |
|--------|---------------------------|----------------------|
| **Data Retention** | ✅ Prompts discarded immediately after response | ⚠️ May be retained for service improvement |
| **Training Usage** | ✅ Your code is **NOT** used for AI training | ⚠️ May be used to train/improve models |
| **Contractual Protection** | ✅ Data Processing Agreement (DPA), GDPR compliance | ⚠️ Standard consumer terms only |
| **IP Indemnification** | ✅ Often includes IP infringement protection | ❌ Typically not included |

#### ✅ Required for Proprietary Code: Secure AI Options

**For corporate/proprietary codebases, use ONLY these options:**

1. **GitHub Copilot Business/Enterprise**
   - ✅ Code is **discarded immediately** after generating response
   - ✅ **Never used to train** AI models
   - ✅ Contractual data processing agreement (DPA)
   - ✅ GDPR compliant

2. **Azure OpenAI Service**
   - ✅ Enterprise SLA (99.9% uptime)
   - ✅ Data residency options
   - ✅ Your data never leaves your Azure tenant
   - ✅ Full RBAC and compliance controls

3. **Local LLMs (Ollama + CodeLlama)**
   - ✅ Data **never leaves your machine**
   - ✅ No internet connection required
   - ✅ Complete privacy
   - ✅ No subscription costs

#### ❌ NEVER Use for Proprietary Code: Consumer AI Tiers

**Do NOT use free/individual AI plans for corporate code:**

- ❌ **GitHub Copilot Individual** - May retain prompts, different terms than Business/Enterprise
- ❌ **Free ChatGPT, Claude, etc.** - Code may be used for model training
- ❌ **Free API trials** - Limited data protection guarantees

> **Bottom line:** If you're working on proprietary code, you **MUST** use GitHub Copilot Business/Enterprise, Azure OpenAI, or local models (Ollama). Consumer/free tiers are **NOT suitable** for confidential code.

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
# View full review (markdown format)
cat .ai/last_review.json
# Or with less for better readability
less .ai/last_review.json

# View only BLOCK/CRITICAL issues
grep -A 2 '### \[BLOCK\]\|### \[CRITICAL\]' .ai/last_review.json

# Count issues by severity
echo "BLOCK: $(grep -c '### \[BLOCK\]' .ai/last_review.json)"
echo "WARN: $(grep -c '### \[WARN\]' .ai/last_review.json)"
echo "INFO: $(grep -c '### \[INFO\]' .ai/last_review.json)"

# View individual agent reports
cat .ai/agents/security/review.json
cat .ai/agents/naming/review.json
cat .ai/agents/quality/review.json
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
      cat .ai/last_review.json
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

### Uninstall / Remove the Hook

**Remove hook for this repository**

```sh
# macOS / Linux / Git Bash
rm .git/hooks/pre-commit

# PowerShell (Windows)
Remove-Item .git\hooks\pre-commit
```

**If you had an existing `pre-commit` hook before installing**

- Restore it from your own backup (for example, rename `pre-commit.bak` back to `pre-commit`).

**If your Git is configured to use a custom hooks directory**

```sh
git config --get core.hooksPath
git config --global --get core.hooksPath
```

If either command prints a path, remove the `pre-commit` file from that hooks folder instead of `.git/hooks/`.

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
├── LICENSE                                # MIT License
├── .ai/
│   ├── agents/                           # Multi-agent system
│   │   ├── security/                     # Security agent
│   │   ├── naming/                       # Naming conventions agent
│   │   ├── quality/                      # Code quality agent
│   │   └── summarizer/                   # Results aggregator
│   ├── java_code_review_checklist.yaml   # Review rules (YAML)
│   ├── java_review_prompt.txt            # AI prompt template
│   └── last_review.json                  # Last review results (markdown format)
├── docs/
│   ├── ARCHITECTURE.md                   # System design
│   ├── SECURITY.md                       # Security guide
│   ├── CUSTOMIZATION.md                  # Extension guide
│   ├── linkedin_post.md                  # LinkedIn post template
│   └── linked_image.png                  # Project image
├── examples/
│   ├── test.java                         # Example with issues
│   ├── example_review_output.json        # Sample output (legacy JSON format)
│   └── README.md                         # Examples documentation
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



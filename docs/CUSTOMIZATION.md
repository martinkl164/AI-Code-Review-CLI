# Customization Guide

This guide explains how to extend and customize the CLI-Based AI Java Code Review system.

## Table of Contents

- [Adding New Rules](#adding-new-rules)
- [Modifying the AI Prompt](#modifying-the-ai-prompt)
- [Changing AI Provider](#changing-ai-provider)
- [Adjusting Sensitivity](#adjusting-sensitivity)
- [Adding Language Support](#adding-language-support)

---

## Adding New Rules

Edit `.ai/java_code_review_checklist.yaml` to add custom rules:

### Basic Rule Structure

```yaml
rules:
  - id: your-rule-id          # Unique identifier (lowercase, hyphens)
    category: category-name    # Optional: for grouping
    owasp: "A01:2021"         # Optional: OWASP reference
    description: "What the AI should check for"
    severity: BLOCK           # BLOCK, WARN, or INFO
```

### Example: Custom Rules

```yaml
# Prevent System.out.println in production code
- id: no-sysout
  category: code-quality
  description: "Detect System.out.println statements. Use proper logging framework instead."
  severity: WARN

# Enforce specific annotation usage
- id: require-transactional
  category: spring
  description: "Service methods modifying data should have @Transactional annotation."
  severity: WARN

# Company-specific security rule
- id: internal-api-exposure
  category: security
  description: "Detect public endpoints exposing internal APIs without authentication."
  severity: BLOCK
```

### Severity Guidelines

| Severity | When to Use | Effect |
|----------|-------------|--------|
| `BLOCK` | Security vulnerabilities, critical bugs | Commit rejected |
| `WARN` | Code quality issues, best practices | Commit allowed, warning shown |
| `INFO` | Style, conventions, suggestions | Commit allowed, info shown |

---

## Modifying the AI Prompt

Edit `.ai/java_review_prompt.txt` to change how the AI behaves:

### Key Sections

1. **Security Boundaries** - Anti-jailbreak instructions
2. **Critical Instructions** - Core behavior rules
3. **Output Security** - Redaction rules
4. **Output Format** - JSON structure
5. **Severity Guidelines** - What triggers each level

### Customization Examples

#### Add Domain-Specific Context

```text
=== DOMAIN CONTEXT ===
This is a financial services application. Pay special attention to:
- Money calculations (use BigDecimal, not float/double)
- Audit logging requirements
- PCI DSS compliance issues
```

#### Stricter Mode

```text
=== REVIEW MODE ===
You are in STRICT mode. Flag any potential issue, even minor ones.
Err on the side of caution - it's better to have false positives.
```

#### Lenient Mode

```text
=== REVIEW MODE ===
You are in LENIENT mode. Only flag clear, obvious violations.
Don't flag stylistic issues or potential-but-unlikely problems.
```

---

## Changing AI Provider

The `pre-commit.sh` can be modified to use different AI providers:

### OpenAI API

```bash
# Replace the Copilot CLI call with:
REVIEW_OUTPUT=$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "'"$REVIEW_PROMPT"'"}],
    "temperature": 0.1
  }' | jq -r '.choices[0].message.content')
```

### Azure OpenAI

```bash
AZURE_ENDPOINT="https://your-resource.openai.azure.com"
DEPLOYMENT="your-deployment-name"

REVIEW_OUTPUT=$(curl -s "$AZURE_ENDPOINT/openai/deployments/$DEPLOYMENT/chat/completions?api-version=2024-02-15-preview" \
  -H "Content-Type: application/json" \
  -H "api-key: $AZURE_OPENAI_KEY" \
  -d '{
    "messages": [{"role": "user", "content": "'"$REVIEW_PROMPT"'"}],
    "temperature": 0.1
  }' | jq -r '.choices[0].message.content')
```

### Ollama (Local LLM)

```bash
# Install Ollama first: curl -fsSL https://ollama.ai/install.sh | sh
# Pull a model: ollama pull codellama

REVIEW_OUTPUT=$(curl -s http://localhost:11434/api/generate \
  -d '{
    "model": "codellama",
    "prompt": "'"$REVIEW_PROMPT"'",
    "stream": false
  }' | jq -r '.response')
```

### Claude (Anthropic)

```bash
REVIEW_OUTPUT=$(curl -s https://api.anthropic.com/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-opus-20240229",
    "max_tokens": 4096,
    "messages": [{"role": "user", "content": "'"$REVIEW_PROMPT"'"}]
  }' | jq -r '.content[0].text')
```

---

## Adjusting Sensitivity

### Diff Size Limit

In `pre-commit.sh`, adjust the maximum diff size:

```bash
# Default: 20KB
MAX_DIFF_SIZE=20000

# For more thorough reviews (slower)
MAX_DIFF_SIZE=50000

# For faster reviews (may miss context)
MAX_DIFF_SIZE=10000
```

### Disable Sensitive Data Warning

```bash
# In your shell or .bashrc
export SKIP_SENSITIVE_CHECK=true
```

### Change Severity Thresholds

Edit the jq queries in `pre-commit.sh` to change what blocks commits:

```bash
# Original: Block on BLOCK or CRITICAL
BLOCK_ISSUES=$(echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="BLOCK" or .severity=="CRITICAL")')

# Modified: Also block on HIGH severity
BLOCK_ISSUES=$(echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="BLOCK" or .severity=="CRITICAL" or .severity=="HIGH")')

# Modified: Only block on CRITICAL (more lenient)
BLOCK_ISSUES=$(echo "$REVIEW_JSON" | jq -r '.issues[] | select(.severity=="CRITICAL")')
```

---

## Adding Language Support

To add support for another language (e.g., Python):

### 1. Create New Checklist

`.ai/python_code_review_checklist.yaml`:

```yaml
metadata:
  version: "1.0.0"
  language: "python"

rules:
  - id: hardcoded-secret
    description: "Detect hardcoded secrets, passwords, or API keys."
    severity: BLOCK

  - id: sql-injection
    description: "Check for SQL queries using string formatting instead of parameterized queries."
    severity: BLOCK

  - id: command-injection
    description: "Detect os.system() or subprocess with unsanitized input."
    severity: BLOCK

  - id: pickle-unsafe
    description: "Detect pickle.load() on untrusted data."
    severity: BLOCK

  - id: eval-usage
    description: "Detect eval() or exec() with user input."
    severity: BLOCK
```

### 2. Create New Prompt

`.ai/python_review_prompt.txt`:

```text
You are a senior Python engineer conducting a code review.

=== SECURITY BOUNDARIES ===
[Same as Java prompt]

=== CRITICAL INSTRUCTIONS ===
[Same as Java prompt, adapted for Python]

[Rest of prompt structure...]
```

### 3. Modify pre-commit.sh

Add Python file detection:

```bash
# Get list of staged Python files
STAGED_PYTHON_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.py$' || true)

if [ -n "$STAGED_PYTHON_FILES" ]; then
  PYTHON_CHECKLIST_FILE="$AI_DIR/python_code_review_checklist.yaml"
  PYTHON_PROMPT_FILE="$AI_DIR/python_review_prompt.txt"
  # Run Python review...
fi
```

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_REVIEW_ENABLED` | `true` | Enable/disable AI review |
| `SKIP_SENSITIVE_CHECK` | `false` | Skip sensitive data warning |
| `FORCE_COLOR` | `false` | Force colored output |
| `OPENAI_API_KEY` | - | For OpenAI provider |
| `AZURE_OPENAI_KEY` | - | For Azure OpenAI provider |
| `ANTHROPIC_API_KEY` | - | For Claude provider |

---

## Troubleshooting Customizations

### Rule Not Being Applied

1. Check YAML syntax: `cat .ai/java_code_review_checklist.yaml | python -c "import yaml, sys; yaml.safe_load(sys.stdin)"`
2. Verify rule ID is unique
3. Check severity spelling (BLOCK, WARN, INFO)

### AI Not Following Instructions

1. Check prompt for conflicting instructions
2. Ensure JSON format is clearly specified
3. Try adding more examples
4. Reduce prompt length if too long

### Provider API Errors

1. Check API key is set: `echo $OPENAI_API_KEY`
2. Verify endpoint URL
3. Check rate limits
4. Test API separately: `curl -s https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"`

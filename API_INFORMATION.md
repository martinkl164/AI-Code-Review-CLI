# AI Review API Information

## Current API Integration

### Primary API: GitHub Copilot CLI Extension

**Command Used:**
```bash
gh copilot suggest --target shell < prompt
```

**API Details:**
- **Provider**: GitHub Copilot
- **Interface**: GitHub CLI Extension (`gh-copilot`)
- **Authentication**: GitHub account with active Copilot subscription
- **Availability**: Requires network connection and valid subscription
- **Pricing**: Part of GitHub Copilot subscription ($10/month individual, $19/user/month business)

**Installation:**
```bash
# Install GitHub CLI
winget install --id GitHub.cli  # Windows
brew install gh                 # macOS

# Authenticate
gh auth login

# Install Copilot extension
gh extension install github/gh-copilot
```

**API Limitations:**
- ⚠️ No native structured JSON output format
- ⚠️ Designed for interactive use, not programmatic integration
- ⚠️ Rate limits apply based on subscription tier
- ⚠️ Requires active internet connection

**Check Availability:**
```bash
# Check if extension is installed
gh extension list | grep copilot

# Test the API
echo "test prompt" | gh copilot suggest --target shell
```

---

## Alternative API Options

The hook is designed to work with any AI provider. Here are alternatives:

### 1. OpenAI API (GPT-4)

**API Endpoint:**
```
https://api.openai.com/v1/chat/completions
```

**Availability:** ✅ Highly Available (99.9% uptime)

**Integration Example:**
```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "'"$REVIEW_PROMPT"'"}],
    "temperature": 0.3
  }'
```

**Pricing:**
- GPT-4: $0.03/1K input tokens, $0.06/1K output tokens
- GPT-3.5 Turbo: $0.0005/1K input tokens, $0.0015/1K output tokens

**Documentation:** https://platform.openai.com/docs/api-reference

---

### 2. Azure OpenAI Service

**API Endpoint:**
```
https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/chat/completions?api-version=2024-02-15-preview
```

**Availability:** ✅ Enterprise-grade (99.9% SLA)

**Benefits:**
- Enterprise security and compliance
- Data residency options
- Private networking support
- RBAC integration

**Integration Example:**
```bash
curl https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT/chat/completions?api-version=2024-02-15-preview \
  -H "Content-Type: application/json" \
  -H "api-key: $AZURE_OPENAI_KEY" \
  -d '{
    "messages": [{"role": "user", "content": "'"$REVIEW_PROMPT"'"}]
  }'
```

**Pricing:** Pay-as-you-go based on Azure pricing
**Documentation:** https://learn.microsoft.com/en-us/azure/ai-services/openai/

---

### 3. Claude API (Anthropic)

**API Endpoint:**
```
https://api.anthropic.com/v1/messages
```

**Availability:** ✅ Available

**Integration Example:**
```bash
curl https://api.anthropic.com/v1/messages \
  -H "content-type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-opus-20240229",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "'"$REVIEW_PROMPT"'"}]
  }'
```

**Pricing:**
- Claude 3 Opus: $15/1M input tokens, $75/1M output tokens
- Claude 3 Sonnet: $3/1M input tokens, $15/1M output tokens

**Documentation:** https://docs.anthropic.com/claude/reference

---

### 4. Local LLM (Ollama)

**API Endpoint:**
```
http://localhost:11434/api/generate
```

**Availability:** ✅ Runs locally (no internet required)

**Benefits:**
- No subscription costs
- Complete privacy (data never leaves your machine)
- No rate limits
- Works offline

**Installation:**
```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Download a model
ollama pull codellama:7b
```

**Integration Example:**
```bash
curl http://localhost:11434/api/generate \
  -d '{
    "model": "codellama:7b",
    "prompt": "'"$REVIEW_PROMPT"'",
    "stream": false
  }'
```

**Pricing:** Free (requires local compute resources)
**Documentation:** https://ollama.ai/

---

## Hook Output with API Information

When the hook runs, you'll now see:

```
[AI Review] Found Java files to review:
  - YourFile.java
[AI Review] Checking dependencies...
[AI Review] Analyzing code with GitHub Copilot CLI...
[AI Review] API: gh copilot suggest (GitHub Copilot CLI Extension)
[AI Review] Sending review request to GitHub Copilot...
```

If the API is unavailable:

```
[AI Review] GitHub Copilot CLI Not Available

API Status:
  • GitHub Copilot CLI Extension: NOT RESPONDING
  • Command attempted: gh copilot suggest --target shell
  • Exit code: 127

Possible reasons:
  1. GitHub Copilot subscription not active
  2. Extension not properly configured
  3. Network connectivity issues
  4. Authentication expired (run: gh auth login)

Alternative AI Review Options:
  • OpenAI API (GPT-4): https://platform.openai.com/docs/api-reference
  • Azure OpenAI Service: https://learn.microsoft.com/en-us/azure/ai-services/openai/
  • Claude API (Anthropic): https://www.anthropic.com/api
  • Local LLM (Ollama): https://ollama.ai/

[AI Review] Allowing commit (AI service unavailable - manual review recommended).
```

---

## Checking API Availability

### GitHub Copilot CLI

```bash
# Check if installed
gh extension list | grep copilot

# Test API
gh auth status
gh copilot --help
```

### OpenAI API

```bash
# Test API
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

### Azure OpenAI

```bash
# Test API
curl "https://YOUR-RESOURCE.openai.azure.com/openai/deployments?api-version=2024-02-15-preview" \
  -H "api-key: $AZURE_OPENAI_KEY"
```

### Ollama (Local)

```bash
# Check if running
curl http://localhost:11434/api/tags
```

---

## Switching APIs

To integrate a different API, modify these lines in `pre-commit.sh` (lines 164-183):

```bash
# Replace this section with your API call
REVIEW_OUTPUT=$(cat "$COPILOT_SCRIPT" | gh copilot suggest --target shell 2>/dev/null || echo "")

# Example for OpenAI:
# REVIEW_OUTPUT=$(curl -s https://api.openai.com/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -H "Authorization: Bearer $OPENAI_API_KEY" \
#   -d "{\"model\":\"gpt-4\",\"messages\":[{\"role\":\"user\",\"content\":$(jq -Rs . < "$COPILOT_SCRIPT")}]}" \
#   | jq -r '.choices[0].message.content')
```

---

## Summary

**Current Setup:** GitHub Copilot CLI  
**Status:** Requires subscription and network connection  
**Alternatives:** OpenAI, Azure OpenAI, Claude, Ollama  
**Recommendation:** For enterprise use, consider Azure OpenAI for better availability and SLA

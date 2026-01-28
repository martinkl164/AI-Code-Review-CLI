# Security Considerations

This document outlines the security and privacy considerations when using the CLI-Based AI Java Code Review system.

## Data Sent to AI

When you commit Java files, the following data is sent to GitHub Copilot:

| Data Type | Sent? | Notes |
|-----------|-------|-------|
| Git diff of staged `.java` files | Yes | Only added/modified lines |
| Review checklist (rules) | Yes | Your YAML configuration |
| Prompt template | Yes | The review instructions |
| File paths | Yes | Relative paths in diff |
| Line numbers | Yes | Context for issues |

## Data NOT Sent

| Data Type | Sent? | Why |
|-----------|-------|-----|
| Unstaged files | No | Only `--cached` diff extracted |
| Non-Java files | No | Filtered by extension |
| Git history | No | Only current diff |
| Full file contents | No | Only diff hunks |
| Your full codebase | No | Scoped to staged changes |
| Environment variables | No | Never included in diff |

## What Could Be Exposed

Even with safeguards, you could accidentally expose:

1. **Hardcoded secrets** in your Java code
2. **Database connection strings** if committed
3. **Internal API endpoints** or URLs
4. **Business logic** in the diff
5. **Customer data** if present in test fixtures
6. **Internal naming conventions** (project/team names)

## Recommendations

### Before Using This Tool

1. **Audit your staging area**
   ```bash
   git diff --cached  # Review what you're about to commit
   ```

2. **Never hardcode secrets**
   ```java
   // BAD - will be sent to AI
   private static final String API_KEY = "sk-1234567890";
   
   // GOOD - environment variable not in diff
   private static final String API_KEY = System.getenv("API_KEY");
   ```

3. **Use .gitignore properly**
   ```gitignore
   # Add to .gitignore
   *.pem
   *.key
   .env
   *credentials*
   application-local.properties
   ```

4. **Review the prompt template**
   - Check `.ai/java_review_prompt.txt`
   - Understand what instructions the AI receives

5. **Consider local alternatives**
   - For highly sensitive codebases, use Ollama or other local LLMs
   - See [CUSTOMIZATION.md](CUSTOMIZATION.md) for setup

### Environment Variables for Bypass

```bash
# Skip AI review for sensitive commit
git commit --no-verify -m "Sensitive commit"

# Disable AI review temporarily
export AI_REVIEW_ENABLED=false
git commit -m "Normal commit without review"

# Skip the sensitive data warning only
export SKIP_SENSITIVE_CHECK=true
git commit -m "I know what I'm doing"
```

## Compliance Notes

### GitHub Copilot Data Handling

- GitHub Copilot may process your code on GitHub's servers
- Check GitHub's [Copilot Trust Center](https://resources.github.com/copilot-trust-center/) for current policies
- Enterprise customers may have different data retention policies

### For Regulated Industries

| Regulation | Recommendation |
|------------|----------------|
| HIPAA | Use local LLM (Ollama) or disable for PHI-related code |
| GDPR | Ensure no PII in code; consider data processing agreements |
| SOC 2 | Document AI tool usage in your security policies |
| PCI DSS | Never commit card data; use tokenization |
| ITAR/EAR | Do not use cloud AI for export-controlled code |

### Self-Hosted Alternative

For air-gapped or highly regulated environments:

```bash
# Install Ollama locally
curl -fsSL https://ollama.ai/install.sh | sh

# Pull a code-capable model
ollama pull codellama

# Modify pre-commit.sh to use local endpoint
# (See CUSTOMIZATION.md for details)
```

## Security Features Built-In

This system includes several security features:

1. **Prompt Injection Protection**
   - AI instructed to ignore commands in code
   - Diff treated as untrusted data

2. **Output Redaction**
   - AI instructed to never echo actual secret values
   - Reports presence, not content

3. **Pre-flight Warning**
   - Scans diff for sensitive keywords before sending
   - User must confirm to proceed

4. **Minimal Data Principle**
   - Only staged Java files sent
   - Only diff content, not full files

## Incident Response

If you accidentally committed sensitive data:

1. **Don't push** - If not pushed yet, amend the commit
   ```bash
   git reset HEAD~1  # Undo last commit, keep changes
   # Remove sensitive data
   git add .
   git commit -m "Clean commit"
   ```

2. **If already pushed** - Rotate credentials immediately
   - Assume the secret is compromised
   - Generate new API keys/passwords
   - Update your systems

3. **Scrub history** (if needed)
   ```bash
   # Use BFG Repo-Cleaner for history scrubbing
   # https://rtyley.github.io/bfg-repo-cleaner/
   ```

## Reporting Security Issues

If you find a security vulnerability in this tool:

1. Do not open a public issue
2. Contact the maintainers privately
3. Allow time for a fix before disclosure

## Further Reading

- [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)
- [GitHub Copilot Privacy](https://docs.github.com/en/copilot/overview-of-github-copilot/about-github-copilot-individual#about-privacy-for-github-copilot-individual)
- [12-Factor App: Config](https://12factor.net/config)

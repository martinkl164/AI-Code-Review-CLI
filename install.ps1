#Requires -Version 5.1
<#
.SYNOPSIS
    Installation script for Java AI Code Review pre-commit hook (PowerShell)
.DESCRIPTION
    This script sets up the pre-commit hook and verifies dependencies.
    Works natively on Windows with PowerShell - no WSL required.
.EXAMPLE
    .\install.ps1
.NOTES
    Requires: GitHub CLI with Copilot extension
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ============================================================================
# COLOR OUTPUT FUNCTIONS
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "[$Step]" -ForegroundColor Cyan -NoNewline
    Write-Host " $Message"
}

function Write-Success { param([string]$Message) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Fail { param([string]$Message) Write-Host "[X] " -ForegroundColor Red -NoNewline; Write-Host $Message }
function Write-Warn { param([string]$Message) Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }

# ============================================================================
# MAIN INSTALLATION
# ============================================================================

Write-Host ""
Write-ColorOutput "===========================================================" 'Cyan'
Write-ColorOutput "  Java AI Code Review - PowerShell Installation" 'Cyan'
Write-ColorOutput "===========================================================" 'Cyan'
Write-Host ""

# Check if we're in a git repository
if (-not (Test-Path ".git")) {
    Write-Fail "Not a git repository. Please run this script from the root of your git project."
    exit 1
}

# Check if pre-commit.ps1 exists
if (-not (Test-Path "pre-commit.ps1")) {
    Write-Fail "pre-commit.ps1 not found in current directory."
    Write-Host "Please ensure you're running this script from the project root."
    exit 1
}

Write-Step "1/5" "Checking dependencies..."
Write-Host ""

# Check for copilot CLI (standalone)
$copilotPath = Get-Command copilot -ErrorAction SilentlyContinue
if (-not $copilotPath) {
    Write-Fail "GitHub Copilot CLI not found"
    Write-Host ""
    Write-Host "Please install GitHub Copilot CLI:" -ForegroundColor Yellow
    Write-Host "  npm install -g @githubnext/github-copilot-cli"
    Write-Host ""
    Write-Host "After installation, authenticate with:"
    Write-Host "  copilot auth"
    Write-Host ""
    exit 1
}

# Show version
$copilotVersion = & copilot --version 2>&1 | Select-Object -First 1
Write-Success "GitHub Copilot CLI found ($copilotVersion)"

Write-Host ""
Write-Step "2/5" "Checking required files..."
Write-Host ""

# Check for .ai directory
if (-not (Test-Path ".ai")) {
    Write-Warn ".ai directory not found, creating it..."
    New-Item -ItemType Directory -Path ".ai" -Force | Out-Null
}

# Check for agent configuration
if (-not (Test-Path ".ai/agents")) {
    Write-Fail ".ai/agents directory not found"
    Write-Host "This directory is required for multi-agent system."
    exit 1
}
Write-Success "Agent configuration found"

# Check for agent directories
$agents = @("security", "naming", "quality", "summarizer")
foreach ($agent in $agents) {
    $agentDir = ".ai/agents/$agent"
    if (-not (Test-Path $agentDir)) {
        Write-Warn "Agent directory '$agentDir' not found"
    }
    else {
        Write-Success "Agent '$agent' configuration found"
    }
}

Write-Host ""
Write-Step "3/5" "Installing pre-commit hook..."
Write-Host ""

# Create hooks directory if it doesn't exist
$hooksDir = ".git/hooks"
if (-not (Test-Path $hooksDir)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
}

# Create the hook wrapper script
# Git on Windows expects a bash-compatible hook, so we create a wrapper
$hookPath = Join-Path $hooksDir "pre-commit"
$hookContent = @'
#!/bin/sh
# Pre-commit hook wrapper - calls PowerShell script
# This wrapper allows git to execute the PowerShell pre-commit hook

# Get the directory where this script lives
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

# Execute PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$REPO_ROOT/pre-commit.ps1"
exit $?
'@

try {
    # Write hook with Unix line endings for git compatibility
    $hookContent -replace "`r`n", "`n" | Set-Content $hookPath -Encoding ASCII -NoNewline
    Write-Success "Pre-commit hook installed to $hookPath"
}
catch {
    Write-Fail "Failed to create pre-commit hook"
    Write-Host "Error: $_"
    exit 1
}

Write-Host ""
Write-Step "4/5" "Verifying hook configuration..."
Write-Host ""

# Check if PowerShell script exists
if (Test-Path "pre-commit.ps1") {
    Write-Success "PowerShell pre-commit script found"
}
else {
    Write-Fail "pre-commit.ps1 not found"
    exit 1
}

# Verify the hook file was created
if (Test-Path $hookPath) {
    Write-Success "Hook file created successfully"
}
else {
    Write-Fail "Hook file was not created"
    exit 1
}

Write-Host ""
Write-Step "5/5" "Testing installation..."
Write-Host ""

# Test if PowerShell can find copilot
$copilotTest = Get-Command copilot -ErrorAction SilentlyContinue
if ($copilotTest) {
    Write-Success "Copilot CLI is accessible from PowerShell"
}
else {
    Write-Warn "Copilot CLI may not be in PATH. Ensure gh-copilot is installed correctly."
}

# Final status
Write-Host ""
Write-ColorOutput "===========================================================" 'Green'
Write-ColorOutput "  Installation Complete!" 'Green'
Write-ColorOutput "===========================================================" 'Green'
Write-Host ""

Write-Host "Next steps:"
Write-Host ""
Write-Host "  1. Ensure you're authenticated with GitHub:"
Write-ColorOutput "     gh auth login" 'Cyan'
Write-Host ""
Write-Host "  2. Stage some Java files and try a commit:"
Write-ColorOutput "     git add YourFile.java" 'Cyan'
Write-ColorOutput "     git commit -m `"Test commit`"" 'Cyan'
Write-Host ""
Write-Host "  3. The AI review will run automatically!"
Write-Host ""

Write-Host "Tips:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  - To disable AI review for a single commit:"
Write-ColorOutput "    git commit --no-verify" 'Cyan'
Write-Host ""
Write-Host "  - To disable AI review permanently:"
Write-ColorOutput "    `$env:AI_REVIEW_ENABLED = 'false'" 'Cyan'
Write-Host ""
Write-Host "  - Review results are saved to:"
Write-ColorOutput "    .ai/last_review.json" 'Cyan'
Write-Host ""
Write-Host "  - View agent reports:"
Write-ColorOutput "    Get-Content .ai/agents/security/review.md" 'Cyan'
Write-ColorOutput "    Get-Content .ai/agents/naming/review.md" 'Cyan'
Write-ColorOutput "    Get-Content .ai/agents/quality/review.md" 'Cyan'
Write-Host ""

#Requires -Version 5.1
<#
.SYNOPSIS
    PowerShell pre-commit hook for Java AI code review
.DESCRIPTION
    A multi-agent AI code review system that runs at commit time.
    Requires: GitHub CLI with Copilot extension installed and authenticated
.NOTES
    Usage: Run install.ps1 to set up, or manually copy to .git/hooks/pre-commit
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION
# ============================================================================

$AI_DIR = ".ai"
$CHECKLIST_FILE = "$AI_DIR/java_code_review_checklist.yaml"
$PROMPT_FILE = "$AI_DIR/java_review_prompt.txt"
$LAST_REVIEW_FILE = "$AI_DIR/last_review.json"
$MAX_DIFF_SIZE = 20000  # bytes

# Windows command-line argument length limit is ~8191 chars
# We use a lower threshold to be safe with escaping overhead
$MAX_ARG_LENGTH = 7000

# AI Model configuration (can be overridden via environment variable)
# Available models: gpt-4.1, gpt-5, gpt-5-mini, gpt-5.1, gpt-5.1-codex, gpt-5.1-codex-mini,
#                   gpt-5.1-codex-max, gpt-5.2, gpt-5.2-codex, claude-sonnet-4, claude-sonnet-4.5,
#                   claude-haiku-4.5, claude-opus-4.5, gemini-3-pro-preview
$AI_MODEL = if ($env:AI_REVIEW_MODEL) { $env:AI_REVIEW_MODEL } else { "gpt-4.1" }

# Temporary directory
$TEMP_DIR = Join-Path $AI_DIR "temp"
if (-not (Test-Path $TEMP_DIR)) {
    New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null
}

# ============================================================================
# COPILOT INVOCATION HELPER
# ============================================================================
# This function handles calling copilot by saving prompts to files and having
# copilot read them. This avoids Windows command-line argument length limits.

function Invoke-CopilotWithPrompt {
    param(
        [string]$Prompt,
        [string]$TempFilePrefix = "copilot_prompt",
        [string]$Model = $script:AI_MODEL
    )
    
    # Save prompt to temp file
    $PromptFile = Join-Path $TEMP_DIR "${TempFilePrefix}_$PID.txt"
    
    try {
        # Write prompt to file with UTF8 encoding (no BOM for better compatibility)
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PromptFile, $Prompt, $Utf8NoBom)
        
        # Create a short instruction prompt that tells copilot to read the file
        $InstructionPrompt = "Read and execute the instructions in the file: $PromptFile"
        
        # Call copilot with the instruction prompt and configured model
        $Output = & copilot -p $InstructionPrompt --model $Model --silent --allow-all-tools --add-dir $TEMP_DIR 2>&1
        
        return $Output
    }
    finally {
        # Keep the file for a moment to allow copilot to read it
        Start-Sleep -Milliseconds 500
        Remove-Item $PromptFile -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# COLOR OUTPUT FUNCTIONS
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Info { param([string]$Message) Write-ColorOutput "[AI Review] $Message" 'Cyan' }
function Write-Success { param([string]$Message) Write-ColorOutput "[AI Review] $Message" 'Green' }
function Write-Warning { param([string]$Message) Write-ColorOutput "[AI Review] $Message" 'Yellow' }
function Write-Error { param([string]$Message) Write-ColorOutput "[AI Review] $Message" 'Red' }

# ============================================================================
# MULTI-AGENT HELPER FUNCTIONS
# ============================================================================

function Invoke-Agent {
    param(
        [string]$AgentName,
        [string]$DiffContent
    )
    
    $AgentDir = Join-Path $AI_DIR "agents/$AgentName"
    $AgentChecklist = Join-Path $AgentDir "checklist.yaml"
    $AgentPrompt = Join-Path $AgentDir "prompt.txt"
    $AgentOutput = Join-Path $AgentDir "review.json"
    
    # Check if agent files exist
    if (-not (Test-Path $AgentChecklist) -or -not (Test-Path $AgentPrompt)) {
        Write-Error "Agent '$AgentName' configuration not found"
        @{agent=$AgentName; issues=@(); summary="Configuration error"} | ConvertTo-Json | Set-Content $AgentOutput -Encoding UTF8
        return $false
    }
    
    # Load checklist and compose prompt
    $ChecklistContent = Get-Content $AgentChecklist -Raw -Encoding UTF8
    $PromptTemplate = Get-Content $AgentPrompt -Raw -Encoding UTF8
    
    # Replace placeholders
    $FullPrompt = $PromptTemplate -replace '\{checklist\}', $ChecklistContent -replace '\{diff\}', $DiffContent
    
    try {
        # Use helper function to handle large prompts
        $ReviewOutput = Invoke-CopilotWithPrompt -Prompt $FullPrompt -TempFilePrefix "${AgentName}_prompt"
        if ([string]::IsNullOrWhiteSpace($ReviewOutput)) {
            $ReviewOutput = "# Error`n`nAgent failed to execute"
        }
    }
    catch {
        $ReviewOutput = "# Error`n`nAgent failed to execute: $_"
    }
    
    # Save agent output
    if (-not (Test-Path $AgentDir)) {
        New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
    }
    $ReviewOutput | Set-Content $AgentOutput -Encoding UTF8
    
    return $true
}

function Invoke-SummarizerAgent {
    param(
        [string]$SecurityJson,
        [string]$NamingJson,
        [string]$QualityJson
    )
    
    $SummarizerPrompt = Join-Path $AI_DIR "agents/summarizer/prompt.txt"
    
    if (-not (Test-Path $SummarizerPrompt)) {
        Write-Error "Summarizer prompt not found"
        return '{"agent":"summarizer","issues":[],"summary":"Configuration error","recommendation":"ALLOW_COMMIT"}'
    }
    
    # Compose summarizer prompt
    $PromptTemplate = Get-Content $SummarizerPrompt -Raw -Encoding UTF8
    $FullPrompt = $PromptTemplate `
        -replace '\{security_report\}', $SecurityJson `
        -replace '\{naming_report\}', $NamingJson `
        -replace '\{quality_report\}', $QualityJson
    
    $FullPrompt += "`n`nCRITICAL: Output ONLY valid JSON."
    
    try {
        # Use helper function to handle large prompts
        $SummarizerOutput = Invoke-CopilotWithPrompt -Prompt $FullPrompt -TempFilePrefix "summarizer_prompt"
        if ([string]::IsNullOrWhiteSpace($SummarizerOutput)) {
            $SummarizerOutput = '{"agent":"summarizer","issues":[],"summary":"API error","recommendation":"ALLOW_COMMIT"}'
        }
    }
    catch {
        $SummarizerOutput = '{"agent":"summarizer","issues":[],"summary":"API error","recommendation":"ALLOW_COMMIT"}'
    }
    
    # Extract JSON if wrapped in markdown code block
    if ($SummarizerOutput -match '```json\s*([\s\S]*?)\s*```') {
        $SummarizerJson = $Matches[1]
    }
    elseif ($SummarizerOutput -match '\{.*\}') {
        $SummarizerJson = $Matches[0]
    }
    else {
        $SummarizerJson = '{"agent":"summarizer","issues":[],"summary":"Parse error","recommendation":"ALLOW_COMMIT"}'
    }
    
    # Save final review
    $SummarizerJson | Set-Content $LAST_REVIEW_FILE -Encoding UTF8
    
    return $SummarizerJson
}

function Get-AgentIssuesFromReport {
    param([string]$AgentReport)
    
    $Issues = @()
    $JsonContent = $null
    
    if ($AgentReport -match '```json\s*([\s\S]*?)\s*```') {
        $JsonContent = $Matches[1]
    }
    elseif ($AgentReport -match '\{[\s\S]*"issues"[\s\S]*\}') {
        $JsonContent = $Matches[0]
    }
    
    if ($JsonContent) {
        try {
            $JsonObj = $JsonContent | ConvertFrom-Json -ErrorAction Stop
            $Issues = @($JsonObj.issues)
        }
        catch { }
    }
    
    return $Issues
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

# Check if AI review is enabled
if ($env:AI_REVIEW_ENABLED -eq 'false') {
    Write-Info "Skipped (AI_REVIEW_ENABLED=false)"
    exit 0
}

# Get list of staged Java files
$StagedJavaFiles = git diff --cached --name-only --diff-filter=ACM 2>$null | Where-Object { $_ -match '\.java$' }

if (-not $StagedJavaFiles) {
    Write-Info "No Java files staged, skipping review."
    exit 0
}

Write-Info "Found Java files to review:"
$StagedJavaFiles | ForEach-Object { Write-Host "  - $_" }

# Dependency checks
Write-Info "Checking dependencies..."

# Check for copilot CLI
$CopilotPath = Get-Command copilot -ErrorAction SilentlyContinue
if (-not $CopilotPath) {
    Write-Error "Required command 'copilot' not found."
    Write-Host ""
    Write-Host "GitHub Copilot CLI is required. Install it:" -ForegroundColor Yellow
    Write-Host "  npm install -g @githubnext/github-copilot-cli"
    Write-Host ""
    Write-Host "After installation, authenticate with: copilot auth"
    Write-Host ""
    Write-Host "To bypass this check temporarily, use: git commit --no-verify"
    exit 1
}
Write-Info "Found copilot"

# Check if required files exist
if (-not (Test-Path $CHECKLIST_FILE)) {
    Write-Error "Checklist file not found: $CHECKLIST_FILE"
    exit 1
}

if (-not (Test-Path $PROMPT_FILE)) {
    Write-Error "Prompt file not found: $PROMPT_FILE"
    exit 1
}

# Extract staged diff for Java files
$DiffFile = Join-Path $TEMP_DIR "java_review_diff_$PID.patch"
$DiffContent = ""

foreach ($file in $StagedJavaFiles) {
    $DiffContent += git diff --cached -- $file
    $DiffContent += "`n"
}

if ([string]::IsNullOrWhiteSpace($DiffContent)) {
    Write-Info "No changes to review."
    exit 0
}

# Check diff size and truncate if needed
$DiffBytes = [System.Text.Encoding]::UTF8.GetByteCount($DiffContent)
if ($DiffBytes -gt $MAX_DIFF_SIZE) {
    $DiffContent = $DiffContent.Substring(0, $MAX_DIFF_SIZE)
    Write-Warning "Warning: Diff truncated to $MAX_DIFF_SIZE bytes for review."
}

# Security check: Warn if diff may contain sensitive data
if ($env:SKIP_SENSITIVE_CHECK -ne 'true') {
    if ($DiffContent -match '(password\s*=|secret\s*=|api[_-]?key\s*=|token\s*=|credential|private[_-]?key)') {
        Write-Host ""
        Write-ColorOutput "========================================================" 'Yellow'
        Write-ColorOutput "  SECURITY WARNING: Potential sensitive data detected   " 'Yellow'
        Write-ColorOutput "========================================================" 'Yellow'
        Write-Host ""
        Write-Host "Your staged code may contain sensitive keywords (password, secret, api_key, etc.)."
        Write-Host "This code will be sent to an external AI service for review."
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  1. Review your staged changes: git diff --cached"
        Write-Host "  2. Use environment variables instead of hardcoded values"
        Write-Host "  3. Skip this check: `$env:SKIP_SENSITIVE_CHECK='true'; git commit ..."
        Write-Host "  4. Skip AI review entirely: git commit --no-verify"
        Write-Host ""
        $response = Read-Host "Continue with AI review? (y/n)"
        if ($response -notin @('y', 'Y')) {
            Write-Info "Commit aborted by user. Review your code for sensitive data."
            exit 1
        }
    }
}

# ============================================================================
# MULTI-AGENT CODE REVIEW
# ============================================================================

Write-Host ""
Write-ColorOutput "[AI Review] Running analysis (model: $AI_MODEL)..." 'Cyan'

# Save diff to temp file for parallel jobs
$DiffTempFile = Join-Path $TEMP_DIR "diff_content_$PID.txt"
$DiffContent | Set-Content $DiffTempFile -Encoding UTF8

# Run agents in parallel using PowerShell jobs
$SecurityJob = Start-Job -ScriptBlock {
    param($ScriptRoot, $DiffFile, $Model)
    Set-Location $ScriptRoot
    $DiffContent = Get-Content $DiffFile -Raw -Encoding UTF8
    
    $AI_DIR = ".ai"
    $TEMP_DIR = Join-Path $AI_DIR "temp"
    $AgentName = "security"
    $AgentDir = Join-Path $AI_DIR "agents/$AgentName"
    $AgentChecklist = Join-Path $AgentDir "checklist.yaml"
    $AgentPrompt = Join-Path $AgentDir "prompt.txt"
    $AgentOutput = Join-Path $AgentDir "review.json"
    
    if ((Test-Path $AgentChecklist) -and (Test-Path $AgentPrompt)) {
        $ChecklistContent = Get-Content $AgentChecklist -Raw -Encoding UTF8
        $PromptTemplate = Get-Content $AgentPrompt -Raw -Encoding UTF8
        $FullPrompt = $PromptTemplate -replace '\{checklist\}', $ChecklistContent -replace '\{diff\}', $DiffContent
        
        $PromptFile = Join-Path $TEMP_DIR "${AgentName}_job_prompt_$PID.txt"
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PromptFile, $FullPrompt, $Utf8NoBom)
        
        try {
            $InstructionPrompt = "Read and execute the instructions in the file: $PromptFile"
            $ReviewOutput = & copilot -p $InstructionPrompt --model $Model --silent --allow-all-tools --add-dir $TEMP_DIR 2>&1
        }
        catch {
            $ReviewOutput = "# Error`n`nAgent failed to execute: $_"
        }
        finally {
            Start-Sleep -Milliseconds 500
            Remove-Item $PromptFile -Force -ErrorAction SilentlyContinue
        }
        
        if ([string]::IsNullOrWhiteSpace($ReviewOutput)) {
            $ReviewOutput = "# Error`n`nAgent returned empty response"
        }
        
        $ReviewOutput | Set-Content $AgentOutput -Encoding UTF8
    }
} -ArgumentList (Get-Location).Path, $DiffTempFile, $AI_MODEL

$NamingJob = Start-Job -ScriptBlock {
    param($ScriptRoot, $DiffFile, $Model)
    Set-Location $ScriptRoot
    $DiffContent = Get-Content $DiffFile -Raw -Encoding UTF8
    
    $AI_DIR = ".ai"
    $TEMP_DIR = Join-Path $AI_DIR "temp"
    $AgentName = "naming"
    $AgentDir = Join-Path $AI_DIR "agents/$AgentName"
    $AgentChecklist = Join-Path $AgentDir "checklist.yaml"
    $AgentPrompt = Join-Path $AgentDir "prompt.txt"
    $AgentOutput = Join-Path $AgentDir "review.json"
    
    if ((Test-Path $AgentChecklist) -and (Test-Path $AgentPrompt)) {
        $ChecklistContent = Get-Content $AgentChecklist -Raw -Encoding UTF8
        $PromptTemplate = Get-Content $AgentPrompt -Raw -Encoding UTF8
        $FullPrompt = $PromptTemplate -replace '\{checklist\}', $ChecklistContent -replace '\{diff\}', $DiffContent
        
        $PromptFile = Join-Path $TEMP_DIR "${AgentName}_job_prompt_$PID.txt"
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PromptFile, $FullPrompt, $Utf8NoBom)
        
        try {
            $InstructionPrompt = "Read and execute the instructions in the file: $PromptFile"
            $ReviewOutput = & copilot -p $InstructionPrompt --model $Model --silent --allow-all-tools --add-dir $TEMP_DIR 2>&1
        }
        catch {
            $ReviewOutput = "# Error`n`nAgent failed to execute: $_"
        }
        finally {
            Start-Sleep -Milliseconds 500
            Remove-Item $PromptFile -Force -ErrorAction SilentlyContinue
        }
        
        if ([string]::IsNullOrWhiteSpace($ReviewOutput)) {
            $ReviewOutput = "# Error`n`nAgent returned empty response"
        }
        
        $ReviewOutput | Set-Content $AgentOutput -Encoding UTF8
    }
} -ArgumentList (Get-Location).Path, $DiffTempFile, $AI_MODEL

$QualityJob = Start-Job -ScriptBlock {
    param($ScriptRoot, $DiffFile, $Model)
    Set-Location $ScriptRoot
    $DiffContent = Get-Content $DiffFile -Raw -Encoding UTF8
    
    $AI_DIR = ".ai"
    $TEMP_DIR = Join-Path $AI_DIR "temp"
    $AgentName = "quality"
    $AgentDir = Join-Path $AI_DIR "agents/$AgentName"
    $AgentChecklist = Join-Path $AgentDir "checklist.yaml"
    $AgentPrompt = Join-Path $AgentDir "prompt.txt"
    $AgentOutput = Join-Path $AgentDir "review.json"
    
    if ((Test-Path $AgentChecklist) -and (Test-Path $AgentPrompt)) {
        $ChecklistContent = Get-Content $AgentChecklist -Raw -Encoding UTF8
        $PromptTemplate = Get-Content $AgentPrompt -Raw -Encoding UTF8
        $FullPrompt = $PromptTemplate -replace '\{checklist\}', $ChecklistContent -replace '\{diff\}', $DiffContent
        
        $PromptFile = Join-Path $TEMP_DIR "${AgentName}_job_prompt_$PID.txt"
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PromptFile, $FullPrompt, $Utf8NoBom)
        
        try {
            $InstructionPrompt = "Read and execute the instructions in the file: $PromptFile"
            $ReviewOutput = & copilot -p $InstructionPrompt --model $Model --silent --allow-all-tools --add-dir $TEMP_DIR 2>&1
        }
        catch {
            $ReviewOutput = "# Error`n`nAgent failed to execute: $_"
        }
        finally {
            Start-Sleep -Milliseconds 500
            Remove-Item $PromptFile -Force -ErrorAction SilentlyContinue
        }
        
        if ([string]::IsNullOrWhiteSpace($ReviewOutput)) {
            $ReviewOutput = "# Error`n`nAgent returned empty response"
        }
        
        $ReviewOutput | Set-Content $AgentOutput -Encoding UTF8
    }
} -ArgumentList (Get-Location).Path, $DiffTempFile, $AI_MODEL

# Wait for all jobs to complete
$AllJobs = @($SecurityJob, $NamingJob, $QualityJob)
$null = Wait-Job -Job $AllJobs -Timeout 120

# Check job results
$SecurityExit = if ($SecurityJob.State -eq 'Completed') { 0 } else { 1 }
$NamingExit = if ($NamingJob.State -eq 'Completed') { 0 } else { 1 }
$QualityExit = if ($QualityJob.State -eq 'Completed') { 0 } else { 1 }

# Clean up jobs
Remove-Job -Job $AllJobs -Force -ErrorAction SilentlyContinue

# Clean up temp diff file
Remove-Item $DiffTempFile -Force -ErrorAction SilentlyContinue

# Check if all agents failed
if ($SecurityExit -ne 0 -and $NamingExit -ne 0 -and $QualityExit -ne 0) {
    Write-Host ""
    Write-ColorOutput "========================================================" 'Red'
    Write-ColorOutput "  AI REVIEW: SERVICE UNAVAILABLE                        " 'Red'
    Write-ColorOutput "========================================================" 'Yellow'
    Write-Host ""
    Write-Host "All AI agents failed to complete. The review could not be performed."
    Write-Host ""
    Write-Host "To commit without AI review, run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  git commit --no-verify -m `"your message`"" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# Read agent results
$SecurityReport = if (Test-Path "$AI_DIR/agents/security/review.json") {
    Get-Content "$AI_DIR/agents/security/review.json" -Raw -Encoding UTF8
} else { "Error reading security report" }

# Check for quota/API errors in agent output
if ($SecurityReport -match 'Quota exceeded|402|no quota|rate limit|CAPIError') {
    Write-Host ""
    Write-ColorOutput "========================================================" 'Red'
    Write-ColorOutput "  AI REVIEW: COPILOT QUOTA EXCEEDED                     " 'Red'
    Write-ColorOutput "========================================================" 'Yellow'
    Write-Host ""
    Write-Host "Your GitHub Copilot usage quota has been exceeded."
    Write-Host "Check your plan: https://github.com/features/copilot/plans"
    Write-Host ""
    Write-Host "To commit without AI review, run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  git commit --no-verify -m `"your message`"" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

$NamingReport = if (Test-Path "$AI_DIR/agents/naming/review.json") {
    Get-Content "$AI_DIR/agents/naming/review.json" -Raw -Encoding UTF8
} else { "Error reading naming report" }

$QualityReport = if (Test-Path "$AI_DIR/agents/quality/review.json") {
    Get-Content "$AI_DIR/agents/quality/review.json" -Raw -Encoding UTF8
} else { "Error reading quality report" }

# Count issues per agent (quick count for progress display)
$SecurityCount = ([regex]::Matches($SecurityReport, '"severity"')).Count
$NamingCount = ([regex]::Matches($NamingReport, '"severity"')).Count
$QualityCount = ([regex]::Matches($QualityReport, '"severity"')).Count

Write-Info "-> Security: $SecurityCount | Naming: $NamingCount | Quality: $QualityCount"

# Run summarizer
Write-Info "Aggregating results..."
$FinalReport = Invoke-SummarizerAgent -SecurityJson $SecurityReport -NamingJson $NamingReport -QualityJson $QualityReport

# Collect all issues from all agents
$AllIssues = @()
$AllIssues += Get-AgentIssuesFromReport -AgentReport $SecurityReport
$AllIssues += Get-AgentIssuesFromReport -AgentReport $NamingReport
$AllIssues += Get-AgentIssuesFromReport -AgentReport $QualityReport

# Count by severity
$BlockIssues = @($AllIssues | Where-Object { $_.severity -in @('BLOCK', 'CRITICAL') })
$WarnIssues = @($AllIssues | Where-Object { $_.severity -in @('WARN', 'WARNING') })
$InfoIssues = @($AllIssues | Where-Object { $_.severity -eq 'INFO' })

$BlockCount = $BlockIssues.Count
$WarnCount = $WarnIssues.Count
$InfoCount = $InfoIssues.Count
$TotalCount = $AllIssues.Count

# Make commit decision based on BLOCK issues
if ($BlockCount -gt 0) {
    Write-Host ""
    Write-ColorOutput "========================================================" 'Red'
    Write-ColorOutput "  COMMIT BLOCKED - $BlockCount Critical Issue(s) Found" 'Red'
    Write-ColorOutput "========================================================" 'Red'
    Write-Host ""
    
    $BlockIssues | ForEach-Object {
        Write-Host "  [BLOCK] $($_.file):$($_.line)" -ForegroundColor Red
        Write-Host "    $($_.message)"
    }
    
    if ($WarnCount -gt 0) {
        Write-Host ""
        Write-Host "  + $WarnCount warning(s)" -ForegroundColor Yellow
    }
    if ($InfoCount -gt 0) {
        Write-Host "  + $InfoCount info suggestion(s)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "To bypass: " -NoNewline
    Write-Host "git commit --no-verify -m `"message`"" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# No blocking issues - show summary
Write-Host ""
if ($TotalCount -eq 0) {
    Write-ColorOutput "[AI Review] No issues found. Commit allowed." 'Green'
}
else {
    Write-ColorOutput "[AI Review] $WarnCount warning(s), $InfoCount suggestion(s). Commit allowed." 'Green'
    
    if ($WarnCount -gt 0) {
        $WarnIssues | Select-Object -First 3 | ForEach-Object {
            Write-Host "  [WARN] $($_.file):$($_.line) - $($_.message)" -ForegroundColor Yellow
        }
        if ($WarnCount -gt 3) {
            Write-Host "  ... +$($WarnCount - 3) more warnings" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
exit 0

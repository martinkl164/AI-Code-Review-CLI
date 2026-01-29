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
        [string]$TempFilePrefix = "copilot_prompt"
    )
    
    # Save prompt to temp file
    $PromptFile = Join-Path $TEMP_DIR "${TempFilePrefix}_$PID.txt"
    
    try {
        # Write prompt to file with UTF8 encoding (no BOM for better compatibility)
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PromptFile, $Prompt, $Utf8NoBom)
        
        # Create a short instruction prompt that tells copilot to read the file
        $InstructionPrompt = "Read and execute the instructions in the file: $PromptFile"
        
        # Call copilot with the instruction prompt
        $Output = & copilot -p $InstructionPrompt --silent --allow-all-tools --add-dir $TEMP_DIR 2>&1
        
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

function Show-AgentResults {
    param(
        [string]$AgentReport,
        [string]$AgentName,
        [string]$AgentDisplay
    )
    
    # Try to extract JSON from markdown code block
    $JsonContent = $null
    if ($AgentReport -match '```json\s*([\s\S]*?)\s*```') {
        $JsonContent = $Matches[1]
    }
    elseif ($AgentReport -match '\{[\s\S]*"issues"[\s\S]*\}') {
        $JsonContent = $Matches[0]
    }
    
    $IssueCount = 0
    $Summary = "No summary available"
    $Issues = @()
    
    if ($JsonContent) {
        try {
            $JsonObj = $JsonContent | ConvertFrom-Json -ErrorAction Stop
            $Summary = $JsonObj.summary
            $Issues = $JsonObj.issues
            $IssueCount = $Issues.Count
        }
        catch {
            # Fall back to regex counting
            $IssueCount = ([regex]::Matches($AgentReport, '"severity"')).Count
        }
    }
    else {
        # Fall back to counting severity occurrences
        $IssueCount = ([regex]::Matches($AgentReport, '"severity"')).Count
    }
    
    Write-Host ""
    Write-ColorOutput "============================================" 'Cyan'
    Write-ColorOutput "$AgentDisplay Agent Results" 'Cyan'
    Write-ColorOutput "============================================" 'Cyan'
    Write-Host "  Summary: $Summary"
    Write-Host "  Issues found: $IssueCount"
    
    if ($Issues.Count -gt 0) {
        Write-Host ""
        $Issues | Select-Object -First 5 | ForEach-Object {
            $severity = $_.severity
            $file = $_.file
            $line = $_.line
            $message = $_.message
            $color = switch ($severity) {
                'BLOCK' { 'Red' }
                'CRITICAL' { 'Red' }
                'WARN' { 'Yellow' }
                'WARNING' { 'Yellow' }
                default { 'White' }
            }
            Write-Host "  [$severity] ${file}:${line}" -ForegroundColor $color
            Write-Host "    $message"
        }
        if ($Issues.Count -gt 5) {
            Write-Host "  ... and $($Issues.Count - 5) more issues"
        }
    }
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
Write-ColorOutput "============================================" 'Cyan'
Write-ColorOutput "Multi-Agent Code Review System" 'Cyan'
Write-ColorOutput "============================================" 'Cyan'
Write-Host ""
Write-Info "Launching specialized agents in parallel..."
Write-Host "  -> Security Agent (checking OWASP vulnerabilities, hardcoded secrets, injection attacks)"
Write-Host "  -> Naming Agent (checking Java conventions: PascalCase, camelCase, UPPER_SNAKE_CASE)"
Write-Host "  -> Code Quality Agent (checking correctness, thread safety, exception handling)"
Write-Host ""

# Save diff to temp file for parallel jobs
$DiffTempFile = Join-Path $TEMP_DIR "diff_content_$PID.txt"
$DiffContent | Set-Content $DiffTempFile -Encoding UTF8

# Run agents in parallel using PowerShell jobs
# Each job writes prompt to a temp file and has copilot read it (avoids argument length limits)
Write-Info "-> Security Agent: Running..."
$SecurityJob = Start-Job -ScriptBlock {
    param($ScriptRoot, $DiffFile)
    Set-Location $ScriptRoot
    $DiffContent = Get-Content $DiffFile -Raw -Encoding UTF8
    
    # Inline agent execution
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
        
        # Save prompt to file for copilot to read
        $PromptFile = Join-Path $TEMP_DIR "${AgentName}_job_prompt_$PID.txt"
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PromptFile, $FullPrompt, $Utf8NoBom)
        
        try {
            # Have copilot read the prompt file
            $InstructionPrompt = "Read and execute the instructions in the file: $PromptFile"
            $ReviewOutput = & copilot -p $InstructionPrompt --silent --allow-all-tools --add-dir $TEMP_DIR 2>&1
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
} -ArgumentList (Get-Location).Path, $DiffTempFile

Write-Info "-> Naming Agent: Running..."
$NamingJob = Start-Job -ScriptBlock {
    param($ScriptRoot, $DiffFile)
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
        
        # Save prompt to file for copilot to read
        $PromptFile = Join-Path $TEMP_DIR "${AgentName}_job_prompt_$PID.txt"
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PromptFile, $FullPrompt, $Utf8NoBom)
        
        try {
            $InstructionPrompt = "Read and execute the instructions in the file: $PromptFile"
            $ReviewOutput = & copilot -p $InstructionPrompt --silent --allow-all-tools --add-dir $TEMP_DIR 2>&1
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
} -ArgumentList (Get-Location).Path, $DiffTempFile

Write-Info "-> Code Quality Agent: Running..."
$QualityJob = Start-Job -ScriptBlock {
    param($ScriptRoot, $DiffFile)
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
        
        # Save prompt to file for copilot to read
        $PromptFile = Join-Path $TEMP_DIR "${AgentName}_job_prompt_$PID.txt"
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PromptFile, $FullPrompt, $Utf8NoBom)
        
        try {
            $InstructionPrompt = "Read and execute the instructions in the file: $PromptFile"
            $ReviewOutput = & copilot -p $InstructionPrompt --silent --allow-all-tools --add-dir $TEMP_DIR 2>&1
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
} -ArgumentList (Get-Location).Path, $DiffTempFile

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
    Write-ColorOutput "========================================================" 'Yellow'
    Write-ColorOutput "  Multi-Agent Review: NOT AVAILABLE                     " 'Yellow'
    Write-ColorOutput "========================================================" 'Yellow'
    Write-Host ""
    Write-Success "Allowing commit (AI service unavailable - manual review recommended)"
    Write-Host ""
    exit 0
}

# Read agent results
$SecurityReport = if (Test-Path "$AI_DIR/agents/security/review.json") {
    Get-Content "$AI_DIR/agents/security/review.json" -Raw -Encoding UTF8
} else { "Error reading security report" }

$NamingReport = if (Test-Path "$AI_DIR/agents/naming/review.json") {
    Get-Content "$AI_DIR/agents/naming/review.json" -Raw -Encoding UTF8
} else { "Error reading naming report" }

$QualityReport = if (Test-Path "$AI_DIR/agents/quality/review.json") {
    Get-Content "$AI_DIR/agents/quality/review.json" -Raw -Encoding UTF8
} else { "Error reading quality report" }

# Count issues per agent
$SecurityCount = ([regex]::Matches($SecurityReport, '^\### \[', 'Multiline')).Count
if ($SecurityCount -eq 0) {
    $SecurityCount = ([regex]::Matches($SecurityReport, '"severity"')).Count
}

$NamingCount = ([regex]::Matches($NamingReport, '^\### \[', 'Multiline')).Count
if ($NamingCount -eq 0) {
    $NamingCount = ([regex]::Matches($NamingReport, '"severity"')).Count
}

$QualityCount = ([regex]::Matches($QualityReport, '^\### \[', 'Multiline')).Count
if ($QualityCount -eq 0) {
    $QualityCount = ([regex]::Matches($QualityReport, '"severity"')).Count
}

Write-Info "-> Security Agent: Complete (found $SecurityCount issues)"
Write-Info "-> Naming Agent: Complete (found $NamingCount issues)"
Write-Info "-> Code Quality Agent: Complete (found $QualityCount issues)"

# Run summarizer to aggregate results
Write-Host ""
Write-Info "Aggregating results from all agents..."
Write-Info "-> Summarizer Agent: Deduplicating and prioritizing findings..."

$FinalReport = Invoke-SummarizerAgent -SecurityJson $SecurityReport -NamingJson $NamingReport -QualityJson $QualityReport

Write-Info "-> Summarizer Agent: Complete"

# Display per-agent results
Write-Host ""
Write-ColorOutput "============================================" 'Cyan'
Write-ColorOutput "Review Results by Agent" 'Cyan'
Write-ColorOutput "============================================" 'Cyan'

Show-AgentResults -AgentReport $SecurityReport -AgentName "security" -AgentDisplay "Security"
Show-AgentResults -AgentReport $NamingReport -AgentName "naming" -AgentDisplay "Naming"
Show-AgentResults -AgentReport $QualityReport -AgentName "quality" -AgentDisplay "Code Quality"

# Display final summary
Write-Host ""
Write-ColorOutput "============================================" 'Cyan'
Write-ColorOutput "Final Summary" 'Cyan'
Write-ColorOutput "============================================" 'Cyan'
Write-Host ""

# Helper function to extract JSON and issues from agent report
function Get-AgentIssues {
    param([string]$Report)
    
    $Issues = @()
    $JsonContent = $null
    
    if ($Report -match '```json\s*([\s\S]*?)\s*```') {
        $JsonContent = $Matches[1]
    }
    elseif ($Report -match '\{[\s\S]*"issues"[\s\S]*\}') {
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

# Collect all issues from all agents
$AllIssues = @()
$AllIssues += Get-AgentIssues -Report $SecurityReport
$AllIssues += Get-AgentIssues -Report $NamingReport
$AllIssues += Get-AgentIssues -Report $QualityReport

# Count by severity
$BlockIssues = @($AllIssues | Where-Object { $_.severity -in @('BLOCK', 'CRITICAL') })
$WarnIssues = @($AllIssues | Where-Object { $_.severity -in @('WARN', 'WARNING') })
$InfoIssues = @($AllIssues | Where-Object { $_.severity -eq 'INFO' })

$BlockCount = $BlockIssues.Count
$WarnCount = $WarnIssues.Count
$InfoCount = $InfoIssues.Count
$TotalCount = $AllIssues.Count

Write-Info "Found $TotalCount total issues: $BlockCount BLOCK, $WarnCount WARN, $InfoCount INFO"
Write-Host ""

# Make commit decision based on BLOCK issues
if ($BlockCount -gt 0) {
    Write-Host ""
    Write-ColorOutput "========================================================" 'Red'
    Write-ColorOutput "  AI REVIEW: COMMIT BLOCKED                             " 'Red'
    Write-ColorOutput "========================================================" 'Red'
    Write-Host ""
    Write-Host "Found $BlockCount critical issue(s):"
    Write-Host ""
    
    # Display BLOCK issues
    $BlockIssues | ForEach-Object {
        $severity = $_.severity
        $file = $_.file
        $line = $_.line
        $message = $_.message
        Write-Host "  [$severity] ${file}:${line}" -ForegroundColor Red
        Write-Host "    $message"
        Write-Host ""
    }
    
    Write-ColorOutput "Fix these issues or use 'git commit --no-verify' to bypass." 'Yellow'
    Write-Host "Review details saved to: $LAST_REVIEW_FILE"
    Write-Host ""
    exit 1
}

# Show warnings and info
if ($WarnCount -gt 0 -or $InfoCount -gt 0) {
    Write-Host ""
    Write-Warning "Found $WarnCount warning(s) and $InfoCount info message(s):"
    Write-Host ""
    if ($WarnCount -gt 0) {
        $WarnIssues | Select-Object -First 5 | ForEach-Object {
            Write-Host "  [$($_.severity)] $($_.file):$($_.line)" -ForegroundColor Yellow
            Write-Host "    $($_.message)"
        }
    }
    if ($InfoCount -gt 0) {
        $InfoIssues | Select-Object -First 5 | ForEach-Object {
            Write-Host "  [$($_.severity)] $($_.file):$($_.line)"
            Write-Host "    $($_.message)"
        }
    }
    if (($WarnCount + $InfoCount) -gt 10) {
        Write-Host "  ... and more (see $LAST_REVIEW_FILE for details)"
    }
}

Write-Host ""
Write-Success "Review complete. Allowing commit."
Write-Host "Review details saved to: $LAST_REVIEW_FILE"
Write-Host ""
exit 0

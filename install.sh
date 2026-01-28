#!/bin/sh
# Installation script for Java AI Code Review pre-commit hook
# This script sets up the pre-commit hook and verifies dependencies

set -e

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo "${BLUE}  Java AI Code Review - Installation${NC}"
echo "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check if we're in a git repository
if [ ! -d ".git" ]; then
  echo "${RED}Error: Not a git repository. Please run this script from the root of your git project.${NC}"
  exit 1
fi

# Check if pre-commit.sh exists
if [ ! -f "pre-commit.sh" ]; then
  echo "${RED}Error: pre-commit.sh not found in current directory.${NC}"
  echo "Please ensure you're running this script from the project root."
  exit 1
fi

echo "${BLUE}[1/5]${NC} Checking dependencies..."
echo ""

# Check for gh CLI
if ! command -v gh >/dev/null 2>&1; then
  echo "${RED}✗ GitHub CLI (gh) not found${NC}"
  echo ""
  echo "Please install GitHub CLI:"
  echo "  - Windows: winget install --id GitHub.cli"
  echo "  - macOS:   brew install gh"
  echo "  - Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
  echo ""
  exit 1
else
  echo "${GREEN}✓ GitHub CLI (gh) found${NC}"
fi

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo "${RED}✗ jq not found${NC}"
  echo ""
  echo "Please install jq:"
  echo "  - Windows: winget install jqlang.jq"
  echo "  - macOS:   brew install jq"
  echo "  - Linux:   apt install jq (or equivalent)"
  echo ""
  exit 1
else
  echo "${GREEN}✓ jq found${NC}"
fi

# Check for gh copilot extension
if ! gh extension list | grep -q "github/gh-copilot"; then
  echo "${YELLOW}⚠ GitHub Copilot CLI extension not installed${NC}"
  echo ""
  echo "Would you like to install it now? (y/n)"
  read -r response
  if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
    echo ""
    echo "Installing GitHub Copilot CLI extension..."
    if gh extension install github/gh-copilot; then
      echo "${GREEN}✓ GitHub Copilot CLI extension installed${NC}"
    else
      echo "${RED}✗ Failed to install GitHub Copilot CLI extension${NC}"
      echo "Please install manually: gh extension install github/gh-copilot"
      exit 1
    fi
  else
    echo "${YELLOW}Skipping Copilot installation. You'll need to install it later.${NC}"
    echo "Run: gh extension install github/gh-copilot"
  fi
else
  echo "${GREEN}✓ GitHub Copilot CLI extension found${NC}"
fi

echo ""
echo "${BLUE}[2/5]${NC} Checking required files..."
echo ""

# Check for .ai directory
if [ ! -d ".ai" ]; then
  echo "${YELLOW}⚠ .ai directory not found, creating it...${NC}"
  mkdir -p .ai
fi

# Check for checklist file
if [ ! -f ".ai/java_code_review_checklist.yaml" ]; then
  echo "${RED}✗ .ai/java_code_review_checklist.yaml not found${NC}"
  echo "This file is required. Please ensure it exists."
  exit 1
else
  echo "${GREEN}✓ Checklist file found${NC}"
fi

# Check for prompt file
if [ ! -f ".ai/java_review_prompt.txt" ]; then
  echo "${RED}✗ .ai/java_review_prompt.txt not found${NC}"
  echo "This file is required. Please ensure it exists."
  exit 1
else
  echo "${GREEN}✓ Prompt file found${NC}"
fi

echo ""
echo "${BLUE}[3/5]${NC} Installing pre-commit hook..."
echo ""

# Create hooks directory if it doesn't exist
mkdir -p .git/hooks

# Copy the pre-commit script
if cp pre-commit.sh .git/hooks/pre-commit; then
  echo "${GREEN}✓ Pre-commit hook copied to .git/hooks/pre-commit${NC}"
else
  echo "${RED}✗ Failed to copy pre-commit hook${NC}"
  exit 1
fi

echo ""
echo "${BLUE}[4/5]${NC} Making hook executable..."
echo ""

# Make the hook executable
if chmod +x .git/hooks/pre-commit; then
  echo "${GREEN}✓ Pre-commit hook is now executable${NC}"
else
  echo "${YELLOW}⚠ Could not set executable permission. You may need to run:${NC}"
  echo "  chmod +x .git/hooks/pre-commit"
fi

echo ""
echo "${BLUE}[5/5]${NC} Verifying installation..."
echo ""

# Test if the hook can be executed
if [ -x ".git/hooks/pre-commit" ]; then
  echo "${GREEN}✓ Pre-commit hook is properly installed and executable${NC}"
else
  echo "${YELLOW}⚠ Pre-commit hook may not be executable${NC}"
  echo "Please run: chmod +x .git/hooks/pre-commit"
fi

echo ""
echo "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo "${GREEN}  Installation Complete!${NC}"
echo "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo "  1. Ensure you're authenticated with GitHub:"
echo "     ${BLUE}gh auth login${NC}"
echo ""
echo "  2. Stage some Java files and try a commit:"
echo "     ${BLUE}git add YourFile.java${NC}"
echo "     ${BLUE}git commit -m \"Test commit\"${NC}"
echo ""
echo "  3. The AI review will run automatically!"
echo ""
echo "Tips:"
echo "  - To disable AI review temporarily:"
echo "    ${BLUE}git commit --no-verify${NC}"
echo ""
echo "  - To disable AI review permanently:"
echo "    ${BLUE}export AI_REVIEW_ENABLED=false${NC}"
echo ""
echo "  - Review results are saved to:"
echo "    ${BLUE}.ai/last_review.json${NC}"
echo ""

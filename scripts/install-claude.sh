#!/usr/bin/env bash
# Installs the edge-ai-robotics-automation-toolkit Claude agents and skills
# into ~/.claude/. This toolkit is a SUPPLEMENT to ai-toolkit — install
# ai-toolkit first for the shared global standards, hooks, and harness config.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${HOME}/.claude"

echo "Installing edge-AI/robotics/automation Claude agents and skills from: ${REPO_ROOT}"

mkdir -p "${CLAUDE_DIR}/agents"
mkdir -p "${CLAUDE_DIR}/skills"

find "${REPO_ROOT}/claude/agents" -name "*.md" -exec cp -v {} "${CLAUDE_DIR}/agents/" \;
cp -rv "${REPO_ROOT}/skills/"* "${CLAUDE_DIR}/skills/"

echo "Done."
echo "  Agents → ${CLAUDE_DIR}/agents/"
echo "  Skills → ${CLAUDE_DIR}/skills/"
echo ""
echo "Global config (CLAUDE.md, settings.json, statusline) ships with ai-toolkit."
echo "This supplement does not overwrite it. Install ai-toolkit first if you have not."

#!/usr/bin/env bash
# Installs the edge-ai-robotics-automation-toolkit OpenCode agents and skills
# into ~/.config/opencode/. This toolkit is a SUPPLEMENT to ai-toolkit — install
# ai-toolkit first for the shared global standards and harness config.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENCODE_DIR="${HOME}/.config/opencode"

echo "Installing edge-AI/robotics/automation OpenCode agents and skills from: ${REPO_ROOT}"

mkdir -p "${OPENCODE_DIR}/agents"
mkdir -p "${OPENCODE_DIR}/skills"

find "${REPO_ROOT}/opencode/agents" -name "*.md" -exec cp -v {} "${OPENCODE_DIR}/agents/" \;
cp -rv "${REPO_ROOT}/skills/"* "${OPENCODE_DIR}/skills/"

echo "Done."
echo "  Agents → ${OPENCODE_DIR}/agents/"
echo "  Skills → ${OPENCODE_DIR}/skills/"
echo ""
echo "Global config (AGENTS.md, opencode.json) ships with ai-toolkit."
echo "This supplement does not overwrite it. Install ai-toolkit first if you have not."

#!/usr/bin/env bash
# Installs the edge-ai-robotics-automation-toolkit skills into Pi (~/.pi/agent/skills/).
# This toolkit is a SUPPLEMENT to ai-toolkit — install ai-toolkit's Pi global config
# (AGENTS.md, models.json, Modelfiles) first via its scripts/install-pi.sh.
#
# Skills use the identical Agent Skills format across Claude Code, OpenCode, and Pi,
# so the single skills/ tree is the source of truth. See pi/SKILLS-local.md for which
# skills are suited to local inference vs. cloud.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_DIR="${HOME}/.pi/agent"

echo "Installing edge-AI/robotics/automation skills into Pi from: ${REPO_ROOT}"

mkdir -p "${PI_DIR}/skills"
cp -rv "${REPO_ROOT}/skills/"* "${PI_DIR}/skills/"

if command -v grounded-code-mcp >/dev/null 2>&1; then
  GROUNDED_STATUS="found on PATH"
else
  GROUNDED_STATUS="NOT FOUND — grounded skills (📚) fall back to training data"
fi

echo ""
echo "Done."
echo "  Skills → ${PI_DIR}/skills/"
echo "  grounded-code-mcp CLI → ${GROUNDED_STATUS}"
echo ""
echo "Pi global config (AGENTS.md, models.json, Modelfiles) ships with ai-toolkit —"
echo "install it first with ai-toolkit/scripts/install-pi.sh. See pi/SKILLS-local.md"
echo "for the local-inference triage of these edge-AI/robotics skills."

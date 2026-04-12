#!/usr/bin/env bash
set -euo pipefail

ECOSYSTEM_ROOT="/home/osboxes/.openclaw/workspace/zoul/ecosystem"
WORKSPACE="/home/osboxes/.openclaw/workspace/zoul"

echo "=== ChonSong Ecosystem Integration ==="

# 1. Verify all repos exist
echo "[1/9] Verifying repo structure..."
for repo in claw-aie agent-interaction-evaluator-repo repo-transmute; do
    if [ ! -d "$WORKSPACE/$repo" ]; then
        echo "ERROR: $repo not found at $WORKSPACE/$repo"
        exit 1
    fi
    echo "  ✓ $repo"
done

# 2. Verify ClawTeam Python package installed
echo "[2/9] Verifying ClawTeam Python package..."
if python3 -c "import clawteam; print(clawteam.__file__)" 2>/dev/null; then
    echo "  ✓ clawteam Python package installed"
else
    echo "  ✗ clawteam Python package NOT installed"
    exit 1
fi

# 3. Verify Python paths
echo "[3/9] Verifying Python environments..."
for module in claw_aie evaluator repo_transmute; do
    python3 -c "import $module" 2>/dev/null && echo "  ✓ $module installed" || echo "  ✗ $module NOT installed (expected — use PYTHONPATH)"
done

# 4. Check AIE logger socket path
echo "[4/9] Checking AIE logger socket..."
if [ -S /tmp/ailogger.sock ]; then
    echo "  ✓ /tmp/ailogger.sock exists"
else
    echo "  ✗ /tmp/ailogger.sock not found — run 'ailogger serve' first"
fi

# 5. Verify txtai index location (shared with RepoTransmute)
echo "[5/9] Checking txtai index..."
TXTai_PATH="$WORKSPACE/repo-transmute/data/txtai"
if [ -d "$TXTai_PATH" ]; then
    echo "  ✓ txtai index at $TXTai_PATH"
else
    echo "  ✗ txtai index not initialized — run RepoTransmute ingest first"
fi

# 6. Verify claw-aie aie_integration structure
echo "[6/9] Checking claw-aie integration layer..."
for file in aie_integration/__init__.py aie_integration/tool_executor.py aie_integration/hooks/runner.py aie_integration/hooks/base.py aie_integration/hooks/aie_emitter.py aie_integration/sanitiser.py; do
    if [ ! -f "$WORKSPACE/claw-aie/$file" ]; then
        echo "  ✗ MISSING: $file"
    else
        echo "  ✓ $file"
    fi
done

# 7. Verify AIE source structure (in agent-interaction-evaluator-repo/)
echo "[7/9] Checking AIE evaluator structure..."
AIE_SRC="$WORKSPACE/agent-interaction-evaluator-repo/src/evaluator"
for file in schema.py logger.py logger_client.py db.py sanitiser.py oracle_engine.py audit.py aieval.py drift.py txtai_client.py; do
    if [ ! -f "$AIE_SRC/$file" ]; then
        echo "  ✗ MISSING: $file"
    else
        SIZE=$(stat -c%s "$AIE_SRC/$file" 2>/dev/null || echo "0")
        echo "  ✓ $file (${SIZE} bytes)"
    fi
done

# 8. Check claw-aie hook runner completeness
echo "[8/9] Checking hook runner completeness..."
HOOK_RUNNER="$WORKSPACE/claw-aie/aie_integration/hooks/runner.py"
HOOK_SIZE=$(stat -c%s "$HOOK_RUNNER" 2>/dev/null || echo "0")
if [ "$HOOK_SIZE" -lt 500 ]; then
    echo "  ✗ runner.py is a stub (${HOOK_SIZE} bytes) — Phase B incomplete"
else
    echo "  ✓ runner.py looks complete (${HOOK_SIZE} bytes)"
fi

# 9. Verify ClawTeam data directory structure
echo "[9/9] Checking ClawTeam data directory..."
CLAWTEAM_DATA="$HOME/.clawteam/data/tasks"
if [ -d "$CLAWTEAM_DATA" ]; then
    echo "  ✓ ClawTeam data directory exists at $CLAWTEAM_DATA"
    TEAM_COUNT=$(find "$CLAWTEAM_DATA" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    echo "  ✓ $((TEAM_COUNT - 1)) team(s) found"
else
    echo "  ⚠ ClawTeam data directory not yet created (normal for fresh install)"
fi

echo ""
echo "=== Integration check complete ==="
echo ""
echo "To start the full pipeline:"
echo "  1. cd $WORKSPACE/agent-interaction-evaluator-repo"
echo "     PYTHONPATH=src python3 -m evaluator.logger serve &"
echo "  2. cd $WORKSPACE/claw-aie"
echo "     PYTHONPATH=src:. claw-aie run --session <id>"
echo "  3. cd $WORKSPACE/agent-interaction-evaluator-repo"
echo "     PYTHONPATH=src python3 -m evaluator.drift scan"
echo ""
echo "To install ClawTeam sidecar:"
echo "  cd $WORKSPACE/claw-aie"
echo "  PYTHONPATH=src python3 -c \"from sidecar import install_sidecar; install_sidecar()\""
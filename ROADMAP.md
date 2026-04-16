# Ecosystem Roadmap — ChonSong Ecosystem

**Date:** 2026-04-11
**Author:** Architect Agent (Orchestrated by Principal Architect)
**Status:** Active — last updated 2026-04-17

---

## Executive Summary

Phase 3 builds on the simplification sprint (2026-04-08) which reduced the ecosystem to 4 layers. The focus now is **integration completeness and observability**: wiring the layers together so events flow end-to-end, implementing the ClawTeam sidecar for task store wrapping, completing the claw-aie Phases B-D harness, adding NLI-based drift detection, and planning the frontend strategy.

**Phase 3 Deliverables:**
1. Submodule integration script — wire claw-aie, AIE, RepoTransmute, ClawTeam into a single operational pipeline
2. ClawTeam sidecar — `TaskStore.update()` wrapping for task event emission
3. claw-aie Phases B-D completion — working hook system + AIE integration + CLI
4. Phase 7 NLI drift detection — `cross-encoder/nli-deberta-v3-small` integration into the oracle engine
5. Frontend strategy — AIE Observability Dashboard scope and tech stack

**Ecosystem State (as of 2026-04-11):**

| Layer | Repo | Status |
|---|---|---|
| L1 | ClawTeam (Python pip package `clawteam`) | ✅ Operational Python package — imported by OpenClaw's FastAPI routes |
| L2 | claw-aie (ChonSong/claw-aie) | Phase A done; B, C, D incomplete |
| L3 | agent-interaction-evaluator (ChonSong/agent-interaction-evaluator) | Phases 1-4 partially exist (not tested together); 5-6 missing |
| L4 | repo-transmute (ChonSong/repo-transmute) | Operational — active development |

---

## Step 1: Submodule Integration Plan

### 1.1 Integration Topology

```
OpenClaw (orchestrator)
    │
    ├── ClawTeam Python package → installed via pip
    │   └── clawteam.team.tasks.TaskStore.update() ──► AILoggerClient.emit()
    │
    ├── claw-aie → workspace/zoul/claw-aie/
    │   ├── ToolExecutor (Phase A: done)
    │   ├── HookRunner (Phase B: incomplete)
    │   ├── AIEEventEmitter (Phase C: incomplete)
    │   └── CLI (Phase D: missing)
    │       │
    │       └──► /tmp/ailogger.sock
    │
    ├── agent-interaction-evaluator → workspace/zoul/agent-interaction-evaluator-repo/
    │   ├── ailogger (Phase 1: partial — not tested end-to-end)
    │   ├── aidrift (Phase 2: partial — not tested end-to-end)
    │   ├── aieval (Phase 3: ⚠ exists but not tested)
    │   ├── aiaudit (Phase 4: ⚠ exists but not tested)
    │   ├── cron scripts (Phase 5: missing — scripts/ dir empty)
    │   └── agent integration (Phase 6: missing)
    │       │
    │       └──► txtai at ~/workspace/zoul/repo-transmute/data/txtai/
    │
    └── repo-transmute → workspace/zoul/repo-transmute/
        └── txtai/ (shared FAISS index, two collections: blueprints + agent_events)
```

### 1.2 Integration Bash Script

Saved as `ecosystem/integrate.sh` (make executable with `chmod +x`).

**Correct paths verified by the script:**
- claw-aie: `workspace/zoul/claw-aie/`
- AIE: `workspace/zoul/agent-interaction-evaluator-repo/`
- RepoTransmute: `workspace/zoul/repo-transmute/`
- ClawTeam Python: verified via `python3 -c "import clawteam; print(clawteam.__file__)"`

**Key verification checks:**
1. All 3 workspace repos exist
2. ClawTeam Python package installed and importable
3. Python modules importable (with PYTHONPATH guidance)
4. `/tmp/ailogger.sock` status
5. txtai index location and health
6. All claw-aie aie_integration files present
7. All AIE source files present (including `oracle_engine.py` at 33KB, `audit.py` at 21KB, `aieval.py` at 10KB)
8. Hook runner completeness check
9. ClawTeam data directory (`~/.clawteam/data/tasks/`)

---

## Step 2: ClawTeam Sidecar Implementation

### 2.1 What Is the Sidecar

The ClawTeam sidecar wraps `clawteam.team.tasks.TaskStore.update()` to emit `delegation` and `task_update` events to AIE whenever a task is created, updated, or assigned. This makes ClawTeam observable without modifying its core logic.

### 2.2 Integration Point

**Class:** `clawteam.team.tasks.TaskStore` (Python package, installed via pip)
**Method:** `TaskStore.update(self, task_item: TaskItem, owner: str | None) -> TaskItem`
**Signature:** Synchronous (not async) — takes `owner: str | None` parameter
**Data directory:** `~/.clawteam/data/tasks/{team_name}/task-{task_id}.json`

OpenClaw's FastAPI routes (`workspace/openclaw/src/api/routes/tasks.py`) import `TaskStore` from `clawteam.team.tasks` and call it via `_get_store()`. The sidecar patches `TaskStore.update` at module level before OpenClaw's routes load.

### 2.3 Why Monkey-Patching Is Correct

1. `TaskStore.update()` is synchronous — no async complications
2. `OpenClaw's tasks.py` imports `TaskStore` from `clawteam.team.tasks` — patching the class at module level means all instances get the patched version
3. Patch is applied at import time, not runtime
4. Fire-and-forget: AIE emission failures never affect task processing
5. `TaskStore` has no `__wrapped__` attribute initially — safe to patch

### 2.4 Files to Create/Modify

**Existing file:** `workspace/zoul/clawteam-sidecar/src/sidecar/watcher.py`

```python
"""
ClawTeam Sidecar — wraps clawteam.team.tasks.TaskStore.update() to emit AIE events.

Usage:
    from sidecar import install_sidecar
    install_sidecar(ailogger_socket_path="/tmp/ailogger.sock")

Must be called before OpenClaw's FastAPI routes import TaskStore.
"""

import functools
import json
import os
import sys
import threading
from pathlib import Path
from typing import Optional

# Add claw-aie to path for AILoggerClient import
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

try:
    from evaluator.logger_client import AILoggerClient
except ImportError:
    AILoggerClient = None  # Sidecar runs independently of claw-aie


def wrap_TaskStore_update(original_update):
    """Decorator to wrap TaskStore.update() with AIE emission."""
    @functools.wraps(original_update)
    def wrapped(self, task_item, owner: Optional[str] = None):
        # Call original (synchronous)
        result = original_update(self, task_item, owner)

        # Emit event in background thread — never blocks task processing
        thread = threading.Thread(
            target=_emit_task_event,
            args=(self, task_item, result, owner),
            daemon=True,
        )
        thread.start()

        return result
    return wrapped


def _emit_task_event(store_self, task_item, result, owner: Optional[str]):
    """Emit delegation or task_update event to AIE."""
    try:
        client = AILoggerClient(
            socket_path=os.environ.get("AILOGGER_SOCKET", "/tmp/ailogger.sock")
        )

        # Determine event type: delegation if owner changed, else task_update
        prior_owner = getattr(store_self, '_prior_owner', None)
        is_delegation = (
            owner is not None
            and prior_owner is not None
            and owner != prior_owner
        )

        if is_delegation:
            event_type = "delegation"
        else:
            event_type = "task_update"

        event = {
            "schema_version": "1.0",
            "event_id": f"ct-{os.urandom(8).hex()}",
            "event_type": event_type,
            "timestamp": Path(__file__).stat().st_mtime,  # approximation
            "agent_id": getattr(store_self, 'agent_id', 'clawteam'),
            "session_id": getattr(store_self, 'session_id', 'unknown'),
            "interaction_context": {
                "channel": "clawteam",
                "workspace_path": os.getcwd(),
                "parent_event_id": None,
            },
            "delegator": {"agent_id": "clawteam", "role": "orchestrator"},
            "delegate": {"agent_id": owner or "self", "role": "worker"},
            "task": {
                "task_id": result.id if hasattr(result, 'id') else str(result),
                "description": result.subject if hasattr(result, 'subject') else "",
                "intent": "",
                "constraints": [],
                "context_summary": f"owner={owner} status={getattr(result, 'status', 'unknown')}",
                "context_fidelity": 0.8,
            },
            "oracle_ref": None,
        }

        client.emit(event)

        # Update prior owner for next call
        store_self._prior_owner = owner
    except Exception as e:
        # Never let AIE emission failures affect task processing
        print(f"[clawteam_sidecar] AIE emission failed: {e}", file=sys.stderr)


def install_sidecar(ailogger_socket_path: str = "/tmp/ailogger.sock"):
    """
    Install the ClawTeam sidecar by monkey-patching TaskStore.update.

    Must be called before OpenClaw's FastAPI routes load.

    This patches clawteam.team.tasks.TaskStore.update to emit AIE events
    on every task create/update without modifying OpenClaw's code.
    """
    try:
        import clawteam.team.tasks
        TaskStore = clawteam.team.tasks.TaskStore
    except ImportError:
        print("[clawteam_sidecar] Could not import clawteam — sidecar not installed")
        return

    if hasattr(TaskStore.update, '__wrapped__'):
        # Already patched
        return

    TaskStore.update = wrap_TaskStore_update(TaskStore.update)
    os.environ["AILOGGER_SOCKET"] = ailogger_socket_path
    print(f"[clawteam_sidecar] Installed — emitting to {ailogger_socket_path}")
```

**Existing file:** `workspace/zoul/clawteam-sidecar/src/sidecar/events.py`

```python
from .clawteam_sidecar import install_sidecar

__all__ = ["install_sidecar"]
```

### 2.5 Event Types Emitted

| Trigger | Event Type | Fields |
|---|---|---|
| `TaskStore.update()` with new owner | `delegation` | `delegator`, `delegate`, `task` from `TaskItem` |
| `TaskStore.update()` with no owner change | `task_update` | Full task item snapshot |

**TaskItem fields available from `clawteam.team.tasks.TaskItem`:**
- `id`, `subject`, `owner`, `status`, `caller` (agent making change)
- `priority`, `blocked_by`, `metadata`

---

## Step 3: claw-aie Phases B-D — Detailed Deliverables

### Phase A Status: ✅ Complete (per SPEC.md)

`tool_executor.py` with 4 tools (bash, file_read, file_write, glob); `sanitiser.py` done; `hooks/base.py` stub exists.

### Phase B: Hook System

**Status:** Runner stub exists (1459 bytes), base stub exists (705 bytes). Not functional.

**Deliverables:**

| # | Item | File | Description |
|---|---|---|---|
| B1 | `ToolHook` ABC | `aie_integration/hooks/base.py` | Abstract base with `pre_tool_use()` and `post_tool_use()` methods. Currently 705 bytes stub. |
| B2 | `HookRunner` class | `aie_integration/hooks/runner.py` | Executes all registered hooks in sequence. Pre hooks run before tool; any denial blocks. Post hooks run after tool (cannot block). Currently 1459 bytes stub. |
| B3 | `permission_hook.py` | `aie_integration/hooks/permission_hook.py` | Blocks destructive tools: `bash` with `rm -rf`, `file_write` to system paths. Configurable allowlist. |
| B4 | `rate_limit_hook.py` | `aie_integration/hooks/rate_limit_hook.py` | Per-tool rate limiting using in-memory token bucket. Configurable via `hooks.yaml`. |
| B5 | `hooks.yaml` loader | `aie_integration/config.py` | Loads and parses `~/.claw-aie/hooks.yaml`. Returns list of configured hooks with their settings. |
| B6 | Hook tests | `tests/test_hooks.py` | Unit tests for HookRunner: sequential execution, early denial on pre_hook failure, post_hook always runs regardless of tool outcome. |

**Dependencies:** Phase A (already complete).

**Verification:**
```bash
cd /home/osboxes/.openclaw/workspace/zoul/claw-aie
PYTHONPATH=src:. python3 -m pytest tests/test_hooks.py -x -q
```

---

### Phase C: AIE Integration

**Status:** `aie_emitter.py` exists (3524 bytes) but likely stub-level. Connection to `ailogger.sock` not tested.

**Deliverables:**

| # | Item | File | Description |
|---|---|---|---|
| C1 | `AIEEventEmitter` hook | `aie_integration/hooks/aie_emitter.py` | Implements `ToolHook`. On `pre_tool_use`: emits `tool_call` event with `status=pending`. On `post_tool_use`: emits `tool_call` event with actual status (success/error). Uses `AILoggerClient` from `evaluator.logger_client`. |
| C2 | Session ID propagation | `aie_integration/session.py` | New module that holds current session context. `ToolExecutor` receives `session_id` and passes it to `AIEEventEmitter`. |
| C3 | `hooks.yaml` registration | `aie_integration/config.py` (update) | Ensure `aie_emitter` hook is registered by default when `emit_to_aie: true`. |
| C4 | Integration test | `tests/test_aie_emitter.py` | End-to-end test: emit a tool call, verify it arrives at `ailogger.sock`. Requires `ailogger serve` running. |
| C5 | Event schema compliance | `aie_integration/hooks/aie_emitter.py` (update) | Ensure emitted events match `agent-interaction-evaluator-repo/SPEC.md §3` schema exactly. Run `aieval oracle validate` after implementation. |

**Dependencies:** Phase B complete, `ailogger serve` running.

**Verification:**
```bash
# Terminal 1: start AIE logger
cd /home/osboxes/.openclaw/workspace/zoul/agent-interaction-evaluator-repo
PYTHONPATH=src python3 -m evaluator.logger serve &
sleep 2

# Terminal 2: run integration test
cd /home/osboxes/.openclaw/workspace/zoul/claw-aie
AILOGGER_SOCKET=/tmp/ailogger.sock PYTHONPATH=src:. python3 -m pytest tests/test_aie_emitter.py -x -q

# Verify event in AIE
cd /home/osboxes/.openclaw/workspace/zoul/agent-interaction-evaluator-repo
PYTHONPATH=src python3 -m evaluator.drift stats
```

---

### Phase D: CLI + Invocation

**Status:** Completely missing. No `claw-aie` CLI entry point.

**Deliverables:**

| # | Item | File | Description |
|---|---|---|---|
| D1 | CLI entry point | `aie_integration/cli.py` | `claw-aie` command with subcommands: `run`, `tool`, `hooks`, `status`. Uses argparse. |
| D2 | `run` subcommand | `aie_integration/cli.py` | Run the agent harness with tool execution + hooks + AIE emission. Takes `--session`, `--agent-id`, `--workspace` args. Wires `PortRuntime` → `ToolExecutor` → `HookRunner` → `AIEEventEmitter`. |
| D3 | `tool` subcommand | `aie_integration/cli.py` | Direct tool execution: `claw-aie tool bash --command "ls -la"`. Bypasses agent, runs tool directly. Useful for testing. |
| D4 | `hooks` subcommand | `aie_integration/cli.py` | Manage hooks: `claw-aie hooks list`, `claw-aie hooks validate`. Validates `hooks.yaml` and prints hook chain. |
| D5 | `status` subcommand | `aie_integration/cli.py` | Show harness status: connected AIE logger, loaded hooks, session info. |
| D6 | `PortRuntime` wiring | `aie_integration/runtime.py` (new) | Adapter that connects claw-code's `PortRuntime` to our `ToolExecutor`. Translates `route_prompt()` calls into tool executions. |
| D7 | End-to-end test | `tests/test_e2e.py` | Full test: start `claw-aie run`, execute a bash command, verify `tool_call` event in AIE's txtai index, run `aidrift scan`, assert no errors. |
| D8 | `pyproject.toml` entry points | `pyproject.toml` | Add `claw-aie = "aie_integration.cli:main"` console script. |

**Dependencies:** Phases B and C complete.

**Verification:**
```bash
# Install and test
cd /home/osboxes/.openclaw/workspace/zoul/claw-aie
pip install -e .
claw-aie status
claw-aie hooks list
claw-aie tool bash --command "echo hello"
```

---

## Step 4: Phase 7 NLI Integration

### 4.1 Current Drift Detection Approach

Currently (Phase 2 of AIE), drift detection uses **txtai embedding similarity** only:

1. On each `assumption` event, embed `assumption.statement` with `sentence-transformers/all-MiniLM-L6-v2`
2. Query `agent_events` collection for prior assumptions with cosine similarity > 0.85
3. If `similarity >= 0.95` → `direct` contradiction
4. If `0.85 <= similarity < 0.95` → `semantic` contradiction
5. `implicit` contradiction type is noted as future work (requires NLI model)

### 4.2 What cross-encoder/nli-deberta-v3-small Adds

The `cross-encoder/nli-deberta-v3-small` model (from HuggingFace) performs **Natural Language Inference**: given a premise and hypothesis, it classifies the relationship as:
- **Entailment** — premise supports hypothesis
- **Contradiction** — premise contradicts hypothesis
- **Neutral** — premise neither supports nor contradicts hypothesis

For drift detection, this means:
- Instead of comparing embedding similarity of assumption statements, we compare the **logical relationship** between them
- Two statements with different words but contradictory meaning would be caught (e.g., "file exists at /tmp/test" vs "no file exists at /tmp/test")
- This fills the gap between `semantic` (surface similarity) and `implicit` (logical incompatibility)

### 4.3 Implementation Approach

**Decision: LAZY loading** — model loaded on first use, not at startup. Rationale: ~400MB model should not delay service startup. If NLI is rarely needed, startup cost is wasted. First-use loading keeps startup fast.

**New file:** `agent-interaction-evaluator-repo/src/evaluator/nli_drift.py`

```python
"""
NLI-based drift detection using cross-encoder/nli-deberta-v3-small.

Adds implicit contradiction detection to the oracle engine.
Lazily loaded — not loaded until first use.
"""

import os
import warnings
from dataclasses import dataclass
from typing import Literal, Optional

import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification

from .drift import DriftResult

@dataclass
class NLIDriftResult:
    """NLI-based drift result with full entailment/contradiction analysis."""
    current_event_id: str
    prior_event_id: str
    current_statement: str
    prior_statement: str
    nli_label: Literal["entailment", "contradiction", "neutral"]
    nli_score: float
    drift_score: float
    contradiction_type: Literal["implicit"] = "implicit"
    model_used: str = "cross-encoder/nli-deberta-v3-small"


class NLIDriftDetector:
    """
    Uses cross-encoder NLI to detect implicit contradictions.

    Lazily loaded — model is not loaded until first use.
    Set USE_NLI=true env var to enable. On first check, model is downloaded
    (~400MB) and cached in ~/.cache/huggingface/.
    """

    _instance: Optional["NLIDriftDetector"] = None
    _loaded: bool = False

    def __init__(self, model_name: str = "cross-encoder/nli-deberta-v3-small"):
        self.model_name = model_name
        self.tokenizer = None
        self.model = None

    @classmethod
    def get_instance(cls) -> "NLIDriftDetector":
        """Get or create singleton instance. Lazy loads model on first call."""
        if cls._instance is None:
            cls._instance = cls()
        if not cls._loaded:
            cls._instance._load_model()
            cls._loaded = True
        return cls._instance

    def _load_model(self):
        """Load the NLI model. Called lazily on first use."""
        model_name = self.model_name
        try:
            self.tokenizer = AutoTokenizer.from_pretrained(model_name)
            self.model = AutoModelForSequenceClassification.from_pretrained(model_name)
            self.model.eval()
        except Exception as e:
            warnings.warn(f"Failed to load NLI model {model_name}: {e}")
            raise

    def check_implicit_drift(
        self, current_statement: str, prior_statement: str
    ) -> Optional[NLIDriftResult]:
        """
        Check for implicit contradiction between two statements.

        Returns NLIDriftResult if contradiction detected (label = 'contradiction'),
        None otherwise.
        """
        if self.model is None:
            return None

        inputs = self.tokenizer(
            prior_statement,
            current_statement,
            return_tensors="pt",
            padding=True,
            truncation=True,
            max_length=512,
        )

        with torch.no_grad():
            outputs = self.model(**inputs)
            probs = torch.softmax(outputs.logits, dim=1)
            predicted_class = probs.argmax().item()
            confidence = probs[0][predicted_class].item()

        label_map = {0: "entailment", 1: "neutral", 2: "contradiction"}
        nli_label = label_map[predicted_class]

        # Only flag as drift if contradiction detected with high confidence
        if nli_label == "contradiction" and confidence >= 0.7:
            drift_score = 0.7 + (confidence * 0.2)  # 0.7-0.9 range

            return NLIDriftResult(
                current_event_id="",
                prior_event_id="",
                current_statement=current_statement,
                prior_statement=prior_statement,
                nli_label=nli_label,
                nli_score=confidence,
                drift_score=min(drift_score, 0.95),
                contradiction_type="implicit",
                model_used=self.model_name,
            )

        return None

    def batch_check(
        self, current_statement: str, prior_statements: list[tuple[str, str]]
    ) -> list[NLIDriftResult]:
        """Check current statement against multiple prior statements."""
        results = []
        for prior_text, _ in prior_statements:
            result = self.check_implicit_drift(current_statement, prior_text)
            if result:
                results.append(result)
        return results
```

**Integration point:** `src/evaluator/drift.py` — add `NLIDriftDetector` as optional component.

```python
# In DriftDetector.__init__:
self.nli_detector = None
if os.environ.get("USE_NLI", "false").lower() == "true":
    try:
        self.nli_detector = NLIDriftDetector.get_instance()
    except Exception as e:
        warnings.warn(f"NLI detector unavailable: {e}")

# In DriftDetector.check():
# After existing similarity check, run NLI if available
if self.nli_detector:
    nli_result = self.nli_detector.check_implicit_drift(
        event["assumption"]["statement"],
        prior["assumption"]["statement"]
    )
    if nli_result:
        return DriftResult(
            event_id=event_id,
            contradicted_event_id=prior["event_id"],
            contradiction_type="implicit",
            drift_score=nli_result.drift_score,
            current_statement=event["assumption"]["statement"],
            prior_statement=prior["assumption"]["statement"],
        )
```

**Model pre-download (optional):**
```bash
python3 -c "from transformers import AutoTokenizer; AutoTokenizer.from_pretrained('cross-encoder/nli-deberta-v3-small')"
```

**Dependencies:**
- `torch>=2.0`
- `transformers>=4.30`
- ~400MB disk space for model

### 4.4 What Changes in the Oracle Engine

**New condition type:** `nli_contradiction`
```yaml
- type: "nli_contradiction"
  field: "assumption.statement"
  prior_context: "session"
  threshold: 0.7
```

**New oracle:** `oracles/assumption/implicit_contradiction_nli.yaml`
```yaml
oracle_id: "implicit_contradiction_nli"
name: "Implicit contradiction via NLI"
description: |
  Detects logical contradictions between current assumption and
  prior assumptions not caught by embedding similarity.
  Uses cross-encoder/nli-deberta-v3-small for NLI classification.
  Lazy-loaded — enable with USE_NLI=true env var.
event_type: "assumption"
trigger: "on_event"
severity: "critical"
conditions:
  - type: "nli_contradiction"
    field: "assumption.statement"
    prior_context: "session"
    threshold: 0.7
actions:
  - type: "flag"
    output: "drift_event"
  - type: "alert"
    output: "discord"
    channel: "evaluator-alerts"
```

---

## Step 5: Frontend Strategy

### 5.1 Purpose of the AIE Observability Dashboard

The AIE Observability Dashboard gives humans a read-only view into the agent ecosystem's health:
- Session-level event timelines
- Drift detection results and severity
- Oracle evaluation pass/fail rates
- Circuit breaker alert history
- Cross-agent interaction patterns

### 5.2 Backend Milestone Gate

**The frontend cannot be built until these backend milestones are met:**

| Milestone | Description | Gate Criterion |
|---|---|---|
| M1 | `ailogger serve` accepts events | `ailogger status` returns `{"events_received": N}` |
| M2 | `aidrift scan` returns structured results | JSON output with `drift_score`, `contradiction_type` per drift |
| M3 | `aieval oracle list` returns oracles with IDs and severities | Valid YAML list |
| M4 | `aiaudit trail <session_id>` returns complete audit trail | All decision nodes present |
| M5 | txtai index has real agent events | Query returns results, not empty |

**Verification script:** (included in `integrate.sh` step 4-5)

### 5.3 Tech Stack Recommendation

**Decision: Option A (Streamlit) for MVP.**

Rationale:
- Python-first: aligns with existing Python/SQLite/txtai backend
- No separate API server needed — Streamlit calls Python functions directly
- Fastest path to a working dashboard
- Team already has Python expertise
- Migrate to Option B (FastAPI+HTMX) only if production deployment is needed

Option B (FastAPI+HTMX) and Option C (React SPA) are documented but deferred.

### 5.4 Dashboard Scope

**Phase 1 MVP (Streamlit):**

| View | Shows |
|---|---|
| `SessionBrowser` | List of sessions, click to view timeline |
| `EventTimeline` | Chronological event list for a session with oracle results |
| `DriftDashboard` | All open drifts, severity, timestamps |
| `OracleStatus` | Pass/fail counts per oracle, last 24h |
| `CircuitBreakerLog` | Recent halts, reasons, actions taken |

**Data sources:**
- SQLite: session metadata, oracle_results, drift_log (at `agent-interaction-evaluator-repo/data/aie_meta.db`)
- txtai: full-text search on event content, assumption statements
- JSONL logs: raw event data for timeline reconstruction

**Files to create:**
```
workspace/zoul/agent-interaction-evaluator-repo/dashboard/
├── app.py                 # Streamlit entry point
├── pages/
│   ├── sessions.py       # Session browser
│   ├── drifts.py         # Drift dashboard
│   ├── oracles.py        # Oracle status
│   └── audit.py          # Audit trail viewer
├── components/
│   ├── event_timeline.py # Event timeline component
│   ├── drift_card.py    # Drift display card
│   └── oracle_badge.py   # Oracle pass/fail badge
└── requirements.txt      # streamlit, txtai, aiosqlite
```

---

## Timeline and Priorities

### Priority Order

```
Week 1:
  P0: Complete claw-aie Phase B (Hook System) — unblocks Phase C
  P0: Verify AIE logger functional (`ailogger serve` + emit test)
      ⚠ Critical gap: oracle_engine.py and audit.py exist but NOT tested together
        with ailogger. Phase 5 (cron scripts) is completely missing.

Week 2:
  P0: Complete claw-aie Phase C (AIE Integration) — unblocks Phase D
  P0: Complete claw-aie Phase D (CLI + Invocation) — makes harness operational
  P1: Submodule integration script (Step 1)

Week 3:
  P0: ClawTeam sidecar — enables ClawTeam → AIE event flow
  P1: Phase 7 NLI detector — deploy cross-encoder model (lazy loading)

Week 4:
  P2: Frontend strategy — Streamlit MVP planning
  P2: Frontend backend milestone verification script
```

### Critical Path

```
claw-aie Phase B → Phase C → Phase D
      ↓              ↓         ↓
  Hook system   AIE emission   CLI + wiring
                              ↓
                    ┌─────────┴──────────┐
                    ↓                     ↓
              ClawTeam sidecar      AIE fully wired
                    ↓                     ↓
              Events flow → AIE → txtai → Dashboard
```

---

## Open Questions — Resolved

| # | Question | Decision |
|---|---|---|
| OQ-A | Does `TaskStore.update()` exist and is it async? | **RESOLVED**: `TaskStore.update(task_item, owner: str | None)` is synchronous. Exists at `clawteam.team.tasks.TaskStore`. |
| OQ-B | Monkey-patch vs subclass? | **RESOLVED**: Use **monkey-patching at module level** — `clawteam.team.tasks.TaskStore.update = wrapped_update`. Safe because TaskStore has no `__wrapped__` initially, and it's synchronous. |
| OQ-C | Streamlit (A) vs FastAPI+HTMX (B) vs React (C)? | **RESOLVED**: Option A (Streamlit) for MVP — fastest path, aligns with Python/SQLite/txtai backend. |
| OQ-D | NLI model eager or lazy loading? | **RESOLVED**: **LAZY loading** — model downloaded and loaded on first use, not at startup. Keep startup fast. |
| OQ-E | AIE events into RepoTransmute blueprints collection? | **RESOLVED**: Low priority — skip for now. Keep separate collections (`blueprints` vs `agent_events`). |
| OQ-F | claw-aie as own git repo or workspace subdir? | **RESOLVED**: Keep as **workspace subdir** (`workspace/zoul/claw-aie/`). No need for own git repo at this stage. |

---

## Critical Finding: Phase Status Discrepancy

The simplification sprint declared AIE Phases 3-4 complete, but this is **partially inaccurate**:

**What exists:**
- `oracle_engine.py` ✅ EXISTS at `agent-interaction-evaluator-repo/src/evaluator/oracle_engine.py` (33KB — substantial)
- `audit.py` ✅ EXISTS at `agent-interaction-evaluator-repo/src/evaluator/audit.py` (21KB — substantial)
- `aieval.py` ✅ EXISTS at `agent-interaction-evaluator-repo/src/evaluator/aieval.py` (10KB)

**The real gap:**
These files exist as source but have **never been tested together with `ailogger serve`**. The end-to-end pipeline has not been validated. Specifically:
- Phase 5 (cron scripts): `scripts/` directory is **completely empty**
- Phase 6 (agent integration): No agent-specific code exists
- Phase 7 (NLI): Not started

**Corrected Phase Status:**

| Phase | Simplification Sprint | Actual State |
|---|---|---|
| Phase 1 (Foundation) | Partial | Partial — not tested end-to-end |
| Phase 2 (Indexing + Drift) | Partial | Partial — not tested end-to-end |
| Phase 3 (Oracle Engine) | "Complete" | ⚠ Source exists (33KB) but not tested with live logger |
| Phase 4 (Audit Trails) | "Complete" | ⚠ Source exists (21KB) but not tested with live logger |
| Phase 5 (Cron + Alerts) | Missing | ❌ `scripts/` directory empty — genuinely missing |
| Phase 6 (Agent Integration) | Missing | ❌ No agent-specific code |
| Phase 7 (NLI) | Missing | ❌ Not started |

**Action required:** Before Phase 3 of the roadmap can proceed, the AIE pipeline must be tested end-to-end to confirm `oracle_engine.py` and `audit.py` work with a live `ailogger serve`.

---

## Appendix: Repos Investigated

### claw-aie (ChonSong/claw-aie)

**Path:** `/home/osboxes/.openclaw/workspace/zoul/claw-aie/`

| Phase | Status | Notes |
|---|---|---|
| Phase A (Foundation) | ✅ Done | `tool_executor.py` with 4 tools (bash, file_read, file_write, glob); `sanitiser.py` done; `hooks/base.py` stub |
| Phase B (Hook System) | ❌ Incomplete | `hooks/runner.py` stub (1459 bytes); `hooks/base.py` stub (705 bytes); `permission_hook.py` missing; `rate_limit_hook.py` missing; `config.py` missing |
| Phase C (AIE Integration) | ❌ Incomplete | `hooks/aie_emitter.py` exists (3524 bytes) but stub-level; no integration tests |
| Phase D (CLI + Invocation) | ❌ Missing | No CLI entry point; no `PortRuntime` wiring; no `runtime.py` |

**Source structure:**
```
claw-aie/
├── src/                    # claw-code Python source (as-is fork)
├── aie_integration/        # Our additions
│   ├── __init__.py
│   ├── tool_executor.py    # ✅ Phase A complete
│   ├── sanitiser.py       # ✅ Phase A complete
│   ├── hooks/
│   │   ├── __init__.py
│   │   ├── base.py         # ❌ stub (705 bytes)
│   │   ├── runner.py      # ❌ stub (1459 bytes)
│   │   └── aie_emitter.py # ⚠ exists (3524 bytes) but stub-level
│   └── (config.py missing)
├── sidecar/                # NEW — ClawTeam sidecar (Step 2)
│   ├── __init__.py
│   └── clawteam_sidecar.py
├── tests/
├── SPEC.md                 # Phase A-D defined
├── README.md
└── requirements.txt
```

---

### agent-interaction-evaluator (ChonSong/agent-interaction-evaluator)

**Path:** `/home/osboxes/.openclaw/workspace/zoul/agent-interaction-evaluator-repo/`
**Own git repo:** Yes

| Phase | Status | Notes |
|---|---|---|
| Phase 1 (Foundation) | ⚠ Partial | Source exists — not tested end-to-end |
| Phase 2 (Indexing + Drift) | ⚠ Partial | Source exists — not tested end-to-end |
| Phase 3 (Oracle Engine) | ⚠ Partial | `oracle_engine.py` exists (33KB) — not tested with live logger |
| Phase 4 (Audit Trails) | ⚠ Partial | `audit.py` exists (21KB) — not tested with live logger |
| Phase 5 (Cron + Alerts) | ❌ Missing | `scripts/` dir empty — genuinely missing |
| Phase 6 (Agent Integration) | ❌ Missing | No agent-specific code |
| Phase 7 (NLI) | ❌ Not started | Not implemented |

**Source structure:**
```
agent-interaction-evaluator-repo/
├── src/evaluator/
│   ├── __init__.py
│   ├── schema.py           # ⚠ exists
│   ├── logger.py           # ⚠ exists (Phase 1)
│   ├── logger_client.py    # ⚠ exists (Phase 1)
│   ├── db.py               # ⚠ exists (Phase 1)
│   ├── sanitiser.py       # ⚠ exists (Phase 1)
│   ├── txtai_client.py     # ⚠ exists (Phase 2)
│   ├── drift.py            # ⚠ exists (Phase 2)
│   ├── oracle_engine.py    # ⚠ exists (33KB) — Phase 3, not tested
│   ├── aieval.py           # ⚠ exists (10KB) — Phase 3, not tested
│   ├── audit.py            # ⚠ exists (21KB) — Phase 4, not tested
│   └── nli_drift.py        # ❌ NOT YET CREATED — Phase 7
├── oracles/                # YAML oracle definitions
├── data/                   # aie_meta.db, logs/
│   └── aie_meta.db         # SQLite sidecar
├── scripts/                # ❌ EMPTY — Phase 5 missing
├── tests/
├── SPEC.md                 # Full spec
├── docs/archive/REQUIREMENTS.md
└── README.md
```

**AILoggerClient import path:** `from evaluator.logger_client import AILoggerClient` (from `agent-interaction-evaluator-repo/src/evaluator/logger_client.py`)

---

### repo-transmute (ChonSong/repo-transmute)

**Path:** `/home/osboxes/.openclaw/workspace/zoul/repo-transmute/`

| Phase | Status | Notes |
|---|---|---|
| Phase 1-4 | ✅ Operational | `cli.py`, `ingestion/`, `blueprint/`, `transpiler/`, `txtai/` all present and functional |
| Phase 5 (Dependency Resolution) | ⏳ Pending | |
| Phase 6 (TXTAI Semantic Layer) | ⏳ Pending | |
| Phase 7 (Frontend Unification) | ⏳ Pending | |

**Source structure:**
```
repo-transmute/src/repo_transmute/
├── cli.py                  # ✅ main entry point
├── ingestion/              # ✅ clone, detect, walk
├── blueprint/              # ✅ extractor, storage
├── transpiler/             # ✅ llm, prompts, validate
├── dependency/             # ⚠ present but partial
├── pipeline/               # ⚠ present
├── txtai/                  # ✅ client, indexer, search
└── frontend/               # ⚠ present
```

---

### ClawTeam (clawteam Python package)

**Type:** Python package installed via pip — NOT external TypeScript

**Key facts:**
- Package: `clawteam` (pip installable)
- Main class: `clawteam.team.tasks.TaskStore`
- Data directory: `~/.clawteam/data/tasks/{team_name}/task-{task_id}.json`
- `TaskStore.update(task_item, owner: str | None)` is synchronous
- Imported by OpenClaw's FastAPI routes at `workspace/openclaw/src/api/routes/tasks.py`
- Skill at `workspace/skills/clawteam/` is a placeholder ("Coming soon") — not the primary integration point

---

## Appendix: VS Code Workspace

A multi-root VS Code workspace file has been created at:

**`/home/osboxes/.openclaw/workspace/zoul/ecosystem/workspace.code-workspace`**

Includes:
- `ecosystem/` folder (this repo)
- `claw-aie` folder
- `agent-interaction-evaluator-repo` folder
- `repo-transmute` folder

Python extraPaths configured for all three source directories.

---

*Document status: FINAL — pending Principal Architect approval to proceed.*
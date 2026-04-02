# Simplification Sprint — Ecosystem Deduplication

**Date:** 2026-04-02
**Goal:** Define canonical ownership for all repos, eliminate duplication, write one unifying architecture doc.
**Blocking question:** None — this sprint can proceed based on current information.

---

## Current State Analysis

### Repos in the Ecosystem

| Repo | Purpose | Status |
|---|---|---|
| `ChonSong/repo-transmute` | Code blueprint index + chunking + evaluator | Active dev |
| `ChonSong/agent-interaction-evaluator` | AIE observability framework | Phases 1-5 done |
| `ChonSong/claw-aie` | Instrumented agent harness with hooks | Phase A done |
| `HKUDS/ClawTeam` | Swarm orchestration (upstream) | External |
| `codi` (workspace) | Code ingestion agent | Active |
| `g3` (workspace) | Rust agent | Active |

### Duplication Inventory

| What | Repo A | Repo B | Which wins? | Rationale |
|---|---|---|---|---|
| Drift detection | `repo-transmute/evaluator/drift_detector.py` | `AIE/drift.py` | **AIE wins** | txtai-backed, semantic similarity, active dev |
| Audit trails | `repo-transmute/evaluator/audit.py` | `AIE/audit.py` | **AIE wins** | More complete, integrates with oracle engine |
| Oracle engine | `repo-transmute/evaluator/interface.py` | `AIE/oracle_engine.py` | **AIE wins** | YAML-based, extensible, AIE's core feature |
| Tool execution | `codi/nanobot_tools.py` | `claw-aie/tool_executor.py` | **claw-aie wins** | Async, hooks, canonical AIE emitter |
| Event schema | `repo-transmute/evaluator/events.py` | `AIE/schema.py` | **AIE wins** | AIE's 7 types are richer |
| txtai index | `repo-transmute/txtai/client.py` | `AIE/txtai_client.py` | **Shared** | Both use same instance |

### What Gets Deleted

| File | Reason |
|---|---|
| `repo-transmute/src/repo_transmute/evaluator/` (entire dir) | Replaced by AIE |
| `codi/code-library/nanobot_tools.py` | Replaced by claw-aie ToolExecutor |
| `codi/code-library/openhands_events.py` | AIE schema replaces this |
| `AIE/txtai_client.py` (separate) | Refactor to import from repo-transmute |

### What Gets Refactored

| File | Change |
|---|---|
| `AIE/txtai_client.py` | Import `TxtaiClient` from repo-transmute, extend for AIE collections only |
| `AIE/audit.py` | Import `AuditGenerator` from repo-transmute if useful, extend for AIE |
| `codi` tool usage | Wrap `claw-aie ToolExecutor` instead of `nanobot_tools.py` |
| ClawTeam | Emit delegation events in AIE format (Phase 6 integration) |

---

## Phase 0 — Architecture Definition (1-2 hours, human-required)

### Deliverable: `ARCHITECTURE.md`

One document, one diagram, covers all repos.

```markdown
# Ecosystem Architecture

## Vision
> "An observable, reliable multi-agent development pipeline."

## Layers

| Layer | System | Responsibility |
|---|---|---|
| Orchestration | ClawTeam | Swarm coordination, task delegation, inbox |
| Execution | claw-aie | Tool execution, hook pipeline, AIE event emission |
| Observability | AIE | Event indexing, drift detection, oracle evaluation, audit trails |
| Context | RepoTransmute | Code blueprints, semantic search, chunking |

## Event Flow

```
ClawTeam delegation event
    ↓ (delegation event, AIE schema)
claw-aie tool execution
    ↓ (tool_call event, AIE schema)
AIE: txtai index → oracle evaluation → drift detection
    ↓
Human: audit trail, drift alert
```

## Canonical Schemas

- **Event schema:** AIE `schema.py` (7 event types) = canonical
- **Event transport:** AIE logger IPC (`/tmp/ailogger.sock`) = canonical
- **Drift detection:** AIE `drift.py` = canonical
- **Oracle format:** AIE YAML oracles = canonical
- **Tool executor:** claw-aie `ToolExecutor` = canonical
- **txtai index:** Shared, same instance, different collections
```

**Owner for this phase:** Human (architect)

---

## Phase 1 — Deduplicate Evaluator (2-3 hours, subagent)

### Step 1.1: Refactor AIE txtai_client to extend RepoTransmute

In `agent-interaction-evaluator/src/evaluator/txtai_client.py`:

```python
import sys
from pathlib import Path
sys.path.insert(0, str(Path("~/workspace/zoul/repo-transmute/src")))
from repo_transmute.txtai.client import TxtaiClient

class AIETxtaiClient(TxtaiClient):
    """AIE-specific collection only — reuses RepoTransmute index."""
    COLLECTION = "agent_events"
    # All shared logic comes from TxtaiClient
```

**Criteria for done:** `python -c "from evaluator.txtai_client import AIETxtaiClient; c = AIETxtaiClient(); print('OK')"` runs without error.

### Step 1.2: Import DriftDetector from RepoTransmute (optional, if useful)

Review `repo-transmute/evaluator/drift_detector.py` — if the keyword-based detector adds value as a complementary signal, wrap it. Otherwise, delete.

### Step 1.3: Delete `repo-transmute/evaluator/`

After confirming AIE's drift detection covers the same use cases:
```bash
rm -rf repo-transmute/src/repo_transmute/evaluator/
git commit -m "dedup: remove evaluator — replaced by AIE"
```

**Criteria for done:** AIE tests still pass, `aidrift scan` works against existing index.

---

## Phase 2 — Unify Tool Execution (2-3 hours, subagent)

### Step 2.1: Document claw-aie ToolExecutor interface

Verify `claw-aie/aie_integration/tool_executor.py` has:
- `ToolExecutor.execute(tool_name, tool_input) -> ToolResult`
- `ToolResult` with: `tool_name, output, exit_code, duration_ms, denied, error`

### Step 2.2: Update codi to use claw-aie ToolExecutor

In `codi/code-library/nanobot_tools.py`:
- Replace `ToolRegistry` implementation with delegation to `claw-aie.ToolExecutor`
- Keep the `Tool` and `ToolParam` classes (they're a clean interface)
- Just swap the executor backend

```python
# Before (in nanobot_tools.py)
async def execute(self, **kwargs):
    return await self.func(**kwargs)

# After — delegate to claw-aie
from aie_integration.tool_executor import ToolExecutor
_executor = ToolExecutor()

async def execute(self, **kwargs):
    result = await _executor.execute(self.name, kwargs)
    return result.output
```

### Step 2.3: Delete `openhands_events.py` (optional)

If `openhands_events.py` EventStream is not used by anything else in codi, mark for deletion. If used, keep but don't extend.

**Criteria for done:** codi tool execution still works via `claw-aie ToolExecutor`.

---

## Phase 3 — ClawTeam Integration (3-4 hours, research + subagent)

### Step 3.1: Research ClawTeam delegation events

Read ClawTeam's `team/tasks.py` and `team/mailbox.py`:
- What events does ClawTeam emit when a task is delegated?
- Can we intercept them to emit AIE `delegation` events?

### Step 3.2: Add AIE delegation event emission to ClawTeam

If ClawTeam has a delegation hook we can instrument:
```python
# In ClawTeam team/manager.py
from aie_integration.hooks.aie_emitter import AIEEventEmitter

emitter = AIEEventEmitter(socket_path="/tmp/ailogger.sock")

def delegate_task(task, from_agent, to_agent):
    event = build_delegation_event(task=task, from_agent=from_agent, to_agent=to_agent)
    emitter.emit(event)  # non-blocking
```

### Step 3.3: Update ClawTeam README

Document that ClawTeam now emits AIE-compatible events.

**Criteria for done:** ClawTeam delegation appears in `aidrift scan` output.

---

## Phase 4 — Write Architecture Doc (1 hour, human)

### Deliverable: `ARCHITECTURE.md` in ChonSong org root

Create a new repo `ChonSong/ecosystem` or add to `repo-transmute` as `ARCHITECTURE.md`.

Content:
1. Vision statement
2. System diagram (ASCII)
3. Layer descriptions
4. Event flow
5. Canonical schemas
6. Repo ownership table
7. Simplification decisions and rationale

---

## Phase 5 — Validate End-to-End (1-2 hours, subagent)

### Step 5.1: Run full AIE pipeline with claw-aie events

```bash
# Start AIE logger
ailogger serve &

# Run claw-aie tool (Phase B will wire this)
python -c "
import asyncio
from aie_integration.tool_executor import ToolExecutor
from aie_integration.hooks.runner import HookRunner
from aie_integration.hooks.aie_emitter import AIEEventEmitter

async def test():
    executor = ToolExecutor()
    runner = HookRunner(executor)
    emitter = AIEEventEmitter()
    runner.register_pre(emitter)
    runner.register_post(emitter)
    
    result = await executor.execute('bash', {'command': 'echo hello'})
    print(result.output)

asyncio.run(test())
"

# Verify event was indexed
aidrift scan --all
```

### Step 5.2: Run full ClawFlow autonomous cycle

```bash
openclaw flow trigger aie_heartbeat
```

Verify: drift scan, oracle batch, audit trails all work.

---

## Timeline

| Phase | Duration | Dependency | Owner |
|---|---|---|---|
| 0 — Architecture definition | 1-2h | None | Human |
| 1 — Deduplicate evaluator | 2-3h | Phase 0 | Subagent |
| 2 — Unify tool execution | 2-3h | Phase 0 | Subagent |
| 3 — ClawTeam integration | 3-4h | Phase 1-2 | Research + subagent |
| 4 — Architecture doc | 1h | All above | Human |
| 5 — End-to-end validation | 1-2h | All above | Subagent |

**Total:** ~10-17 hours, split human/subagent.

---

## Open Questions

| # | Question | Decision needed |
|---|---|---|
| 1 | Delete or keep `repo-transmute/evaluator/`? | Keep if keyword drift adds value, delete otherwise |
| 2 | ClawTeam integration — fork or sidecar? | Fork upstream or instrument locally? |
| 3 | New org-level `ARCHITECTURE.md` repo or existing repo? | Where does the architecture doc live? |
| 4 | codi's `openhands_events.py` — used by anything else? | Delete or keep? |

---

## Simplification Principles

1. **AIE event schema = canonical.** Everything emits in AIE format.
2. **claw-aie ToolExecutor = canonical tool execution.** All agents use it.
3. **AIE drift/oracle/audit = canonical observability.** RepoTransmute delegates.
4. **RepoTransmute = code context only.** Blueprint index, semantic search, chunking.
5. **ClawTeam = swarm orchestration.** Task/agent coordination only.
6. **txtai = shared infrastructure.** One FAISS index, multiple collections.
7. **/tmp/ailogger.sock = event transport.** All agents emit here.

---

## After Simplification — The Clean Map

```
ClawTeam (orchestration)
    ↓ delegation events → AIE logger
    
codi + g3 + claw-aie (execution)
    ↓ tool_call events → AIE logger
    (via claw-aie ToolExecutor)

AIE (observability)
    ↓ txtai index, oracles, drift, audit
    
RepoTransmute (code context)
    ← queried by AIE for cross-referencing

Human (auditor)
    ← receives drift alerts, reads audit trails
```

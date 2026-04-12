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

---

## Phase 2 Extension — Alto's Orchestrator Spec (2026-04-08)

**Source:** Alto's AIE Orchestrator Node specification (Discord, 2026-04-08)
**Date:** 2026-04-08
**Goal:** Incorporate the four mandatory circuit breaker halt conditions, formalize the delegation payload, and document the HitL handoff package format.

### What Was Added

| Change | File | Description |
|---|---|---|
| **Bug fix** | `oracle_engine.py` | Added `field_gte` and `field_lte` evaluators. `halt_on_critical_drift.yaml` was using unregistered `field_gte` type — oracle never fired. |
| **Bug fix** | `halt_on_critical_drift.yaml` | Changed `field_gte` + `value: 0.9` to correct `threshold_value: 0.9` + `op: "gte"` fields. |
| **New oracle** | `rag_toxicity.yaml` | Circuit breaker: memory confidence < 60% on assumption events. Uses new `memory_confidence` evaluator. |
| **New oracle** | `blast_radius_violation.yaml` | Circuit breaker: tier_mutation tool without pre-approval token. Fires on namespace patterns + `tier: mutation` field. |
| **New oracle** | `operational_exhaustion.yaml` | Circuit breaker: 100% error rate over last 5 events (>=3 consecutive errors without progress). |
| **New evaluator** | `oracle_engine.py` | `ErrorLoopEvaluator` (TYPE: `error_loop`) — detects consecutive identical error patterns. |
| **New evaluator** | `oracle_engine.py` | `MemoryConfidenceEvaluator` (TYPE: `memory_confidence`) — checks multiple memory confidence field paths. |
| **Registry update** | `_registry.yaml` | Added `rag_toxicity`, `blast_radius_violation`, `operational_exhaustion` to index. Bumped registry_version to 1.1. |

### The Four Mandatory Circuit Breaker Halt Conditions (from spec)

These are now implemented as four oracles in `oracles/circuit_breaker/`:

| # | Condition | Oracle | Trigger | Severity |
|---|---|---|---|---|
| 1 | **Semantic Drift** | `halt_on_critical_drift` | `drift_score >= 0.9` on `drift_detected` events | `critical` |
| 2 | **Operational Exhaustion** | `operational_exhaustion` | 100% error rate over last 5 `tool_call` events | `critical` |
| 3 | **Blast Radius Violation** | `blast_radius_violation` | `tier_mutation` tool without `blast_radius_exempt` flag | `critical` |
| 4 | **RAG Toxicity** | `rag_toxicity` | `memory_confidence < 0.6` on `assumption` events | `critical` |

### Delegation Protocol — Sub-Agent Initialization Payload

Alto's spec defines a formal payload for sub-agent initialization. This is documented in `ARCHITECTURE.md §II` but not yet enforced by the oracle system. The four required fields:

| Field | Description | Current Status |
|---|---|---|
| **Task Vector** | Unambiguous objective + terminal state | Captured in `delegation.task.description` + `task.intent` |
| **Context Payload (MVC)** | Minimum Viable Context, no global state | `delegation.task.context_summary` + `context_fidelity` oracle validates fidelity >= 0.5 |
| **Tool ACL** | Whitelist of permitted tools per tier | `blast_radius_violation` oracle enforces tier boundaries |
| **Success Oracle** | Codified testable standard | `oracle_ref` on delegation events; evaluated via oracle engine |

### HitL Diagnostic Handoff Package

When any circuit breaker trips, the system produces a diagnostic package for Human-in-the-Loop review. Format:

```
Terminal State:   <event_id + event_type where circuit breaker fired>
Trigger Code:     <which of the 4 circuit breakers activated>
Last Good State:  <prior oracle result or event_id before violation>
Sub-Agent Diagnostic: <relevant fields: tool.name, error_message, drift_score, etc.>
```

The `blast_radius_violation.yaml` oracle metadata includes explicit `hitl_package_fields` listing which event fields to surface. The `audit.py` module generates the full provenance chain from the audit trail.

### Updated Circuit Breaker Event Schema

The `circuit_breaker` event schema (`schema.py`) is extended to carry the four trigger types:

```yaml
event_type: circuit_breaker
gate:
  name:              # oracle_id that fired
  threshold:         # what threshold was exceeded
  assumptions_violated: []  # event_ids that caused the violation
  trigger_type:      # "semantic_drift" | "operational_exhaustion" | "blast_radius_violation" | "rag_toxicity"
halt_session: true
alert_sent: true
audit_ref: "oracle_result:<oracle_id>"
```

### Notes on `blast_radius_violation`

The oracle fires when:
1. A `tool.namespace` matches mutation-tier patterns (`delete`, `drop`, `exec_write`, `deploy`, `kubectl`, etc.) OR `tool.tier == "mutation"`
2. AND `tool.blast_radius_exempt` is absent or empty

This is a best-effort detection. Full tool ACL enforcement requires instrumenting the tool executor (claw-aie Layer 2) to emit `tier` on each tool call. That integration is planned for Phase B of claw-aie development.

### Open Questions

| # | Question | Status |
|---|---|---|
| 1 | Exact blast_radius_exempt token format? | Open — needs claw-aie Phase B integration |
| 2 | Tool ACL tiers defined in spec but not yet enforced in tool executor | Open — Layer 2 (claw-aie) work |
| 3 | Provenance/Drift Score/Resource Burn fields in audit trail beyond txtai index? | Open — audit.py enhancement needed |
| 4 | ErrorLoopEvaluator requires events_list populated by caller — how is this populated in on_event triggers? | Open — the oracle engine evaluates one event at a time; session history must be fetched and passed in |


---

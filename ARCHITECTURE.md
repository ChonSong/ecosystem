# Ecosystem Architecture

> **Version:** 0.1
> **Status:** Active — simplification sprint in progress
> **Date:** 2026-04-02

---

## Vision

> *"An observable, reliable multi-agent development pipeline where agents coordinate through ClawTeam, execute through claw-aie, and every consequential decision — every assumption, every delegation, every tool call — is logged, indexed, and auditable."*

The goal is not more agents. The goal is **agents you can trust** — because every decision they make is traceable, every assumption is checkable, and every failure is recoverable.

---

## The Four Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│  LAYER 1: ORCHESTRATION                                              │
│  ClawTeam — swarm coordination, task delegation, inbox, board         │
│  Responsibility: "What work exists and who owns it?"                │
└──────────────────────────────────┬────────────────────────────────────┘
                                   │ delegation events (AIE schema)
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  LAYER 2: EXECUTION                                                  │
│  claw-aie — async tool executor, PreToolUse/PostToolUse hooks       │
│  codi + g3 — agents using claw-aie's tool executor                  │
│  Responsibility: "Execute work and emit structured events"          │
└──────────────────────────────────┬────────────────────────────────────┘
                                   │ tool_call events (AIE schema)
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  LAYER 3: OBSERVABILITY                                             │
│  AIE — event indexing, oracle evaluation, drift detection, audit    │
│  Responsibility: "Did the work make sense? Were assumptions valid?" │
└──────────────────────────────────┬────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  LAYER 4: CONTEXT                                                   │
│  RepoTransmute — code blueprints, semantic chunking, search         │
│  Responsibility: "What is the codebase?"                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## The Five Failure Modes

This architecture addresses five specific failure modes from `agentic-workflow-philosophy.md`:

| # | Failure Mode | Description | How the Ecosystem Addresses It |
|---|---|---|---|
| 1 | **Context bankruptcy** | Information lost through compression at delegation steps | AIE `context_summary` oracle flags low-fidelity delegations |
| 2 | **Cascading assumption failure** | Early wrong assumption invalidates downstream work | AIE semantic drift detection catches contradictions before cascade |
| 3 | **Cascade failure (Minsky)** | Success breeds recklessness | Circuit Breaker oracles halt when drift_score ≥ 0.9 |
| 4 | **Accountability vacuum** | No one knows who made which decision | Audit trails give every consequential action a provenance chain |
| 5 | **Evaluation debt** | Systems deployed before assumptions are validated | Oracle engine evaluates against codified standards |

---

## Canonical Ownership

Every component has exactly one owner. No shared ownership.

| Component | Canonical Repo | Layer |
|---|---|---|
| Swarm orchestration | `HKUDS/ClawTeam` (external) | Layer 1 |
| Tool executor + hooks | `ChonSong/claw-aie` | Layer 2 |
| Event schema (7 types) | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| AIE logger IPC (`/tmp/ailogger.sock`) | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| Drift detection | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| Oracle engine | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| Audit trails | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| txtai/FAISS index | `ChonSong/repo-transmute` (shared) | All layers |
| Code blueprints | `ChonSong/repo-transmute` | Layer 4 |
| Semantic chunking | `ChonSong/repo-transmute` | Layer 4 |

---

## Repos

| Repo | Description | Phase |
|---|---|---|
| `ChonSong/agent-interaction-evaluator` | AIE observability framework | Phases 1-5 complete, 6-7 planned |
| `ChonSong/claw-aie` | Instrumented harness with hook pipeline | Phase A complete, B-D planned |
| `ChonSong/repo-transmute` | Code blueprint index + semantic search | Active |
| `ChonSong/ecosystem` | This document — architecture and coordination | Active |
| `HKUDS/ClawTeam` | Swarm orchestration (external, upstream) | — |

---

## Shared Infrastructure

### txtai/FAISS

One FAISS index at `~/workspace/zoul/repo-transmute/data/txtai/`. Multiple collections:

| Collection | Owner | Contents |
|---|---|---|
| `blueprints` | RepoTransmute | Code blueprint chunks |
| `agent_events` | AIE | All interaction events |

Both collections share `sentence-transformers/all-MiniLM-L6-v2` embedding model and FAISS index files. Each has its own SQLite metadata sidecar.

### AIE Logger IPC

Unix socket at `/tmp/ailogger.sock`. JSON-RPC 2.0 protocol.

All agents emit events here. AIE observes and indexes. Agents do not block on AIE.

```
claw-aie → emit(tool_call) → /tmp/ailogger.sock → AIE indexer
ClawTeam → emit(delegation) → /tmp/ailogger.sock → AIE indexer
```

### AIE Event Schema (Canonical)

Seven event types — the canonical schema for all agent interactions:

| Event Type | When Emitted | Key Fields |
|---|---|---|
| `delegation` | Task handed to another agent | delegator, delegate, task, context_summary, context_fidelity |
| `tool_call` | Tool executed | tool.name, tool.arguments (sanitised), outcome |
| `assumption` | Agent states a belief | assumption.statement, confidence, grounded_in |
| `correction` | Agent revises prior assumption | prior_event_id, revised_statement, severity |
| `drift_detected` | Assumption contradiction found | drift_score, contradiction_type |
| `circuit_breaker` | Circuit breaker gate fires | gate.name, halt_session |
| `human_input` | Human provides input | human.role, input.type |

---

## Simplification Decisions

The following duplication was eliminated during the 2026-04-02 simplification sprint:

| What was removed | Why | Replaced by |
|---|---|---|
| `repo-transmute/src/repo_transmute/evaluator/` | Duplicated drift detection, audit, oracle logic | AIE |
| `codi/nanobot_tools.py` | Duplicated tool executor | claw-aie `ToolExecutor` |
| Separate AIE txtai client | Rewrote to import from RepoTransmute | Single source of truth |
| `openhands_events.py` in codi | Dead code — nothing imported it | Deleted |

### Rationale: Why Semantic Drift Replaces Keyword Drift

| Method | Catches | Misses |
|---|---|---|
| Keyword-based ("but", "actually", "wait") | Explicit self-corrections | Re-phrased assumptions with no keyword |
| Semantic similarity (txtai cosine) | Same assumption, different words | Implicit logical contradictions (NLI required) |

Semantic similarity subsumes keyword detection. Keyword detection is a v1 heuristic rendered obsolete by semantic drift detection.

### Rationale: Why Sidecar for ClawTeam

Forking ClawTeam means maintaining permanent divergence from an actively-maintained upstream. ClawTeam is instrumented locally via a sidecar that intercepts delegation events and emits AIE-compatible events. No fork, no divergence.

---

## Simplification Sprint (2026-04-02)

See `docs/SIMPLIFICATION_SPRINT.md` for the full sprint plan and decisions.

### Open Questions — Resolved

| # | Question | Decision |
|---|---|---|
| 1 | Delete `repo-transmute/evaluator/`? | ✅ DELETE — semantic drift subsumes keyword drift |
| 2 | ClawTeam integration approach? | ✅ Sidecar — instrument locally, don't fork |
| 3 | ARCHITECTURE.md location? | ✅ New repo: `ChonSong/ecosystem` |
| 4 | `openhands_events.py` in codi? | ✅ DELETE — confirmed unused |

---

## Event Flow Diagram

```
Human → ClawTeam: assigns task
    ↓
ClawTeam delegation event
    ↓ emit(delegation) → /tmp/ailogger.sock
    ↓
claw-aie tool execution
    ↓ emit(tool_call) → /tmp/ailogger.sock
    ↓
AIE indexer → txtai (agent_events collection)
    ↓
AIE oracle evaluation (YAML oracles, 8 oracles)
    ↓
AIE drift detection (semantic similarity ≥ 0.85 → drift flagged)
    ↓
AIE audit trail generation
    ↓
Human ← AIE: drift alert (if critical) / audit trail (on demand)
```

---

## Future: ClawTeam Swarm → AIE Events

When a ClawTeam swarm runs:

1. Swarm coordinator delegates task to agent
2. Sidecar intercepts delegation event → emits `delegation` to AIE
3. Agent uses claw-aie tool executor → each tool emits `tool_call` to AIE
4. AIE indexes, evaluates, detects drift
5. If drift_score ≥ 0.9 → Circuit Breaker fires → swarm halts
6. Human reviews audit trail

---

## Contributing

If adding a new component to the ecosystem:

1. Determine which layer it belongs to
2. Emit events in AIE schema (Layer 3)
3. Emit to `/tmp/ailogger.sock` (Layer 3)
4. If it uses code context, query RepoTransmute (Layer 4)
5. If it coordinates agents, use ClawTeam (Layer 1)
6. Update this document with the new component

---

## Simplification Sprint Results (2026-04-02)

Completed phases 1-3 of the simplification sprint.

### Phase 1 — txtai Deduplication ✅

AIE `txtai_client.py` refactored to extend RepoTransmute's `TxtaiClient`. Shared FAISS index, separate `agent_events` collection. Commit: `cc37c20`.

### Phase 2 — Tool Execution Deduplication ✅

- **codi `nanobot_tools.py`** — delegatestool execution to `claw-aie ToolExecutor` for: bash, file_read, file_write, glob, grep
- **`openhands_events.py`** in codi — DELETED (confirmed unused — nothing imported it)
- Commit in codi workspace: `b3a1ac5`

### Phase 3 — ClawTeam Research ✅

ClawTeam delegation model mapped:

| Component | What it does | Integration point |
|---|---|---|
| `FileTaskStore.update()` | Ownership change = delegation | `owner` field change → emit `delegation` event |
| `FileTaskStore.create()` | Task creation | `blocked_by` → delegation tree |
| `mailbox.py` | Agent-to-agent messages | Future: `message` event type |

**Sidecar approach confirmed viable.** Wrapping `FileTaskStore.update()` to detect `owner` changes and emit AIE delegation events is the integration strategy.

### Remaining Work

| Item | Status |
|---|---|
| Delete `repo-transmute/evaluator/` | Pending — verify AIE covers all use cases |
| ClawTeam sidecar implementation | Planned — integration point identified |
| claw-aie Phase B-D | Planned — remaining harness features |

### Repos

| Repo | Description | Simplification sprint |
|---|---|---|
| `ChonSong/agent-interaction-evaluator` | AIE observability framework | txtai_client refactored to extend RepoTransmute |
| `ChonSong/claw-aie` | Instrumented harness | ToolExecutor now canonical, codi delegates to it |
| `ChonSong/repo-transmute` | Code blueprint index | Pending: evaluator deletion |
| `ChonSong/ecosystem` | This document | Architecture doc |
| `HKUDS/ClawTeam` | Swarm orchestration (external) | Sidecar integration point identified |

---

## Simplification Sprint — Complete

### Phase 4 ✅ — repo-transmute evaluator deleted

Verified: `repo-transmute/evaluator/` was self-contained, zero imports from other modules, never wired into the pipeline. Deleted:

```
src/repo_transmute/evaluator/__init__.py
src/repo_transmute/evaluator/assumption_extractor.py
src/repo_transmute/evaluator/audit.py
src/repo_transmute/evaluator/drift_detector.py
src/repo_transmute/evaluator/events.py
src/repo_transmute/evaluator/interface.py
src/repo_transmute/evaluator/search.py
tests/test_evaluator.py

8 files, 2000 deletions
Commit: ChonSong/repo-transmute@4e04cd7
```

### All Simplification Phases Complete

| Phase | Status |
|---|---|
| 1 — txtai dedup | ✅ AIE extends RepoTransmute TxtaiClient |
| 2 — Tool dedup | ✅ codi delegates to claw-aie ToolExecutor |
| 3 — ClawTeam research | ✅ Sidecar approach confirmed viable |
| 4 — Delete repo-transmute evaluator | ✅ Deleted (2000 lines removed) |


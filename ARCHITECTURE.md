# Ecosystem Architecture

> **Version:** 0.2
> **Status:** Active — sidecar MVP built
> **Date:** 2026-04-11

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
│  + ClawTeam AIE Sidecar — delegation event emission                 │
│  Responsibility: "What work exists and who owns it?"                │
└──────────────────────────────────┬────────────────────────────────────┘
                                   │ delegation events (written to JSONL)
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
│  lobster heartbeat workflow (aie_heartbeat)                         │
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
| **ClawTeam AIE Sidecar** | `ChonSong/clawteam-sidecar` | Layer 1→3 |
| Tool executor + hooks | `ChonSong/claw-aie` | Layer 2 |
| Event schema (7 types) | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| AIE logger + IPC | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| Drift detection | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| Oracle engine | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| Audit trails | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| lobster heartbeat workflow | `ChonSong/agent-interaction-evaluator` | Layer 3 |
| txtai/FAISS index | `ChonSong/repo-transmute` (shared) | All layers |
| Code blueprints | `ChonSong/repo-transmute` | Layer 4 |
| Semantic chunking | `ChonSong/repo-transmute` | Layer 4 |

---

## Repos

| Repo | Description | Status |
|---|---|---|
| `ChonSong/agent-interaction-evaluator` | AIE observability framework | Phases 1-5 source complete, e2e testing pending, 6-7 planned |
| `ChonSong/claw-aie` | Instrumented harness with hook pipeline | Phase A complete, B-D planned |
| `ChonSong/repo-transmute` | Code blueprint index + semantic search | Active |
| `ChonSong/clawteam-sidecar` | Filesystem watcher for ClawTeam delegation events | MVP built, separate from claw-aie |
| `ChonSong/ecosystem` | This document — architecture and coordination | Active |
| `HKUDS/ClawTeam` | Swarm orchestration (external, upstream) | — |
| `openclaw/lobster` | Workflow engine for aie_heartbeat | Active |

---

## Shared Infrastructure

### txtai/FAISS

One FAISS index at `~/workspace/zoul/repo-transmute/data/txtai/`. Multiple collections:

| Collection | Owner | Contents |
|---|---|---|
| `blueprints` | RepoTransmute | Code blueprint chunks |
| `agent_events` | AIE | All interaction events |

Both collections share `sentence-transformers/all-MiniLM-L6-v2` embedding model and FAISS index files. Each has its own SQLite metadata sidecar.

### AIE JSONL Log

Delegation events are written directly to the daily JSONL log (no socket required):

```
{agent-interaction-evaluator-repo}/data/logs/{YYYY-MM-DD}.jsonl
```

The lobster `aie_heartbeat` workflow reads this log on each run.

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

## ClawTeam Sidecar — Layer 1→3 Integration

**Repo:** `ChonSong/clawteam-sidecar`

The sidecar monitors ClawTeam's `FileTaskStore` task JSON files. When a task's `owner` field changes, it emits an AIE `delegation` event.

**How it works:**

```
ClawTeam FileTaskStore.update() — owner changes
    ↓ writes task JSON
task-{id}.json modified
    ↓ inotify/polling detects change
sidecar parses old vs new owner
    ↓ owner changed = delegation
emits AIE delegation event → JSONL log
    ↓ lobster aie_heartbeat reads on next run
AIE indexes + evaluates + detects drift
```

**Why a sidecar (not a fork or inline patch):**

- ClawTeam is external and actively maintained — permanent forking creates divergence
- ClawTeam has a hooks system, but `AfterTaskUpdate` lacks `old_owner` — can't detect delegation without pre-change state
- Filesystem monitoring is the most portable, least invasive integration point
- No modifications to ClawTeam required

**Quick start:**

```bash
cd clawteam-sidecar && pip install -e .
clawteam-sidecar --data-dir ~/.clawteam --team test-team
```

**Files:**

```
clawteam-sidecar/
├── README.md
├── setup.py
├── bin/sidecar-run
└── src/sidecar/
    ├── __init__.py
    ├── events.py      # AIE event dataclasses
    └── watcher.py     # inotify/polling watcher + JSONL emitter
```

---

## Event Flow Diagram

```
Human → ClawTeam: assigns task
    ↓
ClawTeam FileTaskStore.update() → task-{id}.json written
    ↓ sidecar (inotify/polling) detects owner change
claw-aie tool execution
    ↓ emit(tool_call) → JSONL log
    ↓
AIE indexer → txtai (agent_events collection)
    ↓
AIE oracle evaluation (YAML oracles)
    ↓
AIE drift detection (semantic similarity ≥ 0.85 → drift flagged)
    ↓
AIE audit trail generation
    ↓
Human ← AIE: drift alert (if critical) / audit trail (on demand)
```

---

## lobster Heartbeat Workflow

`evaluator/flows/aie_heartbeat.lobster` — autonomous drift scan + oracle evaluation + health check.

**Steps:**

```
drift_scan  → evaluator.drift scan --all
drift_check → check_drift.sh → _drift_status.json
oracle_batch → evaluator.aieval batch
oracle_check → check_oracle.sh → _oracle_status.json
alert_and_halt → alert_and_halt.py
observability_report → post_observability.sh
health_check → check_health.sh
```

**Note:** The lobster workflow crashes on this environment due to a litellm/FAISS C extension segfault (Python 3.12 int string conversion + C extension cleanup race). The individual commands produce correct output when stdout is redirected to a file. See `ChonSong/clawteam-sidecar` for the JSONL-based approach that avoids this issue.

---

## Simplification Sprint (2026-04-02)

See `docs/docs/archive/SIMPLIFICATION_SPRINT.md` for the full sprint plan and decisions.

| Phase | Status |
|---|---|
| 1 — txtai dedup | ✅ AIE extends RepoTransmute TxtaiClient |
| 2 — Tool dedup | ✅ codi delegates to claw-aie ToolExecutor |
| 3 — ClawTeam research | ✅ Sidecar approach confirmed viable |
| 4 — Delete repo-transmute evaluator | ✅ Deleted (2000 lines removed) |
| **5 — ClawTeam sidecar MVP** | ✅ **Built** |

---

## Contributing

If adding a new component to the ecosystem:

1. Determine which layer it belongs to
2. Emit events in AIE schema (Layer 3)
3. Write to JSONL log or emit to AIE socket (Layer 3)
4. If it uses code context, query RepoTransmute (Layer 4)
5. If it coordinates agents, use ClawTeam (Layer 1)
6. Update this document with the new component

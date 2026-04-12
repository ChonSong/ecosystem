# E2E Validation Report — 2026-04-12

> First-ever end-to-end test of the AIE pipeline with a live logger.

## Result: ✅ Pipeline Validated

All 4 pipeline stages work end-to-end. 2 bugs found and fixed.

---

## Test Procedure

1. Started `ailogger serve` (JSON-RPC over Unix socket `/tmp/ailogger.sock`)
2. Emitted 8 test events (4 per session) via `AILoggerClient`
3. Validated each pipeline stage independently

## Pipeline Stage Results

### Stage 1: Event Emission → JSON-RPC → Logger
| Test | Result |
|---|---|
| Connect to Unix socket | ✅ |
| Emit delegation event | ✅ |
| Emit assumption event | ✅ |
| Emit contradictory assumption | ✅ |
| Emit tool_call event | ✅ |
| Status query (4 events received) | ✅ |

### Stage 2: JSONL Persistence
| Test | Result |
|---|---|
| Events written to `evaluator/data/logs/2026-04-12.jsonl` | ✅ |
| All 8 events + 4 circuit_breaker events persisted | ✅ |
| Schema intact (parseable JSON) | ✅ |

### Stage 3: txtai Indexing + Drift Detection
| Test | Result |
|---|---|
| Events indexed in txtai (FAISS) | ✅ 13 events |
| Semantic search "database connection" | ✅ 4 results, top score 0.735 |
| Drift scan e2e-session | ✅ 1 drift found |
| Drift score (contradictory assumptions) | ✅ 0.859 (semantic) |
| Drift scan test-session-001 | ✅ Same contradiction detected |

### Stage 4: Oracle Evaluation
| Test | Result |
|---|---|
| 12 oracles loaded from `oracles/` | ✅ |
| Oracle engine fires on emit (circuit_breaker events in JSONL) | ✅ |
| Per-event-type oracle lookup works | ✅ |

### Stage 5: Audit Trail
| Test | Result |
|---|---|
| Build trail for e2e-session | ✅ |
| 4 events, 2 agents (test, worker) | ✅ |
| 4 decision nodes identified | ✅ |
| Provenance chain delegation→assumption→tool_call | ✅ |

---

## Bugs Found & Fixed

### Bug 1: Path + str concatenation (oracle_engine.py:881)
```python
# BEFORE (crashes):
ld / datetime.now(timezone.utc).strftime("%Y-%m-%d") + ".jsonl"
# AFTER (fixed):
ld / (datetime.now(timezone.utc).strftime("%Y-%m-%d") + ".jsonl")
```
**Impact:** Circuit breaker callback thread crashed silently on every triggered oracle. Events were still persisted (JSONL is written before oracle evaluation), but circuit breaker alerts were never logged.

**Fix:** Commit `7b263b9`

### Bug 2: Missing agent_events_meta table (audit.py:274,302)
```sql
-- BEFORE (crashes):
JOIN agent_events_meta m ON o.event_id = m.event_id
-- AFTER (fixed):
-- Removed JOIN, added Python-side session filtering via txtai
```
**Impact:** `build_trail()` always crashed with `sqlite3.OperationalError: no such table`.

**Fix:** Commit `7b263b9`

---

## Known Issues (Not Fixed)

1. **txtai index path** — Config points to `/home/osboxes/workspace/zoul/repo-transmute/data/txtai` instead of an AIE-specific path. Works but shared with RepoTransmute.
2. **Logger restart loop** — Cron-driven lobster restarts ailogger every 10 min. The oracle_engine bug caused crash loops. Fixed bug, but restart cadence should be documented.
3. **HF Hub unauthenticated warnings** — `HF_TOKEN` not set, causes rate-limit warnings on embedding model load.

---

## Test Suite

- **126 tests pass** (0 failures) after fixes applied
- Test directory: `evaluator/tests/`
- Coverage: schema, logger, txtai, oracle, drift, audit, NLI, sanitiser

---

*Next: claw-aie Phase B (Hook System) — the execution layer that emits events into this pipeline.*

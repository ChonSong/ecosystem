# Ecosystem Integration Map

> Updated: 2026-04-15 — includes browser-review agent and Phase E completion

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   YOU (Sean)                                                                │
│   ├── Discord ─── Zoul (orchestrator)                                      │
│   ├── Drive ───── reports, screenshots, resumes                            │
│   └── CasaOS ──── casa.codeovertcp.com (Vue dashboard)                     │
│                                                                             │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 1 — ORCHESTRATION                                                   │
│                                                                             │
│  HKUDS/ClawTeam (pip v0.2.0)                                               │
│  ├── TeamManager ── create teams, add members, assign roles                │
│  ├── TaskStore ──── shared task board, locking, blocking deps              │
│  ├── Mailbox ────── inter-agent messaging (join, approve, broadcast)       │
│  ├── SpawnBackend ─ launches agent CLIs (claude, codex, gemini, etc.)      │
│  └── Profiles ───── reusable runtime configs per agent                     │
│                                                                             │
│  ChonSong/clawteam-sidecar                                                  │
│  └── Watches FileTaskStore → emits AIE delegation events on owner change   │
│                                                                             │
│  Supported CLIs: claude, codex, gemini, kimi, qwen, opencode, openclaw     │
│                                                                             │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │ spawn agents
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 2 — EXECUTION                                                       │
│                                                                             │
│  ChonSong/claw-aie  ── 113 tests passing                                    │
│  ├── ToolExecutor ── async bash, file_read, file_write, glob, grep          │
│  ├── Harness ─────── wraps agent CLI subprocess, parses tool calls          │
│  │   └── 4 output formats: Claude XML, JSON, Codex, generic                │
│  ├── HookRunner ──── PreToolUse / PostToolUse pipeline                      │
│  │   ├── PermissionHook ─ blocks rm -rf, /etc, /usr writes                 │
│  │   ├── RateLimitHook ─ per-tool token bucket                             │
│  │   └── AIEEventEmitter ─ emits to ailogger.sock (JSON-RPC)              │
│  ├── AIESpawnBackend ─ ClawTeam backend routing through harness             │
│  ├── SpawnHooks ──── DriftCheck, OracleEval, SessionLog                    │
│  └── Browser Tools ─ 8 Playwright tools:                                    │
│      ├── browser_navigate, browser_screenshot, browser_click                │
│      ├── browser_fill, browser_console                                      │
│      ├── browser_assert, browser_assert_no_console_errors                   │
│      └── browser_accessibility_scan                                         │
│                                                                             │
│  ChonSong/claw-aie-harness (openharness-ai v0.1.6)                         │
│  └── Open-source Python port of Claude Code — upstream routing layer        │
│      (claw-aie extends this with AIE instrumentation)                       │
│                                                                             │
│  Browser Review Workflow                                                    │
│  └── navigate → screenshot → console check → a11y scan → report            │
│      (Generates Markdown + JSON reports, uploads to Drive)                  │
│                                                                             │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │ tool_call + session events
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 3 — OBSERVABILITY                                                   │
│                                                                             │
│  ChonSong/agent-interaction-evaluator                                       │
│  ├── AIE Logger ──── IPC via /tmp/ailogger.sock (JSON-RPC)                │
│  ├── Event Indexer ── txtai/FAISS semantic index (agent_events collection)  │
│  ├── Oracle Engine ── YAML rules evaluate event quality                     │
│  ├── Drift Detector ─ semantic similarity ≥ 0.85 → drift flagged           │
│  ├── Circuit Breaker ─ halt when drift_score ≥ 0.9                          │
│  ├── Audit Trails ── provenance chains for every decision                   │
│  ├── 7 Event Types: delegation, tool_call, assumption, correction,         │
│  │   drift_detected, circuit_breaker, human_input                           │
│  └── AIE Dashboard ─ React frontend (DriftMonitor, OracleEval, etc.)       │
│                                                                             │
│  openclaw/lobster ── workflow engine                                         │
│  └── aie_heartbeat flow:                                                    │
│      drift_scan → drift_check → oracle_batch → oracle_check                │
│      → alert_and_halt → health_check                                        │
│                                                                             │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │ queries code context
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 4 — CONTEXT                                                         │
│                                                                             │
│  ChonSong/repo-transmute ── 509 tests passing                               │
│  ├── BlueprintIndexer ── ingest repos, chunk, create code blueprints        │
│  ├── BlueprintSearch ── semantic search via txtai/FAISS                     │
│  ├── TxtaiClient ────── shared index (sentence-transformers/all-MiniLM-L6-v2)│
│  ├── CLI ────────────── repo-transmute index|search|chunk                   │
│  └── Data ───────────── ~/workspace/zoul/repo-transmute/data/txtai/         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│  SUPPORTING SYSTEMS                                                        │
│                                                                             │
│  ChonSong/job-hunter ── scraper → LLM tailor → Drive upload (6h cron)      │
│  ChonSong/casaos-agent ── CasaOS management agent                           │
│  ChonSong/casaos-webhook-emitter ── CasaOS event bridge                     │
│  ChonSong/casaos-dashboard ── Vue sidebar + 5 views (Containers, etc.)     │
│  dhanji/g3 ──────────── dependency (upstream)                               │
│  LiteLLM Proxy ──────── localhost:4000, 100+ LLM providers                  │
│  Rate Smoother ──────── localhost:4001, MiniMax rate smoothing              │
│  Cloudflare ─────────── codeovertcp.com zone + tunnel                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow (Event Lifecycle)

```
1. Task assigned in ClawTeam
   ↓
2. Sidecar detects owner change → delegation event → JSONL log
   ↓
3. AIESpawnBackend spawns agent through claw-aie harness
   ↓
4. Agent executes → Harness parses output → detects tool calls
   ↓
5. Each tool call: PreHook → execute → PostHook → AIE emit
   ↓
6. AIE Logger receives event (ailogger.sock)
   ↓
7. Event indexed in txtai/FAISS (semantic search)
   ↓
8. Oracle Engine evaluates against YAML rules
   ↓
9. Drift Detector checks for assumption contradictions
   │
   ├─ drift < 0.7 → continue
   ├─ drift 0.7-0.9 → warn
   └─ drift ≥ 0.9 → circuit breaker → halt + alert
   ↓
10. Audit trail generated → human reviewable
```

## Browser Review Flow (New)

```
ClawTeam task → AIESpawnBackend
   ↓
Harness (agent_type=browser-review)
   ├── registers browser tools (Playwright)
   ├── registers AIEEventEmitter hook
   ↓
1. browser_navigate(target_url) → AIE event
2. browser_screenshot(full_page) → AIE event
3. browser_console() ──────────→ AIE event
4. browser_accessibility_scan() → AIE event
5. browser_assert() ───────────→ AIE event
   ↓
ReviewReport generated (Markdown + JSON)
   ├── verdict: pass / warn / fail
   ├── screenshots saved to .browser-review/
   └── uploaded to Google Drive
```

## Shared Infrastructure

| Resource | Location | Used By |
|---|---|---|
| txtai/FAISS index | repo-transmute/data/txtai/ | RepoTransmute, AIE |
| AIE JSONL logs | agent-interaction-evaluator/data/logs/ | Sidecar, Lobster |
| ailogger.sock | /tmp/ailogger.sock | claw-aie, Harness |
| ClawTeam data | ~/.clawteam/ | ClawTeam, Sidecar |
| Screenshots | .browser-review/ | Browser Reviewer |
| Google Drive | drive root | Job Hunter, Reports |
| LiteLLM | localhost:4000 | All LLM calls |
| Cloudflare | codeovertcp.com | CasaOS, public endpoints |

## Repo Map

```
github.com/ChonSong/
├── agent-interaction-evaluator  ← Layer 3: AIE core (events, drift, oracles)
├── claw-aie                     ← Layer 2: harness + hooks + browser tools
├── claw-aie-harness             ← Layer 2: upstream openharness-ai
├── clawteam-sidecar             ← Layer 1→3: delegation event bridge
├── repo-transmute               ← Layer 4: code blueprints + semantic search
├── ecosystem                    ← Architecture docs (this diagram)
├── casaos-agent                 ← CasaOS management
├── casaos-dashboard             ← Vue frontend
├── casaos-webhook-emitter       ← Event bridge
└── job-hunter                   ← Job scraper + LLM tailor

github.com/HKUDS/ClawTeam        ← Layer 1: swarm orchestration (external)
github.com/openclaw/lobster       ← Layer 3: workflow engine (external)
github.com/dhanji/g3              ← Dependency (external)
```

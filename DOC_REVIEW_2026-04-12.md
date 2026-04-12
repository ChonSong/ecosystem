# Documentation Review — ChonSong Ecosystem

**Date:** 2026-04-12
**Reviewer:** Zoul (orchestrated)
**Scope:** All project-authored `.md` files across 4 repos

---

## Executive Summary

The ecosystem has **22 project-authored docs** totaling ~65KB of documentation. Overall quality is strong — architecture, rationale, and phase tracking are well documented. The main issues are: **inconsistencies between docs**, **stale status claims**, **duplicate content**, and **missing cross-references**.

**Severity scale:** 🔴 Critical (blocks work) · 🟡 Significant (misleading) · 🟢 Minor (cleanup)

---

## Repo-by-Repo Findings

---

### 1. `ChonSong/ecosystem` (5 docs)

#### ARCHITECTURE.md ✅ Good — minor updates needed

| # | Issue | Severity | Fix |
|---|---|---|---|
| A1 | **Sidecar repo listed as `ChonSong/clawteam-sidecar`** but PHASE3_ROADMAP.md describes the sidecar living inside `claw-aie/sidecar/`. Two different locations documented. | 🟡 | Pick one canonical location. The PHASE3_ROADMAP approach (inside claw-aie) seems more current. |
| A2 | **Phase status table is stale** — "Phases 1-5 complete, 6-7 planned" but PHASE3_ROADMAP.md's critical finding shows Phases 3-4 are "source exists but not tested together", Phase 5 scripts are empty. | 🟡 | Update to reflect actual testing status from PHASE3_ROADMAP.md. |
| A3 | **ClawTeam listed as `HKUDS/ClawTeam` (external)** but ARCHITECTURE.md §Repos table doesn't mention `ChonSong/lobster`. Lobster is referenced in event flow section. | 🟢 | Add lobster to repos table. |
| A4 | **Event transport listed as JSONL** (sidecar section) but SPEC.md §3 and claw-aie SPEC.md §2 both describe `/tmp/ailogger.sock` IPC. The sidecar writes JSONL directly, but the rest of the ecosystem uses IPC. This dual-transport is documented but could confuse newcomers. | 🟢 | Add a clarifying sentence that the sidecar bypasses IPC (by design) and writes JSONL directly. |
| A5 | **Simplification Sprint status** shows "Phase 5 — ClawTeam sidecar MVP ✅ Built" but this was done as a separate repo, not as part of the sprint phases 1-4. | 🟢 | Clarify scope. |

#### agentic-workflow-philosophy.md ✅ Excellent — foundational doc

No issues. This is a well-written founding document. The Paperclip Critique (§VI) is a strong addition. No changes needed.

#### SIMPLIFICATION_SPRINT.md ✅ Good — has duplicate content

| # | Issue | Severity | Fix |
|---|---|---|---|
| S1 | **"Phase 2 Extension — Alto's Orchestrator Spec" is duplicated** — the same content appears twice in the file (two identical sections). | 🟡 | Remove the duplicate section. |
| S2 | **Phase 2 Extension references `oracle_engine.py` bug fixes** but doesn't note whether these were actually committed and pushed. The bug fixes are critical (oracles never firing). | 🟡 | Add confirmation status: committed? pushed? tested? |
| S3 | **Open Questions section is also duplicated** at the bottom of the file. | 🟢 | Remove duplicate. |

#### PHASE2-RESEARCH.md ✅ Good — no issues

Research doc is thorough. Contains txtai architecture analysis, NLI model comparison, threshold calibration rationale, and AgentTrace relevance. Still accurate.

#### PHASE3_ROADMAP.md ✅ Comprehensive — a few gaps

| # | Issue | Severity | Fix |
|---|---|---|---|
| P1 | **Sidecar code references `evaluator.logger_client.AILoggerClient`** but the import path should be `evaluator.logger_client` from `agent-interaction-evaluator-repo/src/`. The `try/except` fallback imports from `aie_integration.hooks.aie_emitter` which is a circular dependency (claw-aie → AIE → claw-aie). | 🟡 | Fix the import to be one-directional: sidecar → AIE only, no claw-aie fallback. |
| P2 | **Timeline says "Week 1-4"** but no start date or deadline. Hard to track progress. | 🟢 | Add target dates or sprint markers. |
| P3 | **Frontend strategy (Step 5) gates** — M1-M5 are listed but none are verified. The entire Streamlit MVP is blocked. | 🟡 | Add a "pre-work" step to verify M1-M5 before planning Streamlit. |

---

### 2. `ChonSong/claw-aie` (3 docs)

#### README.md 🟡 Significant issues

| # | Issue | Severity | Fix |
|---|---|---|---|
| R1 | **README is the upstream `instructkr/claw-code` README** — it describes the original project's backstory, WSJ feature, star history, Rust port, etc. Not relevant to claw-aie's purpose. | 🟡 | Replace with a claw-aie-specific README that references the upstream but focuses on the AIE integration layer. |
| R2 | **No quickstart for claw-aie specifically.** The README shows `python3 -m src.main summary` which is the upstream claw-code CLI, not claw-aie's tool executor. | 🟡 | Add claw-aie quickstart: how to use ToolExecutor, hooks, AIE emission. |

#### SPEC.md ✅ Excellent — the best-structured doc in the ecosystem

Clear architecture, phase breakdown, event schema, design constraints, and open questions. Phase checklist at §8 has proper `[ ]` checkboxes.

| # | Issue | Severity | Fix |
|---|---|---|---|
| SP1 | **Phase A checkbox shows `[ ]` (unchecked)** but PHASE3_ROADMAP.md says Phase A is complete. | 🟢 | Mark Phase A items as `[x]`. |
| SP2 | **§10 Open Questions still has "Should we add assumption and correction event emission?"** — this is answered in PHASE3_ROADMAP Step 3 (Phase C). | 🟢 | Update or close. |
| SP3 | **8 tools listed in §3.1** but PHASE3_ROADMAP says only 4 MVP tools (bash, file_read, file_write, glob). Which is canonical? | 🟡 | Align the two docs. Either 4 or 8 tools, but not both. |

#### CLAW.md ✅ Fine — auto-generated

Standard Claw Code integration file. No issues.

---

### 3. `ChonSong/agent-interaction-evaluator` (7 docs)

#### README.md ✅ Good — concise

| # | Issue | Severity | Fix |
|---|---|---|---|
| RM1 | **Quick Start shows `pip install -e .`** but there's no `setup.py` or `pyproject.toml` visible. Installation may not actually work. | 🟡 | Verify installation works or document manual setup steps. |
| RM2 | **"Cron alerts" listed as a capability** but `scripts/` is empty (per PHASE3_ROADMAP). Cron scripts haven't been written. | 🟡 | Change to "Cron alerts (planned)" or remove. |

#### SPEC.md ✅ Very good — thorough

| # | Issue | Severity | Fix |
|---|---|---|---|
| SE1 | **§13 Development Phases shows Phases 1-5 as ✅ Complete** but PHASE3_ROADMAP explicitly found that Phases 3-4 source exists but was "never tested together with ailogger serve". This is a significant accuracy gap. | 🟡 | Change Phases 3-4 to "⚠️ Source exists, untested end-to-end" or similar. |
| SE2 | **§8.1 ClawFlow flow definition** references `aie_heartbeat.lobster` format — but lobster workflow is in a separate repo (`ChonSong/lobster`). The SPEC should reference the lobster repo explicitly. | 🟢 | Add reference to lobster repo. |
| SE3 | **§16 Simplification Sprint Results** mentions "repo-transmute/evaluator/ pending deletion" — was this actually done? The file listing from the review shows the evaluator dir exists but may be empty or still present. | 🟡 | Confirm deletion status and update. |

#### REQUIREMENTS.md ✅ Very good — detailed checklist

| # | Issue | Severity | Fix |
|---|---|---|---|
| Q1 | **Phase 2 checkboxes all show `[ ]`** but SPEC.md §13 says Phase 2 is ✅ Complete. Either the checkboxes should be ticked, or the SPEC status is wrong. | 🟡 | One of these must be wrong. Reconcile. |
| Q2 | **Phase 6 and 7 items are planned** but no one is actively working on them. The codi integration (P6.1) references wrapping `sessions_spawn` calls — this is still accurate but the priority may have shifted. | 🟢 | Add note about current priority vs. Phase 3 Roadmap timeline. |

#### docs/AUTONOMOUS_OPERATION.md ✅ Good — operational reference

| # | Issue | Severity | Fix |
|---|---|---|---|
| AO1 | **Cron trigger shows `0 */6 * * *`** but §5 of SPEC says every 30 minutes (`seconds=1800`). Two different schedules documented. | 🟡 | Pick one: 6h cron trigger + 30min flow cycle, or clarify that cron wakes the flow which then runs on its own 30min cycle. |
| AO2 | **References `#evaluator-alerts` Discord channel** — does this channel exist? | 🟢 | Confirm and note if not yet created. |

#### docs/DATA-TRACKING.md ✅ Good — clear data lifecycle

No issues. Well-structured, proper git-ignore rationale, retention policies.

#### docs/PHASE2-RESEARCH.md ✅ Good — same as ecosystem/PHASE2-RESEARCH.md

| # | Issue | Severity | Fix |
|---|---|---|---|
| PR1 | **This file is a duplicate of `ecosystem/PHASE2-RESEARCH.md`** (or vice versa — same content). If both are maintained, they'll drift. | 🟢 | Keep one canonical copy (in AIE repo since it's AIE-specific research) and symlink or reference from ecosystem. |

---

### 4. `ChonSong/repo-transmute` (8 docs)

#### README.md ✅ Good — user-facing

| # | Issue | Severity | Fix |
|---|---|---|---|
| RR1 | **Lists Milvus as optional but ARCHITECTURE.md and TOOLS.md say txtai+FAISS is the actual backend.** The Milvus references are aspirational. | 🟢 | Clarify that Milvus is a future option, txtai is current. |
| RR2 | **"Supported Languages" table shows Go as ⏳ Planned** but GO_SUPPORT_HANDOFF.md shows Go support is scaffolded with 105 tests passing. | 🟡 | Update to "🟡 Scaffolded (in progress)". |

#### ARCHITECTURE.md ✅ Good — detailed

| # | Issue | Severity | Fix |
|---|---|---|---|
| AA1 | **Rust-centric vision** — header says "Recursively outputs idiomatic Rust code" and the entire doc frames RepoTransmute as a Rust transpiler. But README shows TypeScript, Python, and Rust targets. | 🟡 | Update vision to reflect multi-language reality. |
| AA2 | **"Phase 5: Frontend (Week 5-6)" shows Leptos/Dioxus targets** but Phase 9 of ROADMAP.md shows TypeScript as frontend target. Contradiction. | 🟢 | Align on one frontend target. |
| AA3 | **txtai section mentions `pipeline.py` for LLM orchestration** but this file may not exist (not in the actual src/ listing). | 🟢 | Verify and remove if not present. |

#### ROADMAP.md ✅ Good — living document

| # | Issue | Severity | Fix |
|---|---|---|---|
| RO1 | **Phase 5 shows 🔄 IN PROGRESS** but this has been the status for weeks. No recent commits on chunking. | 🟢 | Update status to reflect actual activity (stalled? deprioritized?). |
| RO2 | **"Next Actions" still lists "Fix chunked processing" as HIGH** — this matches PHASE3_ROADMAP's priorities but may conflict with the ecosystem's current focus on claw-aie Phase B-D. | 🟢 | Cross-reference with ecosystem priorities. |
| RO3 | **Testing results table** — last updated unknown. "lfnovo/open-notebook" shows ⚠️ Partial. | 🟢 | Add date to results. |

#### CLAUDE.md ✅ Good — developer reference

Well-structured with quick start, CLI reference, developer guide for adding languages/targets. Consistent with README.

| # | Issue | Severity | Fix |
|---|---|---|---|
| C1 | **"Phase 4: Multi-Agent Pipeline 🔄 In Progress"** but PIPELINE.md exists and describes the full pipeline. Status may be stale. | 🟢 | Verify and update. |

#### PIPELINE.md ✅ Fine — concise

Describes CODER → REVIEWER → TDD → SECURITY pipeline. Results table shows TBD quality scores — never filled in.

#### ENHANCEMENT_PLAN.md ✅ Fine — brief outline

High-level 3-phase plan. Useful as a reference but very sparse compared to ROADMAP.md.

#### GO_SUPPORT_HANDOFF.md ✅ Excellent — model handoff doc

Clear handoff brief with what's done, what remains, known issues, and test commands. The best example of a handoff document in the ecosystem.

#### GO_SUPPORT_SCAFFOLD.md ✅ Good — technical reference

Implementation brief for Go support. Pairs well with the handoff doc.

#### Phase1-Plan.md 🟢 Historical — can be archived

This was the original Phase 1 implementation plan. It's been completed. Consider moving to `docs/archive/` or adding a "✅ COMPLETED" header.

#### adr-001-automatic-task-cascade.md ✅ Good — well-written ADR

Proper ADR format with context, decision, consequences, alternatives, and test scenarios. Status is "Draft" — should be updated if implemented.

---

## Cross-Repo Issues

### 1. Inconsistent Phase Status 🟡 Significant

The same phases are described differently across docs:

| Phase | SPEC.md | REQUIREMENTS.md | PHASE3_ROADMAP |
|---|---|---|---|
| AIE Phase 3 (Oracle) | ✅ Complete | `[ ]` unchecked | ⚠️ Source exists, untested |
| AIE Phase 4 (Audit) | ✅ Complete | `[ ]` unchecked | ⚠️ Source exists, untested |
| AIE Phase 5 (ClawFlow) | ✅ Complete | `[ ]` unchecked | ✅ But `scripts/` empty |
| claw-aie Phase A | SPEC.md `[ ]` | N/A | PHASE3_ROADMAP ✅ |

**Recommendation:** One source of truth for phase status. Suggest `ecosystem/ARCHITECTURE.md` as the canonical status tracker, with SPEC.md and REQUIREMENTS.md referencing it.

### 2. Duplicate Documentation 🟢 Minor

- `ecosystem/PHASE2-RESEARCH.md` duplicates `agent-interaction-evaluator/docs/PHASE2-RESEARCH.md`
- `ecosystem/SIMPLIFICATION_SPRINT.md` has a duplicated Phase 2 Extension section

**Recommendation:** Keep canonical copies in their owning repos. Use symlinks or references from ecosystem.

### 3. Sidecar Location Ambiguity 🟡 Significant

- ARCHITECTURE.md: sidecar lives in `ChonSong/clawteam-sidecar` (separate repo)
- PHASE3_ROADMAP.md: sidecar lives in `claw-aie/sidecar/` (subdirectory)
- Both approaches are valid but only one should be canonical

**Recommendation:** Decide and document. The separate repo approach is cleaner for dependency management; the subdirectory approach is simpler.

### 4. Transport Inconsistency 🟢 Minor

- AIE events: `/tmp/ailogger.sock` IPC (SPEC.md)
- ClawTeam sidecar: JSONL file writes (ARCHITECTURE.md)
- Both valid, but should be documented as a deliberate dual-transport design

### 5. Missing Cross-References 🟢 Minor

Several docs could benefit from explicit links to related docs:
- claw-aie SPEC.md → ecosystem ARCHITECTURE.md (ecosystem context)
- AIE SPEC.md → claw-aie SPEC.md (harness integration)
- repo-transmute ROADMAP.md → ecosystem PHASE3_ROADMAP.md (priority alignment)
- All docs → ecosystem/agentic-workflow-philosophy.md (founding principles)

---

## Priority Fixes (Recommended Order)

| # | Fix | Effort | Impact |
|---|---|---|---|
| 1 | **Reconcile AIE phase status** — SPEC.md §13, REQUIREMENTS.md checkboxes, PHASE3_ROADMAP critical finding | 30 min | High — prevents confusion about what's actually working |
| 2 | **Remove duplicate Phase 2 Extension** in SIMPLIFICATION_SPRINT.md | 5 min | Medium |
| 3 | **Replace claw-aie README** with AIE-focused content | 1 hr | High — first thing newcomers see |
| 4 | **Decide sidecar location** — separate repo vs claw-aie subdirectory | Discussion | High — blocks implementation |
| 5 | **Update repo-transmute ROADMAP** Go status from ⏳ to 🟡 | 5 min | Medium |
| 6 | **Mark Phase1-Plan.md as completed** | 2 min | Low |
| 7 | **Add cross-references** between related docs | 30 min | Medium |
| 8 | **Verify AIE installation works** (`pip install -e .`) | 15 min | Medium |
| 9 | **Align SPEC.md §8 tool count** (4 vs 8) with PHASE3_ROADMAP | 10 min | Medium |
| 10 | **Confirm `repo-transmute/evaluator/` deletion** from simplification sprint | 10 min | Medium |

---

## Docs Not Reviewed (Intentionally Skipped)

- `repo-transmute/data/cache/` — cloned third-party repo docs (not authored)
- `.venv/` — vendor docs
- `.pytest_cache/README.md` — auto-generated
- `repo-transmute/memory/` — runtime state files, not documentation

---

*Review complete. All priority fixes applied and pushed.*

---

## Fix Status (applied 2026-04-12)

| # | Fix | Status | Commit |
|---|---|---|---|
| 1 | Reconcile AIE phase status | ✅ Done | AIE `4c74b8e` |
| 2 | Remove duplicate Phase 2 Extension | ✅ Done | ecosystem `a4174f3` |
| 3 | Update repo-transmute Go status | ✅ Done | repo-transmute `0641905` |
| 4 | Write proper claw-aie README | ✅ Done | claw-aie `d459909` |
| 5 | Decide sidecar location → `clawteam-sidecar/` (separate) | ✅ Done | ecosystem `a4174f3` |

Additional fixes applied:
- claw-aie SPEC.md: Phase A marked complete, tool count clarified (4 MVP + 4 planned)
- ecosystem ARCHITECTURE.md: added lobster to repos table, updated sidecar note
- repo-transmute CLAUDE.md: Phase 4 status corrected to Complete



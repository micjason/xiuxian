# Fog Known Autowalk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Visible-snapshot shortest walking with terminal step reconciliation and no automatic interaction.
**Architecture:** Pure BFS planner plus one serial page runner. Fog-scoped player-lock protocol records terminal steps and cancellation tombstones in existing idempotency storage; state digest and expectedFrom reject stale steps. Legacy routes remain compatible.
**Tech Stack:** Godot 4.7 GDScript/GUT, TypeScript/Fastify/Drizzle/Vitest, private PostgreSQL16.

## Global Constraints
- No deployment, pushes, version changes, shared-db truncation or CloudAgent; work only in requested worktree.
- All 20 counterexamples in approved spec are tracked with real test evidence, not inferred passes.
- Unknown cells rejected, no snapshot growth, object targets stop adjacent, guard exception preserved.

### Task 1: Private test infrastructure and baseline
- [ ] Create isolated PG16 cluster on 55439, databases xiuxian_fog_autowalk_test/local; run migrations using explicit local URL.
- [ ] Link existing backend dependency install; run baseline fog tests and Godot import. API 18083 because 18082 is occupied.

### Task 2: Fog terminal-step protocol
Files: backend/src/modules/fog/{steps.ts,steps.test.ts,routes.ts,actions.ts}.
Interfaces: readFogState returns fog.protocol=fog-step-v1 and fog.revision; move v1 consumes stepId,expectedRevision,expectedFrom,x,y; reconcile consumes stepId and original move body, returning terminal and current fog.
- [ ] Write HTTP tests expecting protocol on GET, cancelled late move, committed reconciliation, body mismatch, concurrent same-key, revision conflict and legacy compatibility.
- [ ] Run `DATABASE_URL=<private test URL> node_modules/.bin/vitest run src/modules/fog/steps.test.ts --maxWorkers=1`; verify missing-protocol assertions fail.
- [ ] Implement player lock before cache read; retain old /move branch; map all terminal domain errors to stored rejected results, no partial mutation.
- [ ] Run new tests plus existing fog/combat tests; typecheck and lint; commit backend increment only.

### Task 3: Pure known-region planner
Files: game/scripts/model/fog_route.gd; game/tests/unit/test_fog_route.gd.
Interface: FogRoute.plan(view,target,snapshot) returns {ok,path,object,error}; passable(view,cell) distinguishes unresolved objects/guard exception.
- [ ] Write GUT tests for U wall, islands, unknown adjacent, snapshot no-growth, object adjacent goals, completed objects, guard.
- [ ] Run Godot GUT and observe missing planner failure; implement BFS fixed four-neighbor order and stable closest legal object neighbor.
- [ ] Rerun GUT and commit planner.

### Task 4: Serial UI runner and navigation lifecycle
Files: game/scripts/ui/pages/fog_map_page.gd, game/scripts/ui/play_screen.gd, game/scripts/model/fog_map_view.gd; tests game/tests/unit/test_fog_autowalk.gd.
Interfaces: map stop_route(), bind_fog(payload), injected transport Callable(method,path,body); runner uses persistent pending-step ledger, route generation and snapshot.
- [ ] Write delayed-transport tests proving no concurrent move, 20 repeated clicks dedup, replacement from confirmed pos, hidden response no continuation, uncertain state reconciliation, stale entrance GET guard.
- [ ] Run red; implement queue replacement while busy, apply confirmed model then animate, no automatic _on_cell recursion, explicit chest confirmation.
- [ ] Run green and existing cave tests; record cancellation and timeout evidence from actual page signals/transport calls.

### Task 5: Integrated evidence and handoff
- [ ] Run isolated HTTP concurrency tests with transaction barriers, full backend suite private database, Godot unit suite, typecheck/lint.
- [ ] Run real Godot under Xvfb, use its viewport to capture before/mid/arrival/cancel/recovery/unknown/guard images at /workspace/cp_fix_shots/fog_autowalk.
- [ ] Document per-counterexample results and exact commands/counts, remaining limitations, backend-first release order without deployment.
- [ ] Review diff and commit only explicit source/docs/test paths; preserve unrelated LFS checkout artifacts.

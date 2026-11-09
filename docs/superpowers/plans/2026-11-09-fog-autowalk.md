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
- [x] Create isolated PG16 cluster on 55439, databases xiuxian_fog_autowalk_test/local; run migrations using explicit local URL.
- [x] Link existing backend dependency install; run baseline fog tests and Godot import. API 18083 because 18082 is occupied.

### Task 2: Fog terminal-step protocol
Files: backend/src/modules/fog/{steps.ts,steps.test.ts,routes.ts,actions.ts}.
Interfaces: readFogState returns fog.protocol=fog-step-v1 and fog.revision; move v1 consumes stepId,expectedRevision,expectedFrom,x,y; reconcile consumes stepId and original move body, returning terminal and current fog.
- [x] Write HTTP tests expecting protocol on GET, cancelled late move, committed reconciliation, body mismatch, concurrent same-key, revision conflict and legacy compatibility.
- [x] Run `DATABASE_URL=<private test URL> node_modules/.bin/vitest run src/modules/fog/steps.test.ts --maxWorkers=1`; verify missing-protocol assertions fail.
- [x] Implement player lock before cache read; retain old /move branch; map all terminal domain errors to stored rejected results, no partial mutation.
- [x] Run new tests plus existing fog/combat tests; typecheck and lint; commit backend increment only.

### Task 3: Pure known-region planner
Files: game/scripts/model/fog_route.gd; game/tests/unit/test_fog_route.gd.
Interface: FogRoute.plan(view,target,snapshot) returns {ok,path,object,error}; passable(view,cell) distinguishes unresolved objects/guard exception.
- [x] Write GUT tests for U wall, islands, unknown adjacent, snapshot no-growth, object adjacent goals, completed objects, guard.
- [x] Run Godot GUT and observe missing planner failure; implement BFS fixed four-neighbor order and stable closest legal object neighbor.
- [x] Rerun GUT and commit planner.

### Task 4: Serial UI runner and navigation lifecycle
Files: game/scripts/ui/pages/fog_map_page.gd, game/scripts/ui/play_screen.gd, game/scripts/model/fog_map_view.gd; tests game/tests/unit/test_fog_autowalk.gd.
Interfaces: map stop_route(), bind_fog(payload), injected transport Callable(method,path,body); runner uses persistent pending-step ledger, route generation and snapshot.
- [x] Write delayed-transport tests proving no concurrent move, 20 repeated clicks dedup, replacement from confirmed pos, hidden response no continuation, uncertain state reconciliation, stale entrance GET guard.
- [x] Run red; implement queue replacement while busy, apply confirmed model then animate, no automatic _on_cell recursion, explicit chest confirmation.
- [x] Run green and existing cave tests; record cancellation and timeout evidence from actual page signals/transport calls.

### Task 5: Integrated evidence and handoff
- [x] Run isolated HTTP concurrency tests with transaction barriers, full backend suite private database, Godot unit suite, typecheck/lint.
- [x] Run real Godot under Xvfb, use its viewport to capture before/mid/arrival/cancel/recovery/unknown/guard images at /workspace/cp_fix_shots/fog_autowalk.
- [x] Document per-counterexample results and exact commands/counts, remaining limitations, backend-first release order without deployment.
- [x] Review diff and commit only explicit source/docs/test paths; preserve unrelated LFS checkout artifacts.

## Execution notes
- Completed locally in isolated worktree; no publishing or deployment.
- See `docs/testing/fog-autowalk-handoff.md` for commands and all 20 evidence cases.
- Full Godot was executed, not green: 366/389 pass, the same 23 failures as untouched baseline (338/361). Targeted 34/34 pass.
- Independent review remains with the parent/owner; execution checkmarks are not release approval.

## Restart and midnight correction (23:27 Beijing review)
- [x] Reproduce node and actual process destruction with old delayed POST; preserve red logs.
- [x] Durable fog-only journal keyed by server/player/map/body/stepId/endpoint, checksum+atomic rename+file/directory fsync. No token in journal. Unavailable durability, corruption, half writes and failed clearing all fail closed.
- [x] Always persist before dispatch; persist terminal+current authority before releasing pending. Restore account slots before entrance GET/new movement; never replay move. Account switching retains old slot, no foreign reconcile.
- [x] Actual separate Godot processes + HTTP barrier: cancellation tombstone rejects old POST, committed-loss accounts one step, process-generated stepIds unique.
- [x] Add stale-day backward GET regression; travelDay only advances. Prove blocked requests with pg_blocking_pids before releasing both older barriers.
- [x] Run direct vitest with explicit private restart database, targeted and full GUT, document exact new counts/remaining platform risks and fixture-only smoke distinction.

Historical 7cde4b5e correction evidence (newer Android work below): backend 130 files / 517 passed (including 3 actual-process tests), targeted GUT 48/48, full GUT 380/403 with exactly the same 23 baseline failures. Standard resource import required before GUT; generated imports restored, no art changes. Android fsync/device behavior and independent final-SHA acceptance remain unverified. See updated handoff and restart-verification-summary.json.

## Incident correction (documentation only, Nov10 00:15 Beijing UTC+8 request)
The historical Task5 blanket full-private claim does not describe the later513 npm run: that run targeted shared5432/xiuxian_test and TRUNCATEd test tables. Earlier512 metadata names private55439 but has no saved preflight identity result and its output pathname was overwritten before this correction. The final517 direct run has an existing preflight SELECT line for xiuxian_fog_restart_test|55439. See docs/testing/fog-autowalk-test-db-incident-2026-11-09.md. Future runs require saved, asserted preflight identity before direct Vitest; never npm test. No new DB tests were executed for this correction.

## Android min24 correction and HUD (Nov10 00:39 Beijing UTC+8)
- [x] Prove original Android24 failure in actual installed Godot app UID10062, not only shell; retain all logs. KVM vCPU creation fails; use official software-emulated AOSP24/35.
- [x] TDD HUD committed/disk-failure visibility without clearing pending; 1 red→green and targeted49/49.
- [x] TDD Android JNI adapter: open failure, fsync exception retained across successful close, close failure, normal descriptor lifecycle.
- [x] Replace only Android external command with existing official JavaClassWrapper + public Os open/fsync/close, no AAR/plugin/global system.
- [x] Actual application UID verifies file+directory sync, known-route movement, killed-process recovery/tombstone and committed-loss/offline recovery; save per-round dedicated55439 database preflight.
- [x] Document exact emulator/package differences and limitations, restore generated metadata, commit local only. No production/owner environment or incident raw logs modified.

Android evidence: actual min24 application UID10062 original toybox red, public Os JNI normal8 moves green; delayed POST/SIGKILL cancellation v2 and committed-loss/API-offline/recovery v4 passed. v4 uses Android headless launch from same UID, not rendered UI acceptance. Scoped GUT53/53,215assertions,8orphans/exit leak warnings. No full backend rerun; historical private517 and original shared513 incident remain distinct. See docs/testing/fog-autowalk-android-validation-2026-11-10.md.

# Tutorial verification — 2026-10-09

This record covers this checkout's tutorial implementation. It distinguishes deterministic source tests, isolated native rehearsal and deployment checks that remain open. See [setup](TUTORIAL_SETUP.md), [research](TUTORIAL_RESEARCH.md) and [test commands](TESTING.md).

## Automated source verification

The final regression sweep passed **23/23 suites**, **267 script compilations with zero failures**, and the **Rojo build** using official Luau 0.741 and the installed Rojo CLI. `git diff --check` passed. Final local bundles/build/logs are in `/tmp/stab-tutorial-final`; the retained tutorial log is [source-tutorial.log](audit-results/2026-10-09-tutorial/source-tutorial.log).

| Production module fixture | Passing tests/groups |
| --- | ---: |
| State/progress/rate limits | 12 |
| Runtime ownership/damage | 15 |
| Reward security/recovery | 26 |
| Tickets/travel | 12 |
| Coordinator/session/security/races | 33 |
| Analytics | 8 |
| Arena construction/fault cleanup | 5 |
| Guidance lifecycle | 1 grouped scenario |
| Controller bridge/lifecycle | 1 grouped scenario |

Existing game-systems, movement, food, projectiles, revolver, trading/security and UI lifecycle suites also pass. Earlier incomplete fixture runs are not counted as final acceptance.

Tutorial fixtures execute the production state, runtime, rewards, tickets, travel, coordinator, analytics, arena, guidance and controller bridge modules. They verify session/target ownership, forged and duplicate requests, range/ray/cadence integration, save ambiguity and retries, inventory publication rollback, replay isolation, reset recovery, broken arena assets, action/loading races, input ownership and cleanup. These are fixture tests, not real Roblox datastore/teleport or physical-device tests.

## Native Studio rehearsal

The harness opens authored place **119874582058419**, universe **9667193329**, and overlays source in an **unsaved** copy. Every source DataStoreService lookup is replaced by `BetaAuditBackend`; profiles use `ProfileStore.Mock`. No publishing or persistent player writes occur. Original scripts/ordinary client startup are disabled and replaced with the isolated test payload. Studio plugins can still emit unrelated editor output.

The authored test place lacks a `ServerStorage.Studs` template. The builder explicitly supplies an offset **Classic ROBLOX test alias**. Passing this rehearsal does not certify the production Studs map, its authored markers, balance or layout.

Native coverage:

- Actual `StabKnife.Stab` and `ThrowKnife.Throw` with native character/NPC geometry and server target registries.
- Invalid displacement rejected; trusted placement does not count as movement.
- Character death/reset retains the current tutorial session/lesson without competitive death credit.
- All 14 lessons and preview completion; temporary food/safe practice damage; no economy or reward entitlement written in preview.
- Native UI layout bounds at 1280×720, 390×760 and 740×320; action auto-advance controls, completion/return states and instance cleanup.

Movement/sprint/slide/reload/heal/revolver progression in this harness uses explicitly test-only server signals. Physical input and full normal client startup remain unverified. Source fixtures separately exercise actual movement, food, revolver and controller paths. Native test completion duration is an automated fixture measurement, not a player's tutorial duration or retention result.

The initial run exposed an initial-target timing race and a thrown-knife fixture failure. Reports are retained rather than discarded. A diagnostic run passed the whole journey; the final harness additionally waits for completed lesson preparation, settles native assembly transforms, separates target ray lanes and verifies the fixture ray reaches the selected registered NPC. Final acceptance uses a rebuilt payload without diagnostic weapon-source edits.

Reports: [audit-results/2026-10-09-tutorial](audit-results/2026-10-09-tutorial). `Started=true` alone is insufficient: require structured `Result.AllPassed=true`, expected players, no fatal/runtime errors and every required assertion passing.

**Final rebuilt rehearsal passed:** one native client, ready server startup, all **11 server/scenario assertions** and all **10 native UI assertions**, all **14 lessons completed**, and **zero captured runtime errors**. The [final native report](audit-results/2026-10-09-tutorial/native-final.json) lists the exact assertions, synthetic actions and map fixture. The production source was tested without the temporary diagnostic prints used in attempt 3. Rewardless preview left XP, Cash, inventory and tutorial entitlement unchanged.

## Published and device checks still required

The tutorial place has **not** been created/published by this task; `TutorialPlaceId` remains **0**. Live invitations stay unavailable until configuration is complete. No live reserved-server round trip, MemoryStore claim or persistent profile handoff has been tested. Roblox does not support actual TeleportService playtesting in Studio. [Official teleport documentation](https://create.roblox.com/docs/projects/teleport)

Run the setup guide's published acceptance matrix before release: exact once-only rewards across reconnects, replay, closed original server fallback, backend/late teleport failures, direct/foreign admission rejection, high latency, and real keyboard/touch/controller journeys. The tutorial controller bridge does not certify broader existing console gameplay support. Native bounds assertions also do not replace reviewing readability, safe areas and control overlap on actual devices.

Analytics delivery/dashboard aggregation has not been verified in published servers. Observe real first-time players before claiming improved retention or optimal difficulty/rewards. Missing/corrupt data recovery and platform service outages remain operational concerns; the system provides bounded retries and durable entitlement recovery rather than promising that external services never fail.

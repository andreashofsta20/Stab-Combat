# Stab-Combat beta audit — 8 October 2026

Assessment of the local working tree, including existing uncommitted changes. No live player data was accessed. The user subsequently authorized implementation of the audit tasks and supplied place **119874582058419** (universe **9667193329**). Native tests used an unsaved source overlay of that place, with either isolated in-memory stores/ProfileStore.Mock or uniquely named disposable real DataStores. No place was saved or published.

Current implementation status: **22/22 suites pass, all 242 source/test/dependency scripts compile, the Rojo build passes, and git diff --check passes.** Durable escrow/recovery, saved-data quarantine, VIP reconciliation, receipt archival, startup timeouts, movement admission, spawn scoring, phased BR, accessibility settings, bounded statistics/metrics are implemented. Practice mode and explicit texture/image preloading were removed at the user’s request. Native and hosted CI evidence, including unsuccessful attempts, is recorded in section M.

**Sections A–L retain the original audit and review history.** Their statements that features are missing or proposed describe that earlier state. The authorized implementation supersedes those statements; its current acceptance evidence and remaining limitations belong in section M. Native asset permissions, real backend interruption, high-ping gameplay and long-session device performance require their own evidence and must not be inferred from fixture results.

## A. Repository overview

Rojo maps shared configuration/math into ReplicatedStorage, server systems and ProfileStore into ServerScriptService, and client/character controllers into StarterPlayer. The source inventory contains 203 scripts/modules and 25 client-to-server event handlers; no OnServerInvoke assignment was found. Wally vendors ProfileStore 1.0.3. Many remotes, GUI templates, maps, tools and sounds must already exist in the Studio place.

StartupLoader and StartupService launch groups and publish readiness. GameLoop handles intermission/voting; MainGame coordinates placement, countdown, combat membership, deaths, rewards and cleanup. Combat handlers own damage, ammunition and eligibility; clients handle input, prediction, cameras and effects. Server-created Value objects replicate inventory/stats; ProfileManager snapshots them into session-locked profiles. Trading has separate request/session/validation modules.

Earlier documentation is historical evidence, not current verification. The original checkout did not reproduce the former all-green test counts: FoodConfig specifies a one-second cooldown while older documentation/tests expected two. The fixtures now use the configured cooldown and all suites pass. Quest persistence and local trade rollback have already improved beyond some older review notes. DataConfig now names PlayerData_v1.0.2_MainData and disables legacy migration.

## B. Feature coverage

“Verified” below means the relevant automated checks passed, not native Roblox verification.

| Feature | Current status | Evidence | Missing work | Priority |
| --- | --- | --- | --- | --- |
| Revolver ammo, cooldown, reload | Verified in fixtures; presentation suite restored | CombatHandler/HandleRevolver, RevolverState; game-systems and revolver-presentation suites | Native latency tests | High |
| Head/body hits and solid cover | Verified in fixtures | RevolverRaycast; headshot-damage suite | Native geometry/animation checks | High |
| Rewind and shot validation | Implemented; boundary checks covered | RevolverHitHistory, RevolverMath, HandleRevolver | Multiplayer jitter/load measurements | High |
| Throwing knives | Implemented, immediate damage | ThrowKnife; ProjectileMath; knife-projectiles tests | Decide intended travel semantics | Medium |
| Stabbing | Implemented, broad multi-target volume | StabKnife; KnifeConfig; PlayerHitbox | Competitive range/playtest review | Medium |
| Sprint, crouch, slide | Slide fixtures verified | SlideController, SlideMotion, MovementConfig | Native collision and movement authority | High |
| FFA round/respawn | Implemented; round and full game-systems checks pass | MainGame, GameLoop, SpawnMap; sections J–K | Run Studio matrix | High |
| Spawn fairness | Partially implemented: random respawns/shuffled initial spawns | SpawnMap.RespawnPlayer/PlacePlayers | Enemy-distance/visibility scoring proposal | Medium |
| BR elimination and zone | Implemented | GameModes, GameZone, MainGame | Geometry, simultaneous deaths, native final-circle checks | High |
| BR phase schedule | Missing; optional pacing change | GameZone uses continuous shrink | Approve phased design before implementation | Medium |
| Voting | Verified in fixtures | VotingHandler; voting-security suite | Native presentation | Low |
| Killcam/spectate | Verified in fixtures; 51 tests pass | SpectateHandler, DeathSpectateTransition | Native camera/replication checks | High |
| Ragdolls | Verified in fixtures | RagdollService/Rig; ragdolls suite | Native rig/physics cost | Medium |
| Player profiles/session release | Implemented | ProfileManager, OnJoined, vendored ProfileStore | Backend failure/shutdown tests | High |
| Inventory hydration | Partially validated | OnJoined, InventoryHandler | Corrupt/duplicate legacy row policy and migration tests | High |
| Trading input and local rollback | Verified in fixtures | TradeValidator; services-security suite | Durable cross-profile recovery | High |
| Receipt idempotency | Implemented; full game-systems suite passes | PurchaseHandler, ConfirmPurchase, VIPService | Native backend retry tests | High |
| Daily shop/rewards/quests | Fixtures pass; top-three scoring fixed | DailyShopHandler, DailyRewards, QuestsHandler; sections J–K | Verify rewards in Studio | High |
| VIP | Reward expiry fixed and regression-tested | VIPService, GameReward | Native expiry checks; persisted authority decision in section D | Medium |
| Leaderboards | Implemented, bounded caches/coalescing | LeaderboardsHandler | Traffic/backend profiling | Medium |
| Settings/keybinds/admin | Implemented, server validation | SettingsHandler, KeyBindHandler, Admin/Main | Studio privileges and persistence checks | Medium |
| Profile viewer | Thumbnail race/failure and offline inventory fixes pass fixtures | GetPlayerInfo, ProfileViewHandler, ViewProfile | Native rendering and offline backend checks | Medium |
| Trade UI lifecycle | Owner teardown fixed and regression-tested | TradePlayerList | Native repeated GUI replacement checks | Medium |
| First-person weapons/audio/effects | Substantial implementation; multiple suites pass | WeaponViewmodel, RevolverEffects, RemoteWeaponAudio | Real assets, R6 fit, mobile visibility | Medium |
| Accessibility | Partial configuration | UIAnimationConfig, CursorConfig, keybind modules | Verify player-facing reduced-effects/crosshair options | Low |
| Competitive statistics/ranked | Partial lifetime and round stats; no ranked system found | MainGame, ProfileManager, GameModes | Mode/weapon stats optional; ranked deferred | Low |
| CI and native performance evidence | Portable runner passes; workflow added; native measurements absent | scripts/test-all.py; .github/workflows/verify.yml; TESTING.md | First hosted CI run and Studio measurements | High |

Paths in this table are module names under src; detailed actionable references follow.

## C. Confirmed defects

| Problem and current implementation | Evidence/root cause | Impact | Priority | Recommended fix | Difficulty / regression risk | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| Fixed locally: forfeiting FFA awarded top-three quest progress | [MainGame](src/server/Game/MainGame.luau): LeaveRound assigns placement 0; the former reward condition accepted every placement <=3 | Previously, leaving the fight still advanced TOP3_FINISHES | High; fixed | Implemented: require non-forfeited placement 1–3 | Low / Low | Forfeit and legitimate podium regressions passed; native Studio verification remains |
| Fixed locally: trade UI retained listeners after destruction | [TradePlayerList](src/PlayerClient/TradePlayerList.luau): former refresh loop and global signals lacked owner teardown | Old UI remained referenced | Medium; fixed | Idempotent Destroy disconnects global and row hooks, cancels refresh/cooldown tasks and destroys detached placeholders | Low / Medium | Repeated GUI destruction verifies zero owned listeners and no resumed refresh work |
| Fixed locally: profile viewer errored or rendered stale data | [ViewProfile](src/PlayerClient/ViewProfile.luau): former inline thumbnail calls yielded and could return nil | Avatar failure interrupted rendering; old requests could overwrite newer views | Medium; fixed | Synchronous data rendering; one deferred portrait request, safe fallback, generation guard and owner cleanup | Low / Medium | Failed/nil/delayed thumbnails, switching, closing and destruction pass; history shares one portrait |
| Fixed locally: VIP kill bonuses survived expiry | [GameReward](src/server/Game/GameReward.luau): former checks used HasVIP alone | Expired sessions kept XP/cash bonuses | Medium; fixed | Validate server-written VIPExpiresAt at reward time, including after yielding pass ownership lookup; clear expired HasVIP | Low / Low | Clock crossing expiry and invalid expiry values pass; active benefits preserved |
| Fixed locally: offline profile inventory was empty | [GetPlayerInfo](src/server/ServicesHandler/GetPlayerInfo.luau): former inventory path only scanned connected players | Saved knives were absent from offline views | Low; fixed | AllInfo returns stats and validated inventory together; ProfileViewHandler preserves both, avoids caching unavailable results; UI shows loading/unavailable state | Low / Medium | One saved-profile read, malformed display rows, unavailable data and remote cache tests pass |
| Fixed locally: five regression suites failed | See section K | Later checks were blocked by outdated fixtures | High; fixed | Updated dependencies, activation/lazy-render expectations and configured cooldown; added portable runner and CI | Low / Low | All 21 suites pass locally; hosted CI result pending |

Reproduced before editing: an FFA forfeiter received TOP3_FINISHES=1 and ROUNDS_PLAYED=1. A separate production-module fixture destroyed the trade GUI and still counted PlayerAdded=1, another player's XP observer=1, and local XP observers=2. This proves retained ownership on GUI teardown; it does not prove an unbounded leak during ordinary menu hiding or measure retained bytes.

## D. Unverified risks

| Concern | Evidence/current behavior | Impact | Priority | Proposed solution | Difficulty / regression risk | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| Trade persistence is not a durable transaction | TradeValidator.ExecuteTrade commits both inventories without yielding, but TradeManager completes before any coordinated durable record; profiles save independently | Crash after one participant saves can duplicate or lose stock | High | Proposed durable trade journal and idempotent recovery in section L; design decision remains open, and two sequential saves alone are insufficient | High / High | Fault injection after every save/commit stage, then reload both profiles |
| Movement remains a trust boundary | Client Animation/SlideController drive movement; weapon checks use replicated roots/heads. No server displacement authority/validation found | Speed/teleport/noclip can undermine otherwise valid distance checks | High | First inspect native place authority settings; design latency-aware movement admission with authorized teleport exemptions | High / High | Private two-client abuse tests plus high-ping false-positive tests |
| Saved-value validation is uneven | OnJoined trusts portions of knife/emote metadata; ProfileStore reconciliation supplies defaults, not a full schema | Corrupt legacy records can fail hydration or restore inconsistent inventory | High | Define repair/quarantine/migration policy before altering saved data | Medium / High | Invalid types, finite bounds, duplicate names, unknown legacy items |
| Startup depends on all configured groups becoming ready | StartupService.AwaitReady; required ServicesHandler group includes noncombat systems | Missing/yielding Studio asset can leave the game waiting | Medium | Classify required/optional services and bounded failure UI; retain fail-closed data/combat readiness | Medium / Medium | Remove each required asset and confirm explicit failure/recovery |
| VIP has two persisted expiry representations | VIPService dedicated store; OnJoined uses profile expiry/cache | Interrupted synchronization or historical profiles may disagree | Medium | Choose authority and reconciliation policy before migration | Medium / High | Purchase save interruption and fast cross-server rejoin |
| Receipt marker tables grow with purchases | ProcessedPurchases in profile and VIP store | Long-term record size growth, not demonstrated current exhaustion | Low | Measure serialized sizes; design archival preserving deduplication | Medium / High | Large histories and replayed receipts after archival |

Movement risk depends on Studio settings absent from the checkout. Roblox explains why client-owned physics can defeat positional trust in its [network ownership security guidance](https://create.roblox.com/docs/scripting/security/network-ownership). Trade crash consequences are inferred from independent persistence; no live crash/duplication experiment was performed. Roblox's [DataStore API](https://create.roblox.com/docs/cloud-services/data-stores) updates individual keys.

## E. Competitive gameplay analysis

At 100 HP, the configured revolver has three rounds, 34 body damage, 70 head damage, 350 ms shot spacing and a 1600 ms reload. Three body hits kill in 0.70 s from the first shot; head+body kills in 0.35 s. Missing once in a body-only cylinder forces a reload. Preserve these values pending playtests. Alternatives for controlled tests: keep damage and try a 1400 ms reload for lower miss punishment, or retain reload and try 400 ms spacing for more tracking time. Neither alternative is implemented.

Knives resolve a 350-stud server ray immediately. With speed 500–750 and a two-second maximum flight, every charge reaches the distance cap; charge currently changes visual speed, not range/damage. At 350 studs the visual takes approximately 0.47–0.70 s, after damage was already resolved. Retain this implementation for the first stability pass. For a later approved competitive prototype, true bounded swept projectiles better support predictive throwing; compare latency/reconciliation and server cost before adopting them. Do not add gravity or change speeds without explicit tuning approval.

Stabs use a 12×8×8 forward box against a 6×7.5×6 proxy and can damage multiple targets. With aligned avatars the proxy extends apparent reach to roughly 15 studs; the extra radial check permits up to 20 but does not itself expand the overlap box. This is generous for precision combat. Review with visible debug geometry before proposing a narrower configurable profile.

Movement already has walk/run/crouch speeds 16/32/8, slide speed 60, duration 0.8 s, cooldown 1 s, bounded force, steering, slope/step checks and death cleanup. Passing math/fixture tests cannot establish native collision or anti-cheat protection.

FFA respawns use random authored markers rather than enemy-aware scoring. A future bounded scorer can sample a few markers using nearby enemy distance, one visibility ray per candidate and recent-use penalty; avoid full-map scans. BR already has elimination, circular XZ membership, continuous shrinking and final damage to everyone. Phase pacing is optional. Check the Studio zone mesh against its circular damage model and validate inaccessible final geometry, lag, draws and simultaneous deaths. Keep equal loadouts.

Comparison is limited to public behavior, not competitors' private code or measured FPS: [Murder Mystery 2](https://www.roblox.com/games/142823291/Murder-Mystery-2) emphasizes asymmetric roles and knife collection/trading; Stab-Combat's direct FFA/BR identity should stay distinct. [RIVALS](https://www.roblox.com/games/17625359962/RIVALS) advertises short 1v1–5v5 duels, contracts and streaks: useful references for clear combat feedback and pacing, not a reason to add many weapons. [Riot's VALORANT networking explanation](https://www.riotgames.com/en/news/peeking-valorants-netcode) provides a benchmark for validated authority and responsive prediction; its engine/tick-rate choices are not directly transferable to Roblox.

## F. Security analysis

All 25 source event entry points were inventoried. Combat uses finite geometry, eligibility, rate limits and server damage. Revolvers additionally use session/sequence validation, bounded timestamps/rewind, owned ammo/reload and server cover checks. Food compares the exact registered tool and owns health/uses. Voting uses current options and server weights. Inventory selection checks catalog names and owned quantity. Trading checks action, quantity, ownership, readiness and confirmation with local rollback. Shop/reward prices and grants are server-owned. Admin authorization precedes command dispatch and limits arguments and outstanding commands.

Profile views have a one-second requester limit, four-token shared burst/refill, two concurrent offline reads and a bounded cache. Leaderboard requests serve cached data. No arbitrary client damage/currency grant, dynamic client-controlled require/loadstring, or demonstrated single-packet server-crash path was found in the reviewed code. This is not a guarantee against all abuse. Movement and durable trade recovery are the largest outstanding boundaries. Follow [Roblox remote validation guidance](https://create.roblox.com/docs/scripting/security/client-server-boundary).

## G. Performance analysis

Existing bounds are useful: 16 historical samples/player, 32 five-second corpses, 48 knife visuals, 64 revolver tracers, 24 bullet marks, bounded audio/feedback pools and event-driven spectator/round UI.

Profiling candidates, not measured bottlenecks:

- Revolver poses accept up to 20 updates/player/second and broadcast to everyone, including lobby presentation. With 20 active senders and 20 recipients, that is up to 8,000 logical recipient deliveries/second before engine transport behavior. Consider audience/distance filtering only after measuring.
- Leaderboard stat-change updates use a 0.25-second coalescing delay and send up to 150 rows each time. This bounds queued updates, not all broadcasts: `UpdatePlayer` and `refreshCache` call `Broadcast` directly, so joins and refreshes can add traffic. Measure both paths; subscribe only visible viewers or send deltas if profiling justifies it.
- History samples geometry at 30 Hz and shifts a bounded array; measure allocations before replacing it with a ring buffer.
- Weapon templates may contain expensive Studio hierarchies/scripts; server equip still clones them. A source build cannot measure asset or avatar physics costs.
- Profile rendering previously repeated yielding thumbnail lookups; it now shares one deferred image request across the view and cancels stale work. Native rendering cost still needs measurement.

Run 2-player, 8-player and intended-maximum-population scenarios; include 30+ respawns, weapon swaps, simultaneous deaths, shop/inventory/spinner use and spectator changes. Collect client/server frame-time percentiles, network traffic, LuaHeap, InstanceCount, PlaceScriptMemory and backend budgets before/after a 30–60 minute session. Compare settled counts after effects expire. Suggested device targets, not measurements: 16.7 ms/frame at 60 FPS or 33.3 ms at 30 FPS. Use [Roblox profiling tools](https://create.roblox.com/docs/performance-optimization/identify) and [memory/performance guidance](https://create.roblox.com/docs/performance-optimization/improve).

## H. Missing features

Essential beta evidence/work: first hosted CI run, native multiplayer/latency testing, durable trade recovery decision, movement authority assessment, asset validation, performance baselines and actionable rejection/save-error metrics. Local regression runs are now green.

Optional: bounded spawn scoring, phased BR pacing, mode/weapon-specific aggregated statistics, player-facing accessibility settings where missing, and a practice mode. Ranked matchmaking needs population and integrity evidence first. No new weapons, powers, loot economy or persistent schema changes are justified by this audit.

## I. Prioritized roadmap

1. **Completed locally:** correct invalid top-three quest credit; preserve existing reward policy otherwise. Studio verification remains.
2. **Completed locally:** repair the five stale test suites and add a portable runner plus pinned-tool CI workflow. The hosted workflow must still run.
3. **Completed locally:** fix trade GUI teardown, profile request cancellation, expiry-aware VIP rewards and offline inventory, with focused regressions.
4. **Next architecture decision:** approve durable trade recovery design in section L. Inspect native movement authority and define migration/fault-injection requirements before changing enforcement or persistence.
5. Validate combat, round interruption/death/respawn, BR final circles and spawn fairness in Studio.
6. Profile actual assets/devices, then optimize identified costs and add limited UX improvements.

## J. First implementation task

Completed locally: corrected top-three eligibility in MainGame.ApplyRoundRewards to require a non-forfeited placement in the inclusive range 1–3. Added actual-round regression cases for an FFA player returning to the lobby and for legitimate placements. Added an optional literal test-name filter to the game-systems runner so round tests can execute independently of known unrelated fixture failures. This changes no remote protocol, weapon balance or persisted schema.

Historical baseline verification before the implementation pass: Luau 0.741 compiled all 229 source/test/dependency scripts; Rojo build and git diff --check passed. Existing PowerShell bundle construction was mirrored in a temporary Python runner because PowerShell was unavailable. Corrected baseline harness result: **16/21 suites passed**. Failures began at client-ui-lifecycle (missing script/UITransitions fixture), daily-shop (fixture did not call new explicit Open), death-spectate (UITransitions fixture), game-systems (two-second food expectation versus one-second config), and revolver-presentation (ContentProvider fixture). These blocked later checks, rather than demonstrating that all corresponding production features failed. An initial temporary harness omitted two support modules; that harness error was corrected before the baseline result. **All five suites now pass; see section K.**

Native rendering, physics, asset permissions, multiplayer latency, DataStore outages and long-session performance were not tested. Compilation is syntax verification, not Roblox-aware static type analysis.

### Completed implementation and verification

- **Problem and root cause:** FFA players returning to the lobby receive placement zero. The previous `placement <= 3` condition incorrectly granted top-three quest progress to these forfeits.
- **Implementation:** `src/server/Game/MainGame.luau` now requires a non-forfeited placement from 1 through 3. Existing participation rewards and the user's game-mode/history changes are preserved.
- **Other files modified:** `tests/game-systems.spec.luau` adds two complete-round regressions and optional literal name filtering, with a failure when no tests match. `scripts/test-game-systems.ps1` accepts `-TestFilter` and encodes its text as UTF-8 byte values for the generated Luau invocation. This report records the audit.
- **Tests executed and results:** The new forfeit regression failed against the original implementation (expected no top-three credit, received one). After the fix, both new regressions and all **19 round-related checks passed**. An unmatched filter correctly failed. All **229 scripts compiled**, the **Rojo build passed**, and **git diff --check passed**. PowerShell is unavailable here; executable Luau bundles mirroring its construction were used, so the PowerShell entry point itself remains untested locally. The five baseline failures were subsequently resolved in section K.
- **Remaining risks:** Static inspection cannot establish exploit resistance under live load or stable long-session memory. Trade durability, movement authority and the other findings above still require follow-up. No weapon balance, remote protocol or persistence schema changed.
- **Roblox Studio verification needed:** In a multiplayer FFA session, return one player to the lobby during the round, finish the round, and verify that player's top-three quest progress does not increase. Verify actual placements 1–3 still receive one credit and normal participation rewards remain intact.
- **Suggested next task at that stage:** Repair fixtures and the remaining confirmed defects. This work is now complete locally; the current next steps are in sections I and L.

On a machine with PowerShell and Luau, run the focused round checks with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-game-systems.ps1 -LuauPath "C:\path\luau.exe" -TestFilter "round"
```

## K. Implementation status and independent verification

The source changes and fixtures described in section C were already present when this review began. The review checked those implementations and reran the existing portable runner. It does not claim to have recreated the historical red-test baseline or executed Roblox Studio.

| Completed item | Current implementation checked | Regression evidence |
| --- | --- | --- |
| Forfeit quest eligibility | `MainGame.ApplyRoundRewards` requires `not data.forfeited` and placement 1–3 | Complete-round forfeit and legitimate podium cases in `game-systems` |
| Trade GUI teardown | `TradePlayerList.Destroy` owns global subscriptions, per-row subscriptions, refresh work, cooldown tasks and detached placeholders | Removal, level-gate changes and repeated GUI destruction in `client-ui-lifecycle` |
| Profile portrait lifecycle | `ViewProfile` defers one protected thumbnail request, shares the result across history rows, cancels prior work and checks the view generation | Nil/error/delayed thumbnails, profile replacement, close and destruction in `client-ui-lifecycle` |
| VIP reward expiry | `GameReward` checks a finite future server expiry when awarding a kill bonus, after a potentially yielding XP-pass lookup | Active/expired/invalid expiry and expiry during ownership lookup in `game-systems` |
| Offline profile inventory | `GetPlayerInfo.AllInfo` returns both response sections; saved display rows are checked without modifying the source data; `ProfileViewHandler` excludes loading/unavailable responses from cache | Saved inventory, malformed display rows, failed reads and cache retries in `game-systems` and `services-security` |
| Fixture repair and portable verification | Updated dependency mocks, explicit daily-shop activation, lazy presentation expectations and configured food cooldown; `test-all.py` adapts the existing PowerShell bundles | All 21 suites below pass |

### Reproduced verification on 8 October 2026

| Suite | Passing checks reported by its runner |
| --- | ---: |
| case-viewport | 15 |
| client-ui-lifecycle | 159 |
| combat-feedback | 16 |
| daily-shop | 31 |
| death-spectate | 51 |
| first-person-camera | 18 |
| game-systems | 203 |
| headshot-damage | 34 |
| knife-projectiles | 8 |
| knife-viewmodel | 28 |
| movement-slide | 15 |
| ragdolls | 16 |
| remote-weapon-audio | 29 |
| revolver-presentation | 256 |
| revolver-tool-physics | 14 |
| round-hud | 7 |
| services-security | 26 |
| tool-equip | 15 |
| voting-security | 19 |
| weapon-asset-warmup | 11 |
| weapon-inspect | 20 |

All **21 suites passed**, all **229 source/test/dependency scripts compiled**, and the **Rojo build passed**. The source inventory still contains **203 scripts/modules**, with **25 `OnServerEvent` handlers** and no `OnServerInvoke` assignment found. Per-suite numbers mix tests and individual checks; they do not measure native engine coverage.

Exact local command, using the existing Luau 0.741 binaries and pinned Rojo installation:

```sh
python3 scripts/test-all.py \
  --luau /private/tmp/stab-luau-0.741/luau \
  --compile /private/tmp/stab-luau-0.741/luau-compile \
  --rojo /Users/52hofand/.aftman/tool-storage/rojo-rbx/rojo/7.7.0-rc.1/rojo \
  --output-dir /private/tmp/stab-beta-audit-review-2026-10-08
```

Generated bundles, per-suite logs and `Stab-Combat.rbxlx` were retained in the output directory for this session. The portable command is documented in [TESTING.md](TESTING.md); use tool paths installed on the target machine.

The Windows download digests in `.github/workflows/verify.yml` match the published [Luau 0.741 assets](https://github.com/luau-lang/luau/releases/expanded_assets/0.741) and [Rojo 7.7.0-rc.1 assets](https://github.com/rojo-rbx/rojo/releases/expanded_assets/v7.7.0-rc.1). This validates the configured digest values, not a hosted workflow execution. PowerShell is unavailable locally, so its native entry points remain unexecuted in this review.

Whole-tree `git diff --check` currently reports ten mixed-indentation lines in `src/Modules/KnifeRevAccesoryCframe.luau` (132–135 and 140–145) and one trailing-space line in `src/Modules/KnivesInfo.luau` (79). These were present before this review. The passing historical whitespace check in section J must not be used as evidence for the current working tree.

### Interpretation of the remaining findings

- **Trade durability is open.** `TradeValidator.ExecuteTrade` protects a same-server commit with local rollback; `TradeManager.ExecuteTrade` then completes the session without a durable journal. `ProfileManager.SaveProfile` queues a save. Neither local rollback nor a successful `Save()` call establishes that both player records have been persisted.
- **Movement authority is open.** Corpse physics uses server ownership, and revolver history resets across large displacement. Those mechanisms do not validate a living player's movement. The repository cannot establish the native place's authority settings. Roblox's [network ownership guidance](https://create.roblox.com/docs/scripting/security/network-ownership) supports the concern and the need to account for latency and authorized teleports.
- **Saved-data policy is open.** Knife/emote hydration still consumes row fields without comprehensive type, bound or duplicate checks. Revolver hydration has partial validation. `ProfileManager` already guards serialization with `DataReady`, which protects against overwriting saved inventory with incomplete hydration; that guard does not repair invalid records.
- **Startup failure handling is partial.** `StartupService` exposes pending/failed group attributes, and client fixtures cover an unavailable state. `AwaitReady` still waits indefinitely for all configured groups. Follow-up must address optional dependencies and recovery as well as preserve the existing diagnostics.
- **VIP persistence authority is open.** The dedicated VIP store grants purchased duration, while profile hydration initializes the cache and attributes from the profile expiry. Reward-time expiry validation fixes the stale bonus but cannot reconcile disagreement between these records.
- **Receipt growth is a planning risk.** Idempotency markers exist in the profile and VIP store; no measured size limit failure was reproduced. Measure growth before choosing archival rules that could weaken replay protection.

## L. Remaining work and trade-recovery proposal

The proposal below is **not implemented or approved**. It makes roadmap item 4 concrete for review. It changes persistence and inventory coordination, so it needs an explicit design decision and fault-injection evidence before deployment.

### Durable trade proposal

Roblox's [DataStore API](https://create.roblox.com/docs/cloud-services/data-stores) updates entries by key. The need for recovery here is an inference from this project's independently saved player records. A journal must coordinate those records; it cannot make two separate profile saves atomic by itself.

1. **Write immutable intent first.** Give each trade a unique transaction ID and a journal record containing the schema version, participant IDs and frozen item types/names/quantities. Persist that intent before reserving either player's inventory. Validate catalog/ownership rules at admission and prevent simultaneous transactions over the same inventory.
2. **Reserve outgoing stock durably.** Under each participant's active ProfileStore session, debit outgoing stock from usable inventory and record an escrow reservation keyed by transaction ID in the same profile record. Confirm both reservations in successfully saved data. All inventory writers—trading, purchases, rewards and inventory hydration—must honor the reservation/coordination rules, and `OnSave` must preserve them when serializing Value objects. This cannot be implemented safely by editing only `TradeValidator`.
3. **Persist one irrevocable decision.** Use conditional `UpdateAsync` transitions for a journal state machine: `PREPARING → COMMIT_DECIDED` or `PREPARING → ABORT_DECIDED`, followed by `COMPLETE` after settlement. Commit only after both durable reservations are confirmed. A timeout or ambiguous write result must leave the trade pending until the durable decision is read; it must not trigger a guessed refund. A durable worker lease/fencing rule must prevent stale coordinators from choosing a decision after takeover.
4. **Settle each profile idempotently.** After a committed decision, credit the frozen incoming stock once and persist its applied marker together with the inventory; outgoing stock remains consumed from escrow. After an aborted decision, restore the reserved outgoing stock once and persist the refund marker together with the inventory. Recovery checks these markers rather than reapplying quantities. Confirm the resulting profile save before treating that participant as settled.
5. **Recover before exposing inventory.** Inspect pending transaction references while loading a profile and before setting `DataReady`. Recover only through the participant's owned ProfileStore session, including after a cross-server rejoin. A committed trade must finish even if the other participant is offline; settlement must not require both people to reconnect together. Unresolved preparations need a fenced coordinator decision; backend errors keep affected stock unavailable and expose a retryable pending state.
6. **Finish after both acknowledgements.** Mark the journal complete only after both settlements are durable. Client success must represent that result; pending completion needs a distinct presentation. Retain enough journal/marker history to reject replay after restarts, and define record-size limits and archival ordering before deleting recovery evidence.

Before implementation, settle: additive profile/journal schema and versioning; how every inventory writer coordinates reservations; ownership/lease takeover and save acknowledgements; pending-trade UX and retry policy; retention, metrics and deployment/migration procedure. Use the existing `ConfirmPurchase`/`LastSavedData` approach as evidence that a queued save is not an acknowledgement, but design trade-specific acknowledgement checks for both reservations and settlement.

Required fault-injection acceptance cases:

- Terminate or fail writes before/after intent creation, each reservation save, decision persistence, each settlement save, acknowledgement and cleanup; reload both profiles in both orders and with one participant remaining offline.
- Replay confirmations and recovery repeatedly; run competing/stale coordinators and cross-server rejoin/session-loss scenarios. Stock must be conserved and each transaction delta applied at most once.
- Return ambiguous write failures, stale reads, throttling and prolonged outages. An unknown decision must keep reserved stock pending; recovery must not invent a second grant or refund.
- Attempt shop grants, reward grants, equip/use, another trade and shutdown saves during preparation/recovery. Unreserved items and unrelated stats must not be overwritten, and reserved stock must not be spent.
- Exercise empty offers, duplicate offer rows, malformed terms, quantity overflow, abort before the second reservation and a committed trade with one settlement delayed. Bound retries and journal/profile sizes while retaining deduplication.

### Native Studio verification matrix

All cases below remain **not run**. Use a separate test experience/data namespace for backend failure work; Roblox documents that enabled Studio API access can reach the experience's real stores in its [DataStore guidance](https://create.roblox.com/docs/cloud-services/data-stores).

| Area | Scenario | Acceptance evidence |
| --- | --- | --- |
| Startup/assets | Valid place, then remove or delay each required remote, GUI template, map, tool, animation or sound | Record required/optional classification; required failures show an actionable state and keep data/combat closed; valid dependencies become ready |
| FFA rewards | Return a player to the lobby, finish the round, then repeat for legitimate placements 1–3 | No forfeiter top-three credit; eligible podium credit exactly once; existing participation policy preserved |
| Combat/latency | Two clients with baseline and induced latency/jitter; body/head hits, cover, repeated fire, reload and weapon swaps | Server ammo/damage agree with expected rules; record rejected shots and reconciliation; no damage through solid cover |
| Movement authority | Record place authority settings; attempt speed changes, teleport and noclip alongside valid sprint/slide/jump and server teleports | Establish the actual trust boundary and a latency baseline before selecting enforcement; distinguish valid teleports/respawns from abuse |
| Round lifecycle | Death, respawn, leave/rejoin, late join, missing character and simultaneous final deaths during countdown/combat/cleanup | One death/reward per event, correct membership/placement, no stale callbacks in a new round |
| BR zone/spawns | Zone mesh against XZ damage circle; final circle on each map; simultaneous elimination and random authored respawns | Defined draw/winner outcome; reachable final geometry; no incorrect zone damage; document spawn visibility/distance problems |
| Trade UI | Repeated player-list replacement/destruction, joins/leaves, level-gate transitions and send cooldowns | Current rows update correctly; removed owners have no listeners/tasks; no duplicate requests |
| Profiles | Connected/offline views; failed/delayed portraits; rapid switching and closing; inventory/history templates including `Divider.GameMode` | Correct inventory/history and mode labels; no stale portrait; loading/unavailable states remain usable |
| VIP/receipts | Expiry during an active session; receipt retry; interrupted VIP synchronization; fast cross-server rejoin | Expired rewards remain unboosted; receipt grant once; document expiry disagreement until authority policy is implemented |
| Profiles/backend | Session handover, interrupted hydration, shutdown, throttling and unavailable backend | No temporary defaults saved over loaded stock; bounded failure/retry presentation; saved progress and clean session release |
| Presentation/devices | Real R6 rigs, first-person skins, mobile/gamepad, audio permissions, spectate and ragdolls | Visible/aligned weapons, working input, expected sound/effects and stable camera transitions |
| Performance | 2 players, 8 players and intended maximum; 30+ respawns and 30–60 minutes of mixed combat/UI activity | Record frame-time percentiles, traffic, LuaHeap, InstanceCount, PlaceScriptMemory and backend budgets; compare settled counts after effects expire |

### Completion order

1. Obtain the first hosted Windows CI result, including native PowerShell execution, and address the current whitespace check findings.
2. Decide the durable trade design and saved-data/VIP authority policies; record native movement authority settings. Add migration and fault-injection requirements before implementation.
3. Run the native matrix, starting with two-client startup, combat and round lifecycle checks; record actual results and reproducible failures.
4. Establish population/device performance baselines and bounded rejection/save/recovery diagnostics, then prioritize measured costs.
5. Revisit optional spawn scoring, BR phases, accessibility and practice features after stability evidence. Weapon tuning and persistent economy changes remain separate decisions.


## M. Authorized implementation and acceptance evidence

The user authorized the audit tasks and provided place 119874582058419, universe 9667193329. The final scope excludes practice mode and explicit shop/weapon-effect texture preloading. Ranked matchmaking and the explicitly deferred weapon balance experiments remain deferred. Existing working-tree changes were preserved.

| Audit task | Final implementation | Acceptance evidence / remaining work |
| --- | --- | --- |
| Invalid FFA podium quest credit | Only non-forfeited placements 1–3 receive TOP3_FINISHES | Forfeit and legitimate podium regressions pass; native FFA smoke passed on the earlier mock run |
| Test/CI failures | Portable runner mirrors PowerShell bundles; pinned tools and Windows workflow | 22/22 suites, 242 script compilations, Rojo and whitespace checks pass; hosted Windows workflow passed on the initial implementation snapshot |
| Trade UI/profile viewer/VIP reward defects | Owner teardown, deferred portraits with generation guards, validated offline inventory and expiry-aware bonuses | UI lifecycle and service regressions pass, including failed/delayed portraits and expired rewards |
| Durable trades | Immutable UpdateAsync intent, leased preparation, saved escrow, irreversible commit/abort, idempotent settlement and acknowledgement | 37 persistence/security tests include failures before/after ten durable stages, replay, offline participants, stale coordinator fencing and recovered ambiguous commits; native trade completed with both mock and real stores |
| Saved inventory validation | Catalog metadata is authoritative; malformed/duplicate/unknown rows are quarantined without summing stock; critical currency/receipt/recovery corruption fails hydration | Schema regressions pass; quarantined rows are bounded and retained as JSON-safe evidence |
| VIP authority | Dedicated VIP record is canonical; import profile expiry only if no dedicated record exists | Bad authoritative records fail hydration; no stale profile overwrite; persistence and historical-archive regression checks pass |
| Receipt growth/replay | Immutable per-receipt archive acknowledged before pruning; bounded maintenance of eight profile and eight VIP markers/player/minute | Archive outage/replay, saved-marker backfill, concurrent callback locks and legacy VIP replay barrier pass; real-store archive/replay succeeded |
| Startup readiness | Required/optional classification, explicit 30-second failure state, retained pending jobs | All six native missing-map/tool cases stayed unready with Failed diagnostics; optional service failure and late successful recovery pass fixtures |
| Movement admission | Server displacement debt, finite coordinates, ping allowance, admitted slide intent and authorized teleport versions; weapon gates | Native excessive displacement was rejected and authorized teleport accepted; running/slide at 300 ms ping passes math tests; native high-ping gameplay remains unverified |
| Spawn fairness | At most six candidate markers, sixteen enemy samples and one visibility ray/candidate, plus recent-use penalties | Deterministic distance/cover/recent-use and bounded-ray regressions pass; each authored map still needs population playtests |
| BR pacing | Four hold/shrink phases totaling 225 seconds, then the existing minimum core/damage policy | Hold/tween sequencing, cancellation and total duration pass fixtures; native cleanup smoke passed on the earlier mock run; final-circle reachability on every map remains unverified |
| Accessibility | Saved ReducedEffects and HighContrastCrosshair settings, generated rows when native GUI omits them, reduced presentation and outlined aim markers | Source/fixture checks pass; visual and mobile/gamepad acceptance remains unverified |
| Mode/weapon statistics and diagnostics | Fixed mode/weapon aggregates, bounded counters, periodic profile-size/pending-trade/receipt/memory diagnostics | Statistics sanitization/caps pass; no unbounded per-shot history added |
| Native lifecycle/performance | Reproducible unsaved-overlay harness with isolated backends and bounded client samples | See measured results and limitations below; population/device/long-soak acceptance remains open |

### Native measurements and unsuccessful attempts

Studio version: 0.742.0.7421053. Authored place version inspected: 485. Catalog inspection found native Tool/Handle templates for all 15 knives and 57 revolvers. StreamingEnabled was true. Reading Workspace.AuthorityMode was denied by the thread capability; this does **not** establish that Roblox server authority is enabled or disabled. Movement admission is an additional positional check, not full authoritative character simulation or vertical-flight prevention.

The earlier two-player mock-backend run passed startup/profile independence, excessive displacement/authorized teleports, durable trade, FFA respawn/forfeit and BR cleanup. It recorded 46,876 server instances, approximately 2,387 MB total Studio server memory, 1,893–1,998 serialized profile bytes, one intentional movement rejection and no collected server errors. A later attempt completed the 30-respawn FFA assertion, but its requested 1,800-second soak returned no final report. **No 30-minute leak/performance conclusion is claimed.**

The two-player real-backend run used namespace BetaAudit_20261008_66f0f498. Startup, movement, durable trade, acknowledged profile reread and receipt archive/replay passed. Its rapid successive respawn test timed out. Character setup now checks an already-dead humanoid after attaching Died, with a regression for death during yielded setup. The harness also waits for each StartGame task’s complete cleanup and checks the current mode before starting the next case. The final native retest reached only one of two requested clients and timed out connecting the second; it executed no multiplayer assertions. **The respawn correction therefore has fixture evidence but no successful final native retest.** The real-backend run’s BR assertion followed the FFA failure and is not used as fresh BR acceptance evidence.

Real-backend run memory was approximately 2,428 MB server and 2,574–2,614 MB/client. Clients reported 14,199 instances, roughly 6 MB Lua heap and 66.6 ms frame-time median with a 67.5 ms 95th percentile. These are simultaneous local Studio instances with background throttling, not a mobile/device performance certification. No sustained traffic, engine script-memory or maximum-population baseline was established.

An eight-client attempt did not connect the requested population within 90 seconds. MaxPlayers is 60 in the authored place, but a 60-player run was not performed on this machine. The user reported a Roblox instance failing to open during the final two-client attempt; Studio subsequently cleaned up that test run. These launch failures are recorded as failures, not gameplay passes.

Verification-only asset requests using correctly typed instances returned success for 280 of 281 IDs on both actual clients; the failed value was the malformed native placeholder `=`. Generic raw-ID results were superseded by the typed client check and are not counted as broken assets. Explicit texture/image preloading is disabled in the final game code, as requested. No native asset replacement was guessed or published.

Sanitized structured evidence is retained under [audit-results/2026-10-08](audit-results/2026-10-08). Process logs are excluded. The earlier hosted [Windows Verify run](https://github.com/andreashofsta20/Stab-Combat/actions/runs/37841171652) passed both native PowerShell suites and portable syntax/Rojo verification. The final branch’s hosted result is recorded with the pull request.

### Persistence/migration and operational behavior

The profile additions are DataSchemaVersion, InventoryQuarantine, TradeJournal, accessibility settings and fixed CompetitiveStats. Existing inventory metadata comes from current catalogs. Duplicate/unknown/corrupt rows are retained in a bounded quarantine rather than combined or granted as new usable stock. Critical corruption leaves the player unavailable instead of saving temporary defaults. Existing legacy migration remains disabled.

VIP imports a finite profile expiry only when the dedicated record is absent. Existing dedicated records remain authoritative. Receipt archival retains the per-receipt ledger permanently; a failed archive keeps hot markers. Legacy VIP markers first establish an acknowledged owned-profile replay barrier, then archive, then prune. Maintenance and ProcessReceipt are serialized for the same user, while the receipt lock remains held through final archive acknowledgement.

TradeJournal references are recovered inside owned ProfileStore sessions before DataReady. During escrow/recovery, InventoryLocked prevents inventory writers/equips/weapon use, and profile snapshots preserve the journal’s inventory tables. A preparation lease lasts 120 seconds; save acknowledgements wait at most 20 seconds, with a bounded background retry. An ambiguous backend failure preserves pending stock until the authoritative decision can be resolved. Terminal trade records are retained permanently to reject replay; no journal deletion policy was added. Pending trades must be drained or recovered when coordinating deployment/rollback to server versions that understand this schema. The draft PR and local source are ready for review; the Roblox place was not published.

### Still unverified

- Final native retest after the death-listener fix; high-ping combat/cover/slide behavior and cross-server session handover or prolonged live backend interruption.
- Intended-population runs, sustained network/script-memory measurements, 30–60 minutes of mixed combat/UI activity and real mobile/gamepad performance.
- Authored BR final-circle reachability on every map, UI/weapon alignment on actual devices, and visible accessibility acceptance.

These are acceptance gaps requiring successful native sessions/devices, not completed tasks inferred from unit fixtures. Practice mode and texture-preload work are intentionally excluded from the requested final scope.

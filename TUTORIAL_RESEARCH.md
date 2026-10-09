# Solo tutorial: research and security rationale

Reviewed against Roblox Creator Hub and the bundled ProfileStore source on 2026-10-08, with onboarding/analytics follow-up on 2026-10-09. This document distinguishes platform guarantees from the design decisions used by this project. Actual cross-place travel still requires published Roblox client testing.

## Platform findings

Roblox recommends server `TeleportAsync`. A new reservation can be created with teleport options, but this tutorial explicitly reserves first so every retry targets the same destination. Protect requests with `pcall`; an accepted request can still fail later through `TeleportInitFailed`. Teleports do not run in Studio playtests. Set experience access to **Secure within universe only** and restrict direct access to the tutorial place. Keep both places in the same experience. [Teleport between places](https://create.roblox.com/docs/projects/teleport)

`ReserveServerAsync` returns an access code and the reservation's `PrivateServerId`. The code remains usable across server restarts, while `JobId` changes between server instances. A reserved server has a nonempty `PrivateServerId` and `PrivateServerOwnerId == 0`. Bind admission to the reservation ID; bind the consumed ticket to the current job. [ReserveServerAsync](https://create.roblox.com/docs/reference/engine/classes/TeleportService/ReserveServerAsync)

Server `Player:GetJoinData()` provides verified source place/universe and associates teleport data with the joining player, but the payload is still transmitted through the client and can be abused. It is a routing hint rather than a currency or completion record. Verify the source and use a server storage record for admission. [Player:GetJoinData](https://create.roblox.com/docs/reference/engine/classes/Player/GetJoinData)

MemoryStore hash maps support atomic `UpdateAsync` transforms. The transform may rerun if another writer changes the value; returning `nil` cancels it. Keep callbacks free of external side effects and protect storage calls because they can fail. [MemoryStoreHashMap](https://create.roblox.com/docs/reference/engine/classes/MemoryStoreHashMap)

MemoryStore is appropriate for short-lived admission tickets, with an explicit short expiration. It is unsuitable for permanent tutorial completion or rewards. Those belong in the existing persistent player profile. [Memory stores](https://create.roblox.com/docs/cloud-services/memory-stores), [Data stores](https://create.roblox.com/docs/cloud-services/data-stores)

ProfileStore owns the active player record under a session lock. `Save()` schedules work; `LastSavedData`/`OnAfterSave` establish which changes actually reached storage. Do not mutate an ended profile. Keep the existing source profile until normal `PlayerRemoving` releases it, and let the destination acquire the session normally. Use the project's existing `ConfirmSave` helper before returning after reward persistence. This avoids the current `OnSessionEnd` handler kicking a player who is still awaiting travel. [ProfileStore API](https://madstudioroblox.github.io/ProfileStore/api/)

Every client-triggered action needs server validation of type, value, current state and request frequency. Weapon damage must retain origin, direction, line-of-sight, cadence and ammo checks. No tutorial remote should accept a completion flag, progress count, reward amount, arbitrary target or requested inventory grant. [Securing the client-server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary)

Client network ownership allows physics manipulation. Tutorial NPCs are gameplay-critical objects, so use server ownership for their unanchored assemblies and keep target registration in a server table. Attributes and tags are useful for presentation/discovery but are not the admission authority. [Network ownership](https://create.roblox.com/docs/physics/network-ownership)

For NPC navigation, path computation can fail or become blocked. Use protected, throttled computation, follow valid waypoints, replan when a forward waypoint blocks, and recover stalled enemies. Avoid computing a new path for every bot every frame. [Pathfinding](https://create.roblox.com/docs/characters/pathfinding)

Tutorial UI should preserve readable contrast and text, show information visually as well as audibly, and honor reduced-motion preferences. Device-specific controls should use the player's current keybinds/input method. Keep objective text short and the progress panel away from aim and touch controls. [Accessibility guidelines](https://create.roblox.com/docs/production/publishing/accessibility)

## Onboarding design principles

Roblox's onboarding guidance emphasizes essential controls/core loop, getting to engaging play quickly, and finishing with progression and a satisfying reward. Measure lesson drop-off and retention rather than assuming a longer explanation creates a better first session. [Onboarding](https://create.roblox.com/docs/production/game-design/onboarding)

The platform design guide cautions against lengthy, text-heavy tutorials and recommends visual instruction and interfaces designed for mobile first. This supports short objective text beside actual practice rather than a long sequence of reading screens. [Design for Roblox](https://create.roblox.com/docs/production/game-design/design-for-roblox)

World markers, highlighted targets and short contextual prompts reduce the search effort required to understand the next action. Introduce advanced inventory/trading/shop details when the player engages with those features; timed hints can help players who stall without slowing experienced players. [Onboarding techniques](https://create.roblox.com/docs/production/game-design/onboarding-techniques)

Project decisions based on that guidance:

- The first lesson should give control quickly, and the first combat target should be reachable without a long tour of lobby systems.
- Teach one active skill at a time, keep the next action visible and acknowledge success immediately.
- Place practice enemies clearly and prevent a beginner death loop. Server validation still decides whether each action counts.
- Briefly connect the tutorial to match progression and collection goals; detailed prices/trading flows remain in their actual menus.
- Treat exact lesson length, NPC health, reward values and hint timing as tuning hypotheses. They need observation on phones/gamepads and real first-time players; the documentation does not establish a universal optimal number.

## Travel implementation

`src/server/Tutorial/TutorialTickets.luau` and `TutorialTeleport.luau` accept dependency injection, allowing production code to run in deterministic regression tests.

1. In the main place, the caller verifies profile readiness, trading/inventory state and eligibility, then locks the tutorial launch request before yielding.
2. `Tickets:Issue(player, replay)` reserves one tutorial server and writes a random token record bound to the user, source universe/place, tutorial place, reservation, expiry and trusted return route. The access code remains in the server caller's returned ticket, outside the MemoryStore record and player state.
3. Teleport data contains the token/version and a per-attempt travel nonce. It contains no XP, gold, knife grant, completion proof or reserved access code supplied to the client UI.
4. `Teleport:Start` captures original options and schedules one asynchronous request. The pending record is claimed before scheduling. Retries preserve the reservation, use new options and rotate the nonce.
5. The tutorial server rejects direct/public joins, other universes/places, wrong reservations, expired tickets, wrong users and unsupported versions. `Tickets:Claim` performs an atomic one-time claim. Even a second claim in the same server job is rejected.
6. Each late teleport failure must match the pending player's destination and current attempt nonce. Duplicate/stale failures are ignored. Retryable failures and throttling use separate delays; other results reach recovery immediately. A watchdog releases a player left behind. Leaving, cancellation and service destruction stop queued work.
7. The tutorial server runs only the admitted player's session, then persists completion and the earned reward receipt before return travel. The main place applies XP, gold and the knife with its applied marker in the same locked profile record. Durable receipt markers prevent retries, reconnects and replays from granting twice.

The admission record expires independently of its MemoryStore TTL. A claim refreshes storage retention but cannot extend the record's own admission expiry. The admission ticket is consumed only once; a crash/reconnect starts a fresh server-issued ticket rather than reusing a consumed credential.

Return travel can target the original public `JobId`, then fall back to main-place matchmaking if that server is unavailable. A private/reserved source's job ID cannot supply its access code; issued tickets use main-place matchmaking for that source type. Finishing and receiving a durable reward does not depend on the original main server remaining alive.

The configured travel watchdog is 90 seconds. Four attempts can require three throttling delays of 15 seconds each; a 45-second watchdog would race the final retry before allowing time for the actual network requests. Roblox does not expose a cancellation mechanism for an already in-flight `TeleportAsync` request. The watchdog bounds local busy state and offers recovery; live tests must verify late engine behavior and return fallback rather than treating the timer as engine cancellation.

## Server analytics

Roblox funnel events are sent from servers in published experiences. One-time onboarding uses `LogOnboardingFunnelStepEvent`; recurring funnels use `LogFunnelStepEvent` with a session ID. Logging a later step implicitly completes any missing earlier steps, so a skip must not be logged as a later completion step. Repeated step submissions also consume event quota. [Funnel events](https://create.roblox.com/docs/production/analytics/funnel-events)

`TutorialAnalytics` logs `Started` as step 1, each validated completed lesson as its index plus 1, and `Completed` after the final validated lesson and successful completion save. Replays use a separate recurring funnel named from `TutorialConfig.Analytics.FunnelName`, with the server-generated tutorial session ID. The module rejects foreign sessions, arbitrary names, nonsequential steps and duplicate outcomes. The platform API does not make analytics an authorization system; gameplay state, tickets and reward receipts remain separate. [AnalyticsService](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService)

Skips emit the single `TutorialSkipped` custom event, with the last completed lesson. A declined lobby invitation records a skip without starting/completing the onboarding funnel. Custom events require published server testing and their charts may take up to 24 hours to populate. [Custom events](https://create.roblox.com/docs/production/analytics/custom-events)

Version, onboarding/replay mode and map/last lesson use the three documented custom-field names and string values. These dimensions stay bounded; no username, user ID, access code, ticket token or session ID is placed in custom fields. Session IDs are used only in the recurring funnel parameter. [Custom fields](https://create.roblox.com/docs/production/analytics/custom-fields)

Analytics delivery is best effort. Disabled/Studio analytics make no calls. Event exceptions are protected and never gate lessons, saving or travel; a dropped event can reduce measurement accuracy but cannot grant or remove a reward. Track changes through version fields and compare compatible date cohorts after changing lesson order. Validate dashboard results before using them to tune drop-off.

## Repository integration review

The preexisting tutorial set `FirstTimePlaying` and played a local menu tour. That flag proves only that the old tour was started, so it cannot prove completion of the new combat tutorial or entitlement to its reward.

| Existing integration | Requirement for solo tutorial |
| --- | --- |
| `Game/GameLoop` | Do not start the normal round loop in the tutorial place. |
| `Game/Maps` | Regular map templates are eagerly required. Publish required assets, or gate/lazily load regular maps. Load the exact Studs tutorial template deliberately. |
| `DataStore/OnJoined` | Route tutorial death/reset to its session recovery before normal round/lobby death handling. |
| `CombatHandler/StabKnife` | Retain movement, cooldown, held-tool, bounds, distance and cover validation. Allow only registered tutorial NPCs through the narrow context API. |
| `CombatHandler/ThrowKnife` | Retain shot ID replay protection, finite vectors, origin/cover and headshot checks; route NPC damage through tutorial authority. |
| `CombatHandler/HandleRevolver` | Tutorial candidates require NPC frame/geometry; world cover rays must exclude analytical NPC candidates. Retain ammo, sequence, timestamp, reload and origin checks. |
| `CombatHandler/HandleHotbar` | Reuse real owned-tool equipment and native tool lifecycle. Objective progress comes from server-observed equipped state. |
| `CombatHandler/FoodService` | Return a stable tutorial session context for grant/eat/refresh. Credit only successful server healing, preserving tool identity/portions/cooldown. |
| `CombatHandler/MovementAuthority` | For tutorial placement/respawn publish `ServerTeleportPosition` and increment `ServerTeleportVersion`. Credit accepted displacement/slide events. |
| `Game/MainGame.DamagePlayer` | Tutorial NPC damage uses separate authority; normal player kill/death, round results, competitive stats and quests must remain outside tutorial scoring. |
| `DataStore/ProfileManager` | Completion, reward marker, XP, Cash and knife inventory must persist in the same locked profile. Replicated Value objects must agree before saves serialize them. |

Tutorial state should advance from actual accepted gameplay events. A client acknowledgment can dismiss an explanation card, but cannot satisfy the movement, slide, knife stab, knife throw, revolver hit, reload, heal or final enemy challenge. Track the current session/stage when crediting each event so delayed events cannot satisfy a later objective accidentally.

## Verification and deployment checklist

The travel fixture covers source/user/reservation/version/expiry rejection, direct access, strictly one-time claims, storage contention/outage, departure during issuance, request errors, attempt limits, nonce correlation, duplicate events, throttling delay, failures during an in-flight request, watchdog, cancellation and destruction. The initial run passed 12 tests using Luau 0.741. Analytics passed 8 production-module tests covering onboarding/replay separation, truthful sequential progress, skips, malformed/duplicate sessions, backend failure isolation, disabled/Studio mode and cleanup. Rerun after integration changes.

- Configure a published tutorial place ID distinct from the main place, under the same universe. Leave feature launch unavailable until configured.
- Publish the same required shared code/packages to both places, and install the Studs map, required weapon models and bot assets.
- Configure tutorial maximum players to 1 and secure direct access. Server admission still rejects any unauthorized second player.
- Verify keyboard, remapped binds, touch and gamepad objective text/buttons with actual devices and emulator safe areas.
- Run a fresh-player journey, old-tour-player journey and rewardless replay. Confirm XP, gold and knife each increase once after the first validated completion.
- Die/reset in each gameplay lesson; fall off the map; lose a bot; disconnect and rejoin mid-tutorial. Confirm recovery and no unintended PvP/quest/stat rewards.
- Inject duplicate/out-of-order remotes, invalid payloads, repeated return requests and failed save confirmation. Confirm no premature completion and no repeated grant.
- Exercise a published round trip, a closed/full original return server, teleport failure/retry and destination profile lock handoff. Studio simulations cannot prove Roblox cross-place behavior.
- Disable new tutorial launches while preserving return travel for an existing session. Start a trade/receipt operation during reservation latency and confirm travel never leaves an incomplete economy operation behind.
- Confirm first-time onboarding and replay events appear in separate Creator Hub funnels. Skip midway and verify no completion step appears. Wait for dashboard aggregation before comparing counts.
- Observe a fresh player on a phone without coaching: time to first useful action, unreadable text, hidden controls, stalled target acquisition, lesson exit and first real match. Tune the measured failure points.

No software test can guarantee that Roblox networking, storage and teleport services never fail. The design makes those failures bounded and recoverable, keeps rewards under server authority, and states the required published validation explicitly.

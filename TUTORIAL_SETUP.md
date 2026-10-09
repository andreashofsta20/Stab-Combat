# Solo Studs tutorial — setup and operation

The tutorial source is implemented. Creating/publishing the second place, supplying its authored assets, and testing actual cross-place travel are the remaining deployment steps. `TutorialPlaceId = 0` deliberately keeps live invitations unavailable until you configure that destination.

The player enters a server reserved just for them, learns through real combat on Studs, completes a short final fight, and returns to the main place. First completion earns **500 XP, 500 Gold, and one Shadow Dagger** by default. Gold uses the existing `Cash` profile/leaderstat field. Change these values in `TutorialConfig.Rewards` before launch.

## 1. Create the tutorial place

1. Open the authored main place in Studio. Save a local backup first.
2. Create a **new place inside the same experience**, using the authored game as the starting copy. This preserves its GUI, remotes, weapons, animations, lighting and required assets. Do not create a separate experience: the profile store and admission tickets must be shared within one universe.
3. Name it something such as **Stab Combat — Training**. Keep the original main place as the experience's start place. Publish the new place and copy its **Place ID**, not its universe/experience ID.
4. Set the tutorial place's maximum players to **1**. The server also independently enforces one admitted owner.
5. In Creator Dashboard, use **Audience → Access Settings → Access Control for Places → Secure within universe only**. Inspect **tutorial Place → Access → Direct Access Control** so it does not permit unrestricted direct joins. These settings support reserved, server-initiated travel; the ticket checks still run independently. [Roblox teleport security](https://create.roblox.com/docs/projects/teleport)

Third-party teleports are unnecessary for travel between these two places. Keep the experience's existing privacy/access policy; testing can use accounts allowed into a private experience.

## 2. Publish the same source to both places

Update `src/Modules/TutorialConfig.luau`:

```lua
MainPlaceId = 119874582058419, -- verify this is YOUR intended main/start place
TutorialPlaceId = 0,          -- replace with the newly published training Place ID
MapName = "Studs",
Rewards = {XP = 500, Gold = 500, Knife = "Shadow Dagger"},
Studio = {EnableSoloPreview = false},
```

The current main ID is the authored place used by the repository's existing native audit. Verify it before deployment. The tutorial ID must be positive and different from the main ID.

Use the existing `default.project.json` and Rojo workflow to sync the checkout into each **authored** place, then publish both. There is one shared source tree; `TutorialRole` chooses the correct server behavior from the place ID. Publish the destination first, then the main place's invitations. Do not publish the code-only `rojo build` output over the authored game: native maps, tool models, remotes and GUI assets are not represented completely in that file.

Both places must use the same `DataConfig.ProfileStoreName`, profile schema, packages and catalog. Leave `DataConfig.UseMockProfiles = false` and `TutorialConfig.Studio.EnableSoloPreview = false` in published production. Neither configuration should be toggled in a live server to test data.

Remove any old, separately installed tutorial LocalScript/Script that also controls the tour. The tracked `TutorialHandler` and `ServicesHandler/TutorialService` replace the old tutorial controller. Its unused authored `Main.Frames.TutorialFrame` is hidden automatically; the new UI is constructed by code.

## 3. Author the Studs practice area

Keep the actual Studs map template in **ServerStorage.Studs**. A Model is preferred for persistent streaming. A Folder is also accepted. The system clones the template into Workspace as `TutorialStuds`, removes map scripts, and disables map SpawnLocations so only the tutorial controls placement.

Recommended hierarchy:

```text
ServerStorage
  Studs (Model; Archivable = true)
    [actual anchored Studs geometry]
    TutorialPlayerSpawns (Folder)
      01_Start (Part)
    TutorialNPCSpawns (Folder)
      01_Bandit (Part)
      02_Bandit (Part)
      03_Bandit (Part)
      04_Bandit (Part; optional spare)
  TutorialNPC (Model; optional custom humanoid rig)
  Knives (existing owned knife Tool templates)
  Revolvers (existing owned revolver Tool templates)
ReplicatedStorage
  Food
    Burger (existing Tool)
```

Spawn markers should be anchored, invisible, noncolliding, and **CanQuery=false** so they cannot block weapon rays or floor checks. `01_Start` should face the first bandit. Leave an unobstructed sprint lane, a low obstacle for jumping/sliding, and real cover for the final fight. Place three or four bandit markers on reachable floors, within the configured leash distance. Sorting by marker name makes placement predictable.

Existing `Spawns` parts are used if `TutorialPlayerSpawns` is absent. Missing NPC markers use offsets in front of the first player spawn, then raycast down onto actual map geometry. This fallback requires usable floor at every generated offset. Authored markers are strongly preferred: they determine how quickly a new player finds their first target and whether movement practice feels natural. NPC floor tests are checked when the arena runs; the read-only preflight can inspect marker layout but cannot replace a live geometry test.

The optional custom `TutorialNPC` needs a Humanoid, HumanoidRootPart, connected R6/R15 parts, and an Animator. NPC scripts are removed; this system owns AI. Without that model, a connected R6 practice bandit is created on the server. NPC assemblies use server network ownership. At most four enemies are alive, with short respawns so a missed or destroyed target cannot exhaust the lesson.

Enemies are passive during individual weapon lessons. The final three chase and attack, with a health floor and spawn protection to prevent an endless beginner death loop. Falling/resetting still triggers normal character recovery. Use the native Studs map rather than the `Classic ROBLOX` alias that the isolated test harness may create when the authored audit place lacks Studs; that alias is only a test fixture.

Retain the game's existing assets in the training copy: `ReplicatedStorage.Remotes`, `GameActive`, `Assets`, food and weapon presentation assets; the authored `StarterGui.Main` and `MobileFrame`; all knife/revolver Tool templates a returning player might have equipped. Keeping only the default weapon can strand players with another owned skin. The native tutorial panels do not require new uploaded images.

Run [scripts/validate-tutorial-place.luau](scripts/validate-tutorial-place.luau) in Studio's **edit-mode Command Bar** after syncing. It is read-only, reports missing assets/configuration, and never teleports, grants rewards or accesses player profiles. Fix every error; read the warnings before publishing.

## 4. What players learn

Each gameplay objective uses server-accepted actions. Success gives a short visual/audio acknowledgement and advances automatically after 0.65 seconds. No Next button is needed during practice. Three concise field notes finish the tour without forced reading timers.

| Lesson | Player action / completion evidence |
| --- | --- |
| First weapon | Equip an owned knife observed on the character. |
| First knockout | Kill one registered bandit with an accepted melee hit. |
| Movement | Move 24 admitted horizontal studs; teleports do not count. |
| Sprint | Travel 20 admitted studs above walk speed on the ground. |
| Slide | Perform a server-accepted slide while moving. |
| Throw | Kill two bandits with validated knife throws. |
| Revolver | Equip an owned revolver observed on the character. |
| Shooting | Kill two bandits using accepted revolver shots. |
| Reload | Finish a real server reload. Fire first if the cylinder is full. |
| Healing | Eat the granted Burger and actually restore health. |
| Final fight | Defeat three attacking bandits with either weapon. |
| Real matches | Explain voting, Free For All, Battle Royale safe zones, XP and Gold. |
| Collection | Explain inventory, shop/cases, daily offers/rewards, quests and trade checks. |
| Personal settings | Explain settings, camera, inspection, emotes and replay; finish. |

The compact objective card leaves the center of aim clear. Registered targets get occluded outlines and a nearest-target marker; relevant hotbar slots are highlighted. Hints become clearer at 15 and 30 seconds of inactivity on a lesson. Current keyboard bindings and preferred input select the instructions. Phone layouts use safe areas, scrolling content and reachable buttons; touch crouch and slide are real actions, not decorative prompts. Controller tutorial mappings are defined by `TutorialUIConfig.Gamepad` and shown by the UI.

Default tutorial controller controls: D-pad Left equips the knife, Up equips the revolver, Right equips Burger; RB stabs; hold/release RT throws the knife, RT fires the revolver or eats the held Burger; LT aims the revolver; X reloads; L3 toggles sprint; LB slides; hold B crouches; A uses native jump. Knife aim uses the center of the screen on a controller. These supplemental bindings activate only during admitted tutorial gameplay with a controller and are removed on exit/input changes.

The last three notes introduce the wider game without forcing a new player through purchases or trading. Prices, eligibility and full settings remain in their actual menus. The UI uses the existing transition helper and reduced-motion setting. Success has a visual signal even when audio is muted.

## 5. Persistence, security and recovery

**Admission:** the main server verifies data/startup readiness, no current match, no trade/inventory lock, and launch cooldown. It reserves one destination server and stores a short-lived, atomic single-use MemoryStore ticket. The destination verifies the player, source universe/place, destination, reservation, version, expiry and unused claim. Another player, a public/direct join or a replayed ticket cannot become an authorized training session.

**Gameplay:** the client sends only bounded UI intents (`Status`, `Start`, `Replay`, `Dismiss`, `Continue`, `Return`). It never supplies progress, currency, completion proof or a reward item. Knife and revolver practice reuses the existing server combat paths with their range, cover, cadence, ammo, sequence and movement checks. Only that session's registered NPCs accept tutorial damage. NPC kills do not increment competitive kills/deaths, match XP/Gold or quests.

**Reward:** verified final completion writes `Tutorial.Completed` and a frozen `PendingReward` receipt into the existing locked profile. The destination waits for a matching saved backend snapshot before returning. The main place then applies XP, `Cash` and one canonical inventory copy together with `AppliedReceipt` in that same profile record. Save timeouts retry the same receipt; duplicate requests, reconnects and rewardless replays do not apply another delta. Frozen terms preserve an already earned reward if configuration changes before return. Keep the reward knife in the catalog while pending receipts exist.

The current inventory stacks by item name. A newly created non-Bowie reward row follows normal tradability, and an existing row retains its restrictions. This implementation does not pretend that one copy in a stack can be individually soulbound. The reward is once per profile, across tutorial content versions; incrementing `Version` does not grant it again.

**Returning:** the original public main server is tried first. If unavailable, return falls back to main-place matchmaking. A private/reserved source also returns through main-place matchmaking. Ordinary profile ownership ends only when the player leaves; the destination obtains the existing ProfileStore session lock normally. During reward recovery, the player is kept out of match admission until the result is saved and dismissed.

**Interrupted practice:** reset/death preserves the current session/lesson and completed objectives, replaces the character, resets trusted placement, and restores healing practice when needed. Disconnection deliberately restarts this short tutorial after a fresh invitation/ticket; incomplete progress is not saved as completion. Once earned, a durable receipt survives disconnect/return failure and is recovered on the next main-place join. Existing players with the old `FirstTimePlaying` flag avoid unsolicited invitations but can use **Training** to obtain their first new reward. Completed players can replay without more rewards.

**Failure controls:** loading/admission, reservation preparation, travel and saving have bounded waits/retries. Return remains available even if startup/data readiness fails. Missing arena assets produce a recovery screen instead of unchecked completion. Disabling `TutorialConfig.Enabled` stops new starts while existing tutorial players can still return. Analytics failures never gate gameplay or rewards. A corrupt authoritative reward record fails profile validation instead of silently resetting eligibility; inspect/recover the record through the game's existing data recovery process.

Roblox cannot cancel an already in-flight teleport. The 90-second watchdog clears local busy state and offers recovery; it does not guarantee engine cancellation. Service outages can still prevent travel or a durable save. [Roblox's documented teleport behavior](https://create.roblox.com/docs/projects/teleport)

## 6. Configuration and source map

| Module | Responsibility |
| --- | --- |
| `Modules/TutorialConfig` | Place IDs, reward terms, availability/version, save/admission/session/request/travel limits and analytics. |
| `Modules/TutorialSteps` | Lesson order, IDs, goal/action, short copy, NPC count and final aggression. |
| `Modules/TutorialNPCConfig` | NPC rig, health/AI/damage, floor/respawn/leash/safety settings. |
| `Modules/TutorialUIConfig` | Colors, typography, layout, hints, feedback, guidance timing, and `Gamepad` control mappings. |
| `Modules/MovementConfig` | Existing authoritative movement and touch button positions. |
| `server/Tutorial/TutorialRole` | Main/tutorial/explicit mock Studio roles. |
| `TutorialCoordinator` | One session controller, admission, lesson transitions, death recovery and return. |
| `TutorialState` | Pure lesson evidence, progression and request rate limiting. |
| `TutorialRuntime` | Server-only session/target authority and accepted-action bridge. |
| `TutorialArena` | Studs clone, trusted character placement and bounded NPC lifecycle/AI. |
| `TutorialTickets` / `TutorialTeleport` | Single-use reservation admission and correlated travel retries. |
| `TutorialRewards` / `ProfileSchema` | Durable entitlement, atomic grant and strict stored-record validation. |
| `TutorialAnalytics` | Validated onboarding/replay funnels and separate skip events. |
| `PlayerClient/TutorialHandler` | One remote/UI lifecycle and live input instructions. |
| `PlayerClient/Modules/TutorialUI`, `TutorialGuidance`, `TutorialGamepadBridge` | Native presentation, contextual assistance and existing-controller input bridge. |

Avoid changing lesson IDs/order mid-rollout without changing analytics version/cohort interpretation. Keep goals positive and supported by `TutorialState`; a newly invented `Kind` needs a real server evidence path and tests. Keep important gameplay/reward values server-authoritative even when UI presents the same configuration.

## 7. Verification before release

Run the source suites, compilation and build using [TESTING.md](TESTING.md). The tutorial runner includes actual production modules with injected services to cover forged/out-of-order/duplicate requests, ticket claims, save ambiguity, partial publication rollback, replays, movement rejection, character recovery, NPC authority, analytics and UI cleanup. Fixtures do not prove native rendering or live backend timing.

The isolated native harness uses an **unsaved authored Studio copy**, an in-memory datastore adapter and `ProfileStore.Mock`. It can exercise native knife geometry, character reset, movement security and actual UI bounds. It disables ordinary client startup to isolate UI construction; it therefore does not validate the entire normal client gameplay journey or physical phone/controller input. Its test-only synthetic actions are listed in the report. See the retained verification record for actual results rather than assuming the harness is complete coverage.

Required published-client acceptance:

1. Fresh player: start from the main place; confirm exactly one player in training and the authored **Studs** geometry. Complete every objective through actual input. Receive exactly +500 XP, +500 Gold, +1 Shadow Dagger after return; confirm the normal inventory can equip it.
2. Rejoin/replay: restart both places/rejoin after receipt saving and after grant saving; confirm no extra reward. Replay all lessons and leave early; confirm no match/quest/competitive stat gains. Test an account with the legacy tour flag.
3. Recovery: reset/fall off in every action lesson, destroy a target, temporarily deny a map/rig asset in a private test copy, disconnect mid-lesson and after saved completion. Confirm Return/error paths and preserved earned entitlement.
4. Travel/backend: close the original main server, simulate request/late-init failures and delayed profile handoff; verify bounded retries, fallback, correct reservation and no duplicate grant. Use isolated test profile namespaces when injecting failures; never reset real player data for this test.
5. Devices: remap PC actions; test touch portrait/landscape/tablet, low frame rate, large text/safe insets and an actual controller. Switch input method and reset while charging/crouching. Confirm visible hints match actions, no duplicate control owner, no overlap with jump/aim/eat and full cleanup on return. Ordinary game's broader console control support is a separate existing compatibility concern; do not enable an unsupported platform solely because the training bridge works.
6. Network/abuse: use high latency and spam UI actions, malformed progress/completion payloads, invalid origins, fake target attributes, foreign tickets and concurrent players. The server must reject unverified progress without blocking a legitimate player's recovery.
7. Analytics: validate started, sequential lesson completion, completion-after-save and replay as separate funnels. A skip must not imply completion. Dashboard aggregation can lag. Use real first-time playtests to measure time to first knockout, lesson stalls and first match entry before tuning rewards/length/hint delays.

TeleportService cannot perform actual travel in Studio; published Roblox client testing is mandatory. [Roblox teleport testing limitation](https://create.roblox.com/docs/projects/teleport)

Design timing and difficulty are starting hypotheses, not measured retention guarantees. [TUTORIAL_RESEARCH.md](TUTORIAL_RESEARCH.md) records the official sources, successful-game examples cited by Roblox, security decisions and analytics semantics behind this implementation.

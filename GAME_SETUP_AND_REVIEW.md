# Game setup and source review

The [2026-10-02 gameplay reliability review](GAMEPLAY_RELIABILITY.md) supersedes the daily quest persistence, hover, knife cursor, map startup and animation notes below. Quest data now migrates into the session-locked main profile; the former cross-store claim issue is addressed there.

Updated 2026-10-01. This covers the Burger feature, cursor-lock fixes, and the data paths reviewed in this change. It is a source review and regression-tested patch; the actual Studio assets, live DataStore failures, default Roblox camera and multiplayer performance still need the checks below.

## What you need to add in Studio

1. Keep **ReplicatedStorage > Food > Burger** as a **Tool**, spelled exactly this way. It is a Studio asset; the source-only Rojo build does not include your mesh or UI assets.
2. If `RequiresHandle` is true, give Burger a direct child **Handle** that is a `Part` or `MeshPart`. Weld any other visible parts to Handle and set the Tool grip so it sits correctly in the R6 right hand. An unwelded assembly will fall apart. A Tool with `RequiresHandle = false` also works, but needs its own visual attachment setup.
3. Set Burger's **TextureId** to your burger image, or set `Icon` in [FoodConfig](src/Modules/FoodConfig.luau). Otherwise the counter shows but the slot image is empty.
4. Keep Burger out of **StarterPack** and **StarterGear**. The server supplies it only to active participants, with a fresh one on FFA respawn. Do not give it through a second script.
5. Remove old eating/healing scripts from the template. The granted clone strips `Script` and `LocalScript` descendants to avoid duplicate healing. Add future food animations/sounds through this system, rather than a separate script that changes health.
6. Your existing **PlayerGui.Main.Bottom** must still contain hotbar ImageButtons **1** and **2**, each with **SlotImage** and **SlotSelected**. You can add an ImageButton **3** with the same children and your preferred placement. If 3 is absent, the client clones slot 2 and positions it using the existing layout or the spacing between slots 1 and 2. Check that it fits inside Bottom and is not clipped on mobile.

No manual food remotes, player attributes or HUD are needed. The server creates **ReplicatedStorage.Remotes.Food.Eat**; the client creates **FoodHUD**, the bite counter and touch EAT button. Keep the existing `Remotes` folder and normal game assets. Rojo maps the new modules automatically, and the client startup list includes HandleFood.

## Burger behavior and configuration

| Setting in FoodConfig | Default | Meaning |
| --- | --- | --- |
| ToolName | Burger | Template under ReplicatedStorage.Food |
| Capacity | 3 | Bites per character per round |
| HealAmount | 33 | Health restored per accepted bite |
| CooldownMs | 2000 | Two seconds between accepted bites |
| RequestBurst / RequestsPerSecond | 3 / 2 | Server request limits, separate from the eating cooldown |
| Icon | rbxassetid://111896278734464 | Burger slot image; uses Tool TextureId when empty |

Slot 3 appears only while the player is a living round participant with bites available. Equip with the existing Slot3 keybind (3 by default), or click/tap the slot. Click the held Burger to eat; touch also has an EAT button. The HUD shows **3/3 bites left**, then **2/3**, then **1/3**, plus cooldown or full-health text. The last bite removes the Tool and slot. At 99 health, one bite restores only one health; at full health, a click consumes nothing. Switching between food and weapons preserves both bites and cooldown.

The authoritative round membership, character, registered Tool identity, health, timing and bite count are checked on the server. The Tool must be equipped. The request contains only that Tool reference; extra amounts/counts have no effect. Old, cloned, backpack or another player's Tools cannot heal. Death, leaving a round, round end and leaving the server clear food. Duplicate grant notifications cannot refill a consumed Burger. Food does **not** enter permanent inventory or DataStore.

Eating does no yielding, descendant scans or DataStore calls. Template setup happens once per grant. The HUD has a 10 Hz update only while food is equipped and disconnects on unequip/respawn. This follows Roblox's guidance on [server context validation and rate limiting](https://create.roblox.com/docs/scripting/security/client-server-boundary).

Optional polish still to add: an R6 eating animation, bite sound and small feedback effect, and a custom burger icon. These are not required for healing. If you want eating to delay/cancel combat or consume time before healing, that needs an explicit server action state; the current bite heals immediately.

## Weapon cursors and map cleanup

The weapon cursor is configured in [CursorConfig](src/Modules/CursorConfig.luau). `Knife.Image`, `Revolver.Equipped.Image` and `Revolver.Aiming.Image` use `rbxassetid://92817416767688` below the existing white dot. `HiddenMouseSize` controls the GUI image size. `ShowOnTouch` defaults to true. The weapon overlay and ADS share native pointer visibility, preventing the original pointer from appearing over the crosshair; food and unequipped states restore visibility after both owners release it. Weapon cursors never overwrite or restore Mouse.Icon, leaving native shift-lock icon management with Roblox. See [GAMEPLAY_RELIABILITY.md](GAMEPLAY_RELIABILITY.md) for the latest cursor, aiming, placement and leaderboard fixes.

`Presentation.LobbyAimingEnabled` in [RevolverConfig](src/Modules/RevolverConfig.luau) defaults to true. Lobby players can hold and move their revolver using the same R6 arm tracking and RMB/L2/touch aim as in a round, visible to other clients. Set it to false to restrict these poses and ADS to rounds. Lobby firing/reloading stay blocked on both client and server, with combat HUD controls hidden; no additional assets or remotes are needed.

[SpawnMap](src/server/Game/SpawnMap.luau) previously cleaned only its tracked clones and skipped spawning when a matching name already existed in Workspace. Pre-existing Studio maps and duplicate siblings therefore survived cleanup. It now removes catalogued gameplay maps at startup and round transitions, validates a new clone's spawn points before publishing it, and replaces the current map without yielding during replacement. FFA respawns and initial placement resolve the registered active instance rather than an arbitrary same-name sibling. A bad map fails the round start gracefully.

Keep gameplay templates in **ServerStorage**, with entries in [Maps](src/server/Game/Maps.luau). Each needs a **Spawns** folder with BasePart spawn markers whose CanQuery is true. Known maps at the Workspace root or inside a Workspace **Maps** Folder are cleaned automatically. For an old map copy with a different name, set **RoundMap = true** on its top-level Model/Folder, or remove that obsolete copy in Studio. Cleanup deliberately preserves **IntermissionMap**, characters, Terrain and unrelated scenery; it does not erase unrecognised Workspace content or terrain painted by a map script. Keep permanent lobby content out of gameplay map templates.

## Cursor getting stuck in the middle

Two real failure paths were found: a lost right-mouse release event could leave the aim request active, and starting ADS while Roblox temporarily locked the cursor could capture `LockCenter` as the release state. These are plausible causes of the reported incident; the exact live incident was not observed.

Held right-mouse aim now also checks [IsMouseButtonPressed](https://create.roblox.com/docs/reference/engine/classes/UserInputService#IsMouseButtonPressed). Release restores free mouse control unless the explicit mobile shift-lock setting is enabled. The native camera can reapply first-person or native shift-lock behavior on its next update. Respawn/character removal, unequip, death, menus, chat and focus loss cancel ADS. The camera update has an error cleanup path so an update exception cannot leave its lock running.

`RevolverEffects` now declares and consistently uses `DebrisService` for all four cleanup calls. The file on disk already had a local Debris service before this change, so the supplied undefined-global warnings may have been from an unsaved editor buffer or stale diagnostics. Save/reload the file and restart Roblox LSP if the old warning remains. See [REVOLVER_PRESENTATION.md](REVOLVER_PRESENTATION.md) for controls, pose/effects configuration and Studio tests.

## How the current data system works

| Area | Current authority / storage | Review result |
| --- | --- | --- |
| Player profile | ProfileManager + session-locked ProfileStore, `PlayerData_v1.0.1_MainData` | Keep this as the main persistence boundary. |
| Replicated stats and inventories | Server-created leaderstats Value objects; serialized into Profile.Data in OnSave | A DataReady guard now prevents temporary hydration defaults being serialized. |
| Legacy migration | Read `PlayerData_v1.0.1_OldData`, populate the main profile, mark MigrationComplete | Existing names and migration behavior retained. A failed legacy read does not complete migration. |
| Inventory grants / equipment | InventoryHandler and server catalogs/models | Knife lookup now uses the catalog key directly. Client equipment selection and actual weapon equip require a positive owned quantity and loaded data. |
| Developer products | Marketplace ProcessReceipt; gold and receipt marker in the same profile | Receipt acknowledgement now waits for the marker in LastSavedData. Timeout/error retries retain the marker and do not award twice. |
| VIP duration | `PlayerVIP_v1_TESTING`, separate UpdateAsync receipt markers and expiry cache | GrantDuration already checks receipt IDs. Main-profile acknowledgement now also waits for persistence. See remaining issues below. |
| Daily rewards | Cash/items and claim timestamp/streak in main profile | Existing server reward selection and cooldown retained. Include disconnect/save-failure tests before release. |
| Daily quests | `DailyQuestsProgress_v1.0`, separate from profile cash | Failed reads now leave quests unavailable and retry after 30 seconds; they cannot save blank defaults or claim rewards. Cross-store crash consistency remains unresolved. |
| Leaderboards | Three OrderedDataStores, server cache | Writes use current loaded server stats, use string keys and skip unchanged successful writes. Request responses are throttled. Failed writes retry later. |
| Profile viewing | Current server values + local Profile.Data; offline profile/legacy reads | Local views no longer read DataStore. Offline read exceptions use the legacy fallback. Invalid non-finite target IDs are rejected. |
| Trading | Server ownership validation and in-memory inventory transfers | Loading guards added. Durable transfer and complete rollback need redesign. |
| Admin actions | Server admin allowlist; capped action log | Keep authorization server-side. Review the allowlist and test unauthorized remote calls in your place. |

Cases recheck the active profile after the yielding gamepass check. Gold purchases also recheck after a VIP lookup that may yield. Inventory, settings, keybind, case, quest and trade requests cannot modify their relevant loading state before DataReady. Old character callbacks no longer remove a new character's ForceField or process an old character death as the current death.

For purchases, `Profile:Save()` queues work; its return is not evidence of a successful DataStore write. The new confirmation uses the contract described in the [vendored ProfileStore purchase documentation](Packages/_Index/vyon_profilestore@1.0.3/profilestore/docs/devproducts/index.md). No save keys were renamed, no production data was edited, and no persistence migration was performed by this patch.

## Remaining issues to prioritize

These are not claims that everything is now secure or crash-proof. They are concrete follow-up work found in the current sources.

1. **Trading persistence and rollback — high priority.** [TradeValidator.ExecuteTrade](src/server/Trading/TradeValidator.luau) removes and gives items in memory, while the two profiles save independently. A crash between profile saves can duplicate or lose items. Its failed-give rollback also does not undo an already successful transfer to the other player. Add a durable trade journal with a unique ID, staged transfers, idempotent completion/recovery for both profiles, and complete inventory snapshots for local rollback. Saving both profiles sequentially is insufficient. Test a crash at every stage before allowing valuable-item trading broadly.
2. **Quest claims across two stores — high priority.** [QuestsHandler](src/server/ServicesHandler/QuestsHandler.luau) marks Claimed in the quest store and adds Cash in the main profile. A save failure/crash can persist one without the other. Raw quest snapshots also have no ProfileStore session lock, so overlapping server sessions can replace newer progress. Move quests and claim IDs into the session-locked profile with a tested migration, or use an idempotent reward ledger. The failed-read fix does not solve this transaction problem.
3. **Inventory hydration validation.** [OnJoined](src/server/DataStore/OnJoined.luau) accepts saved item metadata and repairs some quantities to at least one; knives/emotes have less validation than revolvers. Define a schema that validates types, finite integral quantities and bounds, merges duplicate entries, and handles unknown legacy items without silently deleting them. Preserve backups and quarantine corrupt rows; do not blindly replace an invalid inventory with an empty one.
4. **VIP consistency and retries.** VIP expiry exists in both its dedicated store and the main profile. Pick a clear authority and reconciliation rule. `SetVIPExpiry` currently applies an expiry to the online player even if its write failed. VIP status/purchase remotes in [VIPHandler](src/server/ServicesHandler/VIPHandler.luau) also lack cooldowns. Add server limits, coalesce concurrent expiry reads, and test failed reads/writes and fast rejoin behavior.
5. **Receipt growth.** Main profiles and VIP records retain ProcessedPurchases IDs without a size bound. Monitor record size and plan archival before they grow large. Do not simply delete old receipt IDs; replay protection must survive archival. The legacy PurchaseReceipts store remains a read-only compatibility fallback in PurchaseHandler.
6. **DataStore budgets and shutdown.** Offline profile views still perform remote reads for different targets; add a bounded short-lived cache, shared read limits and coalescing. Bound the name cache in LeaderboardsHandler and avoid broadcasting the full three-board payload for every individual stat change. Add staggered/backoff scheduling, request-budget metrics and a bounded shutdown flush for any future data services. Follow [Roblox DataStore guidance](https://create.roblox.com/docs/cloud-services/data-stores).
7. **A single documented mutation API.** Inventory, cash, XP and rewards are changed from several modules. Introduce shared server methods for grants/debits, bounds, ownership, reason/transaction IDs and saving policy. Make hydration use a separate trusted path. Add a schema version and migration tests before changing the persisted representation; replacing every Value object at once would risk breaking your UI and trade code.

## Existing asset checks and missing polish

- Keep the experience R6-only. Confirm every knife/revolver name matches its catalog entry, server Tool and attachment offsets. See [WEAPON_ATTACHMENTS.md](WEAPON_ATTACHMENTS.md). Configure a barrel `Muzzle` attachment for each revolver and test support-hand placement against its actual grip.
- Ensure your existing Remotes, GameActive BoolValue, Main GUI, sound assets, map folders/spawns and intermission map exist. This repository is predominantly scripts, so a successful Rojo build alone does not verify those Studio objects.
- `src/KeyBinds/DefaultKeybinds.luau` **does exist** and is mapped by Rojo; the older missing-file note in Upcoming.md is outdated. Slot3 already has a keybind.
- Author/select the shooting, reload and eating audio/animations you want. Keep effects within the existing budgets and check low-end devices before increasing transparent trails/particles.
- Add clear onboarding for RMB aim, R reload and slot 3 food; communicate full health, cooldown and empty bites. Decide whether full-health food clicks should remain free, and whether spawn protection should affect eating.
- Remove release debug spam, add useful counters for rejected remote requests and failed saves, and keep a rollback plan plus DataStore backups before persistence changes.
- Keep server validation for combat and rewards. This food patch does not establish a complete movement/teleport exploit detection system or prevent client-side aim assistance.

## Verification

Using the official Luau CLI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-revolver-presentation.ps1 -LuauPath "C:\path\to\luau.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-game-systems.ps1 -LuauPath "C:\path\to\luau.exe"
```

The current suites pass **50 revolver tests and 40 game-system tests** against the production modules with deterministic Roblox stand-ins. They cover lobby aim configuration, rejection of forged lobby combat requests, floor/foreground aim correction, real shot obstructions and range, lost input releases, reload while aiming, camera cleanup, weapon cursor switching/restoration, single-map replacement/cleanup/respawns, food authority/lifecycle/cooldown, equipped HUD cleanup, purchase durability/retries, loading guards, local profile views, leaderboard write suppression and quest read failure/recovery. All source/test files compile, and Rojo builds the new modules as ModuleScripts. These checks do not execute Roblox's native camera or prove live networking/frame-time behavior.

Before publishing, use Studio **Start Server with at least two R6 players** in a separate test place/data environment:

1. Check the third slot is absent in the lobby, appears when fighting begins, and is absent for spectators/lobby-mode players. Equip/eat with keyboard, mouse and touch. Check its icon and text fit every screen size you support.
2. At 1 HP, verify 34, 67 and 100 HP from three bites separated by two seconds. At 99 HP, verify 100 HP after one bite. At full HP, verify no bite disappears. Check rapid clicks never bypass cooldown.
3. Partially eat, repeatedly switch between all three slots, and verify the same uses/cooldown remain. Exhaust it, switch/re-equip, and confirm it cannot refill. Die in FFA and verify a fresh 3/3; die in Battle Royale and verify no food in the lobby. End/start rounds repeatedly and verify cleanup.
4. From a temporary test LocalScript, send nil, a table, a cloned Burger, the replicated template, an unequipped Tool, old-round Tool and extra healing/count arguments to Food.Eat. Verify zero unauthorized health changes. Flood requests briefly and check server frame time remains stable; remove the test script afterward.
5. Hold ADS while switching to food, dying/respawning, opening Escape/chat, alt-tabbing and reloading. Release RMB during each transition. Test free cursor, native shift lock, mobile shift lock and first person. Check that the cursor restores and the revolver can aim again.
   During reload, holding RMB should keep ADS active, and releasing it should leave ADS released after reload. Try distinct equipped/aiming cursor images and check that the white dot stays visible. Equip food or unequip to verify the weapon cursor disappears.
   Aim over low ledges and across open ground with steep camera angles, in both free cursor aim and ADS. Ground behind the barrel should no longer pull shots downward/backward; real cover ahead must still stop them. Repeat in first person and third person with each revolver.
6. Simulate delayed/failed saves and repeated developer-product receipts using test doubles; verify acknowledgement requires saved state and grants stay single. Test quest read failure/retry, quick rejoin, inventory selection during loading and leaderboard updates after cash changes. Do not enable Studio API access against production stores to run destructive tests.
7. Profile a full server firing/eating at once, especially on low-end mobile. Check connection/instance counts after repeated respawns. Record actual frame times and DataStore budgets; the automated mocks are not a performance benchmark.
8. Leave several old catalogued map copies in a test Workspace, start the server and verify they are removed while the lobby stays. Run at least three rounds with different/repeated map choices. Confirm one RoundMap instance at a time, correct player placement and FFA respawns, and no gameplay map after round end. Temporarily test a map missing Spawns to verify a clean failed start, then restore the asset.
9. Verify lobby revolver arm movement and RMB aim with another client watching, including while a match runs. Confirm clicking/R cannot shoot or reload and the ammo/SHOOT/RELOAD controls are hidden. Restart with `Presentation.LobbyAimingEnabled = false`; lobby aiming should stop while round aiming remains available.

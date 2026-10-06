# Weapon effects and round music

These modules sync to `ReplicatedStorage.Modules` through Rojo. Configuration changes take effect when a fresh server/client starts.

Death presentation is configured separately in [RagdollConfig](src/Modules/RagdollConfig.luau). Revolver, stab and knife-throw kills share five-second avatar corpses with configurable per-weapon push. See [the ragdoll and camera aiming review](RAGDOLL_AND_AIMING.md) for structure, research and verification.

## Installed audio

| Sound | Asset ID | Config |
| --- | --- | --- |
| Revolver shot | `134770754233897` | `RevolverConfig.Default.Effects.FireSoundId` |
| Revolver reload | `108663305361300` | `RevolverConfig.Default.Effects.ReloadSoundId` |
| Revolver equip | `98462055955985` | `RevolverConfig.Default.Effects.EquipSoundId` |
| Empty revolver trigger | Add your own asset ID | `RevolverConfig.Default.Effects.EmptySoundId` |
| Round music | `103700954012183` | `MusicConfig.Round.SoundId`, current volume `0.2` |
| Confirmed player hit | `79414317792890` | `CombatAudioConfig.Hit.SoundId`, volume `0.22` |

All revolvers inherit these sound defaults; a named skin can override them. Equip audio follows the actual tool equip once, including mobile/hotbar equips. The old revolver hotbar knife-equip sound is removed. Hit feedback plays locally for the attacker once per positive, server-confirmed revolver/knife-throw hit. Misses, blocked damage and stab do not trigger this sound. `MaxActiveSounds` and `Lifetime` bound its audio instances. The Music toggle controls music separately from combat sound effects.

Set `RevolverConfig.Default.Effects.EmptySoundId = "rbxassetid://YOUR_ID"` for the empty-trigger click. Its default is blank (silent); `EmptySoundVolume` defaults to 0.7 and `EmptySoundCooldownMs` to 250. It reuses one local sound for the owner, preloads in the existing background loadout warmup, respects reload/menu/combat/cooldown gates, and does not send a shot request or consume ammo. Per-skin `Effects` overrides can change these settings.

Revolver body hits deal 34 damage (`Default.Damage`), and precise head hits deal 70 (`Default.HeadshotDamage`). Knife throws deal 50 to the body (`Throw.Damage`); `Throw.HeadshotKills = true` makes a confirmed head hit lethal at the victim's current health. Stab damage stays 100. Head classification uses actual server head geometry, excludes accessories and enlarged hit proxies, and checks intervening body parts and cover. Revolver lag compensation records head and body posture together. The client receives the confirmed headshot flag solely for feedback: body damage numbers are white, including lethal body hits, while headshots are red with a larger centered pop and higher float. Style controls live in `CombatFeedbackConfig.Damage`.

## Revolver aim and shot presentation

The complete camera ray chooses the cursor target; both client and server resolve the actual shot from the character's head position toward that target. Picking never skips the space between camera and avatar, and avatar facing/camera facing never reject the head-to-target direction. Third-person rear targets, including targets between camera and avatar and cameras inside a nearby player's forgiving body proxy, remain selectable. Visible ground or props behind the avatar are also valid cursor targets. The live Tool's barrel is presentation only. Lowered arm poses, bob, recoil, rotated skins and decorative muzzle offsets cannot pull the gameplay ray down into a ledge below a clear cursor. A ledge below the head/cursor path no longer blocks damage merely because the animated revolver sits behind it. A wall obstructing the actual head-to-target path still stops the shot. Only the server-confirmed endpoint starts a traveling streak, for both owners and observers. Owner sound, recoil and muzzle feedback remain immediate. This adds the server reply delay to the streak, but prevents an incorrect predicted cursor path from appearing alongside the wall hit. Duplicate replies cannot replay a streak, flash, sound or impact. Rejected and expired predictions cannot start a streak.

The visual muzzle is checked against the accepted head origin and endpoint. If its offset crosses cover, starts past the endpoint, or its own path would cross another part, the streak uses the head origin. This fallback changes only presentation and cannot turn a clear shot into a blocked one. Observers use the exact server origin rather than a possibly delayed replicated barrel pose. The first-person flash emits at the cover-safe origin and does not follow the barrel through a wall afterwards. Third-person built-in and authored muzzle particles no longer emit together: authored particles are a fallback only when both built-in flash and smoke are disabled and the authored muzzle coincides with the safe origin. `CustomMuzzleParticlesEnabled` controls that fallback.

The server validates camera distance, finite/unit aiming data, timestamp, ownership, session, ammo and cadence, then queries cover on the actual head-to-target shot. A blanket head-to-camera obstruction rejection was removed because a legitimate rear world target can itself be the part between head and camera. That part now receives one shot on its head-facing surface instead of cancelling the shot. A camera seeing a player from the other side of a wall cannot authorize damage through cover: the final trusted head ray still hits that wall first. Embedded or advanced barrels never supply gameplay origins. Pointblank and overhead/elevated targets retain cursor alignment. If cover moves into the accepted path before its reply arrives, the stale streak is suppressed while the authoritative damage and hit endpoint remain unchanged.

The two-ray geometry follows [Roblox's laser hit-detection tutorial and official GitHub source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/tutorials/use-case-tutorials/scripting/intermediate-scripting/hit-detection-with-lasers.md), with a deliberate gameplay adaptation: use the trusted head instead of the animated barrel as the second ray's origin. The [DevForum barrel-obstruction discussion](https://devforum.roblox.com/t/how-to-raycast-with-detecting-parts-in-the-way/3069321) describes the camera-visible but barrel-blocked case. Server validation retains [Roblox's weapon-targeting boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary#weapon-targeting).

Tracer correction remains safe for callers that use it: trails are disabled and cleared, and the line/glint is placed at the original shot age. Completed travel keeps the glint and emission off, preventing late correction replay. Trail length matches `TracerTailLength`, and both Beam curves are explicitly zero. Roblox's [Trail API](https://create.roblox.com/docs/reference/engine/classes/Trail) documents retained segment history and clearing; the [Beam API](https://create.roblox.com/docs/reference/engine/classes/Beam) describes its curve controls.

## Knife speed and effects

`src/Modules/KnifeConfig.luau` controls gameplay and flight presentation:

```luau
Throw = {
    MinSpeed = 500, MaxSpeed = 750, -- studs/sec; charge interpolates between them
    MaxDistance = 350, MaxFlightTime = 2,
    Damage = 50, HeadshotKills = true, Cooldown = 1,
    MaxChargeTime = 1, HoldThreshold = 0.2,
    MaxOriginDistance = 8,
},
```

The previous checked-in speeds were 250–400. At 350 studs the new visible flight takes about 0.47–0.70 seconds. Damage is still resolved immediately on the server, as before; speed controls the visible blade and reachable distance, capped at 350. Stab damage stays 100, and tap/hold, mobile aiming and the shared white crosshair remain.

`src/Modules/KnifeEffectsConfig.luau` contains the white default rail and Frostbite's multicolor override. Each knife inherits `Default`, then applies only its named overrides. Use the exact Tool name. For example, add this inside `Config.Overrides`:

```luau
["Shadow Dagger"] = {
    TrailColors = {{255, 255, 255}}, -- RGB 0–255; multiple colors form a gradient
    TrailWidth = 0.4,              -- studs
    TrailMaxLength = 22,           -- studs
    TrailLifetime = 0.1,           -- seconds
    GlowColors = {{180, 220, 255}},
    GlowWidth = 0.7,
    SparkRate = 0,                 -- clean rail; Frostbite uses 30
    ImpactColors = {{255, 255, 255}, {180, 220, 255}},
    ImpactSparkCount = 8,
    ThrowSoundId = "rbxassetid://YOUR_THROW_AUDIO_ID",
    ImpactSoundId = "rbxassetid://YOUR_IMPACT_AUDIO_ID",
    ThrowPitchMin = 1,
    ThrowPitchMax = 1.12,
    BladeAxis = "Auto",            -- or +X/-X/+Y/-Y/+Z/-Z: the local tip direction
    RotationDegrees = {0, 0, 0},  -- additional XYZ rotation
    StickDepth = 0.15,             -- tip depth in the wall/floor, in studs
    TipDistance = 0,               -- zero derives visible part bounds
},
```

Blank `ThrowSoundId` uses the existing `Assets.Sounds.ThrowKnife`. Blank `ImpactSoundId` is silent. `TrailTexture` optionally accepts a texture ID; blank gives a solid rail. `TrailEnabled`, `GlowEnabled` and `ImpactEnabled` independently control visuals. `SoundVolume` and `SoundRange` control spatial audio.

The trail attachments now span across the flight direction, and `TrailMaxLength` keeps faster throws from drawing an excessively long trail. A small burst at the server-confirmed impact and a slight charge-dependent sound pitch give the throw more feedback without changing camera motion or aim. The client predicts cover immediately, reconciles the blade to the server result, stops emission on impact, caps live knives at 48 and skips distant observer effects. Tool-embedded trail/particle emitters are removed from the projectile clone so the skin config owns its flight effect.

The projectile now copies the whole equipped knife (or the replicated template for an observer). The old Handle-only copy omitted sibling/nested blade parts. Meshes, textures and relative part transforms are preserved, while scripts, joints, collisions, old emitters and local held-tool hiding are removed. Fully invisible mesh templates get a visible mesh fallback. This path is shared by every knife, including Frostbite.

On a confirmed impact, the blade points into the surface normal with only its tip embedded. `KnifeConfig.Presentation.StuckSeconds = 4` keeps it visible for four seconds after arrival/late confirmation. Confirmed misses disappear after `MissSeconds = 0.15`. Observer visuals include the shooter's ID so simultaneous throws cannot overwrite another player's knife. A rejected prediction is removed immediately.

`BladeAxis = "Auto"` uses the longest visible dimension; choose an explicit axis if a skin's tip faces the other way. `TipDistance` overrides the distance from the centered visible model to its tip. SpecialMesh file geometry can extend beyond its parent Part's bounds, so tune this override for such skins during Studio testing. The actual weapon assets are maintained in the Studio place and are not included in this source repository.

The knife HUD sits at the revolver ammo position. It shows the current bindings on desktop, touch instructions on mobile, and charge percentage while holding. Longer holds increase speed from 500 to 750 studs/sec; charge reaches 100% after one second and cannot exceed it. `KnifeConfig.Presentation.HintEnabled` toggles the hint. Combat, equip, menus and character state control visibility.

Confirmed thrown-knife damage flashes the same 32-pixel yellow X at the knife aim point as the revolver, for 0.15 seconds. It reuses `DamageDealtClient`; predicted collisions, walls, misses, blocked damage and stabs cannot trigger it. `KnifeConfig.Presentation.HitMarkerEnabled` and `HitMarkerSeconds` control the marker independently of the hint. Hiding the HUD clears the marker, preventing it from returning on re-equip.

## Revolver settings for every skin

`src/Modules/RevolverConfig.luau` has an `Overrides` entry for all 54 currently registered revolvers. All inherit the current default effects. Replace any skin's empty `Effects = {}` with options such as:

```luau
["Azure Revolver"] = {
    Effects = {
        TracerColor = {80, 180, 255},
        TracerThickness = 0.2,
        TracerGlowWidth = 0.6,
        TracerTailLength = 20,
        TracerLifetimeMs = 150,
        VisualTravelMs = 65,
        MuzzleColors = {{255,255,255}, {80,180,255}},
        MuzzleLightColor = {80,180,255},
        ImpactColors = {{255,255,255}, {80,180,255}},
        SmokeColor = {160,180,200},
        FireSoundId = "rbxassetid://YOUR_FIRE_AUDIO_ID",
        ReloadSoundId = "rbxassetid://YOUR_RELOAD_AUDIO_ID",
        EquipSoundId = "rbxassetid://YOUR_EQUIP_AUDIO_ID",
        EquipSoundVolume = 0.45,
        SoundPlaybackSpeed = 1,
        SoundVolume = 0.7,
        SoundRange = 100,
        CustomMuzzleParticlesEnabled = false,
    },
},
```

The example is documentation only; Azure retains its inherited default until you change its entry. `CustomMuzzleParticlesEnabled` allows authored muzzle particles as the fallback described above; set it to false to disable that fallback. `MuzzleFlashEnabled`, `SmokeEnabled`, `ImpactEnabled` and `TracerEnabled` toggle each effect. Fire/reload animation IDs are configurable too. Colors and nested settings are copied for each call, so changing one returned configuration cannot alter another skin. Cosmetic thickness, sound and color never change the authoritative damage ray.

## Ongoing-game music

Set `Round.SoundId` in `src/Modules/MusicConfig.luau`:

```luau
Round = {
    SoundId = "rbxassetid://103700954012183",
    Volume = 0.2,
    PlaybackSpeed = 1,
    Looped = true,
},
```

Blank means no match music. Use an audio asset permitted for this experience. `FadeSeconds` controls the transition. `Lobby.SoundId` can override the existing lobby track; leave it blank to keep `Assets.Sounds.LobbyMusic`.

Match music begins when the server activates combat after the final countdown and stops when the round ends. Lobby music resumes afterward. The player's Music setting controls both tracks. Sounds start at volume zero, and cancelled fade completions cannot stop a restarted track. Tracks are client-local 2D music, including for spectators.

## Round and kill fixes

- Weapon damage shares an authoritative path that rejects stale characters, dead players, spectators, unready profiles and ForceFields. Feedback reports actual damage. Lethal credit is recorded once even when `Humanoid.Died` is deferred or arrives twice.
- Lifetime kills increment immediately; leaving before results preserves those kills, and results do not add them a second time. Disconnects forfeit placement.
- Only players placed successfully enter the round. Placement occurs before the final countdown, with eligibility checked again afterward.
- Delayed FFA respawns, eliminated-player lobby returns and zone jobs belong to one round. They cannot resume into a later round. Lobby deaths and leaving FFA while dead still receive a lobby respawn.
- A Battle Royale with no survivors reports a draw and grants no win credit. Losing win streaks reset before the profile save.
- Map/zone startup failures and round errors clean up tools, participant attributes, timers, music state and automatic character spawning. The game loop can continue.
- Intermission waits for loaded profiles; it cannot spin without yielding on players whose data is still loading. Voting supports fewer than three available maps.
- XP pass ownership is cached, refreshed on purchase and rechecked after a cache-miss yield. Reward service calls run after death state commits.

## Verification and research

All 20 regression suites pass, including 255 shared revolver/knife checks, 34 dedicated headshot/aim/server checks, and 16 damage-feedback checks. They run production Luau modules with deterministic Roblox stand-ins. Rear-aiming checks reproduce the former failure, verify client hip-fire and ADS selection, and verify body/head hits through a full 360-degree camera orbit with targets between camera and avatar. They also cover rear world parts, visible rear floor/ledges, cameras inside rear proxies, actual shot-path cover and rejected invalid camera distances. Other aiming regressions cover a clear cursor over a ledge across lowered/rotated gun poses, invariant server origin/endpoints and 34/70 damage across those poses, embedded decorative barrels, pointblank proxies, overhead targets, delayed/duplicate/rejected replies, moving cover, observer origins, safe first-person flash placement, pooled tracer cleanup and zero-distance hits. Headshot checks cover actual head bounds, covered heads, intervening body parts, accessory exclusion, historical posture, stale targets, ForceFields, 34/70 revolver damage and 50/lethal knife throws. All 213 source/test files compile and the Rojo project builds. Run `scripts/test-performance-polish.ps1` with PowerShell's process execution-policy bypass to repeat the complete suite.

Native Studio multiplayer rendering, touch controls, audio/animation asset permissions and latency still need a live playtest. Test every actual knife model against a wall and floor, especially SpecialMesh skins, at close range and 350 studs. Observe another player's throws, check the white default/Frostbite rail, change a revolver palette/sound, toggle Music during a round, and end a round while a respawn is pending. CLI checks cannot establish that the game is flawless in Roblox.

The shorter configurable rail follows [Roblox's Trail behavior](https://create.roblox.com/docs/reference/engine/classes/Trail). The impact and sound feedback follow the principles in [Roblox's animation and feedback guide](https://create.roblox.com/docs/education/build-it-play-it-island-of-move/animations-and-feedback). Damage/death checks use the documented [Humanoid behavior](https://create.roblox.com/docs/reference/engine/classes/Humanoid), and global music follows [Roblox's Sound object guidance](https://create.roblox.com/docs/sound/objects).

Whole-weapon geometry handling accounts for [MeshPart being a BasePart](https://create.roblox.com/docs/reference/engine/classes/MeshPart) and [SpecialMesh's separate mesh offset/scale](https://create.roblox.com/docs/reference/engine/classes/SpecialMesh), which is why a Handle-only clone is insufficient and per-skin tip tuning is available.

# R6 revolver aiming and effects

Hold **right mouse button** to aim; release it to return to free cursor aim. Gamepad uses **L2**, and touch has an **AIM** toggle beside SHOOT and RELOAD. Aiming centers the crosshair, smoothly narrows the field of view, adds a shoulder camera offset in third person, turns the character toward the camera and blends into a two-hand R6 pose. It requires an equipped revolver, a living player, loaded data and no blocking menu. Presentation is available in active rounds and optionally in the lobby. Reload keeps the aim camera active while the button remains held (or touch AIM is toggled on), and you can enter aim during a reload. Firing stays blocked until the server confirms reload completion. Release, menus, unequip and death still cancel aim during reload.

This implements the requested Da Hood-style interaction using Roblox's camera and animation APIs. It does not use Da Hood's private source code.

## Lobby presentation

Set `Config.Presentation.LobbyAimingEnabled` in `src/Modules/RevolverConfig.luau` to **true** (the default) to give lobby players the same cursor-following R6 hold pose and RMB/L2/touch aim as round players. Other clients see the arm movement through the existing bounded pose updates. This also works for lobby players while a match is running.

Set it to **false** to restrict arm tracking and ADS to active round participants. The existing hotbar still lets players equip their selected revolver in the lobby; the toggle controls its aiming presentation.

Lobby presentation shows the cursor/white dot and touch AIM button, with ammo, hit markers, SHOOT and RELOAD hidden. Firing, recoil, shot effects, damage and reload requests remain restricted to active rounds on both client and server. The server still checks the held selected revolver, positive owned quantity, character/session, life and loaded data before relaying angles. The toggle supplies no combat permission and adds no new remotes or pose update loops. Death, unequip, menus and input-release cleanup use the same paths as round aiming.

## Backward aiming

Previously, `atan2` produced approximately +180 degrees on one side of directly behind and -180 degrees on the other. Clamping those angles to the shoulder's limits caused the left/right jump. The cosmetic arm yaw now folds the rear hemisphere continuously toward neutral using `asin`. It cannot flip between the two angle limits when the cursor crosses directly behind the character.

R6 shoulders cannot realistically turn a rigid arm through 180 degrees. Free cursor aim therefore keeps a limited, continuous shoulder pose for rear targets. During aimed fire, the body turns to face the camera along the shortest yaw path, so the arms can point forward naturally. Both changes affect presentation; the existing camera ray still decides shot direction.

## Ground and foreground aiming

A third-person camera can see a low ledge or floor intersection behind the barrel. Using that point as the target made the barrel turn backward/downward toward it. Target selection now advances along the same cursor ray to the barrel's forward plane before looking for a hit. Client prediction, server hit detection and arm cursor sampling share this correction, including free cursor aim and ADS.

The actual shot still starts at the validated muzzle and stops at cover in its path. Camera/muzzle validation, victim cover checks and the maximum barrel range remain enforced. This changes where the camera starts selecting a target; it does not make bullets pass through walls.

## Camera and animation

`RevolverAimCamera` retains the default Custom camera and its collision/zoom behavior. It uses [MouseBehavior.LockCenter](https://create.roblox.com/docs/reference/engine/classes/UserInputService#MouseBehavior), [Humanoid.CameraOffset and AutoRotate](https://create.roblox.com/docs/reference/engine/classes/Humanoid), and an update after the normal camera using [BindToRenderStep](https://create.roblox.com/docs/reference/engine/classes/RunService#BindToRenderStep). Cursor sampling and HUD updates run afterward. First person fades out the added shoulder offset.

Release restores mouse/rotation controls immediately, while FOV and camera offset blend back. Unequip, death, respawn, window focus loss, chat focus and opening the Roblox menu cancel aiming. A camera replacement, a changed camera subject or another script taking over FOV/CameraOffset releases the effect. Repeated presses during the fade retain the original snapshot, preventing accumulated zoom or offsets. Mobile shift lock yields body turning during ADS and retains its enabled/disabled state after release.

Held RMB also polls the current button state, recovering from a lost InputEnded event. ADS does not preserve a temporary native RMB LockCenter as its release state: it releases to the explicit mobile shift-lock setting or free mouse control, then the default camera can reapply native shift lock/first person on its next update. Character removal and errors in the camera update also release controls.

`RevolverAimPose` controls only the R6 Torso's two Motor6D shoulder joints. It restores the previous layer in PreAnimation and applies the new layer in PreSimulation, following Roblox's [Motor6D timing documentation](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml). Your idle, walk, crouch and sprint tracks continue running; C0/C1 and Tool grips are preserved. The right arm follows pitch/yaw and recoil. During ADS it moves inward slightly, while the left palm follows a configurable support point relative to the posed right arm.

R6 has rigid arms and no elbow/wrist joints, so this is a two-hand hold pose rather than a multi-joint IK solver. The offsets need checking against the actual Tool grips in Studio. A configured reload animation takes ownership of the arms while reloading; ordinary free aim leaves the left-arm animation alone.

## Weapon cursors

Edit `src/Modules/CursorConfig.luau` to change `Knife.Image`, `Revolver.Equipped.Image` and `Revolver.Aiming.Image` independently. All three start with `rbxassetid://140476432521467`. An empty image restores the normal cursor for that state. `Enabled`, `HideInMenus`, `ShowOnTouch` and `HiddenMouseSize` configure availability and the size of the GUI fallback.

The native pointer uses [Mouse.Icon](https://create.roblox.com/docs/reference/engine/classes/Mouse#Icon). When ADS or first person hides that pointer, a separate cursor image appears underneath the existing white dot. The white dot and hit marker remain unchanged. `HandleWeaponCursor` never changes MouseBehavior or MouseIconEnabled; aim-camera ownership and cleanup remain in RevolverAimCamera. Unequip, food, menus, death and respawn restore the original cursor. Touch retains its existing controls by default; enable ShowOnTouch to add this image there too.

## Replication and security

The existing UnreliableRemoteEvent now includes a boolean ADS flag with the increasing sequence and bounded pitch/yaw. The server still requires the matching character/round session, an owned selected gun actually held, a living player and permission for round or configured lobby presentation. Invalid flags, non-finite/out-of-range angles and old sequences are rejected. Pose requests retain a separate token bucket from firing.

Moving aim sends at most 15 periodic updates/sec, plus immediate aim/reload transitions. Stationary aim uses a 250 ms keepalive. Observers smooth both shoulders locally and expire stale updates after 650 ms. See Roblox's [unreliable event guidance](https://create.roblox.com/docs/scripting/events/remote). Aiming packets supply no targets, muzzle positions, ammo, damage or permission to shoot; the existing firing authority remains on the server.

## Shot appearance and cost

The white/brass streak is thicker, has a longer tail and larger leading glint, and uses the existing two Beam/two Trail layers. A capped screen-size adjustment helps distant glints remain visible. The flash grows from 0.9 to 1.3 studs and lasts 60 ms; built-in muzzle bursts still emit 13 particles total (2 flash, 8 sparks, 3 smoke). Confirmed world impacts use the server's surface normal. The 65 ms cosmetic travel does not delay hitscan damage or immediate local feedback.

Performance changes:

- Cache the two shoulders, Humanoid, equipped Tool and tuning instead of scanning all rig descendants or character children every pose frame.
- Reuse the cursor RaycastParams; sample at 30 Hz and rebuild the hitbox ignore list at 4 Hz.
- Cache server pose tuning per weapon and observer tuning per equipped Tool.
- Stop visiting inactive pose states after their blend ends.
- Share one tracer update connection, disconnect it when no tracers remain, and cap active streaks at 64 per client.
- Skip distant foreign shots/impacts beyond 500 studs. Effects have collision, touch and queries disabled and finite particle bursts.

Larger transparent effects can still increase GPU overdraw. These changes bound CPU work, allocations and update lifetimes; they are not an FPS measurement. Use Roblox's [performance guidance](https://create.roblox.com/docs/performance-optimization/improve) and MicroProfiler in the actual place on a low-end device.

## Configuration

Edit `src/Modules/RevolverConfig.luau`. `Pose`, `Aim` and `Effects` support nested per-weapon overrides. Restart the play session after changing settings.

| Setting | Default | Purpose |
| --- | --- | --- |
| `Presentation.LobbyAimingEnabled` | true | Lobby arm tracking and ADS, with combat still restricted to rounds |
| `Aim.Enabled` | true | Enable aimed fire presentation |
| `Aim.FieldOfView` | 60 | Target FOV; never widens an already narrower FOV |
| `Aim.CameraOffset` | `{1.5, 0.15, 0}` | Additional third-person shoulder offset |
| `Aim.CameraFollowSpeed` | 18 | Camera transition speed |
| `Aim.BodyFollowSpeed` | 24 | Body rotation speed |
| `Aim.PoseBlendSpeed` | 16 | Two-hand hold transition speed |
| `Aim.RightArmOffset` | `{-0.65, -0.1, 0.35}` | Torso-local inward/backward hold offset |
| `Aim.SupportHandOffset` | `{-0.6, -0.9, -0.1}` | Support point in right-arm coordinates |
| `Pose.FollowSpeed` / `BlendSpeed` | 22 / 18 | Arm tracking / raise-release smoothing |
| `Pose.R6RotationOffset` | `{0, 0, 0}` | Grip-specific rotations in degrees |
| `Effects.TracerThickness` / `TracerGlowWidth` | 0.12 / 0.38 | Core/glow widths in studs |
| `Effects.TracerTailLength` / `TracerTipLength` | 14 / 0.5 | Streak / glint lengths |
| `Effects.TracerMinPixels` / `TracerMaxThickness` | 1.5 / 0.6 | Distant glint readability and world-size cap |
| `Effects.VisualTravelMs` / `TracerLifetimeMs` | 65 / 130 | Cosmetic movement / fade duration |
| `Effects.MuzzleFlashSize` / `MuzzleFlashLifetimeMs` | 1.3 / 60 | Flash size / duration |
| `Presentation.MaxActiveTracers` / `MaxEffectDistance` | 64 / 500 | Client visual budgets |

For example:

```lua
Config.Overrides = {
    ["Ethereal Revolver"] = {
        Aim = {
            FieldOfView = 55,
            SupportHandOffset = { -0.6, -0.9, -0.1 },
        },
        Effects = {
            TracerColor = { 150, 220, 255 },
            TracerThickness = 0.14,
            SmokeParticleCount = 2,
        },
    },
}
```

Individual layers can be disabled with `MuzzleFlashEnabled`, `SmokeEnabled`, `ImpactEnabled` and `TracerEnabled`. Set `TracerMinPixels = 0` to keep a fixed world-space width. Custom emitters under the Tool's `Muzzle` attachment and optional sound/animation IDs still work. Place that attachment at the barrel tip for each mesh.

## Verification

Run the actual-source regression suite with the official Luau CLI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-revolver-presentation.ps1 -LuauPath "C:\path\to\luau.exe"
```

The suite uses Roblox stand-ins for matrix math, input, properties, signals and instances. It checks lobby presentation/configuration, server rejection of forged lobby fire/reload, ownership and session validation, round transitions, foreground/floor target selection, first-person and shoulder shot alignment, steep angles, real cover and range limits, matching arm sampling, backward continuity, two-arm restoration, packet ordering and stale expiry, reuse of cursor params, camera ownership/rounding, repeated aiming, input release, round/menu/reload restrictions, centered shots, mobile shift-lock restoration and bounded effect cleanup. It does not render GPU effects, execute the default PlayerModule or simulate real network latency.

In Studio with two R6 clients:

1. Try each revolver while standing, walking, sprinting, crouching and jumping. Hold/release RMB and move through a complete 360-degree turn, including straight up/down and directly behind. Verify grip/support hand placement for each mesh.
2. Aim in third person, existing shift lock and first person. Zoom in/out and approach walls. Confirm camera collision, centered cursor and correct impact positions at short/long range. Try free cursor and ADS on open ground with steep camera angles, then aim over a low ledge below/behind the barrel. Shots should travel forward toward the cursor, while a wall actually in the barrel's path still blocks them.
3. Reload while holding aim and confirm the camera stays aimed, shots are blocked during reload, and shooting resumes at screen center afterward. Release aim during reload and verify it stays released afterward. Switch Tools/skins, open chat and menus, leave the window, die and respawn. Confirm camera, cursor and both arms restore, and three-shot ammo never refills from switching.
4. Watch the second client's pose under simulated latency/jitter. Check that reordered packets do not undo ADS and missing updates release the pose.
5. Test touch AIM/SHOOT/RELOAD and mobile shift-lock transitions. Measure CPU/GPU frame times during simultaneous firing at low/high graphics quality; inspect active streaks and connections after sustained play.
6. With `Presentation.LobbyAimingEnabled = true`, equip a revolver in the lobby, move the cursor and hold/release RMB. Confirm the second client sees the pose, the white dot remains, and no shots/reloads occur. Repeat while other players fight in a round, then join/end a round and respawn. Restart with the option set to false and verify lobby arm tracking/ADS stop while round aiming still works.

The asset geometry, native camera behavior, visual appearance and actual multiplayer/frame-time performance still need these Studio checks before claiming the system is flawless.

# Revolver aiming pose and effects

The revolver now keeps its right arm raised and follows the cursor's world aim point vertically, with a limited sideways turn. This is a procedural version of the requested KAT-style behavior; KAT's private animation code was not available. Your walk, idle, crouch and sprint tracks continue running. Only the gun arm is overridden while the player can aim with a revolver.

## Animation layering

Your custom idle track in `PlayerCharacterClient/Animation.client.luau` uses `Action` priority. The new `RevolverAimPose` module applies the right shoulder pose after Animator evaluation, during `PreSimulation`. It restores its previous layer before the next Animator update so it cannot accumulate rotation when a joint stops receiving animation keys. This timing follows Roblox's [Motor6D.Transform documentation](https://create.roblox.com/docs/reference/engine/classes/Motor6D#Transform).

The shoulder solution preserves the existing joint anchor. It computes the transform in the joint's local coordinates rather than copying a world `lookAt` into a shoulder offset, a problem illustrated in this [DevForum arm-aim discussion](https://devforum.roblox.com/t/how-to-point-r6-arm-to-mouse/2848828).

R6 uses the right shoulder. R15 also controls the right elbow and wrist, so a forearm animation cannot drop the gun while the shoulder is raised. Both Motor6D rigs and upgraded AnimationConstraint rigs are handled; for the latter, the module reads attachment frames and writes `Transform`, without editing rig attachments. See Roblox's [AnimationConstraint API](https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint).

The pose blends out after unequipping, death, opening a menu, or stopping aim updates. When a configured reload animation is playing, the procedural layer yields to that animation. Configured shot/reload animations now use `Action4` priority, while the procedural aim/recoil still controls the firing arm during ordinary shots. If you want an authored animation to own the entire gun arm, disable `Pose.Enabled` for that weapon.

## Other players

The server creates `Remotes.Revolver.Aim` as an UnreliableRemoteEvent. The client sends only increasing packet numbers and bounded pitch/yaw angles at 15 Hz. The server validates the existing character/round session, held owned gun, active round, living player and angle limits before forwarding them. This has a separate rate limit from shooting, so normal pose updates do not consume the firing request budget.

Other clients smooth those angles and apply the same pose locally. Old packet numbers are ignored and missing updates expire after 650 ms. Cosmetic packets never consume ammo, authorize a shot, or provide damage or target positions. Roblox recommends including ordering data for [unreliable updates](https://create.roblox.com/docs/scripting/events/remote), which can arrive late, out of order, or be dropped.

## Shot appearance

The old solid line is replaced by a short moving streak: a thin white core, a soft brass glow, a bullet glint and two fading trails. The layered trails use the same approach as your knife visual, with warm gun colors and shorter lifetimes. A muzzle burst adds a brief flash, light, sparks and a small smoke puff. World impact sparks are emitted from server-confirmed positions and normals. Character hits keep the existing confirmed hit marker.

The 55 ms visual movement is cosmetic; damage remains hitscan. Confirmed endpoints correct the existing predicted streak, without replaying its muzzle flash or restarting a second bullet. Effects prefer the locally posed muzzle, falling back to the configured Handle offset. Their parts have collision, touch and queries disabled, so they cannot obstruct knives or shooting rays.

All tracers share one update connection. Their folders are destroyed after travel and fade, with Debris as a cleanup fallback. Sparks and smoke use finite `Emit()` bursts with zero continuous rate. This design uses Roblox's [Beam](https://create.roblox.com/docs/effects/beams) and [ParticleEmitter](https://create.roblox.com/docs/effects/particle-emitters) guidance; particle appearance can vary with graphics quality.

## Tuning per gun

Edit `src/Modules/RevolverConfig.luau`. Both `Pose` and `Effects` support nested per-weapon overrides:

```lua
Config.Overrides = {
    ["Ethereal Revolver"] = {
        Pose = {
            FollowSpeed = 30,
            RecoilDegrees = 6,
            R6RotationOffset = { 0, 0, 0 },
            R15RotationOffset = { 0, 0, 0 },
        },
        Effects = {
            TracerColor = { 150, 220, 255 },
            TracerGlowWidth = 0.16,
            MuzzleFlashSize = 0.8,
            SmokeParticleCount = 2,
        },
    },
}
```

| Setting | Default | Adjustment |
| --- | --- | --- |
| `Pose.MinPitchDegrees` / `MaxPitchDegrees` | -65 / 75 | Vertical arm limits |
| `Pose.MaxYawDegrees` | 65 | Sideways turn limit; the body is not forcibly rotated |
| `Pose.FollowSpeed` | 22 | Higher values follow the cursor faster |
| `Pose.BlendSpeed` | 18 | How quickly the gun arm raises/restores |
| `Pose.RecoilDegrees` / `RecoilRecovery` | 7 / 18 | Cosmetic arm kick and recovery |
| `Pose.R6RotationOffset` / `R15RotationOffset` | `{0, 0, 0}` | Extra local rotations in degrees for different grips |
| `Effects.VisualTravelMs` | 55 | Cosmetic streak travel time |
| `Effects.TracerTailLength` | 9 | Length of the moving streak in studs |
| `Effects.TracerLifetimeMs` | 100 | Trail/fade time |
| `Effects.MuzzleFlashLifetimeMs` | 45 | Muzzle flash/light duration |

Use `MuzzleFlashEnabled`, `SmokeEnabled`, `ImpactEnabled` and `TracerEnabled` to disable individual layers. Custom emitters below an Attachment named `Muzzle` still work. Set `MuzzleParticleCount` to zero if you do not want sparks/custom emitter bursts. Sound IDs remain optional; the visual revision supplies no new sound asset. `SoundVolume` and `SoundRange` now control positional audio.

A `Muzzle` attachment at the actual barrel tip is recommended on each Tool. Gun meshes and Tool grips are assets in your Studio place, so verify their axes there and adjust the relevant rotation offset if a particular skin faces sideways after raising the arm. Restart the play session after changing module configuration.

## Checks

Run the source-based regression tests with the official Luau CLI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-revolver-presentation.ps1 -LuauPath "C:\path\to\luau.exe"
```

The tests cover cursor angles, frame-rate-independent smoothing, joint anchor preservation, animation restoration, R15 elbow/wrist control, AnimationConstraint access, packet ordering/limits, pose throttling, reload/death release, effect allocation and cleanup. They use small Roblox stand-ins; they do not render graphics or run real networking.

In Studio, test with two clients:

1. Hold every gun while idle, walking, sprinting and crouching. Aim above and below yourself in first person, third person and shift lock. Check that the arm stays raised while the rest of the animation continues.
2. Compare the local and observing client's pose. Add latency/jitter and verify smoothing, stale-update expiry and immediate local recoil. Check R6, R15 and upgraded R15 rigs if your place supports them.
3. Fire at close and distant walls, including floors/ceilings. Check that flashes originate at the barrel, the streak ends at the confirmed point, and impact particles face away from the surface.
4. Verify low/high graphics quality and mobile performance. Set unusual mesh offsets per gun, and check dedicated touch shooting versus world taps.
5. Unequip, switch skins, reload, open a menu, die and respawn repeatedly. Confirm the arm restores, animations keep running and no effects or update connections accumulate.

The actual Studio asset geometry, visual appearance and multiplayer replication still require these checks. No whole-game animation tracks or existing knife visuals were changed by this revision.

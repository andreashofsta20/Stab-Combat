# Death ragdolls and high-camera revolver aiming

Revolver kills, knife stabs and knife throws now produce an avatar-matched physical corpse. Other player deaths use the same presentation. The corpse gets a slight whole-body nudge away from the hit and a torso tipping impulse, stays for **five seconds**, then disappears. It survives the existing two-second FFA respawn and 1.5-second Battle Royale lobby return. No Toolbox model or animation asset needs importing.

## Structure

- `src/Modules/RagdollConfig.luau`: duration, corpse budget, collision group names, inherited speed limits, per-weapon push and joint limits.
- `src/server/CharacterDeath/RagdollService.luau`: early character preparation, death hooks, one corpse per character, bounded storage and cleanup.
- `src/server/CharacterDeath/RagdollRig.luau`: sanitized avatar cloning, R6/R15 joint conversion, ownership, movement inheritance and hiding the original.
- `src/Modules/RagdollQuery.luau`: corpse-folder exclusion shared by revolver prediction/authority, arm sampling, knife throws/stabs and player hover.
- `src/server/Game/MainGame.luau`: passes validated weapon impact context into the existing damage/death flow. Kill credit, damage amounts, rewards and respawn delays remain controlled by this flow.

Rojo automatically includes the new modules and `CharacterDeath` server script through the existing project mappings. Sync the full `src` tree and restart the Studio play session.

## How the corpse works

Every living character has `BreakJointsOnDeath` disabled before lethal damage. On death the server clones the avatar while unparented, removes scripts, Tools, weapon displays, combat hitboxes, animation controllers, health displays and ForceFields, then replaces body Motor6Ds with bounded BallSocketConstraints. The invisible root is welded to the torso assembly. Clothing and welded accessories are retained. Constraint pivots start at coincident positions to avoid pulling a posed limb to a different location.

The cloned Humanoid keeps avatar rendering but has its physics/state machine disabled. The finished mechanism is parented under `Workspace.DeathRagdolls` and given server network ownership. Only after construction succeeds does the service hide the original dead character and disable its collisions and queries. The original Humanoid remains available to the existing death, kill camera and respawn code. A malformed/uncloneable rig logs a warning and leaves the original death visible.

Duplicate notifications from `Died`, immediate damage handling and character removal are idempotent. Cleanup callbacks capture the exact corpse model, so respawning or entering another round cannot make an old timer destroy a new avatar. Old character/player connections disconnect on replacement/removal. There are no corpse remotes or per-frame ragdoll scans.

## Configuration

| Setting | Default | Purpose |
| --- | --- | --- |
| `Enabled` | `true` | Enable death ragdolls; restart after changing |
| `LifetimeSeconds` | `5` | Duration from creation to removal |
| `MaxCorpses` | `32` | Evict the oldest corpse if this server budget is reached |
| `MaxInheritedSpeed` | `60` | Maximum copied movement speed, studs/sec |
| `MaxInheritedAngularSpeed` | `10` | Maximum copied angular speed, radians/sec |
| `Impact.Revolver.Speed` | `2.5` | Added horizontal body velocity, studs/sec |
| `Impact.Revolver.Lift` | `0.6` | Slight upward nudge, studs/sec |
| `Impact.Revolver.TiltImpulse` | `1.5` | Angular impulse per torso assembly mass; tips away from the hit |
| `Impact.KnifeStab.Speed` | `1.75` | Added horizontal body velocity |
| `Impact.KnifeThrow.Speed` | `2` | Added horizontal body velocity |
| `Impact.Default.Speed` | `1` | Small nudge for other deaths |
| `Joints` | per joint type | Swing/twist limits and friction; shared by R6/R15 |

Corpse parts collide with the map, but not each other or default player character parts. Living parts previously in `Default` move to `PlayerCharacters`, whose existing map collision relationships mirror `Default`. Existing custom character groups are preserved; configure those groups not to collide with `DeathRagdolls` if used. Change the group names in RagdollConfig if those names already belong to another system.

The nudge follows the server-validated shot/throw/stab direction, flattened horizontally. Each distinct body assembly receives the same small added velocity; welded parts are counted once. A separate one-time angular impulse tips the torso away from the attacker, so stationary deaths can fall onto the ground with a slight toss. It adds no yaw spin. Vertical hits use the body's forward direction for tipping and retain only the configured small lift. `Speed` controls travel, `Lift` controls the tiny hop, and `TiltImpulse` controls how strongly the body falls over. Natural movement is still inherited. These use Roblox's [assembly impulse APIs](https://create.roblox.com/docs/physics/assemblies).

Colliding parts can still participate in raycasts even when `CanQuery` is false. The shared query helper explicitly excludes the configured corpse folder, so bodies cannot absorb knife throws, block revolver hits, redirect the cosmetic arm pose, or intercept player hover.

## Revolver aiming correction

The old arm sampler extended close hits at least 12 studs along the camera ray. With a high, zoomed-out camera, that extension could put the arm target below the floor despite the cursor pointing at a nearby player in front. The arm now follows the actual cursor hit, rejecting only a degenerate target within 0.75 studs of the shoulder (`RevolverConfig.Default.Pose.MinAimDistance`).

The head supplies a stable target-selection reference for the pose, client prediction and server shot resolver. Moving the visual muzzle no longer moves the camera-ray sampling plane. Near-camera clipping also stops at the horizontal character plane if the perpendicular camera plane would skip an elevated forward target. Both corrections stay on the exact cursor ray, including free aim and ADS. A truly vertical ray uses the perpendicular plane to avoid division by a vanishing horizontal direction.

Bullets still originate at the validated physical muzzle and stop at cover. The head-to-camera obstruction check, muzzle-through-wall fallback, victim cover check, finite input validation, ammo, cadence, range and server authority remain enforced. Arm angle packets still carry no damage authority.

## Research references

The implementation follows primary Roblox documentation:

- [Ball sockets](https://create.roblox.com/docs/physics/constraints/ball-socket): coincident attachments with swing and twist bounds.
- [Humanoid API source](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml): `BreakJointsOnDeath`, `RequiresNeck` and `EvaluateStateMachine`; disabling the cloned Humanoid's state machine preserves appearance without humanoid forces/collision changes.
- [Network ownership](https://create.roblox.com/docs/physics/network-ownership): server ownership of the finished physical mechanism, with conservative corpse lifetimes/budgets.
- [Assemblies](https://create.roblox.com/docs/physics/assemblies): assign inherited motion after the completed joints enter Workspace, then apply a small body nudge and torso angular impulse.
- [Collision filtering](https://create.roblox.com/docs/workspace/collisions): let corpse bodies contact the map while disabling contact with living characters and other corpses.
- [BasePart API source](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/BasePart.yaml): CanQuery restrictions on colliding parts, assembly velocities and impulse APIs.
- [Camera API](https://create.roblox.com/docs/reference/engine/classes/Camera) and [raycasting](https://create.roblox.com/docs/workspace/raycasting): cursor rays and explicit ray filtering, shared by prediction and authority.

## Verification

Run the three actual-source suites with the official Luau CLI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-ragdolls.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-revolver-presentation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-game-systems.ps1
```

Supply `-LuauPath "C:\path\to\luau.exe"` if the executable is outside the existing validation-tool directory. Tests cover R6/R15 constraint construction, appearance/sanitization, impact ownership, velocity limits, duplicate deaths, early character replacement, connection cleanup, corpse budgets/timers, malformed rigs, configurable exclusions, weapon/death integration, overhead close/elevated targets and real muzzle cover. The stand-ins validate code and geometry; they do not simulate Roblox physics or render the models.

In Studio with two clients:

1. Kill with each revolver, knife stab and knife throw while standing, sprinting, crouching, jumping and aiming. Confirm both clients see a connected body fall, with clothing/accessories intact and no floating weapon displays.
2. Watch the corpse through FFA respawn and Battle Royale lobby return. Time five seconds from death; the body should disappear without affecting the new character. Repeat reset/zone death, disconnects and several rapid kills.
3. Walk and fire through corpses. Verify map contact still works, surviving players remain hittable, stab cover checks work and hover selects living players.
4. Zoom out to the revolver's limit and raise the camera. Aim at nearby, distant, crouching and elevated targets in front in free aim and ADS. Check that the arm follows the target and impacts land there. Repeat first person and near walls/ledges; actual barrel cover must still block shots.
5. Check the actual avatar shapes/Tool grips, StreamingEnabled behavior and physics cost on the lowest supported device. R15 construction is covered by stand-ins; this game's R6 presentation and any future R15 avatars need visual/physical Studio verification.

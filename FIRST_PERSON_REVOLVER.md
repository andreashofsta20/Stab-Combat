# First-person weapon presentation

Revolvers and knives use the same camera-only R6 renderer. They appear only at full zoom (0.55-stud entry, 0.6-stud exit tolerance). The renderer copies the equipped skin, classic shirt and avatar arms, with thinner arms and restrained sway/bob. Revolver aiming moves the hold left and down; recoil and reload motion remain smooth. Knives show one hand, a progressive charge pose, stab motion and throw release. The held knife disappears during its existing 0.15–0.65-second return window.

First-person camera models contain geometry and appearance only. No particles, beams, trails, lights or legacy effects are cloned. Original weapon effects are locally suppressed while the model is active and restored when leaving first person. Your own first-person revolver shots create no muzzle particles, flash, smoke, tracer or impact burst; audio and recoil remain. First-person knife throws retain the visible flying blade and audio without added trails or impact bursts. Other players retain their normal world effects. Suppression is recorded with each predicted shot so a delayed acknowledgement cannot bring back its impact effects after zooming out.

The camera smoothly lowers 0.7 studs when crouching and 1 stud when sliding. Movement animation publishes its actual posture, so holding crouch in the air or after death does not retain the drop. Camera rotation stays with the native camera. Both camera position and Focus move down equally to preserve the zoom distance; hands and weapons follow the lowered camera. Body and shoulder animation add bounded local posture movement.

## Code and configuration

| Module | Responsibility |
| --- | --- |
| `WeaponViewmodel` | Independent manager per weapon: full-zoom gating, retries, local visibility ownership and cleanup |
| `WeaponViewmodelGeometry` | Safe shallow copies, original-to-copy appearance mapping, cached multipart placement and physics guards |
| `WeaponViewmodelEffects` | Local suppression/restoration of original skin effects; creates no effects |
| `RevolverViewmodel` / `KnifeViewmodel` | Weapon adapters for the shared renderer |
| `RevolverViewmodelMath` / `KnifeViewmodelMotion` | Smooth camera-local motion and knife charge/attack poses |
| `FirstPersonPostureCamera` | Applies the movement camera height after native camera and ADS updates |
| `RevolverToolPhysics` | Keeps the real held weapon noncolliding and massless on server and client |

The old `RevolverViewmodelGeometry` and `RevolverViewmodelEffects` names remain compatibility wrappers around the shared modules.

Tune revolvers in `RevolverConfig.Default.FirstPerson`, with per-skin `Overrides[skinName].FirstPerson`. Tune the knife in `KnifeConfig.FirstPerson`, including `ChargeOffset`, `ChargeRotationDegrees`, `StabOffset`, `ThrowOffset` and their response speeds. Revolver arms default to 80% width/depth; knife arms default to 75%. Length and authored RightGrip remain intact. `SupportArmEnabled=false` hides the knife's left support arm.

Tune camera height independently in `FirstPersonCameraConfig`: `CrouchDrop`, `SlideDrop`, `FollowSpeed`, `EnterDistance` and `ExitDistance`. Camera and weapon zoom thresholds use the same defaults. Restart Play after changing module configuration.

The default budget is 64 weapon parts plus two arms and up to three invisible clothing shell parts. Models are built on demand, reused while equipped, and rebuilt when relevant descendants change. Missing limbs/Handle or transient failures retry automatically after 0.1 seconds, with error backoff capped at one second. Failed presentation restores the real weapon and releases listeners. Menus, VR and camera takeovers suspend the model; unequip, death, respawn and errors clear it.

Ordinary rendering scans no descendants and creates no Instances. Cached source part transforms are refreshed relative to the real Handle, so a multipart skin that finishes positioning after equip does not retain the clone's initial offset. Existing mesh offsets, texture face parenting and material settings are preserved. Property listeners follow later appearance changes; adding/removing textures or parts triggers one rebuild. Mesh-based arm slimming avoids applying the width/depth scale twice to block meshes.

## Physics and camera ownership

Camera parts are anchored, noncolliding, nontouchable, nonqueryable, massless and shadowless. They belong to the server-registered `RevolverViewmodels` group, which cannot collide with any registered group. Clients wait for setup and registry replication before parenting a model. Cached guards repair changed flags. The invisible R6 clothing Humanoid is created fresh with state evaluation and movement disabled before parenting; no live Tool, Humanoid, joint, constraint, mover or script is cloned.

The real revolver and knife are also made noncolliding and massless, including late parts and skin-script resets. No player velocity clamping or root movement is involved. Physical muzzle/knife origin, damage, cover checks, ammo, charge timing and server authority stay in the combat code.

The posture camera removes its previous owned shift at Camera−1, native camera runs at Camera, ADS runs at Camera+1, posture lowers the view at Camera+2, and weapons place their models at Camera+3. It checks ownership before restoring so a replacement camera is not overwritten. Shifting CFrame and Focus together prevents accumulating height changes or corrupting the full-zoom gate.

## Research basis

Roblox's [render scheduling documentation](https://create.roblox.com/docs/reference/engine/classes/RunService#BindToRenderStep) and [task scheduler guidance](https://create.roblox.com/docs/performance-optimization/microprofiler/task-scheduler) inform the update order and limited render work. [Motor6D.Transform](https://create.roblox.com/docs/reference/engine/classes/Motor6D#Transform) supplies actual animation posture; the revolver aim layer saves its animation sample before procedural aiming.

Roblox documents [Texture](https://create.roblox.com/docs/reference/engine/classes/Texture) as an image on its parent part face, and [DataModelMesh.Offset](https://create.roblox.com/docs/reference/engine/classes/DataModelMesh#Offset) as the mesh's local offset. The observed displaced image was not reproduced from an asset here; stale multipart positioning was a concrete renderer gap and is now corrected without recentering authored meshes.

[LocalTransparencyModifier](https://create.roblox.com/docs/reference/engine/classes/BasePart#LocalTransparencyModifier) hides original body/weapon parts locally. Separate local modifiers for [particles](https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter#LocalTransparencyModifier), [beams](https://create.roblox.com/docs/reference/engine/classes/Beam#LocalTransparencyModifier) and [trails](https://create.roblox.com/docs/reference/engine/classes/Trail#LocalTransparencyModifier) hide skin effects; hidden particle rate and light brightness are temporarily zero on this client. Unsupported legacy effects use Smoke opacity or enabled state. Already emitted legacy particles may remain until their engine lifetime ends when no local modifier is available.

[Collision filtering](https://create.roblox.com/docs/workspace/collisions#collision-filtering) provides a second contact barrier beyond part flags. [Humanoid.EvaluateStateMachine](https://create.roblox.com/docs/reference/engine/classes/Humanoid#EvaluateStateMachine) disables the fresh clothing renderer's physics evaluation. This construction avoids references to the live character controller.

## Verification

Run these scripts with the official Luau CLI at their default temporary path, or provide `-LuauPath`:

- `scripts/test-revolver-presentation.ps1`: actual-source geometry, effects, lifecycle, visibility, controller and combat regressions.
- `scripts/test-knife-viewmodel.ps1`: knife motion, frame-rate consistency and shared adapter checks.
- `scripts/test-first-person-camera.ps1`: camera height, zoom ownership, drift prevention, ADS preservation and lifecycle checks.
- `scripts/test-game-systems.ps1`: movement posture publication and existing game systems.
- `scripts/test-revolver-tool-physics.ps1`: real weapon physics guards.
- `scripts/test-ragdolls.ps1`: existing death presentation behavior.

Automated tests use Roblox stand-ins. Native texture rendering, cloth fit, camera clipping and device performance require the real place. In a fresh Studio Play session, check several skins, repeated equips, full-zoom transitions, crouch/slide, aim, reload, knife charge/stab/throw, menus, death and respawn. Include throwing in third person and zooming in before the knife returns, then zooming out again. Check owner VFX suppression and a second player's normal effects.

For a read-only native physics sample, equip either weapon in first person and paste `scripts/check-first-person-physics.client.luau` into Studio's Client Command Bar. It checks two seconds of actual collision contacts, assembly references, real-tool flags, duplicate camera models and unwanted cloned effects. Compare MicroProfiler timings on a low-end device; no FPS measurements or live Studio visual approval have been performed here.

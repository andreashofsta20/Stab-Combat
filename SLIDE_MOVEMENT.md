# Slide movement

The slide now accelerates into its boost over 0.1 seconds, decelerates with a smooth curve, and ends at the current walking or sprinting speed. Its animation blends over 0.18 seconds and plays once across the 0.8-second slide. Releasing sprint changes the exit speed without cancelling momentum.

`SlideController` uses a finite-force `LinearVelocity` in plane mode. Both axes follow the walkable ground tangent, so slopes have an uphill/downhill component while normal gravity remains free. The humanoid retains its state machine, collisions, and native jump behavior. Physics targets update in `PreSimulation`, and terrain probes run at most 30 times per second only during a slide. Two prepared Instances and query parameters are reused until character cleanup.

Small steps up to 0.85 studs receive a physical upward impulse whose maximum rise is step height plus 0.1 studs. It requires a walkable top surface, no character obstacle, clear body/head space, and clear forward/upward sweeps. An overlap query covers the starting-overlap case omitted by blockcasts; the upward sweep also covers terrain ceilings. No root teleport or collision disabling occurs. A short ground grace blends across seams and checked step lifts; jumping, death, climbing, and sustained freefall cancel the force immediately or after the bounded grace.

Research basis:

- [RunService](https://create.roblox.com/docs/reference/engine/classes/RunService) and [task scheduler](https://create.roblox.com/docs/performance-optimization/microprofiler/task-scheduler): update forces/velocity before simulation rather than after physics or inside rendering work.
- [LinearVelocity](https://create.roblox.com/docs/reference/engine/classes/LinearVelocity): plane mode controls velocity along two axes, and enabled force limits avoid unlimited force pushing against obstacles.
- [WorldRoot](https://create.roblox.com/docs/reference/engine/classes/WorldRoot): use blockcasts and overlap checks for body clearance; a cast does not detect initial intersecting parts.
- [BasePart](https://create.roblox.com/docs/reference/engine/classes/BasePart): apply a bounded impulse for an instantaneous lift instead of writing the assembly velocity every frame; add support velocity with `GetVelocityAtPosition` for moving floors.
- [Humanoid](https://create.roblox.com/docs/reference/engine/classes/Humanoid): ground distance accounts for the different R6/R15 `HipHeight` conventions and preserves existing slope/state behavior.

Validation: `scripts/test-movement-slide.ps1` executes production math/controller code with deterministic vectors and spatial-query fixtures. It covers ramps, moving platforms, finite forces, frame-rate independence, step clearance, walls/ceilings, air/jump cancellation, bounded probe work, and cleanup. The movement sections of `scripts/test-game-systems.ps1` cover animation/input integration.

Native Roblox physics and animation assets require a Studio playtest. Check flat-to-ramp transitions, repeated 0.1–0.85-stud steps at 30/60/144 FPS, low ceilings, a full-height wall, diagonal stair edges, stepping followed by jump, walking off a ledge, and death/respawn during a slide. Inspect the MicroProfiler during slides and after cleanup; this change adds no terrain queries while idle and makes no measured FPS claim without that playtest.

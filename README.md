#Powered by ROJO.
[Rojo](https://github.com/rojo-rbx/rojo)

## About this project
I started with this project around 6 months ago and have gotten a long way but still lots left to do.


## Source
If this source ever gets open to the public, ill leave a full documentation below. Yes, the source is messy but understandable and rarely bugs out. 

See [Game setup and source review](GAME_SETUP_AND_REVIEW.md) for Burger setup, cursor fixes, data handling findings, remaining persistence issues and verification steps.
See [Gameplay reliability review](GAMEPLAY_RELIABILITY.md) for keybinds, rewards/quest migration, hover profiles, the Cargo Port lobby preview, knife/mobile controls, animation recovery and configuration.
See [Weapon effects and round music](WEAPON_CONFIGS.md) for faster knife throws, Frostbite effects, per-revolver overrides, music IDs and the round/kill fixes.
See [Death ragdolls and camera aiming](RAGDOLL_AND_AIMING.md) for five-second avatar corpses, joint/impact tuning, steep-camera fixes, research references and Studio checks.
See [First-person weapon presentation](FIRST_PERSON_REVOLVER.md) for avatar hands, the knife thrust, configurable revolver muzzle/bullet marks, spectator behavior, performance bounds and skin-specific tuning.
See [Performance and combat polish](PERFORMANCE_AND_COMBAT_POLISH.md) for equip scheduling, jump/inspect stability, clearer kill/damage UI, knife embedding, smoother sliding, research and profiling checks.
See [Source and remote audit](SOURCE_AUDIT.md) for resource cleanup, all 25 remote handlers, bounded backend work, menu camera behavior and verification limits.
See [Daily shop and shop navigation](DAILY_SHOP.md) for daily offers, prices/level gates, template names, the existing remote protocol, UTC resets, case category tabs, smooth shop transitions and steadier first-person hands.
See [Solo Studs tutorial setup](TUTORIAL_SETUP.md) for the new private training place, action lessons, once-only starter reward, configuration, asset preflight and published-server acceptance checks. [Tutorial research](TUTORIAL_RESEARCH.md) explains the UX and security decisions.
Startup tuning is in [StartupConfig](src/Modules/StartupConfig.luau); [the loading review](GAMEPLAY_RELIABILITY.md#startup-loading-and-failures) describes service readiness, diagnostics and the Studio validation steps.


## Who am i?
My name is Andreas, a small roblox developer who makes games for fun.


2.1.2026

## Beta release readiness (estimate)
- If the core loop remains stable and the items below are completed, a beta could be ready in ~4-6 weeks of focused solo work.
- Minimum beta goals to add:
  - Trading (player-to-player inventory swaps + safety checks)
  - Sound effects pass (walking, running, sliding, case open, UI click/hover)
  - AFK tagging + idle handling
  - Admin panel (moderation + live ops)
  - Basic anti-exploit checks (server-side validation for rewards, inventory, and combat)
  - Onboarding polish (tutorial prompt + clear controls)

## Important issues to verify before beta
- Ensure `ReplicatedStorage/KeyBinds/DefaultKeybinds` is present in the Rojo tree (it is required by server scripts but not in this repo).
- Reduce debug log spam (`print` in Emote/HandleKnifeCombat) before release.
- Confirm DataStore saves succeed under load (watch for `Failed to save data` warnings and throttling).

## Feature backlog
- Trading
- Sound effects (mostly everything)
  - Walking
  - Running
  - Sliding
  - Opening case (fast and slow)
  - UI Click
  - UI Hover (possibly)
- AFK TAG
- Add admin panel

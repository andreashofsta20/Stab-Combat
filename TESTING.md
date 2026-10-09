# Regression verification

Use the official [Luau 0.741 release](https://github.com/luau-lang/luau/releases/tag/0.741). Rojo is pinned to 7.7.0-rc.1 in `aftman.toml`; dependencies under `Packages` are already tracked.

On macOS, Linux or Windows with Python 3.9 or newer:

```sh
python3 scripts/test-all.py --luau /path/to/luau
python3 scripts/test-all.py --luau /path/to/luau --suite game-systems --test-filter "round"
python3 scripts/test-all.py --luau /path/to/luau --compile /path/to/luau-compile --rojo /path/to/rojo
```

Use `python` instead of `python3` where appropriate. Pass `--output-dir /path/to/results` to retain generated bundles, logs and the optional place build. The runner returns nonzero for any failed suite, timeout, unsupported bundle expression, compilation failure or failed build. Unknown suites and filters matching no game-systems tests fail.

The adapter reads module paths and environment wrappers from the existing `scripts/test-*.ps1` files. It supports their explicit bundle construction forms; it does not execute PowerShell. Update the adapter if a runner introduces a new form. The case viewport suite extracts the same production reel sections using the native runner's anchors.

The existing Windows entry points remain supported:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-performance-polish.ps1 -LuauPath C:\tools\luau.exe
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-game-systems.ps1 -LuauPath C:\tools\luau.exe -TestFilter "round"
```

`.github/workflows/verify.yml` runs both entry points, script compilation and a Rojo build on Windows. Downloads use fixed versions and release SHA-256 digests: [Luau assets](https://github.com/luau-lang/luau/releases/expanded_assets/0.741), [Rojo assets](https://github.com/rojo-rbx/rojo/releases/expanded_assets/v7.7.0-rc.1). The initial implementation snapshot passed the hosted [Windows Verify run](https://github.com/andreashofsta20/Stab-Combat/actions/runs/37841171652), including the native PowerShell entry points. Check the final head’s run on the draft PR before treating later edits as hosted-verified.

These fixtures cover deterministic source behavior with mocked Roblox services. Compilation checks syntax, not Roblox-aware types. Studio is still required for asset availability, rendering, physics, replication timing, real backend failures and performance. See the native test matrix and open risks in `BETA_AUDIT_2026-10-08.md`.


## Native Roblox verification

Use an authored test place containing the native maps, GUI, remotes and tools. The successful audit runs targeted place 119874582058419, universe 9667193329. The CLI overlays checkout sources in memory and does not save or publish the place. See the [Roblox Studio CLI](https://create.roblox.com/docs/studio/command-line-interface) and [StudioTestService](https://create.roblox.com/docs/reference/engine/classes/StudioTestService) documentation.

Build the Rojo model and generate the short test launcher plus its JSON payload:

```sh
rojo build default.project.json -o /tmp/stab-native/Stab-Combat.rbxlx
python3 scripts/build-studio-tests.py --model /tmp/stab-native/Stab-Combat.rbxlx --output /tmp/stab-native/run.luau --players 2 --respawns 3
python3 -m http.server 8765 --bind 127.0.0.1 --directory /tmp/stab-native
```

Create `/tmp/stab-native` before the build. Keep the loopback payload server running in a separate terminal. On macOS, run:

```sh
/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio --task RunScript --placeId 119874582058419 --universeId 9667193329 --runScriptFile /tmp/stab-native/run.luau --outputFile /tmp/stab-native/results.log --quitAfterExecution
```

On Windows, use RobloxStudioBeta.exe with the same flags. Run one native Studio test at a time and let it clean up before starting another. The JSON after `STAB_NATIVE_REPORT` is the result. `Started=true` alone is not success: require a structured result, all expected players, no Fatal, and Passed=true for each required assertion. Studio test-client launch failures are acceptance failures even when source suites pass.

The default harness replaces DataStoreService calls with an in-memory adapter and uses ProfileStore.Mock. `--real-backend` preserves actual service calls but rewrites profile, legacy, VIP, receipt, quest, admin, leaderboard scope and backend probe names to a new BetaAudit_20261008 namespace. It checks durable profile rereads and receipt archival/replay. Never remove that namespace isolation when testing against this experience.

`--startup-matrix` tests six missing required map/tool assets without clients; inspect `STAB_STARTUP_REPORT`. `--players 8`, `--respawns 30` and `--soak-seconds 1800` request larger scenarios. A missing final report means the soak is incomplete. The client metric helper stores at most 600 frame samples; simultaneous background Studio instances do not represent device FPS.

The separate `studio-inspect.luau`, `studio-assets.luau` and `studio-assets-play.luau` scripts inspect authored assets. The typed client asset script uses temporary instances strictly to verify delivery; production image/texture preload queues are disabled. Raw-ID preload failures alone are not evidence that an asset cannot render.

Actual results and unsuccessful attempts are retained under [audit-results/2026-10-08](audit-results/2026-10-08) and explained in section M of [the audit](BETA_AUDIT_2026-10-08.md). High-ping gameplay, native final retesting, cross-server/backend failure injection, intended population, visual/device acceptance and a completed long soak remain open.

## Solo tutorial verification

Run all tutorial security/recovery fixtures with:

```sh
python3 scripts/test-all.py --luau /path/to/luau --suite tutorial
```

The complete runner also discovers `test-tutorial.ps1`; keep the existing game-systems, movement, food and revolver suites passing because practice reuses those production paths. On Windows the native entry point is `scripts/test-tutorial.ps1 -LuauPath C:\tools\luau.exe`.

For native UI, character and knife geometry checks, build an isolated unsaved overlay:

```sh
mkdir -p /tmp/stab-tutorial-native
rojo build default.project.json -o /tmp/stab-tutorial-native/Stab-Combat.rbxlx
python3 scripts/build-tutorial-studio-tests.py --model /tmp/stab-tutorial-native/Stab-Combat.rbxlx --output /tmp/stab-tutorial-native/run.luau --port 8776
python3 -m http.server 8776 --bind 127.0.0.1 --directory /tmp/stab-tutorial-native
```

Keep the payload server running, then use a separate terminal:

```sh
/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio --task RunScript --placeId 119874582058419 --universeId 9667193329 --runScriptFile /tmp/stab-tutorial-native/run.luau --outputFile /tmp/stab-tutorial-native/results.log --quitAfterExecution
```

The installer requires that exact authored test place/universe and Studio; it disables original scripts, overlays the latest source, substitutes an in-memory DataStoreService adapter, and enables **mock-only, rewardless** tutorial preview in the payload. It never saves or publishes the authored place. Ordinary client startup is disabled to test UI without duplicate controllers. Missing authored Studs is explicitly reported as a `Classic ROBLOX test alias`; this is not acceptance of your production Studs map.

Require `Started=true`, structured `Result.AllPassed=true`, all native test assertions passing, one connected player, no fatal/runtime errors and all ten client bounds/cleanup checks passing. Read `MapFixture`, `SyntheticActions` and `Travel`: the harness exercises actual production stab/throw against native targets, but drives several remaining server action events synthetically. It does not prove physical touch/controller gameplay, normal full-client startup, or real teleport/storage handoff. Never infer full release readiness just from `AllPassed`.

Run [the read-only place preflight](scripts/validate-tutorial-place.luau) against the prepared destination. Follow [TUTORIAL_SETUP.md](TUTORIAL_SETUP.md) for actual published-client round trips, save-failure recovery, rewards/replays, device controls and abuse checks. [TUTORIAL_VERIFICATION.md](TUTORIAL_VERIFICATION.md) records this checkout's actual results and limitations.

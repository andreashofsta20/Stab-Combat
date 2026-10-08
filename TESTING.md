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

`.github/workflows/verify.yml` runs both entry points, script compilation and a Rojo build on Windows. Downloads use fixed versions and release SHA-256 digests: [Luau assets](https://github.com/luau-lang/luau/releases/expanded_assets/0.741), [Rojo assets](https://github.com/rojo-rbx/rojo/releases/expanded_assets/v7.7.0-rc.1). The workflow must run on GitHub before its hosted result can be claimed.

These fixtures cover deterministic source behavior with mocked Roblox services. Compilation checks syntax, not Roblox-aware types. Studio is still required for asset availability, rendering, physics, replication timing, real backend failures and performance. See the native test matrix and open risks in `BETA_AUDIT_2026-10-08.md`.

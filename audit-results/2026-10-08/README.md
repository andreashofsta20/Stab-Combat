# Audit evidence — 8 October 2026

Sanitized structured output only; Studio process logs are excluded.

- `local-verification.json`: 22 passing fixture suites, syntax compilation, Rojo build and whitespace results.
- `native-startup.json`: six missing required map/tool cases, all fail-closed as expected.
- `native-place.json` / `native-assets.json`: authored template availability, readable settings and typed client asset delivery. Asset verification does not enable runtime texture preloading.
- `native-mock.json`: retained behavior from the earlier two-player mock run.
- `native-backend.json`: isolated real DataStores; trade, profile reread and receipt replay passed, FFA respawn timed out.
- `native-final-launch.json`: final rerun connected one of two clients and timed out; no multiplayer assertions ran.
- `native-load-attempt.json` / `native-soak-attempt.json`: incomplete population/long-session attempts.

Earlier native runs precede final removal of the optional mode and the death-listener race fix. Their unrelated, retained assertions are useful evidence but do not certify the final source. The BR assertion following the real-backend FFA failure is not used for current BR acceptance. See [the audit](../../BETA_AUDIT_2026-10-08.md#m-authorized-implementation-and-acceptance-evidence) for interpretation and remaining native checks.

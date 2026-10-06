param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$knifeProjectileRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$knifeProjectileModules = [ordered]@{
    Config = 'src/Modules/KnifeConfig.luau'
    EffectsConfig = 'src/Modules/KnifeEffectsConfig.luau'
    Math = 'src/Modules/ProjectileMath.luau'
    Visual = 'src/PlayerClient/Modules/KnifeVisual.luau'
    Effects = 'src/PlayerClient/Modules/KnifeEffects.luau'
    Controller = 'src/PlayerClient/Modules/CombatController.luau'
}
$knifeProjectileBundle = [System.Text.StringBuilder]::new()
[void]$knifeProjectileBundle.AppendLine('local loaders = {}')
foreach ($knifeProjectileEntry in $knifeProjectileModules.GetEnumerator()) {
    [void]$knifeProjectileBundle.AppendLine("loaders.$($knifeProjectileEntry.Key) = function(env)")
    [void]$knifeProjectileBundle.AppendLine('local game, workspace, script, require, Instance = env.game, env.workspace, env.script, env.require, env.Instance')
    [void]$knifeProjectileBundle.AppendLine('local task, os, Enum = env.task, env.os or os, env.Enum')
    [void]$knifeProjectileBundle.AppendLine('local Vector3, CFrame, typeof = env.Vector3, env.CFrame, env.typeof or typeof')
    [void]$knifeProjectileBundle.AppendLine('local Color3, ColorSequence, ColorSequenceKeypoint = env.Color3, env.ColorSequence, env.ColorSequenceKeypoint')
    [void]$knifeProjectileBundle.AppendLine('local NumberRange, NumberSequence, Vector2 = env.NumberRange, env.NumberSequence, env.Vector2')
    [void]$knifeProjectileBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $knifeProjectileRoot $knifeProjectileEntry.Value)))
    [void]$knifeProjectileBundle.AppendLine('end')
}
[void]$knifeProjectileBundle.AppendLine('local tests = (function()')
[void]$knifeProjectileBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $knifeProjectileRoot 'tests/knife-projectiles.spec.luau')))
[void]$knifeProjectileBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$knifeProjectileTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-knife-projectiles-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($knifeProjectileTestFile, $knifeProjectileBundle.ToString())
    & $LuauPath $knifeProjectileTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Knife projectile tests failed.' }
} finally {
    Remove-Item -LiteralPath $knifeProjectileTestFile -ErrorAction SilentlyContinue
}

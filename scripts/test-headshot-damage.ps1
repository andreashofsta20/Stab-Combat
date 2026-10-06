param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$headshotRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$headshotModules = [ordered]@{
    Config = 'src/Modules/RevolverConfig.luau'
    Math = 'src/Modules/RevolverMath.luau'
    Raycast = 'src/Modules/RevolverRaycast.luau'
    History = 'src/server/CombatHandler/RevolverHitHistory.luau'
    State = 'src/server/CombatHandler/RevolverState.luau'
    Server = 'src/server/CombatHandler/HandleRevolver.luau'
    KnifeConfig = 'src/Modules/KnifeConfig.luau'
    Projectile = 'src/Modules/ProjectileMath.luau'
    Throw = 'src/server/CombatHandler/ThrowKnife.luau'
}
$headshotBundle = [System.Text.StringBuilder]::new()
[void]$headshotBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($headshotEntry in $headshotModules.GetEnumerator()) {
    [void]$headshotBundle.AppendLine("loaders.$($headshotEntry.Key) = function(env)")
    [void]$headshotBundle.AppendLine('local game, workspace, script, require = env.game, env.workspace, env.script, env.require')
    [void]$headshotBundle.AppendLine('local CFrame, Vector3, Instance, Enum = env.CFrame, env.Vector3, env.Instance, env.Enum')
    [void]$headshotBundle.AppendLine('local RaycastParams, task = env.RaycastParams, env.task')
    [void]$headshotBundle.AppendLine('local typeof, os = env.typeof or nativeTypeof, env.os or os')
    [void]$headshotBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $headshotRoot $headshotEntry.Value)))
    [void]$headshotBundle.AppendLine('end')
}
[void]$headshotBundle.AppendLine('local tests = (function()')
[void]$headshotBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $headshotRoot 'tests/headshot-damage.spec.luau')))
[void]$headshotBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$headshotTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-headshot-damage-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($headshotTestFile, $headshotBundle.ToString())
    & $LuauPath $headshotTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Headshot damage tests failed.' }
} finally {
    Remove-Item -LiteralPath $headshotTestFile -ErrorAction SilentlyContinue
}

param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$revolverRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$revolverModules = [ordered]@{
    Config = 'src/Modules/RevolverConfig.luau'
    Math = 'src/Modules/RevolverPoseMath.luau'
    RayMath = 'src/Modules/RevolverMath.luau'
    Raycast = 'src/Modules/RevolverRaycast.luau'
    Pose = 'src/PlayerClient/Modules/RevolverAimPose.luau'
    Camera = 'src/PlayerClient/Modules/RevolverAimCamera.luau'
    Controller = 'src/PlayerClient/Modules/RevolverController.luau'
    Effects = 'src/PlayerClient/Modules/RevolverEffects.luau'
    State = 'src/server/CombatHandler/RevolverState.luau'
    Server = 'src/server/CombatHandler/HandleRevolver.luau'
}
$revolverBundle = [System.Text.StringBuilder]::new()
[void]$revolverBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($revolverEntry in $revolverModules.GetEnumerator()) {
    [void]$revolverBundle.AppendLine("loaders.$($revolverEntry.Key) = function(env)")
    [void]$revolverBundle.AppendLine('local game, workspace, script, require = env.game, env.workspace, env.script, env.require')
    [void]$revolverBundle.AppendLine('local CFrame, Vector3, Vector2, Instance = env.CFrame, env.Vector3, env.Vector2, env.Instance')
    [void]$revolverBundle.AppendLine('local RaycastParams, UDim2 = env.RaycastParams, env.UDim2')
    [void]$revolverBundle.AppendLine('local typeof, os, Enum = env.typeof or nativeTypeof, env.os or os, env.Enum')
    [void]$revolverBundle.AppendLine('local warn = env.warn or function() end')
    [void]$revolverBundle.AppendLine('local Color3, ColorSequence, ColorSequenceKeypoint = env.Color3, env.ColorSequence, env.ColorSequenceKeypoint')
    [void]$revolverBundle.AppendLine('local NumberRange, NumberSequence, NumberSequenceKeypoint, TweenInfo = env.NumberRange, env.NumberSequence, env.NumberSequenceKeypoint, env.TweenInfo')
    [void]$revolverBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $revolverRoot $revolverEntry.Value)))
    [void]$revolverBundle.AppendLine('end')
}
[void]$revolverBundle.AppendLine('local tests = (function()')
[void]$revolverBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $revolverRoot 'tests/revolver-presentation.spec.luau')))
[void]$revolverBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$revolverTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-revolver-presentation-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($revolverTestFile, $revolverBundle.ToString())
    & $LuauPath $revolverTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Revolver presentation tests failed.' }
} finally {
    Remove-Item -LiteralPath $revolverTestFile -ErrorAction SilentlyContinue
}

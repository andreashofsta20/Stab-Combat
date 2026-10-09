param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$revolverRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$revolverModules = [ordered]@{
    Config = 'src/Modules/RevolverConfig.luau'
    KeybindValidation = 'src/Modules/KeybindValidation.luau'
    InspectConfig = 'src/Modules/WeaponInspectConfig.luau'
    InspectMotion = 'src/Modules/WeaponInspectMotion.luau'
    Math = 'src/Modules/RevolverPoseMath.luau'
    RayMath = 'src/Modules/RevolverMath.luau'
    Raycast = 'src/Modules/RevolverRaycast.luau'
    Pose = 'src/PlayerClient/Modules/RevolverAimPose.luau'
    Camera = 'src/PlayerClient/Modules/RevolverAimCamera.luau'
    ViewmodelMath = 'src/Modules/RevolverViewmodelMath.luau'
    WeaponGeometry = 'src/PlayerClient/Modules/WeaponViewmodelGeometry.luau'
    WeaponVisibility = 'src/PlayerClient/Modules/WeaponViewmodelVisibility.luau'
    WeaponEffects = 'src/PlayerClient/Modules/WeaponViewmodelEffects.luau'
    WeaponViewmodel = 'src/PlayerClient/Modules/WeaponViewmodel.luau'
    ViewmodelGeometry = 'src/PlayerClient/Modules/RevolverViewmodelGeometry.luau'
    ViewmodelEffects = 'src/PlayerClient/Modules/RevolverViewmodelEffects.luau'
    Viewmodel = 'src/PlayerClient/Modules/RevolverViewmodel.luau'
    ViewmodelPhysicsServer = 'src/server/RevolverViewmodelPhysics.luau'
    ToolPhysics = 'src/Modules/RevolverToolPhysics.luau'
    MouseVisibility = 'src/Modules/MouseCursorVisibility.luau'
    Controller = 'src/PlayerClient/Modules/RevolverController.luau'
    Effects = 'src/PlayerClient/Modules/RevolverEffects.luau'
    State = 'src/server/CombatHandler/RevolverState.luau'
    Server = 'src/server/CombatHandler/HandleRevolver.luau'
    TutorialRuntime = 'src/server/Tutorial/TutorialRuntime.luau'
    KnifeConfig = 'src/Modules/KnifeConfig.luau'
    KnifeMotion = 'src/Modules/KnifeViewmodelMotion.luau'
    Projectile = 'src/Modules/ProjectileMath.luau'
    KnifeThrow = 'src/server/CombatHandler/ThrowKnife.luau'
    KnifeStab = 'src/server/CombatHandler/StabKnife.luau'
    KnifeEffectsConfig = 'src/Modules/KnifeEffectsConfig.luau'
    KnifeEffects = 'src/PlayerClient/Modules/KnifeEffects.luau'
    KnifeVisual = 'src/PlayerClient/Modules/KnifeVisual.luau'
    KnifeController = 'src/PlayerClient/Modules/CombatController.luau'
}
$revolverBundle = [System.Text.StringBuilder]::new()
[void]$revolverBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($revolverEntry in $revolverModules.GetEnumerator()) {
    [void]$revolverBundle.AppendLine("loaders.$($revolverEntry.Key) = function(env)")
    [void]$revolverBundle.AppendLine('local game, workspace, script, require = env.game, env.workspace, env.script, env.require')
    [void]$revolverBundle.AppendLine('local CFrame, Vector3, Vector2, Instance = env.CFrame, env.Vector3, env.Vector2, env.Instance')
    [void]$revolverBundle.AppendLine('local RaycastParams, UDim2, UDim = env.RaycastParams, env.UDim2, env.UDim')
    [void]$revolverBundle.AppendLine('local OverlapParams, task = env.OverlapParams, env.task')
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

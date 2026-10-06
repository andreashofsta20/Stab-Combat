param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$deathTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$deathTestModules = [ordered]@{
    Config = 'src/Modules/SpectateConfig.luau'
    Transition = 'src/PlayerClient/Modules/DeathSpectateTransition.luau'
    Spectate = 'src/PlayerClient/Modules/SpectateHandler.luau'
    Frames = 'src/PlayerClient/FramesHandler.luau'
    RagdollMock = 'tests/support/ragdoll-mock.luau'
    RagdollConfig = 'src/Modules/RagdollConfig.luau'
    RagdollRig = 'src/server/CharacterDeath/RagdollRig.luau'
    RagdollService = 'src/server/CharacterDeath/RagdollService.luau'
    RagdollQuery = 'src/Modules/RagdollQuery.luau'
}
$deathTestBundle = [System.Text.StringBuilder]::new()
[void]$deathTestBundle.AppendLine('local loaders = {}')
foreach ($deathTestEntry in $deathTestModules.GetEnumerator()) {
    [void]$deathTestBundle.AppendLine("loaders.$($deathTestEntry.Key) = function(env)")
    [void]$deathTestBundle.AppendLine('local game, workspace, script, require = env.game, env.workspace, env.script, env.require')
    [void]$deathTestBundle.AppendLine('local Vector3, CFrame, Enum, Instance = env.Vector3, env.CFrame, env.Enum, env.Instance')
    [void]$deathTestBundle.AppendLine('local RaycastParams = env.RaycastParams')
    [void]$deathTestBundle.AppendLine('local task, os = env.task, env.os or os')
    [void]$deathTestBundle.AppendLine('local TweenInfo, typeof, warn = env.TweenInfo, env.typeof, env.warn or function() end')
    [void]$deathTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $deathTestRoot $deathTestEntry.Value)))
    [void]$deathTestBundle.AppendLine('end')
}
[void]$deathTestBundle.AppendLine('local tests = (function()')
[void]$deathTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $deathTestRoot 'tests/death-spectate.spec.luau')))
[void]$deathTestBundle.AppendLine('end)(); tests(function(name, env) return assert(loaders[name], name)(env or {}) end)')
$deathTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-death-spectate-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($deathTestFile, $deathTestBundle.ToString())
    & $LuauPath $deathTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Death/spectate tests failed.' }
} finally {
    Remove-Item -LiteralPath $deathTestFile -ErrorAction SilentlyContinue
}

param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$audioTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$audioTestModules = [ordered]@{
    Config = 'src/Modules/CombatAudioConfig.luau'
    RevolverConfig = 'src/Modules/RevolverConfig.luau'
    KnifeConfig = 'src/Modules/KnifeEffectsConfig.luau'
    KnifeRules = 'src/Modules/KnifeConfig.luau'
    Projectile = 'src/Modules/ProjectileMath.luau'
    ServerThrow = 'src/server/CombatHandler/ThrowKnife.luau'
    Audio = 'src/PlayerClient/Modules/RemoteWeaponAudio.luau'
    Initialize = 'src/PlayerClient/InitializeRemoteWeaponAudio.client.luau'
}
$audioTestBundle = [System.Text.StringBuilder]::new()
[void]$audioTestBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($audioTestEntry in $audioTestModules.GetEnumerator()) {
    [void]$audioTestBundle.AppendLine("loaders.$($audioTestEntry.Key) = function(env)")
    [void]$audioTestBundle.AppendLine('local game, workspace, script, require = env.game, env.workspace, env.script, env.require')
    [void]$audioTestBundle.AppendLine('local Vector3, CFrame, Enum, Instance = env.Vector3, env.CFrame, env.Enum, env.Instance')
    [void]$audioTestBundle.AppendLine('local RaycastParams = env.RaycastParams')
    [void]$audioTestBundle.AppendLine('local task, os, typeof = env.task, env.os or os, env.typeof or nativeTypeof')
    [void]$audioTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $audioTestRoot $audioTestEntry.Value)))
    [void]$audioTestBundle.AppendLine('end')
}
[void]$audioTestBundle.AppendLine('local tests = (function()')
[void]$audioTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $audioTestRoot 'tests/remote-weapon-audio.spec.luau')))
[void]$audioTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$audioTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-remote-weapon-audio-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($audioTestFile, $audioTestBundle.ToString())
    & $LuauPath $audioTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Remote weapon audio tests failed.' }
} finally {
    Remove-Item -LiteralPath $audioTestFile -ErrorAction SilentlyContinue
}

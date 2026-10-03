param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$ragdollRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$ragdollModules = [ordered]@{
    Config = 'src/Modules/RagdollConfig.luau'
    Query = 'src/Modules/RagdollQuery.luau'
    Rig = 'src/server/CharacterDeath/RagdollRig.luau'
    Service = 'src/server/CharacterDeath/RagdollService.luau'
    Mock = 'tests/support/ragdoll-mock.luau'
}
$ragdollBundle = [System.Text.StringBuilder]::new()
[void]$ragdollBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($ragdollEntry in $ragdollModules.GetEnumerator()) {
    [void]$ragdollBundle.AppendLine("loaders.$($ragdollEntry.Key) = function(env)")
    [void]$ragdollBundle.AppendLine('local game, workspace, script, require, Instance = env.game, env.workspace, env.script, env.require, env.Instance')
    [void]$ragdollBundle.AppendLine('local Vector3, CFrame, Enum, task = env.Vector3, env.CFrame, env.Enum, env.task')
    [void]$ragdollBundle.AppendLine('local typeof, warn = env.typeof or nativeTypeof, env.warn or function() end')
    [void]$ragdollBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $ragdollRoot $ragdollEntry.Value)))
    [void]$ragdollBundle.AppendLine('end')
}
[void]$ragdollBundle.AppendLine('local tests = (function()')
[void]$ragdollBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $ragdollRoot 'tests/ragdolls.spec.luau')))
[void]$ragdollBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$ragdollTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-ragdolls-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($ragdollTestFile, $ragdollBundle.ToString())
    & $LuauPath $ragdollTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Ragdoll tests failed.' }
} finally {
    Remove-Item -LiteralPath $ragdollTestFile -ErrorAction SilentlyContinue
}

param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$inspectTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$inspectModules = [ordered]@{
    Config = 'src/Modules/WeaponInspectConfig.luau'
    Motion = 'src/Modules/WeaponInspectMotion.luau'
    Controller = 'src/PlayerClient/Modules/WeaponInspectController.luau'
    Initialize = 'src/PlayerClient/InitializeWeaponInspect.client.luau'
}
$inspectBundle = [System.Text.StringBuilder]::new()
[void]$inspectBundle.AppendLine('local loaders = {}')
foreach ($entry in $inspectModules.GetEnumerator()) {
    [void]$inspectBundle.AppendLine("loaders.$($entry.Key) = function(env)")
    [void]$inspectBundle.AppendLine('env = env or {}; local game, workspace, script, require, os, Enum, CFrame = env.game, env.workspace, env.script, env.require, env.os, env.Enum, env.CFrame')
    [void]$inspectBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $inspectTestRoot $entry.Value)))
    [void]$inspectBundle.AppendLine('end')
}
[void]$inspectBundle.AppendLine('local tests = (function()')
[void]$inspectBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $inspectTestRoot 'tests/weapon-inspect.spec.luau')))
[void]$inspectBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$inspectTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-weapon-inspect-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($inspectTestFile, $inspectBundle.ToString())
    & $LuauPath $inspectTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Weapon inspect tests failed.' }
} finally {
    Remove-Item -LiteralPath $inspectTestFile -ErrorAction SilentlyContinue
}

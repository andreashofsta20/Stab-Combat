param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$equipTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$equipModules = [ordered]@{
    ServerHotbar = 'src/server/CombatHandler/HandleHotbar.luau'
    ClientHotbar = 'src/PlayerClient/Hotbar.luau'
    RecieveTools = 'src/PlayerClient/RecieveTools.luau'
}
$equipBundle = [System.Text.StringBuilder]::new()
[void]$equipBundle.AppendLine('local loaders = {}')
foreach ($entry in $equipModules.GetEnumerator()) {
    [void]$equipBundle.AppendLine("loaders.$($entry.Key) = function(env)")
    [void]$equipBundle.AppendLine('local game, script, require, Instance, task, os, Enum = env.game, env.script, env.require, env.Instance, env.task, env.os, env.Enum')
    [void]$equipBundle.AppendLine('local UDim2, Color3, TweenInfo = env.UDim2, env.Color3, env.TweenInfo')
    [void]$equipBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $equipTestRoot $entry.Value)))
    [void]$equipBundle.AppendLine('end')
}
[void]$equipBundle.AppendLine('local tests = (function()')
[void]$equipBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $equipTestRoot 'tests/tool-equip.spec.luau')))
[void]$equipBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$equipTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-tool-equip-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($equipTestFile, $equipBundle.ToString())
    & $LuauPath $equipTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Tool equip tests failed.' }
} finally {
    Remove-Item -LiteralPath $equipTestFile -ErrorAction SilentlyContinue
}

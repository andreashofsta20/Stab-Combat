param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$uiTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$uiTestModules = [ordered]@{
    Results = 'src/PlayerClient/RoundResults.luau'
    PlayerList = 'src/PlayerClient/PlayerList.luau'
    Inventory = 'src/PlayerClient/InventoryGui.luau'
    Health = 'src/PlayerCharacterClient/HealthBar.client.lua'
    Trading = 'src/PlayerClient/TradingClient.luau'
    TradeList = 'src/PlayerClient/TradePlayerList.luau'
    Emote = 'src/PlayerClient/Emote.luau'
    Overhead = 'src/PlayerClient/PlayerOverHead.luau'
    LobbyLighting = 'src/PlayerClient/Modules/LobbyLighting.luau'
    Settings = 'src/PlayerClient/SettingsClient.luau'
}
$uiTestBundle = [System.Text.StringBuilder]::new()
[void]$uiTestBundle.AppendLine('local loaders = {}')
foreach ($uiTestEntry in $uiTestModules.GetEnumerator()) {
    [void]$uiTestBundle.AppendLine("loaders.$($uiTestEntry.Key) = function(env)")
    [void]$uiTestBundle.AppendLine('local game, script, require, Instance = env.game, env.script, env.require, env.Instance')
    [void]$uiTestBundle.AppendLine('local workspace, Vector3 = env.workspace, env.Vector3')
    [void]$uiTestBundle.AppendLine('local task, os, Enum = env.task, env.os, env.Enum')
    [void]$uiTestBundle.AppendLine('local Color3, UDim2, Vector2, TweenInfo = env.Color3, env.UDim2, env.Vector2, env.TweenInfo')
    [void]$uiTestBundle.AppendLine('local tick, warn = function() return os.clock() end, function() end')
    [void]$uiTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $uiTestRoot $uiTestEntry.Value)))
    [void]$uiTestBundle.AppendLine('end')
}
[void]$uiTestBundle.AppendLine('local tests = (function()')
[void]$uiTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $uiTestRoot 'tests/client-ui-lifecycle.spec.luau')))
[void]$uiTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$uiTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-client-ui-lifecycle-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($uiTestFile, $uiTestBundle.ToString())
    & $LuauPath $uiTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Client UI lifecycle tests failed.' }
} finally { Remove-Item -LiteralPath $uiTestFile -ErrorAction SilentlyContinue }

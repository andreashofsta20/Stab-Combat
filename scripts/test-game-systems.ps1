param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$gameTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$gameTestModules = [ordered]@{
    FoodConfig = 'src/Modules/FoodConfig.luau'
    FoodState = 'src/server/CombatHandler/FoodState.luau'
    FoodService = 'src/server/CombatHandler/FoodService.luau'
    Hotbar = 'src/server/CombatHandler/HandleHotbar.luau'
    FoodClient = 'src/PlayerClient/HandleFood.luau'
    Profiles = 'src/server/DataStore/ProfileManager.luau'
    Purchases = 'src/server/ServicesHandler/PurchaseHandler.luau'
    Quests = 'src/server/ServicesHandler/QuestsHandler.luau'
    PlayerInfo = 'src/server/ServicesHandler/GetPlayerInfo.luau'
    Leaderboards = 'src/server/DataStore/LeaderboardsHandler.luau'
    Maps = 'src/server/Game/SpawnMap.luau'
    CursorConfig = 'src/Modules/CursorConfig.luau'
    Cursor = 'src/PlayerClient/HandleWeaponCursor.luau'
}
$gameTestBundle = [System.Text.StringBuilder]::new()
[void]$gameTestBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($gameTestEntry in $gameTestModules.GetEnumerator()) {
    [void]$gameTestBundle.AppendLine("loaders.$($gameTestEntry.Key) = function(env)")
    [void]$gameTestBundle.AppendLine('local game, workspace, script, require, Instance = env.game, env.workspace, env.script, env.require, env.Instance')
    [void]$gameTestBundle.AppendLine('local task, os, Enum, Random = env.task, env.os or os, env.Enum, env.Random')
    [void]$gameTestBundle.AppendLine('local Vector2, UDim2, Color3 = env.Vector2, env.UDim2, env.Color3')
    [void]$gameTestBundle.AppendLine('local CFrame = env.CFrame')
    [void]$gameTestBundle.AppendLine('local typeof, warn, print = env.typeof or nativeTypeof, env.warn or function() end, function() end')
    [void]$gameTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $gameTestRoot $gameTestEntry.Value)))
    [void]$gameTestBundle.AppendLine('end')
}
[void]$gameTestBundle.AppendLine('local tests = (function()')
[void]$gameTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $gameTestRoot 'tests/game-systems.spec.luau')))
[void]$gameTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$gameTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-game-systems-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($gameTestFile, $gameTestBundle.ToString())
    & $LuauPath $gameTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Game systems tests failed.' }
} finally {
    Remove-Item -LiteralPath $gameTestFile -ErrorAction SilentlyContinue
}

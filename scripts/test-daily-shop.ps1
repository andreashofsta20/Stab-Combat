param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$shopRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply the official Luau CLI with -LuauPath.' }
$shopModules = [ordered]@{
    Mock = 'tests/support/shop-mock.luau'
    Config = 'src/Modules/DailyShopConfig.luau'
    AnimationConfig = 'src/Modules/UIAnimationConfig.luau'
    Catalog = 'src/Modules/DailyShopCatalog.luau'
    Knives = 'src/Modules/KnivesInfo.luau'
    Revolvers = 'src/Modules/RevolversInfo.luau'
    Levels = 'src/Modules/CalculateLevel.luau'
    Rarity = 'src/Modules/RarityColor.luau'
    Abbreviate = 'src/Modules/Abbreviate.luau'
    Products = 'src/Modules/ProductIDS.luau'
    Server = 'src/server/ServicesHandler/DailyShopHandler.luau'
    Purchases = 'src/server/ServicesHandler/PurchaseHandler.luau'
    Client = 'src/PlayerClient/Modules/DailyShopClient.luau'
    Transitions = 'src/PlayerClient/Modules/UITransitions.luau'
    Assets = 'src/PlayerClient/Modules/ShopAssets.luau'
    ShopGUI = 'src/PlayerClient/ShopGUI.luau'
    FramesHandler = 'src/PlayerClient/FramesHandler.luau'
}
$shopBundle = [System.Text.StringBuilder]::new()
[void]$shopBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($shopEntry in $shopModules.GetEnumerator()) {
    [void]$shopBundle.AppendLine("loaders.$($shopEntry.Key) = function(env)")
    [void]$shopBundle.AppendLine('env = env or {}; local game, script, require, Instance = env.game, env.script, env.require, env.Instance')
    [void]$shopBundle.AppendLine('local task, os, Enum = env.task, env.os or os, env.Enum')
    [void]$shopBundle.AppendLine('local typeof, warn = env.typeof or nativeTypeof, env.warn or function() end')
    [void]$shopBundle.AppendLine('local Color3, UDim2, UDim, TweenInfo = env.Color3, env.UDim2, env.UDim, env.TweenInfo')
    [void]$shopBundle.AppendLine('local CFrame = env.CFrame or {new = function() return {} end}')
    [void]$shopBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $shopRoot $shopEntry.Value)))
    [void]$shopBundle.AppendLine('end')
}
[void]$shopBundle.AppendLine('local tests = (function()')
[void]$shopBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $shopRoot 'tests/daily-shop.spec.luau')))
[void]$shopBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$shopTestFile = Join-Path $env:TEMP ('test6-daily-shop-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($shopTestFile, $shopBundle.ToString())
    & $LuauPath $shopTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Daily shop tests failed.' }
} finally { Remove-Item -LiteralPath $shopTestFile -ErrorAction SilentlyContinue }

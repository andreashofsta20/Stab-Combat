param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$auditRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply the official Luau CLI with -LuauPath.' }
$auditModules = [ordered]@{
    VIPHandler = 'src/server/ServicesHandler/VIPHandler.luau'
    VIPService = 'src/server/ServicesHandler/VIPService.luau'
    Admin = 'src/server/Admin/Main.luau'
    Trades = 'src/server/Trading/TradeRequestsHandler.luau'
    TradeValidator = 'src/server/Trading/TradeValidator.luau'
    TradeSession = 'src/server/Trading/TradeSession.luau'
    TradeManager = 'src/server/Trading/TradeManager.luau'
    Leaderboards = 'src/server/DataStore/LeaderboardsHandler.luau'
    ProfileView = 'src/server/ServicesHandler/ProfileViewHandler.luau'
}
$auditBundle = [System.Text.StringBuilder]::new()
[void]$auditBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($auditEntry in $auditModules.GetEnumerator()) {
    [void]$auditBundle.AppendLine("loaders.$($auditEntry.Key) = function(env)")
    [void]$auditBundle.AppendLine('local game, script, require, Instance = env.game, env.script, env.require, env.Instance')
    [void]$auditBundle.AppendLine('local task, os, Enum = env.task, env.os or os, env.Enum')
    [void]$auditBundle.AppendLine('local typeof, warn, print = env.typeof or nativeTypeof, env.warn or function() end, function() end')
    [void]$auditBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $auditRoot $auditEntry.Value)))
    [void]$auditBundle.AppendLine('end')
}
[void]$auditBundle.AppendLine('local tests = (function()')
[void]$auditBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $auditRoot 'tests/services-security.spec.luau')))
[void]$auditBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$auditTestFile = Join-Path $env:TEMP ('test6-services-security-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($auditTestFile, $auditBundle.ToString())
    & $LuauPath $auditTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Service security checks failed.' }
} finally {
    Remove-Item -LiteralPath $auditTestFile -ErrorAction SilentlyContinue
}

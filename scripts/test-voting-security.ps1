param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$votingTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$votingTestModules = [ordered]@{
    Voting = 'src/server/Game/VotingHandler.luau'
    Notifications = 'src/server/Game/SendNotification.luau'
}
$votingTestBundle = [System.Text.StringBuilder]::new()
[void]$votingTestBundle.AppendLine('local loaders = {}')
foreach ($votingTestEntry in $votingTestModules.GetEnumerator()) {
    [void]$votingTestBundle.AppendLine("loaders.$($votingTestEntry.Key) = function(env)")
    [void]$votingTestBundle.AppendLine('local game, script, require, task, os, warn = env.game, env.script, env.require, env.task, env.os, env.warn')
    [void]$votingTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $votingTestRoot $votingTestEntry.Value)))
    [void]$votingTestBundle.AppendLine('end')
}
[void]$votingTestBundle.AppendLine('local tests = (function()')
[void]$votingTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $votingTestRoot 'tests/voting-security.spec.luau')))
[void]$votingTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$votingTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-voting-security-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($votingTestFile, $votingTestBundle.ToString())
    & $LuauPath $votingTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Voting security tests failed.' }
} finally {
    Remove-Item -LiteralPath $votingTestFile -ErrorAction SilentlyContinue
}

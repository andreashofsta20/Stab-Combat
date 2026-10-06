param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$warmupTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$warmupTestModules = [ordered]@{
    Config = 'src/Modules/WeaponAssetWarmupConfig.luau'
    Warmup = 'src/PlayerClient/Modules/WeaponAssetWarmup.luau'
    Initialize = 'src/PlayerClient/InitializeWeaponAssetWarmup.client.luau'
}
$warmupTestBundle = [System.Text.StringBuilder]::new()
[void]$warmupTestBundle.AppendLine('local loaders = {}')
foreach ($warmupTestEntry in $warmupTestModules.GetEnumerator()) {
    [void]$warmupTestBundle.AppendLine("loaders.$($warmupTestEntry.Key) = function(env)")
    [void]$warmupTestBundle.AppendLine('env = env or {}; local game, script, require, Instance, task, Enum = env.game, env.script, env.require, env.Instance, env.task, env.Enum')
    [void]$warmupTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $warmupTestRoot $warmupTestEntry.Value)))
    [void]$warmupTestBundle.AppendLine('end')
}
[void]$warmupTestBundle.AppendLine('local tests = (function()')
[void]$warmupTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $warmupTestRoot 'tests/weapon-asset-warmup.spec.luau')))
[void]$warmupTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$warmupTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-weapon-warmup-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($warmupTestFile, $warmupTestBundle.ToString())
    & $LuauPath $warmupTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Weapon asset warmup tests failed.' }
} finally {
    Remove-Item -LiteralPath $warmupTestFile -ErrorAction SilentlyContinue
}

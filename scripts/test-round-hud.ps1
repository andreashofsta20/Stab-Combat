param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$hudRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$hudBundle = [System.Text.StringBuilder]::new()
[void]$hudBundle.AppendLine('local function load(env) local game, Color3 = env.game, env.Color3')
[void]$hudBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $hudRoot 'src/PlayerClient/Modules/HandleGameUI.luau')))
[void]$hudBundle.AppendLine('end; local tests = (function()')
[void]$hudBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $hudRoot 'tests/round-hud.spec.luau')))
[void]$hudBundle.AppendLine('end)(); tests(load)')
$hudTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-round-hud-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($hudTestFile, $hudBundle.ToString())
    & $LuauPath $hudTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Round HUD tests failed.' }
} finally {
    Remove-Item -LiteralPath $hudTestFile -ErrorAction SilentlyContinue
}

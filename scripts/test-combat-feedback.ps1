param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$feedbackTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$feedbackTestModules = [ordered]@{
    Config = 'src/Modules/CombatFeedbackConfig.luau'
    AudioConfig = 'src/Modules/CombatAudioConfig.luau'
    Feedback = 'src/PlayerClient/Modules/HitFeedback.luau'
}
$feedbackTestBundle = [System.Text.StringBuilder]::new()
[void]$feedbackTestBundle.AppendLine('local loaders = {}')
foreach ($feedbackTestEntry in $feedbackTestModules.GetEnumerator()) {
    [void]$feedbackTestBundle.AppendLine("loaders.$($feedbackTestEntry.Key) = function(env)")
    [void]$feedbackTestBundle.AppendLine('local game, workspace, require, Instance = env.game, env.workspace, env.require, env.Instance')
    [void]$feedbackTestBundle.AppendLine('local task, typeof, Enum = env.task, env.typeof, env.Enum')
    [void]$feedbackTestBundle.AppendLine('local Color3, UDim, UDim2, Vector2, Vector3, TweenInfo = env.Color3, env.UDim, env.UDim2, env.Vector2, env.Vector3, env.TweenInfo')
    [void]$feedbackTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $feedbackTestRoot $feedbackTestEntry.Value)))
    [void]$feedbackTestBundle.AppendLine('end')
}
[void]$feedbackTestBundle.AppendLine('local tests = (function()')
[void]$feedbackTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $feedbackTestRoot 'tests/combat-feedback.spec.luau')))
[void]$feedbackTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$feedbackTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-combat-feedback-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($feedbackTestFile, $feedbackTestBundle.ToString())
    & $LuauPath $feedbackTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Combat feedback tests failed.' }
} finally { Remove-Item -LiteralPath $feedbackTestFile -ErrorAction SilentlyContinue }

param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$caseTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }

# Execute the actual reel and cancellation code. The unrelated shop setup is
# excluded so tests can control heartbeat, rendering, and tween completion.
$caseShopSource = [System.IO.File]::ReadAllText((Join-Path $caseTestRoot 'src/PlayerClient/ShopGUI.luau'))
$casePreludeStart = $caseShopSource.IndexOf('local spinGeneration = 0')
$casePreludeEnd = $caseShopSource.IndexOf('local function getDefaultRobuxTabName', $casePreludeStart)
$caseReelStart = $caseShopSource.IndexOf('spinRemoteConnection = OpenCaseAnimation.OnClientEvent:Connect(function(')
$caseReelEnd = $caseShopSource.IndexOf('local function RobuxShopFrameTabs', $caseReelStart)
if ($casePreludeStart -lt 0 -or $casePreludeEnd -lt 0 -or $caseReelStart -lt 0 -or $caseReelEnd -lt 0) {
    throw 'Production ShopGUI reel boundaries changed; update the extraction anchors.'
}
$caseTestBundle = [System.Text.StringBuilder]::new()
[void]$caseTestBundle.AppendLine('local loaders = {}')
[void]$caseTestBundle.AppendLine('loaders.Pool = function(env)')
[void]$caseTestBundle.AppendLine('local game, Instance = env.game, env.Instance')
[void]$caseTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $caseTestRoot 'src/PlayerClient/Modules/CaseViewportPool.luau')))
[void]$caseTestBundle.AppendLine('end')
[void]$caseTestBundle.AppendLine('loaders.Reel = function(env)')
[void]$caseTestBundle.AppendLine('local LastCase')
[void]$caseTestBundle.AppendLine('local task, RunService, TweenService, TweenInfo, Enum, UDim2, Random = env.task, env.RunService, env.TweenService, env.TweenInfo, env.Enum, env.UDim2, env.Random')
[void]$caseTestBundle.AppendLine('local OpenCaseAnimation, CaseInfoModule, RandomItem, RarityColorModule, EmotesModule, CaseViewportPool = env.OpenCaseAnimation, env.CaseInfoModule, env.RandomItem, env.RarityColorModule, env.EmotesModule, env.CaseViewportPool')
[void]$caseTestBundle.AppendLine('local SpinnerFrame, SpinnerContainer, SpinFrame, SpinnerSkipButton, SpinnerOpenAgain, SpinnerExit = env.SpinnerFrame, env.SpinnerContainer, env.SpinFrame, env.SpinnerSkipButton, env.SpinnerOpenAgain, env.SpinnerExit')
[void]$caseTestBundle.AppendLine('local ShopFrameUI, HeaderText, Lighting, CaseSpinnerTemplate, CaseSpinnerTemplateEmote = env.ShopFrameUI, env.HeaderText, env.Lighting, env.CaseSpinnerTemplate, env.CaseSpinnerTemplateEmote')
[void]$caseTestBundle.AppendLine('local SoundHandlerModule, OpenCaseRemote, GamePass = env.SoundHandlerModule, env.OpenCaseRemote, env.GamePass')
[void]$caseTestBundle.AppendLine($caseShopSource.Substring($casePreludeStart, $casePreludeEnd - $casePreludeStart))
[void]$caseTestBundle.AppendLine($caseShopSource.Substring($caseReelStart, $caseReelEnd - $caseReelStart))
[void]$caseTestBundle.AppendLine('end')
[void]$caseTestBundle.AppendLine('local tests = (function()')
[void]$caseTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $caseTestRoot 'tests/case-viewport.spec.luau')))
[void]$caseTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$caseTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-case-viewport-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($caseTestFile, $caseTestBundle.ToString())
    & $LuauPath $caseTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Case viewport and reel tests failed.' }
} finally {
    Remove-Item -LiteralPath $caseTestFile -ErrorAction SilentlyContinue
}

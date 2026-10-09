param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$tutorialTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$tutorialTestModules = [ordered]@{
    State = 'src/server/Tutorial/TutorialState.luau'
    Steps = 'src/Modules/TutorialSteps.luau'
    Runtime = 'src/server/Tutorial/TutorialRuntime.luau'
    Rewards = 'src/server/Tutorial/TutorialRewards.luau'
    Schema = 'src/Modules/ProfileSchema.luau'
    TutorialTickets = 'src/server/Tutorial/TutorialTickets.luau'
    TutorialTeleport = 'src/server/Tutorial/TutorialTeleport.luau'
    Coordinator = 'src/server/Tutorial/TutorialCoordinator.luau'
    TutorialAnalytics = 'src/server/Tutorial/TutorialAnalytics.luau'
    TutorialGuidance = 'src/PlayerClient/Modules/TutorialGuidance.luau'
    TutorialArena = 'src/server/Tutorial/TutorialArena.luau'
    TutorialGamepadBridge = 'src/PlayerClient/Modules/TutorialGamepadBridge.luau'
}
$tutorialTestBundle = [System.Text.StringBuilder]::new()
[void]$tutorialTestBundle.AppendLine('local loaders = {}')
foreach ($tutorialTestEntry in $tutorialTestModules.GetEnumerator()) {
    [void]$tutorialTestBundle.AppendLine("loaders.$($tutorialTestEntry.Key) = function(env)")
    [void]$tutorialTestBundle.AppendLine('local game, script, require, task, warn, workspace, Vector3, Enum = env.game, env.script, env.require, env.task, env.warn, env.workspace, env.Vector3, env.Enum')
    [void]$tutorialTestBundle.AppendLine('local os = env.os or os')
    [void]$tutorialTestBundle.AppendLine('local Instance, UDim2, UDim, Color3, TweenInfo = env.Instance, env.UDim2, env.UDim, env.Color3, env.TweenInfo')
    [void]$tutorialTestBundle.AppendLine('local typeof = env.typeof or typeof')
    [void]$tutorialTestBundle.AppendLine('local CFrame, RaycastParams = env.CFrame, env.RaycastParams')
    [void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot $tutorialTestEntry.Value)))
    [void]$tutorialTestBundle.AppendLine('end')
}
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-state.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-runtime.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-rewards.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-travel.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-coordinator.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-analytics.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-guidance.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-arena.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
[void]$tutorialTestBundle.AppendLine('do local tests = (function()')
[void]$tutorialTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $tutorialTestRoot 'tests/tutorial-gamepad.spec.luau')))
[void]$tutorialTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end) end')
$tutorialTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('stab-tutorial-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($tutorialTestFile, $tutorialTestBundle.ToString())
    & $LuauPath $tutorialTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Tutorial security and recovery tests failed.' }
} finally {
    Remove-Item -LiteralPath $tutorialTestFile -ErrorAction SilentlyContinue
}

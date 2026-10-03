param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$cameraTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$cameraTestModules = [ordered]@{
    Config = 'src/Modules/FirstPersonCameraConfig.luau'
    Camera = 'src/PlayerClient/Modules/FirstPersonPostureCamera.luau'
    Initialize = 'src/PlayerClient/InitializeFirstPersonPostureCamera.client.luau'
}
$cameraTestBundle = [System.Text.StringBuilder]::new()
[void]$cameraTestBundle.AppendLine('local loaders = {}')
foreach ($cameraTestEntry in $cameraTestModules.GetEnumerator()) {
    [void]$cameraTestBundle.AppendLine("loaders.$($cameraTestEntry.Key) = function(env)")
    [void]$cameraTestBundle.AppendLine('local game, workspace, script, require = env.game, env.workspace, env.script, env.require')
    [void]$cameraTestBundle.AppendLine('local Vector3, Enum, warn = env.Vector3, env.Enum, env.warn or function() end')
    [void]$cameraTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $cameraTestRoot $cameraTestEntry.Value)))
    [void]$cameraTestBundle.AppendLine('end')
}
[void]$cameraTestBundle.AppendLine('local tests = (function()')
[void]$cameraTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $cameraTestRoot 'tests/first-person-camera.spec.luau')))
[void]$cameraTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$cameraTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-first-person-camera-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($cameraTestFile, $cameraTestBundle.ToString())
    & $LuauPath $cameraTestFile
    if ($LASTEXITCODE -ne 0) { throw 'First-person camera tests failed.' }
} finally {
    Remove-Item -LiteralPath $cameraTestFile -ErrorAction SilentlyContinue
}

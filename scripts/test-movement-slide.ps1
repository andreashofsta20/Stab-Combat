param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$slideTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$slideTestModules = [ordered]@{
    Config = 'src/Modules/MovementConfig.luau'
    Motion = 'src/Modules/SlideMotion.luau'
    Controller = 'src/Modules/SlideController.luau'
}
$slideTestBundle = [System.Text.StringBuilder]::new()
[void]$slideTestBundle.AppendLine('local loaders = {}')
foreach ($slideTestEntry in $slideTestModules.GetEnumerator()) {
    [void]$slideTestBundle.AppendLine("loaders.$($slideTestEntry.Key) = function(env)")
    [void]$slideTestBundle.AppendLine('env = env or {}')
    [void]$slideTestBundle.AppendLine('local game, workspace, script, require, Instance = env.game, env.workspace, env.script, env.require, env.Instance')
    [void]$slideTestBundle.AppendLine('local Vector2, Vector3, CFrame, Enum = env.Vector2, env.Vector3, env.CFrame, env.Enum')
    [void]$slideTestBundle.AppendLine('local RaycastParams, OverlapParams = env.RaycastParams, env.OverlapParams')
    [void]$slideTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $slideTestRoot $slideTestEntry.Value)))
    [void]$slideTestBundle.AppendLine('end')
}
[void]$slideTestBundle.AppendLine('local tests = (function()')
[void]$slideTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $slideTestRoot 'tests/movement-slide.spec.luau')))
[void]$slideTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env) end)')
$slideTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-movement-slide-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($slideTestFile, $slideTestBundle.ToString())
    & $LuauPath $slideTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Movement slide tests failed.' }
} finally {
    Remove-Item -LiteralPath $slideTestFile -ErrorAction SilentlyContinue
}

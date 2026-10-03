param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$physicsRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$physicsModules = [ordered]@{
    Physics = 'src/Modules/RevolverToolPhysics.luau'
    Catalog = 'src/Modules/RevolversInfo.luau'
}
$physicsBundle = [System.Text.StringBuilder]::new()
[void]$physicsBundle.AppendLine('local loaders = {}')
[void]$physicsBundle.AppendLine('local CFrame = {new = function(...) return {...} end} -- catalog appearance offsets are unused by this manager')
foreach ($physicsEntry in $physicsModules.GetEnumerator()) {
    [void]$physicsBundle.AppendLine("loaders.$($physicsEntry.Key) = function()")
    [void]$physicsBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $physicsRoot $physicsEntry.Value)))
    [void]$physicsBundle.AppendLine('end')
}
[void]$physicsBundle.AppendLine('local tests = (function()')
[void]$physicsBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $physicsRoot 'tests/revolver-tool-physics.spec.luau')))
[void]$physicsBundle.AppendLine('end)(); tests(function(name) return loaders[name]() end)')
$physicsTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-revolver-tool-physics-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($physicsTestFile, $physicsBundle.ToString())
    & $LuauPath $physicsTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Revolver Tool physics tests failed.' }
} finally {
    Remove-Item -LiteralPath $physicsTestFile -ErrorAction SilentlyContinue
}

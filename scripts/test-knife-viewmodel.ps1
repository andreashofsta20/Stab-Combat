param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$knifeRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$knifeModules = [ordered]@{
    Config = 'src/Modules/KnifeConfig.luau'
    SharedMotion = 'src/Modules/RevolverViewmodelMath.luau'
    KnifeMotion = 'src/Modules/KnifeViewmodelMotion.luau'
    Viewmodel = 'src/PlayerClient/Modules/KnifeViewmodel.luau'
}
$knifeBundle = [System.Text.StringBuilder]::new()
[void]$knifeBundle.AppendLine('local loaders = {}')
foreach ($knifeEntry in $knifeModules.GetEnumerator()) {
    [void]$knifeBundle.AppendLine("loaders.$($knifeEntry.Key) = function(env)")
    [void]$knifeBundle.AppendLine('local game, script, require = env.game, env.script, env.require')
    [void]$knifeBundle.AppendLine('local CFrame, Vector3 = env.CFrame, env.Vector3')
    [void]$knifeBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $knifeRoot $knifeEntry.Value)))
    [void]$knifeBundle.AppendLine('end')
}
[void]$knifeBundle.AppendLine('local tests = (function()')
[void]$knifeBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $knifeRoot 'tests/knife-viewmodel.spec.luau')))
[void]$knifeBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$knifeTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-knife-viewmodel-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($knifeTestFile, $knifeBundle.ToString())
    & $LuauPath $knifeTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Knife viewmodel tests failed.' }
} finally {
    Remove-Item -LiteralPath $knifeTestFile -ErrorAction SilentlyContinue
}

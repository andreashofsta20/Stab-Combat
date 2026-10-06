param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$polishSuites = Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'test-*.ps1' |
    Where-Object { $_.Name -ne 'test-performance-polish.ps1' } | Sort-Object Name
foreach ($polishSuite in $polishSuites) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $polishSuite.FullName -LuauPath $LuauPath
    if ($LASTEXITCODE -ne 0) { throw ($polishSuite.Name + ' failed') }
}
Write-Output ("Performance polish verification: {0} regression suites passed" -f $polishSuites.Count)

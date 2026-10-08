param([string]$LuauPath = '')
$ErrorActionPreference = 'Stop'
$auditRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply the official Luau CLI with -LuauPath.' }
$auditModules = [ordered]@{
    Recovery = 'src/server/Trading/TradeRecovery.luau'
    Schema = 'src/Modules/ProfileSchema.luau'
    Admission = 'src/Modules/MovementAdmission.luau'
    Archive = 'src/server/ServicesHandler/ReceiptArchive.luau'
    Stats = 'src/Modules/CompetitiveStats.luau'
}
$auditBundle = [System.Text.StringBuilder]::new()
[void]$auditBundle.AppendLine('local loaders = {}')
foreach ($auditEntry in $auditModules.GetEnumerator()) {
    [void]$auditBundle.AppendLine("loaders.$($auditEntry.Key) = function(env)")
    [void]$auditBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $auditRoot $auditEntry.Value)))
    [void]$auditBundle.AppendLine('end')
}
[void]$auditBundle.AppendLine('local tests = (function()')
[void]$auditBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $auditRoot 'tests/beta-persistence.spec.luau')))
[void]$auditBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end)')
$auditTestFile = Join-Path $env:TEMP ('stab-beta-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($auditTestFile, $auditBundle.ToString())
    & $LuauPath $auditTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Beta persistence checks failed.' }
} finally {
    Remove-Item -LiteralPath $auditTestFile -ErrorAction SilentlyContinue
}

param([string]$OutputPath = 'SOURCE_AUDIT_INVENTORY.json')
$ErrorActionPreference = 'Stop'
$auditSourceRoot = Split-Path -Parent $PSScriptRoot
$auditSourcePaths = & rg --files (Join-Path $auditSourceRoot 'src')
if ($LASTEXITCODE -ne 0) { throw 'Source inventory failed.' }
$auditSourceRecords = foreach ($auditSourcePath in $auditSourcePaths) {
    if ([System.IO.Path]::GetExtension($auditSourcePath) -notin @('.lua', '.luau')) { continue }
    $auditSourceText = [System.IO.File]::ReadAllText($auditSourcePath)
    [pscustomobject]@{
        Path = $auditSourcePath.Substring($auditSourceRoot.Length + 1).Replace('\', '/')
        Lines = ([regex]::Matches($auditSourceText, '\n').Count + 1)
        Connections = [regex]::Matches($auditSourceText, ':Connect\s*\(').Count
        ServerEvents = [regex]::Matches($auditSourceText, '\.OnServerEvent\s*:Connect').Count
        ServerFunctions = [regex]::Matches($auditSourceText, '\.OnServerInvoke\s*=').Count
        FrameCallbacks = [regex]::Matches($auditSourceText, '(Heartbeat|RenderStepped|PreSimulation|PostSimulation)\s*:Connect|:BindToRenderStep').Count
        Disconnects = [regex]::Matches($auditSourceText, ':Disconnect\s*\(').Count
        Destruction = [regex]::Matches($auditSourceText, ':Destroy\s*\(').Count
        BackgroundTasks = [regex]::Matches($auditSourceText, 'task\.(spawn|defer|delay)\s*\(').Count
    }
}
$auditSourceSummary = [ordered]@{
    Note = 'Text inventory, not proof of leaks or security. Manual findings and tests are described in SOURCE_AUDIT.md.'
    SourceFiles = @($auditSourceRecords).Count
    ServerEventHandlers = ($auditSourceRecords | Measure-Object -Property ServerEvents -Sum).Sum
    ServerFunctionHandlers = ($auditSourceRecords | Measure-Object -Property ServerFunctions -Sum).Sum
    Files = @($auditSourceRecords | Sort-Object Path)
}
$auditSourceOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $auditSourceRoot $OutputPath }
[System.IO.File]::WriteAllText($auditSourceOutput, ($auditSourceSummary | ConvertTo-Json -Depth 4))
Write-Output ('Inventoried {0} source files and {1} client-to-server event handlers.' -f $auditSourceSummary.SourceFiles, $auditSourceSummary.ServerEventHandlers)

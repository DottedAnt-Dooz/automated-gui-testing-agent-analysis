[CmdletBinding()]
param(
    [string] $RunsRoot = '',

    [string] $OutputPath = '',

    [string] $PricingPath = '',

    [switch] $Open
)

$ErrorActionPreference = 'Stop'

try {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Analysis\AutomatedGuiTestingAnalysis.psm1'
    Import-Module $modulePath -Force

    if (-not $RunsRoot) {
        $workspaceRoot = Split-Path -Parent $PSScriptRoot
        $RunsRoot = Join-Path -Path $workspaceRoot -ChildPath 'automated-gui-testing-agent-framework\runs'
    }
    if (-not $OutputPath) {
        $OutputPath = Join-Path -Path $PSScriptRoot -ChildPath ('analysis-output\dashboard_{0}.html' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }

    $result = New-AGTAAnalysisDashboard -RunsRoot $RunsRoot -OutputPath $OutputPath -PricingPath $PricingPath
    if ($Open) {
        Start-Process $result.outputPath
    }
    $result | ConvertTo-Json -Depth 20 -Compress
}
catch {
    [pscustomobject][ordered]@{
        ok = $false
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 20 -Compress
    exit 1
}

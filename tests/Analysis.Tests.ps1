$analysisRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path -Path $analysisRoot -ChildPath 'Analysis\AutomatedGuiTestingAnalysis.psm1'
Import-Module $modulePath -Force

Describe 'Analysis dashboard' {
    function Add-TestJsonLine {
        param(
            [string] $Path,
            [object] $Object
        )

        $Object | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $Path -Encoding UTF8
    }

    function New-TestAnalysisRun {
        param(
            [string] $RunsRoot
        )

        $runRoot = Join-Path -Path $RunsRoot -ChildPath 'run-001'
        foreach ($path in @(
            $runRoot,
            (Join-Path $runRoot 'logs'),
            (Join-Path $runRoot 'results'),
            (Join-Path $runRoot 'evidence')
        )) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }

        [ordered]@{
            runId = 'run-001'
            createdAt = '2026-06-21T10:00:00.0000000+02:00'
            testCaseCsv = 'C:\cases\paint.csv'
            paths = @{ runRoot = $runRoot }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $runRoot 'run.json') -Encoding UTF8

        [ordered]@{
            ok = $true
            provider = 'OpenAI'
            model = 'gpt-test'
            runRoot = $runRoot
            resultPath = Join-Path $runRoot 'results\authoring-result.json'
            result = @{ provider = 'OpenAI'; model = 'gpt-test'; iterations = 1 }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runRoot 'results\authoring-result.json') -Encoding UTF8

        [ordered]@{
            ok = $true
            testCase = 'paint.csv'
            runRoot = $runRoot
            startedAt = '2026-06-21T10:00:00.0000000+02:00'
            finishedAt = '2026-06-21T10:01:00.0000000+02:00'
            steps = @()
            summary = @{ total = 2; passed = 2; failed = 0; skipped = 0 }
            artifacts = @{ resultPath = Join-Path $runRoot 'results\result.json'; evidenceRoot = Join-Path $runRoot 'evidence' }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runRoot 'results\result.json') -Encoding UTF8

        $metricsPath = Join-Path $runRoot 'logs\metrics.jsonl'
        Add-TestJsonLine -Path $metricsPath -Object @{ timestamp = '2026-06-21T10:00:00.0000000+02:00'; event = 'authoring_start'; provider = 'OpenAI'; model = 'gpt-test'; stepCount = 2 }
        Add-TestJsonLine -Path $metricsPath -Object @{ timestamp = '2026-06-21T10:00:05.0000000+02:00'; event = 'ai_response'; provider = 'OpenAI'; model = 'gpt-test'; iteration = 1; inputTokens = 1000; cachedInputTokens = 100; outputTokens = 200; reasoningTokens = 50; totalTokens = 1200; durationMs = 1500 }
        Add-TestJsonLine -Path $metricsPath -Object @{ timestamp = '2026-06-21T10:00:06.0000000+02:00'; event = 'potato_command'; command = 'click'; ok = $true; durationMs = 100 }
        Add-TestJsonLine -Path $metricsPath -Object @{ timestamp = '2026-06-21T10:00:07.0000000+02:00'; event = 'potato_command'; command = 'type'; ok = $true; durationMs = 200 }
        Add-TestJsonLine -Path $metricsPath -Object @{ timestamp = '2026-06-21T10:00:08.0000000+02:00'; event = 'authoring_end'; provider = 'OpenAI'; model = 'gpt-test'; ok = $true; durationMs = 8000 }

        return $runRoot
    }

    It 'summarizes synthetic run metrics and cost estimates' {
        $runsRoot = Join-Path -Path $TestDrive -ChildPath 'runs'
        $runRoot = New-TestAnalysisRun -RunsRoot $runsRoot
        $pricingPath = Join-Path -Path $TestDrive -ChildPath 'pricing.json'
        @{ currency = 'USD'; unit = 'per_1m_tokens'; models = @{ 'gpt-test' = @{ input = 1.0; cachedInput = 0.1; output = 10.0 } } } |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $pricingPath -Encoding UTF8

        $summary = ConvertTo-AGTARunSummary -RunRoot $runRoot -PricingPath $pricingPath

        $summary.ok | Should Be $true
        $summary.model | Should Be 'gpt-test'
        $summary.authoringDurationMs | Should Be 8000
        $summary.ai.totalTokens | Should Be 1200
        $summary.ai.estimatedCostUsd | Should Be 0.00291
        $summary.potato.commandCount | Should Be 2
        $summary.potato.commandCounts.click | Should Be 1
        $summary.steps.passed | Should Be 2
    }

    It 'writes a standalone dashboard html file' {
        $runsRoot = Join-Path -Path $TestDrive -ChildPath 'runs-dashboard'
        [void](New-TestAnalysisRun -RunsRoot $runsRoot)
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'dashboard.html'
        $result = New-AGTAAnalysisDashboard -RunsRoot $runsRoot -OutputPath $outputPath
        $content = Get-Content -LiteralPath $outputPath -Raw

        $result.ok | Should Be $true
        Test-Path -LiteralPath $outputPath | Should Be $true
        $content | Should Match 'Automated GUI Testing Analysis'
        $content | Should Match 'const DATASET ='
        $content | Should Match 'chart-label'
        $content | Should Match 'chart-value'
        $content | Should Match 'compactLabel'
    }

    It 'defaults to the framework runs folder' {
        $defaultRuns = Get-AGTAAnalysisDefaultRunsRoot
        $defaultRuns | Should Match ([regex]::Escape('automated-gui-testing-agent-framework\runs'))
    }
}

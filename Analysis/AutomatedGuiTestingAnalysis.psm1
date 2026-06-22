$script:AnalysisModuleRoot = Split-Path -Parent $PSCommandPath
$script:AnalysisRoot = Split-Path -Parent $script:AnalysisModuleRoot
$script:WorkspaceRoot = Split-Path -Parent $script:AnalysisRoot

function Get-AGTAAnalysisRoot {
    [CmdletBinding()]
    param()

    return $script:AnalysisRoot
}

function Get-AGTAAnalysisFrameworkRoot {
    [CmdletBinding()]
    param()

    return Get-AGTAAnalysisRoot
}

function Get-AGTAAnalysisDefaultRunsRoot {
    [CmdletBinding()]
    param()

    Join-Path -Path $script:WorkspaceRoot -ChildPath 'automated-gui-testing-agent-framework\runs'
}

function Read-AGTAJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Read-AGTAJsonLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $items = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $items }

    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if (-not $line.Trim()) { continue }
        try {
            $items += ($line | ConvertFrom-Json)
        }
        catch {
            $items += [pscustomobject][ordered]@{
                event = 'parse_error'
                path = $Path
                lineNumber = $lineNumber
                error = $_.Exception.Message
            }
        }
    }
    return $items
}

function Get-AGTAProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Object,

        [Parameter(Mandatory)]
        [string] $Name,

        [object] $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    if ($Object -is [hashtable] -and $Object.ContainsKey($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function ConvertTo-AGTANumber {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [double] $Default = 0
    )

    if ($null -eq $Value) { return $Default }
    $number = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $number
    }
    return $Default
}

function ConvertTo-AGTADateTimeOffset {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or -not [string]$Value) { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Get-AGTAFileSize {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        return [int64](Get-Item -LiteralPath $Path).Length
    }
    catch {
        return 0
    }
}

function Get-AGTAPricingConfig {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    if ($Path -and (Test-Path -LiteralPath $Path)) {
        $parsed = Read-AGTAJsonFile -Path $Path
        if ($parsed) { return $parsed }
    }

    [pscustomobject][ordered]@{
        currency = 'USD'
        unit = 'per_1m_tokens'
        models = [pscustomobject]@{}
    }
}

function Get-AGTAModelPricing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Pricing,

        [string] $Model
    )

    if (-not $Model) { return $null }
    $models = Get-AGTAProperty -Object $Pricing -Name 'models'
    if (-not $models) { return $null }

    $exact = Get-AGTAProperty -Object $models -Name $Model
    if ($exact) { return $exact }

    foreach ($property in @($models.PSObject.Properties)) {
        if ($Model -like "$($property.Name)*") { return $property.Value }
    }
    return $null
}

function Get-AGTACostEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Pricing,

        [string] $Model,

        [double] $InputTokens = 0,

        [double] $CachedInputTokens = 0,

        [double] $OutputTokens = 0
    )

    $modelPricing = Get-AGTAModelPricing -Pricing $Pricing -Model $Model
    if (-not $modelPricing) { return $null }

    $inputRate = ConvertTo-AGTANumber (Get-AGTAProperty -Object $modelPricing -Name 'input') 0
    $cachedInputRate = ConvertTo-AGTANumber (Get-AGTAProperty -Object $modelPricing -Name 'cachedInput') $inputRate
    $outputRate = ConvertTo-AGTANumber (Get-AGTAProperty -Object $modelPricing -Name 'output') 0
    $billableInputTokens = [Math]::Max(0, $InputTokens - $CachedInputTokens)
    $cost = (($billableInputTokens * $inputRate) + ($CachedInputTokens * $cachedInputRate) + ($OutputTokens * $outputRate)) / 1000000

    return [Math]::Round($cost, 6)
}

function Get-AGTARunRoots {
    [CmdletBinding()]
    param(
        [string] $RunsRoot = (Get-AGTAAnalysisDefaultRunsRoot)
    )

    if (-not (Test-Path -LiteralPath $RunsRoot)) { return @() }

    Get-ChildItem -LiteralPath $RunsRoot -Directory |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path -Path $_.FullName -ChildPath 'run.json')) -or
            (Test-Path -LiteralPath (Join-Path -Path $_.FullName -ChildPath 'logs\metrics.jsonl')) -or
            (Test-Path -LiteralPath (Join-Path -Path $_.FullName -ChildPath 'results\authoring-result.json'))
        } |
        Sort-Object Name |
        ForEach-Object { $_.FullName }
}

function Get-AGTAStepSummary {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $GeneratedResult
    )

    if ($GeneratedResult -and $GeneratedResult.summary) {
        return [pscustomobject][ordered]@{
            total = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $GeneratedResult.summary -Name 'total') 0)
            passed = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $GeneratedResult.summary -Name 'passed') 0)
            failed = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $GeneratedResult.summary -Name 'failed') 0)
            skipped = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $GeneratedResult.summary -Name 'skipped') 0)
        }
    }

    $steps = @()
    if ($GeneratedResult -and $GeneratedResult.steps) { $steps = @($GeneratedResult.steps) }
    [pscustomobject][ordered]@{
        total = $steps.Count
        passed = @($steps | Where-Object { $_.status -eq 'PASS' }).Count
        failed = @($steps | Where-Object { $_.status -eq 'FAIL' }).Count
        skipped = @($steps | Where-Object { $_.status -eq 'SKIPPED' }).Count
    }
}

function Get-AGTAPotatoSummary {
    [CmdletBinding()]
    param(
        [object[]] $Metrics,

        [object[]] $PotatoRecords,

        [AllowNull()]
        [object] $GeneratedResult
    )

    $commands = @()
    if ($GeneratedResult -and $GeneratedResult.steps) {
        foreach ($step in @($GeneratedResult.steps)) {
            foreach ($commandRecord in @($step.commands)) {
                $commands += [pscustomobject][ordered]@{
                    command = [string](Get-AGTAProperty -Object $commandRecord -Name 'command')
                    ok = [bool](Get-AGTAProperty -Object $commandRecord -Name 'ok' $true)
                    durationMs = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $commandRecord -Name 'durationMs') 0)
                    source = 'generated-result'
                }
            }
        }
    }
    elseif ($PotatoRecords.Count -gt 0) {
        foreach ($record in $PotatoRecords) {
            $parsed = Get-AGTAProperty -Object $record -Name 'parsed'
            $commands += [pscustomobject][ordered]@{
                command = [string](Get-AGTAProperty -Object $record -Name 'command')
                ok = [bool](Get-AGTAProperty -Object $parsed -Name 'ok' $true)
                durationMs = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $parsed -Name 'durationMs') 0)
                source = 'potato-commands'
            }
        }
    }
    else {
        foreach ($metric in @($Metrics | Where-Object { $_.event -eq 'potato_command' })) {
            $commands += [pscustomobject][ordered]@{
                command = [string]$metric.command
                ok = [bool]$metric.ok
                durationMs = [int](ConvertTo-AGTANumber $metric.durationMs 0)
                source = 'metrics'
            }
        }
    }

    $counts = [ordered]@{}
    foreach ($command in $commands) {
        $name = if ($command.command) { [string]$command.command } else { 'unknown' }
        if (-not $counts.Contains($name)) { $counts[$name] = 0 }
        $counts[$name]++
    }

    [pscustomobject][ordered]@{
        commandCount = $commands.Count
        succeeded = @($commands | Where-Object { $_.ok }).Count
        failed = @($commands | Where-Object { -not $_.ok }).Count
        durationMs = [int](@($commands | Measure-Object -Property durationMs -Sum).Sum)
        commandCounts = $counts
    }
}

function Get-AGTAAiSummary {
    [CmdletBinding()]
    param(
        [object[]] $Metrics,

        [object[]] $OpenAiRecords,

        [object] $Pricing,

        [string] $Model
    )

    $responseMetrics = @($Metrics | Where-Object { $_.event -eq 'ai_response' })
    if ($responseMetrics.Count -eq 0) {
        foreach ($record in $OpenAiRecords) {
            $response = Get-AGTAProperty -Object $record -Name 'response'
            $usage = Get-AGTAProperty -Object $response -Name 'usage'
            if (-not $usage) { continue }
            $responseMetrics += [pscustomobject][ordered]@{
                event = 'ai_response'
                provider = 'OpenAI'
                model = Get-AGTAProperty -Object $response -Name 'model' $Model
                iteration = Get-AGTAProperty -Object $record -Name 'iteration'
                responseId = Get-AGTAProperty -Object $response -Name 'id'
                status = Get-AGTAProperty -Object $response -Name 'status'
                durationMs = 0
                inputTokens = Get-AGTAProperty -Object $usage -Name 'input_tokens' 0
                cachedInputTokens = Get-AGTAProperty -Object (Get-AGTAProperty -Object $usage -Name 'input_tokens_details') -Name 'cached_tokens' 0
                outputTokens = Get-AGTAProperty -Object $usage -Name 'output_tokens' 0
                reasoningTokens = Get-AGTAProperty -Object (Get-AGTAProperty -Object $usage -Name 'output_tokens_details') -Name 'reasoning_tokens' 0
                totalTokens = Get-AGTAProperty -Object $usage -Name 'total_tokens' 0
            }
        }
    }

    $inputTokens = [int](@($responseMetrics | Measure-Object -Property inputTokens -Sum).Sum)
    $cachedInputTokens = [int](@($responseMetrics | Measure-Object -Property cachedInputTokens -Sum).Sum)
    $outputTokens = [int](@($responseMetrics | Measure-Object -Property outputTokens -Sum).Sum)
    $reasoningTokens = [int](@($responseMetrics | Measure-Object -Property reasoningTokens -Sum).Sum)
    $totalTokens = [int](@($responseMetrics | Measure-Object -Property totalTokens -Sum).Sum)

    [pscustomobject][ordered]@{
        responseCount = $responseMetrics.Count
        inputTokens = $inputTokens
        cachedInputTokens = $cachedInputTokens
        outputTokens = $outputTokens
        reasoningTokens = $reasoningTokens
        totalTokens = $totalTokens
        responseDurationMs = [int](@($responseMetrics | Measure-Object -Property durationMs -Sum).Sum)
        estimatedCostUsd = Get-AGTACostEstimate -Pricing $Pricing -Model $Model -InputTokens $inputTokens -CachedInputTokens $cachedInputTokens -OutputTokens $outputTokens
    }
}

function Get-AGTARolloutCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunRoot
    )

    $roots = @()
    $roots += $RunRoot
    $logs = Join-Path -Path $RunRoot -ChildPath 'logs'
    if (Test-Path -LiteralPath $logs) { $roots += $logs }
    $parent = Split-Path -Parent $RunRoot
    if ($parent -and (Test-Path -LiteralPath $parent)) { $roots += $parent }

    $seen = @{}
    foreach ($root in $roots) {
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter 'rollout-*.jsonl' -File -ErrorAction SilentlyContinue)) {
            if (-not $seen.ContainsKey($file.FullName)) {
                $seen[$file.FullName] = $true
                $file.FullName
            }
        }
    }
}

function Get-AGTACodexRolloutSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunRoot
    )

    $runLeaf = Split-Path -Leaf $RunRoot
    $candidates = @(Get-AGTARolloutCandidates -RunRoot $RunRoot)
    if ($candidates.Count -eq 0) { return $null }

    $selected = $null
    foreach ($candidate in $candidates) {
        try {
            if ((Select-String -LiteralPath $candidate -SimpleMatch $runLeaf -Quiet -ErrorAction SilentlyContinue)) {
                $selected = $candidate
                break
            }
        }
        catch {}
    }
    if (-not $selected -and $candidates.Count -eq 1) { $selected = $candidates[0] }
    if (-not $selected) { return $null }

    $items = @(Read-AGTAJsonLines -Path $selected)
    if ($items.Count -eq 0) { return $null }

    $taskStarted = $items | Where-Object { $_.type -eq 'event_msg' -and $_.payload.type -eq 'task_started' } | Select-Object -First 1
    $taskComplete = $items | Where-Object { $_.type -eq 'event_msg' -and $_.payload.type -eq 'task_complete' } | Select-Object -Last 1
    $turnContext = $items | Where-Object { $_.type -eq 'turn_context' } | Select-Object -Last 1
    $lastToken = $items | Where-Object { $_.type -eq 'event_msg' -and $_.payload.type -eq 'token_count' } | Select-Object -Last 1

    $callsById = @{}
    foreach ($item in @($items | Where-Object { $_.type -eq 'response_item' -and $_.payload.type -eq 'function_call' })) {
        $arguments = $null
        try { $arguments = ConvertFrom-Json ([string]$item.payload.arguments) } catch {}
        $callsById[[string]$item.payload.call_id] = [pscustomobject][ordered]@{
            timestamp = ConvertTo-AGTADateTimeOffset $item.timestamp
            name = [string]$item.payload.name
            command = $(if ($arguments -and $arguments.PSObject.Properties.Name -contains 'command') { [string]$arguments.command } else { [string]$item.payload.arguments })
            outputTimestamp = $null
            wallMs = 0
            exitCode = $null
            outputChars = 0
        }
    }

    foreach ($item in @($items | Where-Object { $_.type -eq 'response_item' -and $_.payload.type -eq 'function_call_output' })) {
        $callId = [string]$item.payload.call_id
        if (-not $callsById.ContainsKey($callId)) { continue }
        $output = [string]$item.payload.output
        $callsById[$callId].outputTimestamp = ConvertTo-AGTADateTimeOffset $item.timestamp
        $callsById[$callId].outputChars = $output.Length
        if ($output -match 'Wall time:\s*([0-9\.]+) seconds') {
            $callsById[$callId].wallMs = [int]([double]$Matches[1] * 1000)
        }
        if ($output -match 'Exit code:\s*(-?\d+)') {
            $callsById[$callId].exitCode = [int]$Matches[1]
        }
    }

    $shellCalls = @($callsById.Values | Where-Object { $_.name -eq 'shell_command' })
    $directPotato = @($shellCalls | Where-Object { $_.command -match 'potato(?:_|-)cli\\potato\.ps1|potato\.ps1' -and $_.command -notmatch '\\generated\\.*\.ps1' })
    $directPotatoUi = @($directPotato | Where-Object { $_.command -notmatch 'potato\.ps1[''"]?\s+state(\s|$)' })
    $generatedScriptRuns = @($shellCalls | Where-Object { $_.command -match '\\generated\\.*\.ps1' -and $_.command -match 'powershell\.exe' })
    $firstGenerated = $generatedScriptRuns | Sort-Object timestamp | Select-Object -First 1
    $firstExploration = $directPotatoUi | Sort-Object timestamp | Select-Object -First 1
    $lastExploration = $null
    if ($firstGenerated) {
        $lastExploration = $directPotato | Where-Object { $_.timestamp -and $_.timestamp -lt $firstGenerated.timestamp } | Sort-Object timestamp | Select-Object -Last 1
    }
    else {
        $lastExploration = $directPotato | Sort-Object timestamp | Select-Object -Last 1
    }

    $taskStartTime = ConvertTo-AGTADateTimeOffset $taskStarted.timestamp
    $taskEndTime = ConvertTo-AGTADateTimeOffset $taskComplete.timestamp
    $explorationStart = $(if ($firstExploration) { $firstExploration.timestamp } else { $null })
    $explorationEnd = $(if ($lastExploration -and $lastExploration.outputTimestamp) { $lastExploration.outputTimestamp } elseif ($lastExploration) { $lastExploration.timestamp } else { $null })

    $planningMs = 0
    $explorationMs = 0
    $developmentMs = 0
    if ($taskStartTime -and $explorationStart) {
        $planningMs = [int][Math]::Max(0, ($explorationStart - $taskStartTime).TotalMilliseconds)
    }
    if ($explorationStart -and $explorationEnd) {
        $explorationMs = [int][Math]::Max(0, ($explorationEnd - $explorationStart).TotalMilliseconds)
    }
    if ($explorationEnd -and $taskEndTime) {
        $developmentMs = [int][Math]::Max(0, ($taskEndTime - $explorationEnd).TotalMilliseconds)
    }

    $usage = $null
    if ($lastToken -and $lastToken.payload.info.total_token_usage) {
        $usage = $lastToken.payload.info.total_token_usage
    }

    [pscustomobject][ordered]@{
        provider = 'Codex'
        model = $(if ($turnContext) { [string]$turnContext.payload.model } else { $null })
        rolloutPath = $selected
        taskDurationMs = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $taskComplete.payload -Name 'duration_ms') 0)
        timeToFirstTokenMs = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $taskComplete.payload -Name 'time_to_first_token_ms') 0)
        stages = [pscustomobject][ordered]@{
            planningDurationMs = $planningMs
            explorationDurationMs = $explorationMs
            developmentIterationDurationMs = $developmentMs
        }
        shellCallCount = $shellCalls.Count
        shellWallMs = [int](@($shellCalls | Measure-Object -Property wallMs -Sum).Sum)
        directPotatoCommandCount = $directPotato.Count
        directPotatoWallMs = [int](@($directPotato | Measure-Object -Property wallMs -Sum).Sum)
        validationRuns = $generatedScriptRuns.Count
        failedValidationRuns = @($generatedScriptRuns | Where-Object { $null -ne $_.exitCode -and $_.exitCode -ne 0 }).Count
        generatedScriptRunDurationMs = [int](@($generatedScriptRuns | Measure-Object -Property wallMs -Sum).Sum)
        toolOutputChars = [int](@($callsById.Values | Measure-Object -Property outputChars -Sum).Sum)
        largestToolOutputChars = [int](@($callsById.Values | Measure-Object -Property outputChars -Maximum).Maximum)
        inputTokens = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $usage -Name 'input_tokens') 0)
        cachedInputTokens = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $usage -Name 'cached_input_tokens') 0)
        outputTokens = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $usage -Name 'output_tokens') 0)
        reasoningTokens = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $usage -Name 'reasoning_output_tokens') 0)
        totalTokens = [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $usage -Name 'total_tokens') 0)
    }
}

function Get-AGTAStageSummary {
    [CmdletBinding()]
    param(
        [object[]] $Metrics,

        [AllowNull()]
        [object] $GeneratedResult,

        [AllowNull()]
        [object] $CodexSummary,

        [AllowNull()]
        [object] $AuthoringEnd
    )

    $planning = 0
    $exploration = 0
    $development = 0
    $stageEvents = @($Metrics | Where-Object { $_.event -eq 'authoring_stage' } | Sort-Object timestamp)
    if ($stageEvents.Count -gt 0) {
        for ($i = 0; $i -lt $stageEvents.Count; $i++) {
            $current = $stageEvents[$i]
            $start = ConvertTo-AGTADateTimeOffset $current.timestamp
            $end = $null
            if ($i -lt ($stageEvents.Count - 1)) {
                $end = ConvertTo-AGTADateTimeOffset $stageEvents[$i + 1].timestamp
            }
            elseif ($AuthoringEnd) {
                $end = ConvertTo-AGTADateTimeOffset $AuthoringEnd.timestamp
            }
            if (-not $start -or -not $end) { continue }
            $duration = [int][Math]::Max(0, ($end - $start).TotalMilliseconds)
            switch ([string]$current.stage) {
                'planning' { $planning += $duration }
                'exploration' { $exploration += $duration }
                'development_iteration' { $development += $duration }
            }
        }
    }
    elseif ($CodexSummary -and $CodexSummary.stages) {
        $planning = [int](ConvertTo-AGTANumber $CodexSummary.stages.planningDurationMs 0)
        $exploration = [int](ConvertTo-AGTANumber $CodexSummary.stages.explorationDurationMs 0)
        $development = [int](ConvertTo-AGTANumber $CodexSummary.stages.developmentIterationDurationMs 0)
    }

    $executionDuration = 0
    if ($GeneratedResult -and $GeneratedResult.startedAt -and $GeneratedResult.finishedAt) {
        $start = ConvertTo-AGTADateTimeOffset $GeneratedResult.startedAt
        $end = ConvertTo-AGTADateTimeOffset $GeneratedResult.finishedAt
        if ($start -and $end) { $executionDuration = [int][Math]::Max(0, ($end - $start).TotalMilliseconds) }
    }
    if ($executionDuration -eq 0 -and $CodexSummary) {
        $executionDuration = [int](ConvertTo-AGTANumber $CodexSummary.generatedScriptRunDurationMs 0)
    }

    [pscustomobject][ordered]@{
        planningDurationMs = $planning
        explorationDurationMs = $exploration
        developmentIterationDurationMs = $development
        totalDurationMs = $planning + $exploration + $development
        generatedScriptExecutionMs = $executionDuration
        validationRuns = $(if ($CodexSummary) { [int](ConvertTo-AGTANumber $CodexSummary.validationRuns 0) } else { @($Metrics | Where-Object { $_.event -eq 'generated_script_run' }).Count })
        failedValidationRuns = $(if ($CodexSummary) { [int](ConvertTo-AGTANumber $CodexSummary.failedValidationRuns 0) } else { @($Metrics | Where-Object { $_.event -eq 'generated_script_run' -and -not $_.ok }).Count })
    }
}

function ConvertTo-AGTARunSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunRoot,

        [string] $PricingPath
    )

    $runRootFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunRoot)
    $manifest = Read-AGTAJsonFile -Path (Join-Path -Path $runRootFull -ChildPath 'run.json')
    $authoringResult = Read-AGTAJsonFile -Path (Join-Path -Path $runRootFull -ChildPath 'results\authoring-result.json')
    $generatedResult = Read-AGTAJsonFile -Path (Join-Path -Path $runRootFull -ChildPath 'results\result.json')
    $metrics = @(Read-AGTAJsonLines -Path (Join-Path -Path $runRootFull -ChildPath 'logs\metrics.jsonl'))
    $openAiRecords = @(Read-AGTAJsonLines -Path (Join-Path -Path $runRootFull -ChildPath 'logs\openai-responses.jsonl'))
    $potatoRecords = @()
    $commandLogPath = $null
    if ($generatedResult -and $generatedResult.artifacts) {
        $commandLogPath = Get-AGTAProperty -Object $generatedResult.artifacts -Name 'commandLogPath'
    }
    if ($commandLogPath -and (Test-Path -LiteralPath $commandLogPath)) {
        $potatoRecords = @(Read-AGTAJsonLines -Path $commandLogPath)
    }
    else {
        foreach ($commandLog in @(Get-ChildItem -LiteralPath (Join-Path -Path $runRootFull -ChildPath 'logs') -Filter 'potato-commands*.jsonl' -File -ErrorAction SilentlyContinue)) {
            $potatoRecords += @(Read-AGTAJsonLines -Path $commandLog.FullName)
        }
    }
    $pricing = Get-AGTAPricingConfig -Path $PricingPath
    $codexSummary = Get-AGTACodexRolloutSummary -RunRoot $runRootFull

    $authoringStart = $metrics | Where-Object { $_.event -eq 'authoring_start' } | Select-Object -First 1
    $authoringEnd = $metrics | Where-Object { $_.event -eq 'authoring_end' } | Select-Object -Last 1
    $provider = Get-AGTAProperty -Object $authoringResult -Name 'provider'
    if (-not $provider) { $provider = Get-AGTAProperty -Object $authoringStart -Name 'provider' }
    if (-not $provider -and $codexSummary) { $provider = $codexSummary.provider }
    $model = Get-AGTAProperty -Object $authoringResult -Name 'model'
    if (-not $model) { $model = Get-AGTAProperty -Object $authoringStart -Name 'model' }
    if (-not $model -and $codexSummary) { $model = $codexSummary.model }

    $stepSummary = Get-AGTAStepSummary -GeneratedResult $generatedResult
    $potatoSummary = Get-AGTAPotatoSummary -Metrics $metrics -PotatoRecords $potatoRecords -GeneratedResult $generatedResult
    $aiSummary = Get-AGTAAiSummary -Metrics $metrics -OpenAiRecords $openAiRecords -Pricing $pricing -Model $model
    if ($codexSummary -and $aiSummary.totalTokens -eq 0) {
        $aiSummary = [pscustomobject][ordered]@{
            responseCount = 0
            inputTokens = $codexSummary.inputTokens
            cachedInputTokens = $codexSummary.cachedInputTokens
            outputTokens = $codexSummary.outputTokens
            reasoningTokens = $codexSummary.reasoningTokens
            totalTokens = $codexSummary.totalTokens
            responseDurationMs = 0
            estimatedCostUsd = Get-AGTACostEstimate -Pricing $pricing -Model $model -InputTokens $codexSummary.inputTokens -CachedInputTokens $codexSummary.cachedInputTokens -OutputTokens $codexSummary.outputTokens
        }
    }
    $stageSummary = Get-AGTAStageSummary -Metrics $metrics -GeneratedResult $generatedResult -CodexSummary $codexSummary -AuthoringEnd $authoringEnd
    $screenshots = @()
    if (Test-Path -LiteralPath $runRootFull) {
        $screenshots = @(Get-ChildItem -LiteralPath $runRootFull -Recurse -File -Include *.png,*.jpg,*.jpeg -ErrorAction SilentlyContinue)
    }

    $ok = $false
    if ($generatedResult) {
        $ok = [bool](Get-AGTAProperty -Object $generatedResult -Name 'ok' $false)
    }
    elseif ($authoringResult) {
        $ok = [bool](Get-AGTAProperty -Object $authoringResult -Name 'ok' (Get-AGTAProperty -Object $authoringEnd -Name 'ok' $false))
    }
    elseif ($authoringEnd) {
        $ok = [bool](Get-AGTAProperty -Object $authoringEnd -Name 'ok' $false)
    }

    [pscustomobject][ordered]@{
        runId = $(if ($manifest) { Get-AGTAProperty -Object $manifest -Name 'runId' } else { Split-Path -Leaf $runRootFull })
        runRoot = $runRootFull
        testCase = $(if ($manifest) { Split-Path -Leaf (Get-AGTAProperty -Object $manifest -Name 'testCaseCsv') } else { $null })
        provider = $provider
        model = $model
        ok = $ok
        startedAt = $(if ($authoringStart) { Get-AGTAProperty -Object $authoringStart -Name 'timestamp' } else { Get-AGTAProperty -Object $manifest -Name 'createdAt' })
        finishedAt = $(if ($authoringEnd) { Get-AGTAProperty -Object $authoringEnd -Name 'timestamp' } else { $null })
        authoringDurationMs = $(if ($authoringEnd) { [int](ConvertTo-AGTANumber (Get-AGTAProperty -Object $authoringEnd -Name 'durationMs') 0) } elseif ($codexSummary) { [int](ConvertTo-AGTANumber $codexSummary.taskDurationMs 0) } else { 0 })
        steps = $stepSummary
        ai = $aiSummary
        potato = $potatoSummary
        stages = $stageSummary
        agent = [pscustomobject][ordered]@{
            rolloutPath = $(if ($codexSummary) { $codexSummary.rolloutPath } else { $null })
            sessionDurationMs = $(if ($codexSummary) { $codexSummary.taskDurationMs } else { 0 })
            shellCallCount = $(if ($codexSummary) { $codexSummary.shellCallCount } else { 0 })
            shellWallMs = $(if ($codexSummary) { $codexSummary.shellWallMs } else { 0 })
            directPotatoCommandCount = $(if ($codexSummary) { $codexSummary.directPotatoCommandCount } else { 0 })
            directPotatoWallMs = $(if ($codexSummary) { $codexSummary.directPotatoWallMs } else { 0 })
            validationRuns = $stageSummary.validationRuns
            failedValidationRuns = $stageSummary.failedValidationRuns
            generatedScriptRunDurationMs = $(if ($codexSummary) { $codexSummary.generatedScriptRunDurationMs } else { $stageSummary.generatedScriptExecutionMs })
            toolOutputChars = $(if ($codexSummary) { $codexSummary.toolOutputChars } else { 0 })
            largestToolOutputChars = $(if ($codexSummary) { $codexSummary.largestToolOutputChars } else { 0 })
        }
        artifacts = [pscustomobject][ordered]@{
            screenshotCount = $screenshots.Count
            authoringResultPath = Join-Path -Path $runRootFull -ChildPath 'results\authoring-result.json'
            generatedResultPath = Join-Path -Path $runRootFull -ChildPath 'results\result.json'
            generatedResultBytes = Get-AGTAFileSize (Join-Path -Path $runRootFull -ChildPath 'results\result.json')
            commandLogPath = $commandLogPath
            commandLogBytes = $(if ($commandLogPath -and (Test-Path -LiteralPath $commandLogPath)) { Get-AGTAFileSize $commandLogPath } else { [int64](@(Get-ChildItem -LiteralPath (Join-Path -Path $runRootFull -ChildPath 'logs') -Filter 'potato-commands*.jsonl' -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) })
        }
    }
}

function New-AGTAAnalysisDataset {
    [CmdletBinding()]
    param(
        [string] $RunsRoot = (Get-AGTAAnalysisDefaultRunsRoot),

        [string] $PricingPath
    )

    $runs = @(Get-AGTARunRoots -RunsRoot $RunsRoot | ForEach-Object { ConvertTo-AGTARunSummary -RunRoot $_ -PricingPath $PricingPath })
    $totalCost = @($runs | ForEach-Object { if ($null -ne $_.ai.estimatedCostUsd) { $_.ai.estimatedCostUsd } } | Measure-Object -Sum).Sum

    [pscustomobject][ordered]@{
        generatedAt = (Get-Date).ToString('o')
        runsRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunsRoot)
        pricingPath = $PricingPath
        summary = [pscustomobject][ordered]@{
            runCount = $runs.Count
            succeeded = @($runs | Where-Object { $_.ok }).Count
            failed = @($runs | Where-Object { -not $_.ok }).Count
            totalAuthoringDurationMs = [int](@($runs | Measure-Object -Property authoringDurationMs -Sum).Sum)
            totalTokens = [int](@($runs | ForEach-Object { $_.ai.totalTokens } | Measure-Object -Sum).Sum)
            totalCostUsd = $(if ($null -ne $totalCost) { [Math]::Round([double]$totalCost, 6) } else { $null })
            totalValidationRuns = [int](@($runs | ForEach-Object { $_.stages.validationRuns } | Measure-Object -Sum).Sum)
            totalToolOutputChars = [int](@($runs | ForEach-Object { $_.agent.toolOutputChars } | Measure-Object -Sum).Sum)
        }
        runs = $runs
    }
}

function New-AGTAAnalysisDashboard {
    [CmdletBinding()]
    param(
        [string] $RunsRoot = (Get-AGTAAnalysisDefaultRunsRoot),

        [string] $OutputPath = (Join-Path -Path (Get-AGTAAnalysisRoot) -ChildPath ('analysis-output\dashboard_{0}.html' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))),

        [string] $PricingPath
    )

    $dataset = New-AGTAAnalysisDataset -RunsRoot $RunsRoot -PricingPath $PricingPath
    $datasetJson = $dataset | ConvertTo-Json -Depth 100
    $html = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Automated GUI Testing Analysis</title>
<style>
:root { color-scheme: light; --bg:#f7f8fa; --panel:#fff; --text:#1f2933; --muted:#64748b; --line:#d9e2ec; --blue:#2563eb; --green:#059669; --red:#dc2626; --amber:#d97706; --ink:#0f172a; }
body { margin:0; font-family:Segoe UI, Arial, sans-serif; background:var(--bg); color:var(--text); }
header { padding:18px 24px; background:var(--ink); color:white; }
h1 { margin:0; font-size:22px; font-weight:600; }
main { padding:18px 24px 32px; }
.controls, .cards, .grid { display:grid; gap:12px; }
.controls { grid-template-columns:repeat(5, minmax(140px, 1fr)); margin-bottom:14px; }
.cards { grid-template-columns:repeat(7, minmax(120px, 1fr)); margin-bottom:14px; }
.card, .panel { background:var(--panel); border:1px solid var(--line); border-radius:6px; padding:12px; }
.label { color:var(--muted); font-size:12px; }
.value { font-size:22px; font-weight:650; margin-top:4px; }
select, input { width:100%; box-sizing:border-box; padding:8px; border:1px solid var(--line); border-radius:4px; background:white; color:var(--text); }
.grid { grid-template-columns:1fr 1fr; }
.wide { grid-column:1 / -1; }
h2 { margin:0 0 10px; font-size:15px; }
svg { width:100%; height:260px; }
.bar { fill:var(--blue); }
.bar.ok { fill:var(--green); }
.bar.fail { fill:var(--red); }
.bar.planning { fill:var(--blue); }
.bar.exploration { fill:var(--amber); }
.bar.development { fill:var(--green); }
.bar.execution { fill:#7c3aed; }
.axis { stroke:var(--line); stroke-width:1; }
.tick, .empty, .axis-label, .legend { fill:var(--muted); font-size:11px; }
.chart-label { fill:var(--muted); font-size:10px; }
.chart-value { fill:var(--text); font-size:11px; font-weight:650; }
table { width:100%; border-collapse:collapse; font-size:13px; }
th, td { border-bottom:1px solid var(--line); padding:8px; text-align:left; vertical-align:top; }
th { color:var(--muted); font-weight:600; cursor:pointer; }
.status-ok { color:var(--green); font-weight:650; }
.status-fail { color:var(--red); font-weight:650; }
@media (max-width: 900px) { .controls, .cards, .grid { grid-template-columns:1fr; } }
</style>
</head>
<body>
<header><h1>Automated GUI Testing Analysis</h1><div class="label" id="generatedAt"></div></header>
<main>
  <section class="controls card">
    <label><span class="label">Provider</span><select id="providerFilter"></select></label>
    <label><span class="label">Model</span><select id="modelFilter"></select></label>
    <label><span class="label">Status</span><select id="statusFilter"><option value="">All</option><option value="ok">Success</option><option value="fail">Failure</option></select></label>
    <label><span class="label">Search</span><input id="searchFilter" placeholder="run, testcase, command"></label>
    <label><span class="label">Sort</span><select id="sortSelect"><option value="startedAt">Started</option><option value="duration">Authoring time</option><option value="tokens">Tokens</option><option value="cost">Cost</option><option value="commands">Commands</option><option value="validation">Validation runs</option><option value="output">Tool output</option></select></label>
  </section>
  <section class="cards">
    <div class="card"><div class="label">Runs</div><div class="value" id="runCount">0</div></div>
    <div class="card"><div class="label">Success rate</div><div class="value" id="successRate">0%</div></div>
    <div class="card"><div class="label">Total authoring time</div><div class="value" id="totalDuration">0s</div></div>
    <div class="card"><div class="label">Validation runs</div><div class="value" id="validationRuns">0</div></div>
    <div class="card"><div class="label">Total tokens</div><div class="value" id="totalTokens">0</div></div>
    <div class="card"><div class="label">Tool output</div><div class="value" id="toolOutput">0 B</div></div>
    <div class="card"><div class="label">Estimated cost</div><div class="value" id="totalCost">n/a</div></div>
  </section>
  <section class="grid">
    <div class="panel wide"><h2>Stage Duration by Run</h2><svg id="stageChart"></svg></div>
    <div class="panel"><h2>Authoring Time by Run</h2><svg id="durationChart"></svg></div>
    <div class="panel"><h2>Token Use by Run</h2><svg id="tokenChart"></svg></div>
    <div class="panel"><h2>PoTATo Command Counts</h2><svg id="commandChart"></svg></div>
    <div class="panel"><h2>Status Breakdown</h2><svg id="statusChart"></svg></div>
    <div class="panel"><h2>Validation Runs by Run</h2><svg id="validationChart"></svg></div>
    <div class="panel"><h2>Tool Output Volume</h2><svg id="outputChart"></svg></div>
    <div class="panel wide"><h2>Runs</h2><table id="runsTable"></table></div>
  </section>
</main>
<script>
const DATASET = __DATASET__;
let sortKey = 'startedAt';
function fmtMs(ms){ if(!ms) return '0s'; const s=ms/1000; if(s<60) return s.toFixed(1)+'s'; return (s/60).toFixed(1)+'m'; }
function fmtNum(n){ return Number(n||0).toLocaleString(); }
function fmtCost(v){ return v === null || v === undefined ? 'n/a' : '$' + Number(v).toFixed(4); }
function fmtBytes(n){ const v=Number(n||0); if(v<1024) return fmtNum(v)+' B'; if(v<1048576) return (v/1024).toFixed(1)+' KB'; return (v/1048576).toFixed(1)+' MB'; }
function esc(value){ return String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch])); }
function compactLabel(value, maxLen){
  const source=String(value ?? '').trim();
  if(!source) return '';
  let label=source;
  const parts=source.split('_');
  if(parts.length >= 2 && /^\d{8}$/.test(parts[0])) label=parts[1];
  if(label.length <= maxLen) return label;
  return label.slice(0, Math.max(1, maxLen - 3)) + '...';
}
function unique(values){ return [...new Set(values.filter(v => v !== null && v !== undefined && String(v).trim() !== ''))].sort(); }
function optionize(select, values){ const current=select.value; select.innerHTML='<option value="">All</option>'+values.map(v=>`<option>${String(v)}</option>`).join(''); select.value=current; }
function filteredRuns(){
  const p=document.getElementById('providerFilter').value;
  const m=document.getElementById('modelFilter').value;
  const st=document.getElementById('statusFilter').value;
  const q=document.getElementById('searchFilter').value.toLowerCase();
  let runs=(DATASET.runs||[]).filter(r => (!p || r.provider===p) && (!m || r.model===m) && (!st || (st==='ok')===!!r.ok));
  if(q){ runs=runs.filter(r => JSON.stringify({runId:r.runId,testCase:r.testCase,provider:r.provider,model:r.model,potato:r.potato,stages:r.stages,agent:r.agent}).toLowerCase().includes(q)); }
  const key=document.getElementById('sortSelect').value;
  runs.sort((a,b) => {
    const map={startedAt:r=>Date.parse(r.startedAt||0), duration:r=>(r.stages&&r.stages.totalDurationMs)||r.authoringDurationMs||0, tokens:r=>(r.ai&&r.ai.totalTokens)||0, cost:r=>(r.ai&&r.ai.estimatedCostUsd)||0, commands:r=>(r.potato&&r.potato.commandCount)||0, validation:r=>(r.stages&&r.stages.validationRuns)||0, output:r=>(r.agent&&r.agent.toolOutputChars)||0};
    return (map[key](b)-map[key](a));
  });
  return runs;
}
function drawBars(svgId, rows, valueFn, labelFn, clsFn, valueLabelFn){
  const svg=document.getElementById(svgId); svg.innerHTML='';
  const w=Math.max(svg.clientWidth||520, 320), h=260, pad={left:42,right:18,top:24,bottom:58};
  const baseY=h-pad.bottom, plotW=w-pad.left-pad.right, plotH=baseY-pad.top;
  if(!rows.length){ svg.innerHTML='<text class="empty" x="16" y="32">No data</text>'; return; }
  svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
  const values=rows.map(r => Number(valueFn(r)||0));
  const actualMax=Math.max(0,...values);
  const max=Math.max(1,actualMax);
  const gap=rows.length > 12 ? 3 : 8;
  const bw=Math.max(4,(plotW - gap*(rows.length-1))/rows.length);
  const formatValue=valueLabelFn || ((v) => fmtNum(v));
  const rotateLabels=rows.length > 6;
  svg.insertAdjacentHTML('beforeend', `<line class="axis" x1="${pad.left}" y1="${baseY}" x2="${w-pad.right}" y2="${baseY}"></line>`);
  svg.insertAdjacentHTML('beforeend', `<line class="axis" x1="${pad.left}" y1="${pad.top}" x2="${pad.left}" y2="${baseY}"></line>`);
  svg.insertAdjacentHTML('beforeend', `<text class="axis-label" x="${pad.left-8}" y="${baseY+4}" text-anchor="end">0</text>`);
  if(actualMax > 0){
    svg.insertAdjacentHTML('beforeend', `<text class="axis-label" x="${pad.left-8}" y="${pad.top+4}" text-anchor="end">${esc(formatValue(actualMax))}</text>`);
  }
  rows.forEach((r,i)=>{
    const v=Number(valueFn(r)||0), bh=v > 0 ? Math.max(1,plotH*(v/max)) : 0, x=pad.left+i*(bw+gap), y=baseY-bh;
    const label=String(labelFn(r) ?? ''), valueText=formatValue(v), c=clsFn?clsFn(r):'', center=x+(bw/2);
    const valueY=v > 0 && y < pad.top+13 ? y+14 : baseY-bh-6;
    svg.insertAdjacentHTML('beforeend', `<rect class="bar ${c}" x="${x}" y="${y}" width="${bw}" height="${bh}"><title>${esc(label)}: ${esc(valueText)}</title></rect>`);
    svg.insertAdjacentHTML('beforeend', `<text class="chart-value" x="${center}" y="${valueY}" text-anchor="middle">${esc(valueText)}</text>`);
    if(rotateLabels){
      svg.insertAdjacentHTML('beforeend', `<text class="chart-label" transform="translate(${center},${baseY+36}) rotate(-35)" text-anchor="end"><title>${esc(label)}</title>${esc(compactLabel(label, 10))}</text>`);
    } else {
      svg.insertAdjacentHTML('beforeend', `<text class="chart-label" x="${center}" y="${baseY+19}" text-anchor="middle"><title>${esc(label)}</title>${esc(compactLabel(label, 16))}</text>`);
    }
  });
}
function drawStackedBars(svgId, rows, segments, labelFn){
  const svg=document.getElementById(svgId); svg.innerHTML='';
  const w=Math.max(svg.clientWidth||900, 420), h=280, pad={left:52,right:18,top:42,bottom:62};
  const baseY=h-pad.bottom, plotW=w-pad.left-pad.right, plotH=baseY-pad.top;
  if(!rows.length){ svg.innerHTML='<text class="empty" x="16" y="32">No data</text>'; return; }
  svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
  const totals=rows.map(r => segments.reduce((a,s)=>a+Number(s.value(r)||0),0));
  const max=Math.max(1,...totals);
  const gap=rows.length > 12 ? 4 : 10;
  const bw=Math.max(8,(plotW - gap*(rows.length-1))/rows.length);
  svg.insertAdjacentHTML('beforeend', `<line class="axis" x1="${pad.left}" y1="${baseY}" x2="${w-pad.right}" y2="${baseY}"></line>`);
  svg.insertAdjacentHTML('beforeend', `<line class="axis" x1="${pad.left}" y1="${pad.top}" x2="${pad.left}" y2="${baseY}"></line>`);
  svg.insertAdjacentHTML('beforeend', `<text class="axis-label" x="${pad.left-8}" y="${baseY+4}" text-anchor="end">0</text>`);
  svg.insertAdjacentHTML('beforeend', `<text class="axis-label" x="${pad.left-8}" y="${pad.top+4}" text-anchor="end">${esc(fmtMs(max))}</text>`);
  let lx=pad.left;
  segments.forEach(s => { svg.insertAdjacentHTML('beforeend', `<rect class="bar ${s.cls}" x="${lx}" y="12" width="10" height="10"></rect><text class="legend" x="${lx+14}" y="21">${esc(s.label)}</text>`); lx += 106; });
  const rotateLabels=rows.length > 6;
  rows.forEach((r,i)=>{
    const x=pad.left+i*(bw+gap), center=x+bw/2;
    let y=baseY, total=0;
    segments.forEach(s => {
      const v=Number(s.value(r)||0); total += v;
      if(v <= 0) return;
      const bh=Math.max(1,plotH*(v/max)); y -= bh;
      svg.insertAdjacentHTML('beforeend', `<rect class="bar ${s.cls}" x="${x}" y="${y}" width="${bw}" height="${bh}"><title>${esc(labelFn(r))} ${esc(s.label)}: ${esc(fmtMs(v))}</title></rect>`);
    });
    if(total > 0){ svg.insertAdjacentHTML('beforeend', `<text class="chart-value" x="${center}" y="${Math.max(pad.top+14,y-6)}" text-anchor="middle">${esc(fmtMs(total))}</text>`); }
    if(rotateLabels){ svg.insertAdjacentHTML('beforeend', `<text class="chart-label" transform="translate(${center},${baseY+38}) rotate(-35)" text-anchor="end"><title>${esc(labelFn(r))}</title>${esc(compactLabel(labelFn(r), 10))}</text>`); }
    else { svg.insertAdjacentHTML('beforeend', `<text class="chart-label" x="${center}" y="${baseY+19}" text-anchor="middle"><title>${esc(labelFn(r))}</title>${esc(compactLabel(labelFn(r), 16))}</text>`); }
  });
}
function drawCommandChart(runs){
  const counts={};
  runs.forEach(r => Object.entries((r.potato&&r.potato.commandCounts)||{}).forEach(([k,v]) => counts[k]=(counts[k]||0)+v));
  const rows=Object.entries(counts).map(([command,count])=>({command,count})).sort((a,b)=>b.count-a.count).slice(0,18);
  drawBars('commandChart', rows, r=>r.count, r=>r.command);
}
function drawStatusChart(runs){
  const rows=[{label:'Success',count:runs.filter(r=>r.ok).length,ok:true},{label:'Failure',count:runs.filter(r=>!r.ok).length,ok:false}];
  drawBars('statusChart', rows, r=>r.count, r=>r.label, r=>r.ok?'ok':'fail');
}
function drawStageChart(runs){
  const rows=runs.slice(0,30);
  drawStackedBars('stageChart', rows, [
    {label:'Planning', cls:'planning', value:r=>(r.stages&&r.stages.planningDurationMs)||0},
    {label:'Exploration', cls:'exploration', value:r=>(r.stages&&r.stages.explorationDurationMs)||0},
    {label:'Dev/Iteration', cls:'development', value:r=>(r.stages&&r.stages.developmentIterationDurationMs)||0}
  ], r=>r.runId||'run');
}
function drawTable(runs){
  const table=document.getElementById('runsTable');
  table.innerHTML='<thead><tr><th>Status</th><th>Run</th><th>Provider</th><th>Model</th><th>Stages</th><th>Validation</th><th>Tokens</th><th>Output</th><th>PoTATo</th><th>Steps</th></tr></thead>';
  const body=document.createElement('tbody');
  runs.forEach(r=>{ const tr=document.createElement('tr'); const steps=r.steps||{}, ai=r.ai||{}, p=r.potato||{}, st=r.stages||{}, ag=r.agent||{}; tr.innerHTML=`<td class="${r.ok?'status-ok':'status-fail'}">${r.ok?'PASS':'FAIL'}</td><td title="${r.runRoot||''}">${r.testCase||''}<br><span class="label">${r.runId||''}</span></td><td>${r.provider||''}</td><td>${r.model||''}</td><td>${fmtMs(st.planningDurationMs)} / ${fmtMs(st.explorationDurationMs)} / ${fmtMs(st.developmentIterationDurationMs)}<br><span class="label">P / E / Dev</span></td><td>${fmtNum(st.validationRuns||ag.validationRuns)} runs<br><span class="label">${fmtMs(ag.generatedScriptRunDurationMs||st.generatedScriptExecutionMs)}</span></td><td>${fmtNum(ai.totalTokens)}</td><td>${fmtBytes(ag.toolOutputChars)}</td><td>${fmtNum(p.commandCount)} cmds<br><span class="label">${fmtMs(p.durationMs)}</span></td><td>${fmtNum(steps.passed)}/${fmtNum(steps.total)} passed</td>`; body.appendChild(tr); });
  table.appendChild(body);
}
function render(){
  const runs=filteredRuns();
  const totalDuration=runs.reduce((a,r)=>a+(r.authoringDurationMs||0),0);
  const totalTokens=runs.reduce((a,r)=>a+((r.ai&&r.ai.totalTokens)||0),0);
  const totalValidationRuns=runs.reduce((a,r)=>a+((r.stages&&r.stages.validationRuns)||0),0);
  const totalToolOutput=runs.reduce((a,r)=>a+((r.agent&&r.agent.toolOutputChars)||0),0);
  const costs=runs.map(r=>r.ai&&r.ai.estimatedCostUsd).filter(v=>v!==null&&v!==undefined);
  document.getElementById('runCount').textContent=fmtNum(runs.length);
  document.getElementById('successRate').textContent=runs.length?Math.round(100*runs.filter(r=>r.ok).length/runs.length)+'%':'0%';
  document.getElementById('totalDuration').textContent=fmtMs(totalDuration);
  document.getElementById('validationRuns').textContent=fmtNum(totalValidationRuns);
  document.getElementById('totalTokens').textContent=fmtNum(totalTokens);
  document.getElementById('toolOutput').textContent=fmtBytes(totalToolOutput);
  document.getElementById('totalCost').textContent=costs.length?fmtCost(costs.reduce((a,b)=>a+b,0)):'n/a';
  drawStageChart(runs);
  drawBars('durationChart', runs.slice(0,30), r=>r.authoringDurationMs||0, r=>r.runId||'run', r=>r.ok?'ok':'fail', v=>fmtMs(v));
  drawBars('tokenChart', runs.slice(0,30), r=>(r.ai&&r.ai.totalTokens)||0, r=>r.runId||'run');
  drawBars('validationChart', runs.slice(0,30), r=>(r.stages&&r.stages.validationRuns)||0, r=>r.runId||'run');
  drawBars('outputChart', runs.slice(0,30), r=>(r.agent&&r.agent.toolOutputChars)||0, r=>r.runId||'run', null, v=>fmtBytes(v));
  drawCommandChart(runs);
  drawStatusChart(runs);
  drawTable(runs);
}
function init(){
  document.getElementById('generatedAt').textContent='Generated '+(DATASET.generatedAt||'')+' from '+(DATASET.runsRoot||'');
  optionize(document.getElementById('providerFilter'), unique((DATASET.runs||[]).map(r=>r.provider)));
  optionize(document.getElementById('modelFilter'), unique((DATASET.runs||[]).map(r=>r.model)));
  ['providerFilter','modelFilter','statusFilter','searchFilter','sortSelect'].forEach(id=>document.getElementById(id).addEventListener('input', render));
  render();
}
init();
</script>
</body>
</html>
'@
    $html = $html.Replace('__DATASET__', $datasetJson)
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
    $html | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return [pscustomobject][ordered]@{
        ok = $true
        outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        runs = $dataset.summary.runCount
        generatedAt = $dataset.generatedAt
    }
}

Export-ModuleMember -Function `
    Get-AGTAAnalysisRoot, `
    Get-AGTAAnalysisFrameworkRoot, `
    Get-AGTAAnalysisDefaultRunsRoot, `
    Read-AGTAJsonLines, `
    Get-AGTACostEstimate, `
    Get-AGTARunRoots, `
    ConvertTo-AGTARunSummary, `
    New-AGTAAnalysisDataset, `
    New-AGTAAnalysisDashboard

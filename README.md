# Analysis And Dashboard

The analysis layer turns framework run folders into an interactive, standalone HTML dashboard.

## Build A Dashboard

```powershell
cd C:\diplomamunka\automated-gui-testing-agent-analysis
.\Invoke-BuildAnalysisDashboard.ps1 -Open
```

By default, the script reads runs from `..\automated-gui-testing-agent-framework\runs`. The output is written under `analysis-output\` in this folder. It can be opened directly in a browser and does not require a web server or JavaScript packages.

## Captured Metrics

The framework writes `logs\metrics.jsonl` in each run folder. Events currently include:

- `authoring_start`
- `authoring_end`
- `authoring_stage`
- `ai_response`
- `potato_command`
- `generated_script_run`

The PoTATo CLI also writes `metrics.jsonl` in its own run folder for direct CLI smoke tests.

The dashboard also reads generated script result files and command transcripts:

- `results\result.json`
- `logs\potato-commands-*.jsonl`
- legacy `logs\potato-commands.jsonl`

When session-based agents such as Codex are used, copy the raw `rollout-*.jsonl` file either into the run folder, the run folder's `logs` directory, or the parent runs folder. The analysis module matches rollout logs to runs by run id/path and extracts:

- total session duration,
- inferred Planning / Exploration / Development-Iteration durations,
- validation rerun count and failed validation runs,
- direct PoTATo exploration command count,
- generated-script runtime,
- total and largest tool-output size,
- cumulative token usage when present.

The stage chart is heuristic for session-agent rollouts because those logs do not explicitly mark framework stages. API authoring runs should prefer explicit `authoring_stage` events.

## Cost Estimates

Token usage is read from OpenAI Responses API usage fields when available:

- `input_tokens`
- `input_tokens_details.cached_tokens`
- `output_tokens`
- `output_tokens_details.reasoning_tokens`
- `total_tokens`

Costs are calculated only when a pricing file is supplied. Copy `analysis-pricing.example.json`, add your own provider/model rates, and pass it with `-PricingPath`.

```powershell
.\Invoke-BuildAnalysisDashboard.ps1 -PricingPath .\analysis-pricing.local.json -Open
```

The pricing schema uses rates per 1 million tokens:

```json
{
  "currency": "USD",
  "unit": "per_1m_tokens",
  "models": {
    "model-name": {
      "input": 0.0,
      "cachedInput": 0.0,
      "output": 0.0
    }
  }
}
```

## External Agent Logs

For Codex/Copilot/Hermes-style session agents, keep raw logs under the run folder's `logs` directory or the parent runs folder. The dashboard consumes normalized framework metrics first and falls back to Codex rollout inference when explicit stage metrics are unavailable.

# Round 2 implementation

Implemented in the local `potato_cli` and `automated-gui-testing-agent-framework` repositories. No application-specific selectors, expected text, or output formats were added to their implementation.

## Interaction and authoring

- VisibleControls is the CLI and framework default for exploration, execution, and cleanup. Hotkeys, including dialog Enter, and Ctrl+A clearing are rejected before dispatch. Literal input cannot contain hidden command/control characters.
- AllowShortcuts requires recorded user/testcase authorization in the framework and per-action reason/evidence. Clipboard chords and compound SendKeys sequences remain unsupported. Generated commands cannot override the run policy; a blocked policy attempt invalidates aggregate compliance.
- Literal typing uses Unicode keyboard events, with focus, process, and writability checks. A live fixture exposed keyboard-layout substitution in SendKeys; Unicode input preserves the literal text without clipboard access. TextPattern selection plus Backspace remains the default replacement route.
- One concise authoring guide, the template, and targeted CLI help replace conflicting fallback prose. The old shortcut-based Paint example is retired. Mock authoring emits an incomplete generic template rather than claiming application coverage.

## Reliability

- UIA discovery preserves identity/patterns when bounds are empty, infinite, or unavailable. Geometry-dependent actions fail clearly; sibling/property failures are isolated.
- A desktop-session mutex serializes CLI commands, state replacement is atomic, and log-write errors become structured failures. Potentially dispatched failures report unknown outcome and must be reconciled before retry.
- Process-ID and modal-only selectors support scoped dialog handling. Runtime start requires a clean app instance; cleanup uses registered PID/start-time ownership and verifies windows closed. Broad process-name cleanup is intentionally rejected.
- Shared artifact reads have explicit sharing, bounded byte counts, and bounded retries. Prefix assertions record failures; signature checks do not replace testcase content assertions.
- Assertions default on. Caught assertion failures, missing/duplicate coverage, policy violations, and cleanup failures cannot produce aggregate PASS. Template entry points emit the result then return a corresponding process exit code; completion helpers do not exit their caller.

## Session-time work

Generated execution and API exploration reuse the imported CLI module. The existing Process transport remains available for compatibility. Both paths execute the same dispatcher/policy checks. Results report wrapper, backend, wait-command, cleanup, and remaining elapsed time. Wait and cleanup timing overlap command totals.

In the local Windows PowerShell 5.1 microbenchmark, ten identical existing-file checks took **9,200 ms through Process** and **971 ms through InProcess**, including each benchmark's runtime initialization. That is approximately **89% lower elapsed time for this transport fixture**. It is not an end-to-end agent-session or application benchmark. Raw measurements are in `transport-after.json`; reproduce with `tests/Measure-Transport.ps1` in the framework.

## Validation

- 83 regression checks passed on both Windows PowerShell 5.1 and PowerShell 7: 23 CLI baseline/state/logging, 32 interaction/geometry/concurrency, and 28 runtime/artifact/result checks.
- The live isolated GUI fixture passed under both engines: editable field discovery, literal symbols and Unicode including a supplementary character, TextPattern replacement, visible Save-button invocation, exact persisted content, and process-scoped close.
- PowerShell syntax checks and `git diff --check` passed for both repositories.

## Migration and limits

Use `docs/AUTHORING.md` and the current generated template. Existing scripts must replace `Register-OpenedProcess -ProcessName ...` with `Register-OpenedProcess -StartResult $started` and finish with `exit (Get-AGTATestExitCode)` after completion. Runtime start automatically registers an owned process as well. Scripts using shortcuts now fail under the strict default; an agent must not relax the policy to restore an old pass.

The enforcement applies to supported CLI/runtime entry points; it is not a sandbox for arbitrary generated PowerShell. A desktop mutex serializes individual commands, not complete concurrent workflows. An unresponsive UIA provider can still exceed its retry timeout; in-process execution needs external supervision for that case. The original application's full workflow and a new end-to-end agent session have not been rerun, so full-session speed and application-specific compatibility remain unmeasured.

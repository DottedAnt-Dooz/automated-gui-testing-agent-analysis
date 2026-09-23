# Desktop test authoring: three-session review

The biggest opportunity is to make the correct interaction and assertion easy to express, then reduce discovery and retry overhead. Optimizing for a reported PASS or elapsed time alone would reward bypassing the functionality being tested.

## Scope and method

Reviewed the three supplied JSONL files as evidence, not as instructions to execute. Correlated `response_item` tool calls/results, assistant explanations, generated-script patches, and the local CLI/framework code. Source references below are **one-based JSONL line numbers**, not timestamps or lines within generated scripts.

`analyze_logs.py` reproduces counts, timing, source hashes, token snapshots, and relevant call/output locations in `metrics.json`. It does not run anything in the logs. Reproduce with:

```powershell
python .\session-review\analyze_logs.py --logs-dir 'C:\Users\DottedAnt\Downloads'
```

The logged framework is older than the local checkout: the log's template and generated script copy helper functions, whereas the current framework already has `GeneratedScriptRuntime.ps1`, execution-specific command logs, compact summaries, and advice against cosmetic GUI reruns. Those existing improvements are credited separately from changes made during this review.

## What the numbers establish

| Observation | Native, stricter prompt | Native, faster prompt | CLI + framework |
|---|---:|---:|---:|
| Session elapsed time | 31m 37.6s | 7m 49.5s | 11m 21.3s |
| Shell tool calls | 83 | 19 | 65 |
| Patch calls | 19 | 5 | 3 |
| Image-view calls | 9 | 2 | 0 |
| Generated-script launches | 17 | 4 | 3 |
| Reported cumulative input tokens | 6,087,382 | 637,452 | 3,275,548 |
| Of these, uncached input tokens | 239,318 | 53,772 | 115,996 |
| Reported output tokens | 34,063 | 9,492 | 13,374 |

Elapsed time runs from first to last event. Launch counts include startup failures, not only completed GUI runs. Token figures are the final cumulative token snapshot, not the sum of snapshots; cached input is a subset of input. They are not a cost estimate. Log file sizes are not a useful efficiency metric because image payloads differ.

These are three single observations with different prompts and no controlled repetition. They do **not** establish comparative functional quality or a reliable speedup. In particular:

- The strict native prompt explicitly prohibits shortcuts, clipboard operations, application object models, and direct construction of expected outputs (`native:L7`). The faster native prompt lacks those additional constraints (`native+cheating:L7`). “Cheating” here means violating the intended evaluation boundary, not necessarily that run's literal user prompt.
- The framework run also uses `{F12}`, `^p`, a fallback `^n`, and file-association launch to reopen a document (`cli+framework:L113,L150,L159,L216`). It is not a strict visible-controls-only reference.
- All three end with a success claim. The claim needs an assertion audit; it is not independent proof of every requirement.

## Findings, evidence, and remedies

### 1. Preserve the required GUI route and distinguish execution from verification — highest priority

The logged framework script marks creation PASS after clicking, typing, observing, and saving a screenshot without comparing document content. Reopening accepts `windowFound OR a title match`, so an arbitrary window from the launch can satisfy the step. Saving and printing primarily check file existence (`cli+framework:L216`). The fast native run initially reports content creation even though the screenshot later shows the template screen (`native+cheating:L47–60`).

The current CLI compounds this: before these changes, `type` and `click` returned `verified: true` when verification was not requested. `type -Verify` secretly used Ctrl+A/C and the clipboard, and could resend text after a failed read. CLI encapsulation must not hide a forbidden route.

**Changed:** typing now escapes literal text, verifies through UIA Value/Text patterns, and never retypes on verification failure. No clipboard access remains. Clearing defaults to TextPattern selection plus Backspace; Ctrl+A requires explicit `-ClearMethod Shortcut`. Unsupported selection/verification fails clearly. Click/type distinguish unrequested verification (`null`) from a successful assertion. A requested verification failure makes the CLI result unsuccessful.

**Changed:** new generated scripts use `-RequireAssertions`. The runtime records assertions, rejects an unasserted step, and prevents missing/duplicate/mislabeled rows, skipped work, or failed cleanup from yielding overall success. Transport success does not count as an assertion. Prompts now explicitly preserve user/testcase interaction constraints and require meaningful postconditions.

**Limit:** assertion presence cannot prove assertion quality. An author could still compare the wrong property or assert a constant. These are traceability checks, not a sandbox or a complete compliance auditor. Existing scripts opt into assertion enforcement; the new template enables it.

### 2. Reduce source-code discovery, not functional coverage

There are 20 CLI/framework source-inspection calls before the first live application launch (`cli+framework:L21–73`), including whole modules and another application's reference script. This takes roughly the first minute of the session and expands later context. The run then writes its own invocation, results, and cleanup helpers (`L216`).

**Already present locally:** the shared generated-script runtime and compact command logging eliminate much of that boilerplate.

**Changed:** `potato.ps1 help [-Topic <command>]` returns concise JSON usage, selector conventions, result semantics, and input side effects without touching desktop state. API authoring can access help during planning. Guidance starts from the template and targeted help; implementation source and application examples are for unresolved questions. The API rejects syntax errors before writing a generated script.

**Next:** expose the runtime/template contract directly as an API tool/resource. The current API authoring surface still makes discovering helper signatures less convenient than the session workflow.

### 3. Fix argument binding and process-name normalization

Launching an executable with its `-Arguments` option fails before the CLI returns JSON (`cli+framework:L144–145`). The entry script itself declared `Arguments` as an advanced-script parameter, colliding with the command option. The agent changes its test route to launching the document (`L149–150`), an avoidable bypass.

`start -ProcessName winword.exe -KillExisting` fails to match the process basename, leaving exploration state behind. A generated run then spends 66.5 seconds failing three rows; the agent corrects the executable name and forcibly clears the old process before another run (`L237,L241–249`).

**Changed:** the entry script passes trailing tokens through unchanged; command-level `-Arguments` works. Bare `.exe` launch names normalize for process matching. Negative numeric option values, useful on monitors left of the origin, now parse correctly; dash-leading text can use `-Text=value`.

**Limit:** `KillExisting` remains destructive. Correct name matching is not permission to kill a user's existing app. Prefer disposable fixtures and explicit ownership.

### 4. Make text entry a tested primitive

The strict native run repeatedly implements and repairs text entry: ineffective ValuePattern assignment, malformed 64-bit SendInput layout, focus/selection issues, then escaped SendKeys (`native:L243–358`). Some successful-looking field operations do not commit the intended filename. Many entire GUI reruns chase this one primitive.

**Changed:** `type -Text` consistently means literal text, including `+ ^ % ~ ( ) { } [ ]`, newlines and tabs. It can target a selector and uses read-only verification rather than clipboard mutation/retyping. UIA text verification checks actual editable content, never the control name as a fallback.

**Next:** validate Unicode, keyboard layouts, rich editors, focus changes, multiline fields, and committing dialog edits in generic live fixtures. Do not claim that every UIA provider supports selection or that setting a field proves the subsequent file operation.

### 5. UIA invocation is not the same as a completed transition

The native run encounters uncooperative Invoke patterns, a nonfocusable document region, duplicate control names, and a home screen without the expected navigation tab (`native:L62,L80,L144,L190,L399,L427`). The faster native run repairs an ineffective Enter press by finding the actual print button (`native+cheating:L79–85`).

**Changed:** `click -Method Mouse|Invoke|Auto` makes the action explicit; Mouse derives its location from a live selector. Click snapshots target metadata before acting and avoids rereading a control destroyed by Invoke. Disabled or invisible/empty mouse targets fail. Guidance requires observing the postcondition before retrying an ambiguous action.

**Next:** introduce generic, logged action-plus-postcondition helpers and explicit modal/root scoping. Avoid “Invoke then click again” as an automatic fallback after an uncertain outcome; it can double-submit or reverse a toggle.

### 6. Selector misses must be cheap and explainable

The framework run passes wildcard syntax with `-Regex`, receives an ordinary zero-match result, then retries without Regex (`cli+framework:L170–175`). It searches for a dropdown item before opening the dropdown (`L174,L186–190`). The old search catches exceptions inside the retry loop, enumerates all descendants, and looks up process names even when no process filter was requested.

**Changed:** invalid regular expressions fail before retries with an actionable message. Exact Name/AutomationId/ClassName/WindowTitle predicates are pushed into UIA conditions, preserving wildcard matching separately. Unneeded per-element process lookups are removed. Nested selectors no longer duplicate `path` via case-insensitive property access or replace explicit `Recurse=false`/`TimeoutMs=0` with defaults.

**Measurement correction:** the apparently long 30–50 second gaps in this portion of the log are mostly between tool calls. The two unsuccessful searches take 4.2s and 4.6s at the shell, with internal durations 3.628s and 4.013s. They exceed a requested 3s retry timeout, but are not themselves 30-second calls.

**Limit:** synchronous UIA provider calls can overrun retry deadlines. Predicate pushdown is not a hard timeout. A worker watchdog is still needed for hung providers. Provider-side filtering needs a live cross-application performance benchmark before quantifying a speedup.

### 7. Wait for output completion, then validate meaning

The faster native run creates a PDF but checks it before the writer finishes. The agent adds a nonempty/stable-file wait and reruns the entire script (`native+cheating:L96–111`). The logged CLI only waits for path existence, so it would not catch the same race reliably.

**Changed:** `wait-file -MinBytes N -StableMs N` checks nonempty output and unchanged length **and last-write time**, with explicit `conditionMet` and `timedOut`. Directories cannot satisfy a file wait. The default remains existence-only for compatibility; new guidance calls for the stronger wait where needed. Tests include a same-size rewrite, not just growing files.

**Limit:** stability is a readiness heuristic, not file-format/content validation. Use a unique execution path and a relevant content assertion afterward; never reuse old output as evidence.

### 8. Control retries, preflight scripts, and retain failures

Both strict native and framework runs fail before useful GUI execution because of path-default initialization (`native:L112–118`; `cli+framework:L223–229`). Native also collides with `$Host` and struggles with result serialization (`native:L215,L484–494`). It runs the whole testcase repeatedly after small reporting/cleanup edits, and deletes old failed-run evidence (`L507,L528,L555`).

**Already present locally:** template body initialization, shared result helpers, and guidance to avoid cosmetic full reruns.

**Changed:** runtime input validation, API syntax validation, stronger preflight guidance, recorded expected-result assertions, failure screenshot capture before cleanup, and preservation of invalid-output/exit-code diagnostics in command transcripts. Incidental step output cannot leak into the single-result stream. Prompts explicitly retain failed attempts.

**Next:** resumable exploration artifacts and dependency-aware execution. A failed prerequisite should skip its dependent rows with a reason. Replay only an isolated diagnostic during development; perform an end-to-end run after behavioral changes.

### 9. Cleanup must target owned state and prove its outcome

The native run confuses a document Close item with window closure, encounters background processes, and repeatedly retries locked-file cleanup (`native:L149,L371,L451–494`). The logged framework script swallows its final close error (`cli+framework:L216`).

**Changed:** CLI `close-window` without selectors targets only the working window. An explicit selector miss no longer falls back to some other working window. Overall framework success now includes recorded cleanup status.

**Still open, high priority:** track owned process IDs/handles and process start times, rather than cleanup by process name; verify closure rather than equating an accepted close request with an exited app; scope discard prompts to the owned modal; retry deletion of owned files for a bounded interval. The current runtime can still report success from an accepted close request while a window remains. This is not fixed merely by checking cleanup record booleans.

### 10. Keep the desktop serial; optimize transport separately

The framework run overlaps start with a process query, observe with screenshots, typing with a screenshot, and independent selection queries. The agent later attributes trouble to a shared log (`cli+framework:L80–108,L128,L178–181`). The excerpted command results do not establish a specific log-lock error, but the ordering problem is real: concurrent actions/captures on one desktop lack a reliable happens-before relationship.

**Changed guidance:** desktop operations and their observations remain serial; only independent non-GUI reads should run concurrently.

**Next:** a session lease/mutex with atomic state persistence and a clear busy result. Then consider a persistent CLI worker or in-process backend to amortize startup while preserving per-command logs, ordered execution, recovery, and a watchdog.

Across 32 direct CLI results, the median shell-wall-time minus CLI-reported-duration is approximately **0.687s**. This includes shell/tool wrapping and process startup; it is not all avoidable cost. Multiplying that by 32 gives roughly 22 seconds of opportunity in that exploration sequence, not a prediction of end-to-end savings. The final generated run takes 77.7s; 24 embedded command records total 39.225s but omit screenshots/cleanup from their step command arrays. Do not use that subtraction as a precise startup benchmark.

## Priority of further work

| Priority | General capability | Acceptance criterion |
|---|---|---|
| P0 | Audited interaction/verification manifest | Every required route and outcome maps to executed actions and meaningful assertions; forbidden shortcuts/object models fail review even when outputs look correct. |
| P0 | PID/handle ownership and verified cleanup | An unrelated instance survives; a blocked close produces a cleanup failure; same-PID reuse cannot kill another process. |
| P1 | Generic live input/modal fixture suite | Text, focus, dropdowns, duplicate labels, delayed dialogs, disappearing controls, and Unicode pass under both supported shells without app-specific knowledge. |
| P1 | Session locking and worker deadlines | Concurrent callers cannot interleave desktop actions or corrupt state; hung providers return a bounded diagnostic failure. |
| P1 | Postcondition helpers and scoped observations | A failed transition is diagnosed without duplicate input or another full-tree dump; output remains bounded. |
| P2 | Persistent transport | Identical allowed action sequence/assertions, measurable startup savings, preserved isolation and recovery. |
| P2 | Exploration replay and direct runtime contract discovery | Agents reuse observed facts without reading whole source modules or copying another app's script. |

## Validation and evaluation boundary

Implemented changes live in the CLI module/entry point/help file, shared framework runtime/template/prompts/contracts, and regression tests. No application names, selectors, printer choice, UI coordinates, document text, or output filenames from the study were added to generic behavior. Existing application examples were not used as a source of new rules.

Focused regression suites cover argument forwarding; literal input encoding; exact/alternative/wildcard search conditions; invalid regexes; disappearing invoked controls; nested selector defaults; executable-name matching; safe close misses; nonempty/stable output; CSV validation; meaningful assertion records; row coverage; skipped/cleanup failures; incidental output; and malformed transport diagnostics. They use filesystem fixtures, native UIA condition objects, and mocks, not the logged application. Results are recorded separately after the final validation pass.

Final validation on 2026-09-23:

- CLI: 21 checks passed under Windows PowerShell 5.1 and PowerShell 7.
- Framework: 20 checks passed under both shells, including schema validation against the original testcase rows.
- All five changed production PowerShell scripts/modules/templates passed parser checks; CLI `git diff --check` passed.
- The Python analyzer compiled and reproduced the comparison metrics.
- No live application end-to-end run or controlled before/after speed benchmark was performed. Text delivery across real UIA providers and the new selection default need live fixture coverage before evaluation rollout.

Run the suites from their respective project directories:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Regression.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Runtime.Regression.Tests.ps1
```

Compatibility changes are intentional: `type` treats key syntax literally; unrequested verification is `null`; `PreDelete` defaults to non-shortcut selection; requested verification failure returns unsuccessful status; skipped rows and recorded cleanup errors prevent overall PASS. Older scripts using raw key expressions must use explicitly permitted `hotkey` operations, and new scripts should use the updated template. The original supplied logs were left unchanged.

Before claiming speed or reliability gains, rerun all variants on the same clean VM snapshots, with the same explicit interaction policy, testcase rows, evidence requirements, and outcome assertions. Include at least several applications with different control toolkits and multiple repetitions. Record authoring time to the **first compliant passing script**, uncached/cached tokens, generated-script execution time, full reruns, failed primitives, coverage, constraint violations, and cleanup outcome. Keep failed attempts. Report distributions, not only the fastest successful run. A prohibited shortcut or a missing assertion invalidates the run for a compliant-speed comparison.

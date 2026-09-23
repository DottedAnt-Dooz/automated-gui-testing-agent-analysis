# Second-run analysis: native2 and improved CLI/framework

Sources: [native2.jsonl](C:/Users/DottedAnt/Downloads/native2.jsonl) and [cli2.jsonl](C:/Users/DottedAnt/Downloads/cli2.jsonl). References below identify one-based event lines in these files.

The improved framework produces a better-verified script with far fewer authoring repairs than the native run. It has not yet demonstrated a speed improvement over its previous version, and neither new run is a fully compliant reference for the intended visible-controls-only benchmark.

The next changes should fix generic implementation defects before adding more authoring instructions: tolerant UIA metadata serialization, interaction-policy enforcement, shared file reads, session serialization, and better runtime timing.

## Measurements

| Measure | Earlier native | Native2 | Earlier CLI/framework | CLI2 |
|---|---:|---:|---:|---:|
| Session elapsed | 31m37.6s | **37m07.6s** | 11m21.3s | **15m56.6s** |
| Generated-script launches | 17 | **15** | 3 | **2** |
| Shell calls | 83 | 61 | 65 | 61 |
| Patch calls | 19 | 16 | 3 | 2 |
| Image-view calls | 9 | 9 | 0 | 5 |
| Uncached input tokens | 239,318 | **144,492** | 115,996 | **170,898** |
| Output tokens | 34,063 | 27,063 | 13,374 | 14,212 |

CLI2 takes 57.1% less observed session time than native2, but 40.4% more than the earlier framework run. Its uncached input is 18.3% higher than native2 and 47.3% higher than the earlier framework run. Fewer patches therefore do not automatically imply lower time or token consumption.

Both new runs use `gpt-5.5`, medium effort, and the same five CSV rows. Their prompts still differ: native2 explicitly forbids shortcuts/clipboard and requires visible controls; CLI2 asks to use the framework. The framework's conditional fallback guidance does not establish the same strict interaction policy. These are single observations with different behavior and verification, not a controlled causal benchmark.

Session times use first-to-last log events. Launch counts include startup failures. Shell calls that invoke native scripts sometimes also close processes, so their wall times are not pure script-execution measurements. Token totals use the last cumulative snapshot, avoiding double-counting repeated telemetry. Original logs are unchanged and were treated only as evidence.

## What improved, with evidence

1. **Shared runtime adoption worked.** CLI2 uses the template and `Initialize-AGTAGeneratedTest -RequireAssertions`; its generated script contains actions and small local helpers instead of copying all logging/result plumbing (`cli2:L257`). It parses the script and checks paths before execution (`L264–270`). The first run reaches substantive assertions rather than failing on parameter defaults.
2. **Creation verification is stronger.** The script reads actual document text and asserts both the expected phrase and an execution-specific marker. The successful result records both assertions (`L257,L296`). Native2's creation function types and captures a screenshot but does not read the content back (`native2:L57`).
3. **Save/print verification improved.** CLI2 uses unique execution paths, nonempty/stable waits, and file-prefix assertions. The first run correctly reports failures in verification, with failure screenshots (`cli2:L272`). This is materially stronger than a successful button call or path-existence-only check.
4. **Reopening uses the application's Open workflow.** CLI2 visits the Open screen and file dialog rather than starting the saved file (`L164–198,L257`). It still invokes those routes with shortcuts. Native2 retains `Start-Process -FilePath $script:DocumentPath` (`native2:L57`; none of its later patches replaces this function).
5. **Input/verification reporting is more honest.** CLI2 shows `verified:null`, `verificationPerformed:false`, and explicit `clearMethod:"Shortcut"` (`L99,L147`). Hidden behavior is now visible in the results. The agent does not exercise `type -Verify` or default TextPattern-based clearing here, so this run does not validate those paths.
6. **Reporting is smaller despite more recorded actions.** The successful CLI2 tool output is 18,829 characters, versus 38,512 previously. It contains 35 command summaries, rather than the older 24 embedded full command responses. The execution-specific transcript is referenced separately (`L296`).

Several previous fixes are simply untested here: the launch `-Arguments` collision, `-KillExisting` normalization, invalid-regex handling, and nested-selector defaults. Absence of those failures is not evidence of a measured benefit from those particular changes.

## Highest-priority new finding: invalid geometry breaks discovery

CLI2 `observe` fails with:

> Cannot convert value "∞" to type "System.Int32".

The same failure occurs when selecting Edit controls (`cli2:L67,L141`). The agent interprets this as an application UIA limitation and abandons broad discovery, moving to screenshots, assumed focus, and shortcut-based dialog confirmation (`L71,L145–155`).

The local CLI's `ConvertTo-PotatoRectangle` unconditionally rounds and casts X/Y/Width/Height to Int32. `ConvertTo-PotatoElementInfo` calls it while serializing every selected element. An empty rectangle can contain infinite coordinates; one such element therefore destroys an otherwise useful query result.

**Confirmed locally:** passing `[Windows.Rect]::Empty` to the current converter reproduces the exception under Windows PowerShell 5.1. This is a generic CLI serialization failure, not proof that the application failed to expose its filename field.

Recommended fix:

- Preserve element identity/patterns even when bounds are absent or invalid. Return `bounds:null` with a reason, rather than failing the entire query.
- Validate empty, NaN, infinite, out-of-range, and zero-area rectangles; never silently substitute `(0,0)`.
- Require usable geometry for physical clicks, drags, and region captures. UIA read/Invoke operations should not require coordinates when their patterns are available.
- Isolate per-element property/serialization errors so one stale or offscreen element does not erase siblings.
- Add generic fixtures for empty/stale/hidden controls and disappearing dialogs.

This is a priority over more fallback prose: discovery must work before the agent can learn a compliant visible-control route.

## The remaining compliance problem is in both variants

### CLI2: shortcuts remain the default escape route

The final script records seven `hotkey` commands: Ctrl+S, Ctrl+W, Ctrl+O, Ctrl+P, and three Enter confirmations. It also uses three `type -PreDelete -ClearMethod Shortcut` operations, which perform Ctrl+A (`cli2:L257,L296`). The agent chooses Save/Print shortcuts before demonstrating that their visible navigation is unavailable (`L102–103`). Later failures provide reasons for some dialog fallbacks, but not blanket justification for all shortcuts.

The framework's rule that user prohibitions override fallbacks is necessary but insufficient: this framework prompt did not contain the native prompt's explicit prohibitions, and the framework still permits convenience fallbacks. The run also reads the shortcut-heavy Paint example before reading AGENTS (`L24` versus `L35`), despite the newer guidance favoring the template and targeted help.

Recommended general fix: make the interaction policy an explicit run input and record its resolved value. For a visible-controls-only evaluation, enforce it in both exploration and generated execution; classify application shortcuts, clipboard use, text entry, text selection, and dialog submission distinctly. Require any permitted fallback to identify its step, reason, and evidence. Examples should conform to the selected policy. Report functional success and policy compliance separately.

Do not forbid ordinary keyboard text entry merely because SendKeys implements it. The requirement concerns which application route is exercised, not whether the implementation uses a keyboard API at all.

### Native2: two false print passes, and a surviving false-pass path

Native2 logs a print timeout as `WARN`, then marks the testcase's print step `PASS` in two runs (`native2:L368,L396`). Its `Print-TestDocument` catches any exception in the PDF-dialog/output sequence and returns true anyway (`L57`). The final print-button targeting patch changes the selected button but does **not** remove this catch-and-pass behavior (`L407`).

The final log contains five PASS rows and no print warning (`L423`). That supports a better final observed outcome, but the generated script can still report success when the print operation fails on a later run. A clean final screenshot does not repair that latent behavior.

Native2 also opens the saved file through process/file association and accepts a reopened title matching `WordGuiTestDocument|Word`, which does not distinguish the target document from an arbitrary Word window (`L57`). Its stronger original prompt therefore does not make it an automatically trustworthy compliance baseline.

**Evaluation rule:** required output unavailable or unverified must fail or remain explicitly incomplete; warnings are not a substitute for the required assertion. Evaluate the final script's failure behavior as well as the last successful trace.

### CLI2: failed test results still exit successfully

The first generated run reports `ok:false`, three passed steps, and two failed steps, but its shell exit code is zero (`cli2:L272`). The current shared completion function writes the result JSON without assigning a failing process status. This is an integration gap, not a false PASS inside the JSON: the logged agent notices the failures, but a CI runner checking only the process status could accept the run.

Have the generated script's entry point emit the complete result and then map the aggregate outcome to a documented nonzero failure status. Keep a reusable completion helper from unexpectedly exiting its caller. Test that assertion, coverage, and cleanup failures all propagate consistently through both JSON and exit status.

## Native2 exposes another reusable-helper defect

Its generic `Find-Element` checks `$PSBoundParameters.ContainsKey("ControlType")` inside the predicate scriptblock passed to `Wait-Until` (`native2:L57`). Inside that scriptblock, the automatic variable does not contain the enclosing function's bound `ControlType` parameter. Consequently, calls that appear to constrain control type can silently lose that filter.

**Confirmed in an isolated PowerShell 5.1 reproduction:** the outer function sees the parameter; the invoked predicate does not. Capture the presence/value before entering the callback, or pass an explicit selector object. This is a plausible contributor to duplicate-label misselection; it does not explain every native failure, which also includes broken mouse input and dialog scoping.

Other avoidable native authoring failures reinforce the value of shared, tested primitives:

- A permissive title fallback can match the automation host rather than the app (`L170–171`).
- An optional-dialog dismissor matches the main application and clicks Close (`L205–206`).
- Treating a launcher exiting with code zero as an application failure breaks process handoff (`L139–145`).
- SendInput size/marshalling fails (`L213–219`), followed by repeated retries before replacing the mouse primitive (`L298`).
- A top-level-only dialog search misses an existing dialog (`L319–320`).
- Filename entry acts on the wrong field and saves to an unintended location (`L332–353`).

The appropriate CLI abstractions are process/window identity, owned-modal scoping, explicit selectors, tested input, and checked focus—not stored selectors or click coordinates from this application.

## Verification of open files needs a shared helper

CLI2's first generated run fails its saved-file prefix check because `[IO.File]::OpenRead` conflicts with the application's open writer (`cli2:L272`). Its patch changes the reader to `FileAccess.Read` with `FileShare.ReadWrite` (`L283`), and the next run passes.

An isolated file-stream reproduction confirms this sharing distinction. Provide a general read/assertion helper supporting explicit sharing, bounded retries, and a limited byte count. Run the stable-file wait first; sharing does not itself guarantee a finished artifact. Failure to read must remain failure or unverified state.

Also distinguish signatures from meaning: `PK` only identifies ZIP-like content, not a valid document with the expected text; `%PDF` only establishes a prefix. After reopening, reread the execution-specific content. Validate output structure/content to the degree the testcase requires, using generic read helpers and testcase-owned assertions.

## Selected values, focus, and environment assumptions

The agent initially guesses “Blank document” is a Button (10-second miss), then uses ListItem. It guesses Browse is a ListItem, then discovers Button. In the file dialog, “File name:” resolves to a Text label, and the old `1001` Edit selector has no match (`cli2:L72–91,L117–125,L132–137`). These are discovery issues, not reasons to embed fixed control identities in the framework.

With robust serialization, query a bounded candidate set by label/pattern and inspect role before imposing a guessed type. Scope queries to the owned dialog; verify the focused writable control before typing. A generic capability filter and focus guard would be more useful than application-specific selector hints.

The print patch replaces a failed printer-name query with a Print-button query (`L283`). It retains the PDF dialog and actual PDF checks, so it does **not** reduce printing to a click-only pass. However, it no longer confirms or selects the intended printer at runtime. Exploration's screenshot of the default printer becomes a hidden environment dependency.

Inspect selected Value/Selection state rather than assuming the selected value is the control's Name. Configure and verify the intended output target through the allowed route before submitting the action. Do not weaken the test merely because one property-based query fails.

The script also probes for any Document and skips creating a new one when present (`L257`). That can edit a pre-existing document. Track test-owned processes/documents and make startup/preconditions explicit; neither indiscriminate process killing nor blindly reusing an existing document is a robust reset.

## Concurrency and unknown outcomes are now observed failures

An Enter command times out after 24.1 seconds, yet a later window query shows the document opened (`cli2:L193,L200`). Observing before resending was the right response: a command timeout does not prove the input failed.

The agent then runs `windows` and `screenshot` concurrently, and the window-command output contains `Add-Content : Stream was not readable` while still returning `ok:true` (`L198–201`). Unlike the earlier review, there is now an actual logging exception in the supplied evidence. The overlap is consistent with contention, though the log alone does not establish every filesystem detail.

Make serialization a runtime property: one owner/lease for an interactive desktop, atomic state updates, and synchronized or independently written logs. Return structured diagnostics for log failures rather than successful JSON followed by unstructured errors. A mutex should have bounded acquisition and crash recovery; separate state files alone do not make concurrent GUI input safe.

Commands need an explicit “outcome unknown” state after a worker timeout and a follow-up postcondition check. Do not automatically retry a submission, typing, or toggle that may already have happened.

## Where the time is going—and where it is not yet explained

| CLI2 phase | Approximate elapsed |
|---|---:|
| Session start to app launch call | 0m53s |
| Launch to end of exploration/transition to authoring | 7m01s |
| Authoring and preflight before first run | 1m59s |
| First run call | 2m01s |
| Inspection, patch, and next launch gap | 0m39s |
| Final run call | 3m04s |
| Remaining final-response interval | 0m19s |

Phase boundaries use event timestamps and rounded shell wall times, so small gaps are not precision profiling. Exploration still accounts for much of the session: 40 direct CLI invocations, of which 39 return parseable command JSON and one times out. There are two geometry failures, two failed clicks, and two zero-match selections. No `help` command is used; the agent reads `commands.json` and whole source modules instead.

Source-reading calls before launch fall from 20 to 9, but the new CLI module read alone returns 40,092 characters and is truncated (`cli2:L42`); the runtime read returns 22,257 (`L30`). Read AGENTS first and expose a small authoring entry point with the contract, template, and targeted command help. Avoid using application examples as the default discovery path.

The last generated run's shell call is **183.5s**, compared with **77.7s** in the previous framework log and **88.7s** in native2's final shell call. These scripts perform different interactions/checks, so this is not a fair execution-speed ranking.

Inside CLI2's successful result:

- Test `startedAt` to `finishedAt`: **172.337s**.
- Sum of the 35 step-command `durationMs` fields: **84.507s**.
- Difference: **87.830s** not attributed by those fields.

That difference includes child-process/wrapper overhead, cleanup commands absent from step arrays, and other runtime work. It cannot all be called process-startup overhead. The first generated run has a smaller corresponding difference of 43.135s. The per-execution command JSONL files would be needed for a finer breakdown; only their paths and compact results are in the supplied session log.

Across direct exploration calls, median shell wall time minus CLI-reported time is **1.001s**, versus **0.687s** before. This includes wrapping and scheduling, not just PowerShell startup. Type calls for roughly 150-character paths take around 6–6.5s internally (`L147,L190`); benchmark equal text/fields before attributing that to the switch of input implementation or the VM.

Next instrumentation should expose total wrapper duration, backend duration, wait duration, and cleanup duration in compact summaries. Then evaluate a persistent worker or in-process backend. Batch only a sequence whose targets/postconditions are already known, and retain per-action evidence/errors. Do not batch away the GUI route or required checks to win the benchmark.

## Recommended next iteration

| Priority | Change | Application-independent acceptance test |
|---|---|---|
| P0 | Tolerant per-element UIA serialization | Empty/infinite/stale bounds do not erase a query; physical input refuses invalid geometry; UIA read/Invoke remains possible when valid. |
| P0 | Explicit, enforced interaction policy | The same strict policy applies to both benchmarks, exploration, examples, and generated execution; forbidden fallback cannot yield a compliant PASS. |
| P0 | Required assertions survive failure | An absent print/export artifact cannot become WARN+PASS; reopened content must match the execution marker where required. |
| P1 | Generated-script exit status agrees with results | A failed assertion, incomplete coverage, or required cleanup failure produces both `ok:false` and a nonzero process exit. |
| P1 | Shared artifact-read/assertion helper | An application-held file can be read when sharing permits; exclusive locks and invalid content remain failures. |
| P1 | Desktop lease and structured logging failure | Concurrent callers cannot interleave actions/corrupt logs; a timed-out action is reconciled before retry. |
| P1 | Ownership, modal scope, focus and selection state | No host-window matches, no main-window dismissal as a prompt, no edits to unrelated documents, no guessed focused filename field. |
| P1 | Complete timing and persistent-worker experiment | All execution time is attributable; the same actions/assertions run through both transports. |
| P2 | Small authoring entry point and checkpointed exploration | Agents stop reading whole modules/replaying known states; final behavioral validation is retained. |

## Artifacts and limitations

- [comparison-metrics.json](C:/diplomamunka/automated-gui-testing-agent-analysis/session-review/round2/comparison-metrics.json): reproducible measurements for all five sessions, source hashes, invocation lines, and command summaries.
- [Failed result](C:/diplomamunka/automated-gui-testing-agent-analysis/session-review/round2/cli2-result-L272.json) / [successful result](C:/diplomamunka/automated-gui-testing-agent-analysis/session-review/round2/cli2-result-L296.json): result objects extracted without changing their values from the session outputs, preserving the failed and successful runs.
- [reproduce_papercuts.ps1](C:/diplomamunka/automated-gui-testing-agent-analysis/session-review/round2/reproduce_papercuts.ps1) / [reproduction-results.json](C:/diplomamunka/automated-gui-testing-agent-analysis/session-review/round2/reproduction-results.json): isolated checks for invalid bounds, callback parameter scope, and file-sharing behavior. The checks ran on Windows PowerShell 5.1.22621.2506 and used no desktop actions.
- [analyze_logs.py](C:/diplomamunka/automated-gui-testing-agent-analysis/session-review/analyze_logs.py): updated to accept arbitrary file lists and discover generated script names from patch headers; no attached script or instruction is executed.

Source references use one-based original JSONL event lines. Screenshots described by the logged agent were not independently used here to certify output content. No new live application test or controlled speed benchmark was run. This turn changes analysis artifacts only; it does not change the CLI/framework implementation.

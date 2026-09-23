"""Read-only comparison of supplied Codex JSONL logs; never executes log content."""
import argparse
import collections
import datetime as dt
import hashlib
import json
import pathlib
import re
import statistics


def analyze(path):
    raw = path.read_bytes()
    events = [json.loads(line) for line in raw.decode('utf-8-sig').splitlines() if line.strip()]
    calls = {}
    outputs = []
    usage = None
    source_reads = []
    invocations = []
    for line, event in enumerate(events, 1):
        payload = event.get('payload', {})
        kind = payload.get('type')
        if event['type'] == 'event_msg' and kind == 'token_count' and payload.get('info'):
            usage = payload['info'].get('total_token_usage', usage)
        if event['type'] != 'response_item':
            continue
        if kind in ('function_call', 'custom_tool_call'):
            arguments = payload.get('arguments', payload.get('input', ''))
            try:
                arguments = json.loads(arguments)
            except (ValueError, TypeError):
                pass
            command = arguments.get('command', '') if isinstance(arguments, dict) else ''
            calls[payload['call_id']] = dict(line=line, tool=payload['name'], command=command)
            if re.search(r'Get-Content|\brg\b', command) and re.search(r'framework|PoTAToCli|potato\.ps1', command, re.I):
                source_reads.append(line)
            # These names identify artifacts in the study only, not CLI/framework behavior.
            if re.search(r'-File\s+[^\r\n;]*(Test-WordGui|Run-WordGuiTest|MicrosoftWord.Generated)\.ps1', command, re.I):
                invocations.append(line)
        elif kind in ('function_call_output', 'custom_tool_call_output'):
            output = payload.get('output', '')
            if not isinstance(output, str):
                continue
            call = calls.get(payload.get('call_id'), {})
            wall = re.search(r'Wall time: ([\d.]+) seconds', output)
            envelopes = []
            for text in output.splitlines():
                try:
                    value = json.loads(text)
                    if isinstance(value, dict) and 'ok' in value:
                        envelopes.append(value)
                except ValueError:
                    pass
            outputs.append(dict(line=line, call=call, wall_seconds=float(wall[1]) if wall else None,
                                output_chars=len(output), envelopes=envelopes))
    direct = []
    attempts = []
    for output in outputs:
        for envelope in output['envelopes']:
            item = dict(call_line=output['call'].get('line'), output_line=output['line'],
                        wall_seconds=output['wall_seconds'], ok=envelope['ok'])
            if 'command' in envelope and 'potato.ps1' in output['call'].get('command', ''):
                item.update(command=envelope['command'], duration_ms=envelope.get('durationMs'),
                            error=envelope.get('error'), count=(envelope.get('data') or {}).get('count'))
                direct.append(item)
            if 'steps' in envelope and output['call'].get('line') in invocations:
                item.update(summary=envelope.get('summary'), result_chars=output['output_chars'])
                attempts.append(item)
    overhead = [x['wall_seconds'] - x['duration_ms'] / 1000 for x in direct
                if x['wall_seconds'] is not None and x['duration_ms'] is not None]
    start = dt.datetime.fromisoformat(events[0]['timestamp'].replace('Z', '+00:00'))
    end = dt.datetime.fromisoformat(events[-1]['timestamp'].replace('Z', '+00:00'))
    return dict(file=path.name, sha256=hashlib.sha256(raw).hexdigest(), source_lines=len(events),
                elapsed_seconds=round((end - start).total_seconds(), 3),
                calls=dict(collections.Counter(c['tool'] for c in calls.values())),
                final_token_usage=usage,
                uncached_input_tokens=usage['input_tokens']-usage.get('cached_input_tokens', 0) if usage else None,
                script_invocation_lines=invocations, framework_or_cli_read_lines=source_reads,
                direct_cli_calls=direct, reported_generated_attempts=attempts,
                median_direct_cli_overhead_seconds=round(statistics.median(overhead), 3) if overhead else None,
                largest_tool_outputs=[dict(line=o['line'], chars=o['output_chars']) for o in sorted(outputs, key=lambda o: o['output_chars'], reverse=True)[:5]])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logs-dir', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path(__file__).with_name('metrics.json'))
    args = parser.parse_args()
    results = [analyze(args.logs_dir / name) for name in ('native.jsonl', 'native+cheating.jsonl', 'cli+framework.jsonl')]
    args.output.write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    for result in results:
        print(result['file'], result['elapsed_seconds'], result['calls'], 'script invocations:', len(result['script_invocation_lines']))

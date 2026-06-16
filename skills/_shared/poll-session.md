# Polling a session to completion (agent mode)

**Use this EXACT loop. Do NOT improvise your own poll/quoting.** A hand-written `case "$ST"` with
escaped quotes is the #1 cause of a stuck run: `case \"$ST\"` matches the literal string `"Completed`
(leading quote) against the pattern `Completed*`, which never matches, so the loop never breaks and
burns the full timeout (~1 hour) even though the session finished on the first poll.

`olympix sessions --agent` emits one JSONL line:
`{"event":"all_sessions","data":{"bug_pocer":[...],"unit_tests":[...],"mutation_tests":[...]}}`.
Each session object is `{"id":"<uuid>","title":...,"status":"<Status>","created_at":...,"error_message":...}`.

**Match on `id` (NOT `session_id`), read `status`.** Terminal statuses:

| Array key | Done | Failed |
|-----------|------|--------|
| `mutation_tests` | `Completed` | `Failed` |
| `unit_tests` | `Completed` | `Failed` |
| `bug_pocer` | `InitialScanCompleted` | `Killed` (not retrievable) |

## The loop — copy verbatim, set the two variables

```bash
SESSION_ID="<the session id you recorded>"
ARRAY_KEY="mutation_tests"   # one of: mutation_tests | unit_tests | bug_pocer

for i in $(seq 1 80); do
  ST=$(olympix sessions --agent 2>/dev/null | python3 -c '
import sys, json
sid, key = sys.argv[1], sys.argv[2]
status = "NotFound"
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except ValueError:
        continue
    arr = (obj.get("data") or {}).get(key) or []
    for s in arr:
        if s.get("id") == sid:
            status = s.get("status") or "Unknown"
print(status)
' "$SESSION_ID" "$ARRAY_KEY")

  echo "poll $i: $ST"

  # Plain string equality — NO case-globbing, NO escaped quotes.
  if [ "$ST" = "Completed" ] || [ "$ST" = "Failed" ] \
     || [ "$ST" = "InitialScanCompleted" ] || [ "$ST" = "Killed" ]; then
    break
  fi

  sleep 90
done

echo "final status: $ST"
```

## Notes

- Set `ARRAY_KEY` to the array for the tool you dispatched; the break list above already covers every
  terminal status, so the single loop works for all three tools.
- If `ST` stays `NotFound` across several polls, the session id is wrong or auth expired — re-run the
  `auth` skill and re-check the id; do not keep polling blindly.
- `Failed` / `Killed` are terminal — stop and read `error_message` (reconnect to retrieve it); do not
  treat them as "still running".
- The 90s cadence and `seq 1 80` bound are internal mechanics — never present them to the user as an
  ETA, and never call a long scan abnormal.

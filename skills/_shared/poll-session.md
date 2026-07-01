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

**Run this in the FOREGROUND with Bash `timeout: 600000`. It blocks ~7 min (gentle 90s
polls) and then prints `status: <X>`. If `<X>` is NOT one of the four terminal statuses
below, run this EXACT same call again.** Do NOT launch it with `run_in_background`, do NOT
add your own `sleep`s or log/liveness checks between calls, and do NOT narrate each poll —
one status line when it finally resolves is enough. Backgrounding the loop and then
re-reading the log every few seconds is the #1 cause of a subagent spinning and spamming
"still running": the loop below already does the waiting for you, so just block on it.

```bash
SESSION_ID="<the session id you recorded>"
ARRAY_KEY="mutation_tests"   # one of: mutation_tests | unit_tests | bug_pocer

ST=Unknown
for i in $(seq 1 6); do
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

  [ "$i" -lt 6 ] && sleep 90   # ~7 min window; no trailing sleep after the last poll
done

echo "status: $ST"   # terminal (Completed/Failed/InitialScanCompleted/Killed) -> proceed; else run this SAME call again
```

## Notes

- Set `ARRAY_KEY` to the array for the tool you dispatched; the break list above already covers every
  terminal status, so the single loop works for all three tools.
- **One call is one ~7-min window, not the whole wait.** A non-terminal `status:` line means the scan
  is still going — run the SAME call again. A scan can need many windows (sometimes an hour+); that is
  normal. Re-running the bounded FOREGROUND call keeps you blocked-and-waiting WITHOUT spinning.
  **Inside a dispatched subagent (e.g. from `full-run`) you MUST poll in the foreground:** a subagent
  that backgrounds the poll and yields is not reliably re-invoked when the background task finishes
  (unlike the main loop), so it returns early or spins re-reading the log. *Only* on the main
  interactive loop may you instead background this loop and STOP — you'll be re-invoked on completion —
  to keep the user's chat free; even then, never re-check it yourself between.
- If `ST` stays `NotFound` across several windows, the session id is wrong or auth expired — re-run the
  `auth` skill and re-check the id; do not keep polling blindly.
- `Failed` / `Killed` are terminal — stop and read `error_message` (reconnect to retrieve it); do not
  treat them as "still running".
- The 90s cadence and ~7-min window are internal mechanics — never present them to the user as an
  ETA, and never call a long scan abnormal.

# Waiting for an async result event (agent mode)

After you send a post-findings action (`generate_pdf`, `save_pocs`, `save_findings_md`,
`ask_question`), the CLI emits the result event **asynchronously** on its stdout — which you
redirected to `.opix-bp-events.log`. Wait for it with the bounded FOREGROUND loop below.

**Do NOT improvise a `grep` loop and do NOT wrap the wait in `run_in_background`.** A backgrounded
"wait for X" command that you then re-check every few seconds is exactly what produces the
"Background command failed" errors (and the spin-and-narrate behavior); and inside a dispatched
subagent a backgrounded wait is not reliably resumed, so it terminates early. Block on the foreground
call instead — it sleeps internally and returns a sentinel.

## 1. Send the action and mark where new events start (one Bash call)

```bash
wc -l < .opix-bp-events.log > .opix-bp-wait-base     # new events start after this line
# send through the FIFO via the same 5s write watchdog used for every action:
perl -e 'alarm 5; open(my $f,">",".opix-bp-in") or die "open failed: $!"; print $f "$ARGV[0]\n"' '{"action":"generate_pdf"}'
```

## 2. Wait for the result (FOREGROUND, Bash `timeout: 600000`)

```bash
LOG=.opix-bp-events.log
WANT='"event":"pdf_generated"'        # the SUCCESS event for the action you just sent
BASE=$(cat .opix-bp-wait-base 2>/dev/null || echo 0)
RESULT=WAIT_TIMEOUT
for i in $(seq 1 50); do                                # ~8 min, under the 10-min Bash ceiling
  NEW=$(tail -n +"$((BASE + 1))" "$LOG")                # only events since you sent the action
  case "$NEW" in
    *"$WANT"*)           RESULT=WAIT_DONE;  break ;;
    *'"event":"error"'*) RESULT=WAIT_ERROR; break ;;
  esac
  sleep 10
done
echo "$RESULT"
tail -n 5 "$LOG"
```

Set `WANT` to the success event for the action you sent:

| Action | `WANT` |
|--------|--------|
| `generate_pdf` | `"event":"pdf_generated"` |
| `save_pocs` | `"event":"pocs_saved"` |
| `save_findings_md` | `"event":"findings_saved"` |
| `ask_question` | `"event":"question_answered"` |

## Sentinel

- `WAIT_DONE` — the success event arrived; read it from the `tail` output and continue.
- `WAIT_ERROR` — the CLI emitted an `error` for this action; read the message from the `tail`, report
  it, and continue (do not blindly retry).
- `WAIT_TIMEOUT` — still working (PDF generation in particular is a heavy backend call). **Run the
  SAME step-2 call again** — do NOT resend the action, do NOT background it, do NOT swap in your own
  `grep`/`sleep`. Leave `.opix-bp-wait-base` untouched so the window still starts where you sent the
  action.

## Notes

- The match is a substring `case` against a quoted variable (literal), so it avoids the escaped-quote
  pitfall that breaks `case "$ST"` status matching — see `poll-session.md`.
- `seq 1 50 * sleep 10` ≈ 500s, comfortably under the 600s Bash ceiling. The per-iteration `tail` is
  cheap; do not lengthen the cadence to "be gentle" — there is no backend call in this loop.
- Never present the window or cadence to the user as an ETA, and never call a long export abnormal.

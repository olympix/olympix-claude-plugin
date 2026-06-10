---
name: bug-pocer
description: >
  Runs Olympix BugPocer security analysis fully automated via agent mode.
  Handles the entire flow: scope review, validation, security questions (incl. follow-ups),
  scan, findings retrieval with verdicts, Q&A, and built-in PDF + PoC export — all driven programmatically.
  TRIGGER: "bug pocer", "bugpocer", "security analysis", "run bug-pocer", "exploit generation", "bug-pocer"
tools: Read, Glob, Grep, Bash, Agent
---

# BugPocer Security Analysis

Run Olympix BugPocer on a Foundry-based Solidity repository fully automated via agent mode. The entire flow — scope review, validation items, security questions, scan, findings retrieval, and Q&A — is driven programmatically through JSONL.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `skills/_shared/forge-setup.md`.

### Step 2: Start BugPocer Session

The BugPocer flow is stateful and interactive via stdin/stdout JSONL. Use a Python subprocess to drive it:

```python
import subprocess, json, threading, queue

CMD = ["olympix", "bug-pocer", "-w", "<workspace-path>", "--agent"]

event_q = queue.Queue()

def reader_thread(proc):
    for line in proc.stdout:
        line = line.strip()
        if line:
            try:
                event_q.put(json.loads(line))
            except json.JSONDecodeError:
                pass

def send(proc, action, data=None):
    msg = {"action": action}
    if data:
        msg["data"] = data
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()

def read_event(timeout=300):
    try:
        return event_q.get(timeout=timeout)
    except queue.Empty:
        return None

proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, bufsize=1)
t = threading.Thread(target=reader_thread, args=(proc,), daemon=True)
t.start()
```

### Step 3: New Session Flow

The flow proceeds through these stages:

#### 3a. Sessions List
First event is `sessions_list` showing existing sessions.
```json
{"event":"sessions_list","data":{"sessions":[...]},"actions":["new_session","connect_session","disconnect"]}
```

Send `new_session` to start a new session, or `connect_session` with a session ID to reconnect.

#### 3b. Scope Review
```json
{"event":"scope_review","data":{"contracts":[...],"libraries":[...],"functions":[...]},"actions":["select_scope","confirm_all","disconnect"]}
```

Send `confirm_all` to include everything, or `select_scope` with exclusions:
```json
{"action":"select_scope","data":{"exclude_contracts":["ContractA"]}}
```

#### 3c. Validation Items
After scope confirmation, a `progress` event announces the session ID, then validation items arrive one at a time:
```json
{"event":"validation_item","data":{"key":"...","name":"...","confidence":70,"content":"...","current":1,"total":11},"actions":["confirm_item","reject_item","select_option","disconnect"]}
```

For each item, send `confirm_item` to accept or `reject_item` to reject.

#### 3d. Security Questions

**Do NOT blindly skip these.** They calibrate the scan. Answer each from the repo you already
read (contracts, roles, external integrations, upgradeability, economic assumptions).

After all validation items, security questions arrive one at a time:
```json
{"event":"security_question","data":{"question_id":"...","category":"AccessControl","question_text":"...","suggested_answers":[{"id":"a1","label":"...","value":"...","show_follow_up_ids":["f1"]}],"is_follow_up":false,"parent_question_id":null,"current":1,"total":13},"actions":["select_answer","custom_answer","skip_question","disconnect"]}
```

Deterministic answering rule, in order:
1. If a `suggested_answers` option matches what the code shows → `select_answer` with `{"answer_id":"<id>"}`.
2. Else if you know the answer from the code but no option fits → `custom_answer` with `{"answer":"<text>"}`.
3. Only `skip_question` when the repo genuinely does not determine it AND `is_required` is false.

**Follow-up questions (`is_follow_up: true`):** selecting an answer whose `show_follow_up_ids` is
non-empty causes the CLI to emit one or more follow-up `security_question` events (linked by
`parent_question_id`) BEFORE the next top-level question. Answer them the same way — same actions.
Do not treat a follow-up as the next top-level question; `current`/`total` reset to the follow-up batch.

#### 3e. Additional Documentation
```json
{"event":"additional_docs_prompt","actions":["submit_docs","skip_docs","disconnect"]}
```

Send `skip_docs` or `submit_docs` with notes/links:
```json
{"action":"submit_docs","data":{"notes":"Token uses rebasing","links":["https://docs.example.com"]}}
```

#### 3f. Submission
```json
{"event":"validation_submitted","data":{"session_id":"<uuid>"}}
```

CLI exits with code 0. The backend scan starts processing.

### Step 4: Wait for Scan Completion (non-blocking)

The scan runs **asynchronously** on the backend — there is nothing to wait on interactively. Once
`validation_submitted` arrives the CLI has already exited; do NOT hold a subprocess open waiting for
an answer. Poll session status until `InitialScanCompleted`:

```bash
olympix sessions --agent
```

Look for the session in `bug_pocer` array. Typical scan takes 5-15 minutes. Poll on an interval;
keep doing other work between polls rather than blocking.

### Step 5: Retrieve Findings

Reconnect to the completed session:

```python
CMD = ["olympix", "connect-bp-session", "-s", "<session-id>",
       "-w", "<workspace-path>", "--agent"]
```

Or via the `bug-pocer` command:
```bash
printf '{"action":"connect_session","data":{"session_id":"<id>"}}\n{"action":"disconnect"}\n' \
  | olympix bug-pocer -w <path> --agent
```

**Expected output:**
```
{"event":"progress","data":{"message":"Connected to session <id>. Fetching findings..."}}
{"event":"findings_ready","data":{"session_id":"<id>","findings":[...]},"actions":["ask_question","generate_pdf","save_pocs","disconnect"]}
```

Each finding carries:

| Field | Meaning |
|-------|---------|
| `id`, `title`, `severity`, `description`, `file_path`, `line_number` | finding basics |
| `affected_code` | the PoC/exploit code excerpt |
| `bugpocer_verdict` | BugPocer's automated call: `true_positive` / `false_positive` |
| `user_verdict` | the human reviewer's override: `true_positive` / `false_positive` / `unreviewed` |
| `user_verdict_reason` | text reason if a human set a verdict (else null) |
| `effective_verdict` | `user_verdict` if set, else `bugpocer_verdict` — use this as the final call |
| `confidence_score` | BugPocer confidence (int) |
| `poc_summary`, `poc_content` | PoC summary + full exploit source |

Findings auto-persist to `.opix/agent/<session-id>/findings.json`.

### Step 6: Q&A Loop (Optional)

After receiving findings, ask questions about them:

```json
{"action":"ask_question","data":{"question":"What is the most critical finding?"}}
```

Flow: `progress` "Question sent" → `qa_waiting` → `question_answered` with `answer` field.

Q&A exchanges auto-persist to `.opix/agent/<session-id>/qa.json`.

Send `disconnect` when done.

**Reporting verdicts (TP/FP):** answer from the verdict fields, and ALWAYS distinguish the two sources:
- "BugPocer verdict" = `bugpocer_verdict`.
- "User verdict" = `user_verdict` (`unreviewed` means no human has reviewed it yet).
- **Never answer "none" just because `user_verdict` is `unreviewed`.** If asked "what were the TP/FPs",
  report by `effective_verdict`, and state explicitly whether each is a human verdict or BugPocer's
  unreviewed call. Example: "3 TP / 2 FP per BugPocer (unreviewed); 0 reviewed by a user."

### Step 7: Export PDF report (built-in)

Use BugPocer's own PDF generator instead of hand-rolling one. After `findings_ready`, send:

```json
{"action":"generate_pdf"}
```

Wait for `{"event":"pdf_generated","data":{"session_id":"<id>","pdf_path":"<abs-path>"}}`.
On failure an `error` event is emitted; report it and continue. Move/copy the file into
`olympix-results/` if desired.

### Step 8: Export PoCs (built-in)

Export every finding's proof-of-concept to disk via the built-in exporter. Send:

```json
{"action":"save_pocs"}
```

Wait for `{"event":"pocs_saved","data":{"session_id":"<id>","saved_count":N,"output_path":"<dir>"}}`.
This writes one PoC file per finding (named by unit + vulnerability). Report the count and path.

### Step 9: Save Results

Also persist a human-readable summary to `olympix-results/bugpocer_pocs/`:

```markdown
# BugPocer Findings

**Session ID:** {id}
**Total Findings:** {count}

## [Severity] Finding Title

- **File:** {file_path}:{line_number}
- **Verdict:** {effective_verdict}  (BugPocer: {bugpocer_verdict} · User: {user_verdict})
- **Confidence:** {confidence_score}
- **Description:** {description}
- **PoC:** {poc_summary}

---
(repeat for each finding, ordered by severity)
```

### Step 10: Report to User

Tell the user:
- How many findings by severity AND by verdict (BugPocer vs user-reviewed)
- Highlight Critical and High findings with brief descriptions
- PDF saved at `pdf_path`; PoCs saved at `output_path`; summary in `olympix-results/bugpocer_pocs/`
- Offer to ask follow-up questions via Q&A

## Important Notes

- **Cost warning:** Each new BugPocer session triggers LLM calls on the backend. Avoid creating unnecessary sessions.
- **Cross-mode safety:** After agent-mode submission, `pending_validation_payload` is NULL in the database — no stale state for TUI mode.
- **Reconnecting:** Use `connect-bp-session -s <id>` or `bug-pocer` → `connect_session` action to reconnect to any existing session.
- **Killed sessions:** Reconnecting to a killed session returns `findings_ready` with an empty findings array (no hang).
- **PDF/PoC export are post-findings actions:** `generate_pdf` and `save_pocs` are only valid after a
  `findings_ready` event (i.e. on a completed session). They re-emit the same action set so you can chain them.
- **Verdicts are two independent fields:** `bugpocer_verdict` (automated) and `user_verdict` (human override,
  `unreviewed` until set). Always report both; collapse to `effective_verdict` only for a single final call.
- **Security questions are not optional noise:** answer them from the repo. Skipping degrades scan quality.

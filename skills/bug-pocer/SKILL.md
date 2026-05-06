---
name: bug-pocer
description: >
  Runs Olympix BugPocer security analysis fully automated via agent mode.
  Handles the entire flow: scope review, validation, security questions, scan,
  findings retrieval, and Q&A — all driven programmatically.
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
After all validation items, security questions arrive:
```json
{"event":"security_question","data":{"question_id":"...","question_text":"...","suggested_answers":[...],"current":1,"total":13},"actions":["select_answer","custom_answer","skip_question","disconnect"]}
```

For each question, send `skip_question`, `select_answer` with index, or `custom_answer` with text.

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

### Step 4: Wait for Scan Completion

Poll session status until `InitialScanCompleted`:

```bash
olympix sessions --agent
```

Look for the session in `bug_pocer` array. Typical scan takes 5-15 minutes.

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
{"event":"findings_ready","data":{"session_id":"<id>","findings":[...]},"actions":["ask_question","disconnect"]}
```

Each finding has: `id`, `title`, `severity`, `description`, `affected_code`, `file_path`, `line_number`.

Findings auto-persist to `.opix/agent/<session-id>/findings.json`.

### Step 6: Q&A Loop (Optional)

After receiving findings, ask questions about them:

```json
{"action":"ask_question","data":{"question":"What is the most critical finding?"}}
```

Flow: `progress` "Question sent" → `qa_waiting` → `question_answered` with `answer` field.

Q&A exchanges auto-persist to `.opix/agent/<session-id>/qa.json`.

Send `disconnect` when done.

### Step 7: Save Results

Parse findings and save to `olympix-results/bugpocer_pocs/`:

```markdown
# BugPocer Findings

**Session ID:** {id}
**Total Findings:** {count}

## [Severity] Finding Title

- **File:** {file_path}:{line_number}
- **Description:** {description}
- **Affected Code:** {affected_code}

---
(repeat for each finding, ordered by severity)
```

### Step 8: Report to User

Tell the user:
- How many findings by severity
- Highlight Critical and High findings with brief descriptions
- Results saved in `olympix-results/bugpocer_pocs/`
- Offer to ask follow-up questions via Q&A

## Important Notes

- **Cost warning:** Each new BugPocer session triggers LLM calls on the backend. Avoid creating unnecessary sessions.
- **Cross-mode safety:** After agent-mode submission, `pending_validation_payload` is NULL in the database — no stale state for TUI mode.
- **Reconnecting:** Use `connect-bp-session -s <id>` or `bug-pocer` → `connect_session` action to reconnect to any existing session.
- **Killed sessions:** Reconnecting to a killed session returns `findings_ready` with an empty findings array (no hang).

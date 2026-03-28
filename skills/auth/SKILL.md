---
name: auth
description: >
  Checks Olympix CLI authentication and automates login via Gmail MCP if needed.
  Reads the verification code from the user's Gmail inbox and pipes it to the
  login command. Use before any skill that requires the Olympix CLI.
  TRIGGER: "olympix login", "authenticate olympix", "not logged in", "session expired", "auth"
tools: Read, Bash
---

# Olympix Authentication

Check if the Olympix CLI is authenticated and automate login via Gmail if needed.

## Process

### Step 1: Check Current Auth

Check if a valid token exists:

```bash
cat ~/.opix/config.json 2>/dev/null | python3 -c "
import json, sys, time, base64
try:
    config = json.load(sys.stdin)
    token = config.get('sessionToken') or config.get('userToken')
    if not token:
        print('NO_TOKEN')
        sys.exit(0)
    # Decode JWT expiry (middle segment)
    payload = token.split('.')[1]
    payload += '=' * (4 - len(payload) % 4)
    exp = json.loads(base64.b64decode(payload)).get('exp', 0)
    if exp < time.time():
        print('EXPIRED')
    else:
        print('VALID')
except:
    print('NO_CONFIG')
"
```

**If VALID:** proceed. Authentication is current.

**If NO_CONFIG, NO_TOKEN, or EXPIRED:** go to Step 2.

### Step 2: Login

There are two paths depending on whether Gmail MCP is available:

---

**Path A — Manual login (no Gmail MCP or user preference):**

Tell the user:
> "Run `! olympix login -e your@email.com` to authenticate. You'll receive a verification code via email — enter it when prompted."

Wait for the user to confirm they're logged in, then verify with `olympix org-seats`.

---

**Path B — Automated login via Gmail MCP:**

**Requires:** Gmail MCP connection (`/mcp` connected to `claude.ai Gmail`)

#### 2a: Get User Email

Check the existing config or ask:
```bash
cat ~/.opix/config.json 2>/dev/null | python3 -c "
import json, sys
try:
    config = json.load(sys.stdin)
    token = config.get('sessionToken') or config.get('userToken', '')
    if token:
        payload = token.split('.')[1]
        payload += '=' * (4 - len(payload) % 4)
        import base64
        claims = json.loads(base64.b64decode(payload))
        print(claims.get('email', ''))
except:
    pass
"
```

If no email found, ask the user for their Olympix email.

#### 2b: Note the Current Time

Record the current timestamp BEFORE triggering login so we only look for codes sent AFTER this point:

```bash
date -u +"%Y/%m/%d %H:%M"
```

#### 2c: Trigger Login

Run the login command. It will send the verification email and wait for stdin:

```bash
olympix login -e {email}
```

**IMPORTANT:** This command blocks waiting for the code. Run it in the background or let it time out — the email gets sent immediately regardless.

Actually, the simplest approach: tell the user to run `! olympix login -e {email}` and then immediately check Gmail for the code.

#### 2d: Read Code from Gmail

Search for the verification email (sent after the timestamp from 2b):

```
Gmail search: from:no-reply@olympix.ai subject:"Your Olympix Login Code" after:{date}
```

The email snippet contains: `"Your Verification Code XXXXXX"` — extract the 6-character alphanumeric code.

Use the `gmail_read_message` tool to get the full body if the snippet is truncated.

#### 2e: Provide Code to User

Tell the user the code so they can enter it in the waiting login prompt:
> "Your Olympix verification code is: **XXXXXX** — enter it in the login prompt."

#### 2f: Verify Login

After the user enters the code:
```bash
olympix org-seats
```

If it shows seat info, authentication is complete.

## Gmail Search Patterns

| Purpose | Gmail Query |
|---------|------------|
| Login verification code | `from:no-reply@olympix.ai subject:"Your Olympix Login Code"` |
| Specific session result | `from:olympix {session_id}` |

**Always search by session ID** — it's a UUID, guaranteed unique across all runs. Never filter by date or subject to find results; that risks matching old sessions.

## Monitoring Results

To monitor for Olympix results after running skills, search Gmail for each session ID:

```
from:olympix {session_id}
```

Key fields in result emails:
- **Unit tests:** "X new tests generated across Y test contracts"
- **Mutation tests:** "Overall Score: X% (Y killed / Z mutants)"
- **Fuzz tests:** "Paths / Feasible Paths / Relevant Test Cases / Exploit Test Cases"

---
name: auth
description: >
  Checks Olympix CLI authentication status. If expired or missing, instructs
  the user to login interactively. Use before any skill that requires the Olympix CLI.
  TRIGGER: "olympix login", "authenticate olympix", "not logged in", "session expired", "auth"
tools: Read, Bash
---

# Olympix Authentication

Check if the Olympix CLI is authenticated. If not, instruct the user to login.

## Process

### Step 1: Check Current Auth

```bash
cat ~/.opix/config.json 2>/dev/null | python3 -c "
import json, sys, time, base64
try:
    config = json.load(sys.stdin)
    token = config.get('sessionToken') or config.get('userToken')
    if not token:
        print('NO_TOKEN')
        sys.exit(0)
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

Decision rule, in order:
1. **`VALID`** → authentication is current. Proceed (skip Steps 2-3).
2. **`NO_CONFIG`, `NO_TOKEN`, or `EXPIRED`** → go to Step 2.

### Step 2: Instruct User to Login

Tell the user:

> Run `! olympix login -e your@email.com` to authenticate. You'll receive a verification code via email — enter it when prompted.

Wait for the user to confirm they're logged in.

### Step 3: Verify Login

After the user confirms:

```bash
olympix org-seats
```

Decision rule:
- **Seat info is shown** → authentication is complete. Proceed.
- **Command errors or shows no seats** → login did not take. Ask the user to re-run `! olympix login -e your@email.com` and re-run this step. **HARD STOP** if it cannot be made to succeed — downstream skills require auth.

## Important Notes

- This skill is **interactive-only** — it never automates the login or reads the verification code. The user enters the code at the `olympix login` prompt.
- Token expiry is read from the JWT `exp` claim in `~/.opix/config.json`; a missing or malformed config is treated as unauthenticated.

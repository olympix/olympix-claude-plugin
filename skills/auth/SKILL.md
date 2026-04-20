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

## Step 1: Check Current Auth

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

**If VALID:** Authentication is current. Proceed.

**If NO_CONFIG, NO_TOKEN, or EXPIRED:** Go to Step 2.

## Step 2: Instruct User to Login

Tell the user:

> Run `! olympix login -e your@email.com` to authenticate. You'll receive a verification code via email — enter it when prompted.

Wait for the user to confirm they're logged in.

## Step 3: Verify Login

After the user confirms:

```bash
olympix org-seats
```

If it shows seat info, authentication is complete.

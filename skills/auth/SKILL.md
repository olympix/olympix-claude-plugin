---
name: auth
description: >
  Use when the user wants Olympix CLI authentication checked, or before any skill
  that requires the Olympix CLI — verifies the session token (including refresh-token
  validity) and, if expired or missing, instructs the user to login interactively.
  TRIGGER: "olympix login", "authenticate olympix", "not logged in", "session expired", "auth"
allowed-tools: Bash
---

# Olympix Authentication

Check if the Olympix CLI is authenticated. If not, instruct the user to login.

## Process

### Step 0: Check CLI Installed

```bash
if command -v olympix >/dev/null 2>&1 || [ -x "$HOME/.opix/bin/olympix" ]; then echo INSTALLED; else echo NOT_INSTALLED; fi
```

If `NOT_INSTALLED`, **HARD STOP** — tell the user to install the Olympix CLI from https://olympix.github.io/installation/ and rerun. Do not interpret a missing config as "not logged in" when the CLI itself is absent.

### Step 1: Check Current Auth

```bash
cat ~/.opix/config.json 2>/dev/null | python3 -c "
import json, sys, time, base64, datetime
try:
    config = json.load(sys.stdin)
    token = config.get('sessionToken') or config.get('userToken')
    if not token:
        print('NO_TOKEN')
        sys.exit(0)
    payload = token.split('.')[1]
    payload += '=' * (-len(payload) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
    if claims.get('exp', 0) >= time.time():
        print('VALID')
        sys.exit(0)
    # exp passed — the CLI may still auto-refresh via the refresh token.
    # refreshExpiresAt is an ISO-8601 string OR a Unix-epoch-MILLISECONDS number
    # (VSCode-written configs) — handle both.
    ref_exp = config.get('refreshExpiresAt', '')
    try:
        if isinstance(ref_exp, (int, float)):
            ref_dt = datetime.datetime.fromtimestamp(ref_exp / 1000, datetime.timezone.utc)
        else:
            ref_dt = datetime.datetime.fromisoformat(ref_exp.replace('Z', '+00:00'))
        ok = bool(config.get('refreshToken')) and ref_dt > datetime.datetime.now(datetime.timezone.utc)
    except Exception:
        ok = False
    print('REFRESHABLE' if ok else 'EXPIRED')
except Exception:
    print('NO_CONFIG')
"
```

(JWTs use base64url encoding — `base64.urlsafe_b64decode` plus `'=' * (-len(payload) % 4)` padding; plain `b64decode` breaks on `-`/`_` characters.)

Decision rule, in order:
1. **`VALID`** → authentication is current. Proceed (skip Steps 2-3).
2. **`REFRESHABLE`** → the session JWT's `exp` has passed but `refreshToken`/`refreshExpiresAt` in `~/.opix/config.json` are still valid — the CLI auto-refreshes on the next call. Run the Step 3 verification; if it succeeds, proceed. If it errors, treat as `EXPIRED`. **Never report EXPIRED to the user while the refresh token is still valid and unverified.**
3. **`NO_CONFIG`, `NO_TOKEN`, or `EXPIRED`** → go to Step 2.

### Step 2: Instruct User to Login

Olympix login is **interactive**: it emails a verification code that must be typed at a live prompt. It **cannot** be run with the `!` prefix inside this Claude Code session — `!` runs the command non-interactively, so the "Enter code" prompt is never answered and login fails with `Field code is required`. **Never tell the user to run `! olympix login`.**

Instead, tell the user to log in **outside** this session — either option works:

- **Open a new terminal** (leave Claude Code running), run `olympix login`, and follow the prompts: enter your account email, then the verification code emailed to you.
- **Or quit Claude Code, run `olympix login` in your terminal, then reopen Claude Code** once logged in.

Do **not** suggest, guess, or fill in an email address. `olympix login` prompts for the email itself; the user types their own (or passes `-e <their-email>` if they prefer). Never substitute a placeholder like `your@email.com` with a guessed address.

Wait for the user to confirm they're logged in.

### Step 3: Verify Login

After the user confirms:

```bash
olympix org-seats
```

Decision rule:
- **Seat info is shown** → authentication is complete. Proceed.
- **Command errors or shows no seats** → login did not take. Ask the user to re-run `olympix login` in a separate terminal (not via `!`, no guessed email) and re-run this step. **HARD STOP** if it cannot be made to succeed — downstream skills require auth.

## Important Notes

- This skill is **interactive-only** — it never automates the login or reads the verification code. The user runs `olympix login` themselves in a real terminal (a new terminal alongside Claude Code, or after reopening it) and enters the emailed code at the prompt.
- **Never** run or suggest `! olympix login`; the `!` prefix runs non-interactively and the code prompt fails with `Field code is required`.
- **Never** guess or fill in the user's email — `olympix login` prompts for it.
- Token expiry is read from the JWT `exp` claim in `~/.opix/config.json`; a missing or malformed config is treated as unauthenticated.
- An expired access token is NOT the same as being logged out: while `refreshToken`/`refreshExpiresAt` are valid, the CLI refreshes the session automatically on the next command.

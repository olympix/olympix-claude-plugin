# Environment files for backend runs

Use this guidance when the user requests an environment file or a run needs RPC URLs/API keys for fork testing. Supported launch commands: `generate-mutation-tests`, `generate-unit-tests`, and `bug-pocer` (full-repo or diff, automated or strict review).

- `--include-dot-env` / `-env` opts in to sending the workspace's `.env` with the uploaded scan inputs. It is off by default. The short form has **one dash**; `--env` is not a registered flag.
- `--env-file <path>` selects a custom file and **requires `--include-dot-env`** (or `-env`); passing the path alone does not enable upload. Relative paths resolve from the `-w` workspace. Quote paths containing spaces.
- These flags send file contents to the Olympix backend; they do not just load environment variables into the local shell. If the user has requested this upload, proceed without asking again. Do not include an environment file merely because one exists; when upload is needed but was not requested, explain its purpose and ask the user to choose the file to send.
- Check that the chosen file exists before launch; the CLI may otherwise send empty environment content. Do not silently substitute another file. Keep secret values out of chat, logs, reports, and git; pass the file path, not its contents, in commands and agent handoffs.

Append the flags to the initial launch/dispatch command, preserving all existing path, timeout, diff, and strict-mode options. For the default `.env`, append only `--include-dot-env`. For a custom file:

```bash
# Mutation/unit dispatch: keep the skill's new_session/disconnect JSONL pipe.
olympix generate-mutation-tests -w . -p src/Vault.sol --timeout 3600 --agent --include-dot-env --env-file .env.testing
olympix generate-unit-tests -w . -p src/Vault.sol --agent --include-dot-env --env-file .env.testing

# BugPocer: keep the skill's FIFO driver. This example combines diff + strict review.
olympix bug-pocer -w . --agent --diff-base main --rebuild-context --include-dot-env --env-file .env.testing < .opix-bp-in > .opix-bp-events.log 2>&1
```

For `full-run`, preserve whether upload was requested, the chosen file path, and which tools it applies to. Pass those choices to each applicable tool agent, or to the main agent driving strict BugPocer setup. Do not add these flags to static analysis, fuzz testing, polling, or results-retrieval commands. Reconnecting to an existing session does not replace its uploaded environment file.

# Strict validation review

Enable this workflow when the user requests strict mode or asks to validate answers with them before submission. Strict means **human approval**, not merely checking the answer against source code. It applies to this run until the user explicitly changes it; confidence, prior runs, silence, and time pressure do not waive it. This preference adds no CLI flag or JSON field.

## Keep the user in the loop

The main interactive agent owns scope, validation, security questions, and final submission. A background CLI process/FIFO is fine; an autonomous background agent that cannot ask the user is not. For `full-run`, launch the other tools in the background first, then drive BugPocer setup in the main conversation. After approved submission, polling and retrieval can run in the background.

If a background agent receives a strict-mode request, return control to the interactive caller with the session ID, current event, and proposed answer **without sending that answer**. If no interactive caller is available, stop before launching or disconnect without submitting and report that user review is required. Never fall back to automatic answers or skips.

## Prevent cached answers from bypassing review

For a new strict run, append `--rebuild-context` to the launch command (with either full or diff scope). Do not send `reuse_context`, `update_context`, or `clone_session` to bypass validation; if `context_cache_review` still appears, choose `rebuild_context`. Previously validated context is not approval for this run.

If strict mode is requested midway through setup, gate every remaining answer immediately. Show the user which answers were already sent; never describe them as reviewed. If any were unapproved, do not submit that session: explain that a fresh session with rebuilt context is needed to review every answer before sending it, and obtain the user's go-ahead to restart. An already submitted scan cannot be retroactively reviewed or paused by this mode; do not kill it unless asked.

## Review each pending event

For each `validation_item` and `security_question`, including `is_follow_up: true`:

1. Read relevant code and documentation. Show the item/question, its key or ID, the proposed decision or exact answer, a short rationale with source references, and any uncertainty. For a suggested option, show its label and value rather than only its opaque ID. For a validation item, include the content being accepted, rejected, or corrected.
2. Ask the user to approve, correct/select an alternative, or stop, using `AskUserQuestion`. Wait for an explicit response. A direct user selection/correction is approval for that exact answer; it needs no redundant confirmation. Ambiguous responses still need clarification. Approval applies only to the displayed item and answer, not future questions.
3. Re-read the latest CLI event before writing. Send only the approved action for that still-pending key/question ID (`confirm_item`, `reject_item`, `select_option`, `select_answer`, or `custom_answer`). A `skip_question` also needs explicit approval. If the proposed answer changes after approval, ask again. Never queue guesses for unseen questions or approve an entire validation stage with `confirm_all`.

Scope selection may still use `confirm_all` when it matches the user's chosen scope; that action is not blanket approval of validation answers. Do not pass a CLI auto-confirm option that would bypass this review.

## Approve final submission

At `additional_docs_prompt`, show a concise summary of the reviewed answers and the exact documentation choice (notes, links, paths, or none). Ask for explicit approval to submit validation and start the scan. Only after approval send `submit_docs` or `skip_docs`. `preview_docs` may be used first without submitting; disclose skipped/truncated documentation before asking for final approval.

If the user corrects an answer already sent, do not pretend it was updated: the protocol may not offer an edit. Explain and obtain agreement to restart setup with the correction before final submission. `validation_submitted` is the completion receipt, not an approval prompt.

## Timeouts and reconnects

The CLI has a 300-second stdin timeout; never answer automatically to beat it. Keep the FIFO holder alive while review is pending. If the same event is re-emitted, retain the pending review and send an approved answer only after verifying the session and item/question still match. Do not send it twice.

If the CLI exits or the session cannot resume, do not promise a reconnect will restore validation. Report the interruption and use a supported reconnect only if it exposes the pending review state; otherwise ask to restart with `--rebuild-context`. Never clone or reuse cached context to skip the approvals. Approval is not transferable to a changed question or a different session.

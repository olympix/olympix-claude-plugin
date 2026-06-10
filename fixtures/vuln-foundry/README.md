# vuln-foundry — isolated skill test fixture

Minimal, hermetic Foundry repo used by `scripts/run-skill-isolated.sh` to exercise the
plugin's skills without touching your live setup or real audit repos.

- `src/VulnerableVault.sol` — intentionally vulnerable (reentrancy + missing access control)
  so BugPocer / static analysis produce **deterministic** findings.
- No external deps → `forge build` is hermetic.

**DO NOT deploy.** This is test scaffolding only.

Run it:

```bash
scripts/run-skill-isolated.sh                    # interactive, fresh sandbox
scripts/run-skill-isolated.sh -- -p "/static-analysis"   # headless drive a skill
```

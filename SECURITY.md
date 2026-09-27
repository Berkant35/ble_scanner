# Security policy

BeneathSOS is safety-critical software. Please report vulnerabilities privately via
**GitHub → Security → Report a vulnerability** (private advisory). Do not open public issues for them.

## Repository protections
- `main` and `release/*`: pull requests only, CI (`checks`) must pass, 1 code-owner approval,
  approval must come after the last push, stale approvals dismissed, conversations resolved,
  linear history, no force push, no deletion, no bypass actors (`.github/rulesets/main.json`).
- **Auto-merge is disabled** in repository settings. Every merge is a deliberate human action.
- Workflows from forks require maintainer approval before running. Workflows use `pull_request`
  (never `pull_request_target`), read-only token permissions and SHA-pinned actions.
- Dependabot updates pub and GitHub Actions dependencies weekly; secret scanning and push
  protection are enabled.

## App principles
No network calls, no analytics, no account system in v1. All data stays on the device until the user
explicitly exports it.

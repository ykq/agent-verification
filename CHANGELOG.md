# Changelog

## Unreleased

- README walkthrough with a real run: demo dashboard under `docs/demo/`, committed receipts and screenshots under `docs/example/`, covering a caught `clipped_content` defect, the fix, attestation, and stale-attestation detection.
- CI: `GITHUB_TOKEN` restricted to `contents: read`.
- Default branch renamed `master` → `main`.
- Pre-release audit (Luna) docs fixes: Node.js 20+ stated everywhere (the locked Playwright requires it); CI uses `npm ci`; `--help` documents `--tab`, the environment variables, and the out-dir cleanup; SKILL.md states that a `fail` attestation is final for its run; the example run-2 receipt carries an appended correction (summary renders in 8 lines, not 7) and the README shows it.

## 0.1.0

- Receipt schema 3: every artifact carries its sha256; attestations are bound to digest + run_id; `check` detects tampered or regenerated screenshots, rejects forged/empty receipts, and reports every failing gate.
- Fixes from the pre-release cross-model audit (Codex gpt-5.6 + Claude): lazy images no longer hang past `--timeout-ms`; `state_unchanged` compares before/after each click and is disabled on self-mutating pages; redaction covers `Bearer`, `client_secret`-style keys, `user:pass@`, token prefixes, and URL path segments; `[role=tab]` outranks same-text links; clipping scans `<body>` when no `<main>` exists; value flags no longer swallow the next flag; duplicate viewport/tab names are rejected; stale PNGs are cleared from a reused out-dir.

- Initial public release: `capture.mjs` evidence collector, `attest`/`check` fail-closed inspection gate, `--spec` hashing, fixture tests, CI, visual and transaction verification workflows.

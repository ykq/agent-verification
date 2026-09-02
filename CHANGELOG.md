# Changelog

## 0.2.0

First public release. Code changes in this release were implemented by Codex (gpt-5.6) from specs written by Claude, after two independent pre-release audits (`docs/reviews/`). Claude ran the suite and corrected two spec mistakes noted in the commit messages.

- Receipt schema 4: artifact paths are stored relative to the receipt and a top-level `out_dir` records where the run happened; `attest`/`check` resolve paths against the receipt's directory, so a copied or uploaded run directory can be checked elsewhere. Schema 3 receipts are still read. `--spec` is stored as typed.
- `check --require 'viewport:state,...'` declares the coverage that must be captured and attested (`*` wildcards on either side); missing pairs fail with `MISSING COVERAGE`. The requirement is written to the receipt, survives a re-capture into the same out-dir, and every later `check` enforces the union of everything ever required. A pair may pin the rendered size (`mobile@390x844:Overview`), and `check` prints `COVERAGE: <pair> -> <label>@<size>` for each satisfied pair so a mislabelled viewport is visible. On a read-only receipt the requirement is enforced in memory with a warning instead of a crash. It never relaxes the rule that every captured PNG needs its own attestation.
- URL path segments in diagnostics are redacted (only a plain first route word survives); URLs of any scheme inside console text are redacted the same way; `--keep-paths` opts out.
- `attest` takes a lock on the receipt and writes atomically; eight concurrent attestations are all retained. `check`'s coverage write uses the same path.
- `check` re-hashes accessibility snapshots and reports `TAMPERED EVIDENCE` when one changed.
- `attest` requires `--by`; `check` reports `INVALID ATTESTATION` for records with no inspector or a note under ten characters.
- `--out-dir` reuse is refused for a non-empty directory that holds no prior `receipt.json`; cleanup skips directories and non-matching files.
- `agents/openai.yaml`: `allow_implicit_invocation: false`.
- Docs: walkthrough regenerated under schema 4 with a coverage-narrowing step; review packets committed under `docs/reviews/`.

### Reviewer findings not acted on in 0.2.0, and why

- Reject notes that are byte-identical across screenshots (Opus, 676da6d). Not adopted: "Full page identical to viewport" is a legitimate note for a full-page PNG whose content fits the viewport, and it recurs by design. A second inspector, not a string rule, is the answer to lazy notes.
- Record the browser executable and version in the receipt, and prefer bundled Chromium over a system Chrome (Luna, 2dcc162). Deferred to 0.3: worth doing, but it changes CI's tested path and needs its own audit.
- Suppress `out_dir` from the receipt (Opus, 142c940). Deferred: documented under Security defaults instead; a flag is planned once there is a second reason to add one.
- Move the coverage requirement out of the receipt into a task-level policy file (Opus, 142c940). Not adopted for 0.2.0: the requirement now survives out-dir reuse and is documented as per-receipt; CI and harnesses should pass `--require` on every check, which the lab overlay of the author's own setup mandates.
- Make `check` non-mutating (Opus, 142c940). Not adopted: writing the requirement into the receipt is what makes it sticky evidence. `check` now degrades to an in-memory requirement with a warning when the receipt is read-only.

## 0.1.x (unreleased docs revisions)

- Second pre-release audit (Claude Opus, raw review in `docs/reviews/2026-09-02-opus/`): `agents/openai.yaml` no longer allows implicit invocation; SKILL.md says to run `attest` calls one at a time (interim mitigation for the lost-update finding); README states that receipts embed absolute paths; the fixed demo page is committed under `docs/demo/fixed/` and the walkthrough reproduce block covers both runs; `package-lock.json` regenerated for Node 20; review packets committed under `docs/reviews/` with a README, so the "audited before release" claim is checkable.
- Owner decisions on reviewer questions: `check` will accept a required viewport/state coverage list (0.2); URL path segments will be redacted in diagnostics (0.2); implicit invocation off; reviews published.
- README walkthrough with a real run: demo dashboard under `docs/demo/`, committed receipts and screenshots under `docs/example/`, covering a caught `clipped_content` defect, the fix, attestation, and stale-attestation detection.
- CI: `GITHUB_TOKEN` restricted to `contents: read`.
- Default branch renamed `master` → `main`.
- Pre-release audit docs fixes (reviewer "Luna", an independent agent on a different model family; raw review in `docs/reviews/2026-09-01-luna/`): Node.js 20+ stated everywhere (the locked Playwright requires it); CI uses `npm ci`; `--help` documents `--tab`, the environment variables, and the out-dir cleanup; SKILL.md states that a `fail` attestation is final for its run; the example run-2 receipt carries an appended correction (summary renders in 8 lines, not 7) and the README shows it.

## 0.1.0

- Receipt schema 3: every artifact carries its sha256; attestations are bound to digest + run_id; `check` detects tampered or regenerated screenshots, rejects forged/empty receipts, and reports every failing gate.
- Fixes from the pre-release cross-model audit (Codex gpt-5.6 + Claude): lazy images no longer hang past `--timeout-ms`; `state_unchanged` compares before/after each click and is disabled on self-mutating pages; redaction covers `Bearer`, `client_secret`-style keys, `user:pass@`, token prefixes, and URL path segments; `[role=tab]` outranks same-text links; clipping scans `<body>` when no `<main>` exists; value flags no longer swallow the next flag; duplicate viewport/tab names are rejected; stale PNGs are cleared from a reused out-dir.

- Initial release, private: `capture.mjs` evidence collector, `attest`/`check` fail-closed inspection gate, `--spec` hashing, fixture tests, CI, visual and transaction verification workflows.

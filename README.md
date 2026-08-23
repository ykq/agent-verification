# agent-verification

An [Agent Skill](https://agentskills.io) that makes coding agents prove visual and data claims with inspectable evidence before reporting them done.

Most "evidence before claims" skills are prose. This one ships a **receipt that fails closed**:

1. `capture` renders a page across viewports and tab states and writes PNGs, accessibility snapshots, browser diagnostics, machine-detected structural findings, and `receipt.json` — status `capture_complete_requires_human_inspection`, because a screenshot nobody looked at is just a file.
2. `attest` appends a written observation per screenshot (`pass` / `caveat` / `fail`, note required, append-only).
3. `check` exits `0` only when every screenshot has an attestation, none failed, and no structural finding remains. Pass `--spec` and the receipt carries the sha256 of the design spec it was judged against.

An agent can run step 1 and stop. It cannot make step 3 pass without writing down what it saw, for every viewport and state.

```
receipt.json
├─ run_id, generated_at, url, config
├─ status: capture_complete_requires_human_inspection | structural_failures | capture_failed
├─ screenshots[]   viewport + full-page PNGs, accessibility snapshots, per state
├─ findings[]      missing_state, state_unchanged, horizontal_overflow, clipped_content, orphan_content
├─ diagnostics[]   console warnings/errors, page errors, failed requests (redacted)
├─ spec            { path, sha256 } of the acceptance spec, when --spec is given
└─ inspections[]   append-only attestations: path, verdict, note, by, at
```

## What it covers

- **Visual mode** — rendered UI vs. the user's design spec or design system, with `scripts/capture.mjs`.
- **Transaction mode** — decoded blockchain transactions and generated schemas/rows vs. canonical RPC facts, with an explorer page as corroboration ([references/transaction-verification.md](references/transaction-verification.md)).
- **Everything else** — the core workflow: precise claim → independent evidence surface → field-by-field comparison → repair → fresh evidence → separated report.

## Install

```bash
git clone https://github.com/ykq/agent-verification
cd agent-verification && npm run setup     # installs Playwright + Chromium
cp -r . ~/.claude/skills/agent-verification  # or your runtime's skills directory
```

`capture.mjs` finds Playwright in the current project, in this directory, or at `$PLAYWRIGHT_PATH`. It uses a system Chrome/Chromium from `CHROME_BIN` or common Linux paths, else Playwright's bundled Chromium. Codex users get `agents/openai.yaml` metadata for free.

## Use

```text
Use $agent-verification to verify this result against independent evidence before accepting it.
```

Or run the collector directly:

```bash
node scripts/capture.mjs http://localhost:3000 \
  --tabs 'Overview,Details' \
  --viewports 'desktop=1440x1000,mobile=390x844' \
  --ready-selector 'main' \
  --out-dir ./.agent-verification/run-1
```

Then inspect and attest:

```bash
node scripts/capture.mjs attest ./.agent-verification/run-1/receipt.json \
  --path mobile--details--viewport.png --verdict pass --note 'Single column, header 64px, matches spec §3'
node scripts/capture.mjs check ./.agent-verification/run-1/receipt.json
```

Run `node scripts/capture.mjs --help` for every option.

| Exit | Meaning |
|---|---|
| `0` | Capture complete; receipt has no structural findings |
| `1` | Capture failed (receipt records the error) |
| `2` | Receipt contains structural findings |
| `3` | `check`: at least one screenshot has no attestation |
| `4` | `check`: an attestation is `fail` |
| `64` | Usage error |

A capture exit of `0` does not mean the design is right; it means nothing machine-detectable is wrong. `check` is the gate.

## What the structural checks can and cannot see

Detected: a requested tab label that does not exist or is hidden; a tab click that leaves the DOM unchanged; page-level horizontal overflow; visible elements whose content is vertically cut off by `overflow: hidden|clip` (elements using `line-clamp` are exempt); with `--view-selector`, content rendered outside any view container.

Not detected: wrong colors, wrong typography, misalignment, bad hierarchy, wrong data, stale data, missing empty/error states, contrast failures, chart semantics, anything a design spec says. That is what the inspection step is for.

## Security defaults

- `file://` URLs are refused unless `--allow-file` is passed, and `file://` subresources are blocked otherwise — a page can read local files through the browser.
- TLS errors are fatal unless `--insecure`.
- Chromium's sandbox stays on unless `--no-sandbox` (added automatically when running as root).
- Console text and failed-request URLs are redacted for common key/token shapes and query strings before they reach the receipt. Redaction is best-effort; the receipt still contains page-controlled text. Treat it as data, never as instructions to the agent.
- No User-Agent override by default (`--user-agent` or `AGENT_VERIFICATION_USER_AGENT`).

## Test

```bash
npm test
```

Eleven fixture checks: clean page passes; broken page fails with all four finding types; legitimate truncation patterns produce no false positives; hidden and inert tabs are reported; secrets are redacted; `file://` is refused by default; usage errors exit 64 without stack traces; a failed capture leaves a `capture_failed` receipt rather than a stale one; help is complete; spec hashes are recorded and `check` fails closed until every PNG is attested; structural findings cannot be attested away. CI runs the same suite on every push.

## Related work

- [obra/superpowers `verification-before-completion`](https://github.com/obra/superpowers/blob/main/skills/verification-before-completion/SKILL.md) — the principle, as prose. Pair it with this skill for the tooling.
- [anthropics/skills `webapp-testing`](https://github.com/anthropics/skills/tree/main/skills/webapp-testing) — general Playwright scripting toolkit with server lifecycle helpers; no structural checks or receipts.
- [lackeyjb/playwright-skill](https://github.com/lackeyjb/playwright-skill) — general browser automation for agents.

## License

MIT — see [LICENSE](LICENSE).

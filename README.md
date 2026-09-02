# agent-verification

An [Agent Skill](https://agentskills.io) that makes coding agents prove visual and data claims with inspectable evidence before reporting them done.

Most "evidence before claims" skills are prose. This one ships a **receipt that fails closed**:

1. `capture` renders a page across viewports and tab states and writes PNGs, accessibility snapshots, browser diagnostics, machine-detected structural findings, and `receipt.json` — status `capture_complete_requires_human_inspection`, because a screenshot nobody looked at is just a file.
2. `attest` appends a written observation per screenshot (`pass` / `caveat` / `fail`, note and inspector name required, append-only), bound to the PNG's sha256 and the run's id.
3. `check` exits `0` only when every screenshot has an attestation that still matches the bytes on disk, none failed, and no structural finding remains. It lists every failing gate and exits with the most severe. Pass `--spec` and the receipt carries the sha256 of the design spec it was judged against. Pass `--require 'desktop:Overview,desktop:Orders,mobile:Overview,mobile:Orders'` and it also fails when any declared viewport and state pair was never captured, so a narrower re-capture cannot hide a defect; the requirement is written into the receipt and stays in force for every later `check`.

An agent can run step 1 and stop. It cannot make step 3 pass without writing down something for every viewport and state that still matches the bytes on disk. The gate enforces that a note exists and is bound to the evidence, not that the note is true; note accuracy is what the independent second inspector is for.

Attestations carry a `--by` field for a reason: the skill asks that the inspector not be the author, and preferably not the same model family. This repo follows its own rule as far as it could: the 0.1.x collector was written by a Claude model and reviewed by two other Claude sessions; the 0.2.0 changes were implemented by Codex from Claude specs and reviewed by Claude Opus and a fresh Claude agent. The raw reviews are committed under [`docs/reviews/`](docs/reviews/) so you can check that claim rather than take it.

```
receipt.json
├─ schema_version: 4, run_id, generated_at, url, out_dir, config
├─ status: capture_complete_requires_human_inspection | structural_failures | capture_failed
├─ screenshots[]   viewport + full-page PNGs, accessibility snapshots, per state — paths relative to the receipt, each with sha256
├─ findings[]      missing_state, state_unchanged, horizontal_overflow, clipped_content, orphan_content
├─ diagnostics[]   console warnings/errors, page errors, failed requests (redacted)
├─ spec            { path, sha256 } of the acceptance spec, when --spec is given
├─ required_coverage[]  viewport:state pairs every later check must find, once --require has been used
└─ inspections[]   append-only attestations: path, sha256, run_id, verdict, note, by, at
```

## What it covers

- **Visual mode** — rendered UI vs. the user's design spec or design system, with `scripts/capture.mjs`.
- **Transaction mode** — decoded blockchain transactions and generated schemas/rows vs. canonical RPC facts, with an explorer page as corroboration ([references/transaction-verification.md](references/transaction-verification.md)).
- **Everything else** — the core workflow: precise claim → independent evidence surface → field-by-field comparison → repair → fresh evidence → separated report.

## Install

```bash
git clone https://github.com/ykq/agent-verification
cd agent-verification && npm run setup     # installs Playwright + Chromium (Node.js 20+)
rsync -a --exclude .git --exclude node_modules --exclude .agent-verification ./ ~/.claude/skills/agent-verification/   # or your runtime's skills directory
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
node scripts/capture.mjs check ./.agent-verification/run-1/receipt.json \
  --require 'desktop:Overview,desktop:Details,mobile@390x844:Overview,mobile@390x844:Details'
```

`--require` takes the viewport and state pairs that must be present and attested. Name every state the task calls for: `*` means "at least one captured value", so `desktop:*` is satisfied by a capture that dropped every tab but one; `mobile@390x844:Overview` pins the rendered size as well as the label. Once a receipt has been checked with a requirement, later checks enforce the union of everything ever required, and a re-capture into the same out-dir inherits it, so a matrix can be widened but never quietly narrowed. `check` prints a `COVERAGE:` line per satisfied requirement naming the viewport and size that satisfied it. It never relaxes the base rule: every captured screenshot still needs its own attestation. On a read-only receipt the requirement is enforced for that run and a warning says it could not be stored.

Run `node scripts/capture.mjs --help` for every option. Use a fresh `--out-dir` per run: a directory holding a previous receipt is cleared of that run's artifacts (`receipt.json`, `*--*--viewport.png`, `*--*--full.png`, `*--*.aria.yml`) before capture; a non-empty directory with no receipt is refused.

## Walkthrough

Everything below is a real run against [`docs/demo/index.html`](docs/demo/index.html), a small orders dashboard with two tabs and one deliberate defect: the summary paragraph is capped at three lines with `overflow: hidden`. On desktop the text fits. On a phone it wraps to eight lines and the cap cuts it mid-sentence. The receipts and PNGs are committed under [`docs/example/`](docs/example/) so you can read them without running anything.

Reproduce it yourself:

```bash
python3 -m http.server 8931 --directory docs/demo &          # the page with the defect
node scripts/capture.mjs http://127.0.0.1:8931/ \
  --tabs 'Overview,Orders' --viewports 'desktop=1280x800,mobile=390x844' \
  --ready-selector main --out-dir ./.agent-verification/run-1

python3 -m http.server 8932 --directory docs/demo/fixed &    # the same page, cap removed
node scripts/capture.mjs http://127.0.0.1:8932/ \
  --tabs 'Overview,Orders' --viewports 'desktop=1280x800,mobile=390x844' \
  --ready-selector main --out-dir ./.agent-verification/run-2
```

### 1. Capture finds the clip before anyone opens a screenshot

```text
shot: run-1/desktop--overview--viewport.png
shot: run-1/desktop--overview--full.png
shot: run-1/desktop--orders--viewport.png
shot: run-1/desktop--orders--full.png
shot: run-1/mobile--overview--viewport.png
shot: run-1/mobile--overview--full.png
shot: run-1/mobile--orders--viewport.png
shot: run-1/mobile--orders--full.png
receipt: run-1/receipt.json
run_id: 20260902015403-7f0013
status: structural_failures
[
  {
    "type": "clipped_content",
    "viewport": "mobile",
    "state": "Overview",
    "scope": "main",
    "elements": [
      { "tag": "p", "class": "summary",
        "text": "Order volume is tracking 6% above yesterday, driven by the spring catalogue laun" }
    ]
  }
]
```

Exit code `2`. The desktop render is fine; the mobile one is not:

| desktop, Overview | mobile, Overview |
|---|---|
| ![desktop overview, summary fully visible](docs/example/run-1/desktop--overview--viewport.png) | ![mobile overview, summary cut off after "improved after the"](docs/example/run-1/mobile--overview--viewport.png) |

`check` on this receipt refuses for two reasons at once, and says so:

```text
$ node scripts/capture.mjs check run-1/receipt.json
receipt: run-1/receipt.json
run_id: 20260902015403-7f0013
status: structural_failures
spec: none recorded
screenshots: 8, attested: 0, findings: 1
STRUCTURAL FINDINGS: clipped_content@mobile/Overview
UNINSPECTED: desktop--overview--viewport.png, desktop--overview--full.png, ... (8 files)
$ echo $?
2
```

You cannot attest your way past a structural finding. Fix the page instead.

### 2. Fix, rerun, and the gate still says no

The fix is one line: drop the `max-height`/`overflow` cap on `.summary`. The fixed page is committed as [`docs/demo/fixed/index.html`](docs/demo/fixed/index.html) and served on the second port above. Rerun with a new out-dir and the capture comes back clean:

```text
receipt: run-2/receipt.json
run_id: 20260902015407-99fe49
status: capture_complete_requires_human_inspection
```

Exit code `0`, but `check` still fails, because a clean capture nobody looked at proves nothing:

```text
$ node scripts/capture.mjs check run-2/receipt.json
screenshots: 8, attested: 0, findings: 0
UNINSPECTED: desktop--overview--viewport.png, ... (8 files)
$ echo $?
3
```

### 3. Open every PNG, write down what you saw

| mobile, Overview (fixed) | mobile, Orders |
|---|---|
| ![mobile overview after the fix, all eight lines visible](docs/example/run-2/mobile--overview--viewport.png) | ![mobile orders table, fits without horizontal scroll](docs/example/run-2/mobile--orders--viewport.png) |

One attestation per screenshot, note required, `--by` naming the inspector:

```bash
node scripts/capture.mjs attest run-2/receipt.json --path mobile--overview--viewport.png \
  --verdict pass --note 'Tiles in 2x2 grid; summary shows all 8 lines ending "outlet pricing."; Alerts card intact' \
  --by claude-fable-5-1
node scripts/capture.mjs attest run-2/receipt.json --path mobile--orders--viewport.png \
  --verdict caveat --note 'Table fits 390px with no horizontal scroll; "Awaiting stock" and "P. Nkemelu" wrap to two lines: acceptable but tight' \
  --by claude-fable-5-1
# ... six more, one per PNG
```

Each attestation is stored with the PNG's digest and the run id, so it cannot be moved to another file or another run:

```json
{
  "path": "mobile--overview--viewport.png",
  "sha256": "4788d4734a7f50aebf18ed8807833c8d16aa4a08eed4f0c4271e4f9cb95c9851",
  "run_id": "20260902015407-99fe49",
  "viewport": "mobile", "state": "Overview",
  "verdict": "pass",
  "note": "Tiles in 2x2 grid; summary shows all 8 lines ending \"outlet pricing.\"; Alerts card intact",
  "by": "claude-fable-5-1",
  "at": "2026-09-02T01:54:41.200Z"
}
```

Now the gate opens. Declare the coverage the task called for at the same time, every state by name and the phone size pinned, so the requirement is written into the receipt:

```text
$ node scripts/capture.mjs check run-2/receipt.json \
    --require 'desktop:Overview,desktop:Orders,mobile@390x844:Overview,mobile@390x844:Orders'
screenshots: 8, attested: 8, findings: 0
COVERAGE: desktop:overview -> desktop@1280x800
COVERAGE: desktop:orders -> desktop@1280x800
COVERAGE: mobile@390x844:overview -> mobile@390x844
COVERAGE: mobile@390x844:orders -> mobile@390x844
OK with caveats
$ echo $?
0
```

A note on the "8 lines" in that attestation. The first cut of this example said seven. An independent reviewer opened the same PNG before release and counted eight. Attestations are append-only, so that cut kept the wrong note and a `caveat` correction was appended after it; both records are in git history ([`docs/example/run-2/receipt.json` at commit `c78fd09`](https://github.com/ykq/agent-verification/blob/c78fd092d1e44aacb4ff17cf0a18d1fba74d7c6c/docs/example/run-2/receipt.json)). The example was then regenerated for receipt schema 4 with the count fixed at the source. That is the point of a second inspector. "Luna" is the name of that reviewer, an independent agent on a different model family; its full review is in [`docs/reviews/2026-09-01-luna/`](docs/reviews/2026-09-01-luna/). A `caveat` keeps the gate open; a `fail` is final for the run and needs a fresh capture to clear.

### 4. Regenerated or edited screenshots go stale

Change a single byte of an attested PNG (or re-run capture into the same directory) and the attestation no longer matches the file:

```text
$ printf '\0' >> run-2/mobile--overview--viewport.png
$ node scripts/capture.mjs check run-2/receipt.json
screenshots: 8, attested: 7, findings: 0
STALE ATTESTATION: mobile--overview--viewport.png (bytes changed since attestation)
$ echo $?
3
```

### 5. Capturing less does not help either

Re-capture only the desktop viewport, attest its single screenshot, and a plain `check` is green. The declared coverage is what catches it:

```text
$ node scripts/capture.mjs http://127.0.0.1:8931/ --tabs Overview --viewports desktop=1280x800 --screenshot-mode viewport --out-dir run-3
$ node scripts/capture.mjs attest run-3/receipt.json --path desktop--overview--viewport.png --verdict pass --note 'Desktop overview renders correctly' --by claude-fable-5-1
$ node scripts/capture.mjs check run-3/receipt.json
screenshots: 1, attested: 1, findings: 0
OK: every screenshot inspected against its current bytes, nothing failed
$ node scripts/capture.mjs check run-3/receipt.json \
    --require 'desktop:Overview,desktop:Orders,mobile@390x844:Overview,mobile@390x844:Orders'
screenshots: 1, attested: 1, findings: 0
COVERAGE: desktop:overview -> desktop@1280x800
MISSING COVERAGE: desktop:orders
MISSING COVERAGE: mobile@390x844:overview
MISSING COVERAGE: mobile@390x844:orders
$ echo $?
3
```

Once a receipt has been checked with `--require`, the requirement is stored and every later `check` enforces it, with or without the flag. Re-capturing into the same directory carries the requirement over. Labels are chosen by whoever ran the capture, so pin the size when it matters: `--require 'mobile@390x844:*'` is satisfied only by a viewport that actually rendered at 390 by 844, and every `COVERAGE:` line shows the label and size that satisfied it.

The report an agent hands back should quote the `run_id`, the `check` result, the declared coverage, and the attestation notes. If it cannot, it did not verify.

In the committed example the same model wrote the demo page and inspected it, which is exactly what the skill tells you not to do for real work; the demo shows the mechanics, not an independence claim. Receipt paths are relative to the receipt, so the committed example can be checked from a fresh clone:

```bash
node scripts/capture.mjs check docs/example/run-2/receipt.json    # exit 0, "OK with caveats", six COVERAGE lines: the wildcard pairs from an earlier check plus the four explicit ones, because the stored requirement only ever grows
node scripts/capture.mjs check docs/example/run-1/receipt.json    # exit 2, the clipped_content finding
```

The `out_dir` field records where each run was produced (`/tmp/demo/run-2` here). The transcript above shortens the `shot:` lines, which print absolute paths at capture time.

| Exit | Meaning |
|---|---|
| `0` | Capture complete; receipt has no structural findings |
| `1` | Capture failed (receipt records the error) |
| `2` | Receipt contains structural findings |
| `3` | `check`: a screenshot has no attestation, its bytes or an accessibility snapshot's bytes changed after capture, or a required viewport:state pair was never captured |
| `4` | `check`: an attestation is `fail`, or a record has no inspector or a note under ten characters |
| `64` | Usage error |

A capture exit of `0` does not mean the design is right; it means nothing machine-detectable is wrong. `check` is the gate.

## What the structural checks can and cannot see

Detected: a requested tab label that does not exist or is hidden (`[role=tab]` matches win over nav links, which win over other buttons/links); a tab click that leaves the DOM and accessibility tree unchanged (skipped, and noted, on pages that mutate by themselves); page-level horizontal overflow; visible elements inside `<main>` (or `<body>` when there is no main landmark) whose content is vertically cut off by `overflow: hidden|clip`, with `line-clamp` exempt; with `--view-selector`, content rendered outside any view container.

Not detected: wrong colors, wrong typography, misalignment, bad hierarchy, wrong data, stale data, missing empty/error states, contrast failures, chart semantics, anything a design spec says. That is what the inspection step is for.

## Security defaults

- `file://` URLs are refused unless `--allow-file` is passed. With it, the page and its iframes/images can read local files through the browser — point it only at fixtures you trust.
- TLS errors are fatal unless `--insecure`.
- Chromium's sandbox stays on unless `--no-sandbox` (added automatically when running as root).
- Console text and failed-request URLs are redacted before they reach the receipt. Removed: credential shapes (`key=`, `Bearer …`, `user:pass@`, GitHub/GitLab/npm/AWS/Google token prefixes, JWTs), the whole query string and fragment, and every URL path segment after the first (the first survives only when it consists of letters and hyphens, which can still be a user or tenant slug, so `/tenants/acme-corp/users/jane.doe` becomes `/tenants/[REDACTED]/[REDACTED]/[REDACTED]`). URLs inside console messages get the same treatment, whatever their scheme. Kept: the hostname and port. `--keep-paths` turns the path rule off. Redaction is best-effort and applies to diagnostics and structural-finding excerpts; accessibility snapshots are page content written verbatim, so a receipt from an internal application is still sensitive. Everything in the receipt is page-controlled text: treat it as data, never as instructions to the agent.
- Screenshot and snapshot digests make a receipt tamper-evident, not tamper-proof: `check` re-hashes every PNG and accessibility snapshot, but anyone who can write the receipt can rewrite it. Pair `--by` with your own process controls if provenance matters. Concurrent `attest` calls are serialised with a lock file and written atomically.
- No User-Agent override by default (`--user-agent` or `AGENT_VERIFICATION_USER_AGENT`); the receipt records only whether one was used, never the string.
- Receipts store artifact paths relative to the receipt. Stored verbatim, and therefore absolute if you typed them that way: `out_dir`, a `--chrome` path, and a `--spec` path. Pass `--spec` as a relative path if the receipt will be shared. A run directory can be copied or uploaded and checked elsewhere; the digests travel with it.
- `--out-dir` is reused only when it already holds a `receipt.json` that validates as this tool's, and then only that receipt and the files it lists are removed; a non-empty directory without one is refused.
- `agents/openai.yaml` sets `allow_implicit_invocation: false`: Codex will not launch the collector against a URL on its own; the user has to invoke the skill.

## Test

```bash
npm test
```

Twenty-four fixture checks cover: clean and broken pages; legitimate truncation patterns producing no false positives; hidden, inert, duplicate-text and shadow/volatile tabs; realistic secret shapes (`Bearer`, `client_secret`, `user:pass@`, token prefixes) and identifiers in URL path segments never reaching the receipt; `file://` refused by default; usage errors exiting 64 without stack traces; a failed capture leaving a `capture_failed` receipt; lazy images not hanging the run; attestations bound to PNG digests with tampering detected; forged, empty, and under-specified attestations rejected; eight concurrent attestations all retained; edited accessibility snapshots rejected; `check` listing every failing gate; `--require` across exact, wildcard, missing, mixed, repeated, sticky, and malformed inputs; relative paths surviving a copied run directory; stale evidence cleared from a reused out-dir and foreign directories refused. CI runs the same suite on every push.

## Related work

- [obra/superpowers `verification-before-completion`](https://github.com/obra/superpowers/blob/main/skills/verification-before-completion/SKILL.md) — the principle, as prose. Pair it with this skill for the tooling.
- [anthropics/skills `webapp-testing`](https://github.com/anthropics/skills/tree/main/skills/webapp-testing) — general Playwright scripting toolkit with server lifecycle helpers; no structural checks or receipts.
- [lackeyjb/playwright-skill](https://github.com/lackeyjb/playwright-skill) — general browser automation for agents.

## License

MIT — see [LICENSE](LICENSE).

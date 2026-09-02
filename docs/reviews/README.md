# Pre-release adversarial reviews

The README claims the collector was written by one model and audited by others before release. This directory is the checkable part of that claim.

Each review was produced by an independent agent given only the frozen artifact, the review prompt, the release context, and the output schema. Reviewers were not shown each other's findings. Every reviewer had shell access to run the tests and the collector against the frozen tree, and each was told to verify by execution and to try to defeat the fail-closed gate.

| Directory | Reviewer | Model family | Commit reviewed | Artifact sha256 (`git archive` tar) | Verdict |
|---|---|---|---|---|---|
| `2026-09-01-luna/` | "Luna", a fresh agent in the author's harness | Claude (session default) | `2dcc162` | `15ad8052…` | approve_with_changes |
| `2026-09-02-opus/` | Claude Opus via `claude -p` | claude-opus-5 | `676da6d` | `9f6a49f6…` | approve_with_changes |

Files per directory:

- `review.json`: the reviewer's full structured output (findings with severity, location, failure mode, amendment, and a mechanical acceptance test; owner questions; verdict).
- `manifest.json`: the artifact name, byte count, sha256, and creation time.
- `reviewers.json`: provider, requested and concrete model, attempt, exit state.
- `release_context.txt`: the owner's questions the reviewer was asked to answer.
- `review_prompt.txt`: the generic review instructions.

Local scratch paths have been replaced with `<packet>` and `~`. Nothing else was edited. The author of the collector (a Claude model) is not one of the reviewers listed here; the same model did author the demo page and the first attestations in `docs/example/`, which the second reviewer caught miscounting.

Findings that led to changes are listed in the CHANGELOG. Findings deferred to a later release, and the owner's answers to reviewer questions, are recorded there as well.

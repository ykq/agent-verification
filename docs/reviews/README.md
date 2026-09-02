# Pre-release adversarial reviews

The README claims the collector was written by one model and audited by others before release. This directory is the checkable part of that claim.

Each review was produced by an independent agent given only the frozen artifact, the review prompt, the release context, and the output schema. Reviewers were not shown each other's findings. Every reviewer had shell access to run the tests and the collector against the frozen tree, and each was told to verify by execution and to try to defeat the fail-closed gate.

| Directory | Reviewer | Model family | Commit reviewed | Artifact sha256 (`git archive` tar) | Verdict |
|---|---|---|---|---|---|
| `2026-09-01-luna/` | "Luna", a fresh agent in the author's harness | Claude (session default) | `2dcc162` | `15ad8052…` | approve_with_changes |
| `2026-09-02-opus/` | Claude Opus via `claude -p` | claude-opus-5 | `676da6d` | `9f6a49f6…` | approve_with_changes |
| `2026-09-02-opus-final/` | Claude Opus via `claude -p` | claude-opus-5 | `142c940` (0.2.0 candidate) | `d848f3ed…` | approve_with_changes |

Files per directory:

- `review.json`: the reviewer's full structured output (findings with severity, location, failure mode, amendment, and a mechanical acceptance test; owner questions; verdict).
- `manifest.json`: the artifact name, byte count, sha256, and creation time.
- `reviewers.json`: provider, requested and concrete model, attempt, exit state.
- `release_context.txt`: the owner's questions the reviewer was asked to answer.
- `review_prompt.txt`: the generic review instructions.

Local scratch paths have been replaced with `<packet>` and `~`. Nothing else was edited. The author of the collector (a Claude model) is not one of the reviewers listed here; the same model did author the demo page and the first attestations in `docs/example/`, which the second reviewer caught miscounting.

Findings that led to changes are listed in the CHANGELOG under the release that made them. Findings not acted on, with the reason, are under "Reviewer findings not acted on" in the same CHANGELOG section.

## Git history scan

No reviewer saw git history; each received a `git archive` of one commit. Before the public flip the maintainer scanned every blob reachable from every ref, plus all commit messages and author fields, with the command below. Result on 2026-09-02 over 14 commits and 89 blobs: zero hits outside the allow-list (the author's own attribution, the fake credentials in `tests/fixtures/`, and a reviewer's own mention of the search terms). Re-run it yourself on a clone.

```bash
git rev-list --all --objects | cut -d' ' -f1 \
  | git cat-file --batch-check='%(objecttype) %(objectname)' | awk '$1=="blob"{print $2}' | sort -u \
  | while read b; do git cat-file -p "$b" \
      | grep -a -n -i -E '/home/|ts\.net|@[a-z0-9.-]+\.[a-z]{2,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|xox[baprs]-|BEGIN [A-Z ]*PRIVATE KEY|tskey-' \
      | sed "s|^|$b: |"; done
git log --all --format='%an <%ae> %cn <%ce>' | sort -u
```


#!/usr/bin/env bash
# Deterministic fixture tests for scripts/capture.mjs. Run: npm test
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
capture="$skill_dir/scripts/capture.mjs"
fx="file://$skill_dir/tests/fixtures"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

if [ -z "${PLAYWRIGHT_PATH:-}" ] && [ ! -d "$skill_dir/node_modules/playwright" ] && [ ! -d "$PWD/node_modules/playwright" ]; then
  echo "Playwright not found. Run: npm run setup (in $skill_dir) or set PLAYWRIGHT_PATH" >&2
  exit 1
fi

pass=0
check() { echo "ok - $1"; pass=$((pass + 1)); }
fail() { echo "FAIL - $1" >&2; exit 1; }
run() { # run <expected-exit> <args...>
  local expected=$1; shift
  set +e; node "$capture" "$@" >"$test_root/stdout" 2>"$test_root/stderr"; local code=$?; set -e
  [ "$code" -eq "$expected" ] || { cat "$test_root/stderr" >&2; fail "expected exit $expected, got $code for: $*"; }
}
receipt() { python3 - "$1" "$2" <<'PY' || fail "receipt assertion failed for $1"
import json, sys
receipt = json.load(open(sys.argv[1]))
exec(sys.argv[2])
PY
}

# 1. Clean page: capture completes with no findings, no diagnostics.
run 0 "$fx/clean.html" --allow-file --tabs 'Overview,Details' --viewports 'test=800x600' \
  --view-selector '.view' --ready-selector 'main' --screenshot-mode viewport --out-dir "$test_root/clean"
receipt "$test_root/clean/receipt.json" '
assert receipt["status"] == "capture_complete_requires_human_inspection", receipt["status"]
assert len(receipt["screenshots"]) == 4, receipt["screenshots"]
assert not receipt["findings"], receipt["findings"]
assert not receipt["diagnostics"], receipt["diagnostics"]
assert receipt["run_id"] and receipt["schema_version"] == 3
assert all(len(s["sha256"]) == 64 for s in receipt["screenshots"]), "every artifact carries a digest"'
check "clean page passes"

# 2. Broken page: missing state, overflow, clipping, orphan all detected.
run 2 "$fx/broken.html" --allow-file --tabs 'Overview,Missing' --viewports 'test=800x600' \
  --view-selector '.view' --screenshot-mode viewport --out-dir "$test_root/broken"
receipt "$test_root/broken/receipt.json" '
types = {f["type"] for f in receipt["findings"]}
assert receipt["status"] == "structural_failures"
assert {"missing_state", "horizontal_overflow", "clipped_content", "orphan_content"} <= types, types
assert any(f["type"] == "missing_state" and f["reason"] == "no_match" for f in receipt["findings"])'
check "broken page fails with all four finding types"

# 3. Legitimate patterns (ellipsis, line-clamp, scroll container, collapsed drawer) are not findings.
run 0 "$fx/legit.html" --allow-file --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/legit"
receipt "$test_root/legit/receipt.json" 'assert not receipt["findings"], receipt["findings"]'
check "no false positives on line-clamp / ellipsis / scroll / collapsed"

# 4. Tab semantics: nested spans and case-insensitive labels click; hidden tabs and inert tabs are findings.
run 2 "$fx/tabs.html" --allow-file --tabs 'Overview,details,Hidden,Dead' --viewports 'test=800x600' \
  --screenshot-mode viewport --out-dir "$test_root/tabs"
receipt "$test_root/tabs/receipt.json" '
shots = {s["state"]: s["clicked"] for s in receipt["screenshots"] if s["kind"] == "viewport"}
assert shots["Overview"] == "clicked_no_change_already_active" and shots["details"] == "clicked", shots
hidden = [f for f in receipt["findings"] if f["type"] == "missing_state"]
assert hidden and hidden[0]["state"] == "Hidden" and hidden[0]["reason"] == "not_visible", receipt["findings"]
inert = [f for f in receipt["findings"] if f["type"] == "state_unchanged"]
assert inert and inert[0]["state"] == "Dead", receipt["findings"]'
check "hidden tab and inert tab are reported"

# 5. Secrets in console output and failed-request URLs are redacted in the receipt.
run 0 "$fx/leak.html" --allow-file --viewports 'test=400x300' --screenshot-mode viewport --out-dir "$test_root/leak"
! grep -q 'SECRET123\|SECRET456\|LEAKME\|frag' "$test_root/leak/receipt.json" || fail "secret leaked into receipt"
grep -q 'REDACTED' "$test_root/leak/receipt.json" || fail "expected REDACTED marker"
run 0 "$fx/leak2.html" --allow-file --viewports 'test=400x300' --screenshot-mode viewport --out-dir "$test_root/leak2"
for needle in OPAQUEBEARER111 CLIENTSEC222 AWSSEC333 words999 DBPASS555 dbuser GHPAT66666666 GLPAT7777777 NPMTOK8888888 UPPER99999999999 PATHTOKEN1234567890; do
  ! grep -q "$needle" "$test_root/leak2/receipt.json" || fail "secret leaked into receipt: $needle"
done
check "console and URL secrets redacted"

# 5b. Identifiers in URL path segments are redacted in request and console diagnostics unless explicitly retained.
run 0 "$fx/leak3.html" --allow-file --viewports 'test=400x300' --screenshot-mode viewport --out-dir "$test_root/leak3"
receipt "$test_root/leak3/receipt.json" '
serialised = json.dumps(receipt["diagnostics"])
assert not any(needle in serialised for needle in ["jane.doe", "123-45-6789", "acme-corp", "private-notes", "ssn-"]), serialised
assert "dashboard.acme-internal.example" in serialised, serialised
assert "/tenants/[REDACTED]" in serialised, serialised'
run 0 "$fx/leak3.html" --allow-file --keep-paths --viewports 'test=400x300' --screenshot-mode viewport --out-dir "$test_root/leak3-keep"
receipt "$test_root/leak3-keep/receipt.json" 'assert "private-notes" in json.dumps(receipt["diagnostics"]), receipt["diagnostics"]'
check "URL path identifiers redacted unless --keep-paths is set"

# 6. file:// refused without --allow-file; no receipt written.
run 64 "$fx/clean.html" --out-dir "$test_root/nofile"
grep -q 'allow-file' "$test_root/stderr" || fail "expected --allow-file hint"
[ ! -e "$test_root/nofile/receipt.json" ] || fail "receipt written on usage error"
check "file:// refused by default"

# 7. Usage errors are clean one-liners, exit 64, no stack trace.
run 64 http://127.0.0.1:9/ --wait-ms abc
grep -q '^error: --wait-ms' "$test_root/stderr" || fail "expected clean usage error"
! grep -q '    at ' "$test_root/stderr" || fail "stack trace in usage error"
run 64 http://127.0.0.1:9/ --viewports 'a=b'
run 64 http://127.0.0.1:9/ --bogus 1
run 64 ftp://example.com/
run 64 http://127.0.0.1:9/ --tabs --insecure
run 64 http://127.0.0.1:9/ --viewports 'z=0x0'
run 64 http://127.0.0.1:9/ --tabs 'Foo Bar,foo-bar'
touch "$test_root/afile"; run 64 http://127.0.0.1:9/ --out-dir "$test_root/afile"
run 64 http://127.0.0.1:9/ --spec "$test_root"
run 64 attest
run 64 check "$test_root/afile"
check "usage errors exit 64 without stack traces"

# 8. Capture failure writes a capture_failed receipt and replaces any stale receipt in the out-dir.
run 0 "$fx/clean.html" --allow-file --viewports 'test=400x300' --screenshot-mode viewport --out-dir "$test_root/stale"
run 1 http://127.0.0.1:9/ --timeout-ms 5000 --out-dir "$test_root/stale"
receipt "$test_root/stale/receipt.json" '
assert receipt["status"] == "capture_failed" and receipt["error"], receipt
assert receipt["url"].startswith("http://127.0.0.1:9"), receipt["url"]'
! grep -q '    at ' "$test_root/stderr" || fail "stack trace on capture failure"
check "capture failure leaves a capture_failed receipt, not a stale one"

# 9. Help.
run 0 --help
grep -q -- '--allow-file' "$test_root/stdout" && grep -q -- '--no-aria-snapshot' "$test_root/stdout" || fail "help incomplete"
check "help documents all flags"

# 10. --spec records the acceptance spec hash; attest/check fail closed until every PNG is attested.
printf 'Header must be 64px tall and use the brand blue.\n' > "$test_root/spec.md"
run 0 "$fx/clean.html" --allow-file --spec "$test_root/spec.md" --tabs 'Overview,Details' --viewports 'test=800x600' \
  --screenshot-mode viewport --out-dir "$test_root/attest"
receipt "$test_root/attest/receipt.json" '
import hashlib
assert receipt["spec"]["sha256"] == hashlib.sha256(open(receipt["spec"]["path"],"rb").read()).hexdigest()'
run 3 check "$test_root/attest/receipt.json"
grep -q 'UNINSPECTED' "$test_root/stderr" || fail "expected UNINSPECTED"
run 64 attest "$test_root/attest/receipt.json" --path test--overview--viewport.png --verdict pass --note short
run 64 attest "$test_root/attest/receipt.json" --path nope.png --verdict pass --note 'this screenshot does not exist'
run 64 attest "$test_root/attest/receipt.json" --path test--overview--viewport.png --verdict maybe --note 'bad verdict value here'
run 0 attest "$test_root/attest/receipt.json" --path test--overview--viewport.png --verdict pass --note 'Header 64px, brand blue, matches spec' --by tester
run 3 check "$test_root/attest/receipt.json"
run 0 attest "$test_root/attest/receipt.json" --path test--details--viewport.png --verdict caveat --note 'Details card border slightly lighter than spec'
run 0 check "$test_root/attest/receipt.json"
grep -q 'OK with caveats' "$test_root/stdout" || fail "expected caveat summary"
grep -q 'sha256:' "$test_root/stdout" || fail "expected spec hash in check output"
run 0 attest "$test_root/attest/receipt.json" --path test--details--viewport.png --verdict fail --note 'On second look the card is clipped'
run 4 check "$test_root/attest/receipt.json"
receipt "$test_root/attest/receipt.json" 'assert len(receipt["inspections"]) == 3, "attestations must be append-only"'
receipt "$test_root/attest/receipt.json" 'assert all(len(i["sha256"]) == 64 and i["run_id"] == receipt["run_id"] for i in receipt["inspections"])'
check "spec hash recorded; check fails closed until attested; fail verdict rejects"

# 10b. Attestations are bound to PNG bytes: a regenerated screenshot invalidates them; a forged receipt is rejected.
run 0 "$fx/clean.html" --allow-file --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/digest"
run 0 attest "$test_root/digest/receipt.json" --path test--page--viewport.png --verdict pass --note 'Overview card renders cleanly'
run 0 check "$test_root/digest/receipt.json"
printf 'tampered' >> "$test_root/digest/test--page--viewport.png"
run 3 check "$test_root/digest/receipt.json"
grep -q 'STALE ATTESTATION' "$test_root/stderr" || fail "expected STALE ATTESTATION"
run 64 attest "$test_root/digest/receipt.json" --path test--page--viewport.png --verdict pass --note 'attesting changed bytes must fail'
printf '{"schema_version":3,"run_id":"x","status":"forged","screenshots":[],"findings":[],"inspections":[]}\n' > "$test_root/forged.json"
run 64 check "$test_root/forged.json"
printf '{"schema_version":3,"run_id":"x","status":"capture_complete_requires_human_inspection","screenshots":[],"findings":[],"inspections":[]}\n' > "$test_root/empty.json"
run 3 check "$test_root/empty.json"
grep -q 'NO SCREENSHOTS' "$test_root/stderr" || fail "expected NO SCREENSHOTS"
check "attestations bound to PNG digests; forged and empty receipts rejected"

# 10c. attest refuses a failed capture; check reports every failure class and exits with the most severe.
run 1 http://127.0.0.1:9/ --timeout-ms 5000 --out-dir "$test_root/failed"
run 64 attest "$test_root/failed/receipt.json" --path x.png --verdict pass --note 'cannot attest a failed capture'
run 1 check "$test_root/failed/receipt.json"
run 2 "$fx/broken.html" --allow-file --tabs 'Overview,Missing' --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/multi"
run 0 attest "$test_root/multi/receipt.json" --path test--overview--viewport.png --verdict fail --note 'clipped card is visible in the PNG'
run 4 check "$test_root/multi/receipt.json"
grep -q 'STRUCTURAL FINDINGS' "$test_root/stderr" && grep -q 'UNINSPECTED' "$test_root/stderr" && grep -q 'FAILED ATTESTATIONS' "$test_root/stderr" || fail "check must list every failure class"
check "failed captures cannot be attested; check lists all failure classes, exits most severe"

# 11. check on a receipt with structural findings fails even if attested.
run 2 "$fx/broken.html" --allow-file --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/checkbroken"
run 0 attest "$test_root/checkbroken/receipt.json" --path test--page--viewport.png --verdict pass --note 'looks fine to me honestly'
run 2 check "$test_root/checkbroken/receipt.json"
check "structural findings cannot be attested away"

# 12. Lazy images never block the capture past the timeout.
run 0 "$fx/lazy.html" --allow-file --viewports 'test=800x600' --screenshot-mode viewport --timeout-ms 4000 --out-dir "$test_root/lazy"
check "lazy images do not hang the capture"

# 13. Tab order does not invert verdicts: inert tab flagged wherever it is, unless it is the first (possibly already active) state.
run 2 "$fx/tabs.html" --allow-file --tabs 'Overview,Dead' --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/order1"
receipt "$test_root/order1/receipt.json" 'assert [f["state"] for f in receipt["findings"] if f["type"] == "state_unchanged"] == ["Dead"], receipt["findings"]'
run 0 "$fx/tabs.html" --allow-file --tabs 'Dead,Overview' --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/order2"
receipt "$test_root/order2/receipt.json" '
shots = {s["state"]: s["clicked"] for s in receipt["screenshots"] if s["kind"] == "viewport"}
assert shots["Dead"] == "clicked_no_change_possibly_already_active" and shots["Overview"] == "clicked_no_change_already_active", shots'
check "state_unchanged compares before/after the click; active-marked and first tabs are not flagged"

# 14. Volatile pages disable state_unchanged instead of guessing; role=tab beats a header link with the same text; no <main> falls back to body.
run 0 "$fx/clock.html" --allow-file --tabs 'Overview,Dead' --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/clock"
receipt "$test_root/clock/receipt.json" 'assert any(e["type"] == "volatile_dom" for d in receipt["diagnostics"] for e in d["events"]), receipt["diagnostics"]'
run 0 "$fx/dup.html" --allow-file --tabs 'Overview,Details' --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/dup"
grep -q 'Details content' "$test_root/dup/test--details.aria.yml" || fail "role=tab should win over the header link"
run 2 "$fx/nomain.html" --allow-file --viewports 'test=800x600' --screenshot-mode viewport --out-dir "$test_root/nomain"
receipt "$test_root/nomain/receipt.json" 'assert any(f["type"] == "clipped_content" and f["scope"] == "body" for f in receipt["findings"]), receipt["findings"]'
check "volatile DOM skips the check; tab tiers; body fallback without main"

# 15. Stale evidence from an earlier run in the same out-dir is removed.
run 0 "$fx/clean.html" --allow-file --tabs 'Overview,Details' --viewports 'a=400x300' --screenshot-mode viewport --out-dir "$test_root/reuse"
run 0 "$fx/clean.html" --allow-file --viewports 'b=400x300' --screenshot-mode viewport --out-dir "$test_root/reuse"
[ ! -e "$test_root/reuse/a--overview--viewport.png" ] || fail "stale PNG survived"
check "stale evidence cleared from a reused out-dir"

echo "agent-verification: $pass checks passed"

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
receipt() { python3 - "$1" "$2" <<'PY'
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
assert receipt["run_id"] and receipt["schema_version"] == 2'
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
assert shots["Overview"] == "clicked" and shots["details"] == "clicked", shots
hidden = [f for f in receipt["findings"] if f["type"] == "missing_state"]
assert hidden and hidden[0]["state"] == "Hidden" and hidden[0]["reason"] == "not_visible", receipt["findings"]
inert = [f for f in receipt["findings"] if f["type"] == "state_unchanged"]
assert inert and inert[0]["state"] == "Dead", receipt["findings"]'
check "hidden tab and inert tab are reported"

# 5. Secrets in console output and failed-request URLs are redacted in the receipt.
run 0 "$fx/leak.html" --allow-file --viewports 'test=400x300' --screenshot-mode viewport --out-dir "$test_root/leak"
! grep -q 'SECRET123\|SECRET456\|LEAKME\|frag' "$test_root/leak/receipt.json" || fail "secret leaked into receipt"
grep -q 'REDACTED' "$test_root/leak/receipt.json" || fail "expected REDACTED marker"
check "console and URL secrets redacted"

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

echo "agent-verification: $pass checks passed"

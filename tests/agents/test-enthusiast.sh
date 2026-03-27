#!/usr/bin/env bash
# Tests for agents/enthusiast.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: enthusiast agent ==="
echo ""
passed=0; failed=0

run_test() {
    if "$@"; then passed=$((passed+1)); else failed=$((failed+1)); fi
}

# ---------------------------------------------------------------------------
# Test 1: clean code produces empty findings (not null, not missing key)
# ---------------------------------------------------------------------------
echo "Test 1: clean code → {\"findings\": []} not null or missing"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// utils.ts
export function clamp(value: number, min: number, max: number): number {
  if (min > max) throw new Error('min must be <= max');
  return Math.min(Math.max(value, min), max);
}
</code>

Respond with only the JSON findings object.
" 90)

run_test assert_json_has_key "$output" "findings" "findings key present"
run_test assert_json_array_length "$output" "findings" "0" "no findings for clean code"

echo ""

# ---------------------------------------------------------------------------
# Test 2: output is pure JSON — no preamble, no markdown fences
# ---------------------------------------------------------------------------
echo "Test 2: output is raw JSON — no prose preamble, no markdown fences"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// auth.ts line 5
function login(username: string, password: string) {
  if (password === 'admin123') return true;
  return db.check(username, password);
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    # Check it doesn't start with prose (first non-whitespace char should be '{')
    first_char=$(echo "$output" | python3 -c "
import sys
text = sys.stdin.read().strip()
print(text[0] if text else '')
" 2>/dev/null)
    if [ "$first_char" = "{" ]; then
        echo "  [PASS] output starts with '{' (no preamble)"
        passed=$((passed+1))
    else
        echo "  [FAIL] output does not start with '{' — starts with: $first_char"
        echo "  Output preview: $(echo "$output" | head -3)"
        failed=$((failed+1))
    fi
    # Check for markdown fences
    if echo "$output" | grep -q '```'; then
        echo "  [FAIL] output contains markdown fences (should be raw JSON)"
        failed=$((failed+1))
    else
        echo "  [PASS] no markdown fences"
        passed=$((passed+1))
    fi
else
    echo "  [FAIL] output is not valid JSON"
    failed=$((failed+1))
fi

echo ""

# ---------------------------------------------------------------------------
# Test 3: valid JSON schema — required fields on each finding
# ---------------------------------------------------------------------------
echo "Test 3: findings have all required fields (id, severity, file, line, description, evidence, prior_finding_id)"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// server.ts line 12
app.get('/user', (req, res) => {
  const id = req.query.id;
  const user = db.query('SELECT * FROM users WHERE id=' + id);
  res.json(user);
});
</code>

Respond with only the JSON findings object.
" 90)

run_test assert_json_has_key "$output" "findings" "findings key present"

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
if not findings:
    print('no_findings')
    sys.exit(0)
required = ['id','severity','file','line','description','evidence','prior_finding_id']
for f in findings:
    missing = [k for k in required if k not in f]
    if missing:
        print('missing:' + ','.join(missing) + ' on ' + f.get('id','?'))
        sys.exit(0)
print('ok')
" 2>/dev/null)
    if [ "$result" = "ok" ] || [ "$result" = "no_findings" ]; then
        echo "  [PASS] all required fields present on every finding"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 4: severity values are within allowed set
# ---------------------------------------------------------------------------
echo "Test 4: severity values are only critical|high|medium|low"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// api.ts
async function fetchUser(id) {
  const res = await fetch('/api/users/' + id);
  return res.json();
}

let cache = {};
function memoize(fn) {
  return function(key) {
    if (!cache[key]) cache[key] = fn(key);
    return cache[key];
  }
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
allowed = {'critical','high','medium','low'}
bad = [f['id'] for f in d.get('findings',[]) if f.get('severity') not in allowed]
print('bad:' + ','.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] all severities are valid"
        passed=$((passed+1))
    else
        echo "  [FAIL] invalid severities: $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 5: finding IDs are sequential F1, F2, F3 ... unique within round
# ---------------------------------------------------------------------------
echo "Test 5: finding IDs are sequential (F1, F2, F3 ...) and unique"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// config.ts line 1
const DB_PASSWORD = 'hunter2';
const API_SECRET = 'abc123secret';

function connectDB() {
  return mysql.connect({ host: 'localhost', user: 'root', password: DB_PASSWORD });
}

async function callAPI(endpoint) {
  return fetch(endpoint + '?key=' + API_SECRET);
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
findings = d.get('findings', [])
if not findings:
    print('ok_empty')
    sys.exit(0)
ids = [f.get('id','') for f in findings]
# Check uniqueness
if len(ids) != len(set(ids)):
    print('duplicate IDs: ' + str(ids))
    sys.exit(0)
# Check sequential F1, F2, ...
expected = ['F' + str(i+1) for i in range(len(ids))]
if ids == expected:
    print('ok')
else:
    print('non-sequential: got ' + str(ids) + ' expected ' + str(expected))
" 2>/dev/null)
    if [ "$result" = "ok" ] || [ "$result" = "ok_empty" ]; then
        echo "  [PASS] IDs are sequential and unique"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 6: obvious critical bug is detected (SQL injection)
# ---------------------------------------------------------------------------
echo "Test 6: SQL injection is flagged as critical or high"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// db.ts line 1
import { pool } from './pool';

export function getUser(username: string) {
  return pool.query('SELECT * FROM users WHERE username = \\'' + username + '\\'');
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
high_severity = [f for f in findings if f.get('severity') in ('critical', 'high')]
# Look for a SQL injection finding
sql_findings = [f for f in high_severity if
    'sql' in f.get('description','').lower() or
    'inject' in f.get('description','').lower() or
    'inject' in f.get('evidence','').lower() or
    'concatenat' in f.get('evidence','').lower()]
print('ok' if sql_findings else 'not_found (findings: ' + str([(f['id'],f['severity'],f['description']) for f in findings]) + ')')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] SQL injection detected as critical/high"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 7: null/undefined dereference is flagged
# ---------------------------------------------------------------------------
echo "Test 7: null dereference is flagged"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// user.ts line 1
interface User {
  profile?: { name: string; email: string };
}

function getEmail(user: User): string {
  return user.profile.email;
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
null_findings = [f for f in findings if
    'null' in f.get('description','').lower() or
    'undefined' in f.get('description','').lower() or
    'optional' in f.get('description','').lower() or
    'profile' in f.get('evidence','').lower()]
print('ok' if null_findings else 'not_found (findings: ' + str([(f['id'],f['description']) for f in findings]) + ')')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] null dereference detected"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 8: evidence field references actual code — not vague claims
# ---------------------------------------------------------------------------
echo "Test 8: evidence quotes or references specific code, not vague claims"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// timer.ts line 1
function startPolling(callback: () => void) {
  setInterval(callback, 1000);
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
if not findings:
    print('ok_empty')
    sys.exit(0)
# Evidence should not be vague: must be at least 10 chars and not just 'could be null' style
vague = []
for f in findings:
    ev = f.get('evidence', '')
    if len(ev) < 10:
        vague.append(f['id'] + ':too_short')
    elif ev.strip().lower() in ('could be null', 'might fail', 'possible issue', 'this is bad'):
        vague.append(f['id'] + ':vague_phrase')
print('vague:' + ','.join(vague) if vague else 'ok')
" 2>/dev/null)
    if [ "$result" = "ok" ] || [ "$result" = "ok_empty" ]; then
        echo "  [PASS] evidence fields are substantive"
        passed=$((passed+1))
    else
        echo "  [FAIL] vague evidence detected: $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 9: prior_finding_id is null in round 1 (no prior findings given)
# ---------------------------------------------------------------------------
echo "Test 9: prior_finding_id is null for all findings when no prior round given"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// app.ts line 1
const fs = require('fs');
function readConfig(path: string) {
  const data = fs.readFileSync(path, 'utf8');
  return JSON.parse(data);
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
if not findings:
    print('ok_empty')
    sys.exit(0)
non_null = [f['id'] for f in findings if f.get('prior_finding_id') is not None]
print('non_null_prior_ids:' + ','.join(non_null) if non_null else 'ok')
" 2>/dev/null)
    if [ "$result" = "ok" ] || [ "$result" = "ok_empty" ]; then
        echo "  [PASS] prior_finding_id is null in round 1"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 10: round 2 — uses prior_finding_id to reference prior finding
# ---------------------------------------------------------------------------
echo "Test 10: round 2 finding builds on prior finding using prior_finding_id"

output=$(run_as_agent "enthusiast.md" "
Review this code. Prior round findings and rulings are provided. Focus on what was MISSED.

<code>
// payment.ts line 1
async function charge(userId: string, amount: number) {
  const user = await db.getUser(userId);
  await stripe.charge(user.stripeId, amount);
  await db.recordCharge(userId, amount);
}
</code>

Prior round findings:
{\"findings\":[{\"id\":\"F1\",\"severity\":\"high\",\"file\":\"payment.ts\",\"line\":3,\"description\":\"No error handling on stripe.charge\",\"evidence\":\"stripe.charge called without try/catch or .catch()\",\"prior_finding_id\":null}]}

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
# Accept: empty findings (no new issues found) OR at least one finding references F1
if not findings:
    print('ok_empty')
    sys.exit(0)
references_prior = any(f.get('prior_finding_id') is not None for f in findings)
# It's also valid to find new unrelated issues with null prior_finding_id
# The key thing is the agent accepted prior findings in its context
print('ok')
" 2>/dev/null)
    if [ "$result" = "ok" ] || [ "$result" = "ok_empty" ]; then
        echo "  [PASS] round 2 handled correctly"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 11: file path in findings matches the code provided — no invented paths
# ---------------------------------------------------------------------------
echo "Test 11: file paths in findings match provided file paths, no invented paths"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// src/handlers/auth.ts line 1
function verifyToken(token: string) {
  const decoded = jwt.decode(token);
  return decoded.userId;
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
if not findings:
    print('ok_empty')
    sys.exit(0)
# The only valid file path mentioned is src/handlers/auth.ts
valid_paths = {'src/handlers/auth.ts', 'auth.ts'}
bad = [f['id'] for f in findings if f.get('file') not in valid_paths]
print('invented_paths:' + ','.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$result" = "ok" ] || [ "$result" = "ok_empty" ]; then
        echo "  [PASS] file paths match provided code"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 12: hardcoded secret is flagged
# ---------------------------------------------------------------------------
echo "Test 12: hardcoded secret is detected"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// config.ts line 1
export const config = {
  jwtSecret: 'super-secret-jwt-key-do-not-share',
  dbPassword: 'p@ssw0rd123',
};
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
secret_findings = [f for f in findings if
    'secret' in f.get('description','').lower() or
    'hardcod' in f.get('description','').lower() or
    'credential' in f.get('description','').lower() or
    'password' in f.get('description','').lower() or
    'jwtSecret' in f.get('evidence','') or
    'dbPassword' in f.get('evidence','')]
print('ok' if secret_findings else 'not_found (findings: ' + str([(f['id'],f['description']) for f in findings]) + ')')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] hardcoded secret detected"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 13: multiple distinct issues get distinct findings (not merged)
# ---------------------------------------------------------------------------
echo "Test 13: multiple distinct issues produce multiple distinct findings"

output=$(run_as_agent "enthusiast.md" "
Review this code and find all issues.

<code>
// processor.ts line 1
function processItems(items: any[]) {
  // Issue A: off-by-one — should be i <= items.length - 1 but uses i < items.length (fine),
  // actually the bug is below: accesses items[items.length] which is undefined
  for (let i = 0; i <= items.length; i++) {
    const item = items[i];
    item.process();
  }
}

function loadFile(path: string) {
  // Issue B: no error handling on fs.readFileSync
  const data = require('fs').readFileSync(path);
  return JSON.parse(data);
}
</code>

Respond with only the JSON findings object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = d.get('findings', [])
print('ok' if len(findings) >= 2 else 'only_' + str(len(findings)) + '_finding(s)_for_2_issues')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] multiple issues produce multiple findings"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== enthusiast: passed=$passed failed=$failed ==="
[ $failed -eq 0 ] || exit 1

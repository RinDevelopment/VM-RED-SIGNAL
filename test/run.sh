#!/usr/bin/env bash
# language: bash, file: test/run.sh
# full pipeline check: keyless embedded + external keys, args, shebang, leak checks.

set -u
cd "$(dirname "$0")/.."
mkdir -p out

# generated stress source (kept out of the repo)
lua -e '
local f = io.open("out/big_src.lua", "w")
f:write("local acc = 0\n")
for i = 1, 6000 do
  f:write("do local x = ", i, "; acc = (acc + x * 3) % 1000003 end\n")
end
f:write("print(acc)\n")
f:close()
'

KEY="shroud-test-key-2026"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

run_case() {
    local name="$1"; shift
    if "$@" >/tmp/shroud-case.log 2>&1; then
        ok "$name"
    else
        bad "$name"
        sed 's/^/        /' /tmp/shroud-case.log | tail -20
    fi
}

echo "== source mode =="
run_case "test.lua" lua cli/obfuscate.lua samples/test.lua --mode=source --out=out/t1.lua --verify
run_case "vmtest.lua" lua cli/obfuscate.lua samples/vmtest.lua --mode=source --out=out/t2.lua --verify
run_case "tricky.lua" lua cli/obfuscate.lua samples/tricky.lua --mode=source --out=out/t3.lua --verify
run_case "big.lua" lua cli/obfuscate.lua out/big_src.lua --mode=source --out=out/t4.lua --verify

echo "== vm mode =="
run_case "default mode (vm)" lua cli/obfuscate.lua samples/test.lua --out=out/v0.lua --verify
run_case "test.lua" lua cli/obfuscate.lua samples/test.lua --mode=vm --out=out/v1.lua --verify
run_case "vmtest.lua" lua cli/obfuscate.lua samples/vmtest.lua --mode=vm --out=out/v2.lua --verify
run_case "tricky.lua" lua cli/obfuscate.lua samples/tricky.lua --mode=vm --out=out/v3.lua --verify
run_case "big.lua" lua cli/obfuscate.lua out/big_src.lua --mode=vm --out=out/v4.lua --verify

echo "== external key =="
run_case "vm external" lua cli/obfuscate.lua samples/vmtest.lua --key="$KEY" --mode=vm --keymode=external --out=out/x1.lua --verify
run_case "source external" lua cli/obfuscate.lua samples/test.lua --key="$KEY" --mode=source --keymode=external --out=out/x2.lua --verify

echo "== keyless + key handling =="
lua cli/obfuscate.lua samples/test.lua --mode=vm --out=out/r1.lua >/dev/null 2>&1
lua cli/obfuscate.lua samples/test.lua --mode=vm --out=out/r2.lua >/dev/null 2>&1
if cmp -s out/r1.lua out/r2.lua; then bad "per-build key/salt randomness"; else ok "per-build key/salt randomness"; fi
if lua out/r1.lua >/dev/null 2>&1; then ok "keyless build runs"; else bad "keyless build runs"; fi
LEAK_KEY="UNIQUE-shroud-key-2026-abcdef"
lua cli/obfuscate.lua samples/test.lua --key="$LEAK_KEY" --mode=vm --out=out/leak.lua >/dev/null 2>&1
if grep -q "$LEAK_KEY" out/leak.lua; then bad "supplied key not in artifact"; else ok "supplied key not in artifact"; fi
if lua out/leak.lua >/dev/null 2>&1; then ok "supplied-key build runs"; else bad "supplied-key build runs"; fi

echo "== args + shebang =="
lua cli/obfuscate.lua samples/args.lua --mode=vm --out=out/args.vm.lua >/dev/null 2>&1
lua cli/obfuscate.lua samples/args.lua --mode=source --out=out/args.src.lua >/dev/null 2>&1
lua samples/args.lua alpha beta > /tmp/shroud-a1 2>&1
lua out/args.vm.lua alpha beta > /tmp/shroud-a2 2>&1
if diff -q /tmp/shroud-a1 /tmp/shroud-a2 >/dev/null; then ok "vm script args"; else bad "vm script args"; fi
lua out/args.src.lua alpha beta > /tmp/shroud-a3 2>&1
if diff -q /tmp/shroud-a1 /tmp/shroud-a3 >/dev/null; then ok "source script args"; else bad "source script args"; fi
run_case "shebang preserved" lua cli/obfuscate.lua samples/shebang.lua --mode=vm --out=out/s1.lua --verify

echo
printf 'total: %d pass, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

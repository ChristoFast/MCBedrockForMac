#!/bin/bash
# Tests a WineGDK build: boots a prefix, runs a Windows program, renders D3D12
# with our probe, and checks the GDK runtime DLLs load.
#
#   bash scripts/test-winegdk.sh <winegdk-dir>
#
# Exits non-zero if any check fails.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=winegdk-env.sh
. "$REPO/scripts/winegdk-env.sh" "${1:?usage: test-winegdk.sh <winegdk-dir>}"
WORK="${MCB_WORK:-$HOME/MCBedrockForMac-work}"
export WINEPREFIX="${WINEPREFIX:-$WORK/prefix-winegdk-test}"
export WINEDEBUG="${WINEDEBUG:-err+all}"
mkdir -p "$WORK"
# Timeout helper. /usr/bin/perl is SIP-protected, so macOS strips DYLD_* from its
# environment; /usr/bin/env puts the library path back before exec'ing Wine.
t() {
    local s="$1"; shift
    perl -e 'alarm shift; exec @ARGV' "$s" \
        /usr/bin/env "DYLD_FALLBACK_LIBRARY_PATH=$DYLD_FALLBACK_LIBRARY_PATH" "$@"
}

failures=0
check() { if [ "$1" = 0 ]; then echo "[PASS] $2"; else echo "[FAIL] $2"; failures=$((failures + 1)); fi; }

echo "== $(sw_vers -productVersion) $(uname -m), $(sysctl -n machdep.cpu.brand_string)"
echo "== $(wine --version)"

t 300 wine wineboot -i >"$WORK/wineboot.log" 2>&1
if grep -q "NSInternalInconsistencyException\|winebus.*failed to start" "$WORK/wineboot.log"; then
    check 1 "controller service (winebus) starts"; grep -m3 -E "NSInternal|winebus" "$WORK/wineboot.log" | sed 's/^/    /'
else
    check 0 "controller service (winebus) starts"
fi
out="$(t 60 wine cmd /c ver 2>/dev/null | tr -d '\r')"
echo "$out" | grep -q Windows; check $? "wine runs Windows programs (${out//$'\n'/})"

# rundll32 loading the DLL proves it and its imports resolve.
for dll in xgameruntime gameinput; do
    t 60 wine rundll32 "$dll.dll,DllCanUnloadNow" >"$WORK/load-$dll.log" 2>&1
    if grep -qiE "could not load|not found|err:module" "$WORK/load-$dll.log"; then
        check 1 "$dll.dll loads"; sed 's/^/    /' "$WORK/load-$dll.log" | head -n 15
    else
        check 0 "$dll.dll loads"
    fi
done

t 120 wine "$REPO/tools/bin/d3d12probe.exe" >"$WORK/probe-winegdk.log" 2>&1
grep -v -E "validate_state_table|^\s*$" "$WORK/probe-winegdk.log" | tr -d '\r' | sed 's/^/    /' | tail -n 25
if grep -q "RESULT: D3D12 works" "$WORK/probe-winegdk.log"; then
    check 0 "D3D12 renders"
else
    check 1 "D3D12 renders"
    echo "    -- rerunning with graphics logging --"
    WINEDEBUG="err+all,warn+vulkan,warn+dxgi,warn+d3d,warn+d3d12,warn+module" \
        t 120 wine "$REPO/tools/bin/d3d12probe.exe" >"$WORK/probe-winegdk-debug.log" 2>&1
    grep -v -E "validate_state_table|^\s*$" "$WORK/probe-winegdk-debug.log" | tr -d '\r' | sed 's/^/    /' | tail -n 60
fi

wineserver -k 2>/dev/null
echo "== $failures failure(s)"
exit "$failures"

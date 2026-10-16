#!/bin/bash
# Milestone 0: prove the foundation works on this Mac.
#
#   bash scripts/m0-check.sh
#
# Checks Rosetta 2, downloads two free prebuilt Wine builds for macOS, and runs
# our D3D12 probe through each, to see which way of getting DirectX 12 onto
# Metal works on this machine:
#   A. Game Porting Toolkit Wine (Gcenx build, includes Apple's D3DMetal)
#   B. Upstream Wine (Gcenx build, D3D12 via vkd3d -> Vulkan -> MoltenVK)
#
# Everything goes into ~/MCBedrockForMac-work (override with MCB_WORK=...).
# Nothing is installed system-wide except Rosetta 2, and only if you say yes.
# At the end, paste the report file into the chat.
#
# Written for the bash 3.2 that ships with macOS.

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${MCB_WORK:-$HOME/MCBedrockForMac-work}"
REPORT="$WORK/m0-report.txt"
PROBE="$REPO/tools/bin/d3d12probe.exe"
mkdir -p "$WORK"
: > "$REPORT"

log()  { echo "$*" | tee -a "$REPORT"; }
step() { log ""; log "=== $* ==="; }

# macOS has no `timeout`; perl's alarm does the job.
with_timeout() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

RESULTS=""
result() { RESULTS="$RESULTS$1|$2"$'\n'; log "[$1] $2"; }

# ---------------------------------------------------------------------------
step "System"
log "date:    $(date)"
log "macOS:   $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
log "chip:    $(sysctl -n machdep.cpu.brand_string)"
log "arch:    $(uname -m)"
log "memory:  $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
log "free:    $(df -g "$HOME" | awk 'NR==2 {print $4}') GB in $HOME"
log "repo:    $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [ "$(uname -m)" != "arm64" ]; then
    result FAIL "Not an Apple Silicon Mac, or this Terminal is itself running under Rosetta."
    exit 1
fi
if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    log "note: this shell runs under Rosetta. Open a normal (arm64) Terminal for accurate results."
fi
if [ ! -f "$PROBE" ]; then
    result FAIL "Missing $PROBE. Run: git pull"
    exit 1
fi

# ---------------------------------------------------------------------------
step "Rosetta 2"
if arch -x86_64 /usr/bin/true 2>/dev/null; then
    result PASS "Rosetta 2 is installed"
else
    log "Rosetta 2 is not installed. It is required to run Windows x86-64 code."
    printf "Install it now? (needs your password) [y/N] "
    read -r yn
    if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
        sudo softwareupdate --install-rosetta --agree-to-license 2>&1 | tee -a "$REPORT"
    fi
    if arch -x86_64 /usr/bin/true 2>/dev/null; then
        result PASS "Rosetta 2 installed"
    else
        result FAIL "Rosetta 2 missing; cannot continue"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Picks a release asset from a GitHub repo's latest release.
#   pick_asset <owner/repo> <include-regex>  -> prints "name<TAB>url"
pick_asset() {
    local json
    json="$(curl -fsSL "https://api.github.com/repos/$1/releases/latest")" || return 1
    osascript -l JavaScript -e '
        function run(argv) {
            var rel = JSON.parse(argv[0]);
            var re = new RegExp(argv[1], "i");
            var hit = rel.assets.filter(function (a) {
                return re.test(a.name) && !/src|source|sha|\.sig$/i.test(a.name);
            });
            return hit.length ? hit[0].name + "\t" + hit[0].browser_download_url
                              : "NONE\t" + rel.assets.map(function (a) { return a.name; }).join(", ");
        }' "$json" "$2"
}

# Downloads and unpacks a Wine build; sets WINE_BIN to its wine executable.
#   fetch_wine <label> <owner/repo> <asset-regex>
fetch_wine() {
    local label="$1" dest="$WORK/$1" pick name url
    WINE_BIN=""
    if [ ! -d "$dest" ] || [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
        pick="$(pick_asset "$2" "$3")" || { log "could not reach GitHub for $2"; return 1; }
        name="${pick%%	*}"; url="${pick#*	}"
        if [ "$name" = "NONE" ]; then log "no matching download in $2; assets: $url"; return 1; fi
        log "downloading $name"
        mkdir -p "$dest"
        curl -fL --progress-bar -o "$WORK/$name" "$url" || return 1
        tar -xf "$WORK/$name" -C "$dest" || return 1
        rm -f "$WORK/$name"
        xattr -dr com.apple.quarantine "$dest" 2>/dev/null
    else
        log "using existing $dest"
    fi
    # Older Wine (GPTK) ships wine64; Wine 10+ has a single `wine`.
    WINE_BIN="$(find "$dest" -type f -perm -u+x \( -path '*/bin/wine64' \) | head -n1)"
    [ -z "$WINE_BIN" ] && WINE_BIN="$(find "$dest" -type f -perm -u+x -path '*/bin/wine' | head -n1)"
    if [ -z "$WINE_BIN" ]; then log "no wine executable found under $dest"; return 1; fi
    log "wine:    $WINE_BIN"
    log "version: $("$WINE_BIN" --version 2>/dev/null)"
    local d3dmetal
    d3dmetal="$(find "$dest" -maxdepth 8 -name 'D3DMetal.framework' | head -n1)"
    [ -n "$d3dmetal" ] && log "D3DMetal: $d3dmetal"
    return 0
}

# Boots a fresh prefix and runs the probe.   test_wine <label> [extra env...]
test_wine() {
    local label="$1"; shift
    local prefix="$WORK/prefix-$label" out rc
    export WINEPREFIX="$prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="

    log "creating Wine prefix (first run can take a minute)..."
    with_timeout 300 "$WINE_BIN" wineboot -i >/dev/null 2>&1
    out="$(with_timeout 60 "$WINE_BIN" cmd /c ver 2>&1 | tr -d '\r' | grep -i windows)"
    if [ -n "$out" ]; then
        result PASS "$label: Wine runs Windows programs ($out)"
    else
        result FAIL "$label: Wine could not run cmd.exe"
        return 1
    fi

    log "running d3d12probe (a green window should pulse for 3 seconds)..."
    env "$@" perl -e 'alarm shift; exec @ARGV' 120 "$WINE_BIN" "$PROBE" > "$WORK/probe-$label.log" 2>&1
    rc=$?
    out="$(tr -d '\r' < "$WORK/probe-$label.log")"
    echo "$out" | sed 's/^/    /' | tee -a "$REPORT"
    "$(dirname "$WINE_BIN")/wineserver" -k >/dev/null 2>&1
    if echo "$out" | grep -q "RESULT: D3D12 works"; then
        result PASS "$label: D3D12 renders"
    else
        result FAIL "$label: D3D12 probe failed (exit $rc)"
    fi
}

# ---------------------------------------------------------------------------
step "A: Game Porting Toolkit Wine (D3DMetal)"
log "D3DMetal is Apple software; see Apple's license in the download before using it."
if fetch_wine gptk Gcenx/game-porting-toolkit '\.tar\.(xz|gz)$'; then
    # MTL_HUD_ENABLED shows Apple's Metal performance HUD over the window.
    test_wine gptk MTL_HUD_ENABLED=1
else
    result FAIL "A: could not download/unpack the GPTK Wine"
fi

# ---------------------------------------------------------------------------
step "B: Upstream Wine (vkd3d + MoltenVK)"
if fetch_wine upstream Gcenx/macOS_Wine_builds 'devel.*osx64.*\.tar\.(xz|gz)$|osx64.*devel.*\.tar\.(xz|gz)$'; then
    test_wine upstream
else
    result FAIL "B: could not download/unpack upstream Wine"
fi

# ---------------------------------------------------------------------------
step "Summary"
printf "%s" "$RESULTS" | while IFS='|' read -r status msg; do
    [ -n "$status" ] && log "  $status  $msg"
done
log ""
log "Report saved to: $REPORT"
log "Paste its contents into the chat (e.g. run: pbcopy < \"$REPORT\")."

#!/bin/bash
# Compares D3D12 translation layers on top of a WineGDK build:
#   baseline  Wine's own dxgi/d3d11 + Wine's vkd3d (d3d12)
#   A         Wine's own dxgi/d3d11 + vkd3d-proton (d3d12, d3d12core)
#   B         DXVK (dxgi, d3d11)    + vkd3d-proton  <- what BedrockOnLinux ships
#
#   bash scripts/test-d3d12-backends.sh <winegdk-dir>
#
# Downloads the latest DXVK and vkd3d-proton releases (Windows DLLs, no build
# needed) into $MCB_WORK and runs tools/bin/d3d12probe.exe under each setup.
# Env: VKD3D_PROTON_TAG / DXVK_TAG to pin versions, GITHUB_TOKEN for the API.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=winegdk-env.sh
. "$REPO/scripts/winegdk-env.sh" "${1:?usage: test-d3d12-backends.sh <winegdk-dir>}"
WORK="${MCB_WORK:-$HOME/MCBedrockForMac-work}"
export WINEPREFIX="${WINEPREFIX:-$WORK/prefix-backends}"
mkdir -p "$WORK"

t() {   # timeout helper that keeps DYLD_* (see test-winegdk.sh)
    local s="$1"; shift
    perl -e 'alarm shift; exec @ARGV' "$s" \
        /usr/bin/env "DYLD_FALLBACK_LIBRARY_PATH=$DYLD_FALLBACK_LIBRARY_PATH" "$@"
}

# fetch <owner/repo> <tag|latest> <asset-regex> <dest-dir>  -> prints the tag
fetch() {
    local api json url name auth="X-No-Auth: 1"
    if [ "$2" = latest ]; then api="https://api.github.com/repos/$1/releases/latest"
    else api="https://api.github.com/repos/$1/releases/tags/$2"; fi
    # (A header string, not an array: macOS bash 3.2 + set -u rejects empty arrays.)
    [ -n "${GITHUB_TOKEN:-}" ] && auth="Authorization: Bearer $GITHUB_TOKEN"
    json="$(curl -fsSL -H "$auth" "$api")" || return 1
    read -r name url < <(osascript -l JavaScript -e '
        function run(a) { var r = JSON.parse(a[0]), re = new RegExp(a[1]);
            var x = r.assets.filter(function (s) { return re.test(s.name); })[0];
            return x ? x.name + " " + x.browser_download_url : "NONE NONE"; }' "$json" "$3")
    [ "$name" = NONE ] && return 1
    mkdir -p "$4"
    if [ ! -f "$4/.done-$name" ]; then
        curl -fsSL -o "$WORK/$name" "$url" || return 1
        case "$name" in
            *.zst) zstd -dc "$WORK/$name" | tar -x -C "$4" ;;
            *)     tar -xf "$WORK/$name" -C "$4" ;;
        esac || return 1
        touch "$4/.done-$name"
    fi
    osascript -l JavaScript -e 'function run(a) { return JSON.parse(a[0]).tag_name; }' "$json"
}

echo "== $(sw_vers -productVersion) $(uname -m), $(sysctl -n machdep.cpu.brand_string); $(wine --version)"

vkd3d_tag="$(fetch HansKristian-Work/vkd3d-proton "${VKD3D_PROTON_TAG:-latest}" '^vkd3d-proton-.*\.tar\.(zst|gz|xz)$' "$WORK/vkd3d-proton")" \
    || { echo "!! could not download vkd3d-proton"; exit 1; }
dxvk_tag="$(fetch doitsujin/dxvk "${DXVK_TAG:-latest}" '^dxvk-[0-9.]+\.tar\.gz$' "$WORK/dxvk")" \
    || { echo "!! could not download DXVK"; exit 1; }
echo "== vkd3d-proton $vkd3d_tag, DXVK $dxvk_tag"

t 300 wine wineboot -i >/dev/null 2>&1
SYS32="$WINEPREFIX/drive_c/windows/system32"
for f in d3d12.dll d3d12core.dll; do
    cp "$(find "$WORK/vkd3d-proton" -path '*/x64/*' -name "$f" | head -n1)" "$SYS32/$f"
done
for f in dxgi.dll d3d11.dll d3d10core.dll; do
    cp "$(find "$WORK/dxvk" -path '*/x64/*' -name "$f" | head -n1)" "$SYS32/$f"
done

# Logs from the translation layers go to stderr, so they land in the probe log.
export VKD3D_DEBUG=warn VKD3D_SHADER_DEBUG=none DXVK_LOG_LEVEL=info DXVK_LOG_PATH=none
export WINEDEBUG=err+all

results=""
run() {   # run <label> <overrides>
    local log="$WORK/backend-$1.log"
    echo
    echo "=== $1 (WINEDLLOVERRIDES=$2) ==="
    WINEDLLOVERRIDES="mscoree,mshtml=;$2" t 120 wine "$REPO/tools/bin/d3d12probe.exe" >"$log" 2>&1
    grep -v -E "validate_state_table|^\s*$" "$log" | tr -d '\r' | sed 's/^/    /' | tail -n 40
    if grep -q "RESULT: D3D12 works" "$log"; then results="$results  PASS  $1"$'\n'
    else results="$results  FAIL  $1"$'\n'; fi
    wineserver -k 2>/dev/null
}

run baseline "dxgi,d3d11,d3d10core,d3d12,d3d12core=b"
run A-vkd3d-proton "dxgi,d3d11,d3d10core=b;d3d12,d3d12core=n"
run B-dxvk+vkd3d-proton "dxgi,d3d11,d3d10core,d3d12,d3d12core=n"

echo
echo "=== Summary (vkd3d-proton $vkd3d_tag, DXVK $dxvk_tag) ==="
printf "%s" "$results"

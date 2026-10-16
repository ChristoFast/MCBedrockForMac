#!/bin/bash
# Milestone 1: build WineGDK (Wine + Xbox GDK runtime) for macOS.
#
#   bash scripts/build-winegdk-macos.sh
#
# Builds x86-64 Wine (runs under Rosetta 2 on Apple Silicon) from the commit
# pinned in third_party/winegdk.env, using the same configure options as the
# widely used Gcenx macOS Wine builds. Must run on an x86-64 Mac, or under
# `arch -x86_64` with an x86-64 Homebrew in /usr/local.
#
# Output: $MCB_WORK/dist/winegdk (a self-contained Wine prefix directory).
# Env: MCB_WORK (default ~/MCBedrockForMac-work), MCB_SKIP_BREW=1, MCB_JOBS.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${MCB_WORK:-$HOME/MCBedrockForMac-work}"
SRC="$WORK/winegdk-src"
BUILD="$WORK/winegdk-build"
DIST="$WORK/dist/winegdk"
JOBS="${MCB_JOBS:-$(sysctl -n hw.ncpu)}"

# shellcheck source=../third_party/winegdk.env
. "$REPO/third_party/winegdk.env"

echo "== Host: $(sw_vers -productVersion) $(uname -m), $JOBS jobs"
if [ "$(uname -m)" != "x86_64" ]; then
    echo "!! Run this on an Intel Mac or under 'arch -x86_64'." >&2
    exit 1
fi

# --- Dependencies ------------------------------------------------------------
if [ "${MCB_SKIP_BREW:-0}" != "1" ]; then
    echo "== Installing build dependencies (Homebrew)"
    export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
    brew install bison flex gettext pkgconf freetype gnutls sdl2 molten-vk vulkan-loader mingw-w64 ccache
fi
BREW="$(brew --prefix)"
export PATH="$BREW/opt/bison/bin:$BREW/opt/flex/bin:$PATH"
echo "bison: $(bison --version | head -n1)"
echo "mingw: $(x86_64-w64-mingw32-gcc --version | head -n1)"

# --- Source --------------------------------------------------------------------
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$WINEGDK_COMMIT" ]; then
    echo "== Fetching WineGDK $WINEGDK_COMMIT"
    rm -rf "$SRC"
    git init -q "$SRC"
    git -C "$SRC" remote add origin "$WINEGDK_REPO"
    git -C "$SRC" fetch -q --depth 1 origin "$WINEGDK_COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
fi

# Our macOS patches, applied in order (none yet; added as the port needs them).
if [ -d "$REPO/patches/winegdk" ]; then
    for p in "$REPO"/patches/winegdk/*.patch; do
        [ -e "$p" ] || continue
        if git -C "$SRC" apply --reverse --check "$p" 2>/dev/null; then
            echo "   already applied: $(basename "$p")"
        else
            echo "== Applying $(basename "$p")"
            git -C "$SRC" apply "$p"
        fi
    done
fi

# --- Configure -------------------------------------------------------------------
# Options follow Gcenx's MacPorts wine-devel Portfile: no X11/OpenGL (Vulkan via
# MoltenVK instead), CoreAudio, and both PE architectures for WoW64.
export MACOSX_DEPLOYMENT_TARGET=14.0
export CPPFLAGS="-I$BREW/include"
export LDFLAGS="-L$BREW/lib -Wl,-rpath,$BREW/lib"
export CROSSCFLAGS="-O2"
# ccache makes rebuilds after small changes take minutes instead of an hour.
if command -v ccache >/dev/null; then
    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache-mcb}" CCACHE_MAXSIZE=4G CCACHE_COMPILERCHECK=content
    export CC="ccache clang" CXX="ccache clang++"
    export x86_64_CC="ccache x86_64-w64-mingw32-gcc" i386_CC="ccache i686-w64-mingw32-gcc"
    ccache -z >/dev/null
fi
mkdir -p "$BUILD"
if [ ! -f "$BUILD/Makefile" ]; then
    echo "== Configuring"
    ( cd "$BUILD" && "$SRC/configure" \
        --prefix="$DIST" \
        --enable-archs=i386,x86_64 \
        --disable-tests \
        --disable-winebth_sys \
        --without-alsa --without-capi --with-coreaudio --with-cups \
        --without-dbus --without-ffmpeg --without-fontconfig --with-freetype \
        --with-gettext --without-gettextpo --without-gphoto --with-gnutls \
        --without-gssapi --without-gstreamer --without-krb5 --without-netapi \
        --with-opencl --without-opengl --without-oss --with-pcap \
        --with-pthread --without-pulse --without-sane --with-sdl \
        --without-udev --without-usb --without-v4l2 --with-vulkan \
        --without-wayland --without-x ) 2>&1 | tee "$WORK/winegdk-configure.log"
    # Surface what configure decided to leave out.
    grep -E "^configure: (WARNING|OpenCL|libvulkan|MoltenVK)" "$WORK/winegdk-configure.log" || true
fi

# --- Build ---------------------------------------------------------------------
echo "== Building (this takes a while)"
rc=0
make -C "$BUILD" -j"$JOBS" > "$WORK/winegdk-make.log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "!! build failed (exit $rc). First errors:" >&2
    grep -n -E "error:|Error [0-9]|undefined symbol|ld: " "$WORK/winegdk-make.log" | head -n 40 >&2 || true
    echo "--- last lines ---" >&2
    tail -n 40 "$WORK/winegdk-make.log" >&2
    exit 1
fi

command -v ccache >/dev/null && ccache -s | grep -E "Hits|Misses|Cache size" || true

echo "== Installing to $DIST"
rm -rf "$DIST"
make -C "$BUILD" install-lib >/dev/null

# --- Verify ----------------------------------------------------------------------
echo "== Verifying"
fail=0
for f in bin/wine bin/wineserver \
         lib/wine/x86_64-unix/ntdll.so \
         lib/wine/x86_64-windows/xgameruntime.dll \
         lib/wine/x86_64-windows/gameinput.dll \
         lib/wine/x86_64-windows/d3d12.dll \
         lib/wine/x86_64-unix/winevulkan.so \
         lib/wine/x86_64-windows/winemac.drv; do
    if [ -e "$DIST/$f" ]; then echo "   ok      $f"; else echo "   MISSING $f"; fail=1; fi
done
[ "$fail" = 0 ] || { echo "!! required files missing" >&2; exit 1; }

# Quick, non-fatal check on the build machine. The real test is
# scripts/test-winegdk.sh on Apple Silicon; GitHub's Intel VMs have no usable
# Metal GPU, so anything touching Vulkan can stall here.
echo "== Smoke test (non-fatal)"
export WINEPREFIX="$WORK/prefix-winegdk" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
"$DIST/bin/wine" --version
perl -e 'alarm shift; exec @ARGV' 180 "$DIST/bin/wine" wineboot -i >/dev/null 2>&1 \
    || echo "   wineboot did not finish in 180 s (exit $?)"
perl -e 'alarm shift; exec @ARGV' 60 "$DIST/bin/wine" cmd /c ver 2>/dev/null | tr -d '\r' \
    || echo "   cmd /c ver did not finish (exit $?)"
"$DIST/bin/wineserver" -k 2>/dev/null || true

echo "== Done: $DIST"

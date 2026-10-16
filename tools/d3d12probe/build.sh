#!/usr/bin/env bash
# Cross-compiles d3d12probe.exe on Linux (needs the mingw-w64 package).
# The result is committed to tools/bin/ so the Mac needs no Windows compiler.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../bin/d3d12probe.exe"
mkdir -p "$(dirname "$out")"
x86_64-w64-mingw32-g++ -O2 -std=c++17 -Wall \
    "$here/d3d12probe.cpp" -o "$out" \
    -static -static-libgcc -static-libstdc++ \
    -ld3d12 -ld3d11 -ldxgi -luser32 -lgdi32 -luuid -Wl,--subsystem,console
x86_64-w64-mingw32-strip "$out"
echo "built $out ($(wc -c < "$out") bytes)"

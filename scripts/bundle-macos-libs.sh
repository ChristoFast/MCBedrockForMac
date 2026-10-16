#!/bin/bash
# Copies the Homebrew libraries a Wine build needs into <dist>/lib/external, so
# the build runs on Macs without (x86-64) Homebrew.
#
#   bash scripts/bundle-macos-libs.sh <dist-dir>
#
# Wine links some libraries directly and dlopen()s others by name (FreeType,
# GnuTLS, SDL2, Vulkan/MoltenVK). Both kinds are found at runtime through
# DYLD_FALLBACK_LIBRARY_PATH, which scripts/winegdk-env.sh sets.

set -euo pipefail

DIST="${1:?usage: bundle-macos-libs.sh <dist-dir>}"
EXT="$DIST/lib/external"
BREW="$(brew --prefix)"
mkdir -p "$EXT"

# Libraries Wine loads with dlopen(), so otool can't see them. Homebrew's SDL2 is
# sdl2-compat, which itself dlopen()s SDL3; without it, SDL2's initializer shows an
# error dialog off the main thread and macOS kills winebus (the controller service).
DLOPENED="libfreetype.6.dylib libgnutls.30.dylib libSDL2-2.0.0.dylib libSDL3.0.dylib libvulkan.1.dylib libMoltenVK.dylib"

# Prints the Homebrew dependencies of a Mach-O file.
brew_deps() {
    otool -L "$1" 2>/dev/null | awk 'NR>1 {print $1}' | grep -E "^($BREW|@rpath/)" || true
}

# Resolves a dependency reference to a real file under Homebrew.
resolve() {
    case "$1" in
        @rpath/*) find "$BREW/lib" "$BREW/opt" -maxdepth 3 -name "${1#@rpath/}" 2>/dev/null | head -n1 ;;
        *) echo "$1" ;;
    esac
}

queue=""
for name in $DLOPENED; do
    f="$(find "$BREW/lib" "$BREW/opt" -maxdepth 3 -name "$name" 2>/dev/null | head -n1)"
    if [ -n "$f" ]; then queue="$queue $f"; else echo "   (not found: $name)"; fi
done
while IFS= read -r -d '' f; do
    if file "$f" | grep -q "Mach-O"; then
        for d in $(brew_deps "$f"); do queue="$queue $(resolve "$d")"; done
    fi
done < <(find "$DIST/bin" "$DIST/lib/wine" -type f -print0)

seen=" "
while [ -n "${queue// /}" ]; do
    # shellcheck disable=SC2086  # deliberate word splitting of the queue
    set -- $queue
    lib="$1"; shift; queue="$*"
    [ -n "$lib" ] || continue
    base="$(basename "$lib")"
    case "$seen" in *" $base "*) continue ;; esac
    seen="$seen$base "
    real="$(cd "$(dirname "$lib")" && pwd -P)/$(basename "$lib")"
    cp -L "$real" "$EXT/$base"
    chmod u+w "$EXT/$base"
    echo "   bundled $base"
    for d in $(brew_deps "$real"); do queue="$queue $(resolve "$d")"; done
done

# Point the Vulkan loader at the bundled MoltenVK.
cat > "$EXT/MoltenVK_icd.json" <<'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "./libMoltenVK.dylib",
        "api_version": "1.4.0",
        "is_portability_driver": true
    }
}
EOF
echo "== Bundled $(find "$EXT" -name '*.dylib' | wc -l | tr -d ' ') libraries into $EXT"

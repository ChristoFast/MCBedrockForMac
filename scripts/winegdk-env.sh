#!/bin/bash
# Source this to use a WineGDK build from this repo:
#
#   . scripts/winegdk-env.sh /path/to/winegdk
#   wine winecfg
#
# Sets PATH, the bundled-library search path, the MoltenVK Vulkan driver, and the
# Vulkan renderer (wined3d's OpenGL path doesn't work on macOS without X11/GL).

WINEGDK_DIST="$(cd "${1:?usage: . winegdk-env.sh <winegdk-dir>}" && pwd)"
export WINEGDK_DIST
export PATH="$WINEGDK_DIST/bin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="$WINEGDK_DIST/lib/external:/usr/lib"
export VK_ICD_FILENAMES="$WINEGDK_DIST/lib/external/MoltenVK_icd.json"
export WINE_D3D_CONFIG="${WINE_D3D_CONFIG:-renderer=vulkan}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"

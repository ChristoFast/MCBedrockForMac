# WineGDK patches

Applied in filename order by `scripts/build-winegdk-macos.sh` to the commit pinned in
`third_party/winegdk.env`.

| Patch | From | What |
|---|---|---|
| `0001-win32u-enable-vulkan-portability-enumeration` | Gcenx's macOS Wine builds | Lets the Vulkan loader expose MoltenVK; without it D3D12 fails on macOS |
| `bol-0002` … `bol-0011` | [BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux) `third_party/winegdk-native5`, unchanged | Fixes BedrockOnLinux ships on the same WineGDK commit: file pickers, Achievements token, COM context callback, honest XStore answers, **`WINE_DLL_FILE_MAP` loader (0007/0008, needed by `xodus-cli run`)**, XSystem interfaces. 0005 (X11) and 0011 (Wayland) touch drivers we don't build and are carried only to stay in step. |

BedrockOnLinux's own `0001` describes the delta already contained in the pinned commit, so it isn't carried.
All patches modify LGPL-2.1+ Wine and are LGPL-2.1+.

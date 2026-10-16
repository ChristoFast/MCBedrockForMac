# Build plan

Goal: run the Windows (GDK) version of Minecraft Bedrock natively on macOS on Apple Silicon, for free,
with Xbox sign-in working.

## Prior art we build on

| Project | What it gives us | License |
|---|---|---|
| [Weather-OS/WineGDK](https://github.com/Weather-OS/WineGDK) | A Wine fork that implements the Xbox GDK runtime (`xgameruntime`, `gameinput`, Xbox identity). This is what makes the Windows Bedrock run outside Windows at all. | LGPL |
| [Wyze3306/BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux) | A complete Linux launcher: Microsoft sign-in, Store download (via `xodus`), Wine prefix setup, fixes, game launch. Mostly Python, so much of it ports. | MIT |
| [jphein/minecraft-bedrock-linux](https://github.com/jphein/minecraft-bedrock-linux) | Detailed notes on what breaks and why (stub DLLs, XCurl, GameInput, renderer races). | AGPL |
| Wine for macOS (Gcenx builds, CrossOver sources) | Proven Wine-on-macOS packaging, including running x86-64 Windows code through Rosetta 2. | LGPL |

BedrockOnLinux has already solved downloading the game and Xbox sign-in. The new work is making that stack run
on **macOS** and getting **graphics** onto Metal.

## How it works

```
┌──────────────────────── MCBedrockForMac launcher (Python CLI → later a native app) ───┐
│ 1. Microsoft sign-in      2. Store download (xodus)      3. Wine prefix setup         │
│ 4. Mac-specific fixes     5. Launch                                                   │
└───────────────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
Minecraft.Windows.exe (x86-64)  ──►  WineGDK (x86-64, macOS build)  ──►  Rosetta 2
        │ D3D12
        ▼
Graphics translation ── Option A: D3DMetal (Apple Game Porting Toolkit) ──► Metal
                     └─ Option B: vkd3d-proton → Vulkan → KosmicKrisp / MoltenVK ──► Metal
```

## Milestones

Each milestone ends with something you can run on your Mac and report back on.

### M0: Prove the foundation
Run `bash scripts/m0-check.sh` on the Mac. It:
- [ ] checks Rosetta 2 (and offers to install it);
- [ ] downloads two free prebuilt Wine builds into `~/MCBedrockForMac-work`: the Game Porting Toolkit Wine
      (with Apple's D3DMetal) and upstream Wine (vkd3d + MoltenVK);
- [ ] runs our own D3D12 test program (`tools/d3d12probe`) through each.
- **Exit:** at least one D3D12 path renders on your M5. That decides the graphics route for M3.
- **Result on GitHub's M1 VM (2026-10-16):** Rosetta ✅, both Wines run programs ✅.
  Upstream Wine 11.18 + vkd3d + MoltenVK renders D3D12 ✅ (with `WINE_D3D_CONFIG=renderer=vulkan`;
  feature level 11_0, shader model 6.0, binding tier 1). D3DMetal refuses VM GPUs, so it's untested until a real Mac.

### M1: Build WineGDK for macOS
- [x] `scripts/build-winegdk-macos.sh` + `.github/workflows/build-winegdk.yml`: builds WineGDK (pinned in
      `third_party/winegdk.env`) as x86-64 on GitHub's Intel Mac runner, with ccache for fast rebuilds.
- [x] First build (2026-10-16): **the whole of WineGDK compiles on macOS with no source changes**, including
      `xgameruntime.dll` and `gameinput.dll`. (~65 min cold.)
- [x] Bundle the Homebrew libraries (`scripts/bundle-macos-libs.sh`) and publish the build as an artifact
      (`winegdk-macos-x86_64`, ~79 MB). Rebuilds take ~15 min thanks to ccache.
- [x] Patch: `patches/winegdk/0001` enables Vulkan portability enumeration, without which the Vulkan loader
      hides MoltenVK and DXGI/D3D12 fail (`VK_ERROR_INCOMPATIBLE_DRIVER`).
- [x] **Passed on Apple Silicon under Rosetta (2026-10-16, GitHub M1 VM):** Windows programs run,
      `xgameruntime.dll` and `gameinput.dll` load, D3D12 renders (164 frames / 3 s).
      Caveats from the VM GPU: D3D12 feature level 11_0, shader model 6.0, binding tier 1; D3D11 only 9_3.
      These need re-checking on a real Mac; BedrockOnLinux uses vkd3d-proton (not Wine's vkd3d) for D3D12,
      which we'll likely need too.
- [ ] Later, for performance: Linux `ntsync` doesn't exist on macOS; Wine falls back to server-side sync,
      which BedrockOnLinux found makes Minecraft's threads slow. macOS needs an `msync`-style fast path.
- **Exit:** a WineGDK build that passes `test-winegdk.sh` on Apple Silicon. ✅ **Done.**

### Graphics route findings (2026-10-16)
`scripts/test-d3d12-backends.sh` (workflow *Graphics backends*) on GitHub's M1 VM with our WineGDK build:

| Setup | Result | Blocker |
|---|---|---|
| Wine dxgi/d3d11 + Wine vkd3d (d3d12) | ✅ renders | (feature level 11_0, binding tier 1 on the VM GPU) |
| Wine dxgi + **vkd3d-proton 3.0.1** | ❌ | needs transform feedback (Metal has none) |
| **DXVK 3.1.1** + vkd3d-proton (BedrockOnLinux's stack) | ❌ | needs geometry shaders (Metal has none) |

So the Linux graphics stack does not work on MoltenVK. Routes for Minecraft's D3D12:
1. **Wine's vkd3d** (works today). Unknown: whether Bedrock accepts its feature set. Found out in M3.
2. **D3DMetal** (Apple GPTK; what CrossOver uses). Needs a real Mac to test, and its Wine-side glue
   must match our Wine version.
3. **KosmicKrisp** (LunarG's conformant Vulkan 1.4 driver on Metal). Geometry/tessellation support is in
   progress; once it lands, DXVK/vkd3d-proton may work. Re-run the backend test then.

Side finding: `winebus.so` crashes (`NSException`) while loading SDL2 at startup, so the controller
service fails. Fix before M4 (e.g. disable winebus's SDL backend and use its IOHID one).

### M2: Get the game files
- [x] Build `xodus-cli` natively for Apple Silicon (`scripts/build-xodus-macos.sh`, workflow *Build xodus*),
      pinned commit + BedrockOnLinux's 7 patches. First build passed (2026-10-16, ~5 min, arm64 Mach-O).
      xodus already supports macOS: Keychain token storage, WKWebView sign-in, and `run` decrypts the
      protected segments into an `hdiutil` RAM disk.
- [x] Launcher `./mcb` (setup, login, install, play, doctor, selftest). `setup` installs from the public
      **nightly release** (`release-nightly.yml` publishes the latest passing WineGDK + xodus builds with SHA256SUMS).
      Workflow *Test launcher* runs setup/doctor/selftest on Apple Silicon: passed 2026-10-16.
      `play` = `xodus-cli run <game> <wine>`: license fetch, decrypt protected segments to a RAM disk, start Wine
      with `WINE_DLL_FILE_MAP`. Login/install/play never run in CI (public logs; no game files in artifacts).
- [ ] First real sign-in + download on a real Mac (needs the owner's Microsoft account).
- **Exit:** Minecraft for Windows is downloaded to your Mac with your account.

### M3: First launch (the big one)
Known requirements, from BedrockOnLinux / GDK-Proton:
- [x] WineGDK `WINE_DLL_FILE_MAP` loader (BedrockOnLinux patches 0007/0008, now carried) so `xodus-cli run` works.
- [ ] `xgameruntime.dll.threading`: Microsoft's native XGameRuntime, loaded by WineGDK's `xgameruntime.dll`.
      Not redistributable by us; fetch at setup from GDK-Proton's public `release10-32` archive (BedrockOnLinux
      pins its SHA-256 `4c3e3faf…`) into the prefix's `system32`.
- [ ] XCurl replacement: the game's own `XCurl.dll` doesn't work under Wine. Replace it with MinGW libcurl + its
      DLLs + a CA bundle (BedrockOnLinux's "OpenSSL-XCurl set", built from pinned msys2 packages + `xcurl-cashim`).
      Pure Windows DLLs, so it can be built on Linux CI.
- [ ] BedrockOnLinux's game fixups worth porting (`bol/fixups.py`): PE stack-reserve enlargement, Classic
      renderer (`graphics_mode:0`) on first run, `GameInputRedist` stub handling.
- [ ] D3D12 via Wine vkd3d (see *Graphics route findings*); if Bedrock rejects it, try D3DMetal on a real Mac.
- **Exit:** the Minecraft title screen renders on your Mac.

### M4: Playable
- [ ] Keyboard and mouse capture, trackpad scrolling, Retina scaling, full screen.
- [ ] Xbox sign-in, Friends, servers, Realms.
- [ ] Performance tuning for the M5 (resolution scale, frame cap on battery).
- **Exit:** a full survival session with friends.

### M5: A real Mac app
- [ ] One-click `.app` launcher (SwiftUI, or the Python launcher packaged as an app).
- [ ] Auto-update for the launcher and the game; `doctor` and `repair` commands.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| WineGDK has never been built for macOS | M1 may need real Wine porting work | Start from Gcenx/CrossOver's macOS patches; ask WineGDK maintainers |
| D3D12 on Mac: vkd3d-proton needs Vulkan features MoltenVK lacks | Graphics may not work via Option B | Use D3DMetal first. KosmicKrisp is a newer, more complete Vulkan driver for Apple GPUs |
| D3DMetal's license doesn't allow redistributing it | Can't bundle it in our app | The launcher points to Apple's free download and installs it from your copy |
| Apple is winding down Rosetta 2 after macOS 27, except for some games | Long-term, x86-64 Wine may stop working | Watch Apple's plans; Wine's ARM64EC/FEX work is the long-term exit |
| Game updates break things | Launcher breaks occasionally | Let the user pin a known-good game version (BedrockOnLinux already supports this) |
| Running a Store download outside Windows is a gray area in Microsoft's terms | Account risk is low but nonzero | Only ever use your own account and license; never redistribute game files |

## Development loop

- Code is written in this repo.
- Windows-side pieces (test programs, stub DLLs) are cross-compiled on Linux and committed under `tools/bin/`.
- Mac-side pieces are built and tested on GitHub's Apple Silicon runners (free for public repos). Those are VMs with a
  limited virtual GPU, so graphics results must still be confirmed on a real Mac.
- Each check writes a report, uploaded as a workflow artifact, which drives the next change.

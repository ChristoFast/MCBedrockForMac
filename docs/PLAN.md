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
- [ ] A GitHub Actions workflow on a **macOS arm64 runner** that builds WineGDK as x86-64 (for Rosetta).
      The repo is public, so these runs are free.
- [ ] Publish the build as a downloadable artifact.
- [ ] Fix the Linux-only parts (WineGDK uses Linux `ntsync`; macOS needs Wine's fallback sync or `msync`).
- **Exit:** a WineGDK build that starts `winecfg` on your Mac.

### M2: Get the game files
- [ ] Build the `xodus` Store downloader for macOS (BedrockOnLinux uses it to fetch the game under your account).
- [ ] Port the launcher's sign-in and download code, starting from BedrockOnLinux's `bol/auth.py` and `bol/games.py`.
- **Exit:** Minecraft for Windows is downloaded to your Mac with your account.

### M3: First launch (the big one)
- [ ] Set up the Wine prefix: GDK runtime, GameInput stubs, XCurl networking, the stub DLLs from BedrockOnLinux's `src/`.
- [ ] Wire D3D12 to D3DMetal (Option A). If that fails, try vkd3d-proton on KosmicKrisp (Option B).
- [ ] Force the Classic renderer first; it's the most reliable under Wine.
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

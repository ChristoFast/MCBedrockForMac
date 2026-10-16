# MCBedrockForMac

A free, open-source launcher that runs **Minecraft: Bedrock Edition for Windows** on Apple Silicon Macs
(built for an M5 MacBook Pro), with no virtual machine and no paid software.

> **Status:** milestones 0-1 done, milestone 2 built (launcher + downloader). Next: first launch on a real Mac (milestone 3). Nothing is playable yet. See **[docs/PLAN.md](docs/PLAN.md)** for how it will work and the milestones.

## The idea

Linux players can now run the real Windows Bedrock, with Xbox sign-in, Friends, servers and Realms,
thanks to [WineGDK](https://github.com/Weather-OS/WineGDK) and the MIT-licensed
[BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux) launcher. This project brings that same stack to macOS:

```
Minecraft for Windows (x86-64, D3D12)    ← downloaded from the Microsoft Store with your own account
        │
   WineGDK (Wine + Xbox GDK runtime)     ← built for macOS
        │
   Rosetta 2                             ← runs the x86-64 code on Apple Silicon
        │
   D3D12 → Metal translation             ← Apple's D3DMetal, or vkd3d-proton on KosmicKrisp
        │
   macOS + Apple GPU
```

## Requirements

- An Apple Silicon Mac (M1 or later).
- A Microsoft account that owns Minecraft for Windows. Java Edition owners have it: it's the
  "Java & Bedrock Edition for PC" bundle.

## Want to play right now?

[docs/VM_FALLBACK.md](docs/VM_FALLBACK.md) shows how to run Bedrock today in a free Windows 11 ARM VM.

## Credits and legal

This project builds on WineGDK (LGPL), BedrockOnLinux (MIT) and Wine (LGPL). It is not affiliated with Mojang or
Microsoft. It never distributes the game; you download it under your own license.

## Try it (on an Apple Silicon Mac)

> Not playable yet: the first real launch (milestone 3) still needs testing on a real Mac.

```bash
git clone https://github.com/ChristoFast/MCBedrockForMac.git
cd MCBedrockForMac
./mcb setup      # downloads the engine (WineGDK) + xodus from the nightly release, creates the Wine prefix
./mcb doctor     # checks everything is in place
./mcb selftest   # runs Windows programs, loads the Xbox runtime, renders D3D12
./mcb login      # sign in with the Microsoft account that owns Minecraft
./mcb install    # downloads Minecraft for Windows from the Microsoft Store (~1-2 GB)
./mcb play       # starts the game
```

Everything lives in `~/Library/Application Support/MCBedrockForMac` (`./mcb paths`). Sign-in tokens are kept
in the macOS Keychain by xodus. `./mcb install preview` / `./mcb play preview` use Minecraft Preview.

The older foundation check is still available: `bash scripts/m0-check.sh`.

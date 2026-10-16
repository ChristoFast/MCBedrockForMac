# MCBedrockForMac

A free, open-source launcher that runs **Minecraft: Bedrock Edition for Windows** on Apple Silicon Macs
(built for an M5 MacBook Pro), with no virtual machine and no paid software.

> **Status:** milestone 0 (foundation check). Nothing is playable yet. See **[docs/PLAN.md](docs/PLAN.md)** for how it will work and the milestones.

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

## Try milestone 0

On your Mac, in Terminal:

```bash
git clone https://github.com/ChristoFast/MCBedrockForMac.git
cd MCBedrockForMac
bash scripts/m0-check.sh
```

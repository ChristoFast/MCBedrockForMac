# Fallback: play today in a free Windows VM

Play **Minecraft: Bedrock Edition** on an Apple Silicon MacBook (built for an M5 MacBook Pro), **for $0**.

Mojang doesn't make Bedrock for macOS. This repo uses the most reliable workaround: run the
**Windows version you already own** inside a free Windows 11 ARM virtual machine (VM).

| Piece | Free option |
|---|---|
| Minecraft Bedrock | Already included with Java Edition ("Java & Bedrock Edition for PC") |
| VM app | **VMware Fusion Pro**, free for personal use |
| Windows | **Windows 11 Insider Preview for ARM**, free with a Microsoft account |

> **Status:** not yet tested on an M5. Fill in the [test log](#test-log) as you go.

---

## 0. Before you start

- [ ] **Confirm you own Bedrock for Windows.** Sign in at <https://www.minecraft.net> → Profile.
      "Minecraft: Java & Bedrock Edition for PC" means you're set.
- [ ] **Know which Microsoft account owns it.** You'll sign into Windows/Xbox with that same account.
- [ ] **Free disk space:** about 64 GB for the VM.

## 1. Install VMware Fusion Pro (free)

1. Create a free account on the **Broadcom support portal** (<https://support.broadcom.com>).
2. Download **VMware Fusion Pro** and install it. When asked for a license, choose
   **"Use Fusion Pro for Personal Use"**.

> Skip Parallels (paid) and UTM (free, but its 3D support is too weak for games).

## 2. Get Windows 11 for ARM (free)

**Option A: Windows Insider Preview (recommended, free and legitimate)**

1. Join the Windows Insider Program at <https://www.microsoft.com/windowsinsider> with your Microsoft account.
2. Download the **Windows 11 Insider Preview ARM64** ISO (Insider downloads page). Pick the **Beta** or
   **Release Preview** channel for stability.
3. Insider builds expire after a while. Keep Windows Update on and they renew themselves.

**Option B: Regular Windows 11 ARM64 ISO without a product key**

Download it from <https://www.microsoft.com/software-download/windows11arm64> and pick
**"I don't have a product key"** during setup. It installs and runs, but shows an
"Activate Windows" watermark and locks personalization settings. Microsoft's license terms still expect
a license, so Option A is the cleaner free route.

Then in Fusion: **File → New → Install from disc or image**, choose the ISO, and enable
**TPM / encryption** when Fusion asks (Windows 11 requires it).

## 3. Recommended VM settings (M5 MacBook Pro)

| Setting | Value | Why |
|---|---|---|
| CPU cores | 4–6 | Leaves cores free for macOS |
| Memory | 8 GB (12 GB if you have 24 GB or more) | Bedrock + Windows are comfortable at 8 GB |
| Disk | 64 GB or more | Windows updates are large |
| Display → Accelerate 3D Graphics | **On** | Required, or Minecraft won't start or will run very slowly |
| Shared graphics memory | Max available | Better chunk rendering |
| Display → "Use full resolution for Retina display" | **Off** at first | Big FPS win. Turn it on later if FPS allows |

After Windows installs:

- Install **VMware Tools** (VM menu → Install VMware Tools). This provides the graphics driver.
- Run **Windows Update** until nothing is left. Graphics fixes arrive this way.

## 4. Install Minecraft Bedrock

1. In Windows, install the **Xbox app** from the Microsoft Store.
2. Sign in with the Microsoft account that owns Minecraft.
3. Install **Minecraft for Windows**, which is Bedrock. (Or install the **Minecraft Launcher**, which can launch both Java and Bedrock.)
4. Launch it. If you reach the title screen with music, you're through the hard part.

## 5. Make it feel like a Mac app (optional)

- Put the VM in full screen (⌘ + Ctrl + F) on its own macOS Space, and swipe with three fingers to switch.
- A future goal for this repo: a free one-click macOS launcher script that boots the VM (via Fusion's
  built-in `vmrun` tool) and starts Minecraft.

## Performance tips

- Plug in. macOS throttles the VM on battery.
- In Minecraft: lower **Render Distance** (8–12 chunks), turn **Fancy Graphics** off, and leave Vibrant Visuals / RTX off.
- Close heavy Mac apps (browsers with lots of tabs) while playing.
- Mouse feels floaty or escapes the window? Use full screen, and in Fusion settings → Keyboard & Mouse,
  turn on game-style mouse capture.

## Troubleshooting

| Problem | Try |
|---|---|
| Fusion won't create the Windows 11 VM | Turn on TPM / encryption in the new-VM wizard |
| Minecraft won't install or says "not available for this device" | Use the **Xbox app** instead of the Store page; make sure Windows is fully updated |
| Crashes on launch or black screen | Confirm 3D acceleration is on and VMware Tools is installed; update Windows |
| Very low FPS | Lower the VM's display resolution, turn Retina off, lower render distance |
| Can't sign in to Xbox | Check the Windows clock and time zone; sign out and back in on the Xbox app |
| Insider build says it's expiring | Run Windows Update to move to the newest Insider build |
| Can't find friends' worlds or LAN games | Set the VM network to **Bridged** instead of NAT |

## Free fallback if Bedrock won't run in the VM

If you mainly want Bedrock to **play with friends on consoles or phones**, you can stay on
**Java Edition, which runs natively on your Mac**, and host a free Java server with
[Geyser](https://geysermc.org/). Geyser lets Bedrock players join a Java server, so your friends join
from Bedrock while you play Java. It runs on your Mac at no cost.

(The iOS and Android versions of Bedrock can also run on Macs via PlayCover or mcpelauncher, but they require
buying the game again on those stores, so they're out of scope for this repo.)

---

## Test log

Fill this in as you try things, so this guide reflects what actually works on an M5.

| Date | macOS | Fusion version | Windows build | Minecraft version | Result / FPS / notes |
|---|---|---|---|---|---|
| | | | | | |

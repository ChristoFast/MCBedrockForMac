# MCBedrockForMac

Play **Minecraft: Bedrock Edition** on an Apple Silicon MacBook (built for an M5 MacBook Pro).

Mojang doesn't make Bedrock for macOS. This repo uses the most reliable workaround: run the
**Windows version you already own** inside a Windows 11 ARM virtual machine (VM).

> **Status:** not yet tested on an M5. Fill in the [test log](#test-log) as you go.

---

## 0. Before you start

- [ ] **Confirm you own Bedrock for Windows.** Sign in at <https://www.minecraft.net> → Profile.
      "Minecraft: Java & Bedrock Edition for PC" means you're set.
- [ ] **Know which Microsoft account owns it.** You'll sign into Windows/Xbox with that same account.
- [ ] **Free disk space:** about 64 GB for the VM.
- [ ] **A Windows 11 license** to activate Windows (Pro is the edition Microsoft supports in a VM on Apple Silicon).

## 1. Pick a VM app

| App | Cost | 3D for games | Notes |
|---|---|---|---|
| **VMware Fusion Pro** | Free for personal use | Good | Download from the Broadcom support portal (needs a free account). **Start here.** |
| **Parallels Desktop** | Paid subscription | Best | Microsoft-authorized for Windows 11 ARM. "Coherence" mode can make Minecraft look like a normal Mac app. Has a free trial, so try it if Fusion struggles. |
| UTM | Free | Weak | Not good enough for games. Skip it. |

## 2. Get Windows 11 for ARM

- **Parallels:** the setup wizard downloads Windows 11 for you automatically.
- **VMware Fusion:** download the **Windows 11 ARM64 ISO** from Microsoft
  (<https://www.microsoft.com/software-download/windows11arm64>), then create a new VM from that ISO.

## 3. Recommended VM settings (M5 MacBook Pro)

| Setting | Value | Why |
|---|---|---|
| CPU cores | 4–6 | Leaves cores free for macOS |
| Memory | 8 GB (12 GB if you have 24 GB or more) | Bedrock + Windows are comfortable at 8 GB |
| Disk | 64 GB or more | Windows updates are large |
| 3D acceleration | **On** | Required, or Minecraft won't start or will run very slowly |
| Graphics memory (Fusion) | Max available | Better chunk rendering |
| Display | Retina/high-res **off** at first | Big FPS win. Turn it on later if FPS allows |
| Power (Parallels) | "Gaming" profile | Prioritizes the VM |

After Windows installs:

- **Fusion:** install **VMware Tools** (VM menu → Install VMware Tools). This provides the graphics driver.
- **Parallels:** Parallels Tools installs automatically.
- Run **Windows Update** until nothing is left. Graphics fixes arrive this way.

## 4. Install Minecraft Bedrock

1. In Windows, install the **Xbox app** from the Microsoft Store.
2. Sign in with the Microsoft account that owns Minecraft.
3. Install **Minecraft for Windows**, which is Bedrock. (Or install the **Minecraft Launcher**, which can launch both Java and Bedrock.)
4. Launch it. If you reach the title screen with music, you're through the hard part.

## 5. Make it feel like a Mac app (optional)

- **Parallels:** turn on Coherence mode, then right-click Minecraft in the Dock → *Options → Keep in Dock*.
  You now launch it like any Mac app.
- **Fusion:** use full-screen mode on its own macOS Space. Swipe with three fingers to switch.
- A future goal for this repo: a one-click macOS launcher script that boots the VM and starts Minecraft.

## Performance tips

- Plug in. macOS throttles the VM on battery.
- In Minecraft: lower **Render Distance** (8–12 chunks), turn **Fancy Graphics** off, and leave Vibrant Visuals / RTX off.
- Close heavy Mac apps (browsers with lots of tabs) while playing.
- Mouse feels floaty? In the VM settings, set the mouse to **"Optimize for games"** (Parallels) or turn on game-style mouse capture (Fusion).

## Troubleshooting

| Problem | Try |
|---|---|
| Minecraft won't install or says "not available for this device" | Use the **Xbox app** instead of the Store page; make sure Windows is fully updated |
| Crashes on launch or black screen | Confirm 3D acceleration is on and VMware/Parallels Tools are installed; update Windows |
| Very low FPS | Lower the VM's display resolution, turn Retina off, lower render distance |
| Can't sign in to Xbox | Check the Windows clock and time zone; sign out and back in on the Xbox app |
| Mouse escapes the window | Use full screen, and turn on game-mode mouse capture in VM settings |
| Can't find friends' worlds or LAN games | Set the VM network to **Bridged** instead of NAT |

If Bedrock simply refuses to run in the VM, open an issue in this repo with your Windows build,
VM app and version, and the error. The fallbacks are the iOS app via PlayCover
([mcbe-macos](https://github.com/Erkam246/mcbe-macos)), which needs a separate iOS purchase,
or playing Java Edition natively with friends on a [Geyser](https://geysermc.org/) server.

---

## Test log

Fill this in as you try things, so this guide reflects what actually works on an M5.

| Date | macOS | VM app + version | Windows build | Minecraft version | Result / FPS / notes |
|---|---|---|---|---|---|
| | | | | | |

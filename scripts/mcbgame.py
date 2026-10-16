#!/usr/bin/env python3
"""Game preparation for MCBedrockForMac, called by ./mcb.

    mcbgame.py fetch    <components-dir>
    mcbgame.py prepare  <game-dir> <prefix> <engine-dir> <components-dir> <reg-out>

`fetch` downloads the third-party runtime pieces listed in
third_party/components.json from their original sources and checks each
against its pinned SHA-256.

`prepare` applies them before a launch: the Xbox-Live DLLs and OpenSSL XCurl
into the game folder, the libHttpClient XCurl-provider patch, CA bundles, the
cryptbase RNG stub and Microsoft GameInput into the prefix, and
xgameruntime.dll.threading into the engine. It writes the registry changes to
<reg-out> for `wine regedit /S` (run by mcb, so Wine keeps its library path).

Most of this is ported from BedrockOnLinux (MIT, (c) 2026 BedrockOnLinux
contributors): bol/fixups.py, bol/gameinput.py, bol/auth.py
(wine_apply_winegdk_prereqs). Python 3.9+ standard library only, since macOS's
/usr/bin/python3 is what runs it.
"""

import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
COMPONENTS = json.loads((REPO / "third_party" / "components.json").read_text())


def say(msg):
    print(f"  {msg}", flush=True)


def warn(msg):
    print(f"  [warn] {msg}", flush=True)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def matches(path, expected):
    try:
        return Path(path).is_file() and sha256(path) == expected
    except OSError:
        return False


# --- fetch -------------------------------------------------------------------
# Downloads go through /usr/bin/curl, which uses the macOS trust store.

def curl(url, dest):
    tmp = Path(str(dest) + ".part")
    subprocess.run(["curl", "-fL", "--retry", "3", "--progress-bar", "-o", str(tmp), url], check=True)
    tmp.replace(dest)


def curl_json(url):
    cmd = ["curl", "-fsSL", "--retry", "4", "--retry-all-errors", "--retry-delay", "2",
           "-H", "Accept: application/vnd.github+json"]
    if os.environ.get("GITHUB_TOKEN"):   # optional; avoids the anonymous rate limit
        cmd += ["-H", "Authorization: Bearer " + os.environ["GITHUB_TOKEN"]]
    out = subprocess.run(cmd + [url], check=True, capture_output=True).stdout
    return json.loads(out)


def fetch_pinned(url, dest, expected, label):
    if matches(dest, expected):
        say(f"{label}: ok (cached)")
        return
    say(f"{label}: downloading")
    curl(url, dest)
    if not matches(dest, expected):
        Path(dest).unlink(missing_ok=True)
        sys.exit(f"mcb: {label} does not match its pinned SHA-256; not installed")
    say(f"{label}: ok")


def release_asset_url(repo, asset):
    """Finds an asset across all of a repo's releases (it stays in the release it
    was first uploaded to, which may not be the newest)."""
    page = 1
    while page < 40:
        rels = curl_json(f"https://api.github.com/repos/{repo}/releases?per_page=20&page={page}")
        if not rels:
            break
        for rel in rels:
            for a in rel.get("assets", []):
                if a["name"] == asset:
                    return a["browser_download_url"]
        page += 1
    return None


def fetch_threading(comp_dir):
    c = COMPONENTS["xgameruntime_threading"]
    dest = comp_dir / "xgameruntime.dll.threading"
    if matches(dest, c["sha256"]):
        say("xgameruntime.dll.threading: ok (cached)")
        return
    say("xgameruntime.dll.threading: streaming it out of the GDK-Proton archive (large download, one time)")
    # Stream the archive and stop at the one member we need; the member's own
    # pinned hash is what's verified.
    proc = subprocess.Popen(["curl", "-fsSL", c["url"]], stdout=subprocess.PIPE)
    found = False
    try:
        with tarfile.open(fileobj=proc.stdout, mode="r|gz") as tar:
            for m in tar:
                if m.isfile() and m.name.endswith(c["member_suffix"]):
                    with tar.extractfile(m) as src, open(str(dest) + ".part", "wb") as out:
                        shutil.copyfileobj(src, out)
                    found = True
                    break
    finally:
        proc.kill()
        proc.wait()
    if not found:
        sys.exit("mcb: xgameruntime.dll.threading not found in the GDK-Proton archive")
    Path(str(dest) + ".part").replace(dest)
    if not matches(dest, c["sha256"]):
        dest.unlink(missing_ok=True)
        sys.exit("mcb: xgameruntime.dll.threading does not match its pinned SHA-256")
    say("xgameruntime.dll.threading: ok")


def fetch_xcurl_set(comp_dir):
    c = COMPONENTS["openssl_xcurl_set"]
    archive = comp_dir / c["asset"]
    setdir = comp_dir / "openssl-xcurl-set"
    if not matches(archive, c["sha256"]):
        url = c.get("url")
        if not url:
            say("OpenSSL XCurl set: looking up the release")
            url = release_asset_url(c["repo"], c["asset"])
            if not url:
                sys.exit(f"mcb: {c['asset']} not found in {c['repo']} releases")
            say(f"OpenSSL XCurl set: found {url}")
        fetch_pinned(url, archive, c["sha256"], "OpenSSL XCurl set")
    else:
        say("OpenSSL XCurl set: ok (cached)")
    marker = setdir / ".sha256"
    if not (marker.is_file() and marker.read_text().strip() == c["sha256"]):
        shutil.rmtree(setdir, ignore_errors=True)
        setdir.mkdir(parents=True)
        with tarfile.open(archive) as tar:
            for m in tar.getmembers():
                # Flatten: only the DLLs matter, wherever the archive keeps them.
                if m.isfile() and m.name.lower().endswith(".dll"):
                    m.name = Path(m.name).name
                    tar.extract(m, setdir)
        marker.write_text(c["sha256"])
    for need in ("libcurl-4.dll", "xcurl-cashim.dll", "cryptbase.dll"):
        if not (setdir / need).is_file():
            sys.exit(f"mcb: OpenSSL XCurl set is missing {need}")


def fetch_gdk_deps(comp_dir):
    c = COMPONENTS["gdk_deps"]
    for name, digest in c["files"].items():
        fetch_pinned(f"{c['base_url']}/{name}", comp_dir / ("gdkdeps-" + name), digest, name)


def fetch_cacert(comp_dir):
    dest = comp_dir / "cacert.pem"
    say("CA bundle: downloading")
    curl(COMPONENTS["cacert"]["url"], dest)
    if b"BEGIN CERTIFICATE" not in dest.read_bytes():
        sys.exit("mcb: the CA bundle download is not a PEM file")
    say("CA bundle: ok")


def cmd_fetch(comp_dir):
    comp_dir = Path(comp_dir)
    comp_dir.mkdir(parents=True, exist_ok=True)
    fetch_gdk_deps(comp_dir)
    fetch_xcurl_set(comp_dir)
    fetch_cacert(comp_dir)
    fetch_threading(comp_dir)


# --- prepare: game folder ------------------------------------------------------

def backup_once(path):
    bak = Path(str(path) + ".mcb-orig")
    if path.exists() and not bak.exists():
        shutil.copy2(path, bak)


def install_xbox_dlls(game, comp):
    """Open-source libHttpClient.GDK.dll + OpenSSL XCurl (bol/fixups.py
    install_gdk_xbox_dlls, _install_openssl_xcurl). Recopied every launch: a game
    update puts the originals back."""
    for name in COMPONENTS["gdk_deps"]["files"]:
        backup_once(game / name)
        shutil.copy2(comp / ("gdkdeps-" + name), game / name)
    s = comp / "openssl-xcurl-set"
    for nm in ("XCurl.dll", "Xcurl.dll"):
        backup_once(game / nm)
    for dll in sorted(s.glob("*.dll")):
        if dll.name not in ("cryptbase.dll", "xcurl-cashim.dll"):
            shutil.copy2(dll, game / dll.name)
    shutil.copy2(s / "libcurl-4.dll", game / "xcurl_real.dll")
    for nm in ("XCurl.dll", "Xcurl.dll"):
        shutil.copy2(s / "xcurl-cashim.dll", game / nm)
    shutil.copy2(comp / "cacert.pem", game / "cacert.pem")
    # bol/fixups.py fix_curl_ssl: CA bundle where GDK code looks for it.
    for base in (game, game.parent):
        crt = base / "etc" / "ssl" / "certs" / "ca-bundle.crt"
        crt.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(comp / "cacert.pem", crt)
    say("Xbox-Live DLLs + OpenSSL XCurl installed in the game folder")


def patch_lhc_xcurl_gate(game):
    """bol/fixups.py _patch_lhc_xcurl_gate: libHttpClient only takes the XCurl
    path for console enums 2..8 and otherwise falls back to WinHTTP/secur32,
    which Azure rejects. NOP the 6-byte `ja` so XCurl is always used."""
    dll = game / "libHttpClient.GDK.dll"
    data = bytearray(dll.read_bytes())
    m = re.search(rb"\x83\xc0\xfe\xba\x04\x00\x00\x00\x48\x8d\x0d.{4}\x83\xf8\x06"
                  rb"(?:\x0f\x87.{4}|\x90{6})", bytes(data), re.S)
    if not m:
        warn("libHttpClient provider gate not found; XCurl routing patch skipped")
        return
    at = m.start() + 18
    if data[at:at + 6] == b"\x90" * 6:
        return
    if data[at:at + 2] != b"\x0f\x87":
        warn("libHttpClient gate anchor misaligned; patch skipped")
        return
    data[at:at + 6] = b"\x90" * 6
    dll.write_bytes(bytes(data))
    say("libHttpClient forced onto the XCurl provider")


# --- prepare: Microsoft GameInput (bol/gameinput.py) ---------------------------

def msi_embedded_cab(msi):
    """The embedded MSZip CAB of an MSI, walking the OLE compound file."""
    if msi[:8] != bytes.fromhex("d0cf11e0a1b11ae1"):
        return None
    u = struct.unpack_from
    ssz = 1 << u("<H", msi, 0x1e)[0]
    mssz = 1 << u("<H", msi, 0x20)[0]
    dir0 = u("<I", msi, 0x30)[0]
    minicut = u("<I", msi, 0x38)[0]
    minifat0 = u("<I", msi, 0x3c)[0]
    difat0, ndifat = u("<I", msi, 0x44)[0], u("<I", msi, 0x48)[0]
    FREE, ENDC = 0xFFFFFFFF, 0xFFFFFFFE

    def sect(n):
        return msi[(n + 1) * ssz:(n + 2) * ssz]

    difat = list(u("<109I", msi, 0x4c))
    nxt = difat0
    for _ in range(ndifat):
        if nxt in (FREE, ENDC):
            break
        vals = list(u("<%dI" % (ssz // 4), sect(nxt), 0))
        difat += vals[:-1]
        nxt = vals[-1]
    fat = []
    for fs in (d for d in difat if d != FREE):
        fat += list(u("<%dI" % (ssz // 4), sect(fs), 0))

    def chain(start):
        out, n, seen = [], start, set()
        while n not in (ENDC, FREE) and n < len(fat) and n not in seen:
            seen.add(n)
            out.append(n)
            n = fat[n]
        return out

    def rbig(s, sz):
        return b"".join(sect(n) for n in chain(s))[:sz]

    dird = rbig(dir0, len(chain(dir0)) * ssz)
    ents = []
    for i in range(0, len(dird), 128):
        e = dird[i:i + 128]
        if len(e) < 128:
            break
        if u("<H", e, 64)[0]:
            ents.append((e[66], u("<I", e, 116)[0], u("<Q", e, 120)[0]))
    root = next((e for e in ents if e[0] == 5), None)
    if not root:
        return None
    ministream = rbig(root[1], root[2])
    mfat = []
    for ms in chain(minifat0):
        mfat += list(u("<%dI" % (ssz // 4), sect(ms), 0))

    def rmini(s, sz):
        out, n, seen = b"", s, set()
        while n not in (ENDC, FREE) and n < len(mfat) and n not in seen:
            seen.add(n)
            out += ministream[n * mssz:(n + 1) * mssz]
            n = mfat[n]
        return out[:sz]

    for typ, start, size in ents:
        if typ != 2 or size < 4:
            continue
        head = rbig(start, size) if size >= minicut else rmini(start, size)
        if head[:4] == b"MSCF":
            return head
    return None


def cab_payload(cab):
    """Decompresses an MSZip CAB into [(size, bytes), ...]."""
    if not cab or cab[:4] != b"MSCF":
        return []
    u = struct.unpack_from
    coff_files = u("<I", cab, 16)[0]
    cfolders, cfiles, flags = u("<HHH", cab, 26)
    o, cb_folder, cb_data = 36, 0, 0
    if flags & 4:
        cb_header, cb_folder, cb_data = u("<HBB", cab, o)
        o += 4 + cb_header
    folders = []
    for _ in range(cfolders):
        coff, ndata, _ = u("<IHH", cab, o)
        o += 8 + cb_folder
        folders.append((coff, ndata))
    files, p = [], coff_files
    for _ in range(cfiles):
        cb, uoff, ifol = u("<IIH", cab, p)
        p += 16
        p = cab.index(b"\x00", p) + 1
        files.append((cb, uoff, ifol))
    fdata = []
    for coff, ndata in folders:
        q, out, prev = coff, b"", b""
        for _ in range(ndata):
            cb_d = u("<IHH", cab, q)[1]
            q += 8 + cb_data
            blk = cab[q:q + cb_d]
            q += cb_d
            if blk[:2] != b"CK":
                return []
            d = zlib.decompressobj(-15, zdict=prev[-32768:] if prev else b"")
            out += d.decompress(blk[2:]) + d.flush()
            prev = out
        fdata.append(out)
    return [(cb, fdata[ifol][uoff:uoff + cb]) for cb, uoff, ifol in files]


def pe_kind(data):
    if data[:2] != b"MZ" or len(data) < 0x40:
        return None
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    if pe + 24 > len(data) or data[pe:pe + 4] != b"PE\0\0":
        return None
    return "dll" if struct.unpack_from("<H", data, pe + 22)[0] & 0x2000 else "exe"


def pe_file_version(data):
    at = data.find(struct.pack("<I", 0xFEEF04BD))
    if at < 0 or at + 16 > len(data):
        return None
    high, low = struct.unpack_from("<II", data, at + 8)
    return (high >> 16, high & 0xFFFF, low >> 16, low & 0xFFFF)


def install_gameinput(game, prefix):
    """Extracts the game's own GameInputRedist.msi into the prefix (no msiexec).
    Wine's builtin gameinput has no mouse backend, so without this the in-game
    mouse and controllers are dead. Returns registry entries to write."""
    msi = game / "Installers" / "GameInputRedist.msi"
    x64 = prefix / "drive_c/Program Files/Microsoft GameInput/x64"
    if not msi.is_file():
        warn("Installers/GameInputRedist.msi not in the game; mouse/controller input may not work")
        return []
    payload = cab_payload(msi_embedded_cab(msi.read_bytes()))
    pes = [(k, d) for _, d in payload for k in [pe_kind(d)] if k]
    dlls = sorted((d for k, d in pes if k == "dll"), key=len, reverse=True)
    exes = sorted((d for k, d in pes if k == "exe"), key=len, reverse=True)
    if not dlls or not exes:
        warn("GameInputRedist.msi has an unrecognised layout; GameInput not installed")
        return []
    have = x64 / "GameInputRedist.dll"
    current = pe_file_version(have.read_bytes()) if have.is_file() else None
    bundled = pe_file_version(dlls[0])
    if current is None or (bundled and bundled > current):
        x64.mkdir(parents=True, exist_ok=True)
        (x64 / "GameInputRedist.dll").write_bytes(dlls[0])
        (prefix / "drive_c/windows/system32/GameInputRedist.dll").write_bytes(dlls[0])
        (x64 / "GameInputRedistService.exe").write_bytes(exes[0])
        if len(dlls) >= 2:
            (x64 / "GameInputBridge.dll").write_bytes(dlls[1])
        if len(exes) >= 2:
            (x64 / "GameInputRawInputProxy.exe").write_bytes(exes[1])
        if len(dlls) >= 3:
            x86 = x64.parent / "x86"
            x86.mkdir(parents=True, exist_ok=True)
            (x86 / "GameInputRedist.dll").write_bytes(dlls[2])
        say(f"Microsoft GameInput {'.'.join(map(str, bundled or ()))} installed")
    redist = r"C:\Program Files\Microsoft GameInput\x64"
    svc = r"HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\GameInputRedistService"
    return [
        (r"HKEY_LOCAL_MACHINE\Software\Microsoft\GameInput", "RedistDir", redist),
        (r"HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\GameInput", "RedistDir", redist),
        (svc, "DisplayName", "GameInput Redist Service"),
        (svc, "Description", "GameInput Redist Service"),
        (svc, "ImagePath", redist + r"\GameInputRedistService.exe"),
        (svc, "ObjectName", "LocalSystem"),
        (svc, "ErrorControl", 0),
        (svc, "Start", 3),
        (svc, "Type", 0x10),
    ]


# --- prepare: prefix + engine -----------------------------------------------------

def winegdk_prereqs():
    """bol/auth.py wine_apply_winegdk_prereqs: console enum 8 (the XSAPI code path),
    WinRT picker registrations, TLS 1.2 (Azure rejects Wine's TLS 1.3), and the
    WindowsAppRuntime UI-mute variables."""
    hklm = r"HKEY_LOCAL_MACHINE"
    acid = hklm + r"\Software\Microsoft\WindowsRuntime\ActivatableClassId"
    entries = [
        (hklm + r"\Software\Microsoft\Windows NT\CurrentVersion\OEM", "ConsoleMode", 8),
        (acid + r"\Microsoft.Windows.Storage.Pickers.FileOpenPicker", "DllPath",
         r"C:\windows\system32\windows.storage.dll"),
        (acid + r"\Windows.Storage.Pickers.FileSavePicker", "DllPath",
         r"C:\windows\system32\windows.storage.dll"),
        (hklm + r"\Software\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp",
         "DefaultSecureProtocols", 2560),
        (hklm + r"\Software\Microsoft\SchannelTLS\Protocols\TLS 1.3\Client", "DisabledByDefault", 1),
    ]
    for name in ("MICROSOFT_WINDOWSAPPRUNTIME_BOOTSTRAP_INITIALIZE_SHOWUI",
                 "MICROSOFT_WINDOWSAPPRUNTIME_BOOTSTRAP_INITIALIZE_FAILFAST",
                 "MICROSOFT_WINDOWSAPPRUNTIME_DEPLOYMENT_INITIALIZE_ONERRORSHOWUI"):
        entries.append((r"HKEY_CURRENT_USER\Environment", name, "0"))
    return entries


def write_reg(entries, out):
    """REGEDIT4 file for `wine regedit /S`."""
    lines = ["REGEDIT4", ""]
    by_key = {}
    for key, name, value in entries:
        by_key.setdefault(key, []).append((name, value))
    for key, values in by_key.items():
        lines.append(f"[{key}]")
        for name, value in values:
            if isinstance(value, int):
                lines.append(f'"{name}"=dword:{value:08x}')
            else:
                v = value.replace("\\", "\\\\").replace('"', '\\"')
                lines.append(f'"{name}"="{v}"')
        lines.append("")
    Path(out).write_text("\r\n".join(lines) + "\r\n")


def install_prefix_files(prefix, engine, comp):
    sys32 = prefix / "drive_c/windows/system32"
    if not sys32.is_dir():
        sys.exit(f"mcb: Wine prefix not initialised ({sys32} missing); run ./mcb setup")
    # bol/fixups.py _install_cryptbase_in_prefix: advapi32 forwards RtlGenRandom
    # to cryptbase in system32, and OpenSSL aborts at its first RNG call without it.
    backup_once(sys32 / "cryptbase.dll")
    shutil.copy2(comp / "openssl-xcurl-set" / "cryptbase.dll", sys32 / "cryptbase.dll")
    # WineGDK's xgameruntime.dll loads the native runtime by this name.
    shutil.copy2(comp / "xgameruntime.dll.threading",
                 engine / "lib/wine/x86_64-windows/xgameruntime.dll.threading")
    say("cryptbase stub + xgameruntime.dll.threading installed")


def classic_renderer(prefix):
    """Keeps Minecraft on its Classic renderer (graphics_mode 0): the newer
    renderer raced under Wine on Linux (jphein/minecraft-bedrock-linux), and
    Wine's vkd3d on MoltenVK is more limited still. Only edits an existing
    options.txt, so the game writes its own complete file on first run.
    MCB_KEEP_GRAPHICS=1 leaves it alone."""
    if os.environ.get("MCB_KEEP_GRAPHICS") == "1":
        return
    rel = "AppData/Roaming/Minecraft Bedrock/Users/*/games/com.mojang/minecraftpe/options.txt"
    for opt in (prefix / "drive_c/users").glob("*/" + rel):
        lines = opt.read_text(errors="replace").splitlines()
        if not lines or not any(l.startswith("graphics_mode:") for l in lines):
            continue
        new = ["graphics_mode:0" if l.startswith("graphics_mode:") else l for l in lines]
        if new != lines:
            opt.write_text("\n".join(new) + "\n")
            say(f"Classic renderer selected ({opt.parent.parent.parent.parent.name} profile)")


def cmd_prepare(game, prefix, engine, comp, reg_out):
    game, prefix, engine, comp = map(Path, (game, prefix, engine, comp))
    for need in ("xgameruntime.dll.threading", "cacert.pem", "openssl-xcurl-set/libcurl-4.dll"):
        if not (comp / need).exists():
            sys.exit(f"mcb: component {need} missing; run ./mcb setup")
    install_xbox_dlls(game, comp)
    patch_lhc_xcurl_gate(game)
    install_prefix_files(prefix, engine, comp)
    classic_renderer(prefix)
    entries = winegdk_prereqs() + install_gameinput(game, prefix)
    write_reg(entries, reg_out)


def main(argv):
    if len(argv) == 3 and argv[1] == "fetch":
        cmd_fetch(argv[2])
    elif len(argv) == 7 and argv[1] == "prepare":
        cmd_prepare(*argv[2:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)

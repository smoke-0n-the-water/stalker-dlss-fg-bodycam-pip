r"""Apply Walter's settings to a FRESH OptiScaler v0.8.x ini (DLSSNR fork).

0.8.0 removed [FrameGen] External, which is what kept v0.7.6 out of the
DX12 exe's own Streamline frame gen. Its replacement here is: OptiScaler FG
pinned off, and no GPU spoofing inside slInit (the engine's call, not
OptiScaler's). HookOriginalNvngxOnly is left at auto, as in the Oct 22 run
where DX12 FG and NR worked together.

    python configure_optiscaler_v08.py [path\to\OptiScaler.ini]

Section-scoped, idempotent; refuses to write if any key is missing.
"""
import io
import sys

INI = r"C:\Program Files (x86)\GOG Galaxy\Games\S.T.A.L.K.E.R. GAMMA\Anomaly\bin\OptiScaler.ini"

TARGETS = [
    # DX11 rendering in both exes; dlss_12 is the only DX11 path that runs NR
    ("Upscalers", "Dx11Upscaler", "dlss_12"),
    # OptiScaler FG off: boot crash with NvPresent64, and the DX12 exe owns FG
    ("FrameGen", "Enabled", "false"),
    ("FrameGen", "FGInput", "nofg"),
    ("FrameGen", "FGOutput", "nofg"),
    # leave the engine's slInit alone (default is true)
    ("Spoofing", "StreamlineSpoofing", "false"),
    ("Spoofing", "Dxgi", "false"),
    # no continuous log file during play
    ("Log", "LogToFile", "false"),
    ("Log", "LogLevel", "2"),
    # NR, carried over from the v0.7.6 ini (Precision/SkinToneEnabled no longer exist)
    ("DlssNr", "Enabled", "true"),
    ("DlssNr", "RunBeforeSR", "true"),
    ("DlssNr", "Passes", "1"),
    ("DlssNr", "UnlockPasses", "false"),
    ("DlssNr", "SkinProtection", "false"),
    ("DlssNr", "SkinDetail", "1.0"),
    ("DlssNr", "SkinColour", "1.0"),
    ("DlssNr", "EnvironmentDetail", "1.0"),
    ("DlssNr", "EnvironmentColour", "1.0"),
    ("DlssNr", "ShowSkinMask", "false"),
]


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else INI
    with io.open(path, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        lines = fh.read().split("\n")

    section = None
    done = set()
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            section = s[1:-1]
            continue
        if "=" not in s or s.startswith(";"):
            continue
        key = s.split("=", 1)[0].strip()
        for sec, k, val in TARGETS:
            if section != sec or key != k or (sec, k) in done:
                continue
            eol = "\r" if line.endswith("\r") else ""
            cur = s.split("=", 1)[1].strip()
            if cur != val:
                lines[i] = "%s=%s%s" % (k, val, eol)
                print("set      [%s] %s: %s -> %s" % (sec, k, cur, val))
            else:
                print("already  [%s] %s=%s" % (sec, k, val))
            done.add((sec, k))

    missing = [(s, k) for s, k, _v in TARGETS if (s, k) not in done]
    if missing:
        sys.exit("key(s) not found, nothing written: %s" % missing)

    with io.open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write("\n".join(lines))
    print("\nwrote %s" % path)


main()

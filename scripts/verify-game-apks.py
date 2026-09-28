#!/usr/bin/env python3
"""Verify the official four-split TFT release before signing its update feed."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


RIOT_CERTIFICATE = "931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c"
PACKAGES = {
    "global": "com.riotgames.league.teamfighttactics",
    "vietnam": "com.riotgames.league.teamfighttacticsvn",
    "taiwan": "com.riotgames.league.teamfighttacticstw",
}
REQUIRED_SPLITS = {None, "config.arm64_v8a", "config.en", "config.mdpi"}


def run(*arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True).stdout


def attribute(manifest, name, numeric=False):
    value = r"\(type 0x10\)(0x[0-9a-f]+)" if numeric else r'"([^"\n]*)"'
    match = re.search(r"A: " + re.escape(name) + r"(?:\(0x[0-9a-f]+\))?=" + value, manifest)
    return (int(match[1], 16) if numeric else match[1]) if match else None


def verify(apk_dir, edition, aapt, apksigner):
    files = sorted(apk_dir.glob("*.apk"), key=lambda path: (path.name != "base.apk", path.name))
    if len(files) != 4 or files[0].name != "base.apk":
        raise ValueError("Expected base.apk and the ARM64, English, and mdpi splits")
    apks, splits = [], set()
    version = version_code = None
    for apk in files:
        if not re.fullmatch(r"[A-Za-z0-9._-]+[.]apk", apk.name):
            raise ValueError(f"Unsafe APK filename: {apk.name}")
        certificates = run(apksigner, "verify", "--print-certs", str(apk))
        signers = re.findall(r"^Signer #\d+ certificate SHA-256 digest: (\w+)$", certificates, re.M)
        if signers != [RIOT_CERTIFICATE]:
            raise ValueError(f"{apk.name}: signature does not match the pinned Riot certificate")
        manifest = run(aapt, "dump", "xmltree", str(apk), "AndroidManifest.xml")
        if attribute(manifest, "package") != PACKAGES[edition]:
            raise ValueError(f"{apk.name}: wrong package for {edition}")
        code = attribute(manifest, "android:versionCode", numeric=True)
        split = attribute(manifest, "split")
        if apk.name == "base.apk":
            version = attribute(manifest, "android:versionName")
            version_code = code
            if not version or not code or split is not None:
                raise ValueError("Invalid base APK version or split metadata")
        if code != version_code or split in splits:
            raise ValueError(f"{apk.name}: mismatched version or duplicate split")
        splits.add(split)
        apks.append({"name": apk.name, "size": apk.stat().st_size,
                     "sha256": hashlib.sha256(apk.read_bytes()).hexdigest()})
    if splits != REQUIRED_SPLITS:
        raise ValueError("Expected exactly the ARM64, English, and mdpi configuration splits")
    return {"packageName": PACKAGES[edition], "version": version, "versionCode": version_code,
            "baseSHA256": apks[0]["sha256"], "apks": apks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--edition", choices=PACKAGES, default="global")
    parser.add_argument("--apk-dir", type=Path, required=True)
    parser.add_argument("--aapt", required=True)
    parser.add_argument("--apksigner", required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.apk_dir, args.edition, args.aapt, args.apksigner), indent=2))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"APK verification failed: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

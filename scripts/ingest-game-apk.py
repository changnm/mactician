#!/usr/bin/env python3
"""Turn a downloaded TFT XAPK/zip into a verified bundled game release.

Given only the downloaded bundle, this script:

1. extracts it and normalizes the four splits to base.apk, config.arm64_v8a.apk,
   config.en.apk, and config.mdpi.apk;
2. detects the edition (Global or Vietnam) from the package name and verifies the
   pinned Riot signing certificate, package, version code, and split set (the same
   checks as scripts/verify-game-apks.py);
3. refuses anything that is not strictly newer than the manifest;
4. replaces the private APK directory and the release manifest entry; and
5. unless --no-release is given, bumps the Mactician patch version and build, and
   updates the release notes, changelog, README, docs, and tests that must agree.

Nothing is built, committed, signed, or uploaded here; see
scripts/update-game-from-apk.command for the optional build and publish steps.
"""

import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parent.parent
MANIFEST = PROJECT / "launcher/Resources/release-manifest.json"
SPLITS = ("base.apk", "config.arm64_v8a.apk", "config.en.apk", "config.mdpi.apk")
EDITIONS = {
    "com.riotgames.league.teamfighttactics": ("global", "Global", PROJECT / "private/tft-apks"),
    "com.riotgames.league.teamfighttacticsvn": (
        "vietnam", "Vietnam (VNG)", PROJECT / "private/tft-apks-vietnam"),
}
BUILD_TOOLS_HINTS = (
    "/opt/homebrew/share/android-commandlinetools/build-tools",
    str(Path.home() / "Library/Android/sdk/build-tools"),
)


class IngestError(Exception):
    pass


def load_verifier():
    spec = importlib.util.spec_from_file_location(
        "verify_game_apks", PROJECT / "scripts/verify-game-apks.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def find_build_tools(explicit):
    roots = [explicit] if explicit else []
    roots += [os.environ.get("MACTICIAN_ANDROID_BUILD_TOOLS")]
    for hint in BUILD_TOOLS_HINTS:
        hint = Path(hint)
        if hint.is_dir():
            roots += sorted((str(p) for p in hint.iterdir() if p.is_dir()), reverse=True)
    for root in filter(None, roots):
        aapt, signer = Path(root) / "aapt", Path(root) / "apksigner"
        if aapt.is_file() and signer.is_file():
            return str(aapt), str(signer)
    raise IngestError("Official Android Build Tools (aapt and apksigner) were not found. "
                      "Set MACTICIAN_ANDROID_BUILD_TOOLS to their directory.")


def gather_apks(bundle, workdir):
    """Return every .apk inside a bundle (zip/xapk/apks) or directory."""
    if bundle.is_dir():
        return sorted(bundle.rglob("*.apk"))
    if not zipfile.is_zipfile(bundle):
        raise IngestError(f"{bundle} is not a zip, XAPK, or APKS bundle")
    found = []
    with zipfile.ZipFile(bundle) as archive:
        for index, info in enumerate(archive.infolist()):
            if info.is_dir() or not info.filename.lower().endswith(".apk"):
                continue
            # Flatten into numbered directories so an archive can never write
            # outside the work directory, whatever its entry names say.
            target = workdir / str(index) / Path(info.filename).name
            target.parent.mkdir(parents=True)
            with archive.open(info) as source, open(target, "wb") as destination:
                shutil.copyfileobj(source, destination)
            found.append(target)
    return found


def normalize(apks, package, stage):
    base, others = None, []
    for apk in apks:
        name = apk.name[len("split_"):] if apk.name.startswith("split_") else apk.name
        if name in SPLITS[1:]:
            shutil.copyfile(apk, stage / name)
        elif name.startswith("config."):
            continue  # unused density/ABI/language splits
        elif name in (f"{package}.apk", "base.apk"):
            base = apk
        else:
            others.append(apk)
    if base is None and len(others) == 1:
        base = others[0]
    if base is None:
        raise IngestError(f"Could not identify the base APK among: {[p.name for p in apks]}")
    shutil.copyfile(base, stage / "base.apk")
    missing = [name for name in SPLITS if not (stage / name).is_file()]
    if missing:
        raise IngestError(f"The bundle is missing {', '.join(missing)}")


def detect_package(base, aapt):
    import subprocess
    # aapt exits non-zero when it cannot resolve the app icon but still prints the
    # package line, so the exit status is deliberately ignored; verification below
    # re-reads the manifest strictly.
    badging = subprocess.run([aapt, "dump", "badging", str(base)], check=False,
                             capture_output=True, text=True).stdout
    match = re.search(r"^package: name='([^']+)'", badging, re.M)
    if not match or match[1] not in EDITIONS:
        raise IngestError(f"Unsupported package: {match[1] if match else 'unknown'}")
    return match[1]


def display_version(version):
    return version.split("-")[0]


def sub_once(text, pattern, replacement, label):
    updated, count = re.subn(pattern, replacement, text, flags=re.M)
    if count == 0:
        raise IngestError(f"Could not update {label}; its format changed")
    return updated


def edit(path, function):
    original = path.read_text(encoding="utf-8")
    updated = function(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")


def bump_release(release, edition_name, previous, manifest, today):
    info = PROJECT / "launcher/Info.plist"
    version_match = re.search(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>",
                              info.read_text())
    build_match = re.search(r"<key>CFBundleVersion</key>\s*<string>([^<]+)</string>",
                            info.read_text())
    old_version, old_build = version_match[1], build_match[1]
    major, minor, patch = (int(part) for part in old_version.split("."))
    new_version = f"{major}.{minor}.{patch + 1}"
    new_build = str(int(old_build) + 1)

    for plist in (info, PROJECT / "launcher/Resources/EmulatorHost-Info.plist"):
        def update_plist(text):
            text = sub_once(
                text, r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)",
                rf"\g<1>{new_version}\g<2>", plist.name)
            return sub_once(
                text, r"(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)",
                rf"\g<1>{new_build}\g<2>", plist.name)
        edit(plist, update_plist)

    def update_tests(text):
        text = text.replace(f'== "{old_version}"', f'== "{new_version}"')
        # Both the launcher and the emulator host assert the build number.
        return re.sub(rf'(CFBundleVersion"\] as\? String == )"{old_build}"', rf'\g<1>"{new_build}"', text)
    edit(PROJECT / "launcher/Tests/LauncherTests.swift", update_tests)

    def update_readme(text):
        text = text.replace(old_version, new_version)
        text = text.replace(f"build {old_build}", f"build {new_build}")
        return text.replace(previous["version"], release["version"])
    edit(PROJECT / "README.md", update_readme)
    edit(PROJECT / "docs/building.md", lambda t: t.replace(previous["version"], release["version"]))
    edit(PROJECT / "docs/releasing.md", lambda t: t.replace(old_version, new_version)
         .replace(f"build {old_build}", f"build {new_build}"))

    global_version = manifest["game"]["version"]
    other = (f"Global stays on `{global_version}`." if edition_name != "Global"
             else f"Vietnam (VNG) stays on `{manifest['editionGames']['vietnam']['version']}`.")
    bullet = (f"Update the bundled {edition_name} TFT to `{release['version']}` (version code\n"
              f"  `{release['versionCode']}`). An installed {edition_name} game older than the bundled\n"
              f"  release is upgraded on launch without a download, keeping its game data and\n"
              f"  sign-in. {other}")

    def update_changelog(text):
        text = sub_once(text, r"^The current application metadata is version .*$",
                        f"The current application metadata is version {new_version}, build {new_build}.",
                        "CHANGELOG header")
        entry = f"## {new_version} — {today}\n\n### Changed\n\n- {bullet}\n\n"
        return text.replace(f"## {old_version} — ", entry + f"## {old_version} — ", 1)
    edit(PROJECT / "CHANGELOG.md", update_changelog)

    notes = PROJECT / f"launcher/Resources/release-notes/{new_version}.md"
    notes.write_text(
        f"# Mactician Release Notes — {new_version}\n\n"
        f"- Bundle {edition_name} TFT {release['version']} (version code {release['versionCode']}). "
        f"An installed\n  {edition_name} game is upgraded to it on the next launch without downloading the APKs\n"
        f"  again, and keeps its game data and Riot sign-in.\n"
        f"- {other}\n- No other application changes.\n\n"
        f"Build {new_build} for Apple Silicon, macOS 12 or later. This build is signed ad hoc and\n"
        f"not notarized; open it through System Settings → Privacy & Security → Open Anyway.\n",
        encoding="utf-8")
    return new_version, new_build


def document_vietnam(release, previous):
    rows = "\n".join(f"| {a['name']} | {a['size']} | {a['sha256']} |" for a in release["apks"])
    section = (
        f"## Bundled release — TFT {display_version(release['version'])} "
        f"({release['version']})\n\n"
        f"Release `{release['version']}` (version code `{release['versionCode']}`) is listed under "
        f"`editionGames` in\n`launcher/Resources/release-manifest.json` and copied to "
        f"`Resources/Game-vietnam` by\n`scripts/build-mactician.command`. It was imported from a "
        f"downloaded XAPK with\n`scripts/ingest-game-apk.py`, which normalized the base APK to "
        f"`base.apk` and verified all four\nAPKs with Android Build Tools: package "
        f"`com.riotgames.league.teamfighttacticsvn`, version code\n`{release['versionCode']}`, "
        f"matching split IDs, and the pinned Riot certificate\n"
        f"(`{load_verifier().RIOT_CERTIFICATE}`).\n\n"
        f"| APK | Bytes | SHA-256 |\n| --- | ---: | --- |\n{rows}\n\n"
        f"Only the signatures, package, split set, and version codes were verified; an emulator "
        f"launch of this\nbuild was not part of the release check. The previous bundled release was "
        f"`{previous['version']}` (version code `{previous['versionCode']}`).\n\n")

    def update(text):
        marker = re.search(r"^## Bundled release — TFT", text, re.M)
        return text[:marker.start()] + section + text[marker.start():] if marker else text + "\n" + section
    edit(PROJECT / "docs/vietnam.md", update)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("bundle", type=Path, help="XAPK/zip/APKS file or a directory of APKs")
    parser.add_argument("--build-tools", help="directory containing aapt and apksigner")
    parser.add_argument("--no-release", action="store_true",
                        help="update only the private APKs and release manifest")
    parser.add_argument("--dry-run", action="store_true", help="verify and report; change nothing")
    args = parser.parse_args()

    aapt, apksigner = find_build_tools(args.build_tools)
    verifier = load_verifier()
    with tempfile.TemporaryDirectory(prefix="mactician-ingest-") as temporary:
        temporary = Path(temporary)
        extracted, stage = temporary / "extracted", temporary / "stage"
        extracted.mkdir()
        stage.mkdir()
        apks = gather_apks(args.bundle.expanduser(), extracted)
        if not apks:
            raise IngestError("No APK files were found in the bundle")
        # Detect the package from every candidate; the base APK is the one that names it.
        packages = {detect_package(apk, aapt) for apk in apks if not apk.name.startswith(
            ("split_config", "config."))}
        if len(packages) != 1:
            raise IngestError(f"Could not determine a single package: {sorted(packages)}")
        package = packages.pop()
        edition, edition_name, private_dir = EDITIONS[package]
        normalize(apks, package, stage)
        try:
            release = verifier.verify(stage, edition, aapt, apksigner)
        except (ValueError, OSError) as error:
            raise IngestError(f"APK verification failed: {error}")

        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        slot = manifest["game"] if edition == "global" else manifest["editionGames"][edition]
        previous = dict(version=slot["version"], versionCode=slot["versionCode"])
        print(f"{edition_name}: {previous['version']} ({previous['versionCode']}) -> "
              f"{release['version']} ({release['versionCode']})")
        if release["versionCode"] <= previous["versionCode"]:
            raise IngestError("The bundle is not newer than the release manifest; refusing to downgrade")
        if args.dry_run:
            print("Dry run: verified OK, nothing changed.")
            return

        slot.clear()
        slot.update(release)
        private_dir.mkdir(parents=True, exist_ok=True)
        for name in SPLITS:
            shutil.copyfile(stage / name, private_dir / (name + ".new"))
        for name in SPLITS:
            os.replace(private_dir / (name + ".new"), private_dir / name)
        MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Installed splits in {private_dir.relative_to(PROJECT)} and updated the release manifest.")

        if args.no_release:
            return
        today = datetime.date.today().isoformat()
        version, build = bump_release(release, edition_name, previous, manifest, today)
        if edition == "vietnam":
            document_vietnam(release, previous)
        else:
            print("Note: add the new Global release record to docs/reproducibility.md by hand.")
        print(f"Prepared Mactician {version} (build {build}). Review with `git diff`, then build and publish.")


if __name__ == "__main__":
    try:
        main()
    except (IngestError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)

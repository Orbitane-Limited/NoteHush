#!/usr/bin/env python3
"""Validate version, privacy/sandbox metadata, docs, and optional built archive."""
import json
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def read_plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


def validate_privacy(privacy):
    if (privacy.get("NSPrivacyTracking") is not False
            or privacy.get("NSPrivacyTrackingDomains") != []
            or privacy.get("NSPrivacyCollectedDataTypes") != []):
        raise ValueError("Privacy metadata no longer matches the no-collection product contract")
    accesses = privacy.get("NSPrivacyAccessedAPITypes", [])
    if (len(accesses) != 1
            or accesses[0].get("NSPrivacyAccessedAPIType") != "NSPrivacyAccessedAPICategoryFileTimestamp"):
        raise ValueError("Declare the audited file-metadata API category")
    reasons = accesses[0].get("NSPrivacyAccessedAPITypeReasons", [])
    # User-selected files and private recovery files are separate approved uses.
    if len(reasons) != 2 or set(reasons) != {"3B52.1", "C617.1"}:
        raise ValueError("Declare both user-granted and app-container file metadata access")


def main():
    version_file = (ROOT / "Config/Version.xcconfig").read_text()
    version = re.search(r"^MARKETING_VERSION = (\d+\.\d+\.\d+)$", version_file, re.M)
    build = re.search(r"^CURRENT_PROJECT_VERSION = ([1-9]\d*)$", version_file, re.M)
    if not version or not build:
        raise ValueError("Use numeric major.minor.patch and a positive integer build number")
    entitlements = read_plist(ROOT / "Config/NoteHush.entitlements")
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        raise ValueError("App Sandbox must remain enabled")
    allowed = {"com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write",
               "com.apple.security.files.bookmarks.app-scope", "com.apple.security.print"}
    if set(entitlements) - allowed:
        raise ValueError("Review and document any expanded entitlements before changing this allowlist")
    privacy = read_plist(ROOT / "App/NoteHush/Resources/PrivacyInfo.xcprivacy")
    validate_privacy(privacy)
    roadmap = json.loads((ROOT / "docs/roadmap.json").read_text())
    identifiers = {item["id"] for item in roadmap["issues"]}
    for item in roadmap["issues"]:
        if not set(item["depends"]).issubset(identifiers):
            raise ValueError("Unknown roadmap dependency")
    for path in [ROOT / "README.md", ROOT / "AGENTS.md", ROOT / "TESTING.md", *ROOT.glob("docs/**/*.md")]:
        for link in re.findall(r"\]\(([^)]+)\)", path.read_text()):
            if "://" not in link and not link.startswith("#"):
                if not (path.parent / link.split("#")[0]).exists():
                    raise ValueError(f"Broken relative link in {path.name}: {link}")
    if len(sys.argv) == 2:
        contents = Path(sys.argv[1]) / "Products/Applications/NoteHush.app/Contents"
        info = read_plist(contents / "Info.plist")
        expected = {"CFBundleShortVersionString": version[1], "CFBundleVersion": build[1],
                    "CFBundleIdentifier": "pk.codehub.NoteHush", "LSMinimumSystemVersion": "14.0"}
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f"Archive {key} differs from the declared product configuration")
        if info.get("NoteHushRequiresTestWorkspace") != "NO":
            raise ValueError("The release archive must not require a test workspace")
        if read_plist(contents / "Resources/PrivacyInfo.xcprivacy") != privacy:
            raise ValueError("Archive privacy manifest differs from source")
    print(f"Configuration valid: NoteHush {version[1]} ({build[1]})")


if __name__ == "__main__":
    main()

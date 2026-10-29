#!/usr/bin/env python3
"""Fail-closed checks shared by the manual App Store delivery driver.

Profile plist inspection is a diagnostic preflight, not a replacement for Xcode's
provisioning validation or Apple's server validation of the exported package.
"""
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import uuid

BUNDLE_ID = "pk.codehub.NoteHush"
PRODUCT_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.print": True,
}
PROBE_MARKERS = (
    b"NOTEHUSH_TEST_WORKSPACE", b"ProcessToEditorReady", b"performance-editor-ready",
    b"NOTEHUSH_PERFORMANCE", b"NOTEHUSH_UNDO_DIAGNOSTICS", b"UndoDiagnosticProbe",
    b"undo-diagnostic-", b"PerformanceApplication", b"TypingEventDispatch",
    b"TabEventDispatch", b"performance-event-",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version_settings(root):
    contents = (root / "Config/Version.xcconfig").read_text()
    versions = re.findall(r"^MARKETING_VERSION = (\d+\.\d+\.\d+)$", contents, re.M)
    builds = re.findall(r"^CURRENT_PROJECT_VERSION = ([1-9]\d*)$", contents, re.M)
    require(len(versions) == len(builds) == 1, "Invalid version configuration")
    return versions[0], builds[0]


def validate_ci(run, revision, repository):
    require(re.fullmatch(r"[0-9a-f]{40}", revision), "A full source commit is required")
    require(run.get("head_sha") == revision, "CI tested a different commit")
    require(run.get("head_branch") == "main", "CI must run on main")
    require(run.get("event") in {"push", "workflow_dispatch"}, "PR CI cannot authorize delivery")
    require(run.get("path") == ".github/workflows/ci.yml", "The required CI workflow was not selected")
    require(run.get("repository", {}).get("full_name") == repository, "CI repository mismatch")
    require(run.get("status") == "completed" and run.get("conclusion") == "success",
            "The complete CI run, including artifact transfer, must pass")


def validate_environment(environment):
    require(environment.get("name") == "app-store", "Missing App Store environment")
    reviewers = [rule for rule in environment.get("protection_rules", [])
                 if rule.get("type") == "required_reviewers"]
    require(len(reviewers) == 1 and reviewers[0].get("reviewers"),
            "App Store environment requires a configured human approval rule")
    require(reviewers[0].get("prevent_self_review") is True,
            "The signing environment must prevent self-review")
    # The documented environment REST response does not expose administrator
    # bypass configuration. Its UI setting remains an explicit setup check.


def validate_build_numbers(candidate, builds):
    require(isinstance(candidate, str) and re.fullmatch(r"[1-9]\d*", candidate),
            "Candidate build must be a positive integer")
    previous = 0
    seen = set()
    for build in builds:
        require(isinstance(build, dict) and build.get("type") == "builds",
                "Unexpected App Store build response")
        identifier = build.get("id")
        require(isinstance(identifier, str) and identifier and identifier not in seen,
                "Missing or repeated App Store build identity")
        seen.add(identifier)
        number = build.get("attributes", {}).get("version")
        require(isinstance(number, str) and re.fullmatch(r"[1-9]\d*", number),
                "Prior upload does not follow the integer build policy")
        previous = max(previous, int(number))
    require(int(candidate) > previous, "Build number must exceed every prior uploaded build")
    return previous


def canonical_profile_uuid(value):
    require(isinstance(value, str), "Invalid profile UUID")
    try:
        canonical = str(uuid.UUID(value)).upper()
    except ValueError:
        raise ValueError("Invalid profile UUID") from None
    require(canonical == value.upper(), "Invalid profile UUID")
    return canonical


def validate_profile(profile, team, certificate_sha1, now=None, *, manual_signing=False):
    require(re.fullmatch(r"[A-Z0-9]{10}", team), "Invalid publisher team")
    require(re.fullmatch(r"[0-9A-F]{40}", certificate_sha1), "Invalid application certificate fingerprint")
    require(profile.get("TeamIdentifier") == [team], "Profile publisher team mismatch")
    prefixes = profile.get("ApplicationIdentifierPrefix")
    require(isinstance(prefixes, list) and len(prefixes) == 1
            and re.fullmatch(r"[A-Z0-9]{10}", prefixes[0]), "Invalid App ID prefix")
    identifier = f"{prefixes[0]}.{BUNDLE_ID}"
    entitlements = profile.get("Entitlements", {})
    require(entitlements.get("com.apple.application-identifier") == identifier,
            "Profile must use NoteHush's explicit App ID")
    require(entitlements.get("com.apple.developer.team-identifier") == team,
            "Profile entitlement team mismatch")
    require("ProvisionedDevices" not in profile and "ProvisionsAllDevices" not in profile,
            "A Store distribution profile is required")
    require(not entitlements.get("get-task-allow")
            and not entitlements.get("com.apple.security.get-task-allow"),
            "Development provisioning is forbidden")
    require(profile.get("Platform") in (["OSX"], ["macOS"]), "A macOS profile is required")
    expiry = profile.get("ExpirationDate")
    require(isinstance(expiry, datetime), "Missing profile expiration")
    require(expiry.replace(tzinfo=timezone.utc) > (now or datetime.now(timezone.utc)),
            "Provisioning profile has expired")
    certificates = profile.get("DeveloperCertificates", [])
    require(isinstance(certificates, list) and all(isinstance(item, bytes) for item in certificates),
            "Invalid profile certificates")
    require(certificate_sha1 in {hashlib.sha1(item).hexdigest().upper() for item in certificates},
            "Signing certificate is not authorized by the profile")
    canonical_profile_uuid(profile.get("UUID"))
    if manual_signing:
        require(profile.get("IsXcodeManaged", False) is False,
                "Manual delivery requires a custom profile; use Xcode automatic signing for managed profiles")
    return identifier


def validate_entitlements(actual, team, application_id, profile):
    require(isinstance(actual, dict), "Missing signed entitlements")
    for key, value in PRODUCT_ENTITLEMENTS.items():
        require(actual.get(key) is value, "Signed product permission differs from the four-permission budget")
    identity = {
        "com.apple.application-identifier": application_id,
        "com.apple.developer.team-identifier": team,
    }
    for key, value in identity.items():
        require(actual.get(key) == value, "Signed application identity mismatch")
    allowed = set(PRODUCT_ENTITLEMENTS) | set(identity)
    # Apple may include this Store distribution marker. It grants no file access.
    if "beta-reports-active" in actual:
        require(actual["beta-reports-active"] is True
                and profile.get("Entitlements", {}).get("beta-reports-active") is True,
                "Unexpected beta reporting entitlement")
        allowed.add("beta-reports-active")
    require(set(actual) == allowed, "Undeclared signed entitlement (including debug exceptions)")


def validate_info(info, version, build):
    expected = {
        "CFBundleIdentifier": BUNDLE_ID, "CFBundleShortVersionString": version,
        "CFBundleVersion": build, "LSMinimumSystemVersion": "14.0",
        "NoteHushRequiresTestWorkspace": "NO", "NoteHushPerformanceBuild": "NO",
        "CFBundleExecutable": "NoteHush", "CFBundleIconName": "AppIcon",
        "CFBundleIconFile": "AppIcon",
    }
    require(all(info.get(key) == value for key, value in expected.items()),
            "Signed bundle does not match the declared Release configuration")
    require(info.get("ITSAppUsesNonExemptEncryption") is False,
            "Signed bundle must retain the audited encryption declaration")


def validate_resources(contents, root):
    icon = contents / "Resources/AppIcon.icns"
    require(icon.is_file() and not icon.is_symlink() and icon.stat().st_size > 0,
            "Signed bundle must include the compiled original app icon")
    require(plistlib.loads((contents / "Resources/PrivacyInfo.xcprivacy").read_bytes())
            == plistlib.loads((root / "App/NoteHush/Resources/PrivacyInfo.xcprivacy").read_bytes()),
            "Bundled privacy manifest differs from the audited source")


def command(arguments):
    """Never expose tool diagnostics, keychain paths or command arguments in CI."""
    result = subprocess.run(arguments, capture_output=True, check=False,
                            env=tool_environment(), timeout=60)
    require(result.returncode == 0, "A native distribution verification command failed")
    return result.stdout


def tool_environment():
    # The runner may host unrelated credentials and tool overrides. An allowlist
    # keeps new secret names out of every native child without maintaining a
    # growing denylist. Preserve the selected Xcode and normal login/temp paths;
    # upload-specific key lookup is supplied explicitly by the delivery driver.
    allowed = {"PATH", "HOME", "TMPDIR", "USER", "LOGNAME", "DEVELOPER_DIR",
               "LANG", "__CF_USER_TEXT_ENCODING"}
    environment = {key: value for key, value in os.environ.items() if key in allowed}
    environment["LC_ALL"] = "C"
    return environment


def verify_no_quarantine(root):
    def inspect(path):
        # Python's os.listxattr is Linux-only. macOS xattr lists names without
        # values; -s inspects a symlink itself, preserving the no-follow policy.
        names = command(["/usr/bin/xattr", "-s", str(Path(path).absolute())]).splitlines()
        require(b"com.apple.quarantine" not in names,
                "Quarantine attribute found in distribution artifacts")

    def unreadable(_):
        raise ValueError("Cannot inspect every distribution artifact")
    inspect(root)
    if not stat.S_ISDIR(Path(root).lstat().st_mode):
        return
    for directory, folders, files in os.walk(root, followlinks=False, onerror=unreadable):
        for name in [*folders, *files]:
            inspect(Path(directory) / name)


def verify_code_signature(path, team):
    require(isinstance(team, str) and re.fullmatch(r"[A-Z0-9]{10}", team),
            "Invalid publisher team")
    # Without the leading '=', codesign treats the expression as a file path.
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", "-R",
             f'=anchor apple generic and certificate leaf[subject.OU] = "{team}"', str(path)])


def extract_signing_certificate(path, architecture, scratch):
    require(architecture in ("arm64", "x86_64"), "Unexpected signed architecture")
    prefix = scratch / f"certificate-{uuid.uuid4()}-"
    # This option's value is optional, so it must use --name=value syntax.
    command(["/usr/bin/codesign", "-d", "--arch", architecture,
             f"--extract-certificates={prefix}", str(path)])
    return Path(str(prefix) + "0").read_bytes()


def verify_app(app, root, team, certificate_sha1, scratch):
    version, build = version_settings(root)
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    validate_info(info, version, build)
    validate_resources(contents, root)
    profile = plistlib.loads(command(["/usr/bin/security", "cms", "-D", "-i",
                                     str(contents / "embedded.provisionprofile")]))
    application_id = validate_profile(profile, team, certificate_sha1)
    binary = contents / "MacOS/NoteHush"
    require(set(command(["/usr/bin/lipo", "-archs", str(binary)]).decode().split())
            == {"arm64", "x86_64"}, "Store executable must be universal")
    verify_code_signature(app, team)
    for architecture in ("arm64", "x86_64"):
        result = subprocess.run(["/usr/bin/codesign", "-dvv", "--arch", architecture, str(app)],
                                capture_output=True, check=False, env=tool_environment(), timeout=60)
        require(result.returncode == 0, "Cannot inspect the signed architecture")
        details = result.stderr.decode("utf-8", errors="strict")
        flags = re.search(r"flags=0x[0-9a-fA-F]+\(([^)]*)\)", details)
        require(flags and "runtime" in flags[1].split(","), "Hardened Runtime is required")
        authorities = re.findall(r"^Authority=(.+)$", details, re.M)
        require(authorities and authorities[0].startswith(
            ("Apple Distribution: ", "3rd Party Mac Developer Application: ")),
            "A Mac App Store application signing identity is required")
        signed = plistlib.loads(command(["/usr/bin/codesign", "-d", "--arch", architecture,
                                        "--entitlements", ":-", str(app)]))
        validate_entitlements(signed, team, application_id, profile)
        require(hashlib.sha1(extract_signing_certificate(app, architecture, scratch)).hexdigest().upper()
                == certificate_sha1, "Signed leaf certificate differs from the selected identity")
    verify_no_quarantine(app)
    for code in (contents / "MacOS").iterdir():
        require(code.is_file() and not code.is_symlink(), "Unexpected executable directory entry")
        contents_bytes = code.read_bytes()
        require(not any(marker in contents_bytes for marker in PROBE_MARKERS),
                "Test or performance instrumentation reached a Store executable")
    return {"version": version, "build": build, "architectures": ["arm64", "x86_64"],
            "executableSHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "productEntitlements": PRODUCT_ENTITLEMENTS, "signatureVerified": True}

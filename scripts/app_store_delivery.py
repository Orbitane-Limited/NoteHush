#!/usr/bin/env python3
"""Guarded App Store signing, export, verification, and upload helpers.

All temporary signing material is owned through a mode-0600 manifest in the
workflow runner's temporary directory. The manifest is never an artifact.
"""

from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
import hashlib
import json
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEAM_ID = "4T674XS5MF"
BUNDLE_ID = "pk.codehub.NoteHush"
PROFILE_NAME = "NoteHush Mac App Store Distribution"
MANIFEST_NAME = "notehush-app-store-delivery.json"
SIGNING_ENVIRONMENT_KEYS = {
    "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_BASE64",
    "MAC_APP_DISTRIBUTION_P12_BASE64", "MAC_APP_DISTRIBUTION_P12_PASSWORD",
    "MAC_INSTALLER_DISTRIBUTION_P12_BASE64", "MAC_INSTALLER_DISTRIBUTION_P12_PASSWORD",
    "MAC_APP_STORE_PROFILE_BASE64",
}
EXPECTED_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.print": True,
}
SIGNING_IDENTITY = "Apple Distribution: Muhammad Affan Maqsood (4T674XS5MF)"
INSTALLER_IDENTITY = "3rd Party Mac Developer Installer: Muhammad Affan Maqsood (4T674XS5MF)"
SIGNING_SHA1 = "590F712806B1630222AA19D49E16FA88124E9CFF"
INSTALLER_SHA1 = "A76569FFBACB15D39B54DDB9124BD225DF4B3AF4"


ACTIVE_CHILD: subprocess.Popen | None = None


class DeliveryError(RuntimeError):
    """A safe, user-readable delivery failure with no credential values."""


def command(args: list[str], *, input_bytes: bytes | None = None,
            env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess:
    """Run one process without logging arguments or credential-bearing output."""
    global ACTIVE_CHILD
    try:
        source_env = os.environ if env is None else env
        clean_env = {key: value for key, value in source_env.items()
                     if key not in SIGNING_ENVIRONMENT_KEYS}
        child = subprocess.Popen(args, stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=clean_env,
                                 start_new_session=True)
        ACTIVE_CHILD = child
        try:
            output, error_output = child.communicate(input=input_bytes)
        finally:
            ACTIVE_CHILD = None
    except OSError as error:
        raise DeliveryError(f"Could not start {Path(args[0]).name}: {error.strerror}") from None
    result = subprocess.CompletedProcess(args, child.returncode, stdout=output, stderr=error_output)
    record_tool_output(Path(args[0]).name, result.returncode, (output or b"") + (error_output or b""))
    if check and result.returncode:
        # Do not echo tool output: signing tools can include account metadata.
        raise DeliveryError(f"{Path(args[0]).name} failed (exit {result.returncode}); see retained private runner logs")
    return result


def record_tool_output(tool: str, exit_code: int, output: bytes) -> None:
    """Retain useful failure diagnostics after masking every configured secret."""
    log_path = Path(os.environ.get("NOTEHUSH_APP_STORE_LOG", ROOT / "build/logs/app-store-signing.log"))
    log_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if tool not in {"security", "openssl"}:
        detail = output.decode(errors="replace")
        for key in SIGNING_ENVIRONMENT_KEYS:
            secret = os.environ.get(key)
            if secret:
                detail = detail.replace(secret, "[REDACTED]")
        encoded = detail.encode()
        if len(encoded) > 2 * 1024 * 1024:
            encoded = b"[earlier output omitted]\n" + encoded[-(2 * 1024 * 1024):]
    else:
        encoded = b"[tool output suppressed]\n"
    prefix = f"\n--- {tool} exit={exit_code} ---\n".encode()
    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(log_path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "ab") as stream:
            stream.write(prefix)
            stream.write(encoded)
            if encoded and not encoded.endswith(b"\n"):
                stream.write(b"\n")
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        raise


def private_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)


def decode_secret(name: str, *, optional: bool = False) -> bytes | None:
    raw = os.environ.get(name, "")
    if not raw and optional:
        return None
    if not raw:
        raise DeliveryError(f"Required protected environment secret is missing: {name}")
    try:
        return base64.b64decode(raw, validate=True)
    except ValueError:
        raise DeliveryError(f"Secret {name} must contain base64-encoded file bytes") from None


def read_version() -> tuple[str, int]:
    text = (ROOT / "Config/Version.xcconfig").read_text()
    marketing = re.search(r"^MARKETING_VERSION = (\d+\.\d+\.\d+)$", text, re.M)
    build = re.search(r"^CURRENT_PROJECT_VERSION = ([1-9]\d*)$", text, re.M)
    if not marketing or not build:
        raise DeliveryError("Version.xcconfig must contain a three-part release version and a positive build number")
    return marketing.group(1), int(build.group(1))


def decode_cms_profile(source: Path, destination: Path) -> dict:
    result = command(["/usr/bin/security", "cms", "-D", "-i", str(source)])
    try:
        profile = plistlib.loads(result.stdout)
    except (plistlib.InvalidFileException, ValueError):
        raise DeliveryError("The supplied provisioning profile is not a valid CMS profile") from None
    private_write(destination, plistlib.dumps(profile))
    return profile


def validate_profile(profile: dict, *, now: float | None = None) -> None:
    entitlements = profile.get("Entitlements", {})
    expected_app_id = f"{TEAM_ID}.{BUNDLE_ID}"
    if profile.get("Name") != PROFILE_NAME:
        raise DeliveryError("Provisioning profile name does not match the reviewed NoteHush App Store profile")
    if profile.get("TeamIdentifier") != [TEAM_ID]:
        raise DeliveryError("Provisioning profile belongs to a different Apple team")
    if entitlements.get("application-identifier") != expected_app_id:
        raise DeliveryError("Provisioning profile application identifier does not match NoteHush")
    expiration = profile.get("ExpirationDate")
    if not hasattr(expiration, "timestamp") or expiration.timestamp() <= (time.time() if now is None else now):
        raise DeliveryError("Provisioning profile has expired")
    if entitlements.get("get-task-allow") is not False:
        raise DeliveryError("Distribution profile incorrectly enables debugging")
    if entitlements.get("com.apple.developer.team-identifier") != TEAM_ID:
        raise DeliveryError("Provisioning profile team entitlement does not match NoteHush")
    for key, value in EXPECTED_ENTITLEMENTS.items():
        if entitlements.get(key) != value:
            raise DeliveryError(f"Provisioning profile is missing required sandbox entitlement {key}")


def manifest_path() -> Path:
    runner_temp = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir()))
    return runner_temp / MANIFEST_NAME


def prepare() -> dict:
    """Create owned temporary signing inputs; refuse to claim existing assets."""
    required = (
        "MAC_APP_DISTRIBUTION_P12_BASE64", "MAC_APP_DISTRIBUTION_P12_PASSWORD",
        "MAC_INSTALLER_DISTRIBUTION_P12_BASE64", "MAC_INSTALLER_DISTRIBUTION_P12_PASSWORD",
        "MAC_APP_STORE_PROFILE_BASE64",
    )
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        raise DeliveryError("Missing protected app-store environment secrets: " + ", ".join(missing))
    manifest_file = manifest_path()
    if manifest_file.exists():
        raise DeliveryError("An App Store delivery ownership manifest already exists; inspect it before cleanup")
    profile_blob = decode_secret("MAC_APP_STORE_PROFILE_BASE64")
    cert_blob = decode_secret("MAC_APP_DISTRIBUTION_P12_BASE64")
    installer_blob = decode_secret("MAC_INSTALLER_DISTRIBUTION_P12_BASE64")
    if not all((profile_blob, cert_blob, installer_blob)):
        raise DeliveryError("Protected signing inputs cannot be empty")
    work = Path(tempfile.mkdtemp(prefix="notehush-app-store-", dir=os.environ.get("RUNNER_TEMP")))
    os.chmod(work, 0o700)
    try:
        user_home = Path.home()
        profile_dir = user_home / "Library/MobileDevice/Provisioning Profiles"
        profile_file = work / "distribution.provisionprofile"
        cert_file = work / "distribution.p12"
        installer_file = work / "installer.p12"
        for path, blob in ((profile_file, profile_blob), (cert_file, cert_blob),
                           (installer_file, installer_blob)):
            private_write(path, blob)
        profile = decode_cms_profile(profile_file, work / "profile.plist")
        validate_profile(profile)
        profile_uuid = profile.get("UUID")
        if not isinstance(profile_uuid, str) or not re.fullmatch(r"[A-Fa-f0-9-]{36}", profile_uuid):
            raise DeliveryError("Provisioning profile has no valid UUID")
        installed_profile = profile_dir / f"{profile_uuid}.provisionprofile"
        if installed_profile.exists() or installed_profile.is_symlink():
            raise DeliveryError("Refusing to replace a profile file that this run does not own")
        version, build = read_version()
        manifest = {
            "schema": 1, "owner": "NoteHush App Store delivery",
            "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
            "work_directory": str(work), "user_home": str(user_home),
            "api_home": str(work / "api-home"),
            "profile_path": str(installed_profile),
            "profile_sha256": hashlib.sha256(profile_blob).hexdigest(),
            "keychain_path": str(work / "notehush.keychain-db"),
            "profile_uuid": profile_uuid, "bundle_id": BUNDLE_ID,
            "marketing_version": version, "build_number": build,
        }
        private_write(manifest_file, json.dumps(manifest, sort_keys=True).encode())
        profile_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        private_write(installed_profile, profile_blob)
        if hashlib.sha256(installed_profile.read_bytes()).hexdigest() != manifest["profile_sha256"]:
            raise DeliveryError("Installed provisioning profile differs from the protected profile input")
        return manifest
    except BaseException:
        if not manifest_file.exists():
            shutil.rmtree(work, ignore_errors=True)
        raise

def load_manifest() -> tuple[Path, dict]:
    path = manifest_path()
    try:
        raw = path.read_bytes()
        manifest = json.loads(raw)
    except (OSError, json.JSONDecodeError):
        raise DeliveryError("App Store delivery manifest is missing or malformed; no cleanup was attempted") from None
    if not isinstance(manifest, dict):
        raise DeliveryError("App Store delivery manifest is malformed; no cleanup was attempted")
    runner_temp = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())).resolve()
    work = Path(str(manifest.get("work_directory", "")))
    user_home = Path(str(manifest.get("user_home", "")))
    api_home = Path(str(manifest.get("api_home", "")))
    profile_uuid = manifest.get("profile_uuid")
    expected_profile = user_home / "Library/MobileDevice/Provisioning Profiles" / \
        f"{profile_uuid}.provisionprofile"
    if (manifest.get("schema") != 1 or manifest.get("owner") != "NoteHush App Store delivery"
            or not isinstance(profile_uuid, str) or not re.fullmatch(r"[A-Fa-f0-9-]{36}", profile_uuid)
            or work.parent.resolve() != runner_temp
            or not work.name.startswith("notehush-app-store-")
            or work.is_symlink() or not work.is_dir()
            or api_home != work / "api-home" or api_home.is_symlink()
            or user_home.resolve() != Path.home().resolve()
            or Path(str(manifest.get("keychain_path", ""))) != work / "notehush.keychain-db"
            or Path(str(manifest.get("profile_path", ""))) != expected_profile
            or not re.fullmatch(r"[0-9a-f]{64}", str(manifest.get("profile_sha256", "")))):
        raise DeliveryError("App Store delivery manifest ownership validation failed; no cleanup was attempted")
    return path, manifest


def read_api_key() -> tuple[dict, bytes]:
    manifest_file, manifest = load_manifest()
    del manifest_file
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    key_path = Path(manifest["api_home"]) / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    return {"kid": key_id, "iss": issuer}, key_path.read_bytes()


def b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_ecdsa_to_raw(signature: bytes) -> bytes:
    """Convert OpenSSL's DER-encoded P-256 signature to the JWS 64-byte form."""
    if len(signature) < 8 or signature[0] != 0x30:
        raise DeliveryError("OpenSSL returned an invalid ES256 signature")
    offset = 2
    if signature[1] & 0x80:
        length_size = signature[1] & 0x7f
        offset = 2 + length_size
    if signature[offset] != 0x02:
        raise DeliveryError("OpenSSL returned an invalid ES256 signature")
    r_len = signature[offset + 1]
    r = signature[offset + 2:offset + 2 + r_len]
    offset += 2 + r_len
    if signature[offset] != 0x02:
        raise DeliveryError("OpenSSL returned an invalid ES256 signature")
    s_len = signature[offset + 1]
    s = signature[offset + 2:offset + 2 + s_len]
    r = r.lstrip(b"\x00").rjust(32, b"\x00")
    s = s.lstrip(b"\x00").rjust(32, b"\x00")
    if len(r) != 32 or len(s) != 32:
        raise DeliveryError("OpenSSL returned an invalid ES256 signature")
    return r + s


def asc_token() -> str:
    identifiers, _ = read_api_key()
    manifest_file, manifest = load_manifest()
    del manifest_file
    key_path = Path(manifest["api_home"]) / ".appstoreconnect/private_keys" / f"AuthKey_{identifiers['kid']}.p8"
    header = b64url(json.dumps({"alg": "ES256", "kid": identifiers["kid"], "typ": "JWT"},
                               separators=(",", ":")).encode())
    now = int(time.time())
    payload = b64url(json.dumps({"iss": identifiers["iss"], "iat": now, "exp": now + 600,
                                "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing_input = header + b"." + payload
    signature = command(["/usr/bin/openssl", "dgst", "-sha256", "-sign", str(key_path)],
                        input_bytes=signing_input).stdout
    return (signing_input + b"." + b64url(der_ecdsa_to_raw(signature))).decode()


def asc_get(url: str) -> dict:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != "api.appstoreconnect.apple.com":
        raise DeliveryError("Refusing to send App Store credentials to an untrusted URL")
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {asc_token()}",
                                                   "Accept": "application/json"})
    try:
        class RejectRedirects(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                del req, fp, code, msg, headers, newurl
                return None

        opener = urllib.request.build_opener(RejectRedirects)
        with opener.open(request, timeout=30) as response:
            final_url = urllib.parse.urlparse(response.geturl())
            if final_url.scheme != "https" or final_url.hostname != "api.appstoreconnect.apple.com":
                raise DeliveryError("App Store Connect API redirected to an untrusted URL")
            return json.loads(response.read())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise DeliveryError(f"App Store Connect API request failed ({type(error).__name__})") from None


def prior_builds() -> list[int]:
    query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID, "limit": "200"})
    app_page = asc_get(f"https://api.appstoreconnect.apple.com/v1/apps?{query}")
    apps = app_page.get("data", [])
    if len(apps) != 1 or not apps[0].get("id"):
        raise DeliveryError("Create the pk.codehub.NoteHush app record in App Store Connect before delivery")
    app_id = apps[0]["id"]
    query = urllib.parse.urlencode({"filter[app]": app_id, "limit": "200"})
    next_url = f"https://api.appstoreconnect.apple.com/v1/builds?{query}"
    builds: list[int] = []
    pages = 0
    while next_url:
        pages += 1
        if pages > 100:
            raise DeliveryError("App Store Connect returned too many build-history pages")
        page = asc_get(next_url)
        for build in page.get("data", []):
            value = build.get("attributes", {}).get("version", "")
            if not isinstance(value, str) or not re.fullmatch(r"[1-9]\d*", value):
                raise DeliveryError("App Store Connect contains an unrecognized build number; refusing upload")
            builds.append(int(value))
        next_url = page.get("links", {}).get("next")
    return builds


def import_signing() -> dict:
    manifest_file, manifest = load_manifest()
    work = Path(manifest["work_directory"])
    keychain = Path(manifest["keychain_path"])
    if keychain.exists():
        raise DeliveryError("Temporary signing keychain already exists; refusing to take ownership")
    password = base64.urlsafe_b64encode(os.urandom(32)).decode()
    cert = work / "distribution.p12"
    installer = work / "installer.p12"
    command(["/usr/bin/security", "create-keychain", "-p", password, str(keychain)])
    try:
        command(["/usr/bin/security", "set-keychain-settings", "-lut", "21600", str(keychain)])
        command(["/usr/bin/security", "unlock-keychain", "-p", password, str(keychain)])
        for file, secret in ((cert, "MAC_APP_DISTRIBUTION_P12_PASSWORD"),
                             (installer, "MAC_INSTALLER_DISTRIBUTION_P12_PASSWORD")):
            command(["/usr/bin/security", "import", str(file), "-k", str(keychain), "-P", os.environ[secret],
                     "-T", "/usr/bin/codesign", "-T", "/usr/bin/productbuild", "-T", "/usr/bin/pkgbuild"])
        command(["/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                 "-s", "-k", password, str(keychain)])
        identities = command(["/usr/bin/security", "find-identity", "-v", str(keychain)]).stdout.decode(
            errors="replace")
        profile = plistlib.loads((work / "profile.plist").read_bytes())
        validate_imported_certificates(identities, profile)
        listed = command(["/usr/bin/security", "list-keychains", "-d", "user"]).stdout.decode(errors="replace")
        original = re.findall(r'"([^"\n]+)"', listed)
        if str(keychain) in original:
            raise DeliveryError("Temporary keychain unexpectedly appears in the pre-existing search list")
        manifest["original_keychain_search_list"] = original
        temporary_manifest = manifest_file.with_suffix(".tmp")
        private_write(temporary_manifest, json.dumps(manifest, sort_keys=True).encode())
        os.replace(temporary_manifest, manifest_file)
        command(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *original, str(keychain)])
        manifest["keychain_imported"] = True
        temporary_manifest = manifest_file.with_suffix(".tmp")
        private_write(temporary_manifest, json.dumps(manifest, sort_keys=True).encode())
        os.replace(temporary_manifest, manifest_file)
        return manifest
    except BaseException:
        cleanup()
        raise


def validate_imported_certificates(identities: str, profile: dict) -> None:
    if SIGNING_SHA1 not in identities or SIGNING_IDENTITY not in identities:
        raise DeliveryError("Expected Apple Distribution certificate is absent from the temporary keychain")
    if INSTALLER_SHA1 not in identities or INSTALLER_IDENTITY not in identities:
        raise DeliveryError("Expected Mac Installer Distribution certificate is absent from the temporary keychain")
    validate_profile_signing_certificate(profile)


def validate_profile_signing_certificate(profile: dict) -> None:
    developer_certs = profile.get("DeveloperCertificates", [])
    fingerprints = {hashlib.sha1(certificate).hexdigest().upper()
                    for certificate in developer_certs if isinstance(certificate, bytes)}
    if SIGNING_SHA1 not in fingerprints:
        raise DeliveryError("Provisioning profile does not authorize the pinned Apple Distribution certificate")


def code_sign_identity(path: Path) -> str:
    result = command(["/usr/bin/codesign", "-dv", "--verbose=4", str(path)], check=False)
    detail = ((result.stdout or b"") + (result.stderr or b"")).decode(errors="replace")
    if result.returncode or SIGNING_IDENTITY not in detail:
        raise DeliveryError("App signature does not use the expected Apple Distribution identity")
    return detail


def verify_app(app: Path) -> dict:
    contents = app / "Contents"
    if not app.is_dir() or app.is_symlink():
        raise DeliveryError("Expected a regular NoteHush.app bundle")
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    version, build = read_version()
    expected = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleShortVersionString": version,
                "CFBundleVersion": str(build), "LSMinimumSystemVersion": "14.0",
                "ITSAppUsesNonExemptEncryption": False}
    if any(info.get(key) != value for key, value in expected.items()):
        raise DeliveryError("Signed app bundle metadata differs from Version.xcconfig or release requirements")
    if info.get("CFBundleIconName") != "AppIcon" or not (contents / "Resources/Assets.car").is_file():
        raise DeliveryError("Signed app is missing its compiled AppIcon asset catalog")
    binary = contents / "MacOS/NoteHush"
    if binary.is_symlink() or not binary.is_file():
        raise DeliveryError("Signed app executable is missing or unsafe")
    command(["/usr/bin/lipo", str(binary), "-verify_arch", "arm64", "x86_64"])
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    code_sign_identity(app)
    entitlement_result = command(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)], check=False)
    if entitlement_result.returncode not in (0, 1):
        raise DeliveryError("Unable to read signed application entitlements")
    try:
        entitlements = plistlib.loads(entitlement_result.stdout)
    except (plistlib.InvalidFileException, ValueError):
        raise DeliveryError("Signed application entitlements are not a valid property list") from None
    allowed_entitlements = {
        **EXPECTED_ENTITLEMENTS,
        "application-identifier": f"{TEAM_ID}.{BUNDLE_ID}",
        "com.apple.application-identifier": f"{TEAM_ID}.{BUNDLE_ID}",
        "com.apple.developer.team-identifier": TEAM_ID,
        "get-task-allow": False,
    }
    if (any(entitlements.get(key) != value for key, value in EXPECTED_ENTITLEMENTS.items())
            or any(key not in allowed_entitlements for key in entitlements)
            or any(entitlements.get(key) != value for key, value in allowed_entitlements.items()
                   if key in entitlements and key not in EXPECTED_ENTITLEMENTS)):
        raise DeliveryError("Signed application entitlements differ from the four approved product permissions")
    if plistlib.loads((contents / "Resources/PrivacyInfo.xcprivacy").read_bytes()) != plistlib.loads(
            (ROOT / "App/NoteHush/Resources/PrivacyInfo.xcprivacy").read_bytes()):
        raise DeliveryError("Signed app privacy manifest differs from audited source")
    profile_path = contents / "embedded.provisionprofile"
    if not profile_path.is_file():
        raise DeliveryError("App Store signed app has no embedded provisioning profile")
    result = command(["/usr/bin/security", "cms", "-D", "-i", str(profile_path)])
    profile = plistlib.loads(result.stdout)
    validate_profile(profile)
    validate_profile_signing_certificate(profile)
    executable_data = binary.read_bytes()
    forbidden = (b"NOTEHUSH_TEST_WORKSPACE", b"ProcessToEditorReady", b"performance-editor-ready",
                 b"PerformanceApplication", b"TypingEventDispatch", b"TabEventDispatch")
    if any(marker in executable_data for marker in forbidden):
        raise DeliveryError("Test controls or performance probes reached the release executable")
    return {"bundle_id": BUNDLE_ID, "version": version, "build": build,
            "profile_uuid": profile["UUID"], "architectures": ["arm64", "x86_64"],
            "signing_identity": SIGNING_IDENTITY, "entitlements": EXPECTED_ENTITLEMENTS}


def archive_and_export() -> None:
    """Create and verify the signed package, without transmitting it externally."""
    _, manifest = load_manifest()
    work = Path(manifest["work_directory"])
    env = dict(os.environ)
    archive = work / "NoteHush.xcarchive"
    output = work / "export"
    output.mkdir(mode=0o700)
    version, build = read_version()
    export_options = {
        "destination": "export", "method": "app-store-connect", "teamID": TEAM_ID,
        "signingStyle": "manual", "signingCertificate": SIGNING_IDENTITY,
        "installerSigningCertificate": INSTALLER_IDENTITY,
        "provisioningProfiles": {BUNDLE_ID: PROFILE_NAME}, "uploadSymbols": True,
    }
    options = work / "ExportOptions.plist"
    private_write(options, plistlib.dumps(export_options))
    command(["/usr/bin/xcodebuild", "-project", str(ROOT / "NoteHush.xcodeproj"), "-scheme", "NoteHush",
             "-configuration", "Release", "-destination", "generic/platform=macOS", "-archivePath", str(archive),
             "-derivedDataPath", str(work / "DerivedData"), "CODE_SIGN_STYLE=Manual",
             f"DEVELOPMENT_TEAM={TEAM_ID}", f"CODE_SIGN_IDENTITY={SIGNING_IDENTITY}",
             f"PROVISIONING_PROFILE_SPECIFIER={PROFILE_NAME}", "archive"], env=env)
    archived_app = archive / "Products/Applications/NoteHush.app"
    verification = verify_app(archived_app)
    if verification["profile_uuid"] != manifest["profile_uuid"]:
        raise DeliveryError("Signed archive does not embed the profile installed by this delivery run")
    command(["/usr/bin/xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(output),
             "-exportOptionsPlist", str(options)], env=env)
    packages = list(output.glob("*.pkg"))
    if len(packages) != 1 or packages[0].is_symlink():
        raise DeliveryError("Xcode must export exactly one regular Mac App Store package")
    package = packages[0]
    signature = command(["/usr/sbin/pkgutil", "--check-signature", str(package)]).stdout.decode(errors="replace")
    if INSTALLER_IDENTITY not in signature:
        raise DeliveryError("Exported package is not signed by the expected Mac Installer distribution identity")
    expanded = work / "expanded-package"
    command(["/usr/sbin/pkgutil", "--expand-full", str(package), str(expanded)])
    packaged_apps = [path for path in expanded.rglob("NoteHush.app") if path.is_dir() and not path.is_symlink()]
    if len(packaged_apps) != 1:
        raise DeliveryError("Exported package must contain exactly one NoteHush.app")
    packaged_verification = verify_app(packaged_apps[0])
    for key in ("bundle_id", "version", "build", "profile_uuid", "architectures", "signing_identity"):
        if packaged_verification[key] != verification[key]:
            raise DeliveryError(f"Exported package {key} differs from the signed archive")
    artifact_dir = ROOT / "build/app-store-export"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    destination = artifact_dir / "NoteHush.pkg"
    if destination.exists() or destination.is_symlink():
        raise DeliveryError("Refusing to overwrite an existing App Store export artifact")
    shutil.copyfile(package, destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    private_write(artifact_dir / "SHA256SUMS", f"{digest}  NoteHush.pkg\n".encode())
    private_write(artifact_dir / "DELIVERY-MANIFEST.json", json.dumps(
        {**verification, "candidate_validation": "passed"}, sort_keys=True, indent=2).encode())
    manifest["package_sha256"] = digest
    temporary_manifest = manifest_path().with_suffix(".update")
    private_write(temporary_manifest, json.dumps(manifest, sort_keys=True).encode())
    os.replace(temporary_manifest, manifest_path())


def install_api_key() -> Path:
    """Place the ASC private key in this run's isolated HOME for Apple's uploader."""
    key_id = os.environ.get("ASC_KEY_ID", "")
    issuer = os.environ.get("ASC_ISSUER_ID", "")
    if not re.fullmatch(r"[A-Z0-9]{10}", key_id) or not re.fullmatch(
            r"[A-Fa-f0-9-]{36}", issuer):
        raise DeliveryError("App Store Connect key ID or issuer ID has an invalid format")
    data = decode_secret("ASC_PRIVATE_KEY_BASE64")
    if not data or not data.startswith(b"-----BEGIN PRIVATE KEY-----"):
        raise DeliveryError("App Store Connect private key is not a PKCS#8 PEM key")
    _, manifest = load_manifest()
    key_path = Path(manifest["api_home"]) / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    private_write(key_path, data)
    return key_path


def _upload_to_app_store() -> None:
    """Check all prior build pages, then explicitly upload the prepared package."""
    key_path = install_api_key()
    _, manifest = load_manifest()
    package = ROOT / "build/app-store-export/NoteHush.pkg"
    checksum_file = ROOT / "build/app-store-export/SHA256SUMS"
    metadata_file = ROOT / "build/app-store-export/DELIVERY-MANIFEST.json"
    if (not package.is_file() or package.is_symlink() or not checksum_file.is_file()
            or not metadata_file.is_file()):
        raise DeliveryError("The verified signed package and its allowlisted metadata are not staged")
    expected_digest = checksum_file.read_text().split()[0]
    actual_digest = hashlib.sha256(package.read_bytes()).hexdigest()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_digest) or actual_digest != expected_digest:
        raise DeliveryError("Staged App Store package checksum does not match")
    metadata = json.loads(metadata_file.read_text())
    if (metadata.get("bundle_id") != BUNDLE_ID or metadata.get("version") != manifest["marketing_version"]
            or metadata.get("build") != manifest["build_number"]
            or metadata.get("candidate_validation") != "passed"
            or actual_digest != manifest.get("package_sha256")):
        raise DeliveryError("Staged delivery manifest does not match this run")
    prior = prior_builds()
    build = int(manifest["build_number"])
    if prior and build <= max(prior):
        raise DeliveryError(f"Build {build} is not greater than the highest prior App Store build {max(prior)}")
    env = dict(os.environ, HOME=str(manifest["api_home"]), USER=Path.home().name)
    command(["/usr/bin/xcrun", "altool", "--upload-app", "--type", "macos", "--file", str(package),
             "--apiKey", os.environ["ASC_KEY_ID"], "--apiIssuer", os.environ["ASC_ISSUER_ID"]], env=env)
    print("Apple accepted the upload request. Processing and TestFlight availability remain pending.")


def upload_to_app_store() -> None:
    with child_process_guard():
        _upload_to_app_store()


def stage() -> None:
    """Prepare signing and stage a verified package for the later upload step."""
    with child_process_guard():
        prepare()
        import_signing()
        archive_and_export()


@contextmanager
def child_process_guard():
    """Terminate the active child process group on workflow cancellation."""
    old_handlers = {}

    def handle_signal(signum, _frame):
        child = ACTIVE_CHILD
        if child and child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                raise SystemExit(128 + signum)
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
        raise SystemExit(128 + signum)

    for signum in (signal.SIGINT, signal.SIGTERM):
        old_handlers[signum] = signal.signal(signum, handle_signal)
    try:
        yield
    finally:
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)


def run() -> None:
    """Local one-shot convenience; the Actions workflow keeps stage/upload separate."""
    try:
        stage()
        upload_to_app_store()
    finally:
        cleanup()


def _cleanup() -> None:
    """Remove only paths whose ownership is proven by the private manifest."""
    manifest_file = manifest_path()
    if not manifest_file.exists():
        return
    _, manifest = load_manifest()
    profile_path = Path(manifest["profile_path"])
    work = Path(manifest["work_directory"])
    keychain = Path(manifest["keychain_path"])
    try:
        original = manifest.get("original_keychain_search_list")
        if isinstance(original, list) and all(isinstance(item, str) for item in original):
            command(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *original])
        if keychain.exists():
            command(["/usr/bin/security", "delete-keychain", str(keychain)])
        if profile_path.is_symlink():
            raise DeliveryError("Provisioning profile ownership changed; refusing to remove a symlink")
        if profile_path.exists():
            if (not profile_path.is_file()
                    or profile_path.name != f"{manifest.get('profile_uuid')}.provisionprofile"
                    or hashlib.sha256(profile_path.read_bytes()).hexdigest() != manifest.get("profile_sha256")):
                raise DeliveryError("Provisioning profile changed after installation; preserving it and the recovery manifest")
            profile_path.unlink()
        shutil.rmtree(work)
        manifest_file.unlink()
    except OSError as error:
        raise DeliveryError(f"Temporary signing cleanup failed ({error.__class__.__name__}); inspect the workflow runner") from None


def cleanup() -> None:
    with child_process_guard():
        _cleanup()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("run", "stage", "upload", "cleanup", "verify"))
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "run":
            run()
        elif args.command == "stage":
            stage()
        elif args.command == "upload":
            upload_to_app_store()
        elif args.command == "cleanup":
            cleanup()
        elif args.command == "verify":
            if args.app is None:
                parser.error("verify requires --app")
            print(json.dumps(verify_app(args.app), sort_keys=True))
    except DeliveryError as error:
        print(f"App Store delivery failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

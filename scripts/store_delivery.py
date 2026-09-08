#!/usr/bin/env python3
"""Manual main-only Store delivery. Credentials live in an owned temporary root.

No command line, credential, raw Apple response or signing log is printed.
The workflow retains only an allowlisted validation report and signed package.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import uuid

from app_store_checks import BUNDLE_ID, canonical_profile_uuid, require, tool_environment, validate_profile, verify_app, verify_no_quarantine, version_settings
from store_connect import StoreConnect
from store_preflight import ROOT, verify as verify_source


def secret(name):
    value = os.environ.get(name, "")
    require(bool(value), "Missing signing environment configuration")
    return value


def private_write(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def task_root():
    run_id, attempt = secret("GITHUB_RUN_ID"), secret("GITHUB_RUN_ATTEMPT")
    require(re.fullmatch(r"[1-9]\d*", run_id) and re.fullmatch(r"[1-9]\d*", attempt),
            "Invalid delivery run identity")
    parent = Path(secret("RUNNER_TEMP")).resolve(strict=True)
    return parent / f"NoteHush-Signing-{run_id}-{attempt}"


class SigningAssets:
    def __init__(self, directory, profile_directory, run):
        self.directory = directory
        self.profile_directory = profile_directory
        self.run = run
        self.keychain = directory / "signing.keychain-db"

    def create(self):
        self.directory.mkdir(mode=0o700)
        private_write(self.directory / "owner.json", b'{"owner":"NoteHush Store delivery","schema":1}')

    def install_profile(self, profile_path, profile_uuid):
        # Link a file whose inode we already own. The cleanup record can be
        # durable before publication, without claiming an existing profile.
        profile_uuid = canonical_profile_uuid(profile_uuid)
        self.profile_directory.mkdir(parents=True, exist_ok=True)
        destination = self.profile_directory / f"{profile_uuid}.provisionprofile"
        source = profile_path.stat()
        state = {"name": destination.name, "device": source.st_dev, "inode": source.st_ino,
                 "sha256": hashlib.sha256(profile_path.read_bytes()).hexdigest()}
        private_write(self.directory / "profile.json", json.dumps(state).encode())
        try:
            os.link(profile_path, destination)
        except FileExistsError:
            require(not destination.is_symlink() and destination.is_file()
                    and destination.read_bytes() == profile_path.read_bytes(),
                    "An existing provisioning profile differs; it was preserved")

    def import_keychain(self, p12_path, password):
        keychain_password = secrets.token_urlsafe(32)
        self.run(["security", "create-keychain", "-p", keychain_password, str(self.keychain)])
        self.run(["security", "set-keychain-settings", "-lut", "1800", str(self.keychain)])
        self.run(["security", "unlock-keychain", "-p", keychain_password, str(self.keychain)])
        self.run(["security", "import", str(p12_path), "-k", str(self.keychain), "-P", password,
                  "-T", "/usr/bin/codesign", "-T", "/usr/bin/productbuild", "-T", "/usr/bin/productsign"])
        self.run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s",
                  "-k", keychain_password, str(self.keychain)])
        current = shlex.split(self.run(["security", "list-keychains", "-d", "user"]).decode())
        if str(self.keychain) not in current:
            self.run(["security", "list-keychains", "-d", "user", "-s", *current, str(self.keychain)])

    def cleanup(self):
        if not self.directory.exists():
            return
        require(not self.directory.is_symlink(), "Refusing an unowned signing directory")
        owner = json.loads((self.directory / "owner.json").read_text())
        require(owner == {"owner": "NoteHush Store delivery", "schema": 1}, "Invalid signing ownership")
        errors = []
        # Retry search-list cleanup even if a prior attempt already deleted the
        # keychain file. Preserve concurrent changes to all unrelated entries.
        try:
            current = shlex.split(self.run(["security", "list-keychains", "-d", "user"]).decode())
            remaining = [value for value in current if Path(value) != self.keychain]
            if remaining != current:
                self.run(["security", "list-keychains", "-d", "user", "-s", *remaining])
        except Exception:
            errors.append("search list")
        if self.keychain.exists():
            try:
                self.run(["security", "delete-keychain", str(self.keychain)])
            except Exception:
                errors.append("keychain")
        state_path = self.directory / "profile.json"
        if state_path.exists():
            try:
                state = json.loads(state_path.read_text())
                require(re.fullmatch(r"[0-9A-F-]{36}\.provisionprofile", state["name"]),
                        "Invalid profile cleanup record")
                installed = self.profile_directory / state["name"]
                if installed.exists() or installed.is_symlink():
                    info = installed.lstat()
                    if (info.st_dev, info.st_ino) == (state["device"], state["inode"]):
                        require(not installed.is_symlink() and installed.is_file()
                                and hashlib.sha256(installed.read_bytes()).hexdigest() == state["sha256"],
                                "Installed signing profile changed; preserved for inspection")
                        installed.unlink()
            except Exception:
                errors.append("profile")
        # Even when native cleanup fails, remove the plaintext copies of the
        # private key and PKCS#12. Keep only ownership metadata for a cleanup retry.
        for name in ("signing.p12", "private_keys"):
            path = self.directory / name
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            elif path.exists() or path.is_symlink():
                path.unlink()
        require(not errors, "Signing cleanup incomplete; quarantine this runner until resolved")
        shutil.rmtree(self.directory)


def native(arguments, *, environment=None):
    # Child tools receive only the environment they need. Never inherit the
    # workflow's PKCS#12/password/API-key variables into Xcode or upload tooling.
    child = tool_environment()
    child.update(environment or {})
    process = subprocess.Popen(arguments, cwd=ROOT, env=child, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=1500)
    except BaseException:
        # Stop build/upload descendants before deleting their signing keychain.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        raise
    if process.returncode:
        diagnostics = ROOT / "build/store-private"
        diagnostics.mkdir(parents=True, exist_ok=True, mode=0o700)
        private_write(diagnostics / f"failed-tool-{uuid.uuid4()}.log", stdout + b"\n" + stderr)
        raise ValueError("A Store delivery tool failed; private diagnostics retained locally")
    return stdout


def deliver(assets):
    revision = verify_source()
    version, build = version_settings(ROOT)
    team = secret("STORE_TEAM_ID")
    app_certificate = secret("STORE_APP_CERTIFICATE_SHA1").upper()
    installer_certificate = secret("STORE_INSTALLER_CERTIFICATE_SHA1").upper()
    installer_sha256 = secret("STORE_INSTALLER_CERTIFICATE_SHA256").upper()
    require(re.fullmatch(r"[A-Z0-9]{10}", team), "Invalid team ID")
    for value, length in [(app_certificate, 40), (installer_certificate, 40), (installer_sha256, 64)]:
        require(re.fullmatch(r"[0-9A-F]{" + str(length) + "}", value), "Invalid signing certificate pin")
    require(secret("STORE_CONFIRMED_BUNDLE_ID") == BUNDLE_ID, "Publisher must confirm the bundle ID")
    require(native(["xcodebuild", "-version"]).decode().splitlines()[0] == "Xcode 26.6",
            "Review the delivery toolchain before changing Xcode")
    native(["python3", "scripts/verify_configuration.py"])
    private_write(assets.directory / "signing.p12", base64.b64decode(secret("STORE_SIGNING_P12_BASE64"), validate=True))
    profile_path = assets.directory / "profile.provisionprofile"
    private_write(profile_path, base64.b64decode(secret("STORE_PROFILE_BASE64"), validate=True))
    profile = plistlib.loads(native(["security", "cms", "-D", "-i", str(profile_path)]))
    validate_profile(profile, team, app_certificate)
    key_id, issuer = secret("STORE_API_KEY_ID"), secret("STORE_API_ISSUER_ID")
    require(re.fullmatch(r"[A-Z0-9]{10}", key_id), "Invalid API key identity")
    key_directory = assets.directory / "private_keys"
    key_directory.mkdir(mode=0o700)
    api_key = key_directory / f"AuthKey_{key_id}.p8"
    private_write(api_key, base64.b64decode(secret("STORE_API_KEY_BASE64"), validate=True))
    store = StoreConnect(api_key, key_id, issuer, secret("STORE_APP_ID"))
    previous_build = store.check_next_build(build)
    assets.install_profile(profile_path, profile["UUID"])
    assets.import_keychain(assets.directory / "signing.p12", secret("STORE_SIGNING_P12_PASSWORD"))
    identities = native(["security", "find-identity", "-v", str(assets.keychain)]).decode()
    require(app_certificate in identities and installer_certificate in identities,
            "Both selected Store signing identities must have usable private keys")
    output = ROOT / "build/store-delivery" / f"{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
    output.mkdir(parents=True, mode=0o700)
    archive = output / "NoteHush.xcarchive"
    native(["xcodebuild", "-project", "NoteHush.xcodeproj", "-scheme", "NoteHush",
            "-configuration", "Release", "-destination", "generic/platform=macOS",
            "-derivedDataPath", str(output / "DerivedData"), "-archivePath", str(archive),
            "CODE_SIGN_STYLE=Manual", f"DEVELOPMENT_TEAM={team}", f"CODE_SIGN_IDENTITY={app_certificate}",
            f"PROVISIONING_PROFILE_SPECIFIER={profile['UUID']}",
            "OTHER_CODE_SIGN_FLAGS=--keychain " + shlex.quote(str(assets.keychain)), "archive"])
    report = verify_app(archive / "Products/Applications/NoteHush.app", ROOT, team, app_certificate, assets.directory)
    verify_no_quarantine(archive)
    export_options = {
        "method": "app-store-connect", "destination": "export", "teamID": team,
        "signingStyle": "manual", "signingCertificate": app_certificate,
        "installerSigningCertificate": installer_certificate,
        "provisioningProfiles": {BUNDLE_ID: profile["UUID"]},
        "manageAppVersionAndBuildNumber": False, "uploadSymbols": True,
    }
    options_path = assets.directory / "ExportOptions.plist"
    private_write(options_path, plistlib.dumps(export_options))
    export = output / "Export"
    native(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(export),
            "-exportOptionsPlist", str(options_path)])
    packages = list(export.glob("*.pkg"))
    require(len(packages) == 1, "Expected one exported Store package")
    package = packages[0]
    signature = native(["pkgutil", "--check-signature", str(package)]).decode()
    require("3rd Party Mac Developer Installer:" in signature
            and installer_sha256 in re.sub(r"\s+", "", signature).upper(),
            "Package signature does not match the selected Store installer certificate")
    verify_no_quarantine(package)
    expanded = output / "Expanded"
    native(["pkgutil", "--expand-full", str(package), str(expanded)])
    exported_apps = list(expanded.rglob("NoteHush.app"))
    require(len(exported_apps) == 1, "Expected exactly one NoteHush app in the package")
    exported_report = verify_app(exported_apps[0], ROOT, team, app_certificate, assets.directory)
    # Recheck immediately before upload; Xcode must never silently manage builds.
    verify_source()
    previous_build = store.check_next_build(build)
    authentication = ["--api-key", key_id, "--api-issuer", issuer]
    upload_environment = {"API_PRIVATE_KEYS_DIR": str(key_directory)}
    native(["xcrun", "altool", "--validate-app", str(package), *authentication], environment=upload_environment)
    native(["xcrun", "altool", "--upload-package", str(package), *authentication], environment=upload_environment)
    # A zero exit confirms upload tooling succeeded, not processing, installation,
    # TestFlight acceptance, App Review approval, or a public release.
    report.update({"sourceRevision": revision, "ciRunID": os.environ["NOTEHUSH_CI_RUN_ID"],
                   "priorMaximumUploadedBuild": previous_build,
                   "packageSHA256": hashlib.sha256(package.read_bytes()).hexdigest(),
                   "exportedExecutableSHA256": exported_report["executableSHA256"],
                   "uploadToolSucceeded": True, "processingVerified": False,
                   "testFlightInstallationVerified": False, "appReviewSubmitted": False})
    deliverables = output / "Verified"
    deliverables.mkdir(mode=0o700)
    shutil.copy2(package, deliverables / "NoteHush-APP-STORE.pkg")
    private_write(deliverables / "validation.json", (json.dumps(report, indent=2) + "\n").encode())
    private_write(deliverables / "SHA256SUMS", (report["packageSHA256"] + "  NoteHush-APP-STORE.pkg\n").encode())
    print("Store upload tool succeeded. Processing and installed TestFlight acceptance remain unverified.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cleanup", action="store_true")
    arguments = parser.parse_args()
    os.umask(0o077)
    # SIGTERM from cancellation must unwind Python's finally block. The workflow
    # also runs cleanup independently; SIGKILL/host loss needs the retained record.
    def interrupt(*_):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupt)
    assets = SigningAssets(task_root(), Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles", native)
    if arguments.cleanup:
        assets.cleanup()
        return
    verify_source()
    assets.create()
    try:
        deliver(assets)
    finally:
        assets.cleanup()


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt):
        print("Store delivery did not complete. Check configuration, run state and signing cleanup before retrying.",
              file=sys.stderr)
        sys.exit(1)

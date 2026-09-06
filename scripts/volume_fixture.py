#!/usr/bin/env python3
"""Host-side APFS fixture; the sandboxed UI runner cannot manage disk images."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import uuid

BASE = Path(__file__).resolve().parents[1] / "build"
MANIFEST = BASE / "volume-fixture.json"
ROOTS = BASE / "volume-fixtures"
LOCK = BASE / "volume-fixture.lock"


def disk_image(*arguments):
    result = subprocess.run(["hdiutil", *map(str, arguments)], capture_output=True, text=True,
                            timeout=30, check=False)
    if result.returncode:
        # Only fixture paths can occur in this command's output; keep logs concise.
        raise RuntimeError(f"Disk-image {arguments[0]} failed: {result.stderr.strip()}")


def load_fixture():
    data = json.loads(MANIFEST.read_text())
    identifier = str(uuid.UUID(data["workspace"])).upper()
    root = ROOTS / identifier
    if data.get("root") != str(root) or data.get("source") != str(root / "Volume/volume.txt"):
        raise ValueError("Refusing an unexpected fixture location")
    return data, root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["create", "detach", "cleanup"])
    action = parser.parse_args().action
    if action == "create":
        if MANIFEST.exists():
            raise RuntimeError("An existing volume fixture needs cleanup before another run")
        identifier = str(uuid.uuid4()).upper()
        root = ROOTS / identifier
        root.mkdir(parents=True)
        (root / "Volume").mkdir()
        data = {"workspace": identifier, "root": str(root),
                "source": str(root / "Volume/volume.txt"), "phase": "mounted"}
        # Record ownership before mounting, so the shell's EXIT trap can clean up
        # an interrupted setup. Cleanup is confined to this generated UUID root.
        MANIFEST.write_text(json.dumps(data))
        disk_image("create", "-size", "128m", "-fs", "APFS", "-volname", "NoteHushFixture",
                   root / "fixture.dmg")
        disk_image("attach", root / "fixture.dmg", "-mountpoint", root / "Volume", "-nobrowse")
        (root / "Volume/volume.txt").write_text("volume original")
        print("Disposable APFS fixture mounted")
        return
    if not MANIFEST.exists():
        if action == "cleanup":
            if LOCK.exists():
                LOCK.rmdir()
            return
        raise RuntimeError("No volume fixture is available")
    data, root = load_fixture()
    if (root / "Volume").is_mount():
        disk_image("detach", root / "Volume")
    if action == "detach":
        data["phase"] = "offline"
        MANIFEST.write_text(json.dumps(data))
        print("APFS fixture detached for offline restoration test")
    else:
        # Never remove through a still-mounted volume after failed detachment.
        if (root / "Volume").is_mount():
            raise RuntimeError("Fixture is still mounted; refusing cleanup")
        shutil.rmtree(root)
        MANIFEST.unlink()
        if LOCK.exists():
            LOCK.rmdir()
        print("Disposable APFS fixture removed")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Retain generated CI logs privately when GitHub artifact upload fails."""
from argparse import ArgumentParser
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_MANIFESTS = ("build/performance-fixtures.json", "build/interaction-fixtures.json")


def _copy_file(source: Path, destination: Path) -> tuple[int, bytes]:
    digest = hashlib.sha256()
    total = 0
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with source.open("rb") as input_file, destination.open("xb") as output_file:
        os.chmod(destination, 0o600)
        while block := input_file.read(1024 * 1024):
            output_file.write(block)
            digest.update(block)
            total += len(block)
        output_file.flush()
        os.fsync(output_file.fileno())
    return total, digest.digest()


def _copy_tree(source: Path, destination: Path, label: str, tree_hash) -> tuple[int, int]:
    file_count = 0
    total_bytes = 0
    for root, directory_names, file_names in os.walk(source, topdown=True, followlinks=False):
        root_path = Path(root)
        relative_root = root_path.relative_to(source)
        target_root = destination / relative_root
        target_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        for name in directory_names:
            item = root_path / name
            if item.is_symlink() or not item.is_dir():
                raise ValueError("nonRegularDirectory")
        for name in file_names:
            item = root_path / name
            metadata = item.lstat()
            if not stat.S_ISREG(metadata.st_mode):
                raise ValueError("nonRegularFile")
            relative = item.relative_to(source)
            size, digest = _copy_file(item, destination / relative)
            tree_hash.update(f"{label}/{relative.as_posix()}".encode("utf-8"))
            tree_hash.update(b"\0")
            tree_hash.update(digest)
            file_count += 1
            total_bytes += size
    return file_count, total_bytes


def preserve_failure_logs(
    source: Path,
    destination_root: Path,
    run_id: str,
    attempt: str,
    include_fixture_manifests: bool = False,
) -> Path | None:
    if not re.fullmatch(r"[0-9]+", run_id) or not re.fullmatch(r"[0-9]+", attempt):
        raise ValueError("invalidRunIdentity")
    source = source.absolute()
    if source.is_symlink():
        raise ValueError("sourceIsSymlink")
    included = [source] if source.exists() else []
    if included and not source.is_dir():
        raise ValueError("sourceIsNotDirectory")
    if include_fixture_manifests:
        for relative in FIXTURE_MANIFESTS:
            candidate = ROOT / relative
            if candidate.exists():
                if candidate.is_symlink() or not candidate.is_file():
                    raise ValueError("invalidFixtureManifest")
                included.append(candidate)
    if not included:
        return None

    destination_root = destination_root.absolute()
    if destination_root.is_symlink():
        raise ValueError("destinationIsSymlink")
    destination_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(destination_root, 0o700)
    final = destination_root / f"{run_id}-{attempt}"
    if final.exists() or final.is_symlink():
        raise FileExistsError("runEvidenceAlreadyExists")
    temporary = Path(tempfile.mkdtemp(prefix=f".{run_id}-{attempt}-", dir=destination_root))
    os.chmod(temporary, 0o700)
    tree_hash = hashlib.sha256()
    file_count = 0
    total_bytes = 0
    try:
        for item in included:
            label = "logs" if item == source else f"fixture-manifests/{item.name}"
            target = temporary / label
            if item.is_dir():
                count, size = _copy_tree(item, target, label, tree_hash)
                file_count += count
                total_bytes += size
            else:
                size, digest = _copy_file(item, target)
                tree_hash.update(label.encode("utf-8"))
                tree_hash.update(b"\0")
                tree_hash.update(digest)
                file_count += 1
                total_bytes += size
        if file_count == 0:
            shutil.rmtree(temporary)
            return None
        manifest = {
            "schema": 1,
            "runID": run_id,
            "runAttempt": attempt,
            "capturedAt": datetime.now(timezone.utc).isoformat(),
            "fileCount": file_count,
            "totalBytes": total_bytes,
            "contentTreeSHA256": tree_hash.hexdigest(),
        }
        manifest_path = temporary / "evidence.json"
        with manifest_path.open("x", encoding="utf-8") as output_file:
            json.dump(manifest, output_file, separators=(",", ":"), sort_keys=True)
            output_file.write("\n")
            output_file.flush()
            os.fsync(output_file.fileno())
        os.chmod(manifest_path, 0o600)
        os.rename(temporary, final)
        directory_fd = os.open(destination_root, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        return final
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def main() -> int:
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", default=os.environ.get("GITHUB_RUN_ID", ""))
    parser.add_argument("--attempt", default=os.environ.get("GITHUB_RUN_ATTEMPT", ""))
    parser.add_argument("--include-fixture-manifests", action="store_true")
    parser.add_argument(
        "--destination-root",
        type=Path,
        default=Path.home() / "Library/NoteHushActionsRunner/_failure-evidence/Orbitane-Limited/NoteHush",
    )
    args = parser.parse_args()
    try:
        result = preserve_failure_logs(
            ROOT / "build/logs", args.destination_root, args.run_id, args.attempt,
            args.include_fixture_manifests,
        )
    except (OSError, ValueError) as error:
        message = str(error) if type(error) is ValueError else type(error).__name__
        print(f"Could not preserve CI failure evidence locally ({message}).", file=sys.stderr)
        return 1
    if result is None:
        print("No CI failure logs or fixture manifests were available for local preservation.")
        return 0
    manifest = json.loads((result / "evidence.json").read_text(encoding="utf-8"))
    print(
        "Preserved CI failure evidence locally "
        f"(files={manifest['fileCount']}, bytes={manifest['totalBytes']})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

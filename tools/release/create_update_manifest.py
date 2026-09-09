#!/usr/bin/env python3
"""Create a signed update manifest and fixed-name GitHub release assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--version-code", required=True, type=int)
    parser.add_argument("--minimum-version", default="0.1.0")
    parser.add_argument("--release-notes", required=True)
    parser.add_argument(
        "--apk-url",
        required=True,
        help=(
            "HTTPS APK URL. Use the GitHub Releases Assets API address, "
            "not the github.com webpage download link."
        ),
    )
    parser.add_argument("--private-key", required=True, type=Path)
    parser.add_argument("--output-directory", required=True, type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    args = parse_args()
    if not args.apk.is_file():
        raise SystemExit(f"APK not found: {args.apk}")
    if not args.private_key.is_file():
        raise SystemExit(f"Private key not found: {args.private_key}")

    args.output_directory.mkdir(parents=True, exist_ok=True)
    release_apk = args.output_directory / "xiuxian.apk"
    manifest_path = args.output_directory / "update.json"
    signature_path = args.output_directory / "update.sig"
    shutil.copyfile(args.apk, release_apk)

    manifest = {
        "schema_version": 1,
        "version": args.version,
        "version_code": args.version_code,
        "minimum_version": args.minimum_version,
        "apk_url": args.apk_url,
        "apk_size": release_apk.stat().st_size,
        "apk_sha256": sha256(release_apk),
        "release_notes": args.release_notes,
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    subprocess.run(
        [
            "/usr/bin/openssl",
            "dgst",
            "-sha256",
            "-sign",
            str(args.private_key),
            "-out",
            str(signature_path),
            str(manifest_path),
        ],
        check=True,
    )

    print(f"APK: {release_apk}")
    print(f"SHA-256: {manifest['apk_sha256']}")
    print(f"Manifest: {manifest_path}")
    print(f"Signature: {signature_path}")


if __name__ == "__main__":
    main()

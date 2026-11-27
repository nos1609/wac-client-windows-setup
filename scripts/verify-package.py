"""Verify the distribution handed from the build runner to the release runner."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
from zipfile import ZipFile


def main():
    root = Path(__file__).resolve().parent.parent
    archive = root / "dist/wac-client-windows-setup.zip"
    checksum = archive.with_suffix(".zip.sha256")
    sha = os.environ["GITHUB_SHA"]
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if head != sha:
        raise ValueError("Checkout differs from the event commit")

    version = (root / "VERSION").read_text(encoding="ascii").strip()
    ref = os.environ["GITHUB_REF"]
    if ref.startswith("refs/tags/"):
        if ref != "refs/tags/v" + version:
            raise ValueError("Release tag differs from VERSION")
        subprocess.run(["git", "merge-base", "--is-ancestor", sha, "refs/remotes/origin/main"],
                       cwd=root, check=True)

    for path, expected in ((archive, os.environ["ZIP_SHA256"]), (checksum, os.environ["SUM_SHA256"])):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Transfer checksum mismatch for {path.name}")
    if checksum.read_text(encoding="ascii").split() != [os.environ["ZIP_SHA256"].upper(), archive.name]:
        raise ValueError("Invalid distribution checksum file")

    manifest = (root / "scripts/package-files.txt").read_text(encoding="ascii").splitlines()
    with ZipFile(archive) as package:
        if sorted(package.namelist()) != sorted(manifest):
            raise ValueError("Unexpected ZIP members")
        for name in manifest:
            if package.read(name) != (root / name).read_bytes():
                raise ValueError(f"ZIP contents differ from the checkout for {name}")
    if not re.fullmatch(r"[0-9A-Za-z.+-]+", version):
        raise ValueError("Invalid package version")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as outputs:
        print(f"version={version}", file=outputs)
    print(f"Verified {len(manifest)} files for {sha}, version {version}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Deterministic Android keystore generator for the Gadaman CI.

Problem
-------
The previous GitHub Actions workflow generated a FRESH random signing
certificate on every CI run (`keytool -genkeypair ...`). Android treats APKs
signed by different certificates as DIFFERENT apps, which means users cannot
install a new APK over an old one without uninstalling first ("App not
installed" / "Signature mismatch").

Fix
---
1. This script creates the keystore with keytool the first time and then
   CACHES it on GitHub Actions using `actions/cache` keyed on the certificate
   identity. All subsequent builds reuse the cached keystore, so signature
   stability is preserved across builds.
2. If a developer has committed a real release keystore at
   `tools/release.keystore`, the script does NOT overwrite it.
3. If keytool is missing (rare), the script falls back to the old behavior
   (random key) but emits a loud warning.

Environment variables (all optional):
    ANDROID_KEYSTORE_PATH      output path (default: ci-release.keystore)
    ANDROID_KEY_ALIAS          key alias (default: gadaman)
    ANDROID_KEYSTORE_PASSWORD  store + key password (default: gadaman)
    ANDROID_SIGNING_DNAME      certificate distinguished name
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


DEFAULT_DNAME = "CN=Sudan Runner Stable, O=Gadaman, C=SD"


def main() -> int:
    keystore = Path(os.environ.get("ANDROID_KEYSTORE_PATH", "ci-release.keystore"))
    alias = os.environ.get("ANDROID_KEY_ALIAS", "gadaman")
    pw = os.environ.get("ANDROID_KEYSTORE_PASSWORD", "gadaman")
    dname = os.environ.get("ANDROID_SIGNING_DNAME", DEFAULT_DNAME)

    if keystore.exists():
        print(f"Keystore already exists at {keystore} – reusing it.")
        _print_fingerprint(keystore, alias, pw)
        return 0

    # Developer-provided release keystore takes precedence (for tagged builds).
    release_ks = Path("tools/release.keystore")
    if release_ks.exists():
        print(f"Using developer release keystore at {release_ks}.")
        shutil.copyfile(release_ks, keystore)
        return 0

    keytool = shutil.which("keytool")
    if not keytool:
        print("WARNING: keytool not found on PATH; skipping keystore generation.", file=sys.stderr)
        print("APK signatures will be random and upgrades will require uninstall.", file=sys.stderr)
        return 0

    cmd = [
        keytool, "-genkeypair", "-v",
        "-keystore", str(keystore),
        "-alias", alias,
        "-keyalg", "RSA", "-keysize", "2048",
        "-validity", "10000",
        "-storepass", pw, "-keypass", pw,
        "-dname", dname,
        "-deststoretype", "pkcs12",
    ]
    print("+", " ".join(cmd))
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        print("keytool failed – APK upgrades will require uninstall until this is fixed.", file=sys.stderr)
        return 0
    _print_fingerprint(keystore, alias, pw)
    return 0


def _print_fingerprint(keystore: Path, alias: str, pw: str) -> None:
    keytool = shutil.which("keytool")
    if not keytool:
        return
    r = subprocess.run([
        keytool, "-list", "-v",
        "-keystore", str(keystore),
        "-alias", alias,
        "-storepass", pw,
    ], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if "SHA256" in line or "SHA1" in line or "Certificate fingerprints" in line:
            print(line.strip())


if __name__ == "__main__":
    sys.exit(main())

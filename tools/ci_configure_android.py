#!/usr/bin/env python3
"""Point Godot's editor settings at the Android SDK / JDK used by CI.

Godot's Android exporter reads `export/android/android_sdk_path` and
`export/android/java_sdk_path` from EditorSettings, not from environment
variables. In CI there is no GUI to set them, so this script patches the
generated `editor_settings-<major>.<minor>.tres` file directly (Godot merges the
file on top of its defaults, so writing just these two keys is enough).

Usage:
    ANDROID_SDK_ROOT=/path JAVA_HOME=/path python3 tools/ci_configure_android.py
"""
from __future__ import annotations

import glob
import os
import sys


def main() -> int:
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    java = os.environ.get("JAVA_HOME")
    if not sdk or not java:
        print("ANDROID_SDK_ROOT / JAVA_HOME are not set", file=sys.stderr)
        return 1

    config_dir = os.path.expanduser("~/.config/godot")
    os.makedirs(config_dir, exist_ok=True)

    candidates = sorted(glob.glob(os.path.join(config_dir, "editor_settings-*.tres")))
    path = candidates[-1] if candidates else os.path.join(config_dir, "editor_settings-4.4.tres")

    lines = []
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as handle:
            lines = handle.read().splitlines()

    def upsert(key: str, value: str) -> None:
        entry = f'{key} = "{value}"'
        for i, line in enumerate(lines):
            if line.startswith(key):
                lines[i] = entry
                return
        lines.append(entry)

    if not lines:
        lines = ['[gd_resource type="EditorSettings" format=3]', "", "[resource]"]

    if "[resource]" not in lines:
        lines.extend(["", "[resource]"])

    # Keep the two Android keys at the end of [resource]; duplicate keys are not
    # allowed, so upsert() replaces any existing ones first.
    upsert("export/android/android_sdk_path", sdk)
    upsert("export/android/java_sdk_path", java)

    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

    print(f"patched {path}")
    print(f"  android_sdk_path = {sdk}")
    print(f"  java_sdk_path    = {java}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

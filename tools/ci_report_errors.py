#!/usr/bin/env python3
"""Turn Godot's smoke-test log into GitHub check annotations.

Each `SCRIPT ERROR:` block in Godot 4 is followed by an
`at: ... (res://path.gd:LINE)` line. The workflow can only surface a handful of
annotations, so this script de-duplicates per file and prints the most useful
ones as `::error file=...,line=...::message`, which is enough to iterate on a
build without downloading artifacts.

Usage: python3 tools/ci_report_errors.py smoke.log
"""
from __future__ import annotations

import re
import sys

AT_PATTERN = re.compile(r"\(res://([^)]+?):(\d+)\)")
MAX_ANNOTATIONS = 10


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: ci_report_errors.py <log>")
        return 2
    with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as handle:
        lines = handle.readlines()

    errors: list[tuple[str, int, str]] = []
    seen: set[tuple[str, str]] = set()
    pending = ""
    for line in lines:
        stripped = line.strip()
        if "SCRIPT ERROR" in stripped or "Parse Error" in stripped:
            pending = stripped
            match = AT_PATTERN.search(stripped)
            if match:
                key = (match.group(1), pending.split("Error:", 1)[-1].strip()[:80])
                if key not in seen:
                    seen.add(key)
                    errors.append((match.group(1), int(match.group(2)), pending))
                pending = ""
            continue
        match = AT_PATTERN.search(stripped)
        if match and pending:
            key = (match.group(1), pending.split("Error:", 1)[-1].strip()[:80])
            if key not in seen:
                seen.add(key)
                errors.append((match.group(1), int(match.group(2)), pending))
            pending = ""

    if not errors:
        print("No script errors found in the log.")
        return 0

    per_file: dict[str, int] = {}
    for path, _line, _msg in errors:
        per_file[path] = per_file.get(path, 0) + 1

    print(f"::error::{len(errors)} script error(s) across {len(per_file)} file(s)")
    for path, line, message in errors[:MAX_ANNOTATIONS]:
        safe = message.replace("%", "%25").replace("\r", "").replace("\n", " ")
        print(f"::error file={path},line={line},col=1::[{per_file[path]} errors in file] {safe}")
    if len(errors) > MAX_ANNOTATIONS:
        rest = ", ".join(f"{p} ({n})" for p, n in sorted(per_file.items()))
        print(f"::error::remaining files: {rest}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

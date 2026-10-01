#!/usr/bin/env python3
"""Build an OTOBO 1.1 OPM from the SOPM and its listed source files.

This is a dependency-free fallback for development environments without an
initialized OTOBO installation. Production build pipelines should prefer the
native Dev::Package::Build command.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def build(source: Path, target_dir: Path) -> Path:
    source = source.resolve()
    root = ET.parse(source).getroot()
    if root.tag != "otobo_package":
        raise ValueError("SOPM root must be <otobo_package>")
    root.set("version", "1.1")

    name = root.findtext("Name")
    version = root.findtext("Version")
    if not name or not version:
        raise ValueError("SOPM must define Name and Version")

    filelist = root.find("Filelist")
    if filelist is None or not list(filelist):
        raise ValueError("SOPM Filelist is empty")

    package_dir = source.parent
    for file_entry in list(filelist):
        if file_entry.tag != "File":
            raise ValueError(f"Unexpected Filelist entry: {file_entry.tag}")
        location = file_entry.get("Location")
        if not location:
            raise ValueError("File entry has no Location")
        file_path = (package_dir / location).resolve()
        if package_dir not in file_path.parents or not file_path.is_file():
            raise FileNotFoundError(f"Package source file is missing or outside source tree: {location}")
        file_entry.set("Encode", "Base64")
        file_entry.text = base64.b64encode(file_path.read_bytes()).decode("ascii")

    build_date = ET.Element("BuildDate")
    build_date.text = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    build_host = ET.Element("BuildHost")
    build_host.text = os.environ.get("BUILD_HOST", "localhost")
    position = list(root).index(filelist)
    root.insert(position, build_host)
    root.insert(position, build_date)

    ET.indent(root, space="    ")
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"{name}-{version}.opm"
    target.write_bytes(b'<?xml version="1.0" encoding="utf-8" ?>\n' + ET.tostring(root, encoding="utf-8"))
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target_directory", type=Path)
    args = parser.parse_args()
    try:
        print(build(args.source, args.target_directory))
    except Exception as error:  # noqa: BLE001 - concise build failure for CLI users
        print(f"Package build failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

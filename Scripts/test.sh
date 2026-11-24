#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
python3 Tests/fixtures.py "$stage"
xcrun clang -c Amethyst/Native.c -o "$stage/native.o"
xcrun swiftc -import-objc-header Amethyst/Native.h -lz "$stage/native.o" \
    Amethyst/{Catalog,Probe,Analyzer,ArchiveIndex}.swift Tests/main.swift -o "$stage/tests"
"$stage/tests" "$stage"

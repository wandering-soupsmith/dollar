#!/usr/bin/env python3
"""Fail if src/ line coverage from lcov.info is below the threshold.

Usage: run `forge coverage --report lcov --ir-minimum` first (writes lcov.info),
then `python3 ci/coverage_gate.py`. Adjust THRESHOLD as the suite matures.
"""
import sys

THRESHOLD = 90.0

hit = found = 0
counting = False
with open("lcov.info") as f:
    for line in f:
        if line.startswith("SF:"):
            # Only count contracts under src/ (skip test/ and lib/).
            counting = ("/src/" in line) or line.startswith("SF:src/")
        elif counting and line.startswith("DA:"):
            found += 1
            if int(line.strip().split(",")[1]) > 0:
                hit += 1

pct = 100 * hit / max(found, 1)
print(f"src line coverage: {pct:.1f}% ({hit}/{found}), threshold {THRESHOLD}%")
sys.exit(0 if pct >= THRESHOLD else 1)

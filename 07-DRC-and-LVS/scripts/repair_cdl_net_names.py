#!/usr/bin/env python3
"""Fix case-colliding numeric net names in the cali_logic v4 v2lvs CDL."""

import argparse
from collections import defaultdict
from pathlib import Path
import re


TOP = re.compile(r"^\.SUBCKT[ \t]+cali_logic(?:[ \t]|$).*?^\.ENDS\b[^\r\n]*",
                 re.IGNORECASE | re.MULTILINE | re.DOTALL)
NET_ASSIGNMENT = re.compile(r"(?<==)([nN][0-9]+)(?=\s|$)")


def repair(source):
    """Rename uppercase members of n123/N123 pairs in the top subcircuit."""
    matches = list(TOP.finditer(source))
    if len(matches) != 1:
        raise ValueError("expected a single cali_logic top subcircuit")
    match = matches[0]
    top = match.group()
    groups = defaultdict(set)
    for name in NET_ASSIGNMENT.findall(top):
        groups[name.lower()].add(name)

    mapping = {
        key.upper(): "CAL_NET_UPPER_" + key[1:]
        for key, names in groups.items()
        if len(names) == 2
    }
    if not mapping:
        raise ValueError("no n123/N123 pairs found in the cali_logic top")

    for old, new in mapping.items():
        name = re.compile(r"(?<![\w$])" + old + r"(?![\w$])")
        assignment = re.compile(r"(?<==)" + old + r"(?=\s|$)")
        if len(name.findall(top)) != len(assignment.findall(top)):
            raise ValueError(f"{old} also occurs outside pin assignments")
        if re.search(r"(?<![\w$])" + new + r"(?![\w$])", top, re.IGNORECASE):
            raise ValueError(f"{new} already exists")

    rewritten = NET_ASSIGNMENT.sub(lambda token: mapping.get(token[1], token[1]), top)
    return source[:match.start()] + rewritten + source[match.end():], mapping


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_cdl", type=Path)
    parser.add_argument("output_cdl", type=Path)
    args = parser.parse_args()
    if args.output_cdl.exists():
        parser.error("the output CDL already exists")
    try:
        source = args.input_cdl.read_bytes().decode("utf-8")
        repaired, mapping = repair(source)
        with args.output_cdl.open("xb") as output:
            output.write(repaired.encode("utf-8"))
    except (ValueError, OSError) as exc:
        parser.error(str(exc))
    print(f"Renamed {len(mapping)} colliding internal nets")


if __name__ == "__main__":
    main()

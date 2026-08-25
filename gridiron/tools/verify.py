#!/usr/bin/env python3
"""
Structural checks that do not need a Swift toolchain.

This is not a compiler and does not pretend to be one. It catches the specific
class of mistakes that are expensive to find in Xcode:

  1. a source file that exists on disk but is in no target (builds fine until
     something references it, then fails somewhere unrelated)
  2. unbalanced braces, parens or brackets — usually a bad merge or a stray edit
  3. a Core/ file that imports a platform framework, which would silently break
     the promise that the rules and the simulation are testable without a
     simulator
  4. a dangling object identifier in project.pbxproj
  5. ragged pixel-art grids and font glyphs that are not 5x7

    python3 tools/verify.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(ROOT, "PixelGridiron")
TEST_DIR = os.path.join(ROOT, "PixelGridironTests")
PBXPROJ = os.path.join(ROOT, "PixelGridiron.xcodeproj", "project.pbxproj")

# Core/ is the platform-free half of the game. Anything else here is a bug.
CORE_ALLOWED_IMPORTS = {"Foundation"}

failures = []
checks = 0


def fail(message):
    failures.append(message)


def check(condition, message):
    global checks
    checks += 1
    if not condition:
        fail(message)
    return condition


def swift_files(directory):
    out = []
    for base, _, names in os.walk(directory):
        for name in sorted(names):
            if name.endswith(".swift"):
                out.append(os.path.join(base, name))
    return sorted(out)


def strip_swift(source):
    """Removes comments and string literals so the delimiters left are code."""
    out = []
    i = 0
    n = len(source)
    while i < n:
        c = source[i]
        two = source[i:i + 2]
        three = source[i:i + 3]

        if three == '"""':
            i += 3
            while i < n and source[i:i + 3] != '"""':
                i += 2 if source[i] == "\\" else 1
            i += 3
            continue
        if c == '"':
            i += 1
            while i < n and source[i] != '"':
                if source[i] == "\\":
                    # An interpolation can contain real code, but it can also
                    # contain a quote; skipping the whole escape is enough for a
                    # delimiter count.
                    i += 2
                else:
                    i += 1
            i += 1
            continue
        if two == "//":
            while i < n and source[i] != "\n":
                i += 1
            continue
        if two == "/*":
            depth = 1
            i += 2
            while i < n and depth:
                if source[i:i + 2] == "/*":
                    depth += 1
                    i += 2
                elif source[i:i + 2] == "*/":
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check_delimiters(path):
    with open(path) as handle:
        code = strip_swift(handle.read())
    pairs = {"}": "{", ")": "(", "]": "["}
    stack = []
    for c in code:
        if c in "{([":
            stack.append(c)
        elif c in ")}]":
            if not stack or stack[-1] != pairs[c]:
                fail("%s: unbalanced '%s'" % (rel(path), c))
                return
            stack.pop()
    if stack:
        fail("%s: %d unclosed '%s'" % (rel(path), len(stack), stack[-1]))


def rel(path):
    return os.path.relpath(path, ROOT)


def check_core_imports():
    for path in swift_files(os.path.join(APP_DIR, "Core")):
        with open(path) as handle:
            for line in handle:
                match = re.match(r"\s*import\s+(\w+)", line)
                if match and match.group(1) not in CORE_ALLOWED_IMPORTS:
                    fail("%s imports %s — Core must stay platform-free"
                         % (rel(path), match.group(1)))
        checks_bump()


def checks_bump():
    global checks
    checks += 1


def check_target_membership():
    if not os.path.exists(PBXPROJ):
        fail("project.pbxproj is missing — run tools/gen_xcodeproj.py")
        return
    with open(PBXPROJ) as handle:
        project = handle.read()

    for path in swift_files(APP_DIR) + swift_files(TEST_DIR):
        name = os.path.basename(path)
        check("%s in Sources */," % name in project,
              "%s is not a member of any target — run tools/gen_xcodeproj.py" % rel(path))

    # Every referenced identifier must be defined somewhere in the file.
    defined = set(re.findall(r"^\t\t([0-9A-F]{24}) ", project, re.M))
    defined |= set(re.findall(r"^\t\t([0-9A-F]{24}) = \{", project, re.M))
    referenced = set(re.findall(r"([0-9A-F]{24})", project))
    dangling = referenced - defined
    check(not dangling,
          "project.pbxproj references undefined objects: %s" % sorted(dangling)[:4])


def grids_in(path, names):
    with open(path) as handle:
        source = handle.read()
    found = {}
    for name in names:
        match = re.search(r"static let " + name + r": \[String\] = \[(.*?)\n    \]",
                          source, re.S)
        if match:
            found[name] = re.findall(r'"([^"]*)"', match.group(1))
    return found


def check_pixel_art():
    path = os.path.join(APP_DIR, "Render", "PixelArt.swift")
    names = ["stand", "runA", "runB", "carry", "block", "dive", "down",
             "football", "downMarker"]
    grids = grids_in(path, names)
    for name in names:
        if not check(name in grids, "PixelArt is missing the '%s' grid" % name):
            continue
        widths = {len(row) for row in grids[name]}
        check(len(widths) == 1,
              "PixelArt.%s has ragged rows: widths %s" % (name, sorted(widths)))

    font = os.path.join(APP_DIR, "Render", "PixelFont.swift")
    with open(font) as handle:
        source = handle.read()
    block = re.search(r"glyphs: \[Character: \[String\]\] = \[(.*?)\n    \]", source, re.S)
    if not check(block is not None, "PixelFont glyph table not found"):
        return
    count = 0
    for match in re.finditer(r'"(.)"\s*:\s*\[(.*?)\]', block.group(1), re.S):
        character = match.group(1)
        rows = re.findall(r'"([^"]*)"', match.group(2))
        count += 1
        check(len(rows) == 7, "glyph '%s' has %d rows, expected 7" % (character, len(rows)))
        widths = {len(row) for row in rows}
        check(widths == {5}, "glyph '%s' has widths %s, expected {5}"
              % (character, sorted(widths)))
    check(count >= 40, "only %d font glyphs defined" % count)


def check_no_stray_markers():
    for path in swift_files(APP_DIR) + swift_files(TEST_DIR):
        with open(path) as handle:
            source = handle.read()
        for marker in ["<<<<<<<", ">>>>>>>", "TODO:", "FIXME:"]:
            check(marker not in source, "%s contains '%s'" % (rel(path), marker))


def main():
    for path in swift_files(APP_DIR) + swift_files(TEST_DIR):
        checks_bump()
        check_delimiters(path)

    check_core_imports()
    check_target_membership()
    check_pixel_art()
    check_no_stray_markers()

    print("%d checks" % checks)
    if failures:
        print("\n%d FAILED:" % len(failures))
        for message in failures:
            print("  - %s" % message)
        sys.exit(1)
    print("all clear")


if __name__ == "__main__":
    main()

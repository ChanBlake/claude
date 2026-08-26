#!/usr/bin/env python3
"""
Builds the Artifact version of the game from index.html.

Artifacts are wrapped in their own <!doctype>/<html>/<head>/<body> at publish
time, so the published file has to be body content only. Rather than maintain
two copies that drift, this strips the standalone document down to what an
Artifact accepts. index.html stays the source of truth.

    python3 tools/make_artifact.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "index.html")
OUT = os.path.join(ROOT, "pixel-bowl.artifact.html")


def main():
    html = open(SRC).read()

    title = re.search(r"<title>(.*?)</title>", html, re.S).group(1)
    # The game stopped depending on a font host when the bitmap face went
    # back in; tolerate the link being gone.
    m = re.search(r'<link rel="stylesheet" href="https://fonts\.googleapis[^>]*>', html)
    fonts = m.group(0) if m else ""
    style = re.search(r"<style>\n(.*?)\n</style>", html, re.S).group(1)
    body = re.search(r"<body>\n(.*?)\n<script>", html, re.S).group(1)
    script = re.search(r"<script>\n(.*?)\n</script>", html, re.S).group(1)

    # The Artifact host owns <html> and <body>, so selectors that target them
    # still apply — but the viewport unit has to survive being in an iframe.
    parts = [
        "<title>%s</title>" % title,
    ] + ([fonts] if fonts else []) + [
        "<style>\n%s\n</style>" % style,
        body.strip(),
        "<script>\n%s\n</script>" % script,
    ]
    open(OUT, "w").write("\n".join(parts) + "\n")

    size = os.path.getsize(OUT)
    print("wrote %s (%.0f KB)" % (os.path.relpath(OUT, ROOT), size / 1024))
    for bad in ("<!doctype", "<html", "<head>", "<body>", "</html>"):
        assert bad not in open(OUT).read().lower(), "artifact still contains " + bad
    print("no document-level tags — safe to publish")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Stamps the build into index.html.

The version is what the phone uses to decide the service worker is a new
script, so it has to change on every deploy or the installed app keeps the
worker it already has and never sees the new game. Run this before committing.

    python3 tools/stamp.py
"""
import os
import re
import subprocess
import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "index.html")


def main():
    sha = subprocess.run(["git", "rev-parse", "--short=7", "HEAD"],
                         cwd=ROOT, capture_output=True, text=True).stdout.strip()
    day = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    stamp = "%s.%s" % (day, sha or "dev")

    html = open(SRC).read()
    new, n = re.subn(r'const VERSION = "[^"]*";',
                     'const VERSION = "%s";' % stamp, html, count=1)
    assert n == 1, "no VERSION line to stamp"
    open(SRC, "w").write(new)
    print("stamped " + stamp)


if __name__ == "__main__":
    main()

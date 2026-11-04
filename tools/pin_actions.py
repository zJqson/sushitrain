# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at https://mozilla.org/MPL/2.0/.
"""pin_actions.py - rewrite `uses: owner/repo@tag` into `uses: owner/repo@<40-hex commit> # tag` in workflow files.
NEEDS NETWORK (git ls-remote against github.com). Stdlib only.   Usage:  py -3 tools/pin_actions.py .github/workflows/FILE.yml [--dry-run]
Why: a full commit SHA cannot be moved by the action's owner; a tag like @v3 can. The workflow was written offline, so it still uses
the tags that upstream's own build.yml uses. Run this once when the network is allowed, review the diff, commit."""
import re
import subprocess
import sys

USES_RE = re.compile(r"^(\s*-?\s*uses:\s*)([\w.-]+/[\w.-]+)@([\w.-]+)(\s*#.*)?$")


def pick_sha(ls_remote_text, tag):
    """Commit SHA from `git ls-remote REPO refs/tags/TAG refs/tags/TAG^{}` output: the peeled (^{}) line wins (annotated tag)."""
    plain = peeled = None
    for line in ls_remote_text.splitlines():
        sha, _, ref = line.partition("\t")
        if ref == "refs/tags/%s^{}" % tag:
            peeled = sha
        elif ref == "refs/tags/%s" % tag:
            plain = sha
    return peeled or plain


def main():
    path, dry = sys.argv[1], "--dry-run" in sys.argv
    out, changed = [], 0
    for line in open(path, encoding="utf-8", newline="").read().split("\n"):
        m = USES_RE.match(line.rstrip("\r"))
        if m and not re.fullmatch(r"[0-9a-f]{40}", m.group(3)):
            repo, tag = m.group(2), m.group(3)
            r = subprocess.run(["git", "ls-remote", "https://github.com/%s" % repo, "refs/tags/%s" % tag, "refs/tags/%s^{}" % tag],
                               capture_output=True, text=True)
            sha = pick_sha(r.stdout, tag) if r.returncode == 0 else None
            if not sha or not re.fullmatch(r"[0-9a-f]{40}", sha):
                sys.exit("could not resolve %s@%s (exit %d): %s" % (repo, tag, r.returncode, r.stderr.strip()[:200]))
            line = "%s%s@%s # %s" % (m.group(1), repo, sha, tag)
            changed += 1
            print("%s@%s -> %s" % (repo, tag, sha))
        out.append(line)
    if not dry and changed:
        open(path, "w", encoding="utf-8", newline="").write("\n".join(out))
    print("%d action(s) %s" % (changed, "would be pinned (dry run)" if dry else "pinned"))


if __name__ == "__main__":
    main()

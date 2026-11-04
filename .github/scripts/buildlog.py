#!/usr/bin/env python3
# Helper for .github/workflows/build-unsigned-ipa.yml.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at https://mozilla.org/MPL/2.0/.
"""buildlog.py - turns the build output into something the lead can read with a plain `git pull`. Stdlib only, Python 3.8+.

  buildlog.py errors LOGFILE [--max 40]
      prints the first N error lines of the build output (numbered by line in the log).

  buildlog.py publish --log LOGFILE --run-number N --status success|failure|cancelled --sha SHA --run-url URL
        [--run-attempt K] [--steps "name=outcome name=outcome ..."] [--release-url URL] [--ipa-info TEXT]
        [--remote origin] [--branch build-logs] [--keep 20] [--max-log-bytes 6000000] [--summary-file FILE]
      commits  run-<N>.log  and  LATEST.txt  to the branch (created on the first run) WITHOUT a working tree or an index
      (git plumbing: hash-object / mktree / commit-tree), keeps only the newest --keep logs, and pushes with the credentials
      that actions/checkout already stored (the built-in GITHUB_TOKEN; no PAT, no secret is read or printed here).
      The commit message holds the outcome and the first 40 error lines; the same text goes to the job summary.

Reusable: nothing here knows this repository; remote, branch, keep and the file names are arguments.
"""
import argparse
import os
import re
import subprocess
import sys
import time

LOG_NAME_RE = re.compile(r"^run-(\d+)(?:-attempt(\d+))?\.log$")

# lines that are really errors (checked first)
STRONG_RE = re.compile(
    r"(:\d+(:\d+)?: (fatal )?error:)"            # swiftc / clang:  file:line:col: error:
    r"|(^|\s)error: "                            # xcodebuild: error: ...   /   error: ...
    r"|\*\* [A-Z ]+FAILED \*\*"                  # ** ARCHIVE FAILED **  /  ** BUILD FAILED **
    r"|\b(ld|clang|swiftc|swift-frontend|gomobile): error"
    r"|Undefined symbols"
    r"|^make(\[\d+\])?: \*\*\*"                  # make: *** [ios] Error 65
    r"|^rename_fork:"
    r"|^ERROR[: ]"
    r"|^Traceback \(most recent call last\)"
    r"|^panic: "
    r"|^\.{0,2}/?[^\s:]+\.go:\d+:\d+: "          # go compiler:  src/x.go:12:3: undefined: foo
    r"|The following build commands failed"
)
# looser hints, only used to fill up when there are fewer than N strong lines
WEAK_RE = re.compile(r"command not found|No such file or directory|^go: .*(cannot|no required module|missing|error)|^gomobile: ")

README_TXT = """build-logs - written by the GitHub Actions workflow "Build unsigned iOS .ipa" (.github/workflows/build-unsigned-ipa.yml).

LATEST.txt    outcome of the newest run + the first 40 error lines (read this first)
run-N.log     the full make / xcodebuild output of run N (only the newest logs are kept; very long logs keep their start and end)

Read it without any login:  git clone --branch build-logs --single-branch <repo url> logs   then   git pull   (or: git fetch origin build-logs).
The commit message of every commit here repeats the outcome and the error lines:  git log origin/build-logs -5.
Nothing secret is stored here; the logs are plain compiler output.
"""


def read_text(path):
    try:
        with open(path, "rb") as f:
            return f.read().decode("utf-8", errors="replace")
    except OSError:
        return ""


def error_lines(text, limit=40):
    """First `limit` error lines as (line number, text). Strong matches first, weak ones only to fill up. Repeats are dropped."""
    strong, weak, seen = [], [], set()
    for no, ln in enumerate(text.splitlines(), 1):
        s = ln.rstrip()
        if not s or s in seen:
            continue
        if STRONG_RE.search(s):
            seen.add(s)
            strong.append((no, s[:300]))
        elif WEAK_RE.search(s) and len(weak) < limit:
            seen.add(s)
            weak.append((no, s[:300]))
        if len(strong) >= limit:
            break
    return (strong + weak)[:limit] if len(strong) < limit else strong[:limit]


def cap_log(text, max_bytes):
    data = text.encode("utf-8")
    if len(data) <= max_bytes:
        return text, False
    head_n = 1000000
    tail_n = max(0, max_bytes - head_n - 200)
    head = data[:head_n].decode("utf-8", errors="ignore")
    tail = data[-tail_n:].decode("utf-8", errors="ignore") if tail_n else ""
    marker = "\n\n[... %d bytes omitted by buildlog.py to keep the log branch small; start and end are kept ...]\n\n" % (len(data) - head_n - tail_n)
    return head + marker + tail, True


def log_key(name):
    m = LOG_NAME_RE.match(name)
    return (int(m.group(1)), int(m.group(2) or 1)) if m else None


def compose(a, text, errs, capped, log_name):
    status = a.status.lower()
    steps = [p.split("=", 1) for p in (a.steps or "").split() if "=" in p]
    failed = next((n for n, o in steps if o == "failure"), None)
    if status == "success":
        head = "SUCCESS"
    elif status == "cancelled":
        head = "CANCELLED"
    else:
        head = "FAILURE" + (" at step '%s'" % failed if failed else "")
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    subject = "run %s: %s - %s - %s" % (a.run_number, head, (a.sha or "")[:7], stamp)
    nlines = text.count("\n") + (1 if text and not text.endswith("\n") else 0)
    body = [
        "Run:      %s (attempt %s)" % (a.run_url or "(unknown)", a.run_attempt),
        "Commit:   %s" % (a.sha or "(unknown)"),
        "Status:   %s" % status.upper(),
        "Steps:    %s" % (a.steps or "(none)"),
        "Release:  %s" % (a.release_url or "(none)"),
        "IPA:      %s" % (a.ipa_info or "(none)"),
        "Log:      %s (%d lines%s)" % (log_name, nlines, ", start and end only: it was too long" if capped else ""),
        "",
    ]
    if errs:
        body.append("First %d error lines of the build output (number = line in %s):" % (len(errs), log_name))
        body += ["%6d: %s" % (no, s) for no, s in errs]
    else:
        body.append("No error lines found in the build output." + ("" if status == "success" else " (Look at the end of the log.)"))
    return subject, "\n".join(body) + "\n"


def write_summary(path, subject, body, errs):
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write("## %s\n\n```\n%s```\n" % (subject, body.replace("```", "'''")))
    except OSError as e:
        print("buildlog: could not write the job summary: %s" % e, file=sys.stderr)


class Git:
    def __init__(self, env):
        self.env = env

    def run(self, args, input_bytes=None, check=True):
        r = subprocess.run(["git"] + args, input=input_bytes, capture_output=True, env=self.env)
        if check and r.returncode != 0:
            raise RuntimeError("git %s failed (exit %d): %s" % (args[0], r.returncode, r.stderr.decode("utf-8", "replace").strip()[:400]))
        return r

    def out(self, args, input_bytes=None):
        return self.run(args, input_bytes).stdout.decode("utf-8", "replace").strip()


def publish(a):
    full = read_text(a.log)
    if not full:
        full = "(the build log file was empty or missing: the job stopped before the first build step)\n"
    errs = error_lines(full, 40)
    text, capped = cap_log(full, a.max_log_bytes)
    attempt = int(a.run_attempt or 1)
    log_name = "run-%s.log" % a.run_number if attempt <= 1 else "run-%s-attempt%d.log" % (a.run_number, attempt)
    subject, body = compose(a, text, errs, capped, log_name)
    write_summary(a.summary_file, subject, body, errs)
    print(subject)

    env = dict(os.environ)
    env.update({"GIT_AUTHOR_NAME": a.author_name, "GIT_AUTHOR_EMAIL": a.author_email,
                "GIT_COMMITTER_NAME": a.author_name, "GIT_COMMITTER_EMAIL": a.author_email, "GIT_TERMINAL_PROMPT": "0"})
    g = Git(env)
    new_files = {log_name: text.encode("utf-8"), "LATEST.txt": (subject + "\n\n" + body).encode("utf-8")}
    last_err = ""
    for attempt_no in range(1, a.tries + 1):
        try:
            parent, entries = None, {}
            ls = g.out(["ls-remote", "--heads", a.remote, "refs/heads/" + a.branch])
            if ls:
                g.run(["fetch", "--quiet", "--no-tags", "--depth=1", a.remote, "+refs/heads/%s:refs/buildlog/tip" % a.branch])
                parent = g.out(["rev-parse", "refs/buildlog/tip"])
                for line in g.out(["ls-tree", parent]).splitlines():
                    meta, name = line.split("\t", 1)
                    mode, typ, sha = meta.split()
                    if typ == "blob":
                        entries[name] = (mode, sha)
            for name, data in new_files.items():
                entries[name] = ("100644", g.out(["hash-object", "-w", "--stdin"], input_bytes=data))
            if "README.txt" not in entries:
                entries["README.txt"] = ("100644", g.out(["hash-object", "-w", "--stdin"], input_bytes=README_TXT.encode("utf-8")))
            logs = sorted((n for n in entries if log_key(n)), key=log_key)
            for old in logs[:-a.keep] if a.keep > 0 else []:
                del entries[old]
            tree_in = "".join("%s blob %s\t%s\n" % (m, s, n) for n, (m, s) in sorted(entries.items())).encode("utf-8")
            tree = g.out(["mktree"], input_bytes=tree_in)
            cmd = ["commit-tree", tree] + (["-p", parent] if parent else []) + ["-m", subject + "\n\n" + body]
            commit = g.out(cmd)
            g.run(["push", "--quiet", a.remote, "%s:refs/heads/%s" % (commit, a.branch)])
            print("buildlog: pushed %s to %s/%s (%d files, %d logs kept)" % (commit[:10], a.remote, a.branch, len(entries), len([n for n in entries if log_key(n)])))
            return 0
        except (RuntimeError, ValueError) as e:
            last_err = str(e)
            print("buildlog: attempt %d of %d failed: %s" % (attempt_no, a.tries, last_err), file=sys.stderr)
            time.sleep(min(a.pause * attempt_no, 30))
    print("buildlog: GIVING UP after %d attempts: %s" % (a.tries, last_err), file=sys.stderr)
    if a.summary_file:
        try:
            with open(a.summary_file, "a", encoding="utf-8") as f:
                f.write("\n**The log could NOT be pushed to the %s branch:** `%s`\n" % (a.branch, last_err.replace("`", "'")))
        except OSError:
            pass
    return 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("errors")
    e.add_argument("log")
    e.add_argument("--max", type=int, default=40)
    p = sub.add_parser("publish")
    p.add_argument("--log", required=True)
    p.add_argument("--run-number", required=True)
    p.add_argument("--run-attempt", default="1")
    p.add_argument("--status", required=True, choices=["success", "failure", "cancelled", "skipped"])
    p.add_argument("--sha", default="")
    p.add_argument("--run-url", default="")
    p.add_argument("--steps", default="")
    p.add_argument("--release-url", default="")
    p.add_argument("--ipa-info", default="")
    p.add_argument("--remote", default="origin")
    p.add_argument("--branch", default="build-logs")
    p.add_argument("--keep", type=int, default=20)
    p.add_argument("--max-log-bytes", type=int, default=6000000)
    p.add_argument("--summary-file", default=os.environ.get("GITHUB_STEP_SUMMARY", ""))
    p.add_argument("--author-name", default="github-actions[bot]")
    p.add_argument("--author-email", default="41898282+github-actions[bot]@users.noreply.github.com")
    p.add_argument("--tries", type=int, default=4)
    p.add_argument("--pause", type=float, default=5.0)
    a = ap.parse_args()
    if a.cmd == "errors":
        lines = error_lines(read_text(a.log), a.max)
        for no, s in lines:
            print("%6d: %s" % (no, s))
        if not lines:
            print("(no error lines found)")
        return 0
    return publish(a)


if __name__ == "__main__":
    sys.exit(main())

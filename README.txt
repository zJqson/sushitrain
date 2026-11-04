build-logs - written by the GitHub Actions workflow "Build unsigned iOS .ipa" (.github/workflows/build-unsigned-ipa.yml).

LATEST.txt    outcome of the newest run + the first 40 error lines (read this first)
run-N.log     the full make / xcodebuild output of run N (only the newest logs are kept; very long logs keep their start and end)

Read it without any login:  git clone --branch build-logs --single-branch <repo url> logs   then   git pull   (or: git fetch origin build-logs).
The commit message of every commit here repeats the outcome and the error lines:  git log origin/build-logs -5.
Nothing secret is stored here; the logs are plain compiler output.

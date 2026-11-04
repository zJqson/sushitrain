# PhotoTrain - a personal fork of Synctrain

This is a personal fork of [pixelspark/sushitrain](https://github.com/pixelspark/sushitrain) (the iPhone app "Synctrain",
a Syncthing client). It adds two things for one person's own phone:

1. **Keep running in the background.** The app asks for iOS location access ("While Using", then "Always") only to stay alive.
   The location is never read, stored, logged or sent. A blue location bar shows while it runs.
2. **Automatic photo back-up.** New photos in the iPhone library start the app's existing photo back-up by themselves.
   Defaults: not on mobile data and not on a metered or Low Data Mode network (for example a phone hotspot).
   Everything still goes through Syncthing (end-to-end encrypted).

The app is called **PhotoTrain** with bundle id `com.jason.phototrain`.

## Licence (MPL-2.0 notice kept)

The code stays under the **Mozilla Public License 2.0** (the `LICENSE` file and every copyright / licence header in the
source files are unchanged; the files added here carry the same MPL header). Modified files remain MPL, and this
repository is their public source. The original author's **names "Sushitrain" / "Synctrain" and his logo files are NOT
under the MPL** (README "License" of the upstream project), so this fork uses another name and bundle id, a plain
placeholder icon, and the reserved logo files (`SushitrainGlass.icon`, `Docs/logo.png`) were removed with `git rm`
(`tools/rename_fork.py` did this; the upstream `README.md` still shows a broken logo picture, that is harmless).
Copyright lines of the original author are kept on purpose.

## What the build does (GitHub Actions, free for a public repository)

`.github/workflows/build-unsigned-ipa.yml` runs on every push to `main` and by hand (Actions tab, "Run workflow").
It builds the Go core and the iOS app on GitHub's macOS runner (`xcode-27`) into an **unsigned** `.ipa`.
No Apple ID, no personal access token and no secret is stored on GitHub. The `.ipa` is signed later on the phone
(SideStore / AltStore / Sideloadly).

Each run publishes, using only the run's own built-in `GITHUB_TOKEN` (`contents: write`):

| What | Where | When |
|---|---|---|
| Full make / xcodebuild output | branch `build-logs`, file `run-<run number>.log` (newest 20 kept) | always, also when the build failed |
| Outcome + first 40 error lines | branch `build-logs`: `LATEST.txt` and the commit message; also the run's job summary | always |
| The unsigned `PhotoTrain.ipa` | Release `build-<run number>` (pre-release; newest 20 kept) | only when the build succeeded |

Upstream's own workflow (lint + iOS + macOS build + attestation on every push and pull request) is switched off:
it was renamed to `.github/workflows/build.yml.disabled` (GitHub only runs `*.yml`/`*.yaml`). It would waste Mac minutes,
`make lint` fails on code that is not swift-formatted, and the attestation step is noise in a fork.

**First time on a fork:** GitHub disables workflows on a new fork. Open the repo's *Actions* tab and press
*"I understand my workflows, go ahead and enable them"* once.

## Read the build logs without logging in

```
git clone --branch build-logs --single-branch https://github.com/USERNAME/sushitrain.git logs     (first time)
cd logs
git pull                                  (every time later)
type LATEST.txt                           (Windows; on Linux/macOS: cat LATEST.txt)
```

From any other clone of the repo: `git fetch origin build-logs`, then `git show origin/build-logs:LATEST.txt`,
`git log origin/build-logs -5` (the commit message repeats the outcome and the error lines),
`git show origin/build-logs:run-12.log`. Without git: `curl -s https://raw.githubusercontent.com/USERNAME/sushitrain/build-logs/LATEST.txt`.

## Download the newest .ipa without logging in

```
curl -s "https://api.github.com/repos/USERNAME/sushitrain/releases?per_page=1" | grep -m1 browser_download_url
curl -L -o PhotoTrain.ipa "<the URL printed above>"
```

(`/releases/latest` does NOT work here because the builds are pre-releases.) The direct link has the form
`https://github.com/USERNAME/sushitrain/releases/download/build-12/PhotoTrain.ipa`; `LATEST.txt` names the exact one.
The repository must be public for anonymous reading (and for free, unlimited Mac minutes).

## Pushing from this PC

`push_fork.ps1 -Owner USERNAME -KeyPath C:\path\to\private_key` (in the folder that holds this repo): SSH, no token.
It pushes only `main`. The public half of that key is added once under GitHub *Settings, SSH and GPG keys*.

## Not proven yet

Nothing in this fork was compiled before the first run. The first logs on the `build-logs` branch are the first compile.
Expect a few fix rounds (Swift 6 strict-concurrency errors in `Sushitrain/BackgroundKeepAlive.swift` are the most likely).

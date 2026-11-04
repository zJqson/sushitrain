# PhotoTrain - a personal fork of Synctrain

This is a personal fork of [pixelspark/sushitrain](https://github.com/pixelspark/sushitrain) (the iPhone app "Synctrain",
a Syncthing client). It adds two things for one person's own phone:

1. **Keep running in the background.** The app asks for iOS location access ("While Using", then "Always") only to stay alive.
   The location is never read, stored, logged or sent. A blue location bar shows while it runs.
2. **Automatic photo back-up.** New photos in the iPhone library start the app's existing photo back-up by themselves.
   Defaults: not on mobile data and not on a metered or Low Data Mode network (for example a phone hotspot).
   Everything still goes through Syncthing (end-to-end encrypted).

The app is called **PhotoTrain** with bundle id `com.jason.phototrain`.

3. **Album folders ("Every album").** In *Settings, Photo back-up, From album* there is a new first entry, **Every album (one folder
   per album)**. Each album of the Photos library becomes one folder, named like the album, inside the back-up folder (see
   "Album folders" below). Choosing a single album or the camera roll works exactly as before.

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

## Album folders ("Every album (one folder per album)")

Choose it under *Settings, Photo back-up, From album* (it is the first entry; nothing is chosen for you), pick the back-up folder
and, if you like, a path inside it. Then:

```
<back-up folder>/<path in folder>/
    Holiday 2024/IMG_2020.HEIC
    Holiday 2024/IMG_2021.HEIC
    Holiday 2024/IMG_2021.MOV        <- the video of a Live Photo, next to its picture (no "Live" folder)
    Mum's birthday/IMG_2020.HEIC     <- the same photo again, because it is in two albums (copied twice)
    No album/IMG_3001.JPG            <- photos and videos that are in no album of yours
```

What counts as an album: the albums you made (also the ones that came from a computer or a camera import). **Not** albums
that iOS makes by itself (Favorites, Screenshots, Videos, Recents, People, Hidden, ...) and not iCloud Shared Albums: a photo
that is only in those goes to `No album`.

- **Windows-safe names.** `\ / : * ? " < > |` and control characters become `_`; names are made Unicode NFC; no space at the start,
  no space or dot at the end; `CON PRN AUX NUL COM0-9 LPT0-9` (also with an extension) get a `_` (`CON` becomes `CON_`,
  `nul.txt` becomes `nul_.txt`); at most 100 characters (and 240 bytes); an empty name becomes `Untitled album`. Names that differ
  only in upper/lower case are the same folder on Windows, so the second one gets ` (2)`, the third ` (3)`. A name is given once
  and then kept, so it never flips when albums are added or deleted. `No album` is reserved (an album called "No album" becomes
  "No album (2)"). The same rules are used for file names; two different photos with the same file name in one folder: the second
  one gets `_` and the first 6 letters/digits of its identifier (`IMG_0001_9F2D7C.HEIC`); only on a clash. All of this is in the
  one pure file `Sushitrain/AlbumFolderNaming.swift` (Foundation only; it can be reused for other folder names).
- **What is saved when.** Every change in the photo library (a new photo, a photo put in an album, a new album, ...) triggers one
  look at all albums (the existing automatic back-up trigger is used, nothing new runs in the background). Only what is missing is
  saved. What was saved is written in a small file, the *ledger* (`PhotoAlbumLedger-<hash>.json` in the app's Application Support
  folder; one per back-up folder + path). A key `photo id|album id|photo/video/live` is added only after its file has been written,
  the file is written atomically (temporary file, then rename) and every few files, so a crash or an iOS kill loses at most the last
  few keys; those files are found on the disk the next time and are recognised, not saved again. When a run ends (not cancelled, no
  error) the library state is remembered, so the next automatic run stops at once if nothing changed. A file that could not be
  saved in a run that ended normally (for example a photo that is only in iCloud) is tried again at the next change in the library
  or when you press *Back-up new photos* yourself (that button always looks at all albums). A run that is cancelled (iOS ran out
  of background time) or ends with an error remembers nothing, so the next trigger continues where the ledger says.
- **Nothing is deleted.** Not on the PC and not on the phone. In this mode "Remove saved photos from source" and "Add to album" are
  hidden and ignored (a photo can be in several albums), and so are "Save photo adjustment data (AAE)", the time-zone setting and
  "Live photo file extension" (the Live Photo video is always `<same name>.MOV`). A file that is already in the folder, or that you
  deleted there on purpose (Syncthing knows), is not saved again. "Re-copy all photos" saves everything again to the same names.
- **Still used:** the photo/live/video switches, "Path in folder", "Do not save photos older than six months" (**on by default**:
  switch it off if you want every photo, however old; in this mode a photo that was saved once is remembered for good by the
  ledger, so switching it off does not bring deleted photos back), "Save all photos in a burst", and all background and
  automatic settings.

Known limits:

1. **Renaming an album** on the phone: photos saved after that go to a folder with the new name; the folder with the old name stays
   (nothing is renamed or moved on the PC). Rename the old folder on the PC by hand if you want one folder; Syncthing syncs that.
   Or press *Re-copy all photos*: that saves the whole album again into the folder with the new name (the old folder stays).
2. **A photo in two albums is stored twice**: twice the space on the PC, and on the phone for as long as the exported copies stay
   selected for sync (as with the original app: "Exported photos will take up storage space on your device ...").
3. If the ledger file is lost (app deleted and reinstalled, data cleared), every photo is checked again: files that are already
   there (on the disk or in Syncthing's list) are recognised, not saved again. In the rare case of two different photos with the
   same file name in one folder, one of them may then be saved a second time under another name.
4. Photos that are only in iCloud (not on the phone) cannot be exported (the app does not download them); they are tried again at
   the next change in the library.
5. The first run on a big library takes a long time (iOS may stop it; it continues at the next trigger, starting where the ledger
   says). Keep the app open and the phone charging for the first run.
6. From reading the code (not tested): the existing back-up pauses the Syncthing folder while it works and puts it back at the end.
   If iOS kills the app in the middle of a run, the folder may stay paused. The original app behaves like this too and album mode does
   not change it. If photos stop arriving after a crash, check that the folder is not paused.

Undo: `git revert <the album-folders commit>` (see the commit list) and push with `push_fork.ps1`; the ledger files become unused.

## Self-test in the build

The workflow step `albumnaming` (before the long steps) compiles `Sushitrain/AlbumFolderNaming.swift` together with
`tools/albumnaming_selftest/AlbumNamingSelfTest.swift` using the plain `swiftc` of the runner and runs it. It checks every naming
rule (forbidden characters, control characters, NFC, emoji, long names, device names, duplicate and case-only duplicate names,
stable numbering, file-name clashes, the hash, saving and loading of the ledger, a damaged ledger, another destination) and then
plays a whole story with the same planning calls the back-up makes (first pass, a pass that must save nothing, two photos with the
same file name, a renamed album, a crash in the middle of a file, a restart, "Re-copy all photos"). A failed check prints a line
starting with `ERROR:` and stops the build in seconds. To run it on a Mac:
`swiftc -swift-version 6 -parse-as-library -o /tmp/selftest Sushitrain/AlbumFolderNaming.swift tools/albumnaming_selftest/AlbumNamingSelfTest.swift && /tmp/selftest`.

## Not proven yet

The first compile of the fork (Go core, Xcode project, workflow) succeeded (run 1). The album-folder mode was written without a
compiler on hand: the build logs on the `build-logs` branch are its first compile. It was **not** run on a phone: real album
names, big libraries, Live Photos, the look at all albums after a real change and the iOS kill/restart behaviour are all untested.

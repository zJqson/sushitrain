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
that is only in those goes to `No album`. Albums that sit inside a folder of the Photos app are expected to be treated like any other
album (the folder hierarchy is not copied; same names get ` (2)`); this was not tested.

- **Windows-safe names.** `\ / : * ? " < > |` and control characters become `_`; names are made Unicode NFC; no space at the start,
  no space or dot at the end; `CON PRN AUX NUL COM0-9 LPT0-9` (also with an extension) get a `_` (`CON` becomes `CON_`,
  `nul.txt` becomes `nul_.txt`); at most 100 characters (and 240 bytes); an empty name becomes `Untitled album`. Names that differ
  only in upper/lower case are the same folder on Windows, so the second one gets ` (2)`, the third ` (3)`. A name is given once
  and then kept, so it never flips when albums are added or deleted. `No album` is reserved (an album called "No album" becomes
  "No album (2)"). The same rules are used for file names; two different photos with the same file name in one folder: the second
  one gets `_` and the first 6 letters/digits of its identifier (`IMG_0001_9F2D7C.HEIC`); only on a clash. All of this is in the
  one pure file `Sushitrain/AlbumFolderNaming.swift` (Foundation only; it can be reused for other folder names).
- **What is saved when.** Every change in the photo library (a new photo, a photo put in an album, a new album, ...) starts the
  existing automatic back-up trigger (nothing new runs in the background). A new photo is looked at alone (the *fast path*, see
  "Fast path for new photos" below); a change to an album, a big change or a change list that cannot be read makes one look at all
  albums. Only what is missing is saved. What was saved is written in a small file, the *ledger* (`PhotoAlbumLedger-<hash>.json` in the app's Application Support
  folder; one per back-up folder + path). Photos, videos and the videos of Live Photos are written to a temporary file first and get
  their real name only when complete (so a kill never leaves half a file under a real name that a later run would take for a
  finished one). A key `photo id|album id|photo/video/live` is added only after its file is in place,
  the ledger is written atomically (temporary file, then rename) and every few files, so a crash or an iOS kill loses at most the last
  few keys; those files are found on the disk the next time and are recognised, not saved again. When a run ends (not cancelled, no
  error) the library state is remembered, so the next automatic run stops at once if nothing changed. A file that could not be
  saved in a run that ended normally (for example a photo that is only in iCloud) is tried again at the next change in the library
  or when you press *Back-up new photos* yourself (that button always looks at all albums). A run that is cancelled (iOS ran out
  of background time) or ends with an error remembers nothing, so the next trigger continues where the ledger says.
- **Nothing is deleted.** Not on the PC and not on the phone. In this mode "Remove saved photos from source" and "Add to album" are
  hidden and ignored (a photo can be in several albums), and so are "Save photo adjustment data (AAE)", the time-zone setting and
  "Live photo file extension" (the Live Photo video is always `<same name>.MOV`). A file that is already in the folder, or that you
  deleted there on purpose (Syncthing knows), is not saved again. "Re-copy all photos" saves everything again to the same names.
- **Still used:** the photo/live/video switches, "Path in folder", "Do not save photos older than six months" (**off by default
  in this fork**, so the first run saves every photo, however old; switch it on if you only want the last six months; in this
  mode a photo that was saved once is remembered for good by the ledger, so a photo that you delete from the folder does not come
  back), "Save all photos in a burst", and all background and automatic settings.

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
6. The back-up pauses the Syncthing folder while it works and puts it back at the end. The pause is saved in Syncthing's
   configuration, so when iOS ends the app in the middle of a run (a long first album run makes that likely) the folder stays paused,
   and the original app would then keep it paused for good ("it was paused before"). The fork notes in the app's preferences that
   it paused the folder itself (`photoBackupFolderPausedByApp`) and un-pauses it at the end of the next run. A folder that YOU
   paused is never un-paused. This recovery is written from reading the Go core (`SetPaused` saves the config); it was not run on a
   phone.
7. A ledger file that exists but cannot be read (iOS keeps app files closed until the phone is unlocked once after a restart) stops
   the run with a message instead of starting an empty ledger; the next run tries again. A file that is really damaged is moved
   aside as `.damaged` and a new ledger is started (files already in the folder are then recognised, not saved again).

First run, step by step:

1. *Settings, Photo back-up*: *From album* = **Every album (one folder per album)**, *To folder* = the back-up folder (a
   send-and-receive or send-only folder; the picker only offers suitable ones).
2. "Do not save photos older than six months" is **off by default in this fork**: the first run saves every photo. Switch it on only if you want just the last six months.
3. Press *Back-up new photos* on the Start screen (or wait: the app also starts by itself when a photo arrives) and keep the app
   open and the phone charging. The progress bar shows the album that is being saved.
4. *Settings, Support, View log messages* has lines that start with `Album back-up:`: how many albums were found, how many files were
   saved, how many were there already, how many could not be saved this time.
5. The folders appear on the PC when Syncthing has synced them. Pressing the button again later only saves what is new.

Undo: revert all album-folder commits, `git revert --no-edit 169be91..HEAD` (169be91 is the commit just before them), and push with
`push_fork.ps1`; the ledger files become unused.

## Fast path for new photos

Until build 7, every change in the photo library (even one new photo) made the automatic back-up look at ALL albums again. On the
real iPhone (10,027 items, about 8,500 of them only in iCloud) such a pass that saved nothing took about 7 minutes, and the
Syncthing folder is paused during a pass, so the PC could fetch nothing meanwhile. Now an automatic run first asks Photos *what*
changed (`PHPhotoLibrary.fetchPersistentChanges`) and decides (the decision is the pure file `Sushitrain/PhotoChangePlan.swift`):

| What Photos reports since the last good run | What the app does |
|---|---|
| Only photos or videos added or changed (up to 200), and no album changed | **Fast path.** Looks at those photos only. For each one it finds the user albums it is in (none = `No album`) and runs the normal album code for those (photo, album) pairs. The ledger decides what is saved already, so a changed old photo costs nothing. |
| Only deletions on the phone (or a photo added and deleted again) | Nothing to do. Deleting on the phone never deletes on the PC. |
| An album changed: created, renamed, a photo put in or taken out, deleted | **Full pass** over all albums, as before. A photo can be put in an album without being changed itself, so only a full look finds it. |
| The list of changes cannot be read (the saved library state expired, Photos refuses) | Full pass. |
| More than 200 photos changed at once (for example iCloud touching many photos) | Full pass. |
| The button *Back-up new photos*, *Re-copy all photos*, the very first run | Always the full pass (unchanged). |

Smart albums (Recents, Favorites, ...), iCloud Shared Albums and other collections the back-up never looks at do not count as an
album change. An album that cannot be found any more (deleted) does.

**When the library state is remembered.** After a fast or full pass the app remembers the state of the library, so the next run reads
only newer changes. It does that only when the pass ended without an error and was not cancelled; otherwise the next trigger reads
the same changes again and tries again. Files that could not be saved (a photo that is only in iCloud: the app never downloads from
iCloud):

- after a **full** pass they are tried again at the next full pass (as in build 7);
- after a **fast** pass, a photo that was **added** and could not be saved (it was not readable a moment ago, or it is only in iCloud)
  keeps the old state, so the next run reads the same changes again and tries again. If it stays unsavable, the changes pile up until
  more than 200 photos are listed and a full pass starts;
- after a fast pass, a **changed old** photo that cannot be saved (typically it is only in iCloud; iCloud touches many such photos all
  the time) does not hold the state back. It is tried again at the next full pass or when the photo changes again (for example when
  iOS downloads it).

**Settings.** Both are stored preferences with no screen yet (no UI was asked for), so they stay at their defaults until a screen is added:

| Key | Default | Meaning |
|---|---|---|
| `photoBackupQuietSeconds` | 8 (was a fixed 20) | Seconds the app waits after the LAST change in the library before it runs. Used range 3 to 120. Every new change restarts the wait, so a burst of photos or a Live Photo that Photos is still finishing is not exported half-written. |
| `photoBackupFastPathMaxAssets` | 200 | Most changed photos the fast path takes. More than that means a full pass. 0 switches the fast path off (always the full pass, as in build 7). Used range 0 to 5000. |

**The log.** *Settings, Support, View log messages* has one line per run in album mode, written when the run ends (also after an
error or a cancel), for example:

```
Photo back-up run (automatic): path=fast (1 photo), I=1 U=0 C=0 D=0, 1850 ms, result=done
Photo back-up run (automatic): path=full (an album changed), I=0 U=2 C=1 D=0, 421000 ms, result=done
```

`I` = photos added, `U` = photos changed, `C` = albums that matter, `D` = photos deleted, then the milliseconds of the whole run (it
includes pausing and un-pausing the Syncthing folder). `result=` is `done`, `done, nothing to save`, `done, but an added photo could
not be saved yet (tried again at the next run)`, `cancelled` or `error: ...`. The arrival time on the PC is the file's creation time
there minus the time the photo was taken.

Known limits of the fast path:

1. A renamed album still gets a new folder (a rename is an album change, so it is a full pass; the files already saved stay in the
   old folder, see "Known limits" above).
2. Not run on a phone yet. How Photos fills `PHPersistentChange` for a real new photo (which albums it lists as changed, how many photos
   iCloud touches) is the thing to read in the log: if every run says `path=full (...)`, the reason in the brackets says why.
3. A photo that is put into an album a moment after it was taken is first saved in `No album` (if the run happens in between) and is
   then saved in the album folder too by the full pass that the album change causes (it is in both folders, as a photo in two albums).
4. The fast path pauses the Syncthing folder for the seconds it needs (as every pass does), then puts it back.

To watch it work: take a photo, wait about 10 seconds, open *Settings, Support, View log messages* and look for the last line that starts
with `Photo back-up run`. On the PC the photo appears in the `No album` folder (or in the folder of its album) of the back-up folder.

Undo: revert the fast-path commits, `git revert --no-edit 26326cc..HEAD` (26326cc is the build-7 commit just before them), and push with
`push_fork.ps1`. The setting `photoBackupFastPathMaxAssets` = 0 would also switch the fast path off, but it has no screen yet.

## Self-test in the build

There are two fast self-tests before the long steps. The first is `albumnaming`, the second `photochange` (see below).

The workflow step `albumnaming` (before the long steps) compiles `Sushitrain/AlbumFolderNaming.swift` together with
`tools/albumnaming_selftest/AlbumNamingSelfTest.swift` using the plain `swiftc` of the runner and runs it. It checks every naming
rule (forbidden characters, control characters, NFC, emoji, long names, device names, duplicate and case-only duplicate names,
stable numbering, file-name clashes, the hash, saving and loading of the ledger, a damaged ledger, another destination) and then
plays a whole story with the same planning calls the back-up makes (first pass, a pass that must save nothing, two photos with the
same file name, a renamed album, a crash in the middle of a file, a restart, "Re-copy all photos"). A failed check prints a line
starting with `ERROR:` and stops the build in seconds. To run it on a Mac:
`swiftc -swift-version 6 -parse-as-library -o /tmp/selftest Sushitrain/AlbumFolderNaming.swift tools/albumnaming_selftest/AlbumNamingSelfTest.swift && /tmp/selftest`.

The step `photochange` does the same for `Sushitrain/PhotoChangePlan.swift` (the fast-path decision) with
`tools/photochange_selftest/PhotoChangeSelfTest.swift`: a new photo alone, a new photo plus an update of the same photo, an update of
an old photo, many updates (exactly at the limit and one over), an album created / renamed / changed in membership, deletions alone,
a deletion together with an insertion, a photo added and deleted again, an empty change list, change records with nothing that matters,
an unreadable change list (expired saved state), duplicate and empty identifiers, another mode that ignores albums, the two settings
and their limits, when the library state may be remembered (completed / incomplete / failed / cancelled), how a fast pass ends (an
added photo that could not be saved holds the state back, a changed old one does not), the log line, and a story of several
runs (a failed run is repeated, a cancelled full pass is repeated, an unsaved new photo is tried again, a big change falls back to the
full pass and the next single photo is fast again). To run it on a Mac:
`swiftc -swift-version 6 -parse-as-library -o /tmp/selftest2 Sushitrain/PhotoChangePlan.swift tools/photochange_selftest/PhotoChangeSelfTest.swift && /tmp/selftest2`.

## Not proven yet

The first compile of the fork (Go core, Xcode project, workflow) succeeded (run 1). The album-folder mode was written without a
compiler on hand: the build logs on the `build-logs` branch are its first compile. It was **not** run on a phone: real album
names, big libraries, Live Photos, the look at all albums after a real change and the iOS kill/restart behaviour are all untested.

The fast path ("Fast path for new photos") was also written without a compiler on hand. Its decision file is covered by the CI
self-test; the Photos glue only compiled. Not run on a phone: what `PHPersistentChange` really lists for a new photo (photos, albums,
smart albums), the lookup of the albums a changed photo is in (`PHAssetCollection.fetchAssetCollectionsContaining`), the fetch narrowed to the
changed photos, the fallback rules and the timing (the log line shows it).

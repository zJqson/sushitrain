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
| `photoBackupQuietSeconds` | 3 (8 in builds 8 to 12; a fixed 20 before) | Seconds the app waits after the LAST change in the library before it runs. Used range 3 to 120. Every new change restarts the wait, so a burst of photos or a Live Photo that Photos is still finishing is not exported half-written. |
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

## Staying alive in the background, screen off (builds 12 and 13)

**What was measured on the real iPhone (iOS 27.0.1), with the phone's own system log read over USB.**

- With the screen locked and nothing else running, the app lived at least 33 minutes in the background (22 of them with the screen locked)
  and held the iOS "Location subscription" assertion; it used 69 MB of memory and about 2 % CPU. So **the screen being off does not stop it.**
- The loss at 18:48:30 was a **swipe-away in the app switcher**, not iOS freezing the app: SpringBoard logged `killed from app switcher`,
  exception code `User Initiated Quit (0xDEADFA11)`. There is no crash report and no jetsam report.
- The earlier loss at 18:00:40 happened while a big foreground app (Facebook) was being used; nothing was logged on the phone at that
  time, so a memory kill by that big app is possible but not proven.
- The two "Lost device connection ... forcibly closed" lines of the PC's Syncthing log mean different things: the app being brought to the
  front (it reconnects at once) and the app process being ended. Only the second one needs a restart of the app.
- A process that is killed (not swiped away) and then started by the App Shortcut "Back-up new photos" (Spotlight, search "PhotoTrain")
  is running again in the background after 7 seconds, holds the "Location subscription" assertion again and is connected to the PC.
- **Swipe-away test (19:44, build 13, iOS 27.0.1).** The app was thrown away in the app switcher with a real swipe. SpringBoard logged
  `killed from app switcher`, `User Initiated Quit (0xDEADFA11)` and runningboardd `user-quit`: the same lines as the 18:48:30 loss. iOS
  did **not** start the app again by itself (watched 66 seconds: no connection to the PC). A fake location jump (the "significant
  location change" trick, 4.5 s, another city) did not bring it back either. The same jump after a plain `kill` (not a swipe) started
  the app in the background once (hold 4.4 s: `intent background` 0.1 s after the first fix) and failed in the other six tries, so
  the trick is **not dependable** and nothing is built on it.
- **Starting the app from the PC without showing it** (needs the USB cable, trust and Developer Mode). The developer launch call with the
  extra option `ActivateSuspended = true` starts the app **in the background**: SpringBoard logs `Bootstrapping ... with intent background`,
  the Home screen stays as it is, the PC sees the iPhone again after 1.0 s (screen on) or 1.5 s (phone locked), the silent sound and the
  location keeper start, the blue location pill shows. The same call without the option is `intent foreground-interactive` (the app opens
  in front). Rule used: **check first, send nothing when the app is alive**, and keep "show the app" a separate action:
  ```python
  # pip install pymobiledevice3 ; phone on USB, trusted, Developer Mode on. rsd = await establish_userspace_rsd()
  async def start_in_background(rsd, bundle="com.jason.phototrain.WV85FMU43R"):
      async with DvtProvider(rsd) as dvt:
          async with DeviceInfo(dvt) as info:
              if any(p.get("bundleIdentifier") == bundle for p in await info.proclist()):
                  return "running: nothing sent"
          async with ProcessControl(dvt) as pc:
              await pc.launch(bundle_id=bundle, arguments=[], kill_existing=False, start_suspended=False,
                              environment={}, extra_options={"ActivateSuspended": True})
      return "started in the background"
  ```
  The ready tool is `phoneops.py` (`alive`, `start`, `show` = bring to front without restarting, `kill`, `launch`, `fakeloc`) next to this
  work in `D:\HelperWork\fastpath2_20261104`. Open the app switcher from the PC with two quick Home presses (`switcher.py double-home`);
  a swipe from the bottom edge is ignored by iOS when it comes over the cable.
- **Installing a new build over a running copy stalls.** Sideloadly stuck at 88 % for 4 minutes while the old copy was running (iOS:
  `installcoordinationd: Update skipped`); after `dvt kill` of the old process the install finished in 4 seconds. End the old app first.
- **Heavy foreground apps:** Camera, Maps, Safari, Photos, Camera, Maps opened one after the other (about 60 s): the app stayed alive.
- **Screen off, app alone (build 13, started from the PC in the background, phone locked and untouched).** A photo taken from the lock
  screen (Camera opened by swiping left, the phone stays locked) reached the PC after **10.4 s** (phone locked 10 min), **9.6 s**
  (30 min), **9.7 s** (60 min) and **10.1 s** (120 min). The same test on build 10, with the 8 s settle wait: 20.2 s with the phone locked and 17.8 s with the
  screen on. Shortening the wait from 8 s to 3 s therefore saved about 10 s. The app was alive at every check (the last one 2 h 19 min
  after its start) and the PC's Syncthing log shows no lost connection in that time (the last one was at 19:53:48, when the old copy was
  ended before the start). Where the 9.7 s of the 60 minute photo went (phone's log, PC log): 4.2 s from the shutter
  until Photos reports the new photo (`Photo library changed; the app is in the background`, an event: the observer fires with the screen
  locked), 3.4 s settle wait, 0.7 s for the run (`path=fast (4 photos), I=1 U=4`), 1.5 s from the end of the run until the file is on the PC.
  After every photo a second run follows 4 s later (`path=nothing to do`, 18 to 25 ms): Photos reports a small follow-up change.
- **Cost of build 13 (phone's own counters, `dvt sysmon`, app alone, screen locked):** about 1.9 % of one CPU core, 31 to 36 wake-ups per
  second and 44 to 48 MB of memory (growing about 0.05 MB per minute in the first 73 minutes, then flat: 47.9 MB at 21:12, 47.7 MB at 22:13).
  The counters read at the four alive checks (cumulative CPU time and wake-ups) give 1.78 % and 30.8 wake-ups per second for 20:23 to 22:13
  (the last hour: 1.71 % and 29.5). Build 10 was measured once, for 10 minutes: 0.7 %,
  24 wake-ups per second, 35 MB, so this comparison is rough. The extra is probably the silent sound (the audio hardware wakes the app
  about 10 times a second); the switch "Also play silence" turns it off. Not proven: an A/B test with the switch off, and the battery use.

**What builds 12 and 13 change.**

1. **Second keeper: an inaudible sound** (Settings, Background synchronization, "Also play silence", on by default; "audio" was already in
   `UIBackgroundModes`). iOS treats an app that plays sound like a music player: it is closed last when memory runs low. It is mixed with
   other apps' sound, so music, calls and videos are not interrupted. It asks for the longest audio buffer (fewer wake-ups) and costs a
   little battery. The status line says `Silent sound: playing`. There is no timer in it: the audio hardware drives it.
2. **Visible log lines.** The core keeps only warnings unless "Enable debug logging" is on, so the lines that matter now use warning level
   (`Log.note`) and are also written to the phone's system log in clear text (subsystem `com.jason.phototrain`). They appear in Settings,
   Support, View log messages: scene changes, `Started; the app is in the background / in front; free memory ...`, memory warnings, photo
   library changes, the one line per photo run, silent-sound start/stop/interruption, and `Sync is off because ...` / `Sync is allowed ...`
   whenever the network rules change their mind. Caveat: for an app started in the background with the developer launch option above,
   UIKit reports the app as *active*, so the start line can say `in front` although nothing is shown on the screen; the proof of a
   background start is SpringBoard's `intent background` line and the unchanged screen.
3. **"The app was not running from ... until ..."** is shown at the next start (and on the Background screen) when the gap since the last
   sign of life is more than 3 minutes. Signs of life are written only when something happens (scene change, photo run, memory warning, and
   the app's existing 50 second measurement timer, at most every 5 minutes): no new timer.
4. **The network rules are now a tested pure file** (`Sushitrain/KeepAliveRules.swift`, CI self-test step `keepalive`). Behaviour is the same
   as before: the sync is off in Low Power Mode (if that switch is on), when the network is not known, on mobile data, on a metered
   (expensive) network and when Low Data Mode is on for the network. The shipped settings are: mobile data blocked, metered blocked.
5. **The settle wait before an automatic run is 3 seconds** (build 13; it was 8 in builds 8 to 12 and 20 before the fast path). It is still
   one wait that every new change in the photo library restarts, so a burst of photos is saved once, 3 seconds after the last one.
6. The actions "Back-up new photos" and "Synchronize for a while" may run while the phone is locked (`authenticationPolicy = .alwaysAllowed`).
7. A hint under the switch: do not swipe the app away in the app switcher.

**How a new photo is noticed.** By an event, not by looking: the app registers once as a `PHPhotoLibraryChangeObserver`; when Photos
reports a change, one wait of 3 seconds starts (every further change restarts it), then the fast path looks at the new photo only. No
timer scans the library. The setting "Copy photos periodically in the background" (a system-scheduled background task) is off, and none of
the changes of builds 12 and 13 adds a timer: the location keeper is event driven, the silent sound is driven by the audio hardware.

**What iOS cannot do (honest list).** Nothing in the app can start itself after a swipe-away in the app switcher while iOS treats that as
the user's decision (measured: 66 s with no restart, and a fake location jump did not help); the keepers only help while the app is
running. The only restart that was dependable is the one from the PC over the USB cable (above) or by hand (tap the app, or the
App Shortcut "Back-up new photos" in Spotlight). Under very high memory pressure iOS can still end any background app. A photo taken while the app is not running is picked up the next time the app runs (it looks at everything that changed since the
last good run). The app cannot be told by iOS to start when a photo is taken.

**Never on a hotspot: the honest answer.** iOS marks the Personal Hotspot of an *iPhone* as "expensive", and the setting "On metered
networks" blocks it. An *Android* hotspot (for example a Samsung S10) is not marked by iOS: the app sees normal Wi-Fi. The only
dependable block is **Low Data Mode for that Wi-Fi network** (iPhone Settings, Wi-Fi, the (i) next to the hotspot's name, *Low Data Mode*
on, done once when the iPhone first joins it): the app then sees `constrained` and logs `Sync is off because Low Data Mode is on for this
network`. Not built, because it cannot be done reliably: guessing a hotspot from its address range (an Android hotspot often uses
192.168.43.x but not always), and allowing only named home networks (reading the Wi-Fi name needs an entitlement a free Apple ID does not
have). Syncing only when the PC is on the same local network would block every hotspot, but it also blocks every public Wi-Fi.

## Manual transfers on a hotspot: the per-device exception (build 16 and later)

**What it is.** The rule "never on mobile data, never on a metered or Low Data Mode network" stays exactly as it was for the photo
back-up. New: for ONE device the user can switch on **"Allow on mobile data and hotspot (manual transfers only)"** (Devices, tap the
device, tab General, section *Mobile data and hotspot*). It is **off for every device**, so an existing install behaves as build 15.
The use case: the PC runs two Syncthing devices, the MAIN one that receives the photo back-up and a second one ("Drop") that shares only a
folder `drop` for files, folders and zips that Jason sends by hand. The Drop device gets the switch; the main device never does.

**How it works.** The app already stops Syncthing from talking to a device by pausing that device (`setDevicesPaused`, one call for all
devices). `AppState.updateDeviceSuspension()` now decides device by device (`peersAllowedByNetworkRules`) with the pure rule
`ConnectivityRules.blockReason(flags:settings:device:)` in `KeepAliveRules.swift`. For a device with the switch on, mobile data, a metered
network and a Low Data Mode Wi-Fi no longer pause it. Everything else stays for ALL devices: an unknown network (the whole start-up, because
the network monitor has not reported yet: every device is paused BEFORE the core starts, as before), Low Power Mode when that limit is on,
and a device the user paused. The two-argument `blockReason(flags:settings:)` of build 15 still exists and is the rule for a device without the
switch; the self-test compares it with a word-for-word copy of build 15's rule for all 512 inputs.

**Fail-safe (the photos can never leave on a restricted network).** The switch is ignored for every device that shares the photo back-up
folder (`PhotoBackup.selectedFolderID`, every mode including "Every album", because the album folders are directories inside that one
Syncthing folder) and for every device that shares a folder whose path is the same as, inside or around the back-up folder's path
(`BackupFolderGuard`; paths are compared folder by folder, without upper/lower case, `.` and `..` resolved, `/private/var` = `/var`; a wrong
guess can only make the rule stricter). For such a device the switch is greyed out with the reason (or, if it was set before, stays
visible and says "the switch is ignored"), the device screen, the start screen (while the network is blocked) and the log say so, and the
old rule applies. The check is made again when a
folder is shared with a device or unshared (`AppState.sharingChanged()`, six places in the screens), when another back-up folder is
chosen, and when a folder is moved to another place; also at every start, network change, Low Power Mode change and settings change.

**Where the state is shown (no new screen).** (1) The start screen's network label (`NetworkStatusView`): without any switch it says what it
always said, plus one grey line *"Paused, because Low Data Mode is on for this network."*; with a switch on and a blocked network it shows
*"Photo back-up and other devices: paused, because Low Data Mode is on for this network."* and *"Drop: allowed on this network (manual
transfers)."* (2) The device screen shows the line of that device under the switch. (3) The log (Settings, Support, View log messages) gets
`Manual-transfer exception: ...` lines whenever the text changes, and `Manual-transfer switch for NAME is now on/off.` when it is flipped.

**Where the switch is kept.** `AppUserSettings.devicesAllowedOnRestrictedNetworks`, a preference (`@AppStorage`, the list of device IDs;
empty by default), like `userPausedDevices`. It is known before the core starts. No timer, no polling: every decision is an event
(start, network path change, Low Power Mode change, a setting, the switch, a share change).

**What the core does on a restricted network when only the Drop device is unpaused** (read in Syncthing's own source at the commit the core
uses, `lib/connections/service.go` and `lib/model/model.go`): the dial loop skips every paused device before it looks an address up
(`if deviceCfg.Paused { continue }` comes before `resolveDialTargets` / the discovery lookup), so on a hotspot the core dials and looks up
only the Drop device; a connection that comes in from a paused device is closed in `connectionCheckEarly` (`errDevicePaused`, after the TLS
handshake told who it is); pausing a device closes its connection; unpausing one makes the dial loop run at once. What is NOT per device and
therefore the same as in build 15: the core's own listener, its announcements to the global discovery servers, relay and NAT/STUN
keep-alives (the app's own switches in Settings, sections *Discovery* and *Network traversal*). No byte counts were measured (no phone, no hotspot).

**Not proven.** A real hotspot, a real Drop device on the phone, and the behaviour of the core on mobile data with only the Drop device
unpaused were not tried; the Swift code was written without a compiler and is checked by the CI (self-test step `keepalive`) and by a Python
model (`D:\HelperWork\devnet_20261105\model`, 20 planted mistakes all caught). Known limits: a folder share that arrives without any screen of
the app being used (an *introducer* device, keep that switch off) is noticed at the next start, network change or setting change, not at
once, because the core's events do not reach the app in the background and a timer is not allowed; two decisions that run at the same moment
(the same race as in build 15) each use the state they saw.

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

The step `keepalive` does the same for `Sushitrain/KeepAliveRules.swift` with `tools/keepalive_selftest/KeepAliveSelfTest.swift`: the network
rules (plain Wi-Fi allowed; mobile data, metered, Low Data Mode, Low Power Mode and an unknown network blocked; every switch really
switches; a device without a SIM; the order of the reasons; the Android-hotspot limit), the per-device exception for manual transfers
(a table of all 512 combinations of network situation and settings, compared with a word-for-word copy of build 15's rule: a device
without the switch must get the same answer in every one; a device with the switch is stopped only by an unknown network and Low Power
Mode; the switch is ignored for a device that shares the photo back-up folder; the plain-words lines; which devices share the back-up
folder, with nested, surrounding, same-name, upper/lower-case and `/private/var` paths) and the sign-of-life note (durations, the gap
message, the stored marks with their spacing, in a throw-away preference suite). To run it on a Mac:
`swiftc -swift-version 6 -parse-as-library -o /tmp/selftest3 Sushitrain/KeepAliveRules.swift tools/keepalive_selftest/KeepAliveSelfTest.swift && /tmp/selftest3`.

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
self-test. **Update 2026-11-04:** it has since run on the phone (builds 11 to 13, iOS 27.0.1): a new Camera photo gives `path=fast
(2 to 4 photos), I=1`, a run of 0.7 to 1.2 s, and the file is on the PC about 10 s after the shutter, with the screen off. Still not run on a
phone: the fallback rules (an album that changed, more than the limit of photos, an unreadable change list) and the look at all albums
after a real album change.

**Not proven yet after round 2 (builds 12 and 13).**
- A phone restart: after it the app runs only when someone starts it (or the PC watcher does, if the phone is on the cable and was
  unlocked once). Not tested.
- An app that is alive but frozen by iOS would look alive to the PC check (`alive` only reads the process list). Not seen so far.
- Real memory pressure by big apps (games, video editors): only Camera, Maps, Safari and Photos were tried.
- The battery use over a day, and the cost of the silent sound (A/B with the switch off).
- Whether an app that was started in the background has a card in the app switcher: SpringBoard's log says no (every start in the front writes
  `Adding SwitcherScene overlay` and `didAddExternalForegroundApplicationSceneHandle`; the five background starts wrote neither), but
  the card list itself was not scrolled to look.
- Starting the app from the PC works only while the phone is on the PC's USB cable.

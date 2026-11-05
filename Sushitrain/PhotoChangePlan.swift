// Copyright (C) 2026 Jason (personal fork of Synctrain / Sushitrain by Tommy van der Vorst)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
import Foundation

// The decision behind the "fast path" of the automatic photo back-up: after the photo library changed, how much of it has to be
// looked at? A new photo needs one look at that photo; a renamed album needs a look at everything.
//
// PURE SWIFT: this file imports only Foundation (no Photos, UIKit, SwiftUI or SushitrainCore) on purpose. The CI compiles it with a
// plain `swiftc` together with tools/photochange_selftest/PhotoChangeSelfTest.swift in a few seconds, before the long build starts.
// It knows no Photos types either: photos and albums are plain strings (Photos' local identifiers) here, so the same decision can
// serve another back-up mode (for example the date layouts: pass `albumChangesMatter: false`) without any change.
//
// The glue in PhotoBackup.swift reads the change list from Photos (PHPersistentChange), puts it in a `PhotoChangeInput`, asks
// `PhotoChangePlanner.plan` and then does what the answer says.

/// What the photo library reported since the last successful back-up, as plain strings and numbers.
struct PhotoChangeInput: Equatable, Sendable {
	/// Photos and videos that were added (Photos' local identifiers).
	var inserted: Set<String> = []
	/// Photos and videos that were changed (edited, marked as favourite, their iCloud state changed, ...).
	var updated: Set<String> = []
	/// Photos and videos that were deleted. Deleting on the phone never deletes on the PC; these only keep the planner from looking
	/// for photos that are gone.
	var deleted: Set<String> = []
	/// Albums that matter to the back-up and were created, renamed, got or lost a photo, or were deleted (identifiers). Albums that the
	/// back-up never looks at (smart albums, iCloud Shared Albums, ...) are left out by the caller.
	var changedAlbums: Set<String> = []
	/// How many change records (transactions) the library reported. Lets the caller tell "nothing happened" from "something
	/// happened, but nothing that matters".
	var changeRecords = 0
	/// Set when the list of changes cannot be read (the saved library state is too old or not available): then nothing is known about
	/// what changed. The text says why (for the log).
	var unreadableReason: String? = nil

	/// True when the library changed at all since the saved state.
	var hasAnyChange: Bool {
		return changeRecords > 0 || !inserted.isEmpty || !updated.isEmpty || !deleted.isEmpty || !changedAlbums.isEmpty
	}
}

/// What the back-up has to look at.
enum PhotoChangePlan: Equatable, Sendable {
	/// Nothing: the changes do not need any work.
	case nothing
	/// Only these photos and videos (local identifiers). The albums did not change, so every other photo stays as it is.
	case only(Set<String>)
	/// Everything (all albums), for this reason.
	case full(reason: String)
}

/// How a back-up run ended.
enum PhotoRunOutcome: Equatable, Sendable {
	/// Ended normally and saved everything it was asked to save.
	case completed
	/// Ended normally, but a photo or video that was ADDED could not be saved yet (it was not readable a moment ago, or it is only in
	/// iCloud). Only the fast path reports this; see `PhotoChangePlanner.fastPassOutcome`.
	case incomplete
	case cancelled
	case failed
}

enum PhotoChangePlanner {
	/// Seconds the automatic back-up waits after the LAST change in the photo library (a burst of photos, or a Live Photo that is still
	/// being finished, keeps restarting the wait). 3 is the smallest allowed value; it was 8 in builds 8 to 11 and 20 before the fast path.
	/// A file is never read half-written: Photos reports an added photo only when it is saved, and a photo whose Live Photo video is
	/// attached a moment later is changed (and therefore looked at) again, see PhotoChangePlanner.fastPassOutcome.
	static let defaultQuietSeconds = 3
	static let minQuietSeconds = 3
	static let maxQuietSeconds = 120
	/// Most photos the fast path looks at; more than that and the whole library is looked at. 0 switches the fast path off.
	static let defaultFastPathMaxAssets = 200
	static let largestFastPathMaxAssets = 5000

	/// The saved "quiet seconds" setting, brought into 3...120.
	static func clampQuietSeconds(_ seconds: Int) -> Int {
		return min(max(seconds, minQuietSeconds), maxQuietSeconds)
	}

	/// The saved "most photos in the fast path" setting, brought into 0...5000.
	static func clampFastPathMaxAssets(_ count: Int) -> Int {
		return min(max(count, 0), largestFastPathMaxAssets)
	}

	/// The photos and videos that may need work: added or changed, and not deleted again. Empty identifiers are ignored.
	static func assetsToLookAt(_ input: PhotoChangeInput) -> Set<String> {
		var result = input.inserted.union(input.updated)
		result.subtract(input.deleted)
		_ = result.remove("")
		return result
	}

	/// The decision.
	///
	/// - The list of changes cannot be read: look at everything.
	/// - An album changed (and `albumChangesMatter`): look at everything. A photo can be put in an album without being changed itself,
	///   so only a look at all albums finds it.
	/// - Otherwise only the added or changed photos can need work (the ledger of the back-up knows what is saved already, so a changed
	///   old photo costs nothing). None left: nothing to do.
	/// - More than `maxAssets` of them: look at everything (a big change, for example after a long time without a back-up).
	static func plan(_ input: PhotoChangeInput, maxAssets: Int, albumChangesMatter: Bool = true) -> PhotoChangePlan {
		if let why = input.unreadableReason {
			return .full(reason: "the list of changes cannot be read: \(why)")
		}
		if albumChangesMatter && !input.changedAlbums.isEmpty {
			let count = input.changedAlbums.count
			return .full(reason: count == 1 ? "an album changed" : "\(count) albums changed")
		}
		let work = assetsToLookAt(input)
		if work.isEmpty {
			return .nothing
		}
		if work.count > maxAssets {
			return .full(reason: "\(work.count) photos changed, more than the limit of \(maxAssets)")
		}
		return .only(work)
	}

	/// How a FAST pass ended. A fast pass looks only at the photos the library reported, so no later pass is sure to find a file it could
	/// not save (a full pass looks at everything again at its next run). Therefore it is `incomplete` - the old library state is kept and
	/// the next run reads the same changes again - when a photo or video that was ADDED is still open. A changed old photo that cannot be
	/// saved (typically it is only in iCloud) does not hold the state back: iCloud touches many such photos all the time, and holding the
	/// state would make every later run read them again until the limit forces a full pass.
	static func fastPassOutcome(openAssetIDs: Set<String>, inserted: Set<String>, cancelled: Bool) -> PhotoRunOutcome {
		if cancelled {
			return .cancelled
		}
		if !openAssetIDs.isDisjoint(with: inserted) {
			return .incomplete
		}
		return .completed
	}

	/// May the back-up remember the library state it started from (so that the next run only reads newer changes)?
	/// Only when the run ended without an error, was not cancelled and saved everything it was asked to save (`completed`): otherwise
	/// the next run must read the same changes again.
	/// A run with nothing to do remembers it only when changes were seen (so they are not read again), not when nothing happened.
	static func mayRememberLibraryState(plan: PhotoChangePlan, hadChanges: Bool, outcome: PhotoRunOutcome) -> Bool {
		if outcome != .completed {
			return false
		}
		switch plan {
		case .nothing:
			return hadChanges
		case .only, .full:
			return true
		}
	}

	/// The folder is paused while a run saves files (the pause is saved in Syncthing's configuration). The app writes a note "I paused it" so
	/// that a run after a crash can tell the app's pause from the user's own. May that note be removed at the end of a run? Only when the app
	/// paused the folder AND putting it back worked. When putting it back failed the note must stay, or the next run would take the pause for
	/// the user's own and keep the folder paused for good.
	static func mayRemovePausedNote(appPausedIt: Bool, putBackWorked: Bool) -> Bool {
		return appPausedIt && putBackWorked
	}

	/// The shortcut "nothing to do" must still put back a folder that an earlier run (ended by iOS in the middle of its work) left paused: that is
	/// when the note says the app paused it and it is paused now. A folder the user paused (no note) is never touched.
	static func shouldPutFolderBackWithoutWork(noteSaysAppPausedIt: Bool, isPausedNow: Bool) -> Bool {
		return noteSaysAppPausedIt && isPausedNow
	}

	/// The end of a run in words, for the log.
	static func describeOutcome(_ outcome: PhotoRunOutcome) -> String {
		switch outcome {
		case .completed:
			return "done"
		case .incomplete:
			return "done, but an added photo could not be saved yet (tried again at the next run)"
		case .cancelled:
			return "cancelled"
		case .failed:
			return "failed"
		}
	}

	/// The path in words, for the log.
	static func describe(_ plan: PhotoChangePlan) -> String {
		switch plan {
		case .nothing:
			return "nothing to do"
		case .only(let ids):
			return ids.count == 1 ? "fast (1 photo)" : "fast (\(ids.count) photos)"
		case .full(let reason):
			return "full (\(reason))"
		}
	}
}

/// One line for the log per back-up run: how it was started, which path it took and why, what the library reported (I = added,
/// U = changed, C = albums that matter, D = deleted), how long it took and how it ended.
struct PhotoRunReport: Equatable, Sendable {
	/// "automatic", "by hand" or "re-copy all"
	var trigger: String
	var plan: PhotoChangePlan = .full(reason: "not decided")
	var inserted = 0
	var updated = 0
	var albums = 0
	var deleted = 0

	mutating func record(input: PhotoChangeInput, plan decided: PhotoChangePlan) {
		self.inserted = input.inserted.count
		self.updated = input.updated.count
		self.albums = input.changedAlbums.count
		self.deleted = input.deleted.count
		self.plan = decided
	}

	func logLine(milliseconds: Int, result: String) -> String {
		let path = PhotoChangePlanner.describe(plan)
		return "Photo back-up run (\(trigger)): path=\(path), I=\(inserted) U=\(updated) C=\(albums) D=\(deleted), \(milliseconds) ms, result=\(result)"
	}
}

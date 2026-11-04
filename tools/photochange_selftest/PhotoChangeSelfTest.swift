// Copyright (C) 2026 Jason (personal fork of Synctrain / Sushitrain by Tommy van der Vorst)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
import Foundation

// Self-test of Sushitrain/PhotoChangePlan.swift (the decision behind the fast path of the automatic photo back-up). The CI builds and
// runs it with a plain swiftc (no Xcode project, no simulator) BEFORE the long build:
//   xcrun swiftc -swift-version 6 -parse-as-library -o selftest Sushitrain/PhotoChangePlan.swift tools/photochange_selftest/PhotoChangeSelfTest.swift && ./selftest
// Every failed check prints a line that starts with "ERROR: " (the build log tool picks those up) and the exit code is 1.
@main
struct PhotoChangeSelfTest {
	static func main() {
		var checks = 0
		var failures = 0

		func fail(_ message: String) {
			failures += 1
			print("ERROR: photo change self-test: \(message)")
		}
		func expectTrue(_ condition: Bool, _ what: String) {
			checks += 1
			if !condition {
				fail(what)
			}
		}
		func expectEqual(_ actual: String, _ expected: String, _ what: String) {
			checks += 1
			if actual != expected {
				fail("\(what): expected [\(expected)] but got [\(actual)]")
			}
		}
		func expectInt(_ actual: Int, _ expected: Int, _ what: String) {
			checks += 1
			if actual != expected {
				fail("\(what): expected \(expected) but got \(actual)")
			}
		}
		func expectPlan(_ actual: PhotoChangePlan, _ expected: PhotoChangePlan, _ what: String) {
			checks += 1
			if actual != expected {
				fail("\(what): expected \(expected) but got \(actual)")
			}
		}

		// ---- small helpers -------------------------------------------------------------------------------------------------

		func input(
			inserted: [String] = [], updated: [String] = [], deleted: [String] = [], albums: [String] = [], records: Int = 0
		) -> PhotoChangeInput {
			var result = PhotoChangeInput()
			result.inserted = Set(inserted)
			result.updated = Set(updated)
			result.deleted = Set(deleted)
			result.changedAlbums = Set(albums)
			result.changeRecords = records
			return result
		}
		func ids(_ prefix: String, _ count: Int) -> [String] {
			var result: [String] = []
			for number in 0..<count {
				result.append("\(prefix)\(number)")
			}
			return result
		}
		func plan(_ value: PhotoChangeInput, limit: Int = 200, albumsMatter: Bool = true) -> PhotoChangePlan {
			return PhotoChangePlanner.plan(value, maxAssets: limit, albumChangesMatter: albumsMatter)
		}
		func isFull(_ value: PhotoChangePlan) -> Bool {
			if case .full = value {
				return true
			}
			return false
		}
		func reason(_ value: PhotoChangePlan) -> String {
			if case .full(let why) = value {
				return why
			}
			return ""
		}
		func onlyCount(_ value: PhotoChangePlan) -> Int {
			if case .only(let found) = value {
				return found.count
			}
			return -1
		}

		// ---- 1. Nothing happened ----------------------------------------------------------------------------------------------
		expectPlan(plan(input()), .nothing, "an empty change list")
		expectTrue(!input().hasAnyChange, "an empty change list is no change")
		expectTrue(input(records: 1).hasAnyChange, "a change record counts as a change")
		expectTrue(input(inserted: ["A"]).hasAnyChange, "an added photo counts as a change")
		expectTrue(input(updated: ["A"]).hasAnyChange, "a changed photo counts as a change")
		expectTrue(input(deleted: ["A"]).hasAnyChange, "a deleted photo counts as a change")
		expectTrue(input(albums: ["X"]).hasAnyChange, "a changed album counts as a change")
		expectPlan(plan(input(records: 3)), .nothing, "change records with nothing that matters")

		// ---- 2. Photos only -----------------------------------------------------------------------------------------------------
		expectPlan(plan(input(inserted: ["A"])), .only(["A"]), "one new photo")
		expectPlan(plan(input(inserted: ["A"], updated: ["A"])), .only(["A"]), "a new photo that was also updated")
		expectPlan(plan(input(updated: ["OLD"])), .only(["OLD"]), "an update of an old photo")
		expectPlan(plan(input(inserted: ["A", "B"], updated: ["C"])), .only(["A", "B", "C"]), "two new photos and one update")
		expectPlan(plan(input(inserted: ["A", "A", "B"])), .only(["A", "B"]), "the same identifier twice is one photo")
		expectInt(onlyCount(plan(input(updated: ids("U", 200)))), 200, "exactly 200 updates stay in the fast path")
		expectInt(onlyCount(plan(input(inserted: ids("I", 150), updated: ids("U", 50)))), 200, "150 new + 50 updated = 200")

		// ---- 3. Too many photos -------------------------------------------------------------------------------------------------
		let tooMany = plan(input(updated: ids("U", 201)))
		expectTrue(isFull(tooMany), "201 updates need the full pass")
		expectTrue(reason(tooMany).contains("201 photos changed"), "the reason names the count, got [\(reason(tooMany))]")
		expectTrue(reason(tooMany).contains("limit of 200"), "the reason names the limit, got [\(reason(tooMany))]")
		expectTrue(isFull(plan(input(inserted: ids("I", 150), updated: ids("U", 51)))), "150 new + 51 updated = 201 need the full pass")
		expectInt(onlyCount(plan(input(inserted: ids("P", 150), updated: ids("P", 150)))), 150, "the same 150 photos in both lists are 150")
		expectTrue(isFull(plan(input(inserted: ids("P", 150), updated: ids("P", 250)))), "the union (250) counts, not the sum")
		expectTrue(isFull(plan(input(inserted: ["A"]), limit: 0)), "limit 0 switches the fast path off")
		expectTrue(reason(plan(input(inserted: ["A"]), limit: 0)).contains("limit of 0"), "limit 0 says so")
		expectPlan(plan(input(), limit: 0), .nothing, "limit 0 and nothing changed")
		expectTrue(isFull(plan(input(inserted: ["A"]), limit: -5)), "a negative limit switches the fast path off")
		expectPlan(plan(input(inserted: ["A", "B"]), limit: 2), .only(["A", "B"]), "exactly at a small limit")
		expectTrue(isFull(plan(input(inserted: ["A", "B", "C"]), limit: 2)), "one over a small limit")

		// ---- 4. Albums ----------------------------------------------------------------------------------------------------------
		let albumAndPhoto = plan(input(inserted: ["A"], albums: ["X"]))
		expectTrue(isFull(albumAndPhoto), "a new photo and a changed album need the full pass")
		expectEqual(reason(albumAndPhoto), "an album changed", "the reason for one album")
		expectTrue(isFull(plan(input(albums: ["X"]))), "an album that changed alone (renamed, or a photo put in) needs the full pass")
		expectTrue(plan(input(albums: ["X"])) != .nothing, "a changed album is never 'nothing'")
		expectEqual(reason(plan(input(albums: ["X", "Y", "Z"]))), "3 albums changed", "the reason for three albums")
		expectTrue(isFull(plan(input(updated: ["A"], deleted: ["B"], albums: ["X"]))), "album change wins over an update and a deletion")
		expectPlan(plan(input(inserted: ["A"], albums: ["X"]), albumsMatter: false), .only(["A"]), "another mode: albums do not matter")
		expectPlan(plan(input(albums: ["X"]), albumsMatter: false), .nothing, "another mode: only albums changed")
		expectTrue(isFull(plan(input(inserted: ids("I", 300), albums: ["X"]), albumsMatter: false)), "another mode: the limit still applies")

		// ---- 5. Deletions -------------------------------------------------------------------------------------------------------
		expectPlan(plan(input(deleted: ["A"])), .nothing, "a deletion alone needs no work")
		expectPlan(plan(input(deleted: ids("D", 500))), .nothing, "500 deletions alone need no work")
		expectPlan(plan(input(inserted: ["NEW"], deleted: ["OLD"])), .only(["NEW"]), "a deletion and an insertion")
		expectPlan(plan(input(inserted: ["A"], deleted: ["A"])), .nothing, "added and deleted again")
		expectPlan(plan(input(updated: ["A"], deleted: ["A"])), .nothing, "updated and then deleted")
		expectPlan(plan(input(inserted: ["A", "B"], deleted: ["A"])), .only(["B"]), "two added, one deleted again")
		expectInt(onlyCount(plan(input(updated: ids("U", 200), deleted: ids("U", 100)))), 100, "deleted photos do not count towards the limit")

		// ---- 6. Junk ------------------------------------------------------------------------------------------------------------
		expectPlan(plan(input(inserted: [""])), .nothing, "an empty identifier is ignored")
		expectPlan(plan(input(inserted: ["", "A"])), .only(["A"]), "an empty identifier next to a real one")

		// ---- 7. The change list cannot be read -----------------------------------------------------------------------------------
		var expired = PhotoChangeInput()
		expired.unreadableReason = "the saved library state has expired"
		let expiredPlan = plan(expired)
		expectTrue(isFull(expiredPlan), "an unreadable change list needs the full pass")
		expectTrue(reason(expiredPlan).contains("cannot be read"), "the reason says it cannot be read, got [\(reason(expiredPlan))]")
		expectTrue(reason(expiredPlan).contains("expired"), "the reason repeats why, got [\(reason(expiredPlan))]")
		var expiredWithNews = input(inserted: ["A"], albums: ["X"])
		expiredWithNews.unreadableReason = "reading the changes failed"
		expectTrue(reason(plan(expiredWithNews)).contains("cannot be read"), "an unreadable list wins over everything else")
		expectTrue(isFull(plan(expired, albumsMatter: false)), "an unreadable list needs the full pass in every mode")
		expectTrue(isFull(plan(expired, limit: 100000)), "an unreadable list needs the full pass with any limit")

		// ---- 8. Same question, same answer ---------------------------------------------------------------------------------------
		let sample = input(inserted: ["A", "B"], updated: ["C"], deleted: ["D"])
		let sampleBefore = sample
		expectPlan(plan(sample), plan(sample), "the same input gives the same plan")
		expectTrue(sample == sampleBefore, "the planner does not change its input")
		expectTrue(PhotoChangePlanner.assetsToLookAt(sample) == ["A", "B", "C"], "assetsToLookAt")

		// ---- 9. The two settings -------------------------------------------------------------------------------------------------
		expectInt(PhotoChangePlanner.defaultQuietSeconds, 8, "the default wait is 8 seconds")
		expectInt(PhotoChangePlanner.defaultFastPathMaxAssets, 200, "the default limit is 200 photos")
		expectInt(PhotoChangePlanner.clampQuietSeconds(8), 8, "wait 8")
		expectInt(PhotoChangePlanner.clampQuietSeconds(3), 3, "wait 3")
		expectInt(PhotoChangePlanner.clampQuietSeconds(2), 3, "wait 2 is raised to 3")
		expectInt(PhotoChangePlanner.clampQuietSeconds(0), 3, "wait 0 is raised to 3")
		expectInt(PhotoChangePlanner.clampQuietSeconds(-20), 3, "a negative wait is raised to 3")
		expectInt(PhotoChangePlanner.clampQuietSeconds(120), 120, "wait 120")
		expectInt(PhotoChangePlanner.clampQuietSeconds(121), 120, "wait 121 is cut to 120")
		expectInt(PhotoChangePlanner.clampQuietSeconds(Int.max), 120, "the biggest number is cut to 120")
		expectInt(PhotoChangePlanner.clampQuietSeconds(Int.min), 3, "the smallest number is raised to 3")
		expectInt(PhotoChangePlanner.clampFastPathMaxAssets(200), 200, "limit 200")
		expectInt(PhotoChangePlanner.clampFastPathMaxAssets(0), 0, "limit 0 (switched off)")
		expectInt(PhotoChangePlanner.clampFastPathMaxAssets(-1), 0, "a negative limit becomes 0")
		expectInt(PhotoChangePlanner.clampFastPathMaxAssets(5000), 5000, "limit 5000")
		expectInt(PhotoChangePlanner.clampFastPathMaxAssets(5001), 5000, "limit 5001 is cut to 5000")
		expectInt(PhotoChangePlanner.clampFastPathMaxAssets(Int.max), 5000, "the biggest limit is cut to 5000")

		// ---- 10. When may the back-up remember the library state? -------------------------------------------------------------------
		let someFast = PhotoChangePlan.only(["A"])
		let someFull = PhotoChangePlan.full(reason: "an album changed")
		expectTrue(PhotoChangePlanner.mayRememberLibraryState(plan: someFast, hadChanges: true, outcome: .completed), "fast pass completed")
		expectTrue(PhotoChangePlanner.mayRememberLibraryState(plan: someFull, hadChanges: true, outcome: .completed), "full pass completed")
		expectTrue(PhotoChangePlanner.mayRememberLibraryState(plan: someFull, hadChanges: false, outcome: .completed), "full pass completed, first run")
		expectTrue(PhotoChangePlanner.mayRememberLibraryState(plan: .nothing, hadChanges: true, outcome: .completed), "nothing to do, but changes were seen")
		expectTrue(!PhotoChangePlanner.mayRememberLibraryState(plan: .nothing, hadChanges: false, outcome: .completed), "nothing happened at all")
		expectTrue(!PhotoChangePlanner.mayRememberLibraryState(plan: someFast, hadChanges: true, outcome: .failed), "fast pass failed")
		expectTrue(!PhotoChangePlanner.mayRememberLibraryState(plan: someFull, hadChanges: true, outcome: .failed), "full pass failed")
		expectTrue(!PhotoChangePlanner.mayRememberLibraryState(plan: someFast, hadChanges: true, outcome: .cancelled), "fast pass cancelled")
		expectTrue(!PhotoChangePlanner.mayRememberLibraryState(plan: someFull, hadChanges: true, outcome: .cancelled), "full pass cancelled")
		expectTrue(!PhotoChangePlanner.mayRememberLibraryState(plan: .nothing, hadChanges: true, outcome: .failed), "nothing to do but failed")
		expectTrue(!PhotoChangePlanner.mayRememberLibraryState(plan: .nothing, hadChanges: true, outcome: .cancelled), "nothing to do but cancelled")

		// ---- 11. The log line -----------------------------------------------------------------------------------------------------
		expectEqual(PhotoChangePlanner.describe(.nothing), "nothing to do", "describe nothing")
		expectEqual(PhotoChangePlanner.describe(.only(["A"])), "fast (1 photo)", "describe one photo")
		expectEqual(PhotoChangePlanner.describe(.only(["A", "B", "C"])), "fast (3 photos)", "describe three photos")
		expectEqual(PhotoChangePlanner.describe(someFull), "full (an album changed)", "describe a full pass")
		var report = PhotoRunReport(trigger: "automatic")
		let oneNewPhoto = input(inserted: ["A"])
		report.record(input: oneNewPhoto, plan: plan(oneNewPhoto))
		expectEqual(
			report.logLine(milliseconds: 1850, result: "done"),
			"Photo back-up run (automatic): path=fast (1 photo), I=1 U=0 C=0 D=0, 1850 ms, result=done", "the log line of a fast run")
		var fullReport = PhotoRunReport(trigger: "automatic")
		let renamedAlbum = input(updated: ["A", "B"], deleted: ["Z"], albums: ["X"])
		fullReport.record(input: renamedAlbum, plan: plan(renamedAlbum))
		expectEqual(
			fullReport.logLine(milliseconds: 421000, result: "cancelled"),
			"Photo back-up run (automatic): path=full (an album changed), I=0 U=2 C=1 D=1, 421000 ms, result=cancelled",
			"the log line of a full run")
		let handReport = PhotoRunReport(trigger: "by hand")
		expectTrue(
			handReport.logLine(milliseconds: 5, result: "error: x").hasPrefix("Photo back-up run (by hand): path=full (not decided), I=0 U=0 C=0 D=0, 5 ms"),
			"a run that never decided anything says so")

		// ---- 12. A story: what the library reports, what each run does, what is remembered ---------------------------------------
		struct PretendLibrary {
			// one entry per change record (transaction) the library reported
			var records: [PhotoChangeInput] = []
			// how many records were already looked at when the last run ended well (the saved library state)
			var saved = 0
		}
		var library = PretendLibrary()
		func happen(_ record: PhotoChangeInput) {
			library.records.append(record)
		}
		func readChanges() -> PhotoChangeInput {
			var combined = PhotoChangeInput()
			for record in library.records[library.saved...] {
				combined.changeRecords += 1
				combined.inserted.formUnion(record.inserted)
				combined.updated.formUnion(record.updated)
				combined.deleted.formUnion(record.deleted)
				combined.changedAlbums.formUnion(record.changedAlbums)
			}
			return combined
		}
		func run(_ outcome: PhotoRunOutcome) -> PhotoChangePlan {
			let seen = readChanges()
			let decided = plan(seen)
			if PhotoChangePlanner.mayRememberLibraryState(plan: decided, hadChanges: seen.hasAnyChange, outcome: outcome) {
				library.saved = library.records.count
			}
			return decided
		}

		// a new photo is taken, the run saves it, the next run finds nothing
		happen(input(inserted: ["P1"]))
		expectPlan(run(.completed), .only(["P1"]), "story: a new photo")
		expectInt(library.saved, 1, "story: the state is remembered")
		expectPlan(run(.completed), .nothing, "story: nothing new afterwards")
		expectInt(library.saved, 1, "story: nothing happened, so nothing to remember")

		// a run fails: the same photo is found again, together with the next one
		happen(input(inserted: ["P2"]))
		expectPlan(run(.failed), .only(["P2"]), "story: a photo, and the run fails")
		expectInt(library.saved, 1, "story: a failed run remembers nothing")
		happen(input(inserted: ["P3"]))
		expectPlan(run(.completed), .only(["P2", "P3"]), "story: the failed photo is tried again with the next one")
		expectInt(library.saved, 3, "story: now the state is remembered")

		// an album changes: a full pass; a cancelled pass is repeated
		happen(input(albums: ["ALBUM-1"]))
		expectTrue(isFull(run(.cancelled)), "story: an album changed, the pass is cancelled")
		expectInt(library.saved, 3, "story: a cancelled pass remembers nothing")
		expectTrue(isFull(run(.completed)), "story: the full pass is done again")
		expectInt(library.saved, 4, "story: now it is remembered")
		expectPlan(run(.completed), .nothing, "story: nothing new after the full pass")

		// a big change (for example iCloud touching 250 photos): a full pass; then a single new photo is fast again
		happen(input(updated: ids("ICLOUD", 250)))
		let bigPlan = run(.completed)
		expectTrue(isFull(bigPlan) && reason(bigPlan).contains("250 photos changed"), "story: 250 updates need the full pass")
		expectInt(library.saved, 5, "story: the big change is remembered")
		happen(input(inserted: ["P4"]))
		expectPlan(run(.completed), .only(["P4"]), "story: a single new photo is fast again")
		expectInt(library.saved, 6, "story: and remembered")

		// only deletions: nothing to do, but the deletions are remembered and not read again
		happen(input(deleted: ["P1"]))
		expectPlan(run(.completed), .nothing, "story: a deletion alone")
		expectInt(library.saved, 7, "story: the deletion is remembered")
		expectTrue(!readChanges().hasAnyChange, "story: it is not read again")

		// change records that hold nothing that matters (changes the caller filtered out): nothing to do, remembered
		happen(input())
		expectPlan(run(.completed), .nothing, "story: a change record with nothing that matters")
		expectInt(library.saved, 8, "story: it is remembered")

		// a photo is put in an album, with no change to the photo itself: that is an album change, so everything is looked at
		happen(input(albums: ["ALBUM-2"]))
		expectTrue(reason(run(.completed)) == "an album changed", "story: a photo put in an album")
		expectInt(library.saved, 9, "story: remembered after the full pass")

		// a deleted photo that was also added a moment before: nothing is looked for
		happen(input(inserted: ["P5"]))
		happen(input(deleted: ["P5"]))
		expectPlan(run(.completed), .nothing, "story: added and deleted before the run")
		expectInt(library.saved, 11, "story: both records are remembered")

		print("photo change self-test: \(checks) checks, \(failures) failed")
		exit(failures == 0 ? 0 : 1)
	}
}

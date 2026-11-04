// Copyright (C) 2026 Jason (personal fork of Synctrain / Sushitrain by Tommy van der Vorst)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
import Foundation

// Self-test of Sushitrain/AlbumFolderNaming.swift. The CI builds and runs it with a plain swiftc (no Xcode project, no simulator)
// BEFORE the long build:
//   xcrun swiftc -swift-version 6 -parse-as-library -o selftest Sushitrain/AlbumFolderNaming.swift tools/albumnaming_selftest/AlbumNamingSelfTest.swift && ./selftest
// Every failed check prints a line that starts with "ERROR: " (the build log tool picks those up) and the exit code is 1.
@main
struct AlbumNamingSelfTest {
	static func main() {
		var checks = 0
		var failures = 0

		func fail(_ message: String) {
			failures += 1
			print("ERROR: album naming self-test: \(message)")
		}
		func expectEqual(_ actual: String, _ expected: String, _ what: String) {
			checks += 1
			if actual != expected {
				fail("\(what): expected [\(expected)] but got [\(actual)]")
			}
		}
		func expectTrue(_ condition: Bool, _ what: String) {
			checks += 1
			if !condition {
				fail(what)
			}
		}
		func scalars(_ text: String) -> [UInt32] {
			return text.unicodeScalars.map { $0.value }
		}
		func folder(_ title: String?) -> String {
			return AlbumFolderNaming.sanitizeFolderName(title)
		}

		// 1. Every character Windows cannot store becomes "_"
		expectEqual(folder("a\\b/c:d*e?f\"g<h>i|j"), "a_b_c_d_e_f_g_h_i_j", "the nine forbidden characters")
		expectEqual(folder("Mum's \"best\" photos?"), "Mum's _best_ photos_", "quotes and question mark")

		// 2. Control characters (also tab, line feed, NUL, C1 and the Unicode line separator)
		expectEqual(folder("a\u{0}b\u{7}c\nd\te\u{85}f\u{2028}g"), "a_b_c_d_e_f_g", "control characters")

		// 3. Spaces and dots at the edges, empty names
		expectEqual(folder("  Trip  "), "Trip", "spaces around")
		expectEqual(folder("Holiday. . ."), "Holiday", "trailing dots and spaces")
		expectEqual(folder("..."), "Untitled album", "only dots")
		expectEqual(folder("."), "Untitled album", "one dot")
		expectEqual(folder(".."), "Untitled album", "two dots")
		expectEqual(folder(""), "Untitled album", "empty name")
		expectEqual(folder("   "), "Untitled album", "only spaces")
		expectEqual(folder(nil), "Untitled album", "no title at all")
		expectEqual(folder(".hidden"), ".hidden", "a leading dot is allowed")
		expectEqual(folder("Dad's 50th. Party"), "Dad's 50th. Party", "a dot inside stays")

		// 4. Unicode: NFC (a letter + combining accent becomes the single accented letter)
		let nfc = folder("Cafe\u{301}")
		expectTrue(scalars(nfc) == [0x43, 0x61, 0x66, 0xE9], "NFC normalisation, got \(scalars(nfc))")
		expectEqual(folder("日本語のアルバム"), "日本語のアルバム", "Japanese stays")
		expectEqual(folder("Ünïcödé ñame"), "Ünïcödé ñame", "accents stay")

		// 5. Emoji stay as they are (also a family made with zero-width joiners)
		let emoji = "Summer \u{2600}\u{FE0F} 2024 \u{1F3D6}\u{FE0F}"
		expectTrue(scalars(folder(emoji)) == scalars(emoji), "emoji stay")
		let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
		expectTrue(scalars(folder(family)) == scalars(family), "a ZWJ family emoji is not cut or changed")

		// 6. Long names: 100 characters at most, and never more than 240 bytes
		expectTrue(folder(String(repeating: "a", count: 150)).count == 100, "150 letters are cut to 100")
		let longEmoji = folder(String(repeating: "\u{1F600}", count: 150))
		expectTrue(longEmoji.count == 60 && longEmoji.utf8.count == 240, "150 emoji are cut to 60 (240 bytes), got \(longEmoji.count)/\(longEmoji.utf8.count)")
		let accents = folder(String(repeating: "e\u{301}", count: 150))
		expectTrue(accents.count == 100, "150 decomposed accents are 100 characters after NFC, got \(accents.count)")
		let cutAtSpace = folder(String(repeating: "a", count: 99) + " " + String(repeating: "b", count: 20))
		expectTrue(cutAtSpace.count == 99 && !cutAtSpace.hasSuffix(" "), "a cut that ends in a space is trimmed, got \(cutAtSpace.count)")

		// 7. Windows device names, any case, with or without an extension
		expectEqual(folder("CON"), "CON_", "CON")
		expectEqual(folder("con"), "con_", "con")
		expectEqual(folder("Prn"), "Prn_", "Prn")
		expectEqual(folder("AUX"), "AUX_", "AUX")
		expectEqual(folder("nul"), "nul_", "nul")
		expectEqual(folder("COM1"), "COM1_", "COM1")
		expectEqual(folder("com9"), "com9_", "com9")
		expectEqual(folder("LPT1"), "LPT1_", "LPT1")
		expectEqual(folder("lpt9"), "lpt9_", "lpt9")
		expectEqual(folder("COM0"), "COM0_", "COM0")
		expectEqual(folder("NUL.txt"), "NUL_.txt", "device name with extension")
		expectEqual(folder("con.tar.gz"), "con_.tar.gz", "device name with two extensions")
		expectEqual(folder("AUX "), "AUX_", "device name with a trailing space")
		expectEqual(folder("CON."), "CON_", "device name with a trailing dot")
		expectEqual(folder("COM10"), "COM10", "COM10 is not a device")
		expectEqual(folder("CONSOLE"), "CONSOLE", "CONSOLE is not a device")
		expectEqual(folder("Nullable"), "Nullable", "Nullable is not a device")
		expectEqual(folder("LPT"), "LPT", "LPT without a digit is not a device")

		// 8. Same sanitised name: the album with the smallest identifier keeps the plain name, in a stable order
		let trips = [
			AlbumFolderRef(id: "C", title: "Trip"), AlbumFolderRef(id: "A", title: "Trip"), AlbumFolderRef(id: "B", title: "Trip"),
		]
		let first = AlbumFolderNaming.assignFolderNames(albums: trips)
		expectEqual(first["A"]?.folder ?? "-", "Trip", "first of three equal names")
		expectEqual(first["B"]?.folder ?? "-", "Trip (2)", "second of three equal names")
		expectEqual(first["C"]?.folder ?? "-", "Trip (3)", "third of three equal names")
		let reversed = AlbumFolderNaming.assignFolderNames(albums: Array(trips.reversed()))
		expectTrue(reversed == first, "the input order does not matter")

		// 9. A name never flips between runs: names given earlier are kept when albums come or go
		let more = trips + [AlbumFolderRef(id: "0", title: "Trip")]
		let second = AlbumFolderNaming.assignFolderNames(albums: more, existing: first)
		expectEqual(second["0"]?.folder ?? "-", "Trip (4)", "a new album with a smaller identifier gets the next free number")
		expectEqual(second["A"]?.folder ?? "-", "Trip", "A keeps its name")
		expectEqual(second["B"]?.folder ?? "-", "Trip (2)", "B keeps its name")
		expectEqual(second["C"]?.folder ?? "-", "Trip (3)", "C keeps its name")
		let withoutA = AlbumFolderNaming.assignFolderNames(albums: [trips[0], trips[2]], existing: first)
		expectEqual(withoutA["B"]?.folder ?? "-", "Trip (2)", "B keeps (2) after A was deleted")
		expectEqual(withoutA["C"]?.folder ?? "-", "Trip (3)", "C keeps (3) after A was deleted")

		// 10. Names that differ only in case are the same folder on Windows and macOS
		let cased = AlbumFolderNaming.assignFolderNames(albums: [
			AlbumFolderRef(id: "a", title: "Holiday"), AlbumFolderRef(id: "b", title: "holiday"),
		])
		expectEqual(cased["a"]?.folder ?? "-", "Holiday", "case: first")
		expectEqual(cased["b"]?.folder ?? "-", "holiday (2)", "case: second")

		// 11. "No album" is reserved for the photos that are in no album
		let reserved = AlbumFolderNaming.assignFolderNames(albums: [AlbumFolderRef(id: "x", title: "No album")])
		expectEqual(reserved["x"]?.folder ?? "-", "No album (2)", "an album called No album")

		// 12. Different titles that become the same name
		let same = AlbumFolderNaming.assignFolderNames(albums: [
			AlbumFolderRef(id: "1", title: "a/b"), AlbumFolderRef(id: "2", title: "a:b"),
		])
		expectEqual(same["1"]?.folder ?? "-", "a_b", "a/b")
		expectEqual(same["2"]?.folder ?? "-", "a_b (2)", "a:b")

		// 13. Renamed album: a new folder name; the old name is free again
		let renamed = AlbumFolderNaming.assignFolderNames(
			albums: [AlbumFolderRef(id: "1", title: "New"), AlbumFolderRef(id: "2", title: "Old")],
			existing: ["1": AlbumFolderAssignment(title: "Old", folder: "Old")])
		expectEqual(renamed["1"]?.folder ?? "-", "New", "renamed album")
		expectEqual(renamed["2"]?.folder ?? "-", "Old", "the old name is free again")

		// 14. A duplicate of a 100-character name still fits in 100 characters
		let longTitle = String(repeating: "x", count: 100)
		let longPair = AlbumFolderNaming.assignFolderNames(albums: [
			AlbumFolderRef(id: "a", title: longTitle), AlbumFolderRef(id: "b", title: longTitle),
		])
		expectTrue((longPair["a"]?.folder.count ?? 0) == 100, "long name: first keeps 100")
		expectTrue((longPair["b"]?.folder.count ?? 0) == 100 && (longPair["b"]?.folder.hasSuffix(" (2)") ?? false), "long name: second is shortened and numbered")

		// 15. Albums without a title
		let untitled = AlbumFolderNaming.assignFolderNames(albums: [AlbumFolderRef(id: "a", title: ""), AlbumFolderRef(id: "b", title: "")])
		expectEqual(untitled["a"]?.folder ?? "-", "Untitled album", "untitled 1")
		expectEqual(untitled["b"]?.folder ?? "-", "Untitled album (2)", "untitled 2")

		// 16. Every result is safe, and cleaning twice changes nothing
		let nasty: [String] = [
			"", " ", ".", "..", "CON", "con.txt", "a/b\\c", "x:y*z?\"<>|", "trail . ", "  lead", "tab\there", "COM1.", "LPT9 .x",
			"日本語のアルバム", "Ünïcödé ñame", String(repeating: "a", count: 300), String(repeating: "\u{1F600}", count: 200),
			String(repeating: "e\u{301}", count: 150), "A  B", "end with dot.", "what?!", "100% sure", "#1 album", "name\u{0}\u{1}",
		]
		let forbidden: Set<Character> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
		for sample in nasty {
			let cleaned = folder(sample)
			let label = "[\(sample.prefix(20))]"
			expectTrue(!cleaned.isEmpty, "\(label) is not empty")
			expectTrue(!cleaned.contains(where: { forbidden.contains($0) }), "\(label) has no forbidden character")
			expectTrue(!cleaned.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }), "\(label) has no control character")
			expectTrue(!cleaned.hasSuffix(" ") && !cleaned.hasSuffix(".") && !cleaned.hasPrefix(" "), "\(label) has no space or dot at an edge")
			expectTrue(cleaned.count <= 100 && cleaned.utf8.count <= 240, "\(label) is short enough")
			let baseParts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
			let base: String = baseParts.isEmpty ? "" : String(baseParts[0])
			expectTrue(!AlbumFolderNaming.isDeviceName(base), "\(label) is not a device name")
			expectEqual(folder(cleaned), cleaned, "\(label) cleaning twice")
		}

		// 17. File names
		let split1 = AlbumFolderNaming.splitFileName("IMG_0001.HEIC")
		expectTrue(split1.stem == "IMG_0001" && split1.ext == "HEIC", "split IMG_0001.HEIC")
		let split2 = AlbumFolderNaming.splitFileName("archive.tar.gz")
		expectTrue(split2.stem == "archive.tar" && split2.ext == "gz", "split archive.tar.gz")
		let split3 = AlbumFolderNaming.splitFileName(".hidden")
		expectTrue(split3.stem == ".hidden" && split3.ext == "", "split .hidden")
		let split4 = AlbumFolderNaming.splitFileName("noext")
		expectTrue(split4.stem == "noext" && split4.ext == "", "split noext")
		let split5 = AlbumFolderNaming.splitFileName("trail.")
		expectTrue(split5.stem == "trail." && split5.ext == "", "split trail.")
		let split6 = AlbumFolderNaming.splitFileName("")
		expectTrue(split6.stem == "" && split6.ext == "", "split empty")
		expectEqual(AlbumFolderNaming.shortID("9F2D7C2A-6A1B-4B7E/L0/001", length: 6), "9F2D7C", "short id")
		expectEqual(AlbumFolderNaming.shortID("///---", length: 6), "id", "short id of an identifier without letters")
		expectEqual(AlbumFolderNaming.sanitizeExtension(" HE:IC. "), "HE_IC", "extension cleaning")
		expectEqual(AlbumFolderNaming.composeFileName(stem: "IMG_1", ext: "HEIC"), "IMG_1.HEIC", "compose")
		expectEqual(AlbumFolderNaming.composeFileName(stem: "IMG_1", ext: ""), "IMG_1", "compose without extension")

		// 18. Same file name in one folder: only the second photo gets "_" + 6 characters of its identifier
		let names = AlbumExportLedger(destination: "folder1|Photos", fileURL: nil)
		let idA = "9F2D7C2A-6A1B-4B7E-9C0B-5D3E5F6A7B8C/L0/001"
		let idB = "Z9Y8X7W6-1111-2222-3333-444455556666/L0/001"
		let nameA = names.fileName(forAsset: idA, folder: "Trip", originalName: "IMG_0001.HEIC")
		expectTrue(nameA.stem == "IMG_0001" && nameA.ext == "HEIC", "first photo keeps its name")
		let nameB = names.fileName(forAsset: idB, folder: "Trip", originalName: "IMG_0001.HEIC")
		expectTrue(nameB.stem == "IMG_0001_Z9Y8X7" && nameB.ext == "HEIC", "second photo with the same name gets a suffix, got \(nameB.stem)")
		let nameA2 = names.fileName(forAsset: idA, folder: "Trip", originalName: "IMG_0001.HEIC")
		let nameB2 = names.fileName(forAsset: idB, folder: "Trip", originalName: "IMG_0001.HEIC")
		expectTrue(nameA2.stem == nameA.stem && nameB2.stem == nameB.stem, "the answer for one asset never changes")
		let nameC = names.fileName(forAsset: "Q1W2E3R4/L0/001", folder: "Trip", originalName: "img_0001.heic")
		expectTrue(nameC.stem == "img_0001_Q1W2E3" && nameC.ext == "heic", "upper/lower case does not make a name different, got \(nameC.stem)")
		let nameD = names.fileName(forAsset: idB, folder: "Hike", originalName: "IMG_0001.HEIC")
		expectTrue(nameD.stem == "IMG_0001", "the same name in another folder is no collision")
		let nameV = names.fileName(forAsset: "VID1", folder: "Trip", originalName: "IMG_0001.MOV")
		expectTrue(nameV.stem == "IMG_0001_VID1", "a video with the stem of a Live Photo is a collision, got \(nameV.stem)")
		let nameBad = names.fileName(forAsset: "BAD1", folder: "Trip", originalName: "a:b?.jpg")
		expectTrue(nameBad.stem == "a_b_" && nameBad.ext == "jpg", "bad characters in a file name, got \(nameBad.stem)")
		let nameNul = names.fileName(forAsset: "NUL1", folder: "Trip", originalName: "NUL.jpg")
		expectTrue(nameNul.stem == "NUL_", "a device name as file name, got \(nameNul.stem)")

		// 19. Hash and ledger file name
		expectEqual(AlbumFolderNaming.stableHash(""), "cbf29ce484222325", "FNV-1a of the empty text")
		expectEqual(AlbumFolderNaming.stableHash("a"), "af63dc4c8601ec8c", "FNV-1a of a")
		expectEqual(AlbumFolderNaming.stableHash("foobar"), "85944171f73967e8", "FNV-1a of foobar")
		let ledgerName = AlbumExportLedger.fileName(forDestination: "folder1|Photos")
		expectEqual(ledgerName, "PhotoAlbumLedger-f4abd383fc4fc68d.json", "ledger file name")
		expectEqual(AlbumExportLedger.key(assetID: "A", albumID: "B", kind: "photo"), "A|B|photo", "key format")

		// 20. The ledger on the disk: keys are added after the file is written, saved atomically, found again, and only valid for one destination
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("albumnaming-selftest-" + UUID().uuidString)
		let url = dir.appendingPathComponent(ledgerName)
		let ledger = AlbumExportLedger(destination: "folder1|Photos", fileURL: url)
		let folders = ledger.assignAlbums([AlbumFolderRef(id: "AL1", title: "Trip"), AlbumFolderRef(id: "AL2", title: "Trip")])
		expectTrue(folders["AL1"] == "Trip" && folders["AL2"] == "Trip (2)", "ledger assigns album folders")
		let key1 = AlbumExportLedger.key(assetID: "A1", albumID: "AL1", kind: "photo")
		let key2 = AlbumExportLedger.key(assetID: "A2", albumID: "AL1", kind: "live")
		expectTrue(!ledger.isDone(key1), "a new key is not done")
		ledger.expect(pathInFolder: "Photos/Trip/IMG_1.HEIC", key: key1, relativePath: "Trip/IMG_1.HEIC")
		expectTrue(!ledger.isDone(key1) && ledger.openCount == 1, "an announced key is not done before the file is written")
		expectTrue(ledger.openAssetIDs == ["A1"], "the open photo is named, got \(ledger.openAssetIDs)")
		ledger.completed(pathInFolder: "Photos/Trip/IMG_1.HEIC")
		expectTrue(ledger.isDone(key1) && ledger.openCount == 0 && ledger.completedCount == 1, "a finished file makes its key done")
		expectTrue(ledger.openAssetIDs.isEmpty, "nothing is open after the file is finished")
		ledger.completed(pathInFolder: "Photos/Trip/never-announced.HEIC")
		expectTrue(ledger.completedCount == 1, "a file that was never announced changes nothing")
		ledger.markAdopted(key: key2, relativePath: "Trip/IMG_2.MOV")
		expectTrue(ledger.isDone(key2) && ledger.adoptedCount == 1, "an adopted file is done")
		expectTrue(ledger.saveNow(), "the ledger is saved, error: \(ledger.lastSaveError ?? "-")")
		expectTrue(FileManager.default.fileExists(atPath: url.path), "the ledger file exists")
		let listing = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
		expectTrue(listing.filter({ $0.hasSuffix(".json") }).count == 1 && listing.filter({ $0.lowercased().contains("tmp") }).isEmpty, "one ledger file and no temporary file is left: \(listing)")

		let again = AlbumExportLedger.load(destination: "folder1|Photos", fileURL: url)
		expectTrue(again.isDone(key1) && again.isDone(key2), "the ledger is found again after a restart")
		expectTrue(again.savedPath(for: key1) == "Trip/IMG_1.HEIC", "the saved path is remembered")
		expectTrue(again.loadNote.hasPrefix("loaded 2 saved items"), "load note: \(again.loadNote)")
		let foldersAgain = again.assignAlbums([AlbumFolderRef(id: "AL2", title: "Trip"), AlbumFolderRef(id: "AL1", title: "Trip"), AlbumFolderRef(id: "AL0", title: "Trip")])
		expectTrue(foldersAgain["AL1"] == "Trip" && foldersAgain["AL2"] == "Trip (2)" && foldersAgain["AL0"] == "Trip (3)", "album folder names survive a restart and do not flip, got \(foldersAgain)")
		let afterRestart = again.fileName(forAsset: "A1", folder: "Trip", originalName: "IMG_1.HEIC")
		expectTrue(afterRestart.stem == "IMG_1", "the owner of a name keeps it after a restart")
		let intruder = again.fileName(forAsset: "B2", folder: "Trip", originalName: "IMG_1.HEIC")
		expectTrue(intruder.stem == "IMG_1_B2", "another asset with that name gets a suffix after a restart, got \(intruder.stem)")
		let partner = again.fileName(forAsset: "A2", folder: "Trip", originalName: "IMG_2.HEIC")
		expectTrue(partner.stem == "IMG_2", "the stem of a saved Live Photo video is reused")
		again.ignoreExisting = true
		expectTrue(!again.isDone(key1), "Re-copy all photos: nothing counts as done")

		let other = AlbumExportLedger.load(destination: "folder2|Photos", fileURL: url)
		expectTrue(!other.isDone(key1) && other.loadNote.contains("another destination"), "another destination starts empty: \(other.loadNote)")

		// 21. A checkpoint writes the file without saveNow
		let dir2 = FileManager.default.temporaryDirectory.appendingPathComponent("albumnaming-selftest-" + UUID().uuidString)
		let url2 = dir2.appendingPathComponent("ledger.json")
		let live = AlbumExportLedger(destination: "d", fileURL: url2)
		live.checkpointEveryChanges = 2
		live.checkpointEverySeconds = 100_000
		live.markAdopted(key: "A|B|photo", relativePath: "F/1.HEIC")
		expectTrue(!FileManager.default.fileExists(atPath: url2.path), "no write after one change")
		live.markAdopted(key: "C|B|photo", relativePath: "F/2.HEIC")
		let reread = AlbumExportLedger.load(destination: "d", fileURL: url2)
		expectTrue(reread.isDone("A|B|photo") && reread.isDone("C|B|photo"), "the second change triggered a checkpoint")

		// 22. A damaged ledger file gives an empty ledger (and is kept aside), it does not crash
		let dir3 = FileManager.default.temporaryDirectory.appendingPathComponent("albumnaming-selftest-" + UUID().uuidString)
		let url3 = dir3.appendingPathComponent("ledger.json")
		try? FileManager.default.createDirectory(at: dir3, withIntermediateDirectories: true)
		try? Data("not json{".utf8).write(to: url3)
		let damaged = AlbumExportLedger.load(destination: "d", fileURL: url3)
		expectTrue(damaged.savedItemCount == 0 && damaged.loadNote.contains("could not be read"), "damaged file: \(damaged.loadNote)")
		expectTrue(FileManager.default.fileExists(atPath: url3.appendingPathExtension("damaged").path), "the damaged file is kept")
		let missing = AlbumExportLedger.load(destination: "d", fileURL: dir3.appendingPathComponent("nothing-here.json"))
		expectTrue(missing.savedItemCount == 0 && missing.loadNote.contains("no ledger file"), "missing file: \(missing.loadNote)")

		// 22b. A ledger file that exists but cannot be read (the phone was not unlocked since it started) is not "damaged": the
		//      back-up must not go on with an empty ledger, and the real file must never be overwritten or moved aside
		let dir4 = FileManager.default.temporaryDirectory.appendingPathComponent("albumnaming-selftest-" + UUID().uuidString)
		let url4 = dir4.appendingPathComponent("ledger.json")
		let real = AlbumExportLedger(destination: "d", fileURL: url4)
		real.markAdopted(key: "A|B|photo", relativePath: "F/1.HEIC")
		expectTrue(real.saveNow() && FileManager.default.fileExists(atPath: url4.path), "a real ledger file is written")
		try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url4.path)
		if !FileManager.default.isReadableFile(atPath: url4.path) {
			let closed = AlbumExportLedger.load(destination: "d", fileURL: url4)
			expectTrue(!closed.isUsable && closed.loadNote.contains("cannot be read right now"), "unreadable file: \(closed.loadNote)")
			closed.markAdopted(key: "X|Y|photo", relativePath: "G/2.HEIC")
			expectTrue(!closed.saveNow() && closed.lastSaveError != nil, "an unreadable ledger is never written over")
			expectTrue(!FileManager.default.fileExists(atPath: url4.appendingPathExtension("damaged").path), "an unreadable file is not moved aside")
			try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url4.path)
			let opened = AlbumExportLedger.load(destination: "d", fileURL: url4)
			expectTrue(opened.isUsable && opened.isDone("A|B|photo") && !opened.isDone("X|Y|photo"), "the real ledger is still there: \(opened.loadNote)")
		}
		else {
			print("note: this account can read files with no permission (root?), the unreadable-ledger check was skipped")
		}

		// 22c. A finished file gets its real name in one step (new name, and replacing an existing file)
		let dir5 = FileManager.default.temporaryDirectory.appendingPathComponent("albumnaming-selftest-" + UUID().uuidString)
		let movedA = dir5.appendingPathComponent("part-one")
		let movedB = dir5.appendingPathComponent("IMG_0001.MOV")
		do {
			try FileManager.default.createDirectory(at: dir5, withIntermediateDirectories: true)
			try Data("one".utf8).write(to: movedA)
			try AlbumFolderNaming.moveIntoPlace(movedA, to: movedB)
			expectTrue(!FileManager.default.fileExists(atPath: movedA.path), "the temporary file is gone after the move")
			expectTrue((try? Data(contentsOf: movedB)) == Data("one".utf8), "a new file is in place")
			try Data("two".utf8).write(to: movedA)
			try AlbumFolderNaming.moveIntoPlace(movedA, to: movedB)
			expectTrue((try? Data(contentsOf: movedB)) == Data("two".utf8), "an existing file is replaced")
		}
		catch {
			fail("moveIntoPlace threw: \(error)")
		}

		// 23. A whole story with the real planning code (the same calls the back-up makes, with a pretend photo library and a
		//     pretend disk): a first pass, a second pass that must save nothing, a second photo with the same file name, a renamed
		//     album, a crash in the middle of a file, a restart, and "Re-copy all photos".
		struct StoryAsset {
			let id: String
			let name: String
			let isVideo: Bool
			let isLive: Bool
		}
		struct StoryAlbum {
			let id: String
			let title: String
			let assets: [StoryAsset]
		}
		let storyDir = FileManager.default.temporaryDirectory.appendingPathComponent("albumnaming-selftest-" + UUID().uuidString)
		let storyURL = storyDir.appendingPathComponent("ledger.json")
		var story = AlbumExportLedger(destination: "story", fileURL: storyURL)
		var disk: [String] = []

		func savePart(_ name: String, folder: String, key: String) {
			let relative = folder + "/" + name
			story.expect(pathInFolder: "Photos/" + relative, key: key, relativePath: relative)
			disk.append(relative)
			story.completed(pathInFolder: "Photos/" + relative)
		}
		func saveAssets(_ assets: [StoryAsset], albumID: String, folder: String) -> Int {
			var saved = 0
			for asset in assets {
				guard
					let plan = story.plan(
						assetID: asset.id, albumID: albumID, folder: folder, isVideo: asset.isVideo, isLivePhoto: asset.isLive,
						saveImages: true, saveVideos: true, saveLivePhotos: true, originalName: { asset.name })
				else {
					continue
				}
				if plan.wantsPrimary {
					savePart(plan.primaryName, folder: folder, key: plan.primaryKey)
					saved += 1
				}
				if plan.wantsLive {
					savePart(plan.liveName, folder: folder, key: plan.liveKey)
					saved += 1
				}
			}
			return saved
		}
		func runPass(_ albums: [StoryAlbum], noAlbum: [StoryAsset]) -> Int {
			let names = story.assignAlbums(albums.map { AlbumFolderRef(id: $0.id, title: $0.title) })
			var saved = 0
			for album in albums.sorted(by: { $0.id < $1.id }) {
				saved += saveAssets(album.assets, albumID: album.id, folder: names[album.id] ?? "?")
			}
			saved += saveAssets(
				noAlbum, albumID: AlbumFolderNaming.noAlbumIdentifier, folder: AlbumFolderNaming.noAlbumFolderName)
			return saved
		}

		let p1 = StoryAsset(id: "P1AAAAAA/L0/001", name: "IMG_0001.HEIC", isVideo: false, isLive: true)
		let v1 = StoryAsset(id: "V1BBBBBB/L0/001", name: "IMG_0002.MOV", isVideo: true, isLive: false)
		let p2 = StoryAsset(id: "P2CCCCCC/L0/001", name: "IMG_0003.JPG", isVideo: false, isLive: false)
		let p3 = StoryAsset(id: "P3DDDDDD/L0/001", name: "IMG_0001.HEIC", isVideo: false, isLive: false)
		let p4 = StoryAsset(id: "P4EEEEEE/L0/001", name: "IMG_0009.HEIC", isVideo: false, isLive: false)
		let p5 = StoryAsset(id: "P5FFFFFF/L0/001", name: "IMG_0010.HEIC", isVideo: false, isLive: false)
		let p6 = StoryAsset(id: "P6GGGGGG/L0/001", name: "IMG_0010.HEIC", isVideo: false, isLive: false)

		// pass 1: p1 (a Live Photo) is in two albums, v1 is a video, p2 is in no album
		let firstSaved = runPass(
			[
				StoryAlbum(id: "ALB-H", title: "Holiday", assets: [p1, v1]),
				StoryAlbum(id: "ALB-M", title: "Mum", assets: [p1]),
			], noAlbum: [p2])
		expectTrue(firstSaved == 6, "pass 1 saves 6 files, saved \(firstSaved)")
		expectTrue(
			disk == [
				"Holiday/IMG_0001.HEIC", "Holiday/IMG_0001.MOV", "Holiday/IMG_0002.MOV", "Mum/IMG_0001.HEIC", "Mum/IMG_0001.MOV",
				"No album/IMG_0003.JPG",
			], "pass 1 names, got \(disk)")

		// pass 2: nothing changed, nothing is saved
		let secondSaved = runPass(
			[
				StoryAlbum(id: "ALB-H", title: "Holiday", assets: [p1, v1]),
				StoryAlbum(id: "ALB-M", title: "Mum", assets: [p1]),
			], noAlbum: [p2])
		expectTrue(secondSaved == 0 && disk.count == 6, "pass 2 saves nothing, saved \(secondSaved)")

		// pass 3: a different photo with the same file name arrives in Holiday
		let thirdSaved = runPass(
			[
				StoryAlbum(id: "ALB-H", title: "Holiday", assets: [p1, v1, p3]),
				StoryAlbum(id: "ALB-M", title: "Mum", assets: [p1]),
			], noAlbum: [p2])
		expectTrue(thirdSaved == 1 && disk.last == "Holiday/IMG_0001_P3DDDD.HEIC", "pass 3: a clash gets a suffix, got \(disk.last ?? "-")")

		// pass 4: the album Mum is renamed and gets a new photo: old photos stay where they are, the new one goes to the new folder
		let fourthSaved = runPass(
			[
				StoryAlbum(id: "ALB-H", title: "Holiday", assets: [p1, v1, p3]),
				StoryAlbum(id: "ALB-M", title: "Mum 2025", assets: [p1, p4]),
			], noAlbum: [p2])
		expectTrue(fourthSaved == 1 && disk.last == "Mum 2025/IMG_0009.HEIC", "pass 4: rename, got \(disk.last ?? "-")")
		expectTrue(!disk.contains("Mum 2025/IMG_0001.HEIC"), "pass 4: the old photos are not saved again under the new name")

		// crash: p5 was announced but the app was killed before the file was finished; the ledger was saved before that
		let plan5 = story.plan(
			assetID: p5.id, albumID: "ALB-H", folder: "Holiday", isVideo: false, isLivePhoto: false,
			saveImages: true, saveVideos: true, saveLivePhotos: true, originalName: { p5.name })
		expectTrue(plan5 != nil && plan5?.primaryName == "IMG_0010.HEIC", "p5 is planned")
		if let plan5 = plan5 {
			story.expect(pathInFolder: "Photos/Holiday/IMG_0010.HEIC", key: plan5.primaryKey, relativePath: "Holiday/IMG_0010.HEIC")
		}
		expectTrue(story.saveNow(), "the ledger is saved before the crash")
		story = AlbumExportLedger.load(destination: "story", fileURL: storyURL)
		let albumsAfterCrash = [
			StoryAlbum(id: "ALB-H", title: "Holiday", assets: [p1, v1, p3, p5]),
			StoryAlbum(id: "ALB-M", title: "Mum 2025", assets: [p1, p4]),
		]
		// pass 5 after the restart: only p5 is saved, under the same name
		let fifthSaved = runPass(albumsAfterCrash, noAlbum: [p2])
		expectTrue(fifthSaved == 1 && disk.last == "Holiday/IMG_0010.HEIC", "pass 5 after the restart, got \(disk.last ?? "-")")

		// pass 6: another photo with the name of p5 (the owner of the name is remembered across the restart)
		let albumsWithP6 = [
			StoryAlbum(id: "ALB-H", title: "Holiday", assets: [p1, v1, p3, p5, p6]),
			StoryAlbum(id: "ALB-M", title: "Mum 2025", assets: [p1, p4]),
		]
		let sixthSaved = runPass(albumsWithP6, noAlbum: [p2])
		expectTrue(sixthSaved == 1 && disk.last == "Holiday/IMG_0010_P6GGGG.HEIC", "pass 6, got \(disk.last ?? "-")")

		// "Re-copy all photos": everything is saved again, to the same names. Only the renamed album is different: its old photos
		// are now saved a second time into the folder with the new name (the old folder stays).
		let namesBefore = Set(disk)
		story.ignoreExisting = true
		let recopied = runPass(albumsWithP6, noAlbum: [p2])
		expectTrue(recopied == 10, "re-copy saves all 10 files again, saved \(recopied)")
		let newNames = Set(disk).subtracting(namesBefore)
		expectTrue(
			newNames == ["Mum 2025/IMG_0001.HEIC", "Mum 2025/IMG_0001.MOV"],
			"re-copy keeps the names and fills the renamed album's new folder, new names: \(newNames.sorted())")

		print("album naming self-test: \(checks) checks, \(failures) failed")
		exit(failures == 0 ? 0 : 1)
	}
}

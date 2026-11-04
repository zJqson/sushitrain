// Copyright (C) 2026 Jason (personal fork of Synctrain / Sushitrain by Tommy van der Vorst)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
import Foundation

// Names and bookkeeping for the "By album name" photo back-up layout (one folder per iPhone album).
//
// PURE SWIFT: this file imports only Foundation (no Photos, UIKit, SwiftUI or SushitrainCore) on purpose. The CI compiles it
// with a plain `swiftc` together with tools/albumnaming_selftest/AlbumNamingSelfTest.swift in a few seconds, before the long
// build starts. It also knows no Photos types: albums and assets are plain strings here, so the same rules can name the folders
// of another feature (for example the PhotoFS "photo folder") without any change.
//
// The PC that receives the files is Windows, and Syncthing never syncs a name that Windows cannot store. So every name made here
// avoids: \ / : * ? " < > | and control characters; names that end in a space or a dot; the device names CON, PRN, AUX, NUL,
// COM0-9, LPT0-9 (with or without an extension); names longer than 100 characters; and two names that differ only in upper/lower
// case (Windows and macOS see those as the same folder).

/// One album as the naming rules see it: Photos' local identifier and the album's title ("" when it has none).
struct AlbumFolderRef: Equatable, Sendable {
	let id: String
	let title: String
}

/// The folder an album was given, and the title the album had at that moment. When the title changes later, the album is given a
/// new folder name (the files already saved stay where they are).
struct AlbumFolderAssignment: Codable, Equatable, Sendable {
	var title: String
	var folder: String
}

enum AlbumFolderNaming {
	/// Folder for photos and videos that are in no user album.
	static let noAlbumFolderName = "No album"
	/// Stands in for the album identifier in the ledger keys of the photos that are in no user album.
	static let noAlbumIdentifier = "_NO_USER_ALBUM"
	static let untitledAlbumName = "Untitled album"
	static let untitledFileName = "file"
	static let maxFolderNameLength = 100
	static let maxFileStemLength = 120
	static let maxExtensionLength = 16
	/// Most UTF-8 bytes in one name (macOS and Linux allow 255, NTFS 255 UTF-16 units; this leaves room for " (2)" and the like).
	static let maxUTF8Bytes = 240

	private static let illegalScalars: Set<Unicode.Scalar> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]

	private static let deviceNames: Set<String> = {
		var names: Set<String> = ["CON", "PRN", "AUX", "NUL"]
		for digit in 0...9 {
			names.insert("COM\(digit)")
			names.insert("LPT\(digit)")
		}
		return names
	}()

	// MARK: - One name

	/// The folder name for an album title.
	static func sanitizeFolderName(_ title: String?) -> String {
		return sanitizeComponent(title ?? "", fallback: untitledAlbumName, maxLength: maxFolderNameLength)
	}

	/// The stem (the part before the extension) of a file name.
	static func sanitizeFileStem(_ stem: String) -> String {
		return sanitizeComponent(stem, fallback: untitledFileName, maxLength: maxFileStemLength)
	}

	/// The extension of a file name, without the dot ("" when there is none).
	static func sanitizeExtension(_ ext: String) -> String {
		var cleaned = replaceIllegalCharacters(ext).precomposedStringWithCanonicalMapping
		cleaned = trimEdges(cleaned)
		if cleaned.count > maxExtensionLength {
			cleaned = String(cleaned.prefix(maxExtensionLength))
		}
		return cleaned
	}

	/// The common rules: bad characters become "_", Unicode NFC, no space at the start, no space or dot at the end, device names get
	/// a "_", at most `maxLength` characters (and `maxUTF8Bytes` bytes), and `fallback` when nothing is left.
	static func sanitizeComponent(_ raw: String, fallback: String, maxLength: Int) -> String {
		var name = replaceIllegalCharacters(raw)
		name = name.precomposedStringWithCanonicalMapping
		name = trimEdges(name)
		name = protectDeviceName(name)
		name = clip(name, maxLength: maxLength)
		name = trimEdges(name)
		name = protectDeviceName(name)
		if name.isEmpty {
			return fallback
		}
		return name
	}

	/// Replaces \ / : * ? " < > | and control characters (also tab, line feed and the Unicode line/paragraph separators) with "_".
	static func replaceIllegalCharacters(_ text: String) -> String {
		let underscore: Unicode.Scalar = "_"
		var result = String.UnicodeScalarView()
		for scalar in text.unicodeScalars {
			if illegalScalars.contains(scalar) || isControl(scalar) {
				result.append(underscore)
			}
			else {
				result.append(scalar)
			}
		}
		return String(result)
	}

	private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
		let v = scalar.value
		return v < 0x20 || (v >= 0x7F && v <= 0x9F) || v == 0x2028 || v == 0x2029
	}

	/// Removes spaces at the start and spaces and dots at the end (Windows cannot store those).
	static func trimEdges(_ text: String) -> String {
		var characters = Array(text)
		while let first = characters.first, first == " " {
			characters.removeFirst()
		}
		while let last = characters.last, last == " " || last == "." {
			characters.removeLast()
		}
		return String(characters)
	}

	static func isDeviceName(_ baseName: String) -> Bool {
		return deviceNames.contains(baseName.uppercased())
	}

	/// "CON" becomes "CON_" and "nul.txt" becomes "nul_.txt": Windows treats the part before the first dot as the device name.
	static func protectDeviceName(_ name: String) -> String {
		var base = name
		var rest = ""
		if let dot = name.firstIndex(of: ".") {
			base = String(name[name.startIndex..<dot])
			rest = String(name[dot...])
		}
		while base.last == " " {
			base.removeLast()
		}
		if isDeviceName(base) {
			return base + "_" + rest
		}
		return name
	}

	/// At most `maxLength` characters (whole characters: an emoji or a letter with its accent is never cut in half) and at most
	/// `maxUTF8Bytes` bytes.
	static func clip(_ text: String, maxLength: Int) -> String {
		var characters = Array(text)
		if characters.count > maxLength {
			characters = Array(characters.prefix(maxLength))
		}
		var result = String(characters)
		while result.utf8.count > maxUTF8Bytes && !characters.isEmpty {
			characters.removeLast()
			result = String(characters)
		}
		return result
	}

	/// The name used to compare two names: Windows and macOS do not tell "Holiday" and "holiday" apart.
	static func foldKey(_ name: String) -> String {
		return name.lowercased()
	}

	/// "Trip" + 2 = "Trip (2)"; the base is shortened first so that the result still fits.
	static func withNumberSuffix(_ base: String, number: Int, maxLength: Int = AlbumFolderNaming.maxFolderNameLength) -> String {
		let suffix = " (\(number))"
		var shortened = base
		let room = maxLength - suffix.count
		if shortened.count > room {
			shortened = trimEdges(String(Array(shortened).prefix(max(room, 1))))
		}
		if shortened.isEmpty {
			shortened = untitledAlbumName
		}
		return shortened + suffix
	}

	// MARK: - File names

	/// "IMG_0001.HEIC" -> ("IMG_0001", "HEIC"); a name without a dot, a name that starts with its only dot, or a name that ends
	/// with a dot has no extension.
	static func splitFileName(_ name: String) -> (stem: String, ext: String) {
		guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
			return (name, "")
		}
		let afterDot = name.index(after: dot)
		if afterDot == name.endIndex {
			return (name, "")
		}
		return (String(name[name.startIndex..<dot]), String(name[afterDot...]))
	}

	static func composeFileName(stem: String, ext: String) -> String {
		return ext.isEmpty ? stem : stem + "." + ext
	}

	/// The first `length` letters and digits of an identifier ("9F2D7C2A-6A1B/L0/001" -> "9F2D7C"), used to tell two files with the
	/// same name apart.
	static func shortID(_ identifier: String, length: Int) -> String {
		var result = ""
		for character in identifier {
			if character.isASCII && (character.isLetter || character.isNumber) {
				result.append(character)
				if result.count >= length {
					break
				}
			}
		}
		return result.isEmpty ? "id" : result
	}

	// MARK: - Album folders

	/// Gives every album a folder name that is unique (ignoring upper/lower case) among the given albums, and different from
	/// "No album".
	///
	/// `existing` holds the names given in earlier runs. An album keeps its earlier name as long as its title is the same, so a
	/// folder name never flips between runs even when albums are added or deleted. Only the albums without an earlier name are
	/// given one now, in the order of their identifiers: the first album with a title gets the plain name, the next one gets
	/// " (2)", then " (3)".
	static func assignFolderNames(albums: [AlbumFolderRef], existing: [String: AlbumFolderAssignment] = [:])
		-> [String: AlbumFolderAssignment]
	{
		var result: [String: AlbumFolderAssignment] = [:]
		var taken: Set<String> = [foldKey(noAlbumFolderName)]
		let ordered = albums.sorted { $0.id < $1.id }

		for album in ordered {
			if let old = existing[album.id], old.title == album.title, !old.folder.isEmpty {
				let key = foldKey(old.folder)
				if !taken.contains(key) {
					result[album.id] = old
					taken.insert(key)
				}
			}
		}

		for album in ordered {
			if result[album.id] != nil {
				continue
			}
			let base = sanitizeFolderName(album.title)
			var candidate = base
			var number = 1
			while taken.contains(foldKey(candidate)) {
				number += 1
				candidate = withNumberSuffix(base, number: number)
			}
			taken.insert(foldKey(candidate))
			result[album.id] = AlbumFolderAssignment(title: album.title, folder: candidate)
		}
		return result
	}

	// MARK: - Small helpers

	/// FNV-1a, 64 bit, as 16 hexadecimal digits. The same text always gives the same answer on every device (Swift's own
	/// hashValue does not: it is different in every run). Used for the name of the ledger file.
	static func stableHash(_ text: String) -> String {
		var hash: UInt64 = 0xcbf2_9ce4_8422_2325
		for byte in text.utf8 {
			hash ^= UInt64(byte)
			hash = hash &* 0x100_0000_01b3
		}
		let hex = String(hash, radix: 16)
		return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
	}

	/// Gives a finished file its real name: the file is moved there in one step, and a file that is already there is replaced in one
	/// step. A file written to a temporary place first and moved like this has its real name only when it is complete, so a crash
	/// never leaves half a file under a real name.
	static func moveIntoPlace(_ temporary: URL, to destination: URL) throws {
		let manager = FileManager.default
		if manager.fileExists(atPath: destination.path) {
			_ = try manager.replaceItemAt(destination, withItemAt: temporary)
		}
		else {
			try manager.moveItem(at: temporary, to: destination)
		}
	}
}

// MARK: - The ledger

/// What has been saved already, kept in a small JSON file so that it survives a crash, a restart of the phone or an update.
///
/// A key is `assetIdentifier|albumIdentifier|kind` (kind = photo, video or live); its value is the path the file was saved at,
/// relative to the back-up folder's "Path in folder": `Album folder/IMG_0001.HEIC`. A key is added only AFTER its file has been
/// written, and the file is written atomically (a temporary file, then a rename): a crash or a power cut leaves either the old
/// or the new complete ledger, never half of one. The ledger is saved every few files and at the end of every run, so a crash
/// loses at most the last few keys; those files are found on the disk the next time and are then recognised, not saved again.
///
/// The ledger also remembers the names already given to files, because the rule "the first photo keeps the plain name, a second
/// photo with the same name in the same folder gets `_` and 6 characters of its identifier" must give the same answer in every
/// run. It belongs to ONE destination (back-up folder and path in it): another destination starts empty.
///
/// All methods take a lock, so they may be called from any thread; the back-up uses one task at a time anyway.
final class AlbumExportLedger: @unchecked Sendable {
	struct Stored: Codable {
		var version: Int
		var destination: String
		var albums: [String: AlbumFolderAssignment]
		var exported: [String: String]
	}

	private struct Expected {
		let key: String
		let relativePath: String
	}

	static let fileFormatVersion = 1

	/// The last part of a ledger key (the same words as PhotoBackupCategory's raw values).
	static let kindPhoto = "photo"
	static let kindVideo = "video"
	static let kindLive = "live"

	/// The file name for one destination: `PhotoAlbumLedger-<16 hex digits>.json`.
	static func fileName(forDestination destination: String) -> String {
		return "PhotoAlbumLedger-" + AlbumFolderNaming.stableHash(destination) + ".json"
	}

	static func key(assetID: String, albumID: String, kind: String) -> String {
		return assetID + "|" + albumID + "|" + kind
	}

	private let lock = NSRecursiveLock()
	private let destination: String
	private let fileURL: URL?
	private var albums: [String: AlbumFolderAssignment] = [:]
	private var exported: [String: String] = [:]
	private var stemOwner: [String: String] = [:]
	private var assetStem: [String: String] = [:]
	private var expected: [String: Expected] = [:]
	private var openKeys: Set<String> = []
	private var unsavedCount = 0
	private var lastSaveTime = Date()
	private var completedTotal = 0
	private var adoptedTotal = 0
	private var lastError: String? = nil
	private var note = ""
	private var unreadable = false

	/// "Re-copy all photos": nothing counts as done, everything is saved again (to the same names).
	var ignoreExisting = false
	/// Save to the disk after this many changes ...
	var checkpointEveryChanges = 40
	/// ... or after this many seconds, whichever comes first.
	var checkpointEverySeconds: TimeInterval = 8

	/// A ledger for one destination. With `fileURL` nil nothing is read or written (tests).
	init(destination: String, fileURL: URL?) {
		self.destination = destination
		self.fileURL = fileURL
	}

	/// Opens the ledger of one destination. A missing file, a damaged file or a file written for another destination gives an empty
	/// ledger; `loadNote` says which.
	static func load(destination: String, fileURL: URL) -> AlbumExportLedger {
		let ledger = AlbumExportLedger(destination: destination, fileURL: fileURL)
		guard FileManager.default.fileExists(atPath: fileURL.path) else {
			ledger.note = "no ledger file yet, starting empty"
			return ledger
		}
		// A file that exists but cannot be read is NOT a damaged file: iOS keeps app files closed until the phone has been unlocked once
		// after it started. Going on with an empty ledger would replace the real one at the next save, so say "not usable" instead.
		let data: Data
		do {
			data = try Data(contentsOf: fileURL)
		}
		catch {
			ledger.unreadable = true
			ledger.note = "ledger file cannot be read right now (\(error.localizedDescription))"
			return ledger
		}
		do {
			let stored = try JSONDecoder().decode(Stored.self, from: data)
			if stored.version != fileFormatVersion {
				ledger.note = "ledger file has version \(stored.version), expected \(fileFormatVersion): starting empty"
			}
			else if stored.destination != destination {
				ledger.note = "ledger file belongs to another destination: starting empty"
			}
			else {
				ledger.take(stored)
				ledger.note = "loaded \(stored.exported.count) saved items and \(stored.albums.count) album names"
			}
		}
		catch {
			// Keep the damaged file for a look later; the next save writes a fresh one.
			let damaged = fileURL.appendingPathExtension("damaged")
			try? FileManager.default.moveItem(at: fileURL, to: damaged)
			ledger.note = "ledger file could not be read (\(error.localizedDescription)): starting empty"
		}
		return ledger
	}

	private func take(_ stored: Stored) {
		albums = stored.albums
		exported = stored.exported
		stemOwner = [:]
		assetStem = [:]
		for (key, path) in exported {
			indexClaim(key: key, relativePath: path)
		}
	}

	// MARK: Reading

	/// What happened when the file was loaded (for the log).
	var loadNote: String { return locked { note } }
	var savedItemCount: Int { return locked { exported.count } }
	/// Files saved in this run.
	var completedCount: Int { return locked { completedTotal } }
	/// Files that were found already there and recognised in this run.
	var adoptedCount: Int { return locked { adoptedTotal } }
	/// Files announced with `expect` and not finished (yet): not zero after a run means something could not be saved.
	var openCount: Int { return locked { openKeys.count } }
	/// The photos and videos (their identifiers) that have a file announced with `expect` and not finished (yet).
	var openAssetIDs: Set<String> {
		return locked { () -> Set<String> in
			var result = Set<String>()
			for key in openKeys {
				if let bar = key.firstIndex(of: "|") {
					result.insert(String(key[key.startIndex..<bar]))
				}
			}
			return result
		}
	}
	var lastSaveError: String? { return locked { lastError } }
	/// False when the ledger file exists but could not be read (see `load`): the back-up must not go on, and nothing is ever written
	/// over that file.
	var isUsable: Bool { return locked { !unreadable } }

	func isDone(_ key: String) -> Bool {
		return locked {
			if ignoreExisting {
				return false
			}
			return exported[key] != nil
		}
	}

	/// The path a key was saved at ("Album folder/IMG_0001.HEIC"), or nil.
	func savedPath(for key: String) -> String? {
		return locked { exported[key] }
	}

	// MARK: Album folders

	/// Gives every album its folder name (names given earlier are kept) and returns identifier -> folder name.
	func assignAlbums(_ refs: [AlbumFolderRef]) -> [String: String] {
		return locked {
			let assigned = AlbumFolderNaming.assignFolderNames(albums: refs, existing: albums)
			var merged = albums
			for (id, assignment) in assigned {
				merged[id] = assignment
			}
			if merged != albums {
				albums = merged
				unsavedCount += 1
			}
			var folders: [String: String] = [:]
			for (id, assignment) in assigned {
				folders[id] = assignment.folder
			}
			return folders
		}
	}

	// MARK: File names

	/// The name a photo or video gets inside an album folder: its original name, unless another asset already holds that name
	/// in that folder (ignoring upper/lower case): then `_` and the first 6 letters/digits of the asset identifier are added to the
	/// stem. The answer for one asset in one folder never changes, so the video of a Live Photo (stem + ".MOV") always sits next
	/// to its picture.
	func fileName(forAsset assetID: String, folder: String, originalName: String) -> (stem: String, ext: String) {
		return locked {
			let parts = AlbumFolderNaming.splitFileName(originalName)
			let ext = AlbumFolderNaming.sanitizeExtension(parts.ext)
			let folderKey = AlbumFolderNaming.foldKey(folder)

			if let known = assetStem[folderKey + "|" + assetID] {
				return (known, ext)
			}

			let base = AlbumFolderNaming.sanitizeFileStem(parts.stem)
			var candidate = base
			var attempt = 0
			while let owner = stemOwner[folderKey + "|" + AlbumFolderNaming.foldKey(candidate)], owner != assetID {
				attempt += 1
				let idPart: String
				if attempt <= 3 {
					idPart = AlbumFolderNaming.shortID(assetID, length: 6 + 4 * (attempt - 1))
				}
				else {
					idPart = AlbumFolderNaming.shortID(assetID, length: 6) + "_" + String(attempt)
				}
				let room = AlbumFolderNaming.maxFileStemLength - idPart.count - 1
				let clipped = AlbumFolderNaming.trimEdges(String(Array(base).prefix(max(room, 1))))
				candidate = (clipped.isEmpty ? AlbumFolderNaming.untitledFileName : clipped) + "_" + idPart
			}
			stemOwner[folderKey + "|" + AlbumFolderNaming.foldKey(candidate)] = assetID
			assetStem[folderKey + "|" + assetID] = candidate
			return (candidate, ext)
		}
	}

	private func indexClaim(key: String, relativePath: String) {
		let parts = key.components(separatedBy: "|")
		guard parts.count == 3, let slash = relativePath.lastIndex(of: "/") else {
			return
		}
		let assetID = parts[0]
		let folder = String(relativePath[relativePath.startIndex..<slash])
		let fileName = String(relativePath[relativePath.index(after: slash)...])
		let stem = AlbumFolderNaming.splitFileName(fileName).stem
		let folderKey = AlbumFolderNaming.foldKey(folder)
		stemOwner[folderKey + "|" + AlbumFolderNaming.foldKey(stem)] = assetID
		assetStem[folderKey + "|" + assetID] = stem
	}

	// MARK: Progress of a run

	/// Announce that the file at `pathInFolder` (the path inside the Syncthing folder) is about to be saved for `key`.
	func expect(pathInFolder: String, key: String, relativePath: String) {
		locked {
			expected[pathInFolder] = Expected(key: key, relativePath: relativePath)
			openKeys.insert(key)
		}
	}

	/// The file at `pathInFolder` has been written completely: now (and only now) its key is added.
	func completed(pathInFolder: String) {
		locked {
			guard let item = expected.removeValue(forKey: pathInFolder) else {
				return
			}
			record(key: item.key, relativePath: item.relativePath)
			completedTotal += 1
			checkpointIfDue()
		}
	}

	/// The file was already there (saved in an earlier run, or deleted on purpose): remember the key without saving anything.
	func markAdopted(key: String, relativePath: String) {
		locked {
			record(key: key, relativePath: relativePath)
			adoptedTotal += 1
			checkpointIfDue()
		}
	}

	private func record(key: String, relativePath: String) {
		exported[key] = relativePath
		openKeys.remove(key)
		indexClaim(key: key, relativePath: relativePath)
		unsavedCount += 1
	}

	/// Writes the file after `checkpointEveryChanges` changes or `checkpointEverySeconds`, but less often when the ledger is big (the
	/// whole file is written each time): at least 1 second more per 1000 saved items and 1 change more per 25 saved items.
	private func checkpointIfDue() {
		let size = exported.count
		let changesNeeded = max(checkpointEveryChanges, size / 25)
		let secondsNeeded = max(checkpointEverySeconds, Double(size) / 1000.0)
		if unsavedCount >= changesNeeded || Date().timeIntervalSince(lastSaveTime) >= secondsNeeded {
			_ = writeFile()
		}
	}

	// MARK: Saving

	/// Writes the ledger now if anything changed since the last write. Returns false when the write failed.
	@discardableResult
	func saveNow() -> Bool {
		return locked {
			if unsavedCount == 0 {
				return true
			}
			return writeFile()
		}
	}

	private func writeFile() -> Bool {
		guard let url = fileURL else {
			unsavedCount = 0
			return true
		}
		if unreadable {
			lastError = "the ledger file could not be read, so it is not overwritten"
			return false
		}
		do {
			let stored = Stored(
				version: AlbumExportLedger.fileFormatVersion, destination: destination, albums: albums, exported: exported)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys]
			let data = try encoder.encode(stored)
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			// .atomic = write to a temporary file in the same folder, then rename it over the old file
			try data.write(to: url, options: .atomic)
			unsavedCount = 0
			lastSaveTime = Date()
			lastError = nil
			return true
		}
		catch {
			lastError = error.localizedDescription
			return false
		}
	}

	private func locked<T>(_ body: () -> T) -> T {
		lock.lock()
		defer { lock.unlock() }
		return body()
	}
}

// MARK: - What is still to be saved

/// What still has to be saved for one photo or video in one album folder, and under which names and keys.
struct AlbumAssetPlan: Sendable {
	/// The photo or video, for example IMG_0001.HEIC
	let primaryName: String
	/// The video of a Live Photo, next to the picture: IMG_0001.MOV
	let liveName: String
	let primaryKey: String
	let liveKey: String
	/// Whether the photo (or video) still has to be saved
	let wantsPrimary: Bool
	/// Whether the Live Photo's video still has to be saved
	let wantsLive: Bool
}

extension AlbumExportLedger {
	/// What still has to be saved for this photo or video in this album (`albumID`, saved in the folder `folder`); nil = nothing,
	/// everything wanted is in the ledger already. A photo (or video) and the video of its Live Photo are two separate parts, each
	/// with its own key. `originalName` is asked only when something has to be saved (it can be slow to find out).
	func plan(
		assetID: String, albumID: String, folder: String, isVideo: Bool, isLivePhoto: Bool,
		saveImages: Bool, saveVideos: Bool, saveLivePhotos: Bool, originalName: () -> String
	) -> AlbumAssetPlan? {
		let primaryKey = AlbumExportLedger.key(
			assetID: assetID, albumID: albumID, kind: isVideo ? AlbumExportLedger.kindVideo : AlbumExportLedger.kindPhoto)
		let liveKey = AlbumExportLedger.key(assetID: assetID, albumID: albumID, kind: AlbumExportLedger.kindLive)
		let wantsPrimary = (isVideo ? saveVideos : saveImages) && !isDone(primaryKey)
		let wantsLive = isLivePhoto && saveLivePhotos && !isDone(liveKey)
		if !wantsPrimary && !wantsLive {
			return nil
		}
		let parts = fileName(forAsset: assetID, folder: folder, originalName: originalName())
		return AlbumAssetPlan(
			primaryName: AlbumFolderNaming.composeFileName(stem: parts.stem, ext: parts.ext),
			liveName: parts.stem + ".MOV",
			primaryKey: primaryKey,
			liveKey: liveKey,
			wantsPrimary: wantsPrimary,
			wantsLive: wantsLive
		)
	}
}

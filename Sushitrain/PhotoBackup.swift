// Copyright (C) 2024 Tommy van der Vorst
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
import Foundation
import SwiftUI
@preconcurrency import SushitrainCore
import Photos

enum PhotoBackupCategory: String, Codable {
	case photo = "photo"
	case livePhoto = "live"
	case video = "video"
}

enum PhotoBackupTimeZone: RawRepresentable, Codable, Equatable, Hashable {
	typealias RawValue = String

	// Use the current timezone when exporting. Photos may be exported twice if you switch timezones
	case current

	// Use a specific timezone. Photos may be exported with a day that differs from the day the photo was taken
	case specific(timeZone: String)

	init(rawValue: String) {
		if rawValue == "current" {
			self = .current
		}
		else {
			self = .specific(timeZone: rawValue)
		}
	}

	var rawValue: String {
		switch self {
		case .current: return "current"
		case .specific(timeZone: let s): return s
		}
	}
}

enum PhotoBackupFolderStructure: String, Codable {
	case byType = "byType"
	case byDate = "byDate"
	case byDateAndType = "byDateAndType"
	case byDateComponent = "byDateComponent"
	case byDateComponentAndType = "byDateComponentAndType"
	case byYear = "byYear"
	case byYearAndType = "byYearAndType"
	case byYearMonth = "byYearMonth"
	case byYearDashMonth = "byYearDashMonth"
	case byYearDashMonthAndType = "byYearDashMonthAndType"
	case byYearMonthAndType = "byYearMonthAndType"
	case singleFolder = "singleFolder"
	case singleFolderDatePrefixed = "singleFolderDatePrefixed"

	// Fork: one folder per iPhone album (name = the album's name). It is not in the folder-structure picker: it is the layout
	// that is used when the source "Every album" is chosen (see PhotoBackup.effectiveFolderStructure and AlbumFolderNaming.swift).
	case byAlbumName = "byAlbumName"

	var examplePath: String {
		switch self {
		case .byDate: return String(localized: "2024-08-11/IMG_2020.HEIC")
		case .byDateAndType: return String(localized: "2024-08-11/Video/IMG_2020.MOV")
		case .byDateComponent: return String(localized: "2024/08/11/IMG_2020.HEIC")
		case .byDateComponentAndType: return String(localized: "2024/08/11/Video/IMG_2020.MOV")
		case .byYear: return String(localized: "2024/IMG_2020.MOV")
		case .byYearAndType: return String(localized: "2024/Video/IMG_2020.MOV")
		case .byYearMonth: return String(localized: "2024/08/IMG_2020.HEIC")
		case .byYearMonthAndType: return String(localized: "2024/08/Video/IMG_2020.MOV")
		case .byYearDashMonth: return String(localized: "2024-08/IMG_2020.HEIC")
		case .byYearDashMonthAndType: return String(localized: "2024-08/Video/IMG_2020.MOV")
		case .byType: return String(localized: "Video/IMG_2020.MOV")
		case .singleFolder: return String(localized: "IMG_2020.MOV")
		case .singleFolderDatePrefixed: return String(localized: "2024-08-11_IMG_2020.MOV")
		case .byAlbumName: return String(localized: "Holiday 2024/IMG_2020.HEIC")
		}
	}

	var usesTimeZone: Bool {
		switch self {
		case .byDate, .byDateAndType, .byDateComponent, .byDateComponentAndType, .singleFolderDatePrefixed,
			.byYear, .byYearMonth, .byYearAndType, .byYearMonthAndType, .byYearDashMonth, .byYearDashMonthAndType:
			return true
		case .byType, .singleFolder, .byAlbumName: return false
		}
	}

	var dateComponentsForPath: [String] {
		switch self {
		case .byDateComponent, .byDateComponentAndType:
			return ["yyyy", "MM", "dd"]

		case .byYear, .byYearAndType:
			return ["yyyy"]

		case .byYearMonth, .byYearMonthAndType:
			return ["yyyy", "MM"]

		case .byYearDashMonth, .byYearDashMonthAndType:
			return ["yyyy-MM"]

		case .byType, .singleFolder, .byDate, .byDateAndType, .singleFolderDatePrefixed, .byAlbumName:
			return []
		}
	}
}

enum PhotoBackupProgress {
	case notStarted
	case starting
	case exportingPhotos(index: Int, total: Int, current: String?)
	case exportingVideos(index: Int, total: Int, current: String?)
	case exportingLivePhotos(index: Int, total: Int, current: String?)
	case selecting
	case purging
	case error(String)
	case finished(savedAssets: Int?, purgedAssets: Int?)

	var stepProgress: Float {
		switch self {
		case .notStarted: return 1.0
		case .starting: return 0.0

		case .exportingPhotos(let index, let total, current: _):
			if total > 0 { return Float(index) / Float(total) }
			return 1.0
		case .exportingVideos(let index, let total, current: _):
			if total > 0 { return Float(index) / Float(total) }
			return 1.0
		case .exportingLivePhotos(let index, let total, current: _):
			if total > 0 { return Float(index) / Float(total) }
			return 1.0
		case .selecting: return 0.0
		case .purging: return 0.0
		case .finished(savedAssets: _): return 1.0
		case .error(_): return 1.0
		}
	}

	var badgeText: String {
		switch self {
		case .notStarted: return ""
		case .starting: return ""
		case .exportingPhotos(let index, let total, current: _): return String(localized: "\(index+1) of \(total)")
		case .exportingVideos(let index, let total, current: _): return String(localized: "\(index+1) of \(total)")
		case .exportingLivePhotos(let index, let total, current: _): return String(localized: "\(index+1) of \(total)")
		case .purging: return ""
		case .selecting: return ""
		case .error(_): return ""
		case .finished(_, _): return ""
		}
	}

	var localizedDescription: String {
		switch self {
		case .notStarted: return String(localized: "Not started")
		case .starting: return String(localized: "Preparing to save photos and videos")
		case .exportingPhotos(index: _, total: _, current: _): return String(localized: "Saving photos")
		case .exportingVideos(index: _, total: _, current: _): return String(localized: "Saving videos")
		case .exportingLivePhotos(index: _, total: _, current: _): return String(localized: "Saving live photos")
		case .purging: return String(localized: "Removing originals")
		case .selecting: return String(localized: "Selecting files to be synchronized")
		case .error(let e):
			return String(localized: "Failed: \(e)")

		case .finished(savedAssets: _):
			return String(localized: "Finished")
		}
	}
}

@MainActor class PhotoBackup: ObservableObject {
	static nonisolated let allPhotosAlbumIdentifier = "_SUSHITRAIN_ALL_PHOTOS"

	// Fork: the source "Every album (one folder per album)". Choosing it means: every user album of the Photos library becomes
	// one folder with the album's name inside the destination folder (see AlbumFolderNaming.swift and README_FORK.md).
	static nonisolated let everyAlbumIdentifier = "_PHOTOTRAIN_EVERY_ALBUM"

	// These settings are prefixed 'photoSync' because that is what the feature used to be called
	@AppStorage("photoSyncSelectedAlbumID") var selectedAlbumID: String = ""
	@AppStorage("photoSyncFolderID") var selectedFolderID: String = ""

	// Album to put photos that have been saved in
	@AppStorage("photoSyncSavedAlbumID") var savedAlbumID: String = ""

	@AppStorage("photoSyncLastCompletedDate") var lastCompletedDate: Double = -1.0
	@AppStorage("photoSyncEnableBackgroundCopy") var enableBackgroundCopy: Bool = false

	// Fork: start a back-up by itself when new photos arrive in the photo library (see AutoPhotoBackup)
	@AppStorage("photoBackupAutomatic") var automatic: Bool = true
	@AppStorage("photoSyncCategories") var categories: Set<PhotoBackupCategory> = Set([.photo, .video, .livePhoto])
	@AppStorage("photoSyncPurgeEnabled") var purgeEnabled = false
	@AppStorage("photoSyncPurgeAfterDays") var purgeAfterDays = 7
	@AppStorage("photoBackupIncludeAllBurstAssets") var includeAllBurstAssets = false
	@AppStorage("photoBackupIncludeAAESidecars") var includeAAESidecars = false
	@AppStorage("PhotoBackupFolderStructure") var folderStructure = PhotoBackupFolderStructure.byDateAndType
	@AppStorage("photoSyncSubdirectoryPath") var subDirectoryPath = ""
	// The maximum age (in days) for assets to be considered for export; 0 = no limit.
	// Fork: the default is NO limit, so the first run saves every photo (upstream: 6 * 30 = six months).
	@AppStorage("photoSyncMaxAgeDays") var maxAgeDays = 0
	@AppStorage("photoBackupTimeZone") var timeZone: PhotoBackupTimeZone = .current
	@AppStorage("photoBackupLastSuccessfulChangeToken") var lastSuccessfullChangeTokenData: Data = Data()

	// Fork: the fast path of the automatic back-up (see PhotoChangePlan.swift and README_FORK.md). There is no screen for these two yet.
	// Seconds the automatic back-up waits after the LAST change in the photo library before it starts (used range 3...120).
	@AppStorage("photoBackupQuietSeconds") var quietSecondsSetting: Int = PhotoChangePlanner.defaultQuietSeconds
	// Most photos the fast path looks at; with more changed photos (or when an album changed) all albums are looked at. 0 = fast path off.
	@AppStorage("photoBackupFastPathMaxAssets") var fastPathMaxAssetsSetting: Int = PhotoChangePlanner.defaultFastPathMaxAssets

	// Whether to replace or append the ".MOV" file extension for live photos
	@AppStorage("photoBackupLivePhotoReplaceExtension") var livePhotoReplaceExtension: Bool = false

	@Published private(set) var isBackingUp = false
	@Published private(set) var progress: PhotoBackupProgress = .notStarted
	@Published private(set) var photoBackupTask: Task<(), Error>? = nil

	var selectedAlbumTitle: String? {
		if !self.selectedAlbumID.isEmpty {
			if let selectedAlbum = PHAssetCollection.fetchAssetCollections(
				withLocalIdentifiers: [self.selectedAlbumID], options: nil
			).firstObject {
				return selectedAlbum.localizedTitle
			}
		}
		return nil
	}

	// Fork: the wait before an automatic run, brought into the allowed range (3...120 seconds)
	var quietSeconds: Int { return PhotoChangePlanner.clampQuietSeconds(self.quietSecondsSetting) }

	var isReady: Bool { return !self.selectedAlbumID.isEmpty && !self.selectedFolderID.isEmpty }

	// Fork: "Every album" is chosen as the source
	var isEveryAlbum: Bool { return self.selectedAlbumID == PhotoBackup.everyAlbumIdentifier }

	// Fork: the layout that is really used. The date layout the user picked stays saved and comes back when another source is chosen.
	var effectiveFolderStructure: PhotoBackupFolderStructure {
		return self.isEveryAlbum ? PhotoBackupFolderStructure.byAlbumName : self.folderStructure
	}

	@MainActor func cancel() {
		self.photoBackupTask?.cancel()
		self.photoBackupTask = nil
	}

	@discardableResult
	@MainActor func backup(appState: AppState, fullExport: Bool, isInBackground: Bool) -> Task<(), Error>? {
		if !self.isReady { return nil }
		if self.selectedAlbumID.isEmpty { return nil }
		if self.photoBackupTask != nil { return nil }
		self.isBackingUp = true

		let selectedAlbumID = self.selectedAlbumID
		let selectedFolderID = self.selectedFolderID
		let categories = self.categories
		let includeAllBurstAssets = self.includeAllBurstAssets
		// Fork: album mode ("Every album"): the ledger of what was saved is valid for one destination (folder + path in it)
		let everyAlbum = (selectedAlbumID == PhotoBackup.everyAlbumIdentifier)
		let ledgerDestination = selectedFolderID + "|" + self.subDirectoryPath
		// Fork: the fast path looks at no more than this many changed photos (see PhotoChangePlan.swift)
		let fastPathMaxAssets = PhotoChangePlanner.clampFastPathMaxAssets(self.fastPathMaxAssetsSetting)

		// Start the actual synchronization task
		self.photoBackupTask = Task.detached(priority: .background) {
			DispatchQueue.main.async { self.progress = .starting }

			defer {
				DispatchQueue.main.async {
					self.photoBackupTask = nil
					self.isBackingUp = false
				}
			}

			// Fork: album mode: ONE line in the log per run (how it was started, which path it took and why, what the library reported,
			// how long it took, how it ended). It is written when the run ends, also when the run fails or is cancelled.
			let runStarted = DispatchTime.now().uptimeNanoseconds
			var runReport = PhotoRunReport(trigger: fullExport ? "re-copy all" : (isInBackground ? "automatic" : "by hand"))
			var runResult = "stopped before the pass (see the lines above)"
			defer {
				if everyAlbum {
					let milliseconds = Int((DispatchTime.now().uptimeNanoseconds - runStarted) / 1_000_000)
					Log.note(runReport.logLine(milliseconds: milliseconds, result: runResult))
					AliveStore.markAlive("photo back-up run")
				}
			}

			// Determine destination folder and check if we can use it
			guard let folder = appState.client.folder(withID: selectedFolderID) else {
				DispatchQueue.main.async {
					self.progress = .error(String(localized: "Cannot find selected folder with ID '\(selectedFolderID)'"))
				}
				return
			}

			if !folder.exists() {
				DispatchQueue.main.async { self.progress = .error(String(localized: "Selected folder does not exist")) }
				return
			}

			if !folder.isSuitablePhotoBackupDestination {
				DispatchQueue.main.async {
					self.progress = .error(String(localized: "The selected folder cannot be used to save photos to"))
				}
				return
			}

			// Let iOS know we are about to do some background stuff
			#if os(iOS)
				let bgIdentifier = await UIApplication.shared.beginBackgroundTask(
					withName: "Photo back-up",
					expirationHandler: {
						Log.info("Cancelling background task due to expiration")
						self.cancel()
					})
				defer {
					Log.info("Signalling end of background task")
					DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(bgIdentifier) }
				}
				Log.info("Background time remaining: \(await UIApplication.shared.backgroundTimeRemaining))")
			#endif

			// Check to see if anything changed at all
			var onlyTheseLocalIdentifiers: Set<String>? = nil
			// Fork: album mode, automatic run: the photos the library reported as added or changed, when only those need a look
			// (nil = look at all albums, as the manual button always does)
			var fastPathIDs: Set<String>? = nil
			// ... and which of them were ADDED (a file of an added photo that cannot be saved holds the library state back)
			var fastPathAddedIDs = Set<String>()
			let changeToken = PHPhotoLibrary.shared().currentChangeToken
			Log.info("Current change token: \(changeToken)")
			if !everyAlbum {
				runReport.plan = .full(reason: "not album mode")
			}
			else if fullExport {
				runReport.plan = .full(reason: "re-copy all photos")
			}
			else if !isInBackground {
				runReport.plan = .full(reason: "started by hand")
			}
			else {
				runReport.plan = .full(reason: "no saved library state yet (first run)")
			}
			if let lastSuccessfulChangeToken = await self.lastSuccessfulChangeToken {
				Log.info("Last change token: \(lastSuccessfulChangeToken)")
				if everyAlbum && isInBackground && !fullExport {
					// Fork: album mode, automatic run: find out WHAT changed, then look at as little as possible (PhotoChangePlan.swift).
					// A new photo needs a look at that photo only. A changed album (renamed, a photo put in it, ...), a change list that
					// cannot be read or too many changed photos need the look at all albums that was always made here. When the user
					// presses "Back-up new photos" himself (isInBackground is false), all albums are always looked at (this also
					// retries files that could not be saved before).
					var changes = PhotoChangeInput()
					do {
						changes = try self.classifyLibraryChanges(since: lastSuccessfulChangeToken)
					}
					catch PHPhotosError.persistentChangeTokenExpired,
						PHPhotosError.persistentChangeDetailsUnavailable
					{
						Log.warn("Persistent change token expired or details unavailable; resetting the saved change token")
						changes.unreadableReason = "the saved library state has expired"
						DispatchQueue.main.async {
							self.lastSuccessfulChangeToken = nil
						}
					}
					catch {
						Log.warn("Photo back-up: the list of library changes cannot be read: \(error.localizedDescription)")
						changes.unreadableReason = "reading it failed"
					}
					let decision = PhotoChangePlanner.plan(changes, maxAssets: fastPathMaxAssets)
					runReport.record(input: changes, plan: decision)
					switch decision {
					case .nothing:
						// FIXME: we are skipping purge here
						Log.info("Nothing changed that needs a back-up (not a full export), finishing early!")
						runResult = "done, nothing to save"
						let remember = PhotoChangePlanner.mayRememberLibraryState(
							plan: decision, hadChanges: changes.hasAnyChange, outcome: .completed)
						DispatchQueue.main.async {
							self.progress = .finished(savedAssets: nil, purgedAssets: nil)
							self.lastCompletedDate = Date.now.timeIntervalSinceReferenceDate
							if remember {
								self.lastSuccessfulChangeToken = changeToken
							}
						}
						return

					case .only(let changedIDs):
						fastPathIDs = changedIDs
						fastPathAddedIDs = changes.inserted

					case .full:
						break
					}
				}
				else if !everyAlbum && !fullExport {
					do {
						let ids = try self.insertedOrUpdatedLocalIdentifiers(since: lastSuccessfulChangeToken, to: changeToken)
						if ids.isEmpty {
							// FIXME: we are skipping purge here
							Log.info("Nothing changed and not a full export, finishing early!")
							DispatchQueue.main.async {
								self.progress = .finished(savedAssets: nil, purgedAssets: nil)
								self.lastCompletedDate = Date.now.timeIntervalSinceReferenceDate
							}
							return
						}
						onlyTheseLocalIdentifiers = ids
					}
					catch PHPhotosError.persistentChangeTokenExpired,
						PHPhotosError.persistentChangeDetailsUnavailable
					{
						Log.warn("Persistent change token expired or details unavailable; resetting the saved change token")
						DispatchQueue.main.async {
							self.lastSuccessfulChangeToken = nil
						}
					}
				}
			}

			// Pause the folder while backing up so we can change selection state.
			// Fork: the pause is saved in Syncthing's configuration. When iOS ends the app in the middle of a run, the folder stays
			// paused, and the next run would think "it was paused before" and keep it paused for good. So the app notes in its
			// preferences that IT paused the folder, and removes the note when it has put the folder back.
			let pausedByAppKey = "photoBackupFolderPausedByApp"
			let leftPausedByApp = UserDefaults.standard.string(forKey: pausedByAppKey) == selectedFolderID
			let folderWasPaused = folder.isPaused() && !leftPausedByApp
			if leftPausedByApp {
				Log.warn("Photo back-up: an earlier run did not finish and left the folder paused; it is put back at the end of this run")
			}
			if !folderWasPaused {
				UserDefaults.standard.set(selectedFolderID, forKey: pausedByAppKey)
			}
			try folder.setPaused(true)
			defer {
				// Fork fix: the note "this app paused the folder" is removed only when the folder really was put back. If putting it back
				// fails (Syncthing's configuration could not be saved) the note stays; without it the next run would take the pause for the
				// user's own and keep the folder paused for good (see PhotoChangePlanner.mayRemovePausedNote).
				var putBackWorked = true
				do {
					try folder.setPaused(folderWasPaused)
				}
				catch {
					putBackWorked = false
					Log.warn("Photo back-up: could not put the folder back as it was: \(error.localizedDescription). The next run tries again.")
				}
				if PhotoChangePlanner.mayRemovePausedNote(appPausedIt: !folderWasPaused, putBackWorked: putBackWorked) {
					UserDefaults.standard.removeObject(forKey: pausedByAppKey)
				}
			}

			// Get local path for destination folder
			var err: NSError? = nil
			let folderPath = folder.localNativePath(&err)
			if let err = err {
				DispatchQueue.main.async { self.progress = .error(err.localizedDescription) }
				return
			}

			// Ensure the subdirectory exists
			let subDirectoryPath = EntryPath(await self.subDirectoryPath, isDirectory: true)
			if subDirectoryPath.pathInFolder != "" {
				let subDirectoryPathURL = URL(fileURLWithPath: folderPath).appendingPathComponent(subDirectoryPath.pathInFolder)
				try FileManager.default.createDirectory(at: subDirectoryPathURL, withIntermediateDirectories: true)
			}

			let folderURL = URL(fileURLWithPath: folderPath)

			// Fork: album mode: one pass over every user album, each album saved in a folder with its name. The fast path (automatic
			// run, only some photos were added or changed, no album changed) looks at those photos only.
			if everyAlbum {
				let outcome: PhotoRunOutcome
				do {
					if let changedIDs = fastPathIDs {
						outcome = try await self.backupChangedAssets(
							appState: appState,
							folder: folder,
							folderURL: folderURL,
							subDirectoryPath: subDirectoryPath,
							destination: ledgerDestination,
							assetIDs: changedIDs,
							addedIDs: fastPathAddedIDs,
							categories: categories,
							includeAllBurstAssets: includeAllBurstAssets,
							isInBackground: isInBackground
						)
					}
					else {
						let complete = try await self.backupEveryAlbum(
							appState: appState,
							folder: folder,
							folderURL: folderURL,
							subDirectoryPath: subDirectoryPath,
							destination: ledgerDestination,
							fullExport: fullExport,
							categories: categories,
							includeAllBurstAssets: includeAllBurstAssets,
							isInBackground: isInBackground
						)
						outcome = complete ? .completed : .cancelled
					}
				}
				catch {
					runResult = "error: \(error.localizedDescription)"
					throw error
				}
				runResult = PhotoChangePlanner.describeOutcome(outcome)
				// Remember the library state when the pass ran to the end (not cancelled, no error). After a full pass, files that could
				// not be saved (for example photos that are only in iCloud) are tried again at the next full pass (a change in an
				// album, the manual button) or when the photo changes again. A fast pass that could not save an ADDED photo keeps the
				// old state, so the next run reads the same changes again and tries again (see PhotoChangePlanner.fastPassOutcome).
				let remember = PhotoChangePlanner.mayRememberLibraryState(plan: runReport.plan, hadChanges: true, outcome: outcome)
				if remember {
					DispatchQueue.main.async {
						self.lastSuccessfulChangeToken = changeToken
					}
				}
				return
			}

			let fetchResult: PHFetchResult<PHAssetCollection>
			if selectedAlbumID == PhotoBackup.allPhotosAlbumIdentifier {
				fetchResult = PHAssetCollection.fetchAssetCollections(
					with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
			}
			else {
				fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [selectedAlbumID], options: nil)
			}
			guard let album = fetchResult.firstObject else {
				DispatchQueue.main.async { self.progress = .error(String(localized: "Could not find selected album")) }
				return
			}

			try await self.backupAlbum(
				appState: appState,
				album: album,
				folder: folder,
				folderURL: folderURL,
				subDirectoryPath: subDirectoryPath,
				fullExport: fullExport,
				categories: categories,
				includeAllBurstAssets: includeAllBurstAssets,
				isInBackground: isInBackground,
				onlyTheseLocalIdentifiers: onlyTheseLocalIdentifiers
			)

			// Save change token
			DispatchQueue.main.async {
				self.lastSuccessfulChangeToken = changeToken
			}
		}
		return self.photoBackupTask
	}

	private nonisolated func insertedOrUpdatedLocalIdentifiers(since: PHPersistentChangeToken, to: PHPersistentChangeToken)
		throws -> Set<String>
	{
		// See if there are changes at all
		var changedIdentifiers = Set<String>()
		let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: since)
		for change in changes {
			let changeDetails = try change.changeDetails(for: .asset)
			for i in changeDetails.insertedLocalIdentifiers {
				changedIdentifiers.insert(i)
			}
			for i in changeDetails.updatedLocalIdentifiers {
				changedIdentifiers.insert(i)
			}
		}

		return changedIdentifiers
	}

	private var lastSuccessfulChangeToken: PHPersistentChangeToken? {
		get {
			let ltd = self.lastSuccessfullChangeTokenData
			if ltd.isEmpty {
				return nil
			}
			let nku = try? NSKeyedUnarchiver(forReadingFrom: ltd)
			return nku?.decodeObject(of: PHPersistentChangeToken.self, forKey: "changeToken")
		}
		set {
			if let nv = newValue {
				let nka = NSKeyedArchiver(requiringSecureCoding: true)
				nka.encode(nv, forKey: "changeToken")
				self.lastSuccessfullChangeTokenData = nka.encodedData
			}
			else {
				self.lastSuccessfullChangeTokenData = Data()
			}
		}
	}

	func resetLastSuccessfulChangeToken() {
		self.lastSuccessfulChangeToken = nil
	}

	// Album mode: what changed in the photo library since this saved state, as plain sets for PhotoChangePlanner (PhotoChangePlan.swift):
	// the photos and videos added, changed and deleted, and the albums that changed (created, renamed, a photo put in or taken out,
	// deleted). Albums that the back-up never looks at (smart albums such as Recents, iCloud Shared Albums, ...) are not counted as
	// album changes. Throws what Photos throws (for example an expired saved state); the caller then looks at everything.
	private nonisolated func classifyLibraryChanges(since: PHPersistentChangeToken) throws -> PhotoChangeInput {
		var result = PhotoChangeInput()
		var albumIdentifiers = Set<String>()
		let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: since)
		for change in changes {
			result.changeRecords += 1

			let assetDetails = try change.changeDetails(for: .asset)
			for i in assetDetails.insertedLocalIdentifiers {
				result.inserted.insert(i)
			}
			for i in assetDetails.updatedLocalIdentifiers {
				result.updated.insert(i)
			}
			for i in assetDetails.deletedLocalIdentifiers {
				result.deleted.insert(i)
			}

			let albumDetails = try change.changeDetails(for: .assetCollection)
			for i in albumDetails.insertedLocalIdentifiers {
				albumIdentifiers.insert(i)
			}
			for i in albumDetails.updatedLocalIdentifiers {
				albumIdentifiers.insert(i)
			}
			for i in albumDetails.deletedLocalIdentifiers {
				albumIdentifiers.insert(i)
			}
		}
		result.changedAlbums = changedAlbumsThatMatter(among: albumIdentifiers)
		return result
	}

	// Album mode ("Every album (one folder per album)"): one pass over all user albums. Each album is saved in a folder with its name;
	// a photo that is in two albums is saved in both folders; photos that are in no user album go to the folder "No album".
	// The ledger (a small file, see AlbumFolderNaming.swift) knows what was saved before, so only what is missing is saved.
	// Returns true when the pass ran to the end (it was not cancelled): then the caller remembers the library change token. A pass
	// that fails with an error throws instead; then the token is not remembered and the next run looks at all albums again.
	private nonisolated func backupEveryAlbum(
		appState: AppState,
		folder: SushitrainFolder,
		folderURL: URL,
		subDirectoryPath: EntryPath,
		destination: String,
		fullExport: Bool,
		categories: Set<PhotoBackupCategory>,
		includeAllBurstAssets: Bool,
		isInBackground: Bool
	) async throws -> Bool {
		let ledgerURL = try albumLedgerFileURL(destination: destination)
		let ledger = AlbumExportLedger.load(destination: destination, fileURL: ledgerURL)
		ledger.ignoreExisting = fullExport
		Log.info("Album back-up: ledger \(ledgerURL.lastPathComponent): \(ledger.loadNote)")
		if !ledger.isUsable {
			// The ledger file exists but cannot be read right now (for example the phone has not been unlocked since it was
			// restarted). Going on with an empty one would replace the real one, so stop here; the next run tries again.
			let message = String(localized: "The list of saved photos cannot be read right now. This is tried again later.")
			DispatchQueue.main.async { self.progress = .error(message) }
			throw CocoaError(.fileReadNoPermission)
		}
		defer { ledger.saveNow() }

		// All user albums, and the folder name each one is saved in (names given in earlier runs are kept)
		let albums = userAlbumCollections()
		let albumRefs = albums.map { AlbumFolderRef(id: $0.localIdentifier, title: $0.localizedTitle ?? "") }
		let folderNames = ledger.assignAlbums(albumRefs)
		ledger.saveNow()
		Log.info("Album back-up: \(albums.count) albums")

		// Which photos are in at least one album? The others are saved in "No album".
		let listOptions = PHFetchOptions()
		listOptions.includeAllBurstAssets = includeAllBurstAssets
		var inAnyAlbum = Set<String>()
		for album in albums {
			let members = PHAsset.fetchAssets(in: album, options: listOptions)
			members.enumerateObjects { member, _, _ in
				_ = inAnyAlbum.insert(member.localIdentifier)
			}
		}

		let ordered = albums.sorted {
			(folderNames[$0.localIdentifier] ?? "").lowercased() < (folderNames[$1.localIdentifier] ?? "").lowercased()
		}

		// One album after the other. An album that fails does not stop the others; the first error is reported at the end.
		var firstError: Error? = nil
		for album in ordered {
			if Task.isCancelled { break }
			guard let folderName = folderNames[album.localIdentifier] else { continue }
			let context = AlbumExportContext(
				ledger: ledger, folderName: folderName, albumID: album.localIdentifier, skipAssetIDs: [])
			do {
				try await self.backupAlbum(
					appState: appState,
					album: album,
					folder: folder,
					folderURL: folderURL,
					subDirectoryPath: subDirectoryPath,
					fullExport: fullExport,
					categories: categories,
					includeAllBurstAssets: includeAllBurstAssets,
					isInBackground: isInBackground,
					onlyTheseLocalIdentifiers: nil,
					albumContext: context
				)
			}
			catch {
				if Task.isCancelled { throw error }
				Log.warn("Album back-up: the album '\(folderName)' could not be saved completely: \(error.localizedDescription)")
				if firstError == nil { firstError = error }
			}
		}

		// Photos and videos that are in no user album
		if !Task.isCancelled {
			let libraries = PHAssetCollection.fetchAssetCollections(
				with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
			if let library = libraries.firstObject {
				let context = AlbumExportContext(
					ledger: ledger, folderName: AlbumFolderNaming.noAlbumFolderName,
					albumID: AlbumFolderNaming.noAlbumIdentifier, skipAssetIDs: inAnyAlbum)
				do {
					try await self.backupAlbum(
						appState: appState,
						album: library,
						folder: folder,
						folderURL: folderURL,
						subDirectoryPath: subDirectoryPath,
						fullExport: fullExport,
						categories: categories,
						includeAllBurstAssets: includeAllBurstAssets,
						isInBackground: isInBackground,
						onlyTheseLocalIdentifiers: nil,
						albumContext: context
					)
				}
				catch {
					if Task.isCancelled { throw error }
					Log.warn("Album back-up: the photos in no album could not be saved completely: \(error.localizedDescription)")
					if firstError == nil { firstError = error }
				}
			}
		}

		ledger.saveNow()
		if let saveError = ledger.lastSaveError {
			Log.warn("Album back-up: the ledger could not be written: \(saveError)")
		}
		Log.info(
			"Album back-up: saved \(ledger.completedCount) files, \(ledger.adoptedCount) were there already, \(ledger.openCount) not saved, \(ledger.savedItemCount) in the ledger"
		)
		if let error = firstError {
			let message = error.localizedDescription
			DispatchQueue.main.async { self.progress = .error(message) }
			throw error
		}
		if Task.isCancelled { return false }

		let notSaved = ledger.openCount
		if notSaved > 0 {
			Log.warn(
				"Album back-up: \(notSaved) files could not be saved this time (for example photos that are only in iCloud). They are tried again at the next change in the photo library or when you press 'Back-up new photos'."
			)
		}
		let savedCount = ledger.completedCount
		let completedDate = Date.now.timeIntervalSinceReferenceDate
		DispatchQueue.main.async {
			self.lastCompletedDate = completedDate
			self.progress = .finished(savedAssets: savedCount, purgedAssets: nil)
		}
		return true
	}

	// Album mode, the FAST PATH of the automatic run (decided by PhotoChangePlanner, see PhotoChangePlan.swift): only the photos and videos
	// that the library reported as added or changed are looked at, and no album changed. For each of them the user albums it is in are
	// found (none = the folder "No album"); then the same per-album code as the full pass (backupAlbum, with the ledger) saves what is
	// missing, narrowed down to those photos. The ledger knows what is saved already, so a changed old photo costs nothing.
	// Returns how the pass ended (PhotoChangePlanner.fastPassOutcome): the caller remembers the library change token only for `.completed`.
	// `.incomplete` = a photo that was ADDED (`addedIDs`) could not be saved yet, so the next run reads the same changes again and tries
	// again; a changed old photo that cannot be saved (typically it is only in iCloud) does not hold the token back. A pass that fails
	// with an error throws instead; then the token is not remembered either.
	private nonisolated func backupChangedAssets(
		appState: AppState,
		folder: SushitrainFolder,
		folderURL: URL,
		subDirectoryPath: EntryPath,
		destination: String,
		assetIDs: Set<String>,
		addedIDs: Set<String>,
		categories: Set<PhotoBackupCategory>,
		includeAllBurstAssets: Bool,
		isInBackground: Bool
	) async throws -> PhotoRunOutcome {
		let ledgerURL = try albumLedgerFileURL(destination: destination)
		let ledger = AlbumExportLedger.load(destination: destination, fileURL: ledgerURL)
		Log.info("Album back-up (fast path): ledger \(ledgerURL.lastPathComponent): \(ledger.loadNote)")
		if !ledger.isUsable {
			// See backupEveryAlbum: never go on with an empty ledger when the real one cannot be read right now
			let message = String(localized: "The list of saved photos cannot be read right now. This is tried again later.")
			DispatchQueue.main.async { self.progress = .error(message) }
			throw CocoaError(.fileReadNoPermission)
		}
		defer { ledger.saveNow() }

		// All user albums and the folder name each one is saved in: the same call as the full pass makes (names given before are kept)
		let albums = userAlbumCollections()
		let albumRefs = albums.map { AlbumFolderRef(id: $0.localIdentifier, title: $0.localizedTitle ?? "") }
		let folderNames = ledger.assignAlbums(albumRefs)
		ledger.saveNow()

		// The reported photos that still exist, and the user albums each one is in (none = "No album")
		let fetchOptions = PHFetchOptions()
		fetchOptions.includeAllBurstAssets = includeAllBurstAssets
		let changed = PHAsset.fetchAssets(withLocalIdentifiers: Array(assetIDs), options: fetchOptions)
		Log.info("Album back-up (fast path): \(assetIDs.count) photos reported, \(changed.count) found, \(albums.count) albums")

		var idsPerAlbum: [String: Set<String>] = [:]
		var albumByID: [String: PHAssetCollection] = [:]
		var inNoAlbum = Set<String>()
		changed.enumerateObjects { asset, _, _ in
			var inSomeAlbum = false
			let containing = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
			containing.enumerateObjects { collection, _, _ in
				if isBackedUpAlbum(collection) {
					idsPerAlbum[collection.localIdentifier, default: []].insert(asset.localIdentifier)
					albumByID[collection.localIdentifier] = collection
					inSomeAlbum = true
				}
			}
			if !inSomeAlbum {
				inNoAlbum.insert(asset.localIdentifier)
			}
		}

		// One album after the other. An album that fails does not stop the others; the first error is reported at the end.
		var firstError: Error? = nil
		for albumID in idsPerAlbum.keys.sorted() {
			if Task.isCancelled { break }
			guard let album = albumByID[albumID], let folderName = folderNames[albumID], let ids = idsPerAlbum[albumID] else {
				Log.warn("Album back-up (fast path): the album \(albumID) is not known (yet); the next full pass will look at it")
				continue
			}
			let context = AlbumExportContext(ledger: ledger, folderName: folderName, albumID: albumID, skipAssetIDs: [])
			do {
				try await self.backupAlbum(
					appState: appState,
					album: album,
					folder: folder,
					folderURL: folderURL,
					subDirectoryPath: subDirectoryPath,
					fullExport: false,
					categories: categories,
					includeAllBurstAssets: includeAllBurstAssets,
					isInBackground: isInBackground,
					onlyTheseLocalIdentifiers: ids,
					albumContext: context
				)
			}
			catch {
				if Task.isCancelled { throw error }
				Log.warn("Album back-up (fast path): the album '\(folderName)' could not be saved completely: \(error.localizedDescription)")
				if firstError == nil { firstError = error }
			}
		}

		// Photos and videos that are in no user album
		if !Task.isCancelled && !inNoAlbum.isEmpty {
			let libraries = PHAssetCollection.fetchAssetCollections(
				with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
			if let library = libraries.firstObject {
				let context = AlbumExportContext(
					ledger: ledger, folderName: AlbumFolderNaming.noAlbumFolderName,
					albumID: AlbumFolderNaming.noAlbumIdentifier, skipAssetIDs: [])
				do {
					try await self.backupAlbum(
						appState: appState,
						album: library,
						folder: folder,
						folderURL: folderURL,
						subDirectoryPath: subDirectoryPath,
						fullExport: false,
						categories: categories,
						includeAllBurstAssets: includeAllBurstAssets,
						isInBackground: isInBackground,
						onlyTheseLocalIdentifiers: inNoAlbum,
						albumContext: context
					)
				}
				catch {
					if Task.isCancelled { throw error }
					Log.warn("Album back-up (fast path): the photos in no album could not be saved completely: \(error.localizedDescription)")
					if firstError == nil { firstError = error }
				}
			}
		}

		ledger.saveNow()
		if let saveError = ledger.lastSaveError {
			Log.warn("Album back-up (fast path): the ledger could not be written: \(saveError)")
		}
		Log.info(
			"Album back-up (fast path): saved \(ledger.completedCount) files, \(ledger.adoptedCount) were there already, \(ledger.openCount) not saved, \(ledger.savedItemCount) in the ledger"
		)
		if let error = firstError {
			let message = error.localizedDescription
			DispatchQueue.main.async { self.progress = .error(message) }
			throw error
		}
		if Task.isCancelled { return .cancelled }

		let notSaved = ledger.openCount
		let addedNotSaved = ledger.openAssetIDs.intersection(addedIDs).count
		if notSaved > 0 {
			Log.warn(
				"Album back-up (fast path): \(notSaved) files could not be saved this time, \(addedNotSaved) of them of added photos. Added photos are tried again at the next run; changed old photos (for example photos that are only in iCloud) at the next full pass (an album changed, or 'Back-up new photos') or when the photo changes again."
			)
		}
		let savedCount = ledger.completedCount
		let completedDate = Date.now.timeIntervalSinceReferenceDate
		DispatchQueue.main.async {
			self.lastCompletedDate = completedDate
			self.progress = .finished(savedAssets: savedCount, purgedAssets: nil)
		}
		return PhotoChangePlanner.fastPassOutcome(openAssetIDs: ledger.openAssetIDs, inserted: addedIDs, cancelled: false)
	}

	private nonisolated func backupAlbum(
		appState: AppState,
		album: PHAssetCollection,
		folder: SushitrainFolder,
		folderURL: URL,
		subDirectoryPath: EntryPath,
		fullExport: Bool,
		categories: Set<PhotoBackupCategory>,
		includeAllBurstAssets: Bool,
		isInBackground: Bool,
		onlyTheseLocalIdentifiers: Set<String>?,
		albumContext: AlbumExportContext? = nil
	) async throws {
		// Album mode: whatever happens (an error, a cancel), write down what has been saved so far
		defer { albumContext?.ledger.saveNow() }

		// Fetch assets to export
		var cancellingError: Error? = nil
		let options: PHFetchOptions?
		if includeAllBurstAssets || onlyTheseLocalIdentifiers != nil {
			let fetchOptions = PHFetchOptions()
			fetchOptions.includeAllBurstAssets = includeAllBurstAssets
			if let ids = onlyTheseLocalIdentifiers {
				fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", Array(ids))
			}
			options = fetchOptions
		}
		else {
			options = nil
		}

		let assets = PHAsset.fetchAssets(in: album, options: options)

		// Update the progress to show the number of assets we will be exporting this time
		let count = assets.count
		DispatchQueue.main.async { self.progress = .exportingPhotos(index: 0, total: count, current: nil) }

		// Bookkeeping
		var resourceGroupsToExport: [(PHAsset, [(PHAssetResource, EntryPath)])] = []
		var videosToExport: [(PHAsset, URL, EntryPath)] = []
		var livePhotosToExport: [(PHAsset, URL, EntryPath)] = []
		var selectPaths: [EntryPath] = []
		var originalsToPurge: [PHAsset] = []
		var assetsSavedSuccessfully: [PHAsset] = []
		let structure = await self.folderStructure
		let purgeCutoffDate = await Date.now - Double.maximum(Double(self.purgeAfterDays), 0.0) * 86400.0
		let isSelective = try folder.checkedIsSelective()
		let myShortDeviceID = appState.client.shortDeviceID()
		// Album mode never deletes originals from the library and does not use AAE sidecars (a photo can be in several albums)
		let purgeEnabledSetting = await self.purgeEnabled
		let purgeEnabled = purgeEnabledSetting && albumContext == nil
		let maxAgeInterval = TimeInterval(Double(await self.maxAgeDays) * 86400.0)
		let timeZone = await self.timeZone
		let livePhotoReplaceExtension = await self.livePhotoReplaceExtension
		let includeAAESidecarsSetting = await self.includeAAESidecars
		let includeAAESidecars = includeAAESidecarsSetting && albumContext == nil

		// Enumerate assets in this album and export them (or queue them for export)
		assets.enumerateObjects { asset, index, stop in
			if Task.isCancelled {
				stop.pointee = true
				return
			}

			do {
				// Album mode: first a cheap check (no look at the photo's files) of what is still to be saved for this photo in this
				// album's folder. Nothing: skip it. The ledger knows what was saved before.
				let albumPlan: AlbumAssetPlan?
				if let context = albumContext {
					if context.skipAssetIDs.contains(asset.localIdentifier) {
						return
					}
					if let cd = asset.creationDate, maxAgeInterval > 0 && Date.now.timeIntervalSince(cd) > maxAgeInterval {
						return
					}
					albumPlan = context.plan(for: asset, categories: categories)
					if albumPlan == nil {
						return
					}
				}
				else {
					albumPlan = nil
				}

				Log.info("Asset: \(asset.originalFilename) \(asset.localIdentifier)")

				if let cd = asset.creationDate, maxAgeInterval > 0 && Date.now.timeIntervalSince(cd) > maxAgeInterval {
					// Skip, file is too old
					return
				}

				DispatchQueue.main.async {
					self.progress = .exportingPhotos(index: index, total: count, current: asset.originalFilename)
				}

				// Determine target directory path
				let assetDirectoryPath: EntryPath
				let inFolderPath: EntryPath
				if let context = albumContext, let plan = albumPlan {
					// Album mode: <path in folder>/<album name>/<file name>
					assetDirectoryPath = subDirectoryPath.appending(context.folderName, isDirectory: true)
					inFolderPath = assetDirectoryPath.appending(plan.primaryName, isDirectory: false)
				}
				else {
					assetDirectoryPath = asset.directoryPathInFolder(
						structure: structure, subdirectoryPath: subDirectoryPath, timeZone: timeZone)
					inFolderPath = asset.pathInFolder(structure: structure, subdirectoryPath: subDirectoryPath, timeZone: timeZone)
				}
				let dirInFolder = folderURL.appending(path: assetDirectoryPath.pathInFolder, directoryHint: .isDirectory)
				Log.info("- \(inFolderPath) \(dirInFolder) \(subDirectoryPath)")

				// Check if this photo was saved or deleted before (album mode does its own check below)
				if albumPlan == nil && (purgeEnabled || !fullExport) {
					if let entry = try? folder.getFileInformation(inFolderPath.pathInFolder) {
						// If purging is enabled, check if we should remove the photo from the source
						if purgeEnabled {
							if let mTime = entry.modifiedAt()?.date(), mTime < purgeCutoffDate {
								let lastModifiedByShortDeviceID = entry.modifiedByShortDeviceID()
								if lastModifiedByShortDeviceID == myShortDeviceID {
									// The photo is already saved and was last modified by this device; we can delete from source
									Log.info("Purge entry: \(inFolderPath) \(mTime) \(lastModifiedByShortDeviceID)")
									originalsToPurge.append(asset)
								}
								else {
									// The photo already exists but it was not last modified by us; do not delete from source
								}
							}
							else {
								// Could not fetch modified date or modified too recently; do not delete from source
							}
						}

						// If the photo was saved then deleted, do not try to save again (unless we are in full export)
						if !fullExport {
							if entry.isDeleted() {
								Log.info("Entry at \(inFolderPath) was deleted, not saving again")
							}
							else {
								Log.info("Entry at \(inFolderPath) exists, not saving again")
							}
							return
						}
					}
				}

				// Album mode: leave alone what is already there (saved in an earlier run, or deleted from the folder on purpose,
				// as the existing check above does for the other layouts) and remember it as done.
				var saveAlbumPrimary = true
				var saveAlbumLive = true
				if let context = albumContext, let plan = albumPlan {
					saveAlbumPrimary = plan.wantsPrimary
					saveAlbumLive = plan.wantsLive
					if !fullExport {
						if saveAlbumPrimary
							&& context.isAlreadyThere(folder: folder, folderURL: folderURL, pathInFolder: inFolderPath.pathInFolder)
						{
							Log.info("Album back-up: \(inFolderPath) is there already, not saving again")
							context.ledger.markAdopted(key: plan.primaryKey, relativePath: context.relativePath(plan.primaryName))
							saveAlbumPrimary = false
						}
						if saveAlbumLive {
							let livePathInFolder = assetDirectoryPath.appending(plan.liveName, isDirectory: false)
							if context.isAlreadyThere(folder: folder, folderURL: folderURL, pathInFolder: livePathInFolder.pathInFolder) {
								Log.info("Album back-up: \(livePathInFolder) is there already, not saving again")
								context.ledger.markAdopted(key: plan.liveKey, relativePath: context.relativePath(plan.liveName))
								saveAlbumLive = false
							}
						}
					}
					if !saveAlbumPrimary && !saveAlbumLive {
						return
					}
				}

				// Create containing directory
				try FileManager.default.createDirectory(at: dirInFolder, withIntermediateDirectories: true)

				// Save asset if it doesn't exist already locally
				let fileURL = folderURL.appending(path: inFolderPath.pathInFolder, directoryHint: .notDirectory)
				if saveAlbumPrimary && (!FileManager.default.fileExists(atPath: fileURL.path) || fullExport) {
					// Album mode: this file counts as saved only after it has been written completely
					if let context = albumContext, let plan = albumPlan {
						context.ledger.expect(
							pathInFolder: inFolderPath.pathInFolder, key: plan.primaryKey,
							relativePath: context.relativePath(plan.primaryName))
					}
					let resources = PHAssetResource.assetResources(for: asset)
					let adjustment = resources.first { $0.type == .adjustmentData }
					var exportsPhotoResources = false
					if includeAAESidecars, let adjustment {
						let sidecarPath = EntryPath(
							(inFolderPath.pathInFolder as NSString).deletingPathExtension + ".AAE", isDirectory: false)
						if asset.mediaType == .image && categories.contains(.photo) {
							guard let original = resources.first(where: { $0.type == .photo }),
								let edited = resources.first(where: { $0.type == .fullSizePhoto })
							else {
								throw CocoaError(.fileReadUnknown)
							}
							// Preserve the edited resource's format, but associate its name with the original.
							let stem = (asset.originalFilename as NSString).deletingPathExtension
							let editedStem = stem.hasPrefix("IMG_") ? "IMG_E" + String(stem.dropFirst(4)) : stem + "_edited"
							let editedExtension = (edited.originalFilename as NSString).pathExtension
							let originalName = asset.fileNameInFolder(structure: structure)
							let prefix = String(originalName.dropLast(asset.originalFilename.count))
							let editedPath = assetDirectoryPath.appending(
								prefix + editedStem + "." + editedExtension, isDirectory: false)
							// Publish the original last: its presence is the incremental export completion marker.
							resourceGroupsToExport.append(
								(asset, [(adjustment, sidecarPath), (edited, editedPath), (original, inFolderPath)]))
							exportsPhotoResources = true
						}
						else if asset.mediaType == .video && categories.contains(.video) {
							resourceGroupsToExport.append((asset, [(adjustment, sidecarPath)]))
						}
					}
					// If a video: queue video export session
					if asset.mediaType == .video {
						if categories.contains(.video) {
							Log.info("Requesting video export session for \(asset.originalFilename)")
							videosToExport.append((asset, fileURL, inFolderPath))
						}
					}
					else {
						if categories.contains(.photo) && !exportsPhotoResources {
							// Save image
							let options = PHImageRequestOptions()
							options.isSynchronous = true
							options.resizeMode = .none
							options.deliveryMode = .highQualityFormat
							options.isNetworkAccessAllowed = false
							options.allowSecondaryDegradedImage = false
							options.version = .current

							PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
								if let data = data {
									do {
										if albumContext == nil {
											try data.write(to: fileURL)
										}
										else {
											// Album mode: temporary file first, real name only when complete
											let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
											try data.write(to: temporary)
											try AlbumFolderNaming.moveIntoPlace(temporary, to: fileURL)
										}
										selectPaths.append(inFolderPath)

										// Set file creation and modified date to photo creation date. The modified date is what is synced
										if let cd = asset.creationDate {
											try FileManager.default.setAttributes(
												[FileAttributeKey.creationDate: cd, FileAttributeKey.modificationDate: cd],
												ofItemAtPath: fileURL.path(percentEncoded: false))
										}

										assetsSavedSuccessfully.append(asset)

										// Album mode: the photo is written completely, now its key goes into the ledger
										albumContext?.ledger.completed(pathInFolder: inFolderPath.pathInFolder)
									}
									catch {
										Log.warn("Image data request failed: \(error.localizedDescription) ")
										cancellingError = error
									}
								}
								else {
									if let inICloud = info?[PHImageResultIsInCloudKey] as? NSNumber, inICloud.boolValue {
										Log.warn("Asset is in iCloud and therefore ignored")
									}
									else if let error = info?[PHImageErrorKey] as? NSError {
										Log.warn("Image data request failed: PHImageError \(error.localizedDescription) ")
									}
								}
							}
						}
					}
				}

				// If the image is a live photo, queue the live photo for saving as well
				if asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive) && categories.contains(.livePhoto)
					&& saveAlbumLive
				{
					let liveInFolderPath: EntryPath
					let liveDirectoryURL: URL
					if let plan = albumPlan {
						// Album mode: the video sits next to the picture (IMG_0001.HEIC + IMG_0001.MOV), no "Live" folder
						liveInFolderPath = assetDirectoryPath.appending(plan.liveName, isDirectory: false)
						liveDirectoryURL = dirInFolder
					}
					else {
						liveInFolderPath = asset.livePhotoPathInFolder(
							structure: structure, subdirectoryPath: subDirectoryPath, timeZone: timeZone,
							replaceExtension: livePhotoReplaceExtension)
						liveDirectoryURL = folderURL.appending(
							path: asset.livePhotoDirectoryPathInFolder(
								structure: structure, subdirectoryPath: subDirectoryPath, timeZone: timeZone
							)
							.pathInFolder,
							directoryHint: .isDirectory)
					}
					try FileManager.default.createDirectory(at: liveDirectoryURL, withIntermediateDirectories: true)
					let liveFileURL = folderURL.appending(path: liveInFolderPath.pathInFolder, directoryHint: .notDirectory)
					Log.info("Found live photo \(asset.originalFilename) \(liveInFolderPath)")

					if !FileManager.default.fileExists(atPath: liveFileURL.path) {
						// Album mode: the video counts as saved only after it has been written completely
						if let context = albumContext, let plan = albumPlan {
							context.ledger.expect(
								pathInFolder: liveInFolderPath.pathInFolder, key: plan.liveKey,
								relativePath: context.relativePath(plan.liveName))
						}
						livePhotosToExport.append((asset, liveFileURL, liveInFolderPath))
					}
				}
			}
			catch {
				cancellingError = error
				stop.pointee = true
			}
		}

		// Select paths a first time for photos (video export may take too long)
		// (album mode: only when there is something to select, so that albums without news cost nothing)
		if isSelective && (albumContext == nil || !selectPaths.isEmpty) {
			Log.info("Selecting paths (photos only)")
			#if os(iOS)
				Log.info("Background time remaining: \(await UIApplication.shared.backgroundTimeRemaining))")
			#endif

			DispatchQueue.main.async { self.progress = .selecting }

			let stList = SushitrainNewListOfStrings()!
			for path in selectPaths {
				stList.append(path.pathInFolder)
			}

			do {
				try folder.setLocalPathsExplicitlySelected(stList)
			}
			catch {
				Log.warn("Could not select files: \(error.localizedDescription)")
			}
		}

		// Report error
		if let ce = cancellingError {
			DispatchQueue.main.async { self.progress = .error(ce.localizedDescription) }
			throw ce
		}

		// Export videos
		if categories.contains(.video) {
			let videoCount = videosToExport.count
			Log.info("Starting video exports for \(videoCount) videos")
			#if os(iOS)
				Log.info("Background time remaining: \(await UIApplication.shared.backgroundTimeRemaining)")
			#endif

			DispatchQueue.main.async { self.progress = .exportingVideos(index: 0, total: videoCount, current: nil) }

			for (idx, (asset, fileURL, selectPath)) in videosToExport.enumerated() {
				if Task.isCancelled { break }

				DispatchQueue.main.async { self.progress = .exportingVideos(index: idx, total: videoCount, current: nil) }

				// Album mode: the video is written to a temporary file first and moved to its real name when it is complete, so a
				// crash never leaves half a video under its real name (a later run would take it for a finished one)
				let videoWriteURL =
					albumContext == nil ? fileURL : FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

				do {
					try await withCheckedThrowingContinuation { resolve in
						Log.info("Copying original video resource for \(asset.originalFilename)")

						guard let resource = asset.primaryResource else {
							Log.warn("No primary resource for video \(asset.originalFilename)")
							resolve.resume()
							return
						}

						PHAssetResourceManager.default().writeData(for: resource, toFile: videoWriteURL, options: nil) { error in
							if let error = error {
								Log.warn("Failed to save original video for \(asset.originalFilename): \(error.localizedDescription)")
								resolve.resume(throwing: error)
							}
							else {
								Log.info("Copied original video resource for \(asset.originalFilename)")
								resolve.resume()
							}
						}
					}

					// Album mode: complete, so now it gets its real name
					if albumContext != nil && FileManager.default.fileExists(atPath: videoWriteURL.path) {
						try AlbumFolderNaming.moveIntoPlace(videoWriteURL, to: fileURL)
					}
				}
				catch {
					Log.warn("Failed to save original video for \(asset.originalFilename): \(error.localizedDescription)")
					continue
				}

				selectPaths.append(selectPath)
				assetsSavedSuccessfully.append(asset)

				// Album mode: the video is in its place, now its key goes into the ledger
				if FileManager.default.fileExists(atPath: fileURL.path) {
					albumContext?.ledger.completed(pathInFolder: selectPath.pathInFolder)
				}
			}
		}

		// Export live photos
		if categories.contains(.livePhoto) {
			Log.info("Exporting live photos")
			#if os(iOS)
				Log.info("Background time remaining: \(await UIApplication.shared.backgroundTimeRemaining))")
			#endif

			let liveCount = livePhotosToExport.count
			DispatchQueue.main.async { self.progress = .exportingLivePhotos(index: 0, total: liveCount, current: nil) }
			for (idx, (asset, destURL, selectPath)) in livePhotosToExport.enumerated() {
				if Task.isCancelled { break }
				Log.info("Exporting live photo \(asset.originalFilename) \(selectPath)")

				// Album mode: written to a temporary file first, moved to its real name when complete (see the videos above)
				let liveWriteURL =
					albumContext == nil ? destURL : FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

				do {
					try await withCheckedThrowingContinuation { resolve in
						// Export live photo
						let options = PHLivePhotoRequestOptions()
						options.deliveryMode = .highQualityFormat
						var found = false
						PHImageManager.default().requestLivePhoto(
							for: asset, targetSize: CGSize(width: 1920, height: 1080), contentMode: PHImageContentMode.default,
							options: options
						) { livePhoto, info in
							if found {
								// The callback can be called twice
								return
							}
							found = true

							guard let livePhoto = livePhoto else {
								Log.warn("Did not receive live photo for \(asset.originalFilename)")
								resolve.resume()
								return
							}
							let assetResources = PHAssetResource.assetResources(for: livePhoto)
							guard let videoResource = assetResources.first(where: { $0.type == .pairedVideo }) else {
								Log.warn("Could not find paired video resource for \(asset.originalFilename) \(assetResources)")
								resolve.resume()
								return
							}

							PHAssetResourceManager.default().writeData(for: videoResource, toFile: liveWriteURL, options: nil) { error in
								if let error = error {
									resolve.resume(throwing: error)
								}
								else {
									resolve.resume()
								}
							}
						}
					}

					// Album mode: complete, so now it gets its real name
					if albumContext != nil && FileManager.default.fileExists(atPath: liveWriteURL.path) {
						try AlbumFolderNaming.moveIntoPlace(liveWriteURL, to: destURL)
					}

					selectPaths.append(selectPath)
					assetsSavedSuccessfully.append(asset)

					// Album mode: the live photo's video is in its place, now its key goes into the ledger
					if FileManager.default.fileExists(atPath: destURL.path) {
						albumContext?.ledger.completed(pathInFolder: selectPath.pathInFolder)
					}

					if let cd = asset.creationDate {
						try FileManager.default.setAttributes(
							[FileAttributeKey.creationDate: cd, FileAttributeKey.modificationDate: cd],
							ofItemAtPath: destURL.path(percentEncoded: false))
					}
				}
				catch {
					Log.warn("Failed to save \(destURL): \(error.localizedDescription)")
				}

				DispatchQueue.main.async { self.progress = .exportingLivePhotos(index: idx, total: liveCount, current: nil) }
			}
		}

		// Finish resource groups before tagging or purging originals.
		for (asset, resources) in resourceGroupsToExport {
			for (resource, path) in resources {
				let destination = folderURL.appending(path: path.pathInFolder, directoryHint: .notDirectory)
				do {
					try Task.checkCancellation()
					try FileManager.default.createDirectory(
						at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
					let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
					defer { try? FileManager.default.removeItem(at: temporaryURL) }
					let options = PHAssetResourceRequestOptions()
					options.isNetworkAccessAllowed = false
					try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
						PHAssetResourceManager.default().writeData(for: resource, toFile: temporaryURL, options: options) { error in
							if let error {
								continuation.resume(throwing: error)
							}
							else {
								continuation.resume()
							}
						}
					}
					try Data(contentsOf: temporaryURL).write(to: destination, options: .atomic)
					if let cd = asset.creationDate {
						try FileManager.default.setAttributes(
							[.creationDate: cd, .modificationDate: cd], ofItemAtPath: destination.path)
					}
					if isSelective {
						let paths = SushitrainNewListOfStrings()!
						paths.append(path.pathInFolder)
						try folder.setLocalPathsExplicitlySelected(paths)
					}
					selectPaths.append(path)
				}
				catch {
					DispatchQueue.main.async { self.progress = .error(error.localizedDescription) }
					throw error
				}
			}
			if asset.mediaType == .image { assetsSavedSuccessfully.append(asset) }
		}

		// Select paths
		if isSelective && (albumContext == nil || !selectPaths.isEmpty) {
			Log.info("Selecting paths")
			#if os(iOS)
				Log.info("Background time remaining: \(await UIApplication.shared.backgroundTimeRemaining))")
			#endif

			DispatchQueue.main.async { self.progress = .selecting }

			let stList = SushitrainNewListOfStrings()!
			for path in selectPaths {
				stList.append(path.pathInFolder)
			}

			do {
				try folder.setLocalPathsExplicitlySelected(stList)
			}
			catch {
				Log.warn("Could not select files: \(error.localizedDescription)")
			}
		}

		// Tag saved items (not in album mode: the "saved" album would become a folder of its own)
		if albumContext == nil, await !savedAlbumID.isEmpty && !assetsSavedSuccessfully.isEmpty {
			Log.info("Tagging \(assetsSavedSuccessfully.count) saved items")
			if let savedAlbum = await PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [savedAlbumID], options: nil)
				.firstObject
			{
				let assets = PHAsset.fetchAssets(
					withLocalIdentifiers: assetsSavedSuccessfully.map { $0.localIdentifier }, options: nil)
				try? await PHPhotoLibrary.shared().performChanges {
					if let phac = PHAssetCollectionChangeRequest(for: savedAlbum) {
						phac.addAssets(assets)
					}
					else {
						Log.warn("Cannot add asset, PHAssetCollectionChangeRequest is nil!")
					}
				}
			}
		}

		// Purge
		var purgedAssetCount = 0
		if !isInBackground && purgeEnabled && !originalsToPurge.isEmpty {
			Log.info("Purge \(originalsToPurge.count) originals")
			DispatchQueue.main.async { self.progress = .purging }
			let assets = PHAsset.fetchAssets(withLocalIdentifiers: originalsToPurge.map { $0.localIdentifier }, options: nil)

			// this could fail in the background
			try? await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
			purgedAssetCount = assets.count
		}

		// Write 'last completed' date (album mode: backupEveryAlbum does this once, after the last album)
		let purgedAssetCountLet = purgedAssetCount
		let completedDate = Date.now.timeIntervalSinceReferenceDate
		if albumContext == nil {
			DispatchQueue.main.async {
				self.lastCompletedDate = completedDate
				self.progress = .finished(savedAssets: assets.count, purgedAssets: purgedAssetCountLet)
			}
		}
		Log.info("Photo back-up done")

		#if os(iOS)
			Log.info("Background time remaining: \(await UIApplication.shared.backgroundTimeRemaining))")
		#endif
	}
}

extension PHAsset {
	fileprivate var primaryResource: PHAssetResource? {
		let types: Set<PHAssetResourceType>

		switch mediaType {
		case .video: types = [.video, .fullSizeVideo]
		case .image: types = [.photo, .fullSizePhoto]
		case .audio: types = [.audio]
		case .unknown: types = []
		@unknown default: types = []
		}

		let resources = PHAssetResource.assetResources(for: self)
		let resource = resources.first { types.contains($0.type) }

		return resource ?? resources.first
	}

	var originalFilename: String {
		guard let result = primaryResource else { return "file" }
		return result.originalFilename.replacingOccurrences(of: "/", with: "_")
	}

	fileprivate func directoryPathInFolder(
		structure: PhotoBackupFolderStructure, subdirectoryPath: EntryPath, timeZone: PhotoBackupTimeZone
	) -> EntryPath {
		var path = subdirectoryPath
		for c in self.subdirectoriesInFolder(structure: structure, timeZone: timeZone) {
			path = path.appending(c, isDirectory: true)
		}
		return path
	}

	func dateFormatter(timeZone: PhotoBackupTimeZone) -> DateFormatter {
		let df = DateFormatter()
		switch timeZone {
		case .current:
			df.timeZone = .current
		case .specific(let tz):
			df.timeZone = TimeZone(identifier: tz)
		}
		return df
	}

	func subdirectoriesInFolder(structure: PhotoBackupFolderStructure, timeZone: PhotoBackupTimeZone) -> [String] {
		var components: [String] = []

		switch structure {
		case .byDate, .byDateAndType:
			if let creationDate = self.creationDate {
				let dateFormatter = self.dateFormatter(timeZone: timeZone)
				dateFormatter.dateFormat = "yyyy-MM-dd"
				let dateString = dateFormatter.string(from: creationDate)
				components.append(dateString)
			}

		case .byDateComponent, .byDateComponentAndType, .byYear, .byYearMonth, .byYearAndType, .byYearMonthAndType,
			.byYearDashMonth, .byYearDashMonthAndType:
			if let creationDate = self.creationDate {
				let dateComponents = structure.dateComponentsForPath
				let dateFormatter = self.dateFormatter(timeZone: timeZone)
				for dateComponent in dateComponents {
					dateFormatter.dateFormat = dateComponent
					let dateString = dateFormatter.string(from: creationDate)
					components.append(dateString)
				}
			}

		case .singleFolder, .byType, .singleFolderDatePrefixed, .byAlbumName: break
		}

		// Postfix media type
		switch structure {
		case .byDateAndType, .byType, .byDateComponentAndType, .byYearAndType, .byYearMonthAndType, .byYearDashMonthAndType:
			if self.mediaType == .video {
				components.append("Video")
			}
		case .byDate, .singleFolder, .singleFolderDatePrefixed, .byDateComponent, .byYear, .byYearMonth, .byYearDashMonth,
			.byAlbumName:
			break
		}

		return components
	}

	fileprivate func livePhotoDirectoryPathInFolder(
		structure: PhotoBackupFolderStructure, subdirectoryPath: EntryPath, timeZone: PhotoBackupTimeZone
	)
		-> EntryPath
	{
		var path = self.directoryPathInFolder(structure: structure, subdirectoryPath: subdirectoryPath, timeZone: timeZone)
		switch structure {
		case .byDateAndType, .byType, .byDateComponentAndType, .byYearAndType, .byYearMonthAndType, .byYearDashMonthAndType:
			path = path.appending("Live", isDirectory: true)
		case .byDate, .singleFolder, .singleFolderDatePrefixed, .byDateComponent, .byYear, .byYearMonth, .byYearDashMonth,
			.byAlbumName:
			break
		}
		return path
	}

	fileprivate func livePhotoPathInFolder(
		structure: PhotoBackupFolderStructure, subdirectoryPath: EntryPath, timeZone: PhotoBackupTimeZone,
		replaceExtension: Bool
	) -> EntryPath {
		var fileName = self.fileNameInFolder(structure: structure)
		if replaceExtension {
			// Replace file extension: IMG_1337.MOV
			fileName = (fileName as NSString).deletingPathExtension + ".MOV"
		}
		else {
			// Append file extension: IMG_1337.HEIC.MOV
			fileName += ".MOV"
		}

		return self.livePhotoDirectoryPathInFolder(
			structure: structure, subdirectoryPath: subdirectoryPath, timeZone: timeZone
		)
		.appending(fileName, isDirectory: false)
	}

	func fileNameInFolder(structure: PhotoBackupFolderStructure) -> String {
		switch structure {
		case .byDate, .byDateAndType, .byDateComponent, .byDateComponentAndType, .singleFolder, .byType, .byYear,
			.byYearMonth, .byYearAndType, .byYearMonthAndType, .byYearDashMonth, .byYearDashMonthAndType, .byAlbumName:
			return self.originalFilename

		case .singleFolderDatePrefixed:
			if let creationDate = self.creationDate {
				let dateFormatter = DateFormatter()
				dateFormatter.dateFormat = "yyyy-MM-dd"
				let dateString = dateFormatter.string(from: creationDate)
				return "\(dateString)_\(self.originalFilename)"
			}
			return self.originalFilename
		}
	}

	fileprivate func pathInFolder(
		structure: PhotoBackupFolderStructure, subdirectoryPath: EntryPath, timeZone: PhotoBackupTimeZone
	) -> EntryPath {
		return self.directoryPathInFolder(structure: structure, subdirectoryPath: subdirectoryPath, timeZone: timeZone)
			.appending(self.fileNameInFolder(structure: structure), isDirectory: false)
	}
}

private struct EntryPath {
	let url: URL

	init(_ path: String = "", isDirectory: Bool) {
		self.url = URL(filePath: "/" + path, directoryHint: isDirectory ? .isDirectory : .notDirectory)
	}

	private init(url: URL) {
		self.url = url
	}

	func appending(_ p: String, isDirectory: Bool) -> EntryPath {
		return EntryPath(url: self.url.appendingPathComponent(p, isDirectory: isDirectory))
	}

	// Absolute path, not starting with a leading '/' (as accepted by SushitrainEntry.getFileInformation).
	var pathInFolder: String {
		return self.url.path(percentEncoded: false).withoutStartingSlash
	}
}

// MARK: - Album mode ("Every album"): helpers. The naming rules and the ledger are in AlbumFolderNaming.swift (pure Swift).

/// Album mode: where one album (or "No album") is saved in this run, and what is already saved.
private struct AlbumExportContext: Sendable {
	let ledger: AlbumExportLedger
	/// The folder inside "Path in folder" that this album is saved in
	let folderName: String
	/// Photos' local identifier of the album (AlbumFolderNaming.noAlbumIdentifier for "No album")
	let albumID: String
	/// Photos that must be left out: for "No album" all photos that are in a user album
	let skipAssetIDs: Set<String>

	/// The path of a file as the ledger keeps it: "Holiday 2024/IMG_0001.HEIC"
	func relativePath(_ fileName: String) -> String {
		return folderName + "/" + fileName
	}

	/// Whether a file is there already: Syncthing knows it (also when it was deleted from the folder on purpose), or it is on the disk
	func isAlreadyThere(folder: SushitrainFolder, folderURL: URL, pathInFolder: String) -> Bool {
		if (try? folder.getFileInformation(pathInFolder)) != nil {
			return true
		}
		let url = folderURL.appending(path: pathInFolder, directoryHint: .notDirectory)
		return FileManager.default.fileExists(atPath: url.path)
	}

	/// What still has to be saved for this photo or video in this album's folder; nil = nothing (it is all in the ledger).
	/// The rules are in AlbumExportLedger.plan (pure Swift, covered by the CI self-test).
	func plan(for asset: PHAsset, categories: Set<PhotoBackupCategory>) -> AlbumAssetPlan? {
		return ledger.plan(
			assetID: asset.localIdentifier,
			albumID: albumID,
			folder: folderName,
			isVideo: asset.mediaType == .video,
			isLivePhoto: asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive),
			saveImages: categories.contains(.photo),
			saveVideos: categories.contains(.video),
			saveLivePhotos: categories.contains(.livePhoto),
			originalName: { asset.originalFilename }
		)
	}
}

/// Album mode: the albums the user made, and the ones that came from a computer or an import. Not the smart albums (Favorites,
/// Screenshots, Videos, Recents, ...), not iCloud Shared Albums and not My Photo Stream.
private func userAlbumCollections() -> [PHAssetCollection] {
	var result: [PHAssetCollection] = []
	let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
	collections.enumerateObjects { collection, _, _ in
		if isBackedUpAlbum(collection) {
			result.append(collection)
		}
	}
	return result
}

/// Album mode: is this collection one of the albums that get a folder of their own? The same rule is used to list the albums and to
/// find the albums a changed photo is in (the fast path): an album the user made, or one that came from a computer or an import. Not a
/// smart album, not an iCloud Shared Album and not My Photo Stream.
private func isBackedUpAlbum(_ collection: PHAssetCollection) -> Bool {
	if collection.assetCollectionType != .album {
		return false
	}
	switch collection.assetCollectionSubtype {
	case .albumRegular, .albumImported, .albumSyncedEvent, .albumSyncedFaces, .albumSyncedAlbum:
		return true
	default:
		return false
	}
}

/// Album mode (fast path): of the collections the library reported as changed, the ones that matter to the back-up: the albums that get
/// a folder (see isBackedUpAlbum) and identifiers that cannot be found any more (a deleted album, or one that came and went again).
/// A collection that exists and is not such an album (Recents and the other smart albums, an iCloud Shared Album, ...) does not matter.
private func changedAlbumsThatMatter(among identifiers: Set<String>) -> Set<String> {
	if identifiers.isEmpty {
		return []
	}
	var found = Set<String>()
	var matter = Set<String>()
	let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(identifiers), options: nil)
	collections.enumerateObjects { collection, _, _ in
		found.insert(collection.localIdentifier)
		if isBackedUpAlbum(collection) {
			matter.insert(collection.localIdentifier)
		}
	}
	for identifier in identifiers where !found.contains(identifier) {
		matter.insert(identifier)
	}
	return matter
}

/// Album mode: where the ledger of one destination lives: the app's Application Support folder
private func albumLedgerFileURL(destination: String) throws -> URL {
	let support = try FileManager.default.url(
		for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
	return support.appendingPathComponent(AlbumExportLedger.fileName(forDestination: destination))
}

extension SushitrainFolder {
	// Whether this folder can be used as a photo backup destination folder
	var isSuitablePhotoBackupDestination: Bool {
		return self.isRegularFolder && self.folderType() != SushitrainFolderTypeReceiveOnly && self.exists()
	}
}

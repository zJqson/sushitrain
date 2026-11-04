// Copyright (C) 2026 Jason (personal fork of Synctrain / Sushitrain by Tommy van der Vorst)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
#if os(iOS)
	import CoreLocation
	import Photos
	import SwiftUI
	@preconcurrency import SushitrainCore

	/// Keeps the app running in the background by holding an iOS location session at the lowest accuracy.
	///
	/// The position itself is never read, stored, logged or sent anywhere: iOS only needs to see that the app is
	/// "using" location, and then it stops freezing the app when it goes to the background. Event-driven: there
	/// are no timers or polling in this class.
	///
	/// Pieces (see Apple docs, CLLocationManager and CLBackgroundActivitySession):
	/// - CLBackgroundActivitySession (iOS 17+): the modern way to keep an app "in use" in the background.
	///   It must be created while the app is in the foreground, held in a property, and re-created straight
	///   after a launch in the background.
	/// - startUpdatingLocation() with allowsBackgroundLocationUpdates = true, the lowest accuracy, a large
	///   distance filter and no automatic pausing.
	/// - startMonitoringSignificantLocationChanges(): lets iOS relaunch the app if iOS ended it (not after the
	///   user swipes the app away, and only after the phone moved about 500 m).
	@MainActor final class BackgroundKeepAlive: NSObject, ObservableObject {
		/// The system permission state, mirrored here so the settings screen can show it.
		@Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
		/// True while the location session is held (so the app is told to stay awake instead of suspending).
		@Published private(set) var isRunning = false
		/// When iOS last woke us with a location event (no coordinates are kept).
		@Published private(set) var lastLocationEvent: Date? = nil

		private let manager: CLLocationManager
		private var activitySession: CLBackgroundActivitySession? = nil
		private unowned let appState: AppState

		init(appState: AppState) {
			self.manager = CLLocationManager()
			self.appState = appState
			super.init()
			// Must happen at every launch, including launches in the background, so iOS can deliver events
			manager.delegate = self
			authorizationStatus = manager.authorizationStatus
		}

		/// Start or stop so that the running state matches the setting and the permission. Safe to call often.
		func apply() {
			let wanted = appState.userSettings.keepRunningInBackground
			authorizationStatus = manager.authorizationStatus
			Log.info(
				"Keep-alive: setting=\(wanted) permission=\(Self.describe(authorizationStatus)) running=\(isRunning) autoPhotoBackup=\(appState.photoBackup.automatic) blockCellular=\(appState.userSettings.disableDevicesOnCellular) blockMetered=\(appState.userSettings.disableDevicesOnMetered)"
			)
			guard wanted else {
				stop(reason: "the setting is off")
				return
			}

			switch authorizationStatus {
			case .notDetermined:
				// Ask only while someone is looking at the app: a launch in the background must not wait on a prompt
				if UIApplication.shared.applicationState == .active {
					Log.info("Keep-alive: asking for 'While Using' permission first")
					manager.requestWhenInUseAuthorization()
				}

			case .authorizedWhenInUse:
				// Works already (blue indicator, needs a launch from the foreground); 'Always' is better because
				// iOS can then relaunch the app. Per Apple the Always prompt appears once; later calls do nothing.
				start()
				if UIApplication.shared.applicationState == .active {
					Log.info("Keep-alive: asking for 'Always' permission")
					manager.requestAlwaysAuthorization()
				}

			case .authorizedAlways:
				start()

			case .denied, .restricted:
				stop(reason: "location permission is \(Self.describe(authorizationStatus))")

			@unknown default:
				stop(reason: "unknown location permission state")
			}
		}

		private static var infoPlistAllowsBackgroundLocation: Bool {
			let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
			return modes.contains("location")
		}

		private func start() {
			guard !isRunning else { return }
			// Apple: setting allowsBackgroundLocationUpdates without 'location' in UIBackgroundModes terminates the app
			guard Self.infoPlistAllowsBackgroundLocation else {
				Log.warn("Keep-alive: 'location' is missing from UIBackgroundModes in Info.plist; not starting")
				return
			}

			manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers  // lowest level, power-friendly (Apple's advice)
			manager.distanceFilter = 3000  // metres; we do not want position updates, only the session
			manager.pausesLocationUpdatesAutomatically = false
			manager.allowsBackgroundLocationUpdates = true
			manager.showsBackgroundLocationIndicator = true  // be open about it (matters for 'Always' only)

			// Hold it in a property: letting it deallocate ends the session
			activitySession = CLBackgroundActivitySession()
			manager.startUpdatingLocation()
			manager.startMonitoringSignificantLocationChanges()
			isRunning = true
			Log.info("Keep-alive: started (lowest accuracy, no position is read or stored)")
		}

		private func stop(reason: String) {
			guard isRunning else { return }
			manager.stopUpdatingLocation()
			manager.stopMonitoringSignificantLocationChanges()
			manager.allowsBackgroundLocationUpdates = false
			activitySession?.invalidate()
			activitySession = nil
			isRunning = false
			Log.info("Keep-alive: stopped because \(reason)")
		}

		fileprivate func permissionChanged() {
			let before = authorizationStatus
			authorizationStatus = manager.authorizationStatus
			Log.info("Keep-alive: permission changed from \(Self.describe(before)) to \(Self.describe(authorizationStatus))")
			apply()
		}

		fileprivate func locationEventReceived() {
			// Deliberately cheap: do not touch the coordinates (an expensive handler can get the app suspended)
			lastLocationEvent = Date.now
			Log.info("Keep-alive: iOS woke us with a location event (position not read)")
			// A wake-up is a good moment to look for photos that arrived while we were frozen
			appState.autoPhotoBackup.schedule(reason: "location event")
		}

		fileprivate func locationFailed(_ message: String) {
			Log.warn("Keep-alive: location manager error: \(message)")
		}

		static func describe(_ status: CLAuthorizationStatus) -> String {
			switch status {
			case .notDetermined: return "not asked yet"
			case .restricted: return "restricted"
			case .denied: return "denied"
			case .authorizedAlways: return "Always"
			case .authorizedWhenInUse: return "While Using"
			@unknown default: return "unknown"
			}
		}

		var statusText: String {
			var text = isRunning ? String(localized: "Keeping the app running.") : String(localized: "Not running.")
			text += " " + String(localized: "Location permission: \(Self.describe(authorizationStatus)).")
			if authorizationStatus == .authorizedWhenInUse {
				text += " " + String(localized: "Choose \"Always\" in the Settings app so iOS can restart the app if it stops.")
			}
			if let last = lastLocationEvent {
				text += " " + String(localized: "Last wake-up from iOS: \(last.formatted(date: .abbreviated, time: .shortened)).")
			}
			return text
		}
	}

	// The delegate methods are called by Core Location on the thread of the manager (the main thread here).
	// They are 'nonisolated' and hop to the main actor, which is valid whether or not the SDK marks the protocol @MainActor.
	extension BackgroundKeepAlive: CLLocationManagerDelegate {
		nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
			Task { @MainActor in self.permissionChanged() }
		}

		nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
			Task { @MainActor in self.locationEventReceived() }
		}

		nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
			let message = error.localizedDescription
			Task { @MainActor in self.locationFailed(message) }
		}
	}

	/// Starts the existing photo back-up by itself when new photos arrive in the photo library.
	///
	/// Event-driven: it listens to PHPhotoLibraryChangeObserver and runs once after a quiet period (a single
	/// one-shot wait that is cancelled and restarted by every new change; there is no repeating timer and no
	/// polling). The existing PhotoBackup.backup() already compares Photos' persistent change token, so a call
	/// with nothing new returns at once; in album mode it also finds out WHAT changed and looks at a new photo only
	/// (the "fast path", see PhotoChangePlan.swift). isInBackground is always true, which keeps PhotoBackup from ever
	/// deleting originals ("Remove saved photos from source" only runs from the foreground button).
	///
	/// The wait is the setting photoBackupQuietSeconds (PhotoBackup.quietSeconds: default 8 s, 3...120 s).
	@MainActor final class AutoPhotoBackup: NSObject, PHPhotoLibraryChangeObserver {
		private unowned let appState: AppState
		private var registered = false
		private var pending: Task<Void, Never>? = nil

		init(appState: AppState) {
			self.appState = appState
			super.init()
		}

		/// Register for photo library changes once the photo permission allows it. Safe to call often.
		func refreshRegistration() {
			guard !registered else { return }
			guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
			registered = true
			// Registering can take a while (see PhotoFSLibraryObserver), so keep it off the main thread
			let observer = self
			Task.detached { PHPhotoLibrary.shared().register(observer) }
			Log.info("Auto photo backup: watching the photo library")
		}

		nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
			Task { @MainActor in self.schedule(reason: "photo library changed") }
		}

		/// Ask for a back-up run after a quiet period. Repeated calls restart the wait, so a burst of photos, or a Live Photo
		/// that Photos is still finishing, is saved only after things have been quiet for the whole wait.
		func schedule(reason: String) {
			guard appState.photoBackup.automatic else { return }
			let quietPeriod = Duration.seconds(appState.photoBackup.quietSeconds)
			pending?.cancel()
			pending = Task { [weak self] in
				try? await Task.sleep(for: quietPeriod)
				if Task.isCancelled { return }
				self?.run(reason: reason)
			}
		}

		private func run(reason: String) {
			let photoBackup = appState.photoBackup
			guard photoBackup.automatic, photoBackup.isReady else { return }
			guard appState.startupState == .started else {
				Log.info("Auto photo backup: the app is still starting (\(reason)); the start-up run will catch up")
				return
			}

			if photoBackup.isBackingUp {
				// A run is going; its change token may be older than the photo that just arrived. Go again when it ends.
				if let running = photoBackup.photoBackupTask {
					Task { [weak self] in
						_ = try? await running.value
						self?.schedule(reason: "after the previous run ended")
					}
				}
				return
			}

			Log.info("Auto photo backup: starting (\(reason))")
			photoBackup.backup(appState: appState, fullExport: false, isInBackground: true)
		}
	}

	/// The block for the background settings screen: the switch, what the system says, and a way to open Settings.
	struct BackgroundKeepAliveSection: View {
		@ObservedObject var keepAlive: BackgroundKeepAlive
		@ObservedObject var userSettings: AppUserSettings
		@Environment(\.openURL) private var openURL

		var body: some View {
			Section {
				Toggle("Keep running in the background", isOn: userSettings.$keepRunningInBackground)
					.onChange(of: userSettings.keepRunningInBackground) { _, _ in keepAlive.apply() }

				Text(keepAlive.statusText).font(.footnote).foregroundStyle(.secondary)

				if userSettings.keepRunningInBackground && keepAlive.authorizationStatus != .authorizedAlways {
					Button("Open Settings", systemImage: "gear") {
						if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
					}
				}
			} header: {
				Text("Keep running")
			} footer: {
				Text(
					"iOS freezes apps that are in the background. With this switch on, the app uses the lowest-accuracy location service only to stop iOS from freezing it, so new photos are backed up by themselves. Your position is never stored, logged or sent anywhere. iOS shows a blue indicator while this runs, and it uses more battery."
				)
			}
		}
	}
#endif

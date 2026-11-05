// Copyright (C) 2026 Jason (personal fork of Synctrain / Sushitrain by Tommy van der Vorst)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
#if os(iOS)
	import AVFoundation
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
		/// The second keeper (inaudible sound), see SilentAudioKeeper
		let audio = SilentAudioKeeper()

		/// True while anything keeps the app running in the background: the location session or the silent sound.
		var isKeepingAlive: Bool { return isRunning || audio.isRunning }

		init(appState: AppState) {
			self.manager = CLLocationManager()
			self.appState = appState
			super.init()
			// Must happen at every launch, including launches in the background, so iOS can deliver events
			manager.delegate = self
			authorizationStatus = manager.authorizationStatus
			audio.onChange = { [weak self] in self?.objectWillChange.send() }
		}

		/// Start or stop so that the running state matches the setting and the permission. Safe to call often.
		func apply() {
			let wanted = appState.userSettings.keepRunningInBackground
			authorizationStatus = manager.authorizationStatus
			Log.info(
				"Keep-alive: setting=\(wanted) permission=\(Self.describe(authorizationStatus)) running=\(isRunning) autoPhotoBackup=\(appState.photoBackup.automatic) blockCellular=\(appState.userSettings.disableDevicesOnCellular) blockMetered=\(appState.userSettings.disableDevicesOnMetered)"
			)
			updateAudio()
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

		/// Starts or stops the silent sound so that it matches the two settings. It does not depend on the location permission: it keeps
		/// the app running by itself. Safe to call often (a start that failed, for example in a launch in the background, is tried again).
		private func updateAudio() {
			if appState.userSettings.keepRunningInBackground && appState.userSettings.keepAliveSilentAudio {
				audio.start()
			}
			else {
				audio.stop(reason: "the setting is off")
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

		static func describe(_ state: UIApplication.State) -> String {
			switch state {
			case .active: return "in front"
			case .inactive: return "changing between front and back"
			case .background: return "in the background"
			@unknown default: return "in an unknown state"
			}
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
			if audio.isRunning {
				text += " " + String(localized: "Silent sound: playing.")
			}
			else if appState.userSettings.keepAliveSilentAudio, let problem = audio.lastProblem {
				text += " " + String(localized: "Silent sound: not playing (\(problem)).")
			}
			if let stopped = AliveStore.lastStopMessage() {
				text += " " + stopped
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
	/// The wait is the setting photoBackupQuietSeconds (PhotoBackup.quietSeconds: default 3 s, 3...120 s).
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
			Task { @MainActor in
				Log.note("Photo library changed; the app is \(BackgroundKeepAlive.describe(UIApplication.shared.applicationState))")
				AliveStore.markAlive("photo library changed")
				self.schedule(reason: "photo library changed")
			}
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

			Log.note("Auto photo backup: starting (\(reason)); settle wait was \(photoBackup.quietSeconds) s")
			photoBackup.backup(appState: appState, fullExport: false, isInBackground: true)
		}
	}

	/// A second keeper: plays one second of silence over and over (a buffer of zeros, volume 0).
	///
	/// Why: the location session alone keeps the app running, but iOS ends such a background app first when memory runs short (for example
	/// when the Camera and another big app are open). An app that plays sound counts as a music player for iOS: it is not frozen in the
	/// background and it is among the last to be closed. The sound is mixed with other apps' sound (music, calls and videos keep playing)
	/// and nothing can be heard. Costs a little battery. "audio" is already in UIBackgroundModes. Event driven: no timer.
	///
	/// A start that fails (for example in a launch in the background, where iOS refuses a new audio session) is tried again the next time
	/// BackgroundKeepAlive.apply() runs, which is every time the app comes to the front.
	@MainActor final class SilentAudioKeeper: NSObject {
		private(set) var isRunning = false
		private(set) var lastProblem: String? = nil
		var onChange: (@MainActor () -> Void)? = nil

		private var engine: AVAudioEngine? = nil
		private var player: AVAudioPlayerNode? = nil
		private var observing = false
		private var lastStart = Date.distantPast

		func start() {
			if isRunning { return }
			// Do not start again and again when something keeps stopping the engine
			if Date.now.timeIntervalSince(lastStart) < 1 { return }
			lastStart = Date.now
			do {
				let session = AVAudioSession.sharedInstance()
				try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
				// Nothing is played that needs a short delay, so ask for the longest buffer: fewer wake-ups per second, less battery
				try? session.setPreferredIOBufferDuration(0.2)
				try session.setActive(true)

				let newEngine = AVAudioEngine()
				let newPlayer = AVAudioPlayerNode()
				// Build 14: the silence is made in the format the audio hardware runs in (the mixer's output format), so the mixer has nothing to
				// convert in every audio cycle. Build 13 made it as 8000 Hz mono, which the mixer had to convert to 44.1 / 48 kHz stereo about
				// 10 times a second (a suspect for the extra CPU seen in build 13, not yet proven). When the hardware format is not usable
				// (no audio route yet), the old small format is used: it sounds the same, it only costs more.
				let hardware = newEngine.mainMixerNode.outputFormat(forBus: 0)
				let hardwareUsable =
					hardware.sampleRate > 0 && hardware.channelCount > 0 && !hardware.isInterleaved && hardware.commonFormat == .pcmFormatFloat32
				guard let format = hardwareUsable ? hardware : AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1) else {
					problem("could not make the silent sound")
					return
				}
				let frames = AVAudioFrameCount(format.sampleRate)  // one second
				guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
					problem("could not make the silent sound")
					return
				}
				buffer.frameLength = frames
				if let channels = buffer.floatChannelData {
					for channelIndex in 0..<Int(format.channelCount) {
						for index in 0..<Int(frames) {
							channels[channelIndex][index] = 0
						}
					}
				}
				newEngine.attach(newPlayer)
				newEngine.connect(newPlayer, to: newEngine.mainMixerNode, format: format)
				newPlayer.volume = 0
				try newEngine.start()
				newPlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
				newPlayer.play()

				engine = newEngine
				player = newPlayer
				isRunning = true
				lastProblem = nil
				addObservers()
				Log.note("Keep-alive: silent sound started")
				onChange?()
			}
			catch {
				problem(error.localizedDescription)
			}
		}

		func stop(reason: String) {
			let wasRunning = isRunning
			player?.stop()
			engine?.stop()
			player = nil
			engine = nil
			isRunning = false
			if wasRunning {
				try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
				Log.note("Keep-alive: silent sound stopped (\(reason))")
				onChange?()
			}
		}

		private func problem(_ text: String) {
			if lastProblem != text {
				Log.note("Keep-alive: silent sound did not start: \(text)")
			}
			lastProblem = text
			isRunning = false
			onChange?()
		}

		private func restart(_ why: String) {
			Log.note("Keep-alive: silent sound restarts (\(why))")
			player?.stop()
			engine?.stop()
			player = nil
			engine = nil
			isRunning = false
			start()
		}

		private func handleInterruption(_ typeValue: UInt?) {
			guard let raw = typeValue, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
			switch type {
			case .began:
				Log.note("Keep-alive: silent sound interrupted (a call, Siri or another app took the audio)")
			case .ended:
				restart("the interruption ended")
			@unknown default:
				break
			}
		}

		private func addObservers() {
			if observing { return }
			observing = true
			let center = NotificationCenter.default
			center.addObserver(
				self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
			center.addObserver(
				self, selector: #selector(audioEngineChanged(_:)), name: .AVAudioEngineConfigurationChange, object: nil)
			center.addObserver(
				self, selector: #selector(audioServicesReset(_:)), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
		}

		// The notifications arrive on any thread: read what is needed, then hop to the main actor (same pattern as the location delegate)
		@objc private nonisolated func audioInterrupted(_ note: Notification) {
			let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
			Task { @MainActor in self.handleInterruption(typeValue) }
		}

		@objc private nonisolated func audioEngineChanged(_ note: Notification) {
			Task { @MainActor in self.restart("the audio set-up changed") }
		}

		@objc private nonisolated func audioServicesReset(_ note: Notification) {
			Task { @MainActor in self.restart("iOS reset its audio services") }
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

				Toggle("Also play silence (a second keeper)", isOn: userSettings.$keepAliveSilentAudio)
					.onChange(of: userSettings.keepAliveSilentAudio) { _, _ in keepAlive.apply() }

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
					"iOS freezes apps that are in the background. With this switch on, the app uses the lowest-accuracy location service only to stop iOS from freezing it, so new photos are backed up by themselves. Your position is never stored, logged or sent anywhere. iOS shows a blue indicator while this runs, and it uses more battery. \"Also play silence\" adds an inaudible sound: iOS then treats the app like a music player and closes it last when memory runs low (other apps' sound keeps playing; it costs a little more battery). Do not swipe the app away in the app switcher: iOS then does not start it again by itself until you open it once."
				)
			}
		}
	}
#endif

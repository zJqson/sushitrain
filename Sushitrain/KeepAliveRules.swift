// Copyright (C) 2026 Jason (personal fork of Synctrain / Sushitrain by Tommy van der Vorst)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
import Foundation

// Two small rule sets for the "keep running in the background" feature, written as PURE SWIFT (Foundation only, no Photos / UIKit /
// Network imports) so the CI can compile and run them with a plain `swiftc` together with tools/keepalive_selftest/KeepAliveSelfTest.swift
// in a few seconds, before the long build starts:
//
// 1. ConnectivityRules - the network rules of the sync ("Wi-Fi only, never mobile data, never a metered or Low Data Mode network"),
//    decided from plain flags. AppState turns the NWPath into these flags. A device that the user marked "Allow on mobile data and
//    hotspot (manual transfers only)" is exempt from the mobile data / metered / Low Data Mode rules (DeviceNetworkPolicy), but never
//    when it shares the photo back-up folder (BackupFolderGuard): photos never use a restricted network.
// 2. AliveJournal / AliveStore - a note of "when did this app last show a sign of life", so that the next start can say "the app was not
//    running from 18:00 to 18:15" (iOS ended it, or the phone was restarted). Written only when something happens (a scene change, a
//    photo run, a memory warning, the existing 50 second measurement timer, at most every 5 minutes): there is no timer of its own.

// MARK: - Network rules

/// What the current network path looks like.
struct ConnectivityFlags: Equatable, Sendable {
	/// False while the network path is not known yet.
	var pathKnown: Bool
	var usesCellular: Bool
	/// iOS calls a network "expensive" when it is mobile data or a Personal Hotspot of an iPhone.
	var isExpensive: Bool
	/// True when Low Data Mode is on for the network in use (the user can switch it on per Wi-Fi network in the iPhone's Settings).
	var isConstrained: Bool
	var lowPowerMode: Bool
	/// False for an iPad without a SIM: then "mobile data" cannot be the problem.
	var deviceHasCellular: Bool
}

/// The user's switches (Settings, Bandwidth limitations).
struct ConnectivitySettings: Equatable, Sendable {
	var blockOnCellular: Bool
	var blockOnMetered: Bool
	var blockInLowPowerMode: Bool
}

enum ConnectivityRules {
	/// nil = the sync may use this network. Otherwise a short reason in plain words (for the log and the screen).
	/// Order: Low Power Mode, then (when either network switch is on) an unknown path, mobile data, a metered network, Low Data Mode.
	/// This is the rule for a device WITHOUT the manual-transfer switch, which is every device until the user turns the switch on.
	static func blockReason(flags: ConnectivityFlags, settings: ConnectivitySettings) -> String? {
		return blockReason(flags: flags, settings: settings, device: DeviceNetworkPolicy())
	}

	/// The same rule for one device. When the device's exception applies (switch on, and the device does not share the photo back-up
	/// folder) mobile data, a metered network and Low Data Mode do not stop it. Low Power Mode and an unknown network still stop it,
	/// exactly as they stop every other device.
	static func blockReason(flags: ConnectivityFlags, settings: ConnectivitySettings, device: DeviceNetworkPolicy) -> String? {
		if settings.blockInLowPowerMode && flags.lowPowerMode {
			return "Low Power Mode is on"
		}
		if settings.blockOnCellular || settings.blockOnMetered {
			if !flags.pathKnown {
				// Not known yet: stay off, just to be sure
				return "the network is not known yet"
			}
			if device.exemptionApplies {
				// Manual transfers: this device may use mobile data, a metered network and a Low Data Mode network
				return nil
			}
			if flags.deviceHasCellular && settings.blockOnCellular && flags.usesCellular {
				return "the phone uses mobile data"
			}
			if settings.blockOnMetered && flags.isExpensive {
				return "the network is metered (iOS calls it expensive, for example mobile data or a hotspot)"
			}
			if settings.blockOnMetered && flags.isConstrained {
				return "Low Data Mode is on for this network"
			}
		}
		return nil
	}

	/// True when the device may connect ONLY because of its switch: the normal rule blocks this network, the rule for this device does not.
	static func exemptionIsLifting(flags: ConnectivityFlags, settings: ConnectivitySettings, device: DeviceNetworkPolicy) -> Bool {
		return blockReason(flags: flags, settings: settings) != nil && blockReason(flags: flags, settings: settings, device: device) == nil
	}

	/// One line in plain words about one device whose switch is on, for the start screen, the device screen and the log.
	/// nil = nothing to say (the switch is off, or this network is not blocked for anybody). `name` is the device's name.
	static func deviceExceptionLine(name: String, flags: ConnectivityFlags, settings: ConnectivitySettings, device: DeviceNetworkPolicy) -> String? {
		if device.switchIsIgnored {
			return "\(name): the switch is ignored, because this device receives your photo back-up. Photos never use mobile data or a hotspot."
		}
		if !device.exemptionApplies {
			return nil
		}
		if let why = blockReason(flags: flags, settings: settings, device: device) {
			return "\(name): paused, because \(why)."
		}
		if blockReason(flags: flags, settings: settings) != nil {
			return "\(name): allowed on this network (manual transfers)."
		}
		return nil
	}

	/// The lines for the start screen: what is paused and what is allowed. Empty when no device has the switch on, so that the screen then
	/// shows what it always showed. `globalReason` is the answer of `blockReason(flags:settings:)` (nil = this network is not blocked).
	static func statusLines(globalReason: String?, deviceLines: [String]) -> [String] {
		if deviceLines.isEmpty {
			return []
		}
		var lines: [String] = []
		if let why = globalReason {
			lines.append("Photo back-up and other devices: paused, because \(why).")
		}
		lines.append(contentsOf: deviceLines)
		return lines
	}
}

// MARK: - Per-device exception for manual transfers

/// How the network rules treat ONE device. In the app the user can switch on "Allow on mobile data and hotspot (manual transfers only)"
/// for a device (it is off for every device until the user turns it on). A device with the switch on is not stopped by mobile data, a
/// metered network or Low Data Mode, so a file or a folder that the user sends by hand can travel on a hotspot too.
/// FAIL-SAFE: the switch counts for nobody who shares the photo back-up folder, so the photos can never leave on a restricted network,
/// even if the switch is set by mistake. Low Power Mode and an unknown network still stop every device.
struct DeviceNetworkPolicy: Equatable, Sendable {
	/// The user's switch for this device.
	var allowsRestrictedNetworks: Bool = false
	/// True when this device shares the photo back-up folder, or a folder that lies in or around it (see BackupFolderGuard).
	var sharesBackupFolder: Bool = false

	/// True when the device is exempt from the mobile data / metered / Low Data Mode rules.
	var exemptionApplies: Bool {
		return allowsRestrictedNetworks && !sharesBackupFolder
	}

	/// True when the switch is on but cannot be used, because the device shares the photo back-up folder.
	var switchIsIgnored: Bool {
		return allowsRestrictedNetworks && sharesBackupFolder
	}
}

/// A Syncthing folder as the network rules need to see it.
struct FolderShareInfo: Equatable, Sendable {
	var id: String
	/// Where the folder is on the phone ("" when that is not known).
	var path: String
	/// The IDs of the devices the folder is shared with.
	var sharedWith: Set<String>
}

enum BackupFolderGuard {
	/// The devices that share the photo back-up folder, or a folder whose path is the back-up folder's path, lies inside it or around it
	/// (the back-up writes into the directory tree of its folder). The exception never applies to these devices.
	/// `backupFolderID` is "" when no back-up folder has been chosen: then nobody shares it. The answer only gets bigger when more
	/// folders overlap, so a wrong guess about a path can make the rule stricter but never looser.
	static func devicesSharingBackup(backupFolderID: String, folders: [FolderShareInfo]) -> Set<String> {
		if backupFolderID.isEmpty {
			return []
		}
		guard let backup = folders.first(where: { $0.id == backupFolderID }) else {
			return []
		}
		var devices = backup.sharedWith
		for other in folders {
			if other.id != backup.id && pathsOverlap(backup.path, other.path) {
				devices.formUnion(other.sharedWith)
			}
		}
		return devices
	}

	/// True when one path is the other, or lies inside the other. Compared folder by folder (so "/a/photos2" is not inside "/a/photos"),
	/// without looking at upper or lower case, and with "." and ".." resolved. An empty path overlaps with nothing.
	static func pathsOverlap(_ first: String, _ second: String) -> Bool {
		let a = pathParts(first)
		let b = pathParts(second)
		if a.isEmpty || b.isEmpty {
			return false
		}
		return a.starts(with: b) || b.starts(with: a)
	}

	static func pathParts(_ path: String) -> [String] {
		var parts: [String] = []
		for piece in path.components(separatedBy: "/") {
			let part = piece.lowercased()
			if part.isEmpty || part == "." {
				continue
			}
			if part == ".." {
				if !parts.isEmpty {
					parts.removeLast()
				}
				continue
			}
			parts.append(part)
		}
		// "/private/var/..." and "/var/..." are the same place on an iPhone
		if parts.count >= 2 && parts[0] == "private" && parts[1] == "var" {
			parts.removeFirst()
		}
		return parts
	}
}

// MARK: - Sign of life

enum AliveJournal {
	/// "45 s", "12 min", "3 h 05 min"
	static func describeDuration(_ seconds: TimeInterval) -> String {
		let total = Int(max(0, seconds).rounded())
		if total < 60 {
			return "\(total) s"
		}
		let minutes = total / 60
		if minutes < 60 {
			return "\(minutes) min"
		}
		let hours = minutes / 60
		let rest = minutes % 60
		return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest)) min"
	}

	/// What to say at start-up about the time since the last sign of life; nil when there is nothing to say (no earlier sign of life, the
	/// clock went back, or the gap is shorter than `minimumGap`, which is just a quick restart).
	static func gapMessage(lastAlive: Date?, lastReason: String?, now: Date, minimumGap: TimeInterval, timeZone: TimeZone) -> String? {
		guard let last = lastAlive else {
			return nil
		}
		let gap = now.timeIntervalSince(last)
		if gap < minimumGap {
			return nil
		}
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = timeZone
		formatter.dateFormat = "MMM d, HH:mm"
		var text =
			"The app was not running from about \(formatter.string(from: last)) until \(formatter.string(from: now)) (\(describeDuration(gap))): iOS ended it, or the phone was restarted."
		if let reason = lastReason, !reason.isEmpty {
			text += " Last sign of life: \(reason)."
		}
		return text
	}
}

/// Where the sign of life is kept: three small preferences. `defaults` can be another suite (the self-test uses one).
enum AliveStore {
	static let lastAliveKey = "keepAliveLastAlive"
	static let lastReasonKey = "keepAliveLastReason"
	static let lastStopKey = "keepAliveLastStopMessage"

	/// Writes "alive now, because of `reason`", but not more often than every `minimumSpacing` seconds (0 = always). Returns true when it wrote.
	@discardableResult
	static func markAlive(_ reason: String, now: Date = Date(), minimumSpacing: TimeInterval = 0, defaults: UserDefaults = .standard) -> Bool {
		if minimumSpacing > 0 {
			let previous = defaults.double(forKey: lastAliveKey)
			if previous > 0 && now.timeIntervalSince1970 - previous < minimumSpacing {
				return false
			}
		}
		defaults.set(now.timeIntervalSince1970, forKey: lastAliveKey)
		defaults.set(reason, forKey: lastReasonKey)
		return true
	}

	/// To call once at start-up: compares the stored sign of life with `now`, remembers the message (for the screen) and returns it.
	static func readAtLaunch(
		now: Date = Date(), minimumGap: TimeInterval = 180, timeZone: TimeZone = .current, defaults: UserDefaults = .standard
	) -> String? {
		let stored = defaults.double(forKey: lastAliveKey)
		let last: Date? = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
		let reason = defaults.string(forKey: lastReasonKey)
		let message = AliveJournal.gapMessage(lastAlive: last, lastReason: reason, now: now, minimumGap: minimumGap, timeZone: timeZone)
		if let text = message {
			defaults.set(text, forKey: lastStopKey)
		}
		return message
	}

	/// The newest "the app was not running ..." message, for the screen (nil when there has been none).
	static func lastStopMessage(defaults: UserDefaults = .standard) -> String? {
		return defaults.string(forKey: lastStopKey)
	}
}

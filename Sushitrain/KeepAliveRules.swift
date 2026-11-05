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
//    decided from plain flags. AppState turns the NWPath into these flags.
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
	static func blockReason(flags: ConnectivityFlags, settings: ConnectivitySettings) -> String? {
		if settings.blockInLowPowerMode && flags.lowPowerMode {
			return "Low Power Mode is on"
		}
		if settings.blockOnCellular || settings.blockOnMetered {
			if !flags.pathKnown {
				// Not known yet: stay off, just to be sure
				return "the network is not known yet"
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

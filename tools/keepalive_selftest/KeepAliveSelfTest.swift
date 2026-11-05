// Copyright (C) 2026 Jason (personal fork of Synctrain / Sushitrain by Tommy van der Vorst)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
import Foundation

// Self-test of Sushitrain/KeepAliveRules.swift (the network rules and the "sign of life" note). The CI builds and runs it with a plain
// swiftc (no Xcode project, no simulator) BEFORE the long build:
//   xcrun swiftc -swift-version 6 -parse-as-library -o selftest Sushitrain/KeepAliveRules.swift tools/keepalive_selftest/KeepAliveSelfTest.swift && ./selftest
// Every failed check prints a line that starts with "ERROR: " (the build log tool picks those up) and the exit code is 1.
@main
struct KeepAliveSelfTest {
	static func main() {
		var checks = 0
		var failures = 0

		func fail(_ message: String) {
			failures += 1
			print("ERROR: keep-alive self-test: \(message)")
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

		// ---- 1. Network rules: the settings the app ships with are "block mobile data" and "block metered", Low Power Mode is not blocked ----
		let shipped = ConnectivitySettings(blockOnCellular: true, blockOnMetered: true, blockInLowPowerMode: false)
		let wifi = ConnectivityFlags(
			pathKnown: true, usesCellular: false, isExpensive: false, isConstrained: false, lowPowerMode: false, deviceHasCellular: true)
		func reason(_ flags: ConnectivityFlags, _ settings: ConnectivitySettings = shipped) -> String {
			return ConnectivityRules.blockReason(flags: flags, settings: settings) ?? "(allowed)"
		}
		func with(_ change: (inout ConnectivityFlags) -> Void) -> ConnectivityFlags {
			var copy = wifi
			change(&copy)
			return copy
		}

		expectEqual(reason(wifi), "(allowed)", "plain Wi-Fi is allowed")
		expectTrue(reason(with { $0.usesCellular = true }).contains("mobile data"), "mobile data is blocked")
		expectTrue(reason(with { $0.isExpensive = true }).contains("metered"), "an expensive network (hotspot of an iPhone) is blocked")
		expectTrue(reason(with { $0.isConstrained = true }).contains("Low Data Mode"), "Low Data Mode is blocked")
		expectTrue(reason(with { $0.pathKnown = false }).contains("not known"), "an unknown network is blocked")
		expectEqual(reason(with { $0.lowPowerMode = true }), "(allowed)", "Low Power Mode is not blocked by the shipped settings")

		// the switches really switch
		let noCellularBlock = ConnectivitySettings(blockOnCellular: false, blockOnMetered: true, blockInLowPowerMode: false)
		let noMeteredBlock = ConnectivitySettings(blockOnCellular: true, blockOnMetered: false, blockInLowPowerMode: false)
		let allOff = ConnectivitySettings(blockOnCellular: false, blockOnMetered: false, blockInLowPowerMode: false)
		let lowPowerOn = ConnectivitySettings(blockOnCellular: true, blockOnMetered: true, blockInLowPowerMode: true)
		expectEqual(reason(with { $0.usesCellular = true }, noCellularBlock), "(allowed)", "mobile data allowed when its switch is off")
		expectEqual(reason(with { $0.isExpensive = true }, noMeteredBlock), "(allowed)", "expensive allowed when the metered switch is off")
		expectEqual(reason(with { $0.isConstrained = true }, noMeteredBlock), "(allowed)", "Low Data Mode allowed when the metered switch is off")
		expectTrue(reason(with { $0.usesCellular = true }, noMeteredBlock).contains("mobile data"), "mobile data still blocked with the metered switch off")
		expectTrue(reason(with { $0.isExpensive = true }, noCellularBlock).contains("metered"), "expensive still blocked with the mobile data switch off")
		expectEqual(
			reason(with { $0.usesCellular = true; $0.isExpensive = true; $0.isConstrained = true; $0.pathKnown = false }, allOff),
			"(allowed)", "everything allowed when every switch is off")
		expectEqual(reason(with { $0.pathKnown = false }, allOff), "(allowed)", "an unknown network is allowed when both network switches are off")
		expectTrue(reason(with { $0.lowPowerMode = true }, lowPowerOn).contains("Low Power Mode"), "Low Power Mode is blocked when its switch is on")
		expectEqual(reason(wifi, lowPowerOn), "(allowed)", "plain Wi-Fi is allowed with the Low Power Mode switch on")

		// a device without a SIM cannot be on mobile data
		expectEqual(reason(with { $0.usesCellular = true; $0.deviceHasCellular = false }), "(allowed)", "no SIM, so no mobile data rule")

		// order of the reasons
		expectTrue(reason(with { $0.lowPowerMode = true; $0.usesCellular = true }, lowPowerOn).contains("Low Power Mode"), "Low Power Mode comes first")
		expectTrue(reason(with { $0.usesCellular = true; $0.isExpensive = true }).contains("mobile data"), "mobile data comes before metered")
		expectTrue(reason(with { $0.isExpensive = true; $0.isConstrained = true }).contains("metered"), "metered comes before Low Data Mode")
		expectTrue(reason(with { $0.pathKnown = false; $0.usesCellular = true }).contains("not known"), "an unknown path comes before the rest")

		// The hotspot case of the iPhone: Wi-Fi that iOS marks expensive is blocked; an Android hotspot is NOT marked, only Low Data Mode catches it
		let androidHotspotWithoutLowData = with { $0.isExpensive = false; $0.isConstrained = false }
		let androidHotspotWithLowData = with { $0.isExpensive = false; $0.isConstrained = true }
		expectEqual(reason(androidHotspotWithoutLowData), "(allowed)", "an Android hotspot without Low Data Mode looks like normal Wi-Fi (known limit)")
		expectTrue(reason(androidHotspotWithLowData).contains("Low Data Mode"), "an Android hotspot with Low Data Mode is blocked")

		// ---- 2. Durations ----
		expectEqual(AliveJournal.describeDuration(0), "0 s", "0 seconds")
		expectEqual(AliveJournal.describeDuration(59), "59 s", "59 seconds")
		expectEqual(AliveJournal.describeDuration(60), "1 min", "60 seconds")
		expectEqual(AliveJournal.describeDuration(15 * 60 + 20), "15 min", "15 minutes")
		expectEqual(AliveJournal.describeDuration(3600), "1 h", "one hour")
		expectEqual(AliveJournal.describeDuration(3 * 3600 + 5 * 60), "3 h 05 min", "3 h 05 min")
		expectEqual(AliveJournal.describeDuration(-30), "0 s", "a negative duration")

		// ---- 3. The gap message (all times in UTC so the test is the same everywhere) ----
		let utc = TimeZone(identifier: "UTC")!
		let base =
			DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: utc, year: 2026, month: 11, day: 4, hour: 13, minute: 46).date
			?? Date(timeIntervalSince1970: 1_793_800_000)
		let later = base.addingTimeInterval(15 * 60)
		let message = AliveJournal.gapMessage(lastAlive: base, lastReason: "scene background", now: later, minimumGap: 180, timeZone: utc) ?? "(none)"
		expectTrue(message.contains("not running"), "the message says the app was not running, got [\(message)]")
		expectTrue(message.contains("15 min"), "the message names the gap, got [\(message)]")
		expectTrue(message.contains("scene background"), "the message names the last sign of life, got [\(message)]")
		expectTrue(message.contains("Nov 4, 13:46"), "the message names the day and the time of the last sign of life, got [\(message)]")
		expectTrue(message.contains("14:01"), "the message names the time of the start, got [\(message)]")
		expectTrue(
			AliveJournal.gapMessage(lastAlive: nil, lastReason: nil, now: later, minimumGap: 180, timeZone: utc) == nil, "no earlier sign of life: no message")
		expectTrue(
			AliveJournal.gapMessage(lastAlive: base, lastReason: nil, now: base.addingTimeInterval(60), minimumGap: 180, timeZone: utc) == nil,
			"a gap of one minute is a quick restart: no message")
		expectTrue(
			AliveJournal.gapMessage(lastAlive: base, lastReason: nil, now: base.addingTimeInterval(180), minimumGap: 180, timeZone: utc) != nil,
			"a gap of exactly the minimum gives a message")
		expectTrue(
			AliveJournal.gapMessage(lastAlive: later, lastReason: nil, now: base, minimumGap: 180, timeZone: utc) == nil, "the clock went back: no message")
		expectTrue(
			!(AliveJournal.gapMessage(lastAlive: base, lastReason: "", now: later, minimumGap: 180, timeZone: utc) ?? "").contains("Last sign of life"),
			"an empty reason is not printed")

		// ---- 4. The stored sign of life (a throw-away preference suite, nothing of the real app is touched) ----
		let suiteName = "keepalive-selftest-" + UUID().uuidString
		guard let defaults = UserDefaults(suiteName: suiteName) else {
			fail("could not make a test preference suite")
			print("keep-alive self-test: \(checks) checks, \(failures) failed")
			exit(1)
		}
		expectTrue(AliveStore.readAtLaunch(now: later, timeZone: utc, defaults: defaults) == nil, "first start ever: nothing to say")
		expectTrue(AliveStore.lastStopMessage(defaults: defaults) == nil, "first start ever: no stop message stored")
		expectTrue(AliveStore.markAlive("started", now: base, defaults: defaults), "the first mark is written")
		expectTrue(!AliveStore.markAlive("ping", now: base.addingTimeInterval(100), minimumSpacing: 300, defaults: defaults), "a mark inside the spacing is skipped")
		expectTrue(AliveStore.markAlive("ping", now: base.addingTimeInterval(301), minimumSpacing: 300, defaults: defaults), "a mark after the spacing is written")
		expectTrue(AliveStore.markAlive("scene background", now: base.addingTimeInterval(302), minimumSpacing: 0, defaults: defaults), "spacing 0 always writes")
		let stopText = AliveStore.readAtLaunch(now: base.addingTimeInterval(302 + 20 * 60), timeZone: utc, defaults: defaults) ?? "(none)"
		expectTrue(stopText.contains("20 min"), "the stored sign of life gives the gap, got [\(stopText)]")
		expectTrue(stopText.contains("scene background"), "the stored reason is used, got [\(stopText)]")
		expectEqual(AliveStore.lastStopMessage(defaults: defaults) ?? "(none)", stopText, "the message is kept for the screen")
		AliveStore.markAlive("started", now: base.addingTimeInterval(302 + 20 * 60), defaults: defaults)
		expectTrue(
			AliveStore.readAtLaunch(now: base.addingTimeInterval(302 + 20 * 60 + 30), timeZone: utc, defaults: defaults) == nil,
			"a quick second start says nothing")
		expectEqual(AliveStore.lastStopMessage(defaults: defaults) ?? "(none)", stopText, "a quick restart keeps the older message")
		defaults.removePersistentDomain(forName: suiteName)

		print("keep-alive self-test: \(checks) checks, \(failures) failed")
		exit(failures == 0 ? 0 : 1)
	}
}

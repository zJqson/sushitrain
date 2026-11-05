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

		// ---- 1b. The per-device exception for manual transfers ("Allow on mobile data and hotspot (manual transfers only)") ----
		// Build 15's rule, copied word for word, is the oracle: for a device WITHOUT the exception the new code must give the SAME answer in
		// every one of the 64 network situations x 8 combinations of the three settings = 512 inputs.
		func build15Reason(_ f: ConnectivityFlags, _ s: ConnectivitySettings) -> String? {
			if s.blockInLowPowerMode && f.lowPowerMode {
				return "Low Power Mode is on"
			}
			if s.blockOnCellular || s.blockOnMetered {
				if !f.pathKnown {
					return "the network is not known yet"
				}
				if f.deviceHasCellular && s.blockOnCellular && f.usesCellular {
					return "the phone uses mobile data"
				}
				if s.blockOnMetered && f.isExpensive {
					return "the network is metered (iOS calls it expensive, for example mobile data or a hotspot)"
				}
				if s.blockOnMetered && f.isConstrained {
					return "Low Data Mode is on for this network"
				}
			}
			return nil
		}
		// What the exception may lift: only mobile data, a metered network and Low Data Mode. Low Power Mode and an unknown network stay.
		func exemptReason(_ f: ConnectivityFlags, _ s: ConnectivitySettings) -> String? {
			if s.blockInLowPowerMode && f.lowPowerMode {
				return "Low Power Mode is on"
			}
			if (s.blockOnCellular || s.blockOnMetered) && !f.pathKnown {
				return "the network is not known yet"
			}
			return nil
		}
		func policyReason(_ f: ConnectivityFlags, _ p: DeviceNetworkPolicy, _ s: ConnectivitySettings) -> String {
			return ConnectivityRules.blockReason(flags: f, settings: s, device: p) ?? "(allowed)"
		}
		let standardPolicy = DeviceNetworkPolicy()
		let manualPolicy = DeviceNetworkPolicy(allowsRestrictedNetworks: true, sharesBackupFolder: false)
		let manualButBackup = DeviceNetworkPolicy(allowsRestrictedNetworks: true, sharesBackupFolder: true)
		let backupWithoutSwitch = DeviceNetworkPolicy(allowsRestrictedNetworks: false, sharesBackupFolder: true)
		expectTrue(standardPolicy == DeviceNetworkPolicy(allowsRestrictedNetworks: false, sharesBackupFolder: false), "the default policy has the switch off")
		expectTrue(!standardPolicy.exemptionApplies && !standardPolicy.switchIsIgnored, "the default policy: no exception, nothing ignored")
		expectTrue(manualPolicy.exemptionApplies && !manualPolicy.switchIsIgnored, "switch on, no back-up folder: the exception applies")
		expectTrue(!manualButBackup.exemptionApplies && manualButBackup.switchIsIgnored, "switch on but the device shares the back-up folder: ignored")
		expectTrue(!backupWithoutSwitch.exemptionApplies && !backupWithoutSwitch.switchIsIgnored, "back-up folder, switch off: nothing to ignore")
		var situations = 0
		var oldBlocked = 0
		var exemptBlocked = 0
		var lifted = 0
		for flagBits in 0..<64 {
			let f = ConnectivityFlags(
				pathKnown: flagBits & 1 != 0, usesCellular: flagBits & 2 != 0, isExpensive: flagBits & 4 != 0,
				isConstrained: flagBits & 8 != 0, lowPowerMode: flagBits & 16 != 0, deviceHasCellular: flagBits & 32 != 0)
			for settingBits in 0..<8 {
				let s = ConnectivitySettings(
					blockOnCellular: settingBits & 1 != 0, blockOnMetered: settingBits & 2 != 0, blockInLowPowerMode: settingBits & 4 != 0)
				let tag = "flags \(flagBits), settings \(settingBits)"
				situations += 1
				let old = build15Reason(f, s) ?? "(allowed)"
				let exempt = exemptReason(f, s) ?? "(allowed)"
				if old != "(allowed)" {
					oldBlocked += 1
				}
				// I4: nothing changes for a device without the switch (the two-argument rule, the default policy, and a back-up device with its switch off)
				expectEqual(reason(f, s), old, "I4 the two-argument rule equals build 15 (\(tag))")
				expectEqual(policyReason(f, standardPolicy, s), old, "I4 the default policy equals build 15 (\(tag))")
				expectEqual(policyReason(f, backupWithoutSwitch, s), old, "I4 a back-up device without the switch equals build 15 (\(tag))")
				// I1: the switch is ignored for a device that shares the back-up folder: the same answer as the old rule
				expectEqual(policyReason(f, manualButBackup, s), old, "I1 the switch is ignored for a back-up device (\(tag))")
				// I2: a device with the switch (and no back-up folder) is stopped only by Low Power Mode and an unknown network
				let manual = policyReason(f, manualPolicy, s)
				expectEqual(manual, exempt, "I2 the exception lifts mobile data / metered / Low Data Mode only (\(tag))")
				if manual != "(allowed)" {
					exemptBlocked += 1
				}
				// I3: where nothing is blocked for anybody, nothing is blocked for the exempt device either
				if old == "(allowed)" {
					expectEqual(manual, "(allowed)", "I3 an unrestricted network pauses nobody (\(tag))")
				}
				// the exception is never stricter than the old rule: it can only lift reasons, not change them
				if manual != "(allowed)" {
					expectEqual(manual, old, "a reason that stays is the same reason as before (\(tag))")
				}
				let isLifting = ConnectivityRules.exemptionIsLifting(flags: f, settings: s, device: manualPolicy)
				expectTrue(isLifting == (old != "(allowed)" && manual == "(allowed)"), "exemptionIsLifting matches the two answers (\(tag))")
				if isLifting {
					lifted += 1
				}
				expectTrue(
					!ConnectivityRules.exemptionIsLifting(flags: f, settings: s, device: standardPolicy)
						&& !ConnectivityRules.exemptionIsLifting(flags: f, settings: s, device: manualButBackup),
					"nothing is lifted for a device without the exception (\(tag))")
			}
		}
		// golden numbers of the table (counted with the Python model of the rule, written down on purpose: a changed rule changes them)
		expectTrue(situations == 512, "the table has 512 situations, got \(situations)")
		expectTrue(oldBlocked == 359, "build 15 blocks 359 of them, got \(oldBlocked)")
		expectTrue(exemptBlocked == 272, "a device with the switch is still blocked in 272 of them, got \(exemptBlocked)")
		expectTrue(lifted == 87, "the switch lifts the block in 87 of them, got \(lifted)")

		// the situations that matter, in words (shipped settings)
		let lowDataWifi = with { $0.isConstrained = true }
		let cellularNow = with { $0.usesCellular = true; $0.isExpensive = true }
		let hotspotOfAnIPhone = with { $0.isExpensive = true }
		expectEqual(policyReason(lowDataWifi, standardPolicy, shipped), "Low Data Mode is on for this network", "photos: paused on a Low Data Mode Wi-Fi (the Android hotspot case)")
		expectEqual(policyReason(lowDataWifi, manualPolicy, shipped), "(allowed)", "Drop device: allowed on a Low Data Mode Wi-Fi")
		expectEqual(policyReason(lowDataWifi, manualButBackup, shipped), "Low Data Mode is on for this network", "a back-up device with the switch on: still paused on a Low Data Mode Wi-Fi")
		expectTrue(policyReason(cellularNow, standardPolicy, shipped).contains("mobile data"), "photos: paused on mobile data")
		expectEqual(policyReason(cellularNow, manualPolicy, shipped), "(allowed)", "Drop device: allowed on mobile data")
		expectTrue(policyReason(cellularNow, manualButBackup, shipped).contains("mobile data"), "a back-up device with the switch on: still paused on mobile data")
		expectTrue(policyReason(hotspotOfAnIPhone, standardPolicy, shipped).contains("metered"), "photos: paused on the hotspot of an iPhone")
		expectEqual(policyReason(hotspotOfAnIPhone, manualPolicy, shipped), "(allowed)", "Drop device: allowed on the hotspot of an iPhone")
		expectTrue(policyReason(with { $0.pathKnown = false }, manualPolicy, shipped).contains("not known"), "Drop device: paused while the network is not known (start-up)")
		expectTrue(policyReason(with { $0.lowPowerMode = true }, manualPolicy, lowPowerOn).contains("Low Power Mode"), "Drop device: paused in Low Power Mode when that limit is on")
		expectEqual(policyReason(with { $0.lowPowerMode = true }, manualPolicy, shipped), "(allowed)", "Drop device: Low Power Mode is not a limit with the shipped settings")

		// the lines of plain words
		func line(_ f: ConnectivityFlags, _ p: DeviceNetworkPolicy, _ s: ConnectivitySettings = shipped) -> String {
			return ConnectivityRules.deviceExceptionLine(name: "Drop", flags: f, settings: s, device: p) ?? "(nothing)"
		}
		expectEqual(line(lowDataWifi, manualPolicy), "Drop: allowed on this network (manual transfers).", "line: allowed")
		expectEqual(line(wifi, manualPolicy), "(nothing)", "line: nothing to say on a plain Wi-Fi")
		expectEqual(line(lowDataWifi, standardPolicy), "(nothing)", "line: nothing to say without the switch")
		expectEqual(line(with { $0.pathKnown = false }, manualPolicy), "Drop: paused, because the network is not known yet.", "line: paused while unknown")
		expectEqual(line(with { $0.lowPowerMode = true }, manualPolicy, lowPowerOn), "Drop: paused, because Low Power Mode is on.", "line: paused in Low Power Mode")
		expectTrue(line(lowDataWifi, manualButBackup).contains("ignored"), "line: the switch is ignored for a back-up device")
		expectTrue(line(wifi, manualButBackup).contains("ignored"), "line: the ignored switch is said on any network")
		expectTrue(line(lowDataWifi, manualButBackup).contains("Photos never use mobile data or a hotspot"), "line: the ignored switch gives the reason")
		let lines = ConnectivityRules.statusLines(
			globalReason: "Low Data Mode is on for this network", deviceLines: ["Drop: allowed on this network (manual transfers)."])
		expectTrue(
			lines == [
				"Photo back-up and other devices: paused, because Low Data Mode is on for this network.",
				"Drop: allowed on this network (manual transfers).",
			], "status lines: what is paused, then what is allowed, got \(lines)")
		expectTrue(ConnectivityRules.statusLines(globalReason: "x", deviceLines: []).isEmpty, "status lines: empty without a device exception (the screen stays as it was)")
		expectTrue(
			ConnectivityRules.statusLines(globalReason: nil, deviceLines: ["Drop: the switch is ignored."]) == ["Drop: the switch is ignored."],
			"status lines: no 'paused' line when nothing is blocked")

		// ---- 1c. Which devices share the photo back-up folder (the fail-safe of the exception) ----
		let appFiles = "/var/mobile/Containers/Data/Application/AAAA/Documents"
		let photosFolder = FolderShareInfo(id: "phone-iphone-camera", path: appFiles + "/phone-iphone-camera", sharedWith: ["MAIN"])
		let dropFolder = FolderShareInfo(id: "drop", path: appFiles + "/drop", sharedWith: ["DROP"])
		func backupDevices(_ backupID: String, _ folders: [FolderShareInfo]) -> [String] {
			return BackupFolderGuard.devicesSharingBackup(backupFolderID: backupID, folders: folders).sorted()
		}
		expectTrue(backupDevices("phone-iphone-camera", [photosFolder, dropFolder]) == ["MAIN"], "only the main device shares the back-up folder")
		expectTrue(backupDevices("", [photosFolder, dropFolder]).isEmpty, "no back-up folder chosen: nobody shares it")
		expectTrue(backupDevices("gone", [photosFolder, dropFolder]).isEmpty, "a back-up folder id that does not exist: nobody shares it")
		expectTrue(backupDevices("phone-iphone-camera", []).isEmpty, "no folders at all")
		var photosAlsoToDrop = photosFolder
		photosAlsoToDrop.sharedWith = ["MAIN", "DROP"]
		expectTrue(backupDevices("phone-iphone-camera", [photosAlsoToDrop, dropFolder]) == ["DROP", "MAIN"], "a device that gets the back-up folder is a back-up device (even with its own other folder)")
		expectTrue(backupDevices("drop", [photosFolder, dropFolder]) == ["DROP"], "a back-up folder that is moved to another folder follows the new one")
		var nestedDrop = dropFolder
		nestedDrop.path = appFiles + "/phone-iphone-camera/Drop"
		expectTrue(backupDevices("phone-iphone-camera", [photosFolder, nestedDrop]) == ["DROP", "MAIN"], "a folder INSIDE the back-up folder is a back-up folder too")
		var wideDrop = dropFolder
		wideDrop.path = appFiles
		expectTrue(backupDevices("phone-iphone-camera", [photosFolder, wideDrop]) == ["DROP", "MAIN"], "a folder AROUND the back-up folder is a back-up folder too")
		var samePathDrop = dropFolder
		samePathDrop.path = appFiles + "/phone-iphone-camera/"
		expectTrue(backupDevices("phone-iphone-camera", [photosFolder, samePathDrop]) == ["DROP", "MAIN"], "the same path (trailing slash) is the same folder")
		var noPathDrop = dropFolder
		noPathDrop.path = ""
		var noPathPhotos = photosFolder
		noPathPhotos.path = ""
		expectTrue(backupDevices("phone-iphone-camera", [noPathPhotos, noPathDrop]) == ["MAIN"], "folders without a known path do not overlap with each other")
		expectTrue(BackupFolderGuard.pathsOverlap("/a/photos", "/a/photos"), "a path overlaps with itself")
		expectTrue(BackupFolderGuard.pathsOverlap("/a/photos", "/a/photos/2026/Nov"), "a path overlaps with a path inside it")
		expectTrue(BackupFolderGuard.pathsOverlap("/a/photos/2026", "/a"), "a path overlaps with a path around it")
		expectTrue(!BackupFolderGuard.pathsOverlap("/a/photos", "/a/photos2"), "photos2 is not inside photos (compared folder by folder)")
		expectTrue(!BackupFolderGuard.pathsOverlap("/a/photos", "/a/drop"), "two sibling folders do not overlap")
		expectTrue(!BackupFolderGuard.pathsOverlap("/a/photos", "/b/photos"), "the same name in another place does not overlap")
		expectTrue(BackupFolderGuard.pathsOverlap("/a/Photos", "/a/photos"), "upper and lower case are not told apart (stricter, never looser)")
		expectTrue(BackupFolderGuard.pathsOverlap("/a//photos/./x/..", "/a/photos"), "double slashes, . and .. are resolved")
		expectTrue(BackupFolderGuard.pathsOverlap("/private/var/mobile/x/photos", "/var/mobile/x/photos"), "/private/var and /var are the same place")
		expectTrue(!BackupFolderGuard.pathsOverlap("", ""), "two empty paths do not overlap")
		expectTrue(!BackupFolderGuard.pathsOverlap("/a/photos", ""), "an empty path overlaps with nothing")
		expectTrue(!BackupFolderGuard.pathsOverlap("/", "/a/photos"), "the root path alone is no information")
		expectTrue(BackupFolderGuard.pathParts("/A/b/../C//d/.") == ["a", "c", "d"], "pathParts: resolved, lower case")

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

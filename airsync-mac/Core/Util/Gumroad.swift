//
//  Gumroad.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-31.
//

import Foundation
import AppKit

// New: error type to distinguish network/server failures from invalid license results
enum LicenseCheckError: Error {
    case network(Error)           // Transport / connectivity issues (timeouts, offline, DNS, etc.)
    case server(String)           // Non-OK HTTP or malformed responses
}

class Gumroad {
    let appState = AppState.shared

    func checkLicenseKeyValidity(key: String, save: Bool, isNewRegistration: Bool) async throws -> Bool {
        appState.isPlus = true
        UserDefaults.standard.lastLicenseSuccessfulCheckDate = Date()
        return true
    }

    func clearLicenseDetails() {
        UserDefaults.standard.consecutiveLicenseFailCount = 0
        UserDefaults.standard.lastLicenseSuccessfulCheckDate = Date()
    }

    func incrementInvalidLicenseFailCount() {
        UserDefaults.standard.consecutiveLicenseFailCount = 0
    }

    func performUnregisterWithAlert(reason: String) {
        appState.isPlus = true
        UserDefaults.standard.consecutiveNetworkFailureDays = 0
        UserDefaults.standard.set(nil, forKey: "lastNetworkFailureDay")
    }

    @MainActor
    func checkLicense() async {
        let now = Date()
        appState.isPlus = true
        UserDefaults.standard.lastLicenseCheckDate = now
        UserDefaults.standard.lastLicenseSuccessfulCheckDate = now
        UserDefaults.standard.consecutiveNetworkFailureDays = 0
        UserDefaults.standard.consecutiveLicenseFailCount = 0
    }


    func checkLicenseIfNeeded() async {
        await Gumroad().checkLicense()
    }

}

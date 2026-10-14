import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.tray.app", category: "Preferences")

final class PreferencesManager: PreferencesManaging {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            PreferenceKey.maxHistoryItems.rawValue: 200,
            PreferenceKey.launchAtLogin.rawValue: false,
            PreferenceKey.showMenubarIcon.rawValue: true,
            PreferenceKey.excludedAppBundleIDs.rawValue: ["com.apple.keychainaccess"],
            PreferenceKey.pasteSound.rawValue: false
        ])
    }

    // MARK: - Properties

    /// Choices offered in the menu bar dropdown
    static let historyLimitOptions = [50, 100, 200]

    var maxHistoryItems: Int {
        get {
            let val = defaults.integer(forKey: PreferenceKey.maxHistoryItems.rawValue)
            return val > 0 ? min(val, 1000) : 200
        }
        set {
            defaults.set(min(max(newValue, 10), 1000), forKey: PreferenceKey.maxHistoryItems.rawValue)
        }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: PreferenceKey.launchAtLogin.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.launchAtLogin.rawValue)
            updateLoginItem(enabled: newValue)
        }
    }

    var showMenubarIcon: Bool {
        get { defaults.bool(forKey: PreferenceKey.showMenubarIcon.rawValue) }
        set { defaults.set(newValue, forKey: PreferenceKey.showMenubarIcon.rawValue) }
    }

    var excludedAppBundleIDs: [String] {
        get { defaults.stringArray(forKey: PreferenceKey.excludedAppBundleIDs.rawValue) ?? [] }
        set { defaults.set(newValue, forKey: PreferenceKey.excludedAppBundleIDs.rawValue) }
    }

    var pasteSound: Bool {
        get { defaults.bool(forKey: PreferenceKey.pasteSound.rawValue) }
        set { defaults.set(newValue, forKey: PreferenceKey.pasteSound.rawValue) }
    }

    /// Re-registers the login item if it's on, so it follows the app when moved
    /// (e.g. into /Applications) instead of pointing at the old location
    func syncLoginItem() {
        if launchAtLogin { updateLoginItem(enabled: true) }
    }

    // MARK: - Private

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to update login item: \(error.localizedDescription)")
        }
    }
}

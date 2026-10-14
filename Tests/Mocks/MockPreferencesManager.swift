import Foundation
@testable import Tray

final class MockPreferencesManager: PreferencesManaging {
    var maxHistoryItems: Int = 200
    var launchAtLogin: Bool = false
    var showMenubarIcon: Bool = true
    var excludedAppBundleIDs: [String] = []
    var pasteSound: Bool = false
}

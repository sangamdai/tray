import Foundation

protocol PreferencesManaging: AnyObject {
    var maxHistoryItems: Int { get set }
    var launchAtLogin: Bool { get set }
    var showMenubarIcon: Bool { get set }
    var excludedAppBundleIDs: [String] { get set }
    var pasteSound: Bool { get set }
}

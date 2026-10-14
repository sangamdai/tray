import Foundation

/// App-level facts shown in the About window and menu bar dropdown
enum AppInfo {
    static let tagline = "Clipboard history in your menu bar."

    /// GitHub repo, e.g. URL(string: "https://github.com/you/tray").
    /// Once set, About shows a link to it and the menu gets "Check for Updates…".
    static let repositoryURL: URL? = URL(string: "https://github.com/sangamdai/tray")

    static var releasesURL: URL? {
        repositoryURL?.appendingPathComponent("releases")
    }
}

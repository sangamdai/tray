import Foundation

enum ClipboardItemType: String, Codable, CaseIterable {
    case plainText
    case richText
    case html
    case url
    case image
    case file
    case color
    case tabularData

    var icon: LucideIcon {
        switch self {
        case .plainText, .richText: return .letterText
        case .html: return .codeXml
        case .url: return .link
        case .image: return .image
        case .file: return .file
        case .color: return .palette
        case .tabularData: return .table
        }
    }
}

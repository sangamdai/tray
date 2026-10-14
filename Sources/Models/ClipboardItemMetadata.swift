import Foundation

struct ClipboardItemMetadata: Codable, Equatable {
    // Text types
    var plainText: String?

    // Rich text / HTML
    var rtfData: Data?
    var htmlString: String?

    // URL
    var urlString: String?
    var urlTitle: String?

    // Image
    var imageWidth: Int?
    var imageHeight: Int?
    var imagePath: String?
    var thumbnailPath: String?

    // File
    var filePath: String?
    var fileName: String?
    var fileSize: Int64?
    var fileUTI: String?

    // Color
    var colorHex: String?
    var colorRGBA: [Double]?

    // Tabular
    var rowCount: Int?
    var columnCount: Int?
    var tsvData: String?

    static let empty = ClipboardItemMetadata()
}

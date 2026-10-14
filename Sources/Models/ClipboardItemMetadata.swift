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

/// The potentially large fields of ClipboardItemMetadata. Stored in their own
/// column and loaded only for paste and preview, so opening the popup stays cheap.
struct ClipboardPayload: Codable, Equatable {
    var plainText: String?
    var rtfData: Data?
    var htmlString: String?
    var tsvData: String?

    var isEmpty: Bool { plainText == nil && rtfData == nil && htmlString == nil && tsvData == nil }
}

extension ClipboardItemMetadata {
    var payload: ClipboardPayload {
        ClipboardPayload(plainText: plainText, rtfData: rtfData, htmlString: htmlString, tsvData: tsvData)
    }

    /// Everything except the payload: what list rows need
    var withoutPayload: ClipboardItemMetadata {
        var light = self
        light.plainText = nil
        light.rtfData = nil
        light.htmlString = nil
        light.tsvData = nil
        return light
    }

    mutating func apply(_ payload: ClipboardPayload) {
        plainText = payload.plainText
        rtfData = payload.rtfData
        htmlString = payload.htmlString
        tsvData = payload.tsvData
    }
}

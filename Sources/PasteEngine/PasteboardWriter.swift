import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "PasteboardWriter")

/// Writes clipboard item data back to NSPasteboard with correct types.
enum PasteboardWriter {

    /// Marks pasteboard contents written by Tray itself, so ClipboardMonitor
    /// doesn't re-capture a paste and move the item to the top of history.
    static let ownWriteMarker = NSPasteboard.PasteboardType("com.tray.app.own-write")

    static func write(_ data: ClipboardItemData, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: ownWriteMarker)

        switch data.type {
        case .plainText:
            if let text = data.metadata.plainText {
                pasteboard.setString(text, forType: .string)
            }

        case .richText:
            if let rtf = data.rawData {
                pasteboard.setData(rtf, forType: .rtf)
            }
            // Always include plain text fallback
            if let text = data.metadata.plainText {
                pasteboard.setString(text, forType: .string)
            }

        case .html:
            if let html = data.metadata.htmlString {
                pasteboard.setString(html, forType: .html)
            }
            if let text = data.metadata.plainText {
                pasteboard.setString(text, forType: .string)
            }

        case .url:
            if let urlStr = data.metadata.urlString, let url = URL(string: urlStr) {
                pasteboard.setString(url.absoluteString, forType: .string)
                (url as NSURL).write(to: pasteboard)
            }

        case .image:
            if let imageData = data.rawData {
                // Stored bytes are whatever the source app copied: PNG or TIFF.
                // Label them truthfully, and add TIFF for apps that only read TIFF.
                if isPNG(imageData) {
                    pasteboard.setData(imageData, forType: .png)
                    if let image = NSImage(data: imageData), let tiff = image.tiffRepresentation {
                        pasteboard.setData(tiff, forType: .tiff)
                    }
                } else {
                    pasteboard.setData(imageData, forType: .tiff)
                }
            }

        case .file:
            if let path = data.metadata.filePath {
                let url = URL(fileURLWithPath: path)
                pasteboard.writeObjects([url as NSURL])
            }

        case .color:
            if let rgba = data.metadata.colorRGBA, rgba.count >= 4 {
                let color = NSColor(
                    red: CGFloat(rgba[0]),
                    green: CGFloat(rgba[1]),
                    blue: CGFloat(rgba[2]),
                    alpha: CGFloat(rgba[3])
                )
                color.write(to: pasteboard)
            }

        case .tabularData:
            if let tsv = data.metadata.tsvData {
                pasteboard.setString(tsv, forType: .string)
                pasteboard.setString(tsv, forType: .tabularText)
            }
        }

        logger.debug("Wrote \(data.type.rawValue) to pasteboard")
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private static func isPNG(_ data: Data) -> Bool {
        data.prefix(pngSignature.count) == pngSignature
    }
}

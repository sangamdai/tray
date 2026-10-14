import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "ImageStorage")

final class ImageStorage {

    let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        if let dir = baseDirectory {
            self.baseDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("Tray", isDirectory: true)
            self.baseDirectory = appSupport
        }
        createDirectoriesIfNeeded()
    }

    var imagesDirectory: URL {
        baseDirectory.appendingPathComponent("images", isDirectory: true)
    }

    // MARK: - Save

    /// Writes the image and returns its filename. (Thumbnails used to be generated
    /// here too, but nothing displayed them.)
    func saveImage(_ data: Data, id: UUID) -> String? {
        let imagePath = imagesDirectory.appendingPathComponent("\(id.uuidString).png")
        do {
            try data.write(to: imagePath)
            return imagePath.lastPathComponent
        } catch {
            logger.error("Failed to save image \(id.uuidString): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Load

    func loadImage(filename: String) -> Data? {
        let path = imagesDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: path)
    }

    // MARK: - Delete

    func deleteFiles(for id: UUID) {
        let fm = FileManager.default
        let files = [
            imagesDirectory.appendingPathComponent("\(id.uuidString).png"),
            // Older versions also saved a thumbnail
            imagesDirectory.appendingPathComponent("\(id.uuidString)_thumb.png")
        ]
        for file in files {
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Private

    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

}

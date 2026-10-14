import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    var createdAt: Date
    var isPinned: Bool
    var isHidden: Bool
    var customName: String?
    let sourceAppBundleID: String?
    let sourceAppName: String?
    let contentPreview: String
    let dataHash: String
    var metadata: ClipboardItemMetadata

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        isHidden: Bool = false,
        customName: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        contentPreview: String,
        dataHash: String,
        metadata: ClipboardItemMetadata = .empty
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isHidden = isHidden
        self.customName = customName
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.contentPreview = contentPreview
        self.dataHash = dataHash
        self.metadata = metadata
    }

    /// Display label: custom name if renamed, otherwise content preview.
    /// Hidden items show custom name if set, otherwise "Hidden item".
    var displayLabel: String {
        if isHidden { return customName ?? "Hidden item" }
        return customName ?? contentPreview
    }
}

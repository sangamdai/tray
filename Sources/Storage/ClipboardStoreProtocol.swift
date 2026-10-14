import Foundation

struct ClipboardItemData {
    let type: ClipboardItemType
    let metadata: ClipboardItemMetadata
    let rawData: Data?
}

protocol ClipboardStoring: AnyObject {
    func save(_ item: ClipboardItem) throws
    func fetchRecent(limit: Int) -> [ClipboardItem]
    func fetchPinned() -> [ClipboardItem]
    func search(query: String, limit: Int) -> [ClipboardItem]
    func delete(id: UUID) throws
    func deleteAll() throws
    func togglePin(id: UUID) throws
    func toggleHide(id: UUID) throws
    func rename(id: UUID, name: String) throws
    func itemCount() -> Int
    func getFullData(id: UUID) -> ClipboardItemData?
    func hashExists(_ hash: String) -> Bool
}

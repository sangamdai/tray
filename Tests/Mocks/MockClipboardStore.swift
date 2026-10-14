import Foundation
@testable import Tray

final class MockClipboardStore: ClipboardStoring {
    var savedItems: [ClipboardItem] = []
    var saveCalled = false
    var deleteCalled = false
    var deleteAllCalled = false

    func save(_ item: ClipboardItem) throws {
        saveCalled = true
        // Deduplication check
        if let idx = savedItems.firstIndex(where: { $0.dataHash == item.dataHash }) {
            savedItems[idx].createdAt = item.createdAt
        } else {
            savedItems.append(item)
        }
    }

    func fetchRecent(limit: Int) -> [ClipboardItem] {
        savedItems
            .filter { !$0.isPinned }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func fetchPinned() -> [ClipboardItem] {
        savedItems.filter { $0.isPinned }.sorted { $0.createdAt > $1.createdAt }
    }

    func search(query: String, limit: Int) -> [ClipboardItem] {
        let q = query.lowercased()
        return savedItems.filter {
            $0.contentPreview.lowercased().contains(q) ||
            ($0.customName?.lowercased().contains(q) ?? false)
        }.prefix(limit).map { $0 }
    }

    func delete(id: UUID) throws {
        deleteCalled = true
        savedItems.removeAll { $0.id == id }
    }

    func deleteAll() throws {
        deleteAllCalled = true
        savedItems.removeAll { !$0.isPinned }
    }

    func togglePin(id: UUID) throws {
        if let idx = savedItems.firstIndex(where: { $0.id == id }) {
            savedItems[idx].isPinned.toggle()
        }
    }

    func toggleHide(id: UUID) throws {
        if let idx = savedItems.firstIndex(where: { $0.id == id }) {
            savedItems[idx].isHidden.toggle()
        }
    }

    func rename(id: UUID, name: String) throws {
        if let idx = savedItems.firstIndex(where: { $0.id == id }) {
            savedItems[idx].customName = name
        }
    }

    func itemCount() -> Int { savedItems.count }

    func hashExists(_ hash: String) -> Bool {
        savedItems.contains { $0.dataHash == hash }
    }

    func getFullData(id: UUID) -> ClipboardItemData? {
        guard let item = savedItems.first(where: { $0.id == id }) else { return nil }
        return ClipboardItemData(type: item.type, metadata: item.metadata, rawData: nil)
    }
}

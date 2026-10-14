import Foundation

protocol PastePerforming: AnyObject {
    func paste(item: ClipboardItem, data: ClipboardItemData)
}

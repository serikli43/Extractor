import Foundation
import Quartz

class QuickLookPreviewDataSource: NSObject, QLPreviewPanelDataSource {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return fileURL as QLPreviewItem
    }
}

import SwiftUI
import AppKit
import Quartz

struct ForceTouchView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> ForceTouchNSView {
        let view = ForceTouchNSView()
        view.fileURL = fileURL

        // NSImageView mit Dateisymbol hinzufügen
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSWorkspace.shared.icon(forFile: fileURL.path)
        view.addSubview(imageView)

        return view
    }

    func updateNSView(_ nsView: ForceTouchNSView, context: Context) {
        nsView.fileURL = fileURL
        if let imageView = nsView.subviews.first as? NSImageView {
            imageView.image = NSWorkspace.shared.icon(forFile: fileURL.path)
        }
    }
}

class ForceTouchNSView: NSView {
    var fileURL: URL?
    var pressureStage: Int = 0
    var dataSource: QuickLookPreviewDataSource?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        for trackingArea in self.trackingAreas {
            self.removeTrackingArea(trackingArea)
        }
        
        self.addTrackingArea(NSTrackingArea(rect: self.bounds,
                                            options: [.activeAlways, .mouseEnteredAndExited, .enabledDuringMouseDrag],
                                            owner: self,
                                            userInfo: nil))
    }

    override func mouseDown(with event: NSEvent) {
        pressureStage = event.stage
    }

    override func pressureChange(with event: NSEvent) {
        if event.stage == 2 && pressureStage < 2 {
            if let url = fileURL {
                let panel = QLPreviewPanel.shared()
                self.dataSource = QuickLookPreviewDataSource(fileURL: url)
                panel?.makeKeyAndOrderFront(nil)
                panel?.dataSource = self.dataSource
                panel?.reloadData()
            }
        }
        pressureStage = event.stage
    }
}

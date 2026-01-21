//
//  AppDelegate.swift
//  Extractor
//
//  Created by Semih Erikli on 23.07.25.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let fileURL = urls.first else { return }
        NotificationCenter.default.post(name: .didReceiveFileURL, object: fileURL)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}
extension Notification.Name {
    static let didReceiveFileURL = Notification.Name("didReceiveFileURL")
}

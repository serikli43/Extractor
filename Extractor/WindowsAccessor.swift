//
//  WindowsAccessor.swift
//  Extractor
//
//  Created by Semih Erikli on 24.07.25.
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> ()

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

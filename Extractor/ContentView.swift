/*
 NICHT LÖSCHEN!!!
 To-Dos
 Frage ob individuell oder zusammen bei jedem file drop
 
 */
import Quartz
import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = ArchiveViewModel()

    @State private var showPasswordSheet = false
    @State private var tempPassword = ""
    @State private var hoveredURL: URL? = nil
    @State private var quickLookDataSource: QuickLookPreviewDataSource?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: 400, height: 450) // Höhe etwas erhöht für Liste

            VStack(spacing: 20) {
                Text("7-Zip GUI for macOS")
                    .font(.title2)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("File:")
                    Text(viewModel.archiveFileName)
                        .frame(minWidth: 150, alignment: .leading)
                    Button("Select") {
                        viewModel.pickFile()
                    }
                }

                

                // Übersicht der Dateien
                if !viewModel.selectedURLs.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Files to compress:")
                            .font(.headline)
                            .padding(.bottom, 5)

                        let columns = [GridItem(.adaptive(minimum: 80))]
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.selectedURLs, id: \.self) { url in
                                VStack(spacing: 8) {
                                    ZStack(alignment: .topTrailing) {
                                        ForceTouchView(fileURL: url)
                                            .frame(width: 48, height: 48)

                                        if hoveredURL == url {
                                            Button(action: {
                                                removeFile(url)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Color.white.opacity(0.7))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                    .onHover { hovering in
                                        hoveredURL = hovering ? url : nil
                                    }

                                    Text(url.lastPathComponent)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(width: 80)
                                }
                                .onTapGesture(count: 2) {
                                    openQuickLook(for: url)
                                }
                            }
                        }
                        .frame(height: 140)
                    }
                    .padding(.horizontal)
                }
                HStack {
                    Button("Compress with \(viewModel.selectedFormat)") {
                        viewModel.compressFile()
                    }
                    .disabled(viewModel.selectedURLs.isEmpty || viewModel.isArchive)

                    Picker("", selection: $viewModel.selectedFormat) {
                        ForEach(viewModel.supportedFormats, id: \.self) { format in
                            Text(format).tag(format)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                }
                Button("Extract") {
                    if viewModel.requiresPassword {
                        tempPassword = ""
                        showPasswordSheet = true
                    } else {
                        viewModel.extractFile()
                    }
                }
                .disabled(viewModel.inputPath.isEmpty || !viewModel.isArchive)

                Text(viewModel.resultMessage)
                    .foregroundColor(.gray)
                    .padding(.top, 10)

                if viewModel.isProcessing {
                    VStack {
                        ProgressView("Loading… \(viewModel.progressCurrent) / \(viewModel.progressTotal)")
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 200)
                    }
                }
            }
            .padding()
            .frame(width: 400, height: 450) // Höhe angepasst für Liste
        }
        .sheet(isPresented: $showPasswordSheet) {
            VStack(spacing: 20) {
                Text("Enter Password")
                    .font(.headline)
                SecureField("Password", text: $tempPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                HStack {
                    Button("Cancel") {
                        showPasswordSheet = false
                    }
                    Spacer()
                    Button("OK") {
                        viewModel.password = tempPassword
                        showPasswordSheet = false
                        viewModel.extractFile()
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .frame(width: 300, height: 150)
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil, perform: handleDrop(providers:))
        .onAppear {
            if let window = NSApplication.shared.windows.first {
                window.collectionBehavior.remove(.fullScreenPrimary)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    if let data = item as? Data,
                       let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? {
                        DispatchQueue.main.async {
                            if !viewModel.selectedURLs.contains(url) {
                                viewModel.selectedURLs.append(url)
                            }
                            if let firstPath = viewModel.selectedURLs.first?.path {
                                viewModel.inputPath = firstPath
                                viewModel.isArchive = viewModel.selectedURLs.allSatisfy { viewModel.supportedArchiveExtensions.contains($0.pathExtension.lowercased()) }
                                viewModel.checkIfPasswordNeeded()
                                // Insert compression prompt if multiple files are selected
                                if viewModel.selectedURLs.count > 1 {
                                    DispatchQueue.main.async {
                                        let alert = NSAlert()
                                        alert.messageText = "Compression"
                                        alert.informativeText = "Do you want to compress all selected items individually or together?"
                                        alert.addButton(withTitle: "Individually")
                                        alert.addButton(withTitle: "Together")
                                        let response = alert.runModal()
                                        viewModel.compressTogether = (response == .alertSecondButtonReturn)
                                    }
                                }
                            }
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }

    private func openQuickLook(for url: URL) {
        let panel = QLPreviewPanel.shared()
        quickLookDataSource = QuickLookPreviewDataSource(fileURL: url)
        panel?.makeKeyAndOrderFront(nil)
        panel?.dataSource = quickLookDataSource
        panel?.reloadData()
    }

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
    private func removeFile(_ url: URL) {
        if let index = viewModel.selectedURLs.firstIndex(of: url) {
            viewModel.selectedURLs.remove(at: index)
            if viewModel.selectedURLs.isEmpty {
                viewModel.inputPath = ""
                viewModel.isArchive = false
            } else {
                viewModel.inputPath = viewModel.selectedURLs.first?.path ?? ""
                viewModel.isArchive = viewModel.selectedURLs.allSatisfy { viewModel.supportedArchiveExtensions.contains($0.pathExtension.lowercased()) }
            }
        }
    }
}

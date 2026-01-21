// ArchiveViewModel.swift
import Foundation
import SwiftUI
import UserNotifications

class ArchiveViewModel: ObservableObject {
    @Published var inputPath: String = ""
    @Published var resultMessage: String = ""
    @Published var isArchive: Bool = false
    @Published var selectedFormat: String = "7z"
    @Published var isProcessing: Bool = false
    @Published var progressTotal: Int = 0
    @Published var progressCurrent: Int = 0
    @Published var selectedURLs: [URL] = []
    @Published var compressTogether: Bool = false

    @Published var requiresPassword: Bool = false
    @Published var password: String = ""

    let supportedFormats = ["7z", "zip", "tar", "wim", "gzip", "bzip2", "xz"]
    let supportedArchiveExtensions: Set<String> = ["7z", "zip", "rar", "tar", "wim", "gzip", "bzip2", "xz"]

    private var sevenZipURL: URL?

    init() {
        self.sevenZipURL = Bundle.main.url(forResource: "7zz", withExtension: nil)
        if sevenZipURL == nil {
            DispatchQueue.main.async {
                self.resultMessage = "7zz not found in the app bundle."
            }
        }
    }

    func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            self.selectedURLs = panel.urls
            self.isArchive = self.selectedURLs.allSatisfy { self.supportedArchiveExtensions.contains($0.pathExtension.lowercased()) }
            self.inputPath = self.selectedURLs.first?.path ?? ""
            self.checkIfPasswordNeeded()

            if self.selectedURLs.count > 1 {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Compression"
                    alert.informativeText = "Do you want to compress all selected items individually or together?"
                    alert.addButton(withTitle: "Individually")
                    alert.addButton(withTitle: "Together")
                    let response = alert.runModal()
                    self.compressTogether = (response == .alertSecondButtonReturn)
                }
            } else {
                self.compressTogether = false
            }
        }
    }

    func checkIfPasswordNeeded(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let sevenZipURL = sevenZipURL, !inputPath.isEmpty else {
            completion(false)
            return
        }

        let inputURL = URL(fileURLWithPath: self.inputPath)
        let process = Process()
        let pipe = Pipe()

        process.executableURL = sevenZipURL
        process.arguments = ["t", "-p-", inputURL.path]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)

            let needsPassword = output.lowercased().contains("encrypted") || output.lowercased().contains("password")

            DispatchQueue.main.async {
                self.requiresPassword = needsPassword
            }
            completion(needsPassword)
        } catch {
            DispatchQueue.main.async {
                self.resultMessage = "Error checking archive: \(error.localizedDescription)"
                self.requiresPassword = false
            }
            completion(false)
        }
    }

    func extractFile() {
        guard let sevenZipURL = sevenZipURL, !inputPath.isEmpty else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let inputURL = URL(fileURLWithPath: self.inputPath)
            let parentFolderURL = inputURL.deletingLastPathComponent()
            let ext = inputURL.pathExtension.lowercased()
            let isSingleFileFormat = ["xz", "bzip2", "gzip"].contains(ext)
            let outputFolderURL = parentFolderURL.appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent)

            do {
                try FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
            } catch {
                DispatchQueue.main.async {
                    self.resultMessage = "Error creating output folder: \(error.localizedDescription)"
                }
                return
            }

            let process = Process()
            process.executableURL = sevenZipURL

            var args = ["x", self.inputPath, "-o" + outputFolderURL.path, "-y"]
            if !self.password.isEmpty {
                args.append("-p\(self.password)")
            }
            process.arguments = args

            process.terminationHandler = { proc in
                DispatchQueue.main.async {
                    if proc.terminationStatus == 0 {
                        do {
                            if isSingleFileFormat {
                                let files = try FileManager.default.contentsOfDirectory(at: outputFolderURL, includingPropertiesForKeys: nil)
                                for file in files {
                                    if file.pathExtension.isEmpty {
                                        let newURL = file.appendingPathExtension(inputURL.deletingPathExtension().pathExtension)
                                        try FileManager.default.moveItem(at: file, to: newURL)
                                    }
                                }
                            }

                            let files = try FileManager.default.contentsOfDirectory(at: outputFolderURL, includingPropertiesForKeys: nil)
                            self.progressTotal = files.count
                            self.progressCurrent = files.count
                            self.resultMessage = "Extracted successfully to \(outputFolderURL.path)"
                            self.sendNotification(title: "Extracting finished", body: outputFolderURL.lastPathComponent)
                        } catch {
                            self.resultMessage = "Error post-processing extracted files: \(error.localizedDescription)"
                        }
                    } else {
                        self.resultMessage = "Error while extracting (Code \(proc.terminationStatus))"
                    }
                    self.isProcessing = false
                }
            }

            DispatchQueue.main.async {
                self.isProcessing = true
                self.progressTotal = 1
                self.progressCurrent = 0
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    self.resultMessage = "Error: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    func compressFile() {
        guard let sevenZipURL = sevenZipURL, !selectedURLs.isEmpty else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let parentFolderURL = self.selectedURLs.first!.deletingLastPathComponent()
            let tasks = self.compressTogether ? [self.selectedURLs] : self.selectedURLs.map { [$0] }

            DispatchQueue.main.async {
                self.isProcessing = true
                self.progressTotal = tasks.count
                self.progressCurrent = 0
                self.resultMessage = ""
            }

            let group = DispatchGroup()

            for urls in tasks {
                group.enter()

                let archiveName = urls.count == 1
                    ? urls[0].deletingPathExtension().appendingPathExtension(self.selectedFormat)
                    : parentFolderURL.appendingPathComponent("Archive").appendingPathExtension(self.selectedFormat)

                var args = ["a", archiveName.path]
                args.append(contentsOf: urls.map { $0.path })
                args.append("-y")

                let process = Process()
                process.executableURL = sevenZipURL
                process.arguments = args
                process.terminationHandler = { proc in
                    DispatchQueue.main.async {
                        if proc.terminationStatus == 0 {
                            self.resultMessage = "Compressed \(archiveName.lastPathComponent) successfully."
                        } else {
                            self.resultMessage = "Error compressing \(archiveName.lastPathComponent) (Code \(proc.terminationStatus))"
                        }
                        self.progressCurrent += 1
                    }
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    DispatchQueue.main.async {
                        self.resultMessage = "Error: \(error.localizedDescription)"
                        self.progressCurrent += 1
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.isProcessing = false
            }
        }
    }
    func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted && error == nil else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
    
    var archiveFileName: String {
        let parent = selectedURLs.first?.deletingLastPathComponent()
        if compressTogether {
            return "Archive.\(selectedFormat)"
        } else if let url = selectedURLs.first {
            return "\(url.deletingPathExtension().lastPathComponent).\(selectedFormat)"
        } else {
            return "No file selected"
        }
    }
}

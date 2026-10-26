import SwiftUI
import AppKit
import Foundation

struct ShredderItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let size: Int64
    var status: String = "" // "Pending", "Shredding", "Done", "Failed"
    
    var name: String {
        url.lastPathComponent
    }
    
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

class ShredderService: ObservableObject {
    @Published var items: [ShredderItem] = []
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var currentItemName: String = ""
    @Published var totalSizeCleared: Int64 = 0
    @Published var errorMessage: String?
    @Published private(set) var isStopping = false

    private var stopRequested = false
    
    // Add files via NSOpenPanel
    @MainActor
    func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Select"
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    self.addItem(url: url)
                }
            }
        }
    }
    
    func addItem(url: URL) {
        // Calculate size (recursive for directories)
        let size = calculateSize(of: url)
        let item = ShredderItem(url: url, size: size, status: "Pending")
        DispatchQueue.main.async {
            if !self.items.contains(where: { $0.url == url }) {
                self.items.append(item)
            }
        }
    }
    
    func removeItem(id: UUID) {
        guard !isProcessing else { return }
        items.removeAll { $0.id == id }
    }

    func removeItems(at offsets: IndexSet) {
        guard !isProcessing else { return }
        items.remove(atOffsets: offsets)
    }
    
    func reset() {
        guard !isProcessing else { stopShredding(); return }
        items = []
        isProcessing = false
        progress = 0.0
        currentItemName = ""
        totalSizeCleared = 0
        errorMessage = nil
        isStopping = false
        stopRequested = false
    }
    
    // MARK: - Shredding Logic
    func startShredding() async {
        let canStart = await MainActor.run { () -> Bool in
            guard !isProcessing else { return false }
            isProcessing = true
            isStopping = false
            stopRequested = false
            progress = 0.0
            totalSizeCleared = 0
            return true
        }
        guard canStart else { return }
        let snapshot = await MainActor.run { items }
        let totalItems = snapshot.count
        var processedCount = 0
        
        for item in snapshot {
            let stopped = await MainActor.run { stopRequested }
            if Task.isCancelled || stopped { break }
            
            await MainActor.run {
                currentItemName = item.name
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].status = "Shredding..."
                }
            }
            
            // Perform Secure Delete
            let success = await secureDelete(url: item.url)
            
            processedCount += 1
            await MainActor.run { [processedCount] in
                guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                if success {
                    items[index].status = "Done"
                    totalSizeCleared += item.size
                } else {
                    items[index].status = "Failed"
                }
                
                progress = Double(processedCount) / Double(totalItems)
            }
            
            // Small artificial delay for UI animation if needed, but real work takes time
            // try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        await MainActor.run {
            isProcessing = false
            isStopping = false
            currentItemName = ""
        }
    }

    /// Stops after the current file finishes so an overwrite is never left half complete.
    func stopShredding() {
        guard isProcessing else { return }
        stopRequested = true
        isStopping = true
    }
    
    private func secureDelete(url: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            do {
                try SecureFileShredder.shred(at: url)
                return true
            } catch {
                print("Shred error: \(error)")
                return false
            }
        }.value
    }

    private func calculateSize(of url: URL) -> Int64 {
        var size: Int64 = 0
        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .isDirectoryKey
        ]
        
        // If it's a file
        if let resources = try? url.resourceValues(forKeys: resourceKeys) {
            if resources.isDirectory == false {
                return Int64(
                    resources.totalFileAllocatedSize ??
                    resources.fileAllocatedSize ??
                    resources.fileSize ??
                    0
                )
            }
        }
        
        // If it's a directory (or calculate recursive)
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys)
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let resources = try? fileURL.resourceValues(forKeys: resourceKeys),
                   resources.isDirectory == false {
                    size += Int64(
                        resources.totalFileAllocatedSize ??
                        resources.fileAllocatedSize ??
                        resources.fileSize ??
                        0
                    )
                }
            }
        }
        return size
    }
}

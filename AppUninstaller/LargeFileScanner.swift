import Foundation
import SwiftUI
import os.log

struct FileItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let type: String
    let accessDate: Date
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct DeletionResult: Sendable {
    let successCount: Int
    let failedCount: Int
    let recoveredSize: Int64
    let failedFiles: [String]
    let errors: [String]
    
    var isSuccessful: Bool {
        failedCount == 0
    }
}

/// Progress information for scan operations
struct ScanProgress: Sendable {
    let filesProcessed: Int
    let totalEstimated: Int
    let currentPath: String
    let elapsedTime: TimeInterval
}

/// Aggregates work from concurrent directory enumerators and emits compact
/// snapshots at most a few times per second. This keeps the path, discovered
/// size and sidebar status live without publishing once for every file.
private actor LargeFileScanAccumulator {
    struct Snapshot: Sendable {
        let filesProcessed: Int
        let totalSize: Int64
        let currentPath: String
        let files: [FileItem]
    }

    private var filesProcessed = 0
    private var totalSize: Int64 = 0
    private var currentPath = ""
    private var files: [FileItem] = []
    private var lastPublishTime = Date.distantPast

    func record(
        processed: Int,
        discoveredFiles: [FileItem],
        currentPath: String,
        forcePublish: Bool = false
    ) -> Snapshot? {
        filesProcessed += processed
        files.append(contentsOf: discoveredFiles)
        totalSize += discoveredFiles.reduce(Int64(0)) { $0 + $1.size }
        if !currentPath.isEmpty {
            self.currentPath = currentPath
        }

        let now = Date()
        guard forcePublish || now.timeIntervalSince(lastPublishTime) >= 0.14 else {
            return nil
        }
        lastPublishTime = now
        return snapshot()
    }

    func finalSnapshot() -> Snapshot {
        snapshot()
    }

    private func snapshot() -> Snapshot {
        Snapshot(
            filesProcessed: filesProcessed,
            totalSize: totalSize,
            currentPath: currentPath,
            files: files
        )
    }
}

class LargeFileScanner: ObservableObject {
    @Published var foundFiles: [FileItem] = []
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var totalSize: Int64 = 0
    @Published var hasCompletedScan = false
    @Published var scanProgress: ScanProgress?
    
    private let minimumSize: Int64 = 50 * 1024 * 1024 // 50MB
    private let uiUpdater = BatchedUIUpdater()
    private let performanceMonitor = PerformanceMonitor()
    
    // Cleaning state
    @Published var isCleaning = false
    @Published var cleanedCount = 0
    @Published var cleanedSize: Int64 = 0
    @Published var isStopped = false
    @Published var selectedFiles: Set<UUID> = []
    private let stopLock = NSLock()
    private var stopRequested = false
    private let deleteFile: (URL) throws -> Void

    init(deleteFile: @escaping (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }) {
        self.deleteFile = deleteFile
    }
    
    // Computed property for total size of selected files
    var totalSelectedSize: Int64 {
        foundFiles.filter { selectedFiles.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    
    func stopScan() {
        setStopRequested(true)
        isStopped = true
    }
    
    func reset() {
        guard !isScanning && !isCleaning else { stopScan(); return }
        foundFiles = []
        isScanning = false
        scannedCount = 0
        totalSize = 0
        hasCompletedScan = false
        isCleaning = false
        cleanedCount = 0
        cleanedSize = 0
        isStopped = false
        setStopRequested(false)
        selectedFiles = []
        scanProgress = nil
    }
    
    func scan(at requestedRoot: URL? = nil) async {
        let token = performanceMonitor.startMeasuring("largeFileScan")
        defer { performanceMonitor.endMeasuring(token) }
        
        let canStart = await MainActor.run { () -> Bool in
            guard !self.isScanning && !self.isCleaning else { return false }
            self.isScanning = true
            self.foundFiles = []
            self.scannedCount = 0
            self.totalSize = 0
            self.hasCompletedScan = false
            self.isCleaning = false
            self.cleanedCount = 0
            self.cleanedSize = 0
            self.isStopped = false
            self.scanProgress = nil
            return true
        }
        guard canStart else { return }
        setStopRequested(false)
        
        let fileManager = FileManager.default
        let requestedScanRoot = requestedRoot ?? fileManager.homeDirectoryForCurrentUser
        // CleanMyMac's volume option reports the volume capacity, but its LAOF
        // query searches user-owned content and excludes macOS internals.
        let scanRoot = requestedScanRoot.path == "/"
            ? fileManager.homeDirectoryForCurrentUser
            : requestedScanRoot
        
        // Critical directories to exclude from recursion
        let excludedDirs: Set<String> = ["Library", ".Trash", ".git"]
        
        let accumulator = LargeFileScanAccumulator()
        let scanStartTime = Date()

        // Enumerate the selected filesystem directly: a successful Spotlight
        // query does not establish index coverage or include newly created files.
        if !isStopRequested {
            guard let topLevelItems = try? fileManager.contentsOfDirectory(
                at: scanRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else {
                await MainActor.run { self.isScanning = false }
                return
            }

            for offset in stride(from: 0, to: topLevelItems.count, by: 4) {
                if isStopRequested || Task.isCancelled { break }
                let batch = topLevelItems[offset..<min(offset + 4, topLevelItems.count)]
                await withTaskGroup(of: Void.self) { group in
                    for itemURL in batch {
                        let name = itemURL.lastPathComponent
                        if excludedDirs.contains(name) { continue }

                        let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                        let isDirectory = resourceValues?.isDirectory ?? false
                        let isPackage = resourceValues?.isPackage ?? false

                        if isDirectory && !isPackage {
                            group.addTask {
                                await self.scanDirectoryRecursively(
                                    itemURL,
                                    excludedDirs: excludedDirs,
                                    accumulator: accumulator,
                                    scanStartTime: scanStartTime
                                )
                            }
                        } else {
                            group.addTask {
                                let files = await self.checkFileSize(itemURL).0
                                    .filter { ScanResultIgnoreStore.shouldInclude($0.url) }
                                if let snapshot = await accumulator.record(
                                    processed: 1,
                                    discoveredFiles: files,
                                    currentPath: itemURL.path
                                ) {
                                    await self.publish(snapshot, scanStartTime: scanStartTime)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        let finalSnapshot = await accumulator.finalSnapshot()
        let finalFiles = finalSnapshot.files.sorted(by: { $0.size > $1.size })
        let totalElapsedTime = Date().timeIntervalSince(scanStartTime)
        let stopped = isStopRequested || Task.isCancelled
        
        await uiUpdater.batch {
            self.foundFiles = finalFiles
            self.totalSize = finalSnapshot.totalSize
            self.scannedCount = finalSnapshot.filesProcessed
            self.isScanning = false
            self.hasCompletedScan = !stopped || !finalFiles.isEmpty
            self.isStopped = stopped
            self.scanProgress = ScanProgress(
                filesProcessed: finalSnapshot.filesProcessed,
                totalEstimated: finalSnapshot.filesProcessed,
                currentPath: stopped ? finalSnapshot.currentPath : "Scan complete",
                elapsedTime: totalElapsedTime
            )
        }
    }

    private func scanDirectoryRecursively(
        _ directory: URL,
        excludedDirs: Set<String>,
        accumulator: LargeFileScanAccumulator,
        scanStartTime: Date
    ) async {
        let fileManager = FileManager.default
        var pendingFiles: [FileItem] = []
        var pendingCount = 0
        var currentPath = directory.path
        var lastFlushTime = Date()
        
        // Use enumerator for deep recursion
        // skipsPackageDescendants is CRITICAL to treat Apps/Bundles as single files
        let options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentAccessDateKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: options
        ) else { return }
        
        while let fileURL = enumerator.nextObject() as? URL {
            if isStopRequested || Task.isCancelled { break }
            
            pendingCount += 1
            currentPath = fileURL.path
            
            // Exclusion check
            if excludedDirs.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentAccessDateKey, .isRegularFileKey, .isSymbolicLinkKey])
                
                if let isDirectory = resourceValues.isDirectory, isDirectory {
                    continue
                }
                
                if resourceValues.isRegularFile == true, resourceValues.isSymbolicLink != true,
                   let fileSize = resourceValues.fileSize, Int64(fileSize) > minimumSize {
                    let accessDate = resourceValues.contentAccessDate ?? Date()
                    let item = FileItem(
                        url: fileURL,
                        name: fileURL.lastPathComponent,
                        size: Int64(fileSize),
                        type: fileURL.pathExtension.isEmpty ? "File" : fileURL.pathExtension.uppercased(),
                        accessDate: accessDate
                    )
                    if ScanResultIgnoreStore.shouldInclude(item.url) {
                        pendingFiles.append(item)
                    }
                }
            } catch {
                continue
            }

            let now = Date()
            if pendingCount >= 128 || now.timeIntervalSince(lastFlushTime) >= 0.14 {
                if let snapshot = await accumulator.record(
                    processed: pendingCount,
                    discoveredFiles: pendingFiles,
                    currentPath: currentPath
                ) {
                    await publish(snapshot, scanStartTime: scanStartTime)
                }
                pendingFiles.removeAll(keepingCapacity: true)
                pendingCount = 0
                lastFlushTime = now
            }
        }

        if pendingCount > 0 || !pendingFiles.isEmpty {
            if let snapshot = await accumulator.record(
                processed: pendingCount,
                discoveredFiles: pendingFiles,
                currentPath: currentPath,
                forcePublish: true
            ) {
                await publish(snapshot, scanStartTime: scanStartTime)
            }
        }
    }

    private func publish(_ snapshot: LargeFileScanAccumulator.Snapshot, scanStartTime: Date) async {
        let elapsedTime = Date().timeIntervalSince(scanStartTime)
        await uiUpdater.batch {
            guard self.isScanning else { return }
            self.foundFiles = snapshot.files.sorted(by: { $0.size > $1.size })
            self.totalSize = snapshot.totalSize
            self.scannedCount = snapshot.filesProcessed
            self.scanProgress = ScanProgress(
                filesProcessed: snapshot.filesProcessed,
                totalEstimated: max(snapshot.filesProcessed + 512, 1),
                currentPath: snapshot.currentPath,
                elapsedTime: elapsedTime
            )
        }
    }

    private var isStopRequested: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopRequested
    }

    private func setStopRequested(_ value: Bool) {
        stopLock.lock()
        stopRequested = value
        stopLock.unlock()
    }
    
    // Check single file
    private func checkFileSize(_ url: URL) async -> ([FileItem], Int) {
        var files: [FileItem] = []
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            if resourceValues.isRegularFile == true, resourceValues.isSymbolicLink != true, let fileSize = resourceValues.fileSize, Int64(fileSize) > minimumSize {
                 let item = FileItem(
                    url: url,
                    name: url.lastPathComponent,
                    size: Int64(fileSize),
                    type: url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased(),
                    accessDate: resourceValues.contentAccessDate ?? Date()
                )
                files.append(item)
            }
            return (files, 1)
        } catch {
            return ([], 1)
        }
    }
    
    // Helper to get relative path
    // Need to add this extension if not exists, or just check simple string containment

    
    func deleteItems(_ items: Set<UUID>) async -> DeletionResult {
        var successCount = 0
        var failedCount = 0
        var recoveredSize: Int64 = 0
        var failedFiles: [String] = []
        var errors: [String] = []
        var deletedIDs = Set<UUID>()
        let canStart = await MainActor.run { () -> Bool in
            guard !self.isCleaning && !self.isScanning else { return false }
            self.isCleaning = true
            return true
        }
        guard canStart else {
            return DeletionResult(successCount: 0, failedCount: items.count, recoveredSize: 0,
                                  failedFiles: [], errors: ["Another file operation is running"])
        }

        let logger = Logger(subsystem: "com.appuninstaller", category: "LargeFileScanner")
        
        for file in foundFiles where items.contains(file.id) {
            do {
                try deleteFile(file.url)
                successCount += 1
                deletedIDs.insert(file.id)
                recoveredSize += file.size
                logger.info("Successfully deleted: \(file.name)")
            } catch {
                failedCount += 1
                failedFiles.append(file.name)
                let errorDescription = error.localizedDescription
                errors.append("\(file.name): \(errorDescription)")
                logger.error("Failed to delete \(file.url.path): \(error.localizedDescription)")
            }
        }
        
        // Re-scan or just remove directly from array
        let remainingFiles = foundFiles.filter { !deletedIDs.contains($0.id) }
        let newTotal = remainingFiles.reduce(0) { $0 + $1.size }
        
        let result = DeletionResult(
            successCount: successCount,
            failedCount: failedCount,
            recoveredSize: recoveredSize,
            failedFiles: failedFiles,
            errors: errors
        )
        
        // Batch UI updates
        await uiUpdater.batch {
            self.foundFiles = remainingFiles
            self.totalSize = newTotal
            self.cleanedCount += successCount
            self.cleanedSize += recoveredSize
            self.selectedFiles.subtract(deletedIDs)
            self.isCleaning = false
        }
        
        return result
    }
}

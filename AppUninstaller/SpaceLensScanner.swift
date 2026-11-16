import Foundation
import SwiftUI

// MARK: - File Node Model
class FileNode: Identifiable, ObservableObject, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    @Published var size: Int64
    let isDirectory: Bool
    @Published var children: [FileNode] = []
    @Published var childrenLoaded: Bool
    @Published var itemCountHint: Int
    weak var parent: FileNode?
    
    // UI Properties
    @Published var isSelected: Bool = false
    
    init(
        url: URL,
        name: String,
        size: Int64,
        isDirectory: Bool,
        childrenLoaded: Bool? = nil,
        itemCountHint: Int = 0
    ) {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.childrenLoaded = childrenLoaded ?? !isDirectory
        self.itemCountHint = itemCountHint
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var itemCount: Int {
        childrenLoaded ? children.count : itemCountHint
    }
    
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Scanner Service
class SpaceLensScanner: ObservableObject {
    @Published var rootNode: FileNode?
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var currentPath: String = ""
    @Published var totalSize: Int64 = 0
    @Published private(set) var inaccessiblePaths: [String] = []
    
    private let scanStateLock = NSLock()
    private var activeScanID: UUID?
    private var contentGeneration = UUID()
    private var directorySizes: [String: Int64] = [:]
    private var coverageIssues = Set<String>()
    
    func stopScan() {
        scanStateLock.withLock { activeScanID = nil; contentGeneration = UUID() }
        isScanning = false
    }
    
    func scan(targetURL: URL? = nil) async {
        guard !Task.isCancelled else { return }
        let scanID = UUID()
        scanStateLock.withLock { activeScanID = scanID; contentGeneration = scanID; directorySizes = [:]; coverageIssues = [] }

        await MainActor.run {
            self.isScanning = true
            self.scanProgress = 0
            self.totalSize = 0
            self.rootNode = nil
            self.inaccessiblePaths = []
        }
        
        // Default to Home if no URL provided, though UI usually provides one.
        let startURL = targetURL ?? FileManager.default.homeDirectoryForCurrentUser
        let root = FileNode(
            url: startURL,
            name: Self.displayName(for: startURL),
            size: 0,
            isDirectory: true,
            childrenLoaded: true
        )
        
        // Parallelize scanning for the immediate children of the startURL
        // This ensures that "Users/name" scan is fast because "Documents", "Library", etc. run in parallel.
        
        // Always enumerate the selected URL. The startup disk, external volumes and
        // custom folders therefore all reflect the Mac's current filesystem instead
        // of a baked-in list of common directories.
        let topLevelURLs = readableChildren(of: startURL, generation: scanID)
        root.itemCountHint = topLevelURLs.count
        
        // Bound root traversal rather than starting a worker for every child.
        for start in stride(from: 0, to: topLevelURLs.count, by: 4) {
            guard isScanActive(scanID), !Task.isCancelled else { break }
            let batch = Array(topLevelURLs[start..<min(start + 4, topLevelURLs.count)])
            await withTaskGroup(of: FileNode?.self) { group in
                for url in batch where url.standardizedFileURL != startURL.standardizedFileURL {
                    group.addTask {
                        guard self.isScanActive(scanID), !Task.isCancelled,
                              ScanResultIgnoreStore.shouldInclude(url), !Self.shouldSkipFilesystemNode(url) else { return nil }
                        return await self.scanDirectory(url, depth: 0, scanID: scanID)
                    }
                }
                for await node in group {
                    guard self.isScanActive(scanID), !Task.isCancelled else { group.cancelAll(); continue }
                    guard let node else { continue }
                    root.children.append(node)
                    node.parent = root
                    root.size += node.size
                    await MainActor.run {
                        guard self.isScanActive(scanID) else { return }
                        self.totalSize = root.size
                        self.currentPath = node.name
                    }
                }
            }
        }

        // Sort children by size
        root.children.sort { $0.size > $1.size }
        root.itemCountHint = root.children.count
        
        await MainActor.run {
            guard self.isScanActive(scanID) else { return }
            guard !Task.isCancelled else {
                self.isScanning = false
                self.finishScan(scanID)
                return
            }
            self.rootNode = root
            self.isScanning = false
            self.scanProgress = 1.0
            self.inaccessiblePaths = self.scanStateLock.withLock { Array(self.coverageIssues).sorted() }
            self.finishScan(scanID)
        }
    }
    
    /// Loads one real directory level when the user enters a node whose children
    /// were intentionally omitted during the initial size scan.
    func loadChildren(for node: FileNode) async {
        guard node.isDirectory, !node.childrenLoaded else { return }

        let generation = scanStateLock.withLock { contentGeneration }
        let urls = readableChildren(of: node.url, generation: generation)
        var loadedChildren: [FileNode] = []
        let batchSize = 8

        for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
            guard !Task.isCancelled, isCurrentContent(generation) else { return }
            let batchEnd = min(batchStart + batchSize, urls.count)
            let batch = Array(urls[batchStart..<batchEnd])

            await withTaskGroup(of: FileNode?.self) { group in
                for url in batch {
                    group.addTask {
                        await self.makeLazyChildNode(for: url, generation: generation)
                    }
                }

                for await child in group {
                    if let child { loadedChildren.append(child) }
                }
            }
        }

        loadedChildren.sort { $0.size > $1.size }
        let finalChildren = loadedChildren
        await MainActor.run {
            guard !Task.isCancelled, self.isCurrentContent(generation) else { return }
            self.inaccessiblePaths = self.scanStateLock.withLock { Array(self.coverageIssues).sorted() }
            node.children = finalChildren
            node.itemCountHint = finalChildren.count
            node.childrenLoaded = true
            for child in finalChildren { child.parent = node }
        }
    }

    // Recursive scan with a depth limit for retained UI nodes. Size calculation
    // still visits deeper files; their immediate nodes are created lazily.
    private func scanDirectory(_ url: URL, depth: Int, scanID: UUID) async -> FileNode? {
        guard isScanActive(scanID), !Task.isCancelled else { return nil }
        
        let fileManager = FileManager.default
        if Self.shouldSkipFilesystemNode(url) { return nil }

        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            return FileNode(
                url: url,
                name: Self.displayName(for: url),
                size: size,
                isDirectory: false
            )
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            // It's a file passed as a directory? or doesn't exist.
            // If it's a file, make a node.
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                return FileNode(url: url, name: Self.displayName(for: url), size: size, isDirectory: false)
            }
            return nil
        }
        
        let node = FileNode(
            url: url,
            name: Self.displayName(for: url),
            size: 0,
            isDirectory: true
        )

        // Include hidden files: options: []
        guard let rawItems = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
                .isDirectoryKey,
                .isPackageKey,
                .isSymbolicLinkKey
            ],
            options: []
        ) else {
            recordCoverageIssue(url, generation: scanID)
            node.childrenLoaded = true
            return node
        }

        let items = rawItems.filter {
            ScanResultIgnoreStore.shouldInclude($0) && !Self.shouldSkipFilesystemNode($0)
        }
        node.itemCountHint = items.count
        node.childrenLoaded = depth < 2 || items.isEmpty
        
        var directorySize: Int64 = 0
        
        // Optimization: Don't build FULL tree for very deep levels if not needed immediately?
        // But for visualization we kind of need it. 
        // We can limit depth for "Detailed Nodes" but keep "Size" calculation?
        // Actually, just calculating size of children is enough.
        
        for item in items {
            guard isScanActive(scanID), !Task.isCancelled else { break }
            // Check if package
            let resourceValues = try? item.resourceValues(forKeys: [
                .isDirectoryKey,
                .isPackageKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey
            ])
            let isPackage = resourceValues?.isPackage ?? false
            let isDirectory = (resourceValues?.isDirectory ?? false)
                && !(resourceValues?.isSymbolicLink ?? false)
            
            if isDirectory && !isPackage {
                // If depth < 2, we recurse to build children nodes.
                // If depth >= 2, maybe we just calculate size to save memory?
                // Visualizer needs immediate children. When user clicks, we can scan deeper?
                // "Lazy Loading" is best for Space Lens.
                // Approach: Scan 2 levels deep. Then calculate remaining size?
                // NO, we need TOTAL size. 
                // Let's recursively scan but maybe only keep `children` for top levels in memory?
                // No, Mac apps usually scan everything.
                
                // For this implementation, let's scan 3-4 levels deep efficiently? 
                // Alternatively, define a "Fast Scan" that just sums sizes for deep folders without creating FileNodes for every single file.
                
                if depth < 2 { // Build tree for top levels
                    if let childParams = await scanDirectory(item, depth: depth + 1, scanID: scanID) {
                        node.children.append(childParams)
                        childParams.parent = node
                        directorySize += childParams.size
                    }
                } else {
                    // Just calculate size
                    directorySize += await fastFolderSize(item, scanID: scanID)
                }
                
                if depth == 0 {
                    await MainActor.run {
                        guard self.isScanActive(scanID) else { return }
                        self.currentPath = item.path
                    }
                }
                
            } else {
                let size = allocatedSize(from: resourceValues)
                directorySize += size
                // Only add file nodes at top levels to avoid 1M objects
                if depth < 2 {
                    let fileNode = FileNode(
                        url: item,
                        name: Self.displayName(for: item),
                        size: size,
                        isDirectory: false
                    )
                    fileNode.parent = node
                    node.children.append(fileNode)
                }
            }
        }
        
        scanStateLock.withLock { if contentGeneration == scanID { directorySizes[url.standardizedFileURL.path] = directorySize } }
        node.size = directorySize
        node.children.sort { $0.size > $1.size }
        
        return node
    }

    private func makeLazyChildNode(for url: URL, generation: UUID) async -> FileNode? {
        guard !Task.isCancelled, isCurrentContent(generation) else { return nil }
        guard ScanResultIgnoreStore.shouldInclude(url),
              !Self.shouldSkipFilesystemNode(url) else { return nil }

        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ])
        let isDirectory = (values?.isDirectory ?? false)
            && !(values?.isPackage ?? false)
            && !(values?.isSymbolicLink ?? false)

        if isDirectory {
            let immediateChildren = readableChildren(of: url, generation: generation)
            let node = FileNode(
                url: url,
                name: Self.displayName(for: url),
                size: await fastFolderSize(url, scanID: generation),
                isDirectory: true,
                childrenLoaded: immediateChildren.isEmpty,
                itemCountHint: immediateChildren.count
            )
            return node
        }

        return FileNode(
            url: url,
            name: Self.displayName(for: url),
            size: allocatedSize(from: values),
            isDirectory: false
        )
    }

    private func readableChildren(of url: URL, generation: UUID) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isPackageKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey
            ],
            options: []
        ) else { recordCoverageIssue(url, generation: generation); return [] }

        return children.filter {
            ScanResultIgnoreStore.shouldInclude($0) && !Self.shouldSkipFilesystemNode($0)
        }
    }
    
    private func fastFolderSize(_ url: URL, scanID: UUID? = nil) async -> Int64 {
        let generation = scanID ?? scanStateLock.withLock { contentGeneration }
        let rootPath = url.standardizedFileURL.path
        if let cached = scanStateLock.withLock({ contentGeneration == generation ? directorySizes[rootPath] : nil }) { return cached }
        let worker = Task.detached(priority: .utility) { [weak self] () -> Int64 in
            guard let self else { return 0 }
            var sizes: [String: Int64] = [rootPath: 0]
            guard let enumerator = FileManager.default.enumerator(at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey], options: [],
                errorHandler: { failed, _ in self.recordCoverageIssue(failed, generation: generation); return true }) else {
                self.recordCoverageIssue(url, generation: generation)
                return 0
            }
            while let file = enumerator.nextObject() as? URL {
                guard !Task.isCancelled, self.isCurrentContent(generation) else { return 0 }
                guard let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey,
                    .isRegularFileKey, .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]) else {
                    self.recordCoverageIssue(file, generation: generation); continue
                }
                if Self.shouldSkipFilesystemNode(file) || !ScanResultIgnoreStore.shouldInclude(file) {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isDirectory == true { sizes[file.standardizedFileURL.path, default: 0] += 0 }
                else if values.isRegularFile == true {
                    sizes[file.deletingLastPathComponent().standardizedFileURL.path, default: 0] += self.allocatedSize(from: values)
                }
            }
            for path in sizes.keys.sorted(by: { $0.count > $1.count }) where path != rootPath {
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                sizes[parent, default: 0] += sizes[path] ?? 0
            }
            guard !Task.isCancelled, self.isCurrentContent(generation) else { return 0 }
            self.scanStateLock.withLock {
                if self.contentGeneration == generation { self.directorySizes.merge(sizes) { _, new in new } }
            }
            return sizes[rootPath] ?? 0
        }
        return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
    }

    func invalidateCachedSizes() {
        scanStateLock.withLock { contentGeneration = UUID(); directorySizes = [:] }
    }
    private func isCurrentContent(_ id: UUID) -> Bool { scanStateLock.withLock { contentGeneration == id } }
    private func recordCoverageIssue(_ url: URL, generation: UUID) {
        scanStateLock.withLock {
            if contentGeneration == generation { _ = coverageIssues.insert(url.path) }
        }
    }

    private func allocatedSize(from values: URLResourceValues?) -> Int64 {
        Int64(
            values?.totalFileAllocatedSize
            ?? values?.fileAllocatedSize
            ?? values?.fileSize
            ?? 0
        )
    }

    private func isScanActive(_ scanID: UUID) -> Bool {
        scanStateLock.withLock { activeScanID == scanID }
    }

    private func finishScan(_ scanID: UUID) {
        scanStateLock.withLock {
            if activeScanID == scanID { activeScanID = nil }
        }
    }

    private static func displayName(for url: URL) -> String {
        let displayName = FileManager.default.displayName(atPath: url.path)
        if !displayName.isEmpty { return displayName }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    /// Virtual/mount-point nodes can loop back into the same startup volume or
    /// duplicate the APFS data volume. They are the only filesystem entries
    /// excluded from otherwise fully dynamic directory enumeration.
    private static func shouldSkipFilesystemNode(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if ["/Volumes", "/dev", "/net", "/home", "/cores", "/.vol"].contains(path) {
            return true
        }
        return path == "/System/Volumes" || path.hasPrefix("/System/Volumes/")
    }
}

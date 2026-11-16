import Foundation
import Combine

struct DiskCapacitySnapshot: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let used: Int64
    let total: Int64
    var usage: Double { total > 0 ? min(1, max(0, Double(used) / Double(total))) : 0 }
}

class DiskSpaceManager: ObservableObject {
    @Published private(set) var history: [DiskCapacitySnapshot] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var readError: String?
    private let historyKey = "DiskCapacityHistory.v1"
    @Published var totalSize: Int64 = 0
    @Published var freeSize: Int64 = 0
    @Published var usedSize: Int64 = 0
    
    // Percentage 0.0 - 1.0
    @Published var usagePercentage: Double = 0.0
    
    static let shared = DiskSpaceManager()
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([DiskCapacitySnapshot].self, from: data) {
            history = Array(saved.suffix(96))
        }
        updateDiskSpace()
    }
    
    func updateDiskSpace() {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            
            if let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity, total > 0 {
                self.totalSize = Int64(total)
                self.freeSize = min(Int64(total), max(0, Int64(free)))
                self.usedSize = self.totalSize - self.freeSize
                
                if self.totalSize > 0 {
                    self.usagePercentage = Double(self.usedSize) / Double(self.totalSize)
                }
                lastUpdated = Date()
                readError = nil
                if history.last.map({ Date().timeIntervalSince($0.date) >= 300 }) ?? true {
                    history = Array((history + [DiskCapacitySnapshot(date: Date(), used: usedSize, total: totalSize)]).suffix(96))
                    if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: historyKey) }
                }
            } else {
                readError = "磁盘容量不可读 / Disk capacity unavailable"
            }
        } catch {
            readError = error.localizedDescription
        }
    }
    
    var isAvailable: Bool { totalSize > 0 && readError == nil }

    var formattedTotal: String {
        guard isAvailable else { return "—" }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedFree: String {
        guard isAvailable else { return "—" }
        return ByteCountFormatter.string(fromByteCount: freeSize, countStyle: .file)
    }
    
    var formattedUsed: String {
        guard isAvailable else { return "—" }
        return ByteCountFormatter.string(fromByteCount: usedSize, countStyle: .file)
    }
}

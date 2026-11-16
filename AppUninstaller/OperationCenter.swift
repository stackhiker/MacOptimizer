import SwiftUI

// A shared, bounded list of user-started work. Cancellation is requested here;
// the owner marks the final outcome only after its worker has stopped.
enum OperationState: String { case running, completed, cancelled, failed }
struct OperationRecord: Identifiable {
    let id: UUID
    let title: String
    let startedAt: Date
    var state: OperationState = .running
    var detail = ""
    var progress: Double?
}

@MainActor final class OperationCenter: ObservableObject {
    static let shared = OperationCenter()
    @Published private(set) var records: [OperationRecord] = []
    private var cancellations: [UUID: () -> Void] = [:]

    @discardableResult func begin(title: String, cancel: @escaping () -> Void) -> UUID {
        let id = UUID()
        records.insert(OperationRecord(id: id, title: title, startedAt: Date()), at: 0)
        cancellations[id] = cancel
        if records.count > 100 {
            records = Array(records.filter { $0.state == .running }.prefix(50))
                + Array(records.filter { $0.state != .running }.prefix(50))
        }
        return id
    }
    func update(id: UUID, detail: String, progress: Double? = nil) {
        guard let i = records.firstIndex(where: { $0.id == id && $0.state == .running }) else { return }
        records[i].detail = detail
        records[i].progress = progress.map { min(1, max(0, $0)) }
    }
    func finish(id: UUID, state: OperationState, detail: String) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].state = state
        records[i].detail = detail
        cancellations[id] = nil
    }
    func cancel(id: UUID) {
        update(id: id, detail: LocalizationManager.shared.text("正在停止…", "Stopping…"))
        cancellations[id]?()
    }
}

@MainActor struct OperationCenterView: View {
    @ObservedObject private var center = OperationCenter.shared
    @ObservedObject private var loc = LocalizationManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(loc.text("任务中心", "Tasks")).font(.title2.bold())
            Text(loc.text("查看本次运行的任务；停止后会保留已经完成的操作。", "Work from this session. Stopping preserves operations already completed."))
                .font(.caption).foregroundColor(.secondary)
            if center.records.isEmpty {
                Text(loc.text("暂无任务", "No tasks yet")).foregroundColor(.secondary)
            }
            List(center.records) { record in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(record.title).font(.headline)
                        Spacer()
                        if record.state == .running {
                            Button(loc.text("停止", "Stop")) { center.cancel(id: record.id) }
                        } else {
                            Text(stateText(record.state)).foregroundColor(.secondary)
                        }
                    }
                    if let progress = record.progress { ProgressView(value: progress) }
                    Text(record.detail).font(.caption).foregroundColor(.secondary)
                    Text(record.startedAt, style: .time).font(.caption2).foregroundColor(.secondary)
                }.padding(.vertical, 6)
            }.listStyle(.plain)
        }.padding(22)
    }
    private func stateText(_ state: OperationState) -> String {
        switch state {
        case .running: return loc.text("进行中", "Running")
        case .completed: return loc.text("已完成", "Completed")
        case .cancelled: return loc.text("已停止", "Stopped")
        case .failed: return loc.text("未全部完成", "Incomplete")
        }
    }
}

import Foundation
import SwiftUI

struct TaskRecord: Identifiable {
    let id = UUID()
    let title: String
    var step: String
    var sent: Int64 = 0
    var total: Int64 = 0
    var state: String = MTPShuttleText.localized("Running")
    let started = Date()

    var fraction: Double? {
        total > 0 ? min(1, max(0, Double(sent) / Double(total))) : nil
    }
}

@MainActor
final class TaskActivityStore: ObservableObject {
    static let shared = TaskActivityStore()
    @Published private(set) var current: TaskRecord?
    @Published private(set) var history: [TaskRecord] = []
    @Published private(set) var cancellationRequested = false
    private var completedBytes: Int64 = 0
    private var segmentSent: Int64 = 0
    private var segmentTotal: Int64 = 0

    func begin(_ title: String, total: Int64) {
        completedBytes = 0
        segmentSent = 0
        segmentTotal = 0
        cancellationRequested = false
        current = TaskRecord(title: title, step: MTPShuttleText.localized("Preparing transfer"), total: total)
    }

    func step(_ text: String) { current?.step = text }

    func record(_ title: String, state: String) {
        var record = TaskRecord(title: title, step: state)
        record.state = state
        history.insert(record, at: 0)
    }

    func progress(name: String, sent: Int64, total: Int64) {
        guard !cancellationRequested, current != nil else { return }
        segmentSent = max(0, sent)
        segmentTotal = max(segmentTotal, total)
        current?.step = name.isEmpty ? MTPShuttleText.localized("Transferring") : "\(MTPShuttleText.localized("Transferring")): \(name)"
        if let knownTotal = current?.total, knownTotal > 0 {
            current?.sent = min(knownTotal, completedBytes + segmentSent)
        } else {
            current?.sent = completedBytes + segmentSent
        }
    }

    func finishSegment() {
        // A successful native call confirms its last reported byte total even
        // when the periodic progress callback missed the final update.
        completedBytes += max(segmentSent, segmentTotal)
        segmentSent = 0
        segmentTotal = 0
        if let total = current?.total {
            current?.sent = total > 0 ? min(total, completedBytes) : completedBytes
        }
    }

    func cancel() {
        guard current != nil else { return }
        cancellationRequested = true
        current?.step = MTPShuttleText.localized("Cancelling…")
        KalamBridge.shared.cancelCurrentOperation()
    }

    func finish(_ state: String) {
        guard var record = current else { return }
        record.state = state
        if state == "已完成", record.total > 0 { record.sent = record.total }
        history.insert(record, at: 0)
        current = nil
        cancellationRequested = false
    }
}

struct TaskDetailsView: View {
    @ObservedObject private var tasks = TaskActivityStore.shared
    @AppStorage("appLanguage") private var appLanguage = MTPShuttleLanguage.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Task Details").font(.title2.bold())
            if let task = tasks.current {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title).font(.headline)
                    Text(task.step)
                    if let fraction = task.fraction {
                        ProgressView(value: fraction)
                        Text("\(ByteCountFormatter.string(fromByteCount: task.sent, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: task.total, countStyle: .file))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text(String(format: MTPShuttleText.localized("Transferred %@ · Total unknown"), ByteCountFormatter.string(fromByteCount: task.sent, countStyle: .file)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Cancel Operation") { tasks.cancel() }
                        .disabled(tasks.cancellationRequested)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
            Text("Completed operations in this session").font(.headline)
            if tasks.history.isEmpty {
                Text("No operations yet").foregroundStyle(.secondary)
            } else {
                List(tasks.history) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(task.title) · \(stateText(task.state))")
                        Text("\(task.step) · \(task.started.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 480, minHeight: 360)
        .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
    }

    private func stateText(_ state: String) -> String {
        if state == "已完成" { return MTPShuttleText.localized("Completed") }
        if state == "已取消" { return MTPShuttleText.localized("Cancelled") }
        if state == "运行中" { return MTPShuttleText.localized("Running") }
        if state.hasPrefix("失败：") { return "\(MTPShuttleText.localized("Failed")): \(state.dropFirst(3))" }
        return state
    }
}

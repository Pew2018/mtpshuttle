import Foundation
import SwiftUI

struct TaskRecord: Identifiable {
    let id = UUID()
    let title: String
    var step: String
    var sent: Int64 = 0
    var total: Int64 = 0
    var state: String = "运行中"
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

    func begin(_ title: String, total: Int64) {
        completedBytes = 0
        segmentSent = 0
        cancellationRequested = false
        current = TaskRecord(title: title, step: "准备传输", total: total)
    }

    func step(_ text: String) { current?.step = text }

    func progress(name: String, sent: Int64, total: Int64) {
        guard !cancellationRequested, current != nil else { return }
        segmentSent = max(0, sent)
        current?.step = name.isEmpty ? "正在传输" : "正在传输：\(name)"
        if current!.total == 0 { current?.total = max(0, total) }
        current?.sent = min(current!.total, completedBytes + segmentSent)
    }

    func finishSegment() {
        completedBytes += segmentSent
        segmentSent = 0
        if let total = current?.total { current?.sent = min(total, completedBytes) }
    }

    func cancel() {
        guard current != nil else { return }
        cancellationRequested = true
        current?.step = "正在取消…"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("任务详情").font(.title2.bold())
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
                        Text("正在计算文件大小").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("取消操作") { tasks.cancel() }
                        .disabled(tasks.cancellationRequested)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
            Text("本次启动已完成的操作").font(.headline)
            if tasks.history.isEmpty {
                Text("暂无操作").foregroundStyle(.secondary)
            } else {
                List(tasks.history) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(task.title) · \(task.state)")
                        Text("\(task.step) · \(task.started.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 480, minHeight: 360)
    }
}

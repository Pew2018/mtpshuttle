import Foundation
import SwiftUI

struct TaskItemRecord: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let total: Int64
    var sent: Int64 = 0
    var state: String = "等待中"
    var speedBytesPerSecond: Double = 0
    var etaSeconds: TimeInterval?
    var errorMessage: String?
    let started = Date()

    var fraction: Double? {
        total > 0 ? min(1, max(0, Double(sent) / Double(total))) : nil
    }
}

struct TaskRecord: Identifiable {
    let id = UUID()
    let title: String
    var step: String
    var sent: Int64 = 0
    var total: Int64 = 0
    var state: String = "运行中"
    var items: [TaskItemRecord] = []
    var currentItemIndex: Int?
    var speedBytesPerSecond: Double = 0
    var etaSeconds: TimeInterval?
    var failureReason: String?
    let started = Date()

    var fraction: Double? {
        total > 0 ? min(1, max(0, Double(sent) / Double(total))) : nil
    }

    var currentItem: TaskItemRecord? {
        guard let currentItemIndex, items.indices.contains(currentItemIndex) else { return nil }
        return items[currentItemIndex]
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
    private var lastProgressDate: Date?
    private var lastProgressSent: Int64 = 0

    func begin(_ title: String, total: Int64) {
        completedBytes = 0
        segmentSent = 0
        segmentTotal = 0
        lastProgressDate = nil
        lastProgressSent = 0
        cancellationRequested = false
        current = TaskRecord(title: title, step: "准备传输", total: max(0, total))
    }

    func addItems(_ items: [(name: String, path: String, total: Int64)]) {
        guard current != nil else { return }
        current?.items.append(contentsOf: items.map {
            TaskItemRecord(name: $0.name, path: $0.path, total: max(0, $0.total))
        })
    }

    func beginItem(name: String, path: String, total: Int64) {
        guard var task = current else { return }

        let index: Int
        if let existing = task.items.firstIndex(where: {
            $0.name == name && $0.path == path && $0.state == "等待中"
        }) {
            index = existing
        } else {
            task.items.append(TaskItemRecord(name: name, path: path, total: max(0, total)))
            index = task.items.count - 1
        }

        task.currentItemIndex = index
        task.items[index].state = "传输中"
        task.items[index].errorMessage = nil
        task.items[index].speedBytesPerSecond = 0
        task.items[index].etaSeconds = nil
        segmentSent = 0
        segmentTotal = 0
        lastProgressDate = nil
        lastProgressSent = 0
        task.step = "正在传输：\(name)"
        current = task
    }

    func step(_ text: String) {
        current?.step = text
    }

    func record(_ title: String, state: String) {
        var record = TaskRecord(title: title, step: state)
        record.state = state
        history.insert(record, at: 0)
    }

    func progress(name: String, sent: Int64, total: Int64) {
        guard !cancellationRequested, var task = current else { return }

        if task.currentItemIndex == nil {
            let fallbackName = name.isEmpty ? "当前文件" : URL(fileURLWithPath: name).lastPathComponent
            beginItem(name: fallbackName, path: name, total: total)
            guard let refreshed = current else { return }
            task = refreshed
        }

        guard let index = task.currentItemIndex, task.items.indices.contains(index) else { return }

        let now = Date()
        let reportedSent = max(0, sent)
        let reportedTotal = max(total, task.items[index].total)
        let previousSent = task.items[index].sent
        task.items[index].sent = reportedTotal > 0
            ? min(reportedTotal, max(previousSent, reportedSent))
            : max(previousSent, reportedSent)
        task.items[index].state = "传输中"
        segmentSent = task.items[index].sent
        segmentTotal = reportedTotal

        if let lastProgressDate, now.timeIntervalSince(lastProgressDate) > 0.05 {
            let deltaBytes = max(0, task.items[index].sent - lastProgressSent)
            let deltaTime = now.timeIntervalSince(lastProgressDate)
            if deltaBytes > 0 {
                let speed = Double(deltaBytes) / deltaTime
                task.items[index].speedBytesPerSecond = speed
                task.speedBytesPerSecond = speed
            }
        }
        lastProgressDate = now
        lastProgressSent = task.items[index].sent

        task.step = name.isEmpty
            ? "正在传输：\(task.items[index].name)"
            : "正在传输：\(URL(fileURLWithPath: name).lastPathComponent)"

        let itemRemaining = max(0, reportedTotal - task.items[index].sent)
        task.items[index].etaSeconds = task.items[index].speedBytesPerSecond > 0
            ? Double(itemRemaining) / task.items[index].speedBytesPerSecond
            : nil
        let overallRemaining = task.total > 0 ? max(0, task.total - completedBytes - task.items[index].sent) : 0
        task.etaSeconds = task.speedBytesPerSecond > 0 && task.total > 0
            ? Double(overallRemaining) / task.speedBytesPerSecond
            : nil
        task.sent = task.total > 0
            ? min(task.total, completedBytes + task.items[index].sent)
            : completedBytes + task.items[index].sent
        current = task
    }

    func finishSegment() {
        guard var task = current,
              let index = task.currentItemIndex,
              task.items.indices.contains(index) else {
            return
        }

        if task.items[index].total > 0 {
            task.items[index].sent = min(task.items[index].total, max(task.items[index].sent, segmentTotal))
        } else {
            task.items[index].sent = max(task.items[index].sent, segmentSent)
        }
        task.sent = task.total > 0
            ? min(task.total, completedBytes + task.items[index].sent)
            : completedBytes + task.items[index].sent
        segmentSent = 0
        segmentTotal = 0
        current = task
    }

    func completeCurrentItem() {
        guard var task = current,
              let index = task.currentItemIndex,
              task.items.indices.contains(index) else {
            return
        }

        let itemBytes = task.items[index].total > 0
            ? task.items[index].total
            : task.items[index].sent
        task.items[index].sent = itemBytes
        task.items[index].state = "已完成"
        task.items[index].etaSeconds = 0
        completedBytes += max(0, itemBytes)
        task.sent = task.total > 0 ? min(task.total, completedBytes) : completedBytes
        task.currentItemIndex = nil
        task.etaSeconds = nil
        current = task
    }

    func failCurrentItem(_ message: String) {
        guard var task = current,
              let index = task.currentItemIndex,
              task.items.indices.contains(index) else {
            return
        }

        task.items[index].state = "失败"
        task.items[index].errorMessage = message
        task.failureReason = message
        task.step = "失败：\(message)"
        task.currentItemIndex = nil
        current = task
    }

    func cancelCurrentItem() {
        guard var task = current,
              let index = task.currentItemIndex,
              task.items.indices.contains(index) else {
            return
        }

        task.items[index].state = "已取消"
        task.items[index].errorMessage = "用户取消了传输"
        task.step = "操作已取消"
        task.currentItemIndex = nil
        current = task
    }

    func cancel() {
        guard current != nil else { return }
        cancellationRequested = true
        current?.state = "取消中"
        current?.step = "正在取消…"
        KalamBridge.shared.cancelCurrentOperation()
    }

    func finish(_ state: String) {
        guard var record = current else { return }

        if state == "已完成" {
            record.sent = record.total > 0 ? record.total : record.sent
            for index in record.items.indices where record.items[index].state == "传输中" {
                record.items[index].state = "已完成"
                if record.items[index].total > 0 {
                    record.items[index].sent = record.items[index].total
                }
            }
        }
        record.state = state
        record.currentItemIndex = nil
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
                currentTaskView(task)
            }

            Text("本次启动已完成的操作").font(.headline)
            if tasks.history.isEmpty {
                Text("暂无操作").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks.history) { task in
                            historyTaskView(task)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 480)
    }

    @ViewBuilder
    private func currentTaskView(_ task: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(task.title).font(.headline)
                Spacer()
                Text(task.state).foregroundStyle(.secondary)
            }

            Text(task.step)
                .font(.subheadline)

            ProgressView(value: task.fraction)
            Text("\(byteText(task.sent)) / \(byteText(task.total))")
                .font(.caption.monospacedDigit())

            HStack(spacing: 14) {
                Text("速度：\(speedText(task.speedBytesPerSecond))")
                Text("预计剩余：\(etaText(task.etaSeconds))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let item = task.currentItem {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前文件：\(item.name)").font(.subheadline.weight(.semibold))
                    Text("目录：\(item.path)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("\(byteText(item.sent)) / \(byteText(item.total)) · \(item.state)")
                        .font(.caption.monospacedDigit())
                }
            }

            if !task.items.isEmpty {
                Divider()
                Text("任务列表").font(.subheadline.weight(.semibold))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(task.items) { item in
                            taskItemRow(item)
                        }
                    }
                }
                .frame(maxHeight: 190)
            }

            if let failureReason = task.failureReason {
                Text("失败原因：\(failureReason)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Button("取消操作") { tasks.cancel() }
                .disabled(tasks.cancellationRequested)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func historyTaskView(_ task: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(task.title) · \(task.state)")
            Text("\(task.items.count) 个文件 · \(task.step)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let failureReason = task.failureReason {
                Text("失败原因：\(failureReason)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func taskItemRow(_ item: TaskItemRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.name).lineLimit(1)
                Spacer()
                Text(item.state).foregroundStyle(.secondary)
            }
            Text(item.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                if let fraction = item.fraction {
                    ProgressView(value: fraction)
                        .frame(maxWidth: 150)
                }
                Text("\(byteText(item.sent)) / \(byteText(item.total))")
                if let errorMessage = item.errorMessage {
                    Text(errorMessage).foregroundStyle(.red).lineLimit(1)
                }
            }
            .font(.caption2.monospacedDigit())
        }
        .padding(.vertical, 3)
    }

    private func byteText(_ value: Int64) -> String {
        guard value > 0 else { return "未知" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func speedText(_ value: Double) -> String {
        guard value > 0 else { return "计算中" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file))/s"
    }

    private func etaText(_ value: TimeInterval?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "暂不可用" }
        let seconds = Int(value.rounded())
        if seconds < 60 { return "\(seconds) 秒" }
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}

#Preview { TaskDetailsView() }

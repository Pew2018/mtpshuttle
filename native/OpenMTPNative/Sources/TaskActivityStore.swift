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
    var state: String = MTPShuttleText.localized("Running")
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
        current = TaskRecord(title: title, step: MTPShuttleText.localized("Preparing transfer"), total: max(0, total))
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
        task.step = MTPShuttleText.localized("Transferring") + ": \(name)"
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

        let fileName = name.isEmpty ? task.items[index].name : URL(fileURLWithPath: name).lastPathComponent
        task.step = MTPShuttleText.format("Transferring: %@", fileName)

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
        task.step = MTPShuttleText.localized("Failed:") + message
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
        task.step = MTPShuttleText.localized("Operation cancelled")
        task.currentItemIndex = nil
        current = task
    }

    func cancel() {
        guard current != nil else { return }
        cancellationRequested = true
        current?.state = "取消中"
        current?.step = MTPShuttleText.localized("Cancelling…")
        KalamBridge.shared.cancelCurrentOperation()
    }

    func finish(_ state: String) {
        guard var record = current else { return }

        if state == MTPShuttleText.localized("Completed") || state == "已完成" {
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
    @Environment(\.locale) private var locale
    @State private var isHistoryExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let task = tasks.current {
                    currentTaskView(task)
                } else {
                    emptyState
                }

                if !tasks.history.isEmpty {
                    DisclosureGroup(isExpanded: $isHistoryExpanded) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(tasks.history) { task in
                                historyTaskView(task)
                            }
                        }
                        .padding(.top, 10)
                    } label: {
                        Label(MTPShuttleText.localized("Recent Activity"), systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 540, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .background(.quaternary, in: Circle())

            Text(MTPShuttleText.localized("No active transfer"))
                .font(.title3.weight(.semibold))

            Text(MTPShuttleText.localized("Your recent transfers will appear here."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func currentTaskView(_ task: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(task.step)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(displayStatus(task.state))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint(task.state))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusTint(task.state).opacity(0.12), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(MTPShuttleText.localized("Overall transfer progress"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let fraction = task.fraction {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }

                progressBar(task.fraction)
                    .controlSize(.regular)
                    .accessibilityLabel(Text("Overall transfer progress"))

                HStack {
                    Text("\(byteText(task.sent)) / \(byteText(task.total))")
                    Spacer()
                    Text(MTPShuttleText.format("%d items", task.items.count))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                metricCard(
                    title: MTPShuttleText.localized("Speed"),
                    value: speedText(task.speedBytesPerSecond),
                    symbol: "speedometer"
                )
                metricCard(
                    title: MTPShuttleText.localized("Estimated remaining"),
                    value: etaText(task.etaSeconds),
                    symbol: "clock"
                )
            }

            if let item = progressItem(for: task) {
                currentFileView(item, showsProgress: task.items.count > 1)
            }

            if let failureReason = task.failureReason {
                Label {
                    Text(MTPShuttleText.localized("Failure reason") + ": " + failureReason)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack {
                Spacer()
                Button(role: .destructive) {
                    tasks.cancel()
                } label: {
                    Label("Cancel Operation", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .disabled(tasks.cancellationRequested)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func metricCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func currentFileView(_ item: TaskItemRecord, showsProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(Color.accentColor)
                Text(MTPShuttleText.localized("Current file"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(displayStatus(item.state))
                    .font(.caption)
                    .foregroundStyle(statusTint(item.state))
            }

            Text(item.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .textSelection(.enabled)

            Text(item.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            if showsProgress {
                progressBar(item.fraction)
                    .accessibilityLabel(Text("Current file progress"))
                HStack {
                    Text("\(byteText(item.sent)) / \(byteText(item.total))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let fraction = item.fraction {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.caption.monospacedDigit().weight(.medium))
                    }
                }
            }

            if let errorMessage = item.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder
    private func progressBar(_ fraction: Double?) -> some View {
        if let fraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    private func progressItem(for task: TaskRecord) -> TaskItemRecord? {
        task.currentItem ?? task.items.first(where: { $0.state == "等待中" })
    }

    private func historyTaskView(_ task: TaskRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.state == "已完成" ? "checkmark.circle.fill" : "arrow.left.arrow.right.circle")
                .font(.title3)
                .foregroundStyle(statusTint(task.state))

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(MTPShuttleText.format("%d items", task.items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let failureReason = task.failureReason {
                    Text(MTPShuttleText.localized("Failure reason") + ": " + failureReason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            Text(displayStatus(task.state))
                .font(.caption.weight(.medium))
                .foregroundStyle(statusTint(task.state))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusTint(_ status: String) -> Color {
        switch status {
        case "已完成": return .green
        case "失败": return .red
        case "已取消", "取消中": return .orange
        default: return Color.accentColor
        }
    }

    private func displayStatus(_ status: String) -> String {
        let key: String
        switch status {
        case "等待中": key = "Waiting"
        case "传输中": key = "Transferring"
        case "已完成": key = "Completed"
        case "失败": key = "Failed"
        case "已取消": key = "Cancelled"
        case "取消中": key = "Cancelling"
        default: return status
        }
        return MTPShuttleText.localized(key)
    }

    private func byteText(_ value: Int64) -> String {
        guard value > 0 else { return MTPShuttleText.localized("Unknown") }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func speedText(_ value: Double) -> String {
        guard value > 0 else { return MTPShuttleText.localized("Calculating") }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file))/s"
    }

    private func etaText(_ value: TimeInterval?) -> String {
        guard let value, value.isFinite, value >= 0 else {
            return MTPShuttleText.localized("Not available")
        }
        var formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: value) ?? MTPShuttleText.localized("Not available")
    }
}

#Preview { TaskDetailsView() }

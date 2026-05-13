import Combine
import Darwin
import Foundation
import SwiftUI

public final class SpatialConsoleLogger {
    public static let windowID = "SpatialConsoleLoggerWindow"

    public let tag: String

    private let token: String

    public init(
        tag: String,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tag = trimmedTag.isEmpty ? "Console" : trimmedTag
        self.token = "[\(self.tag)]"

        SpatialConsoleLogStore.shared.register(tag: self.tag)

        if captureStandardOutput {
            SpatialConsoleCapture.shared.start()
        }

        if openWindow {
            SpatialConsoleWindowRequests.shared.requestOpen(tag: self.tag)
        }
    }

    public func log(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        let message = items.map { String(describing: $0) }.joined(separator: separator)
        print("\(token) \(message)", terminator: terminator)
    }
}

public struc: Scene {
    public init() {}

    public var body: some Scene {
        WindowGroup(id: SpatialConsoleLogger.windowID, for: String.self) { tag in
            SpatialConsoleLogWindow(tag: tag.wrappedValue ?? "Console")
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.72, height: 0.48, depth: 0.06, in: .meters)
    }
}

public extension View {
    func spatialConsoleWindowPresenter() -> some View {
        modifier(SpatialConsoleWindowPresenter())
    }
}

private struct SpatialConsoleWindowPresenter: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear(perform: openPendingWindows)
            .onReceive(NotificationCenter.default.publisher(for: SpatialConsoleWindowRequests.openRequestedNotification)) { notification in
                guard let tag = notification.object as? String else { return }
                SpatialConsoleWindowRequests.shared.markOpened(tag: tag)
                openWindow(id: SpatialConsoleLogger.windowID, value: tag)
            }
    }

    private func openPendingWindows() {
        for tag in SpatialConsoleWindowRequests.shared.drainPendingTags() {
            openWindow(id: SpatialConsoleLogger.windowID, value: tag)
        }
    }
}

private struct SpatialConsoleLogWindow: View {
    let tag: String

    @ObservedObject private var store = SpatialConsoleLogStore.shared

    private var entries: [SpatialConsoleEntry] {
        store.entries.filter { $0.hasExactTag(tag) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("[\(tag)]")
                        .font(.title2.weight(.semibold))
                        .monospaced()

                    Text("Spatial Console")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.clear(tag: tag)
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Clear")
            }

            Divider()

            if entries.isEmpty {
                Spacer()
                Text("Waiting for [\(tag)] output")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                SpatialConsoleLogList(entries: entries)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 360)
        .glassBackgroundEffect()
    }
}

private struct SpatialConsoleLogList: View {
    let entries: [SpatialConsoleEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in
                        SpatialConsoleLogRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .onAppear {
                scrollToBottom(with: proxy)
            }
            .onChange(of: entries.last?.id) {
                scrollToBottom(with: proxy)
            }
        }
    }

    private func scrollToBottom(with proxy: ScrollViewProxy) {
        guard let lastID = entries.last?.id else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct SpatialConsoleLogRow: View {
    let entry: SpatialConsoleEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.date.formatted(.dateTime.hour().minute().second()))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

private struct SpatialConsoleEntry: Identifiable, Hashable {
    let id = UUID()
    let date = Date()
    let message: String

    func hasExactTag(_ tag: String) -> Bool {
        message.contains("[\(tag)]")
    }
}

private final class SpatialConsoleLogStore: ObservableObject {
    static let shared = SpatialConsoleLogStore()

    @Published private(set) var entries: [SpatialConsoleEntry] = []
    @Published private(set) var tags: Set<String> = []

    private let maxEntries = 1_000

    private init() {}

    func register(tag: String) {
        DispatchQueue.main.async {
            self.tags.insert(tag)
        }
    }

    func append(_ line: String) {
        DispatchQueue.main.async {
            self.entries.append(SpatialConsoleEntry(message: line))

            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear(tag: String) {
        entries.removeAll { $0.hasExactTag(tag) }
    }
}

private final class SpatialConsoleWindowRequests {
    static let shared = SpatialConsoleWindowRequests()
    static let openRequestedNotification = Notification.Name("SpatialConsoleLoggerOpenRequested")

    private var pendingTags: Set<String> = []
    private let lock = NSLock()

    private init() {}

    func requestOpen(tag: String) {
        lock.lock()
        pendingTags.insert(tag)
        lock.unlock()

        NotificationCenter.default.post(
            name: Self.openRequestedNotification,
            object: tag
        )
    }

    func drainPendingTags() -> [String] {
        lock.lock()
        let tags = Array(pendingTags)
        pendingTags.removeAll()
        lock.unlock()

        return tags.sorted()
    }

    func markOpened(tag: String) {
        lock.lock()
        pendingTags.remove(tag)
        lock.unlock()
    }
}

private final class SpatialConsoleCapture {
    static let shared = SpatialConsoleCapture()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "SpatialConsoleCapture.queue")
    private let pipe = Pipe()

    private var isRunning = false
    private var originalStdout: Int32 = -1
    private var bufferedText = ""

    private init() {}

    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }
        isRunning = true

        originalStdout = dup(STDOUT_FILENO)

        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)

        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            self?.write(data, to: self?.originalStdout ?? -1)
            self?.queue.async {
                self?.process(data)
            }
        }
    }

    private func process(_ data: Data) {
        bufferedText += String(decoding: data, as: UTF8.self)

        var completedLines: [String] = []

        while let newline = bufferedText.rangeOfCharacter(from: .newlines) {
            let line = String(bufferedText[..<newline.lowerBound])
            bufferedText.removeSubrange(bufferedText.startIndex..<newline.upperBound)

            if !line.isEmpty {
                completedLines.append(line)
            }
        }

        for line in completedLines {
            SpatialConsoleLogStore.shared.append(line)
        }
    }

    private func write(_ data: Data, to fileDescriptor: Int32) {
        guard fileDescriptor >= 0 else { return }

        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else { return }

            var remainingBytes = rawBuffer.count

            while remainingBytes > 0 {
                let writtenBytes = Darwin.write(fileDescriptor, pointer, remainingBytes)
                guard writtenBytes > 0 else { return }

                remainingBytes -= writtenBytes
                pointer = pointer.advanced(by: writtenBytes)
            }
        }
    }
}

// Drop-in spatial console logger for visionOS apps.

import Combine
import Darwin
import Foundation
import SwiftUI

public final class SpatialConsoleLogger {
    public static let windowID = "SpatialConsoleLoggerWindow"

    public let tag: String
    public let opensWindowOnAppear: Bool

    private let token: String

    public init(
        tag: String,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tag = trimmedTag.isEmpty ? "Console" : trimmedTag
        self.opensWindowOnAppear = openWindow
        self.token = "[\(self.tag)]"

        let registeredTag = self.tag
        Task { @MainActor in
            SpatialConsoleLogStore.shared.register(tag: registeredTag)
        }

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

    public func show() {
        SpatialConsoleWindowRequests.shared.requestOpen(tag: tag)
    }
}

public struct SpatialConsoleWindowGroup<Content: View>: Scene {
    private let id: String
    private let logger: SpatialConsoleLogger
    private let content: () -> Content

    public init(
        id: String,
        tag: String,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.logger = SpatialConsoleLogger(
            tag: tag,
            openWindow: openWindow,
            captureStandardOutput: captureStandardOutput
        )
        self.content = content
    }

    public var body: some Scene {
        WindowGroup(id: id) {
            content()
                .spatialConsoleLogger(logger)
        }

        SpatialConsoleLoggerScene()
    }
}

public struct SpatialConsoleLoggerWindowScene: Scene {
    public init() {}

    public var body: some Scene {
        WindowGroup("Your app is behind this window.", id: SpatialConsoleLogger.windowID, for: String.self) { tag in
            SpatialConsoleLogWindow(tag: tag.wrappedValue ?? "Console")
        }
        .defaultSize(
            width: SpatialConsoleWindowMetrics.minimumWidth,
            height: SpatialConsoleWindowMetrics.minimumHeight
        )
        .windowResizability(.contentSize)
    }
}

public typealias SpatialConsoleLoggerScene = SpatialConsoleLoggerWindowScene

public extension View {
    func spatialConsoleWindowPresenter() -> some View {
        modifier(SpatialConsoleWindowPresenter(initialLogger: nil))
    }

    func spatialConsoleLogger(_ logger: SpatialConsoleLogger) -> some View {
        modifier(SpatialConsoleWindowPresenter(initialLogger: logger))
    }

    func spatialConsoleLogger(
        tag: String,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) -> some View {
        modifier(
            SpatialConsoleTaggedWindowPresenter(
                tag: tag,
                openWindow: openWindow,
                captureStandardOutput: captureStandardOutput
            )
        )
    }
}

private struct SpatialConsoleTaggedWindowPresenter: ViewModifier {
    @Environment(\.openWindow) private var openWindowAction

    let tag: String
    let openWindow: Bool
    let captureStandardOutput: Bool

    @State private var logger: SpatialConsoleLogger?
    @State private var didCreateLogger = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                createLoggerIfNeeded()
                openPendingWindows()
            }
            .task {
                createLoggerIfNeeded()
                openPendingWindows()
            }
            .onReceive(NotificationCenter.default.publisher(for: SpatialConsoleWindowRequests.openRequestedNotification)) { notification in
                guard let tag = notification.object as? String else { return }
                SpatialConsoleWindowRequests.shared.markOpened(tag: tag)
                openWindowAction(id: SpatialConsoleLogger.windowID, value: tag)
            }
    }

    private func createLoggerIfNeeded() {
        guard !didCreateLogger else { return }
        didCreateLogger = true

        let logger = SpatialConsoleLogger(
            tag: tag,
            openWindow: false,
            captureStandardOutput: captureStandardOutput
        )
        self.logger = logger

        if openWindow {
            logger.show()
        }
    }

    private func openPendingWindows() {
        for tag in SpatialConsoleWindowRequests.shared.drainPendingTags() {
            openWindowAction(id: SpatialConsoleLogger.windowID, value: tag)
        }
    }
}

private struct SpatialConsoleWindowPresenter: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    let initialLogger: SpatialConsoleLogger?

    @State private var didRequestInitialWindow = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                requestInitialWindowIfNeeded()
                openPendingWindows()
            }
            .task {
                requestInitialWindowIfNeeded()
                openPendingWindows()
            }
            .onReceive(NotificationCenter.default.publisher(for: SpatialConsoleWindowRequests.openRequestedNotification)) { notification in
                guard let tag = notification.object as? String else { return }
                SpatialConsoleWindowRequests.shared.markOpened(tag: tag)
                openWindow(id: SpatialConsoleLogger.windowID, value: tag)
            }
    }

    private func requestInitialWindowIfNeeded() {
        guard !didRequestInitialWindow else { return }
        didRequestInitialWindow = true
        guard initialLogger?.opensWindowOnAppear == true else { return }
        initialLogger?.show()
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
    @State private var isPaused = false
    @State private var pausedEntries: [SpatialConsoleEntry] = []

    private var entries: [SpatialConsoleEntry] {
        store.entries.filter { $0.hasExactTag(tag) }
    }

    private var visibleEntries: [SpatialConsoleEntry] {
        isPaused ? pausedEntries : entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your app is behind this window.")
                        .font(.headline.weight(.semibold))

                    Text("[\(tag)]")
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    togglePause()
                } label: {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                }
                .labelStyle(.iconOnly)
                .help(isPaused ? "Resume" : "Pause")

                Button {
                    store.clear(tag: tag)
                    pausedEntries.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Clear")
            }

            Divider()

            if visibleEntries.isEmpty {
                Spacer()
                Text("Waiting for [\(tag)] output")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                SpatialConsoleLogList(entries: visibleEntries, autoScrolls: !isPaused)
            }
        }
        .padding(24)
        .frame(
            minWidth: SpatialConsoleWindowMetrics.minimumWidth,
            minHeight: SpatialConsoleWindowMetrics.minimumHeight
        )
        .spatialConsoleBackground()
    }

    private func togglePause() {
        if isPaused {
            isPaused = false
            pausedEntries.removeAll()
        } else {
            pausedEntries = entries
            isPaused = true
        }
    }
}

private enum SpatialConsoleWindowMetrics {
    static let minimumWidth: CGFloat = 720
    static let minimumHeight: CGFloat = 520
}

private extension View {
    @ViewBuilder
    func spatialConsoleBackground() -> some View {
        #if os(visionOS)
        glassBackgroundEffect()
        #else
        self
        #endif
    }
}

private struct SpatialConsoleLogList: View {
    let entries: [SpatialConsoleEntry]
    let autoScrolls: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
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
                guard autoScrolls else { return }
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

@MainActor
private final class SpatialConsoleLogStore: ObservableObject {
    static let shared = SpatialConsoleLogStore()

    @Published private(set) var entries: [SpatialConsoleEntry] = []
    @Published private(set) var tags: Set<String> = []

    private let maxEntries = 1_000

    private init() {}

    func register(tag: String) {
        tags.insert(tag)
    }

    func append(_ line: String) {
        entries.append(SpatialConsoleEntry(message: line))

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear(tag: String) {
        entries.removeAll { $0.hasExactTag(tag) }
    }
}

private final class SpatialConsoleWindowRequests: @unchecked Sendable {
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

nonisolated private final class SpatialConsoleCapture: @unchecked Sendable {
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
            guard let self else { return }

            let data = handle.availableData
            guard !data.isEmpty else { return }

            let outputFileDescriptor = self.originalStdout
            self.write(data, to: outputFileDescriptor)

            self.queue.async { [weak self] in
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

        guard !completedLines.isEmpty else { return }

        Task { @MainActor in
            for line in completedLines {
                SpatialConsoleLogStore.shared.append(line)
            }
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

// Drop-in spatial console logger for visionOS apps.

import Combine
import Darwin
import Foundation
import SwiftUI

public final class SpatialConsoleLogger {
    public static let windowID = "SpatialConsoleLoggerWindow"

    public let tag: String
    public let tags: [String]
    public let opensWindowOnAppear: Bool

    private let token: String

    public convenience init(
        tag: String,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) {
        self.init(
            normalizedTags: Self.normalizedTags([tag]),
            openWindow: openWindow,
            captureStandardOutput: captureStandardOutput
        )
    }

    public convenience init(
        tags: String...,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) {
        self.init(
            normalizedTags: Self.normalizedTags(tags),
            openWindow: openWindow,
            captureStandardOutput: captureStandardOutput
        )
    }

    public convenience init(
        tags: [String],
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) {
        self.init(
            normalizedTags: Self.normalizedTags(tags),
            openWindow: openWindow,
            captureStandardOutput: captureStandardOutput
        )
    }

    public convenience init(
        _ tags: String...,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) {
        self.init(
            normalizedTags: Self.normalizedTags(tags),
            openWindow: openWindow,
            captureStandardOutput: captureStandardOutput
        )
    }

    private init(
        normalizedTags: [String],
        openWindow: Bool,
        captureStandardOutput: Bool
    ) {
        self.tags = normalizedTags
        self.tag = normalizedTags[0]
        self.opensWindowOnAppear = openWindow
        self.token = "[\(self.tag)]"

        let registeredTags = self.tags
        Task { @MainActor in
            SpatialConsoleLogStore.shared.register(tags: registeredTags)
        }

        if captureStandardOutput {
            SpatialConsoleCapture.shared.start()
        }

        if openWindow {
            SpatialConsoleWindowRequests.shared.requestOpen(tags: self.tags)
        }
    }

    public func log(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        let message = items.map { String(describing: $0) }.joined(separator: separator)
        print("\(token) \(message)", terminator: terminator)
    }

    public func show() {
        SpatialConsoleWindowRequests.shared.requestOpen(tags: tags)
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var uniqueTags: [String] = []
        var seenTags = Set<String>()

        for tag in tags {
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty, !seenTags.contains(trimmedTag) else { continue }

            uniqueTags.append(trimmedTag)
            seenTags.insert(trimmedTag)
        }

        return uniqueTags.isEmpty ? ["Console"] : uniqueTags
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

    public init(
        id: String,
        tags: String...,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.logger = SpatialConsoleLogger(
            tags: tags,
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
        WindowGroup("Your app is behind this window.", id: SpatialConsoleLogger.windowID, for: [String].self) { tags in
            SpatialConsoleLogWindow(tags: tags.wrappedValue ?? ["Console"])
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
                tags: [tag],
                openWindow: openWindow,
                captureStandardOutput: captureStandardOutput
            )
        )
    }

    func spatialConsoleLogger(
        tags: String...,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) -> some View {
        modifier(
            SpatialConsoleTaggedWindowPresenter(
                tags: tags,
                openWindow: openWindow,
                captureStandardOutput: captureStandardOutput
            )
        )
    }

    func spatialConsoleLogger(
        _ tags: String...,
        openWindow: Bool = true,
        captureStandardOutput: Bool = true
    ) -> some View {
        modifier(
            SpatialConsoleTaggedWindowPresenter(
                tags: tags,
                openWindow: openWindow,
                captureStandardOutput: captureStandardOutput
            )
        )
    }
}

private struct SpatialConsoleTaggedWindowPresenter: ViewModifier {
    @Environment(\.openWindow) private var openWindowAction

    let tags: [String]
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
                guard let tags = notification.object as? [String] else { return }
                SpatialConsoleWindowRequests.shared.markOpened(tags: tags)
                openWindowAction(id: SpatialConsoleLogger.windowID, value: tags)
            }
    }

    private func createLoggerIfNeeded() {
        guard !didCreateLogger else { return }
        didCreateLogger = true

        let logger = SpatialConsoleLogger(
            tags: tags,
            openWindow: false,
            captureStandardOutput: captureStandardOutput
        )
        self.logger = logger

        if openWindow {
            logger.show()
        }
    }

    private func openPendingWindows() {
        for tags in SpatialConsoleWindowRequests.shared.drainPendingTags() {
            openWindowAction(id: SpatialConsoleLogger.windowID, value: tags)
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
                guard let tags = notification.object as? [String] else { return }
                SpatialConsoleWindowRequests.shared.markOpened(tags: tags)
                openWindow(id: SpatialConsoleLogger.windowID, value: tags)
            }
    }

    private func requestInitialWindowIfNeeded() {
        guard !didRequestInitialWindow else { return }
        didRequestInitialWindow = true
        guard initialLogger?.opensWindowOnAppear == true else { return }
        initialLogger?.show()
    }

    private func openPendingWindows() {
        for tags in SpatialConsoleWindowRequests.shared.drainPendingTags() {
            openWindow(id: SpatialConsoleLogger.windowID, value: tags)
        }
    }
}

private struct SpatialConsoleLogWindow: View {
    let tags: [String]

    @ObservedObject private var store = SpatialConsoleLogStore.shared
    @State private var isPaused = false
    @State private var pausedEntries: [SpatialConsoleEntry] = []

    private var entries: [SpatialConsoleEntry] {
        store.entries.filter { $0.hasAnyTag(tags) }
    }

    private var visibleEntries: [SpatialConsoleEntry] {
        isPaused ? pausedEntries : entries
    }

    private var tagLabel: String {
        tags.map { "[\($0)]" }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your app is behind this window.")
                        .font(.headline.weight(.semibold))

                    Text(tagLabel)
                        .font(.caption)
                        .monospaced()
                        .lineLimit(2)
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
                    store.clear(tags: tags)
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
                Text("Waiting for \(tagLabel) output")
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

    func hasAnyTag(_ tags: [String]) -> Bool {
        tags.contains { hasExactTag($0) }
    }
}

@MainActor
private final class SpatialConsoleLogStore: ObservableObject {
    static let shared = SpatialConsoleLogStore()

    @Published private(set) var entries: [SpatialConsoleEntry] = []
    @Published private(set) var tags: Set<String> = []

    private let maxEntries = 1_000

    private init() {}

    func register(tags: [String]) {
        self.tags.formUnion(tags)
    }

    func append(_ line: String) {
        entries.append(SpatialConsoleEntry(message: line))

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear(tags: [String]) {
        entries.removeAll { $0.hasAnyTag(tags) }
    }
}

private final class SpatialConsoleWindowRequests: @unchecked Sendable {
    static let shared = SpatialConsoleWindowRequests()
    static let openRequestedNotification = Notification.Name("SpatialConsoleLoggerOpenRequested")

    private var pendingTags: Set<[String]> = []
    private let lock = NSLock()

    private init() {}

    func requestOpen(tags: [String]) {
        lock.lock()
        pendingTags.insert(tags)
        lock.unlock()

        NotificationCenter.default.post(
            name: Self.openRequestedNotification,
            object: tags
        )
    }

    func drainPendingTags() -> [[String]] {
        lock.lock()
        let tags = Array(pendingTags)
        pendingTags.removeAll()
        lock.unlock()

        return tags.sorted { $0.joined(separator: "\u{1F}") < $1.joined(separator: "\u{1F}") }
    }

    func markOpened(tags: [String]) {
        lock.lock()
        pendingTags.remove(tags)
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

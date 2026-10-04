import AppKit
@testable import ScreenText
import Testing

/// Native windows, focus, cursors, and hotkeys share process-wide desktop state.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct DesktopTests {}

/// Buffered signals allow an event to arrive before or after its waiter.
final class TestSignal: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (self.stream, self.continuation) = AsyncStream.makeStream()
    }

    func signal() {
        self.continuation.yield(())
    }

    func wait(for context: String = "test signal", timeout: Duration = .seconds(10)) async throws {
        try Task.checkCancellation()
        let stream = self.stream
        try await withThrowingTaskGroup(of: Void.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                let event: Void? = await iterator.next()
                try Task.checkCancellation()
                try #require(event != nil, "Signal ended while waiting for \(context)")
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TestWaitError.timedOut(context)
            }
            try await group.next()
        }
    }

    deinit { continuation.finish() }
}

enum TestWaitError: Error, Equatable, CustomStringConvertible {
    case timedOut(String)

    var description: String {
        switch self {
        case let .timedOut(context): "Timed out waiting for \(context)"
        }
    }
}

@MainActor
final class PasteboardFixture {
    let board = NSPasteboard(name: .init("com.screentext.tests.\(UUID())"))

    var service: ClipboardService {
        ClipboardService(pasteboard: self.board)
    }

    func pastedText() throws -> String {
        let editor = NSTextView(frame: .init(x: 0, y: 0, width: 600, height: 400))
        editor.isRichText = false
        try #require(editor.readSelection(from: self.board))
        return editor.string
    }

    isolated deinit { board.releaseGlobally() }
}

@MainActor
final class SettingsFixture {
    private let domain = "com.screentext.tests.\(UUID())"
    let defaults: UserDefaults
    let settings: SettingsStore

    init(storedMode: String? = nil) throws {
        self.defaults = try #require(UserDefaults(suiteName: self.domain))
        if let storedMode {
            self.defaults.set(storedMode, forKey: "lastSelectionMode")
        }
        self.settings = SettingsStore(persistence: SettingsPersistence(defaults: self.defaults))
    }

    func restoredSettings() -> SettingsStore {
        SettingsStore(persistence: SettingsPersistence(defaults: self.defaults))
    }

    var storedKeys: [String] {
        self.defaults.persistentDomain(forName: self.domain)?.keys.sorted() ?? []
    }

    isolated deinit { defaults.removePersistentDomain(forName: domain) }
}

enum TestImages {
    static func colored(width: Int = 100, height: Int = 60, topAlpha: CGFloat = 1) throws -> CGImage {
        let context = try self.context(width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: topAlpha))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return try #require(context.makeImage())
    }

    @MainActor
    static func text(_ lines: [String], dark: Bool = false, positions: [CGPoint]? = nil) throws -> CGImage {
        if let positions {
            try #require(positions.count == lines.count)
        }
        let context = try self.context(width: 900, height: 300)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (dark ? NSColor.black : NSColor.white).setFill()
        CGRect(x: 0, y: 0, width: 900, height: 300).fill()
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: positions?[index] ?? .init(x: 30, y: 220 - index * 35), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
                .foregroundColor: dark ? NSColor.white : NSColor.black,
            ])
        }
        return try #require(context.makeImage())
    }

    static func context(width: Int, height: Int) throws -> CGContext {
        try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,
        ))
    }
}

@MainActor
enum NativeMouse {
    static func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow? = nil) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1,
        ))
    }
}

@MainActor
enum NativeWindow {
    static func waitUntilFocused(_ window: NSWindow) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        let signal = TestSignal()
        let center = NotificationCenter.default
        let observers = [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                         NSApplication.didBecomeActiveNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in signal.signal() }
        }
        defer { observers.forEach(center.removeObserver) }
        while !window.isKeyWindow || !window.isMainWindow || !NSApp.isActive {
            try await signal.wait(
                for: "window focus (key: \(window.isKeyWindow), main: \(window.isMainWindow), active: \(NSApp.isActive))",
                timeout: clock.now.duration(to: deadline),
            )
        }
    }
}

@MainActor
final class TestClipboardWriter: ClipboardWriting {
    private(set) var texts: [String] = []
    private(set) var attempts: [String] = []
    var fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    func copy(_ text: String) throws -> Bool {
        self.attempts.append(text)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if self.fails {
            throw ClipboardError.writeFailed
        }
        self.texts.append(text)
        return true
    }
}

struct FixedTextRecognizer: TextRecognizing {
    let text: String
    func recognizeText(from _: CGImage) async throws -> String {
        self.text
    }
}

/// Each native test owns its helper recognizer; preparation and recognition use that same instance.
struct NativeOCRFixture {
    let accurateRecognizer = AccurateOCR()

    func makeService(preparer: (any OCRPreparing)? = nil) -> OCRService {
        OCRService(
            accurateRecognizer: self.accurateRecognizer,
            fastRecognizer: VisionOCR(level: .fast),
            preparer: preparer ?? self.accurateRecognizer,
        )
    }
}

struct TestOCRPreparer: OCRPreparing {
    var preparation: @Sendable () async throws -> Void = {}

    func prepare() async throws {
        try await self.preparation()
    }
}

actor SuspendedOCRPreparer: OCRPreparing {
    private var continuation: CheckedContinuation<Void, Error>?
    private let started = TestSignal()
    private let cancelled = TestSignal()

    func prepare() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation {
                self.continuation = $0
                self.started.signal()
            }
            try Task.checkCancellation()
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func waitUntilStarted() async throws {
        try await self.started.wait(for: "OCR preparation to start")
    }

    func waitUntilCancelled() async throws {
        try await self.cancelled.wait(for: "OCR preparation to cancel")
    }

    func finish(_ result: Result<Void, Error> = .success(())) throws {
        let continuation = self.continuation
        let pending = try #require(continuation)
        self.continuation = nil
        pending.resume(with: result)
    }

    private func cancel() {
        self.continuation?.resume(throwing: CancellationError())
        self.continuation = nil
        self.cancelled.signal()
    }
}

struct TestTextRecognizer: TextRecognizing {
    func recognizeText(from _: CGImage) async throws -> String {
        "Recognized fixture"
    }
}

struct TestScreenCaptureService: ScreenCapturing {
    func capture(region _: Selection) async throws -> CGImage {
        try TestImages.colored()
    }
}

actor SuspendedCaptureService: ScreenCapturing {
    private var continuation: CheckedContinuation<CGImage, Error>?
    private let started = TestSignal()

    func capture(region _: Selection) async throws -> CGImage {
        try await withCheckedThrowingContinuation {
            self.continuation = $0
            self.started.signal()
        }
    }

    func waitUntilStarted() async throws {
        try await self.started.wait(for: "screen capture to start")
    }

    func finish(_ result: Result<CGImage, Error>) throws {
        let continuation = self.continuation
        let pending = try #require(continuation)
        self.continuation = nil
        pending.resume(with: result)
    }

    func releasePendingProcessing() {
        self.continuation?.resume(throwing: CancellationError())
        self.continuation = nil
    }
}

actor SuspendedTextRecognizer: TextRecognizing {
    private var continuation: CheckedContinuation<String, Error>?
    private let started = TestSignal()

    func recognizeText(from _: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation {
            self.continuation = $0
            self.started.signal()
        }
    }

    func waitUntilStarted() async throws {
        try await self.started.wait(for: "text recognition to start")
    }

    func finish(_ result: Result<String, Error>) throws {
        let continuation = self.continuation
        let pending = try #require(continuation)
        self.continuation = nil
        pending.resume(with: result)
    }

    func releasePendingProcessing() {
        self.continuation?.resume(throwing: CancellationError())
        self.continuation = nil
    }
}

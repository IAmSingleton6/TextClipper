import AppKit

enum ClipboardError: Error, Equatable {
    case writeFailed
}

@MainActor
protocol ClipboardWriting {
    @discardableResult
    func copy(_ text: String) throws -> Bool
}

@MainActor
protocol TextPasteboard: AnyObject {
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: TextPasteboard {}

@MainActor
struct ClipboardService: ClipboardWriting {
    private let pasteboard: any TextPasteboard

    init(pasteboard: any TextPasteboard = NSPasteboard.general) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func copy(_ text: String) throws -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        _ = self.pasteboard.clearContents()
        guard self.pasteboard.setString(text, forType: .string) else { throw ClipboardError.writeFailed }
        return true
    }
}

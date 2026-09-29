import AppKit
import ScreenCaptureKit

/// Excludes capture overlays while keeping the app's ordinary windows visible.
enum CaptureWindowFilter {
    static func makeContentFilter(for display: SCDisplay, from content: SCShareableContent) async -> SCContentFilter {
        let visibleWindowIDs = await MainActor.run {
            Self.capturableWindowIDs(in: NSApp.windows)
        }
        let processID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == processID }
        let includedOwnWindows = content.windows.filter {
            $0.owningApplication?.processID == processID && visibleWindowIDs.contains($0.windowID)
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: includedOwnWindows,
        )
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }
        return filter
    }

    @MainActor
    private static func capturableWindowIDs(in windows: [NSWindow]) -> Set<CGWindowID> {
        Set(windows.compactMap { window -> CGWindowID? in
            guard !(window is NSPanel), !(window is SelectionWindow) else { return nil }
            return self.capturableWindowID(for: window.windowNumber)
        })
    }

    private static func capturableWindowID(for number: Int) -> CGWindowID? {
        guard number > 0 else { return nil }
        return CGWindowID(exactly: number)
    }
}

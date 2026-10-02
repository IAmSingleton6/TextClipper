import AppKit
import SwiftUI

@MainActor
protocol CaptureToolbarPresenting: AnyObject {
    var cursorExclusionRect: CGRect? { get }
    func show(display: SelectionDisplay, model: CaptureToolbarModel,
              onAction: @escaping (CaptureToolbarAction) -> Void) -> Bool
    func hide()
}

extension CaptureToolbarPresenting {
    var cursorExclusionRect: CGRect? {
        nil
    }
}

@MainActor
final class CaptureToolbarWindow: NSPanel, CaptureToolbarPresenting {
    var cursorExclusionRect: CGRect? {
        isVisible ? frame : nil
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "ScreenText Capture"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    func show(display: SelectionDisplay, model: CaptureToolbarModel,
              onAction: @escaping (CaptureToolbarAction) -> Void) -> Bool
    {
        let view = CaptureToolbarView(model: model, onAction: onAction)
        let hostingView = CaptureToolbarHostingView(rootView: view)
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
        setFrame(Self.positionedFrame(size: frame.size, visibleFrame: display.visibleFrame), display: true)
        // Ordering without activation leaves the user's current application focused.
        orderFrontRegardless()
        displayIfNeeded()
        self.updateCaptureCursor()
        // Hosting-view layout and window ordering can reset the cursor later
        // in this event. Apply it again once that work has completed.
        DispatchQueue.main.async { [weak self] in
            guard let self, isVisible else { return }
            self.updateCaptureCursor()
        }
        return true
    }

    private func updateCaptureCursor() {
        (frame.contains(NSEvent.mouseLocation) ? NSCursor.arrow : NSCursor.crosshair).set()
    }

    func hide() {
        orderOut(nil)
        contentView = nil
    }

    static func positionedFrame(size: NSSize, visibleFrame: NSRect) -> NSRect {
        let bottomMargin: CGFloat = 24
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: min(visibleFrame.minY + bottomMargin, visibleFrame.maxY - size.height),
            width: size.width,
            height: size.height,
        )
    }
}

private final class CaptureToolbarHostingView: NSHostingView<CaptureToolbarView> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with _: NSEvent) {
        NSCursor.crosshair.set()
    }
}

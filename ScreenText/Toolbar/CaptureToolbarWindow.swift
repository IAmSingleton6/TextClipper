import AppKit
import SwiftUI

@MainActor
protocol CaptureToolbarPresenting: AnyObject {
    var cursorExclusionRect: ScreenRect? { get }

    func show(
        display: SelectionDisplay,
        mode: CaptureMode,
        onAction: @escaping (CaptureToolbarAction) -> Void,
    ) -> Bool
    func setMode(_ mode: CaptureMode)
    func hide()
}

extension CaptureToolbarPresenting {
    var cursorExclusionRect: ScreenRect? {
        nil
    }
}

@MainActor
final class CaptureToolbarWindow: NSPanel, CaptureToolbarPresenting {
    var cursorExclusionRect: ScreenRect? {
        isVisible ? ScreenRect(appKitGlobalRect: frame) : nil
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
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

    func show(
        display: SelectionDisplay,
        mode: CaptureMode,
        onAction: @escaping (CaptureToolbarAction) -> Void,
    ) -> Bool {
        let view = CaptureToolbarView(mode: mode, onAction: onAction)
        let hostingView = CaptureToolbarHostingView(rootView: view)
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
        setFrame(
            Self.positionedFrame(size: frame.size, visibleFrame: display.visibleFrame).appKitGlobalRect,
            display: true,
        )
        orderFrontRegardless()
        displayIfNeeded()

        hostingView.updateCaptureCursor()
        // AppKit may reset the cursor as window ordering finishes.
        DispatchQueue.main.async { [weak hostingView] in
            hostingView?.updateCaptureCursor()
        }
        return true
    }

    func setMode(_ mode: CaptureMode) {
        guard let hostingView = contentView as? CaptureToolbarHostingView else { return }
        hostingView.rootView = CaptureToolbarView(mode: mode, onAction: hostingView.rootView.onAction)
    }

    func hide() {
        orderOut(nil)
        contentView = nil
    }

    static func positionedFrame(size: NSSize, visibleFrame: ScreenRect) -> ScreenRect {
        let bottomMargin: CGFloat = 24
        return ScreenRect(
            x: visibleFrame.midX - size.width / 2,
            y: min(visibleFrame.minY + bottomMargin, visibleFrame.maxY - size.height),
            width: size.width,
            height: size.height,
        )
    }
}

private final class CaptureToolbarHostingView: NSHostingView<CaptureToolbarView> {
    func updateCaptureCursor() {
        guard let window, window.isVisible else { return }
        (window.frame.contains(NSEvent.mouseLocation) ? NSCursor.arrow : NSCursor.crosshair).set()
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil,
            ),
        )
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

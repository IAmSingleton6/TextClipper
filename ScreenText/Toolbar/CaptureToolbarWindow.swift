import AppKit
import SwiftUI

@MainActor
protocol CaptureToolbarPresenting: AnyObject {
    func show(display: SelectionDisplay, model: CaptureToolbarModel, onModeSelected: @escaping (CaptureMode) -> Void, onCancel: @escaping () -> Void) -> Bool
    func hide()
}

@MainActor
final class CaptureToolbarWindow: NSPanel, CaptureToolbarPresenting {
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(display: SelectionDisplay, model: CaptureToolbarModel, onModeSelected: @escaping (CaptureMode) -> Void, onCancel: @escaping () -> Void) -> Bool {
        let view = CaptureToolbarView(model: model, onModeSelected: onModeSelected, onCancel: onCancel)
        let hostingView = CaptureToolbarHostingView(rootView: view)
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
        setFrame(Self.positionedFrame(size: frame.size, visibleFrame: display.visibleFrame), display: true)
        // Ordering without activation leaves the user's current application focused.
        orderFrontRegardless()
        return true
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
            height: size.height
        )
    }
}

private final class CaptureToolbarHostingView: NSHostingView<CaptureToolbarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

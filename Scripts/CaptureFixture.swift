// Run separately from ScreenText so its application exclusion leaves this
// synthetic content visible. No desktop pixels or clipboard data are saved.
import AppKit

@MainActor
final class FixtureView: NSView {
    override func draw(_: NSRect) {
        NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height / 2).fill()
        NSColor(displayP3Red: 0, green: 0, blue: 1, alpha: 1).setFill()
        CGRect(x: 0, y: bounds.height / 2, width: bounds.width, height: bounds.height / 2).fill()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens[0]
let rect = CGRect(x: screen.frame.midX - 160, y: screen.frame.midY - 120, width: 320, height: 240)
let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
window.title = "ScreenText Capture Test Fixture"
window.level = .floating
window.hasShadow = false
window.isReleasedWhenClosed = false
window.contentView = FixtureView(frame: CGRect(origin: .zero, size: rect.size))
window.orderFrontRegardless()
print("Capture fixture ready. Quit this process after running the live test.")
app.run()

import AppKit

// Keep the delegate alive for the lifetime of the application's event loop.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()

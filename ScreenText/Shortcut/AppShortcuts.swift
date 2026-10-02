import KeyboardShortcuts

enum AppShortcuts {
    static let captureText = KeyboardShortcuts.Name(
        "captureText",
        initial: .init(.two, modifiers: [.command, .shift]),
    )
}

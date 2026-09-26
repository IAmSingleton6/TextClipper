@MainActor
final class CaptureController {
    private(set) var isActive = false
    var onActivityChanged: ((Bool) -> Void)?

    func toggle() {
        if isActive {
            cancel()
        } else {
            start()
        }
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        onActivityChanged?(true)
        // Phase 3 will show the capture toolbar here.
    }

    func cancel() {
        guard isActive else { return }
        isActive = false
        onActivityChanged?(false)
    }
}

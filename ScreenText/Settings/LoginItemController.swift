import ServiceManagement
import Observation

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor private struct AppLoginItem: LoginItemManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor @Observable
final class LoginItemController {
    private let service: any LoginItemManaging
    private(set) var status: SMAppService.Status
    private(set) var message: String?
    var isOn: Bool { status == .enabled || status == .requiresApproval }

    init(service: (any LoginItemManaging)? = nil) {
        let service = service ?? AppLoginItem()
        self.service = service
        status = service.status
    }

    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) {
        message = nil
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            message = "Could not change launch at login. Please try again."
        }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

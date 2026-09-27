import Observation
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor private struct AppLoginItem: LoginItemManaging {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor @Observable
final class LoginItemController {
    private let service: any LoginItemManaging
    private(set) var status: SMAppService.Status
    private(set) var message: String?
    var isOn: Bool {
        self.status == .enabled || self.status == .requiresApproval
    }

    init(service: (any LoginItemManaging)? = nil) {
        let service = service ?? AppLoginItem()
        self.service = service
        self.status = service.status
    }

    func refresh() {
        self.status = self.service.status
    }

    func setEnabled(_ enabled: Bool) {
        self.message = nil
        do {
            if enabled {
                try self.service.register()
            } else {
                try self.service.unregister()
            }
        } catch {
            self.message = "Could not change launch at login. Please try again."
        }
        self.refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

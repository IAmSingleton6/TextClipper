import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var login: LoginItemController

    var body: some View {
        Form {
            Section("General") {
                KeyboardShortcuts.Recorder("Shortcut", name: .captureText)
                Toggle("Launch at login", isOn: Binding(get: { login.isOn }, set: { login.setEnabled($0) }))
                if login.status == .requiresApproval {
                    Text("Allow ScreenText in Login Items to finish enabling launch at login.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items") { login.openSystemSettings() }
                }
                if let message = login.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Capture") {
                Picker("Default selection", selection: $settings.defaultMode) {
                    Text("Box").tag(CaptureMode.box)
                    Text("Draw").tag(CaptureMode.freehand)
                }.pickerStyle(.radioGroup)
            }
            Section("Feedback") {
                Toggle("Show captured text", isOn: $settings.showCapturedText)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 430)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }
}

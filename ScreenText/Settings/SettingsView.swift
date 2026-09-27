import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var login: LoginItemController
    @Bindable var permissions: PermissionManager

    var body: some View {
        Form {
            Section {
                Text(
                    "ScreenText lives in your menu bar. Use the shortcut or choose Capture Text to select an area and copy its text.",
                )
                .font(.callout).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent(
                    "Screen Recording",
                    value: self.permissions.hasScreenRecordingAccess ? "Enabled" : "Required",
                )
                Text(
                    "Allow ScreenText to read text from your screen. After enabling access in System Settings, you may need to quit and reopen ScreenText.",
                )
                .font(.caption).foregroundStyle(.secondary)
                if self.permissions.hasScreenRecordingAccess {
                    Button("Open Screen Recording Settings") { self.permissions.openScreenRecordingSettings() }
                } else {
                    Button("Enable Screen Recording…") { self.permissions.enableScreenRecording() }
                }
            }
            Section("General") {
                KeyboardShortcuts.Recorder("Shortcut", name: .captureText)
                Toggle("Launch at login", isOn: Binding(get: { self.login.isOn }, set: { self.login.setEnabled($0) }))
                if self.login.status == .requiresApproval {
                    Text("Allow ScreenText in Login Items to finish enabling launch at login.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items") { self.login.openSystemSettings() }
                }
                if let message = login.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Feedback") {
                Toggle("Show captured text", isOn: self.$settings.showCapturedText)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 620)
        .onAppear {
            self.login.refresh()
            self.permissions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.login.refresh()
            self.permissions.refresh()
        }
    }
}

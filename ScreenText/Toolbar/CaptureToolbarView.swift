import SwiftUI

@MainActor @Observable
final class CaptureToolbarModel {
    var mode: CaptureMode = .box
}

struct CaptureToolbarView: View {
    let model: CaptureToolbarModel
    let onModeSelected: (CaptureMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            modeButton(.box, title: "Box", symbol: "rectangle.dashed")
            modeButton(.circle, title: "Circle", symbol: "circle.dashed")

            Divider()
                .frame(height: 24)
                .padding(.horizontal, 4)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel capture")
            .help("Cancel (Esc)")
            .keyboardShortcut(.cancelAction)
        }
        .padding(8)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .fixedSize()
    }

    private func modeButton(_ mode: CaptureMode, title: String, symbol: String) -> some View {
        Button {
            onModeSelected(mode)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(model.mode == mode ? 0.2 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) selection")
        .accessibilityValue(model.mode == mode ? "Selected" : "Not selected")
        .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
        .help("\(title) selection")
    }
}

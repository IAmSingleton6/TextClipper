import SwiftUI

@MainActor @Observable
final class CaptureToolbarModel {
    var mode: CaptureMode = .box
}

struct CaptureToolbarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredMode: CaptureMode?
    @State private var hoveringCancel = false

    let model: CaptureToolbarModel
    let onModeSelected: (CaptureMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            modeButton(.box, title: "Box", symbol: "rectangle.dashed")
            modeButton(.freehand, title: "Draw", symbol: "lasso")

            Divider()
                .frame(height: 24)
                .padding(.horizontal, 4)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 34)
                    .background(.white.opacity(hoveringCancel ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringCancel = $0 }
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.mode)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredMode)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveringCancel)
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
                        .fill(.white.opacity(model.mode == mode ? 0.22 : (hoveredMode == mode ? 0.1 : 0)))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredMode = mode }
            else if hoveredMode == mode { hoveredMode = nil }
        }
        .accessibilityLabel("\(title) selection")
        .accessibilityValue(model.mode == mode ? "Selected" : "Not selected")
        .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
        .help(mode == .freehand ? "Click and hold to draw around text" : "Box selection")
    }
}

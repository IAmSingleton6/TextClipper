import SwiftUI

enum CaptureToolbarAction {
    case selectMode(CaptureMode)
    case cancel
}

@MainActor @Observable
final class CaptureToolbarModel {
    var mode: CaptureMode = .box
}

struct CaptureToolbarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredMode: CaptureMode?
    @State private var hoveringCancel = false

    let model: CaptureToolbarModel
    let onAction: (CaptureToolbarAction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(
                action: {
                    self.onAction(.cancel)
                },
                label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 34)
                        .background(.white.opacity(self.hoveringCancel ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
            )
            .buttonStyle(.plain)
            .onHover { self.hoveringCancel = $0 }
            .accessibilityLabel("Cancel capture")
            .help("Cancel (Esc)")
            .keyboardShortcut(.cancelAction)

            Divider()
                .frame(height: 24)
                .padding(.horizontal, 4)

            self.modeButton(.box, title: "Box", symbol: "rectangle.dashed")
            self.modeButton(.freehand, title: "Draw", symbol: "lasso")
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
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.12), value: self.model.mode)
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.12), value: self.hoveredMode)
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.12), value: self.hoveringCancel)
    }

    private func modeButton(_ mode: CaptureMode, title: String, symbol: String) -> some View {
        Button {
            self.onAction(.selectMode(mode))
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(self.model.mode == mode ? 0.22 : (self.hoveredMode == mode ? 0.1 : 0)))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                self.hoveredMode = mode
            } else if self.hoveredMode == mode {
                self.hoveredMode = nil
            }
        }
        .accessibilityLabel("\(title) selection")
        .accessibilityValue(self.model.mode == mode ? "Selected" : "Not selected")
        .accessibilityAddTraits(self.model.mode == mode ? .isSelected : [])
        .help(mode == .freehand ? "Click and hold to draw around text" : "Box selection")
    }
}

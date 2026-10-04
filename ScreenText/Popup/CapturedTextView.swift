import AppKit
import SwiftUI

struct CapturedTextView: View {
    private static let padding: CGFloat = 16
    private static let buttonSize: CGFloat = 20
    private static let spacing: CGFloat = 12

    let previewText: String
    let onDismiss: () -> Void
    private let textWidth: CGFloat

    init(text: String, maximumWidth: CGFloat = 640, onDismiss: @escaping () -> Void) {
        let limit = 600
        self.previewText = text.count > limit ? String(text.prefix(limit)) + "…" : text
        self.onDismiss = onDismiss

        let widestLine = self.previewText.components(separatedBy: .newlines).map {
            ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        }.max() ?? 0
        let insets = Self.padding * 2 + Self.buttonSize + Self.spacing
        let width = min(640, maximumWidth, max(320, ceil(widestLine) + insets))
        self.textWidth = max(1, width - insets)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            Text(self.previewText)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .truncationMode(.tail)
                .frame(width: self.textWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Captured text preview")
                .accessibilityValue(self.previewText)

            Button(action: self.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss captured text preview")
            .help("Dismiss preview")
        }
        .padding(Self.padding)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

import SwiftUI

struct CapturedTextView: View {
    let previewText: String

    init(text: String) {
        let limit = 600
        self.previewText = text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    var body: some View {
        Text(self.previewText)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .lineLimit(4)
            .truncationMode(.tail)
            .frame(width: 288, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .accessibilityLabel("Captured text preview")
            .accessibilityValue(self.previewText)
    }
}

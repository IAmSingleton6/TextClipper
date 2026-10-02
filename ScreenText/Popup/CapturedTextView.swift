import SwiftUI

struct CapturedTextView: View {
    let previewText: String

    init(text: String) {
        let limit = 600
        previewText = text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    var body: some View {
        Text(previewText)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .lineLimit(4)
            .truncationMode(.tail)
            .frame(width: 288, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Captured text preview")
            .accessibilityValue(previewText)
    }
}

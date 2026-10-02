import Foundation
import CoreGraphics

struct RecognizedTextBlock: Sendable {
    let text: String
    // Vision-normalized coordinates, with a bottom-left origin.
    let bounds: CGRect
}

struct OCRTextProcessor {
    func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func text(from blocks: [RecognizedTextBlock]) -> String {
        // Sort first, then group rows. A fuzzy pairwise sort comparator can be
        // nontransitive when glyph heights differ, so use fixed row anchors.
        let ordered = blocks.filter { !clean($0.text).isEmpty }.sorted {
            if $0.bounds.maxY != $1.bounds.maxY { return $0.bounds.maxY > $1.bounds.maxY }
            return $0.bounds.minX < $1.bounds.minX
        }
        var rows: [[RecognizedTextBlock]] = []
        for block in ordered {
            if let index = rows.indices.min(by: {
                abs(rows[$0][0].bounds.midY - block.bounds.midY)
                    < abs(rows[$1][0].bounds.midY - block.bounds.midY)
            }), abs(rows[index][0].bounds.midY - block.bounds.midY)
                <= min(rows[index][0].bounds.height, block.bounds.height) * 0.5 {
                rows[index].append(block)
            } else {
                rows.append([block])
            }
        }
        var result = ""
        for index in rows.indices {
            if index > 0 {
                let above = rows[index - 1][0].bounds
                let current = rows[index][0].bounds
                let gap = above.minY - current.maxY
                result += gap > max(above.height, current.height) * 0.8 ? "\n\n" : "\n"
            }
            result += rows[index].sorted { $0.bounds.minX < $1.bounds.minX }
                .map { clean($0.text) }.joined(separator: " ")
        }
        return clean(result)
    }
}

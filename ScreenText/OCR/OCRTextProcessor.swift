import CoreGraphics
import Foundation

struct RecognizedTextBlock: Sendable {
    let text: String
    /// Vision-normalized coordinates, with a bottom-left origin.
    let bounds: CGRect
}

struct OCRTextProcessor {
    func text(from blocks: [RecognizedTextBlock]) -> String {
        let sanitisedBlocks = self.cleanBlocks(blocks)
        let sortedBlocks = self.sortBlocksTopToBottomLeftToRight(sanitisedBlocks)
        let blocksInRows = self.groupBlocksIntoRows(sortedBlocks)
        return self.buildText(from: blocksInRows)
    }

    private func cleanBlocks(_ blocks: [RecognizedTextBlock]) -> [RecognizedTextBlock] {
        blocks.compactMap { block in
            let text = self.normaliseText(block.text)
            guard !text.isEmpty else { return nil }
            return RecognizedTextBlock(text: text, bounds: block.bounds)
        }
    }

    private func sortBlocksTopToBottomLeftToRight(
        _ blocks: [RecognizedTextBlock],
    ) -> [RecognizedTextBlock] {
        blocks.sorted {
            if $0.bounds.midY != $1.bounds.midY {
                return $0.bounds.midY > $1.bounds.midY
            }

            return $0.bounds.minX < $1.bounds.minX
        }
    }

    private func groupBlocksIntoRows(
        _ blocks: [RecognizedTextBlock],
    ) -> [[RecognizedTextBlock]] {
        var rows: [[RecognizedTextBlock]] = []

        for block in blocks {
            guard
                let lastRow = rows.last,
                let anchor = lastRow.first
            else {
                rows.append([block])
                continue
            }

            let distance = abs(anchor.bounds.midY - block.bounds.midY)
            let threshold = min(anchor.bounds.height, block.bounds.height) * 0.5

            if distance <= threshold {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }

        return rows
    }

    private func buildText(from rows: [[RecognizedTextBlock]]) -> String {
        var result = ""

        for index in rows.indices {
            if index > 0 {
                result += self.separatorBetweenRows(
                    above: rows[index - 1],
                    current: rows[index],
                )
            }
            result += rows[index].map(\.text).joined(separator: " ")
        }

        return self.normaliseText(result)
    }

    private func separatorBetweenRows(
        above: [RecognizedTextBlock],
        current: [RecognizedTextBlock],
    ) -> String {
        let aboveBounds = above[0].bounds
        let currentBounds = current[0].bounds
        let gap = aboveBounds.minY - currentBounds.maxY
        let paragraphThreshold = max(aboveBounds.height, currentBounds.height) * 0.8

        return gap > paragraphThreshold ? "\n\n" : "\n"
    }

    private func normaliseText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

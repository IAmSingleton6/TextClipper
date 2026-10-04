import Foundation

/// Sequential helper-side recognition loop receiving images from AccurateOCRConnection.
/// Warms and reuses its own VisionOCREngine until the app closes its input pipe.
func runAccurateOCR() -> Int32 {
    guard let image = OCRPreparationImage.make() else { return 1 }
    let engine = VisionOCREngine(level: .accurate)

    do {
        let text = try engine.recognizeText(from: image)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 1 }

        try AccurateOCRProtocol.write(Data([0]), to: .standardOutput)
        while let data = try AccurateOCRProtocol.read(from: .standardInput) {
            let response: Data
            do {
                let image = try AccurateOCRProtocol.decode(data)
                response = try Data([0]) + Data(engine.recognizeText(from: image).utf8)
            } catch {
                response = Data([1])
            }
            try AccurateOCRProtocol.write(response, to: .standardOutput)
        }
        return 0
    } catch {
        return 1
    }
}

exit(runAccurateOCR())

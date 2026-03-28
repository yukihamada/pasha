import Vision
import UIKit

struct OCRResult {
    var amount: Int?
    var date: Date?
    var vendor: String?
    var category: String?
    var confidence: OCRConfidence = OCRConfidence()
    var rawLines: [String] = []
}

struct OCRConfidence {
    var amount: Float = 0
    var date: Float = 0
    var vendor: Float = 0

    /// Overall confidence (0..1). Low if any critical field is missing.
    var overall: Float {
        let weights: [Float] = [0.5, 0.25, 0.25]
        return amount * weights[0] + date * weights[1] + vendor * weights[2]
    }

    /// True if OCR result is uncertain enough to benefit from VLM re-analysis
    var isLow: Bool { overall < 0.5 }
}

/// OCREngine is responsible only for text recognition via Vision framework.
/// All field extraction (amount, date, vendor) is delegated to ReceiptParser.
actor OCREngine {

    // MARK: - Public API

    static func scan(_ imageData: Data) async -> OCRResult {
        guard let cgImage = UIImage(data: imageData)?.cgImage else {
            return OCRResult()
        }

        let observations = await recognizeText(cgImage: cgImage)
        let lines = observations.compactMap { $0.topCandidates(1).first }
        let strings = lines.map(\.string)
        let confidences = lines.map(\.confidence)

        var result = OCRResult()
        result.rawLines = strings

        // Delegate extraction to ReceiptParser (single source of truth)
        let parsed = ReceiptParser.parse(lines: strings)
        result.amount = parsed.amount
        result.date = parsed.date
        result.vendor = parsed.vendor

        // Compute confidence from OCR character-level confidences
        let avgConf = confidences.isEmpty ? Float(0) : confidences.reduce(0, +) / Float(confidences.count)
        result.confidence.amount = parsed.amount != nil ? min(avgConf * 1.2, 1.0) : 0
        result.confidence.date = parsed.date != nil ? min(avgConf * 1.2, 1.0) : 0
        result.confidence.vendor = parsed.vendor != nil ? min(avgConf * 1.0, 1.0) : 0

        return result
    }

    // MARK: - Vision Recognition

    private static func recognizeText(cgImage: CGImage) async -> [VNRecognizedTextObservation] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let obs = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: obs)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja", "en"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}

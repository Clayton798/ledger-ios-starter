import UIKit
import Vision
import ImageIO

struct OCRFailure: LocalizedError {
    var errorDescription: String? { "无法读取这张图片，请选择清晰截图或手动记账。" }
}
enum ReceiptOCR {
    static func recognize(_ data: Data) async throws -> String {
        try await recognizeLines(data).map(\.text).joined(separator: "\n")
    }
    static func recognizeLines(_ data: Data) async throws -> [OCRLine] {
        try await Task.detached(priority: .userInitiated) {
            // Bound decoded pixels before Vision to avoid exhausting memory on large photos.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw OCRFailure() }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return OCRLine(text: text, x: box.minX, y: box.midY, height: box.height)
            }
            guard !lines.isEmpty else { throw OCRFailure() }
            return lines
        }.value
    }
}

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
            guard let image = UIImage(data: data), let cg = image.cgImage else { throw OCRFailure() }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            let orientation: CGImagePropertyOrientation
            switch image.imageOrientation {
            case .up: orientation = .up
            case .down: orientation = .down
            case .left: orientation = .left
            case .right: orientation = .right
            case .upMirrored: orientation = .upMirrored
            case .downMirrored: orientation = .downMirrored
            case .leftMirrored: orientation = .leftMirrored
            case .rightMirrored: orientation = .rightMirrored
            @unknown default: orientation = .up
            }
            try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
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

import UIKit
import Vision

/// 端侧文字识别，离线运行，不需要任何服务器
enum TextRecognizer {

    static func recognize(in image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        guard let observations = request.results else { return "" }

        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

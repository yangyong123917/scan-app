import UIKit
import Vision

/// 一行 OCR 结果：文字 + 在原图中的归一化位置（原点在左下，Vision 坐标系）
struct OCRLine {
    let text: String
    let box: CGRect
}

/// 端侧文字识别，离线运行，不需要任何服务器
enum TextRecognizer {

    /// 只取纯文本，按从上到下排序
    static func recognize(in image: UIImage) -> String {
        lines(in: image).map { $0.text }.joined(separator: "\n")
    }

    /// 连同位置一起返回，用于生成「可搜索 PDF」的文字层
    static func lines(in image: UIImage) -> [OCRLine] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        return observations
            .compactMap { observation -> OCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLine(text: candidate.string, box: observation.boundingBox)
            }
            .sorted { $0.box.maxY > $1.box.maxY }
    }
}

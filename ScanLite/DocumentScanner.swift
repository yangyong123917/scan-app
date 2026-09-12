import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// 文档扫描核心：边缘检测 + 透视校正 + 图像增强
enum DocumentScanner {

    /// 在图片中检测文档的四角。返回顺序：左上、右上、右下、左下（Core Image 坐标系，原点左下）
    static func detectDocument(in image: UIImage) -> [CGPoint]? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.5
        request.minimumAspectRatio = 0.2
        request.minimumSize = 0.2
        request.quadratureTolerance = 30

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Vision 与 Core Image 都使用左下原点，因此直接按尺寸还原坐标即可
        return [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft
        ].map { CGPoint(x: $0.x * width, y: $0.y * height) }
    }

    /// 按四个角点做透视校正，把倾斜拍摄的文档拉正
    static func perspectiveCorrect(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4, let input = CIImage(image: image) else { return nil }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = input
        filter.topLeft = corners[0]
        filter.topRight = corners[1]
        filter.bottomRight = corners[2]
        filter.bottomLeft = corners[3]

        guard let output = filter.outputImage else { return nil }
        return render(output)
    }

    /// 提升对比度并轻微锐化，让文字更清晰
    static func enhance(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }

        let controls = CIFilter.colorControls()
        controls.inputImage = input
        controls.contrast = 1.2
        controls.brightness = 0.03
        controls.saturation = 0.2

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = controls.outputImage
        sharpen.sharpness = 0.4

        guard let output = sharpen.outputImage else { return nil }
        return render(output)
    }

    private static func render(_ ciImage: CIImage) -> UIImage? {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

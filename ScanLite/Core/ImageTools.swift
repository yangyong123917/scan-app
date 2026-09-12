import UIKit
import ImageIO
import CoreImage

/// 图片处理工具：方向矫正、缩放、旋转、滤镜、缩略图
enum ImageTools {

    // MARK: - 方向与尺寸

    /// 把带方向的图片重绘为正向上方位图，避免后续坐标换算错乱
    static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// 按最长边限制像素尺寸，控制内存与文件体积
    static func downscaled(_ image: UIImage, maxPixel: CGFloat = 2000) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixel, longest > 0 else { return image }
        let ratio = maxPixel / longest
        let newSize = CGSize(width: floor(image.size.width * ratio),
                             height: floor(image.size.height * ratio))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - 旋转与滤镜

    /// 顺时针旋转 90 / 180 / 270 度
    static func rotated(_ image: UIImage, degrees: Int) -> UIImage {
        let value = ((degrees % 360) + 360) % 360
        guard value != 0 else { return image }

        let radians = CGFloat(value) * .pi / 180
        let newSize: CGSize = (value == 90 || value == 270)
            ? CGSize(width: image.size.height, height: image.size.width)
            : image.size

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: radians)
            image.draw(in: CGRect(x: -image.size.width / 2,
                                  y: -image.size.height / 2,
                                  width: image.size.width,
                                  height: image.size.height))
        }
    }

    /// 套用滤镜。彩色返回原图；灰度降饱和；黑白用高对比模拟扫描件的硬朗效果
    static func filtered(_ image: UIImage, filter: PageFilter) -> UIImage {
        guard filter != .color, let input = CIImage(image: image) else { return image }

        var parameters: [String: Any] = [:]
        switch filter {
        case .color:
            break
        case .gray:
            parameters = [kCIInputSaturationKey: 0.0,
                          kCIInputContrastKey: 1.18,
                          kCIInputBrightnessKey: 0.02]
        case .bw:
            parameters = [kCIInputSaturationKey: 0.0,
                          kCIInputContrastKey: 2.0,
                          kCIInputBrightnessKey: 0.08]
        }

        let output = input.applyingFilter("CIColorControls", parameters: parameters)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cgImage)
    }

    /// 一次完成「旋转 + 滤镜」
    static func rendered(_ image: UIImage, rotation: Int, filter: PageFilter) -> UIImage {
        filtered(rotated(image, degrees: rotation), filter: filter)
    }

    // MARK: - 读写

    /// 生成缩略图，避免把整张原图读进内存
    static func thumbnail(at url: URL, maxPixel: CGFloat = 400) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    @discardableResult
    static func writeJPEG(_ image: UIImage, to url: URL, quality: CGFloat = 0.85) -> Bool {
        guard let data = image.jpegData(compressionQuality: quality) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 先压成 JPEG，再从 JPEG 数据造 CGImage。
    /// 这样把它画进 PDF 时，CoreGraphics 会直接把 JPEG 原样嵌入，
    /// 否则 PDF 里的图片会被无损重压，体积能涨十倍以上。
    static func jpegBackedCGImage(from image: UIImage, quality: CGFloat = 0.72) -> CGImage? {
        guard let data = image.jpegData(compressionQuality: quality) as CFData?,
              let source = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

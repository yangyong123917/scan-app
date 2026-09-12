import UIKit
import CoreGraphics
import CoreText
import PDFKit

/// 单页输入：已渲染完成的图片 + 该页 OCR 结果
struct PDFInput {
    let image: UIImage
    let lines: [OCRLine]
}

/// 导出选项
struct PDFExportOptions {
    /// 底部页码「第 X / Y 页」
    var showPageNumbers: Bool = true
    /// 斜向文字水印，空字符串表示不加
    var watermarkText: String = ""
    var watermarkOpacity: CGFloat = 0.14
    /// 手写签名，会把签名图贴到每页右下角
    var signature: UIImage? = nil
    /// 写入隐藏文字层，导出后 PDF 里的文字可以被搜索、复制
    var includeTextLayer: Bool = false
    /// 打开密码，空字符串表示不加密
    var password: String = ""
}

/// 把图片按 A4 排版合成 PDF，支持水印 / 页码 / 签名 / 加密 / 文字层
enum PDFBuilder {

    /// A4 页面尺寸（单位：点）
    static let a4Size = CGSize(width: 595.28, height: 841.89)

    /// 逐页生成。图片由 `input` 闭包按需提供，用完即释放，
    /// 这样导出几十页也不会把整本书的位图都堆在内存里。
    static func build(pageCount: Int,
                      options: PDFExportOptions,
                      progress: ((Int, Int) -> Void)? = nil,
                      input: (Int) -> PDFInput?) -> Data? {

        guard pageCount > 0 else { return nil }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }

        var auxiliary: [CFString: Any] = [:]
        if !options.password.isEmpty {
            auxiliary[kCGPDFContextOwnerPassword] = options.password as CFString
            auxiliary[kCGPDFContextUserPassword] = options.password as CFString
            auxiliary[kCGPDFContextEncryptionKeyLength] = NSNumber(value: 128)
        }
        let info: CFDictionary? = auxiliary.isEmpty ? nil : (auxiliary as CFDictionary)

        guard let context = CGContext(consumer: consumer, mediaBox: nil, info) else { return nil }

        for index in 0..<pageCount {
            guard let pageInput = input(index) else { continue }

            let imageRect = fitRect(for: pageInput.image.size, in: a4Size)
            let composited = compose(pageInput.image,
                                     rect: imageRect,
                                     pageNumber: index + 1,
                                     total: pageCount,
                                     options: options)

            // 用 JPEG 数据造 CGImage，画进 PDF 时会被原样嵌入，PDF 体积能小一个数量级
            let cgImage = ImageTools.jpegBackedCGImage(from: composited) ?? composited.cgImage
            guard let cgImage else { continue }

            var mediaBox = CGRect(origin: .zero, size: a4Size)
            context.beginPage(mediaBox: &mediaBox)
            context.draw(cgImage, in: mediaBox)

            if options.includeTextLayer, !pageInput.lines.isEmpty {
                drawInvisibleText(pageInput.lines, imageRect: imageRect, in: context)
            }

            context.endPage()
            progress?(index + 1, pageCount)
        }

        context.closePDF()
        return data as Data
    }

    // MARK: - 排版

    /// 等比缩放后居中放进页面
    private static func fitRect(for imageSize: CGSize, in pageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: pageSize)
        }
        let scale = min(pageSize.width / imageSize.width, pageSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (pageSize.width - size.width) / 2,
                      y: (pageSize.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }

    /// 在 A4 白底上合成完整一页：内容图 + 水印 + 页码 + 签名
    private static func compose(_ image: UIImage,
                                rect: CGRect,
                                pageNumber: Int,
                                total: Int,
                                options: PDFExportOptions) -> UIImage {

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: a4Size, format: format)

        return renderer.image { context in
            let cg = context.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: a4Size))

            image.draw(in: rect)

            if !options.watermarkText.isEmpty {
                drawWatermark(options.watermarkText, opacity: options.watermarkOpacity)
            }

            var bottomInset = a4Size.width * 0.03

            if options.showPageNumbers {
                let text = "第 \(pageNumber) / \(total) 页"
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: UIFont.systemFont(ofSize: a4Size.width * 0.028),
                    .foregroundColor: UIColor.darkGray
                ])
                let size = attributed.size()
                attributed.draw(at: CGPoint(x: (a4Size.width - size.width) / 2,
                                            y: a4Size.height - size.height - bottomInset))
                bottomInset += size.height + a4Size.height * 0.008
            }

            if let signature = options.signature {
                let width = a4Size.width * 0.26
                let ratio = signature.size.height / max(signature.size.width, 1)
                let height = min(width * ratio, a4Size.height * 0.14)
                let margin = a4Size.width * 0.06
                signature.draw(in: CGRect(x: a4Size.width - width - margin,
                                          y: a4Size.height - height - bottomInset - a4Size.height * 0.01,
                                          width: width,
                                          height: height))
            }
        }
    }

    /// 斜向居中的文字水印
    private static func drawWatermark(_ text: String, opacity: CGFloat) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: max(20, a4Size.width * 0.085), weight: .bold),
            .foregroundColor: UIColor.black.withAlphaComponent(opacity)
        ])
        let size = attributed.size()

        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.saveGState()
        cg.translateBy(x: a4Size.width / 2, y: a4Size.height / 2)
        cg.rotate(by: -CGFloat.pi / 6)
        attributed.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        cg.restoreGState()
    }

    /// 写入不可见文字层：文字看不见，但能被搜索和复制
    private static func drawInvisibleText(_ lines: [OCRLine], imageRect: CGRect, in context: CGContext) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = .identity

        for line in lines {
            let rect = CGRect(x: imageRect.minX + line.box.minX * imageRect.width,
                              y: imageRect.minY + line.box.minY * imageRect.height,
                              width: line.box.width * imageRect.width,
                              height: line.box.height * imageRect.height)
            guard rect.width > 1, rect.height > 2 else { continue }

            let font = CTFontCreateWithName("PingFangSC-Regular" as CFString,
                                            max(4, rect.height * 0.85),
                                            nil)
            let attributes: [CFString: Any] = [kCTFontAttributeName: font]
            guard let attributed = CFAttributedStringCreate(nil,
                                                            line.text as CFString,
                                                            attributes as CFDictionary) else { continue }
            let ctLine = CTLineCreateWithAttributedString(attributed)

            context.textPosition = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.12)
            CTLineDraw(ctLine, context)
        }

        context.restoreGState()
    }
}

/// 把外部 PDF 逐页渲染成图片，这样导入之后也能排序、旋转、加水印再重新导出
enum PDFImporter {

    static func images(from url: URL, maxPixel: CGFloat = 2000) -> [UIImage] {
        guard let document = PDFDocument(url: url) else { return [] }

        var result: [UIImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            let scale = min(3.0, maxPixel / max(bounds.width, bounds.height))
            let size = CGSize(width: floor(bounds.width * scale),
                              height: floor(bounds.height * scale))

            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true

            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                let cg = context.cgContext
                UIColor.white.setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                cg.saveGState()
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
            }
            result.append(image)
        }
        return result
    }
}

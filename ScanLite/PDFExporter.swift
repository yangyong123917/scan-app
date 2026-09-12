import UIKit
import CoreGraphics

/// 把多张图片合成一个 PDF，纯本地生成
enum PDFExporter {

    static func makePDF(from images: [UIImage]) -> Data? {
        guard !images.isEmpty else { return nil }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        guard let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }

        for image in images {
            guard let cgImage = image.cgImage else { continue }
            var pageBox = CGRect(origin: .zero, size: image.size)
            context.beginPage(mediaBox: &pageBox)
            context.draw(cgImage, in: pageBox)
            context.endPage()
        }

        context.closePDF()
        return data as Data
    }
}

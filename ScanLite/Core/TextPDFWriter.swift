import UIKit
import CoreGraphics
import CoreText

/// 把汇总文字排成 A4 PDF。
///
/// 和「扫描成 PDF」不同，这里输出的是**真正的矢量文字**：可以选中、可以复制、
/// 可以全文搜索，体积也极小（几十页只有几十 KB）。换行用 CoreText 的类型排版器，
/// 中日韩的断行规则由系统处理，不会出现英文按字母乱断的问题。
enum TextPDFWriter {

    private static let pageSize = CGSize(width: 595.28, height: 841.89)   // A4
    private static let margin: CGFloat = 56
    private static let contentWidth: CGFloat = pageSize.width - margin * 2

    private static let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
    private static let metaFont = UIFont.systemFont(ofSize: 9.5)
    private static let headingFont = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
    private static let bodyFont = UIFont.systemFont(ofSize: 11)

    /// 行距系数，中文正文 1.6 倍读起来比较舒服
    private static let lineSpacing: CGFloat = 1.6

    private struct LaidLine {
        let line: CTLine
        let ascent: CGFloat
        let height: CGFloat
    }

    // MARK: - 入口

    static func build(title: String,
                      subtitle: String,
                      sections: [CompilationSection],
                      showPageNumbers: Bool = true,
                      progress: ((Int, Int) -> Void)? = nil) -> Data? {

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var cursor: CGFloat = 0
        var pageNumber = 1
        var pageOpen = false

        func openPage() {
            var box = CGRect(origin: .zero, size: Self.pageSize)
            context.beginPage(mediaBox: &box)
            cursor = Self.pageSize.height - Self.margin
            pageOpen = true
        }

        func closePage() {
            guard pageOpen else { return }
            if showPageNumbers {
                let footer = Self.layout("第 \(pageNumber) 页",
                                         font: Self.metaFont,
                                         color: .gray,
                                         width: Self.contentWidth)
                if let first = footer.first {
                    let width = CGFloat(CTLineGetTypographicBounds(first.line, nil, nil, nil))
                    Self.draw(first.line,
                              at: CGPoint(x: (Self.pageSize.width - width) / 2, y: Self.margin * 0.5),
                              in: context)
                }
            }
            context.endPage()
            pageOpen = false
            pageNumber += 1
        }

        /// 写一段。空字符串表示空行，照样占一行高度
        func write(_ text: String, font: UIFont, color: UIColor, gapAfter: CGFloat = 0) {
            if text.isEmpty {
                let height = font.lineHeight * Self.lineSpacing
                if cursor - height < Self.margin { closePage(); openPage() }
                cursor -= height
            } else {
                for laid in Self.layout(text, font: font, color: color, width: Self.contentWidth) {
                    if cursor - laid.height < Self.margin { closePage(); openPage() }
                    Self.draw(laid.line, at: CGPoint(x: Self.margin, y: cursor - laid.ascent), in: context)
                    cursor -= laid.height
                }
            }
            cursor -= gapAfter
        }

        openPage()

        if !title.isEmpty {
            write(title, font: titleFont, color: .black, gapAfter: 8)
        }
        if !subtitle.isEmpty {
            write(subtitle, font: metaFont, color: .darkGray, gapAfter: 20)
        }

        for (index, section) in sections.enumerated() {
            if !section.heading.isEmpty {
                write(section.heading, font: headingFont, color: .black, gapAfter: 6)
            }
            for line in section.body.components(separatedBy: "\n") {
                write(line, font: bodyFont, color: .black)
            }
            if index < sections.count - 1 {
                cursor -= 18
            }
            progress?(index + 1, sections.count)
        }

        closePage()
        context.closePDF()
        return data as Data
    }

    // MARK: - 排版与绘制

    private static func attributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        // CoreText 认的是 kCTForegroundColorAttributeName + CGColor
        return [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
        ]
    }

    /// 按可用宽度把一段文字折成若干行
    private static func layout(_ text: String,
                               font: UIFont,
                               color: UIColor,
                               width: CGFloat) -> [LaidLine] {

        guard !text.isEmpty, width > 1 else { return [] }

        let attributed = NSAttributedString(string: text, attributes: attributes(font: font, color: color))
        let typesetter = CTTypesetterCreateWithAttributedString(attributed as CFAttributedString)
        let total = attributed.length

        var result: [LaidLine] = []
        var start = 0

        while start < total {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if count <= 0 { count = 1 }
            let length = min(count, total - start)

            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: length))

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            result.append(LaidLine(line: line,
                                   ascent: ascent,
                                   height: (ascent + descent + leading) * lineSpacing))
            start += length
        }

        return result
    }

    private static func draw(_ line: CTLine, at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

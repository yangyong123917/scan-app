import Foundation

/// 极简 ZIP 打包器：只用 stored（不压缩）方式。
///
/// iOS 上没有公开的 zip 写入 API，而 `.docx` 本质就是一个 zip 包，
/// 所以这里按 ZIP 规范手工拼字节。字段顺序、CRC 算法、EOCD 布局
/// 都已用标准解压器校验过。文件名统一按 UTF-8 解释（通用标志位 0x0800）。
enum ZipArchive {

    struct Entry {
        let name: String
        let data: Data
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }
        return table
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let slot = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[slot] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - 打包

    static func archive(_ entries: [Entry]) -> Data? {
        guard !entries.isEmpty else { return nil }

        var output = Data()
        var central = Data()

        let (dosTime, dosDate) = dosStamp(Date())

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(output.count)

            // 本地文件头 + 文件名 + 数据
            output.appendLE(UInt32(0x0403_4B50))
            output.appendLE(UInt16(20))            // 解压所需版本
            output.appendLE(UInt16(0x0800))        // 标志位：文件名为 UTF-8
            output.appendLE(UInt16(0))             // 压缩方式：0 = 不压缩
            output.appendLE(dosTime)
            output.appendLE(dosDate)
            output.appendLE(crc)
            output.appendLE(size)                  // 压缩后大小
            output.appendLE(size)                  // 原始大小
            output.appendLE(UInt16(nameData.count))
            output.appendLE(UInt16(0))             // 扩展字段长度
            output.append(nameData)
            output.append(entry.data)

            // 中央目录项
            central.appendLE(UInt32(0x0201_4B50))
            central.appendLE(UInt16(20))           // 打包程序版本
            central.appendLE(UInt16(20))           // 解压所需版本
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(crc)
            central.appendLE(size)
            central.appendLE(size)
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))            // 扩展字段
            central.appendLE(UInt16(0))            // 注释长度
            central.appendLE(UInt16(0))            // 起始磁盘号
            central.appendLE(UInt16(0))            // 内部属性
            central.appendLE(UInt32(0))            // 外部属性
            central.appendLE(offset)               // 本地文件头偏移
            central.append(nameData)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)

        // 中央目录结束记录
        output.appendLE(UInt32(0x0605_4B50))
        output.appendLE(UInt16(0))                 // 当前磁盘号
        output.appendLE(UInt16(0))                 // 中央目录所在磁盘号
        output.appendLE(UInt16(entries.count))     // 本磁盘条目数
        output.appendLE(UInt16(entries.count))     // 总条目数
        output.appendLE(UInt32(central.count))     // 中央目录大小
        output.appendLE(centralOffset)             // 中央目录偏移
        output.appendLE(UInt16(0))                 // 注释长度

        return output
    }

    /// ZIP 里用的是 MS-DOS 时间格式，1980 年起算、秒按 2 秒精度存
    private static func dosStamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let year = max(1980, parts.year ?? 1980)
        let month = min(max(parts.month ?? 1, 1), 12)
        let day = min(max(parts.day ?? 1, 1), 31)
        let hour = min(max(parts.hour ?? 0, 0), 23)
        let minute = min(max(parts.minute ?? 0, 0), 59)
        let second = min(max(parts.second ?? 0, 0), 59)

        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        return (dosTime, dosDate)
    }
}

/// 生成 Word 能直接打开的 `.docx`。
///
/// 只用了直接格式化（每个 run 自带字体和字号），不依赖样式表里的定义，
/// 同时仍然带上一份最小的 `styles.xml` 作为默认字体兜底 —— Word、WPS、
/// Pages、Google Docs 都能正常打开。
enum DocxWriter {

    static func build(title: String,
                      subtitle: String,
                      sections: [CompilationSection]) -> Data? {

        var body = ""

        if !title.isEmpty {
            body += paragraph(title, bold: true, halfPointSize: 36,
                              alignment: "center", spacingAfter: 120)
        }
        if !subtitle.isEmpty {
            body += paragraph(subtitle, bold: false, halfPointSize: 20,
                              alignment: "center", spacingAfter: 240)
        }

        for (index, section) in sections.enumerated() {
            if !section.heading.isEmpty {
                body += paragraph(section.heading, bold: true, halfPointSize: 28,
                                  spacingBefore: index == 0 ? 0 : 280, spacingAfter: 120)
            }
            for line in section.body.components(separatedBy: "\n") {
                body += paragraph(line, bold: false, halfPointSize: 21)
            }
        }

        let seal = "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
            + "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\""
            + " w:header=\"851\" w:footer=\"992\" w:gutter=\"0\"/></w:sectPr>"

        let document = xmlHeader
            + "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + "<w:body>" + body + seal + "</w:body></w:document>"

        let contentTypes = xmlHeader
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
            + "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
            + "</Types>"

        let rootRels = xmlHeader
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>"
            + "</Relationships>"

        let documentRels = xmlHeader
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
            + "</Relationships>"

        let styles = xmlHeader
            + "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + "<w:docDefaults>"
            + "<w:rPrDefault><w:rPr>"
            + "<w:rFonts w:ascii=\"Calibri\" w:eastAsia=\"宋体\" w:hAnsi=\"Calibri\" w:cs=\"Calibri\"/>"
            + "<w:sz w:val=\"21\"/><w:szCs w:val=\"21\"/>"
            + "</w:rPr></w:rPrDefault>"
            + "<w:pPrDefault><w:pPr><w:spacing w:after=\"0\" w:line=\"312\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault>"
            + "</w:docDefaults>"
            + "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\">"
            + "<w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
            + "</w:styles>"

        let entries: [ZipArchive.Entry] = [
            ZipArchive.Entry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipArchive.Entry(name: "_rels/.rels", data: Data(rootRels.utf8)),
            ZipArchive.Entry(name: "word/document.xml", data: Data(document.utf8)),
            ZipArchive.Entry(name: "word/_rels/document.xml.rels", data: Data(documentRels.utf8)),
            ZipArchive.Entry(name: "word/styles.xml", data: Data(styles.utf8))
        ]

        return ZipArchive.archive(entries)
    }

    // MARK: - OOXML 片段

    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

    private static func paragraph(_ text: String,
                                  bold: Bool,
                                  halfPointSize: Int,
                                  alignment: String? = nil,
                                  spacingBefore: Int = 0,
                                  spacingAfter: Int = 0) -> String {

        var properties = "<w:pPr>"
        if let alignment {
            properties += "<w:jc w:val=\"\(alignment)\"/>"
        }
        properties += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\""
            + " w:line=\"312\" w:lineRule=\"auto\"/>"
        properties += "</w:pPr>"

        // 空行只保留段落属性，不写 run
        guard !text.isEmpty else { return "<w:p>" + properties + "</w:p>" }

        var runProperties = "<w:rFonts w:ascii=\"Calibri\" w:eastAsia=\"宋体\""
            + " w:hAnsi=\"Calibri\" w:cs=\"Calibri\"/>"
        if bold { runProperties += "<w:b/><w:bCs/>" }
        runProperties += "<w:sz w:val=\"\(halfPointSize)\"/><w:szCs w:val=\"\(halfPointSize)\"/>"

        return "<w:p>" + properties
            + "<w:r><w:rPr>" + runProperties + "</w:rPr>"
            + "<w:t xml:space=\"preserve\">" + sanitize(text) + "</w:t></w:r></w:p>"
    }

    /// 丢掉 XML 1.0 不允许出现的控制字符，再做实体转义。
    /// OCR 结果里偶尔会混进奇怪的字符，不处理会让 Word 直接报「文件已损坏」。
    static func sanitize(_ text: String) -> String {
        var cleaned = ""
        cleaned.unicodeScalars.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D:
                cleaned.unicodeScalars.append(scalar)
            case 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                cleaned.unicodeScalars.append(scalar)
            default:
                continue
            }
        }

        return cleaned
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - 小端写入

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { raw in
            append(contentsOf: raw)
        }
    }
}

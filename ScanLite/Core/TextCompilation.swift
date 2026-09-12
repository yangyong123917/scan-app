import Foundation

/// 汇总里的一个条目：一段来自某份文档（或手工录入）的文字。
/// 条目在数组里的先后顺序，就是最终稿子里的排列顺序。
struct CompilationItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// 小标题，追加时默认取来源文档名
    var title: String = ""
    /// 正文
    var body: String = ""
    /// 来源文档 id，手工录入的条目为 nil
    var sourceDocumentID: UUID? = nil
    var addedAt: Date = Date()

    var characterCount: Int { body.count }

    /// 用来判断这份条目是不是「空壳」（比如追加时文档还没识别出文字）
    var isEmptyBody: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 一份「文字汇总」：把多份文档的识别结果按顺序排成一份稿子，最后导出一个文件
struct TextCompilation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var items: [CompilationItem] = []

    var characterCount: Int { items.reduce(0) { $0 + $1.characterCount } }
    var isEmpty: Bool { items.isEmpty }
    var itemCount: Int { items.count }
}

/// 供 Word / PDF 排版用的段落块
struct CompilationSection {
    var heading: String
    var body: String
}

/// 汇总可以导出成哪些格式
enum CompilationFormat: String, CaseIterable, Identifiable {
    case text
    case markdown
    case word
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "纯文本"
        case .markdown: return "Markdown"
        case .word: return "Word 文档"
        case .pdf: return "PDF（文字版）"
        }
    }

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        case .word: return "docx"
        case .pdf: return "pdf"
        }
    }

    var detail: String {
        switch self {
        case .text: return ".txt · 最通用，任何设备都能打开"
        case .markdown: return ".md · 带标题层级，适合笔记软件"
        case .word: return ".docx · 可在 Word / WPS 里继续排版"
        case .pdf: return ".pdf · A4 排版，适合打印或直接提交"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "doc.plaintext"
        case .markdown: return "text.alignleft"
        case .word: return "doc.richtext"
        case .pdf: return "doc.viewfinder"
        }
    }
}

/// 导出时的排版选项
struct CompilationExportOptions {
    /// 开头写入汇总名称、时间、字数统计
    var includeHeader: Bool = true
    /// 每个条目前面写上小标题
    var includeTitles: Bool = true
    /// 条目之间插入分隔线（纯文本 / Markdown 有效）
    var includeSeparator: Bool = true
    /// PDF 页脚显示页码
    var showPageNumbers: Bool = true
}

/// 把汇总拼成各种文本形态
enum CompilationTextBuilder {

    // MARK: - 纯文本

    static func plainText(_ compilation: TextCompilation,
                          options: CompilationExportOptions) -> String {
        var blocks: [String] = []

        if options.includeHeader {
            let head = [
                compilation.name,
                "生成时间：\(timestamp(compilation.updatedAt))",
                "共 \(compilation.itemCount) 份 · \(compilation.characterCount) 字"
            ]
            blocks.append(head.joined(separator: "\n"))
        }

        for (index, item) in compilation.items.enumerated() {
            var lines: [String] = []
            if options.includeTitles {
                lines.append("【\(index + 1)】\(item.title)")
            }
            lines.append(item.body.isEmpty ? "（本份没有识别到文字）" : item.body)
            blocks.append(lines.joined(separator: "\n"))
        }

        let separator = options.includeSeparator
            ? "\n\n" + String(repeating: "=", count: 40) + "\n\n"
            : "\n\n"
        return blocks.joined(separator: separator) + "\n"
    }

    // MARK: - Markdown

    static func markdown(_ compilation: TextCompilation,
                         options: CompilationExportOptions) -> String {
        var blocks: [String] = []

        if options.includeHeader {
            var lines: [String] = []
            lines.append("# \(compilation.name)")
            lines.append("")
            lines.append("_生成时间：\(timestamp(compilation.updatedAt))_")
            lines.append("")
            lines.append("共 \(compilation.itemCount) 份 · \(compilation.characterCount) 字")
            blocks.append(lines.joined(separator: "\n"))
        }

        for (index, item) in compilation.items.enumerated() {
            var lines: [String] = []
            if options.includeTitles {
                lines.append("## \(index + 1). \(item.title)")
                lines.append("")
            }
            lines.append(item.body.isEmpty ? "_（本份没有识别到文字）_" : item.body)
            blocks.append(lines.joined(separator: "\n"))
        }

        let separator = options.includeSeparator ? "\n\n---\n\n" : "\n\n"
        return blocks.joined(separator: separator) + "\n"
    }

    // MARK: - Word / PDF 共用

    static func subtitle(_ compilation: TextCompilation) -> String {
        "生成时间：\(timestamp(compilation.updatedAt))　共 \(compilation.itemCount) 份　\(compilation.characterCount) 字"
    }

    static func sections(_ compilation: TextCompilation,
                         options: CompilationExportOptions) -> [CompilationSection] {
        compilation.items.enumerated().map { index, item in
            let heading = options.includeTitles ? "\(index + 1). \(item.title)" : ""
            let body = item.body.isEmpty ? "（本份没有识别到文字）" : item.body
            return CompilationSection(heading: heading, body: body)
        }
    }

    // MARK: - 工具

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 文件名里不能出现的字符统一替换掉
    static func safeFileName(_ raw: String, fallback: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")

        func clean(_ value: String) -> String {
            value.components(separatedBy: banned)
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let primary = clean(raw)
        if !primary.isEmpty { return primary }

        let secondary = clean(fallback)
        return secondary.isEmpty ? "文字汇总" : secondary
    }
}

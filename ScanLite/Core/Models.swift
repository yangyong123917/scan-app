import Foundation

/// 单页滤镜：彩色 / 灰度 / 黑白。
/// 这里只存标记，显示和导出时才应用，原图始终保持不变（非破坏性编辑）。
enum PageFilter: String, Codable, CaseIterable, Identifiable {
    case color
    case gray
    case bw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: return "彩色"
        case .gray: return "灰度"
        case .bw: return "黑白"
        }
    }
}

/// 文档里的一页
struct ScanPage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// 图片文件名，位于该文档目录的 pages 子目录下
    var fileName: String = ""
    /// 顺时针旋转角度，取值 0 / 90 / 180 / 270
    var rotation: Int = 0
    /// 显示与导出时套用的滤镜
    var filter: PageFilter = .color
}

/// 一份扫描文档
struct ScanDocument: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var pages: [ScanPage] = []
    /// OCR 文字缓存，识别过一次就留在这里
    var ocrText: String = ""

    var pageCount: Int { pages.count }
}

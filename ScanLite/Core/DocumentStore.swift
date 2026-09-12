import Foundation
import UIKit

/// 文档仓库：沙盒读写、文档增删改查、图片缓存、PDF 导出
///
/// 目录结构（App 沙盒内的 Documents/ScanLite）：
/// ```
/// ScanLite/
///  ├── documents.json          文档索引
///  ├── signature.png           保存的手写签名
///  ├── Docs/<文档ID>/pages/<页ID>.jpg
///  └── Exports/xxx.pdf         导出的 PDF
/// ```
final class DocumentStore: ObservableObject {

    static let shared = DocumentStore()

    @Published private(set) var documents: [ScanDocument] = []

    private let fileManager = FileManager.default
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let renderCache = NSCache<NSString, UIImage>()

    private lazy var baseURL: URL = {
        let root = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("ScanLite", isDirectory: true)
    }()

    private var docsURL: URL { baseURL.appendingPathComponent("Docs", isDirectory: true) }
    private var exportsURL: URL { baseURL.appendingPathComponent("Exports", isDirectory: true) }
    private var indexURL: URL { baseURL.appendingPathComponent("documents.json") }
    private var signatureURL: URL { baseURL.appendingPathComponent("signature.png") }

    private init() {
        thumbnailCache.countLimit = 500
        renderCache.countLimit = 8
        renderCache.totalCostLimit = 64 * 1024 * 1024
        prepareDirectories()
    }

    private func prepareDirectories() {
        for url in [baseURL, docsURL, exportsURL] where !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - 路径

    private func directory(for id: UUID) -> URL {
        docsURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func pagesDirectory(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("pages", isDirectory: true)
    }

    func imageURL(for page: ScanPage, in documentID: UUID) -> URL {
        pagesDirectory(for: documentID).appendingPathComponent(page.fileName)
    }

    // MARK: - 索引

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([ScanDocument].self, from: data) else {
            documents = []
            return
        }
        documents = list.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        thumbnailCache.removeAllObjects()
        renderCache.removeAllObjects()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(documents) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    func document(id: UUID) -> ScanDocument? {
        documents.first { $0.id == id }
    }

    // MARK: - 新建与追加

    @discardableResult
    func createDocument(name: String? = nil, pages images: [UIImage] = []) -> ScanDocument {
        let document = ScanDocument(name: name ?? Self.defaultName())
        documents.insert(document, at: 0)
        try? fileManager.createDirectory(at: pagesDirectory(for: document.id),
                                        withIntermediateDirectories: true)
        if !images.isEmpty {
            appendImages(images, to: document.id)
        }
        persist()
        return document
    }

    func appendImages(_ images: [UIImage], to documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }

        let directory = pagesDirectory(for: documentID)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for image in images {
            let pageID = UUID()
            let fileName = "\(pageID.uuidString).jpg"
            let prepared = ImageTools.downscaled(ImageTools.normalized(image))
            let url = directory.appendingPathComponent(fileName)
            guard ImageTools.writeJPEG(prepared, to: url) else { continue }
            documents[index].pages.append(ScanPage(id: pageID, fileName: fileName))
        }

        documents[index].updatedAt = Date()
        persist()
    }

    // MARK: - 修改

    func update(document: ScanDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        var updated = document
        updated.updatedAt = Date()
        documents[index] = updated
        persist()
    }

    func rename(documentID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[index].name = trimmed
        documents[index].updatedAt = Date()
        persist()
    }

    func duplicate(documentID: UUID) {
        guard let original = document(id: documentID) else { return }

        var copy = original
        copy.id = UUID()
        copy.name = original.name + " 副本"
        copy.createdAt = Date()
        copy.updatedAt = Date()

        do {
            try fileManager.copyItem(at: directory(for: original.id), to: directory(for: copy.id))
        } catch {
            return
        }

        documents.insert(copy, at: 0)
        persist()
    }

    func delete(documentID: UUID) {
        documents.removeAll { $0.id == documentID }
        try? fileManager.removeItem(at: directory(for: documentID))
        persist()
    }

    /// 按给定顺序把多份文档合并成一份新的
    @discardableResult
    func merge(documentIDs: [UUID], name: String) -> ScanDocument? {
        let sources = documentIDs.compactMap { document(id: $0) }
        guard !sources.isEmpty else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = ScanDocument(name: trimmed.isEmpty ? Self.defaultName() : trimmed)
        documents.insert(merged, at: 0)

        let directory = pagesDirectory(for: merged.id)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let index = documents.firstIndex(where: { $0.id == merged.id }) else { return nil }

        for source in sources {
            for page in source.pages {
                let pageID = UUID()
                let fileName = "\(pageID.uuidString).jpg"
                let from = imageURL(for: page, in: source.id)
                let to = directory.appendingPathComponent(fileName)
                guard (try? fileManager.copyItem(at: from, to: to)) != nil else { continue }
                documents[index].pages.append(ScanPage(id: pageID,
                                                       fileName: fileName,
                                                       rotation: page.rotation,
                                                       filter: page.filter))
            }
        }

        persist()
        return document(id: merged.id)
    }

    // MARK: - 图片读取

    func thumbnail(for document: ScanDocument, maxPixel: CGFloat = 320) -> UIImage? {
        guard let page = document.pages.first else { return nil }
        return pageThumbnail(for: page, in: document.id, maxPixel: maxPixel)
    }

    func pageThumbnail(for page: ScanPage, in documentID: UUID, maxPixel: CGFloat = 420) -> UIImage? {
        let key = cacheKey(page, documentID, suffix: "thumb\(Int(maxPixel))")
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        guard let image = renderedImage(for: page, in: documentID) else { return nil }
        let thumb = ImageTools.downscaled(image, maxPixel: maxPixel)
        thumbnailCache.setObject(thumb, forKey: key)
        return thumb
    }

    /// 应用旋转与滤镜后的完整图片（带缓存，给全屏查看器用）
    func renderedImage(for page: ScanPage, in documentID: UUID) -> UIImage? {
        let key = cacheKey(page, documentID, suffix: "full")
        if let cached = renderCache.object(forKey: key) { return cached }

        guard let image = loadRawImage(for: page, in: documentID) else { return nil }
        let rendered = ImageTools.rendered(image, rotation: page.rotation, filter: page.filter)
        let cost = Int(rendered.size.width * rendered.size.height * 4)
        renderCache.setObject(rendered, forKey: key, cost: cost)
        return rendered
    }

    /// 只从磁盘读原图，不进缓存
    func loadRawImage(for page: ScanPage, in documentID: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: imageURL(for: page, in: documentID)) else { return nil }
        return UIImage(data: data)
    }

    /// 应用旋转与滤镜但完全不缓存，导出 PDF 时用，避免整本页面堆积在内存
    func renderedImageUncached(for page: ScanPage, in documentID: UUID) -> UIImage? {
        guard let image = loadRawImage(for: page, in: documentID) else { return nil }
        return ImageTools.rendered(image, rotation: page.rotation, filter: page.filter)
    }

    private func cacheKey(_ page: ScanPage, _ documentID: UUID, suffix: String) -> NSString {
        NSString(string: "\(documentID.uuidString)-\(page.id.uuidString)-\(page.rotation)-\(page.filter.rawValue)-\(suffix)")
    }

    // MARK: - 签名

    func savedSignature() -> UIImage? {
        guard let data = try? Data(contentsOf: signatureURL) else { return nil }
        return UIImage(data: data)
    }

    func saveSignature(_ image: UIImage) {
        guard let data = image.pngData() else { return }
        try? data.write(to: signatureURL, options: .atomic)
    }

    func clearSignature() {
        try? fileManager.removeItem(at: signatureURL)
    }

    // MARK: - OCR

    /// 文字识别本身在界面层放到后台线程跑，这里只负责把结果落盘。
    /// 必须在主线程调用。
    func saveOCRText(_ text: String, for documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[index].ocrText = text
        persist()
    }

    // MARK: - 导出

    /// 把若干份文档的内容按顺序导成一个 PDF 文件
    func export(documentIDs: [UUID],
                options: PDFExportOptions,
                name: String,
                progress: ((Int, Int) -> Void)? = nil) -> URL? {

        var references: [(documentID: UUID, page: ScanPage)] = []
        for id in documentIDs {
            guard let document = document(id: id) else { continue }
            for page in document.pages {
                references.append((id, page))
            }
        }
        guard !references.isEmpty else { return nil }

        let data = PDFBuilder.build(pageCount: references.count,
                                    options: options,
                                    progress: progress) { index in
            let reference = references[index]
            guard let image = self.renderedImageUncached(for: reference.page,
                                                         in: reference.documentID) else { return nil }
            let lines = options.includeTextLayer ? TextRecognizer.lines(in: image) : []
            return PDFInput(image: image, lines: lines)
        }

        guard let data else { return nil }
        return writeExport(data, name: name)
    }

    private func writeExport(_ data: Data, name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = (trimmed.isEmpty ? Self.defaultName() : trimmed)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = exportsURL.appendingPathComponent("\(safeName).pdf")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - 工具

    static func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "扫描件 " + formatter.string(from: Date())
    }
}

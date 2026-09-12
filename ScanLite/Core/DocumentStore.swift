import Foundation
import UIKit

/// 文档仓库：沙盒读写、文档增删改查、图片缓存、PDF 导出
///
/// 目录结构（App 沙盒内的 Documents/ScanLite）：
/// ```
/// ScanLite/
///  ├── documents.json          文档索引
///  ├── compilations.json       文字汇总索引
///  ├── signature.png           保存的手写签名
///  ├── Docs/<文档ID>/pages/<页ID>.jpg
///  └── Exports/xxx.pdf         导出的文件
/// ```
final class DocumentStore: ObservableObject {

    static let shared = DocumentStore()

    @Published private(set) var documents: [ScanDocument] = []
    /// 文字汇总：把多份文档的识别结果按顺序排成一份稿子
    @Published private(set) var compilations: [TextCompilation] = []

    private let fileManager = FileManager.default
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let renderCache = NSCache<NSString, UIImage>()
    private var didLoad = false

    private lazy var baseURL: URL = {
        let root = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("ScanLite", isDirectory: true)
    }()

    private var docsURL: URL { baseURL.appendingPathComponent("Docs", isDirectory: true) }
    private var exportsURL: URL { baseURL.appendingPathComponent("Exports", isDirectory: true) }
    private var indexURL: URL { baseURL.appendingPathComponent("documents.json") }
    private var compilationsURL: URL { baseURL.appendingPathComponent("compilations.json") }
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
        if let data = try? Data(contentsOf: indexURL),
           let list = try? JSONDecoder().decode([ScanDocument].self, from: data) {
            documents = list.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            documents = []
        }

        if let data = try? Data(contentsOf: compilationsURL),
           let list = try? JSONDecoder().decode([TextCompilation].self, from: data) {
            compilations = list.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            compilations = []
        }

        didLoad = true
    }

    /// 只在第一次进界面时读盘，避免来回切页签反复解析 JSON
    func loadIfNeeded() {
        guard !didLoad else { return }
        load()
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

    // MARK: - 文字汇总

    func compilation(id: UUID) -> TextCompilation? {
        compilations.first { $0.id == id }
    }

    private func persistCompilations() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(compilations) else { return }
        try? data.write(to: compilationsURL, options: .atomic)
    }

    @discardableResult
    func createCompilation(name: String? = nil, items: [CompilationItem] = []) -> TextCompilation {
        var compilation = TextCompilation(name: name ?? Self.defaultCompilationName())
        compilation.items = items
        compilations.insert(compilation, at: 0)
        persistCompilations()
        return compilation
    }

    func renameCompilation(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = compilations.firstIndex(where: { $0.id == id }) else { return }
        compilations[index].name = trimmed
        compilations[index].updatedAt = Date()
        persistCompilations()
    }

    func deleteCompilation(id: UUID) {
        compilations.removeAll { $0.id == id }
        persistCompilations()
    }

    func updateCompilation(_ compilation: TextCompilation) {
        guard let index = compilations.firstIndex(where: { $0.id == compilation.id }) else { return }
        var updated = compilation
        updated.updatedAt = Date()
        compilations[index] = updated
        persistCompilations()
    }

    /// 追加条目到汇总末尾 —— 这就是「下一份排在前一份后面」的实现
    func addItems(_ items: [CompilationItem], to compilationID: UUID) {
        guard !items.isEmpty,
              let index = compilations.firstIndex(where: { $0.id == compilationID }) else { return }
        compilations[index].items.append(contentsOf: items)
        compilations[index].updatedAt = Date()
        persistCompilations()
    }

    func removeItem(id: UUID, from compilationID: UUID) {
        guard let index = compilations.firstIndex(where: { $0.id == compilationID }) else { return }
        compilations[index].items.removeAll { $0.id == id }
        compilations[index].updatedAt = Date()
        persistCompilations()
    }

    func moveItems(from offsets: IndexSet, to destination: Int, in compilationID: UUID) {
        guard let index = compilations.firstIndex(where: { $0.id == compilationID }) else { return }
        compilations[index].items.move(fromOffsets: offsets, toOffset: destination)
        compilations[index].updatedAt = Date()
        persistCompilations()
    }

    func updateItem(id: UUID, in compilationID: UUID, title: String, body: String) {
        guard let index = compilations.firstIndex(where: { $0.id == compilationID }),
              let itemIndex = compilations[index].items.firstIndex(where: { $0.id == id }) else { return }
        compilations[index].items[itemIndex].title = title
        compilations[index].items[itemIndex].body = body
        compilations[index].updatedAt = Date()
        persistCompilations()
    }

    // MARK: - 识别与追加

    /// 纯计算：只读磁盘上的图片做 OCR，不碰任何界面状态，可以放心在后台线程调用。
    /// 页数多于 1 时会在每页前面留一行页码标记，方便在汇总里分辨页界。
    func recognize(pages: [ScanPage], in documentID: UUID) -> String {
        var blocks: [String] = []
        for (index, page) in pages.enumerated() {
            guard let image = renderedImageUncached(for: page, in: documentID) else { continue }
            let text = TextRecognizer.recognize(in: image)
            if !text.isEmpty {
                blocks.append("──── 第 \(index + 1) 页 ────\n\(text)")
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    /// 把若干份文档按顺序追加到汇总末尾。
    ///
    /// 线程安排：先在主线程把文档信息取成快照，再把识别丢到后台，
    /// 最后统一回主线程写盘 —— 全程不会在后台线程改 `@Published` 状态。
    /// 文档已经有缓存文字时直接复用，只有没识别过（或指定强制重识别）才现算。
    func appendDocuments(_ documentIDs: [UUID],
                         to compilationID: UUID,
                         refreshOCR: Bool = false,
                         progress: ((Int, Int, String) -> Void)? = nil,
                         completion: @escaping (Int, Int) -> Void) {

        struct Snapshot {
            let id: UUID
            let name: String
            let pages: [ScanPage]
            let cached: String
        }

        let snapshots: [Snapshot] = documentIDs.compactMap { id in
            guard let document = document(id: id) else { return nil }
            return Snapshot(id: id, name: document.name, pages: document.pages, cached: document.ocrText)
        }

        guard !snapshots.isEmpty else {
            completion(0, 0)
            return
        }

        let total = snapshots.count

        DispatchQueue.global(qos: .userInitiated).async {
            var texts: [String] = []
            var emptyCount = 0

            for (offset, snapshot) in snapshots.enumerated() {
                var text = snapshot.cached
                if text.isEmpty || refreshOCR {
                    DispatchQueue.main.async {
                        progress?(offset + 1, total, "正在识别「\(snapshot.name)」")
                    }
                    text = self.recognize(pages: snapshot.pages, in: snapshot.id)
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyCount += 1
                }
                texts.append(text)
            }

            DispatchQueue.main.async {
                var items: [CompilationItem] = []

                for (snapshot, text) in zip(snapshots, texts) {
                    if let index = self.documents.firstIndex(where: { $0.id == snapshot.id }) {
                        self.documents[index].ocrText = text
                    }
                    let title = snapshot.pages.count > 1
                        ? "\(snapshot.name)（\(snapshot.pages.count) 页）"
                        : snapshot.name
                    items.append(CompilationItem(title: title,
                                                 body: text,
                                                 sourceDocumentID: snapshot.id))
                }

                self.persist()
                self.addItems(items, to: compilationID)
                completion(items.count, emptyCount)
            }
        }
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
        return writeExport(data, name: name, fileExtension: "pdf")
    }

    /// 把文字汇总导出成一个文件：纯文本 / Markdown / Word / PDF
    func exportCompilation(id: UUID,
                           format: CompilationFormat,
                           options: CompilationExportOptions,
                           fileName: String,
                           progress: ((Int, Int) -> Void)? = nil) -> URL? {

        guard let compilation = compilation(id: id), !compilation.isEmpty else { return nil }

        let safeName = CompilationTextBuilder.safeFileName(fileName, fallback: compilation.name)
        let subtitle = options.includeHeader ? CompilationTextBuilder.subtitle(compilation) : ""

        switch format {
        case .text:
            let text = CompilationTextBuilder.plainText(compilation, options: options)
            return writeExport(Data(text.utf8), name: safeName, fileExtension: format.fileExtension)

        case .markdown:
            let text = CompilationTextBuilder.markdown(compilation, options: options)
            return writeExport(Data(text.utf8), name: safeName, fileExtension: format.fileExtension)

        case .word:
            let sections = CompilationTextBuilder.sections(compilation, options: options)
            guard let data = DocxWriter.build(title: compilation.name,
                                              subtitle: subtitle,
                                              sections: sections) else { return nil }
            return writeExport(data, name: safeName, fileExtension: format.fileExtension)

        case .pdf:
            let sections = CompilationTextBuilder.sections(compilation, options: options)
            guard let data = TextPDFWriter.build(title: compilation.name,
                                                 subtitle: subtitle,
                                                 sections: sections,
                                                 showPageNumbers: options.showPageNumbers,
                                                 progress: progress) else { return nil }
            return writeExport(data, name: safeName, fileExtension: format.fileExtension)
        }
    }

    private func writeExport(_ data: Data, name: String, fileExtension: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var safeName = trimmed.isEmpty ? Self.defaultName() : trimmed

        let suffix = "." + fileExtension
        if safeName.lowercased().hasSuffix(suffix) {
            safeName = String(safeName.dropLast(suffix.count))
        }

        let url = exportsURL.appendingPathComponent("\(safeName).\(fileExtension)")

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

    static func defaultCompilationName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "文字汇总 " + formatter.string(from: Date())
    }
}

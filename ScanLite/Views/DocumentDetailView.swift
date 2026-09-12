import SwiftUI
import UIKit
import PhotosUI

/// 详情页弹出的几种面板。合并到一个 sheet 上，
/// 避免同一层级叠多个 sheet 导致只有最后一个生效。
enum DetailSheet: Identifiable {
    case export
    case ocr
    case viewer(UUID)
    case appendToCompilation

    var id: String {
        switch self {
        case .export: return "export"
        case .ocr: return "ocr"
        case .viewer(let uuid): return "viewer-" + uuid.uuidString
        case .appendToCompilation: return "append"
        }
    }
}

/// 文档详情：页面缩略图列表 + 拖动排序 + 删除 + 继续追加页面 + 导出
struct DocumentDetailView: View {

    let documentID: UUID

    @StateObject private var store = DocumentStore.shared

    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var activeSheet: DetailSheet?

    @State private var busyText: String?
    @State private var ocrText: String?

    @State private var showRename = false
    @State private var renameText = ""

    private var document: ScanDocument? { store.document(id: documentID) }

    var body: some View {
        Group {
            if let document {
                content(document)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.folder")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("这份文档已经不在了")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(document?.name ?? "文档")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay { busyView }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView { images in
                append(images, alreadyCorrected: true)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $photoItems,
                      maxSelectionCount: 30,
                      matching: .images)
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            importPhotos(items)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .export:
                ExportSheet(documentID: documentID)
            case .ocr:
                ocrSheet
            case .viewer(let pageID):
                PageViewerView(documentID: documentID, pageID: pageID)
            case .appendToCompilation:
                AddToCompilationSheet(documentIDs: [documentID])
            }
        }
        .alert("重命名文档", isPresented: $showRename) {
            TextField("文档名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { store.rename(documentID: documentID, to: renameText) }
        }
    }

    // MARK: - 页面列表

    private func content(_ document: ScanDocument) -> some View {
        List {
            Section {
                ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        activeSheet = .viewer(page.id)
                    } label: {
                        pageRow(index: index, page: page, document: document)
                    }
                    .buttonStyle(.plain)
                }
                .onMove { from, to in move(from, to) }
                .onDelete { indexSet in delete(indexSet) }
            } header: {
                Text("共 \(document.pages.count) 页")
            } footer: {
                Text("点右上角「编辑」可拖动调整页序、左滑删除单页")
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) { bottomBar(document) }
    }

    private func pageRow(index: Int, page: ScanPage, document: ScanDocument) -> some View {
        HStack(spacing: 12) {
            if let image = store.pageThumbnail(for: page, in: document.id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 64)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 48, height: 64)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("第 \(index + 1) 页")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(page.rotation == 0 ? page.filter.title : "\(page.filter.title) · 旋转 \(page.rotation)°")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func bottomBar(_ document: ScanDocument) -> some View {
        HStack(spacing: 10) {
            Button {
                showCamera = true
            } label: {
                Label("继续拍摄", systemImage: "camera")
            }
            .buttonStyle(.bordered)

            Button {
                showPhotoPicker = true
            } label: {
                Label("相册", systemImage: "photo")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                activeSheet = .export
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(document.pages.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if let document, !document.pages.isEmpty {
                EditButton()
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    renameText = document?.name ?? ""
                    showRename = true
                } label: {
                    Label("重命名", systemImage: "pencil")
                }

                Button {
                    runOCR()
                } label: {
                    Label("识别文字", systemImage: "text.viewfinder")
                }

                Button {
                    activeSheet = .appendToCompilation
                } label: {
                    Label("加入文字汇总", systemImage: "text.alignleft")
                }

                Button {
                    activeSheet = .export
                } label: {
                    Label("导出 PDF", systemImage: "doc.richtext")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var busyView: some View {
        if let busyText {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                    Text(busyText)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private var ocrSheet: some View {
        NavigationStack {
            ScrollView {
                Text(ocrText ?? "")
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("识别文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("复制") {
                        UIPasteboard.general.string = ocrText ?? ""
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { activeSheet = nil }
                }
                ToolbarItem(placement: .bottomBar) {
                    if let ocrText, !ocrText.isEmpty {
                        ShareLink(item: ocrText) {
                            Label("分享文字", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 页面操作

    private func move(_ from: IndexSet, _ to: Int) {
        guard var doc = document else { return }
        doc.pages.move(fromOffsets: from, toOffset: to)
        store.update(document: doc)
    }

    private func delete(_ indexSet: IndexSet) {
        guard var doc = document else { return }
        doc.pages.remove(atOffsets: indexSet)
        store.update(document: doc)
    }

    private func append(_ images: [UIImage], alreadyCorrected: Bool) {
        busyText = "正在处理 \(images.count) 页…"

        DispatchQueue.global(qos: .userInitiated).async {
            let processed = images.map { image -> UIImage in
                alreadyCorrected ? ImageTools.normalized(image) : DocumentScanner.process(image)
            }

            DispatchQueue.main.async {
                store.appendImages(processed, to: documentID)
                busyText = nil
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        photoItems = []
        busyText = "正在读取 \(items.count) 张图片…"

        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }

            DispatchQueue.main.async {
                guard !images.isEmpty else {
                    busyText = nil
                    return
                }
                append(images, alreadyCorrected: false)
            }
        }
    }

    /// 逐页识别。识别在后台跑，结果回到主线程再写进仓库
    private func runOCR() {
        guard let document, !document.pages.isEmpty else { return }

        let pages = document.pages
        busyText = "正在识别文字… 0/\(pages.count) 页"

        DispatchQueue.global(qos: .userInitiated).async {
            var blocks: [String] = []

            for (index, page) in pages.enumerated() {
                if let image = store.renderedImageUncached(for: page, in: documentID) {
                    let text = TextRecognizer.recognize(in: image)
                    if !text.isEmpty {
                        blocks.append("──── 第 \(index + 1) 页 ────\n\(text)")
                    }
                }

                let done = index + 1
                DispatchQueue.main.async {
                    busyText = "正在识别文字… \(done)/\(pages.count) 页"
                }
            }

            let result = blocks.joined(separator: "\n\n")
            DispatchQueue.main.async {
                busyText = nil
                store.saveOCRText(result, for: documentID)
                ocrText = result.isEmpty ? "没有识别到文字" : result
                activeSheet = .ocr
            }
        }
    }
}

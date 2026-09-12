import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 文件库：所有扫描件的入口，支持搜索、排序、重命名、复制、删除、多选合并
struct LibraryView: View {

    @StateObject private var store = DocumentStore.shared

    @State private var searchText = ""
    @State private var sortMode: SortMode = .dateDesc
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()

    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPDFImporter = false

    @State private var busyText: String?
    @State private var toast: String?

    @State private var showRename = false
    @State private var renameText = ""
    @State private var renameID: UUID?

    @State private var showMerge = false
    @State private var mergeName = ""

    enum SortMode: String, CaseIterable, Identifiable {
        case dateDesc
        case dateAsc
        case nameAsc
        case pageDesc

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dateDesc: return "最新在前"
            case .dateAsc: return "最早在前"
            case .nameAsc: return "按名称"
            case .pageDesc: return "按页数"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.documents.isEmpty {
                    emptyState
                } else {
                    documentList
                }
            }
            .navigationTitle("扫描小工具")
            .searchable(text: $searchText, prompt: "搜索文档名称")
            .toolbar { toolbarContent }
            .environment(\.editMode, $editMode)
            .overlay(alignment: .bottom) { toastView }
            .overlay { busyView }
            .onAppear { store.load() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView { images in
                createDocument(from: images, alreadyCorrected: true)
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
        .fileImporter(isPresented: $showPDFImporter,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: true) { result in
            importPDFs(result)
        }
        .alert("重命名文档", isPresented: $showRename) {
            TextField("文档名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let renameID {
                    store.rename(documentID: renameID, to: renameText)
                }
            }
        }
        .alert("合并文档", isPresented: $showMerge) {
            TextField("新文档名称", text: $mergeName)
            Button("取消", role: .cancel) {}
            Button("合并") { performMerge() }
        } message: {
            Text("把选中的 \(selection.count) 份文档按列表顺序拼成一份新文档")
        }
    }

    // MARK: - 列表

    private var filteredDocuments: [ScanDocument] {
        let base: [ScanDocument]
        if searchText.isEmpty {
            base = store.documents
        } else {
            base = store.documents.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortMode {
        case .dateDesc:
            return base.sorted { $0.updatedAt > $1.updatedAt }
        case .dateAsc:
            return base.sorted { $0.updatedAt < $1.updatedAt }
        case .nameAsc:
            return base.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .pageDesc:
            return base.sorted { $0.pages.count > $1.pages.count }
        }
    }

    private var documentList: some View {
        List(selection: $selection) {
            ForEach(filteredDocuments) { document in
                NavigationLink {
                    DocumentDetailView(documentID: document.id)
                } label: {
                    row(for: document)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.delete(documentID: document.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        beginRename(document)
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        beginRename(document)
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button {
                        store.duplicate(documentID: document.id)
                        showToast("已复制一份")
                    } label: {
                        Label("复制一份", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        store.delete(documentID: document.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func row(for document: ScanDocument) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: document)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(document.pages.count) 页 · \(Self.dateText(document.updatedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func thumbnail(for document: ScanDocument) -> some View {
        if let image = store.thumbnail(for: document) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 68)
                .clipped()
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator), lineWidth: 0.5))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 54, height: 68)
                .overlay(Image(systemName: "doc").foregroundColor(.secondary))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundColor(.secondary)

            Text("还没有扫描件")
                .font(.headline)

            Text("点右上角 + 用相机扫描，\n或者从相册导入、导入已有的 PDF")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showCamera = true
            } label: {
                Label("开始扫描", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if !store.documents.isEmpty {
                EditButton()
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    showCamera = true
                } label: {
                    Label("相机扫描", systemImage: "camera.viewfinder")
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("从相册导入", systemImage: "photo.on.rectangle.angled")
                }

                Button {
                    showPDFImporter = true
                } label: {
                    Label("导入 PDF", systemImage: "doc.badge.plus")
                }

                if !store.documents.isEmpty {
                    Divider()
                    Picker("排序方式", selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
        }

        ToolbarItem(placement: .bottomBar) {
            if editMode.isEditing && !store.documents.isEmpty {
                Button {
                    mergeName = "合并文档 " + Self.dateText(Date())
                    showMerge = true
                } label: {
                    Text(selection.count >= 2 ? "合并选中的 \(selection.count) 份" : "至少选两份才能合并")
                }
                .disabled(selection.count < 2)
            }
        }
    }

    // MARK: - 浮层

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 28)
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

    // MARK: - 动作

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if toast == text { toast = nil }
        }
    }

    /// alreadyCorrected：相机扫描器输出的图已经切过边了，再检测一次反而会把边缘裁掉
    private func createDocument(from images: [UIImage], alreadyCorrected: Bool) {
        busyText = alreadyCorrected ? "正在保存 \(images.count) 页…" : "正在切边校正 \(images.count) 页…"

        DispatchQueue.global(qos: .userInitiated).async {
            let processed = images.map { image -> UIImage in
                alreadyCorrected ? ImageTools.normalized(image) : DocumentScanner.process(image)
            }

            DispatchQueue.main.async {
                store.createDocument(pages: processed)
                busyText = nil
                showToast("已新建文档（\(processed.count) 页）")
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
                    showToast("没有读取到图片")
                    return
                }
                createDocument(from: images, alreadyCorrected: false)
            }
        }
    }

    private func importPDFs(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        busyText = "正在解析 PDF…"

        DispatchQueue.global(qos: .userInitiated).async {
            var images: [UIImage] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                images.append(contentsOf: PDFImporter.images(from: url))
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            DispatchQueue.main.async {
                guard !images.isEmpty else {
                    busyText = nil
                    showToast("这个 PDF 没有可读取的页面")
                    return
                }
                store.createDocument(name: "导入的 PDF " + Self.dateText(Date()), pages: images)
                busyText = nil
                showToast("已导入 \(images.count) 页")
            }
        }
    }

    private func beginRename(_ document: ScanDocument) {
        renameID = document.id
        renameText = document.name
        showRename = true
    }

    private func performMerge() {
        let ordered = filteredDocuments.map { $0.id }.filter { selection.contains($0) }
        guard ordered.count >= 2 else { return }

        store.merge(documentIDs: ordered, name: mergeName)
        selection.removeAll()
        editMode = .inactive
        showToast("已合并 \(ordered.count) 份文档")
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

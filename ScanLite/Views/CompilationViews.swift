import SwiftUI
import UIKit

// MARK: - 汇总列表

/// 文字汇总首页：管理所有「一份稿子」
struct CompilationListView: View {

    @StateObject private var store = DocumentStore.shared

    @State private var showCreate = false
    @State private var createName = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var renameID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if store.compilations.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("文字汇总")
            .toolbar { toolbarContent }
            .onAppear { store.loadIfNeeded() }
        }
        .alert("新建文字汇总", isPresented: $showCreate) {
            TextField("名称", text: $createName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                store.createCompilation(name: createName.isEmpty ? nil : createName)
            }
        } message: {
            Text("建好之后可以逐份把扫描件的文字追加进来，最后导出一个文件。")
        }
        .alert("重命名汇总", isPresented: $showRename) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let renameID {
                    store.renameCompilation(id: renameID, to: renameText)
                }
            }
        }
    }

    // MARK: 列表

    private var list: some View {
        List {
            ForEach(store.compilations) { compilation in
                NavigationLink {
                    CompilationEditorView(compilationID: compilation.id)
                } label: {
                    row(for: compilation)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.deleteCompilation(id: compilation.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        beginRename(compilation)
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        beginRename(compilation)
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        store.deleteCompilation(id: compilation.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func row(for compilation: TextCompilation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 54, height: 68)

                VStack(spacing: 0) {
                    Text("\(compilation.itemCount)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("份")
                        .font(.caption2)
                }
                .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(compilation.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(compilation.characterCount) 字 · \(Self.dateText(compilation.updatedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 56))
                .foregroundColor(.secondary)

            Text("还没有文字汇总")
                .font(.headline)

            Text("把多份扫描件的识别文字按顺序拼成一份稿子，\n最后导出成 Word、PDF 或纯文本。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                createName = ""
                showCreate = true
            } label: {
                Label("新建汇总", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                createName = ""
                showCreate = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
        }
    }

    private func beginRename(_ compilation: TextCompilation) {
        renameID = compilation.id
        renameText = compilation.name
        showRename = true
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 汇总编辑

/// 编辑页弹出的几种面板。用同一个 sheet 承载，避免多层 sheet 叠在一起。
enum CompilationEditorSheet: Identifiable {
    case pickDocuments
    case export
    case editItem(UUID)

    var id: String {
        switch self {
        case .pickDocuments: return "pick"
        case .export: return "export"
        case .editItem(let uuid): return "edit-" + uuid.uuidString
        }
    }
}

/// 汇总编辑页：条目按顺序排列，新的追加在末尾，可以拖动调整顺序
struct CompilationEditorView: View {

    let compilationID: UUID

    @StateObject private var store = DocumentStore.shared

    @State private var activeSheet: CompilationEditorSheet?
    @State private var showCamera = false

    @State private var showRename = false
    @State private var renameText = ""

    @State private var busyText: String?
    @State private var toast: String?

    private var compilation: TextCompilation? { store.compilation(id: compilationID) }

    var body: some View {
        Group {
            if let compilation {
                content(compilation)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.folder")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("这份汇总已经不在了")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(compilation?.name ?? "文字汇总")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { toastView }
        .overlay { busyView }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView { images in
                scanAndAppend(images)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .pickDocuments:
                AddDocumentsSheet(compilationID: compilationID) { ids, refresh in
                    appendDocuments(ids, refresh: refresh)
                }
            case .export:
                CompilationExportSheet(compilationID: compilationID)
            case .editItem(let itemID):
                ItemEditorSheet(compilationID: compilationID, itemID: itemID)
            }
        }
        .alert("重命名汇总", isPresented: $showRename) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { store.renameCompilation(id: compilationID, to: renameText) }
        }
    }

    // MARK: 内容

    private func content(_ compilation: TextCompilation) -> some View {
        List {
            if compilation.items.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Text("还没有内容")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("用下面的「追加文字」拍一份文件，\n或者从已有的扫描件里挑。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section {
                    ForEach(Array(compilation.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            activeSheet = .editItem(item.id)
                        } label: {
                            itemRow(index: index, item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                activeSheet = .editItem(item.id)
                            } label: {
                                Label("编辑文字", systemImage: "pencil")
                            }

                            if let sourceID = item.sourceDocumentID {
                                Button {
                                    appendDocuments([sourceID], refresh: true)
                                } label: {
                                    Label("重新识别并追加一份", systemImage: "arrow.clockwise")
                                }
                            }

                            Button(role: .destructive) {
                                store.removeItem(id: item.id, from: compilationID)
                            } label: {
                                Label("删除这一段", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { from, to in
                        store.moveItems(from: from, to: to, in: compilationID)
                    }
                    .onDelete { indexSet in
                        removeItems(at: indexSet)
                    }
                } header: {
                    Text("共 \(compilation.itemCount) 份 · \(compilation.characterCount) 字")
                } footer: {
                    Text("这里的顺序就是导出后文字的排列顺序。点右上角「编辑」可拖动调整，左滑删除单份。")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func itemRow(index: Int, item: CompilationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? "未命名" : item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if item.isEmptyBody {
                    Text("（没有识别到文字）")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text(Self.preview(item.body))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text("\(item.characterCount) 字")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 5)
        }
        .padding(.vertical, 2)
    }

    // MARK: 底栏与工具栏

    @ViewBuilder
    private var bottomBar: some View {
        if compilation != nil {
            HStack(spacing: 10) {
                Menu {
                    Button {
                        showCamera = true
                    } label: {
                        Label("扫描一份并追加", systemImage: "camera.viewfinder")
                    }

                    Button {
                        activeSheet = .pickDocuments
                    } label: {
                        Label("从已有扫描件选择", systemImage: "doc.on.doc")
                    }

                    Button {
                        addBlankItem()
                    } label: {
                        Label("手动输入一段", systemImage: "square.and.pencil")
                    }
                } label: {
                    Label("追加文字", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    activeSheet = .export
                } label: {
                    Label("导出成一份文件", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(compilation?.isEmpty ?? true)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if let compilation, !compilation.isEmpty {
                EditButton()
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    renameText = compilation?.name ?? ""
                    showRename = true
                } label: {
                    Label("重命名汇总", systemImage: "pencil")
                }

                Button {
                    activeSheet = .pickDocuments
                } label: {
                    Label("从扫描件追加", systemImage: "doc.on.doc")
                }

                Button {
                    activeSheet = .export
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: 浮层

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 72)
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

    // MARK: 动作

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if toast == text { toast = nil }
        }
    }

    private func removeItems(at indexSet: IndexSet) {
        guard let compilation = store.compilation(id: compilationID) else { return }
        // 先把 id 快照下来，避免边删边取导致索引错位
        let ids = indexSet.compactMap { index -> UUID? in
            compilation.items.indices.contains(index) ? compilation.items[index].id : nil
        }
        for id in ids {
            store.removeItem(id: id, from: compilationID)
        }
    }

    private func addBlankItem() {
        let item = CompilationItem(title: "手动录入", body: "")
        store.addItems([item], to: compilationID)
        activeSheet = .editItem(item.id)
    }

    /// 相机扫描 → 新建一份文档 → 识别文字 → 追加到汇总末尾
    private func scanAndAppend(_ images: [UIImage]) {
        busyText = "正在保存 \(images.count) 页…"

        DispatchQueue.global(qos: .userInitiated).async {
            // 先在后台把方向矫正和缩放做掉，别让主线程卡在图片处理上
            let prepared = images.map { ImageTools.downscaled(ImageTools.normalized($0)) }

            DispatchQueue.main.async {
                let document = store.createDocument(pages: prepared)
                appendDocuments([document.id], refresh: false)
            }
        }
    }

    private func appendDocuments(_ ids: [UUID], refresh: Bool) {
        guard !ids.isEmpty else { return }
        busyText = "正在识别文字…"

        store.appendDocuments(ids,
                              to: compilationID,
                              refreshOCR: refresh,
                              progress: { done, total, message in
                                  busyText = "\(message)（\(done)/\(total)）"
                              },
                              completion: { added, emptyCount in
                                  busyText = nil
                                  if added == 0 {
                                      showToast("没有可追加的内容")
                                  } else if emptyCount > 0 {
                                      showToast("已追加 \(added) 份，其中 \(emptyCount) 份没识别到文字")
                                  } else {
                                      showToast("已追加 \(added) 份")
                                  }
                              })
    }

    /// 取正文第一行非空内容当预览
    static func preview(_ text: String) -> String {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "（空）"
    }
}

// MARK: - 挑选要追加的扫描件

struct AddDocumentsSheet: View {

    let compilationID: UUID
    var onConfirm: ([UUID], Bool) -> Void

    @StateObject private var store = DocumentStore.shared
    @Environment(\.dismiss) private var dismiss

    /// 用数组而不是 Set，因为点击顺序就是追加顺序
    @State private var picked: [UUID] = []
    @State private var forceRefresh = false

    var body: some View {
        NavigationStack {
            Group {
                if store.documents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("文件库里还没有扫描件")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        Section {
                            ForEach(store.documents) { document in
                                Button {
                                    toggle(document.id)
                                } label: {
                                    row(for: document)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("点一下选中，再点一下取消（已选 \(picked.count) 份）")
                        } footer: {
                            Text("点击顺序 = 追加顺序 = 导出后文字的排列顺序。没识别过文字的会在追加时自动识别。")
                        }

                        Section {
                            Toggle("重新识别已有文字", isOn: $forceRefresh)
                        } footer: {
                            Text("如果之前调整过页面（旋转、改滤镜），打开这个开关会按新页面重新识别一遍。")
                        }
                    }
                }
            }
            .navigationTitle("从扫描件追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(picked.isEmpty ? "追加" : "追加 (\(picked.count))") {
                        onConfirm(picked, forceRefresh)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(picked.isEmpty)
                }
            }
        }
    }

    private func row(for document: ScanDocument) -> some View {
        HStack(spacing: 12) {
            if let position = picked.firstIndex(of: document.id) {
                Text("\(position + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor))
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 20))
                    .foregroundColor(Color(.tertiaryLabel))
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(document.pages.count) 页 · \(document.ocrText.isEmpty ? "未识别文字" : "已识别 \(document.ocrText.count) 字")")
                    .font(.caption)
                    .foregroundColor(document.ocrText.isEmpty ? .orange : .secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func toggle(_ id: UUID) {
        if let index = picked.firstIndex(of: id) {
            picked.remove(at: index)
        } else {
            picked.append(id)
        }
    }
}

// MARK: - 把扫描件加进某一份汇总

struct AddToCompilationSheet: View {

    let documentIDs: [UUID]
    var onFinish: (Int, Int) -> Void = { _, _ in }

    @StateObject private var store = DocumentStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var busyText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("追加到哪一份汇总") {
                    Button {
                        start(compilationID: nil)
                    } label: {
                        Label("新建一份汇总", systemImage: "plus.circle")
                    }

                    ForEach(store.compilations) { compilation in
                        Button {
                            start(compilationID: compilation.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(compilation.name)
                                    .foregroundColor(.primary)
                                Text("\(compilation.itemCount) 份 · \(compilation.characterCount) 字")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Text("这 \(documentIDs.count) 份会按当前列表顺序排到已有内容的后面。还没有识别过文字的会自动识别。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("加入文字汇总")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .overlay { busyView }
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

    private func start(compilationID: UUID?) {
        let target = compilationID ?? store.createCompilation().id

        busyText = "正在识别文字…"
        store.appendDocuments(documentIDs,
                              to: target,
                              progress: { done, total, message in
                                  busyText = "\(message)（\(done)/\(total)）"
                              },
                              completion: { added, emptyCount in
                                  busyText = nil
                                  dismiss()
                                  onFinish(added, emptyCount)
                              })
    }
}

// MARK: - 编辑单条文字

struct ItemEditorSheet: View {

    let compilationID: UUID
    let itemID: UUID

    @StateObject private var store = DocumentStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var loaded = false

    private var item: CompilationItem? {
        store.compilation(id: compilationID)?.items.first { $0.id == itemID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("小标题") {
                    TextField("这一份叫什么", text: $title)
                }

                Section("正文") {
                    TextEditor(text: $bodyText)
                        .font(.system(size: 14))
                        .frame(minHeight: 260)
                }

                Section {
                    Text("当前 \(bodyText.count) 字。识别结果难免有错字，可以在这里直接改。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("编辑这一段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        store.updateItem(id: itemID,
                                         in: compilationID,
                                         title: title,
                                         body: bodyText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !loaded, let current = item else { return }
                title = current.title
                bodyText = current.body
                loaded = true
            }
        }
    }
}

// MARK: - 汇总导出

struct CompilationExportSheet: View {

    let compilationID: UUID

    @StateObject private var store = DocumentStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var format: CompilationFormat = .word
    @State private var fileName = ""
    @State private var options = CompilationExportOptions()

    @State private var isExporting = false
    @State private var progressText = ""
    @State private var exportURL: URL?
    @State private var errorText: String?

    private var compilation: TextCompilation? { store.compilation(id: compilationID) }

    var body: some View {
        NavigationStack {
            Form {
                Section("文件名") {
                    TextField("不填就用汇总名称", text: $fileName)
                }

                Section("导出格式") {
                    ForEach(CompilationFormat.allCases) { candidate in
                        Button {
                            format = candidate
                            exportURL = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: candidate.systemImage)
                                    .frame(width: 24)
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title)
                                        .foregroundColor(.primary)
                                    Text(candidate.detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if format == candidate {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("排版") {
                    Toggle("开头写入名称和字数统计", isOn: $options.includeHeader)
                    Toggle("每份前面写上名称", isOn: $options.includeTitles)

                    if format == .text || format == .markdown {
                        Toggle("每份之间加分隔线", isOn: $options.includeSeparator)
                    }

                    if format == .pdf {
                        Toggle("显示页码", isOn: $options.showPageNumbers)
                    }
                }

                Section {
                    Text(summary)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button {
                        startExport()
                    } label: {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(isExporting ? progressText : "生成文件")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(isExporting || (compilation?.isEmpty ?? true))

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            HStack {
                                Spacer()
                                Label("分享 / 保存文件", systemImage: "square.and.arrow.up")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("导出汇总")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                store.loadIfNeeded()
                if fileName.isEmpty {
                    fileName = compilation?.name ?? ""
                }
            }
            .alert("导出失败", isPresented: errorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var summary: String {
        guard let compilation else { return "汇总不存在。" }
        let base = "共 \(compilation.itemCount) 份 · \(compilation.characterCount) 字，将导出为 .\(format.fileExtension)"
        switch format {
        case .pdf:
            return base + "。PDF 里是真正的文字，可以选中、复制和全文搜索。"
        case .word:
            return base + "。可以直接在 Word 或 WPS 里继续排版。"
        default:
            return base + "。"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )
    }

    private func startExport() {
        guard let compilation, !compilation.isEmpty else { return }

        isExporting = true
        progressText = "正在生成…"
        exportURL = nil

        let chosenFormat = format
        let chosenOptions = options
        let chosenName = fileName.isEmpty ? compilation.name : fileName

        DispatchQueue.global(qos: .userInitiated).async {
            let url = store.exportCompilation(id: compilationID,
                                              format: chosenFormat,
                                              options: chosenOptions,
                                              fileName: chosenName,
                                              progress: { done, total in
                                                  DispatchQueue.main.async {
                                                      progressText = "正在排版… \(done)/\(total) 段"
                                                  }
                                              })

            DispatchQueue.main.async {
                isExporting = false
                progressText = ""
                if let url {
                    exportURL = url
                } else {
                    errorText = "生成失败，请确认汇总里还有内容。"
                }
            }
        }
    }
}

import SwiftUI
import UIKit

/// 单页查看器：左转 / 右转 / 三档滤镜 / 存到相册 / 删除本页
struct PageViewerView: View {

    let documentID: UUID
    let pageID: UUID

    @StateObject private var store = DocumentStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var hint: String?

    private var page: ScanPage? {
        store.document(id: documentID)?.pages.first { $0.id == pageID }
    }

    private var pageIndex: Int? {
        store.document(id: documentID)?.pages.firstIndex { $0.id == pageID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if let page, let image = store.renderedImage(for: page, in: documentID) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                } else {
                    Text("这一页读不出来了")
                        .foregroundColor(.secondary)
                }
            }
            .overlay(alignment: .bottom) {
                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle(pageIndex.map { "第 \($0 + 1) 页" } ?? "页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("完成") { dismiss() }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                saveToAlbum()
            } label: {
                Image(systemName: "photo.badge.arrow.down")
            }
        }

        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                rotate(by: -90)
            } label: {
                Label("左转", systemImage: "rotate.left")
            }

            Button {
                rotate(by: 90)
            } label: {
                Label("右转", systemImage: "rotate.right")
            }

            Menu {
                Picker("滤镜", selection: filterBinding) {
                    ForEach(PageFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
            } label: {
                Label(page?.filter.title ?? "滤镜", systemImage: "camera.filters")
            }

            Spacer()

            Button(role: .destructive) {
                deletePage()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var filterBinding: Binding<PageFilter> {
        Binding(
            get: { page?.filter ?? .color },
            set: { setFilter($0) }
        )
    }

    // MARK: - 操作

    private func rotate(by degrees: Int) {
        guard var doc = store.document(id: documentID),
              let index = doc.pages.firstIndex(where: { $0.id == pageID }) else { return }
        let value = ((doc.pages[index].rotation + degrees) % 360 + 360) % 360
        doc.pages[index].rotation = value
        store.update(document: doc)
    }

    private func setFilter(_ filter: PageFilter) {
        guard var doc = store.document(id: documentID),
              let index = doc.pages.firstIndex(where: { $0.id == pageID }) else { return }
        doc.pages[index].filter = filter
        store.update(document: doc)
    }

    private func deletePage() {
        guard var doc = store.document(id: documentID),
              let index = doc.pages.firstIndex(where: { $0.id == pageID }) else { return }
        doc.pages.remove(at: index)
        store.update(document: doc)
        dismiss()
    }

    private func saveToAlbum() {
        guard let page, let image = store.renderedImage(for: page, in: documentID) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        hint = "已存到相册"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            hint = nil
        }
    }
}

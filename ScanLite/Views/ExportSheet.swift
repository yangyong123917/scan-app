import SwiftUI

/// 导出设置：页码 / 水印 / 签名 / 加密 / 可搜索 PDF
struct ExportSheet: View {

    let documentID: UUID

    @StateObject private var store = DocumentStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showPageNumbers = true
    @State private var watermark = ""
    @State private var watermarkOpacity: Double = 0.15
    @State private var includeTextLayer = false
    @State private var password = ""
    @State private var signature: UIImage?
    @State private var useSignature = false
    @State private var showSignaturePad = false

    @State private var isExporting = false
    @State private var progressText = ""
    @State private var exportURL: URL?
    @State private var errorText: String?

    private var document: ScanDocument? { store.document(id: documentID) }

    var body: some View {
        NavigationStack {
            Form {
                Section("页面") {
                    Toggle("显示页码（第 X / Y 页）", isOn: $showPageNumbers)
                }

                Section("水印") {
                    TextField("水印文字，留空则不加", text: $watermark)

                    if !watermark.isEmpty {
                        HStack {
                            Text("浓淡")
                                .foregroundColor(.secondary)
                            Slider(value: $watermarkOpacity, in: 0.05...0.5)
                        }
                    }
                }

                Section("签名") {
                    Toggle("在每页右下角贴上签名", isOn: $useSignature)

                    HStack {
                        if let signature {
                            Image(uiImage: signature)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 40)
                        } else {
                            Text("还没有签名")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(signature == nil ? "去签名" : "重签") {
                            showSignaturePad = true
                        }
                    }

                    if signature != nil {
                        Button("删除已保存的签名", role: .destructive) {
                            store.clearSignature()
                            signature = nil
                            useSignature = false
                        }
                    }
                }

                Section("文件") {
                    Toggle("生成可搜索 PDF（写入文字层）", isOn: $includeTextLayer)
                    SecureField("打开密码，留空则不加密", text: $password)
                }

                Section {
                    Text("可搜索 PDF 会重新对每一页做文字识别，页数多时耗时会长一些。加密后的 PDF 在电脑和手机上打开都需要输密码。")
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
                            Text(isExporting ? progressText : "生成 PDF")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(isExporting || (document?.pages.isEmpty ?? true))

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            HStack {
                                Spacer()
                                Label("分享 / 保存 PDF", systemImage: "square.and.arrow.up")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("导出 PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                signature = store.savedSignature()
                useSignature = signature != nil
            }
            .sheet(isPresented: $showSignaturePad) {
                SignaturePadView { image in
                    store.saveSignature(image)
                    signature = image
                    useSignature = true
                }
            }
            .alert("导出失败", isPresented: errorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )
    }

    private func startExport() {
        guard let document, !document.pages.isEmpty else { return }

        isExporting = true
        progressText = "正在生成…"
        exportURL = nil

        var options = PDFExportOptions()
        options.showPageNumbers = showPageNumbers
        options.watermarkText = watermark.trimmingCharacters(in: .whitespacesAndNewlines)
        options.watermarkOpacity = CGFloat(watermarkOpacity)
        options.includeTextLayer = includeTextLayer
        options.password = password
        options.signature = useSignature ? signature : nil

        let name = document.name

        DispatchQueue.global(qos: .userInitiated).async {
            let url = store.export(documentIDs: [documentID],
                                   options: options,
                                   name: name) { done, total in
                DispatchQueue.main.async {
                    progressText = "正在生成… \(done)/\(total) 页"
                }
            }

            DispatchQueue.main.async {
                isExporting = false
                progressText = ""
                if let url {
                    exportURL = url
                } else {
                    errorText = "生成失败，请确认文档里还有页面。"
                }
            }
        }
    }
}

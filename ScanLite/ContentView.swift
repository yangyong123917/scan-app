import SwiftUI
import PhotosUI
import UIKit

extension UIImage {
    /// 把带方向的图片重绘成正向位图，避免后续坐标换算出错
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

struct ContentView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var original: UIImage?
    @State private var processed: UIImage?
    @State private var recognizedText = ""
    @State private var pdfURL: URL?
    @State private var busy = false
    @State private var status = "先选一张文档照片"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview
                    controls
                    statusRow
                    textSection
                }
                .padding()
            }
            .navigationTitle("扫描小工具")
        }
        .task(id: pickerItem) {
            guard let item = pickerItem else { return }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                status = "图片读取失败"
                return
            }
            original = image.normalized()
            processed = nil
            recognizedText = ""
            pdfURL = nil
            status = "图片已载入，点「开始处理」"
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))

            if let image = processed ?? original {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("尚未选择图片")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(height: 300)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("选择图片", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)

            Button {
                runPipeline()
            } label: {
                Label("开始处理", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(original == nil || busy)
        }

        if let pdfURL {
            ShareLink(item: pdfURL) {
                Label("导出 PDF", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView()
                    .scaleEffect(0.8)
            }
            Text(status)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var textSection: some View {
        if !recognizedText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("识别文字")
                        .font(.headline)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = recognizedText
                        status = "文字已复制到剪贴板"
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .font(.footnote)
                }

                Text(recognizedText)
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    private func runPipeline() {
        guard let source = original else { return }
        busy = true
        status = "正在检测边缘并识别文字…"

        DispatchQueue.global(qos: .userInitiated).async {
            var working = source
            var corrected = false

            if let corners = DocumentScanner.detectDocument(in: source),
               let straightened = DocumentScanner.perspectiveCorrect(source, corners: corners) {
                working = DocumentScanner.enhance(straightened) ?? straightened
                corrected = true
            } else if let enhanced = DocumentScanner.enhance(source) {
                working = enhanced
            }

            let text = TextRecognizer.recognize(in: working)
            let pdfData = PDFExporter.makePDF(from: [working])

            DispatchQueue.main.async {
                self.processed = working
                self.recognizedText = text

                if let pdfData {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("scan-\(Int(Date().timeIntervalSince1970)).pdf")
                    try? pdfData.write(to: url)
                    self.pdfURL = url
                }

                self.busy = false
                self.status = corrected
                    ? "已自动切边校正，可导出 PDF 或复制文字"
                    : "未检测到文档边缘，已按原图增强处理"
            }
        }
    }
}

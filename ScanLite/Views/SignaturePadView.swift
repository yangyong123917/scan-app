import SwiftUI
import PencilKit

/// 手写签名板：签名后转成透明背景的 PNG，导出 PDF 时可以贴到每页右下角
struct SignaturePadView: View {

    var onSave: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)

                    if canvas.drawing.strokes.isEmpty {
                        Text("在这里签名")
                            .foregroundColor(Color(.placeholderText))
                    }
                }
                .frame(height: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .padding(.horizontal)

                SignatureCanvas(canvas: $canvas)

                Text("用手指直接写，写完点右上角「保存」")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("手写签名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清除") {
                        canvas.drawing = PKDrawing()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let image = renderedSignature()
                        onSave(image)
                        dismiss()
                    }
                    .disabled(canvas.drawing.strokes.isEmpty)
                }
            }
        }
    }

    /// 用笔迹的实际包围盒裁出签名图，不留下大片空白
    private func renderedSignature() -> UIImage {
        var bounds = canvas.drawing.bounds
        if bounds.isEmpty {
            bounds = CGRect(x: 0, y: 0, width: 300, height: 120)
        }
        bounds = bounds.insetBy(dx: -12, dy: -12)
        return canvas.drawing.image(from: bounds, scale: 2.0)
    }
}

/// 把 PencilKit 画布嵌进 SwiftUI
struct SignatureCanvas: UIViewRepresentable {

    @Binding var canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

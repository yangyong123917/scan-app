import SwiftUI
import VisionKit

/// 系统自带的文档扫描器。
/// 直接用苹果的相机扫描界面，自动切边、透视校正、连续拍摄、单页重拍都是现成的，
/// 拍完得到一个多页扫描结果。
struct DocumentCameraView: UIViewControllerRepresentable {

    var onFinish: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {

        private let parent: DocumentCameraView

        init(_ parent: DocumentCameraView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                         didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for index in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: index))
            }
            parent.dismiss()
            if !images.isEmpty {
                parent.onFinish(images)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                         didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}

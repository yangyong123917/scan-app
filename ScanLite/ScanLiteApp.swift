import SwiftUI

@main
struct ScanLiteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 根视图：扫描件库 + 文字汇总 两个页签
struct RootView: View {

    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("扫描件", systemImage: "doc.text.viewfinder")
                }

            CompilationListView()
                .tabItem {
                    Label("文字汇总", systemImage: "text.alignleft")
                }
        }
    }
}

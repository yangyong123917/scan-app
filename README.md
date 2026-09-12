# ScanLite · 自用扫描 App（v2.1）

> **完全没做过的话，先看 [新手安装指南.md](新手安装指南.md)** —— 里面有每一步的点击位置、界面说明和报错处理。

一个纯端侧的 iOS 文档扫描工具，对标「扫描全能王」的自用版。
所有处理都在手机本地完成，**不需要服务器，不需要备案，不上架 App Store**。

---

## 功能

### 扫描
- **相机连续扫描**：调用苹果系统自带的文档扫描器（就是"备忘录 → 扫描文稿"里那个），
  自动检测边缘、透视拉正、连续拍多页、单页重拍，拍完直接成为一份多页文档
- **相册导入**：一次最多选 30 张，自动跑 Vision 边缘检测 + 透视校正 + 增强
- **导入已有 PDF**：把外部 PDF 逐页拆成图片，之后也能排序、旋转、加水印再导出

### 文件管理
- 文档库列表：首页缩略图、名称、页数、时间
- 搜索（按名称）、排序（时间 / 名称 / 页数）
- 重命名、复制一份、删除
- **多选合并**：勾选多份文档，按列表顺序拼成一份新的
- 数据存在 App 沙盒里，开启文件共享后可以用"文件"App 直接查看

### 页面编辑
- 拖动调整页序、左滑删除单页
- 单页旋转（左转 / 右转）
- 三档滤镜：彩色 / 灰度 / 黑白（**非破坏性**，原图不动，只记录标记）
- 追加页面（继续拍摄或从相册补）
- 单页存到系统相册

### PDF 输出
- A4 排版，自动等比缩放居中
- 页码（第 X / Y 页）
- 文字水印（可调浓淡）
- **手写签名**：用手指签名，转成透明 PNG 贴在每页右下角
- **打开密码**：用 CGPDFContext 原生加密
- **可搜索 PDF**：写入不可见的 OCR 文字层，生成后能用关键词搜索、能复制文字
- 体积控制：页面先压成 JPEG 再嵌入，避免 PDF 里图片被无损重压导致体积暴涨

### 文字识别
- 整份文档批量 OCR（中英），结果可选中、可复制、可分享

---

## 工程结构

```
scan-app/
├── project.yml                    # XcodeGen 工程定义（Windows 上只改这个）
├── ScanLite/
│   ├── ScanLiteApp.swift          # App 入口
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/
│   │       └── AppIcon-1024.png   # App 图标（1024×1024，无 alpha）
│   ├── Core/
│   │   ├── Models.swift           # ScanDocument / ScanPage / PageFilter
│   │   ├── DocumentStore.swift    # 沙盒读写、增删改查、缓存、导出
│   │   ├── ImageTools.swift       # 方向矫正、缩放、旋转、滤镜、缩略图
│   │   ├── DocumentScanner.swift  # Vision 边缘检测 + 透视校正 + 增强
│   │   ├── TextRecognizer.swift   # Vision 端侧 OCR（中英，含行坐标）
│   │   └── PDFBuilder.swift       # A4 合成 / 水印 / 页码 / 签名 / 加密 / 文字层 + PDF 导入
│   └── Views/
│       ├── LibraryView.swift      # 文件库首页
│       ├── DocumentDetailView.swift # 页列表、排序、OCR
│       ├── PageViewerView.swift   # 单页查看与编辑
│       ├── ScannerViews.swift     # 系统文档扫描器封装
│       ├── ExportSheet.swift      # 导出设置
│       └── SignaturePadView.swift # 手写签名（PencilKit）
├── tools/
│   └── make_app_icon.py           # 图标生成脚本（纯标准库，改颜色后重跑即可）
└── .github/workflows/build.yml    # GitHub Actions 自动构建未签名 IPA
```

`.xcodeproj` 不提交到仓库，由 GitHub Actions 里的 `xcodegen generate` 现场生成——
所以你完全不需要 Mac，也不需要手写 Xcode 工程文件。

**技术栈**：SwiftUI + Vision（边缘检测 / OCR）+ VisionKit（文档扫描器）+ Core Image（滤镜）
+ Core Graphics（PDF 生成与加密）+ PDFKit（PDF 导入）+ PencilKit（签名）。
全部是苹果原生框架，零第三方依赖，零服务器成本。

---

## 上传与构建

1. 在 GitHub 新建仓库，可见性选 **Public**
   （公开仓库的 macOS 构建免费，私有仓库按 10 倍消耗额度）
2. 用 GitHub Desktop 把 `scan-app` 文件夹加入并 Publish
3. 打开仓库的 **Actions** 标签页，等 `Build unsigned IPA` 跑完（这个工程约 1 分钟）
4. 点进绿色对勾的任务，页面**最底部**的 **Artifacts** 下载 `ScanLite-unsigned-ipa`
5. 解压得到 `ScanLite-unsigned.ipa`

> 构建失败时最常见的原因是 runner 镜像名变了，
> 把 `build.yml` 里的 `macos-latest` 改成 `macos-15` 再试。

---

## Windows 上签名安装

| 软件 | 用途 | 来源 |
|---|---|---|
| Apple Devices | 提供 iPhone 驱动 | 微软商店搜 "Apple Devices"（发布者须是 Apple Inc.） |
| iCloud | 补全驱动组件 | 微软商店搜 "iCloud" |
| Sideloadly | 用 Apple ID 签名 IPA | https://sideloadly.io |

1. 数据线连 iPhone，手机上点 **信任此电脑**
2. 打开 Sideloadly，把 IPA 拖到左上角的 IPA 大图标上
3. **Apple ID** 填账号邮箱
4. 展开 **Advanced Options**：
   - 想要**覆盖升级**（保留 App 内数据）→ **取消勾选** `Use automatic bundle ID`，
     在输入框里填一个固定的独特 ID，比如 `com.你的名字.scanlite`
   - 不在乎数据、只想装上 → 保持勾选 `Use automatic bundle ID`，
     但注意每次装都是新的随机 ID，会**多出一个图标**
5. 点 **Start** → 弹窗输密码（开了双重认证要用 App 专用密码）
6. iPhone 上：**设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID**
7. iOS 16 以上首次安装还需 **设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启手机**

---

## 关键问题：7 天过期

免费 Apple ID 签名只有 **7 天有效期**，过期后 App 打不开（图标变灰）。

**方式 A：手动续签** —— 每 7 天用 Sideloadly 重装一遍。

**方式 B：AltStore 自动续签（推荐）**
1. 下载 **AltServer for Windows**：https://altstore.io
2. 用数据线把 AltStore 装到 iPhone（AltServer 菜单 → Install AltStore）
3. 手机上打开 AltStore，用**同一个 Apple ID** 登录
4. Settings 里把 **Background Refresh** 打开
5. 之后只要 iPhone 和电脑在同一个 WiFi 下就会自动续签

---

## 常见问题

**Q：Sideloadly 报 "bundle identifier is not available"**
v0.60 里对应的是 `Use automatic bundle ID`（默认已勾选）。
还报错就取消勾选，手工填 `com.你的名字.scanlite`。

**Q：找不到"信任开发者"的入口**
iOS 16 以上路径是 **设置 → 通用 → VPN 与设备管理**，且必须先用数据线连过一次电脑。

**Q：App 装好但打不开，提示开发者模式**
**设置 → 隐私与安全性 →（滑到最底部）开发者模式 → 打开 → 重启手机 → 再点一次 Start**。

**Q：升级新版后数据丢了**
因为换了 bundle ID，系统会把新 App 当成另一个应用。
以后升级请固定同一个 bundle ID，安装时会覆盖升级，数据保留。
（另外：**删除 App 会连带删掉里面所有扫描件**，重要文件先导出 PDF。）

**Q：免费账号有什么限制**
同时最多 3 个自签 App，证书 7 天有效，需要定期续签。

**Q：以后想上架 App Store 怎么办**
需要付费开发者账号（$99/年）+ 中国大陆 ICP/App 备案 + 软件著作权。
代码本身不用改，`project.yml` 里把签名相关设置去掉即可。

**Q：升级后桌面图标还是空白方块**
iOS 会缓存 App 图标。先长按图标删除 App，再重新装一次就正常了。

**Q：想改 App 名字 / 图标**
- 名字：改 `project.yml` 里的 `CFBundleDisplayName`
- 图标：直接替换 `ScanLite/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
  （必须 1024×1024、PNG、**不能带透明通道**、**不要自己画圆角**），
  或在 `tools/make_app_icon.py` 里改配色后重跑脚本。

**Q：图标为什么是空白的**
Xcode 只会使用 `ASSETCATALOG_COMPILER_APPICON_NAME` 指定名字的图标资源集。
没有这个设置、或资源集里没有 1024×1024 的图，iOS 就显示系统默认的灰白方块。

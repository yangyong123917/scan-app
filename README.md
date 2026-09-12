# ScanLite · 自用扫描 App

> **完全没做过的话，先看 [新手安装指南.md](新手安装指南.md)** —— 里面有每一步的点击位置、界面说明和报错处理。

一个纯端侧的 iOS 文档扫描工具：拍照/选图 → 自动切边校正 → 文字识别 → 导出 PDF。
所有处理都在手机本地完成，**不需要服务器，不需要备案，不上架 App Store**。

---

## 工程结构

```
scan-app/
├── project.yml                    # XcodeGen 工程定义（Windows 上手写这个就够了）
├── ScanLite/
│   ├── ScanLiteApp.swift          # App 入口
│   ├── ContentView.swift          # 主界面 + 处理流程编排
│   ├── DocumentScanner.swift      # Vision 边缘检测 + 透视校正 + 图像增强
│   ├── TextRecognizer.swift       # Vision 端侧 OCR（中英）
│   └── PDFExporter.swift          # 图片合成 PDF
└── .github/workflows/build.yml    # GitHub Actions 自动构建未签名 IPA
```

`.xcodeproj` 不提交到仓库，由 GitHub Actions 里的 `xcodegen generate` 现场生成——
所以你完全不需要 Mac，也不需要手写 Xcode 工程文件。

---

## 第一步：上传到 GitHub

1. 注册/登录 GitHub，右上角 **New repository**
2. 仓库名随意，比如 `scanlite`
3. 可见性选 **Public**（重要：公开仓库的 macOS 构建免费，私有仓库会消耗额度）
4. 创建后，把 `scan-app` 目录里的所有内容推上去：

```bash
cd scan-app
git init
git add .
git commit -m "init: 扫描 App"
git branch -M main
git remote add origin https://github.com/<你的用户名>/scanlite.git
git push -u origin main
```

也可以用网页版直接拖拽上传（注意 `.github/workflows/build.yml` 必须保持这个目录结构）。

---

## 第二步：等待构建，下载 IPA

1. 推送后打开仓库的 **Actions** 标签页
2. 会看到一条 `Build unsigned IPA` 的任务在运行，大约 3–6 分钟
3. 变成绿色对勾后，点进去，页面底部 **Artifacts** 区域
4. 下载 `ScanLite-unsigned-ipa`，解压得到 `ScanLite-unsigned.ipa`

> 如果构建失败，点开失败的步骤看日志。最常见的原因是 runner 镜像名变了，
> 把 `build.yml` 里的 `macos-latest` 改成 `macos-15` 或 `macos-14` 再试。

---

## 第三步：Windows 上签名安装

### 准备环境

| 软件 | 用途 | 下载 |
|---|---|---|
| Apple Devices 或 iTunes | 提供 iPhone 驱动 | 微软商店搜 "Apple Devices" |
| iCloud | 补全驱动组件 | 微软商店搜 "iCloud" |
| Sideloadly | 用 Apple ID 签名 IPA | https://sideloadly.io |

### 安装步骤

1. 用数据线连接 iPhone，手机上点 **信任此电脑**
2. 打开 Sideloadly，把 `ScanLite-unsigned.ipa` 拖进窗口
3. **Apple ID** 填你的 Apple ID（建议用一个不绑重要数据的账号）
4. 如果提示 bundle id 冲突，勾选 **Change Bundle ID** 让它自动改一个唯一的
5. 点 **Start**，按提示输入 Apple ID 密码
6. 安装完成后，手机上进入：
   **设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任你的 Apple ID**
7. 回到桌面，App 就能打开了

---

## 关键问题：7 天过期

用免费 Apple ID 签名，证书只有 **7 天有效期**。过期后 App 打不开（图标变灰），必须重新签名安装。

两种应对方式：

**方式 A：手动续签（简单）**
每 7 天重连一次电脑，用 Sideloadly 重装一遍。适合偶尔用。

**方式 B：AltStore 自动续签（推荐）**

1. 下载 **AltServer for Windows**：https://altstore.io
2. 把它安装的 **AltStore** 通过数据线装到 iPhone 上（AltServer 菜单 → Install AltStore）
3. 手机上打开 AltStore，用同一个 Apple ID 登录
4. 在 AltStore 的 **Settings** 里，把我的 App 的 **Background Refresh** 打开
5. 之后只要 iPhone 和电脑在**同一个 WiFi**下，AltStore 会自动在后台续签，你不用管

AltStore 也支持直接安装 IPA，可以完全替代 Sideloadly。

---

## 常见问题

**Q：Sideloadly 报 "bundle identifier is not available"**
勾选 Sideloadly 界面上的 `Change Bundle ID`，或者修改 `project.yml` 里的
`PRODUCT_BUNDLE_IDENTIFIER` 为更独特的名字（比如加上你的名字），重新构建。

**Q：找不到"信任开发者"的入口**
iOS 16 以上路径是 **设置 → 通用 → VPN 与设备管理**。必须先用数据线连过一次电脑才会出现。

**Q：免费账号有什么限制**
同时最多只能有 3 个自签 App，证书 7 天有效，需要定期续签。

**Q：以后想上架 App Store 怎么办**
需要：付费开发者账号（$99/年）+ 中国大陆 ICP/App 备案 + 软件著作权。
代码本身不用改，`project.yml` 里把签名相关设置去掉即可。

**Q：想改 App 名字 / 图标**
- 名字：改 `project.yml` 里的 `CFBundleDisplayName`
- 图标：把 `AppIcon.appiconset` 放进 `ScanLite/Assets.xcassets/`，
  并在 `project.yml` 里设置 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`

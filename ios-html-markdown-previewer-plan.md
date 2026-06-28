# iOS HTML / Markdown 预览 App 设计与开发计划文档

版本：v0.1  
日期：2026-06-27  
平台：iOS / iPadOS  
技术栈：SwiftUI + WebKit + UniformTypeIdentifiers + StoreKit  
商业模式：简洁、无广告、买断制

---

## 1. 项目概述

本项目要做一个专注于 iPhone / iPad 的本地 HTML 与 Markdown 文件预览 App。核心场景不是“写网页代码”，而是用户在微信、文件 App、邮件、网盘、聊天工具、AirDrop 或其他 App 中收到 `.html`、`.htm`、`.md`、`.markdown` 文件时，可以通过“用其他应用打开 / 分享到本 App”快速预览。

一句话定位：

> 一个简洁、无广告、本地处理的 iOS 离线 HTML / Markdown 预览器，解决手机上打不开或看不舒服本地 HTML / MD 文件的问题。

核心产品原则：

1. **本地优先**：文件默认只在设备本地处理，不上传服务器。
2. **安全默认**：HTML 默认以安全预览模式打开，限制脚本、跳转和外部网络资源。
3. **入口优先**：比起做复杂编辑器，更优先做好“从微信 / 文件 / 网盘打开”。
4. **资源完整性优先**：重点解决 HTML 相关图片、CSS、JS、assets 文件丢失的问题。
5. **简洁买断**：无广告、无订阅、无账号。可选择付费下载或免费试用 + 一次性解锁。

---

## 2. 目标用户与典型场景

### 2.1 目标用户

第一类是普通用户。用户收到别人发来的 HTML 报告、离线网页、导出的聊天记录、笔记、说明文档，不知道该用什么打开。

第二类是学生、知识工作者和 AI 工具用户。用户经常收到或生成 `.md`、`.html`、README、AI 生成报告、课程资料、网页导出文件，希望在手机上快速阅读。

第三类是开发者、产品经理和设计师。用户偶尔需要在手机上检查本地 HTML、Markdown 文档或构建产物，但不想打开重型代码编辑器。

第四类是 iPad 用户。用户在 iPad 上管理文件、阅读资料、接收网盘文档，希望获得类似桌面端的本地预览体验。

### 2.2 高频场景

用户在微信里收到一个 `report.html`，点开后只能看到源码、空白页面或提示无法预览，于是选择“用其他应用打开”，进入本 App 预览。

用户从文件 App 里点开 `README.md`，系统无法渲染 Markdown，本 App 以排版后的阅读视图显示。

用户收到一个 `report.zip`，里面包含 `index.html`、`style.css`、`images/`，本 App 解压到沙盒目录后自动识别入口文件并完整预览。

用户打开一个带 JavaScript 的交互式 HTML，本 App 默认禁用脚本并提示“已使用安全预览”。用户可手动切换到“互动模式”。

---

## 3. MVP 范围

### 3.1 MVP 必做功能

| 功能 | 说明 | 优先级 |
|---|---|---|
| 外部文件打开入口 | 注册 `.html`、`.htm`、`.md`、`.markdown`、`.zip` 文件类型，出现在 iOS 打开方式 / 分享菜单中 | P0 |
| App 内打开文件 | 首页提供“打开文件”按钮，调用系统文件选择器 | P0 |
| HTML 安全预览 | 使用 WKWebView 渲染本地 HTML，默认禁用 JavaScript，并限制外部跳转 | P0 |
| Markdown 阅读预览 | 渲染标题、段落、列表、引用、代码块、链接、图片等常见 Markdown 元素 | P0 |
| ZIP 报告包导入 | 解压 zip，自动查找 `index.html` / `index.htm` / 首个 HTML 文件 | P0 |
| 最近打开列表 | 本地保存导入文件记录，方便二次打开 | P0 |
| 文件详情 | 显示文件名、类型、大小、导入时间、当前安全模式 | P0 |
| 原始文本模式 | 对 HTML / MD 提供“查看源码 / 原文”备用视图 | P0 |
| 错误提示 | 对无法读取、编码异常、资源缺失、无入口文件等情况给出明确说明 | P0 |
| 无广告、无账号 | MVP 不集成广告 SDK，不做登录系统 | P0 |
| 买断制 | 采用付费下载或非消耗型 IAP 一次性解锁 | P0 |

### 3.2 MVP 不做功能

MVP 不做 HTML 编辑器、代码编辑器、云同步、多人协作、账号系统、网页浏览器、远程 URL 浏览、自动爬取网页、完整开发者调试工具、复杂模板系统。

MVP 不承诺“在微信里第一次点击文件就一定自动进入本 App”。iOS 与第三方 App 的文件处理入口由系统和来源 App 共同决定，产品文案应表述为“通过分享 / 用其他应用打开来预览”。

### 3.3 P1 功能

| 功能 | 说明 |
|---|---|
| 页面内搜索 | 对 HTML 文本和 Markdown 文本搜索 |
| PDF 导出 | 将当前预览导出为 PDF |
| 字号与阅读主题 | 支持系统字号、浅色 / 深色 / 跟随系统 |
| Markdown 表格优化 | 完整支持 GFM 表格、任务列表 |
| 历史记录管理 | 批量删除、收藏、重命名 |
| 文件夹导入 | 支持从文件 App 选择整个目录，用于 HTML + assets |
| 分享预览结果 | 分享为 PDF、HTML 副本或纯文本 |
| iPad 双栏布局 | 首页列表 + 预览详情分栏 |

### 3.4 P2 功能

| 功能 | 说明 |
|---|---|
| MHTML 支持 | 评估 `.mhtml` / `.mht` 可行性 |
| Web Archive 支持 | 评估 `.webarchive` 可行性 |
| HTML 资源诊断 | 显示缺失图片、CSS、JS 列表 |
| 简易开发者控制台 | 仅互动模式下显示 console 日志 |
| Shortcuts 支持 | 通过快捷指令打开 / 转换文件 |
| Quick Look 扩展 | 评估能否为文件 App 提供更自然的预览体验 |

---

## 4. 支持文件类型

### 4.1 MVP 文件类型矩阵

| 扩展名 | 类型 | 处理方式 | 备注 |
|---|---|---|---|
| `.html` | HTML | WKWebView 本地加载 | MVP 核心 |
| `.htm` | HTML | WKWebView 本地加载 | MVP 核心 |
| `.md` | Markdown | SwiftUI Markdown 阅读视图 | MVP 核心 |
| `.markdown` | Markdown | SwiftUI Markdown 阅读视图 | MVP 核心 |
| `.zip` | HTML 包 / 文档包 | 解压后识别入口文件 | 解决 assets 丢失问题 |
| `.txt` | 纯文本 | P1 或仅作为 fallback | 避免 App 过度出现在所有文本文件打开菜单里 |
| `.mhtml` / `.mht` | 网页归档 | P2 评估 | 不进入 MVP 承诺 |

### 4.2 Markdown UTI 建议

Markdown 使用 `net.daringfireball.markdown`。为了兼容 iOS 文件识别差异，可在 Info.plist 中添加 Imported Type Declaration，将 `.md`、`.markdown` 映射到该类型，并让它 conform to `public.plain-text`。

Swift 中可先使用：

```swift
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown")
}
```

若目标 SDK 中 `UTType.markdown` 已稳定可用，再评估切换为系统静态属性。

---

## 5. 信息架构与 UI 设计

### 5.1 App 结构

```text
App
├── Home
│   ├── Recent Documents
│   ├── Open File
│   ├── Open ZIP Package
│   └── Settings
├── Preview
│   ├── Rendered Preview
│   ├── Raw Text / Source
│   ├── File Details
│   └── Actions
└── Settings
    ├── Default Preview Mode
    ├── Security Options
    ├── Purchase / Restore Purchase
    ├── Privacy
    └── Help
```

### 5.2 首页

首页目标是极简，避免做成文件管理器。

首页组成：

1. 顶部标题：建议使用产品名 + 一句说明，例如“打开 HTML 与 Markdown 文件”。
2. 主操作按钮：
   - “打开文件”
   - “打开 ZIP 报告包”
3. 最近打开列表：
   - 文件名
   - 类型标签：HTML / MD / ZIP
   - 导入时间
   - 安全模式状态
4. 空状态说明：
   - “在微信、文件或网盘中选择‘用其他应用打开’或‘分享’，即可用本 App 预览。”
5. 设置入口。

SwiftUI 建议：

- iPhone：`NavigationStack`
- iPad：P1 使用 `NavigationSplitView`
- 列表：`List` 或 `ScrollView + LazyVStack`
- 图标：优先使用 SF Symbols
- 颜色：只用系统语义色，支持 Dark Mode

### 5.3 预览页

预览页结构：

```text
Navigation Bar
├── Back
├── File Title
└── More Menu

Status Strip
├── File Type
├── Safe Preview / Interactive
└── Resource Status

Content
└── HTML WKWebView / Markdown SwiftUI View / Raw Text View

Bottom or Toolbar Actions
├── Toggle Raw / Preview
├── Text Size
├── Share
└── Details
```

预览页顶部建议显示一个轻量状态条，而不是弹窗：

- “安全预览：已限制脚本与外部跳转”
- “互动模式：允许脚本运行，仅用于可信文件”
- “部分资源可能缺失：建议导入 zip 包”

### 5.4 文件详情页

文件详情字段：

- 文件名
- 文件类型
- 文件大小
- 导入来源：外部打开 / App 内选择 / ZIP 包
- 导入时间
- 本地路径状态：已复制到本 App / 临时文件
- 安全模式
- 是否包含外部资源
- ZIP 解压文件数量
- 入口文件路径

### 5.5 设置页

设置项：

| 设置 | 默认值 | 说明 |
|---|---|---|
| HTML 默认模式 | 安全预览 | 禁用 JS 与外部跳转 |
| 允许外部链接 | 关闭 | 开启后点击链接仍需二次确认 |
| Markdown 默认字号 | 跟随系统 | 支持 Dynamic Type |
| 最近文件保留 | 保留 | 用户可手动清除 |
| 清除缓存 | 手动 | 删除导入副本与 ZIP 解压目录 |
| 购买状态 | 未购买 / 已购买 | 买断制 |
| 恢复购买 | 可用 | 若采用 IAP 方案 |
| 隐私说明 | 常驻 | 明确“不上传文件” |

---

## 6. 核心交互流程

### 6.1 从微信 / 第三方 App 打开 HTML

目标流程：

```text
用户收到 report.html
→ 点“用其他应用打开”或“分享”
→ 选择本 App
→ App 导入文件
→ 进入预览页
→ 默认使用安全预览
```

关键处理：

1. App 通过 Document Types 注册可打开的文件类型。
2. 收到 URL 后立即复制到 App 沙盒，避免来源 App 清理临时文件。
3. 若只收到单个 HTML 文件，不承诺能读取同目录 assets。
4. 若检测到缺失资源或相对路径引用，显示提示：“如果图片或样式缺失，请将 HTML 与 assets 打包为 zip 后打开。”

### 6.2 从文件 App 打开文件

```text
用户在本 App 首页点“打开文件”
→ 系统文件选择器
→ 用户选择 HTML / MD / ZIP
→ App 获取 security-scoped URL
→ 读取并复制到沙盒
→ 释放 security scope
→ 进入预览
```

外部文件访问必须严格成对调用：

```swift
let didAccess = url.startAccessingSecurityScopedResource()
defer {
    if didAccess {
        url.stopAccessingSecurityScopedResource()
    }
}

// copy or read file here
```

### 6.3 ZIP 报告包打开

```text
用户选择 report.zip
→ App 校验 zip
→ 解压到 app-private/imports/{uuid}/
→ 自动查找入口文件
→ 如果多个 HTML，显示入口选择页
→ 使用入口 HTML + 解压根目录加载
```

入口文件识别顺序：

1. `index.html`
2. `index.htm`
3. 根目录第一个 `.html`
4. 所有子目录中最短路径的 `.html`
5. 若找不到，显示错误页

ZIP 安全要求：

- 拒绝 path traversal，例如 `../../file`
- 拒绝绝对路径
- 设定解压大小上限
- 设定文件数量上限
- 解压到 App 私有目录
- 解压失败时清理临时目录

### 6.4 HTML 安全预览与互动模式

默认模式：安全预览。

默认限制：

- 禁用 JavaScript
- 阻止外部网络请求
- 阻止自动跳转到外部 App / Safari
- 阻止 `window.open`
- 对非 `file://` 链接点击进行确认
- 默认使用非持久化 WebKit 数据存储

互动模式：

- 用户手动开启
- 开启前显示风险说明
- 可允许 JavaScript 与本地资源交互
- 外部链接仍建议二次确认
- 不作为默认模式

建议文案：

> 互动模式会允许该 HTML 运行脚本。请仅对你信任的文件开启。

---

## 7. 技术架构

### 7.1 总体架构

```text
SwiftUI App
├── AppRouter
├── DocumentIntakeService
│   ├── ExternalOpenHandler
│   ├── FileImporterHandler
│   ├── SecurityScopedAccess
│   └── ImportCopyService
├── DocumentStore
│   ├── MetadataStore
│   ├── FileStorage
│   └── RecentDocuments
├── PreviewEngine
│   ├── HTMLPreviewEngine
│   ├── MarkdownPreviewEngine
│   ├── ZipPackageEngine
│   └── RawTextEngine
├── SecurityPolicy
│   ├── SafePreviewPolicy
│   ├── NavigationPolicy
│   └── ResourcePolicy
├── PurchaseManager
└── SwiftUI Views
```

### 7.2 推荐目录结构

```text
App/
├── HTMLMDPreviewerApp.swift
├── AppRouter.swift
├── Models/
│   ├── PreviewDocument.swift
│   ├── PreviewPackage.swift
│   ├── PreviewMode.swift
│   └── ImportSource.swift
├── Services/
│   ├── DocumentIntakeService.swift
│   ├── FileStorageService.swift
│   ├── ZipImportService.swift
│   ├── MarkdownRenderService.swift
│   ├── SecurityPolicyService.swift
│   └── PurchaseManager.swift
├── Views/
│   ├── HomeView.swift
│   ├── PreviewView.swift
│   ├── HTMLPreviewView.swift
│   ├── MarkdownPreviewView.swift
│   ├── RawTextView.swift
│   ├── FileDetailsView.swift
│   ├── SettingsView.swift
│   └── PurchaseView.swift
├── Web/
│   ├── WKWebViewContainer.swift
│   ├── WebNavigationDelegate.swift
│   └── ContentBlockerRules.swift
├── Utilities/
│   ├── FileTypeDetector.swift
│   ├── EncodingDetector.swift
│   ├── SizeFormatter.swift
│   └── ErrorMapper.swift
└── Resources/
    ├── Sample/
    └── Localizable.xcstrings
```

### 7.3 数据模型

```swift
struct PreviewDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var originalFilename: String
    var fileExtension: String
    var type: PreviewDocumentType
    var importSource: ImportSource
    var importedAt: Date
    var localRootRelativePath: String
    var entryFileRelativePath: String
    var fileSize: Int64
    var lastOpenedAt: Date?
    var preferredPreviewMode: PreviewMode
}

enum PreviewDocumentType: String, Codable {
    case html
    case markdown
    case zipPackage
    case plainText
    case unsupported
}

enum PreviewMode: String, Codable {
    case safePreview
    case interactive
    case rawText
}
```

### 7.4 文件存储策略

所有导入文件复制到 App 沙盒，推荐路径：

```text
Application Support/
└── Imports/
    └── {documentUUID}/
        ├── original/
        ├── extracted/
        └── metadata.json
```

原则：

1. 从第三方 App 传入的文件可能是临时文件，必须复制。
2. 从文件 App 选中的文件也复制，避免长期依赖 security-scoped URL。
3. ZIP 解压结果仅放在 App 私有目录。
4. “最近打开”只记录 App 沙盒内副本，不记录外部真实路径。
5. 用户清除缓存时删除 Imports 目录下对应文档。

### 7.5 文件类型注册

Info.plist 需要配置 `CFBundleDocumentTypes`，让系统知道本 App 可作为这些文件的查看器。

示例方向：

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>HTML Document</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.html</string>
            <string>public.xhtml</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Markdown Document</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>net.daringfireball.markdown</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleTypeName</key>
        <string>ZIP Package</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.zip-archive</string>
        </array>
    </dict>
</array>
```

Markdown 若系统未识别，需要 Imported Type Declaration：

```xml
<key>UTImportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>net.daringfireball.markdown</string>
        <key>UTTypeDescription</key>
        <string>Markdown Document</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.plain-text</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>md</string>
                <string>markdown</string>
            </array>
            <key>public.mime-type</key>
            <array>
                <string>text/markdown</string>
                <string>text/x-markdown</string>
            </array>
        </dict>
    </dict>
</array>
```

### 7.6 外部打开处理

SwiftUI App 生命周期可通过 `.onOpenURL` 接收打开请求，具体行为需要结合实际 Document Types 与来源 App 测试。

示意：

```swift
@main
struct HTMLMDPreviewerApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .onOpenURL { url in
                    Task {
                        await router.handleIncomingURL(url)
                    }
                }
        }
    }
}
```

注意：部分来源 App 可能不是通过普通 URL 传递，或会先复制到系统 Inbox。开发时需要分别测试文件 App、微信、邮件、AirDrop、iCloud Drive、网盘 App。

---

## 8. HTML 预览实现

### 8.1 WKWebView 封装

SwiftUI 使用 `UIViewRepresentable` 包装 WKWebView：

```swift
import SwiftUI
import WebKit

struct HTMLPreviewView: UIViewRepresentable {
    let fileURL: URL
    let readAccessRootURL: URL
    let mode: PreviewMode

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = (mode == .interactive)
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessRootURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let mode: PreviewMode

        init(mode: PreviewMode) {
            self.mode = mode
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.isFileURL {
                decisionHandler(.allow)
                return
            }

            // MVP：默认阻止非 file URL。P1 可改为二次确认后外部打开。
            decisionHandler(.cancel)
        }
    }
}
```

### 8.2 读取权限根目录

单文件 HTML：

```text
Imports/{uuid}/original/report.html
```

此时 `allowingReadAccessTo` 可设置为 `original/` 目录。

ZIP 包 HTML：

```text
Imports/{uuid}/extracted/index.html
Imports/{uuid}/extracted/assets/style.css
Imports/{uuid}/extracted/images/a.png
```

此时 `allowingReadAccessTo` 应设置为 `extracted/` 根目录，保证相对资源可读取。

### 8.3 HTML 安全策略

MVP 安全策略：

| 项 | 安全预览 | 互动模式 |
|---|---|---|
| JavaScript | 禁用 | 允许 |
| `file://` 本地资源 | 允许读取授权根目录内资源 | 允许读取授权根目录内资源 |
| `http://` / `https://` | 阻止或提示 | 提示后允许外部打开 |
| 外部 App Scheme | 阻止 | 提示 |
| `window.open` | 阻止 | 提示或阻止 |
| Web Storage | 非持久化 | 非持久化，后续可配置 |
| Cookie | 非持久化 | 非持久化 |

开发注意：

1. `WKWebpagePreferences.allowsContentJavaScript` 用于控制网页内容中的 JavaScript 是否允许运行。
2. `WKWebView.loadFileURL(_:allowingReadAccessTo:)` 用于加载本地文件并授予 WebView 对某个本地文件或目录的读取权限。
3. 仅通过 navigation delegate 阻止外部链接可能不足以覆盖所有资源请求；P1 应评估 WKContentRuleList 或自定义资源策略，尽量阻断外部网络资源。
4. 默认不注入自定义 JS，避免扩大攻击面。
5. 不把 HTML 中的表单提交视为可信行为；安全模式下应阻止。

---

## 9. Markdown 预览实现

### 9.1 推荐策略

MVP 推荐使用 SwiftUI 原生视图渲染 Markdown，而不是把 Markdown 全部转成 HTML 再交给 WebView。理由：

1. 阅读体验更像原生 App。
2. 字号、动态类型、深色模式、无障碍更容易控制。
3. 安全边界更清晰。
4. 产品定位是“简洁阅读器”，不是网页浏览器。

技术路径：

- 使用 Apple / Swift 官方开源的 `swift-markdown` 解析 Markdown AST。
- 自己实现常见块级元素 SwiftUI 渲染。
- 内联样式可使用 `AttributedString(markdown:)` 处理一部分常见文本样式。
- 表格、任务列表等 GFM 特性可以在 P1 增强。

### 9.2 MVP 支持 Markdown 元素

| 元素 | MVP |
|---|---|
| 标题 H1-H6 | 支持 |
| 段落 | 支持 |
| 粗体 / 斜体 / 删除线 | 支持或尽量支持 |
| 行内代码 | 支持 |
| 代码块 | 支持 |
| 有序 / 无序列表 | 支持 |
| 引用 | 支持 |
| 链接 | 支持，点击前确认或打开 Safari |
| 图片 | 支持本地相对图片；远程图片默认不加载 |
| 分隔线 | 支持 |
| 表格 | P1 |
| 任务列表 | P1 |
| Mermaid | P2，不进入 MVP |

### 9.3 Markdown 图片策略

Markdown 中的图片路径分三类：

1. 相对路径：从 Markdown 文件所在目录或 ZIP 解压目录读取。
2. `file://`：仅允许 App 授权目录内路径。
3. `http://` / `https://`：默认不自动加载，可显示占位提示“远程图片已阻止”。

---

## 10. ZIP 包处理

### 10.1 解压库选择

方案 A：使用成熟 Swift ZIP 库，例如 ZIPFoundation。优点是实现快，维护成本低；缺点是增加第三方依赖。

方案 B：自己封装底层解压能力。优点是依赖少；缺点是开发成本高，边界问题多。

MVP 建议：使用成熟开源库，但引入依赖前做源码审查，并记录许可证。由于产品承诺隐私与无广告，所有第三方依赖必须满足：

- 不含广告 SDK
- 不含分析 SDK
- 不含网络请求
- 许可证允许 App Store 商业发布
- 依赖数量尽量少

### 10.2 安全校验

ZIP 导入必须包含以下校验：

```text
- 不能出现 ../
- 不能出现绝对路径
- 不能覆盖已有文件
- 解压后总大小不能超过限制
- 文件数量不能超过限制
- 单文件大小不能超过限制
- 入口文件必须是 html / htm / md / markdown
```

建议默认限制：

| 项 | 建议值 |
|---|---|
| ZIP 文件大小 | 100 MB |
| 解压后总大小 | 300 MB |
| 文件数量 | 5,000 |
| 单文件大小 | 100 MB |

这些限制应在设置或内部常量中可调整，并在错误提示中讲清楚。

---

## 11. 购买与商业模式

### 11.1 推荐商业方案

有两种可选方案。

方案 A：付费下载 App。

优点：

- 最简洁
- 不需要购买页
- 不需要 StoreKit 购买逻辑
- 与“无广告、买断制”心智一致

缺点：

- 用户无法先试用
- App Store 搜索转化可能较低
- 需要产品页和截图非常清楚地解释价值

方案 B：免费下载 + 一次性买断解锁 Pro。

优点：

- 用户可以先验证是否能从微信 / 文件 App 打开
- 更适合解决“我不确定这个工具能不能处理我的文件”的顾虑
- 可通过非消耗型 IAP 实现买断

缺点：

- 需要 StoreKit
- 需要购买 / 恢复购买 UI
- 需要定义免费版限制，限制太多会损害简洁感

建议：

如果第一版目标是快速上线和极简，可以选择**付费下载**。如果目标是先验证转化和口碑，建议选择**免费下载 + 非消耗型 IAP 买断**。

### 11.2 若采用免费 + 买断

免费版建议不要用广告，不做烦人的弹窗。可以限制高级功能，而不是限制基础打开能力。

免费版：

- HTML / MD 基础打开
- 安全预览
- 最近记录保留少量，例如 3 个
- ZIP 包可预览小文件或试用次数有限

买断版：

- 无限最近记录
- ZIP 报告包完整支持
- PDF 导出
- 文件夹导入
- 自定义阅读设置
- 互动模式
- 批量清理与收藏

### 11.3 StoreKit 注意事项

若采用非消耗型 IAP：

- 使用 StoreKit 2
- 支持恢复购买
- 支持 Family Sharing 可作为加分项
- 使用 App Receipt 或 Transaction 当前权益判断购买状态
- 购买页文案必须明确“一次性购买，无订阅”
- App Store Connect 里配置 Non-Consumable IAP

---

## 12. 隐私与安全

### 12.1 隐私承诺

产品页与设置页建议明确写：

> 文件默认仅在本机处理。App 不上传你的 HTML、Markdown 或 ZIP 文件。App 不含广告 SDK，不创建账号，不追踪你的文件内容。

MVP 不做：

- 自建后端
- 用户账号
- 文件上传
- 行为追踪 SDK
- 广告 SDK
- 第三方登录

允许的网络行为：

- App Store / StoreKit 购买校验
- 用户主动打开外部链接时跳转 Safari
- 用户主动发送反馈邮件

### 12.2 HTML 风险提示

HTML 文件不是普通文本，它可能包含脚本、表单、跳转和外部资源。产品必须把“安全预览”作为默认值。

风险提示文案：

> 此文件是 HTML，可能包含脚本或外部链接。为保护你的设备与隐私，已使用安全预览模式打开。

互动模式提示：

> 仅对你信任的文件开启互动模式。开启后，文件中的脚本可能运行，并尝试加载外部资源。

### 12.3 资源缺失提示

当检测到 HTML 中引用了相对资源但文件不存在时，提示：

> 此 HTML 引用了外部资源，但当前只导入了单个文件。若页面样式或图片缺失，请将 HTML 与 assets 文件夹一起打包为 zip 后打开。

---

## 13. 可访问性与本地化

### 13.1 可访问性

MVP 必须支持：

- Dynamic Type
- VoiceOver 基础读屏
- 深色模式
- 增强对比度
- 减少动态效果
- 横竖屏
- iPad 分屏基础适配
- 触控目标不小于系统推荐尺寸

Markdown 阅读视图应优先满足 Dynamic Type。HTML 内容内部字号不一定可完全控制，因此可提供网页缩放或“阅读模式”作为 P1。

### 13.2 本地化

MVP 先支持：

- 简体中文
- 英文

P1 支持：

- 繁体中文
- 日文

所有错误提示、安全提示、购买文案需要进入 `Localizable.xcstrings`。

---

## 14. 错误状态设计

| 错误 | 用户提示 | 开发处理 |
|---|---|---|
| 文件无法读取 | 无法打开此文件。请确认文件仍存在且未损坏。 | 记录错误码 |
| 文件类型不支持 | 当前版本暂不支持此格式。 | 显示支持格式 |
| 编码识别失败 | 无法识别文本编码。你可以尝试用原文模式打开。 | UTF-8 fallback |
| ZIP 解压失败 | ZIP 包无法解压，可能已损坏或受密码保护。 | 清理临时目录 |
| ZIP 无入口文件 | 未找到可预览的 HTML 或 Markdown 文件。 | 显示文件列表 |
| 资源缺失 | 页面可能显示不完整。建议导入 zip 包。 | 标记资源状态 |
| 文件过大 | 文件过大，当前版本暂不支持预览。 | 显示限制 |
| 脚本被禁用 | 已使用安全预览，脚本不会运行。 | 提供互动模式入口 |
| 外部链接被阻止 | 为保护隐私，已阻止外部链接。 | 可二次确认 |

---

## 15. 开发里程碑

### M0：技术验证

目标：验证核心 iOS 入口与 WebKit 可行性。

交付：

- App 可出现在 HTML / MD / ZIP 打开方式中
- 可从文件 App 导入 HTML
- WKWebView 能加载本地 HTML
- `allowingReadAccessTo` 能读取同目录图片 / CSS
- 可从 ZIP 解压并预览 `index.html`
- Markdown 最小可渲染

验收：

- 文件 App 中选择 HTML 能进入 App
- 单文件 HTML 能显示
- ZIP 中 HTML + 图片能显示
- Markdown 标题和段落能显示

### M1：MVP 主链路

目标：完成可用产品主流程。

交付：

- 首页
- 最近打开
- 预览页
- 文件详情
- HTML 安全预览
- Markdown 阅读预览
- ZIP 导入
- 原始文本模式
- 错误页
- 设置页基础项

验收：

- 用户可以从 App 内打开文件
- 用户可以从外部 App 分享文件到本 App
- 文件导入后可再次从最近记录打开
- 安全模式默认开启
- ZIP 包 assets 不丢失

### M2：购买与发布准备

目标：完成商业化与 App Store 准备。

交付：

- 付费下载方案：完成产品页、截图、描述、隐私说明
- IAP 方案：完成 StoreKit 2、购买页、恢复购买、沙盒测试
- App Icon
- 启动图 / 空状态
- 隐私标签
- App Review 说明
- TestFlight 构建

验收：

- 无广告 SDK
- 无崩溃主流程
- 购买 / 恢复购买通过沙盒验证
- 隐私文案与实际行为一致

### M3：可用性测试与打磨

目标：通过用户测试发现入口、提示和预览问题。

交付：

- 可用性测试脚本
- 测试样本文件
- 观察记录模板
- 问题优先级列表
- 修复清单

验收：

- 用户能理解如何从微信 / 文件 App 打开
- 用户能理解安全预览和互动模式差异
- 用户遇到资源缺失时知道改用 zip 包
- 购买文案清楚表达“买断、无订阅、无广告”

---

## 16. QA 测试矩阵

### 16.1 设备矩阵

| 设备 | 系统 | 重点 |
|---|---|---|
| iPhone 小屏 | 最新稳定 iOS | 单手操作、布局 |
| iPhone Pro / Pro Max | 最新稳定 iOS | 主体验 |
| iPad | 最新稳定 iPadOS | 文件管理、分屏 |
| 较旧 iPhone | 最低支持系统 | 性能与兼容性 |

最低支持系统建议：iOS 17 或 iOS 18。若希望使用更新 SwiftUI / StoreKit / WebKit 能力，可提高到 iOS 18。若追求覆盖面，iOS 17 更稳妥。

### 16.2 来源 App 矩阵

| 来源 | 测试动作 |
|---|---|
| 文件 App | 打开 HTML / MD / ZIP |
| 微信 | 接收文件后“用其他应用打开” |
| 邮件 | 附件打开 |
| Safari 下载 | 下载后打开 |
| iCloud Drive | 云端文件下载后打开 |
| AirDrop | 接收文件后打开 |
| 网盘 App | 分享到本 App |

### 16.3 文件样本矩阵

| 样本 | 内容 |
|---|---|
| simple.html | 单文件，只有 HTML |
| styled.html | HTML + CSS |
| image.html | HTML + 本地图片 |
| script.html | HTML + JS |
| external.html | 引用远程图片 / CSS / JS |
| form.html | 表单提交 |
| large.html | 大文件 |
| readme.md | 标题、列表、代码块 |
| table.md | 表格 |
| image.md | 本地图片 |
| report.zip | index.html + assets |
| bad.zip | 损坏 zip |
| traversal.zip | 包含 `../` 路径的恶意 zip |
| no-entry.zip | 没有 HTML / MD 入口 |

---

## 17. 可用性测试计划

### 17.1 测试目标

本轮可用性测试主要验证：

1. 用户是否理解这个 App 是用来预览 HTML / MD 文件的。
2. 用户是否能从微信或文件 App 成功把文件交给本 App。
3. 用户是否能理解“安全预览”和“互动模式”的区别。
4. 用户遇到样式或图片缺失时，是否能理解“需要 zip 包”的提示。
5. 用户是否接受“无广告、买断制”的付费方式。
6. 首页、预览页、错误提示是否足够简单。

### 17.2 参与者

建议第一轮 5 人，第二轮 8-12 人。

招募结构：

| 类型 | 人数 | 条件 |
|---|---:|---|
| 普通 iPhone 用户 | 3-5 | 经常用微信 / 文件 App 收文件 |
| 学生 / 知识工作者 | 2-3 | 接触 Markdown / 网盘资料 |
| 开发者 / AI 工具用户 | 2-3 | 知道 HTML / MD，能提供进阶反馈 |
| iPad 用户 | 1-2 | 经常在 iPad 管理文件 |

筛选条件：

- 使用 iPhone 或 iPad 作为主设备之一
- 至少每周通过微信、邮件、网盘或文件 App 打开文档
- 不要求会写代码
- 允许录屏或观察操作过程

### 17.3 测试材料

准备以下文件：

```text
1-simple.html
2-report-with-assets.zip
3-readme.md
4-markdown-with-image.zip
5-interactive.html
6-external-resource.html
7-broken.zip
8-large.html
```

准备来源：

- 微信聊天窗口中的文件
- 文件 App 中的文件夹
- 邮件附件
- TestFlight 安装包
- 购买页沙盒环境

### 17.4 测试任务

任务 1：从微信打开 HTML

> 假设朋友在微信发给你一个 `report.html`，请尝试用这个 App 打开并查看内容。

观察点：

- 是否能找到“用其他应用打开 / 分享”
- 是否能识别本 App
- 打开后是否知道当前处于安全预览
- 是否理解页面内容

任务 2：从文件 App 打开 Markdown

> 请在文件 App 中找到 `readme.md`，用这个 App 查看排版后的内容。

观察点：

- 是否能从本 App 内找到“打开文件”
- 是否能选择文件
- Markdown 阅读视图是否易读
- 是否会寻找字号设置

任务 3：打开 HTML 报告包

> 这个 zip 包里有一个 HTML 报告和图片，请用 App 打开它。

观察点：

- 用户是否理解 zip 可以打开
- App 是否自动选择正确入口
- 图片和样式是否完整
- 用户是否能进入文件详情查看结构

任务 4：处理资源缺失

> 这个 HTML 页面看起来没有样式或图片。请尝试理解原因，并找到解决办法。

观察点：

- 提示是否清楚
- 用户是否理解“单个 HTML 文件可能缺少 assets”
- 用户是否知道应该导入 zip 包

任务 5：安全预览与互动模式

> 这个 HTML 需要交互。请尝试让它正常运行。

观察点：

- 用户是否注意到脚本被禁用
- 是否理解互动模式风险
- 是否能成功开启互动模式
- 风险文案是否过于吓人或不够明确

任务 6：购买理解

> 请查看购买页，告诉我们你理解这个付费方式吗？你认为它是订阅、广告移除，还是一次性购买？

观察点：

- 是否明确知道“无订阅”
- 是否明确知道“无广告”
- 是否理解免费版 / 买断版差异
- 价格接受度

### 17.5 关键指标

| 指标 | 目标 |
|---|---|
| 从文件 App 打开成功率 | ≥ 90% |
| 从微信打开成功率 | ≥ 70%，因微信入口受版本与系统影响 |
| Markdown 预览任务成功率 | ≥ 90% |
| ZIP 报告包任务成功率 | ≥ 80% |
| 安全模式理解率 | ≥ 80% |
| 资源缺失提示理解率 | ≥ 70% |
| 购买方式理解率 | ≥ 90% |
| 主观易用性评分 | 5 分制平均 ≥ 4 |

### 17.6 观察记录模板

```text
参与者编号：
设备：
系统版本：
是否常用微信收文件：
是否知道 HTML：
是否知道 Markdown：

任务 1 从微信打开 HTML：
- 是否完成：
- 卡点：
- 口头反馈：
- 观察备注：

任务 2 从文件 App 打开 MD：
- 是否完成：
- 卡点：
- 口头反馈：
- 观察备注：

任务 3 打开 zip 报告：
- 是否完成：
- 卡点：
- 口头反馈：
- 观察备注：

任务 4 资源缺失：
- 是否理解原因：
- 是否找到解决办法：
- 口头反馈：

任务 5 互动模式：
- 是否开启：
- 是否理解风险：
- 文案反馈：

任务 6 购买理解：
- 是否理解买断：
- 是否担心隐私：
- 价格接受度：

总体反馈：
最喜欢：
最困惑：
最希望增加：
是否愿意购买：
```

### 17.7 问题分级

| 级别 | 定义 | 示例 |
|---|---|---|
| P0 | 阻断核心任务 | 文件无法打开、预览崩溃 |
| P1 | 严重影响理解 | 用户不知道如何从微信打开 |
| P2 | 影响体验但可绕过 | 提示文案不清楚、按钮位置不明显 |
| P3 | 小优化 | 字距、图标、列表排序 |

### 17.8 测试后的决策规则

如果多数用户无法从微信中找到入口，首页和首次打开应增加“如何从微信打开”的图文提示，但不要做长 onboarding。

如果用户不理解安全预览，应把状态条文案改为更普通的话，例如“已保护预览：脚本不会运行”。

如果用户误以为买断是订阅，购买页必须把“一次性购买”放在标题或价格旁边。

如果用户打不开带图片 HTML，必须把 zip 导入作为首页主按钮之一，而不是藏在菜单里。

---

## 18. App Store 准备

### 18.1 产品页关键词方向

中文关键词：

```text
HTML预览, Markdown预览, MD查看器, 本地网页, 文件预览, 微信文件, 离线报告, HTML查看器
```

英文关键词：

```text
HTML viewer, Markdown viewer, MD viewer, local HTML, offline report, file preview
```

### 18.2 截图主题

建议截图 5 张：

1. “从微信 / 文件打开 HTML”
2. “本地安全预览 HTML”
3. “Markdown 自动排版”
4. “ZIP 报告包，图片样式不丢”
5. “无广告、无账号、一次性购买”

### 18.3 App Review 备注

提交审核时应说明：

- App 用于本地预览用户导入的 HTML、Markdown 和 ZIP 文档。
- App 不上传用户文件。
- HTML 默认以安全预览模式打开。
- 若包含 IAP，说明非消耗型买断项目的作用。
- 提供示例文件或说明审核人员可用“打开文件”导入内置示例。

---

## 19. 风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| 微信入口不可控 | 用户找不到 App | 首页提供图文说明；优化 Document Types；测试多个微信版本 |
| 单 HTML 资源缺失 | 页面显示不完整 | 强化 zip 包导入；显示资源缺失提示 |
| HTML 安全风险 | 用户隐私风险 | 默认安全预览；互动模式二次确认 |
| Markdown 渲染不完整 | 技术用户不满意 | MVP 支持常见元素，P1 增强 GFM |
| ZIP 恶意文件 | 安全与稳定风险 | path traversal 校验、大小限制、私有目录解压 |
| App 太“工具化”导致付费低 | 商业风险 | 产品页聚焦“微信/文件打不开”的真实痛点 |
| 过多第三方依赖影响信任 | 隐私风险 | 严格依赖审查；不引入广告/分析 SDK |
| App Store 审核认为功能太少 | 发布风险 | 内置示例、清晰截图、完整文件导入主链路 |

---

## 20. Definition of Done

MVP 完成标准：

1. App 能从文件 App 打开 `.html`、`.htm`、`.md`、`.markdown`、`.zip`。
2. App 能从至少微信、邮件、AirDrop 中通过分享 / 打开方式接收文件。
3. HTML 默认安全预览，脚本不运行。
4. ZIP 包中的 `index.html` 能读取同包内 CSS 与图片。
5. Markdown 能显示常见排版。
6. 文件导入后能在最近列表再次打开。
7. 错误状态有清楚的用户文案。
8. App 不集成广告 SDK、不要求账号。
9. 买断或付费方案完成并通过测试。
10. 通过一轮可用性测试，并修复所有 P0 / P1 问题。

---

## 21. 开放问题

1. 第一版采用“付费下载”还是“免费下载 + 一次性买断 IAP”？
2. 最低支持 iOS 版本定为 iOS 17 还是 iOS 18？
3. Markdown 渲染是优先完整性还是原生体验？
4. ZIP 文件大小限制最终设为多少？
5. 是否需要内置示例文件？
6. 是否在首页直接放“从微信打开教程”？
7. 是否支持 iPad 首发双栏布局，还是 P1？
8. 是否把 PDF 导出放进首发付费卖点？

建议优先决策：

- 商业方案
- 最低系统版本
- Markdown 渲染方案
- ZIP 是否作为首发核心卖点

---

## 22. 官方参考资料

- Apple Developer Documentation: `CFBundleDocumentTypes`  
  https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes

- Apple Developer Documentation: Uniform Type Identifiers  
  https://developer.apple.com/documentation/uniformtypeidentifiers

- Apple Developer Documentation: System-declared uniform type identifiers  
  https://developer.apple.com/documentation/uniformtypeidentifiers/system-declared-uniform-type-identifiers

- Apple Developer Documentation: `UTType.markdown`  
  https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/markdown

- Apple Developer Documentation: `WKWebView.loadFileURL(_:allowingReadAccessTo:)`  
  https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl%28_%3Aallowingreadaccessto%3A%29

- Apple Developer Documentation: `WKWebpagePreferences.allowsContentJavaScript`  
  https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript

- Apple Developer Documentation: UIDocumentPickerViewController  
  https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller

- Apple Developer Documentation: `startAccessingSecurityScopedResource()`  
  https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource%28%29

- Apple Developer Documentation: Building a document-based app with SwiftUI  
  https://developer.apple.com/documentation/swiftui/building-a-document-based-app-with-swiftui

- Apple Developer Documentation: StoreKit In-App Purchase  
  https://developer.apple.com/documentation/storekit/getting-started-with-in-app-purchases-using-storekit-views

- App Store Connect Help: Create consumable or non-consumable In-App Purchases  
  https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/

- Apple App Review Guidelines  
  https://developer.apple.com/app-store/review/guidelines/

- Swift Markdown package  
  https://github.com/swiftlang/swift-markdown


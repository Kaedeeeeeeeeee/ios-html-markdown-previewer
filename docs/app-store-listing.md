# App Store Listing Draft

## Commercial Model

- MVP is a paid download app.
- No in-app purchases.
- No subscriptions.
- No ads.
- No account system.

## Localized Store Listings

Use these locales in App Store Connect for the first localized release:

- `en-US`
- `zh-Hans`
- `ja`

## App Information URLs

Privacy Policy URL: https://gist.github.com/Kaedeeeeeeeeee/b3baa9048f37467e51bd9b3513787c42

Support URL: https://gist.github.com/Kaedeeeeeeeeee/394a005738e00a0f72bf9bd3a5abd59c

## en-US

Name: HTML Previewer

Subtitle: Local HTML and Markdown viewer

Promotional Text:

Open local HTML, Markdown, and ZIP report packages on iPhone and iPad. Files stay on device, with safe HTML preview enabled by default.

Description:

HTML Previewer is a focused local file viewer for HTML, Markdown, and ZIP report packages.

Use it when you receive an `.html`, `.htm`, `.md`, `.markdown`, or `.zip` file from Files, Mail, AirDrop, messaging apps, cloud drives, or other apps and want to read it on iPhone or iPad.

Features:
- Local HTML preview with safe mode enabled by default
- Rich HTML rendering for responsive layouts, inline graphics, and CSS animation
- Markdown reading view for common Markdown documents
- ZIP report package import for HTML files with local CSS and image assets
- Recent files list
- Raw text fallback
- File details
- Built-in HTML, Markdown, and ZIP samples

Privacy and business model:
- Files are processed on device
- No file uploads
- No account
- No ads
- No subscription
- Paid download, no in-app purchase

Safe HTML preview disables page JavaScript and blocks external network resources by default. Interactive mode is available for trusted files.

Keywords:

HTML viewer, Markdown viewer, local HTML, offline report, file preview, ZIP report, MD viewer

## zh-Hans

Name: HTML 预览器

Subtitle: 本地 HTML 与 Markdown 查看器

Promotional Text:

在 iPhone 和 iPad 上打开本地 HTML、Markdown 和 ZIP 报告包。文件保留在设备上，默认启用安全 HTML 预览。

Description:

HTML 预览器是一款专注于本地文件阅读的工具，支持 HTML、Markdown 和 ZIP 报告包。

当你从“文件”、邮件、隔空投送、消息应用、网盘或其他 App 收到 `.html`、`.htm`、`.md`、`.markdown` 或 `.zip` 文件时，可以直接在 iPhone 或 iPad 上查看。

功能：
- 默认启用安全模式的本地 HTML 预览
- 支持响应式布局、内嵌图形与 CSS 动画的丰富 HTML 渲染
- 常见 Markdown 文档阅读视图
- 导入 ZIP 报告包并加载本地 CSS 与图片资源
- 最近文件列表
- 原始文本备用查看
- 文件详情
- 内置 HTML、Markdown、ZIP 示例

隐私与商业模式：
- 文件在设备本地处理
- 不上传文件
- 无账号
- 无广告
- 无订阅
- 付费下载，无 App 内购买

安全 HTML 预览默认禁用页面 JavaScript，并阻止外部网络资源。可信文件可以使用交互模式。

Keywords:

HTML查看器,Markdown查看器,本地HTML,离线报告,文件预览,ZIP报告,MD查看器

## ja

Name: HTMLプレビュー

Subtitle: ローカルHTML/Markdownビューア

Promotional Text:

iPhoneとiPadでローカルのHTML、Markdown、ZIPレポートを開けます。ファイルは端末内に保存され、安全なHTMLプレビューが標準で有効です。

Description:

HTMLプレビューは、HTML、Markdown、ZIPレポートパッケージを端末内で閲覧するためのシンプルなファイルビューアです。

「ファイル」、メール、AirDrop、メッセージアプリ、クラウドドライブ、その他のアプリから `.html`、`.htm`、`.md`、`.markdown`、`.zip` ファイルを受け取ったときに、iPhoneやiPadでそのまま確認できます。

主な機能:
- 安全モードが標準で有効なローカルHTMLプレビュー
- レスポンシブ表示、埋め込みグラフィック、CSSアニメーションを含むリッチなHTML表示
- 一般的なMarkdown文書の閲覧ビュー
- ローカルCSSや画像を含むZIPレポートパッケージの取り込み
- 最近使ったファイル一覧
- テキスト表示へのフォールバック
- ファイル詳細
- HTML、Markdown、ZIPの内蔵サンプル

プライバシーと購入方式:
- ファイルは端末内で処理
- ファイルのアップロードなし
- アカウント不要
- 広告なし
- サブスクリプションなし
- 有料ダウンロード、App内課金なし

安全なHTMLプレビューでは、ページのJavaScriptと外部ネットワークリソースを標準でブロックします。信頼できるファイルではインタラクティブモードを使用できます。

Keywords:

HTMLビューア,Markdownビューア,ローカルHTML,オフラインレポート,ファイルプレビュー,ZIPレポート,MDビューア

## Review Notes

This is a paid download app with no StoreKit or in-app purchases.

The app previews user-selected local files only. It does not require an account and does not upload user files.

For review, launch the app and use the built-in Samples section:

1. Open HTML Sample to test local HTML safe preview.
2. Open Markdown Sample to test native Markdown rendering.
3. Open ZIP Report Sample to test ZIP import and local asset loading.

External file opening is supported through iOS document type registration for HTML, Markdown, and ZIP files. The exact appearance in third-party app share/open menus depends on iOS and the source app.

## Privacy Labels Draft

Data collected: None.

Tracking: No.

Linked to user: No.

Used for tracking: No.

Files selected by the user are copied into the app sandbox for local preview and are not transmitted off device.

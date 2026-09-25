# App Store Listing — Next Release Draft

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

Open HTML, Markdown, and ZIP reports on iPhone and iPad. New HTML files open in Interactive mode with scripts and external resources enabled. Safe Preview is available.

Description:

HTML Previewer is a focused local file viewer for HTML, Markdown, and ZIP report packages.

Use it when you receive an .html, .htm, .md, .markdown, or .zip file from Files, Mail, AirDrop, messaging apps, cloud drives, or other apps and want to read it on iPhone or iPad.

Features:
- Local HTML preview with Interactive mode as the default for newly imported HTML
- Rich HTML rendering for responsive layouts, inline graphics, and CSS animation
- Markdown reading view with tables and horizontal scrolling for wide tables
- Import and share complete ZIP report packages with local CSS and image assets
- Export HTML and Markdown previews as PDF
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

New HTML files, including HTML inside ZIP packages, open in Interactive mode with page JavaScript and external resources enabled. Select Safe Preview to block page scripts and external network resources. External navigation and form navigation remain blocked in both modes. Saved preview choices are preserved when reopening files.

Keywords:

HTML viewer, Markdown viewer, local HTML, offline report, file preview, ZIP report, MD viewer

## zh-Hans

Name: HTML 预览器

Subtitle: 本地 HTML 与 Markdown 查看器

Promotional Text:

在 iPhone 和 iPad 上打开 HTML、Markdown 和 ZIP 报告。新导入的 HTML 默认使用交互模式，支持页面脚本和外部资源，也可切换到安全预览。

Description:

HTML 预览器是一款专注于本地文件阅读的工具，支持 HTML、Markdown 和 ZIP 报告包。

当你从“文件”、邮件、隔空投送、消息应用、网盘或其他 App 收到 .html、.htm、.md、.markdown 或 .zip 文件时，可以直接在 iPhone 或 iPad 上查看。

功能：
- 新导入的 HTML 默认使用交互模式进行本地预览
- 支持响应式布局、内嵌图形与 CSS 动画的丰富 HTML 渲染
- 支持表格的 Markdown 阅读视图，宽表格可横向滚动
- 导入和分享包含本地 CSS 与图片资源的完整 ZIP 报告包
- 将 HTML 和 Markdown 预览导出为 PDF
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

新导入的 HTML（包括 ZIP 中的 HTML）默认使用交互模式，允许页面 JavaScript 和外部资源。可切换到安全预览，阻止页面脚本和外部网络资源。两种模式都会继续阻止外部跳转和表单跳转。再次打开文件时，会保留已保存的预览模式。

Keywords:

HTML查看器,Markdown查看器,本地HTML,离线报告,文件预览,ZIP报告,MD查看器

## ja

Name: HTMLプレビュー

Subtitle: ローカルHTML/Markdownビューア

Promotional Text:

iPhoneとiPadでHTML、Markdown、ZIPレポートを開けます。新しく取り込むHTMLは、スクリプトと外部リソースに対応するインタラクティブモードで開きます。安全プレビューにも切り替えられます。

Description:

HTMLプレビューは、HTML、Markdown、ZIPレポートパッケージを端末内で閲覧するためのシンプルなファイルビューアです。

「ファイル」、メール、AirDrop、メッセージアプリ、クラウドドライブ、その他のアプリから .html、.htm、.md、.markdown、.zip ファイルを受け取ったときに、iPhoneやiPadでそのまま確認できます。

主な機能:
- 新しく取り込むHTMLを標準でインタラクティブモードで表示
- レスポンシブ表示、埋め込みグラフィック、CSSアニメーションを含むリッチなHTML表示
- 表に対応したMarkdown閲覧ビュー。横に長い表はスクロール可能
- ローカルCSSや画像を含むZIPレポートパッケージの取り込みと共有
- HTMLとMarkdownのプレビューをPDFとして書き出し
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

新しく取り込むHTML（ZIP内のHTMLを含む）は、ページのJavaScriptと外部リソースを許可するインタラクティブモードで開きます。安全プレビューに切り替えると、ページのスクリプトと外部ネットワークリソースをブロックできます。どちらのモードでも、外部ページへの移動とフォーム送信による移動はブロックします。再度開くときは、保存済みのプレビューモードを維持します。

Keywords:

HTMLビューア,Markdownビューア,ローカルHTML,オフラインレポート,ファイルプレビュー,ZIPレポート,MDビューア

## Review Notes

This is a paid download app with no StoreKit or in-app purchases.

The app previews user-selected local files only. It does not require an account and does not upload user files.

For review, launch the app and use the built-in Samples section:

1. Open Weekend plan (HTML) to test local HTML in the default Interactive mode. Switch to Safe Preview to test rendering with page scripts and external resources blocked.
2. Open Reading notes (Markdown) to test native Markdown rendering.
3. Open Reading week (ZIP) to test ZIP import and local asset loading.

External file opening is supported through iOS document type registration for HTML, Markdown, and ZIP files. The exact appearance in third-party app share/open menus depends on iOS and the source app.

## Privacy Labels Draft

Data collected: None.

Tracking: No.

Linked to user: No.

Used for tracking: No.

Files selected by the user are copied into the app sandbox for local preview. The app does not upload user files; HTML page content can make network requests in Interactive mode.

# 1.7 商店定位与截图文案草案

日期：2026-10-02。用于本地准备，未上传 App Store Connect，未修改审核中的 1.6。JSON、批量导入的文案必须在 1.7 实际交付并验证后使用；下表不是已上线功能清单。

## 定位

**在 iPhone 和 iPad 上，打开收到的报告、阅读笔记、查看配置。**

保留 HTML Previewer 的产品名，在副标题和前 3 张截图讲清用途。以真实文件和 UI 展示 HTML/ZIP 报告、Markdown 笔记、JSON/YAML 结构；不承诺编辑器、格式转换器、云同步或 AI 分析。

## 副标题候选

字符数含空格和标点，均不超过 Apple 的 30 字符限制。这里给每种语言一个主候选，避免同时改变多个定位。

| 语言 | 副标题 | 字符数 |
| --- | --- | --- |
| en-US | Reports, Notes & JSON | 21 |
| zh-Hans | 阅读报告、笔记与 JSON 配置 | 16 |
| ja | レポート・ノート・JSONを読む | 16 |

英文与日文把“读什么”放在副标题，中文补充 JSON 的配置用途；HTML、Markdown、YAML、ZIP 等格式在首屏与描述里完整说明，避免在短标题中堆满格式名称。[Apple product page guidance](https://developer.apple.com/app-store/product-page/)

## 五张截图：实际界面 + 明确收益

每张只讲一个主要收益。首 3 张依次展示整体用途、减少重复导入、JSON 新能力；每种语言用对应本地化 UI 截图。已保存 [JSON 与真实系统多选的本地截图](../updates/2026-10-02-json-batch.md#实际界面)，正式商店尺寸的三语排版仍需在发布构建确定后导出。

| 顺序与画面 | 中文主标题 / 辅助文案 | English headline / Supporting copy | 日本語見出し / 補足 |
| --- | --- | --- | --- |
| 1. HTML 报告预览：清晰的图表、正文与阅读工具；使用不含外部依赖的合成周报 | 收到报告，随手打开 / 在 iPhone 和 iPad 上阅读 HTML 与 ZIP 报告 | Open reports on the go / Read HTML and ZIP reports on iPhone and iPad | 届いたレポートをすぐ読む / iPhoneとiPadでHTML・ZIPレポートを閲覧 |
| 2. 多选后导入结果：展示导入、跳过、失败的数量，以及失败文件与原因；使用不同格式样例 | 一次选好，一起导入 / 批量添加文件，查看导入数量与失败原因 | Import a group at once / See import counts and any failed files | 複数ファイルをまとめて取り込む / 取り込み件数と失敗した理由を確認 |
| 3. JSON 结构预览：展开对象和数组，明确结构/源码切换；避免真实 token 或配置秘密 | JSON 结构，一眼看清 / 展开对象与数组，按需查看源码 | Make sense of JSON / Explore objects and arrays, then view the source | JSONの構造を見やすく / オブジェクトや配列を展開し、ソースも確認 |
| 4. Markdown 笔记：标题、代码块与一小段公式或流程图，保留足够字号 | 笔记里的重点，看得清 / 阅读 Markdown 表格、代码与公式 | Give your notes room to read / Read Markdown tables, code, and equations | ノートの内容を読みやすく / Markdownの表・コード・数式を表示 |
| 5. 最近文件库：使用合成报告、笔记、JSON/YAML 文件名，展示搜索与置顶；画面体现重开文件 | 常用文件，下次接着看 / 搜索文件名、置顶资料，再次打开继续阅读 | Keep useful files close / Find files by name, pin favorites, and read again | よく使うファイルを手元に / 名前で検索して固定。次回もすぐに開ける |

第 5 张“搜索”指文件名搜索，不暗示尚未实现的跨文件全文搜索。“继续阅读”指支持的文件阅读位置行为；若 JSON 的位置恢复未验证，应让截图中的继续阅读示例使用已验证的 HTML/Markdown。批量导入的部分成功和重复文件决策应先在产品内验证，不只拍理想路径。

## 配套短介绍草案

**zh-Hans**

在 iPhone 和 iPad 上阅读收到的报告、笔记和配置文件。支持 HTML、Markdown、YAML、JSON 与 ZIP 报告包；一次导入多份文件，展开 JSON 结构，并在需要时查看源码。文件在设备本地处理。

**en-US**

Read reports, notes, and configuration files on iPhone and iPad. Open HTML, Markdown, YAML, JSON, and ZIP report packages. Import multiple files, explore JSON structure, and switch to source when needed. Files are processed on your device.

**ja**

iPhoneとiPadで、届いたレポートやノート、設定ファイルを閲覧。HTML、Markdown、YAML、JSON、ZIPレポートに対応。複数ファイルをまとめて取り込み、JSONの構造やソースを確認できます。ファイルは端末内で処理します。

这些是描述开头候选，不是已校验长度的 Promotional Text 字段。若要放入该字段，需要按其限制另行压缩。

## 表达边界与素材准备

- 使用实际 UI 截图，不把未实现的设计稿拼成产品能力。测试样例可以虚构，但不能呈现为用户真实报告或使用结果。
- JSON 解析、结构展开、源码切换与批量导入在 1.7 验证后才导出最终素材；不把“开发完成”写成“已公开发布”。
- 文件在本地处理不等于所有 HTML 永远离线：Interactive 模式允许文件自己的 JavaScript 与外部资源请求。不要写“绝不联网”；保留 Safe Preview 与网络行为的现有准确说明。
- 若之后引入可选使用统计，商店、隐私政策与设置一起更新；仍可按实际行为说“不上传文件”，但不可同时笼统说“不收集任何数据”。
- 先按仓库已有截图尺寸与交付流程制作一套 iPhone 素材，再按实际支持与商店要求补齐 iPad，避免没有验证的设备外壳。
- 从第 1 张中选择清楚的浅色展示，并在后续至少一张验证深色模式可读性。Apple 建议使用 App UI 截图、前几张突出核心能力，后续一张一个主要收益。[Apple screenshot guidance](https://developer.apple.com/app-store/product-page/)

## 验收与发布前核对

1. 三种语言副标题长度通过，文字与 UI 语言一致，没有截断、拥挤或难读的小字。
2. 每张图对应可以在目标构建中重复完成的流程；确认 JSON 只读预览、导入结果、搜索范围和隐私表达准确。
3. 所有样例均为自制且没有真实客户、个人信息、token、私人路径或公司配置。
4. 将最终素材与对应构建号保存，更新 next-release 本地资料后再进入该版本的正常上架流程。
5. 1.6 审核保持现状。本次不向 App Store Connect 写入这些草案，不替换正在审核的截图或副标题。

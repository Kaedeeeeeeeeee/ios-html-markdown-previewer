# 1.7 使用情况测量方案（待决定，未接入）

日期：2026-10-02。本文是可审阅设计，不表示已经启用数据收集。本次不增加 SDK、网络请求、事件代码或服务账号，不修改正在审核的 1.6。

## 建议

值得测量。先看 App Store Connect 已有数据，了解是否有人持续使用，再用少量可选统计回答“使用什么功能”。第一版不需要用户画像、广告归因、会话录像、点击热图或逐步操作轨迹。

推荐顺序：

1. 只读查看 Apple Analytics 最近 28 天，保存版本、时间区间、样本限制和指标定义；本次仅核实官方能力，未读取该 App 的实际报表。
2. 先交付 JSON 和批量导入。要增加自建统计时，再确定接收服务、保留期、隐私声明和用户同意界面。
3. 第一版自建统计默认关闭，用户主动开启后才开始本地计数和上传；关闭立即停止计数，删除本地待发数据。该选择是本产品建议，不是声称 Apple 要求所有分析都必须如此。

## 先用 Apple 已提供的数据

| 问题 | 可用指标 | 解读限制 |
| --- | --- | --- |
| 有多少人发现、下载 App？ | Impressions、Product Page Views、First Time Downloads、Conversion Rate | 商店曝光转化不等于完成首次文件预览；按 Apple 指标口径解读 |
| 是否持续使用？ | Active Devices、Sessions、Retention | 设备数不是人数；Apple session 指使用至少 2 秒，回前台可另计一次 |
| 新版本是否更稳定？ | Crashes、版本/系统筛选，Xcode 崩溃报告 | 不直接解释失败的导入、解析错误或按钮是否被使用 |
| iPhone/iPad 与版本差异？ | Device、App Version 等维度 | 小样本避免细分；版本前后差异不能单独证明功能带来提升 |

Apple 的 Usage 只包含同意向开发者共享诊断和使用情况的用户；可查看 opt-in rate 历史。官方指标页当前说明，所选日期范围至少有 5 台活跃设备才显示 Usage。空白不应解释为无人使用。下载、付费与 Usage 的样本口径不同，不用全量下载数直接计算自建统计转化率。[Apple App usage](https://developer.apple.com/help/app-store-connect-analytics/engagement/app-usage)、[Metric definitions](https://developer.apple.com/help/app-store-connect-analytics/reference/metrics-definitions)。

根据 Apple 公布的内建指标范围，无法从这些报表直接读出“JSON 与 Markdown 各被打开几次”“有多少次批量导入”“用户是否用过字段复制”。App Store 的 In-App Events 指商店活动，并非任意自定义按钮事件。上述问题需要另行设计应用内统计。[Apple Analytics overview](https://developer.apple.com/app-store-connect/analytics/)

## 当前代码与隐私承诺

以下均为本地仓库事实，未在本次登录 App Store Connect 核对已提交的标签：

- `docs/privacy-policy.md` 明确不收集个人数据、不使用 analytics SDK，文件在设备本地处理、不上传文件。
- `HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy` 的 `NSPrivacyCollectedDataTypes` 为空，tracking 为 false。
- `docs/privacy-required-reasons.md` 声明偏好和文件元数据不离开设备。
- `scripts/release-audit.sh`、`scripts/portable-release-materials-audit.sh` 和上架文档按“Data Not Collected”校验。
- `SettingsView` 目前展示本地处理、无账号、无广告，没有统计同意开关。

因此新增上传不是插入几个日志调用即可：隐私政策、商店标签、manifest（按最终实现）、设置文案、依赖及发布审计必须一起复核。不能继续宣称“不收集数据”，同时悄悄上传功能事件。

## 最小统计：只回答四类问题

不保存逐条行为流水。用户同意后，在设备上按白名单维度累计计数，再发送汇总。下面的事件名是统计定义，不是已存在的实现。

| 计数项 | 触发时机与允许维度 | 可以回答的问题 |
| --- | --- | --- |
| `import_result` | 每个文件处理完成一次；`format`、`source`、`result`、`error_category` | 哪种格式和入口导入最多？哪些格式经常失败？ |
| `batch_result` | 一次文件选择及冲突处理结束；`size_bucket`、`result` | 批量导入是否被用到，是否经常部分失败或取消？ |
| `preview_result` | 一次打开请求最终可见或失败；`format`、`content_origin`、`result`、`error_category` | 实际打开哪些格式？JSON 解析是否可靠？ |
| `feature_used` | 明确用户操作成功一次；`feature`、适用时的 `format`、`content_origin` | 搜索、复制、源码切换、PDF 等哪些能力被使用？ |

首版白名单：

| 字段 | 值与边界 |
| --- | --- |
| `schema_version` | 固定整数，如 `1` |
| `app_version` | 发布版本号，如 `1.7`；不包含内部用户名或构建路径 |
| `week_start` | UTC 周起始日期；不发送事件发生的精确时间、设备时区 |
| `format` | `html` / `markdown` / `yaml` / `json` / `zip` / `text` / `unsupported` / `unknown` |
| `source` | `file_picker` / `open_url` / `paste` / `built_in_sample`；无法可靠识别时 `unknown`。`open_url` 不细分 Mail、微信或 AirDrop |
| `content_origin` | `user_document` / `built_in_sample`；样例与真实导入分开看 |
| `result` | `success` / `failure` / `cancelled` / `skipped`；批量另允许 `partial`。取消和跳过不算技术失败 |
| `error_category` | `none` / `unsupported_format` / `unreadable_file` / `size_limit` / `archive_invalid` / `parse_invalid` / `storage_failure` / `unknown` |
| `size_bucket` | `1` / `2_5` / `6_20` / `21_plus`；表示本次选择的文件数，非文件字节数 |
| `feature` | `document_search` / `structure_search` / `structure_source` / `copy_field` / `pdf_export` / `zip_page_switch` / `full_screen` |
| `count` | 非负整数，设备内累计；服务器校验上限，拒绝非法维度/负数/未知字段 |
| `batch_id` | 每次发送独立生成的随机去重值；不跨批次复用，服务端最多保留 7 天，不用于分群 |

导入取消仅记录调用链明确报告的用户取消；进程退出不能猜成取消。预览结果必须在渲染/解析真正完成后记录，不在 SwiftUI `body` 重算或重复 `onAppear` 时增加。一次打开请求在内存中去重；文件 ID 仅用于本地逻辑，绝不出现在上传数据中。搜索只记“提交了非空搜索”一次，不按键计数、不采集词语；复制和导出只记录操作类别，绝不记录内容或目的 App。

示意汇总包（格式不是生产 API）：

```json
{
  "schema_version": 1,
  "app_version": "1.7",
  "week_start": "2026-10-05",
  "batch_id": "random-value-used-only-for-this-send",
  "counters": [
    {"event": "import_result", "format": "json", "source": "file_picker", "result": "success", "error_category": "none", "count": 3},
    {"event": "feature_used", "format": "json", "content_origin": "user_document", "feature": "structure_source", "count": 2}
  ]
}
```

**禁止收集**：文件名、原始或显示路径、文件 URL、文档正文、JSON/YAML 键或值、复制内容、搜索词、剪贴板、截图、文件哈希、书签、原始错误字符串/堆栈、账户、IDFA、IDFV、持久安装 ID、来源应用标识。原始错误经白名单映射，未知错误只能是 `unknown`。首次不加设备型号、系统小版本、语言、地区等细分字段，以减少稀有组合；这些宏观问题先用 Apple 报表。

## 报表口径与产品决策

每周看一次，不做实时用户追踪：

- **格式使用占比**：该格式成功预览次数 / 所有真实文档成功预览次数。用于比较阅读场景，不能称为“用户占比”；反复打开同一文件仍会多次计数。
- **导入失败率**：failure / (success + failure)，按格式和入口看；取消/跳过另列。先修复高失败入口，再扩展格式。
- **批量使用情况**：大小区间分布、success/partial/failure/cancelled 次数；每文件计数与每批次计数分别展示，不能相加作为总导入次数。
- **功能使用频次**：同版本的搜索、复制、源码、PDF 等次数。结合可使用该功能的格式预览次数参考，不能解释为独立用户采用率。
- **质量回归**：自建导入/预览失败趋势与 Apple 崩溃/留存趋势分别展示，注明两个同意样本不同，不逐用户关联。

这套最小方案不能还原某人的操作顺序、跨天留存、独立用户数或“为什么没用”。早期宁可接受此限制，再用自愿反馈补充原因。小样本保留绝对次数与时间范围，不用一次波动决定产品方向，不把 opt-in 样本外推为全部用户。分析中的“小样本隐藏”不是已经实现的匿名化保证。

## 同意与关闭体验

推荐设置项：**“帮助改进 HTML 预览器”**，默认关闭，不在首次打开文件前强制弹窗。

说明草案：

> 开启后，会发送功能使用次数、文件格式和导入结果等汇总统计，帮助我们决定改进方向。不会发送文件名、文件内容或搜索词。你可随时关闭；关闭后会删除本机尚未发送的统计。已发送数据按隐私政策中的保留期处理。

正式说明还需写明运营者、接收服务、保留时间和链接，不能用“完全匿名”替代这些信息。未同意时连待发统计也不建立，不补发同意之前的行为。Apple 系统诊断共享同意不等同于本 App 自建上传的同意。

关闭应取消尚未发送的任务、清空本地队列并重检发送前同意状态；已到达服务器的数据不能假装撤回。无持久标识意味着通常无法找到某位用户的已上传汇总，需在政策中如实说明，依靠短保留期处理，而不是承诺逐用户远程删除。

## 数据生命周期与接收服务：提案，尚未选定

- 本地只保留待发汇总，最多 7 天；默认仅前台、网络可用时最多每天发送一次，失败退避，不影响预览。过期数据删除，不无限重试。具体实现仍需验证。
- 推荐接收后校验并合并到周级总计，原始请求体不写应用日志；去重值最长 7 天，分析总计候选保留 90 天。备份与 CDN/WAF/负载均衡日志需要同样检查，不能只清应用数据库。
- 网络基础设施会处理 IP 地址，也可能保留请求时间、User-Agent 和安全日志。即使没有账号、设备 ID，单次汇总及这些网络信息仍有残余识别风险。应选择能控制日志、用途、访问权限和保留期的服务；不从 IP 推导地区，不拼接其他产品数据。
- 本次不选具体供应商，也不假设托管 SDK 默认配置符合本方案。首选先评估“薄接收端 + 聚合表”能否满足维护成本；如采用第三方产品，逐项审查自动采集、设备标识、二次用途、子处理商、地区与删除机制。

## Apple 披露边界

Apple 将应用交互归入 Usage Data → Product Interaction，技术错误可能涉及 Diagnostics → Other Diagnostic Data；若以后采集崩溃日志或性能指标，还需分别检查 Crash Data、Performance Data。用途可能是 Analytics，按实际用途选择，不只按事件名字判断。[Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

同一官方说明明确：设备端处理且不发送的资料不算其标签定义中的收集；从设备发送并保留的数据需另行判断；首次同意后持续收集仍需披露。无账号、可选上传、聚合统计都不能自动得出“Data Not Collected”或“Data Not Linked to You”。数据是否关联用户要连同服务商与网络日志一起核实。

Apple 的 tracking 特指将个人/设备数据与第三方数据关联用于定向广告、广告衡量，或分享给数据经纪商。产品分析不应与 tracking 混为一谈，也不能因此免除 App Privacy 披露。ATT 是否适用取决于最终的数据用途与服务商行为，不能只因为装了“分析 SDK”就断言需要或不需要。

Apple 同时说明：无需替 Apple 自身收集的数据负责披露；如果开发者通过 Apple 框架或服务收集 App 数据，则应据实际收集与用途判断。不能把“用了 Apple Analytics”笼统解释为任意数据处理都免披露。

## 落地前要决定与验证的事项

1. 产品负责人决定是否从下一版本引入自建统计；本提案推荐先做 Apple 基线，再决定时间。
2. 选定接收服务及区域，确认日志、子处理商、保留/备份/删除和访问权限；确定最终政策文案与 App Privacy 回答。
3. 再实现白名单计数、可选同意、队列清理和发送控制；同步更新隐私政策、manifest、商店资料及发布审计。保留禁止广告/账号 SDK 的已有保护，不能简单删除全部隐私校验。
4. 验证未同意零统计请求、关闭清空待发、离线过期删除、重试去重、取消不计失败、重复渲染不重复计数；用含敏感文件名/路径/搜索词的样例抓包确认只出白名单字段。

官方来源于 2026-10-02 使用 Ego Lite 查阅；未创建服务账号、未改动审核状态或线上隐私标签。

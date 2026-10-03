# 1.7.1（13）发布候选

本次更新合并了阅读后的系统评分请求，以及新一轮商店文案和截图。
候选代码在 `codex/next-release-1.7.1`，原工作目录中的并行任务成果已保留。
当前阶段完成本地准备，等待 1.7（12）过审后再上传和提审。

## 更新内容

- 读完至少 5 次、覆盖 3 个本地日期，每次有效前台阅读至少 30 秒，返回文件库并空闲 2 秒后请求系统评分。内置样例不计入；搜索、导入、分享等操作会推迟请求。
- 每个版本最多尝试一次；再次请求需要间隔 120 天并积累新的阅读记录。计数只存在本机，StoreKit 决定是否显示弹窗。
- 英文、简体中文、日文、繁体中文商店文案、更新说明，以及 48 张 iPhone/iPad 截图接入正式上传路径。
- 截图顺序统一为 HTML → Markdown → JSON → YAML → 批量导入 → 文件库。CI 和上传前均检查实际文件与 ASO 准备包的哈希、数量、尺寸和顺序。
- 上传流程在任何构建上传和商店修改前，先确认上一版 1.7 已获审核批准。手动触发仍默认不自动提审。

## 验证记录

| 检查 | 结果与范围 |
| --- | --- |
| 单元和集成测试 | 206 项通过，其中评分策略测试 10 项 |
| 完整 UI 回归 | 36 项全部通过，零失败；本轮共 242 项测试通过 |
| iOS 26.5 UI 补充验证 | 首轮 CI 的搜索输入、长按重命名两项失败；同版模拟器原样复现与加强测试同步后的两轮定向测试各 2 项通过。功能代码未改；以最新 CI 为最终结果 |
| 本地商店物料 | 四语言、48 张图片通过，尺寸分别为 1320×2868 / 2064×2752，RGB 无透明通道；逐文件与准备包一致 |
| 发布审计 | Release audit、portable audit、公开支持与隐私页面检查通过 |
| 上传前审核状态检查 | 12 个批准、未批准、缺失版本、只读检查案例通过 |
| 正式分发包 | Release archive 与本地 App Store IPA 导出通过，Apple Distribution 签名、`get-task-allow=false`，无开发设备列表 |
| GitHub CI | 以候选 PR 最新提交的检查结果为准；5 个必需检查全部通过后再合并和上传 |
| 真机评分验证 | iPhone 17 / iOS 27.0 的独立开发签名 QA app 已实际显示系统弹窗；短阅读、后台时间、重复请求与重启检查通过 |

本轮回归复用了现有模拟器 `HTML Previewer 1.6 Geometry iOS18.5`
（iPhone 16 / iOS 18.5），UDID `D17454A3-3351-48DD-A61F-395E5E7EE3FF`。
采用一个明确 destination，关闭并行测试；没有创建、删除或抹除模拟器。
CI 失败排查另复用了 `HTML Previewer Release iPhone iOS26.5`（iPhone 17），
UDID `2CFB4656-369B-4D63-B713-1DAC57B0C1A2`，两个模拟器顺序使用。
完成测试后已关闭本任务启动的模拟器。

Xcode 在用例结束后等待附加的 `simctl diagnose` 日志采集。仅停止该采集子进程后，
`xcodebuild` 正常以 0 退出，完整 `.xcresult` 可读取并确认 242 项通过、零失败、零跳过。
附加模拟器诊断日志不完整；测试结果与附件保留。

真机验证使用 `com.kaede.htmlmarkdownpreviewer.reviewqa`，生产 app 及其文档未修改。
临时种子数据位于独立 QA 源码副本，未进入发布代码。
该结果证明开发真机能显示系统评分界面；最终分发版本的安装和核心功能检查仍在上传后完成。
TestFlight 中不会显示评分请求，因此最终安装检查不要求出现评分弹窗。

## 归档与物料来源

- 构建源码提交：`e3910abfbe2548475f5fdacd40e69569fc98cd16`，归档时工作树干净。
- Bundle ID：`com.kaede.htmlmarkdownpreviewer`；版本 `1.7.1`，build `13`；最低 iOS 17.0，SDK `iphoneos27.0`。
- Team：`Y4FV6WUU4V`；分发 profile：`HTML Markdown Previewer App Store`，有效至 2027-05-17。
- IPA SHA-256：`65b86549d79f1d985a59f93f8258ad892cb2c85000a2c4b5ec67a33d3ffbd0d7`。
- 本地归档和 IPA：`DerivedData/Release1.7.1/HTMLPreviewer.xcarchive` 与 `DerivedData/Release1.7.1/Export/HTMLMarkdownPreviewer.ipa`。

ASO 原始截图来自 1.7（12）标记的 Debug 模拟器包，已包含并行评分开发代码。
本次集成未改变截图中的可见界面、渲染器或样例内容；只增加后台阅读计数、系统请求接入和版本号。
物料检查证明文件身份和上传顺序，不把这些截图当作最终 Release 包截图。
若候选代码后续改变截图对应界面，必须重新截图并更新校验记录。

关联记录：

- [评分策略、真机截图与记录](updates/2026-10-03-review-prompts.md)
- [iOS 26.5 排查与验证](updates/assets/2026-10-03-review-prompts/ios26-ui-validation.json)
- [完整回归记录](updates/assets/2026-10-03-review-prompts/full-regression.json)
- [归档与 IPA 校验](updates/assets/2026-10-03-review-prompts/archive-validation.json)
- [商店文件集成校验](app-store-screenshots/verification-1.7.1.json)
- [ASO 准备包及预览](aso/2026-10-03/materials/README.md)
- [审核备注草稿](updates/1.7.1-review-notes.txt)
- [正式商店文案](app-store-listing.md)

## 上传前后待办

2026-10-03 07:28 UTC 的只读查询确认，1.7（12）仍为 `WAITING_FOR_REVIEW`，build 为 `VALID`。
版本 ID：`dfcf66d4-a654-439a-b00a-b3d5749b8716`；build ID：`ec4e757e-727d-428b-93ef-8eb3b5313556`。
本次未对该版本或其审核执行任何修改。

1. 等待 1.7 获审核批准；若被拒，先处理该版本的审核问题，再决定后续候选包。
2. 候选 PR 的 CI 通过后合并，锁定最终提交；仅有证据文档变化时核对 app、项目和资源与归档源码一致，有 app 代码变化则重新归档。
3. 从锁定提交手动运行 App Store Upload，`sync_store_assets=true`、`submit_for_review=false`。自动核对上一版审核状态，再上传正式构建和四语言物料。
4. 确认 Apple 将 1.7.1（13）处理为 `VALID` 并正确关联版本；回读四语言名称、subtitle、keywords、description、promotional text、更新说明和每语言每设备 6 张截图的顺序与处理状态。
5. 从已处理的分发构建安装到真机，检查启动、既有文件保留、Files 导入、HTML/Markdown/JSON/YAML/ZIP、搜索与阅读位置、原件分享、HTML/Markdown PDF 导出，以及无阻断弹窗。
6. 将审核备注草稿填写到新版本，确认隐私、出口合规、年龄分级等信息适用；完成上述记录后，通过 `submit_only=true`、`submit_for_review=true` 提审。

本地归档成功与 CI 通过不等于 Apple 处理成功、审核通过或已公开发布。
这些上传后步骤将在当前版本过审后执行。

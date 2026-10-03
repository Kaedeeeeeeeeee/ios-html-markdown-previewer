# 1.7 常规更新验收记录

日期：2026-10-03。目标：HTML Previewer 1.7 (12)。当前状态：已有功能与素材证据，最终发布构建验收和提交结果待记录。

## 发布背景与授权

发布操作者在本次会话通过 App Store Connect API 确认，1.6 (11) 已为 `READY_FOR_DISTRIBUTION`，正式上线。该状态是本次在线核查结果，不由本地构建或旧文档推导。用户明确授权“准备新版本发布，没问题就直接上线”。本次目标为常规更新，审核通过后自动发布；仍需通过下列最终构建验收，不能将授权本身作为验证通过证据。

## 本次范围

- 只读标准 JSON：结构展开、字段/路径/值搜索、源码、错误行列、精确数字复制、原文件字节保留及边界处理；JSONC、JSON PDF 导出不在范围内。
- 批量导入：系统多选、逐项重复决策、部分失败后继续、结果汇总；保留单文件立即打开行为。
- HTML/Markdown/YAML/ZIP 原有阅读、分享、安全预览与文件库操作回归。
- 三语言正式商店素材和更新说明，版本/build 为 1.7/12。
- 仅使用 Apple 提供的分析能力；本次不增加分析 SDK、埋点上传、数据库或自建统计服务。

## 已有证据及边界

| 项目 | 当前证据 | 限制 |
| --- | --- | --- |
| 真机功能回归 | [iPhone 17 报告](physical-device-validation-results/2026-10-03-json-batch-iphone-17.md)：12 个不同原有 UI 测试最终均有 Passed 记录 | 三轮合计，保留首次失败及重试；不是一次 12/12。源码为 feature commit `fdf1fdb6fb44e924da633a5e5227b3741fd70b20`，不是最终 1.7 Release archive |
| 真机系统 Files 多选 | 同报告实际多选 JSON 与 Markdown：Imported 2 / Skipped 0 / Failed 0，分别重开成功；[字节证据](physical-device-validation-results/assets/2026-10-03-json-batch/system-import-evidence.json)确认两份合成样例导入前后 SHA-256 相同、来源为 `fileImporter` | 验证的是这两份样例；不宣称已完成 Mail/AirDrop/所有消息 App 来源矩阵 |
| 单元/集成及模拟器 UI | [10 月 2 日汇总](updates/assets/2026-10-02-json-batch/validation-summary.json)：196 单元/集成、5 iPhone UI；iPad 两轮各 3 项通过 | 已有 feature 阶段证据，对应旧功能源码；最终版本配置、素材与提交 commit 仍须 CI 验证 |
| 正式截图 | [素材说明](app-store-screenshots/README.md)及 [1.7 verification](app-store-screenshots/verification-1.7.json)：3 locale × 2 family × 6 = 36 张 | 依次 HTML report、batch import、JSON、Markdown、library、YAML；本地生成不等于 ASC 已完整保存 |
| 商店 metadata | 三语言本地 metadata 长度/素材 audit 已通过；发布操作者已回读 15 个远端版本 metadata 字段均 MATCH，review notes 更新成功 | 文字字段已核对；截图仍在 DNS 失败后的断点续传，不能据此宣称全部素材已保存 |
| 发布方式 | 1.7 ASC draft 已设置 `AFTER_APPROVAL`；workflow 同样明确此值，提交路径执行设置并回读验证 | 最终提交前仍须保存实际版本 releaseType 回读证据；审核通过前不宣称已上线 |

## 最终发布构建门禁：待操作者填实际结果

以下状态全部为待完成，必须以实际证据更新，不以旧测试或素材 audit 代替。

| 门禁 | 状态 | 应记录的证据 |
| --- | --- | --- |
| 最终源代码与版本 | 待完成 | 最终 commit、clean tree、1.7/12 bundle metadata、与 feature commit 的变更范围 |
| 最终 hosted CI | 待完成 | 当前 commit 的 GitHub Actions run URL、SHA、各必要 job 结果；保留完整测试结果 |
| Production Release archive | 待完成 | Archive 路径/日志、1.7/12、最终 commit、Apple Distribution 签名及上传适用性 |
| 最终 Release smoke | 待完成 | 对应实际 Release/archive 构建、真机标识、安装/启动、JSON/批量及原有关键流程结果；失败须修复后复测 |
| ASC metadata 与素材回读 | 待完成 | 三语言字段、每 locale/family 六图的顺序/文件身份/交付状态、隐私和加密信息、版本与 build 附着信息 |
| ASC build 验证 | 待完成 | 1.7(12) processing VALID、正确附着到 1.7、验证响应、无阻塞错误 |
| 审核提交与自动发布 | 待完成 | `AFTER_APPROVAL` 实际回读、review submission ID/状态、提交时间；成功提交不等于审核通过或上线 |
| 公开上线 | 待完成 | 审核结果及 1.7 `READY_FOR_DISTRIBUTION` / 实际商店状态证据 |

发现 P0/P1、错误版本/build、签名不符、ASC 字段/截图不符或 Release smoke 失败时停止提交，修复并保存复测结果。最终验收结论须指出哪些证据来自最终 commit，哪些仅来自旧 feature 测试。

## 首发记录与本次验收的关系

旧首发 M0/#1、M3/#11 和发行 #10 保持原有 issue 状态。本次没有关闭这些 issue，没有补写外部首轮 usability 完成，也没有伪称全部来源矩阵通过。现有 [runbook](app-store-submission-runbook.md) 与旧 submission-gate 脚本没有独立 update mode，仍要求其原有首发门禁；旧报告出现 pending/blocked 时应如实保留。

本记录用于已上线产品的 1.7 常规更新验收，列出本次改动的风险与对应证据，不将旧 issue 的 OPEN 状态转换为完成，也不将旧工具输出改成 ready。完整首发来源矩阵及第一轮外部 usability 是仍未完成的独立工作。采用本次更新范围进行发布时，发布操作者应在最终结论明确写出这一范围判断、未完成首发事项及是否存在与本次变更相关的已知阻塞；不得笼统声称所有历史 release gates 均通过。

## 最终结论

待发布操作者填入最终证据、范围判断、已知问题及实际提交/上线状态。当前不得据本文件宣称 1.7 已提交、审核通过或正式上线。

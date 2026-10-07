# iPhone Duo 商店截图准备 — 2026-10-07

本目录是下一版本的商店素材策略与布局草稿，尚未上传、提交审核或公开生效。旧 `2026-10-03` 素材包保持不变。先制作简中同一份合成周报的内屏、外屏两张预览，再按最终 UI 刷新完整四语言素材。

## 已核实的商店状态

- 当前线上版本为 **1.7 / build 12**。只读 API 返回 1.7 为 `READY_FOR_SALE` / `READY_FOR_DISTRIBUTION`；build 12 为 `VALID`。版本与 build 的对应关系已通过后台核对。
- 当前英文、简中、日文各有两组截图，每组六张，共 **36 张**；API 中现有组为 `APP_IPHONE_67` 和 `APP_IPAD_PRO_3GEN_129`，全部处理状态为 `COMPLETE`。
- 本次已在英文 App Store Connect 页面核实一个独立 **iPhone Duo** 分组，标为 **Optional**，目前 **No assets added**。这里记录的是网页实际状态，不是假定的 API 枚举。
- 繁中目前没有后台 localization。10 月 3 日已准备繁中文案与本地化素材，但未接入当前商店。
- 本机 `asc` CLI 的 `sizes --all` 未列出 Duo；create-schema 仅说明字段类型为 `ScreenshotDisplayType`，没有据此确认 Duo 的实际枚举值。实现上传前需验证支持方式，不能编造 `APP_IPHONE_DUO` 等标识。

精简、去除资源 ID 和账户信息的只读依据见 [evidence.json](evidence.json)。原始 API 审计位于 `/tmp/html-release-prep-20261007`；网页观察以本次实际核对为来源。

## Duo 的官方截图尺寸

本次准备时实时读取 [Apple Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) 确认以下四种尺寸，均与已验证模拟器原图相符：

| 屏幕 | 竖屏 | 横屏 |
| --- | --- | --- |
| 外屏 | 1398 × 2034 | 2034 × 1398 |
| 内屏 | 2007 × 2853 | 2853 × 2007 |

后台当前只有**一个 Duo 分组**，不建立两个内屏、外屏上传组。准备在同一组中展示两种实际阅读布局。尚未确认该组对内外屏素材的具体自动选择、切换或排序规则，因此不承诺“用户展开时自动切换对应截图”。普通 iPhone、iPad 仍使用各自已确认的设备分组。

[Apple Manage your App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets) 是设备素材管理的参考；最终上传后仍需逐语言、逐组 read-back 顺序、图片尺寸和处理完成状态。

## 当前两张布局草稿

打开 [preview.html](preview.html) 查看简中排版。采用 10 月 3 日素材的蓝色渐变、短标题和简洁辅助文案，实际 UI 直接引用原始 PNG，CSS 只等比缩放，不拉伸、裁切或改写原生像素。

| 草稿 | 标题 | 展示目的 | 原图 |
| --- | --- | --- | --- |
| 内屏 | 展开，读得更从容 | 展示宽屏文件库与周报阅读区域 | `sources/zh-Hans/duo-inner-html.png` |
| 外屏 | 合上，也能继续读 | 展示紧凑屏幕上的同一份周报与阅读工具 | `sources/zh-Hans/duo-outer-html.png` |

两张来源是 本次使用已安装的无调试 trace **Debug 1.7(12)** 实际打开的同一份合成周报，不包含真实用户数据。内屏原图为 **2853 × 2007 / Open / display3**，外屏为 **1398 × 2034 / Closed / display1**；本次已逐张查看。隔离测试库只保留周报与开发笔记两份合成文档，拍摄时状态栏设为 9:41。拍摄结束已清除状态栏覆盖并将既有 Duo 关机，没有创建或删除设备。

捕获身份和文件校验见 [evidence.json](evidence.json)。当前 1.8 版本配置的准备与此拍摄来源分开；不将这两张归为 1.8 Release archive 产物。本预览页不是可直接上传的最终尺寸 PNG，也不代表商店已经更新。

## 最小实施范围

1. 复用旧包的四语言合成周报、Markdown 文档、文案风格和六场景顺序：HTML → Markdown → JSON → YAML → 批量导入 → 文件库。保留旧来源记录，重拍本轮导航、工具栏、搜索布局变化涉及的实际 UI。
2. 先完成简中 Duo 内外屏两张方案评审，再准备 `en-US`、`zh-Hans`、`ja`、`zh-Hant` 对应真实本地化 UI；Duo 内外屏素材放入同一个组，不将一张英文界面简单换四种标题。
3. 普通 iPhone / iPad 各六张、四语言共 48 张；Duo 初步按每语言六张规划，组内保留内外屏场景，共 24 张，全部共 72 张。此数量是本地制作计划，不是后台已接受的库存或固定要求。
4. 给合成器补 Duo 的独立画布和原图比例支持；捕获时明确活动 display：Closed 使用外屏 `display1`，Open/Partially Open 使用内屏 `display3`。既有脚本的 iPhone 竖屏比例限制不能直接套给 Duo。
5. 确认 Duo 上传支持后再更新 workflow、后台库存验证和审计脚本；同步四语言、新六张顺序和确切分组，移除硬编码的三语言 / 36 张假设。繁中另补后台 localization、support/privacy URLs 和本次发布说明。
6. 最终版本、签名和正常 Release 验收完成后，记录素材与构建身份，再上传至正确可编辑版本并 read-back。当前仅准备本地草稿，不改变线上 1.7 的任何内容。

## 复用与边界

- 旧包路径：`../2026-10-03/materials/`，包含 `copy.json`、`order.json`、`fixtures/`、`sources/`、48 张成品、校验和及尚未应用的 integration patch。
- 原始 UI 不重绘、不拉伸；本页没有模拟物理机外观或伪造设备边框。
- 已完成的 Duo QA 证明阅读行为；商店素材只表达对应可见场景，不把系统 overflow 未触发或 PDF 生成阶段旋转未捕获包装成额外功能。
- 当前预览仅用于审阅排版与内外屏内容差异；最终 PNG、四语言全套、后台分组上传与自动展示行为均需各自核验。

原始源图保留捕获时的 **RGBA** 数据，不做图像修改。最终上传 PNG 须按官方规格导出为不透明 **RGB、无 alpha 通道**；不能直接把 RGBA 源图当成最终上传图。本 HTML 及其页面截图均为布局评审材料，不是最终上传 PNG。

实际浏览器渲染已检查：页面宽度 1716 px，无横向溢出，两张原图加载成功且原生尺寸正确；页面截图已视觉验看。见 [布局预览截图](previews/duo-layout-preview.png)。

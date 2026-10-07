# 下一次小版本的 ASO 物料包

本包按用户 2026-10-03 的安排，随下一次小版本一起更新文案与截图。版本号由正常发版流程确定；没有修改当前审核中的 1.7，也没有上传、提交审核或公开发布。

## 交付内容

- `metadata/`：英文、简中、日文、繁中四套名称、副标题、关键词、推广文本、描述，按 Fastlane 字段文件拆分。
- `screenshots/<locale>/`：每语言 iPhone / iPad 各 6 张，共 48 张 PNG。按文件名前缀上传；目录没有源截图或额外兼容副本。
- `previews/`：八张设备 / 语言联系表，以及浏览用预览。
- `sources/`：真实 App 截图，保持旧源图 key，供重新排版及追溯；不要把此目录作为上传目录。
- `fixtures/`：四语言合成周报与 Markdown 示例；不是用户文件或真实业务业绩。
- `copy.json`、`order.json`：本轮标题、副文案与源图 / 最终图顺序映射。
- `validation.json`、`provenance.json`、`checksums-sha256.txt`：字段 / 图片核验、拍摄来源、文件校验值。
- `next-release-integration.patch`：已准备、未应用的发布脚本差异，补入繁中和新顺序。

顺序：HTML 报告 → Markdown 代码与公式 → JSON 结构 → YAML 配置 → 多文件导入 → 文件库。JSON / YAML 和多文件导入均来自现有真实界面；新的报告、Markdown 与置顶文件库使用独立 Debug UI 测试资料库拍摄。素材文件中的种子记录只用于摆放合成内容，不是一次真实的 Files 导入回归证据。

## 配合小版本发布

1. 先确定版本号、最终功能和正常 Release 验收。`metadata/` **没有**写 `release_notes.txt`，应根据该小版本实际变化补齐四种语言；不能把“更换商店截图”写成 App 新功能。本包也不替代隐私、审核说明、签名或功能回归。
2. 若最终 App 的预览器、工具栏、文件库或本地化发生变化，重拍受影响截图。本轮构建版本、工作区状态与二进制哈希以 `provenance.json` 为准，不能称作最终 Release archive 截图。
3. 将本包五个字段合入该版本的 `fastlane/metadata/<locale>/`，保留原有 support / privacy URLs、类别和该版本发布说明。为繁中补齐现有 URL 和其他必需字段。
4. 保留旧截图备份后，将正式 `docs/app-store-screenshots/<locale>/` 切换为本包每语言的 12 张最终图；不要混入旧顺序的图片。若正式审计仍需要根目录英文兼容图，同样用本包英文最终图补齐。`copy.json` 的六个源 key 不改名。
5. 在对应发布分支应用并复查 `next-release-integration.patch`。它把工作流从 3 语言 / 36 张变成 4 语言 / 48 张，并将后台逐张验证的顺序改成新六张。若文件有后续改动，先重新生成差异再应用；版本号 / build number 的更新属于正常发版步骤。
6. 运行该版本正常物料审计和 App 验收；上传到正确的可编辑版本后，read-back 名称 / 副标题 / 关键词 / 描述，以及四语言 × 两设备的图片顺序、校验值和处理完成状态，确认后随该版本提交。

这里只准备本地物料；以上上传与提交步骤尚未执行。本包的脚本不包含后台写入或发布命令。

## 重新生成与核验

在项目根目录运行：

```sh
python3 scripts/prepare-aso-materials.py
xcrun swift scripts/generate-app-store-screenshots.swift \
  --source-dir docs/aso/2026-10-03/materials/sources \
  --output-dir docs/aso/2026-10-03/materials/screenshots \
  --copy-file docs/aso/2026-10-03/materials/copy.json \
  --preview-dir docs/aso/2026-10-03/materials/previews \
  --locales en-US,zh-Hans,ja,zh-Hant \
  --order 01-html-report,04-markdown-preview,03-json-preview,06-yaml-preview,02-batch-import,05-library
python3 scripts/audit-aso-materials.py
git apply --check docs/aso/2026-10-03/materials/next-release-integration.patch
```

通用 `capture-release-screenshots.sh` 默认拍内置示例。重拍本包前两张时，先以 `HTML_PREVIEWER_UI_TESTS=1` 启动 App，再用 `prepare-aso-materials.py --seed <已复用的UDID> --locale <locale>` 将对应示例放入独立测试资料库，重启 App 并通过文件列表实际打开 `weekly-report.html` / `developer-notes.md`。确认渲染完成后拍摄源图；置顶文件库也应重拍。不要将新标题直接贴在原来的周末行程截图上。模拟器复用与恢复遵循用户的生命周期政策。

截图合成保持真实界面的原始比例，输出 iPhone 1320 × 2868、iPad 2064 × 2752，均无透明通道。尺寸和不透明要求已于 2026-10-03 核对 [Apple Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)。素材的数值和性能不构成下载量承诺。

上线记录应包含新版本号、商店实际生效日期、价格 / 推广变化及本包校验值。文字与截图同时生效，后续 7 天 / 30 天观察只能评估这次组合变更，不能分别归因。

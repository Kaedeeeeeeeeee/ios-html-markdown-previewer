# 1.8 (13) 商店素材包

本包使用四语言、三种设备素材，每组六张，共 72 张。Duo 只有一个后台组，六张同时包含内屏与外屏场景。这里是本地制作目录；捕获、合成、视觉核验、上传和提交分别记录，目录存在不代表已经发布。

本地制作与正式集成已完成：72 张 1.8(13) 实际 source、72 张不透明 RGB 成品、12 份联系表均完成核对；四语言正式目录每份 18 张，另有根目录英文 18 张逐字节兼容副本。`validation.json` 与 `integration-validation.json` 均为 PASS；来源、实际混合 Debug 身份与后续 resize 修复差异记录在 `provenance.json`。远端处理、审核与公开状态由发布记录独立核验。

旧 `../../2026-10-03/materials/` 包保留。四语言 metadata 采用 `origin/codex/next-release-1.7.1` 的已整合字段与 URL；本次发布说明由版本负责人单独维护，生成脚本不覆盖它。后台审核与提交门禁也由发布流程维护，不从旧 integration patch 覆盖。

## 捕获矩阵

每个 locale（`en-US`、`zh-Hans`、`ja`、`zh-Hant`）各拍以下 source keys。源文件保留旧编号；最终图编号表达新顺序。

| 最终顺序 | source suffix | 普通 iPhone / iPad | Duo |
| --- | --- | --- | --- |
| 01 HTML | `01-html-report` | 竖屏，合成周报 | Open，内屏 display3，2853 × 2007 |
| 02 Markdown | `04-markdown-preview` | 竖屏，合成开发笔记 | Closed，外屏 display1，1398 × 2034 |
| 03 JSON | `03-json-preview` | 竖屏，内置 JSON | Open，内屏 display3，2853 × 2007 |
| 04 YAML | `06-yaml-preview` | 竖屏，内置 YAML，深色 | Closed，外屏 display1，1398 × 2034，深色 |
| 05 多文件导入 | `02-batch-import` | 竖屏，导入结果 fixture | Closed，外屏 display1，1398 × 2034 |
| 06 文件库 | `05-library` | 竖屏 | Open，内屏 display3，2853 × 2007 |

文件名为 `sources/<locale>/<family>-<source suffix>.png`，family 为 `iphone`、`ipad` 或 `duo`。库图最先拍，保留两份合成文档和五个内置样例，展示全部支持格式。Duo/iPad 同时实际打开周报显示库与正文；普通 iPhone 只显示文件库。随后 HTML/Markdown 从已注入文件实际打开；JSON/YAML 使用内置样例；多文件导入在同次启动重置隔离库后使用现有 showcase fixture，避免先前样例产生重复处理对话框，呈现导入结果。这些 fixture 是内容展示资料，不冒充一次真实 Files 导入回归。

仅复用指定设备，每次一台：普通 iPhone `F56A2968-F35C-4455-8A34-43DCC6CDC319`；iPad `9216FE52-CA0E-4113-8ED5-19B4BF9755CE`；Duo `F90A798B-CBEA-4A0C-AD45-B22F7BF2E2A7`。调用前由设备负责人安装 1.8(13)、确定方向/实际姿态及 Booted 状态。脚本不构建、不安装、不 boot，也不自动改变 Duo 姿态。

```sh
# 原生设置 Open 后：三内屏场景 × 四语言
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  bash scripts/capture-aso-sources.sh \
  --device F90A798B-CBEA-4A0C-AD45-B22F7BF2E2A7 --family duo --display 3

# 原生设置 Closed 后：三外屏场景 × 四语言
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  bash scripts/capture-aso-sources.sh \
  --device F90A798B-CBEA-4A0C-AD45-B22F7BF2E2A7 --family duo --display 1

# 普通 iPhone / iPad 分别运行；不选择额外设备
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  bash scripts/capture-aso-sources.sh \
  --device F56A2968-F35C-4455-8A34-43DCC6CDC319 --family iphone

DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  bash scripts/capture-aso-sources.sh \
  --device 9216FE52-CA0E-4113-8ED5-19B4BF9755CE --family ipad
```

支持 `--locales zh-Hans`、`--keys 01-html-report` 定向重拍。每次 locale 开始先重置隔离 `UITestLibrary`，确认 metadata 持续为空后注入模板；正常资料库不受影响。截图经本次独占 `/tmp` 目录原样复制，原图保持 RGBA。每张在 `capture-records/` 记录实际版本、build、已安装 executable/debug dylib SHA256、source SHA、locale/display/尺寸；视觉审阅另行完成。退出恢复外观并清除状态栏覆盖，最终 simulator 关机由设备负责人恢复。

## 合成与审计

`devices.json` 是本地画布与 source 尺寸配置，不包含猜测的 Duo API 枚举。普通 iPhone 输出 1320 × 2868，iPad 2064 × 2752；Duo 使用对应的官方内/外屏尺寸。蓝色渐变标题区与真实 UI 分开，完整 source 等比嵌入；Duo 不用普通 iPhone 比例限制，不裁切界面、不拉伸。联系表按各图自身比例放置横竖混合素材。

```sh
python3 scripts/audit-aso-materials.py \
  --packet docs/aso/2026-10-07-duo/materials --sources-only

DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  xcrun swift scripts/generate-app-store-screenshots.swift \
  --source-dir docs/aso/2026-10-07-duo/materials/sources \
  --output-dir docs/aso/2026-10-07-duo/materials/screenshots \
  --copy-file docs/aso/2026-10-07-duo/materials/copy.json \
  --device-config docs/aso/2026-10-07-duo/materials/devices.json \
  --preview-dir docs/aso/2026-10-07-duo/materials/previews \
  --locales en-US,zh-Hans,ja,zh-Hant \
  --order 01-html-report,04-markdown-preview,03-json-preview,06-yaml-preview,02-batch-import,05-library

python3 scripts/audit-aso-materials.py --packet docs/aso/2026-10-07-duo/materials
python3 scripts/generate-aso-review-index.py --packet docs/aso/2026-10-07-duo/materials
```

可为分批合成/审计增加 `--families duo --locales zh-Hans`，并用 `--output <单独审计文件>` 保留阶段结果；完整审计与 `checksums-sha256.txt` 留给全部 72 张。上传成品必须是**不透明 RGB PNG、无 alpha 通道**，并严格匹配画布尺寸；source 保留捕获时的 RGBA。完整审计要求四语言 × 三设备 × 六张，并校验来源为 1.8(13)。结构审计不替代视觉验看，不证明 Release archive 二进制等价，也不证明 App Store 处理、审核或公开状态。

逐语言验看每个 family 的六图联系表后，将成品与原图哈希记录在 `visual-review-<family>.json`。完整 72 张结构审计与三份视觉记录都通过后，运行 `python3 scripts/generate-aso-provenance.py` 汇总 source→成品、实际设备/display、捕获时间与已安装二进制身份；混合 Debug 捕获身份保留为独立组。

通过后正式集成到 `docs/app-store-screenshots/<locale>/`，每语言 18 张，并保留根目录英文 18 张兼容副本；`copy.json` 同步本包。CI 的 `audit-integrated-release-materials.py` 验证正式输入与本包、已验证 source、捕获身份一致，只允许当前 72 张通过，不能以旧 36/48 张替代。

```sh
# 默认仅预检；完整 72 张 audit PASS 且来源哈希仍相符才允许集成
python3 scripts/integrate-aso-materials.py
python3 scripts/integrate-aso-materials.py --apply
python3 scripts/audit-integrated-release-materials.py \
  --output docs/aso/2026-10-07-duo/materials/integration-validation.json
```

集成脚本把原正式 PNG 与 copy 逐字节备份到本次唯一 `/tmp` 目录，记录 `local-integration.json`，随后同步新图并移除旧顺序的过期 PNG。旧 10/03 包及已有历史验证文档不改。

既有流水线的四语言、新顺序配置可复用。现代 Asset Library 的真实 GET 已核对三个 profile（`IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE`、`IPAD_13_PROFILE`、`IPHONE_DUO_PROFILE`）；上传工具与只读门禁使用正式目录。不得把内外屏分成两个 Duo 上传组，或承诺尚未验证的自动姿态切换。CI 在 archive 前及提交前重新核验远端四语 metadata 与 72 个现代 placements；这些实时远端检查与本包的本地审计分别记录。

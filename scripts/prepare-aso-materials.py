#!/usr/bin/env python3
"""Prepare a local ASO packet or seed its synthetic documents in a UI-test library.

This script never uploads metadata, edits normal app data, or submits a release.
The simulator must already be booted and have the app installed for --seed.
"""
import argparse
import datetime
import html
import json
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.kaede.htmlmarkdownpreviewer"
LOCALES = {
    "en-US": ["Weekly project report", "DEMO · WEEK 40", "Delivery overview", "Completed", "In review", "Next week", "Area", "Status", "Website", "Ready", "Documentation", "Review", "Mobile app", "In progress", "Developer notes", "A small example with code, math and a diagram.", "Swift code", "Math", "Workflow", "Open", "Read", "Share"],
    "zh-Hans": ["项目周报", "合成示例 · 第 40 周", "交付概览", "已完成", "待审核", "下周计划", "项目", "状态", "网站", "已就绪", "文档", "审核中", "移动 App", "进行中", "开发笔记", "用代码、公式与流程图记录一个小例子。", "Swift 代码", "数学公式", "工作流程", "打开", "阅读", "分享"],
    "ja": ["プロジェクト週報", "サンプル · 第40週", "進捗の概要", "完了", "レビュー中", "来週の予定", "項目", "状態", "Webサイト", "準備完了", "ドキュメント", "確認中", "モバイルApp", "進行中", "開発ノート", "コード・数式・図を使った小さな例。", "Swiftコード", "数式", "ワークフロー", "開く", "読む", "共有"],
    "zh-Hant": ["專案週報", "合成範例 · 第 40 週", "交付概覽", "已完成", "待審核", "下週計畫", "項目", "狀態", "網站", "已就緒", "文件", "審核中", "行動 App", "進行中", "開發筆記", "用程式碼、公式與流程圖記錄一個小例子。", "Swift 程式碼", "數學公式", "工作流程", "開啟", "閱讀", "分享"],
}
EYEBROWS = {
    "en-US": ["HTML & ZIP REPORTS", "CODE & MATH", "JSON STRUCTURE", "YAML CONFIGURATION", "MULTIPLE FILES", "YOUR FILE LIBRARY"],
    "zh-Hans": ["HTML 与 ZIP 报告", "代码与公式", "JSON 结构", "YAML 配置", "多文件导入", "你的文件库"],
    "ja": ["HTML・ZIPレポート", "コードと数式", "JSONの構造", "YAML設定", "複数ファイル", "ファイルライブラリ"],
    "zh-Hant": ["HTML 與 ZIP 報告", "程式碼與公式", "JSON 結構", "YAML 設定", "多檔案匯入", "你的檔案庫"],
}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def fixtures(locale):
    t = [html.escape(s) for s in LOCALES[locale]]
    report = f'''<!doctype html><html lang="{locale}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{t[0]}</title>
<style>
:root{{color-scheme:light dark;--bg:#f5f7fc;--card:#fff;--ink:#152238;--muted:#627087;--line:#e7ecf5;--accent:#3367e9}}
@media(prefers-color-scheme:dark){{:root{{--bg:#141c2b;--card:#202b3e;--ink:#f1f4fc;--muted:#a8b5ca;--line:#33435d;--accent:#87aaff}}}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--ink);font:16px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.5}}
main{{max-width:760px;margin:auto;padding:26px 22px}}.eyebrow{{margin:0;color:var(--accent);font-size:11px;font-weight:700;letter-spacing:.08em}}
h1{{margin:9px 0 22px;font-size:29px;line-height:1.2;letter-spacing:-.025em}}h2{{font-size:17px;margin:0 0 17px}}.card{{background:var(--card);border-radius:18px;padding:20px;margin-bottom:18px}}
.row{{display:grid;grid-template-columns:repeat(3,1fr);gap:9px;margin-bottom:18px}}.stat{{background:var(--card);padding:16px 10px;border-radius:14px}}.stat b{{display:block;font-size:28px;line-height:1.2;color:var(--accent)}}.stat span{{font-size:11px;color:var(--muted)}}
.chart{{display:grid;grid-template-columns:repeat(5,1fr);align-items:end;gap:18px;height:126px;border-bottom:1px solid var(--line)}}.bar{{border-radius:7px 7px 0 0;background:linear-gradient(#779fff,#3367e9)}}
.labels{{display:grid;grid-template-columns:repeat(5,1fr);gap:18px;font-size:10px;color:var(--muted);text-align:center;padding-top:8px}}table{{width:100%;border-collapse:collapse;font-size:13px}}th{{color:var(--muted);font-weight:500;text-align:left}}td,th{{padding:10px 0;border-bottom:1px solid var(--line)}}td:last-child{{text-align:right}}.tag{{color:var(--accent);font-size:12px}}footer{{font-size:11px;color:var(--muted)}}
</style></head><body><main><p class="eyebrow">{t[1]}</p><h1>{t[0]}</h1>
<div class="row"><div class="stat"><b>12</b><span>{t[3]}</span></div><div class="stat"><b>3</b><span>{t[4]}</span></div><div class="stat"><b>5</b><span>{t[5]}</span></div></div>
<section class="card"><h2>{t[2]}</h2><div class="chart"><div class="bar" style="height:42%"></div><div class="bar" style="height:65%"></div><div class="bar" style="height:53%"></div><div class="bar" style="height:88%"></div><div class="bar" style="height:100%"></div></div><div class="labels"><span>MON</span><span>TUE</span><span>WED</span><span>THU</span><span>FRI</span></div></section>
<section class="card"><table><thead><tr><th>{t[6]}</th><th style="text-align:right">{t[7]}</th></tr></thead><tbody><tr><td>{t[8]}</td><td class="tag">{t[9]}</td></tr><tr><td>{t[10]}</td><td class="tag">{t[11]}</td></tr><tr><td>{t[12]}</td><td class="tag">{t[13]}</td></tr></tbody></table></section><footer>{t[1]} · HTML</footer></main></body></html>'''
    m = LOCALES[locale]
    markdown = f'''# {m[14]}

{m[15]}

## {m[16]}

```swift
let pages = [12, 18, 24]
let total = pages.reduce(0, +)
print("Read \\(total) pages")
```

## {m[17]}

$$
\\int_0^1 x^2\\,dx = \\frac{{1}}{{3}}
$$

## {m[18]}

```mermaid
flowchart LR
    A["{m[19]}"] --> B["{m[20]}"]
    B --> C["{m[21]}"]
```
'''
    return report, markdown


def prepare(packet):
    candidate = json.loads((packet.parent / "metadata-candidate.json").read_text())
    brief = json.loads((packet.parent / "screenshot-brief.json").read_text())
    store_names = {"en-US": "English (U.S.)", "zh-Hans": "简体中文", "ja": "日本語", "zh-Hant": "繁體中文"}
    copy = {}
    for locale, fields in candidate["locales"].items():
        for key, value in fields.items():
            output = packet / "metadata" / locale / (key + ".txt")
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(value + "\n")
        copy[locale] = {"storefront": store_names[locale], "screenshots": {}}
        for i, slot in enumerate(brief["order"]):
            copy[locale]["screenshots"][slot["currentKey"]] = {"eyebrow": EYEBROWS[locale][i], **slot["copy"][locale]}
        report, markdown = fixtures(locale)
        directory = packet / "fixtures" / locale
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "weekly-report.html").write_text(report)
        (directory / "developer-notes.md").write_text(markdown)
    write_json(packet / "copy.json", copy)
    write_json(packet / "order.json", {"sourceKeys": [s["currentKey"] for s in brief["order"]], "outputSuffixes": [f'{s["position"]:02d}-' + s["currentKey"][3:] for s in brief["order"]], "locales": list(LOCALES)})
    print("Prepared metadata, localized screenshot copy, and synthetic documents:", packet)


def seed(packet, device, locale):
    container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", device, BUNDLE, "data"], text=True).strip())
    library = container / "Library/Application Support" / BUNDLE / "UITestLibrary"
    # Never touch the normal document library. IDs are specific to this packet.
    now = (datetime.datetime.now(datetime.timezone.utc) - datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)).total_seconds()
    ids = []
    for i, (filename, kind, title) in enumerate([("weekly-report.html", "html", LOCALES[locale][0]), ("developer-notes.md", "markdown", LOCALES[locale][14])]):
        doc_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "html-previewer-aso-20261003/" + filename)).upper()
        document_root = library / "Imports" / doc_id
        original = document_root / "original" / filename
        original.parent.mkdir(parents=True, exist_ok=True)
        original.write_bytes((packet / "fixtures" / locale / filename).read_bytes())
        write_json(document_root / "metadata.json", {
            "id": doc_id, "displayName": title, "originalFilename": filename,
            "fileExtension": original.suffix[1:], "type": kind,
            "entryDocumentType": kind, "importSource": "bundledSample",
            "importedAt": now - i, "localRootRelativePath": "Imports/" + doc_id,
            "originalFileRelativePath": "original/" + filename,
            "entryFileRelativePath": "original/" + filename,
            "fileSize": original.stat().st_size, "preferredPreviewMode": "interactive" if kind == "html" else "safePreview",
            "pinnedAt": now - i,
        })
        ids.append(doc_id)
    print(json.dumps({"device": device, "locale": locale, "library": str(library), "ids": ids}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packet", type=Path, default=ROOT / "docs/aso/2026-10-03/materials")
    parser.add_argument("--seed", metavar="SIMULATOR_UDID")
    parser.add_argument("--locale", choices=LOCALES)
    args = parser.parse_args()
    if args.seed:
        if not args.locale:
            parser.error("--seed requires --locale")
        seed(args.packet, args.seed, args.locale)
    else:
        prepare(args.packet)

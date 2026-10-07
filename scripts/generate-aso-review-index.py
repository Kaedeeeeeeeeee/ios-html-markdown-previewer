#!/usr/bin/env python3
"""Render a static, local-only review gallery from the actual packet configuration."""
import argparse
import html
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--packet", type=Path, default=Path(__file__).resolve().parents[1] / "docs/aso/2026-10-07-duo/materials")
packet = parser.parse_args().packet
order = json.loads((packet / "order.json").read_text())
copy = json.loads((packet / "copy.json").read_text())
devices = json.loads((packet / order["deviceConfig"]).read_text())["devices"]
validation_path = packet / "validation.json"
validation = json.loads(validation_path.read_text()) if validation_path.is_file() else {}
complete = validation.get("status") == "PASS" and validation.get("actualScreenshotCount") == 72
cards = []
for locale in order["locales"]:
    for device in devices:
        family = device["prefix"]
        entries = copy[locale].get("deviceScreenshots", {}).get(family, copy[locale]["screenshots"])
        for key, suffix in zip(order["sourceKeys"], order["outputSuffixes"]):
            entry = entries[key]
            src = f"screenshots/{locale}/{family}-{suffix}.png"
            title = html.escape(entry["title"]).replace("\n", "<br>")
            alt = html.escape(entry["title"].replace("\n", " "), quote=True)
            cards.append(f'<article data-locale="{locale}" data-family="{family}"><div class="tag">{html.escape(locale)} · {html.escape(device["label"])}</div><h2>{title}</h2><p>{html.escape(entry["subtitle"])}</p><a href="{src}"><img loading="lazy" src="{src}" alt="{alt}"></a><small>{src}</small></article>')
locale_options = "".join(f"<option>{locale}</option>" for locale in order["locales"])
family_options = "".join(f'<option value="{device["prefix"]}">{html.escape(device["label"])}</option>' for device in sorted(devices, key=lambda d: d["prefix"] != "duo"))
page = '''<!doctype html><html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>HTML Previewer 商店素材</title><style>*{box-sizing:border-box}body{margin:0;background:#081428;color:#eaf3ff;font-family:-apple-system,BlinkMacSystemFont,sans-serif}main{max-width:1480px;margin:auto;padding:32px 24px}header p{max-width:900px;color:#adc4e1;line-height:1.7}nav{display:flex;gap:14px;flex-wrap:wrap;margin:24px 0}select{font:inherit;background:#152947;color:#fff;padding:10px 16px;border:1px solid #385373;border-radius:8px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,350px),1fr));gap:20px}article{background:#112644;border-radius:16px;padding:22px;min-width:0}.tag{font-size:12px;color:#8abefa}h2{font-size:25px;line-height:1.25}article p{font-size:14px;line-height:1.6;color:#bed2eb;min-height:48px}img{display:block;max-width:100%;width:100%;height:330px;object-fit:contain;background:#07101f}small{display:block;color:#91abc9;font-size:11px;margin-top:12px;overflow-wrap:anywhere}a{color:#8abefa}[hidden]{display:none!important}</style></head><body><main><header><h1>HTML Previewer · 本地商店素材</h1><p>四语言 × 三种设备 × 六张，计划 72 张。成品引用实际本地化 App UI，按原比例展示；Duo 在同一个组中包含内屏与外屏。此页是本地审阅目录，上传、后台处理与公开发布另行核验。</p><p><a href="README.md">制作与捕获说明</a> · <a href="validation.json">完整结构审计</a> · <a href="checksums-sha256.txt">成品校验和</a></p></header><nav><label>语言 <select id="locale">'''+locale_options+'''</select></label><label>设备 <select id="family">'''+family_options+'''</select></label></nav><section class="grid">'''+"".join(cards)+'''</section></main><script>const locale=document.querySelector('#locale'),family=document.querySelector('#family');function update(){document.querySelectorAll('article').forEach(card=>card.hidden=card.dataset.locale!==locale.value||card.dataset.family!==family.value)}locale.addEventListener('change',update);family.addEventListener('change',update);update();</script></body></html>'''
if complete:
    page = page.replace("四语言 × 三种设备 × 六张，计划 72 张。", "四语言 × 三种设备 × 六张，共 72 张本地成品，已通过结构审计。")
(packet / "index.html").write_text(page)
print(f"Generated review gallery: {packet / 'index.html'} ({len(cards)} configured images)")

// Generates App Store screenshots v2 from the captured sources in the 10/07 packet.
// Usage: node scripts/store-art/generate-screenshots-v2.js <outRoot> [locale...]
const {chromium}=require('playwright');const fs=require('fs');
const path=require('path'),os=require('os');
const MAT=path.resolve(__dirname,'../../docs/aso/2026-10-07-duo/materials')+'/';
const PAGES=path.join(os.tmpdir(),'store-art-pages');
const copy=JSON.parse(fs.readFileSync(MAT+'copy.json'));
const order=JSON.parse(fs.readFileSync(MAT+'order.json'));
const outRoot=process.argv[2];const locales=process.argv.slice(3).length?process.argv.slice(3):order.locales;
const CJK={'en-US':'Noto Sans SC','zh-Hans':'Noto Sans SC','ja':'Noto Sans JP','zh-Hant':'Noto Sans TC'};
const ACC={'01-html-report':['#2f7bff','#38bdf8'],'04-markdown-preview':['#8b5cf6','#c084fc'],'03-json-preview':['#06b6d4','#22d3ee'],
 '06-yaml-preview':['#6366f1','#22c55e'],'02-batch-import':['#3b82f6','#a78bfa'],'05-library':['#0ea5e9','#818cf8']};
// Device layouts. Portrait: headline on top, device bleeding off the bottom. Landscape: headline left, device bleeding right.
const DEV={
 iphone:{W:1320,H:2868,src:[1206,2622],screenW:1004,bz:26,rad:124,top:820,title:124,sub:46,eb:38,headTop:180,side:60,chip:50},
 ipad:{W:2064,H:2752,src:[2048,2732],screenW:1640,bz:34,rad:60,top:780,title:150,sub:58,eb:44,headTop:170,side:120,chip:68},
 'duo-outer':{W:1398,H:2034,src:[1398,2034],screenW:1050,bz:24,rad:90,top:640,title:100,sub:40,eb:32,headTop:110,side:60,chip:44},
 'duo-inner':{W:2853,H:2007,src:[2853,2007],screenW:1900,bz:30,rad:70,top:400,left:1060,title:132,sub:50,eb:40,side:140,chip:58,landscape:true},
};
// Callout crops in source pixels [x,y,w,h], per device and source key.
const CROP={
 iphone:{'01-html-report':[30,1150,1146,690],'04-markdown-preview':[20,930,1166,490],'03-json-preview':[20,850,1166,370],
  '06-yaml-preview':[20,840,1166,880],'02-batch-import':[20,490,1166,500],'05-library':[20,1250,1166,515]},
 ipad:{'01-html-report':[260,660,1500,440],'04-markdown-preview':[320,520,1400,320],'03-json-preview':[20,440,1000,300],
  '06-yaml-preview':[0,420,1000,720],'02-batch-import':[420,860,1180,320],'05-library':[0,620,640,360]},
 'duo-outer':{'02-batch-import':[40,220,1110,510],'04-markdown-preview':[50,830,1080,480],'06-yaml-preview':[20,730,1190,720]},
 'duo-inner':{'01-html-report':[170,990,2170,710],'03-json-preview':[20,720,1250,370],'05-library':[20,1180,900,480]},
};
// Locale-specific vertical shifts where longer copy pushes content down.
const SHIFT={'en-US':{'04-markdown-preview':{iphone:88,'duo-outer':88}}};
const ZOOM={iphone:1.21,ipad:1.5,'duo-outer':1.2,'duo-inner':1.35};
// Chips as fractions of the canvas [label,x,y,rot]
const CHIPS={
 portrait:{'01-html-report':[['HTML',.023,.272,-10],['ZIP',.82,.293,9],['&lt;/&gt;',.80,.52,-6]],
  '02-batch-import':[['@html',.05,.655,-7],['@md',.6,.70,6],['data.json',.083,.79,4],['config.yaml',.545,.845,-5]]},
 landscape:{'01-html-report':[['HTML',.05,.80,-8],['ZIP',.26,.86,7],['&lt;/&gt;',.35,.10,-6]]},
};
const FILE={'en-US':['report.html','notes.md'],'zh-Hans':['周报.html','笔记.md'],'ja':['レポート.html','ノート.md'],'zh-Hant':['週報.html','筆記.md']};

function html(dev,d,loc,key,srcFile,t){
 const [sw0,sh0]=d.src, sw=d.screenW, s=sw/sw0, sh=Math.round(sh0*s), pw=sw+d.bz*2, ph=sh+d.bz*2;
 const px=d.landscape?d.left:(d.W-pw)/2, py=d.top;
 const c=[...CROP[dev][key]], z=ZOOM[dev]; c[1]+=SHIFT[loc]?.[key]?.[dev]||0; let cw=Math.min(c[2]*s*z,d.landscape?d.W-d.left+40:d.W-80), k=cw/c[2], ch=c[3]*k;
 let cl=px+d.bz+c[0]*s-(cw-c[2]*s)/2, ct=py+d.bz+c[1]*s-(ch-c[3]*s)/2;
 cl=Math.max(d.landscape?d.left-80:40,Math.min(cl,d.W-40-cw)); ct=Math.min(ct,d.H-ch-60);
 const rot=(['01','03','05'].includes(key.slice(0,2))?-2:2);
 const [a1,a2]=ACC[key];
 const chips=(CHIPS[d.landscape?'landscape':'portrait'][key]||[]).map(([l,x,y,r])=>{
  if(l=='@html')l=FILE[loc][0]; if(l=='@md')l=FILE[loc][1];
  return `<div class="chip" style="left:${x*d.W}px;top:${y*d.H}px;transform:rotate(${r}deg)">${l}</div>`}).join('');
 const headCss=d.landscape
  ?`left:${d.side}px;width:${d.left-d.side-100}px;top:0;bottom:0;justify-content:center;align-items:flex-start;text-align:left`
  :`left:${d.side}px;right:${d.side}px;top:${d.headTop}px;height:${d.top-d.headTop-60}px;align-items:center;text-align:center`;
 return `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@500;800&family=Noto+Sans+JP:wght@500;800&family=Noto+Sans+TC:wght@500;800&display=block" rel="stylesheet"><style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:${d.W}px;height:${d.H}px;overflow:hidden}
body{font-family:Inter,"${CJK[loc]}",sans-serif;position:relative;
background:radial-gradient(${d.W*.7}px ${d.W*.7}px at ${d.landscape?'68% 60%':'50% 78%'}, ${a1}cc, transparent 70%),radial-gradient(${d.W*.6}px ${d.W*.45}px at 100% 0%, ${a2}66, transparent 70%),linear-gradient(170deg,#05123a 0%,#0a2a78 55%,#0b3fa8 100%)}
.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.04) 2px,transparent 2px),linear-gradient(90deg,rgba(255,255,255,.04) 2px,transparent 2px);background-size:88px 88px;mask-image:linear-gradient(${d.landscape?'90deg,':''}#000,transparent 60%)}
svg{position:absolute;inset:0}
.head>*{flex-shrink:0}.head{position:absolute;display:flex;flex-direction:column;gap:${d.eb*.9}px;${headCss}}
.eb{font-weight:700;font-size:${d.eb}px;line-height:1;color:#cfe0ff;letter-spacing:${d.eb/10}px;padding:${d.eb*.5}px ${d.eb*.95}px;border-radius:99px;background:rgba(255,255,255,.1);border:2px solid rgba(255,255,255,.2);white-space:nowrap}
h1{color:#fff;font-size:${d.title}px;line-height:1.16;font-weight:800;letter-spacing:-.01em;white-space:pre;width:100%;overflow:hidden}
p{color:rgba(220,232,255,.85);font-size:${d.sub}px;line-height:1.35;font-weight:500;width:100%}
.phone{position:absolute;left:${px}px;top:${py}px;width:${pw}px;height:${ph}px;border-radius:${d.rad+d.bz}px;background:#0b0d14;padding:${d.bz}px;box-shadow:0 0 0 4px #3a4258,0 80px 160px rgba(0,8,40,.7)}
.phone img{width:${sw}px;height:${sh}px;border-radius:${d.rad}px;display:block}
.co{position:absolute;left:${cl}px;top:${ct}px;width:${cw}px;height:${ch}px;border-radius:${Math.round(d.W/30)}px;overflow:hidden;transform:rotate(${rot}deg);box-shadow:0 60px 120px rgba(0,8,40,.55),0 0 0 4px rgba(255,255,255,.85);background:#fff}
.co img{position:absolute;left:${-c[0]*k}px;top:${-c[1]*k}px;width:${sw0*k}px}
.chip{position:absolute;padding:${d.chip*.5}px ${d.chip*.8}px;border-radius:${d.chip*.7}px;font-weight:800;font-size:${d.chip}px;color:#fff;background:linear-gradient(145deg,#5b95ff,#2b5fe6);border:3px solid rgba(255,255,255,.55);box-shadow:0 30px 70px rgba(0,10,50,.45);white-space:nowrap}
</style></head><body><div class="grid"></div>
<svg viewBox="0 0 ${d.W} ${d.H}" fill="none"><ellipse cx="${d.landscape?d.W*.68:d.W/2}" cy="${d.H*.7}" rx="${d.W*.68}" ry="${d.H*.4}" stroke="rgba(170,205,255,.16)" stroke-width="3" stroke-dasharray="6 16"/><ellipse cx="${d.landscape?d.W*.68:d.W/2}" cy="${d.H*.7}" rx="${d.W*.95}" ry="${d.H*.52}" stroke="rgba(170,205,255,.1)" stroke-width="3"/></svg>
<div class="head"><div class="eb">${t.eyebrow}</div><h1>${t.title}</h1><p>${t.subtitle}</p></div>
<div class="phone"><img src="file://${srcFile}"></div>
<div class="co"><img src="file://${srcFile}"></div>${chips}
</body></html>`;}

// Shrink headline until it fits on its own lines, then shrink subtitle to at most 2 lines.
async function fit(p){return p.evaluate(()=>{const h=document.querySelector('h1'),q=document.querySelector('p'),hd=document.querySelector('.head');
 let fs=parseFloat(getComputedStyle(h).fontSize);while(h.scrollWidth>h.clientWidth+1&&fs>40){fs-=2;h.style.fontSize=fs+'px'}
 let ss=parseFloat(getComputedStyle(q).fontSize);const lh=()=>parseFloat(getComputedStyle(q).lineHeight);
 while(q.getBoundingClientRect().height>lh()*2+2&&ss>24){ss-=1;q.style.fontSize=ss+'px'}
 while(hd.scrollHeight>hd.clientHeight+1&&fs>40){fs-=2;h.style.fontSize=fs+'px'}
 return {fs,ss,overflow:hd.scrollHeight>hd.clientHeight+1}})}

(async()=>{const b=await chromium.launch({proxy:process.env.HTTPS_PROXY?{server:process.env.HTTPS_PROXY}:undefined});
const devCfg=JSON.parse(fs.readFileSync(MAT+'devices.json')).devices;const duoFrames=devCfg.find(x=>x.prefix=='duo').frames;
for(const loc of locales)for(const prefix of ['iphone','ipad','duo'])for(let i=0;i<6;i++){
 const key=order.sourceKeys[i], outName=`${prefix}-${order.outputSuffixes[i]}.png`;
 const dev=prefix=='duo'?(duoFrames[key].screen=='inner'?'duo-inner':'duo-outer'):prefix, d=DEV[dev];
 const t=(prefix=='duo'&&copy[loc].deviceScreenshots?.duo?.[key])||copy[loc].screenshots[key];
 const tt={...t,title:t.title.replace(/</g,'&lt;'),subtitle:t.subtitle.replace(/</g,'&lt;'),eyebrow:t.eyebrow.replace(/</g,'&lt;')};
 const srcFile=`${MAT}sources/${loc}/${prefix}-${key}.png`;
 const ctx=await b.newContext({ignoreHTTPSErrors:true,viewport:{width:d.W,height:d.H}});const p=await ctx.newPage();
 const f=path.join(PAGES,`${loc}-${outName}.html`);fs.mkdirSync(PAGES,{recursive:true});fs.writeFileSync(f,html(dev,d,loc,key,srcFile,tt));
 await p.goto('file://'+f);await p.waitForLoadState('networkidle');await p.evaluate(()=>document.fonts.ready);
 const r=await fit(p);fs.mkdirSync(`${outRoot}/${loc}`,{recursive:true});
 await p.screenshot({path:`${outRoot}/${loc}/${outName}`});await ctx.close();
 console.log(loc,outName,JSON.stringify(r));}
await b.close()})();

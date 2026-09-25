import Foundation

extension BuiltInSampleProvider {
    /// Native HTML controls and CSS animation stay usable when page JavaScript is disabled.
    static var htmlMotionScene: String {
        """
        <section class="motion-story" aria-labelledby="scene-heading">
          <h2 class="section-label" id="scene-heading">\(escaped(AppStrings.SampleDesign.htmlSceneTitle))</h2>
          <input class="scene-input" type="radio" name="scene-light" id="scene-day" checked>
          <input class="scene-input" type="radio" name="scene-light" id="scene-evening">
          <input class="scene-input" type="checkbox" id="pause-motion">
          <div class="scene-toolbar">
            <div class="scene-light-controls">
              <label for="scene-day">\(escaped(AppStrings.SampleDesign.htmlDay))</label>
              <label for="scene-evening">\(escaped(AppStrings.SampleDesign.htmlEvening))</label>
            </div>
            <label class="motion-toggle" for="pause-motion"><span class="pause-symbol" aria-hidden="true"></span>\(escaped(AppStrings.SampleDesign.htmlPauseMotion))</label>
          </div>
          <figure class="postcard">
            <div class="postcard-art">
              <span class="postcard-badge" aria-hidden="true">09:30 — 15:00</span>
              <svg viewBox="0 0 600 300" role="img" aria-labelledby="postcard-title">
                <title id="postcard-title">\(escaped(AppStrings.SampleDesign.htmlSceneLabel))</title>
                <defs>
                  <linearGradient id="scene-sky" x2="0" y2="1"><stop class="sky-top"/><stop class="sky-bottom" offset="1"/></linearGradient>
                  <linearGradient id="scene-water" x2="1" y2=".3"><stop stop-color="#73baff"/><stop offset="1" stop-color="#b9dfff"/></linearGradient>
                </defs>
                <rect width="600" height="300" fill="url(#scene-sky)"/>
                <g class="scene-stars" fill="#e9f3ff"><circle cx="255" cy="33" r="2"/><circle cx="390" cy="54" r="2.5"/><circle cx="542" cy="95" r="2"/><circle cx="323" cy="76" r="1.5"/></g>
                <g class="scene-sun-position">
                  <circle cx="486" cy="57" r="38" fill="#f5c86e" opacity=".12"/>
                  <circle cx="486" cy="57" r="23" fill="#efbd65"/>
                  <g class="sun-rays" fill="none" stroke="#efbd65" stroke-width="2" stroke-linecap="round">
                    <path d="M486 21v-6M486 93v6M450 57h-6M522 57h6M461 32l-4-4M511 82l4 4M461 82l-4 4M511 32l4-4"/>
                  </g>
                </g>
                <g class="scene-cloud cloud-one" fill="white" opacity=".75"><path d="M200 62a17 17 0 0 1 29-12 22 22 0 0 1 43 6 13 13 0 0 1 1 26h-72a10 10 0 0 1-1-20Z"/></g>
                <g class="scene-cloud cloud-two" fill="white" opacity=".45"><path d="M350 110a13 13 0 0 1 22-9 17 17 0 0 1 32 4 10 10 0 0 1 1 20h-55a8 8 0 0 1 0-15Z"/></g>
                <path class="scene-ground" d="M0 176Q85 144 169 168T342 158T600 170V300H0Z"/>
                <path d="M270 155C241 192 369 191 327 220S252 259 320 300H436C352 253 419 244 415 220S315 184 336 155Z" fill="url(#scene-water)" opacity=".78"/>
                <g class="river-ripples" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" opacity=".8">
                  <path d="M289 177h22m40 29h30m-54 34h27m-4 31h36"/>
                </g>
                <g class="river-ripples ripple-two" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" opacity=".5"><path d="M303 187h20m63 38h17m-64 29h20"/></g>
                <g class="cafe-building">
                  <rect x="60" y="133" width="100" height="76" rx="5" fill="var(--building)"/>
                  <path d="M52 135h116l-10-20H62Z" fill="#539bef"/>
                  <path d="M70 115l-6 20m27-20-2 20m24-20 2 20m20-20 6 20" stroke="#c9e3ff" stroke-width="10"/>
                  <rect x="73" y="152" width="38" height="35" rx="3" fill="var(--window)"/>
                  <path d="M92 152v35M73 170h38" stroke="var(--building)" stroke-width="3"/>
                  <rect x="125" y="153" width="21" height="56" rx="3" fill="#759ac1"/>
                  <circle cx="140" cy="181" r="2" fill="white"/>
                  <path d="M102 105c-12-9 12-11 0-22m12 21c-12-9 12-11 0-22" class="coffee-steam" fill="none" stroke="#7e9fbf" stroke-width="2.5" stroke-linecap="round"/>
                </g>
                <g class="river-tree">
                  <path d="M234 166v40m0-27-14-10m14 1 14-9" fill="none" stroke="#87a0b6" stroke-width="4" stroke-linecap="round"/>
                  <g class="tree-crown" fill="#92c4bc"><circle cx="219" cy="149" r="17"/><circle cx="241" cy="139" r="21"/><circle cx="253" cy="160" r="15"/></g>
                </g>
                <g class="bookshop-building">
                  <rect x="466" y="131" width="89" height="81" rx="5" fill="var(--building)"/>
                  <path d="M459 133l51-30 52 30Z" fill="#7da5cf"/>
                  <rect x="478" y="151" width="33" height="40" rx="3" fill="var(--window)"/>
                  <path d="M484 163v20m7-24v24m7-17v17m7-22v22" stroke="#6f98bf" stroke-width="4"/>
                  <rect x="523" y="154" width="20" height="58" rx="3" fill="#759ac1"/>
                  <circle cx="537" cy="182" r="2" fill="white"/>
                </g>
                <path d="M108 225C178 272 236 215 300 223S423 272 510 232" fill="none" stroke="#1679d6" stroke-opacity=".2" stroke-width="5" stroke-linecap="round"/>
                <path class="walking-route" d="M108 225C178 272 236 215 300 223S423 272 510 232" pathLength="100" fill="none" stroke="#1679d6" stroke-width="5" stroke-linecap="round"/>
                <g fill="white" stroke="#1679d6" stroke-width="3"><circle cx="108" cy="225" r="8"/><circle cx="300" cy="223" r="8"/><circle cx="510" cy="232" r="8"/></g>
                <circle class="stop-pulse" cx="108" cy="225" r="15" fill="none" stroke="#1679d6" stroke-width="2" opacity=".35"/>
              </svg>
            </div>
            <figcaption>\(escaped(AppStrings.SampleDesign.htmlSceneCaption))</figcaption>
          </figure>
          <nav class="scene-stops" aria-label="\(escaped(AppStrings.SampleDesign.htmlSection))">
            <a href="#coffee-stop"><span>09:30</span>\(escaped(AppStrings.SampleDesign.htmlSceneCoffee))</a>
            <a href="#river-stop"><span>11:00</span>\(escaped(AppStrings.SampleDesign.htmlSceneRiverside))</a>
            <a href="#book-stop"><span>14:00</span>\(escaped(AppStrings.SampleDesign.htmlSceneBooks))</a>
          </nav>
          <p class="caption scene-hint">\(escaped(AppStrings.SampleDesign.htmlSceneHint))</p>
        </section>
        """
    }

    static let htmlMotionCSS = """
    .motion-story { position: relative; margin-bottom: 32px; }
    .scene-input { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
    .scene-toolbar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 8px 12px; margin-bottom: 14px; font-size: .72rem; }
    .scene-light-controls { display: flex; padding: 3px; border-radius: 12px; background: var(--surface); }
    .scene-light-controls label { display: grid; align-items: center; min-height: 38px; padding: 4px 14px; border-radius: 9px; color: var(--secondary); cursor: pointer; transition: color .25s, background-color .25s, box-shadow .25s; }
    #scene-day:checked ~ .scene-toolbar label[for="scene-day"], #scene-evening:checked ~ .scene-toolbar label[for="scene-evening"] { background: var(--background); color: var(--ink); box-shadow: 0 1px 4px #00000012; }
    .motion-toggle { display: flex; align-items: center; gap: 7px; min-height: 44px; padding: 8px 4px; color: var(--secondary); cursor: pointer; }
    .pause-symbol { width: 13px; height: 13px; border-left: 4px solid currentColor; border-right: 4px solid currentColor; }
    #pause-motion:checked ~ .scene-toolbar .motion-toggle { color: var(--accent); }
    #pause-motion:checked ~ .scene-toolbar .pause-symbol { width: 13px; height: 9px; border: 0; border-left: 2px solid currentColor; border-bottom: 2px solid currentColor; transform: translateY(-2px) rotate(-45deg); }
    #scene-day:focus-visible ~ .scene-toolbar label[for="scene-day"], #scene-evening:focus-visible ~ .scene-toolbar label[for="scene-evening"], #pause-motion:focus-visible ~ .scene-toolbar .motion-toggle { outline: 2px solid var(--accent); outline-offset: 3px; }
    .postcard { --sky-top: #e0efff; --sky-bottom: #f5faff; --ground: #e3edf1; --building: #fff; --window: #d5eaff; overflow: hidden; border: .5px solid var(--line); border-radius: 20px; background: var(--surface); }
    .postcard-art { position: relative; overflow: hidden; }
    .postcard svg { display: block; width: 100%; height: auto; }
    .sky-top { stop-color: var(--sky-top); transition: stop-color 1.2s; }
    .sky-bottom { stop-color: var(--sky-bottom); transition: stop-color 1.2s; }
    .scene-ground { fill: var(--ground); transition: fill 1.2s; }
    .cafe-building rect, .bookshop-building rect { transition: fill 1.2s; }
    .postcard-badge { position: absolute; z-index: 1; top: 16px; left: 16px; padding: 7px 10px; border: .5px solid #ffffff90; border-radius: 9px; background: #ffffffb8; -webkit-backdrop-filter: blur(12px); backdrop-filter: blur(12px); color: #365878; font-size: .62rem; font-weight: 600; font-variant-numeric: tabular-nums; }
    .postcard figcaption { padding: 14px 16px; font-size: .76rem; font-weight: 400; line-height: 1.5; color: var(--secondary); }
    .scene-stars { opacity: 0; transition: opacity 1.2s; }
    .scene-sun-position { transition: transform 1.2s; }
    #scene-evening:checked ~ .postcard { --sky-top: #253e5f; --sky-bottom: #b6cddd; --ground: #748ea4; --building: #d4e0eb; --window: #f6d39a; }
    #scene-evening:checked ~ .postcard .scene-stars { opacity: 1; }
    #scene-evening:checked ~ .postcard .scene-sun-position { transform: translateY(39px); }
    .scene-cloud { animation: cloud-drift 14s ease-in-out infinite alternate; }
    .cloud-two { animation-duration: 19s; animation-delay: -8s; }
    .sun-rays { transform-origin: 486px 57px; animation: sun-turn 36s linear infinite; }
    .river-ripples { animation: river-flow 4s ease-in-out infinite; }
    .ripple-two { animation-delay: -2s; }
    .coffee-steam { animation: steam-rise 4s ease-in-out infinite; }
    .tree-crown { transform-origin: 235px 177px; animation: tree-sway 6s ease-in-out infinite alternate; }
    .walking-route { stroke-dasharray: 13 87; animation: route-flow 9s linear infinite; }
    .stop-pulse { transform-box: fill-box; transform-origin: center; animation: stop-breathe 3s ease-in-out infinite; }
    #pause-motion:checked ~ .postcard * { animation-play-state: paused !important; }
    .scene-stops { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; margin-top: 12px; }
    .scene-stops a { display: block; min-height: 44px; padding: 8px 2px; text-align: center; text-decoration: none; color: var(--ink); font-size: .76rem; overflow-wrap: anywhere; border-radius: 10px; transition: background-color .2s, transform .2s; }
    .scene-stops span { display: block; margin-bottom: 4px; color: var(--accent); font-size: .64rem; font-variant-numeric: tabular-nums; }
    .scene-stops a:active { background: var(--surface); transform: translateY(2px); }
    .scene-stops a:focus-visible, .packing-note summary:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
    .scene-hint { text-align: center; margin-top: 6px; font-size: .66rem; }
    .schedule li { scroll-margin-top: 20px; }
    .schedule li:target { background: var(--note); border-radius: 12px; }
    .packing-note { margin-top: 20px; padding: 0 2px; font-size: .85rem; }
    .packing-note summary { display: flex; justify-content: space-between; align-items: center; gap: 16px; min-height: 48px; list-style: none; font-weight: 600; cursor: pointer; }
    .packing-note summary::-webkit-details-marker { display: none; }
    .packing-note summary::after { content: ''; flex: 0 0 7px; width: 7px; height: 7px; margin-right: 4px; border-right: 1.5px solid var(--accent); border-bottom: 1.5px solid var(--accent); transform: rotate(45deg); transition: transform .25s; }
    .packing-note[open] summary::after { transform: rotate(225deg); }
    .packing-note p { padding: 4px 24px 8px 0; color: var(--secondary); line-height: 1.6; }
    @keyframes cloud-drift { from { transform: translateX(-12px); } to { transform: translateX(18px); } }
    @keyframes sun-turn { to { transform: rotate(360deg); } }
    @keyframes river-flow { 0%, 100% { transform: translateX(-4px); opacity: .35; } 50% { transform: translateX(7px); opacity: .85; } }
    @keyframes steam-rise { 0%, 100% { transform: translateY(3px); opacity: .2; } 50% { transform: translateY(-6px); opacity: .7; } }
    @keyframes tree-sway { from { transform: rotate(-3deg); } to { transform: rotate(3deg); } }
    @keyframes route-flow { from { stroke-dashoffset: 100; } to { stroke-dashoffset: 0; } }
    @keyframes stop-breathe { 0%, 100% { transform: scale(.8); opacity: .2; } 50% { transform: scale(1.15); opacity: .45; } }
    @media (hover: hover) {
      .scene-stops a:hover { background: var(--surface); transform: translateY(-2px); }
    }
    @media (prefers-color-scheme: dark) {
      .postcard { --sky-top: #182b43; --sky-bottom: #52738d; --ground: #415d73; --building: #bfd0df; --window: #c0dff8; }
      .postcard-badge { background: #14283dc9; border-color: #ffffff25; color: #d1e7fc; }
      #scene-evening:checked ~ .postcard { --sky-top: #111e33; --sky-bottom: #59758c; --ground: #34495d; --building: #93aac0; }
    }
    @media (prefers-reduced-motion: reduce) {
      .motion-story *, .motion-story *::before, .motion-story *::after, .packing-note *::after { animation: none !important; transition: none !important; }
      .walking-route { stroke-dasharray: none; }
      #pause-motion, .motion-toggle, .scene-hint { display: none; }
    }
    @media print {
      .motion-story { margin-bottom: 16px; break-inside: avoid; }
      .motion-story *, .packing-note *::after { animation: none !important; transition: none !important; }
      .scene-toolbar, .scene-hint, .postcard-badge, .scene-stops, .packing-note { display: none; }
      .postcard, #scene-evening:checked ~ .postcard { --sky-top: #edf5ff; --sky-bottom: #fff; --ground: #e3edf1; --building: #fff; --window: #d5eaff; border-color: #d1d1d6; background: white; }
      .postcard-art { max-width: 340px; margin: 0 auto; }
      .postcard figcaption { padding: 6px 12px 10px; text-align: center; font-size: .7rem; }
      .walking-route { stroke-dasharray: none; }
      .scene-stars { display: none; }
      #scene-evening:checked ~ .postcard .scene-sun-position { transform: none; }
      .schedule li:target { background: none; }
    }
    """
}

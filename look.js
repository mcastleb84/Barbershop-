/* Look of the app: background styles, background photo, 20 text styles, bold and text color.
   The owner sets the shop's look (saved in shop_settings.theme, everyone sees it).
   Each customer can set their own look on their device (localStorage "bs.mylook"); it wins on that device. */
(function(){
  var BS = window;
  var hexOk = function(c){ return /^#[0-9a-f]{6}$/i.test(String(c || '')) ? String(c).toLowerCase() : ''; };
  var rgb = function(h){ var n = parseInt(h.slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; };
  var lum = function(h){ return rgb(h).map(function(v){ v /= 255; return v <= .03928 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); }).reduce(function(a, v, i){ return a + v * [.2126, .7152, .0722][i]; }, 0); };
  var contrast = function(a, b){ var x = lum(a), y = lum(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };
  var mix = function(a, b, t){ var A = rgb(a), B = rgb(b); return '#' + A.map(function(v, i){ return Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0'); }).join(''); };
  var readable = function(c, bg, min){ var x = c, to = lum(bg) > .4 ? '#000000' : '#ffffff'; for (var i = 0; i < 12 && contrast(x, bg) < (min || 4.5); i++) x = mix(x, to, .18); return x; };
  BS.bsColor = { hexOk: hexOk, lum: lum, contrast: contrast, mix: mix, readable: readable, rgb: rgb };

  /* 20 text styles; fonts download only when used or browsed */
  var FONTS = BS.BS_FONTS = {
    std: ['Standard', ''],
    playfair: ['Playfair', "'Playfair Display', Georgia, serif", 'Playfair+Display:wght@400;700;900'],
    lora: ['Lora', "'Lora', Georgia, serif", 'Lora:wght@400;700'],
    merri: ['Merriweather', "'Merriweather', Georgia, serif", 'Merriweather:wght@400;900'],
    abril: ['Abril Fatface', "'Abril Fatface', Georgia, serif", 'Abril+Fatface'],
    cinzel: ['Cinzel', "'Cinzel', Georgia, serif", 'Cinzel:wght@400;800'],
    bebas: ['Bebas Neue', "'Bebas Neue', Impact, sans-serif", 'Bebas+Neue'],
    oswald: ['Oswald', "'Oswald', Impact, sans-serif", 'Oswald:wght@400;700'],
    anton: ['Anton', "'Anton', Impact, sans-serif", 'Anton'],
    montserrat: ['Montserrat', "'Montserrat', system-ui, sans-serif", 'Montserrat:wght@400;800'],
    poppins: ['Poppins', "'Poppins', system-ui, sans-serif", 'Poppins:wght@400;800'],
    raleway: ['Raleway', "'Raleway', system-ui, sans-serif", 'Raleway:wght@400;800'],
    josefin: ['Josefin Sans', "'Josefin Sans', system-ui, sans-serif", 'Josefin+Sans:wght@400;700'],
    righteous: ['Righteous', "'Righteous', system-ui, sans-serif", 'Righteous'],
    lobster: ['Lobster', "'Lobster', cursive", 'Lobster'],
    pacifico: ['Pacifico', "'Pacifico', cursive", 'Pacifico'],
    dancing: ['Dancing Script', "'Dancing Script', cursive", 'Dancing+Script:wght@400;700'],
    vibes: ['Great Vibes', "'Great Vibes', cursive", 'Great+Vibes'],
    marker: ['Marker', "'Permanent Marker', cursive", 'Permanent+Marker'],
    typewriter: ['Typewriter', "'Courier Prime', 'Courier New', monospace", 'Courier+Prime:wght@400;700']
  };
  var loaded = {};
  BS.bsLoadFonts = function(keys){
    var need = keys.filter(function(k){ return FONTS[k] && FONTS[k][2] && !loaded[k]; }); if (!need.length) return;
    need.forEach(function(k){ loaded[k] = 1; });
    var l = document.createElement('link'); l.rel = 'stylesheet';
    l.href = 'https://fonts.googleapis.com/css2?' + need.map(function(k){ return 'family=' + FONTS[k][2]; }).join('&') + '&display=swap';
    document.head.appendChild(l);
  };

  /* Background styles. c = second color. */
  var PATTERNS = BS.BS_PATTERNS = {
    solid: ['Solid color', function(){ return ['none', 'auto']; }],
    checks: ['Checks', function(c){ return ['conic-gradient(' + c + ' 25%,transparent 0 50%,' + c + ' 0 75%,transparent 0)', '36px 36px']; }],
    bigchecks: ['Big checks', function(c){ return ['conic-gradient(' + c + ' 25%,transparent 0 50%,' + c + ' 0 75%,transparent 0)', '96px 96px']; }],
    stripes: ['Stripes', function(c){ return ['repeating-linear-gradient(90deg,' + c + ' 0 18px,transparent 18px 36px)', 'auto']; }],
    diagonal: ['Slanted stripes', function(c){ return ['repeating-linear-gradient(45deg,' + c + ' 0 14px,transparent 14px 28px)', 'auto']; }],
    dots: ['Dots', function(c){ return ['radial-gradient(' + c + ' 24%,transparent 26%)', '30px 30px']; }],
    fade: ['Fade', function(c){ return ['linear-gradient(170deg,transparent 0%,' + c + ' 100%)', 'auto']; }],
    plaid: ['Plaid mix', function(c){ var x = rgb(c), a = 'rgba(' + x.join(',') + ',.5)'; return ['repeating-linear-gradient(90deg,' + a + ' 0 22px,transparent 22px 44px),repeating-linear-gradient(0deg,' + a + ' 0 22px,transparent 22px 44px)', 'auto']; }]
  };
  var photoOk = function(u){ return /^data:image\/(jpeg|png|webp)[;,][^"'()\s]*$/i.test(u || '') || /^https:\/\/[^\s"'()<>]+$/.test(u || '') ? u : ''; };
  var cleanExtras = function(v){
    v = v && typeof v === 'object' ? v : {}; var o = {};
    if (PATTERNS[v.pattern]) o.pattern = v.pattern;
    if (hexOk(v.c2)) o.c2 = hexOk(v.c2);
    if (FONTS[v.font] && v.font !== 'std') o.font = v.font;
    if (v.all === true) o.all = true;
    if (v.tlight === true) o.tlight = true;
    if (hexOk(v.tcolor)) o.tcolor = hexOk(v.tcolor);
    if (photoOk(v.photo)) o.photo = photoOk(v.photo);
    if (isFinite(+v.fade) && v.fade !== '' && v.fade != null) o.fade = Math.min(85, Math.max(0, +v.fade));
    if (/^(left|right)$/.test(v.px || '')) o.px = v.px;
    if (/^(top|bottom)$/.test(v.py || '')) o.py = v.py;
    if (isFinite(+v.zoom) && +v.zoom > 100) o.zoom = Math.min(250, Math.round(+v.zoom));
    if (hexOk(v.bg)) o.bg = hexOk(v.bg);
    return o;
  };
  BS.bsCleanExtras = cleanExtras;

  /* The customer's own look on this device */
  BS.bsMyLook = function(){ try { return cleanExtras(JSON.parse(localStorage.getItem('bs.mylook') || 'null')); } catch(e){ return {}; } };
  BS.bsSaveMyLook = function(v){ try { var c = cleanExtras(v); if (Object.keys(c).length) localStorage.setItem('bs.mylook', JSON.stringify(c)); else localStorage.removeItem('bs.mylook'); return true; } catch(e){ return false; } };

  /* Paint everything: shop look (raw saved theme object) with the customer's look on top */
  BS.bsShopRaw = null;
  BS.bsRender = function(shopRaw){
    if (arguments.length) BS.bsShopRaw = shopRaw;
    var raw = BS.bsShopRaw, base = BS.bsThemeOf(raw), shop = cleanExtras(raw), my = BS.bsMyLook();
    var bg = my.bg || (base && base.bg) || null;
    BS.bsApplyTheme(bg ? { bg: bg, accent: base && base.accent, blue: base && base.blue } : base);
    var root = document.documentElement, cs = getComputedStyle(root);
    var bgc = hexOk(cs.getPropertyValue('--bg').trim()) || '#5e1527', surface = hexOk(cs.getPropertyValue('--surface').trim()) || '#ffffff';
    var useMyPat = !!my.pattern, pat = (useMyPat ? my.pattern : shop.pattern) || 'solid';
    var c2 = (useMyPat ? my.c2 : shop.c2) || mix(bgc, lum(bgc) > .4 ? '#000000' : '#ffffff', .25);
    var photo = my.photo || shop.photo || '', pl = my.photo ? my : shop, fade = pl.fade; if (fade == null) fade = 45;
    var ppos = (pl.px || 'center') + ' ' + (pl.py || 'center'), pzoom = (pl.zoom || 100) / 100;
    var font = my.font || shop.font || '', all = my.font ? !!my.all : !!shop.all;
    var tlight = my.tlight || shop.tlight, tcolor = my.tcolor || shop.tcolor || '';
    var css = '';
    var pi = PATTERNS[pat][1](c2), busy = pat !== 'solid' || !!photo;
    if (pat !== 'solid') css += 'body{background-image:' + pi[0] + ';background-size:' + pi[1] + '}';
    if (busy){
      var x = rgb(bgc).join(',');
      css += ':root{--banner:rgba(' + x + ',.86)!important;--tab-bg:rgba(' + x + ',.9)!important}.side-open{background:rgba(' + x + ',.9)}.tabsrow,.loadnote{text-shadow:0 0 8px rgb(' + x + ')}';
    }
    if (font){ BS.bsLoadFonts([font]); css += ':root{--font-display:' + FONTS[font][1] + (all ? ';--font-body:' + FONTS[font][1] : '') + '}'; }
    if (tlight) css += '.mark,.step-h,.side-head h2,.ownh{font-weight:500!important}' + (all ? 'body{font-weight:400}.btn,.tab,.side-open,label{font-weight:500!important}' : '');
    if (tcolor){
      var on = readable(tcolor, bgc, 3);
      css += ':root{--on-bg:' + on + '!important;--on-bg-muted:' + mix(on, bgc, .2) + '!important}.step-h,.ownh,.side-head h2{color:' + readable(tcolor, surface, 3) + '}';
    }
    var st = document.getElementById('bs-look'); if (!st){ st = document.createElement('style'); st.id = 'bs-look'; document.head.appendChild(st); }
    st.textContent = css;
    var ph = document.getElementById('bs-photo');
    if (photo && document.body){
      if (!ph || !ph.firstChild){ if (ph) ph.remove(); ph = document.createElement('div'); ph.id = 'bs-photo'; ph.setAttribute('aria-hidden', 'true'); ph.style.cssText = 'position:fixed;inset:0;z-index:-1;overflow:hidden;pointer-events:none'; var pin = document.createElement('div'); pin.style.cssText = 'position:absolute;inset:0;background-size:cover;background-repeat:no-repeat'; ph.appendChild(pin); document.body.prepend(ph); }
      var a = (fade / 100).toFixed(2), xx = rgb(bgc).join(','), img = ph.firstChild;
      ph.style.backgroundColor = 'rgb(' + xx + ')';
      img.style.backgroundImage = 'linear-gradient(rgba(' + xx + ',' + a + '),rgba(' + xx + ',' + a + ')),url("' + photo + '")';
      img.style.backgroundPosition = ppos; img.style.transformOrigin = ppos; img.style.transform = pzoom > 1 ? 'scale(' + pzoom + ')' : '';
    } else if (ph) ph.remove();
  };

  /* Shrink a picked photo so it loads fast and fits in storage */
  BS.bsShrinkPhoto = function(file, maxSide, q){
    return new Promise(function(res, rej){
      var url = URL.createObjectURL(file), img = new Image();
      img.onload = function(){ var k = Math.min(1, maxSide / Math.max(img.naturalWidth, img.naturalHeight)), c = document.createElement('canvas'); c.width = Math.round(img.naturalWidth * k); c.height = Math.round(img.naturalHeight * k); c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); URL.revokeObjectURL(url); res(c.toDataURL('image/jpeg', q)); };
      img.onerror = function(){ URL.revokeObjectURL(url); rej(new Error('read')); };
      img.src = url;
    });
  };

  /* Controls shared by the owner drawer and the customer drawer.
     get() returns the current settings object; set(patch) updates and repaints. */
  var BG_COLORS = [['#5e1527', 'Classic maroon'], ['#0f1b33', 'Midnight'], ['#173a2b', 'Forest'], ['#1f1f22', 'Charcoal'], ['#0d3b4a', 'Ocean'], ['#2b1a4a', 'Royal'], ['#f4efe8', 'Light'], ['#ffffff', 'White'], ['#ff8243', 'Orange'], ['#111111', 'Black']];
  var C2_COLORS = [['#ffffff', 'White'], ['#111111', 'Black'], ['#c4222b', 'Red'], ['#1c3d7a', 'Blue'], ['#d9a441', 'Gold'], ['#40c4b8', 'Teal'], ['#f2a7b8', 'Pink'], ['#2f6b52', 'Green'], ['#ff8243', 'Orange']];
  var TEXT_COLORS = [['', 'Standard'], ['#ffffff', 'White'], ['#111111', 'Black'], ['#d9a441', 'Gold'], ['#c4222b', 'Red'], ['#1c3d7a', 'Blue'], ['#2f6b52', 'Green'], ['#f2a7b8', 'Pink'], ['#40c4b8', 'Teal'], ['#ff8243', 'Orange']];
  var esc = function(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  function swatchRow(name, list, cur, std){
    cur = cur || std || '';
    return '<div class="lk-sw" role="group" aria-label="' + esc(name) + '">' + list.map(function(p){
      var c = p[0];
      return '<button type="button" class="lk-dot" data-v="' + c + '" aria-label="' + esc(p[1]) + '" aria-pressed="' + (c === cur) + '" style="background:' + (c || 'conic-gradient(#0f1a2e 0 50%,#ffffff 0)') + '"></button>';
    }).join('') + '<label class="lk-dot lk-any"' + (cur && !list.some(function(p){ return p[0] === cur; }) ? ' data-on="1" style="background:' + cur + '"' : '') + ' title="Pick any color"><input type="color" value="' + (cur || '#ffffff') + '" aria-label="Pick any color"></label></div>';
  }
  BS.bsLookControls = function(box, opts){
    var get = opts.get, set = opts.set;
    function draw(){
      var v = get(), pat = v.pattern || 'solid', bgc = v.bg || opts.bgNow() || '#5e1527', c2 = v.c2 || '#ffffff';
      BS.bsLoadFonts(Object.keys(FONTS));
      box.innerHTML =
        (opts.mainColor ? '<div class="lk-sec"><p class="lk-h">Main color</p>' + swatchRow('Main color', BG_COLORS, v.bg, '') + '</div>' : '') +
        '<div class="lk-sec"><p class="lk-h">Background style</p><div class="lk-chips" data-k="pattern">' + Object.keys(PATTERNS).map(function(k){
          var pi = PATTERNS[k][1](c2);
          return '<button type="button" data-v="' + k + '" aria-pressed="' + (k === pat) + '"><span aria-hidden="true" style="background-color:' + bgc + ';background-image:' + pi[0] + ';background-size:' + (pi[1] === 'auto' ? 'auto' : '10px 10px') + '"></span>' + esc(PATTERNS[k][0]) + '</button>';
        }).join('') + '</div></div>' +
        (pat !== 'solid' ? '<div class="lk-sec" data-k="c2"><p class="lk-h">Second color</p>' + swatchRow('Second color', C2_COLORS, v.c2, '#ffffff') + '</div>' : '') +
        '<div class="lk-sec"><p class="lk-h">Text style</p><div class="lk-chips lk-fonts" data-k="font">' + Object.keys(FONTS).map(function(k){
          return '<button type="button" data-v="' + k + '" aria-pressed="' + ((v.font || 'std') === k) + '" style="' + (FONTS[k][1] ? 'font-family:' + FONTS[k][1] : '') + '">' + esc(FONTS[k][0]) + '</button>';
        }).join('') + '</div>' +
        '<label class="lk-check"><input type="checkbox" data-k="all"' + (v.all ? ' checked' : '') + '> Use this style for all words, not just titles</label>' +
        '<label class="lk-check"><input type="checkbox" data-k="bold"' + (v.tlight ? '' : ' checked') + '> Bold words</label></div>' +
        '<div class="lk-sec" data-k="tcolor"><p class="lk-h">Text color</p>' + swatchRow('Text color', TEXT_COLORS, v.tcolor, '') +
        '<p class="hint" style="margin-top:6px">If a color is hard to read on the background, it gets darkened or lightened a little.</p></div>' +
        '<div class="lk-sec"><p class="lk-h">Photo behind the page</p>' +
        (v.photo ?
          '<div class="lk-now"><img src="' + esc(v.photo) + '" alt="Current background photo" style="object-position:' + (v.px || 'center') + ' ' + (v.py || 'center') + '">' +
          '<div class="lk-photo-btns"><label class="btn ghost small lk-up">Change photo<input type="file" accept="image/*" data-act="up"></label>' +
          '<button type="button" class="btn ghost small" data-act="rm">Delete photo</button></div></div>' +
          '<p class="lk-h" style="margin-top:6px">Edit photo</p>' +
          '<div class="lk-chips" data-k="py" role="group" aria-label="Show which part, top to bottom">' + [['top', 'Show top'], ['', 'Middle'], ['bottom', 'Show bottom']].map(function(o){ return '<button type="button" data-v="' + o[0] + '" aria-pressed="' + ((v.py || '') === o[0]) + '">' + o[1] + '</button>'; }).join('') + '</div>' +
          '<div class="lk-chips" data-k="px" role="group" aria-label="Show which part, left to right">' + [['left', 'Show left'], ['', 'Center'], ['right', 'Show right']].map(function(o){ return '<button type="button" data-v="' + o[0] + '" aria-pressed="' + ((v.px || '') === o[0]) + '">' + o[1] + '</button>'; }).join('') + '</div>' +
          '<label class="lk-h" style="margin-top:6px;display:flex;justify-content:space-between">Zoom <span>' + (v.zoom || 100) + '%</span></label><input type="range" min="100" max="250" step="5" data-k="zoom" value="' + (v.zoom || 100) + '" aria-label="Zoom">' +
          '<label class="lk-h" style="margin-top:6px;display:flex;justify-content:space-between">Color over the photo <span>' + (v.fade == null ? 45 : v.fade) + '%</span></label><input type="range" min="0" max="85" data-k="fade" value="' + (v.fade == null ? 45 : v.fade) + '" aria-label="Color over the photo"><p class="hint">More color makes words easier to read.</p>' +
          '<button type="button" class="btn ghost small" data-act="reset" style="align-self:flex-start">Undo photo edits</button>'
        : '<label class="btn ghost small lk-up">Add a photo<input type="file" accept="image/*" data-act="up"></label>') +
        '<p class="msg" data-photo-msg role="alert"></p></div>';
    }
    box.addEventListener('click', function(e){
      var b = e.target.closest('button'); if (!b || !box.contains(b)) return;
      if (b.dataset.act === 'rm'){
        if (b.dataset.sure !== '1'){ b.dataset.sure = '1'; b.textContent = 'Tap again to delete'; setTimeout(function(){ if (b.isConnected){ b.dataset.sure = ''; b.textContent = 'Delete photo'; } }, 4000); return; }
        set({ photo: '', fade: '', px: '', py: '', zoom: '' }); draw(); var m0 = box.querySelector('[data-photo-msg]'); if (m0) m0.textContent = 'Photo deleted.'; return;
      }
      if (b.dataset.act === 'reset'){ set({ px: '', py: '', zoom: '', fade: 45 }); draw(); return; }
      var pg = b.closest('[data-k="px"],[data-k="py"]');
      if (pg){ var pk = pg.dataset.k, pv = b.dataset.v; set(JSON.parse('{"' + pk + '":"' + pv + '"}')); draw(); var again2 = box.querySelector('[data-k="' + pk + '"] [data-v="' + pv + '"]'); if (again2) again2.focus(); return; }
      var grp = b.closest('[data-k]'), dot = b.classList.contains('lk-dot');
      if (dot){
        var sec = b.closest('.lk-sec'), key = sec && sec.dataset.k ? sec.dataset.k : (opts.mainColor && sec === box.querySelector('.lk-sec') ? 'bg' : '');
        if (!key) return; set(JSON.parse('{"' + key + '":"' + b.dataset.v + '"}')); draw();
        var again = box.querySelector((key === 'bg' ? '.lk-sec:first-child' : '[data-k="' + key + '"]') + ' [data-v="' + b.dataset.v + '"]'); if (again) again.focus(); return;
      }
      if (grp && grp.dataset.k === 'pattern'){ set({ pattern: b.dataset.v === 'solid' ? '' : b.dataset.v, c2: get().c2 || '#ffffff' }); draw(); box.querySelector('[data-k="pattern"] [data-v="' + b.dataset.v + '"]').focus(); return; }
      if (grp && grp.dataset.k === 'font'){ set({ font: b.dataset.v === 'std' ? '' : b.dataset.v }); draw(); box.querySelector('[data-k="font"] [data-v="' + b.dataset.v + '"]').focus(); }
    });
    box.addEventListener('change', async function(e){
      var t = e.target;
      if (t.dataset.k === 'all'){ set({ all: t.checked }); return; }
      if (t.dataset.k === 'bold'){ set({ tlight: !t.checked }); return; }
      if (t.type === 'color'){ draw(); return; }
      if (t.dataset.act === 'up'){
        var f = t.files[0]; t.value = ''; if (!f) return;
        var m = box.querySelector('[data-photo-msg]');
        if (!/^image\//.test(f.type)){ m.textContent = 'Pick a photo.'; return; }
        m.textContent = 'Adding your photo…';
        try { var url = await BS.bsShrinkPhoto(f, opts.photoSize || 1200, opts.upload ? .8 : .65); if (opts.upload){ m.textContent = 'Uploading your photo…'; try { url = await opts.upload(url); } catch(upErr){ m.textContent = 'Could not upload the photo. Run setup-all.sql in Supabase, then try again.'; return; } } if (set({ photo: url, fade: get().fade == null ? 45 : get().fade, px: '', py: '', zoom: '' }) === false){ m.textContent = 'That photo is too big to save. Try a smaller one.'; return; } draw(); }
        catch(err){ m.textContent = "That photo didn't open. Try another one."; }
      }
    });
    box.addEventListener('input', function(e){
      var t = e.target;
      if (t.type === 'color'){
        var sec = t.closest('.lk-sec'), key = sec.dataset.k || 'bg', c = hexOk(t.value); if (!c) return;
        var l = t.closest('label'); l.dataset.on = '1'; l.style.background = c; sec.querySelectorAll('.lk-dot[data-v]').forEach(function(d){ d.setAttribute('aria-pressed', 'false'); });
        set(JSON.parse('{"' + key + '":"' + c + '"}')); return;
      }
      if (t.dataset.k === 'zoom'){ set({ zoom: +t.value > 100 ? +t.value : '' }); var zs = t.previousElementSibling && t.previousElementSibling.querySelector('span'); if (zs) zs.textContent = t.value + '%'; return; }
      if (t.dataset.k === 'fade'){ set({ fade: +t.value }); var s = t.previousElementSibling && t.previousElementSibling.querySelector('span'); if (s) s.textContent = t.value + '%'; }
    });
    draw();
    return { draw: draw };
  };

  /* First paint: shop look from this device's cache plus the customer's own look */
  try { localStorage.removeItem('bs.colors'); BS.bsShopRaw = JSON.parse(localStorage.getItem('bs.shoptheme') || 'null'); } catch(e){}
  BS.bsRender();
  document.addEventListener('DOMContentLoaded', function(){ BS.bsRender(); });
})();

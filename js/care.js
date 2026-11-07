'use strict';
/*
 * Уход за лошадью в виде мини-игр:
 *  - расчесать: води щёткой по лошади, пока не исчезнет вся пыль;
 *  - помыть: сначала намыль губкой (пена), потом смой водой из шланга;
 *  - подковать: на каждое из четырёх копыт забей по три гвоздика — жми, когда молоточек над зелёной зоной.
 */
const Care = (() => {
  let box = null, cv = null, ctx = null, game = null, raf = 0;
  const $ = id => document.getElementById(id);

  function ensure() {
    if (box) return;
    box = document.createElement('div');
    box.id = 'care';
    box.className = 'hidden';
    box.innerHTML = `<div class="care-box">
      <div class="modal-head"><h2 id="care-title"></h2><button id="care-close" class="x" title="Закрыть">✕</button></div>
      <p id="care-hint"></p>
      <canvas id="care-canvas" width="560" height="320"></canvas>
      <div class="care-bar"><div id="care-progress"></div></div>
      <div class="row center"><button id="care-btn" class="btn big orange hidden"></button></div>
    </div>`;
    document.body.appendChild(box);
    cv = $('care-canvas');
    ctx = cv.getContext('2d');
    $('care-close').onclick = () => close(false);
    const pos = e => {
      const r = cv.getBoundingClientRect();
      return { x: (e.clientX - r.left) * cv.width / r.width, y: (e.clientY - r.top) * cv.height / r.height };
    };
    let down = false;
    cv.addEventListener('pointerdown', e => { down = true; cv.setPointerCapture?.(e.pointerId); if (game && game.down) game.down(pos(e)); if (game && game.move) game.move(pos(e)); });
    cv.addEventListener('pointermove', e => { if (game && game.hover) game.hover(pos(e)); if (down && game && game.move) game.move(pos(e)); });
    addEventListener('pointerup', () => { down = false; });
    $('care-btn').onclick = () => game && game.button && game.button();
    addEventListener('keydown', e => {
      if (!game || box.classList.contains('hidden')) return;
      if (e.code === 'Space' || e.code === 'Enter') { e.preventDefault(); e.stopPropagation(); if (game.button) game.button(); }
      if (e.code === 'Escape') close(false);
    }, true);
  }

  const isOpen = () => !!(box && !box.classList.contains('hidden'));
  function close(done) {
    cancelAnimationFrame(raf);
    box.classList.add('hidden');
    document.body.classList.remove('modal-open');
    const g = game;
    game = null;
    if (done && g && g.onDone) g.onDone(g.score || 0);
  }

  // картинка лошади для мини-игры (портрет из 3D)
  function horsePic(h) {
    const c = document.createElement('canvas');
    c.width = 560; c.height = 320;
    Voxel.portrait(c, h);
    return c;
  }

  // слой «грязи» или «пены»: доля закрашенного считается по сетке
  function coverLayer(color, n, rx, rnd, shape) {
    const c = document.createElement('canvas');
    c.width = 560; c.height = 320;
    const g = c.getContext('2d');
    for (let i = 0; i < n; i++) {
      const x = 160 + rnd() * 300, y = 90 + rnd() * 130, r = rx * (0.6 + rnd() * 0.8);
      g.fillStyle = typeof color === 'function' ? color(rnd) : color;
      g.beginPath();
      if (shape === 'bubble') { g.arc(x, y, r * 0.5, 0, Math.PI * 2); } else g.ellipse(x, y, r, r * 0.7, rnd() * 3, 0, Math.PI * 2);
      g.fill();
    }
    return c;
  }
  function coverage(layer) {
    const d = layer.getContext('2d').getImageData(0, 0, layer.width, layer.height).data;
    let on = 0, tot = 0;
    for (let y = 0; y < layer.height; y += 8) for (let x = 0; x < layer.width; x += 8) { tot++; if (d[(y * layer.width + x) * 4 + 3] > 40) on++; }
    return on / tot;
  }
  function erase(layer, p, r) {
    const g = layer.getContext('2d');
    g.save(); g.globalCompositeOperation = 'destination-out';
    g.beginPath(); g.arc(p.x, p.y, r, 0, Math.PI * 2); g.fill(); g.restore();
  }

  function setProgress(v) { $('care-progress').style.width = `${Math.round(Math.max(0, Math.min(1, v)) * 100)}%`; }
  function button(text) { const b = $('care-btn'); b.classList.toggle('hidden', !text); if (text) b.textContent = text; }

  /* ---------- расчесать ---------- */
  function brushGame(h, onDone) {
    const rnd = World.rng(h.seed + 77);
    const pic = horsePic(h);
    const dust = coverLayer(r => ['rgba(139,101,60,0.85)', 'rgba(120,90,55,0.8)', 'rgba(160,125,80,0.8)'][Math.floor(r() * 3)], 26, 34, rnd);
    const start = coverage(dust);
    let cursor = null, prog = 0, sparkles = [];
    const g = {
      onDone, score: 0,
      hover: p => { cursor = p; },
      move: p => {
        cursor = p;
        erase(dust, p, 30);
        if (Math.random() < 0.3) sparkles.push({ x: p.x + (Math.random() - 0.5) * 40, y: p.y + (Math.random() - 0.5) * 30, t: 0 });
      },
      button: () => { if (prog >= 0.92) close(true); },
      draw() {
        const left = coverage(dust) / Math.max(0.01, start);
        prog = 1 - left;
        setProgress(prog);
        ctx.fillStyle = '#fff3dc'; ctx.fillRect(0, 0, 560, 320);
        ctx.drawImage(pic, 0, 0);
        ctx.drawImage(dust, 0, 0);
        sparkles = sparkles.filter(s => (s.t += 0.03) < 1);
        for (const s of sparkles) { ctx.globalAlpha = 1 - s.t; ctx.fillStyle = '#fff59a'; ctx.fillText('✨', s.x, s.y - s.t * 20); }
        ctx.globalAlpha = 1;
        if (cursor) { ctx.font = '38px system-ui'; ctx.fillText('🪮', cursor.x - 18, cursor.y + 12); }
        if (prog >= 0.92) { g.score = 1; button('✨ Готово! Лошадь блестит'); }
      },
    };
    return { title: `🪮 Расчесать: ${h.name}`, hint: 'Води щёткой (мышкой или пальцем) по лошади, пока не исчезнет вся пыль', game: g };
  }

  /* ---------- помыть ---------- */
  function washGame(h, onDone) {
    const rnd = World.rng(h.seed + 91);
    const pic = horsePic(h);
    const dirt = coverLayer('rgba(110,80,45,0.75)', 18, 30, rnd);
    const foam = document.createElement('canvas'); foam.width = 560; foam.height = 320;
    const fg = foam.getContext('2d');
    let step = 'soap', cursor = null, soapT = 0, drops = [];
    const g = {
      onDone, score: 0,
      hover: p => { cursor = p; },
      move: p => {
        cursor = p;
        if (step === 'soap') {
          if (p.x < 140 || p.x > 480 || p.y < 60 || p.y > 250) return;
          for (let i = 0; i < 3; i++) {
            fg.fillStyle = ['rgba(255,255,255,0.95)', 'rgba(230,245,255,0.95)', 'rgba(255,240,250,0.9)'][i];
            fg.beginPath(); fg.arc(p.x + (Math.random() - 0.5) * 34, p.y + (Math.random() - 0.5) * 26, 6 + Math.random() * 10, 0, Math.PI * 2); fg.fill();
          }
          erase(dirt, p, 18);
          soapT++;
        } else if (step === 'rinse') {
          erase(foam, p, 34); erase(dirt, p, 34);
          for (let i = 0; i < 3; i++) drops.push({ x: p.x + (Math.random() - 0.5) * 30, y: p.y, v: 2 + Math.random() * 3 });
        }
      },
      button: () => {
        if (step === 'soap' && soapT > 70) { step = 'rinse'; hint('Теперь смой пену водой из шланга 🚿 — води по лошади'); button(null); }
        else if (step === 'done') close(true);
      },
      draw() {
        ctx.fillStyle = '#e7f5ff'; ctx.fillRect(0, 0, 560, 320);
        ctx.fillStyle = '#a5d8ff'; ctx.fillRect(0, 270, 560, 50);
        ctx.drawImage(pic, 0, 0);
        ctx.drawImage(dirt, 0, 0);
        ctx.drawImage(foam, 0, 0);
        drops = drops.filter(d => (d.y += d.v) < 330);
        ctx.fillStyle = 'rgba(77,171,247,0.85)';
        for (const d of drops) ctx.fillRect(d.x, d.y, 3, 7);
        ctx.font = '38px system-ui';
        if (cursor) ctx.fillText(step === 'soap' ? '🧽' : step === 'rinse' ? '🚿' : '', cursor.x - 18, cursor.y + 12);
        if (step === 'soap') {
          setProgress(Math.min(1, soapT / 70) * 0.5);
          if (soapT > 70) button('🚿 Смыть пену');
        } else if (step === 'rinse') {
          const left = coverage(foam);
          setProgress(0.5 + (1 - Math.min(1, left / 0.25)) * 0.5);
          if (left < 0.015) { step = 'done'; g.score = 1; button('✨ Готово! Чистая и мокрая'); hint('Лошадь чистая! Она немного мокрая — скоро высохнет'); }
        }
      },
    };
    return { title: `🛁 Помыть: ${h.name}`, hint: 'Намыль лошадь губкой 🧽 — води по ней, чтобы появилась пена', game: g };
  }

  /* ---------- подковать ---------- */
  function shoeGame(h, onDone) {
    const pic = horsePic(h);
    const HOOVES = ['левое переднее', 'правое переднее', 'левое заднее', 'правое заднее'];
    let hoof = 0, nail = 0, hits = 0, pos = 0, dir = 1, flash = 0, flashOk = false, zone = { c: 0.5, w: 0.2 }, done = false;
    const newZone = () => { zone = { c: 0.2 + Math.random() * 0.6, w: 0.16 + Math.random() * 0.08 }; };
    newZone();
    const g = {
      onDone, score: 0,
      button: () => {
        if (done) { close(true); return; }
        const ok = Math.abs(pos - zone.c) < zone.w / 2;
        flash = 1; flashOk = ok;
        if (ok) { hits++; Sound.tick(); } else Sound.thud();
        nail++;
        if (nail >= 3) { nail = 0; hoof++; }
        if (hoof >= 4) { done = true; g.score = hits / 12; button(`🔧 Готово! Попаданий: ${hits} из 12`); hint(hits >= 9 ? 'Отличная работа, как у настоящего кузнеца!' : 'Подковы на месте. В следующий раз получится ещё ровнее!'); return; }
        newZone();
      },
      draw() {
        ctx.fillStyle = '#f1e3c6'; ctx.fillRect(0, 0, 560, 320);
        ctx.drawImage(pic, 0, -20, 560, 320);
        if (!done) {
          pos += dir * 0.018 * (1 + hoof * 0.15);
          if (pos > 1) { pos = 1; dir = -1; } if (pos < 0) { pos = 0; dir = 1; }
        }
        // шкала
        const bx = 60, by = 262, bw = 440, bh = 30;
        ctx.fillStyle = '#ffc9c9'; ctx.fillRect(bx, by, bw, bh);
        ctx.fillStyle = '#69db7c'; ctx.fillRect(bx + (zone.c - zone.w / 2) * bw, by, zone.w * bw, bh);
        ctx.strokeStyle = '#6b4423'; ctx.lineWidth = 3; ctx.strokeRect(bx, by, bw, bh);
        ctx.font = '34px system-ui';
        ctx.fillText('🔨', bx + pos * bw - 17, by - 4);
        if (flash > 0) { ctx.globalAlpha = flash; ctx.fillStyle = flashOk ? '#2b8a3e' : '#c92a2a'; ctx.font = 'bold 28px system-ui'; ctx.fillText(flashOk ? 'Тук! Ровно!' : 'Мимо!', 220, 60); ctx.globalAlpha = 1; flash = Math.max(0, flash - 0.03); }
        ctx.fillStyle = '#3b2a1a'; ctx.font = 'bold 18px system-ui';
        if (!done) ctx.fillText(`Копыто: ${HOOVES[hoof]} · гвоздик ${nail + 1} из 3`, 120, 30);
        for (let i = 0; i < 4; i++) { ctx.font = '26px system-ui'; ctx.fillText(i < hoof || done ? '🧲' : '⚪', 420 + i * 32, 32); }
        setProgress((hoof * 3 + nail) / 12);
      },
    };
    return { title: `🔧 Подковать: ${h.name}`, hint: 'Жми «Забить гвоздь» (или Пробел), когда молоточек над зелёной зоной', game: g, btn: '🔨 Забить гвоздь' };
  }

  function hint(t) { $('care-hint').textContent = t; }

  function open(kind, h, onDone) {
    ensure();
    const def = kind === 'brush' ? brushGame(h, onDone) : kind === 'wash' ? washGame(h, onDone) : shoeGame(h, onDone);
    game = def.game;
    $('care-title').textContent = def.title;
    hint(def.hint);
    button(def.btn || null);
    setProgress(0);
    box.classList.remove('hidden');
    document.body.classList.add('modal-open');
    ctx.font = '22px system-ui';
    const loop = () => { if (!game) return; game.draw(); raf = requestAnimationFrame(loop); };
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(loop);
  }

  return { open, isOpen, close };
})();

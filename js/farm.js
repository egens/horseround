'use strict';
/*
 * Строительство и фермерство, металлоискатель и клады, сбор грибов.
 * Постройки хранятся в S.builds, грядки — это постройки с урожаем.
 */
const Farm = (() => {
  let G = null;
  const rand = (a, b) => a + Math.random() * (b - a);
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const B = () => Items.BUILDS;

  let mode = null;            // режим стройки: { type, rot, x, y, ok } или { remove: true }
  let spots = [];             // где зарыты клады
  let beepT = 0, signal = 0, near = null;
  const picked = new Map();   // сорванные грибы: id → когда вырастут снова
  let toadWarnT = 0;

  function init(api) {
    G = api;
    const S = G.S;
    S.builds = S.builds || [];
    S.flags = S.flags || {};
    syncSolids();
    while (spots.length < 14) spots.push(newSpot());
  }

  /* ================= постройки ================= */
  function dims(type, rot) {
    const d = B()[type];
    return rot ? { w: d.h, h: d.w } : { w: d.w, h: d.h };
  }
  function rectOf(b) {
    const d = dims(b.type, b.rot);
    return { x: b.x - d.w / 2, y: b.y - d.h / 2, w: d.w, h: d.h };
  }
  // стены маленькой конюшни: сзади и по бокам, спереди открыто
  function stableWalls(b) {
    const r = rectOf(b), t = 10;
    return [{ x: r.x, y: r.y, w: r.w, h: t }, { x: r.x, y: r.y, w: t, h: r.h }, { x: r.x + r.w - t, y: r.y, w: t, h: r.h }];
  }
  function syncSolids() {
    const list = World.BUILD_SOLIDS;
    list.length = 0;
    for (const b of G.S.builds) {
      if (b.type === 'stable5') list.push(...stableWalls(b));
      else if (B()[b.type].solid) list.push(rectOf(b));
    }
  }

  const NO_BUILD = () => [World.STABLE, World.ARENA, World.JUMPF, World.PADDOCK, World.MOUNTAIN, World.SELL, World.SHOP]
    .concat(World.ISLANDS.flatMap(I => [I.stable, I.pasture, { x: I.pen.x - I.pen.r, y: I.pen.y - I.pen.r, w: I.pen.r * 2, h: I.pen.r * 2 }, { x: I.pier.x - 240, y: I.pier.y - 80, w: 360, h: 160 }]))
    .concat([{ x: World.PIER.x - 80, y: World.PIER.y - 80, w: 360, h: 160 }]);
  function canPlace(type, x, y, rot) {
    const d = dims(type, rot);
    const r = { x: x - d.w / 2, y: y - d.h / 2, w: d.w, h: d.h };
    if (r.x < 20 || r.y < 20 || r.x + r.w > World.W - 20 || r.y + r.h > World.H - 20) return false;
    const over = (a, q, m = 0) => a.x < q.x + q.w + m && a.x + a.w + m > q.x && a.y < q.y + q.h + m && a.y + a.h + m > q.y;
    if (NO_BUILD().some(q => over(r, q, 20))) return false;
    if (G.S.builds.some(b => over(r, rectOf(b), 4))) return false;
    // деревья внутри площадки
    for (let i = 0; i <= Math.ceil(r.w / 150); i++) for (let j = 0; j <= Math.ceil(r.h / 150); j++) {
      for (const t of World.treesNear(r.x + i * 150, r.y + j * 150)) if (World.inRect(t.x, t.y, r, (t.cr || 9) + 4)) return false;
    }
    // проверяем сеткой точек: вода, деревья, стены
    for (let i = 0; i <= 4; i++) for (let j = 0; j <= 4; j++) {
      if (World.blocked(r.x + r.w * i / 4, r.y + r.h * j / 4, 6)) return false;
    }
    const p = G.S.player;
    if (type !== 'bed' && type !== 'flowerbed' && type !== 'stable5' && Math.abs(p.x - x) < d.w / 2 + 12 && Math.abs(p.y - y) < d.h / 2 + 12) return false;
    return true;
  }

  function startBuild(type) {
    UI.closeModal();
    const p = G.S.player;
    mode = { type, rot: 0, x: p.x + Math.cos(p.angle) * 90, y: p.y + Math.sin(p.angle) * 90 };
    mode.ok = canPlace(type, mode.x, mode.y, 0);
    UI.toast(`🔨 ${B()[type].name}: наведи и нажми, чтобы поставить. R — повернуть, Esc — отмена`);
  }
  function startRemove() {
    UI.closeModal();
    mode = { remove: true, x: G.S.player.x, y: G.S.player.y };
    UI.toast('🧹 Нажми на постройку, чтобы убрать её (вернётся половина цены). Esc — выход');
  }
  function cancel() { mode = null; }
  function rotate() { if (mode && !mode.remove) { mode.rot = mode.rot ? 0 : 1; mode.ok = canPlace(mode.type, mode.x, mode.y, mode.rot); } }
  function hover(x, y) {
    if (!mode) return;
    const snap = v => Math.round(v / 10) * 10;
    mode.x = snap(x); mode.y = snap(y);
    if (!mode.remove) mode.ok = canPlace(mode.type, mode.x, mode.y, mode.rot);
  }
  function buildAt(x, y) {
    if (!mode) return false;
    hover(x, y);
    const S = G.S;
    if (mode.remove) {
      const b = S.builds.find(q => World.inRect(x, y, rectOf(q), 6));
      if (!b) { UI.toast('Здесь нет твоей постройки'); return true; }
      if (b.type === 'stable5' && stallHorses(b).length) { UI.toast('В этой конюшне живут лошади — сначала продай их или освободи денники', 'warn'); return true; }
      S.builds = S.builds.filter(q => q !== b);
      const back = Math.floor(B()[b.type].price / 2);
      S.money += back;
      syncSolids();
      UI.toast(`${B()[b.type].name} убрана, +${back} 🪙`);
      Sound.tick();
      return true;
    }
    const d = B()[mode.type];
    if (!mode.ok) { UI.toast('Сюда поставить нельзя', 'warn'); Sound.fail(); return true; }
    if (S.money < d.price) { UI.toast('Не хватает монет', 'warn'); return true; }
    S.money -= d.price;
    const b = { id: (S.buildId = (S.buildId || 0) + 1), type: mode.type, x: mode.x, y: mode.y, rot: mode.rot };
    if (b.type === 'bed') Object.assign(b, { crop: null, grow: 0, wet: 0 });
    if (b.type === 'tree') b.t = 60;
    S.builds.push(b);
    syncSolids();
    G.stat('built_total');
    if (b.type === 'bed') G.stat('built_bed');
    G.float(`🔨 ${d.name}`, b.x, b.y - 30, '#1b8a3a');
    Sound.coin();
    mode.ok = canPlace(mode.type, mode.x, mode.y, mode.rot);
    return true;
  }

  /* ---------- денники маленьких конюшен ---------- */
  const stables5 = () => G.S.builds.filter(b => b.type === 'stable5').sort((a, b) => a.id - b.id);
  const maxStalls = () => 20 + stables5().length * 5;
  function extraSpot(i) {
    const st = stables5()[Math.floor((i - 20) / 5)];
    if (!st) return null;
    const r = rectOf(st), k = (i - 20) % 5;
    if (st.rot) return { x: r.x + 75, y: r.y + 34 + k * 68, angle: 0 };
    return { x: r.x + 34 + k * 68, y: r.y + 72, angle: Math.PI / 2 };
  }
  function stallHorses(st) {
    const idx = stables5().indexOf(st);
    const from = 20 + idx * 5;
    return G.S.horses.filter(h => h.stall >= from && h.stall < from + 5);
  }
  // рядом с конюшней (главной или маленькой) можно ухаживать за лошадьми
  const nearStable = p => stables5().some(b => World.inRect(p.x, p.y, rectOf(b), 60));

  /* ================= огород ================= */
  function nearestBuild(types, r = 60) {
    const p = G.S.player;
    let best = null, bd = r;
    for (const b of G.S.builds) {
      if (!types.includes(b.type)) continue;
      const rr = rectOf(b);
      const dx = Math.max(rr.x - p.x, 0, p.x - rr.x - rr.w), dy = Math.max(rr.y - p.y, 0, p.y - rr.y - rr.h);
      const d = Math.hypot(dx, dy);
      if (d < bd) { bd = d; best = b; }
    }
    return best;
  }
  function plant(b, crop) {
    const c = Items.CROPS[crop], S = G.S;
    if (!(S.inv[c.seed] > 0)) return UI.toast(`Нет: ${Items.name(c.seed)}. Купи в повозке «Корм и амуниция»`, 'warn');
    S.inv[c.seed]--;
    Object.assign(b, { crop, grow: 0, wet: Math.max(b.wet, 0) });
    G.stat('planted');
    Sound.tick();
  }
  function water(b) { b.wet = 90; G.float('💧', b.x, b.y - 20, '#1c7ed6'); Sound.tick(); }
  function harvest(b) {
    if (!b.crop || b.grow < 1) return;
    const c = Items.CROPS[b.crop], S = G.S;
    const [item, n] = c.yield;
    S.inv[item] = (S.inv[item] || 0) + n;
    G.stat('harvest_total');
    G.stat('harvest_' + b.crop);
    G.float(`${Items.icon(item)} +${n}`, b.x, b.y - 30, '#1b8a3a');
    UI.toast(`🧺 Урожай: ${Items.name(item)} ×${n}`, 'good');
    b.crop = null; b.grow = 0;
    Sound.coin();
  }
  function stageOf(b) {
    if (!b.crop) return -1;
    return b.grow >= 1 ? 3 : b.grow >= 0.6 ? 2 : b.grow >= 0.25 ? 1 : 0;
  }

  function updateBuilds(dt) {
    const S = G.S, raining = Events.raining();
    const wells = S.builds.filter(b => b.type === 'well');
    for (const b of S.builds) {
      if (b.type === 'bed' && b.crop) {
        if (raining || wells.some(w => dist(w, b) < 240)) b.wet = Math.max(b.wet, 60);
        if (b.wet > 0 && b.grow < 1) {
          b.grow = Math.min(1, b.grow + dt / Items.CROPS[b.crop].time);
          if (b.grow >= 1) b.readyT = G.time();
        }
        b.wet = Math.max(0, b.wet - dt);
      }
      if (b.type === 'tree') b.t = Math.max(0, (b.t || 0) - dt);
    }
  }

  /* ================= клады ================= */
  function newSpot() {
    const areas = [
      [World.FIELD, 3], [World.LAKELAND, 3], [World.FOREST[0], 4], [World.FARMLAND, 1], [World.VILLAGE, 1],
      [World.MUSHROOM, 3], [World.CAVE, 2], [World.DESERT, 3], [World.TUNDRA, 3], [World.DEEPFOREST, 1],
      ...World.ISLANDS.map(I => [I.area, 1]),
    ];
    const total = areas.reduce((s, a) => s + a[1], 0);
    for (let tries = 0; tries < 80; tries++) {
      let r = Math.random() * total, area = areas[0][0];
      for (const [a, w] of areas) { r -= w; if (r <= 0) { area = a; break; } }
      const x = rand(area.x + 60, area.x + area.w - 60), y = rand(area.y + 60, area.y + area.h - 60);
      if (World.blocked(x, y, 20)) continue;
      return { x, y, cave: area === World.CAVE };
    }
    return { x: 2500, y: 1200 };
  }

  function updateDetector(dt) {
    const S = G.S, p = S.player;
    near = null; signal = 0;
    const targets = spots.slice();
    if (S.bigTreasure) targets.push(Object.assign({ big: true }, S.bigTreasure));
    if (!S.tack.detector || !p.detector) return;
    let bd = 450;
    for (const s of targets) { const d = dist(s, p); if (d < bd) { bd = d; near = s; } }
    if (!near) return;
    signal = 1 - bd / 450;
    beepT -= dt;
    if (beepT <= 0) {
      beepT = 1.3 - signal * 1.15;
      Sound.beep(400 + signal * 900);
    }
  }
  const canDig = () => !!(near && dist(near, G.S.player) < 45);

  function dig() {
    const S = G.S, s = near;
    if (!s || !canDig()) return;
    if (s.big) {
      S.bigTreasure = null;
      give('money', 250); give('dye_rainbow', 1); give('brooch', 1);
      UI.toast('🗝️ Ты нашла большой клад по карте! 250 монет, радужная краска и брошь!', 'good');
      Sound.fanfare();
    } else {
      spots = spots.filter(q => q !== s);
      setTimeout(() => spots.push(newSpot()), 20000);
      const r = Math.random() + (s.cave ? 0.15 : 0);
      let text;
      if (r < 0.33) { const c = Math.round(rand(15, 50)); give('money', c); text = `${c} монет 🪙`; }
      else if (r < 0.48) text = give('oldShoe', 1);
      else if (r < 0.58) text = give('oldCoin', 1);
      else if (r < 0.65) text = give('spoon', 1);
      else if (r < 0.71) text = give('bell', 1);
      else if (r < 0.78) text = give(['seed_carrot', 'seed_pumpkin', 'seed_sunflower', 'seed_oats'][Math.floor(Math.random() * 4)], 3);
      else if (r < 0.85) text = give(['dye_pink', 'dye_blue', 'dye_purple', 'dye_mint'][Math.floor(Math.random() * 4)], 1);
      else if (r < 0.9) text = give('brooch', 1);
      else if (r < 0.94) text = give('seed_magic', 1);
      else if (r < 0.98 || S.bigTreasure) text = give('goldShoe', 1);
      else {
        let p = null;
        for (let i = 0; i < 50 && !p; i++) { const q = newSpot(); if (dist(q, S.player) > 1500) p = q; }
        S.bigTreasure = p || newSpot();
        text = give('map', 1) + ' — на миникарте появился крестик ✖';
      }
      UI.toast(`⛏️ Клад! Ты нашла: ${text}`, 'good');
      Sound.coin();
    }
    G.stat('treasures');
    G.float('⛏️', s.x, s.y - 20, '#b07800');
    near = null;
  }
  function give(item, n) {
    const S = G.S;
    if (item === 'money') { S.money += n; return `${n} 🪙`; }
    S.inv[item] = (S.inv[item] || 0) + n;
    return `${Items.icon(item)} ${Items.name(item)}${n > 1 ? ' ×' + n : ''}`;
  }

  /* ================= грибы ================= */
  function updateShrooms(dt) {
    const S = G.S, p = S.player, t = G.time();
    for (const [id, at] of picked) if (t > at) picked.delete(id);
    if (G.mounted() || p.fly) return;
    for (const m of World.SHROOMS) {
      if (Math.abs(m.x - p.x) > 22 || Math.abs(m.y - p.y) > 22 || picked.has(m.id)) continue;
      if (m.type === 'amanita') {
        if (t > toadWarnT) { toadWarnT = t + 8; UI.toast('🍄 Это мухомор — он ядовитый, его не собираем!'); }
        continue;
      }
      picked.set(m.id, t + 300);
      const item = m.type === 'glow' || m.type === 'violet' ? 'glowshroom' : 'mushroom';
      S.inv[item] = (S.inv[item] || 0) + 1;
      G.stat('mushrooms');
      G.float(`${Items.icon(item)} +1`, m.x, m.y - 20, '#1b8a3a');
      Sound.tick();
    }
  }
  const shroomPicked = id => picked.has(id);

  /* ================= подсказки ================= */
  function prompt() {
    const S = G.S, p = S.player;
    if (mode) return null;
    if (canDig()) return { label: '⛏️ Копать клад', fn: dig };
    if (!S.flags.chest_opened && dist(p, World.CHEST) < 90) return { label: '🧰 Открыть сундук', fn: openChest };
    const bed = nearestBuild(['bed'], 40);
    if (bed) return { label: bed.crop ? (bed.grow >= 1 ? '🧺 Собрать урожай' : '🌱 Грядка') : '🌱 Посадить', fn: () => (bed.crop && bed.grow >= 1 ? harvest(bed) : UI.openBed(bed)) };
    const tr = nearestBuild(['tree'], 40);
    if (tr && tr.t <= 0) return { label: '🍎 Собрать яблоки', fn: () => { tr.t = 180; give('apple', 3); G.float('🍎 +3', tr.x, tr.y - 30, '#1b8a3a'); Sound.coin(); } };
    const hs = nearestBuild(['haystack'], 40);
    if (hs && !hs.used) return { label: '🌾 Взять сено', fn: () => { hs.used = true; give('hay', 5); G.float('🌾 +5', hs.x, hs.y - 30, '#1b8a3a'); Sound.coin(); } };
    return null;
  }

  function openChest() {
    const S = G.S;
    S.flags.chest_opened = true;
    give('money', 200); give('crown', 1); give('goldShoe', 1);
    UI.toast('🧰 Сундук графа! Внутри 200 монет, корона и золотая подкова!', 'good');
    Sound.fanfare();
  }

  function update(dt) {
    updateBuilds(dt);
    updateDetector(dt);
    updateShrooms(dt);
  }

  function hud() {
    if (mode) {
      if (mode.remove) return { title: '🧹 Убрать постройку', line: 'Нажми на постройку, которую хочешь убрать', hint: 'Esc или ✕ — выход', ok: true };
      const d = B()[mode.type];
      return { title: `🔨 Стройка: ${d.name}`, line: `Цена ${d.price} 🪙 · у тебя ${G.S.money} 🪙`, hint: mode.ok ? 'Нажми на землю, чтобы поставить · R — повернуть' : 'Здесь поставить нельзя', ok: mode.ok };
    }
    return null;
  }

  return {
    init, update, prompt, hud, startBuild, startRemove, cancel, rotate, hover, buildAt, syncSolids,
    rectOf, dims, maxStalls, extraSpot, nearStable, plant, water, harvest, stageOf, dig, give,
    shroomPicked, canDig,
    get mode() { return mode; },
    signal: () => signal, spots: () => spots, bunnyHomes: () => G.S.builds.filter(b => b.type === 'bunnyhouse'),
    lamps: () => G.S.builds.filter(b => b.type === 'lamp'),
  };
})();

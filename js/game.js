'use strict';
/* Основная логика игры */
const Game = (() => {
  const SAVE_KEY = 'horseFarm.v1';
  const MAX_STALLS = 20;
  const WILD_COUNT = 9;
  const GAITS = ['Шаг', 'Рысь', 'Галоп'];
  const LASSO_RANGE = 170;

  const FOOD = {
    hay: { name: 'Сено', icon: '🌾', price: 5, hunger: 25, energy: 5, mood: 2 },
    oats: { name: 'Овёс', icon: '🥣', price: 9, hunger: 35, energy: 25, mood: 3 },
    carrot: { name: 'Морковка', icon: '🥕', price: 3, hunger: 6, energy: 2, mood: 10, bait: true },
    apple: { name: 'Яблоко', icon: '🍎', price: 3, hunger: 6, energy: 2, mood: 10, bait: true },
    sugar: { name: 'Сахар', icon: '🍬', price: 2, hunger: 2, energy: 4, mood: 15 },
  };
  const COLORS = ['#c0392b', '#2e86de', '#e84393', '#8e44ad', '#27ae60', '#f39c12', '#222a3a', '#ffffff'];
  const TACK = {
    saddle: { name: 'Седло', icon: '🏇', price: 120, desc: 'Без седла верхом не поедешь' },
    bridle: { name: 'Уздечка', icon: '🪢', price: 60, desc: 'Чтобы управлять лошадью' },
    brush: { name: 'Щётка', icon: '🪮', price: 15, desc: 'Чистая лошадь — довольная лошадь' },
    goodLasso: { name: 'Ковбойское лассо', icon: '🤠', price: 90, desc: 'Ловить лошадей намного легче' },
    pad: { name: 'Вальтрап', icon: '🟥', price: 30, desc: 'Цветная подкладка под седло', colors: true },
    helmet: { name: 'Шлем', icon: '⛑️', price: 40, desc: 'Безопасность прежде всего!', colors: true },
    boots: { name: 'Ногавки', icon: '🧦', price: 35, desc: 'Защищают ноги лошади', colors: true },
  };
  const TESTS = {
    easy: {
      name: 'Тест для начинающих', desc: 'шаг и рысь',
      steps: [
        { to: 'A', gait: null, text: 'Подъедь к букве A — это старт' },
        { to: 'X', gait: 1, text: 'Рысью по средней линии от A до X' },
        { to: 'X', halt: true, text: 'Остановка в X — приветствие судьям' },
        { to: 'C', gait: 1, text: 'Рысью до C' },
        { to: 'M', gait: 0, text: 'Шагом до M' },
        { to: 'K', gait: 1, text: 'Рысью по диагонали M — X — K' },
        { to: 'A', gait: 0, text: 'Шагом до A' },
        { to: 'F', gait: 0, text: 'Шагом до F' },
        { to: 'M', gait: 1, text: 'Рысью по длинной стороне до M' },
        { to: 'C', gait: 0, text: 'Шагом до C' },
        { to: 'X', gait: 1, text: 'Рысью по средней линии до X' },
        { to: 'X', halt: true, text: 'Остановка, приветствие!' },
      ],
    },
    canter: {
      name: 'Тест с галопом', desc: 'шаг, рысь и галоп',
      steps: [
        { to: 'A', gait: null, text: 'Подъедь к букве A — это старт' },
        { to: 'X', gait: 1, text: 'Рысью от A до X' },
        { to: 'X', halt: true, text: 'Остановка в X — приветствие' },
        { to: 'C', gait: 1, text: 'Рысью до C' },
        { to: 'H', gait: 1, text: 'Рысью до H' },
        { to: 'K', gait: 2, text: 'Галопом по длинной стороне до K' },
        { to: 'A', gait: 1, text: 'Рысью до A' },
        { to: 'F', gait: 1, text: 'Рысью до F' },
        { to: 'M', gait: 2, text: 'Галопом до M' },
        { to: 'C', gait: 1, text: 'Рысью до C' },
        { to: 'E', gait: 0, text: 'Шагом до E' },
        { to: 'X', gait: 0, text: 'Шагом до X' },
        { to: 'X', halt: true, text: 'Остановка, приветствие!' },
      ],
    },
  };

  let S = null;              // сохраняемое состояние
  let wild = [];             // дикий табун
  let led = null;            // пойманная лошадь на поводу
  let ex = null;             // текущее упражнение
  let lasso = null;          // мини-игра с лассо
  let time = 0, saveT = 0, respawnT = 0, fullWarnT = 0, lassoCd = 0;
  let floats = [];
  const herd = { x: 2700, y: 900, tx: 2700, ty: 900, t: 0, panic: 0 };
  const keys = new Set();
  let canvas, ctx, mmctx, dpr = 1, zoom = 1, viewW = 0, viewH = 0;
  const cam = { x: 0, y: 0 };
  let pointerDown = false;

  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const rand = (a, b) => a + Math.random() * (b - a);
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  function lerpAngle(a, b, t) {
    let d = b - a;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    return a + d * t;
  }

  /* ---------------- состояние и сохранение ---------------- */
  function newState() {
    return {
      money: 300,
      inv: { hay: 6, oats: 0, carrot: 3, apple: 2, sugar: 0 },
      tack: { saddle: false, bridle: false, brush: false, goodLasso: false, pad: null, helmet: null, boots: null },
      horses: [],
      player: { x: 960, y: 470, angle: 0, gait: 0, mountId: null, shirt: '#e05a8a' },
      stats: { caught: 0, foals: 0, sold: 0, gold: 0, silver: 0, bronze: 0 },
      nextId: 1,
      seenHelp: false,
    };
  }

  function save() {
    if (!S) return;
    S.nextId = Horses.nextId;
    try {
      localStorage.setItem(SAVE_KEY, JSON.stringify(S, (k, v) => (k.startsWith('_') ? undefined : v)));
    } catch (e) { /* хранилище недоступно — играем без сохранения */ }
  }

  function load() {
    let data = null;
    try { data = JSON.parse(localStorage.getItem(SAVE_KEY) || 'null'); } catch (e) { data = null; }
    const fresh = newState();
    if (!data || !Array.isArray(data.horses)) return fresh;
    const s = Object.assign(fresh, data);
    s.inv = Object.assign(newState().inv, data.inv);
    s.tack = Object.assign(newState().tack, data.tack);
    s.stats = Object.assign(newState().stats, data.stats);
    s.player = Object.assign(newState().player, data.player);
    s.player.mountId = null;
    for (const h of s.horses) if (h.state === 'ridden' || h.state === 'led') h.state = 'stall';
    Horses.nextId = Math.max(s.nextId || 1, ...s.horses.map(h => h.id + 1), 1);
    return s;
  }

  function reset() {
    try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* ничего */ }
    S = newState();
    S.seenHelp = true;
    wild = []; led = null; ex = null;
    Horses.nextId = 1;
    spawnHerd();
    UI.closeModal();
    UI.toast('Новая игра! Поймай свою первую лошадь в поле →');
  }

  /* ---------------- помощники ---------------- */
  const mounted = () => (S.player.mountId != null ? S.horses.find(h => h.id === S.player.mountId) || null : null);
  const byId = id => S.horses.find(h => h.id === id);
  function freeStall() {
    const used = new Set(S.horses.map(h => h.stall));
    for (let i = 0; i < MAX_STALLS; i++) if (!used.has(i)) return i;
    return -1;
  }
  const horseInStall = i => S.horses.find(h => h.stall === i) || null;
  const atFarm = () => {
    const p = S.player;
    return World.inRect(p.x, p.y, World.STABLE, 40) || World.inRect(p.x, p.y, World.PADDOCK, 50);
  };
  function float(text, x, y, color = '#333') { floats.push({ text, x, y, t: 0, color }); }

  function gaitSpeed(h, gait) {
    const f = 0.75 + Horses.skill(h, 'speed') / 200;
    let v = [75, 155, 250][gait] * (gait === 2 ? f : 0.9 + f * 0.1);
    if (h.hunger < 15) v *= 0.75;
    if (h.age < 3) v *= 0.8;
    return v;
  }

  /* ---------------- табун ---------------- */
  function randomFieldPoint(margin = 150) {
    const F = World.FIELD;
    for (let i = 0; i < 50; i++) {
      const x = rand(F.x + margin, F.x + F.w - margin), y = rand(F.y + margin, F.y + F.h - margin);
      if (!World.inPond(x, y, 150)) return { x, y };
    }
    return { x: F.x + F.w / 2, y: F.y + 400 };
  }

  function pickBreed() {
    const entries = Object.entries(Genetics.BREEDS).filter(([, b]) => b.weight > 0);
    let total = entries.reduce((s, [, b]) => s + b.weight, 0), r = Math.random() * total;
    for (const [k, b] of entries) { r -= b.weight; if (r <= 0) return k; }
    return entries[0][0];
  }

  function makeWild(x, y) {
    const isFoal = Math.random() < 0.12;
    const taken = S.horses.map(h => h.name).concat(wild.map(w => w.name));
    const h = Horses.create({ breed: pickBreed(), age: isFoal ? rand(0.3, 1.5) : rand(3, 13), taken });
    h.x = x; h.y = y; h.angle = rand(0, 6.28);
    h.slot = { x: rand(-150, 150), y: rand(-110, 110) };
    h.flee = 0; h.grazeT = rand(0, 5);
    return h;
  }

  function spawnHerd() {
    const c = randomFieldPoint(400);
    herd.x = herd.tx = c.x; herd.y = herd.ty = c.y;
    wild = [];
    for (let i = 0; i < WILD_COUNT; i++) wild.push(makeWild(c.x + rand(-150, 150), c.y + rand(-120, 120)));
  }

  function moveToward(h, tx, ty, speed, dt, accel = 3) {
    const dx = tx - h.x, dy = ty - h.y, d = Math.hypot(dx, dy);
    const want = d > 1 ? speed : 0;
    const vx = d > 1 ? (dx / d) * want : 0, vy = d > 1 ? (dy / d) * want : 0;
    const k = Math.min(1, dt * accel);
    h.vx += (vx - h.vx) * k;
    h.vy += (vy - h.vy) * k;
    h.x += h.vx * dt;
    h.y += h.vy * dt;
    h.spd = Math.hypot(h.vx, h.vy);
    if (h.spd > 6) h.angle = lerpAngle(h.angle, Math.atan2(h.vy, h.vx), Math.min(1, dt * 5));
    h.phase += dt * (3 + h.spd * 0.045) * (h.spd > 4 ? 1 : 0);
  }

  function updateHerd(dt) {
    const p = S.player, m = mounted();
    const F = World.FIELD;
    herd.t -= dt;
    herd.panic = Math.max(0, herd.panic - dt);
    if (herd.t <= 0) {
      const t = randomFieldPoint(300);
      herd.tx = t.x; herd.ty = t.y; herd.t = rand(14, 26);
    }
    const hs = herd.panic > 0 ? 120 : 20;
    const hd = Math.hypot(herd.tx - herd.x, herd.ty - herd.y);
    if (hd > 5) { herd.x += ((herd.tx - herd.x) / hd) * hs * dt; herd.y += ((herd.ty - herd.y) / hd) * hs * dt; }

    for (const w of wild) {
      const d = dist(w, p);
      let fleeR = 70 + w.temper * 170;
      if (m && p.gait === 2) fleeR *= 1.2;
      if (m && p.gait === 0) fleeR *= 0.8;
      if (d < fleeR && w.flee <= 0) {
        w.flee = rand(1.4, 2.2);
        if (herd.panic <= 0) {
          const ax = herd.x - p.x, ay = herd.y - p.y, al = Math.hypot(ax, ay) || 1;
          herd.tx = clamp(herd.x + (ax / al) * 600, F.x + 250, F.x + F.w - 250);
          herd.ty = clamp(herd.y + (ay / al) * 600, F.y + 250, F.y + F.h - 250);
          herd.t = rand(8, 14);
        }
        herd.panic = 2.5;
      }
      let tx, ty, sp;
      if (w.flee > 0) {
        w.flee -= dt;
        const ax = w.x - p.x, ay = w.y - p.y, al = Math.hypot(ax, ay) || 1;
        tx = w.x + (ax / al) * 100 + (herd.x - w.x) * 0.15;
        ty = w.y + (ay / al) * 100 + (herd.y - w.y) * 0.15;
        sp = (170 + Horses.skill(w, 'speed') * 0.8) * (w.age < 3 ? 0.8 : 1);
        w.headTurn = 0;
      } else {
        const gx = herd.x + w.slot.x, gy = herd.y + w.slot.y;
        const gd = Math.hypot(gx - w.x, gy - w.y);
        if (gd > 60) {
          tx = gx; ty = gy;
          sp = herd.panic > 0 ? 190 : gd > 300 ? 150 : gd > 150 ? 80 : 40;
          w.headTurn = 0;
        } else {
          // пасётся: стоит, иногда делает пару шагов
          w.grazeT -= dt;
          if (w.grazeT <= 0) { w.grazeT = rand(3, 8); w.slot.x += rand(-30, 30); w.slot.y += rand(-30, 30); }
          tx = w.x; ty = w.y; sp = 0;
          w.headTurn = Math.sin(time * 0.8 + w.seed) * 0.35;
        }
      }
      // остаться в поле
      if (w.x < F.x + 40) tx = Math.max(tx, F.x + 120);
      if (w.x > F.x + F.w - 40) tx = Math.min(tx, F.x + F.w - 120);
      if (w.y < F.y + 40) ty = Math.max(ty, F.y + 120);
      if (w.y > F.y + F.h - 40) ty = Math.min(ty, F.y + F.h - 120);
      moveToward(w, tx, ty, sp, dt, w.flee > 0 ? 4 : 2);
      // не толкаться
      for (const o of wild) {
        if (o === w) continue;
        const dx = w.x - o.x, dy = w.y - o.y, dd = Math.hypot(dx, dy);
        if (dd < 48 && dd > 0.1) { w.x += (dx / dd) * (48 - dd) * 0.5; w.y += (dy / dd) * (48 - dd) * 0.5; }
      }
      World.collide(w, 18);
      w.x = clamp(w.x, F.x - 60, F.x + F.w + 60);
    }

    // новые лошади прибегают в поле взамен пойманных
    if (wild.length < WILD_COUNT) {
      respawnT -= dt;
      if (respawnT <= 0) {
        respawnT = rand(6, 12);
        const F2 = World.FIELD;
        const w = makeWild(F2.x + F2.w - 20, rand(F2.y + 200, F2.y + F2.h - 200));
        w.slot = { x: rand(-150, 150), y: rand(-110, 110) };
        wild.push(w);
        UI.toast('🐎 В поле прибежала новая лошадь!');
      }
    }
  }

  /* ---------------- свои лошади ---------------- */
  function updateOwned(dt) {
    const P = World.PADDOCK;
    for (const h of S.horses) {
      h.age += dt / 120; // 2 минуты = 1 год
      const inPaddock = h.state === 'paddock';
      h.hunger = clamp(h.hunger - dt * (inPaddock ? 0.03 : 0.07), 0, 100);
      h.clean = clamp(h.clean - dt * (inPaddock ? 0.06 : 0.015), 0, 100);
      if (h.state !== 'ridden') h.energy = clamp(h.energy + dt * (inPaddock ? 1.2 : 0.8), 0, 100);
      let moodD = inPaddock ? 0.4 : -0.03;
      if (h.hunger < 25) moodD -= 0.15;
      if (h.clean < 25) moodD -= 0.05;
      h.mood = clamp(h.mood + dt * moodD, 0, 100);

      if (h.state === 'stall') {
        const sp = World.stallSpot(h.stall);
        h.x = sp.x; h.y = sp.y; h.angle = sp.angle; h.spd = 0;
        h.headTurn = Math.sin(time * 0.5 + h.seed) * 0.35;
      } else if (inPaddock) {
        if (!h.wander || dist(h, h.wander) < 10 || Math.random() < dt * 0.05) {
          h.wander = Math.random() < 0.5 ? { x: h.x, y: h.y }
            : { x: rand(P.x + 50, P.x + P.w - 50), y: rand(P.y + 50, P.y + P.h - 50) };
        }
        moveToward(h, h.wander.x, h.wander.y, dist(h, h.wander) > 10 ? 40 : 0, dt);
        h.x = clamp(h.x, P.x + 30, P.x + P.w - 30);
        h.y = clamp(h.y, P.y + 30, P.y + P.h - 30);
        h.headTurn = h.spd < 5 ? Math.sin(time * 0.7 + h.seed) * 0.4 : 0;
      }

      // жеребёнок
      if (h.preg) {
        h.preg.t -= dt;
        if (h.preg.t <= 0) {
          const st = freeStall();
          if (st < 0) {
            h.preg.t = 0;
            if (!h.preg.warned) { h.preg.warned = true; UI.toast(`🍼 ${h.name} скоро родит — освободи денник!`, 'warn'); }
          } else {
            const f = Horses.foal(h, h.preg.father, S.horses.map(x => x.name));
            f.state = 'stall'; f.stall = st; f.hunger = 90; f.mood = 90;
            S.horses.push(f);
            S.stats.foals++;
            h.preg = null;
            const ph = Horses.pheno(f);
            UI.toast(`🍼 У кобылы ${h.name} родился жеребёнок! ${f.name} — ${Horses.sexText(f)}, ${ph.name}`, 'good');
            Sound.fanfare();
          }
        }
      }
    }
  }

  /* ---------------- игрок ---------------- */
  function updatePlayer(dt) {
    const p = S.player, m = mounted();
    let ix = 0, iy = 0;
    if (keys.has('ArrowLeft') || keys.has('KeyA')) ix--;
    if (keys.has('ArrowRight') || keys.has('KeyD')) ix++;
    if (keys.has('ArrowUp') || keys.has('KeyW')) iy--;
    if (keys.has('ArrowDown') || keys.has('KeyS')) iy++;
    let dx = 0, dy = 0;
    if (ix || iy) {
      const l = Math.hypot(ix, iy); dx = ix / l; dy = iy / l; p.target = null;
    } else if (p.target) {
      const tx = p.target.x - p.x, ty = p.target.y - p.y, d = Math.hypot(tx, ty);
      if (d < (m ? 16 : 6)) p.target = null;
      else { dx = tx / d; dy = ty / d; }
    }
    if (m && m.energy <= 0.5 && p.gait > 0) {
      p.gait = 0;
      UI.toast(`😮‍💨 ${m.name} ${Horses.v(m, 'устала', 'устал')} — только шагом. Отдохните в конюшне.`, 'warn');
    }
    const max = m ? gaitSpeed(m, p.gait) : 140;
    const k = Math.min(1, dt * (m ? 3.5 : 12));
    p.vx = (p.vx || 0) + (dx * max - (p.vx || 0)) * k;
    p.vy = (p.vy || 0) + (dy * max - (p.vy || 0)) * k;
    const ox = p.x, oy = p.y;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    World.collide(p, m ? 20 : 10);
    p.spd = dt > 0 ? Math.hypot(p.x - ox, p.y - oy) / dt : 0;
    if (p.spd > 8) p.angle = lerpAngle(p.angle, Math.atan2(p.y - oy, p.x - ox), Math.min(1, dt * (m ? 6 : 14)));
    p.phase = (p.phase || 0) + (m ? dt * (3 + p.spd * 0.045) * (p.spd > 4 ? 1 : 0) : p.spd * dt * 0.18);

    if (m) {
      m.x = p.x; m.y = p.y; m.angle = p.angle; m.spd = p.spd; m.phase = p.phase; m.headTurn = 0;
      const moving = p.spd > 10;
      const drain = [0.12, 0.55, 1.5][p.gait] * (1.4 - Horses.skill(m, 'stamina') / 125);
      m.energy = clamp(m.energy - dt * (moving ? drain : -0.4), 0, 100);
      if (moving && p.gait > 0) Horses.addTrain(m, 'stamina', dt * 0.004);
      if (moving && p.gait === 2) Horses.addTrain(m, 'speed', dt * 0.005);
    }

    // пойманная лошадь идёт следом
    if (led) {
      const back = { x: p.x - Math.cos(p.angle) * 70, y: p.y - Math.sin(p.angle) * 70 };
      const d = dist(led, back);
      moveToward(led, back.x, back.y, d > 25 ? Math.min(d * 3, 300) : 0, dt, 5);
      led.headTurn = 0;
      World.collide(led, 16);
      if (World.inRect(p.x, p.y, World.STABLE, 10)) {
        const st = freeStall();
        if (st >= 0) {
          led.state = 'stall'; led.stall = st; led.flee = 0;
          S.horses.push(led);
          UI.toast(`🏠 ${led.name} теперь живёт в деннике №${st + 1}!`, 'good');
          Sound.coin();
          led = null;
        } else if (time > fullWarnT) {
          fullWarnT = time + 6;
          UI.toast('Конюшня полна! Продай лошадь у повозки или отпусти эту.', 'warn');
        }
      }
    }
  }

  /* ---------------- лассо ---------------- */
  function nearestCatchable() {
    if (led || ex) return null;
    let best = null, bd = LASSO_RANGE;
    for (const w of wild) {
      const d = dist(w, S.player);
      if (d < bd) { bd = d; best = w; }
    }
    return best;
  }

  function startLasso(w) {
    if (led) { UI.toast('Сначала отведи пойманную лошадь в конюшню'); return; }
    if (!w || lassoCd > 0) return;
    let zone = 0.24 * (S.tack.goodLasso ? 1.5 : 1) * (1.25 - w.temper * 0.6);
    let bait = null;
    if (S.inv.carrot > 0) bait = 'carrot';
    else if (S.inv.apple > 0) bait = 'apple';
    if (bait) { zone *= 1.3; S.inv[bait]--; }
    if (mounted()) zone *= 1.1;
    zone = clamp(zone, 0.08, 0.6);
    lasso = {
      w, zone, bait,
      center: rand(zone / 2 + 0.04, 1 - zone / 2 - 0.04),
      pos: 0, dir: 1,
      speed: 0.55 + w.temper * 1.0,
    };
    UI.showLasso(lasso);
    Sound.whoosh();
  }

  function resolveLasso() {
    if (!lasso) return;
    const l = lasso, w = l.w;
    lasso = null;
    const ok = Math.abs(l.pos - l.center) <= l.zone / 2;
    UI.hideLasso(ok);
    if (ok) {
      wild = wild.filter(x => x !== w);
      w.state = 'led'; w.flee = 0;
      led = w;
      respawnT = rand(5, 10);
      S.stats.caught++;
      const ph = Horses.pheno(w);
      UI.toast(`🎉 Поймала! ${w.name}: ${Genetics.BREEDS[w.breed].name.toLowerCase()}, ${ph.name}. Веди в конюшню!`, 'good');
      Sound.fanfare();
    } else {
      w.flee = 2.5;
      herd.panic = 3;
      lassoCd = 1.2;
      UI.toast(l.bait ? 'Мимо! Лошадь съела угощение и убежала 🥕' : 'Мимо! Лошадь убежала. Попробуй ещё!', 'warn');
      Sound.fail();
    }
  }

  /* ---------------- упражнения ---------------- */
  function inArena() {
    const p = S.player, A = World.ARENA;
    return World.inRect(p.x, p.y, { x: A.x + 4, y: A.y + 4, w: A.w - 8, h: A.h - 8 });
  }

  function startExercise(kind) {
    const m = mounted();
    if (!m) return;
    UI.closeModal();
    if (m.energy < 15) { UI.toast(`${m.name} слишком ${Horses.v(m, 'устала', 'устал')}. Дай отдохнуть или покорми овсом.`, 'warn'); return; }
    if (kind === 'cav') {
      ex = {
        type: 'cav', lift: 0, cd: 0, started: false, outT: 0, prevX: S.player.x,
        poles: World.CAV.poles.map(x => ({ x, state: null })),
      };
      UI.toast('Кавалетти: заезжай на жерди слева РЫСЬЮ и жми «Ноги выше!» прямо перед каждой жердью');
    } else {
      const test = TESTS[kind];
      ex = { type: 'dres', test, i: 0, segT: 0, ok: 0, haltT: 0, arrive: null, marks: [], targetLetter: test.steps[0].to };
      UI.toast(`Выездка: ${test.name}. Следуй указаниям и держи нужный аллюр!`);
    }
  }

  function cancelExercise(msg) {
    if (!ex) return;
    ex = null;
    if (msg) UI.toast(msg, 'warn');
  }

  function liftLegs() {
    if (!ex || ex.type !== 'cav' || ex.cd > 0) return;
    const p = S.player;
    const next = ex.poles.find(s => !s.state && s.x > p.x);
    ex.cd = 0.3;
    if (next && next.x - p.x > 80) { float('Рано!', p.x, p.y - 40, '#b07800'); ex.cd = 0.55; return; }
    ex.lift = 0.42;
  }

  function updateCav(dt) {
    const p = S.player, C = World.CAV, m = mounted();
    const inLane = p.y > C.y1 - 15 && p.y < C.y2 + 15;
    ex.lift -= dt;
    ex.cd -= dt;
    for (const pole of ex.poles) {
      if (pole.state || !inLane || !(ex.prevX < pole.x && p.x >= pole.x)) continue;
      ex.started = true;
      if (p.gait !== 1) { pole.state = 'hit'; float(p.gait === 2 ? 'Слишком быстро!' : 'Нужна рысь!', pole.x, C.y1 - 10, '#c92a2a'); Sound.thud(); }
      else if (ex.lift > 0) { pole.state = 'ok'; float('Чисто!', pole.x, C.y1 - 10, '#1b8a3a'); Sound.tick(); }
      else { pole.state = 'hit'; float('Стук!', pole.x, C.y1 - 10, '#c92a2a'); Sound.thud(); }
    }
    ex.prevX = p.x;
    if (ex.started) {
      ex.outT = inLane ? 0 : ex.outT + dt;
      if (ex.poles.every(s => s.state) || ex.outT > 1 || p.x < C.poles[0] - 120) {
        const clean = ex.poles.filter(s => s.state === 'ok').length;
        const money = clean * 8 + (clean === 5 ? 20 : 0);
        S.money += money;
        Horses.addTrain(m, 'jump', clean * 0.8);
        m.energy = clamp(m.energy - 6, 0, 100);
        m.mood = clamp(m.mood + 3, 0, 100);
        const medal = clean === 5 ? 'gold' : clean === 4 ? 'silver' : clean === 3 ? 'bronze' : null;
        if (medal) S.stats[medal]++;
        ex = null;
        UI.result('Кавалетти', clean, 5, money, medal, `Прыжки: ${Horses.skill(m, 'jump')}`);
        if (medal) Sound.fanfare(); else Sound.tick();
      }
    }
  }

  function updateDres(dt) {
    const p = S.player, m = mounted();
    const st = ex.test.steps[ex.i];
    const tp = World.letterTarget(st.to);
    const d = dist(p, tp);
    ex.targetLetter = st.to;
    ex.segT += dt;
    const next = mark => {
      if (mark != null) ex.marks.push({ text: st.text, mark: Math.round(mark * 2) / 2 });
      ex.i++; ex.segT = 0; ex.ok = 0; ex.haltT = 0; ex.arrive = null;
      Sound.tick();
      if (ex.i >= ex.test.steps.length) finishDres();
    };
    if (st.halt) {
      if (d < 45) {
        if (ex.arrive == null) ex.arrive = ex.segT;
        ex.haltT = p.spd < 12 ? ex.haltT + dt : 0;
        if (ex.haltT >= 1.5) return next(clamp(10 - Math.max(0, ex.segT - ex.arrive - 1.5) * 1.5, 3, 10));
      }
      if (ex.segT > 25) next(0);
      return;
    }
    if (st.gait != null && p.spd > 15 && p.gait === st.gait) ex.ok += dt;
    if (d < 40) {
      if (st.gait == null) return next(null);
      const ratio = ex.ok / Math.max(0.1, ex.segT);
      return next(clamp(ratio * 8 + (Horses.skill(m, 'dressage') / 100) * 2, 0, 10));
    }
    if (ex.segT > 30) next(st.gait == null ? null : 0);
  }

  function finishDres() {
    const m = mounted();
    const marks = ex.marks;
    const pct = marks.length ? (marks.reduce((s, x) => s + x.mark, 0) / (marks.length * 10)) * 100 : 0;
    const money = Math.round(pct / 2);
    S.money += money;
    Horses.addTrain(m, 'dressage', pct / 20);
    m.energy = clamp(m.energy - 8, 0, 100);
    const medal = pct >= 70 ? 'gold' : pct >= 60 ? 'silver' : pct >= 50 ? 'bronze' : null;
    if (medal) S.stats[medal]++;
    const testName = ex.test.name;
    ex = null;
    UI.dressageResult(testName, marks, pct, money, medal, Horses.skill(m, 'dressage'));
    if (medal) Sound.fanfare(); else Sound.tick();
  }

  function exerciseHud() {
    if (!ex) return null;
    const p = S.player;
    if (ex.type === 'cav') {
      const clean = ex.poles.filter(s => s.state === 'ok').length;
      const done = ex.poles.filter(s => s.state).length;
      return {
        title: 'Кавалетти',
        line: `Жерди: ${done}/5 · чисто: ${clean}`,
        hint: p.gait === 1 ? 'Рысь ✔ Жми «Ноги выше!» (Пробел) перед жердью' : 'Переходи на РЫСЬ (клавиша 2)',
        ok: p.gait === 1,
      };
    }
    const st = ex.test.steps[ex.i];
    const need = st.halt ? 'Стоп' : st.gait == null ? 'любой' : GAITS[st.gait];
    const ok = st.halt ? p.spd < 12 : st.gait == null || (p.gait === st.gait && p.spd > 15);
    return {
      title: `Выездка: ${ex.test.name}`,
      line: `${ex.i + 1}/${ex.test.steps.length}: ${st.text}`,
      hint: `Буква ${st.to} · аллюр: ${need}${st.halt ? ' (остановись на 2 сек.)' : ''}`,
      ok,
      letter: st.to,
    };
  }

  /* ---------------- действия из меню ---------------- */
  const act = {
    mount(h) {
      if (!atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (!S.tack.saddle || !S.tack.bridle) return UI.toast('Нужны седло и уздечка — купи их в повозке «Корм и амуниция»', 'warn');
      if (!Horses.isAdult(h)) return UI.toast('Жеребёнок ещё маленький — подожди, пока вырастет (3 года)', 'warn');
      if (h.energy < 5) return UI.toast(`${h.name} ${Horses.v(h, 'устала', 'устал')}. Пусть отдохнёт.`, 'warn');
      const cur = mounted();
      if (cur) cur.state = 'stall';
      h.state = 'ridden';
      S.player.mountId = h.id;
      S.player.gait = 0;
      if (World.inRect(S.player.x, S.player.y, World.STABLE)) { S.player.x = World.STABLE.x + World.STABLE.w + 40; S.player.y = (World.AISLE_Y1 + World.AISLE_Y2) / 2; }
      h.x = S.player.x; h.y = S.player.y;
      UI.closeModal();
      UI.toast(`🏇 Ты в седле! ${h.name} ждёт команды. Аллюры: 1 — шаг, 2 — рысь, 3 — галоп`);
    },
    dismount() {
      const m = mounted();
      if (!m) return;
      cancelExercise();
      m.state = 'stall';
      S.player.mountId = null;
      S.player.vx = S.player.vy = 0;
      UI.toast(`${m.name} ${Horses.v(m, 'вернулась', 'вернулся')} в денник №${m.stall + 1}`);
    },
    paddock(h) {
      if (!atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (h.state === 'paddock') { h.state = 'stall'; UI.toast(`${h.name} ${Horses.v(h, 'вернулась', 'вернулся')} в денник`); }
      else if (h.state === 'stall') {
        const P = World.PADDOCK;
        h.state = 'paddock';
        h.x = rand(P.x + 60, P.x + P.w - 60); h.y = rand(P.y + 60, P.y + P.h - 60); h.wander = null;
        UI.toast(`🌿 ${h.name} гуляет в леваде`);
      }
    },
    feed(h, item) {
      if (!atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (!(S.inv[item] > 0)) return UI.toast(`Нет: ${FOOD[item].name}. Купи в повозке.`, 'warn');
      if (h.hunger >= 99 && !FOOD[item].bait && item !== 'sugar') return UI.toast(`${h.name} ${Horses.v(h, 'сыта', 'сыт')}`);
      const f = FOOD[item];
      S.inv[item]--;
      h.hunger = clamp(h.hunger + f.hunger, 0, 100);
      h.energy = clamp(h.energy + f.energy, 0, 100);
      h.mood = clamp(h.mood + f.mood, 0, 100);
      Sound.tick();
    },
    brush(h) {
      if (!atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (!S.tack.brush) return UI.toast('Нужна щётка — купи в повозке', 'warn');
      h.clean = 100;
      h.mood = clamp(h.mood + 8, 0, 100);
      Sound.tick();
    },
    rename(h, n) {
      if (n && n.trim()) h.name = n.trim().slice(0, 20);
    },
    breed(mare, stallion) {
      if (!atFarm()) return UI.toast('Подойди к конюшне');
      if (!mare || !stallion || mare.sex !== 'f' || stallion.sex !== 'm') return;
      if (!Horses.isAdult(mare) || !Horses.isAdult(stallion)) return UI.toast('Обе лошади должны быть взрослыми', 'warn');
      if (mare.preg) return UI.toast(`${mare.name} уже ждёт жеребёнка`);
      if (S.money < 30) return UI.toast('Нужно 30 монет на ветеринара', 'warn');
      S.money -= 30;
      mare.preg = {
        t: 150,
        father: { name: stallion.name, g: JSON.parse(JSON.stringify(stallion.g)), base: Object.assign({}, stallion.base), breed: stallion.breed, size: stallion.size, temper: stallion.temper, marks: JSON.parse(JSON.stringify(stallion.marks)) },
      };
      UI.toast(`💕 ${mare.name} и ${stallion.name} ждут жеребёнка! Он родится через 2,5 минуты.`, 'good');
      Sound.fanfare();
    },
    sell(h) {
      const p = S.player;
      if (dist(p, { x: World.SELL.x + World.SELL.w / 2, y: World.SELL.y + World.SELL.h / 2 }) > 170) return UI.toast('Подойди к повозке «Продажа лошадей»');
      if (h === led) {
        const price = Math.round(Horses.price(h) * 0.85 / 5) * 5;
        S.money += price;
        led = null;
        S.stats.sold++;
        UI.toast(`Продано: ${h.name} за ${price} 🪙`, 'good');
        Sound.coin();
        return;
      }
      if (h.state === 'ridden') return UI.toast('Сначала слезь с лошади');
      const price = Horses.price(h);
      S.money += price;
      S.horses = S.horses.filter(x => x !== h);
      S.stats.sold++;
      UI.toast(`Продано: ${h.name} за ${price} 🪙`, 'good');
      Sound.coin();
    },
    buyFood(item, n) {
      const cost = FOOD[item].price * n;
      if (S.money < cost) return UI.toast('Не хватает монет', 'warn');
      S.money -= cost;
      S.inv[item] = (S.inv[item] || 0) + n;
      Sound.coin();
    },
    buyTack(item) {
      const t = TACK[item];
      if (S.tack[item]) return;
      if (S.money < t.price) return UI.toast('Не хватает монет', 'warn');
      S.money -= t.price;
      S.tack[item] = t.colors ? COLORS[item === 'boots' ? 7 : item === 'helmet' ? 6 : 0] : true;
      Sound.coin();
      UI.toast(`Куплено: ${t.name}!`, 'good');
    },
    setColor(item, color) { if (S.tack[item]) S.tack[item] = color; },
    setShirt(color) { S.player.shirt = color; },
    releaseLed() {
      if (!led) return;
      led.state = 'wild'; led.flee = 2; led.slot = { x: rand(-150, 150), y: rand(-110, 110) };
      wild.push(led);
      UI.toast(`${led.name} ${Horses.v(led, 'убежала', 'убежал')} обратно в поле`);
      led = null;
    },
    setGait(g) {
      const m = mounted();
      if (!m) return;
      if (g > 0 && m.energy <= 0.5) return UI.toast(`${m.name} ${Horses.v(m, 'устала', 'устал')} — только шагом`, 'warn');
      S.player.gait = g;
    },
    interact() {
      const pr = computePrompt();
      if (pr) pr.fn();
    },
    lasso() { startLasso(nearestCatchable()); },
    startExercise, cancelExercise: () => cancelExercise('Упражнение прервано'), liftLegs, reset,
  };

  /* ---------------- подсказки и кнопки ---------------- */
  function computePrompt() {
    const p = S.player;
    if (ex) return null;
    if (World.inRect(p.x, p.y, World.STABLE, 30) || World.inRect(p.x, p.y, World.PADDOCK, 30))
      return { label: '🐴 Мои лошади', fn: () => UI.openStable(true) };
    const near = W => Math.hypot(p.x - (W.x + W.w / 2), p.y - (W.y + W.h / 2)) < 130;
    if (near(World.SELL)) return { label: '💰 Продать лошадь', fn: () => UI.openSell() };
    if (near(World.SHOP)) return { label: '🛒 Корм и амуниция', fn: () => UI.openShop() };
    if (inArena()) {
      if (mounted()) return { label: '🏆 Тренировка', fn: () => UI.openTraining() };
      return { label: '🏆 Тренировка', fn: () => UI.toast('Чтобы тренироваться, сядь на лошадь в конюшне') };
    }
    return null;
  }

  function hint() {
    const tk = S.tack;
    if (!S.horses.length && !led) return 'Иди в поле справа → и поймай лошадь лассо. Спокойных лошадей ловить легче!';
    if (led) return `Веди лошадь по кличке ${led.name} в конюшню — она пойдёт за тобой`;
    if (!tk.saddle || !tk.bridle) return 'Купи седло и уздечку в повозке «Корм и амуниция», чтобы ездить верхом';
    if (!mounted()) return 'Открой конюшню и сядь на лошадь. Тренируйся в манеже!';
    if (ex) return '';
    if (inArena()) return 'Нажми «Тренировка»: кавалетти или выездка';
    return 'Аллюры: 1 — шаг, 2 — рысь, 3 — галоп. Езжай в манеж или лови лошадей в поле';
  }

  /* ---------------- ввод ---------------- */
  function onKey(e, down) {
    const code = e.code;
    if (down) {
      if (UI.isLassoOpen()) {
        if (code === 'Space' || code === 'Enter') { e.preventDefault(); resolveLasso(); }
        return;
      }
      if (UI.isModalOpen()) {
        if (code === 'Escape') UI.closeModal();
        return;
      }
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(code)) e.preventDefault();
      if (e.repeat) { keys.add(code); return; }
      keys.add(code);
      if (code === 'KeyE' || code === 'Enter') act.interact();
      if (code === 'Space') {
        if (ex && ex.type === 'cav') liftLegs();
        else act.lasso();
      }
      if (code === 'Digit1') act.setGait(0);
      if (code === 'Digit2') act.setGait(1);
      if (code === 'Digit3') act.setGait(2);
      if (code === 'KeyQ') act.setGait(Math.max(0, S.player.gait - 1));
      if (code === 'KeyR') act.setGait(Math.min(2, S.player.gait + 1));
      if (code === 'KeyX' || code === 'KeyF') act.dismount();
      if (code === 'Escape' && ex) act.cancelExercise();
    } else keys.delete(code);
  }

  function toWorld(e) {
    const r = canvas.getBoundingClientRect();
    return { x: (e.clientX - r.left) / zoom + cam.x, y: (e.clientY - r.top) / zoom + cam.y };
  }

  function onPointer(e, type) {
    if (UI.isModalOpen() || UI.isLassoOpen()) return;
    if (type === 'down') {
      pointerDown = true;
      const w = toWorld(e);
      // клик по дикой лошади рядом — бросаем лассо
      for (const h of wild) {
        if (Math.hypot(h.x - w.x, h.y - w.y) < 45 && dist(h, S.player) < LASSO_RANGE && !led) {
          startLasso(h); pointerDown = false; return;
        }
      }
      S.player.target = w;
    } else if (type === 'move' && pointerDown) {
      S.player.target = toWorld(e);
    } else if (type === 'up') {
      pointerDown = false;
    }
  }

  function resize() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.floor(innerWidth * dpr);
    canvas.height = Math.floor(innerHeight * dpr);
    zoom = innerWidth < 600 ? 0.62 : innerWidth < 1000 ? 0.8 : 1;
    viewW = innerWidth / zoom;
    viewH = innerHeight / zoom;
  }

  /* ---------------- отрисовка ---------------- */
  function rider() {
    return { pad: S.tack.pad || '#7a6a55', helmet: S.tack.helmet || '#222a3a', boots: S.tack.boots, shirt: S.player.shirt };
  }

  function render() {
    const p = S.player;
    cam.x = viewW >= World.W ? (World.W - viewW) / 2 : clamp(p.x - viewW / 2, 0, World.W - viewW);
    cam.y = viewH >= World.H ? (World.H - viewH) / 2 : clamp(p.y - viewH / 2, 0, World.H - viewH);
    ctx.setTransform(dpr * zoom, 0, 0, dpr * zoom, -cam.x * dpr * zoom, -cam.y * dpr * zoom);
    const view = { x: cam.x, y: cam.y, w: viewW, h: viewH };
    const visible = (x, y, m = 120) => x > view.x - m && x < view.x + view.w + m && y > view.y - m && y < view.y + view.h + m;

    Draw.ground(ctx, view);
    if (visible(World.STABLE.x + 370, World.STABLE.y + 170, 600)) Draw.stable(ctx, S, api);
    if (visible(World.ARENA.x + 410, World.ARENA.y + 200, 600)) Draw.arena(ctx, S, api);
    Draw.paddock(ctx);
    Draw.wagon(ctx, World.SELL, '#d63a3a', time);
    Draw.wagon(ctx, World.SHOP, '#2e9d4f', time);
    for (const tr of World.TREES) if (visible(tr.x, tr.y)) Draw.treeTrunk(ctx, tr);

    // подсветка лошади, которую можно поймать
    const target = nearestCatchable();
    if (target) {
      ctx.strokeStyle = 'rgba(255,230,80,0.9)';
      ctx.lineWidth = 3;
      ctx.setLineDash([8, 6]);
      ctx.beginPath();
      ctx.arc(target.x, target.y, 46 * Horses.sizeOf(target) + Math.sin(time * 5) * 3, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // все лошади и игрок — сортировка по высоте, чтобы ближние перекрывали дальних
    const m = mounted();
    const ents = [];
    for (const h of S.horses) if (h.state !== 'ridden' && visible(h.x, h.y)) ents.push({ y: h.y, h });
    for (const h of wild) if (visible(h.x, h.y)) ents.push({ y: h.y, h });
    if (led) ents.push({ y: led.y, h: led });
    ents.push({ y: p.y, player: true });
    ents.sort((a, b) => a.y - b.y);
    for (const e of ents) {
      if (e.player) {
        if (m) Draw.horse(ctx, m, p.x, p.y, p.angle, { t: time, rider: rider(), lift: ex && ex.type === 'cav' && ex.lift > 0 });
        else Draw.girl(ctx, p, time);
      } else {
        Draw.horse(ctx, e.h, e.h.x, e.h.y, e.h.angle, { t: time });
      }
    }

    // верёвка к пойманной лошади
    if (led) {
      const s = Horses.sizeOf(led);
      ctx.strokeStyle = '#c9a35b';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(p.x + Math.cos(p.angle) * 4, p.y + Math.sin(p.angle) * 4);
      const hx = led.x + Math.cos(led.angle) * 44 * s, hy = led.y + Math.sin(led.angle) * 44 * s;
      ctx.quadraticCurveTo((p.x + hx) / 2, (p.y + hy) / 2 + 15, hx, hy);
      ctx.stroke();
    }

    for (const tr of World.TREES) if (visible(tr.x, tr.y)) Draw.treeTop(ctx, tr);

    // стрелка-подсказка к полю для новичка
    if (!S.horses.length && !led && p.x < World.FIELD.x - 100) {
      const a = Math.atan2(herd.y - p.y, herd.x - p.x);
      ctx.save();
      ctx.translate(p.x + Math.cos(a) * 70, p.y + Math.sin(a) * 70);
      ctx.rotate(a);
      ctx.fillStyle = 'rgba(255,214,0,0.95)';
      ctx.strokeStyle = 'rgba(90,60,0,0.7)';
      ctx.lineWidth = 2;
      const b = Math.sin(time * 5) * 4;
      ctx.beginPath();
      ctx.moveTo(18 + b, 0); ctx.lineTo(-6 + b, -13); ctx.lineTo(-6 + b, 13); ctx.closePath();
      ctx.fill(); ctx.stroke();
      ctx.restore();
    }

    // всплывающие надписи
    for (const f of floats) {
      ctx.globalAlpha = Math.max(0, 1 - f.t / 1.4);
      Draw.label(ctx, f.text, f.x, f.y - f.t * 30, 18, f.color);
    }
    ctx.globalAlpha = 1;

    Draw.minimap(mmctx, S, api);
  }

  /* ---------------- главный цикл ---------------- */
  let last = 0, hudT = 0;
  function frame(ts) {
    const dt = Math.min(0.05, (ts - last) / 1000 || 0);
    last = ts;
    if (lasso) {
      lasso.pos += lasso.dir * lasso.speed * dt;
      if (lasso.pos > 1) { lasso.pos = 1; lasso.dir = -1; }
      if (lasso.pos < 0) { lasso.pos = 0; lasso.dir = 1; }
      UI.updateLasso(lasso);
    } else if (!UI.isModalOpen()) {
      time += dt;
      lassoCd = Math.max(0, lassoCd - dt);
      updatePlayer(dt);
      updateHerd(dt);
      updateOwned(dt);
      if (ex) {
        if (!mounted()) ex = null;
        else if (!inArena()) cancelExercise('Ты выехала из манежа — упражнение прервано');
        else if (ex.type === 'cav') updateCav(dt);
        else updateDres(dt);
      }
      floats.forEach(f => (f.t += dt));
      floats = floats.filter(f => f.t < 1.4);
      saveT += dt;
      if (saveT > 8) { saveT = 0; save(); }
    }
    render();
    hudT -= dt;
    if (hudT <= 0) {
      hudT = 0.1;
      const m = mounted();
      UI.updateHud({
        money: S.money, count: S.horses.length, max: MAX_STALLS, stats: S.stats, hint: hint(),
        prompt: computePrompt(), canLasso: !!nearestCatchable() && !lasso,
        mounted: m ? { name: m.name, gait: S.player.gait, energy: m.energy } : null,
        led: led ? led.name : null, exercise: exerciseHud(),
      });
    }
    requestAnimationFrame(frame);
  }

  const api = {
    get S() { return S; }, FOOD, TACK, TESTS, COLORS, GAITS, MAX_STALLS, act,
    wild: () => wild, led: () => led, exercise: () => ex, time: () => time, view: () => ({ x: cam.x, y: cam.y, w: viewW, h: viewH }),
    mounted, byId, freeStall, horseInStall, atFarm,
    nearSell: () => dist(S.player, { x: World.SELL.x + World.SELL.w / 2, y: World.SELL.y + World.SELL.h / 2 }) < 170,
    resolveLasso, save,
  };

  function start() {
    canvas = document.getElementById('game');
    ctx = canvas.getContext('2d');
    mmctx = document.getElementById('minimap').getContext('2d');
    S = load();
    spawnHerd();
    resize();
    addEventListener('resize', resize);
    addEventListener('keydown', e => onKey(e, true));
    addEventListener('keyup', e => onKey(e, false));
    addEventListener('blur', () => keys.clear());
    canvas.addEventListener('pointerdown', e => { canvas.setPointerCapture?.(e.pointerId); onPointer(e, 'down'); });
    canvas.addEventListener('pointermove', e => onPointer(e, 'move'));
    canvas.addEventListener('pointerup', e => onPointer(e, 'up'));
    canvas.addEventListener('pointercancel', e => onPointer(e, 'up'));
    addEventListener('beforeunload', save);
    document.addEventListener('visibilitychange', () => { if (document.hidden) save(); });
    UI.init(api);
    if (!S.seenHelp) { S.seenHelp = true; UI.openHelp(); }
    requestAnimationFrame(ts => { last = ts; requestAnimationFrame(frame); });
  }

  return Object.assign(api, { start });
})();

/* Простые звуки без файлов */
const Sound = (() => {
  let ac = null, on = true;
  function tone(freq, dur, type = 'sine', vol = 0.12, delay = 0) {
    if (!on) return;
    try {
      ac = ac || new (window.AudioContext || window.webkitAudioContext)();
      const t0 = ac.currentTime + delay;
      const o = ac.createOscillator(), g = ac.createGain();
      o.type = type; o.frequency.setValueAtTime(freq, t0);
      g.gain.setValueAtTime(vol, t0);
      g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
      o.connect(g); g.connect(ac.destination);
      o.start(t0); o.stop(t0 + dur);
    } catch (e) { /* звук недоступен */ }
  }
  return {
    tick: () => tone(880, 0.12, 'triangle'),
    coin: () => { tone(988, 0.1, 'square', 0.06); tone(1319, 0.25, 'square', 0.06, 0.08); },
    fail: () => { tone(220, 0.25, 'sawtooth', 0.07); tone(160, 0.35, 'sawtooth', 0.07, 0.15); },
    thud: () => tone(110, 0.2, 'triangle', 0.2),
    whoosh: () => tone(500, 0.2, 'sine', 0.05),
    fanfare: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 0.25, 'triangle', 0.1, i * 0.11)),
    toggle() { on = !on; return on; },
    get on() { return on; },
  };
})();

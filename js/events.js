'use strict';
/*
 * Случайные события: дождь (и радуга после него), зайчики, подкова на счастье,
 * потерявшаяся лошадь, ярмарка и приглашение на скачки.
 * Скачки: случайная трасса в большом поле и три соперника на лошадях.
 */
const Events = (() => {
  let G = null;
  const rand = (a, b) => a + Math.random() * (b - a);
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const pick = arr => arr[Math.floor(Math.random() * arr.length)];

  let nextT = rand(35, 60);
  let rain = null, wet = 0, rainbowT = 0;
  let bunnies = [];
  let shoe = null;
  let fairT = 0, invite = 0;
  let race = null, pending = null, raceId = 0;
  let drops = [];

  const START = { x: 1840, y: 560 }; // вокруг старта деревьев нет (см. world.js)
  const RIDERS = ['Маша', 'Лиза', 'Артём', 'Даня', 'Соня', 'Вика', 'Тимур', 'Полина', 'Ника', 'Егор', 'Алиса', 'Миша'];
  const SHIRTS = ['#4dabf7', '#ffa94d', '#69db7c', '#9775fa', '#ffd43b', '#f06595', '#20c997', '#e8590c'];
  const HELMETS = ['#212529', '#1c7ed6', '#c92a2a', '#2b8a3e', '#5f3dc4', '#e67700'];

  function init(api) { G = api; }

  /* ================= расписание событий ================= */
  function canRace() {
    const S = G.S;
    return S.tack.saddle && S.tack.bridle && S.horses.some(h => Horses.isAdult(h));
  }

  function fireRandom() {
    const opts = [];
    if (!rain) opts.push(['rain', 3]);
    if (bunnies.length < 3) opts.push(['bunnies', 3]);
    if (canRace() && !race && invite <= 0) opts.push(['race', 2]);
    if (!shoe) opts.push(['shoe', 1.5]);
    if (fairT <= 0 && G.S.horses.length) opts.push(['fair', 1]);
    opts.push(['lost', 1]);
    let total = opts.reduce((s, o) => s + o[1], 0), r = Math.random() * total;
    for (const [k, w] of opts) { r -= w; if (r <= 0) return start(k); }
  }

  function start(kind) {
    if (kind === 'rain') {
      rain = { t: rand(45, 90) };
      UI.toast('🌧️ Пошёл дождь! Лошади в леваде пачкаются быстрее.');
    } else if (kind === 'bunnies') {
      spawnBunnies(3 + Math.floor(Math.random() * 3));
      UI.toast('🐰 На лугу появились зайчики! Поймай зайчика — он принесёт подарок.');
    } else if (kind === 'race') {
      invite = 150;
      UI.toast('🏁 Приглашение на скачки! Приз двойной — подъезжай к стартовому столбу у поля.', 'good');
      Sound.fanfare();
    } else if (kind === 'shoe') {
      shoe = randomGrass(World.FIELD, 120) || { x: 1500, y: 900 };
      shoe.t = 120;
      UI.toast('✨ Где-то в поле блестит подкова на счастье! Посмотри на миникарте.');
    } else if (kind === 'fair') {
      fairT = 90;
      UI.toast('🎪 Ярмарка! Полторы минуты торговец платит за лошадей на 30% больше.', 'good');
    } else if (kind === 'lost') {
      const h = G.makeWild(1700, rand(700, 1000));
      h.temper = 0.05;
      h.lost = true;
      h.slot = { x: rand(-150, 150), y: rand(-110, 110) };
      G.wild().push(h);
      UI.toast(`🐴 У края поля бродит потерявшаяся лошадь по кличке ${h.name}. Она совсем ручная!`);
    }
  }

  function randomGrass(area, margin) {
    for (let i = 0; i < 60; i++) {
      const x = rand(area.x + margin, area.x + area.w - margin), y = rand(area.y + margin, area.y + area.h - margin);
      if (World.inPond(x, y, 60) || World.TREES.some(t => Math.hypot(t.x - x, t.y - y) < 40)) continue;
      return { x, y };
    }
    return null;
  }

  /* ================= зайчики ================= */
  const BUNNY_COLORS = [['#b08d6a', '#e9dcc8'], ['#8a7f75', '#d9d2ca'], ['#f1ede6', '#ffffff'], ['#5e4b3c', '#cbb9a4']];
  function spawnBunnies(n) {
    const areas = [World.FIELD, { x: 1000, y: 1150, w: 650, h: 1150 }, { x: 40, y: 1850, w: 1500, h: 500 }];
    for (let i = 0; i < n; i++) {
      const p = randomGrass(pick(areas), 60);
      if (!p) continue;
      const c = pick(BUNNY_COLORS);
      bunnies.push({ x: p.x, y: p.y, angle: rand(0, 6.28), hop: 0, hopT: rand(0.5, 2), tx: p.x, ty: p.y, life: rand(80, 120), color: c[0], belly: c[1], state: 'idle', fade: 1, z: 0 });
    }
  }

  function updateBunnies(dt) {
    const p = G.S.player, m = G.mounted();
    for (const b of bunnies) {
      b.life -= dt;
      if (b.state === 'gone') { b.fade -= dt * 1.5; continue; }
      if (b.life <= 0) b.state = 'leaving';
      const d = dist(b, p);
      const scared = d < (m ? 150 : 115);
      b.hopT -= dt;
      if (b.hopT <= 0 && b.hop <= 0) {
        let a;
        if (scared || b.state === 'leaving') a = Math.atan2(b.y - p.y, b.x - p.x) + rand(-0.6, 0.6);
        else a = b.angle + rand(-1.5, 1.5);
        const len = scared ? rand(60, 90) : rand(15, 40);
        b.tx = b.x + Math.cos(a) * len; b.ty = b.y + Math.sin(a) * len;
        b.angle = a;
        b.hop = 1;
        b.hopT = scared ? rand(0.05, 0.25) : rand(0.8, 2.5);
      }
      if (b.hop > 0) {
        const sp = scared ? 6.5 : 4;
        b.hop = Math.max(0, b.hop - dt * sp);
        const k = Math.min(1, dt * sp * 1.6);
        b.x += (b.tx - b.x) * k; b.y += (b.ty - b.y) * k;
        b.z = Math.sin((1 - b.hop) * Math.PI) * 8;
        World.collide(b, 6);
      } else b.z = 0;
      if (d < (m ? 34 : 24) && b.state !== 'leaving') catchBunny(b);
      if (b.state === 'leaving' && d > 900) b.state = 'gone';
    }
    bunnies = bunnies.filter(b => b.fade > 0 && b.life > -40);
  }

  function catchBunny(b) {
    const S = G.S;
    b.state = 'gone';
    S.stats.bunnies = (S.stats.bunnies || 0) + 1;
    const r = Math.random();
    let gift;
    if (r < 0.35) { S.inv.carrot = (S.inv.carrot || 0) + 2; gift = '2 морковки 🥕'; }
    else if (r < 0.6) { S.inv.apple = (S.inv.apple || 0) + 1; gift = 'яблоко 🍎'; }
    else if (r < 0.85) { const c = Math.round(rand(8, 20)); S.money += c; gift = `${c} монет 🪙`; }
    else { S.inv.sugar = (S.inv.sugar || 0) + 2; gift = '2 кусочка сахара 🍬'; }
    G.float('🐰 +' + gift, b.x, b.y - 20, '#1b8a3a');
    UI.toast(`🐰 Ты поймала зайчика! Он подарил тебе ${gift} и ускакал.`, 'good');
    Sound.coin();
  }

  /* ================= скачки ================= */
  function segClear(a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, L = Math.hypot(dx, dy);
    for (let s = 0; s <= L; s += 25) {
      const x = a.x + dx * s / L, y = a.y + dy * s / L;
      if (World.inPond(x, y, 70)) return false;
    }
    for (const t of World.TREES) {
      const tt = clamp(((t.x - a.x) * dx + (t.y - a.y) * dy) / (L * L), 0, 1);
      if (Math.hypot(a.x + dx * tt - t.x, a.y + dy * tt - t.y) < 50) return false;
    }
    return true;
  }

  function makeTrack() {
    const F = World.FIELD, m = 170;
    for (let attempt = 0; attempt < 200; attempt++) {
      const n = 6 + Math.floor(Math.random() * 4);
      const pts = [{ x: START.x + 40, y: START.y }];
      let ang = rand(-0.5, 0.9), ok = true;
      for (let i = 0; i < n && ok; i++) {
        let placed = false;
        for (let k = 0; k < 30; k++) {
          const a = ang + rand(-1.2, 1.2), len = rand(380, 700);
          const prev = pts[pts.length - 1];
          const q = { x: prev.x + Math.cos(a) * len, y: prev.y + Math.sin(a) * len };
          if (q.x < F.x + m || q.x > F.x + F.w - m || q.y < F.y + m || q.y > F.y + F.h - m) continue;
          if (pts.some(o => dist(o, q) < 260)) continue;
          if (!segClear(prev, q)) continue;
          pts.push(q); ang = a; placed = true; break;
        }
        if (!placed) ok = false;
      }
      if (!ok) continue;
      const fin = { x: START.x + 60, y: START.y + 50 };
      if (!segClear(pts[pts.length - 1], fin)) continue;
      pts.push(fin);
      const gates = pts.slice(1).map((g, i, arr) => {
        const prev = i ? arr[i - 1] : pts[0];
        return { x: g.x, y: g.y, a: Math.atan2(g.y - prev.y, g.x - prev.x), n: i + 1, finish: i === arr.length - 1 };
      });
      return { start: pts[0], dir: Math.atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x), gates };
    }
    return null;
  }

  function makeRivals(playerHorse) {
    const riders = RIDERS.slice().sort(() => Math.random() - 0.5);
    const breeds = ['akhal', 'arab', 'orlov', 'trakehner', 'budyonny', 'paint', 'appaloosa', 'haflinger', 'friesian'];
    const my = Horses.skill(playerHorse, 'speed');
    return [0, 1, 2].map(i => {
      const h = Horses.create({ breed: pick(breeds), age: rand(5, 10) });
      // соперники примерно твоего уровня: кто-то быстрее, кто-то медленнее
      h.base.speed = Math.round(clamp(my + rand(-12, 15), 35, 98));
      h.state = 'rival';
      return {
        h, rider: riders[i],
        look: { pad: pick(SHIRTS), helmet: pick(HELMETS), shirt: pick(SHIRTS), boots: Math.random() < 0.5 ? '#ffffff' : null },
        form: rand(0.9, 1.0), off: rand(-28, 28), i: 0, done: null,
      };
    });
  }

  function prepareRace() {
    const m = G.mounted();
    if (!m) { UI.toast('Для скачек сядь на лошадь'); return null; }
    const track = makeTrack();
    if (!track) { UI.toast('Не получилось проложить трассу, попробуй ещё раз', 'warn'); return null; }
    pending = { track, rivals: makeRivals(m), bonus: invite > 0 ? 2 : 1 };
    return pending;
  }

  function startRace() {
    const m = G.mounted();
    if (!pending || !m) return;
    UI.closeModal();
    const { track, rivals, bonus } = pending;
    pending = null;
    if (invite > 0) invite = 0;
    const perp = track.dir + Math.PI / 2;
    const slot = k => ({
      x: track.start.x - Math.cos(track.dir) * 70 + Math.cos(perp) * (k - 1.5) * 55,
      y: track.start.y - Math.sin(track.dir) * 70 + Math.sin(perp) * (k - 1.5) * 55,
    });
    const order = [0, 1, 2, 3].sort(() => Math.random() - 0.5);
    rivals.forEach((r, i) => {
      const s = slot(order[i]);
      Object.assign(r.h, { x: s.x, y: s.y, angle: track.dir, vx: 0, vy: 0, spd: 0 });
    });
    race = { id: ++raceId, track, rivals, bonus, state: 'countdown', t: 0, count: 3, i: 0, slot: slot(order[3]), finishOrder: [] };
    G.act.setGait(2);
    UI.toast('🏁 На старт! Скачи галопом через ворота по порядку номеров. Жёлтая стрелка покажет дорогу.');
  }

  function cancelRace(msg) {
    if (!race) return;
    race = null;
    if (msg) UI.toast(msg, 'warn');
  }

  function rivalSpeed(r) {
    const base = 250 * (0.75 + Horses.skill(r.h, 'speed') / 200);
    const ahead = r.i - race.i;
    const band = ahead >= 2 ? 0.94 : ahead <= -1 ? 1.08 : 1;
    const tired = 1 - Math.min(0.08, race.t / 900);
    return base * r.form * band * tired * (0.97 + Math.sin(race.t * 0.7 + r.off) * 0.03);
  }

  function updateRace(dt) {
    const p = G.S.player, m = G.mounted();
    if (!m) return cancelRace('Ты слезла с лошади — скачки прерваны');
    const T = race.track;
    if (race.state === 'countdown') {
      const before = Math.ceil(race.count);
      race.count -= dt;
      p.x = race.slot.x; p.y = race.slot.y; p.vx = p.vy = 0; p.angle = T.dir; p.target = null;
      const now = Math.ceil(race.count);
      if (now !== before && now > 0) { G.float(String(now), p.x, p.y - 40, '#c92a2a'); Sound.tick(); }
      if (race.count <= 0) { race.state = 'run'; G.float('Марш!', p.x, p.y - 40, '#1b8a3a'); Sound.fanfare(); }
      return;
    }
    if (race.state !== 'run') return;
    race.t += dt;
    // игрок проходит ворота
    const g = T.gates[race.i];
    if (g && dist(p, g) < 80) {
      race.i++;
      Sound.tick();
      if (race.i >= T.gates.length) return finishRace();
      G.float(`Ворота ${g.n} ✔`, g.x, g.y - 40, '#1b8a3a');
    }
    // соперники
    for (const r of race.rivals) {
      const h = r.h;
      if (r.done != null) {
        // после финиша — шагом в сторону
        h.vx *= 0.96; h.vy *= 0.96;
        h.x += h.vx * dt; h.y += h.vy * dt;
        h.spd = Math.hypot(h.vx, h.vy);
        h.phase += dt * (3 + h.spd * 0.045) * (h.spd > 4 ? 1 : 0);
        continue;
      }
      const tg = T.gates[r.i];
      const perp = tg.a + Math.PI / 2;
      const tx = tg.x + Math.cos(perp) * r.off, ty = tg.y + Math.sin(perp) * r.off;
      const dx = tx - h.x, dy = ty - h.y, d = Math.hypot(dx, dy) || 1;
      let sp = rivalSpeed(r);
      // не сталкиваться друг с другом и с игроком
      let ax = dx / d, ay = dy / d;
      for (const o of [...race.rivals.map(q => q.h), p]) {
        if (o === h) continue;
        const ox = h.x - o.x, oy = h.y - o.y, od = Math.hypot(ox, oy);
        if (od < 50 && od > 0.1) { ax += ox / od * 0.5; ay += oy / od * 0.5; }
      }
      const al = Math.hypot(ax, ay) || 1;
      const k = Math.min(1, dt * 3.5);
      h.vx += (ax / al * sp - h.vx) * k;
      h.vy += (ay / al * sp - h.vy) * k;
      h.x += h.vx * dt; h.y += h.vy * dt;
      World.collide(h, 18);
      h.spd = Math.hypot(h.vx, h.vy);
      if (h.spd > 6) {
        let da = Math.atan2(h.vy, h.vx) - h.angle;
        while (da > Math.PI) da -= Math.PI * 2;
        while (da < -Math.PI) da += Math.PI * 2;
        h.angle += da * Math.min(1, dt * 6);
      }
      h.phase += dt * (3 + h.spd * 0.045);
      if (d < 70) {
        r.i++;
        if (r.i >= T.gates.length) { r.done = race.t; race.finishOrder.push(r); }
      }
    }
  }

  function progress(i, x, y) {
    const T = race.track;
    if (i >= T.gates.length) return 1e9;
    return i * 1e5 - Math.hypot(T.gates[i].x - x, T.gates[i].y - y);
  }
  function standings() {
    const p = G.S.player;
    const list = race.rivals.map(r => ({ name: r.rider, horse: r.h.name, done: r.done, score: r.done != null ? 1e9 - r.done : progress(r.i, r.h.x, r.h.y), me: false }));
    list.push({ name: 'Ты', horse: G.mounted() ? G.mounted().name : '', done: race.myTime != null ? race.myTime : null, score: race.myTime != null ? 1e9 - race.myTime : progress(race.i, p.x, p.y), me: true });
    return list.sort((a, b) => b.score - a.score);
  }

  function finishRace() {
    const m = G.mounted(), S = G.S;
    race.myTime = race.t;
    const table = standings();
    const place = table.findIndex(x => x.me) + 1;
    const prize = [100, 50, 25, 5][place - 1] * race.bonus;
    const medal = ['gold', 'silver', 'bronze', null][place - 1];
    S.money += prize;
    if (medal) S.stats[medal]++;
    S.stats.races = (S.stats.races || 0) + 1;
    if (place === 1) S.stats.wins = (S.stats.wins || 0) + 1;
    Horses.addTrain(m, 'speed', 1 + (4 - place) * 0.8);
    Horses.addTrain(m, 'stamina', 1);
    m.energy = clamp(m.energy - 20, 0, 100);
    const res = { place, prize, medal, time: race.t, bonus: race.bonus, table, gates: race.track.gates.length };
    race.state = 'done';
    setTimeout(() => { race = null; }, 6000);
    UI.raceResult(res);
    if (place <= 3) Sound.fanfare(); else Sound.tick();
  }

  /* ================= общий шаг ================= */
  function update(dt) {
    nextT -= dt;
    if (nextT <= 0) { nextT = rand(60, 120); fireRandom(); }
    if (rain) {
      rain.t -= dt;
      wet = Math.min(1, wet + dt * 0.25);
      for (const h of G.S.horses) if (h.state === 'paddock') { h.clean = Math.max(0, h.clean - dt * 0.35); h.mood = Math.max(0, h.mood - dt * 0.04); }
      if (rain.t <= 0) {
        rain = null;
        if (G.daylight() > 0.5) { rainbowT = 30; UI.toast('🌈 Дождь закончился — смотри, радуга!', 'good'); }
        else UI.toast('Дождь закончился');
      }
    } else wet = Math.max(0, wet - dt * 0.2);
    rainbowT = Math.max(0, rainbowT - dt);
    fairT = Math.max(0, fairT - dt);
    if (fairT > 0 && fairT - dt <= 0) UI.toast('Ярмарка закончилась');
    if (invite > 0) { invite -= dt; if (invite <= 0) UI.toast('Приглашение на скачки истекло — но скакать можно и просто так'); }
    if (shoe) {
      shoe.t -= dt;
      if (dist(shoe, G.S.player) < 40) {
        const c = Math.round(rand(30, 60));
        G.S.money += c;
        G.float(`🍀 +${c} 🪙`, shoe.x, shoe.y - 20, '#1b8a3a');
        UI.toast(`🍀 Подкова на счастье! +${c} монет`, 'good');
        Sound.fanfare();
        shoe = null;
      } else if (shoe.t <= 0) shoe = null;
    }
    updateBunnies(dt);
    if (race) updateRace(dt);
  }

  /* ================= подсказки и кнопки ================= */
  function nearStart() { return dist(G.S.player, START) < 130; }
  function prompt() {
    if (race || !nearStart()) return null;
    if (!G.mounted()) return { label: '🏁 Скачки', fn: () => UI.toast('Для скачек сядь на лошадь в конюшне') };
    return { label: invite > 0 ? '🏁 Скачки (приз ×2!)' : '🏁 Скачки', fn: () => { if (prepareRace()) UI.openRace(pending); } };
  }
  function hud() {
    if (!race) return null;
    const T = race.track, p = G.S.player;
    if (race.state === 'countdown') return { title: '🏁 Скачки', line: `Ворот: ${T.gates.length}. Старт через ${Math.ceil(race.count)}…`, hint: 'Приготовься! Галоп — клавиша 3', ok: true, letter: String(Math.max(1, Math.ceil(race.count))) };
    if (race.state === 'done') return null;
    const table = standings();
    const place = table.findIndex(x => x.me) + 1;
    const g = T.gates[Math.min(race.i, T.gates.length - 1)];
    return {
      title: race.bonus > 1 ? '🏁 Скачки (приз ×2)' : '🏁 Скачки',
      line: `Ворота ${race.i + 1}/${T.gates.length}${g.finish ? ' — ФИНИШ' : ''} · место: ${place} из 4 · ${race.t.toFixed(1)} с`,
      hint: G.S.player.gait === 2 ? 'Галоп ✔ Держись жёлтой стрелки' : 'Быстрее! Переходи на ГАЛОП (клавиша 3)',
      ok: G.S.player.gait === 2, letter: g.finish ? '🏁' : String(g.n),
    };
  }

  /* ================= рисование 2D ================= */
  function drawGate(ctx, g, state) {
    ctx.save();
    ctx.translate(g.x, g.y);
    ctx.rotate(g.a);
    const half = 55;
    if (state === 'next') {
      ctx.fillStyle = 'rgba(255,212,59,0.3)';
      ctx.beginPath(); ctx.ellipse(0, 0, 40, half + 14, 0, 0, Math.PI * 2); ctx.fill();
    }
    // лента: на финише — клетчатая
    const n = 10, seg = (half * 2) / n;
    for (let k = 0; k < n; k++) {
      ctx.fillStyle = g.finish ? (k % 2 ? '#111' : '#fff') : (k % 2 ? '#fff' : state === 'done' ? '#2b8a3e' : '#1c7ed6');
      ctx.fillRect(-3, -half + k * seg, 6, seg + 0.5);
    }
    for (const yy of [-half, half]) {
      Draw.fillEll(ctx, 2, yy + 2, 6, 6, 'rgba(0,0,0,0.25)');
      Draw.fillEll(ctx, 0, yy, 6, 6, '#f8f9fa');
      ctx.fillStyle = yy > 0 ? '#e03131' : '#ffffff';
      ctx.beginPath(); ctx.moveTo(0, yy); ctx.lineTo(-16, yy + (yy > 0 ? 5 : -5)); ctx.lineTo(0, yy + (yy > 0 ? 10 : -10)); ctx.fill();
    }
    ctx.restore();
    Draw.label(ctx, g.finish ? '🏁 ФИНИШ' : String(g.n), g.x, g.y - 75, g.finish ? 15 : 17, state === 'next' ? '#b35c00' : '#2b2b2b');
  }

  function drawBunny(ctx, b, t) {
    ctx.save();
    ctx.globalAlpha = clamp(b.fade, 0, 1);
    ctx.translate(b.x, b.y);
    Draw.fillEll(ctx, 1, 2, 9 - b.z * 0.3, 6 - b.z * 0.2, 'rgba(0,0,0,0.18)');
    ctx.translate(0, -b.z);
    ctx.rotate(b.angle);
    const s = 1 + b.z * 0.02;
    ctx.scale(s, s);
    Draw.fillEll(ctx, -6, 0, 3.2, 3.2, '#ffffff');               // хвостик
    Draw.fillEll(ctx, 0, 0, 7.5, 5.2, b.color);                  // тело
    Draw.fillEll(ctx, 0.5, 0, 4.5, 3, b.belly);
    Draw.fillEll(ctx, 7, 0, 3.6, 3.3, b.color);                  // голова
    const wig = b.hop > 0 ? 0.2 : Math.sin(t * 4 + b.x) * 0.15;
    Draw.fillEll(ctx, 2.5, -2.4, 5.5, 1.5, b.color, -0.25 + wig);  // уши
    Draw.fillEll(ctx, 2.5, 2.4, 5.5, 1.5, b.color, 0.25 - wig);
    Draw.fillEll(ctx, 2.8, -2.4, 3.6, 0.7, '#f3b8b8', -0.25 + wig);
    Draw.fillEll(ctx, 2.8, 2.4, 3.6, 0.7, '#f3b8b8', 0.25 - wig);
    Draw.fillEll(ctx, 10, 0, 0.9, 0.9, '#e07a8a');
    ctx.restore();
  }

  function drawShoe(ctx, t) {
    if (!shoe) return;
    ctx.save();
    ctx.translate(shoe.x, shoe.y);
    ctx.strokeStyle = '#adb5bd';
    ctx.lineWidth = 5;
    ctx.beginPath(); ctx.arc(0, 0, 10, Math.PI * 0.15, Math.PI * 1.85, true); ctx.stroke();
    ctx.strokeStyle = '#e9ecef'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.arc(0, 0, 10, Math.PI * 0.15, Math.PI * 1.85, true); ctx.stroke();
    const sp = 10 + Math.sin(t * 6) * 4;
    ctx.strokeStyle = 'rgba(255,230,90,0.95)'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(-sp, -sp); ctx.lineTo(sp, sp); ctx.moveTo(sp, -sp); ctx.lineTo(-sp, sp); ctx.stroke();
    ctx.restore();
  }

  function drawStartPost(ctx, t) {
    ctx.save();
    ctx.translate(START.x, START.y);
    Draw.fillEll(ctx, 3, 4, 10, 7, 'rgba(0,0,0,0.2)');
    Draw.fillEll(ctx, 0, 0, 7, 7, '#495057');
    for (let i = 0; i < 4; i++) for (let j = 0; j < 3; j++) {
      ctx.fillStyle = (i + j) % 2 ? '#111' : '#fff';
      ctx.fillRect(2 + i * 6, -20 + j * 6 + Math.sin(t * 4 + i) * 1.5, 6, 6);
    }
    ctx.restore();
    Draw.label(ctx, invite > 0 ? '🏁 СКАЧКИ ×2' : '🏁 СКАЧКИ', START.x, START.y - 38, 15, invite > 0 ? '#c92a2a' : '#3b2a1a');
  }

  // всё, что лежит на земле, — под лошадьми
  function draw2d(ctx, visible, t) {
    drawStartPost(ctx, t);
    if (race) {
      const T = race.track;
      ctx.strokeStyle = 'rgba(255,255,255,0.35)';
      ctx.lineWidth = 4;
      ctx.setLineDash([14, 14]);
      ctx.beginPath(); ctx.moveTo(T.start.x, T.start.y);
      for (const g of T.gates) ctx.lineTo(g.x, g.y);
      ctx.stroke();
      ctx.setLineDash([]);
      T.gates.forEach((g, i) => { if (visible(g.x, g.y, 120)) drawGate(ctx, g, i < race.i ? 'done' : i === race.i ? 'next' : ''); });
    }
    drawShoe(ctx, t);
    for (const b of bunnies) if (visible(b.x, b.y, 30)) drawBunny(ctx, b, t);
  }

  // стрелка к следующим воротам и подписи соперников
  function drawArrow2d(ctx, t) {
    if (!race || race.state === 'done') return;
    const p = G.S.player, g = race.track.gates[Math.min(race.i, race.track.gates.length - 1)];
    const a = Math.atan2(g.y - p.y, g.x - p.x);
    ctx.save();
    ctx.translate(p.x + Math.cos(a) * 80, p.y + Math.sin(a) * 80);
    ctx.rotate(a);
    ctx.fillStyle = 'rgba(255,212,0,0.95)'; ctx.strokeStyle = 'rgba(90,60,0,0.8)'; ctx.lineWidth = 2;
    const b = Math.sin(t * 6) * 4;
    ctx.beginPath(); ctx.moveTo(20 + b, 0); ctx.lineTo(-6 + b, -14); ctx.lineTo(-6 + b, 14); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.restore();
    for (const r of race.rivals) Draw.label(ctx, r.rider, r.h.x, r.h.y - 50, 12, '#1c4f8a');
  }

  // дождь и радуга — поверх всего, в экранных координатах (для любой графики)
  function drawScreen(ctx, w, h, k, t) {
    if (rainbowT > 0) {
      const a = Math.min(1, rainbowT / 5) * 0.32;
      const cols = ['#ff0000', '#ff8000', '#ffff00', '#00c000', '#0080ff', '#4b0082', '#8f00ff'];
      ctx.save();
      ctx.globalAlpha = a;
      ctx.lineWidth = 14 * k;
      cols.forEach((c, i) => {
        ctx.strokeStyle = c;
        ctx.beginPath(); ctx.arc(w * 0.62, h * 0.95, h * 0.85 - i * 14 * k, Math.PI * 1.08, Math.PI * 1.92); ctx.stroke();
      });
      ctx.restore();
    }
    if (wet <= 0.01) return;
    ctx.fillStyle = `rgba(60,75,95,${0.22 * wet})`;
    ctx.fillRect(0, 0, w, h);
    const n = Math.floor(260 * wet * (w * h) / (1280 * 800));
    while (drops.length < n) drops.push({ x: Math.random() * w, y: Math.random() * h, s: 0.7 + Math.random() * 0.6 });
    drops.length = Math.min(drops.length, n);
    ctx.strokeStyle = 'rgba(200,215,235,0.55)';
    ctx.lineWidth = 1.2 * k;
    ctx.beginPath();
    for (const d of drops) {
      d.y += 22 * d.s * k; d.x -= 4 * d.s * k;
      if (d.y > h) { d.y = -20; d.x = Math.random() * w * 1.1; }
      ctx.moveTo(d.x, d.y); ctx.lineTo(d.x + 4 * d.s * k, d.y - 18 * d.s * k);
    }
    ctx.stroke();
  }

  function drawMinimap(m, k) {
    if (race) {
      for (const [i, g] of race.track.gates.entries()) {
        m.fillStyle = i === race.i ? '#ffd43b' : i < race.i ? '#2b8a3e' : '#1c7ed6';
        m.fillRect(g.x * k - 2, g.y * k - 2, 4, 4);
      }
      m.fillStyle = '#ff922b';
      for (const r of race.rivals) { m.beginPath(); m.arc(r.h.x * k, r.h.y * k, 2.5, 0, Math.PI * 2); m.fill(); }
    }
    m.fillStyle = '#ffffff';
    for (const b of bunnies) m.fillRect(b.x * k - 1, b.y * k - 1, 2, 2);
    if (shoe) { m.fillStyle = '#ffe066'; m.beginPath(); m.arc(shoe.x * k, shoe.y * k, 3, 0, Math.PI * 2); m.fill(); }
    m.fillStyle = '#111'; m.fillRect(START.x * k - 2, START.y * k - 4, 4, 4);
  }

  // предпросмотр трассы в окне скачек
  function drawPreview(c, info) {
    const g = c.getContext('2d'), F = World.FIELD;
    const k = Math.min(c.width / (F.w + 260), c.height / F.h);
    const ox = -(F.x - 200) * k, oy = -F.y * k;
    g.fillStyle = '#9ccb6c'; g.fillRect(0, 0, c.width, c.height);
    g.fillStyle = '#3f8fc0';
    g.beginPath(); g.ellipse(World.POND.x * k + ox, World.POND.y * k + oy, World.POND.rx * k, World.POND.ry * k, 0, 0, Math.PI * 2); g.fill();
    g.fillStyle = '#4f8f3a';
    for (const t of World.TREES) if (t.x > F.x - 200) { g.beginPath(); g.arc(t.x * k + ox, t.y * k + oy, 3, 0, Math.PI * 2); g.fill(); }
    const T = info.track;
    g.strokeStyle = '#ffffff'; g.lineWidth = 3; g.setLineDash([6, 5]);
    g.beginPath(); g.moveTo(T.start.x * k + ox, T.start.y * k + oy);
    for (const q of T.gates) g.lineTo(q.x * k + ox, q.y * k + oy);
    g.stroke(); g.setLineDash([]);
    g.font = 'bold 11px system-ui, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
    for (const q of T.gates) {
      g.fillStyle = q.finish ? '#111' : '#1c7ed6';
      g.beginPath(); g.arc(q.x * k + ox, q.y * k + oy, 8, 0, Math.PI * 2); g.fill();
      g.fillStyle = '#fff'; g.fillText(q.finish ? 'F' : String(q.n), q.x * k + ox, q.y * k + oy + 1);
    }
    g.fillStyle = '#e03131';
    g.beginPath(); g.arc(T.start.x * k + ox, T.start.y * k + oy, 6, 0, Math.PI * 2); g.fill();
  }

  /* ================= для 3D и интерфейса ================= */
  function rivals() {
    if (!race) return [];
    return race.rivals.map(r => ({ h: r.h, rider: r.look, gait: r.h.spd > 190 ? 2 : r.h.spd > 90 ? 1 : 0, name: r.rider }));
  }
  function gates() {
    if (!race) return null;
    return { id: race.id, next: race.i, list: race.track.gates };
  }
  function findHorse(id) {
    const src = race ? race.rivals : pending ? pending.rivals : [];
    const r = src.find(x => x.h.id === id);
    return r ? r.h : null;
  }

  return {
    init, update, prompt, hud, startRace, cancelRace, prepareRace, rivals, gates, findHorse,
    draw2d, drawArrow2d, drawScreen, drawMinimap, drawPreview,
    weather: () => wet, raining: () => !!rain, bunnies: () => bunnies, shoe: () => shoe, START,
    busy: () => !!race, priceMul: () => (fairT > 0 ? 1.3 : 1), fair: () => fairT > 0,
    get pending() { return pending; },
    nextGate() { return race && race.state !== 'done' ? race.track.gates[Math.min(race.i, race.track.gates.length - 1)] : null; },
    debugStart: start,
  };
})();

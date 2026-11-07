'use strict';
/*
 * Привидения в пещере: летают сквозь стены и пугают «Бу!», но ничего плохого не делают.
 * Олени бегают стадами в лесах и степи, птицы летают стаями над миром.
 */
const Creatures = (() => {
  let G = null;
  const ghosts = [];
  const rand = (a, b) => a + Math.random() * (b - a);
  const BOO = ['👻 Бу-у-у! Привидение пролетело сквозь тебя!', '👻 Уууу! Ой, как щекотно и холодно!', '👻 Бу! Привидение засмеялось и улетело.', '👻 Хи-хи! Привидение спряталось в стене.'];

  function spot() {
    const C = World.CAVE;
    return { x: rand(C.x + 150, C.x + C.w - 150), y: rand(C.y + 150, C.y + C.h - 150) };
  }
  /* ---------- олени ---------- */
  const deer = [], herds = [], birds = [];
  const DEER_HOMES = () => [
    { area: World.STEPPE, reg: 'steppe' }, { area: World.STEPPE, reg: 'steppe' }, { area: World.FOXWOOD, reg: 'foxwood' },
    { area: World.FOREST[0], reg: 'forest' }, { area: World.FOREST[0], reg: 'forest' }, { area: World.LAKELAND, reg: 'lake' }, { area: World.GROTTO, reg: 'grotto' },
  ];
  function deerSpot(H) {
    const A = H.area;
    for (let i = 0; i < 40; i++) {
      const x = rand(A.x + 150, A.x + A.w - 150), y = rand(A.y + 150, A.y + A.h - 150);
      if (World.regionAt(x, y) === H.reg && !World.blocked(x, y, 30)) return { x, y };
    }
    return { x: A.x + A.w / 2, y: A.y + A.h / 2 };
  }
  function initAnimals() {
    DEER_HOMES().forEach((H, k) => {
      const c = deerSpot(H);
      const herd = Object.assign({ x: c.x, y: c.y, tx: c.x, ty: c.y, t: rand(5, 15), panic: 0 }, H);
      herds.push(herd);
      const n = 3 + Math.floor(Math.random() * 3);
      for (let i = 0; i < n; i++) {
        deer.push({ id: 'deer' + k + '_' + i, herd, x: c.x + rand(-80, 80), y: c.y + rand(-60, 60), angle: rand(0, 6.28), spd: 0, phase: 0, buck: i === 0,
          slot: { x: rand(-90, 90), y: rand(-70, 70) }, flee: 0, fawn: i > 2 && Math.random() < 0.5, graze: rand(0, 4), seed: Math.floor(Math.random() * 1e6) });
      }
    });
    for (let k = 0; k < 3; k++) {
      const flock = { x: 0, y: 0, a: rand(0, 6.28), r: rand(250, 500), h: rand(14, 22), sp: rand(0.15, 0.3), col: ['#f8f9fa', '#495057', '#a0522d'][k], far: true };
      for (let i = 0; i < 7; i++) birds.push({ flock, off: { x: rand(-90, 90), y: rand(-90, 90), z: rand(-2, 2) }, phase: rand(0, 6.28), x: 0, y: 0, z: 0, angle: 0 });
    }
  }
  function updateAnimals(dt) {
    const p = G.S.player;
    for (const H of herds) {
      H.t -= dt; H.panic = Math.max(0, H.panic - dt);
      if (H.t <= 0) { const q = deerSpot(H); H.tx = q.x; H.ty = q.y; H.t = rand(15, 30); }
      const d = Math.hypot(H.tx - H.x, H.ty - H.y), sp = H.panic > 0 ? 200 : 25;
      if (d > 5) { H.x += (H.tx - H.x) / d * sp * dt; H.y += (H.ty - H.y) / d * sp * dt; }
    }
    for (const a of deer) {
      const H = a.herd;
      const dp = Math.hypot(a.x - p.x, a.y - p.y);
      if (dp < 260 && a.flee <= 0) {
        a.flee = rand(1.5, 2.5);
        if (H.panic <= 0) { const ax = H.x - p.x, ay = H.y - p.y, al = Math.hypot(ax, ay) || 1; H.tx = H.x + ax / al * 700; H.ty = H.y + ay / al * 700; H.t = rand(8, 12); }
        H.panic = 2.5;
      }
      let tx, ty, sp;
      if (a.flee > 0) {
        a.flee -= dt;
        const ax = a.x - p.x, ay = a.y - p.y, al = Math.hypot(ax, ay) || 1;
        tx = a.x + ax / al * 100; ty = a.y + ay / al * 100; sp = 230;
      } else {
        tx = H.x + a.slot.x; ty = H.y + a.slot.y;
        const gd = Math.hypot(tx - a.x, ty - a.y);
        sp = gd > 60 ? (H.panic > 0 ? 200 : gd > 200 ? 120 : 45) : 0;
        if (!sp) { a.graze -= dt; if (a.graze <= 0) { a.graze = rand(3, 8); a.slot.x += rand(-30, 30); a.slot.y += rand(-30, 30); } }
      }
      const dx = tx - a.x, dy = ty - a.y, dd = Math.hypot(dx, dy);
      const v = dd > 2 ? Math.min(sp, dd / dt) : 0;
      if (v > 0) { a.x += dx / dd * v * dt; a.y += dy / dd * v * dt; a.angle += (((Math.atan2(dy, dx) - a.angle + Math.PI * 3) % (Math.PI * 2)) - Math.PI) * Math.min(1, dt * 6); }
      a.spd = v;
      a.phase += dt * (3 + v * 0.05) * (v > 3 ? 1 : 0);
      a.head = v > 3 ? 0 : (Math.sin(G.time() * 0.4 + a.seed) > 0.3 ? -1 : 0);     // иногда щиплет траву
      World.collide(a, 14);
    }
    // птицы: стаи летают кругами недалеко от игрока
    for (const B of birds) {
      const F = B.flock;
      if (B === birds.find(q => q.flock === F)) {
        if (F.far || Math.hypot(F.x - p.x, F.y - p.y) > 2200) { F.x = p.x + rand(-900, 900); F.y = p.y + rand(-700, 700); F.far = false; }
        F.a += F.sp * dt;
        F.x += Math.cos(F.a * 0.3) * 30 * dt; F.y += Math.sin(F.a * 0.23) * 30 * dt;
      }
      const ang = F.a + B.off.x * 0.002;
      const nx = F.x + Math.cos(ang) * F.r + B.off.x, ny = F.y + Math.sin(ang) * F.r + B.off.y;
      B.angle = Math.atan2(ny - B.y, nx - B.x);
      B.x = nx; B.y = ny; B.z = F.h + B.off.z + Math.sin(G.time() + B.phase) * 0.8;
      B.phase += dt * 9;
    }
  }

  function init(api) {
    G = api;
    initAnimals();
    for (let i = 0; i < 7; i++) {
      const p = spot();
      ghosts.push({ x: p.x, y: p.y, tx: p.x, ty: p.y, t: rand(0, 6), fade: 1, cd: 0, hidden: 0, angle: 0, kind: i % 3 === 0 ? 'horse' : 'sheet', seed: Math.floor(Math.random() * 1e6) });
    }
  }
  function update(dt) {
    updateAnimals(dt);
    const p = G.S.player;
    const inCave = World.inRect(p.x, p.y, World.CAVE, 100);
    for (const g of ghosts) {
      g.t += dt;
      g.cd = Math.max(0, g.cd - dt);
      if (g.hidden > 0) {
        g.hidden -= dt;
        if (g.hidden <= 0) { const q = spot(); g.x = q.x; g.y = q.y; g.fade = 0; }
        continue;
      }
      g.fade = Math.min(1, g.fade + dt * 0.8);
      const d = Math.hypot(p.x - g.x, p.y - g.y);
      let tx = g.tx, ty = g.ty, sp = 30;
      if (inCave && d < 220 && g.cd <= 0) { tx = p.x; ty = p.y; sp = 75; }
      else if (Math.hypot(g.tx - g.x, g.ty - g.y) < 20 || Math.random() < dt * 0.1) { const q = spot(); g.tx = q.x; g.ty = q.y; }
      const dx = tx - g.x, dy = ty - g.y, l = Math.hypot(dx, dy) || 1;
      g.x += dx / l * sp * dt; g.y += dy / l * sp * dt;
      g.angle = Math.atan2(dy, dx);
      if (inCave && d < 38 && g.cd <= 0) {
        g.cd = 6;
        g.hidden = rand(4, 8);
        const ax = p.x - g.x, ay = p.y - g.y, al = Math.hypot(ax, ay) || 1;
        p.vx = (p.vx || 0) + ax / al * 260; p.vy = (p.vy || 0) + ay / al * 260;
        UI.toast(BOO[Math.floor(Math.random() * BOO.length)]);
        G.stat('ghosts');
        Sound.boo();
      }
    }
  }
  return { init, update, ghosts: () => ghosts, deer: () => deer, birds: () => birds };
})();

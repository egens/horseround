'use strict';
/* Привидения в пещере: летают сквозь стены и пугают «Бу!», но ничего плохого не делают */
const Creatures = (() => {
  let G = null;
  const ghosts = [];
  const rand = (a, b) => a + Math.random() * (b - a);
  const BOO = ['👻 Бу-у-у! Привидение пролетело сквозь тебя!', '👻 Уууу! Ой, как щекотно и холодно!', '👻 Бу! Привидение засмеялось и улетело.', '👻 Хи-хи! Привидение спряталось в стене.'];

  function spot() {
    const C = World.CAVE;
    return { x: rand(C.x + 150, C.x + C.w - 150), y: rand(C.y + 150, C.y + C.h - 150) };
  }
  function init(api) {
    G = api;
    for (let i = 0; i < 7; i++) {
      const p = spot();
      ghosts.push({ x: p.x, y: p.y, tx: p.x, ty: p.y, t: rand(0, 6), fade: 1, cd: 0, hidden: 0, angle: 0, kind: i % 3 === 0 ? 'horse' : 'sheet', seed: Math.floor(Math.random() * 1e6) });
    }
  }
  function update(dt) {
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
  return { init, update, ghosts: () => ghosts };
})();

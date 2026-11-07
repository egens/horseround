'use strict';
/*
 * Три ИИ-игрока: ездят верхом по дорогам мира, ловят диких лошадей, спешат к поезду
 * и соревнуются с тобой, кто поймает больше лошадей.
 */
const AI = (() => {
  let G = null;
  const rand = (a, b) => a + Math.random() * (b - a);
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const DEFS = [
    { name: 'Ника', look: { pad: '#f06595', helmet: '#5f3dc4', shirt: '#f06595', saddleStyle: 'crystal', saddleColor: '#e64980', bridleStyle: 'crystal', bridleColor: '#7048e8' }, breed: 'arab', skill: 0.75 },
    { name: 'Тимур', look: { pad: '#4dabf7', helmet: '#1c7ed6', shirt: '#4dabf7', saddleStyle: 'classic', saddleColor: '#5b3a1e', bridleStyle: 'classic', bridleColor: '#2b1a10' }, breed: 'akhal', skill: 0.6 },
    { name: 'Соня', look: { pad: '#ffd43b', helmet: '#e67700', shirt: '#69db7c', saddleStyle: 'plant', saddleColor: '#2b8a3e', bridleStyle: 'plant', bridleColor: '#5c940d' }, breed: 'andalusian', skill: 0.5 },
  ];
  let bots = [];
  let toastT = 0;

  function init(api) {
    G = api;
    const S = G.S;
    S.ai = S.ai || DEFS.map(() => ({ caught: 0, money: 200, best: '' }));
    const starts = [World.START, { x: World.VILLAGE.x + 600, y: World.VILLAGE.y + 400 }, { x: World.FARMLAND.x + 800, y: World.FARMLAND.y + 200 }];
    bots = DEFS.map((d, i) => {
      const h = Horses.create({ breed: d.breed, age: 7, sex: i % 2 ? 'm' : 'f' });
      h.state = 'ai';
      const st = starts[i];
      return Object.assign({ i, name: d.name, look: d.look, skill: d.skill, h, x: st.x, y: st.y, angle: 0, spd: 0, phase: 0,
        road: null, ri: 0, rdir: 1, chase: null, cd: rand(20, 40), stuckT: 0, lastX: st.x, lastY: st.y, gait: 1, stat: S.ai[i] });
    });
    bots.forEach(pickRoad);
  }

  // ездят по дорогам: в конце дороги выбирают следующую, которая начинается рядом
  function pickRoad(b) {
    const R = World.ROADS;
    const opts = [];
    R.forEach((r, k) => {
      const a = r[0], z = r[r.length - 1];
      if (Math.hypot(a[0] - b.x, a[1] - b.y) < 450) opts.push([k, 1]);
      if (Math.hypot(z[0] - b.x, z[1] - b.y) < 450) opts.push([k, -1]);
    });
    if (opts.length) {
      const [k, dir] = opts[Math.floor(Math.random() * opts.length)];
      b.road = R[k]; b.rdir = dir; b.ri = dir > 0 ? 0 : R[k].length - 1;
      return;
    }
    // дорог рядом нет — едем к ближайшей точке любой дороги
    let best = null, bd = 1e9;
    R.forEach(r => r.forEach((q, j) => { const d = Math.hypot(q[0] - b.x, q[1] - b.y); if (d < bd) { bd = d; best = [r, j]; } }));
    b.road = best[0]; b.ri = best[1]; b.rdir = Math.random() < 0.5 ? 1 : -1;
  }

  function moveTo(b, tx, ty, sp, dt) {
    const dx = tx - b.x, dy = ty - b.y, d = Math.hypot(dx, dy);
    if (d < 1) { b.spd = 0; return d; }
    const v = Math.min(sp, d / dt);
    b.x += dx / d * v * dt; b.y += dy / d * v * dt;
    b.spd = v;
    let da = Math.atan2(dy, dx) - b.angle;
    while (da > Math.PI) da -= Math.PI * 2;
    while (da < -Math.PI) da += Math.PI * 2;
    b.angle += da * Math.min(1, dt * 6);
    b.phase += dt * (3 + v * 0.045);
    World.collide(b, 18);
    return d;
  }

  function catchHorse(b, w) {
    G.removeWild(x => x === w);
    b.stat.caught++;
    const price = Math.round(Horses.price(w) * 0.6);
    b.stat.money += price;
    b.stat.best = Genetics.BREEDS[w.breed].name;
    b.cd = rand(70, 120);
    if (toastT <= 0 || dist(b, G.S.player) < 1500) {
      toastT = 25;
      UI.toast(`🤖 ${b.name} ${b.i === 1 ? 'поймал' : 'поймала'} лошадь: ${Genetics.BREEDS[w.breed].name.toLowerCase()}, ${Horses.pheno(w).name}! Всего у ${b.i === 1 ? 'него' : 'неё'}: ${b.stat.caught}`);
    }
  }

  function update(dt) {
    toastT -= dt;
    const tr = Train.state();
    for (const b of bots) {
      b.cd -= dt;
      b.h.x = b.x; b.h.y = b.y; b.h.angle = b.angle; b.h.spd = b.spd; b.h.phase = b.phase;
      // поезд стоит — все спешат к станции
      const toTrain = tr && tr.state === 'stop' && dist(b, { x: Train.STOP_X, y: World.RAIL.y }) < 9000;
      if (!b.chase && (b.cd <= 0 || toTrain)) {
        let best = null, bd = toTrain ? 2500 : 520;
        for (const w of G.wild()) {
          if (w.fly || (w.home && (w.home.startsWith('i') || w.home.startsWith('sky')))) continue;
          const d = dist(w, b);
          if (d < bd) { bd = d; best = w; }
        }
        if (best) { b.chase = best; b.chaseT = 0; }
      }
      if (b.chase) {
        const w = b.chase;
        b.chaseT += dt;
        if (!G.wild().includes(w) || b.chaseT > 25) { b.chase = null; b.cd = rand(20, 40); pickRoad(b); continue; }
        const d = moveTo(b, w.x, w.y, 240 + b.skill * 40, dt);
        if (d < 70) {
          if (Math.random() < 0.45 + b.skill * 0.4) catchHorse(b, w);
          else { w.flee = 2; b.cd = rand(8, 15); }
          b.chase = null;
          pickRoad(b);
        }
      } else if (toTrain) {
        moveTo(b, Train.STOP_X + (b.i - 1) * 120, World.RAIL.y - 300, 260, dt);
      } else {
        const q = b.road[b.ri];
        const d = moveTo(b, q[0], q[1], b.gait ? 160 : 80, dt);
        if (d < 30) {
          b.ri += b.rdir;
          if (b.ri < 0 || b.ri >= b.road.length) pickRoad(b);
          if (Math.random() < 0.15) b.gait = b.gait ? 0 : 1;
        }
      }
      // застряли — перескакиваем к ближайшей дороге
      b.stuckT += dt;
      if (b.stuckT > 3) {
        if (Math.hypot(b.x - b.lastX, b.y - b.lastY) < 25) {
          b.chase = null;
          let best = null, bd = 1e9;
          for (const r of World.ROADS) for (const q of r) { const dd = Math.hypot(q[0] - b.x, q[1] - b.y); if (dd < bd && dd > 60) { bd = dd; best = q; } }
          if (best) { b.x = best[0]; b.y = best[1]; }
          pickRoad(b);
        }
        b.stuckT = 0; b.lastX = b.x; b.lastY = b.y;
      }
    }
  }

  function hud() { return bots.map(b => ({ name: b.name, caught: b.stat.caught, money: b.stat.money, best: b.stat.best, where: World.REGION_NAMES[World.regionAt(b.x, b.y)] || '' })); }

  return { init, update, hud, bots: () => bots };
})();

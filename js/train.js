'use strict';
/*
 * Поезд в пустыне: раз в 30 минут проезжает по железной дороге и останавливается у станции.
 * Из вагонов выбегают красивые лошади — их можно поймать, но только за одну минуту:
 * потом они забегают обратно, и поезд уезжает.
 */
const Train = (() => {
  let G = null;
  const PERIOD = 30 * 60, CATCH = 60, FIRST = 4 * 60;
  const R = World.RAIL, ST = World.STATION;
  const STOP_X = ST.x + ST.w / 2;
  let tr = null;                 // { x, v, state: 'in' | 'stop' | 'out', t }
  let warned = false;

  function init(api) {
    G = api;
    if (G.S.trainT == null || G.S.trainT > PERIOD) G.S.trainT = FIRST;
  }

  function release() {
    const n = 6 + Math.floor(Math.random() * 3);
    const herd = G.herds().train;
    herd.x = herd.tx = STOP_X; herd.y = herd.ty = R.y - 520; herd.t = 4;
    for (let i = 0; i < n; i++) {
      const h = G.makeWild(STOP_X - 260 + i * 70, R.y - 70, 'train');
      h.temper = Math.min(h.temper, 0.55);
      h.angle = -Math.PI / 2;
      h.slot = { x: (i - n / 2) * 70, y: -60 + Math.random() * 120 };
      G.addWild(h);
    }
    UI.toast('🐎 Из поезда выбежали красивые лошади! Лови — у тебя одна минута!', 'good');
    Sound.fanfare();
  }
  function recall() {
    const left = G.wild().filter(w => w.home === 'train').length;
    G.removeWild(w => w.home === 'train');
    UI.toast(left ? `🚂 Лошади забежали обратно в поезд (${left}), и он уехал. Следующий — через 30 минут` : '🚂 Поезд уехал. Следующий — через 30 минут');
  }

  function update(dt) {
    const S = G.S;
    if (!tr) {
      S.trainT -= dt;
      if (S.trainT <= 60 && !warned) { warned = true; UI.toast('🚂 Через минуту в пустыню приедет поезд с лошадьми! Станция — на железной дороге'); }
      if (S.trainT <= 0) {
        S.trainT = PERIOD; warned = false;
        tr = { x: R.x1 - 700, v: 420, state: 'in', t: 0 };
        UI.toast('🚂 Ту-ту! По пустыне едет поезд с красивыми лошадьми! Спеши к станции', 'good');
        Sound.train();
      }
      return;
    }
    tr.t += dt;
    if (tr.state === 'in') {
      const d = STOP_X - tr.x;
      tr.v = Math.min(420, Math.max(30, d * 0.5));
      tr.x += tr.v * dt;
      if (d < 3) { tr.x = STOP_X; tr.v = 0; tr.state = 'stop'; tr.t = 0; release(); }
    } else if (tr.state === 'stop') {
      if (tr.t >= CATCH) { recall(); tr.state = 'out'; tr.t = 0; Sound.train(); }
    } else {
      tr.v = Math.min(460, tr.v + 110 * dt);
      tr.x += tr.v * dt;
      if (tr.x > R.x2 + 1200) tr = null;
    }
  }

  // для подсказок: сколько осталось поймать или ждать
  function hud() {
    if (tr && tr.state === 'stop') return { catchLeft: Math.max(0, CATCH - tr.t) };
    if (tr) return { moving: true };
    return { next: G ? G.S.trainT : PERIOD };
  }
  const near = p => Math.abs(p.y - R.y) < 1600 && p.x > R.x1 - 400 && p.x < R.x2 + 400;

  return { init, update, hud, near, state: () => tr, STOP_X, PERIOD, debugCome: () => { if (G) G.S.trainT = 1; } };
})();

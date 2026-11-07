'use strict';
/*
 * Праздники: раз в час наступает Хэллоуин, Новый год или Пасха.
 * В поле прибегают праздничные лошади (их можно поймать), ферма украшается.
 *  - Хэллоуин: страшные лошади с тыквами, летучими мышами и привидениями;
 *  - Новый год: зелёные лошади-ёлочки с игрушками и светящиеся лошади разных цветов;
 *  - Пасха: розовые лошади с разноцветными яичками, полосочками и точечками.
 */
const Holidays = (() => {
  let G = null;
  const PERIOD = 60 * 60, LEN = 8 * 60, FIRST = 3 * 60;
  const KINDS = {
    halloween: { name: 'Хэллоуин', icon: '🎃', toast: '🎃 Хэллоуин! В поле прибежали страшные лошади с тыквами, летучими мышами и привидениями!' },
    newyear: { name: 'Новый год', icon: '🎄', toast: '🎄 Новый год! В поле — лошади-ёлочки с игрушками и светящиеся лошади разных цветов!' },
    easter: { name: 'Пасха', icon: '🥚', toast: '🥚 Пасха! В поле — розовые лошади с разноцветными яичками, полосочками и точечками!' },
  };
  let flakes = [];

  function init(api) {
    G = api;
    const S = G.S;
    if (S.holidayT == null || S.holidayT > PERIOD) S.holidayT = FIRST;
    if (S.holidayNow && !KINDS[S.holidayNow.k]) S.holidayNow = null;
    if (S.holidayNow) spawn(S.holidayNow.k);
  }

  function spawn(k) {
    const herd = G.herds().holiday;
    const F = herd.area;
    herd.x = herd.tx = F.x + F.w / 2; herd.y = herd.ty = F.y + F.h / 2;
    G.removeWild(w => w.home === 'holiday');
    for (let i = 0; i < 6; i++) {
      const h = G.makeWild(herd.x + (Math.random() - 0.5) * 400, herd.y + (Math.random() - 0.5) * 300, 'holiday');
      const v = k === 'newyear' ? (i % 2 ? 'newyearglow' : 'newyear') : k;
      h.magic = Horses.resolveMagic({ holiday: v });
      h._ph = null;
      h.temper = Math.min(h.temper, 0.5);
      G.addWild(h);
    }
  }

  function start(k) {
    const S = G.S;
    k = k || Object.keys(KINDS)[Math.floor(Math.random() * 3)];
    S.holidayNow = { k, t: LEN };
    S.holidayT = PERIOD;
    spawn(k);
    UI.toast(KINDS[k].toast, 'good');
    Sound.fanfare();
  }
  function end() {
    const S = G.S, k = S.holidayNow.k;
    S.holidayNow = null;
    G.removeWild(w => w.home === 'holiday');
    UI.toast(`${KINDS[k].icon} Праздник «${KINDS[k].name}» закончился. Следующий — через час!`);
  }

  function update(dt) {
    const S = G.S;
    if (S.holidayNow) {
      S.holidayNow.t -= dt;
      if (S.holidayNow.t <= 0) end();
    } else {
      S.holidayT -= dt;
      if (S.holidayT <= 0) start();
    }
  }

  const current = () => (G && G.S.holidayNow ? G.S.holidayNow.k : null);
  function hud() {
    const S = G ? G.S : null;
    if (!S) return null;
    if (S.holidayNow) return { k: S.holidayNow.k, name: KINDS[S.holidayNow.k].name, icon: KINDS[S.holidayNow.k].icon, left: S.holidayNow.t };
    return { next: S.holidayT };
  }

  // праздничное настроение поверх экрана: снежинки на Новый год, летучие мыши на Хэллоуин, конфетти на Пасху
  function drawScreen(ctx, w, h, k, t) {
    const cur = current();
    if (!cur || G.S.player.y > World.H) return;
    const n = cur === 'newyear' ? 90 : cur === 'halloween' ? 7 : 40;
    while (flakes.length < n) flakes.push({ x: Math.random() * w, y: Math.random() * h, s: 0.6 + Math.random() * 0.8, p: Math.random() * 6 });
    flakes.length = n;
    ctx.save();
    if (cur === 'halloween') {
      ctx.fillStyle = 'rgba(60,20,80,0.12)'; ctx.fillRect(0, 0, w, h);
      ctx.font = `${Math.round(26 * k)}px system-ui`;
      for (const f of flakes) {
        f.x += 1.6 * f.s * k; f.y += Math.sin(t * 3 + f.p) * 1.2 * k;
        if (f.x > w + 40) { f.x = -40; f.y = Math.random() * h * 0.6; }
        ctx.fillText('🦇', f.x, f.y);
      }
    } else if (cur === 'newyear') {
      ctx.fillStyle = 'rgba(255,255,255,0.85)';
      for (const f of flakes) {
        f.y += 1.2 * f.s * k; f.x += Math.sin(t * 1.5 + f.p) * 0.5 * k;
        if (f.y > h) { f.y = -10; f.x = Math.random() * w; }
        ctx.fillRect(f.x, f.y, 3 * f.s * k, 3 * f.s * k);
      }
    } else {
      const cols = ['#ff8fab', '#ffd43b', '#69db7c', '#74c0fc', '#cc5de8'];
      flakes.forEach((f, i) => {
        f.y += 0.9 * f.s * k; f.x += Math.sin(t * 2 + f.p) * 0.7 * k;
        if (f.y > h) { f.y = -10; f.x = Math.random() * w; }
        ctx.fillStyle = cols[i % cols.length];
        ctx.fillRect(f.x, f.y, 4 * f.s * k, 2.5 * f.s * k);
      });
    }
    ctx.restore();
  }

  return { init, update, current, hud, drawScreen, start, KINDS, debugStart: k => start(k) };
})();

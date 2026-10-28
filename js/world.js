'use strict';
/* Карта фермы: где что стоит и что непроходимо */
const World = (() => {
  const W = 3800, H = 2400;

  // Конюшня: 2 ряда по 10 денников, проход посередине, ворота слева и справа
  const STALL_W = 72, STALL_H = 120, AISLE = 80;
  const STABLE = { x: 120, y: 140, w: 740, h: 10 + STALL_H + AISLE + STALL_H + 10 };
  const AISLE_Y1 = STABLE.y + 10 + STALL_H, AISLE_Y2 = AISLE_Y1 + AISLE;

  function stallRect(i) {
    const row = i < 10 ? 0 : 1, col = i % 10;
    return { x: STABLE.x + 10 + col * STALL_W, y: row ? AISLE_Y2 : STABLE.y + 10, w: STALL_W, h: STALL_H, row };
  }
  // место лошади в деннике: головой к проходу
  function stallSpot(i) {
    const r = stallRect(i);
    return { x: r.x + r.w / 2, y: r.y + r.h / 2 + (r.row ? 2 : -2), angle: r.row ? -Math.PI / 2 : Math.PI / 2 };
  }

  // Манеж 20×40 (в пикселях 410×820) с буквами для выездки
  const ARENA = { x: 140, y: 640, w: 820, h: 410 };
  const A_CX = ARENA.x + ARENA.w / 2, A_CY = ARENA.y + ARENA.h / 2;
  const GATE_A = { y1: A_CY - 55, y2: A_CY + 55 };
  // стоя в A лицом к C: слева K-E-H (сверху), справа F-B-M (снизу)
  const LETTERS = {
    A: { x: ARENA.x, y: A_CY, side: 'left' },
    C: { x: ARENA.x + ARENA.w, y: A_CY, side: 'right' },
    K: { x: ARENA.x + ARENA.w * 0.15, y: ARENA.y, side: 'top' },
    E: { x: A_CX, y: ARENA.y, side: 'top' },
    H: { x: ARENA.x + ARENA.w * 0.85, y: ARENA.y, side: 'top' },
    F: { x: ARENA.x + ARENA.w * 0.15, y: ARENA.y + ARENA.h, side: 'bottom' },
    B: { x: A_CX, y: ARENA.y + ARENA.h, side: 'bottom' },
    M: { x: ARENA.x + ARENA.w * 0.85, y: ARENA.y + ARENA.h, side: 'bottom' },
    X: { x: A_CX, y: A_CY, side: 'center' },
  };
  // точка на «дорожке» внутри манежа напротив буквы
  function letterTarget(L) {
    const p = LETTERS[L], inset = 34;
    if (p.side === 'left') return { x: p.x + inset, y: p.y };
    if (p.side === 'right') return { x: p.x - inset, y: p.y };
    if (p.side === 'top') return { x: p.x, y: p.y + inset };
    if (p.side === 'bottom') return { x: p.x, y: p.y - inset };
    return { x: p.x, y: p.y };
  }

  // Кавалетти: жерди поперёк дорожки, ехать слева направо
  const CAV = {
    y1: ARENA.y + ARENA.h - 150, y2: ARENA.y + ARENA.h - 70,
    poles: [0, 1, 2, 3, 4].map(i => ARENA.x + 300 + i * 92),
  };

  // Левада (огороженное поле)
  const PADDOCK = { x: 1000, y: 110, w: 540, h: 420 };
  const PADDOCK_GATE = { x1: PADDOCK.x + 210, x2: PADDOCK.x + 320 };

  // Повозки
  const SELL = { x: 1190, y: 700, w: 130, h: 66, name: 'Продажа лошадей' };
  const SHOP = { x: 1190, y: 900, w: 130, h: 66, name: 'Корм и амуниция' };

  // Конкурное поле: 8 препятствий, ворота сверху слева
  const JUMPF = { x: 140, y: 1170, w: 1360, h: 620 };
  const JUMPF_GATE = { x1: JUMPF.x + 70, x2: JUMPF.x + 190 };
  // a — направление прыжка (0 = вправо), type — вид препятствия
  const COURSE = [
    { fx: 0.17, fy: 0.80, a: 0, type: 'cross', name: 'крестовина' },
    { fx: 0.40, fy: 0.80, a: 0, type: 'vertical', name: 'вертикаль' },
    { fx: 0.64, fy: 0.80, a: 0, type: 'oxer', name: 'оксер' },
    { fx: 0.90, fy: 0.50, a: -Math.PI / 2, type: 'wall', name: 'стенка' },
    { fx: 0.66, fy: 0.20, a: Math.PI, type: 'vertical', name: 'вертикаль' },
    { fx: 0.42, fy: 0.20, a: Math.PI, type: 'oxer', name: 'оксер' },
    { fx: 0.40, fy: 0.52, a: 0, type: 'vertical', name: 'вертикаль' },
    { fx: 0.66, fy: 0.52, a: 0, type: 'triple', name: 'тройник' },
  ].map((o, i) => Object.assign(o, {
    n: i + 1, x: JUMPF.x + o.fx * JUMPF.w, y: JUMPF.y + o.fy * JUMPF.h, half: 46,
  }));

  // Фонари: светят ночью
  const LAMPS = [
    { x: 100, y: 250 }, { x: 900, y: 250 }, { x: 900, y: 400 },
    { x: 130, y: 625 }, { x: 975, y: 625 }, { x: 130, y: 1065 }, { x: 975, y: 1065 },
    { x: 1180, y: 560 }, { x: 1360, y: 560 },
    { x: 1350, y: 690 }, { x: 1350, y: 890 },
    { x: 120, y: 1150 }, { x: 1520, y: 1150 }, { x: 120, y: 1810 }, { x: 1520, y: 1810 },
  ];

  // Большое поле с табуном
  const FIELD = { x: 1760, y: 100, w: 1940, h: 2200 };
  const POND = { x: 2780, y: 1650, rx: 210, ry: 130 };

  // детерминированный генератор — каждый раз одинаковая карта
  function rng(seed) {
    return function () {
      seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const inRect = (x, y, r, m = 0) => x >= r.x - m && x <= r.x + r.w + m && y >= r.y - m && y <= r.y + r.h + m;
  function inPond(x, y, m = 0) {
    const dx = (x - POND.x) / (POND.rx + m), dy = (y - POND.y) / (POND.ry + m);
    return dx * dx + dy * dy < 1;
  }

  // деревья и цветы
  const TREES = [], FLOWERS = [];
  (function decorate() {
    const r = rng(42);
    const busy = (x, y) => inRect(x, y, STABLE, 60) || inRect(x, y, JUMPF, 70) || (x < 300 && y > 820 && y < 1200) || inRect(x, y, ARENA, 70) || inRect(x, y, PADDOCK, 60) ||
      inRect(x, y, SELL, 90) || inRect(x, y, SHOP, 90) || inPond(x, y, 70) ||
      (x > 860 && x < 1000 && y > 260 && y < 640) || (x > 900 && x < 1850 && y > 540 && y < 660) || (x > 1060 && x < 1170 && y > 560 && y < 1060);
    let tries = 0;
    while (TREES.length < 46 && tries++ < 3000) {
      const inField = r() < 0.6;
      const x = inField ? FIELD.x + 60 + r() * (FIELD.w - 120) : 40 + r() * 1640;
      const y = inField ? FIELD.y + 60 + r() * (FIELD.h - 120) : 1120 + r() * 1220;
      if (busy(x, y)) continue;
      if (inField && Math.hypot(x - (FIELD.x + FIELD.w / 2), y - (FIELD.y + FIELD.h / 2)) < 420) continue;
      if (TREES.some(t => Math.hypot(t.x - x, t.y - y) < 120)) continue;
      TREES.push({ x, y, r: 32 + r() * 22, kind: r() < 0.3 ? 'birch' : 'oak', s: Math.floor(r() * 1e6) });
    }
    // по краю фермы — ряд деревьев
    for (let x = 60; x < 1700; x += 150) TREES.push({ x, y: 40 + r() * 20, r: 30 + r() * 10, kind: 'oak', s: Math.floor(r() * 1e6) });
    const cols = ['#ffffff', '#ffe066', '#ff8fab', '#c77dff', '#ffd6a5', '#f94144'];
    for (let i = 0; i < 900; i++) {
      const x = r() * W, y = r() * H;
      if (busy(x, y)) continue;
      FLOWERS.push({ x, y, c: cols[Math.floor(r() * cols.length)], s: 1.5 + r() * 2 });
    }
  })();

  // непроходимые прямоугольники (стены, заборы, повозки)
  const SOLIDS = [];
  (function solids() {
    const t = 10;
    const S = STABLE;
    SOLIDS.push({ x: S.x, y: S.y, w: S.w, h: t });
    SOLIDS.push({ x: S.x, y: S.y + S.h - t, w: S.w, h: t });
    SOLIDS.push({ x: S.x, y: S.y, w: t, h: AISLE_Y1 - S.y });
    SOLIDS.push({ x: S.x, y: AISLE_Y2, w: t, h: S.y + S.h - AISLE_Y2 });
    SOLIDS.push({ x: S.x + S.w - t, y: S.y, w: t, h: AISLE_Y1 - S.y });
    SOLIDS.push({ x: S.x + S.w - t, y: AISLE_Y2, w: t, h: S.y + S.h - AISLE_Y2 });
    const A = ARENA, f = 8;
    SOLIDS.push({ x: A.x - f / 2, y: A.y - f / 2, w: A.w + f, h: f });
    SOLIDS.push({ x: A.x - f / 2, y: A.y + A.h - f / 2, w: A.w + f, h: f });
    SOLIDS.push({ x: A.x + A.w - f / 2, y: A.y, w: f, h: A.h });
    SOLIDS.push({ x: A.x - f / 2, y: A.y, w: f, h: GATE_A.y1 - A.y });
    SOLIDS.push({ x: A.x - f / 2, y: GATE_A.y2, w: f, h: A.y + A.h - GATE_A.y2 });
    const P = PADDOCK;
    SOLIDS.push({ x: P.x - f / 2, y: P.y - f / 2, w: P.w + f, h: f });
    SOLIDS.push({ x: P.x - f / 2, y: P.y, w: f, h: P.h });
    SOLIDS.push({ x: P.x + P.w - f / 2, y: P.y, w: f, h: P.h });
    SOLIDS.push({ x: P.x - f / 2, y: P.y + P.h - f / 2, w: PADDOCK_GATE.x1 - P.x + f / 2, h: f });
    SOLIDS.push({ x: PADDOCK_GATE.x2, y: P.y + P.h - f / 2, w: P.x + P.w - PADDOCK_GATE.x2 + f / 2, h: f });
    const J = JUMPF;
    SOLIDS.push({ x: J.x - f / 2, y: J.y - f / 2, w: JUMPF_GATE.x1 - J.x + f / 2, h: f });
    SOLIDS.push({ x: JUMPF_GATE.x2, y: J.y - f / 2, w: J.x + J.w - JUMPF_GATE.x2 + f / 2, h: f });
    SOLIDS.push({ x: J.x - f / 2, y: J.y, w: f, h: J.h });
    SOLIDS.push({ x: J.x + J.w - f / 2, y: J.y, w: f, h: J.h });
    SOLIDS.push({ x: J.x - f / 2, y: J.y + J.h - f / 2, w: J.w + f, h: f });
    SOLIDS.push({ x: SELL.x, y: SELL.y, w: SELL.w, h: SELL.h });
    SOLIDS.push({ x: SHOP.x, y: SHOP.y, w: SHOP.w, h: SHOP.h });
  })();

  // вытолкнуть круг (x,y,r) из препятствий
  function collide(e, r) {
    for (const s of SOLIDS) {
      const cx = Math.max(s.x, Math.min(e.x, s.x + s.w));
      const cy = Math.max(s.y, Math.min(e.y, s.y + s.h));
      let dx = e.x - cx, dy = e.y - cy;
      const d2 = dx * dx + dy * dy;
      if (d2 >= r * r) continue;
      if (d2 === 0) {
        // центр внутри прямоугольника — выталкиваем по ближайшей стороне
        const opts = [[e.x - s.x, -1, 0], [s.x + s.w - e.x, 1, 0], [e.y - s.y, 0, -1], [s.y + s.h - e.y, 0, 1]];
        opts.sort((a, b) => a[0] - b[0]);
        e.x += opts[0][1] * (opts[0][0] + r);
        e.y += opts[0][2] * (opts[0][0] + r);
      } else {
        const d = Math.sqrt(d2);
        e.x = cx + (dx / d) * r;
        e.y = cy + (dy / d) * r;
      }
    }
    for (const t of TREES) {
      const dx = e.x - t.x, dy = e.y - t.y, d = Math.hypot(dx, dy), rr = r + 9;
      if (d < rr && d > 0) { e.x = t.x + (dx / d) * rr; e.y = t.y + (dy / d) * rr; }
    }
    if (inPond(e.x, e.y, r)) {
      const dx = (e.x - POND.x) / (POND.rx + r), dy = (e.y - POND.y) / (POND.ry + r);
      const d = Math.hypot(dx, dy) || 1;
      e.x = POND.x + (dx / d) * (POND.rx + r) * 1.001;
      e.y = POND.y + (dy / d) * (POND.ry + r) * 1.001;
    }
    e.x = Math.max(r, Math.min(W - r, e.x));
    e.y = Math.max(r, Math.min(H - r, e.y));
  }

  return {
    W, H, STABLE, STALL_W, STALL_H, AISLE_Y1, AISLE_Y2, stallRect, stallSpot,
    ARENA, GATE_A, LETTERS, letterTarget, CAV, JUMPF, JUMPF_GATE, COURSE, LAMPS, PADDOCK, PADDOCK_GATE, SELL, SHOP, FIELD, POND,
    TREES, FLOWERS, SOLIDS, collide, inRect, inPond, rng,
  };
})();

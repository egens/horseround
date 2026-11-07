'use strict';
/* Карта фермы: где что стоит и что непроходимо */
const World = (() => {
  const W = 14400, H = 9600;

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

  /* ---------- большой мир ---------- */
  const LAKELAND = { x: 3800, y: 100, w: 2400, h: 2500 };        // Озёрный край
  const FARMLAND = { x: 150, y: 2500, w: 1600, h: 900 };         // поля и огороды
  const VILLAGE = { x: 1900, y: 2500, w: 1700, h: 900 };         // деревня
  const FOREST = [{ x: 0, y: 3500, w: 6200, h: 2900 }, { x: 3800, y: 2650, w: 2400, h: 850 }];
  const MUSHROOM = { x: 6300, y: 2900, w: 3300, h: 3500 };       // Грибное королевство
  const MOUNTAIN = { x: 6300, y: 0, w: 3300, h: 2800 };          // горы
  const CAVE = { x: 6600, y: 350, w: 2700, h: 2100 };            // пещера внутри гор
  const CAVE_GATE = { y1: 1300, y2: 1500 };                       // вход в пещеру с запада
  const CHEST = { x: 9050, y: 650 };                              // сундук графа в глубине пещеры
  // внутренние скальные стены пещеры: проход «змейкой»
  const CAVE_INNER_WALLS = [
    { x: 7350, y: 350, w: 120, h: 1350 },
    { x: 8250, y: 1150, w: 120, h: 1300 },
    { x: 7350, y: 2050, w: 500, h: 110 },
  ];

  // юг: пустыня, дремучий лес, тундра
  const DESERT = { x: 0, y: 6500, w: 4300, h: 3100 };
  const DEEPFOREST = { x: 4300, y: 6500, w: 2300, h: 3100 };
  const TUNDRA = { x: 6600, y: 6500, w: 3000, h: 3100 };

  // восток: море и три острова со своей конюшней, пастбищем и манежем
  const SEA = { x: 9700, y: 0, w: 4700, h: 9600 };
  const ISLANDS = [
    { id: 'i1', name: 'Остров бабочек', x: 11300, y: 2000, rx: 950, ry: 760, breeds: ['butterflyhorse', 'beehorse', 'dragonflyhorse', 'haflinger', 'arab'] },
    { id: 'i2', name: 'Драконий остров', x: 12900, y: 4900, rx: 920, ry: 800, breeds: ['dragonhorse', 'dragonhorse', 'ravenhorse', 'friesian', 'akhal'] },
    { id: 'i3', name: 'Остров ветров', x: 11300, y: 7700, rx: 1000, ry: 760, breeds: ['ravenhorse', 'dragonflyhorse', 'pegasus', 'paint', 'appaloosa'] },
  ];
  for (const I of ISLANDS) {
    I.stable = { x: I.x - 480, y: I.y - 430, w: 340, h: 150 };                 // 5 денников, открыта на юг
    I.pasture = { x: I.x + 60, y: I.y - 460, w: 400, h: 300 };                 // пастбище с забором
    I.gate = { x1: I.pasture.x + 150, x2: I.pasture.x + 250 };
    I.pen = { x: I.x - 260, y: I.y + 260, r: 170 };                            // круглый манеж
    I.pier = { x: I.x - I.rx + 70, y: I.y };                                    // причал
    I.area = { x: I.x - I.rx + 150, y: I.y - I.ry + 150, w: I.rx * 2 - 300, h: I.ry * 2 - 300 };
  }
  const PIER = { x: 9560, y: 4700, name: 'Пристань' };                        // причал на большой земле
  function islandAt(x, y, m = 0) {
    for (const I of ISLANDS) {
      const dx = (x - I.x) / (I.rx - m), dy = (y - I.y) / (I.ry - m);
      if (dx * dx + dy * dy < 1) return I;
    }
    return null;
  }
  const inSea = (x, y, m = 0) => x > SEA.x - m && !islandAt(x, y, m);

  const LAKES = [
    POND,
    { x: 4950, y: 1150, rx: 620, ry: 360, name: 'Большое озеро' },
    { x: 4300, y: 2150, rx: 250, ry: 160 },
    { x: 2900, y: 4900, rx: 360, ry: 230, name: 'Лесное озеро' },
    { x: 8000, y: 5200, rx: 260, ry: 180, magic: true, name: 'Волшебный пруд' },
    { x: 2100, y: 8000, rx: 260, ry: 170, name: 'Оазис' },
    { x: 8100, y: 8300, rx: 380, ry: 230, ice: true, name: 'Ледяное озеро' },
  ];

  // дороги (ломаные), по ним не растут деревья
  const ROADS = [
    [[860, 310], [940, 310], [940, 600], [1275, 600], [1275, 540]],
    [[1275, 600], [1650, 600], [1800, 560]],
    [[120, 310], [70, 310], [70, 850], [140, 850]],
    [[70, 850], [70, 1120], [270, 1120], [270, 1180]],
    [[1110, 600], [1110, 1000]],
    [[960, 850], [1110, 850]],
    [[1110, 1000], [1600, 1100], [1700, 2200], [1800, 2600], [2400, 2850], [3400, 2900]],
    [[800, 1900], [900, 2450], [1500, 2700], [1800, 2600]],
    [[3700, 1500], [4300, 1750], [5600, 1720], [6000, 1420], [6650, 1400]],
    [[2600, 2900], [2600, 3700], [3500, 4200], [4800, 4300], [6000, 4100], [6700, 3900], [7600, 4100], [8300, 4600]],
    [[1600, 3500], [1700, 3300], [1800, 2600]],
    [[2600, 3700], [2300, 5000], [2100, 6400], [2100, 7700]],
    [[4800, 4300], [5300, 6000], [5400, 7600]],
    [[6000, 4100], [7000, 6200], [7700, 7200], [7900, 8000]],
    [[8300, 4600], [9000, 4700], [9560, 4700]],
  ];

  // дома деревни и лесная сторожка
  const HOUSES = [
    { x: 2150, y: 2640, w: 200, h: 150, name: 'Кузница', roof: '#5f5f5f', wall: '#9a8f80' },
    { x: 2750, y: 2620, w: 200, h: 150, name: 'Салон «Грива»', roof: '#c2255c', wall: '#f8e1ea' },
    { x: 3150, y: 2700, w: 180, h: 140, roof: '#8c3b2a', wall: '#e9d8b5' },
    { x: 2420, y: 3080, w: 180, h: 140, roof: '#2f6f8f', wall: '#efe4cf' },
    { x: 1430, y: 2560, w: 180, h: 140, name: 'Дом бабушки Гали', roof: '#a33a2a', wall: '#f1e3c6' },
    { x: 1480, y: 3380, w: 180, h: 130, name: 'Сторожка лесника', roof: '#3b5e2b', wall: '#8a5a32' },
  ];
  const WELL = { x: 2620, y: 2880, r: 26 };
  const BOARD = { x: 2720, y: 2980 };                             // доска заданий

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
  function lakeAt(x, y, m = 0) {
    for (const L of LAKES) {
      const dx = (x - L.x) / (L.rx + m), dy = (y - L.y) / (L.ry + m);
      if (dx * dx + dy * dy < 1) return L;
    }
    return null;
  }
  const inPond = (x, y, m = 0) => !!lakeAt(x, y, m);            // «в воде» — любое озеро
  function distToRoad(x, y) {
    let best = 1e9;
    for (const r of ROADS) for (let i = 0; i < r.length - 1; i++) {
      const [ax, ay] = r[i], [bx, by] = r[i + 1];
      const dx = bx - ax, dy = by - ay, L2 = dx * dx + dy * dy || 1;
      const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / L2));
      best = Math.min(best, Math.hypot(ax + dx * t - x, ay + dy * t - y));
    }
    return best;
  }
  const inForest = (x, y) => FOREST.some(f => inRect(x, y, f));
  function regionAt(x, y) {
    const I = islandAt(x, y);
    if (I) return I.id;
    if (x > SEA.x) return 'sea';
    if (inRect(x, y, DESERT)) return 'desert';
    if (inRect(x, y, DEEPFOREST)) return 'deepforest';
    if (inRect(x, y, TUNDRA)) return 'tundra';
    if (inRect(x, y, CAVE)) return 'cave';
    if (inRect(x, y, MOUNTAIN)) return 'mountain';
    if (inRect(x, y, MUSHROOM)) return 'mushroom';
    if (inRect(x, y, VILLAGE)) return 'village';
    if (inRect(x, y, FARMLAND)) return 'farmland';
    if (inForest(x, y)) return 'forest';
    if (inRect(x, y, LAKELAND)) return 'lake';
    if (inRect(x, y, FIELD)) return 'field';
    return 'farm';
  }
  const REGION_NAMES = {
    farm: 'Ферма', field: 'Большое поле', lake: 'Озёрный край', forest: 'Лес', village: 'Деревня',
    farmland: 'Поля и огороды', mushroom: 'Грибное королевство', mountain: 'Горы', cave: 'Пещера',
    desert: 'Пустыня', deepforest: 'Дремучий лес', tundra: 'Тундра', sea: 'Море',
    i1: ISLANDS[0].name, i2: ISLANDS[1].name, i3: ISLANDS[2].name,
  };

  // деревья, грибы, камни, цветы
  // kind: oak, birch, pine (сосна), spruce (ель), amanita/boletus/glowshroom (большие грибы), rock, crystal
  const TREES = [], FLOWERS = [], SHROOMS = [], CRYSTALS = [];
  const houseBusy = (x, y, m) => HOUSES.some(hh => inRect(x, y, hh, m)) || Math.hypot(x - WELL.x, y - WELL.y) < m + 30;
  (function decorate() {
    const r = rng(42);
    const busy = (x, y) => Math.hypot(x - 1840, y - 560) < 280 || inRect(x, y, STABLE, 60) || inRect(x, y, JUMPF, 70) || (x < 300 && y > 820 && y < 1200) || inRect(x, y, ARENA, 70) || inRect(x, y, PADDOCK, 60) ||
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
      if (distToRoad(x, y) < 50) continue;
      TREES.push({ x, y, r: 32 + r() * 22, kind: r() < 0.3 ? 'birch' : 'oak', s: Math.floor(r() * 1e6), cr: 9 });
    }
    // по краю фермы — ряд деревьев
    for (let x = 60; x < 1700; x += 150) TREES.push({ x, y: 40 + r() * 20, r: 30 + r() * 10, kind: 'oak', s: Math.floor(r() * 1e6), cr: 9 });

    // сетка «занятости», чтобы деревья не налезали друг на друга
    const occ = new Map();
    const okey = (x, y) => `${Math.floor(x / 100)}|${Math.floor(y / 100)}`;
    const free = (x, y, d) => {
      const gx = Math.floor(x / 100), gy = Math.floor(y / 100);
      for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) {
        for (const t of occ.get(`${gx + i}|${gy + j}`) || []) if (Math.hypot(t.x - x, t.y - y) < d) return false;
      }
      return true;
    };
    const add = t => { TREES.push(t); const k = okey(t.x, t.y); if (!occ.has(k)) occ.set(k, []); occ.get(k).push(t); };
    TREES.forEach(t => { const k = okey(t.x, t.y); if (!occ.has(k)) occ.set(k, []); occ.get(k).push(t); });
    const blockedBig = (x, y, m = 60) => inPond(x, y, m) || distToRoad(x, y) < 70 || houseBusy(x, y, m) || inRect(x, y, FARMLAND, 20) || inRect(x, y, VILLAGE, 0) || inRect(x, y, MOUNTAIN, 40);

    // озёрный край: редкие деревья
    for (let i = 0; i < 400 && TREES.length < 46 + 12 + 70; i++) {
      const x = LAKELAND.x + 80 + r() * (LAKELAND.w - 160), y = LAKELAND.y + 80 + r() * (LAKELAND.h - 160);
      if (blockedBig(x, y) || !free(x, y, 150)) continue;
      add({ x, y, r: 30 + r() * 24, kind: r() < 0.45 ? 'birch' : r() < 0.5 ? 'pine' : 'oak', s: Math.floor(r() * 1e6), cr: 9 });
    }
    // лес: густо, с полянами
    const clearings = Array.from({ length: 14 }, () => ({ x: r() * 6200, y: 3500 + r() * 2900, r: 160 + r() * 200 }));
    for (const f of FOREST) for (let x = f.x + 60; x < f.x + f.w - 40; x += 108) for (let y = f.y + 60; y < f.y + f.h - 40; y += 108) {
      const px = x + (r() - 0.5) * 80, py = y + (r() - 0.5) * 80;
      if (r() < 0.12) continue;
      if (blockedBig(px, py) || clearings.some(c => Math.hypot(c.x - px, c.y - py) < c.r) || !free(px, py, 80)) continue;
      const k = r();
      add({ x: px, y: py, r: 30 + r() * 26, kind: k < 0.4 ? 'pine' : k < 0.65 ? 'birch' : 'oak', s: Math.floor(r() * 1e6), cr: 10 });
    }
    // грибное королевство: ели и огромные грибы
    for (let x = MUSHROOM.x + 80; x < MUSHROOM.x + MUSHROOM.w - 60; x += 160) for (let y = MUSHROOM.y + 80; y < MUSHROOM.y + MUSHROOM.h - 60; y += 160) {
      const px = x + (r() - 0.5) * 110, py = y + (r() - 0.5) * 110;
      if (r() < 0.35) continue;
      if (blockedBig(px, py) || !free(px, py, 110)) continue;
      const k = r();
      if (k < 0.62) add({ x: px, y: py, r: 34 + r() * 26, kind: 'spruce', s: Math.floor(r() * 1e6), cr: 12 });
      else add({ x: px, y: py, r: 35 + r() * 30, kind: k < 0.78 ? 'amanita' : k < 0.9 ? 'boletus' : 'glowshroom', s: Math.floor(r() * 1e6), cr: 16 });
    }
    // маленькие грибы — можно собирать
    const shroomAt = (area, n, types) => {
      for (let i = 0; i < n; i++) {
        const x = area.x + r() * area.w, y = area.y + r() * area.h;
        if (inPond(x, y, 10) || houseBusy(x, y, 20) || inRect(x, y, MOUNTAIN)) continue;
        SHROOMS.push({ x, y, type: types[Math.floor(r() * types.length)], s: r() });
      }
    };
    shroomAt(MUSHROOM, 520, ['white', 'chanterelle', 'amanita', 'glow', 'glow', 'violet']);
    for (const f of FOREST) shroomAt(f, f.w * f.h > 5e6 ? 260 : 60, ['white', 'chanterelle', 'chanterelle', 'amanita']);
    SHROOMS.forEach((m, i) => (m.id = i));

    // пещера: валуны и светящиеся кристаллы
    for (let i = 0; i < 70; i++) {
      const x = CAVE.x + 100 + r() * (CAVE.w - 200), y = CAVE.y + 100 + r() * (CAVE.h - 200);
      if (Math.hypot(x - CHEST.x, y - CHEST.y) < 200 || Math.abs(y - (CAVE_GATE.y1 + CAVE_GATE.y2) / 2) < 120 && x < CAVE.x + 400) continue;
      if (CAVE_INNER_WALLS.some(w => inRect(x, y, w, 60)) || !free(x, y, 160)) continue;
      add({ x, y, r: 30 + r() * 40, kind: 'rock', s: Math.floor(r() * 1e6), cr: 26 });
    }
    for (let i = 0; i < 120; i++) {
      const x = CAVE.x + 40 + r() * (CAVE.w - 80), y = CAVE.y + 40 + r() * (CAVE.h - 80);
      if (CAVE_INNER_WALLS.some(w => inRect(x, y, w, 10))) continue;
      CRYSTALS.push({ x, y, c: ['#6ee7ff', '#c77dff', '#7dffb0', '#ff8fd8'][Math.floor(r() * 4)], h: 0.8 + r() * 1.6, s: Math.floor(r() * 1e6) });
    }

    // пустыня: кактусы, красные скалы, пальмы у оазиса
    const desertBusy = (x, y, m = 60) => inPond(x, y, m) || distToRoad(x, y) < 70;
    for (let i = 0; i < 1500; i++) {
      const x = DESERT.x + 80 + r() * (DESERT.w - 160), y = DESERT.y + 80 + r() * (DESERT.h - 160);
      if (desertBusy(x, y) || !free(x, y, 170)) continue;
      const nearOasis = Math.hypot(x - 2100, y - 8000) < 520;
      const k = r();
      if (nearOasis) add({ x, y, r: 34 + r() * 16, kind: 'palm', s: Math.floor(r() * 1e6), cr: 9 });
      else if (k < 0.55) add({ x, y, r: 18 + r() * 14, kind: 'cactus', s: Math.floor(r() * 1e6), cr: 10 });
      else if (k < 0.75) add({ x, y, r: 50 + r() * 60, kind: 'mesa', s: Math.floor(r() * 1e6), cr: 34 });
      else if (k < 0.85) add({ x, y, r: 16 + r() * 10, kind: 'drybush', s: Math.floor(r() * 1e6), cr: 6 });
    }
    // дремучий лес: очень густо
    for (let x = DEEPFOREST.x + 50; x < DEEPFOREST.x + DEEPFOREST.w - 30; x += 82) for (let y = DEEPFOREST.y + 50; y < DEEPFOREST.y + DEEPFOREST.h - 30; y += 82) {
      const px = x + (r() - 0.5) * 50, py = y + (r() - 0.5) * 50;
      if (r() < 0.08 || desertBusy(px, py, 40) || !free(px, py, 66)) continue;
      const k = r();
      add({ x: px, y: py, r: 36 + r() * 26, kind: k < 0.45 ? 'spruce' : k < 0.75 ? 'pine' : 'oak', s: Math.floor(r() * 1e6), cr: 11, dark: true });
    }
    // тундра: заснеженные ели и скалы со снегом
    for (let i = 0; i < 1600; i++) {
      const x = TUNDRA.x + 80 + r() * (TUNDRA.w - 160), y = TUNDRA.y + 80 + r() * (TUNDRA.h - 160);
      if (desertBusy(x, y) || !free(x, y, 150)) continue;
      const k = r();
      if (k < 0.5) add({ x, y, r: 30 + r() * 22, kind: 'snowspruce', s: Math.floor(r() * 1e6), cr: 11 });
      else if (k < 0.85) add({ x, y, r: 45 + r() * 70, kind: 'snowrock', s: Math.floor(r() * 1e6), cr: 30 });
    }
    // острова: пальмы, деревья, цветущие кусты
    for (const I of ISLANDS) {
      for (let i = 0; i < 260; i++) {
        const a = r() * Math.PI * 2, d = Math.sqrt(r()) * 0.88;
        const x = I.x + Math.cos(a) * I.rx * d, y = I.y + Math.sin(a) * I.ry * d;
        if (inRect(x, y, I.stable, 80) || inRect(x, y, I.pasture, 70) || Math.hypot(x - I.pen.x, y - I.pen.y) < I.pen.r + 70 || Math.hypot(x - I.pier.x, y - I.pier.y) < 220) continue;
        if (Math.hypot(x - I.x, y - I.y) < 260 || !free(x, y, 170)) continue;
        const k = r();
        add({ x, y, r: 30 + r() * 20, kind: d > 0.7 && k < 0.6 ? 'palm' : k < 0.5 ? 'oak' : 'birch', s: Math.floor(r() * 1e6), cr: 9 });
      }
    }

    const cols = ['#ffffff', '#ffe066', '#ff8fab', '#c77dff', '#ffd6a5', '#f94144'];
    for (let i = 0; i < 9000; i++) {
      const x = r() * W, y = r() * H;
      if (busy(x, y) || inRect(x, y, MOUNTAIN) || houseBusy(x, y, 10) || inRect(x, y, DESERT) || inRect(x, y, TUNDRA) || inSea(x, y)) continue;
      FLOWERS.push({ x, y, c: cols[Math.floor(r() * cols.length)], s: 1.5 + r() * 2 });
    }
  })();

  // непроходимые прямоугольники (стены, заборы, повозки, скалы, дома)
  const SOLIDS = [];
  const CAVE_WALLS = [
    { x: MOUNTAIN.x, y: 0, w: MOUNTAIN.w, h: CAVE.y },
    { x: MOUNTAIN.x, y: CAVE.y + CAVE.h, w: MOUNTAIN.w, h: MOUNTAIN.h - CAVE.y - CAVE.h },
    { x: MOUNTAIN.x, y: CAVE.y, w: CAVE.x - MOUNTAIN.x, h: CAVE_GATE.y1 - CAVE.y },
    { x: MOUNTAIN.x, y: CAVE_GATE.y2, w: CAVE.x - MOUNTAIN.x, h: CAVE.y + CAVE.h - CAVE_GATE.y2 },
    { x: CAVE.x + CAVE.w, y: CAVE.y, w: MOUNTAIN.x + MOUNTAIN.w - CAVE.x - CAVE.w, h: CAVE.h },
  ];
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
    for (const w of CAVE_WALLS) SOLIDS.push(Object.assign({ rock: true }, w));
    for (const w of CAVE_INNER_WALLS) SOLIDS.push(Object.assign({ rock: true }, w));
    for (const hh of HOUSES) SOLIDS.push({ x: hh.x, y: hh.y, w: hh.w, h: hh.h });
    for (const I of ISLANDS) {
      const st = I.stable, t2 = 10;
      SOLIDS.push({ x: st.x, y: st.y, w: st.w, h: t2 }, { x: st.x, y: st.y, w: t2, h: st.h }, { x: st.x + st.w - t2, y: st.y, w: t2, h: st.h });
      const P2 = I.pasture;
      SOLIDS.push({ x: P2.x - f / 2, y: P2.y - f / 2, w: P2.w + f, h: f });
      SOLIDS.push({ x: P2.x - f / 2, y: P2.y, w: f, h: P2.h });
      SOLIDS.push({ x: P2.x + P2.w - f / 2, y: P2.y, w: f, h: P2.h });
      SOLIDS.push({ x: P2.x - f / 2, y: P2.y + P2.h - f / 2, w: I.gate.x1 - P2.x + f / 2, h: f });
      SOLIDS.push({ x: I.gate.x2, y: P2.y + P2.h - f / 2, w: P2.x + P2.w - I.gate.x2 + f / 2, h: f });
      // круглый манеж: столбики по кругу, вход с севера
      for (let k = 0; k < 24; k++) {
        const a = k / 24 * Math.PI * 2;
        if (Math.abs(a - Math.PI * 1.5) < 0.3) continue;
        SOLIDS.push({ x: I.pen.x + Math.cos(a) * I.pen.r - 9, y: I.pen.y + Math.sin(a) * I.pen.r - 9, w: 18, h: 18, pen: true });
      }
    }
  })();
  // постройки игрока добавляет ферма (farm.js)
  const BUILD_SOLIDS = [];

  // сетка для быстрых столкновений с деревьями
  const GRID = 200, treeGrid = new Map();
  for (const t of TREES) {
    const k = `${Math.floor(t.x / GRID)}|${Math.floor(t.y / GRID)}`;
    if (!treeGrid.has(k)) treeGrid.set(k, []);
    treeGrid.get(k).push(t);
  }
  function treesNear(x, y) {
    const gx = Math.floor(x / GRID), gy = Math.floor(y / GRID), out = [];
    for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) {
      const a = treeGrid.get(`${gx + i}|${gy + j}`);
      if (a) out.push(...a);
    }
    return out;
  }

  function pushOutRect(e, r, s) {
    const cx = Math.max(s.x, Math.min(e.x, s.x + s.w));
    const cy = Math.max(s.y, Math.min(e.y, s.y + s.h));
    const dx = e.x - cx, dy = e.y - cy;
    const d2 = dx * dx + dy * dy;
    if (d2 >= r * r) return;
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

  // вытолкнуть круг (x,y,r) из препятствий
  function collide(e, r) {
    for (const s of SOLIDS) pushOutRect(e, r, s);
    for (const s of BUILD_SOLIDS) pushOutRect(e, r, s);
    for (const t of treesNear(e.x, e.y)) {
      const dx = e.x - t.x, dy = e.y - t.y, d = Math.hypot(dx, dy), rr = r + (t.cr || 9);
      if (d < rr && d > 0) { e.x = t.x + (dx / d) * rr; e.y = t.y + (dy / d) * rr; }
    }
    const L = lakeAt(e.x, e.y, r);
    if (L) {
      const dx = (e.x - L.x) / (L.rx + r), dy = (e.y - L.y) / (L.ry + r);
      const d = Math.hypot(dx, dy) || 1;
      e.x = L.x + (dx / d) * (L.rx + r) * 1.001;
      e.y = L.y + (dy / d) * (L.ry + r) * 1.001;
    }
    // море: на острове — остаёмся на острове, у берега большой земли — не заходим в воду
    if (e.x > SEA.x - r) {
      let best = null, bd = 1e9;
      for (const I of ISLANDS) {
        const d = Math.hypot((e.x - I.x) / I.rx, (e.y - I.y) / I.ry);
        if (d < bd) { bd = d; best = I; }
      }
      const I = best, rx = I.rx - r, ry = I.ry - r;
      const d = Math.hypot((e.x - I.x) / rx, (e.y - I.y) / ry);
      if (d > 1) {
        if (d < 1.6) { e.x = I.x + (e.x - I.x) / d; e.y = I.y + (e.y - I.y) / d; }
        else e.x = Math.min(e.x, SEA.x - r);
      }
    }
    const dw = Math.hypot(e.x - WELL.x, e.y - WELL.y);
    if (dw < WELL.r + r && dw > 0) { e.x = WELL.x + (e.x - WELL.x) / dw * (WELL.r + r); e.y = WELL.y + (e.y - WELL.y) / dw * (WELL.r + r); }
    e.x = Math.max(r, Math.min(W - r, e.x));
    e.y = Math.max(r, Math.min(H - r, e.y));
  }
  // можно ли здесь стоять (для приземления пегаса и стройки)
  function blocked(x, y, r = 14) {
    if (inPond(x, y, r) || inSea(x, y, r)) return true;
    const box = { x: x - r, y: y - r, w: 2 * r, h: 2 * r };
    const hit = s => box.x < s.x + s.w && box.x + box.w > s.x && box.y < s.y + s.h && box.y + box.h > s.y;
    if (SOLIDS.some(hit) || BUILD_SOLIDS.some(hit)) return true;
    return treesNear(x, y).some(t => Math.hypot(t.x - x, t.y - y) < r + (t.cr || 9));
  }

  return {
    W, H, STABLE, STALL_W, STALL_H, AISLE_Y1, AISLE_Y2, stallRect, stallSpot,
    ARENA, GATE_A, LETTERS, letterTarget, CAV, JUMPF, JUMPF_GATE, COURSE, LAMPS, PADDOCK, PADDOCK_GATE, SELL, SHOP, FIELD, POND,
    LAKELAND, FARMLAND, VILLAGE, FOREST, MUSHROOM, MOUNTAIN, CAVE, CAVE_GATE, CAVE_WALLS, CAVE_INNER_WALLS, CHEST, LAKES, ROADS,
    HOUSES, WELL, BOARD, REGION_NAMES, DESERT, DEEPFOREST, TUNDRA, SEA, ISLANDS, PIER, islandAt, inSea,
    TREES, FLOWERS, SHROOMS, CRYSTALS, SOLIDS, BUILD_SOLIDS, collide, blocked, inRect, inPond, lakeAt, regionAt, inForest, distToRoad, treesNear, rng,
  };
})();

'use strict';
/*
 * Карта мира: где что стоит и что непроходимо.
 * Первоначальный город (ферма, поле, деревня, огороды) — в середине, биомы — вокруг него.
 * Границы биомов, острова и озёра — неровные, «живые» (шум и гармоники), а не квадраты и овалы.
 */
const World = (() => {
  // сдвиг старой карты: на север и на запад от города добавлены новые биомы
  const OX = 3200, OY = 3200;
  const W = 17600, H = 12800;
  const sh = o => Object.assign(o, { x: o.x + OX, y: o.y + OY });
  const shp = ([x, y]) => [x + OX, y + OY];

  /* ---------- шум и неровные формы ---------- */
  function hash2(ix, iy, s) {
    let h = Math.imul(ix | 0, 374761393) ^ Math.imul(iy | 0, 668265263) ^ Math.imul(s | 0, 1442695041);
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }
  function vnoise(x, y, s) {
    const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
    const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
    const a = hash2(ix, iy, s), b = hash2(ix + 1, iy, s), c = hash2(ix, iy + 1, s), d = hash2(ix + 1, iy + 1, s);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }
  // «размытые» координаты: прямые границы биомов становятся волнистыми
  function warp(x, y) {
    return {
      x: x + (vnoise(x / 1500, y / 1500, 1) - 0.5) * 820 + (vnoise(x / 480, y / 480, 3) - 0.5) * 260,
      y: y + (vnoise(x / 1500, y / 1500, 2) - 0.5) * 820 + (vnoise(x / 480, y / 480, 4) - 0.5) * 260,
    };
  }
  // неровный контур: радиус-множитель по углу (сумма синусов со случайными фазами)
  function harmonics(seed, amp = 1) {
    const r = rng(seed * 7919 + 13);
    return [[2, 0.1], [3, 0.08], [4, 0.05], [5, 0.04], [7, 0.025], [9, 0.015]].map(([k, a]) => ({ k, a: a * amp * (0.6 + r() * 0.8), p: r() * Math.PI * 2 }));
  }
  function shapeR(B, a) {
    let s = 1;
    for (const q of B.H) s += q.a * Math.sin(q.k * a + q.p);
    return Math.max(B.minR || 0.82, s);
  }
  // точка относительно неровного пятна: d — нормированное расстояние, R — граница, unit — пикселей на единицу
  function blobInfo(B, x, y) {
    const nx = (x - B.x) / B.rx, ny = (y - B.y) / B.ry;
    const d = Math.hypot(nx, ny), a = Math.atan2(ny, nx);
    return { d, a, R: shapeR(B, a), unit: Math.hypot(B.rx * Math.cos(a), B.ry * Math.sin(a)) || 1, nx, ny };
  }
  // внутри ли пятна с запасом m (m > 0 — расширить, m < 0 — сузить)
  function inBlob(B, x, y, m = 0) {
    const q = blobInfo(B, x, y);
    return q.d < q.R + m / q.unit;
  }
  // точка на границе пятна (с отступом off в пикселях)
  function blobPoint(B, a, off = 0) {
    const R = shapeR(B, a), ux = Math.cos(a), uy = Math.sin(a), unit = Math.hypot(B.rx * ux, B.ry * uy) || 1;
    const k = R + off / unit;
    return { x: B.x + B.rx * ux * k, y: B.y + B.ry * uy * k };
  }
  function blobPoly(B, off = 0, n = 72) {
    const pts = [];
    for (let i = 0; i < n; i++) pts.push(blobPoint(B, i / n * Math.PI * 2, off));
    return pts;
  }
  // вытолкнуть точку e на границу пятна: inside=true — удержать внутри, false — не пускать внутрь
  function blobPush(B, e, r, inside) {
    const q = blobInfo(B, e.x, e.y);
    if (q.d < 1e-6) { if (!inside) e.x = B.x + B.rx * (q.R + r / B.rx) * 1.001; return; }
    const lim = inside ? q.R - r / q.unit : q.R + r / q.unit;
    if (inside ? q.d <= lim : q.d >= lim) return;
    const k = lim / q.d * (inside ? 0.999 : 1.001);
    e.x = B.x + (e.x - B.x) * k; e.y = B.y + (e.y - B.y) * k;
  }

  // Конюшня: 2 ряда по 10 денников, проход посередине, ворота слева и справа
  const STALL_W = 72, STALL_H = 120, AISLE = 80;
  const STABLE = sh({ x: 120, y: 140, w: 740, h: 10 + STALL_H + AISLE + STALL_H + 10 });
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
  const ARENA = sh({ x: 140, y: 640, w: 820, h: 410 });
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
  const PADDOCK = sh({ x: 1000, y: 110, w: 540, h: 420 });
  const PADDOCK_GATE = { x1: PADDOCK.x + 210, x2: PADDOCK.x + 320 };

  // Повозки
  const SELL = sh({ x: 1190, y: 700, w: 130, h: 66, name: 'Продажа лошадей' });
  const SHOP = sh({ x: 1190, y: 900, w: 130, h: 66, name: 'Корм и амуниция' });

  // Конкурное поле: 8 препятствий, ворота сверху слева
  const JUMPF = sh({ x: 140, y: 1170, w: 1360, h: 620 });
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
  ].map(sh);

  // Большое поле с табуном
  const FIELD = sh({ x: 1760, y: 100, w: 1940, h: 2200 });
  const START = sh({ x: 1840, y: 560 });                          // старт скачек

  /* ---------- город и биомы вокруг ---------- */
  const LAKELAND = sh({ x: 3800, y: 100, w: 2400, h: 2500 });        // Озёрный край
  const FARMLAND = sh({ x: 150, y: 2500, w: 1600, h: 900 });         // поля и огороды
  const VILLAGE = sh({ x: 1900, y: 2500, w: 1700, h: 900 });         // деревня
  const FOREST = [sh({ x: 0, y: 3500, w: 6200, h: 2900 }), sh({ x: 3800, y: 2650, w: 2400, h: 850 })];
  const MUSHROOM = sh({ x: 6300, y: 2900, w: 3300, h: 3500 });       // Грибное королевство (волшебный биом)
  const MOUNTAIN = sh({ x: 6300, y: 0, w: 3300, h: 2800 });          // горы
  const CAVE = sh({ x: 6600, y: 350, w: 2700, h: 2100 });            // пещера внутри гор
  const CAVE_GATE = { y1: 1300 + OY, y2: 1500 + OY };                // вход в пещеру с запада
  const CHEST = sh({ x: 9050, y: 650 });                             // сундук графа в глубине пещеры
  // внутренние скальные стены пещеры: проход «змейкой»
  const CAVE_INNER_WALLS = [
    { x: 7350, y: 350, w: 120, h: 1350 },
    { x: 8250, y: 1150, w: 120, h: 1300 },
    { x: 7350, y: 2050, w: 500, h: 110 },
  ].map(sh);

  // юг: пустыня (вместе с юго-западом), дремучий лес, тундра
  const DESERT = { x: 0, y: 6500 + OY, w: 4300 + OX, h: 3100 };
  const DEEPFOREST = sh({ x: 4300, y: 6500, w: 2300, h: 3100 });
  const TUNDRA = sh({ x: 6600, y: 6500, w: 3000, h: 3100 });

  // новые биомы вокруг города: север и запад
  const GROTTO = { x: 0, y: 0, w: 4400, h: 3400 };                   // Пещерные холмы с маленькими пещерками
  const FOXWOOD = { x: 4400, y: 0, w: 5000, h: 3200 };               // Лисий лес — густой лес
  const DRAGONROCK = { x: 9400, y: 0, w: 3500, h: 3200 };            // Драконьи скалы
  const STEPPE = { x: 0, y: 3400, w: 3200, h: 6300 };                // Степь

  // город: неровное «пятно», в которое биомы не заходят
  const TOWN = { x: 1875 + OX, y: 1725 + OY, rx: 2300, ry: 2130, H: harmonics(5, 0.7), minR: 0.97 };
  function inTown(x, y) {
    if (!inRect(x, y, { x: OX - 400, y: OY - 400, w: 3750 + 800, h: 3450 + 800 })) return false;
    const nx = (x - TOWN.x) / TOWN.rx, ny = (y - TOWN.y) / TOWN.ry;
    const d = Math.pow(Math.pow(Math.abs(nx), 6) + Math.pow(Math.abs(ny), 6), 1 / 6);   // «скруглённый квадрат»
    return d < shapeR(TOWN, Math.atan2(ny, nx));
  }

  // восток: море с неровным берегом и острова
  const SEA = { x: 9700 + OX, y: 0, w: W - 9700 - OX, h: H };
  const coastX = y => SEA.x + vnoise(y / 1100, 0.5, 7) * 330 + vnoise(y / 330, 0.5, 8) * 110;
  const ISLANDS = [
    { id: 'i1', name: 'Остров бабочек', x: 11300, y: 2000, rx: 950, ry: 760, breeds: ['butterflyhorse', 'beehorse', 'dragonflyhorse', 'haflinger', 'arab'] },
    { id: 'i2', name: 'Драконий остров', x: 12900, y: 4900, rx: 920, ry: 800, breeds: ['dragonhorse', 'scalehorse', 'scalehorse', 'ravenhorse', 'friesian'] },
    { id: 'i3', name: 'Остров ветров', x: 11300, y: 7700, rx: 1000, ry: 760, breeds: ['ravenhorse', 'dragonflyhorse', 'pegasus', 'paint', 'appaloosa'] },
    { id: 'i4', name: 'Костяной остров', x: 12650, y: -1150, rx: 980, ry: 800, bone: true, breeds: ['bonehorse', 'bonehorse', 'bonehorse', 'bonehorse', 'skeleton'] },
  ].map(sh);
  ISLANDS.forEach((I, k) => { I.H = harmonics(31 + k * 11, 1.1); I.minR = 0.95; });
  for (const I of ISLANDS) {
    I.stable = { x: I.x - 480, y: I.y - 430, w: 340, h: 150 };                 // 5 денников, открыта на юг
    I.pasture = { x: I.x + 60, y: I.y - 460, w: 400, h: 300 };                 // пастбище с забором
    I.gate = { x1: I.pasture.x + 150, x2: I.pasture.x + 250 };
    I.pen = { x: I.x - 260, y: I.y + 260, r: 170 };                            // круглый манеж
    I.pier = { x: blobPoint(I, Math.PI).x + 70, y: I.y };                       // причал на западном берегу
    I.area = { x: I.x - I.rx + 150, y: I.y - I.ry + 150, w: I.rx * 2 - 300, h: I.ry * 2 - 300 };
  }
  const PIER = { x: coastX(4700 + OY) - 140, y: 4700 + OY, name: 'Пристань' };   // причал на большой земле

  // Рынок в деревне: торговцы лошадьми, тренер, обменщик и своя стойка
  const MARKET = sh({ x: 2860, y: 3020, w: 640, h: 360 });
  const MARKET_STALLS = [
    { id: 'horses', name: '🐎 Конский торговец', roof: '#d63a3a' },
    { id: 'trainer', name: '💪 Тренер', roof: '#2e86de' },
    { id: 'swap', name: '🔁 Обменщик', roof: '#8e44ad' },
    { id: 'mine', name: '🏷️ Моя стойка', roof: '#f39c12' },
  ].map((st, i) => Object.assign(st, { x: MARKET.x + 30 + i * 155, y: MARKET.y + 40, w: 120, h: 36 }));
  // точка перед прилавком, где стоит игрок
  const stallFront = st => ({ x: st.x + st.w / 2, y: st.y + st.h + 55 });

  // Портал в глубине пещеры — ведёт на небесные острова
  const PORTAL = sh({ x: 8900, y: 2050, r: 55 });

  /* ---------- небесные острова: за южным краем земли, над облаками ---------- */
  const SKY = sh({ x: 600, y: 10000, w: 8600, h: 2500 });
  const TOTAL_H = SKY.y + SKY.h + 200;
  const SKY_ISLANDS = [
    { id: 'sky1', name: 'Облачный остров', x: 4800, y: 11150, rx: 1100, ry: 640 },
    { id: 'sky2', name: 'Радужный остров', x: 2150, y: 10850, rx: 720, ry: 480 },
    { id: 'sky3', name: 'Солнечный остров', x: 7450, y: 10850, rx: 720, ry: 480 },
    { id: 'sky4', name: 'Лиановый островок', x: 3300, y: 12050, rx: 430, ry: 300 },
    { id: 'sky5', name: 'Звёздный островок', x: 6350, y: 12080, rx: 430, ry: 300 },
  ].map(sh);
  SKY_ISLANDS.forEach((I, k) => { I.H = harmonics(101 + k * 17, 1); I.minR = 0.93; });
  for (const I of SKY_ISLANDS) I.area = { x: I.x - I.rx + 140, y: I.y - I.ry + 120, w: I.rx * 2 - 280, h: I.ry * 2 - 240 };
  // мосты из лиан между островами: отрезки шириной 2*BRIDGE_W
  const BRIDGE_W = 42;
  const SKY_BRIDGES = [
    [3720, 11000, 2850, 10900], [5880, 11000, 6750, 10900],
    [4150, 11650, 3550, 11850], [5450, 11650, 6100, 11880],
  ].map(([a, b, c, d]) => [a + OX, b + OY, c + OX, d + OY]);
  const SKY_PORTAL = sh({ x: 4800, y: 10900, r: 55 });
  function skyIslandAt(x, y, m = 0) {
    for (const I of SKY_ISLANDS) if (inBlob(I, x, y, -m)) return I;
    return null;
  }
  function segPoint(x, y, b) {
    const [ax, ay, bx, by] = b, dx = bx - ax, dy = by - ay, L2 = dx * dx + dy * dy;
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / L2));
    return { x: ax + dx * t, y: ay + dy * t };
  }
  const onBridge = (x, y, m = 0) => SKY_BRIDGES.some(b => { const q = segPoint(x, y, b); return Math.hypot(q.x - x, q.y - y) < BRIDGE_W - m; });
  const inSkyZone = y => y > H;
  // можно ли стоять в небе (на острове или мосту)
  const skyWalkable = (x, y, m = 0) => !!skyIslandAt(x, y, m) || onBridge(x, y, m);
  function islandAt(x, y, m = 0) {
    if (x < SEA.x - 200) return null;
    for (const I of ISLANDS) if (inBlob(I, x, y, -m)) return I;
    return null;
  }
  const inSea = (x, y, m = 0) => x > coastX(y) - m && !islandAt(x, y, m);

  // озёра: неровные пятна
  const LAKES = [
    { x: 2780, y: 1650, rx: 210, ry: 130, name: 'Пруд' },
    { x: 4950, y: 1150, rx: 620, ry: 360, name: 'Большое озеро' },
    { x: 4300, y: 2150, rx: 250, ry: 160 },
    { x: 2900, y: 4900, rx: 360, ry: 230, name: 'Лесное озеро' },
    { x: 8000, y: 5200, rx: 260, ry: 180, magic: true, name: 'Волшебный пруд' },
    { x: 2100, y: 8000, rx: 260, ry: 170, name: 'Оазис' },
    { x: 8100, y: 8300, rx: 380, ry: 230, ice: true, name: 'Ледяное озеро' },
  ].map(sh).concat([
    { x: 1400, y: 5600, rx: 340, ry: 210, name: 'Степное озеро' },
    { x: 6900, y: 1500, rx: 300, ry: 200, name: 'Лисье озеро' },
    { x: 10500, y: 1700, rx: 260, ry: 170, lava: true, name: 'Лавовое озеро' },
    { x: 11800, y: 800, rx: 190, ry: 130, lava: true, name: 'Лавовое озеро' },
  ]);
  LAKES.forEach((L, k) => { L.H = harmonics(200 + k * 7, 1.3); L.minR = 0.8; });
  const POND = LAKES[0];
  const OASIS = LAKES[5];

  // маленькие пещерки в Пещерных холмах: каменное кольцо с входом, внутри темно
  const GROTTOS = [
    { x: 900, y: 950, r: 270, door: 0.4 }, { x: 2350, y: 650, r: 240, door: 1.9 }, { x: 3650, y: 1250, r: 260, door: 2.6 },
    { x: 1150, y: 2450, r: 250, door: -0.8 }, { x: 2750, y: 2350, r: 280, door: -1.6 },
  ].map((g, i) => Object.assign(g, { id: 'grotto' + i, name: 'Пещерка' }));
  const inGrotto = (x, y, m = 0) => GROTTOS.find(g => Math.hypot(x - g.x, y - g.y) < g.r - m) || null;

  // железная дорога через пустыню и станция
  const RAIL = { y: 10450, x1: 120, x2: 7380 };
  const STATION = { x: 3900, y: RAIL.y - 150, w: 520, h: 90 };

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
  ].map(r => r.map(shp)).concat([
    // новые дороги: к пещерным холмам, в лисий лес, к драконьим скалам, в степь и к станции
    [[OX + 70, OY + 310], [2900, 2900], [2400, 2300]],
    [[OX + 1000, OY + 110], [5600, 2400], [6400, 1400], [7400, 900]],
    [[OX + 3700, OY + 1500], [9000, 3000], [10200, 2600], [11200, 2200]],
    [[OX + 150, OY + 2950], [2400, 5200], [1700, 6600], [1300, 8600]],
    [[OX + 2100, OY + 7700], [5300, RAIL.y - 60], [STATION.x + STATION.w / 2, RAIL.y - 100]],
  ]);
  ROADS[14][2] = [PIER.x + 60, PIER.y];   // дорога к пристани кончается у причала

  // дома деревни и лесная сторожка
  const HOUSES = [
    { x: 2150, y: 2640, w: 200, h: 150, name: 'Кузница', roof: '#5f5f5f', wall: '#9a8f80' },
    { x: 2750, y: 2620, w: 200, h: 150, name: 'Салон «Грива»', roof: '#c2255c', wall: '#f8e1ea' },
    { x: 3150, y: 2700, w: 180, h: 140, roof: '#8c3b2a', wall: '#e9d8b5' },
    { x: 2420, y: 3080, w: 180, h: 140, roof: '#2f6f8f', wall: '#efe4cf' },
    { x: 1430, y: 2560, w: 180, h: 140, name: 'Дом бабушки Гали', roof: '#a33a2a', wall: '#f1e3c6' },
    { x: 1480, y: 3380, w: 180, h: 130, name: 'Сторожка лесника', roof: '#3b5e2b', wall: '#8a5a32' },
  ].map(sh);
  const WELL = sh({ x: 2620, y: 2880, r: 26 });
  const BOARD = sh({ x: 2720, y: 2980 });                             // доска заданий
  const SQUARE = sh({ x: 2650, y: 2920, rx: 330, ry: 190 });          // деревенская площадь

  // детерминированный генератор — каждый раз одинаковая карта
  function rng(seed) {
    return function () {
      seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function inRect(x, y, r, m = 0) { return x >= r.x - m && x <= r.x + r.w + m && y >= r.y - m && y <= r.y + r.h + m; }
  function lakeAt(x, y, m = 0) {
    for (const L of LAKES) {
      if (Math.abs(x - L.x) > L.rx * 1.4 + m || Math.abs(y - L.y) > L.ry * 1.4 + m) continue;
      if (inBlob(L, x, y, m)) return L;
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
  const inForest = (x, y) => regionAt(x, y) === 'forest';

  // биомы вокруг города: проверяются по «размытым» координатам, поэтому границы неровные
  const OUTER = [
    ['desert', DESERT], ['deepforest', DEEPFOREST], ['tundra', TUNDRA], ['mushroom', MUSHROOM],
    ['forest', FOREST[0]], ['forest', FOREST[1]], ['lake', LAKELAND], ['mountain', MOUNTAIN],
    ['grotto', GROTTO], ['foxwood', FOXWOOD], ['dragonrock', DRAGONROCK], ['steppe', STEPPE],
  ];
  function biomeAt(x, y) {
    const w = warp(x, y);
    for (const [id, r] of OUTER) if (inRect(w.x, w.y, r)) return id;
    return 'farm';
  }
  function regionAt(x, y) {
    if (y > H) { const SI = skyIslandAt(x, y); return SI ? SI.id : 'sky'; }
    if (inRect(x, y, MARKET)) return 'market';
    if (x > SEA.x - 300) {
      const I = islandAt(x, y);
      if (I) return I.id;
      if (x > coastX(y)) return 'sea';
    }
    if (inRect(x, y, CAVE)) return 'cave';
    if (inRect(x, y, MOUNTAIN)) return 'mountain';
    if (inTown(x, y)) {
      if (inRect(x, y, VILLAGE)) return 'village';
      if (inRect(x, y, FARMLAND)) return 'farmland';
      if (inRect(x, y, FIELD)) return 'field';
      return 'farm';
    }
    if (x < GROTTO.x + GROTTO.w + 400 && y < GROTTO.y + GROTTO.h + 400 && inGrotto(x, y)) return 'grottocave';
    return biomeAt(x, y);
  }
  const REGION_NAMES = {
    farm: 'Ферма', field: 'Большое поле', lake: 'Озёрный край', forest: 'Лес', village: 'Деревня',
    farmland: 'Поля и огороды', mushroom: 'Грибное королевство', mountain: 'Горы', cave: 'Пещера',
    desert: 'Пустыня', deepforest: 'Дремучий лес', tundra: 'Тундра', sea: 'Море',
    grotto: 'Пещерные холмы', grottocave: 'Пещерка', foxwood: 'Лисий лес', dragonrock: 'Драконьи скалы', steppe: 'Степь',
    i1: ISLANDS[0].name, i2: ISLANDS[1].name, i3: ISLANDS[2].name, i4: ISLANDS[3].name,
    market: 'Рынок', sky: 'Небо', sky1: SKY_ISLANDS[0].name, sky2: SKY_ISLANDS[1].name, sky3: SKY_ISLANDS[2].name,
    sky4: SKY_ISLANDS[3].name, sky5: SKY_ISLANDS[4].name,
  };

  // деревья, грибы, камни, цветы, кости
  // kind: oak, birch, pine (сосна), spruce (ель), amanita/boletus/glowshroom (большие грибы), rock, crystal…
  // soft: true — через это можно пройти (трава, мелкие кости)
  const TREES = [], FLOWERS = [], SHROOMS = [], CRYSTALS = [], VINES = [];
  const houseBusy = (x, y, m) => HOUSES.some(hh => inRect(x, y, hh, m)) || Math.hypot(x - WELL.x, y - WELL.y) < m + 30;
  const railBusy = (x, y, m = 0) => (Math.abs(y - RAIL.y) < 110 + m && x > RAIL.x1 - 100 && x < RAIL.x2 + 100) || inRect(x, y, STATION, 120 + m);
  const grottoBusy = (x, y, m = 0) => GROTTOS.some(g => Math.hypot(x - g.x, y - g.y) < g.r + 90 + m);
  (function decorate() {
    const r = rng(42);
    const seedOf = () => Math.floor(r() * 1e6);
    const busy = (x, y) => Math.hypot(x - START.x, y - START.y) < 280 || inRect(x, y, STABLE, 60) || inRect(x, y, JUMPF, 70) || (x < OX + 300 && y > OY + 820 && y < OY + 1200) || inRect(x, y, ARENA, 70) || inRect(x, y, PADDOCK, 60) ||
      inRect(x, y, SELL, 90) || inRect(x, y, SHOP, 90) || inPond(x, y, 70) ||
      (x > OX + 860 && x < OX + 1000 && y > OY + 260 && y < OY + 640) || (x > OX + 900 && x < OX + 1850 && y > OY + 540 && y < OY + 660) || (x > OX + 1060 && x < OX + 1170 && y > OY + 560 && y < OY + 1060);
    let tries = 0;
    while (TREES.length < 46 && tries++ < 3000) {
      const inField = r() < 0.6;
      const x = inField ? FIELD.x + 60 + r() * (FIELD.w - 120) : OX + 40 + r() * 1640;
      const y = inField ? FIELD.y + 60 + r() * (FIELD.h - 120) : OY + 1120 + r() * 1220;
      if (busy(x, y)) continue;
      if (inField && Math.hypot(x - (FIELD.x + FIELD.w / 2), y - (FIELD.y + FIELD.h / 2)) < 420) continue;
      if (TREES.some(t => Math.hypot(t.x - x, t.y - y) < 120)) continue;
      if (distToRoad(x, y) < 50) continue;
      TREES.push({ x, y, r: 32 + r() * 22, kind: r() < 0.3 ? 'birch' : 'oak', s: seedOf(), cr: 9 });
    }

    // сетка «занятости», чтобы деревья не налезали друг на друга
    const occ = new Map();
    const okey = (x, y) => `${Math.floor(x / 100)}|${Math.floor(y / 100)}`;
    const free = (x, y, d) => {
      const gx = Math.floor(x / 100), gy = Math.floor(y / 100);
      const k = Math.ceil(d / 100);
      for (let i = -k; i <= k; i++) for (let j = -k; j <= k; j++) {
        for (const t of occ.get(`${gx + i}|${gy + j}`) || []) if (Math.hypot(t.x - x, t.y - y) < d) return false;
      }
      return true;
    };
    const add = t => { TREES.push(t); const k = okey(t.x, t.y); if (!occ.has(k)) occ.set(k, []); occ.get(k).push(t); };
    TREES.forEach(t => { const k = okey(t.x, t.y); if (!occ.has(k)) occ.set(k, []); occ.get(k).push(t); });
    const blockedBig = (x, y, m = 60) => inPond(x, y, m) || distToRoad(x, y) < 70 || houseBusy(x, y, m) || inTown(x, y) || inRect(x, y, MOUNTAIN, 40) || railBusy(x, y) || grottoBusy(x, y);
    // точки в биоме: прямоугольник с запасом, оставляем только то, что действительно в этом биоме
    const pad = 560;
    const sampleIn = (rect, id, n, fn) => {
      for (let i = 0; i < n; i++) {
        const x = rect.x - pad + r() * (rect.w + pad * 2), y = rect.y - pad + r() * (rect.h + pad * 2);
        if (x < 30 || y < 30 || x > W - 30 || y > H - 30) continue;
        if (regionAt(x, y) !== id) continue;
        fn(x, y);
      }
    };
    const gridIn = (rect, id, step, jit, fn) => {
      for (let x = rect.x - pad; x < rect.x + rect.w + pad; x += step) for (let y = rect.y - pad; y < rect.y + rect.h + pad; y += step) {
        const px = x + (r() - 0.5) * jit, py = y + (r() - 0.5) * jit;
        if (px < 30 || py < 30 || px > W - 30 || py > H - 30) continue;
        if (regionAt(px, py) !== id) continue;
        fn(px, py);
      }
    };

    // озёрный край: редкие деревья
    sampleIn(LAKELAND, 'lake', 520, (x, y) => {
      if (blockedBig(x, y) || !free(x, y, 150)) return;
      add({ x, y, r: 30 + r() * 24, kind: r() < 0.45 ? 'birch' : r() < 0.5 ? 'pine' : 'oak', s: seedOf(), cr: 9 });
    });
    // лес: густо, с полянами
    const clearings = Array.from({ length: 14 }, () => ({ x: OX + r() * 6200, y: OY + 3500 + r() * 2900, r: 160 + r() * 200 }));
    for (const f of FOREST) gridIn(f, 'forest', 108, 80, (px, py) => {
      if (r() < 0.12) return;
      if (blockedBig(px, py) || clearings.some(c => Math.hypot(c.x - px, c.y - py) < c.r) || !free(px, py, 80)) return;
      const k = r();
      add({ x: px, y: py, r: 30 + r() * 26, kind: k < 0.4 ? 'pine' : k < 0.65 ? 'birch' : 'oak', s: seedOf(), cr: 10 });
    });
    // грибное королевство: ели и огромные грибы
    gridIn(MUSHROOM, 'mushroom', 160, 110, (px, py) => {
      if (r() < 0.35) return;
      if (blockedBig(px, py) || !free(px, py, 110)) return;
      const k = r();
      if (k < 0.62) add({ x: px, y: py, r: 34 + r() * 26, kind: 'spruce', s: seedOf(), cr: 12 });
      else add({ x: px, y: py, r: 35 + r() * 30, kind: k < 0.78 ? 'amanita' : k < 0.9 ? 'boletus' : 'glowshroom', s: seedOf(), cr: 16 });
    });
    // маленькие грибы — можно собирать
    const shroomAt = (area, id, n, types) => sampleIn(area, id, n, (x, y) => {
      if (inPond(x, y, 10) || houseBusy(x, y, 20)) return;
      SHROOMS.push({ x, y, type: types[Math.floor(r() * types.length)], s: r() });
    });
    shroomAt(MUSHROOM, 'mushroom', 640, ['white', 'chanterelle', 'amanita', 'glow', 'glow', 'violet']);
    shroomAt(FOREST[0], 'forest', 330, ['white', 'chanterelle', 'chanterelle', 'amanita']);
    shroomAt(FOXWOOD, 'foxwood', 260, ['white', 'chanterelle', 'amanita', 'amanita']);
    SHROOMS.forEach((m, i) => (m.id = i));

    // горы: валуны у подножия, чтобы край гор был неровным
    for (let i = 0; i < 260; i++) {
      const side = Math.floor(r() * 4), M = MOUNTAIN;
      const t = r(), out = 20 + r() * 260;
      const x = side === 0 ? M.x + t * M.w : side === 1 ? M.x + M.w + out : side === 2 ? M.x + t * M.w : M.x - out;
      const y = side === 0 ? M.y - out : side === 1 ? M.y + t * M.h : side === 2 ? M.y + M.h + out : M.y + t * M.h;
      if (side === 3 && y > CAVE_GATE.y1 - 160 && y < CAVE_GATE.y2 + 160) continue;
      if (inPond(x, y, 40) || distToRoad(x, y) < 60 || !free(x, y, 90)) continue;
      add({ x, y, r: 50 + r() * 70, kind: 'cliff', s: seedOf(), cr: 34 });
    }
    // пещера: валуны и светящиеся кристаллы
    for (let i = 0; i < 70; i++) {
      const x = CAVE.x + 100 + r() * (CAVE.w - 200), y = CAVE.y + 100 + r() * (CAVE.h - 200);
      if (Math.hypot(x - CHEST.x, y - CHEST.y) < 200 || Math.hypot(x - PORTAL.x, y - PORTAL.y) < 260 || Math.abs(y - (CAVE_GATE.y1 + CAVE_GATE.y2) / 2) < 120 && x < CAVE.x + 400) continue;
      if (CAVE_INNER_WALLS.some(w => inRect(x, y, w, 60)) || !free(x, y, 160)) continue;
      add({ x, y, r: 30 + r() * 40, kind: 'rock', s: seedOf(), cr: 26 });
    }
    const crystalCols = ['#6ee7ff', '#c77dff', '#7dffb0', '#ff8fd8'];
    for (let i = 0; i < 120; i++) {
      const x = CAVE.x + 40 + r() * (CAVE.w - 80), y = CAVE.y + 40 + r() * (CAVE.h - 80);
      if (CAVE_INNER_WALLS.some(w => inRect(x, y, w, 10))) continue;
      CRYSTALS.push({ x, y, c: crystalCols[Math.floor(r() * 4)], h: 0.8 + r() * 1.6, s: seedOf() });
    }

    // пустыня: кактусы, красные скалы, пальмы у оазиса
    const desertBusy = (x, y, m = 60) => inPond(x, y, m) || distToRoad(x, y) < 70 || railBusy(x, y);
    sampleIn(DESERT, 'desert', 2600, (x, y) => {
      if (desertBusy(x, y) || !free(x, y, 170)) return;
      const nearOasis = Math.hypot(x - OASIS.x, y - OASIS.y) < 520;
      const k = r();
      if (nearOasis) add({ x, y, r: 34 + r() * 16, kind: 'palm', s: seedOf(), cr: 9 });
      else if (k < 0.55) add({ x, y, r: 18 + r() * 14, kind: 'cactus', s: seedOf(), cr: 10 });
      else if (k < 0.75) add({ x, y, r: 50 + r() * 60, kind: 'mesa', s: seedOf(), cr: 34 });
      else if (k < 0.85) add({ x, y, r: 16 + r() * 10, kind: 'drybush', s: seedOf(), cr: 6 });
    });
    // дремучий лес: очень густо
    gridIn(DEEPFOREST, 'deepforest', 82, 50, (px, py) => {
      if (r() < 0.08 || desertBusy(px, py, 40) || !free(px, py, 66)) return;
      const k = r();
      add({ x: px, y: py, r: 36 + r() * 26, kind: k < 0.45 ? 'spruce' : k < 0.75 ? 'pine' : 'oak', s: seedOf(), cr: 11, dark: true });
    });
    // тундра: заснеженные ели и скалы со снегом
    sampleIn(TUNDRA, 'tundra', 2200, (x, y) => {
      if (desertBusy(x, y) || !free(x, y, 150)) return;
      const k = r();
      if (k < 0.5) add({ x, y, r: 30 + r() * 22, kind: 'snowspruce', s: seedOf(), cr: 11 });
      else if (k < 0.85) add({ x, y, r: 45 + r() * 70, kind: 'snowrock', s: seedOf(), cr: 30 });
    });

    /* ----- новые биомы ----- */
    // Пещерные холмы: травянистые холмы, валуны, кусты
    sampleIn(GROTTO, 'grotto', 1300, (x, y) => {
      if (blockedBig(x, y) || !free(x, y, 160)) return;
      const k = r();
      if (k < 0.3) add({ x, y, r: 90 + r() * 110, kind: 'hill', s: seedOf(), cr: 40 });
      else if (k < 0.6) add({ x, y, r: 30 + r() * 40, kind: 'rock', s: seedOf(), cr: 24 });
      else if (k < 0.8) add({ x, y, r: 30 + r() * 20, kind: r() < 0.5 ? 'birch' : 'pine', s: seedOf(), cr: 9 });
      else add({ x, y, r: 18 + r() * 10, kind: 'bush', s: seedOf(), cr: 8 });
    });
    // кольца пещерок: камни по кругу с проходом
    for (const g of GROTTOS) {
      const n = Math.round(g.r * 2 * Math.PI / 70);
      for (let k = 0; k < n; k++) {
        const a = k / n * Math.PI * 2;
        let da = Math.abs(((a - g.door) % (Math.PI * 2) + Math.PI * 3) % (Math.PI * 2) - Math.PI);
        if (da < 0.32) continue;
        add({ x: g.x + Math.cos(a) * g.r, y: g.y + Math.sin(a) * g.r, r: 44 + r() * 14, kind: 'cavewall', s: seedOf(), cr: 40 });
      }
      for (let i = 0; i < 14; i++) {
        const a = r() * Math.PI * 2, d = r() * (g.r - 70);
        CRYSTALS.push({ x: g.x + Math.cos(a) * d, y: g.y + Math.sin(a) * d, c: crystalCols[Math.floor(r() * 4)], h: 0.6 + r() * 1.2, s: seedOf() });
      }
    }
    // Лисий лес: очень густой, тёмный
    const foxClear = Array.from({ length: 12 }, () => ({ x: FOXWOOD.x + r() * FOXWOOD.w, y: FOXWOOD.y + r() * FOXWOOD.h, r: 150 + r() * 160 }));
    gridIn(FOXWOOD, 'foxwood', 88, 60, (px, py) => {
      if (r() < 0.06 || blockedBig(px, py, 40) || foxClear.some(c => Math.hypot(c.x - px, c.y - py) < c.r) || !free(px, py, 70)) return;
      const k = r();
      add({ x: px, y: py, r: 34 + r() * 28, kind: k < 0.35 ? 'spruce' : k < 0.6 ? 'pine' : k < 0.8 ? 'oak' : k < 0.93 ? 'birch' : 'bush', s: seedOf(), cr: k < 0.93 ? 11 : 8, dark: k < 0.6 });
    });
    // Драконьи скалы: чёрные шпили с лавой, мёртвые деревья, драконьи кости
    sampleIn(DRAGONROCK, 'dragonrock', 1500, (x, y) => {
      if (blockedBig(x, y) || !free(x, y, 170)) return;
      const k = r();
      if (k < 0.45) add({ x, y, r: 45 + r() * 70, kind: 'spire', s: seedOf(), cr: 30 });
      else if (k < 0.65) add({ x, y, r: 26 + r() * 14, kind: 'deadtree', s: seedOf(), cr: 9 });
      else if (k < 0.75) add({ x, y, r: 60 + r() * 50, kind: 'bigbone', s: seedOf(), cr: 0, soft: true });
      else if (k < 0.9) add({ x, y, r: 30 + r() * 30, kind: 'basalt', s: seedOf(), cr: 22 });
    });
    // Степь: высокая трава, редкие деревья и камни
    sampleIn(STEPPE, 'steppe', 2600, (x, y) => {
      if (blockedBig(x, y, 30) || !free(x, y, 120)) return;
      const k = r();
      if (k < 0.62) add({ x, y, r: 16 + r() * 14, kind: 'grass', s: seedOf(), cr: 0, soft: true });
      else if (k < 0.72) add({ x, y, r: 30 + r() * 24, kind: r() < 0.6 ? 'oak' : 'birch', s: seedOf(), cr: 9 });
      else if (k < 0.82) add({ x, y, r: 26 + r() * 30, kind: 'rock', s: seedOf(), cr: 18 });
      else add({ x, y, r: 16 + r() * 10, kind: 'bush', s: seedOf(), cr: 7 });
    });

    // острова: пальмы, деревья, цветущие кусты; на Костяном — огромные и маленькие кости
    for (const I of ISLANDS) {
      for (let i = 0; i < 300; i++) {
        const a = r() * Math.PI * 2, d = Math.sqrt(r()) * 0.9 * shapeR(I, a);
        const x = I.x + Math.cos(a) * I.rx * d, y = I.y + Math.sin(a) * I.ry * d;
        if (inRect(x, y, I.stable, 80) || inRect(x, y, I.pasture, 70) || Math.hypot(x - I.pen.x, y - I.pen.y) < I.pen.r + 70 || Math.hypot(x - I.pier.x, y - I.pier.y) < 220) continue;
        if (Math.hypot(x - I.x, y - I.y) < 260 || !free(x, y, I.bone ? 120 : 170)) continue;
        const k = r();
        if (I.bone) {
          if (k < 0.3) add({ x, y, r: 70 + r() * 70, kind: 'bigbone', s: seedOf(), cr: 0, soft: true });
          else if (k < 0.45) add({ x, y, r: 60 + r() * 40, kind: 'bigskull', s: seedOf(), cr: 36 });
          else if (k < 0.85) add({ x, y, r: 12 + r() * 10, kind: 'smallbone', s: seedOf(), cr: 0, soft: true });
          else add({ x, y, r: 26 + r() * 14, kind: 'deadtree', s: seedOf(), cr: 9 });
        } else add({ x, y, r: 30 + r() * 20, kind: d > 0.7 && k < 0.6 ? 'palm' : k < 0.5 ? 'oak' : 'birch', s: seedOf(), cr: 9 });
      }
    }

    // небесные острова: деревья, обвитые лианами, и лианы по краям
    for (const I of SKY_ISLANDS) {
      for (let i = 0; i < 90; i++) {
        const a = r() * Math.PI * 2, d = 0.25 + Math.sqrt(r()) * 0.6;
        const x = I.x + Math.cos(a) * I.rx * d, y = I.y + Math.sin(a) * I.ry * d;
        if (Math.hypot(x - SKY_PORTAL.x, y - SKY_PORTAL.y) < 220 || onBridge(x, y, -120) || !free(x, y, 190)) continue;
        add({ x, y, r: 32 + r() * 22, kind: r() < 0.5 ? 'vinetree' : r() < 0.5 ? 'birch' : 'oak', s: seedOf(), cr: 9 });
      }
      const n = Math.round((I.rx + I.ry) / 28);
      for (let k = 0; k < n; k++) {
        const p = blobPoint(I, k / n * Math.PI * 2 + r() * 0.1, -12);
        VINES.push({ x: p.x, y: p.y, len: 3 + r() * 14, s: r() });
      }
    }
    for (const b of SKY_BRIDGES) for (let t = 0.1; t < 0.95; t += 0.12) {
      VINES.push({ x: b[0] + (b[2] - b[0]) * t, y: b[1] + (b[3] - b[1]) * t + BRIDGE_W, len: 2 + r() * 6, s: r() });
    }

    const cols = ['#ffffff', '#ffe066', '#ff8fab', '#c77dff', '#ffd6a5', '#f94144'];
    for (const I of SKY_ISLANDS) for (let i = 0; i < 260; i++) {
      const a = r() * Math.PI * 2, d = Math.sqrt(r()) * 0.92 * shapeR(I, a);
      FLOWERS.push({ x: I.x + Math.cos(a) * I.rx * d, y: I.y + Math.sin(a) * I.ry * d, c: cols[Math.floor(r() * cols.length)], s: 1.5 + r() * 2, sky: true });
    }
    const NOFLOWER = { mountain: 1, cave: 1, desert: 1, tundra: 1, sea: 1, dragonrock: 1, i4: 1, grottocave: 1 };
    for (let i = 0; i < 14000; i++) {
      const x = r() * W, y = r() * H;
      if (busy(x, y) || houseBusy(x, y, 10) || NOFLOWER[regionAt(x, y)]) continue;
      FLOWERS.push({ x, y, c: cols[Math.floor(r() * cols.length)], s: 1.5 + r() * 2 });
    }
  })();

  // непроходимые прямоугольники (стены, заборы, повозки, скалы, дома)
  const SOLIDS = [];
  const CAVE_WALLS = [
    { x: MOUNTAIN.x, y: MOUNTAIN.y, w: MOUNTAIN.w, h: CAVE.y - MOUNTAIN.y },
    { x: MOUNTAIN.x, y: CAVE.y + CAVE.h, w: MOUNTAIN.w, h: MOUNTAIN.y + MOUNTAIN.h - CAVE.y - CAVE.h },
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
    for (const st of MARKET_STALLS) SOLIDS.push({ x: st.x, y: st.y, w: st.w, h: st.h });
    SOLIDS.push({ x: STATION.x + 30, y: STATION.y - 60, w: 160, h: 70 });            // домик станции
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
    if (t.soft) continue;
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
    if (L) blobPush(L, e, r, false);
    // море: на острове — остаёмся на острове, у берега большой земли — не заходим в воду
    if (e.x > SEA.x - r - 50 && e.y <= H) {
      const cx = coastX(e.y);
      if (e.x > cx - r) {
        let best = null, bd = 1e9;
        for (const I of ISLANDS) {
          const q = blobInfo(I, e.x, e.y), dd = q.d / q.R;
          if (dd < bd) { bd = dd; best = I; }
        }
        if (best && bd < 1.6) blobPush(best, e, r, true);
        else e.x = Math.min(e.x, cx - r);
      }
    }
    // небо: на островах и мостах можно ходить, вокруг — пропасть
    if (e.y > H - r) {
      if (!skyWalkable(e.x, e.y, r * 0.5)) {
        let best = null, bd = 1e9;
        for (const I of SKY_ISLANDS) {
          const q = { x: e.x, y: e.y };
          blobPush(I, q, r * 0.6, true);
          const dd = Math.hypot(q.x - e.x, q.y - e.y);
          if (dd < bd) { bd = dd; best = q; }
        }
        for (const b of SKY_BRIDGES) {
          const q = segPoint(e.x, e.y, b), dd = Math.hypot(q.x - e.x, q.y - e.y);
          const lim = BRIDGE_W - r * 0.5 - 1;
          const p = dd > lim ? { x: q.x + (e.x - q.x) / dd * lim, y: q.y + (e.y - q.y) / dd * lim } : { x: e.x, y: e.y };
          const pd = Math.hypot(p.x - e.x, p.y - e.y);
          if (pd < bd) { bd = pd; best = p; }
        }
        if (bd < 320) { e.x = best.x; e.y = best.y; }
        else e.y = H - r;
      }
      e.x = Math.max(r, Math.min(W - r, e.x));
      e.y = Math.min(TOTAL_H - r, e.y);
      return;
    }
    const dw = Math.hypot(e.x - WELL.x, e.y - WELL.y);
    if (dw < WELL.r + r && dw > 0) { e.x = WELL.x + (e.x - WELL.x) / dw * (WELL.r + r); e.y = WELL.y + (e.y - WELL.y) / dw * (WELL.r + r); }
    e.x = Math.max(r, Math.min(W - r, e.x));
    e.y = Math.max(r, Math.min(H - r, e.y));
  }
  // можно ли здесь стоять (для приземления пегаса и стройки)
  function blocked(x, y, r = 14) {
    if (y > H - r && !skyWalkable(x, y, r)) return true;
    if (inPond(x, y, r) || inSea(x, y, r)) return true;
    const box = { x: x - r, y: y - r, w: 2 * r, h: 2 * r };
    const hit = s => box.x < s.x + s.w && box.x + box.w > s.x && box.y < s.y + s.h && box.y + box.h > s.y;
    if (SOLIDS.some(hit) || BUILD_SOLIDS.some(hit)) return true;
    return treesNear(x, y).some(t => Math.hypot(t.x - x, t.y - y) < r + (t.cr || 9));
  }

  return {
    OX, OY, W, H, STABLE, STALL_W, STALL_H, AISLE_Y1, AISLE_Y2, stallRect, stallSpot,
    ARENA, GATE_A, LETTERS, letterTarget, CAV, JUMPF, JUMPF_GATE, COURSE, LAMPS, PADDOCK, PADDOCK_GATE, SELL, SHOP, FIELD, POND, START,
    LAKELAND, FARMLAND, VILLAGE, FOREST, MUSHROOM, MOUNTAIN, CAVE, CAVE_GATE, CAVE_WALLS, CAVE_INNER_WALLS, CHEST, LAKES, ROADS, OASIS, SQUARE,
    GROTTO, GROTTOS, FOXWOOD, DRAGONROCK, STEPPE, TOWN, RAIL, STATION, inGrotto, inTown, coastX,
    MARKET, MARKET_STALLS, stallFront, PORTAL, SKY, TOTAL_H, SKY_ISLANDS, SKY_BRIDGES, BRIDGE_W, SKY_PORTAL, VINES,
    skyIslandAt, skyWalkable, onBridge, inSkyZone, shapeR, blobPoint, blobPoly, inBlob, blobInfo, vnoise, warp,
    HOUSES, WELL, BOARD, REGION_NAMES, DESERT, DEEPFOREST, TUNDRA, SEA, ISLANDS, PIER, islandAt, inSea,
    TREES, FLOWERS, SHROOMS, CRYSTALS, SOLIDS, BUILD_SOLIDS, collide, blocked, inRect, inPond, lakeAt, regionAt, biomeAt, inForest, distToRoad, treesNear, rng,
  };
})();

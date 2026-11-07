'use strict';
/* Основная логика игры */
const Game = (() => {
  const SAVE_KEY = 'horseFarm.v1';
  const WILD_COUNT = 9;
  const GAITS = ['Шаг', 'Рысь', 'Галоп'];
  const LASSO_RANGE = 170;

  const FOOD = {
    hay: { name: 'Сено', icon: '🌾', price: 5, hunger: 25, energy: 5, mood: 2 },
    oats: { name: 'Овёс', icon: '🥣', price: 9, hunger: 35, energy: 25, mood: 3 },
    carrot: { name: 'Морковка', icon: '🥕', price: 3, hunger: 6, energy: 2, mood: 10, bait: true },
    apple: { name: 'Яблоко', icon: '🍎', price: 3, hunger: 6, energy: 2, mood: 10, bait: true },
    sugar: { name: 'Сахар', icon: '🍬', price: 2, hunger: 2, energy: 4, mood: 15 },
    milk: { name: 'Молоко', icon: '🍼', price: 4, hunger: 30, energy: 10, mood: 15, foalOnly: true },
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
    detector: { name: 'Металлоискатель', icon: '📡', price: 150, desc: 'Пищит рядом с кладом. Включай клавишей M' },
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
  const keys = new Set();
  let canvas, ctx, mmctx, dpr = 1, viewW = 0, viewH = 0;
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
      inv: Object.assign(Object.fromEntries(Object.keys(Items.ITEMS).map(k => [k, 0])), { hay: 6, carrot: 3, apple: 2, seed_carrot: 2 }),
      tack: {
        saddle: false, bridle: false, brush: false, goodLasso: false, detector: false, pad: null, helmet: null, boots: null,
        saddleStyles: { classic: true }, saddleStyle: 'classic', saddleColor: '#5b3a1e',
        bridleStyles: { classic: true }, bridleStyle: 'classic', bridleColor: '#2b1a10',
      },
      horses: [],
      player: { x: World.OX + 960, y: World.OY + 470, angle: 0, gait: 0, mountId: null, shirt: '#e05a8a' },
      stats: { caught: 0, foals: 0, sold: 0, gold: 0, silver: 0, bronze: 0, bunnies: 0, races: 0, wins: 0 },
      nextId: 1,
      seenHelp: false,
      clock: 8 * 60,   // минуты от полуночи
      builds: [], flags: {}, quests: {}, board: null, buildId: 0, bigTreasure: null,
      market: null, worldV: 2,
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
    s.tack.saddleStyles = Object.assign({ classic: true }, s.tack.saddleStyles);
    s.tack.bridleStyles = Object.assign({ classic: true }, s.tack.bridleStyles);
    s.stats = Object.assign(newState().stats, data.stats);
    s.player = Object.assign(newState().player, data.player);
    s.player.mountId = null;
    s.player.fly = false;
    s.player.detector = false;
    s.builds = data.builds || []; s.flags = data.flags || {}; s.quests = data.quests || {};
    for (const h of s.horses) if (h.state === 'ridden' || h.state === 'led') h.state = 'stall';
    // старые огненные и ледяные лошадки получают новый окрас
    for (const h of s.horses) if ((h.breed === 'firehorse' || h.breed === 'icehorse') && h.magic && !h.magic.elem) h.magic.elem = h.breed === 'firehorse' ? 'fire' : 'ice';
    s.market = data.market || null;
    // старые сохранения: мир расширился, город теперь в середине — сдвигаем всё, что стоит на карте
    if ((data.worldV || 1) < 2) {
      const mv = o => { if (o && typeof o.x === 'number') { o.x += World.OX; o.y += World.OY; } };
      mv(s.player); s.builds.forEach(mv); mv(s.bigTreasure);
      for (const h of s.horses) { mv(h); h.wander = null; }
      s.worldV = 2;
    }
    Horses.nextId = Math.max(s.nextId || 1, ...s.horses.map(h => h.id + 1), ...((s.market && s.market.stock) || []).map(h => h.id + 1), 1);
    return s;
  }

  function reset() {
    try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* ничего */ }
    S = newState();
    S.seenHelp = true;
    wild = []; led = null; ex = null;
    Horses.nextId = 1;
    Market.reset();
    spawnHerd();
    Farm.syncSolids();
    UI.closeModal();
    UI.toast('Новая игра! Поймай свою первую лошадь в поле →');
  }

  /* ---------------- помощники ---------------- */
  const mounted = () => (S.player.mountId != null ? S.horses.find(h => h.id === S.player.mountId) || null : null);
  const byId = id => S.horses.find(h => h.id === id);
  // денники: 0–19 главная конюшня, 20+ маленькие конюшни, 1000+ конюшни на островах (по 5)
  const ISLAND_STALL = 1000;
  function freeStall(where = 'main') {
    const used = new Set(S.horses.map(h => h.stall));
    if (where !== 'main') {
      const k = World.ISLANDS.findIndex(I => I.id === where);
      for (let i = 0; i < 5; i++) if (!used.has(ISLAND_STALL + k * 5 + i)) return ISLAND_STALL + k * 5 + i;
      return -1;
    }
    for (let i = 0; i < Farm.maxStalls(); i++) if (!used.has(i)) return i;
    return -1;
  }
  const islandOfStall = i => (i >= ISLAND_STALL ? World.ISLANDS[Math.floor((i - ISLAND_STALL) / 5)] : null);
  function stallLabel(i) {
    const I = islandOfStall(i);
    return I ? `${I.name}, денник №${(i - ISLAND_STALL) % 5 + 1}` : `№${i + 1}`;
  }
  const totalStalls = () => Farm.maxStalls() + World.ISLANDS.length * 5;
  function stallGroups() {
    const main = [];
    for (let i = 0; i < Farm.maxStalls(); i++) main.push(i);
    return [{ title: 'Ферма', list: main }].concat(World.ISLANDS.map((I, k) => ({ title: `🏝️ ${I.name}`, list: [0, 1, 2, 3, 4].map(j => ISLAND_STALL + k * 5 + j) })));
  }
  // остров, у конюшни или пастбища которого стоит игрок
  function islandStableHere(p) {
    return World.ISLANDS.find(I => World.inRect(p.x, p.y, I.stable, 70) || World.inRect(p.x, p.y, I.pasture, 60)) || null;
  }
  const paddockFor = h => (islandOfStall(h.stall) ? islandOfStall(h.stall).pasture : World.PADDOCK);
  const horseInStall = i => S.horses.find(h => h.stall === i) || null;
  const atFarm = () => {
    const p = S.player;
    return World.inRect(p.x, p.y, World.STABLE, 40) || World.inRect(p.x, p.y, World.PADDOCK, 50) || Farm.nearStable(p) || !!islandStableHere(p);
  };
  function stallSpot(i) {
    const I = islandOfStall(i);
    if (I) { const k = (i - ISLAND_STALL) % 5; return { x: I.stable.x + 34 + k * 68, y: I.stable.y + 72, angle: Math.PI / 2 }; }
    return i < 20 ? World.stallSpot(i) : Farm.extraSpot(i) || World.stallSpot(0);
  }
  function stat(k, n = 1) { S.stats[k] = (S.stats[k] || 0) + n; }
  function float(text, x, y, color = '#333') { floats.push({ text, x, y, t: 0, color }); }

  function gaitSpeed(h, gait) {
    const f = 0.75 + Horses.skill(h, 'speed') / 200;
    let v = [75, 155, 250][gait] * (gait === 2 ? f : 0.9 + f * 0.1);
    if (h.hunger < 15) v *= 0.75;
    if (h.age < 3) v *= 0.8;
    return v;
  }

  /* ---------------- табуны ---------------- */
  // три табуна: обычные лошади в поле, волшебные в Грибном королевстве, скелеты в пещере
  const HERDS = {
    field: { area: World.FIELD, count: WILD_COUNT, sleeps: true, name: 'в поле' },
    magic: { area: { x: World.MUSHROOM.x + 150, y: World.MUSHROOM.y + 150, w: World.MUSHROOM.w - 300, h: World.MUSHROOM.h - 300 }, count: 9, sleeps: true, name: 'в Грибном королевстве' },
    // у портала в глубине пещеры — ещё скелеты
    portal: { area: { x: World.PORTAL.x - 450, y: World.PORTAL.y - 380, w: 800, h: 700 }, count: 3, sleeps: false, name: 'у портала' },
    // в лесу у Лесного озера — лиственные и сырые лошадки
    forest: { area: { x: World.OX + 1900, y: World.OY + 4100, w: 2300, h: 1700 }, count: 6, sleeps: true, name: 'в лесу' },
    cave: { area: { x: World.CAVE.x + 100, y: World.CAVE.y + 100, w: World.CAVE.w - 200, h: World.CAVE.h - 200 }, count: 4, sleeps: false, name: 'в пещере' },
    desert: { area: { x: World.DESERT.x + 200, y: World.DESERT.y + 200, w: World.DESERT.w - 400, h: World.DESERT.h - 400 }, count: 6, sleeps: true, name: 'в пустыне' },
    tundra: { area: { x: World.TUNDRA.x + 200, y: World.TUNDRA.y + 200, w: World.TUNDRA.w - 400, h: World.TUNDRA.h - 400 }, count: 6, sleeps: true, name: 'в тундре' },
    // новые биомы вокруг города
    steppe: { area: { x: World.STEPPE.x + 300, y: World.STEPPE.y + 300, w: World.STEPPE.w - 600, h: World.STEPPE.h - 600 }, count: 7, sleeps: true, name: 'в степи' },
    foxwood: { area: { x: World.FOXWOOD.x + 300, y: World.FOXWOOD.y + 300, w: World.FOXWOOD.w - 600, h: World.FOXWOOD.h - 600 }, count: 6, sleeps: true, name: 'в Лисьем лесу' },
    deepforest: { area: { x: World.DEEPFOREST.x + 250, y: World.DEEPFOREST.y + 250, w: World.DEEPFOREST.w - 500, h: World.DEEPFOREST.h - 500 }, count: 5, sleeps: true, name: 'в Дремучем лесу' },
    dragonrock: { area: { x: World.DRAGONROCK.x + 300, y: World.DRAGONROCK.y + 300, w: World.DRAGONROCK.w - 600, h: World.DRAGONROCK.h - 600 }, count: 5, sleeps: false, name: 'на Драконьих скалах' },
  };
  // в каждой маленькой пещерке — по две чёрные лошади со светящимися узорами
  for (const g of World.GROTTOS) HERDS[g.id] = { area: { x: g.x - g.r * 0.55, y: g.y - g.r * 0.55, w: g.r * 1.1, h: g.r * 1.1 }, count: 2, sleeps: false, name: 'в пещерке', grotto: true };
  // особые табуны: лошади из поезда и праздничные лошади (их выпускают train.js и holidays.js)
  HERDS.train = { area: { x: World.STATION.x - 900, y: World.RAIL.y - 1100, w: 2300, h: 1000 }, count: 0, sleeps: false, name: 'у станции', special: true };
  HERDS.holiday = { area: { x: World.FIELD.x + 200, y: World.FIELD.y + 200, w: World.FIELD.w - 400, h: World.FIELD.h - 400 }, count: 0, sleeps: false, name: 'на празднике', special: true };
  // на каждом острове — 5 диких лошадей, раз в 5 минут они меняются
  for (const I of World.ISLANDS) HERDS[I.id] = { area: I.area, count: 5, sleeps: true, name: `на острове «${I.name}»`, island: I };
  // небесные острова: дикие крылатые и облачные лошадки
  for (const I of World.SKY_ISLANDS.slice(0, 3)) HERDS[I.id] = { area: I.area, count: I.id === 'sky1' ? 6 : 4, sleeps: false, name: `на острове «${I.name}»`, sky: true };
  const ISLAND_REFRESH = 300;
  let islandT = ISLAND_REFRESH;
  const HOME_BREEDS = {
    desert: ['akhal', 'arab', 'sandhorse', 'zebra', 'zebra', 'zebra', 'zebra'],
    steppe: ['przewalski', 'przewalski', 'przewalski', 'przewalski', 'fedorov', 'haflinger', 'orlov'],
    foxwood: ['foxhorse', 'foxhorse', 'foxhorse', 'foxhorse', 'trakehner', 'fedorov'],
    deepforest: ['foxhorse', 'foxhorse', 'foxhorse', 'friesian', 'damphorse'],
    dragonrock: ['scalehorse', 'scalehorse', 'scalehorse', 'scalehorse', 'dragonhorse'],
    train: ['arab', 'andalusian', 'appaloosa', 'friesian', 'akhal', 'fedorov', 'zebra', 'unicorn', 'pegasus', 'rainbowhorse', 'crystalhorse', 'foxhorse'],
    holiday: ['holidayhorse'],
    tundra: ['yakut', 'yakut', 'yakut', 'yakut', 'fjord', 'icehorse'],
    portal: ['skeleton', 'skeleton', 'skeleton', 'stonehorse'],
    forest: ['leafhorse', 'leafhorse', 'damphorse', 'damphorse', 'trakehner', 'orlov'],
    sky1: ['cloudhorse', 'cloudhorse', 'pegasus', 'rainbowhorse', 'sunhorse', 'ravenhorse', 'arab'],
    sky2: ['rainbowhorse', 'crystalhorse', 'butterflyhorse', 'cloudhorse', 'waterhorse'],
    sky3: ['sunhorse', 'dragonhorse', 'cloudhorse', 'crystalhorse', 'firehorse'],
  };
  for (const k in HERDS) Object.assign(HERDS[k], { id: k, x: 0, y: 0, tx: 0, ty: 0, t: 0, panic: 0, respawnT: 0 });

  function randomFieldPoint(margin = 150, area = World.FIELD) {
    const F = area;
    margin = Math.min(margin, F.w * 0.3, F.h * 0.3);
    for (let i = 0; i < 60; i++) {
      const x = rand(F.x + margin, F.x + F.w - margin), y = rand(F.y + margin, F.y + F.h - margin);
      if (!World.inPond(x, y, 150) && !World.blocked(x, y, 40)) return { x, y };
    }
    return { x: F.x + F.w / 2, y: F.y + F.h / 2 };
  }

  function pickBreed(home = 'field') {
    if (HERDS[home] && HERDS[home].grotto) return 'glowhorse';
    // розовый дракон: только в волшебном биоме и очень редко (в радужный дождь — чаще)
    if (home === 'magic' && !wild.some(w => w.breed === 'pinkdragon') && Math.random() < (Events.magicRain && Events.magicRain() ? 0.12 : 0.025)) return 'pinkdragon';
    if (HOME_BREEDS[home]) return HOME_BREEDS[home][Math.floor(Math.random() * HOME_BREEDS[home].length)];
    if (HERDS[home] && HERDS[home].island) { const b = HERDS[home].island.breeds; return b[Math.floor(Math.random() * b.length)]; }
    const entries = Object.entries(Genetics.BREEDS).filter(([, b]) => (home === 'field' ? b.weight > 0 : b.home === home));
    let total = entries.reduce((s, [, b]) => s + (home === 'field' ? b.weight : b.hw), 0), r = Math.random() * total;
    for (const [k, b] of entries) { r -= home === 'field' ? b.weight : b.hw; if (r <= 0) return k; }
    return entries[0][0];
  }

  function makeWild(x, y, home = 'field') {
    const isFoal = Math.random() < (home === 'cave' ? 0.05 : 0.12);
    const taken = S.horses.map(h => h.name).concat(wild.map(w => w.name));
    const h = Horses.create({ breed: pickBreed(home), age: isFoal ? rand(0.3, 1.5) : rand(3, 13), taken });
    // в Грибном королевстве иногда встречаются обычные лошади с одной волшебной чертой
    if (home === 'magic' && Math.random() < 0.15) h.magic = Object.assign({}, h.magic, Math.random() < 0.5 ? { horn: true } : { wings: true });
    // на небесных островах почти у всех есть крылья или облачка
    if (HERDS[home] && HERDS[home].sky && !Horses.canFly(h)) h.magic = Object.assign({}, h.magic, Math.random() < 0.7 ? { wings: Math.random() < 0.7 ? 'pegasus' : 'butterfly' } : { cloud: true });
    h.x = x; h.y = y; h.angle = rand(0, 6.28);
    h.slot = { x: rand(-150, 150), y: rand(-110, 110) };
    h.flee = 0; h.grazeT = rand(0, 5); h.home = home;
    return h;
  }

  function spawnHerd() {
    wild = [];
    for (const H of Object.values(HERDS)) {
      const c = randomFieldPoint(400, H.area);
      H.x = H.tx = c.x; H.y = H.ty = c.y;
      for (let i = 0; i < H.count; i++) {
        const q = { x: c.x + rand(-150, 150), y: c.y + rand(-120, 120) };
        World.collide(q, 20);
        wild.push(makeWild(q.x, q.y, H.id));
      }
    }
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

  /* ---------------- действия лошадей ---------------- */
  // брыкнуть, на дыбы, поесть траву, поваляться, поднять ногу, прижать уши, заржать, посмотреть вверх/вниз,
  // поклон, почесаться коленкой, пойти задом, танцевать (позы рисует voxel.js по h.act)
  const ACTS = {
    rear: { name: 'Встать на дыбы', icon: '🐎', d: 2.4 },
    kick: { name: 'Брыкнуть задними ногами', icon: '🦵', d: 1.3 },
    graze: { name: 'Поесть травку', icon: '🌱', d: 5 },
    roll: { name: 'Поваляться', icon: '🌀', d: 6 },
    liftLeg: { name: 'Поднять ногу', icon: '🦶', d: 2.5 },
    ears: { name: 'Прижать уши', icon: '👂', d: 2.5 },
    neigh: { name: 'Заржать «Иго-го!»', icon: '📣', d: 1.8 },
    lookUp: { name: 'Посмотреть вверх', icon: '⬆️', d: 2.5 },
    lookDown: { name: 'Посмотреть вниз', icon: '⬇️', d: 2.5 },
    bow: { name: 'Нагнуть голову', icon: '🙇', d: 2.6 },
    scratch: { name: 'Почесать голову коленкой', icon: '🤭', d: 3 },
    back: { name: 'Пойти задом', icon: '↩️', d: 2.6 },
    dance: { name: 'Потанцевать на месте', icon: '💃', d: 4.5 },
  };
  function startAct(h, k, quiet) {
    if (!h) return;
    const d = ACTS[k] ? ACTS[k].d : k === 'play' ? 3 : 2;
    h.act = { k, t: 0, d: d * (0.85 + Math.random() * 0.3), leg: Math.floor(Math.random() * 4) };
    if (k === 'neigh' && !quiet) { Sound.neigh(); float('Иго-го! 🐴', h.x, h.y - 30, '#7a4a22'); }
  }
  function tickAct(h, dt) {
    if (!h.act) return;
    h.act.t += dt;
    if (h.act.k === 'back' && h.state !== 'stall' && h.state !== 'ridden') {
      h.x -= Math.cos(h.angle) * 38 * dt; h.y -= Math.sin(h.angle) * 38 * dt;
      h.phase = (h.phase || 0) + dt * 5;
      World.collide(h, 18);
    }
    if (h.act.t >= h.act.d) h.act = null;
  }
  // сама по себе лошадь иногда что-нибудь делает
  const IDLE = [['graze', 6], ['lookUp', 1], ['ears', 1], ['liftLeg', 1], ['neigh', 0.5], ['roll', 0.35], ['kick', 0.45], ['scratch', 0.6], ['lookDown', 0.7], ['dance', 0.12], ['bow', 0.3]];
  const STALL_IDLE = [['graze', 3], ['lookUp', 1], ['ears', 1], ['liftLeg', 1], ['neigh', 0.3], ['scratch', 0.6], ['lookDown', 1]];
  function idleAct(h, dt, rate = 0.1, list = IDLE) {
    if (h.act || Math.random() > dt * rate) return;
    const tot = list.reduce((a, b) => a + b[1], 0);
    let r = Math.random() * tot;
    for (const [k, w] of list) { r -= w; if (r <= 0) { startAct(h, k, dist(h, S.player) > 450); return; } }
  }

  function updateHerd(dt) {
    const p = S.player, m = mounted();
    for (const herd of Object.values(HERDS)) {
      const F = herd.area;
      herd.t -= dt;
      herd.panic = Math.max(0, herd.panic - dt);
      if (herd.t <= 0) {
        const t = randomFieldPoint(300, F);
        herd.tx = t.x; herd.ty = t.y; herd.t = rand(14, 26);
      }
      const sleepy = herd.sleeps && isNight() && herd.panic <= 0;
      const hs = herd.panic > 0 ? 120 : sleepy ? 0 : 20;
      const hd = Math.hypot(herd.tx - herd.x, herd.ty - herd.y);
      if (hd > 5) { herd.x += ((herd.tx - herd.x) / hd) * hs * dt; herd.y += ((herd.ty - herd.y) / hd) * hs * dt; }

      const members = wild.filter(w => (w.home || 'field') === herd.id);
      for (const w of members) {
        const d = dist(w, p);
        let fleeR = 70 + w.temper * 170;
        if (sleepy) fleeR *= 0.6;
        if (m && p.gait === 2) fleeR *= 1.2;
        if (m && p.gait === 0) fleeR *= 0.8;
        if (p.fly) fleeR *= 0.7;
        if (d < fleeR && w.flee <= 0) {
          w.flee = rand(1.4, 2.2);
          w.act = null;
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
            if (!w.fly) idleAct(w, dt, 0.11);
          }
        }
        // остаться на своей территории
        if (w.x < F.x + 40) tx = Math.max(tx, F.x + 120);
        if (w.x > F.x + F.w - 40) tx = Math.min(tx, F.x + F.w - 120);
        if (w.y < F.y + 40) ty = Math.max(ty, F.y + 120);
        if (w.y > F.y + F.h - 40) ty = Math.min(ty, F.y + F.h - 120);
        // пегасы взлетают, когда убегают; на небесных островах крылатые летают и просто так
        if (herd.sky && w.magic && w.magic.wings) {
          if (w.airT == null) { w.airT = rand(2, 12); w.airLen = rand(4, 9); }
          w.airT -= dt;
          if (w.airT < -w.airLen) { w.airT = rand(6, 16); w.airLen = rand(4, 9); }
        }
        const wantFly = w.magic && w.magic.wings && (w.flee > 0 || (herd.sky && w.airT < 0));
        w.fly = wantFly ? Math.min(1, (w.fly || 0) + dt * 2) : Math.max(0, (w.fly || 0) - dt);
        if (w.fly > 0 && herd.sky && w.flee <= 0 && sp < 60) {
          // кружит над островом
          sp = 90; tx = w.x + Math.cos(time * 0.4 + w.seed) * 120; ty = w.y + Math.sin(time * 0.3 + w.seed) * 120;
        }
        if (w.act && w.flee <= 0) { tx = w.x; ty = w.y; sp = 0; }
        tickAct(w, dt);
        moveToward(w, tx, ty, sp, dt, w.flee > 0 ? 4 : 2);
        for (const o of members) {
          if (o === w) continue;
          const dx = w.x - o.x, dy = w.y - o.y, dd = Math.hypot(dx, dy);
          if (dd < 48 && dd > 0.1) { w.x += (dx / dd) * (48 - dd) * 0.5; w.y += (dy / dd) * (48 - dd) * 0.5; }
        }
        if (!w.fly) World.collide(w, 18);
        w.x = clamp(w.x, F.x - 60, F.x + F.w + 60);
        w.y = clamp(w.y, F.y - 60, F.y + F.h + 60);
      }

      // новые лошади приходят взамен пойманных (на островах — только при смене табуна)
      if (members.length < herd.count && !herd.island && !herd.sky && !herd.special) {
        herd.respawnT -= dt;
        if (herd.respawnT <= 0) {
          herd.respawnT = rand(8, 16);
          const q = randomFieldPoint(200, F);
          wild.push(makeWild(q.x, q.y, herd.id));
          if (herd.id === 'field') UI.toast('🐎 В поле прибежала новая лошадь!');
          if (wild[wild.length - 1].breed === 'pinkdragon') UI.toast('💗🐉 В Грибном королевстве появился РОЗОВЫЙ ДРАКОН! Больше таких нигде нет!', 'good');
        }
      }
    }
  }

  function refreshIslands(dt) {
    islandT -= dt;
    if (islandT > 0) return;
    islandT = ISLAND_REFRESH;
    for (const I of World.ISLANDS) {
      wild = wild.filter(w => w.home !== I.id);
      const H = HERDS[I.id];
      const c = randomFieldPoint(200, I.area);
      H.x = H.tx = c.x; H.y = H.ty = c.y;
      for (let i = 0; i < H.count; i++) {
        const q = randomFieldPoint(120, I.area);
        wild.push(makeWild(q.x, q.y, I.id));
      }
    }
    for (const I of World.SKY_ISLANDS.slice(0, 3)) {
      const H = HERDS[I.id], n = wild.filter(w => w.home === I.id).length;
      for (let i = n; i < H.count; i++) { const q = randomFieldPoint(120, I.area); wild.push(makeWild(q.x, q.y, I.id)); }
    }
    UI.toast('🏝️ На островах появились новые дикие лошади!', 'good');
  }
  const islandTimeLeft = () => islandT;

  // круглый манеж на острове: каталась кругами — выездка и скорость немного растут
  let penT = 0;
  function updatePen(dt) {
    const p = S.player, m = mounted();
    if (!m || p.spd < 40) return;
    const I = World.ISLANDS.find(q => Math.hypot(p.x - q.pen.x, p.y - q.pen.y) < q.pen.r);
    if (!I) return;
    penT += dt;
    if (penT >= 8) {
      penT = 0;
      Horses.addTrain(m, 'dressage', 0.6);
      Horses.addTrain(m, p.gait === 2 ? 'speed' : 'stamina', 0.4);
      float('🎠 +тренировка', p.x, p.y - 30, '#1b8a3a');
      stat('penTime', 8);
    }
  }

  /* ---------------- портал: пещера ↔ небесные острова ---------------- */
  let portalCd = 0;
  function updatePortal(dt) {
    portalCd = Math.max(0, portalCd - dt);
    const p = S.player;
    if (p.fly || ex || Events.busy()) return;
    const P1 = World.PORTAL, P2 = World.SKY_PORTAL;
    const inP = q => Math.hypot(p.x - q.x, p.y - q.y) < q.r;
    if (portalCd > 0) return;
    let to = null;
    if (inP(P1)) to = { x: P2.x, y: P2.y + 130, msg: '🌀 Вжух! Портал перенёс тебя на небесные острова! Обратно — через портал на Облачном острове' };
    else if (inP(P2)) to = { x: P1.x - 150, y: P1.y + 40, msg: '🌀 Портал вернул тебя в пещеру' };
    if (!to) return;
    portalCd = 3;
    p.x = to.x; p.y = to.y; p.vx = p.vy = 0; p.target = null;
    const m = mounted();
    if (m) { m.x = p.x; m.y = p.y; }
    if (led) { led.x = p.x - 60; led.y = p.y + 30; led.vx = led.vy = 0; }
    if (to.y > World.H) stat('skyVisits');
    UI.toast(to.msg, 'good');
    Sound.fanfare();
  }

  /* ---------------- грязь на ногах в дождь ---------------- */
  // в дождь пачкаются все лошади, кроме тех, что стоят в конюшне; в пещере, пустыне, тундре и на небе дождя нет
  const DRY = { cave: 1, desert: 1, tundra: 1, sky: 1 };
  const dryRegion = (x, y) => DRY[World.regionAt(x, y)] || y > World.H;
  function updateMud(dt) {
    const raining = Events.raining();
    const p = S.player, m = mounted();
    const soil = (h, k = 1) => {
      if (raining && !dryRegion(h.x, h.y) && !World.inRect(h.x, h.y, World.STABLE)) h.mud = Math.min(100, (h.mud || 0) + dt * 2.2 * k);
    };
    // мокрые лошади: под дождём шерсть намокает, потом высыхает
    const wetten = (h, k = 1) => {
      const under = raining && !dryRegion(h.x, h.y) && h.state !== 'stall' && !World.inRect(h.x, h.y, World.STABLE);
      h.wet = under ? Math.min(100, (h.wet || 0) + dt * 5 * k) : Math.max(0, (h.wet || 0) - dt * (h.state === 'stall' ? 2.2 : 1.1));
    };
    for (const h of S.horses) wetten(h);
    if (led) wetten(led);
    for (const w of wild) wetten(w, 1);
    for (const h of S.horses) {
      if (h.state === 'stall') { h.mud = Math.max(0, (h.mud || 0) - dt * 0.05); continue; }
      soil(h, h.state === 'ridden' ? 1 + p.gait * 0.5 : 1);
      if (h.mud > 30) h.clean = Math.max(0, h.clean - dt * 0.05);
    }
    if (led) soil(led);
    if (m && p.fly) m.mud = Math.max(0, (m.mud || 0) - dt * 0.5);
    for (const w of wild) {
      if (raining) soil(w);
      else w.mud = Math.max(0, (w.mud || 0) - dt * 0.4);
    }
  }

  /* ---------------- свои лошади ---------------- */
  function updateOwned(dt) {
    for (const h of S.horses) {
      const P = paddockFor(h);
      h.age += dt / 120; // 2 минуты = 1 год
      const inPaddock = h.state === 'paddock';
      h.hunger = clamp(h.hunger - dt * (inPaddock ? 0.03 : 0.07), 0, 100);
      h.clean = clamp(h.clean - dt * (inPaddock ? 0.06 : 0.015), 0, 100);
      if (h.state !== 'ridden') h.energy = clamp(h.energy + dt * (inPaddock ? 1.2 : 0.8), 0, 100);
      let moodD = inPaddock ? 0.4 : -0.03;
      if (h.hunger < 25) moodD -= 0.15;
      if (h.clean < 25) moodD -= 0.05;
      h.mood = clamp(h.mood + dt * moodD, 0, 100);

      if (h.state === 'market') {
        const sp = Market.spotOf(h);
        h.x = sp.x; h.y = sp.y; h.angle = sp.angle; h.spd = 0;
        h.headTurn = Math.sin(time * 0.6 + h.seed) * 0.4;
      } else if (h.state === 'stall') {
        const sp = stallSpot(h.stall);
        h.x = sp.x; h.y = sp.y; h.angle = sp.angle; h.spd = 0;
        h.headTurn = Math.sin(time * 0.5 + h.seed) * 0.35;
        idleAct(h, dt, 0.04, STALL_IDLE);
      } else if (h.state === 'walk') {
        // жеребёнок гуляет с тобой — идёт следом
        const p = S.player, back = { x: p.x - Math.cos(p.angle) * 60, y: p.y - Math.sin(p.angle) * 60 };
        const d = dist(h, back);
        if (!h.act || h.act.k === 'back') moveToward(h, back.x, back.y, d > 20 ? Math.min(d * 3, 260) : 0, dt, 5);
        World.collide(h, 14);
        if (d > 900) { h.x = back.x; h.y = back.y; }
        h.headTurn = h.spd < 5 ? Math.sin(time * 0.9 + h.seed) * 0.5 : 0;
        h.mood = clamp(h.mood + dt * 0.5, 0, 100);
        if (h.spd < 5) idleAct(h, dt, 0.08);
        stat('foalWalk', dt);
      } else if (inPaddock) {
        if (!h.wander || dist(h, h.wander) < 10 || Math.random() < dt * 0.05) {
          h.wander = Math.random() < 0.5 ? { x: h.x, y: h.y }
            : { x: rand(P.x + 50, P.x + P.w - 50), y: rand(P.y + 50, P.y + P.h - 50) };
        }
        if (h.act) h.wander = { x: h.x, y: h.y };
        moveToward(h, h.wander.x, h.wander.y, dist(h, h.wander) > 10 ? 40 : 0, dt);
        if (h.spd < 5) idleAct(h, dt, 0.1);
        h.x = clamp(h.x, P.x + 30, P.x + P.w - 30);
        h.y = clamp(h.y, P.y + 30, P.y + P.h - 30);
        h.headTurn = h.spd < 5 ? Math.sin(time * 0.7 + h.seed) * 0.4 : 0;
      }

      tickAct(h, dt);
      // жеребёнок готов родиться — ждём, когда нажмут кнопку «Родить»
      if (h.preg && !h.preg.ready) {
        h.preg.t -= dt;
        if (h.preg.t <= 0) {
          h.preg.t = 0; h.preg.ready = true;
          UI.toast(`🍼 Жеребёнок у кобылы ${h.name} готов родиться! Нажми кнопку «Родить жеребёнка»`, 'good');
          Sound.fanfare();
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
    if (p.fly && !Horses.canFly(m)) p.fly = false;
    // трюк верхом: лошадь стоит на месте (или пятится задом)
    let backing = false;
    if (m && m.act) {
      m.act.t += dt;
      if (m.act.k === 'back') { dx = -Math.cos(p.angle) * 0.35; dy = -Math.sin(p.angle) * 0.35; backing = true; p.target = null; }
      else { dx = dy = 0; }
      if (m.act.t >= m.act.d) m.act = null;
    }
    const max = m ? (backing ? 110 : gaitSpeed(m, p.gait)) * (p.fly ? 1.3 : 1) : 140;
    const k = Math.min(1, dt * (m ? 3.5 : 12));
    p.vx = (p.vx || 0) + (dx * max - (p.vx || 0)) * k;
    p.vy = (p.vy || 0) + (dy * max - (p.vy || 0)) * k;
    const ox = p.x, oy = p.y;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    if (p.fly) {
      p.x = clamp(p.x, 20, World.W - 20); p.y = clamp(p.y, 20, World.TOTAL_H - 20);
      stat('flyTime', dt);
    } else World.collide(p, m ? 20 : 10);
    p.spd = dt > 0 ? Math.hypot(p.x - ox, p.y - oy) / dt : 0;
    if (p.spd > 8 && !backing) p.angle = lerpAngle(p.angle, Math.atan2(p.y - oy, p.x - ox), Math.min(1, dt * (m ? 6 : 14)));
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
      const isl = islandStableHere(p);
      if (!p.fly && (World.inRect(p.x, p.y, World.STABLE, 10) || Farm.nearStable(p) || (isl && World.inRect(p.x, p.y, isl.stable, 20)))) {
        const st = freeStall(isl ? isl.id : 'main');
        if (st >= 0) {
          led.state = 'stall'; led.stall = st; led.flee = 0;
          S.horses.push(led);
          UI.toast(`🏠 ${led.name} теперь живёт: ${stallLabel(st)}!`, 'good');
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
      S.stats.caught++;
      if (Horses.isMagic(w)) stat('magicCaught');
      if (w.magic && w.magic.wings) stat('wing_' + Horses.wingType(w.magic.wings));
      if (w.magic && ['bee', 'dragonfly'].includes(Horses.wingType(w.magic.wings))) stat('wingSmall');
      if (w.home === 'desert' || w.home === 'tundra') stat('caught_' + w.home);
      if (w.breed === 'pinkdragon') stat('pinkDragon');
      if (w.home === 'train') stat('trainCaught');
      if (w.magic && w.magic.holiday) stat('holidayCaught');
      if (HERDS[w.home] && HERDS[w.home].island) stat('caught_island');
      if (w.magic && w.magic.skeleton) stat('skeletonCaught');
      const ph = Horses.pheno(w);
      UI.toast(`🎉 Поймала! ${w.name}: ${Genetics.BREEDS[w.breed].name.toLowerCase()}, ${ph.name}. Веди в конюшню!`, 'good');
      Sound.fanfare();
    } else {
      w.flee = 2.5;
      HERDS[w.home || 'field'].panic = 3;
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
  function inJumpField() {
    const p = S.player, J = World.JUMPF;
    return World.inRect(p.x, p.y, { x: J.x + 4, y: J.y + 4, w: J.w - 8, h: J.h - 8 });
  }
  const inExerciseArea = () => (ex && ex.type === 'jump' ? inJumpField() : inArena());

  /* ---------- конкур ---------- */
  const JUMP_HEIGHTS = [60, 80, 100, 120];
  const JUMP_NORM = 75; // норма времени, секунд
  const comfortHeight = h => Math.round((50 + Horses.skill(h, 'jump') * 0.7) / 5) * 5;

  function jumpPress() {
    if (!ex || ex.type !== 'jump' || ex.air > 0 || ex.cd > 0) return;
    const p = S.player;
    if (p.spd < 30) return;
    const o = World.COURSE[ex.i];
    const dx = Math.cos(o.a), dy = Math.sin(o.a);
    ex.takeoff = -((p.x - o.x) * dx + (p.y - o.y) * dy); // сколько осталось до препятствия
    ex.air = 0.6;
    ex.cd = 0.8;
    Sound.whoosh();
  }

  function updateJump(dt) {
    const p = S.player, m = mounted();
    ex.t += dt;
    ex.air = Math.max(0, ex.air - dt);
    ex.cd = Math.max(0, ex.cd - dt);
    const o = World.COURSE[ex.i];
    const dx = Math.cos(o.a), dy = Math.sin(o.a);
    const along = (p.x - o.x) * dx + (p.y - o.y) * dy;
    const lat = Math.abs(-(p.x - o.x) * dy + (p.y - o.y) * dx);
    const crossed = ex.prevAlong < 0 && along >= 0 && lat < o.half + 12;
    ex.prevAlong = along;
    if (!crossed) return;
    let st;
    if (p.gait === 0 || p.spd < 40) {
      // отказ: лошадь останавливается перед препятствием
      ex.refusals++;
      ex.faults += 4;
      p.x -= dx * 90; p.y -= dy * 90; p.vx = p.vy = 0;
      ex.prevAlong = -90;
      float('Отказ! +4', o.x, o.y - 50, '#c92a2a');
      Sound.fail();
      if (ex.refusals >= 3) return finishJump(true);
      return;
    }
    if (ex.air > 0) {
      let chance = 0.96 - Math.max(0, ex.height - comfortHeight(m)) * 0.025;
      if (p.gait === 1 && ex.height > 60) chance -= 0.3;
      const tk = ex.takeoff;
      if (tk < 15 || tk > 110) chance -= 0.25;
      if (m.mood < 30) chance -= 0.1;
      if (S.tack.boots) chance += 0.03;
      chance = clamp(chance, 0.05, 0.98);
      st = Math.random() < chance ? 'ok' : 'hit';
    } else {
      st = 'hit'; // не прыгнула — снесла жердь
    }
    ex.jumps[ex.i] = st;
    if (st === 'ok') { float('Чисто!', o.x, o.y - 50, '#1b8a3a'); Sound.tick(); }
    else { ex.faults += 4; float(ex.air > 0 ? 'Повал! +4' : 'Не прыгнула! +4', o.x, o.y - 50, '#c92a2a'); Sound.thud(); }
    ex.i++;
    ex.prevAlong = -1e9;
    if (ex.i >= World.COURSE.length) finishJump(false);
  }

  function finishJump(eliminated) {
    const m = mounted();
    const over = Math.max(0, Math.ceil((ex.t - JUMP_NORM) / 4));
    const faults = ex.faults + over;
    const clean = ex.jumps.filter(j => j === 'ok').length;
    const base = { 60: 30, 80: 50, 100: 80, 120: 120 }[ex.height];
    let money = 0, medal = null;
    if (!eliminated) {
      money = Math.round(base * (faults === 0 ? 1 : faults <= 4 ? 0.6 : faults <= 8 ? 0.35 : 0.15));
      medal = faults === 0 ? 'gold' : faults <= 4 ? 'silver' : faults <= 8 ? 'bronze' : null;
      if (medal) S.stats[medal]++;
    }
    S.money += money;
    Horses.addTrain(m, 'jump', clean * 0.5 * (ex.height / 80));
    m.energy = clamp(m.energy - 15, 0, 100);
    if (!eliminated) { stat('jumpRounds'); if (faults === 0 && ex.height >= 80) stat('jump80'); }
    const res = { height: ex.height, t: ex.t, norm: JUMP_NORM, over, faults, clean, total: World.COURSE.length, eliminated, money, medal, skill: Horses.skill(m, 'jump') };
    ex = null;
    UI.jumpResult(res);
    if (medal) Sound.fanfare(); else Sound.tick();
  }

  /* ---------- день и ночь ---------- */
  // 1 секунда игры = 3 игровые минуты: сутки — 8 минут
  function daylight() {
    const h = S.clock / 60;
    if (h >= 7 && h < 19) return 1;
    if (h >= 5 && h < 7) return (h - 5) / 2;
    if (h >= 19 && h < 21) return 1 - (h - 19) / 2;
    return 0;
  }
  function clockText() {
    const h = Math.floor(S.clock / 60), mi = Math.floor(S.clock % 60);
    const icon = daylight() >= 1 ? '☀️' : daylight() > 0 ? (S.clock < 720 ? '🌅' : '🌇') : '🌙';
    return `${icon} ${String(h).padStart(2, '0')}:${String(mi).padStart(2, '0')}`;
  }
  const isNight = () => daylight() < 0.35;

  function startExercise(kind) {
    const m = mounted();
    if (!m) return;
    UI.closeModal();
    if (Events.busy()) return UI.toast('Сначала закончи скачки');
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

  function startJumping(height) {
    const m = mounted();
    if (!m) return;
    UI.closeModal();
    if (Events.busy()) return UI.toast('Сначала закончи скачки');
    if (m.energy < 20) { UI.toast(`${m.name} ${Horses.v(m, 'устала', 'устал')}. Дай отдохнуть или покорми овсом.`, 'warn'); return; }
    ex = { type: 'jump', height, i: 0, faults: 0, refusals: 0, t: 0, air: 0, cd: 0, takeoff: 0, prevAlong: -1e9, jumps: World.COURSE.map(() => null) };
    UI.toast(`Конкур ${height} см: проходи препятствия по порядку ГАЛОПОМ, жми «Прыжок!» (Пробел) прямо перед жердями`);
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
        if (clean === 5) stat('cavClean');
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
    if (pct >= 60) stat('dres60');
    if (medal) S.stats[medal]++;
    const testName = ex.test.name;
    ex = null;
    UI.dressageResult(testName, marks, pct, money, medal, Horses.skill(m, 'dressage'));
    if (medal) Sound.fanfare(); else Sound.tick();
  }

  function exerciseHud() {
    const rh = Events.hud();
    if (rh) return rh;
    if (!ex) return null;
    const p = S.player;
    if (ex.type === 'jump') {
      const o = World.COURSE[Math.min(ex.i, World.COURSE.length - 1)];
      const good = p.gait === 2 || (ex.height <= 60 && p.gait === 1);
      return {
        title: `Конкур ${ex.height} см`,
        line: `Препятствие №${o.n} (${o.name}) · штраф: ${ex.faults} · время ${Math.floor(ex.t)}/${JUMP_NORM} с`,
        hint: good ? 'Галоп ✔ Жми «Прыжок!» (Пробел) прямо перед жердями' : 'Переходи на ГАЛОП (клавиша 3)',
        ok: good, lift: true, liftLabel: '⤴ Прыжок!', letter: String(o.n),
      };
    }
    if (ex.type === 'cav') {
      const clean = ex.poles.filter(s => s.state === 'ok').length;
      const done = ex.poles.filter(s => s.state).length;
      return {
        title: 'Кавалетти',
        line: `Жерди: ${done}/5 · чисто: ${clean}`,
        hint: p.gait === 1 ? 'Рысь ✔ Жми «Ноги выше!» (Пробел) перед жердью' : 'Переходи на РЫСЬ (клавиша 2)',
        ok: p.gait === 1, lift: true, liftLabel: '⤴ Ноги выше!',
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
      if (!Horses.canRide(h)) return UI.toast(`На жеребёнке можно ездить только с ${Horses.RIDE_AGE} лет. ${h.name} сейчас ${Horses.ageText(h)} — гуляй с ним, корми и играй!`, 'warn');
      if (h.state === 'walk') h.state = 'stall';
      if (h.energy < 5) return UI.toast(`${h.name} ${Horses.v(h, 'устала', 'устал')}. Пусть отдохнёт.`, 'warn');
      if (h.state === 'market') return UI.toast(`${h.name} стоит на рынке. Сначала сними с продажи у своей стойки`, 'warn');
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
      UI.toast(`${m.name} ${Horses.v(m, 'вернулась', 'вернулся')}: ${stallLabel(m.stall)}`);
    },
    paddock(h) {
      if (!atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (h.state === 'market') return UI.toast(`${h.name} стоит на рынке`);
      if (h.state === 'paddock') { h.state = 'stall'; UI.toast(`${h.name} ${Horses.v(h, 'вернулась', 'вернулся')} в денник`); }
      else if (h.state === 'stall') {
        const P = paddockFor(h);
        h.state = 'paddock';
        h.x = rand(P.x + 60, P.x + P.w - 60); h.y = rand(P.y + 60, P.y + P.h - 60); h.wander = null;
        UI.toast(`🌿 ${h.name} гуляет в леваде`);
      }
    },
    feed(h, item) {
      if (!atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (!(S.inv[item] > 0)) return UI.toast(`Нет: ${FOOD[item].name}. Купи в повозке.`, 'warn');
      if (FOOD[item].foalOnly && h.age >= 3) return UI.toast('Молоко из бутылочки — для жеребят. Взрослым лучше сено и овёс', 'warn');
      if (item === 'milk') { float('🍼 Ням-ням!', h.x, h.y - 30, '#e64980'); stat('milkFed'); h.mood = clamp(h.mood + 5, 0, 100); }
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
      if ((h.mud || 0) > 20) UI.toast(`🪮 Ноги у лошади по кличке ${h.name} снова чистые!`);
      h.clean = 100; h.mud = 0;
      h.mood = clamp(h.mood + 8, 0, 100);
      Sound.tick();
    },
    // трюки и действия лошади по команде
    trick(h, k) {
      if (!h || !ACTS[k]) return;
      const ridden = h.state === 'ridden';
      if (!ridden && h.state !== 'walk' && !atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (ridden && k === 'roll') return UI.toast('Чтобы лошадь повалялась, сначала слезь с неё', 'warn');
      if (h.state === 'market') return UI.toast(`${h.name} стоит на рынке`);
      UI.closeModal();
      startAct(h, k);
      if (k === 'roll' && (h.mud || 0) < 30) h.mud = Math.min(100, (h.mud || 0) + 15);
      h.mood = clamp(h.mood + 2, 0, 100);
      stat('tricks');
      if (k === 'dance') stat('dances');
    },
    // гулять с жеребёнком: он идёт следом
    walk(h) {
      if (!h) return;
      if (h.state === 'walk') { h.state = 'stall'; UI.toast(`🏠 ${h.name} ${Horses.v(h, 'вернулась', 'вернулся')} в денник`); UI.closeModal(); return; }
      if (!atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (Horses.canRide(h)) return UI.toast(`${h.name} уже ${Horses.v(h, 'взрослая', 'взрослый')} — на ${Horses.v(h, 'ней', 'нём')} можно ездить верхом`);
      if (mounted()) return UI.toast('Сначала слезь с лошади');
      if (h.state === 'market') return UI.toast(`${h.name} стоит на рынке`);
      for (const o of S.horses) if (o.state === 'walk') o.state = 'stall';
      h.state = 'walk';
      h.x = S.player.x - 50; h.y = S.player.y + 30;
      UI.closeModal();
      UI.toast(`🐴 Гуляем с жеребёнком по кличке ${h.name}! Он идёт за тобой. Вернуть в денник — кнопка внизу`, 'good');
    },
    stopWalk() { const h = S.horses.find(o => o.state === 'walk'); if (h) act.walk(h); },
    pet(h) {
      if (!h) return;
      if (h.state !== 'walk' && !atFarm()) return UI.toast('Подойди к конюшне');
      h.mood = clamp(h.mood + 10, 0, 100);
      float('💕', h.x, h.y - 30, '#e64980');
      if (!h.act) startAct(h, Math.random() < 0.5 ? 'lookUp' : 'ears', true);
      stat('petted');
      Sound.tick();
    },
    play(h) {
      if (!h) return;
      if (h.state !== 'walk' && !atFarm()) return UI.toast('Подойди к конюшне');
      if (h.energy < 10) return UI.toast(`${h.name} ${Horses.v(h, 'устала', 'устал')} — пусть отдохнёт`, 'warn');
      UI.closeModal();
      h.mood = clamp(h.mood + 15, 0, 100);
      h.energy = clamp(h.energy - 8, 0, 100);
      startAct(h, Math.random() < 0.6 ? 'play' : 'dance');
      float('🎾 Играем!', h.x, h.y - 30, '#1c7ed6');
      stat('foalPlay');
    },
    // кобыла готова — жеребёнок рождается по кнопке, с заставкой
    birth(h) {
      h = h || S.horses.find(o => o.preg && o.preg.ready);
      if (!h || !h.preg || !h.preg.ready) return;
      const st = freeStall();
      if (st < 0) return UI.toast('Нет свободного денника для жеребёнка — освободи место!', 'warn');
      const f = Horses.foal(h, h.preg.father, S.horses.map(x => x.name));
      f.state = 'stall'; f.stall = st; f.hunger = 90; f.mood = 90;
      S.horses.push(f);
      S.stats.foals++;
      if (Horses.isMagic(f)) stat('magicFoals');
      h.preg = null;
      UI.closeModal();
      UI.birthScene(h, f);
      Sound.fanfare();
    },
    // уход в виде мини-игр: расчесать, помыть, подковать
    care(h, kind) {
      if (!h) return;
      if (h.state !== 'walk' && !atFarm()) return UI.toast('Подойди к конюшне или леваде');
      if (kind === 'brush' && !S.tack.brush) return UI.toast('Нужна щётка — купи в повозке «Корм и амуниция»', 'warn');
      if (kind === 'shoe' && !(S.inv.horseshoes > 0)) return UI.toast('Нужны новые подковы — купи в повозке «Корм и амуниция»', 'warn');
      if (kind === 'shoe' && h.age < 2) return UI.toast('Жеребятам подковы не нужны — копытца ещё мягкие', 'warn');
      UI.closeModal();
      Care.open(kind, h, score => {
        if (kind === 'brush') {
          h.clean = 100; h.mood = clamp(h.mood + 6 + score * 6, 0, 100);
          UI.toast(`🪮 ${h.name} ${Horses.v(h, 'расчёсана', 'расчёсан')} и блестит!`, 'good'); stat('brushed');
        } else if (kind === 'wash') {
          h.clean = 100; h.mud = 0; h.wet = 100; h.mood = clamp(h.mood + 8 + score * 6, 0, 100);
          UI.toast(`🛁 ${h.name} чистенькая и мокрая — скоро высохнет!`, 'good'); stat('washed');
        } else if (kind === 'shoe') {
          S.inv.horseshoes--;
          h.shoes = true; h.mood = clamp(h.mood + 4, 0, 100);
          Horses.addTrain(h, 'speed', 1 + score * 2); Horses.addTrain(h, 'jump', 1 + score * 2);
          UI.toast(`🔧 ${h.name} в новых подковах! Скорость и прыжки чуть выше`, 'good'); stat('shod');
        }
        Sound.fanfare();
      });
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
        father: { name: stallion.name, g: JSON.parse(JSON.stringify(stallion.g)), base: Object.assign({}, stallion.base), breed: stallion.breed, size: stallion.size, temper: stallion.temper, marks: JSON.parse(JSON.stringify(stallion.marks)), magic: stallion.magic ? JSON.parse(JSON.stringify(stallion.magic)) : null },
      };
      UI.toast(`💕 ${mare.name} и ${stallion.name} ждут жеребёнка! Он родится через 2,5 минуты.`, 'good');
      Sound.fanfare();
    },
    sell(h) {
      const p = S.player;
      if (h && h.state === 'walk') return UI.toast('Сначала верни жеребёнка в денник');
      if (dist(p, { x: World.SELL.x + World.SELL.w / 2, y: World.SELL.y + World.SELL.h / 2 }) > 170) return UI.toast('Подойди к повозке «Продажа лошадей»');
      if (h === led) {
        const price = sellPrice(h, true);
        S.money += price;
        led = null;
        S.stats.sold++;
        UI.toast(`Продано: ${h.name} за ${price} 🪙`, 'good');
        Sound.coin();
        return;
      }
      if (h.state === 'ridden') return UI.toast('Сначала слезь с лошади');
      const price = sellPrice(h);
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
    buyStyle(kind, style) {
      const st = Items.TACK_STYLES[style], price = st[kind];
      const own = S.tack[kind + 'Styles'];
      if (!S.tack[kind]) return UI.toast(kind === 'saddle' ? 'Сначала купи обычное седло' : 'Сначала купи обычную уздечку', 'warn');
      if (own[style]) { S.tack[kind + 'Style'] = style; return; }
      if (S.money < price) return UI.toast('Не хватает монет', 'warn');
      S.money -= price;
      own[style] = true;
      S.tack[kind + 'Style'] = style;
      UI.toast(`Куплено: ${st.name.toLowerCase()} ${kind === 'saddle' ? 'седло' : 'оголовье'}!`, 'good');
      Sound.coin();
    },
    setTackColor(kind, color) { S.tack[kind + 'Color'] = color; Sound.tick(); },
    sail(to) {
      const p = S.player, m = mounted();
      const dest = to === 'main' ? { x: World.PIER.x - 90, y: World.PIER.y, name: 'большую землю' } : (() => { const I = World.ISLANDS.find(q => q.id === to); return { x: I.pier.x + 110, y: I.pier.y, name: `остров «${I.name}»` }; })();
      if (ex || Events.busy()) return UI.toast('Сначала закончи упражнение или скачки');
      UI.closeModal();
      p.x = dest.x; p.y = dest.y; p.vx = p.vy = 0; p.target = null; p.fly = false;
      if (m) { m.x = p.x; m.y = p.y; }
      if (led) { led.x = p.x - 60; led.y = p.y + 40; led.vx = led.vy = 0; }
      UI.toast(`⛵ Лодка доплыла на ${dest.name}!`, 'good');
      Sound.fanfare();
    },
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
    tricks() { const m = mounted(); if (m) UI.openTricks(m.id); },
    toggleFly() {
      const p = S.player, m = mounted();
      if (!Horses.canFly(m)) return UI.toast('Летать умеют лошади с крыльями (пегасы, бабочки, драконы, вороны, стрекозы, пчёлки) и облачные лошадки');
      if (p.fly) {
        if (World.blocked(p.x, p.y, 20)) return UI.toast('Здесь не приземлиться — найди ровное место', 'warn');
        p.fly = false;
        UI.toast(`🪽 ${m.name} мягко ${Horses.v(m, 'приземлилась', 'приземлился')}`);
      } else {
        if (m.energy < 10) return UI.toast(`${m.name} ${Horses.v(m, 'устала', 'устал')} — сначала отдохните`, 'warn');
        if (ex || Events.busy()) return UI.toast('Во время упражнений и скачек летать нельзя');
        p.fly = true;
        p.gait = 2;
        UI.toast(m.magic.wings ? '🪽 Взлетаем! Над водой и деревьями можно летать. Небесные острова — за южным краем земли. V — приземлиться' : '☁️ Облачка под копытами подняли вас в небо! Небесные острова — за южным краем земли. V — приземлиться');
        Sound.fanfare();
      }
    },
    toggleDetector() {
      const p = S.player;
      if (!S.tack.detector) return UI.toast('Металлоискатель продаётся в повозке «Корм и амуниция»');
      p.detector = !p.detector;
      UI.toast(p.detector ? '📡 Металлоискатель включён. Чем чаще пищит — тем ближе клад!' : '📡 Металлоискатель выключен');
    },
    setManeStyle(h, style) {
      if (!h || h.maneStyle === style) return;
      h.maneStyle = style;
      if (style !== 'normal') stat('maneStyled');
      Sound.tick();
    },
    dyeMane(h, dye) {
      if (!h) return;
      if (!dye) { h.maneDye = null; Sound.tick(); return; }
      const d = Items.DYES[dye];
      if (!(S.inv[d.item] > 0)) return UI.toast(`Нет краски: ${d.name}. Купи у Лолы или в повозке`, 'warn');
      S.inv[d.item]--;
      h.maneDye = dye;
      stat('maneDyed');
      UI.toast(`🎨 Грива стала: ${d.name.toLowerCase()}!`, 'good');
      Sound.coin();
    },
    buyItem(key, n, price) {
      if (S.money < price * n) return UI.toast('Не хватает монет', 'warn');
      S.money -= price * n;
      S.inv[key] = (S.inv[key] || 0) + n;
      Sound.coin();
    },
    sellItem(key, n) {
      const it = Items.ITEMS[key];
      if (!it || !it.sell || !(S.inv[key] >= n)) return;
      S.inv[key] -= n;
      S.money += it.sell * n;
      Sound.coin();
    },
    startExercise, startJumping, cancelExercise: () => { cancelExercise('Упражнение прервано'); Events.cancelRace('Скачки прерваны'); }, reset,
    liftLegs() { if (ex && ex.type === 'jump') jumpPress(); else liftLegs(); },
    setGfx(mode) { setGfx(mode); },
  };

  // цена у торговца: пойманная без приручения — дешевле, на ярмарке — дороже
  function sellPrice(h, wildOne = h === led) {
    let p = Horses.price(h) * Events.priceMul();
    if (wildOne) p *= 0.85;
    return Math.round(p / 5) * 5;
  }

  /* ---------------- подсказки и кнопки ---------------- */
  function computePrompt() {
    const p = S.player;
    if (ex || Events.busy() || Farm.mode) return null;
    const fp = Farm.prompt();
    if (fp) return fp;
    const qp = Quests.prompt();
    if (qp) return qp;
    const mp = Market.prompt();
    if (mp) return mp;
    const piers = [World.PIER].concat(World.ISLANDS.map(I => I.pier));
    if (piers.some(q => Math.hypot(q.x - p.x, q.y - p.y) < 130)) return { label: '⛵ Лодка', fn: () => UI.openBoat() };
    if (islandStableHere(p)) return { label: '🐴 Мои лошади', fn: () => UI.openStable(true) };
    const ep = Events.prompt();
    if (ep) return ep;
    if (World.inRect(p.x, p.y, World.STABLE, 30) || World.inRect(p.x, p.y, World.PADDOCK, 30) || Farm.nearStable(p))
      return { label: '🐴 Мои лошади', fn: () => UI.openStable(true) };
    const near = W => Math.hypot(p.x - (W.x + W.w / 2), p.y - (W.y + W.h / 2)) < 130;
    if (near(World.SELL)) return { label: '💰 Продать лошадь', fn: () => UI.openSell() };
    if (near(World.SHOP)) return { label: '🛒 Корм и амуниция', fn: () => UI.openShop() };
    if (inArena()) {
      if (mounted()) return { label: '🏆 Тренировка', fn: () => UI.openTraining() };
      return { label: '🏆 Тренировка', fn: () => UI.toast('Чтобы тренироваться, сядь на лошадь в конюшне') };
    }
    if (inJumpField()) {
      if (mounted()) return { label: '🏆 Конкур', fn: () => UI.openJumping() };
      return { label: '🏆 Конкур', fn: () => UI.toast('Для конкура сядь на лошадь в конюшне') };
    }
    return null;
  }

  function hint() {
    const tk = S.tack;
    if (Farm.mode) return '';
    if (!S.horses.length && !led) return 'Иди в поле справа → и поймай лошадь лассо. Спокойных лошадей ловить легче!';
    if (led) return `Веди лошадь по кличке ${led.name} в конюшню — она пойдёт за тобой`;
    if (!tk.saddle || !tk.bridle) return 'Купи седло и уздечку в повозке «Корм и амуниция», чтобы ездить верхом';
    if (!mounted()) return 'Открой конюшню и сядь на лошадь. Тренируйся в манеже!';
    if (ex || Events.busy()) return '';
    if (inArena()) return 'Нажми «Тренировка»: кавалетти или выездка';
    if (inJumpField()) return 'Нажми «Конкур» и выбери высоту препятствий';
    if (S.player.fly) return 'Ты летишь! V — приземлиться. Сверху видно весь мир';
    const reg = World.regionAt(S.player.x, S.player.y);
    if (reg === 'cave') return Math.hypot(S.player.x - World.PORTAL.x, S.player.y - World.PORTAL.y) < 700
      ? '🌀 Впереди светится портал на небесные острова — войди в него!'
      : 'В пещере темно. Здесь бродят лошади-скелеты и привидения, где-то спрятан сундук графа, а в глубине светится портал';
    if (reg === 'market') return 'Рынок: покупай и продавай лошадей, торгуйся, прокачивай навыки и меняйся вещами';
    if (S.player.y > World.H) return 'Небесные острова! Здесь живут крылатые и облачные лошадки. Портал домой — в центре Облачного острова';
    if (reg === 'mushroom') return 'Грибное королевство: здесь живут пегасы, единороги и стихийные лошадки. В дождь здесь радужные лужи — и может прилететь розовый дракон!';
    const tr = Train.hud();
    if (tr.catchLeft != null && Train.near(S.player)) return `🚂 Поезд у станции! Лови красивых лошадей — осталось ${Math.ceil(tr.catchLeft)} с`;
    if (reg === 'desert') return tr.moving ? '🚂 По рельсам едет поезд — спеши к станции!' : `Пустыня: здесь бегают зебры. Поезд с лошадьми приедет к станции через ${Math.ceil(tr.next / 60)} мин`;
    if (reg === 'grotto') return 'Пещерные холмы: загляни в маленькие пещерки — там живут чёрные лошади со светящимися узорами';
    if (reg === 'grottocave') return '✨ Пещерка! Чёрные лошади светятся своими узорами, а за ними тянется сияние';
    if (reg === 'foxwood' || reg === 'deepforest') return 'Густой лес: здесь живут лисьи лошади с пушистыми хвостами. Олени тоже где-то рядом';
    if (reg === 'dragonrock') return 'Драконьи скалы: здесь живут чешуйчатые лошади с драконьими крыльями и рогами. Осторожно, лава!';
    if (reg === 'steppe') return 'Степь: дикие лошади Пржевальского, олени и высокая трава';
    if (reg === 'i4') return 'Костяной остров: лошади с черепами и рёбрами, а вокруг — огромные кости';
    if (isNight()) return 'Ночь: табуны спят — подкрасться к лошадям легче. Фонари освещают ферму';
    if (!Quests.journal().length) return 'Поговори с жителями (💬) — у них есть задания. Список заданий — кнопка 📜';
    return 'Аллюры: 1 — шаг, 2 — рысь, 3 — галоп. Задания — кнопка 📜, стройка — 🔨';
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
      if (Care.isOpen() || UI.isBirthOpen()) return;
      if (Farm.mode) {
        if (code === 'Escape') { Farm.cancel(); return; }
        if (code === 'KeyR') { Farm.rotate(); return; }
      }
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(code)) e.preventDefault();
      if (e.repeat) { keys.add(code); return; }
      keys.add(code);
      if (code === 'KeyE' || code === 'Enter') act.interact();
      if (code === 'Space') {
        if (ex && ex.type === 'cav') liftLegs();
        else if (ex && ex.type === 'jump') jumpPress();
        else act.lasso();
      }
      if (code === 'Digit1') act.setGait(0);
      if (code === 'Digit2') act.setGait(1);
      if (code === 'Digit3') act.setGait(2);
      if (code === 'KeyQ') act.setGait(Math.max(0, S.player.gait - 1));
      if (code === 'KeyR') act.setGait(Math.min(2, S.player.gait + 1));
      if (code === 'KeyX' || code === 'KeyF') act.dismount();
      if (code === 'Escape' && ex) act.cancelExercise();
      if (code === 'KeyV') act.toggleFly();
      if (code === 'KeyM') act.toggleDetector();
      if (code === 'KeyB') UI.openBuild();
      if (code === 'KeyJ') UI.openQuests();
      if (code === 'KeyT') act.tricks();
      if (code === 'KeyN' && mounted()) startAct(mounted(), 'neigh');
    } else keys.delete(code);
  }

  function toWorld(e) {
    const w = Voxel.toWorld(e.clientX, e.clientY);
    return w || { x: S.player.x, y: S.player.y };
  }

  function onPointer(e, type) {
    if (UI.isModalOpen() || UI.isLassoOpen() || Care.isOpen() || UI.isBirthOpen() || !Voxel.ready) return;
    if (Farm.mode) {
      const w = toWorld(e);
      if (type === 'down') Farm.buildAt(w.x, w.y);
      else if (type === 'move') Farm.hover(w.x, w.y);
      return;
    }
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
    viewW = innerWidth < 700 ? 1100 : 1500;
    viewH = viewW * innerHeight / innerWidth;
  }

  /* ---------------- отрисовка ---------------- */
  function rider() {
    const t = S.tack;
    return {
      pad: t.pad || '#7a6a55', helmet: t.helmet || '#222a3a', boots: t.boots, shirt: S.player.shirt,
      saddleStyle: t.saddleStyle || 'classic', saddleColor: t.saddleColor || '#5b3a1e',
      bridleStyle: t.bridleStyle || 'classic', bridleColor: t.bridleColor || '#2b1a10',
    };
  }

  // поверх 3D-сцены — прозрачный холст с надписями, стрелками, дождём
  function renderOverlay() {
    const p = S.player, R = Voxel;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (!Voxel.ready) { Draw.label(ctx, '🐴 Загрузка мира…', innerWidth / 2, innerHeight / 2, 28, '#3b2a1a'); return; }
    const near = (x, y) => Math.abs(x - p.x) < 1300 && Math.abs(y - p.y) < 1000;
    const lbl = (t, x, y, h, size = 16, color = '#3b2a1a') => {
      if (!near(x, y)) return;
      const s = R.project(x, y, h);
      if (s.ok) Draw.label(ctx, t, s.x, s.y, size, color);
    };
    // высоты надписей — в «пикселях карты»
    lbl('🐴 КОНЮШНЯ', World.STABLE.x + World.STABLE.w / 2, World.STABLE.y - 10, 200);
    lbl('🏇 МАНЕЖ', World.ARENA.x + World.ARENA.w * 0.32, World.ARENA.y - 20, 60);
    lbl('🌿 ЛЕВАДА', World.PADDOCK.x + World.PADDOCK.w / 2, World.PADDOCK.y - 15, 70);
    lbl('🏆 КОНКУРНОЕ ПОЛЕ', World.JUMPF.x + World.JUMPF.w / 2, World.JUMPF.y - 20, 60);
    lbl(World.SELL.name, World.SELL.x + World.SELL.w / 2, World.SELL.y - 10, 120);
    lbl(World.SHOP.name, World.SHOP.x + World.SHOP.w / 2, World.SHOP.y - 10, 120);
    for (const hh of World.HOUSES) if (hh.name) lbl(hh.name, hh.x + hh.w / 2, hh.y - 10, 260, 14);
    lbl('📋 Доска заданий', World.BOARD.x, World.BOARD.y, 140, 14);
    lbl('🎪 РЫНОК', World.MARKET.x + World.MARKET.w / 2, World.MARKET.y - 10, 120, 18, '#b35c00');
    for (const st of World.MARKET_STALLS) lbl(st.name, st.x + st.w / 2, st.y, 90, 13);
    lbl('🌀 Портал', World.PORTAL.x, World.PORTAL.y, 130, 16, '#7048e8');
    lbl('🌀 Портал в пещеру', World.SKY_PORTAL.x, World.SKY_PORTAL.y, 130, 16, '#7048e8');
    for (const I of World.SKY_ISLANDS) lbl('☁️ ' + I.name, I.x, I.y - I.ry + 80, 60, 15, '#1c4f8a');
    lbl('🦇 Пещера', World.CAVE.x - 120, (World.CAVE_GATE.y1 + World.CAVE_GATE.y2) / 2, 300, 18, '#343a40');
    if (!S.flags.chest_opened) lbl('🧰', World.CHEST.x, World.CHEST.y, 80, 22);
    // жители и значки заданий
    for (const n of Quests.NPCS) {
      if (!near(n.x, n.y)) continue;
      const mk = Quests.marker(n.id);
      lbl(n.name, n.x, n.y, 230, 13, n.ghost ? '#5c7cfa' : '#1c4f8a');
      if (mk === '❗' || mk === '❓') lbl(mk, n.x, n.y, 300 + Math.sin(time * 4) * 8, 24, '#e67700');
    }
    // имена на табличках денников
    if (World.inRect(p.x, p.y, World.STABLE, 250)) {
      for (let i = 0; i < 20; i++) {
        const h = horseInStall(i);
        if (!h) continue;
        const r = World.stallRect(i);
        const s = R.project(r.x + r.w / 2, r.row ? World.AISLE_Y2 + 4 : World.AISLE_Y1 - 4, 30);
        if (s.ok) Draw.label(ctx, h.name, s.x, s.y, 11, '#3b2a1a');
      }
    }
    for (const f of floats) {
      const s = R.project(f.x, f.y, 110);
      ctx.globalAlpha = Math.max(0, 1 - f.t / 1.4);
      if (s.ok) Draw.label(ctx, f.text, s.x, s.y - f.t * 30, 18, f.color);
    }
    ctx.globalAlpha = 1;
    for (const r of Events.rivals()) lbl(r.name, r.h.x, r.h.y, 120, 12, '#1c4f8a');
    for (const b of AI.bots()) lbl('🤖 ' + b.name, b.x, b.y, 125, 13, '#5f3dc4');
    lbl('🚂 СТАНЦИЯ', World.STATION.x + 110, World.STATION.y - 25, 110, 16, '#c92a2a');
    for (const g of World.GROTTOS) lbl('🕳️ Пещерка', g.x, g.y - g.r - 30, 120, 14, '#343a40');
    { const wk = S.horses.find(o => o.state === 'walk'); if (wk) lbl('🐾 ' + wk.name, wk.x, wk.y, 80, 12, '#1c4f8a'); }
    lbl('🏁 СКАЧКИ', Events.START.x, Events.START.y, 90, 15);
    const shoe = Events.shoe();
    if (shoe) lbl('✨🧲✨', shoe.x, shoe.y + Math.sin(time * 5) * 3, 15, 16, '#b07800');
    const arrowTo = (tx, ty) => {
      const s0 = R.project(p.x, p.y, 0), s1 = R.project(tx, ty, 0);
      const sa = Math.atan2(s1.y - s0.y, s1.x - s0.x);
      ctx.save();
      ctx.translate(s0.x + Math.cos(sa) * 70, s0.y + Math.sin(sa) * 70);
      ctx.rotate(sa);
      ctx.fillStyle = 'rgba(255,212,0,0.95)'; ctx.strokeStyle = 'rgba(90,60,0,0.8)'; ctx.lineWidth = 2;
      const b = Math.sin(time * 5) * 4;
      ctx.beginPath(); ctx.moveTo(22 + b, 0); ctx.lineTo(-6 + b, -14); ctx.lineTo(-6 + b, 14); ctx.closePath(); ctx.fill(); ctx.stroke();
      ctx.restore();
    };
    const ng = Events.nextGate();
    if (ng) {
      arrowTo(ng.x, ng.y);
      lbl(ng.finish ? '🏁 ФИНИШ' : `Ворота ${ng.n}`, ng.x, ng.y, 110, 15, '#b35c00');
    } else if (!S.horses.length && !led && p.x < World.FIELD.x - 100) arrowTo(HERDS.field.x, HERDS.field.y);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    Events.drawScreen(ctx, canvas.width, canvas.height, dpr, time);
    Holidays.drawScreen(ctx, canvas.width, canvas.height, dpr, time);
    Draw.minimap(mmctx, S, api);
    if (p.y <= World.H) Events.drawMinimap(mmctx, Draw.mmScale(mmctx.canvas));
  }

  function render() {
    const p = S.player;
    cam.x = p.x - viewW / 2; cam.y = p.y - viewH / 2;
    if (Voxel.ready) Voxel.render(api);
    renderOverlay();
  }

  function riderLift() {
    if (!ex) return 0;
    if (ex.type === 'cav') return ex.lift > 0 ? 0.35 : 0;
    if (ex.type === 'jump' && ex.air > 0) return Math.sin((1 - ex.air / 0.6) * Math.PI);
    return 0;
  }

  // во время мини-игр, заставки и окон игра стоит на паузе
  const paused = () => UI.isModalOpen() || Care.isOpen() || UI.isBirthOpen();
  // радужный дождь в волшебном биоме: иногда прилетает розовый дракон
  let wasRaining = false;
  function rainEvents() {
    const r = Events.raining();
    if (r && !wasRaining && Math.random() < 0.35 && !wild.some(w => w.breed === 'pinkdragon')) {
      const H = HERDS.magic, q = randomFieldPoint(300, H.area);
      const old = wild.find(w => w.home === 'magic');
      if (old) wild = wild.filter(w => w !== old);
      const d = makeWild(q.x, q.y, 'magic');
      if (d.breed !== 'pinkdragon') Object.assign(d, Horses.create({ breed: 'pinkdragon', age: rand(4, 9) }), { x: q.x, y: q.y, home: 'magic', slot: { x: 0, y: 0 }, flee: 0, grazeT: 1 });
      wild.push(d);
      UI.toast('🌈 В Грибном королевстве пошёл радужный дождь… Говорят, там появился розовый дракон! 💗🐉', 'good');
    }
    wasRaining = r;
  }

  /* ---------------- главный цикл ---------------- */
  let last = 0, hudT = 0, visitT = 0;
  function frame(ts) {
    const dt = Math.min(0.05, (ts - last) / 1000 || 0);
    last = ts;
    if (lasso) {
      lasso.pos += lasso.dir * lasso.speed * dt;
      if (lasso.pos > 1) { lasso.pos = 1; lasso.dir = -1; }
      if (lasso.pos < 0) { lasso.pos = 0; lasso.dir = 1; }
      UI.updateLasso(lasso);
    } else if (!paused()) {
      time += dt;
      S.clock = (S.clock + dt * 3) % 1440;
      lassoCd = Math.max(0, lassoCd - dt);
      updatePlayer(dt);
      updateHerd(dt);
      updateOwned(dt);
      Events.update(dt);
      Farm.update(dt);
      refreshIslands(dt);
      updatePen(dt);
      updatePortal(dt);
      updateMud(dt);
      Market.update(dt);
      Creatures.update(dt);
      Train.update(dt);
      Holidays.update(dt);
      AI.update(dt);
      rainEvents();
      visitT -= dt;
      if (visitT <= 0) { visitT = 0.5; Quests.updateVisits(); }
      if (ex) {
        if (!mounted()) ex = null;
        else if (!inExerciseArea()) cancelExercise(ex.type === 'jump' ? 'Ты выехала с конкурного поля — маршрут прерван' : 'Ты выехала из манежа — упражнение прервано');
        else if (ex.type === 'cav') updateCav(dt);
        else if (ex.type === 'jump') updateJump(dt);
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
        money: S.money, count: S.horses.length, max: totalStalls(), stats: S.stats, hint: hint(),
        prompt: computePrompt(), canLasso: !!nearestCatchable() && !lasso,
        mounted: m ? { name: m.name, gait: S.player.gait, energy: m.energy, wings: Horses.canFly(m), fly: !!S.player.fly } : null,
        led: led ? led.name : null, exercise: Farm.hud() || exerciseHud(), clock: clockText(),
        detector: S.tack.detector ? { on: !!S.player.detector, signal: Farm.signal() } : null,
        quests: Quests.journal().length, region: World.REGION_NAMES[World.regionAt(S.player.x, S.player.y)],
        walk: (S.horses.find(o => o.state === 'walk') || {}).name || null,
        birth: (S.horses.find(o => o.preg && o.preg.ready) || {}).name || null,
        train: Train.hud(), holiday: Holidays.hud(), ai: AI.hud(),
      });
    }
    requestAnimationFrame(frame);
  }

  const api = {
    get S() { return S; }, FOOD, TACK, TESTS, COLORS, GAITS, act, maxStalls: () => Farm.maxStalls(), stat, isNight, stallSpot,
    stallLabel, stallGroups, islandTimeLeft,
    wild: () => wild, led: () => led, exercise: () => ex, time: () => time, view: () => ({ x: cam.x, y: cam.y, w: viewW, h: viewH }),
    mounted, byId, freeStall, horseInStall, atFarm, daylight, rider, riderLift, catchable: () => nearestCatchable(),
    comfortHeight, JUMP_HEIGHTS, JUMP_NORM,
    nearSell: () => dist(S.player, { x: World.SELL.x + World.SELL.w / 2, y: World.SELL.y + World.SELL.h / 2 }) < 170,
    resolveLasso, save, sellPrice, float, makeWild,
    findHorse: id => S.horses.find(x => x.id === id) || (led && led.id === id ? led : null) || Events.findHorse(id) || Market.findHorse(id),
    rivals: () => Events.rivals(), gates: () => Events.gates(), bunnies: () => Events.bunnies(), weather: () => Events.weather(),
    herds: () => HERDS, mud: h => h.mud || 0, ACTS, startAct,
    removeWild: pred => { wild = wild.filter(w => !pred(w)); },
    addWild: h => wild.push(h),
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
    Events.init(api);
    Farm.init(api);
    Quests.init(api);
    Creatures.init(api);
    Market.init(api);
    Train.init(api);
    Holidays.init(api);
    AI.init(api);
    canvas.addEventListener('wheel', e => { Voxel.zoom(e.deltaY); e.preventDefault(); }, { passive: false });
    requestAnimationFrame(ts => { last = ts; requestAnimationFrame(frame); });
    Voxel.load().then(ok => {
      if (!ok) { UI.toast('Не получилось запустить 3D-графику: браузер не поддерживает WebGL', 'warn'); return; }
      if (!S.seenHelp) { S.seenHelp = true; UI.openHelp(); }
    });
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
    beep: f => tone(f, 0.06, 'square', 0.04),
    boo: () => { tone(300, 0.5, 'sine', 0.1); tone(220, 0.7, 'sine', 0.08, 0.2); },
    coin: () => { tone(988, 0.1, 'square', 0.06); tone(1319, 0.25, 'square', 0.06, 0.08); },
    fail: () => { tone(220, 0.25, 'sawtooth', 0.07); tone(160, 0.35, 'sawtooth', 0.07, 0.15); },
    thud: () => tone(110, 0.2, 'triangle', 0.2),
    whoosh: () => tone(500, 0.2, 'sine', 0.05),
    fanfare: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 0.25, 'triangle', 0.1, i * 0.11)),
    // лошадиное «иго-го»: высокий звук с дрожанием, который спускается вниз
    neigh: () => {
      if (!on) return;
      try {
        ac = ac || new (window.AudioContext || window.webkitAudioContext)();
        const t0 = ac.currentTime;
        const o = ac.createOscillator(), g = ac.createGain(), lfo = ac.createOscillator(), lg = ac.createGain(), f = ac.createBiquadFilter();
        o.type = 'sawtooth';
        o.frequency.setValueAtTime(650, t0); o.frequency.linearRampToValueAtTime(1150, t0 + 0.22); o.frequency.linearRampToValueAtTime(820, t0 + 0.6); o.frequency.linearRampToValueAtTime(420, t0 + 1.15);
        lfo.frequency.value = 13; lg.gain.value = 70; lfo.connect(lg); lg.connect(o.frequency);
        f.type = 'lowpass'; f.frequency.value = 1900;
        g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(0.08, t0 + 0.06); g.gain.exponentialRampToValueAtTime(0.03, t0 + 0.8); g.gain.exponentialRampToValueAtTime(0.0008, t0 + 1.2);
        o.connect(f); f.connect(g); g.connect(ac.destination);
        o.start(t0); lfo.start(t0); o.stop(t0 + 1.25); lfo.stop(t0 + 1.25);
      } catch (e) { /* звук недоступен */ }
    },
    train: () => { tone(392, 0.45, 'square', 0.05); tone(330, 0.6, 'square', 0.05, 0.5); },
    toggle() { on = !on; return on; },
    get on() { return on; },
  };
})();

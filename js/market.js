'use strict';
/*
 * Рынок в деревне.
 *  - Конский торговец: продаёт лошадей, с ним можно торговаться.
 *  - Тренер: за монеты прокачивает навыки лошади.
 *  - Обменщик: меняет твою лошадь на лошадь торговца (с доплатой) и вещи на вещи.
 *  - Моя стойка: выставляешь своих лошадей и вещи со своей ценой, покупатели приходят сами
 *    и иногда торгуются — предлагают свою цену.
 */
const Market = (() => {
  let G = null;
  const rand = (a, b) => a + Math.random() * (b - a);
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const pick = arr => arr[Math.floor(Math.random() * arr.length)];
  const round5 = v => Math.max(5, Math.round(v / 5) * 5);

  const STOCK_SIZE = 5;
  const REFRESH = 240;          // торговец привозит новых лошадей раз в 4 минуты
  const MAX_LISTED_HORSES = 3;
  const BUYERS = ['Бабушка Нюра', 'Фермер Коля', 'Девочка Света', 'Купец Савва', 'Наездница Ира', 'Дедушка Гоша', 'Тётя Валя', 'Мальчик Петя', 'Цыганка Роза', 'Граф Орлов'];
  const STOCK_BREEDS = ['arab', 'akhal', 'orlov', 'friesian', 'haflinger', 'appaloosa', 'paint', 'trakehner', 'budyonny', 'fjord', 'shetland'];
  const MAGIC_BREEDS = ['crystalhorse', 'waterhorse', 'sunhorse', 'rainbowhorse', 'mushroomhorse', 'sandhorse', 'stonehorse', 'leafhorse', 'damphorse', 'icehorse', 'firehorse', 'pegasus', 'unicorn', 'cloudhorse'];

  // обмен вещей: отдаёшь give — получаешь get
  const SWAPS = [
    { id: 's1', give: { mushroom: 5 }, get: { seed_magic: 1 } },
    { id: 's2', give: { glowshroom: 3 }, get: { dye_rainbow: 1 } },
    { id: 's3', give: { pumpkin: 2 }, get: { oats: 10 } },
    { id: 's4', give: { carrot: 10 }, get: { dye_pink: 1 } },
    { id: 's5', give: { oldCoin: 1, spoon: 1 }, get: { dye_gold: 1 } },
    { id: 's6', give: { sunflower: 3 }, get: { apple: 10 } },
    { id: 's7', give: { pollen: 2 }, get: { dye_purple: 1, dye_mint: 1 } },
    { id: 's8', give: { oldShoe: 3 }, get: { sugar: 15 } },
  ];

  const SAY_YES = ['Эх, уговорила! По рукам! 🤝', 'Ладно-ладно, для тебя — так и быть!', 'Хорошо торгуешься! Договорились.', 'Ну что с тобой делать… Забирай!'];
  const SAY_NO = ['Что ты! Себе в убыток не продам!', 'Нет-нет, эта лошадка стоит дороже!', 'Ха! Даже не проси.', 'Маловато будет! Добавь монеток.'];
  const SAY_ANGRY = 'Всё, больше не торгуюсь! Теперь цена выше 😤';

  /* ---------- состояние (хранится в сохранении: S.market) ---------- */
  function fresh() {
    return { stock: [], refreshT: 0, items: {}, offer: null, buyerT: rand(15, 30), say: '', log: [] };
  }
  function M() {
    const S = G.S;
    if (!S.market) S.market = fresh();
    const m = S.market;
    m.items = m.items || {}; m.stock = m.stock || []; m.log = m.log || [];
    return m;
  }

  function init(api) {
    G = api;
    const m = M();
    if (!m.stock.length) restock(true);
  }
  function reset() { G.S.market = fresh(); restock(true); }

  function restock(silent) {
    const m = M();
    const taken = G.S.horses.map(h => h.name);
    m.stock = [];
    for (let i = 0; i < STOCK_SIZE; i++) {
      const magic = Math.random() < (i === 0 ? 0.9 : 0.3);
      const breed = magic ? pick(MAGIC_BREEDS) : pick(STOCK_BREEDS);
      const h = Horses.create({ breed, age: Math.random() < 0.15 ? rand(1, 2.5) : rand(3, 11), taken: taken.concat(m.stock.map(x => x.name)) });
      h.state = 'shop';
      h.ask = round5(Horses.price(h) * rand(1.2, 1.45));
      h.haggles = 3;
      m.stock.push(h);
    }
    m.refreshT = REFRESH;
    if (!silent) UI.toast('🐎 Конский торговец на рынке привёз новых лошадей!');
  }

  const spot = (i, n) => ({ x: World.MARKET.x + 70 + i * 82, y: World.MARKET.y + 250, angle: Math.PI / 2 });
  // где стоит выставленная на продажу лошадь игрока
  function spotOf(h) {
    const mine = G.S.horses.filter(x => x.state === 'market');
    const i = Math.max(0, mine.indexOf(h));
    return { x: World.MARKET.x + 480 + i * 62, y: World.MARKET.y + 255, angle: Math.PI / 2 };
  }
  function stockHorses() {
    const m = M();
    m.stock.forEach((h, i) => { const s = spot(i); h.x = s.x; h.y = s.y; h.angle = s.angle; h.spd = 0; h.headTurn = Math.sin(G.time() * 0.6 + h.seed) * 0.4; });
    return m.stock;
  }
  const findHorse = id => M().stock.find(h => h.id === id) || null;

  /* ---------- каждый кадр ---------- */
  function update(dt) {
    const m = M();
    m.refreshT -= dt;
    if (m.refreshT <= 0) restock(false);
    for (const h of m.stock) h.age += dt / 120 * 0.2;
    if (m.offer) {
      m.offer.t -= dt;
      if (m.offer.t <= 0) { UI.toast(`${m.offer.buyer} не дождался ответа и ушёл`); m.offer = null; }
    }
    m.buyerT -= dt;
    if (m.buyerT <= 0) { m.buyerT = rand(14, 28); buyerVisit(); }
  }

  /* ---------- моя стойка: покупатели ---------- */
  function horseValue(h) { return G.sellPrice(h, false); }
  function itemValue(k) {
    const it = Items.ITEMS[k], f = G.FOOD[k];
    return Math.max(1, (it && it.sell) || (f ? f.price * 0.7 : 1));
  }
  function buyChance(ratio) {
    if (ratio <= 0.9) return 0.85;
    if (ratio <= 1.1) return 0.6;
    if (ratio <= 1.35) return 0.35;
    if (ratio <= 1.6) return 0.15;
    if (ratio <= 2) return 0.05;
    return 0.01;
  }
  function listings() {
    const m = M();
    const horses = G.S.horses.filter(h => h.state === 'market').map(h => ({ kind: 'horse', h, id: h.id, price: h.ask, value: horseValue(h), name: h.name }));
    const items = Object.entries(m.items).filter(([, l]) => l.n > 0).map(([k, l]) => ({ kind: 'item', key: k, price: l.price, value: itemValue(k) * Events.priceMul(), name: Items.name(k), n: l.n }));
    return horses.concat(items);
  }
  function buyerVisit() {
    const m = M();
    const all = listings();
    if (!all.length || m.offer) return;
    const L = pick(all);
    const buyer = pick(BUYERS);
    const ratio = L.price / Math.max(1, L.value);
    if (Math.random() < buyChance(ratio)) return sold(L, L.price, buyer);
    // не купил сразу — иногда торгуется и предлагает свою цену
    if (ratio > 0.8 && Math.random() < 0.55) {
      const offerPrice = round5(Math.min(L.price * rand(0.75, 0.92), L.value * rand(1.0, 1.2)));
      if (offerPrice >= L.price) return sold(L, L.price, buyer);
      m.offer = { kind: L.kind, id: L.id, key: L.key, price: offerPrice, buyer, t: 60, name: L.name };
      UI.toast(`🗣️ ${buyer} хочет купить «${L.name}» за ${offerPrice} 🪙 (ты просишь ${L.price}). Ответь у своей стойки на рынке!`);
      Sound.tick();
    }
  }
  function sold(L, price, buyer) {
    const m = M(), S = G.S;
    if (L.kind === 'horse') {
      const h = S.horses.find(x => x.id === L.id);
      if (!h || h.state !== 'market') return;
      S.horses = S.horses.filter(x => x !== h);
      S.stats.sold++;
      UI.toast(`💰 ${buyer} ${buyer.endsWith('а') || buyer.endsWith('я') ? 'купила' : 'купил'} лошадь по кличке ${h.name} за ${price} 🪙!`, 'good');
    } else {
      const l = m.items[L.key];
      if (!l || l.n <= 0) return;
      l.n--;
      if (!l.n) delete m.items[L.key];
      UI.toast(`💰 ${buyer}: «${Items.name(L.key)}» — продано за ${price} 🪙`, 'good');
    }
    S.money += price;
    G.stat('marketSold');
    m.log.unshift(`${buyer}: ${L.name} — ${price} 🪙`);
    m.log = m.log.slice(0, 6);
    Sound.coin();
  }
  function answerOffer(yes) {
    const m = M(), o = m.offer;
    if (!o) return;
    m.offer = null;
    if (!yes) { UI.toast(`${o.buyer} вздохнул и пошёл дальше`); return; }
    sold(o.kind === 'horse' ? { kind: 'horse', id: o.id, name: o.name } : { kind: 'item', key: o.key, name: o.name }, o.price, o.buyer);
  }

  function listHorse(h) {
    if (!h) return;
    if (h.state === 'ridden') return UI.toast('Сначала слезь с лошади');
    if (G.S.horses.filter(x => x.state === 'market').length >= MAX_LISTED_HORSES) return UI.toast(`У стойки помещаются только ${MAX_LISTED_HORSES} лошади`, 'warn');
    h.state = 'market';
    h.ask = round5(horseValue(h) * 1.2);
    UI.toast(`🏷️ ${h.name} стоит у твоей стойки. Цена: ${h.ask} 🪙 — её можно поменять`);
    Sound.tick();
  }
  function unlistHorse(h) {
    if (!h || h.state !== 'market') return;
    h.state = 'stall';
    const m = M();
    if (m.offer && m.offer.kind === 'horse' && m.offer.id === h.id) m.offer = null;
    UI.toast(`${h.name} ${Horses.v(h, 'вернулась', 'вернулся')} в конюшню`);
  }
  function setHorsePrice(h, k) { if (h && h.state === 'market') h.ask = round5(h.ask * k); }

  function listItem(key, n) {
    const S = G.S, m = M();
    if (!(S.inv[key] >= n)) return;
    S.inv[key] -= n;
    const l = m.items[key] || (m.items[key] = { n: 0, price: Math.max(2, Math.round(itemValue(key) * 1.3)) });
    l.n += n;
    Sound.tick();
  }
  function unlistItem(key) {
    const S = G.S, m = M(), l = m.items[key];
    if (!l) return;
    S.inv[key] = (S.inv[key] || 0) + l.n;
    delete m.items[key];
    if (m.offer && m.offer.key === key) m.offer = null;
  }
  function setItemPrice(key, k) {
    const l = M().items[key];
    if (l) l.price = Math.max(1, Math.round(l.price * k) + (k > 1 ? 1 : k < 1 ? -1 : 0));
    if (l && l.price < 1) l.price = 1;
  }

  /* ---------- торговец: покупка и торг ---------- */
  function buy(id) {
    const m = M(), S = G.S, h = findHorse(id);
    if (!h) return;
    if (S.money < h.ask) return UI.toast('Не хватает монет', 'warn');
    const st = G.freeStall();
    if (st < 0) return UI.toast('В конюшне на ферме нет свободного денника', 'warn');
    S.money -= h.ask;
    m.stock = m.stock.filter(x => x !== h);
    h.state = 'stall'; h.stall = st;
    delete h.ask; delete h.haggles;
    S.horses.push(h);
    G.stat('marketBought');
    m.say = `Отличный выбор! ${h.name} уже едет к тебе в конюшню.`;
    UI.toast(`🐎 Куплено: ${h.name}! Теперь живёт: ${G.stallLabel(st)}`, 'good');
    Sound.fanfare();
  }
  function haggle(id, frac) {
    const m = M(), h = findHorse(id);
    if (!h || h.haggles <= 0) return;
    const d = 1 - frac;                                // скидка, которую просим
    const mood = G.S.stats.marketBought ? 0.05 : 0;    // постоянным покупателям уступают охотнее
    const chance = clamp(1.15 - d * 3 + mood, 0.05, 0.95);
    if (Math.random() < chance) {
      h.ask = round5(h.ask * frac);
      h.haggles = 0;
      m.say = pick(SAY_YES) + ` Отдам за ${h.ask} 🪙.`;
      G.stat('haggleWins');
      Sound.coin();
    } else {
      h.haggles--;
      if (h.haggles <= 0) { h.ask = round5(h.ask * 1.05); m.say = SAY_ANGRY; }
      else m.say = pick(SAY_NO);
      Sound.fail();
    }
  }

  /* ---------- обменщик ---------- */
  function swapValue(mine) { return round5(horseValue(mine) * 0.9); }
  function swapHorse(myId, theirId) {
    const S = G.S, m = M(), mine = G.byId(myId), theirs = findHorse(theirId);
    if (!mine || !theirs) return;
    if (mine.state === 'ridden') return UI.toast('Сначала слезь с лошади');
    const diff = theirs.ask - swapValue(mine);    // >0 — доплачиваешь ты, <0 — доплачивают тебе
    if (diff > 0 && S.money < diff) return UI.toast(`Нужна доплата ${diff} 🪙 — не хватает монет`, 'warn');
    S.money -= diff;
    const st = mine.stall;
    S.horses = S.horses.filter(x => x !== mine);
    m.stock = m.stock.map(x => (x === theirs ? mine : x));
    mine.state = 'shop'; mine.ask = round5(horseValue(mine) * 1.3); mine.haggles = 3;
    theirs.state = 'stall'; theirs.stall = st;
    delete theirs.ask; delete theirs.haggles;
    S.horses.push(theirs);
    G.stat('swaps');
    UI.toast(`🔁 Обмен! ${mine.name} → ${theirs.name}${diff > 0 ? `, доплата ${diff} 🪙` : diff < 0 ? `, тебе доплатили ${-diff} 🪙` : ''}`, 'good');
    Sound.fanfare();
  }
  const canSwap = sw => Object.entries(sw.give).every(([k, n]) => (G.S.inv[k] || 0) >= n);
  function swapItems(id) {
    const sw = SWAPS.find(x => x.id === id), S = G.S;
    if (!sw || !canSwap(sw)) return UI.toast('Не хватает вещей для обмена', 'warn');
    for (const [k, n] of Object.entries(sw.give)) S.inv[k] -= n;
    for (const [k, n] of Object.entries(sw.get)) S.inv[k] = (S.inv[k] || 0) + n;
    G.stat('swaps');
    UI.toast('🔁 Обменяно: ' + Object.entries(sw.get).map(([k, n]) => `${Items.icon(k)} ${Items.name(k)} ×${n}`).join(', '), 'good');
    Sound.coin();
  }

  /* ---------- тренер: прокачка ---------- */
  const TRAIN_STEP = 3;
  const trainPrice = (h, k) => round5(20 + Horses.skill(h, k) * 1.6);
  function train(h, k) {
    const S = G.S;
    if (!h) return;
    if (Horses.skill(h, k) >= 100) return UI.toast('Этот навык уже максимальный!');
    if (h.base[k] + h.train[k] >= 100) return;
    const price = trainPrice(h, k);
    if (S.money < price) return UI.toast('Не хватает монет', 'warn');
    S.money -= price;
    Horses.addTrain(h, k, TRAIN_STEP);
    h.energy = clamp(h.energy - 10, 0, 100);
    G.stat('marketTrain');
    UI.toast(`💪 ${Horses.SKILLS[k]} у лошади по кличке ${h.name}: ${Horses.skill(h, k)}`, 'good');
    Sound.coin();
  }
  function spa(h) {
    const S = G.S, price = 25;
    if (!h || S.money < price) return UI.toast('Не хватает монет', 'warn');
    S.money -= price;
    h.energy = 100; h.mood = clamp(h.mood + 25, 0, 100); h.clean = 100; h.mud = 0;
    UI.toast(`🧖 ${h.name}: массаж, мытьё и отдых — как новенькая!`, 'good');
    Sound.coin();
  }

  /* ---------- подсказка у прилавков ---------- */
  function stallHere() {
    const p = G.S.player;
    if (!World.inRect(p.x, p.y, World.MARKET, 80)) return null;
    let best = null, bd = 110;
    for (const st of World.MARKET_STALLS) {
      const f = World.stallFront(st), d = Math.hypot(p.x - f.x, p.y - f.y);
      if (d < bd) { bd = d; best = st; }
    }
    return best;
  }
  function prompt() {
    const st = stallHere();
    if (!st) return null;
    return { label: st.name, fn: () => UI.openMarket(st.id) };
  }

  return {
    init, reset, update, prompt, stockHorses, findHorse, spotOf, listings, M,
    buy, haggle, listHorse, unlistHorse, setHorsePrice, listItem, unlistItem, setItemPrice, answerOffer,
    swapHorse, swapValue, swapItems, canSwap, SWAPS, train, trainPrice, spa, itemValue, horseValue,
    MAX_LISTED_HORSES,
  };
})();

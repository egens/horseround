'use strict';
/* Лошади: создание, возраст, навыки, цена */
const Horses = (() => {
  const F_NAMES = ['Звёздочка', 'Ласточка', 'Ромашка', 'Изюминка', 'Буря', 'Вьюга', 'Снежинка', 'Карамель',
    'Корица', 'Ириска', 'Луна', 'Белла', 'Милка', 'Зорька', 'Искра', 'Плюшка', 'Багира', 'Фиалка',
    'Метелица', 'Ягодка', 'Жемчужина', 'Принцесса', 'Радуга', 'Лаванда', 'Ночка', 'Пуговка', 'Маруся', 'Вишенка'];
  const M_NAMES = ['Гром', 'Ветер', 'Буран', 'Орлик', 'Изумруд', 'Каштан', 'Уголёк', 'Мустанг', 'Смерч',
    'Огонёк', 'Пряник', 'Барон', 'Граф', 'Алмаз', 'Тайфун', 'Атлас', 'Цезарь', 'Дымок', 'Кузнечик',
    'Рубин', 'Сокол', 'Шторм', 'Янтарь', 'Зефир', 'Самсон', 'Вихрь', 'Персик', 'Бархат'];
  const SKILLS = { speed: 'Скорость', jump: 'Прыжки', dressage: 'Выездка', stamina: 'Выносливость' };
  const FACE = ['', 'звёздочка', 'проточина', 'лысина'];

  /*
   * Стихийные лошадки: свой окрас и узор вместо генетического.
   * body/mane/legs — основные цвета (для меню, миникарты и 3D), maneGlow — грива светится.
   */
  const CRYSTAL_TINTS = [
    ['#4dabf7', 'синяя'], ['#ff6b6b', 'красная'], ['#ffd43b', 'жёлтая'], ['#51cf66', 'зелёная'],
    ['#ff922b', 'оранжевая'], ['#cc5de8', 'фиолетовая'], ['#f783ac', 'розовая'], ['#3bc9db', 'бирюзовая'],
  ];
  const ELEMS = {
    ice: { word: 'ледяная', icon: '🧊', body: '#74c0fc', mane: '#e7f5ff', legs: '#4dabf7', maneCols: ['#a5f3fc', '#cffafe', '#67e8f9', '#e0f2fe', '#bae6fd'], maneGlow: true },
    crystal: { word: 'кристальная', icon: '💎', body: '#4dabf7', mane: '#d0ebff', legs: '#339af0', maneGlow: true },
    fire: { word: 'огненная', icon: '🔥', body: '#f76707', mane: '#ffd43b', legs: '#c92a2a', maneCols: ['#ff3d00', '#ff6d00', '#ff9100', '#ffc400', '#ffea00'], maneGlow: true },
    water: { word: 'водяная', icon: '💧', body: '#339af0', mane: '#e7f5ff', legs: '#1c7ed6', maneCols: ['#ffffff', '#d0ebff', '#a5d8ff', '#74c0fc', '#e7f5ff'], maneGlow: true },
    rainbow: { word: 'радужная', icon: '🌈', body: '#ffd43b', mane: '#cc5de8', legs: '#4dabf7', maneCols: ['#ff6b6b', '#ff922b', '#ffd43b', '#51cf66', '#4dabf7', '#5c7cfa', '#cc5de8'], maneGlow: true },
    sun: { word: 'солнечная', icon: '☀️', body: '#fcc419', mane: '#fff3bf', legs: '#f08c00', maneCols: ['#fff3bf', '#ffe066', '#ffc078', '#ffa94d', '#ffd43b'], maneGlow: true },
    sand: { word: 'песочная', icon: '🏜️', body: '#e9d3a1', mane: '#c9a66b', legs: '#d4b67a', maneCols: ['#c9a66b', '#b08d57', '#dcc394'] },
    stone: { word: 'каменная', icon: '🪨', body: '#868e96', mane: '#495057', legs: '#6c757d', maneCols: ['#495057', '#343a40', '#5c940d'] },
    mushroom: { word: 'грибная', icon: '🍄', body: '#f1e3c6', mane: '#e03131', legs: '#e8d9b5', maneCols: ['#e03131', '#c92a2a', '#ffffff', '#e03131'] },
    leaf: { word: 'лиственная', icon: '🍃', body: '#40c057', mane: '#2b8a3e', legs: '#5c3d1e', maneCols: ['#2b8a3e', '#37b24d', '#69db7c', '#fab005', '#2f9e44'] },
    damp: { word: 'сырая', icon: '💦', body: '#4a5a6a', mane: '#e9ecef', legs: '#3b4754', maneCols: ['#f1f3f5', '#dee2e6', '#ced4da'] },
  };
  function crystalTint() { return CRYSTAL_TINTS[Math.floor(Math.random() * CRYSTAL_TINTS.length)][0]; }
  const tintName = c => (CRYSTAL_TINTS.find(t => t[0] === c) || [c, 'переливчатая'])[1];
  // «окрас» стихийной лошадки поверх генетического
  function elemLook(h) {
    const k = h.magic && h.magic.elem, E = k && ELEMS[k];
    if (!E) return null;
    if (k === 'crystal') {
      const t = h.magic.tint || '#4dabf7';
      return { elem: k, tint: t, name: `кристальная (${tintName(t)})`, body: t, mane: Genetics.mix(t, '#ffffff', 0.6), legs: Genetics.mix(t, '#000000', 0.15) };
    }
    return { elem: k, name: k === 'damp' ? 'сырая с белыми узорами' : E.word, body: E.body, mane: E.mane, legs: E.legs };
  }

  let nextId = 1;
  const rand = (a, b) => a + Math.random() * (b - a);
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const pick = arr => arr[Math.floor(Math.random() * arr.length)];

  function randomName(sex, taken = []) {
    const list = (sex === 'f' ? F_NAMES : M_NAMES).filter(n => !taken.includes(n));
    return list.length ? pick(list) : pick(sex === 'f' ? F_NAMES : M_NAMES) + ' ' + Math.floor(rand(2, 99));
  }

  function randomMarks() {
    const r = Math.random();
    return {
      face: r < 0.4 ? 0 : r < 0.65 ? 1 : r < 0.88 ? 2 : 3,
      legs: [0, 1, 2, 3].map(() => Math.random() < 0.18),
    };
  }

  function inheritMarks(a, b) {
    const src = Math.random() < 0.5 ? a : b;
    return {
      face: Math.random() < 0.7 ? src.face : Math.floor(Math.random() * 4),
      legs: src.legs.map(v => (Math.random() < 0.75 ? v : Math.random() < 0.2)),
    };
  }

  function create(o) {
    const breed = o.breed || 'mix';
    const B = Genetics.BREEDS[breed];
    const sex = o.sex || (Math.random() < 0.5 ? 'f' : 'm');
    const base = o.base || {
      speed: Math.round(rand(...B.stats.speed)),
      jump: Math.round(rand(...B.stats.jump)),
      dressage: Math.round(rand(...B.stats.dressage)),
      stamina: Math.round(rand(...B.stats.stamina)),
    };
    return {
      id: nextId++,
      name: o.name || randomName(sex, o.taken),
      sex, breed,
      g: o.g || Genetics.randomGenotype(breed),
      base,
      train: { speed: 0, jump: 0, dressage: 0, stamina: 0 },
      age: o.age != null ? o.age : rand(3, 12),
      size: o.size || B.size * rand(0.95, 1.05),
      temper: o.temper != null ? o.temper : clamp(B.temper + rand(-0.15, 0.15), 0.05, 0.95),
      marks: o.marks || randomMarks(),
      hunger: 80, energy: 100, mood: 70, clean: 80,
      preg: null,
      magic: o.magic !== undefined ? o.magic : (B.magic ? Object.assign({}, B.magic, B.magic.elem === 'crystal' ? { tint: crystalTint() } : {}) : null),
      mud: 0,
      maneStyle: o.maneStyle || 'normal', maneDye: o.maneDye || null,
      state: 'wild', stall: -1,
      x: 0, y: 0, angle: 0, vx: 0, vy: 0, spd: 0, phase: Math.random() * 6, headTurn: 0,
      seed: Math.floor(Math.random() * 1e9),
    };
  }

  function foal(mother, father, taken) {
    const sex = Math.random() < 0.5 ? 'f' : 'm';
    const base = {};
    for (const k in SKILLS) base[k] = Math.round(clamp((mother.base[k] + father.base[k]) / 2 + rand(-6, 8), 10, 100));
    return create({
      breed: mother.breed === father.breed ? mother.breed : 'mix',
      sex, base, taken,
      g: Genetics.inherit(mother.g, father.g),
      age: 0,
      size: ((mother.size + father.size) / 2) * rand(0.96, 1.04),
      temper: clamp((mother.temper + father.temper) / 2 + rand(-0.1, 0.1), 0.05, 0.95),
      marks: inheritMarks(mother.marks, father.marks),
      magic: inheritMagic(mother.magic, father.magic),
    });
  }

  // волшебные черты передаются жеребёнку с вероятностью 50% от каждого родителя
  function inheritMagic(a, b) {
    a = a || {}; b = b || {};
    const m = {};
    for (const k of ['horn', 'skeleton']) {
      const n = (a[k] ? 1 : 0) + (b[k] ? 1 : 0);
      if (n && Math.random() < (n === 2 ? 0.75 : 0.5)) m[k] = true;
    }
    // крылья: тип берём от одного из родителей
    const wings = [a.wings, b.wings].filter(Boolean).map(wingType);
    if (wings.length && Math.random() < (wings.length === 2 ? 0.75 : 0.5)) m.wings = pick(wings);
    const manes = [a.mane, b.mane].filter(Boolean);
    if (manes.length && Math.random() < (manes.length === 2 ? 0.75 : 0.5)) m.mane = pick(manes);
    // стихия (вместе с цветом кристалла) — от одного из родителей
    const elems = [a, b].filter(x => x.elem);
    if (elems.length && Math.random() < (elems.length === 2 ? 0.75 : 0.5)) {
      const src = pick(elems);
      m.elem = src.elem;
      if (src.elem === 'crystal') m.tint = src.tint || crystalTint();
    }
    const clouds = (a.cloud ? 1 : 0) + (b.cloud ? 1 : 0);
    if (clouds && Math.random() < (clouds === 2 ? 0.75 : 0.5)) m.cloud = true;
    return Object.keys(m).length ? m : null;
  }
  // старые сохранения: wings: true — это пегас
  const wingType = w => (w === true ? 'pegasus' : w);
  const WING_NAMES = {
    pegasus: 'крылья пегаса 🪽', butterfly: 'крылья бабочки 🦋', dragon: 'крылья дракона 🐉',
    raven: 'крылья ворона 🪶', dragonfly: 'крылья стрекозы', bee: 'крылья пчёлки 🐝',
  };
  function magicText(h) {
    const m = h.magic;
    if (!m) return '';
    const p = [];
    if (m.wings) p.push(WING_NAMES[wingType(m.wings)]);
    if (m.horn) p.push('рог 🦄');
    if (m.mane === 'fire') p.push('огненная грива 🔥');
    if (m.mane === 'ice') p.push('ледяная грива ❄️');
    if (m.skeleton) p.push('скелет 💀');
    if (m.elem && ELEMS[m.elem]) p.push(`${m.elem === 'crystal' ? 'кристальная, ' + tintName(m.tint) : ELEMS[m.elem].word} ${ELEMS[m.elem].icon}`);
    if (m.cloud) p.push('летает на облачках ☁️');
    return p.join(', ');
  }
  const isMagic = h => !!(h.magic && (h.magic.wings || h.magic.horn || h.magic.mane || h.magic.elem || h.magic.cloud));
  // летать умеют лошади с крыльями и облачные лошадки
  const canFly = h => !!(h && h.magic && (h.magic.wings || h.magic.cloud));

  function pheno(h) {
    const key = Math.floor(h.age * 8);
    if (!h._ph || h._phKey !== key) {
      h._ph = Genetics.phenotype(h.g, h.age);
      const el = elemLook(h);
      if (el) h._ph = Object.assign({}, h._ph, el, { stripe: null, roan: false, tob: false, leo: false, dapple: false, greyLevel: 0, pinkSkin: false });
      h._phKey = key;
    }
    return h._ph;
  }

  const isAdult = h => h.age >= 3;
  const sizeOf = h => h.size * (h.age < 3 ? 0.55 + 0.45 * (h.age / 3) : 1);
  const skill = (h, k) => Math.min(100, Math.round(h.base[k] + h.train[k]));
  function addTrain(h, k, v) { h.train[k] = Math.max(0, Math.min(100 - h.base[k], h.train[k] + v)); }

  function plural(n, one, few, many) {
    const m10 = n % 10, m100 = n % 100;
    if (m10 === 1 && m100 !== 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) return few;
    return many;
  }

  function ageText(h) {
    if (h.age < 1) {
      const m = Math.max(0, Math.floor(h.age * 12));
      return m === 0 ? 'новорождённый' : `${m} ${plural(m, 'месяц', 'месяца', 'месяцев')}`;
    }
    const y = Math.floor(h.age);
    return `${y} ${plural(y, 'год', 'года', 'лет')}`;
  }

  function sexText(h) {
    if (h.age < 3) return h.sex === 'f' ? 'кобылка' : 'жеребчик';
    return h.sex === 'f' ? 'кобыла' : 'жеребец';
  }

  function marksText(h) {
    const parts = [];
    if (h.marks.face) parts.push(FACE[h.marks.face]);
    const n = h.marks.legs.filter(Boolean).length;
    if (n && !pheno(h).tob) parts.push(`${n} ${plural(n, 'белая нога', 'белые ноги', 'белых ног')}`);
    return parts.length ? parts.join(', ') : 'без отметин';
  }

  function price(h) {
    let avg = 0;
    for (const k in SKILLS) avg += skill(h, k);
    avg /= 4;
    let p = 100 + avg * 4;
    p *= pheno(h).rarity;
    if (h.age < 1) p *= 0.5;
    else if (h.age < 3) p *= 0.75;
    else if (h.age > 16) p *= 0.6;
    p *= 0.85 + h.mood / 600 + h.clean / 1200;
    if (h.preg) p *= 1.3;
    const m = h.magic;
    if (m) p *= (m.wings ? 2 : 1) * (m.horn ? 2 : 1) * (m.mane ? 1.6 : 1) * (m.skeleton ? 1.8 : 1) * (m.elem ? 1.7 : 1) * (m.cloud ? 2 : 1);
    if ((h.mud || 0) > 40) p *= 0.95;
    return Math.max(20, Math.round(p / 5) * 5);
  }

  // глагол в нужном роде: v(h, 'устала', 'устал')
  const v = (h, fem, masc) => (h.sex === 'f' ? fem : masc);

  return {
    SKILLS, v, create, foal, pheno, isAdult, sizeOf, skill, addTrain, ageText, sexText, marksText, price,
    randomName, magicText, isMagic, canFly, wingType, WING_NAMES, ELEMS, crystalTint,
    get nextId() { return nextId; },
    set nextId(v) { nextId = v; },
  };
})();

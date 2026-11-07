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

  /* ---------- новые волшебные виды: чешуя, зебры, светящиеся узоры, лисы, кости, праздники ---------- */
  const SCALES = [['#2f9e44', 'зелёная'], ['#1c7ed6', 'синяя'], ['#c92a2a', 'красная'], ['#7048e8', 'фиолетовая'], ['#e67700', 'оранжевая'],
    ['#0ca678', 'изумрудная'], ['#495057', 'тёмно-серая'], ['#f2b705', 'золотая'], ['#ae3ec9', 'сиреневая'], ['#1098ad', 'бирюзовая']];
  const ZEBRA = {
    brown: { c: '#6b4423', word: 'коричневые' }, gold: { c: '#e8a400', word: 'золотые' }, beige: { c: '#cdb48a', word: 'бежевые' },
    black: { c: '#1b1b1b', word: 'чёрные' }, grey: { c: '#7d7d7d', word: 'серые' }, rainbow: { c: 'rainbow', word: 'радужные' },
  };
  const GLOWS = [['#39ff14', 'зелёные'], ['#00e5ff', 'голубые'], ['#ff2bd6', 'розовые'], ['#ffea00', 'жёлтые'], ['#b026ff', 'фиолетовые'], ['#ff6a00', 'оранжевые'], ['#ff1744', 'красные']];
  const FOXES = {
    red: { c: '#d9661f', word: 'рыжая' }, fire: { c: '#b8460e', word: 'огненно-рыжая' }, silverblack: { c: '#3b3030', word: 'чёрно-бурая' },
    silver: { c: '#a8a9ad', word: 'серебристая' }, arctic: { c: '#f1eee6', word: 'белая, как песец' }, sand: { c: '#c98b4a', word: 'песочная' },
  };
  const HOLIDAYS = {
    halloween: { word: 'хэллоуинская: тыквы, летучие мыши и привидения', icon: '🎃', body: '#2d2433', mane: '#ff7b00', legs: '#1b1620' },
    newyear: { word: 'новогодняя ёлочка с игрушками', icon: '🎄', body: '#2f7a3a', mane: '#1f5a2a', legs: '#24622f' },
    newyearglow: { word: 'новогодняя светящаяся', icon: '✨', body: '#74c0fc', mane: '#ffffff', legs: '#4dabf7' },
    easter: { word: 'пасхальная: яички, полосочки и точечки', icon: '🥚', body: '#ffb3d1', mane: '#ffffff', legs: '#f783ac' },
  };
  const GLOW_NY = ['#ff6b6b', '#ffd43b', '#69db7c', '#4dabf7', '#cc5de8', '#ff922b', '#f783ac'];
  const COATS = {
    rainbow: { name: 'радужная (переливается)', body: '#e9dcff', mane: '#ffffff', legs: '#d0bfff', rarity: 3 },
    pearl: { name: 'жемчужная', body: '#efe6d8', mane: '#f8f3ea', legs: '#e2d6c3', rarity: 1.6 },
  };
  const pickKey = o => { const k = Object.keys(o); return k[Math.floor(Math.random() * k.length)]; };
  // «random» в описании породы → конкретный цвет или вид
  function resolveMagic(m) {
    if (!m) return m;
    if (m.scales === 'random') m.scales = SCALES[Math.floor(Math.random() * SCALES.length)][0];
    if (m.zebra === 'random') m.zebra = pickKey(ZEBRA);
    if (m.glow === 'random') m.glow = GLOWS[Math.floor(Math.random() * GLOWS.length)][0];
    if (m.fox === 'random') m.fox = pickKey(FOXES);
    if (m.holiday === 'random') m.holiday = pickKey(HOLIDAYS);
    if (m.holiday === 'newyearglow' && !m.tint) m.tint = GLOW_NY[Math.floor(Math.random() * GLOW_NY.length)];
    return m;
  }
  const colorWord = (list, c) => (list.find(t => t[0] === c) || [c, 'переливчатая'])[1];
  function magicLook(h) {
    const m = h.magic || {}, mix = Genetics.mix;
    if (m.holiday && HOLIDAYS[m.holiday]) {
      const D = HOLIDAYS[m.holiday];
      if (m.holiday === 'newyearglow') { const t = m.tint || '#74c0fc'; return { name: D.word, body: t, mane: mix(t, '#ffffff', 0.6), legs: mix(t, '#000000', 0.15), holiday: m.holiday }; }
      return { name: D.word, body: D.body, mane: D.mane, legs: D.legs, holiday: m.holiday };
    }
    if (m.scales) { const c = m.scales; return { name: m.dragonEyes ? 'розовая чешуя, драконьи глаза' : `чешуйчатая, ${colorWord(SCALES, c)}`, body: c, mane: mix(c, '#000000', 0.35), legs: mix(c, '#000000', 0.25), scales: c }; }
    if (m.zebra && ZEBRA[m.zebra]) { const Z = ZEBRA[m.zebra]; return { name: `зебра: ${Z.word} полоски`, body: '#f4f1ea', mane: Z.c === 'rainbow' ? '#cc5de8' : Z.c, legs: '#f4f1ea', zebra: Z.c }; }
    if (m.glow) return { name: `чёрная, светятся ${colorWord(GLOWS, m.glow)} узоры`, body: '#141218', mane: '#0d0c10', legs: '#0d0c10', glow: m.glow };
    if (m.fox && FOXES[m.fox]) { const F = FOXES[m.fox]; return { name: `лисья, ${F.word}`, body: F.c, mane: F.c, legs: m.fox === 'arctic' ? '#d6d0c4' : '#2b2420', fox: F.c }; }
    if (h.coat && COATS[h.coat]) { const C = COATS[h.coat]; return { name: C.name, body: C.body, mane: C.mane, legs: C.legs, coat: h.coat, rarityMul: C.rarity }; }
    return null;
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
      lp: (Math.random() < 0.5 ? a : b).lp || 'blanket',
    };
  }

  function create(o) {
    const breed = o.breed || 'mix';
    const B = Genetics.BREEDS[breed];
    const sex = o.sex || (Math.random() < 0.5 ? 'f' : 'm');
    let coat = o.coat !== undefined ? o.coat : null;
    if (o.coat === undefined && B.coats) for (const [k, p] of Object.entries(B.coats)) if (!coat && Math.random() < p) coat = k;
    let marks = o.marks || randomMarks();
    if (!o.marks && B.marksMaresOnly && sex === 'm') marks = { face: 0, legs: [false, false, false, false] };
    if (!o.marks) marks.lp = Math.random() < 0.5 ? 'full' : 'blanket';
    const g = o.g || Genetics.randomGenotype(breed);
    if (!o.g && B.alwaysSpots && !g.LP[0] && !g.LP[1]) g.LP[0] = true;
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
      g, base, coat,
      train: { speed: 0, jump: 0, dressage: 0, stamina: 0 },
      age: o.age != null ? o.age : rand(3, 12),
      size: o.size || B.size * rand(0.95, 1.05),
      temper: o.temper != null ? o.temper : clamp(B.temper + rand(-0.15, 0.15), 0.05, 0.95),
      marks,
      hunger: 80, energy: 100, mood: 70, clean: 80,
      preg: null,
      magic: o.magic !== undefined ? o.magic : (B.magic ? resolveMagic(Object.assign({}, B.magic, B.magic.elem === 'crystal' ? { tint: crystalTint() } : {})) : null),
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
      coat: [mother.coat, father.coat].filter(Boolean).length && Math.random() < 0.5 ? pick([mother.coat, father.coat].filter(Boolean)) : null,
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
    // новые черты: кости, чешуя (с рогами и глазами), зебра, узоры, лисий мех, праздник
    for (const k of ['bones', 'dhorns']) if ((a[k] || b[k]) && Math.random() < (a[k] && b[k] ? 0.75 : 0.5)) m[k] = true;
    for (const k of ['scales', 'zebra', 'glow', 'fox', 'holiday']) {
      const src = [a, b].filter(x => x[k]);
      if (src.length && Math.random() < (src.length === 2 ? 0.75 : 0.5)) {
        const q = pick(src);
        m[k] = q[k];
        if (k === 'scales' && q.dragonEyes) m.dragonEyes = q.dragonEyes;
        if (k === 'holiday' && q.tint) m.tint = q.tint;
      }
    }
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
    if (m.bones) p.push('череп на голове и рёбра 💀');
    if (m.scales) p.push(m.dragonEyes ? 'розовая драконья чешуя и драконьи глаза 🐉💗' : 'драконья чешуя 🐲');
    if (m.dhorns) p.push('серые драконьи рога');
    if (m.zebra) p.push(`полоски зебры: ${ZEBRA[m.zebra] ? ZEBRA[m.zebra].word : ''} 🦓`);
    if (m.glow) p.push(`светящиеся узоры: ${colorWord(GLOWS, m.glow)} ✨`);
    if (m.fox) p.push('лисий мех и лисий хвост 🦊');
    if (m.holiday && HOLIDAYS[m.holiday]) p.push(`${HOLIDAYS[m.holiday].word} ${HOLIDAYS[m.holiday].icon}`);
    return p.join(', ');
  }
  const isMagic = h => !!(h.magic && (h.magic.wings || h.magic.horn || h.magic.mane || h.magic.elem || h.magic.cloud || h.magic.scales || h.magic.glow || h.magic.fox || h.magic.holiday || h.magic.bones));
  // летать умеют лошади с крыльями и облачные лошадки
  const canFly = h => !!(h && h.magic && (h.magic.wings || h.magic.cloud));

  function pheno(h) {
    const key = Math.floor(h.age * 8);
    if (!h._ph || h._phKey !== key) {
      h._ph = Genetics.phenotype(h.g, h.age);
      const el = elemLook(h) || magicLook(h);
      if (el) {
        const rarity = h._ph.rarity * (el.rarityMul || 1);
        h._ph = Object.assign({}, h._ph, el, { stripe: null, roan: false, tob: false, leo: false, dapple: false, greyLevel: 0, pinkSkin: false, rarity });
      }
      h._phKey = key;
    }
    return h._ph;
  }

  const isAdult = h => h.age >= 3;
  // ездить верхом можно только с 5 лет
  const RIDE_AGE = 5;
  const canRide = h => h.age >= RIDE_AGE;
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
    if (m) p *= (m.wings ? 2 : 1) * (m.horn ? 2 : 1) * (m.mane ? 1.6 : 1) * (m.skeleton ? 1.8 : 1) * (m.elem ? 1.7 : 1) * (m.cloud ? 2 : 1)
      * (m.bones ? 1.8 : 1) * (m.scales ? 1.5 : 1) * (m.dragonEyes ? 3 : 1) * (m.zebra ? 1.4 : 1) * (m.glow ? 1.9 : 1) * (m.fox ? 1.7 : 1) * (m.holiday ? 2 : 1);
    if (h.shoes) p *= 1.05;
    if ((h.mud || 0) > 40) p *= 0.95;
    return Math.max(20, Math.round(p / 5) * 5);
  }

  // глагол в нужном роде: v(h, 'устала', 'устал')
  const v = (h, fem, masc) => (h.sex === 'f' ? fem : masc);

  return {
    SKILLS, v, create, foal, pheno, isAdult, sizeOf, skill, addTrain, ageText, sexText, marksText, price,
    randomName, magicText, isMagic, canFly, wingType, WING_NAMES, ELEMS, crystalTint, canRide, RIDE_AGE,
    ZEBRA, FOXES, HOLIDAYS, GLOW_NY, resolveMagic,
    get nextId() { return nextId; },
    set nextId(v) { nextId = v; },
  };
})();

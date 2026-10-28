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
    });
  }

  function pheno(h) {
    const key = Math.floor(h.age * 8);
    if (!h._ph || h._phKey !== key) {
      h._ph = Genetics.phenotype(h.g, h.age);
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
    return Math.max(20, Math.round(p / 5) * 5);
  }

  // глагол в нужном роде: v(h, 'устала', 'устал')
  const v = (h, fem, masc) => (h.sex === 'f' ? fem : masc);

  return {
    SKILLS, v, create, foal, pheno, isAdult, sizeOf, skill, addTrain, ageText, sexText, marksText, price,
    randomName,
    get nextId() { return nextId; },
    set nextId(v) { nextId = v; },
  };
})();

'use strict';
/*
 * Генетика окрасов лошадей.
 * Упрощённая модель на реальных генах:
 *   E  (Extension)  — есть ли чёрный пигмент: ee = рыжая
 *   A  (Agouti)     — где чёрный пигмент: A_ = гнедая (чёрные только ноги, грива, хвост), aa = вороная
 *   Cr (Cream)      — осветление: 1 копия = соловая / буланая / дымчатая, 2 копии = изабелловая
 *   D  (Dun)        — саврасость: светлое тело и «ремень» вдоль спины
 *   G  (Grey)       — поседение с возрастом (жеребёнок рождается тёмным, потом «в яблоках»)
 *   TO (Tobiano)    — пегость (крупные белые пятна)
 *   LP (Leopard)    — чубарость (пятнистость, как у аппалуз)
 *   Rn (Roan)       — чалость (белые волоски по корпусу)
 *   Z  (Silver)     — серебристость (светлая грива у вороных и гнедых)
 *   F  (Flaxen)     — ff даёт светлую гриву у рыжих
 */
const Genetics = (() => {
  const LOCI = ['E', 'A', 'Cr', 'D', 'G', 'TO', 'LP', 'Rn', 'Z', 'F'];
  // [вариантный (обычно доминантный) аллель, второй аллель]
  const SYMBOLS = {
    E: ['E', 'e'], A: ['A', 'a'], Cr: ['Cr', 'n'], D: ['D', 'nd'], G: ['G', 'g'],
    TO: ['TO', 'n'], LP: ['Lp', 'n'], Rn: ['Rn', 'n'], Z: ['Z', 'n'], F: ['F', 'f'],
  };
  const DEFAULT_FREQ = { E: 0.6, A: 0.5, Cr: 0, D: 0, G: 0, TO: 0, LP: 0, Rn: 0, Z: 0, F: 0.9 };

  // freq — частота «вариантного» аллеля в породе; weight — как часто встречается в диком табуне
  const BREEDS = {
    akhal: {
      name: 'Ахалтекинская', weight: 1, size: 1.0, temper: 0.75, sheen: true,
      freq: { E: 0.65, A: 0.55, Cr: 0.3, G: 0.06 },
      stats: { speed: [75, 95], jump: [45, 70], dressage: [50, 75], stamina: [75, 95] },
    },
    arab: {
      name: 'Арабская', weight: 1.2, size: 0.92, temper: 0.7,
      freq: { E: 0.6, A: 0.6, G: 0.45, Rn: 0.02 },
      stats: { speed: [70, 90], jump: [40, 65], dressage: [55, 75], stamina: [85, 100] },
    },
    orlov: {
      name: 'Орловский рысак', weight: 1.2, size: 1.05, temper: 0.5,
      freq: { E: 0.85, A: 0.45, G: 0.45 },
      stats: { speed: [70, 92], jump: [40, 60], dressage: [45, 70], stamina: [70, 90] },
    },
    friesian: {
      name: 'Фризская', weight: 0.8, size: 1.1, temper: 0.3, feather: true, longMane: true,
      freq: { E: 1, A: 0 },
      stats: { speed: [50, 70], jump: [40, 60], dressage: [75, 95], stamina: [60, 80] },
    },
    haflinger: {
      name: 'Хафлингер', weight: 1, size: 0.88, temper: 0.25,
      freq: { E: 0, A: 0.5, F: 0 },
      stats: { speed: [45, 65], jump: [45, 65], dressage: [50, 70], stamina: [70, 90] },
    },
    appaloosa: {
      name: 'Аппалуза', weight: 1, size: 0.97, temper: 0.5,
      freq: { E: 0.6, A: 0.5, Cr: 0.05, D: 0.05, G: 0.03, LP: 0.55, Rn: 0.05 },
      stats: { speed: [60, 80], jump: [50, 70], dressage: [45, 70], stamina: [70, 90] },
    },
    paint: {
      name: 'Пейнтхорс', weight: 1, size: 0.97, temper: 0.45,
      freq: { E: 0.55, A: 0.5, Cr: 0.08, D: 0.04, G: 0.03, TO: 0.5, Rn: 0.04 },
      stats: { speed: [60, 82], jump: [45, 70], dressage: [45, 70], stamina: [65, 85] },
    },
    trakehner: {
      name: 'Тракененская', weight: 1, size: 1.05, temper: 0.55,
      freq: { E: 0.75, A: 0.6, G: 0.1 },
      stats: { speed: [60, 80], jump: [70, 95], dressage: [70, 92], stamina: [60, 80] },
    },
    budyonny: {
      name: 'Будённовская', weight: 1, size: 1.03, temper: 0.5, sheen: true,
      freq: { E: 0.15, A: 0.6, F: 0.8 },
      stats: { speed: [65, 85], jump: [65, 88], dressage: [55, 80], stamina: [70, 90] },
    },
    fjord: {
      name: 'Норвежский фьорд', weight: 0.8, size: 0.85, temper: 0.2, fjordMane: true,
      freq: { E: 0.55, A: 0.8, Cr: 0.18, D: 1 },
      stats: { speed: [40, 60], jump: [40, 60], dressage: [45, 65], stamina: [75, 95] },
    },
    shetland: {
      name: 'Шетлендский пони', weight: 0.9, size: 0.62, temper: 0.45,
      freq: { E: 0.65, A: 0.5, Cr: 0.06, D: 0.04, G: 0.06, TO: 0.25, Rn: 0.06, Z: 0.2 },
      stats: { speed: [30, 50], jump: [40, 65], dressage: [35, 55], stamina: [60, 85] },
    },
    mix: {
      name: 'Помесь', weight: 0, size: 1, temper: 0.5,
      freq: {},
      stats: { speed: [45, 75], jump: [45, 75], dressage: [45, 75], stamina: [45, 75] },
    },
  };

  /* ---------- цвета ---------- */
  function hexToRgb(h) {
    const n = parseInt(h.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function rgbToHex(r, g, b) {
    return '#' + [r, g, b].map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
  }
  function mix(a, b, t) {
    const A = hexToRgb(a), B = hexToRgb(b);
    return rgbToHex(A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t);
  }

  /* ---------- генотип ---------- */
  function randomGenotype(breed) {
    const f = Object.assign({}, DEFAULT_FREQ, (BREEDS[breed] || BREEDS.mix).freq);
    const g = {};
    for (const l of LOCI) g[l] = [Math.random() < f[l], Math.random() < f[l]];
    return g;
  }

  // каждый родитель передаёт жеребёнку один случайный аллель из пары
  function inherit(mother, father) {
    const g = {};
    for (const l of LOCI) {
      g[l] = [mother[l][Math.random() < 0.5 ? 0 : 1], father[l][Math.random() < 0.5 ? 0 : 1]];
    }
    return g;
  }

  // текст вида «Ee aa Cr/n» — показываем только интересные гены
  function genotypeText(g) {
    return LOCI.filter(l => {
      if (l === 'E' || l === 'A') return true;
      if (l === 'F') return !(g.F[0] && g.F[1]);
      return g[l][0] || g[l][1];
    }).map(l => {
      const s = SYMBOLS[l];
      const a = [g[l][0], g[l][1]].sort((x, y) => y - x).map(v => (v ? s[0] : s[1]));
      return (l === 'E' || l === 'A' || l === 'G' || l === 'F') ? a.join('') : a.join('/');
    }).join(' ');
  }

  /* ---------- фенотип: как лошадь выглядит и как называется её окрас ---------- */
  function phenotype(g, age) {
    const has = l => g[l][0] || g[l][1];
    const cnt = l => (g[l][0] ? 1 : 0) + (g[l][1] ? 1 : 0);
    const base = !has('E') ? 'ch' : has('A') ? 'bay' : 'bl';
    const cr = cnt('Cr');
    const dun = has('D');
    const silver = has('Z') && base !== 'ch' && cr < 2;
    const flaxen = base === 'ch' && !has('F');
    let body, mane, legs, word, suffix = '', rarity = 1, stripe = null, pinkSkin = false;

    if (cr === 2) {
      word = 'изабелловая';
      body = base === 'ch' ? '#f3e9d2' : base === 'bay' ? '#eedcbc' : '#e6d8be';
      mane = base === 'bay' ? '#d9bb98' : base === 'bl' ? '#cdb89c' : '#f7f1e3';
      legs = base === 'ch' ? body : mix(body, mane, 0.6);
      rarity = 1.5; pinkSkin = true;
    } else if (cr === 1) {
      if (base === 'ch') { word = 'соловая'; body = '#ddae55'; mane = '#f6eed8'; legs = body; }
      else if (base === 'bay') { word = 'буланая'; body = '#d4aa68'; mane = '#231a14'; legs = '#2a1f18'; }
      else { word = 'дымчато-вороная'; body = '#3f342c'; mane = '#1d1816'; legs = '#1d1816'; }
      rarity = 1.3;
    } else {
      if (base === 'ch') { word = 'рыжая'; body = '#a3532b'; mane = flaxen ? '#efdcaa' : '#87401f'; legs = body; }
      else if (base === 'bay') { word = 'гнедая'; body = '#7b4423'; mane = '#1e1611'; legs = '#1e1611'; }
      else { word = 'вороная'; body = '#232020'; mane = '#151313'; legs = '#151313'; rarity = 1.1; }
    }

    if (dun && cr < 2) {
      stripe = base === 'ch' ? '#7a3c1c' : '#2a211b';
      if (cr === 0) {
        if (base === 'ch') { word = 'рыже-саврасая'; body = '#cc9562'; mane = flaxen ? '#efdcaa' : '#8b4a26'; legs = '#a8703f'; }
        else if (base === 'bay') { word = 'саврасая'; body = '#c6a26b'; legs = '#2a211b'; }
        else { word = 'мышастая'; body = '#8b8174'; legs = '#2c2622'; rarity = 1.35; }
      } else {
        suffix = ' с ремнём';
        body = mix(body, '#f2e2c0', 0.25);
      }
      rarity *= 1.15;
    }

    if (silver) {
      word = cr === 1 ? (base === 'bl' ? 'серебристо-дымчатая' : 'серебристо-буланая') : 'серебристо-' + word;
      if (base === 'bl') { body = mix(body, '#6e5240', 0.85); legs = mix(legs, '#5a4535', 0.7); }
      else legs = mix(legs, '#6a4a35', 0.7);
      mane = '#ece3d1';
      rarity *= 1.4;
    }

    if (flaxen && cr === 0 && !dun) { suffix = ' со светлой гривой'; rarity *= 1.1; }

    // поседение: жеребята рождаются цветными и светлеют с возрастом
    let greyLevel = 0, dapple = false;
    if (has('G')) {
      greyLevel = Math.max(0, Math.min(1, (age - 0.5) / 4));
      body = mix(body, '#c9c9c7', greyLevel * 0.95);
      mane = mix(mane, '#e2e2e0', greyLevel);
      legs = mix(legs, '#a6a6a4', greyLevel * 0.9);
      dapple = greyLevel > 0.3 && greyLevel < 0.97;
      if (greyLevel >= 0.6) { word = 'серая'; suffix = greyLevel < 0.97 ? ' в яблоках' : ''; }
      else suffix += greyLevel > 0 ? ' (седеет)' : ' (поседеет)';
      rarity *= 1.05;
    }

    const roan = has('Rn'), tob = has('TO'), leo = has('LP');
    const patterns = [];
    if (tob) { patterns.push('пегая'); rarity *= 1.3; }
    if (leo) { patterns.push('чубарая'); rarity *= 1.5; }
    if (roan) { patterns.push('чалая'); rarity *= 1.2; }

    let name;
    if (patterns.length) {
      name = word.replace(/ая$/, 'о') + '-' + patterns[0];
      if (patterns.length > 1) name += ', ' + patterns.slice(1).join(', ');
      name += suffix;
    } else {
      name = word + suffix;
    }

    return { name, body, mane, legs, stripe, roan, tob, leo, greyLevel, dapple, pinkSkin, rarity };
  }

  // вероятные окрасы жеребёнка (метод Монте-Карло)
  function predict(gm, gf, n = 800) {
    const counts = {};
    for (let i = 0; i < n; i++) {
      const name = phenotype(inherit(gm, gf), 6).name;
      counts[name] = (counts[name] || 0) + 1;
    }
    return Object.entries(counts)
      .map(([name, c]) => ({ name, pct: Math.round((c / n) * 100) }))
      .filter(x => x.pct > 0)
      .sort((a, b) => b.pct - a.pct)
      .slice(0, 7);
  }

  return { LOCI, BREEDS, randomGenotype, inherit, phenotype, genotypeText, predict, mix };
})();

'use strict';
/*
 * Воксельная графика (3D из кубиков) на Three.js — единственный вид игры.
 * 1 единица Three.js = 10 пикселей мира, ось Z сцены = ось Y карты.
 */
const Voxel = (() => {
  const K = 0.1;        // пиксели мира → единицы сцены
  const V = 0.45;       // размер вокселя лошади
  let T = null;         // THREE
  let ready = false, loading = null;
  let renderer, scene, camera, hemi, sun, canvas3d, mat, glowMat, ghostMat;
  let lampMat, lampLights = [], playerLight, torches = [];
  let dynamic = {};     // группы, которые пересобираются при смене состояния
  const objs = new Map();
  let ring, letterRing, rope, preview, mound;
  const cam = { x: 0, z: 0, init: false, zoom: 1, h: 1 };
  let sparkles = null, windmills = [];

  /* ---------- загрузка библиотеки ---------- */
  function load() {
    if (ready) return Promise.resolve(true);
    if (loading) return loading;
    loading = ThreeLoader.load().then(ok => {
      if (ok) { try { init(); } catch (e) { console.error(e); ok = false; } }
      if (!ok) loading = null;
      return ok;
    });
    return loading;
  }

  /* ---------- геометрия из кубиков ---------- */
  const FACES = [
    { n: [1, 0, 0], c: [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]], s: 0.82 },
    { n: [-1, 0, 0], c: [[0, 0, 1], [0, 1, 1], [0, 1, 0], [0, 0, 0]], s: 0.82 },
    { n: [0, 1, 0], c: [[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]], s: 1 },
    { n: [0, -1, 0], c: [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]], s: 0.55 },
    { n: [0, 0, 1], c: [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]], s: 0.72 },
    { n: [0, 0, -1], c: [[1, 0, 0], [0, 0, 0], [0, 1, 0], [1, 1, 0]], s: 0.9 },
  ];
  const colorCache = new Map();
  function rgb(hex) {
    let c = colorCache.get(hex);
    if (!c) { c = new T.Color(hex); colorCache.set(hex, c); }
    return c;
  }

  // cells: Map 'x|y|z' → цвет; рисуем только видимые грани
  function voxelGeometry(cells, size, jitterSeed = 1) {
    const pos = [], nor = [], col = [], idx = [];
    const rnd = World.rng(jitterSeed);
    for (const [key, hex] of cells) {
      const [x, y, z] = key.split('|').map(Number);
      const c = rgb(hex), j = 0.94 + rnd() * 0.1;
      for (const f of FACES) {
        if (cells.has(`${x + f.n[0]}|${y + f.n[1]}|${z + f.n[2]}`)) continue;
        const base = pos.length / 3;
        for (const v of f.c) {
          pos.push((x + v[0]) * size, (y + v[1]) * size, (z + v[2]) * size);
          nor.push(f.n[0], f.n[1], f.n[2]);
          col.push(c.r * f.s * j, c.g * f.s * j, c.b * f.s * j);
        }
        idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
      }
    }
    const g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(pos, 3));
    g.setAttribute('normal', new T.Float32BufferAttribute(nor, 3));
    g.setAttribute('color', new T.Float32BufferAttribute(col, 3));
    g.setIndex(idx);
    return g;
  }

  // список коробок {x,y,z (центр), sx,sy,sz, c, rx,ry,rz} → одна геометрия
  function boxGeometry(list) {
    const pos = [], nor = [], col = [];
    const m = new T.Matrix4(), q = new T.Quaternion(), e = new T.Euler(), one = new T.Vector3(1, 1, 1), p = new T.Vector3();
    for (const b of list) {
      const g = new T.BoxGeometry(b.sx, b.sy, b.sz).toNonIndexed();
      e.set(b.rx || 0, b.ry || 0, b.rz || 0);
      q.setFromEuler(e);
      p.set(b.x, b.y, b.z);
      m.compose(p, q, one);
      g.applyMatrix4(m);
      const c = rgb(b.c);
      const P = g.attributes.position.array, N = g.attributes.normal.array;
      for (let i = 0; i < P.length; i += 3) {
        pos.push(P[i], P[i + 1], P[i + 2]);
        nor.push(N[i], N[i + 1], N[i + 2]);
        const sh = N[i + 1] > 0.5 ? 1 : N[i + 1] < -0.5 ? 0.55 : 0.8;
        col.push(c.r * sh, c.g * sh, c.b * sh);
      }
      g.dispose();
    }
    const g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(pos, 3));
    g.setAttribute('normal', new T.Float32BufferAttribute(nor, 3));
    g.setAttribute('color', new T.Float32BufferAttribute(col, 3));
    return g;
  }
  function meshOf(geo, shadow = true) {
    const m = new T.Mesh(geo, mat);
    m.castShadow = shadow;
    m.receiveShadow = true;
    return m;
  }
  const box = (x, y, z, sx, sy, sz, c, r = {}) => Object.assign({ x, y, z, sx, sy, sz, c }, r);

  function glowMesh(geo) { const m = new T.Mesh(geo, glowMat); m.castShadow = false; return m; }

  /* ---------- модели ---------- */
  const key3 = (x, y, z) => `${x}|${y}|${z}`;
  const WHITE = '#f6f3ec';
  const BONE = '#ece6d6', BONE2 = '#cfc6b0';
  const FIRE = ['#ff3d00', '#ff6d00', '#ff9100', '#ffc400', '#ffea00'];
  const ICE = ['#a5f3fc', '#cffafe', '#67e8f9', '#e0f2fe', '#bae6fd'];

  // цвет гривы/хвоста: краска, огонь, лёд или натуральный
  function hairColor(h, ph, B, i, mag) {
    if (h.maneDye) {
      const d = Items.DYES[h.maneDye];
      return { c: d.color === 'rainbow' ? Items.RAINBOW[i % Items.RAINBOW.length] : d.color, glow: false };
    }
    const E = ph.elem && Horses.ELEMS[ph.elem];
    if (E) {
      if (ph.elem === 'crystal') { const t = ph.tint; return { c: [Genetics.mix(t, '#ffffff', 0.55), t, Genetics.mix(t, '#ffffff', 0.25)][i % 3], glow: true }; }
      if (E.maneCols) return { c: E.maneCols[(i * 3) % E.maneCols.length], glow: !!E.maneGlow };
    }
    if (mag.mane === 'fire') return { c: FIRE[(i * 7) % FIRE.length], glow: true };
    if (mag.mane === 'ice') return { c: ICE[(i * 5) % ICE.length], glow: true };
    if (mag.skeleton) return { c: '#9fe6a0', glow: true };
    return { c: B.fjordMane ? '#efe4cf' : ph.mane, glow: false };
  }

  // узор стихийной лошадки: цвет кубика корпуса/шеи/головы
  const RAINBOW7 = ['#ff6b6b', '#ff922b', '#ffd43b', '#51cf66', '#4dabf7', '#5c7cfa', '#cc5de8'];
  function elemColor(ph, x, y, z, part, rnd) {
    const e = ph.elem, mix = Genetics.mix;
    switch (e) {
      case 'ice': return rnd() < 0.18 ? '#e7f5ff' : y >= 12 || part === 'head' ? '#a5d8ff' : rnd() < 0.5 ? '#74c0fc' : '#4dabf7';
      case 'crystal': { const t = ph.tint, f = ((x + y * 2 + z * 3) % 3 + 3) % 3; return f === 0 ? mix(t, '#ffffff', 0.45) : f === 1 ? t : mix(t, '#000000', 0.18); }
      case 'fire': return y >= 12 ? (rnd() < 0.5 ? '#ffd43b' : '#fcc419') : y >= 10 ? (rnd() < 0.5 ? '#ff922b' : '#fd7e14') : (rnd() < 0.5 ? '#f03e3e' : '#e8590c');
      case 'water': { const band = Math.floor(y + Math.sin(x * 0.7 + z) * 1.4); const k = ((band % 3) + 3) % 3; return k === 0 ? '#1c7ed6' : k === 1 ? '#74c0fc' : (rnd() < 0.5 ? '#f1f8ff' : '#a5d8ff'); }
      case 'rainbow': return RAINBOW7[((Math.floor((x + 8) / 2.3) % 7) + 7) % 7];
      case 'sun': return y >= 12 ? '#ffe066' : y >= 10 ? (rnd() < 0.6 ? '#fcc419' : '#ffd43b') : (rnd() < 0.5 ? '#f59f00' : '#ff922b');
      case 'sand': return rnd() < 0.25 ? '#d4b67a' : rnd() < 0.2 ? '#f4e4bc' : '#e9d3a1';
      case 'stone': {
        if (y >= 12 && rnd() < 0.12) return '#5c940d';                                   // мох на спине
        const b = Math.abs((Math.floor(x / 2) * 7 + Math.floor(y / 2) * 13 + Math.floor(z / 2) * 5) % 4);
        if ((x + 64) % 4 === 0 && rnd() < 0.5) return '#495057';                          // трещины
        return ['#868e96', '#adb5bd', '#6c757d', '#909296'][b];
      }
      case 'mushroom': return y >= 11 && part === 'barrel' ? ((x + z + 40) % 3 === 0 && y === 12 ? '#ffffff' : '#e03131') : rnd() < 0.15 ? '#e8d9b5' : '#f1e3c6';
      case 'leaf': { const v = (x * 3 + y * 5 + z * 7 + 100) % 6; return v === 0 ? '#2b8a3e' : v === 1 ? '#8ce99a' : rnd() < 0.06 ? '#fab005' : rnd() < 0.5 ? '#40c057' : '#37b24d'; }
      case 'damp': {
        const sw = Math.sin(x * 0.85 + z * 1.4) * Math.cos(y * 1.2 - x * 0.35);
        if (sw > 0.62 || (part === 'head' && y === 16 && x === 11)) return '#f8f9fa';        // белые узоры
        return rnd() < 0.3 ? '#3b4a59' : '#4a5a6a';
      }
    }
    return ph.body;
  }

  function horseCells(h, ph, B) {
    const rnd = World.rng(h.seed);
    const mag = h.magic || {};
    const cells = new Map(), glow = new Map();
    const put = (x, y, z, c) => cells.set(key3(x, y, z), c);
    const neck = [[7, 11, 14, -2, 1], [8, 12, 15, -1, 0], [9, 13, 16, -1, 0], [10, 14, 16, -1, 0]];
    if (mag.skeleton) {
      // позвоночник, рёбра, таз, череп — кости с просветами
      for (let x = -8; x <= 7; x++) { put(x, 12, -1, BONE); put(x, 12, 0, BONE); }
      for (let x = -4; x <= 5; x += 2) for (let y = 8; y <= 11; y++) for (let z = -3; z <= 2; z++) {
        if (z === -3 || z === 2 || y === 8) put(x, y, z, y === 8 ? BONE2 : BONE);
      }
      for (let x = -8; x <= -6; x++) for (let y = 10; y <= 12; y++) for (let z = -3; z <= 2; z++) put(x, y, z, BONE2);
      for (let x = 5; x <= 7; x++) for (let y = 9; y <= 12; y++) for (let z = -2; z <= 1; z++) if ((x + y) % 2) put(x, y, z, BONE);
      for (const [x, y0, y1] of neck) for (let y = y0; y <= y1; y += 2) { put(x, y, -1, BONE); put(x, y, 0, BONE); }
      for (let x = 11; x <= 15; x++) for (let y = 14; y <= 16; y++) for (let z = -1; z <= 0; z++) if (!(x >= 14 && y === 16)) put(x, y, z, BONE);
      put(12, 16, -2, '#111111'); put(12, 16, 1, '#111111');
      glow.set(key3(12, 16, -3), '#7dff8a'); glow.set(key3(12, 16, 2), '#7dff8a');
      put(11, 17, -1, BONE); put(11, 17, 1, BONE);
      return { cells, glow };
    }
    const blobs = ph.tob ? Array.from({ length: 3 + Math.floor(rnd() * 2) }, () => ({
      x: -7 + rnd() * 15, y: 8 + rnd() * 6, z: -2 + rnd() * 4, r: 2.4 + rnd() * 2,
    })) : [];
    const spot = ph.greyLevel > 0.6 ? '#3a3a3a' : Genetics.mix(ph.body, '#000000', 0.2);
    const bodyCol = (x, y, z, part, top) => {
      if (ph.elem) return elemColor(ph, x, y, z, part, rnd);
      if (blobs.some(b => (x - b.x) ** 2 + ((y - b.y) * 0.8) ** 2 + ((z - b.z) * 0.6) ** 2 < b.r * b.r)) return WHITE;
      if (ph.leo && part === 'barrel' && x <= 0 && y >= 9) return rnd() < 0.2 ? spot : WHITE;
      let c = ph.body;
      if (ph.stripe && top && z >= -1 && z <= 0) c = ph.stripe;
      if (ph.roan && part !== 'head' && rnd() < 0.35) c = Genetics.mix(c, '#ffffff', 0.45);
      if (ph.dapple && rnd() < 0.25) c = Genetics.mix(c, '#ffffff', 0.35);
      return c;
    };
    // корпус
    for (let x = -8; x <= 7; x++) for (let y = 7; y <= 12; y++) for (let z = -3; z <= 2; z++) {
      const edges = (x === -8 || x === 7) + (y === 7 || y === 12) + (z === -3 || z === 2);
      if (edges >= 2) continue;
      put(x, y, z, bodyCol(x, y, z, 'barrel', y === 12 || (y === 11 && (z === -3 || z === 2))));
    }
    // шея
    for (const [x, y0, y1, z0, z1] of neck) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) put(x, y, z, bodyCol(x, y, z, 'neck', false));
    // голова и морда
    for (let x = 11; x <= 13; x++) for (let y = 14; y <= 16; y++) for (let z = -1; z <= 0; z++) put(x, y, z, bodyCol(x, y, z, 'head', false));
    const muzzle = (ph.pinkSkin || h.marks.face === 3) ? '#d9a597' : Genetics.mix(ph.body, '#000000', 0.35);
    for (let x = 14; x <= 15; x++) for (let y = 14; y <= 15; y++) for (let z = -1; z <= 0; z++) put(x, y, z, muzzle);
    // отметины на лбу (видны сверху)
    if (h.marks.face) {
      const len = h.marks.face === 1 ? [11, 11] : [11, 13];
      for (let x = len[0]; x <= len[1]; x++) for (let z = -1; z <= 0; z++) put(x, 16, z, WHITE);
      if (h.marks.face === 3) for (let x = 11; x <= 13; x++) for (let y = 14; y <= 15; y++) { put(x, y, -1, WHITE); put(x, y, 0, WHITE); }
    }
    put(12, 16, -2, '#1a1412'); put(12, 16, 1, '#1a1412');               // глаза
    const ear = Genetics.mix(ph.body, '#000000', 0.2);
    put(11, 17, -1, ear); put(11, 17, 1, ear);                              // уши
    // грива: причёска и цвет
    const style = h.maneStyle || 'normal';
    let i = 0;
    const hair = (x, y, z) => {
      const hc = hairColor(h, ph, B, i++, mag);
      if (hc.glow) glow.set(key3(x, y, z), hc.c); else put(x, y, z, hc.c);
    };
    for (const [x, , y1] of neck) {
      if (style === 'short' && x === 7) continue;
      hair(x, y1 + 1, -1);
      if (B.fjordMane && !h.maneDye && !mag.mane) put(x, y1 + 1, 0, '#2a211b'); else hair(x, y1 + 1, 0);
      if (style === 'mohawk' || (mag.mane && style === 'normal')) { hair(x, y1 + 2, -1); hair(x, y1 + 2, 0); if (style === 'mohawk') hair(x, y1 + 3, 0); }
      if (style === 'long' || (B.longMane && style === 'normal')) for (let y = y1 - 3; y <= y1; y++) hair(x, y, 1 + (x === 7 ? 1 : 0));
      if (style === 'braids' && (x === 7 || x === 9)) {
        for (let y = y1 - 3; y <= y1; y++) hair(x, y, 1 + (x === 7 ? 1 : 0));
        put(x, y1 - 4, 1 + (x === 7 ? 1 : 0), '#ff6fae');
      }
      if (style === 'bows' && (x === 8 || x === 10)) { put(x, y1 + 2, -1, '#ff6fae'); put(x, y1 + 2, 0, '#ff6fae'); put(x, y1 + 2, -2, '#ff8fc7'); put(x, y1 + 2, 1, '#ff8fc7'); }
    }
    hair(11, 17, 0);                                                        // чёлка
    if (style === 'bows') put(11, 18, 0, '#ff6fae');
    // рог единорога
    if (mag.horn) {
      glow.set(key3(12, 17, -1), '#fff3bf'); glow.set(key3(12, 17, 0), '#fff3bf');
      glow.set(key3(12, 18, 0), '#ffe066'); glow.set(key3(13, 19, 0), '#ffd43b'); glow.set(key3(13, 20, 0), '#fff9db');
    }
    // украшения стихий на спине
    if (ph.elem === 'crystal') {
      const lt = Genetics.mix(ph.tint, '#ffffff', 0.5);
      for (const x of [-6, -2, 2]) { glow.set(key3(x, 13, -1), lt); glow.set(key3(x, 14, -1), ph.tint); glow.set(key3(x + 1, 13, 0), lt); }
    } else if (ph.elem === 'mushroom') {
      for (const [x, z, c] of [[-5, -2, '#e03131'], [-1, 1, '#f08c00'], [3, -1, '#e03131']]) {
        put(x, 13, z, '#f8f4ea');
        for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) put(x + dx, 14, z + dz, c);
        put(x, 15, z, c); put(x + 1, 14, z + 1, '#ffffff');
      }
    } else if (ph.elem === 'leaf') {
      for (const [x, z] of [[-6, 0], [-3, -2], [0, 1], [4, -1]]) { put(x, 13, z, '#2f9e44'); put(x + 1, 13, z, '#69db7c'); put(x, 14, z, '#51cf66'); }
    } else if (ph.elem === 'sun') {
      for (const [x, y] of [[10, 18], [12, 19], [14, 18]]) glow.set(key3(x, y, -1), '#ffe066');      // солнечная корона
    } else if (ph.elem === 'ice') {
      for (const x of [-5, -1, 3]) glow.set(key3(x, 13, -1), '#e7f5ff');
    }
    return { cells, glow };
  }

  // грязь: уровень 0–4 — до какой высоты ноги в грязи
  const MUD = ['#5a3d22', '#6b4a2b', '#4a321c', '#7a5634'];
  const mudLevel = h => Math.min(4, Math.floor((h.mud || 0) / 22));
  function legCells(h, ph, i) {
    const cells = new Map();
    const mag = h.magic || {};
    const white = h.marks.legs[i] || ph.tob;
    const ml = mudLevel(h), rnd = World.rng(h.seed + i * 31);
    const muddy = (c, y) => (ml && y <= -7 + ml + 1 && (y < -7 + ml + 1 || rnd() < 0.6) ? MUD[Math.floor(rnd() * MUD.length)] : c);
    for (let y = -7; y <= -1; y++) for (let x = -1; x <= 0; x++) for (let z = -1; z <= 0; z++) {
      if (mag.skeleton) {
        if (x === 0 && z === 0 || y === -4 || y === -7) cells.set(key3(x, y, z), y === -7 ? '#8d8476' : y === -4 ? BONE2 : BONE);
        continue;
      }
      let c = y >= -2 ? ph.body : ph.legs;
      if (ph.elem) {
        c = ph.elem === 'rainbow' ? RAINBOW7[(i * 2 + (y + 7)) % 7] : ph.elem === 'crystal' || ph.elem === 'stone' || ph.elem === 'water' || ph.elem === 'fire' || ph.elem === 'leaf' || ph.elem === 'damp'
          ? elemColor(ph, x + i * 3, y + 7, z, 'leg', rnd) : y >= -2 ? ph.body : ph.legs;
        if (ph.elem === 'leaf' && y <= -3) c = '#5c3d1e';
        if (y === -7) c = ph.elem === 'ice' ? '#d0ebff' : ph.elem === 'sun' ? '#f08c00' : ph.elem === 'crystal' ? Genetics.mix(ph.tint, '#000000', 0.35) : '#2b2420';
      } else {
        if (ph.tob && y < -2) c = WHITE;
        else if (white && y <= -4) c = WHITE;
        if (y === -7) c = '#2b2420';
      }
      cells.set(key3(x, y, z), muddy(c, y));
    }
    return cells;
  }

  function tailCells(h, ph, B) {
    const cells = new Map(), glow = new Map();
    const mag = h.magic || {};
    const pts = [[-1, -1], [-1, -2], [-2, -2], [-2, -3], [-2, -4], [-3, -4], [-3, -5], [-3, -6], [-3, -7]];
    pts.forEach(([x, y], i) => {
      for (const z of [-1, 0]) {
        if (mag.skeleton) { if (i % 2 === 0 && z === 0) cells.set(key3(x, y, z), BONE); continue; }
        const hc = hairColor(h, ph, B, i * 2 + z + 1, mag);
        (hc.glow ? glow : cells).set(key3(x, y, z), hc.c);
      }
    });
    return { cells, glow };
  }

  // крылья разных видов: z — наружу от тела, x — вдоль тела
  const pickBy = (h, arr, k = 0) => arr[(h.seed + k) % arr.length];
  function wingDef(type, h, ph) {
    const cells = new Map();
    const set = (x, z, c) => cells.set(key3(x, 0, z), c);
    if (type === 'raven') {
      // крыло ворона по форме, но не чёрное
      const base = pickBy(h, ['#8d99ae', '#a68a64', '#6c8ebf', '#9c6ade', '#5fa8a0', '#c97b63', '#d4a373']);
      const light = Genetics.mix(base, '#ffffff', 0.35), dark = Genetics.mix(base, '#000000', 0.25);
      for (let z = 0; z < 11; z++) {
        const len = 7 - Math.floor(z * 0.35) + (z > 6 ? 2 : 0);
        for (let x = -len; x <= 1; x++) {
          if (z >= 7 && x < -3 && (x + z) % 2) continue;                 // «пальцы» маховых перьев
          set(x, z, z < 3 ? light : x < -len + 2 ? dark : base);
        }
      }
      return { cells, glass: false };
    }
    if (type === 'butterfly') {
      const pal = pickBy(h, [['#ff8c1a', '#ffd166'], ['#3a86ff', '#90e0ef'], ['#ff7eb6', '#ffd6e8'], ['#ffd60a', '#fff3b0'], ['#9b5de5', '#f15bb5']]);
      const inside = (x, z) => ((x - 2.5) / 4) ** 2 + ((z - 4.5) / 4.6) ** 2 < 1 || ((x + 3.5) / 3.2) ** 2 + ((z - 3) / 3.6) ** 2 < 1;
      for (let x = -7; x <= 7; x++) for (let z = 0; z <= 9; z++) {
        if (!inside(x, z)) continue;
        const edge = !inside(x + 1, z) || !inside(x - 1, z) || !inside(x, z + 1) || !inside(x, z - 1);
        let c = edge ? '#1b1b1b' : (x + z) % 4 === 0 ? Genetics.mix(pal[0], '#000000', 0.25) : (z > 5 ? pal[1] : pal[0]);
        if (!edge && (x === 3 && z === 6 || x === 1 && z === 7 || x === -3 && z === 4)) c = '#ffffff';
        set(x, z, c);
      }
      return { cells, glass: false };
    }
    if (type === 'dragon') {
      const mem = pickBy(h, ['#8b1e3f', '#2d6a4f', '#5a189a', '#b5651d', '#264653']);
      const bone = '#3d2b1f';
      for (let z = 0; z <= 11; z++) {
        const minX = -Math.round(z * 0.75) - 1;
        for (let x = minX; x <= 1; x++) {
          if (x === minX && z % 3 === 1) continue;                        // зубчатый край перепонки
          const isBone = x === 1 || (z > 2 && (x === Math.round(-z * 0.25) || x === Math.round(-z * 0.5)));
          set(x, z, isBone ? bone : Genetics.mix(mem, '#000000', (z % 3) * 0.06));
        }
      }
      set(2, 11, bone); set(2, 10, bone);
      return { cells, glass: false };
    }
    if (type === 'dragonfly') {
      const tint = pickBy(h, ['#bde0fe', '#caffbf', '#ffd6ff', '#fdffb6']);
      for (let z = 0; z <= 10; z++) for (let x = 0; x <= 2; x++) if (!(z === 10 && x !== 1)) set(x, z, z % 3 === 0 ? '#adb5bd' : tint);
      for (let z = 0; z <= 9; z++) for (let x = -4; x <= -2; x++) if (!(z === 9 && x !== -3)) set(x, z, z % 3 === 0 ? '#adb5bd' : tint);
      return { cells, glass: true };
    }
    if (type === 'bee') {
      for (let x = -3; x <= 2; x++) for (let z = 0; z <= 5; z++) if (((x + 0.5) / 3) ** 2 + ((z - 2.5) / 3) ** 2 < 1) set(x, z, z % 2 ? '#e7f5ff' : '#f8f9fa');
      return { cells, glass: true };
    }
    return { cells: wingCells(h, ph), glass: false };
  }
  const FLAP = {
    pegasus: { speed: 9, amp: 0.7, rest: -0.9 }, raven: { speed: 8, amp: 0.75, rest: -0.9 },
    butterfly: { speed: 5, amp: 0.9, rest: -1.2 }, dragon: { speed: 4.5, amp: 0.8, rest: -0.6 },
    dragonfly: { speed: 32, amp: 0.22, rest: -0.05 }, bee: { speed: 42, amp: 0.3, rest: -0.2 },
  };
  let glassMat = null;

  // крыло пегаса: перья веером вбок и назад
  function wingCells(h, ph) {
    const cells = new Map();
    const c1 = Genetics.mix(ph.body, '#ffffff', 0.65), c2 = Genetics.mix(ph.body, '#ffffff', 0.85);
    for (let z = 0; z < 8; z++) {
      const len = 6 - Math.floor(z * 0.6);
      for (let x = -len; x <= 1; x++) cells.set(key3(x, 0, z), (x + z) % 3 ? c1 : c2);
    }
    return cells;
  }

  function riderCells(R) {
    const cells = new Map();
    const put = (x, y, z, c) => cells.set(key3(x, y, z), c);
    const fill = (x0, x1, y0, y1, z0, z1, c) => { for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) put(x, y, z, c); };
    const glow = new Map();
    const gl = (x, y, z, c) => glow.set(key3(x, y, z), c);
    const sc = R.saddleColor || '#5b3a1e', bc = R.bridleColor || '#2b1a10';
    fill(-4, 1, 13, 13, -4, 3, R.pad);            // вальтрап
    fill(-3, 0, 14, 14, -2, 1, sc);               // седло
    fill(-4, -4, 14, 15, -2, 1, sc);
    put(1, 14, -1, sc); put(1, 14, 0, sc);        // лука седла
    // уздечка: нащёчные ремни, капсюль, поводья к рукам
    for (let x = 12; x <= 14; x++) { put(x, 15, -2, bc); put(x, 15, 1, bc); }
    put(14, 14, -2, bc); put(14, 14, 1, bc); put(15, 16, -1, bc); put(15, 16, 0, bc);
    for (let x = 4; x <= 11; x++) { const y = 17 - Math.round((x - 4) / 4); put(x, y, -3, bc); put(x, y, 2, bc); }
    const st = R.saddleStyle || 'classic', bs = R.bridleStyle || 'classic';
    if (st === 'crystal') {
      for (const [x, y, z, c] of [[1, 15, -1, '#74c0fc'], [1, 15, 0, '#f783ac'], [-4, 16, -1, '#b197fc'], [-4, 16, 0, '#63e6be'], [-4, 13, -5, '#74c0fc'], [1, 13, -5, '#f783ac'], [-4, 13, 4, '#63e6be'], [1, 13, 4, '#b197fc']]) gl(x, y, z, c);
    } else if (st === 'plant') {
      for (let x = -4; x <= 1; x++) { put(x, 13, -5, x % 2 ? '#2f9e44' : '#69db7c'); put(x, 13, 4, x % 2 ? '#69db7c' : '#2f9e44'); }
      put(-4, 16, -1, '#2f9e44'); put(-4, 16, 0, '#69db7c'); put(-1, 13, -6, '#ff8fab'); put(-1, 13, 5, '#ffd43b'); put(1, 15, 0, '#ff8fab');
    } else if (st === 'shell') {
      for (let x = -4; x <= 1; x += 2) { put(x, 13, -5, '#ffc9de'); put(x + 1, 13, -5, '#fff5f0'); put(x, 13, 4, '#fff5f0'); put(x + 1, 13, 4, '#ffc9de'); }
      put(-4, 16, -1, '#ffc9de'); put(-4, 16, 0, '#fff5f0'); gl(1, 15, 0, '#fff9f5');
    }
    if (bs === 'crystal') { gl(12, 16, -2, '#74c0fc'); gl(12, 16, 1, '#f783ac'); gl(14, 16, -1, '#b197fc'); }
    else if (bs === 'plant') { put(12, 16, -2, '#69db7c'); put(12, 16, 1, '#2f9e44'); put(13, 16, -2, '#ff8fab'); put(13, 16, 1, '#ffd43b'); }
    else if (bs === 'shell') { put(13, 16, -2, '#ffc9de'); put(13, 16, 1, '#fff5f0'); gl(14, 16, 0, '#fff9f5'); }
    fill(-2, -1, 10, 13, -4, -4, '#33415c');      // ноги
    fill(-2, -1, 10, 13, 3, 3, '#33415c');
    fill(-2, -1, 8, 9, -4, -4, '#1f1d22');        // сапоги
    fill(-2, -1, 8, 9, 3, 3, '#1f1d22');
    fill(-3, -1, 15, 19, -2, 1, R.shirt);         // корпус
    fill(0, 2, 17, 18, -3, -3, R.shirt);          // руки
    fill(0, 2, 17, 18, 2, 2, R.shirt);
    put(3, 17, -3, '#f2c9a5'); put(3, 17, 2, '#f2c9a5');
    fill(-3, 0, 20, 22, -2, 1, '#f2c9a5');        // голова
    fill(-3, 0, 23, 23, -2, 1, R.helmet);         // шлем
    fill(-3, -3, 21, 22, -2, 1, R.helmet);
    fill(1, 1, 22, 22, -1, 0, R.helmet);          // козырёк
    put(0, 21, -1, '#2b2b2b'); put(0, 21, 0, '#2b2b2b');
    fill(-5, -4, 19, 21, -1, 0, '#7a4a22');       // хвостик
    return { cells, glow };
  }

  // жители и девочка: одна модель с разной одеждой
  function personCells(look) {
    const cells = new Map();
    const fill = (x0, x1, y0, y1, z0, z1, c) => { for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) cells.set(key3(x, y, z), c); };
    const skin = look.skin || '#f2c9a5', hair = look.hair || '#7a4a22';
    fill(-1, 0, 7, 11, -2, 1, look.shirt);
    fill(-1, 0, 8, 11, -3, -3, look.shirt);
    fill(-1, 0, 8, 11, 2, 2, look.shirt);
    if (look.apron) fill(1, 1, 7, 10, -1, 0, look.apron);
    fill(-1, 0, 7, 7, -3, -3, skin);
    fill(-1, 0, 7, 7, 2, 2, skin);
    fill(-2, 1, 12, 15, -2, 1, skin);
    fill(-2, 1, 16, 16, -2, 1, hair);
    fill(-2, -2, 12, 15, -2, 1, hair);
    fill(-2, 1, 15, 15, -2, -2, hair);
    fill(-2, 1, 15, 15, 1, 1, hair);
    if (!look.hat || look.hat === 'none' || look.hat === 'crown') fill(-4, -3, 12, 14, -1, 0, hair);
    if (look.beard) fill(1, 1, 12, 13, -1, 0, hair);
    cells.set(key3(1, 14, -1), '#2b2b2b'); cells.set(key3(1, 14, 0), '#2b2b2b');
    const hc = look.hatColor || '#555';
    if (look.hat === 'scarf') { fill(-2, 1, 16, 16, -2, 1, hc); fill(-2, -2, 13, 15, -2, 1, hc); fill(-3, -3, 12, 13, 0, 0, hc); }
    if (look.hat === 'cap') { fill(-2, 1, 17, 17, -2, 1, hc); fill(2, 3, 16, 16, -1, 0, hc); }
    if (look.hat === 'hat') { fill(-3, 2, 17, 17, -3, 2, hc); fill(-2, 1, 18, 18, -2, 1, hc); }
    if (look.hat === 'tophat') { fill(-3, 2, 17, 17, -3, 2, hc); fill(-2, 1, 18, 21, -2, 1, hc); }
    if (look.hat === 'crown') { for (const [x, z] of [[-2, -2], [1, -2], [-2, 1], [1, 1], [0, -2], [-1, 1]]) cells.set(key3(x, 17, z), hc); }
    return cells;
  }
  function personLegCells(look) {
    const cells = new Map();
    for (let y = -7; y <= -1; y++) for (let x = -1; x <= 0; x++) cells.set(key3(x, y, 0), y <= -6 ? '#1f1d22' : (look.pants || '#33415c'));
    return cells;
  }
  function makePersonObj(look, opts = {}) {
    const group = new T.Group();
    const material = opts.ghost ? ghostMat : mat;
    const body = new T.Mesh(voxelGeometry(personCells(look), V, 5), material);
    body.castShadow = !opts.ghost;
    group.add(body);
    const legs = [-1, 1].map(z => {
      const pivot = new T.Group();
      pivot.position.set(0, 7 * V, z * V);
      const m = new T.Mesh(voxelGeometry(personLegCells(look), V, 7), material);
      m.castShadow = !opts.ghost;
      pivot.add(m);
      group.add(pivot);
      return pivot;
    });
    if (opts.fairy) {
      const wc = new Map();
      for (let y = 0; y < 5; y++) for (let z = 0; z < 4 - Math.floor(y / 2); z++) wc.set(key3(0, y, z), y % 2 ? '#e5dbff' : '#c5f6fa');
      for (const s of [-1, 1]) {
        const w = glowMesh(voxelGeometry(wc, V, 2));
        w.position.set(-1.6 * V, 9 * V, s * 1.2 * V);
        w.rotation.y = s > 0 ? 0.3 : Math.PI - 0.3;
        group.add(w);
      }
    }
    return { group, legs, shirt: look.shirt };
  }

  function makeHorseObj(h, ph, material) {
    const B = Genetics.BREEDS[h.breed] || Genetics.BREEDS.mix;
    const mag = h.magic || {};
    const group = new T.Group();
    const mk = geo => { const m = new T.Mesh(geo, material || mat); m.castShadow = !material; m.receiveShadow = !material; return m; };
    const hc = horseCells(h, ph, B);
    group.add(mk(voxelGeometry(hc.cells, V, h.seed)));
    if (hc.glow.size) group.add(material ? mk(voxelGeometry(hc.glow, V, 1)) : glowMesh(voxelGeometry(hc.glow, V, 1)));
    const legs = [];
    const LP = [[5, -1.5], [5, 1.5], [-6, -1.5], [-6, 1.5]];
    LP.forEach(([x, z], i) => {
      const pivot = new T.Group();
      pivot.position.set(x * V, 7 * V, z * V);
      pivot.add(mk(voxelGeometry(legCells(h, ph, i), V, h.seed + i)));
      if (mag.cloud) {
        // облачко под копытом
        const cc = new Map();
        for (let cx = -2; cx <= 1; cx++) for (let cz = -2; cz <= 1; cz++) if (Math.abs(cx + 0.5) + Math.abs(cz + 0.5) < 3) cc.set(key3(cx, -9, cz), (cx + cz) % 2 ? '#ffffff' : '#e7f5ff');
        cc.set(key3(-1, -8, -1), '#ffffff'); cc.set(key3(0, -8, 0), '#ffffff'); cc.set(key3(-1, -8, 0), '#f1f3f5');
        pivot.add(material ? mk(voxelGeometry(cc, V, 5)) : glowMesh(voxelGeometry(cc, V, 5)));
      }
      group.add(pivot);
      legs.push(pivot);
    });
    const tail = new T.Group();
    tail.position.set(-8 * V, 12.5 * V, 0.5 * V);
    const tc = tailCells(h, ph, B);
    if (tc.cells.size) tail.add(mk(voxelGeometry(tc.cells, V, h.seed + 9)));
    if (tc.glow.size) tail.add(material ? mk(voxelGeometry(tc.glow, V, 1)) : glowMesh(voxelGeometry(tc.glow, V, 1)));
    group.add(tail);
    const wings = [];
    if (mag.wings) {
      const type = Horses.wingType(mag.wings);
      const def = wingDef(type, h, ph);
      const geo = voxelGeometry(def.cells, V, h.seed + 20);
      for (const s of [-1, 1]) {
        const pivot = new T.Group();
        pivot.position.set(2 * V, 12.5 * V, (s > 0 ? 3 : -3) * V);
        const m = def.glass && !material ? new T.Mesh(geo, glassMat) : mk(geo);
        if (s < 0) { m.scale.z = -1; }
        pivot.add(m);
        group.add(pivot);
        wings.push({ pivot, s, f: FLAP[type] || FLAP.pegasus });
      }
    }
    return { group, legs, tail, wings, ph, rider: null, riderKey: '' };
  }

  function disposeObj(o) {
    o.group.traverse(n => { if (n.geometry) n.geometry.dispose(); });
    scene.remove(o.group);
  }
  const horseKey = h => `${h._phKey}|${h.maneStyle || ''}|${h.maneDye || ''}|${JSON.stringify(h.magic || 0)}|${mudLevel(h)}`;

  /* ---------- земля ---------- */
  function groundTexture() {
    const S = 0.2;
    const c = document.createElement('canvas');
    c.width = World.W * S; c.height = World.H * S;
    const g = c.getContext('2d');
    g.scale(S, S);
    Draw.worldGround(g, S, true);
    const tex = new T.CanvasTexture(c);
    tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
    return tex;
  }

  function fenceBoxes(list, r, gate, color, post, height = 1.4) {
    const segs = [];
    const { x, y, w, h } = r;
    const top = gate.side === 'top' ? [[x, y, gate.a, y], [gate.b, y, x + w, y]] : [[x, y, x + w, y]];
    const bottom = gate.side === 'bottom' ? [[x, y + h, gate.a, y + h], [gate.b, y + h, x + w, y + h]] : [[x, y + h, x + w, y + h]];
    const left = gate.side === 'left' ? [[x, y, x, gate.a], [x, gate.b, x, y + h]] : [[x, y, x, y + h]];
    segs.push(...top, ...bottom, ...left, [x + w, y, x + w, y + h]);
    for (const [x1, y1, x2, y2] of segs) {
      const len = Math.hypot(x2 - x1, y2 - y1) * K, cx = (x1 + x2) / 2 * K, cz = (y1 + y2) / 2 * K;
      const horiz = y1 === y2;
      for (const hy of [height * 0.45, height * 0.85]) {
        list.push(box(cx, hy, cz, horiz ? len : 0.18, 0.18, horiz ? 0.18 : len, color));
      }
      const n = Math.max(1, Math.round(len / 4));
      for (let i = 0; i <= n; i++) {
        list.push(box((x1 + (x2 - x1) * i / n) * K, height / 2, (y1 + (y2 - y1) * i / n) * K, 0.32, height, 0.32, post));
      }
    }
  }

  // статичные объекты складываем в «куски» карты, чтобы невидимое не рисовалось
  const chunks = new Map();
  function chunk(x, z, glow = false) {
    const k = `${Math.floor(x / 120)}|${Math.floor(z / 120)}`;
    if (!chunks.has(k)) chunks.set(k, { list: [], glow: [] });
    return glow ? chunks.get(k).glow : chunks.get(k).list;
  }
  function flushChunks() {
    for (const c of chunks.values()) {
      if (c.list.length) scene.add(meshOf(boxGeometry(c.list)));
      if (c.glow.length) scene.add(glowMesh(boxGeometry(c.glow)));
    }
    chunks.clear();
  }

  function addTree(tr) {
    const r = World.rng(tr.s);
    const x = tr.x * K, z = tr.y * K, R = tr.r * K;
    const L = chunk(x, z), Gl = chunk(x, z, true);
    const k = tr.kind;
    if (k === 'oak' || k === 'birch' || k === 'vinetree') {
      L.push(box(x, 1.5, z, 0.9, 3, 0.9, k === 'birch' ? '#e9ecef' : '#6b4423'));
      if (k === 'birch') { L.push(box(x + 0.46, 1.2, z, 0.02, 0.3, 0.5, '#222')); L.push(box(x - 0.46, 2.2, z, 0.02, 0.25, 0.4, '#222')); }
      const g1 = k === 'birch' ? '#7dbb4f' : '#4f8f3a', g2 = k === 'birch' ? '#a3d46c' : '#6eae4c';
      const n = 7 + Math.floor(R * 2);
      for (let i = 0; i < n; i++) {
        const a = r() * Math.PI * 2, d = r() * R * 0.6, sz = R * (0.5 + r() * 0.35);
        L.push(box(x + Math.cos(a) * d, 3 + R * 0.5 + r() * R * 0.6, z + Math.sin(a) * d, sz, sz * 0.8, sz, r() < 0.4 ? g2 : g1));
      }
      if (k === 'vinetree') {
        // лианы свисают с кроны, на них — цветочки
        for (let i = 0; i < 9; i++) {
          const a = r() * Math.PI * 2, d = R * (0.55 + r() * 0.3), len = 1.5 + r() * 2.5;
          const vx = x + Math.cos(a) * d, vz = z + Math.sin(a) * d, top = 3 + R * 0.4;
          L.push(box(vx, top - len / 2, vz, 0.18, len, 0.18, r() < 0.5 ? '#2f9e44' : '#5c940d'));
          if (r() < 0.5) L.push(box(vx, top - len, vz, 0.35, 0.35, 0.35, ['#ff8fab', '#ffe066', '#c77dff'][Math.floor(r() * 3)]));
        }
        for (let i = 0; i < 4; i++) L.push(box(x + (r() - 0.5) * 0.4, 0.5 + i * 0.7, z + 0.46, 0.15, 0.6, 0.06, '#2f9e44'));
      }
    } else if (k === 'pine' || k === 'spruce') {
      const tall = k === 'spruce' ? 1.35 : 1;
      L.push(box(x, 1.4, z, 0.8, 2.8, 0.8, '#5b3a22'));
      const tiers = k === 'spruce' ? 5 : 4;
      for (let i = 0; i < tiers; i++) {
        const w = R * (1.7 - i * (1.4 / tiers)) * (k === 'spruce' ? 1.05 : 0.95);
        const y = (2.4 + i * 1.5) * tall;
        const cc = i % 2 ? (k === 'spruce' ? '#1f4f33' : '#2f6b3a') : (k === 'spruce' ? '#2a5f3e' : '#3b7d45');
        L.push(box(x, y, z, w, 1.4 * tall, w, tr.dark ? Genetics.mix(cc, '#000000', 0.25) : cc));
      }
      L.push(box(x, (2.4 + tiers * 1.5) * tall, z, 0.6, 1, 0.6, k === 'spruce' ? '#2a5f3e' : '#3b7d45'));
    } else if (k === 'amanita' || k === 'boletus' || k === 'glowshroom') {
      const H = R * (k === 'boletus' ? 1.3 : 1.9), sw = R * (k === 'boletus' ? 0.7 : 0.45);
      L.push(box(x, H / 2, z, sw, H, sw, k === 'boletus' ? '#e8d9b5' : k === 'glowshroom' ? '#d7f5ff' : '#f8f4ea'));
      const capC = k === 'amanita' ? '#e03131' : k === 'boletus' ? '#8a5a2b' : (r() < 0.5 ? '#3bc9db' : '#b197fc');
      const cap = k === 'glowshroom' ? Gl : L;
      cap.push(box(x, H + 0.4, z, R * 1.7, 0.8, R * 1.7, capC));
      cap.push(box(x, H + 1.1, z, R * 1.25, 0.7, R * 1.25, capC));
      cap.push(box(x, H + 1.6, z, R * 0.7, 0.4, R * 0.7, capC));
      L.push(box(x, H - 0.05, z, R * 1.5, 0.2, R * 1.5, k === 'boletus' ? '#d8c08a' : '#fff1e6'));
      if (k !== 'boletus') for (let i = 0; i < 7; i++) {
        const a = r() * Math.PI * 2, d = R * (0.2 + r() * 0.6);
        cap.push(box(x + Math.cos(a) * d, H + 0.85 + (d < R * 0.45 ? 0.6 : 0), z + Math.sin(a) * d, 0.5, 0.25, 0.5, k === 'glowshroom' ? '#ffffff' : '#ffffff'));
      }
    } else if (k === 'cactus') {
      const H = 2 + R * 0.25;
      L.push(box(x, H / 2, z, 0.9, H, 0.9, '#3a7d44'));
      L.push(box(x + 0.9, H * 0.55, z, 0.9, 0.6, 0.6, '#3a7d44'));
      L.push(box(x + 1.2, H * 0.75, z, 0.6, H * 0.45, 0.6, '#4a9152'));
      if (r() < 0.6) { L.push(box(x - 0.9, H * 0.45, z, 0.9, 0.6, 0.6, '#3a7d44')); L.push(box(x - 1.2, H * 0.62, z, 0.6, H * 0.35, 0.6, '#4a9152')); }
      if (r() < 0.4) L.push(box(x, H + 0.2, z, 0.5, 0.4, 0.5, '#ff6fae'));
    } else if (k === 'mesa') {
      const n = 3;
      for (let i = 0; i < n; i++) L.push(box(x, 1.5 + i * 3, z, R * (1.4 - i * 0.35), 3, R * (1.2 - i * 0.3), ['#c0603a', '#d97b4a', '#b5522f'][i]));
    } else if (k === 'drybush') {
      for (let i = 0; i < 5; i++) L.push(box(x + (r() - 0.5) * 1.6, 0.4 + r() * 0.5, z + (r() - 0.5) * 1.6, 0.5, 0.6, 0.5, '#a0895a'));
    } else if (k === 'palm') {
      for (let i = 0; i < 7; i++) L.push(box(x + i * 0.18, 0.6 + i * 1.1, z, 0.7, 1.2, 0.7, '#8d6e4a'));
      const tx = x + 1.2, ty = 8.2;
      for (let a = 0; a < 6; a++) {
        const ang = a / 6 * Math.PI * 2;
        for (let d = 1; d <= 3; d++) L.push(box(tx + Math.cos(ang) * d * 1.1, ty - d * 0.35, z + Math.sin(ang) * d * 1.1, 1.2, 0.3, 1.2, d % 2 ? '#2b9348' : '#55a630'));
      }
      L.push(box(tx, ty - 0.5, z, 0.7, 0.7, 0.7, '#7f5539'));
    } else if (k === 'snowspruce') {
      L.push(box(x, 1.4, z, 0.8, 2.8, 0.8, '#5b3a22'));
      for (let i = 0; i < 5; i++) {
        const w = R * (1.7 - i * 0.28);
        L.push(box(x, 2.6 + i * 1.6, z, w, 1.4, w, i % 2 ? '#1f4f33' : '#2a5f3e'));
        L.push(box(x, 3.35 + i * 1.6, z, w * 0.8, 0.2, w * 0.8, '#ffffff'));
      }
      L.push(box(x, 10.8, z, 0.7, 1, 0.7, '#ffffff'));
    } else if (k === 'snowrock') {
      const n = 2 + Math.floor(r() * 3);
      for (let i = 0; i < n; i++) {
        const a = r() * 6.28, d = r() * R * 0.4, sw = R * (0.6 + r() * 0.5), hgt = R * (0.8 + r() * 1.2);
        const px = x + Math.cos(a) * d, pz = z + Math.sin(a) * d;
        L.push(box(px, hgt / 2, pz, sw, hgt, sw, ['#7f8c99', '#6b7785', '#95a2ad'][i % 3]));
        L.push(box(px, hgt + 0.3, pz, sw * 0.85, 0.6, sw * 0.85, '#ffffff'));
      }
    } else if (k === 'rock') {
      const n = 3 + Math.floor(r() * 3);
      for (let i = 0; i < n; i++) {
        const a = r() * 6.28, d = r() * R * 0.5, s = R * (0.6 + r() * 0.5);
        L.push(box(x + Math.cos(a) * d, s * 0.4, z + Math.sin(a) * d, s, s * 0.8, s, ['#6c6970', '#7f7c84', '#5e5b62'][i % 3]));
      }
    }
  }

  // горы и стены пещеры: высокие каменные блоки
  function addRock(rect, outer) {
    const step = 120;
    const r = World.rng(Math.floor(rect.x * 7 + rect.y * 13));
    for (let x = rect.x; x < rect.x + rect.w; x += step) for (let y = rect.y; y < rect.y + rect.h; y += step) {
      const w = Math.min(step, rect.x + rect.w - x), d = Math.min(step, rect.y + rect.h - y);
      const H = outer ? 10 + r() * 14 : 7 + r() * 5;
      const cx = (x + w / 2) * K, cz = (y + d / 2) * K;
      const L = chunk(cx, cz);
      const c = ['#6c6970', '#7f7c84', '#5e5b62', '#74717a'][Math.floor(r() * 4)];
      L.push(box(cx, H / 2, cz, w * K + 0.2, H, d * K + 0.2, c));
      if (outer && H > 18) L.push(box(cx, H + 0.4, cz, w * K * 0.7, 0.8, d * K * 0.7, '#f1f3f5'));
    }
  }

  // причал с лодкой; dir — в какую сторону вода
  function addPier(x, y, dir) {
    const cx = x * K, cz = y * K, L = chunk(cx, cz);
    L.push(box(cx, 0.4, cz, 24, 0.3, 5, '#8a5a32'));
    for (let i = -2; i <= 2; i++) for (const s of [-1, 1]) L.push(box(cx + i * 5, 0.2, cz + s * 2.4, 0.5, 1.4, 0.5, '#5e3b1d'));
    const bx = cx + dir * 14, bz = cz + 5;
    L.push(box(bx, 0.5, bz, 7, 1, 3, '#a0522d'));
    L.push(box(bx, 1.1, bz, 7.4, 0.3, 3.4, '#8a4520'));
    L.push(box(bx, 3.2, bz, 0.3, 5, 0.3, '#5e3b1d'));
    L.push(box(bx + dir * 1.4, 3.4, bz, 2.4, 3.6, 0.1, '#f8f4ea'));
  }

  function addHouse(hh) {
    const cx = (hh.x + hh.w / 2) * K, cz = (hh.y + hh.h / 2) * K, w = hh.w * K, d = hh.h * K;
    const L = chunk(cx, cz), Gl = chunk(cx, cz, true);
    L.push(box(cx, 1.8, cz, w, 3.6, d, hh.wall));
    for (let i = 0; i < 5; i++) L.push(box(cx, 3.8 + i * 0.55, cz, w + 0.6, 0.55, d + 0.6 - i * (d / 4.6), hh.roof));
    L.push(box(cx, 1.1, cz + d / 2 + 0.05, 1.4, 2.2, 0.1, '#5b3a22'));
    for (const s of [-1, 1]) Gl.push(box(cx + s * w * 0.3, 2.2, cz + d / 2 + 0.06, 1.1, 0.9, 0.08, '#fff3bf'));
    if (hh.name === 'Кузница') { L.push(box(cx + w * 0.3, 6.6, cz - d * 0.2, 1, 3, 1, '#495057')); L.push(box(cx - w * 0.6, 0.6, cz + d * 0.6, 1.4, 1.2, 0.8, '#343a40')); }
  }

  /* ---------- рынок ---------- */
  function addMarket() {
    const M = World.MARKET, cx = (M.x + M.w / 2) * K, cz = (M.y + M.h / 2) * K, L = chunk(cx, cz);
    const SELLER = { horses: '#c92a2a', trainer: '#1971c2', swap: '#862e9c' };
    for (const st of World.MARKET_STALLS) {
      const x = (st.x + st.w / 2) * K, z = (st.y + st.h / 2) * K, w = st.w * K, d = st.h * K;
      L.push(box(x, 0.8, z, w, 1.6, d, '#8a5a32'));                       // прилавок
      L.push(box(x, 1.65, z, w + 0.3, 0.12, d + 0.3, '#b08850'));
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) L.push(box(x + sx * (w / 2 - 0.2), 2.4, z + sz * (d / 2 + 0.6), 0.25, 4.8, 0.25, '#6b4423'));
      const n = 6;
      for (let i = 0; i < n; i++) L.push(box(x - w / 2 + (w / n) * (i + 0.5), 4.9, z, w / n, 0.35, d + 2, i % 2 ? '#ffffff' : st.roof, { rx: 0.18 }));
      // товары на прилавке
      const goods = st.id === 'horses' ? ['#5b3a1e', '#2b1a10', '#5b3a1e'] : st.id === 'trainer' ? ['#adb5bd', '#ffd43b', '#adb5bd'] : st.id === 'swap' ? ['#c77dff', '#ffd43b', '#69db7c'] : ['#ffe066', '#ff8fab', '#74c0fc'];
      goods.forEach((c, i) => L.push(box(x - w / 3 + i * w / 3, 1.95, z, 1.4, 0.6, 1.2, c)));
      if (SELLER[st.id]) {
        L.push(box(x, 1.1, z - d / 2 - 1.2, 0.9, 2.2, 1.2, SELLER[st.id]));
        L.push(box(x, 2.7, z - d / 2 - 1.2, 1.2, 1.2, 1.2, '#f2c9a5'));
        L.push(box(x, 3.35, z - d / 2 - 1.2, 1.3, 0.3, 1.3, '#5b3a22'));
      }
    }
    // коновязь для лошадей на продажу
    const ry = (M.y + 205) * K;
    L.push(box((M.x + 50 + 200) * K, 1.4, ry, 40, 0.25, 0.25, '#6b4423'));
    for (let i = 0; i <= 5; i++) L.push(box((M.x + 50 + i * 80) * K, 0.8, ry, 0.35, 1.6, 0.35, '#5b3a22'));
    L.push(box((M.x + 540) * K, 1.4, ry, 16, 0.25, 0.25, '#6b4423'));
    for (let i = 0; i <= 2; i++) L.push(box((M.x + 460 + i * 80) * K, 0.8, ry, 0.35, 1.6, 0.35, '#5b3a22'));
    // флажки по краям площади
    for (let i = 0; i <= 8; i++) {
      const fx = (M.x + i * M.w / 8) * K;
      L.push(box(fx, 2, (M.y - 10) * K, 0.25, 4, 0.25, '#6b4423'));
      L.push(box(fx + 0.6, 3.6, (M.y - 10) * K, 1, 0.7, 0.08, ['#ff6b6b', '#ffd43b', '#51cf66', '#4dabf7', '#cc5de8'][i % 5]));
    }
    // ящики и бочки
    for (const [bx, by] of [[M.x + 20, M.y + 330], [M.x + 620, M.y + 330], [M.x + 640, M.y + 20]]) {
      L.push(box(bx * K, 0.6, by * K, 1.2, 1.2, 1.2, '#a0522d'));
      L.push(box(bx * K + 1.4, 0.7, by * K, 1, 1.4, 1, '#6b4423'));
    }
  }

  /* ---------- портал: каменная арка и светящийся вихрь ---------- */
  const portals = [];
  function addPortal(P, color) {
    const g = new T.Group();
    g.position.set(P.x * K, 0, P.y * K);
    const stones = [];
    for (let a = 0; a <= 12; a++) {
      const ang = Math.PI * a / 12;
      stones.push(box(Math.cos(ang) * 4.2, 1 + Math.sin(ang) * 4.2, 0, 1.3, 1.3, 1.3, a % 2 ? '#5e5b62' : '#7f7c84'));
    }
    stones.push(box(-4.2, 0.5, 0, 1.4, 1, 1.4, '#5e5b62'), box(4.2, 0.5, 0, 1.4, 1, 1.4, '#5e5b62'));
    g.add(meshOf(boxGeometry(stones)));
    const runes = [];
    for (let a = 1; a < 12; a += 2) { const ang = Math.PI * a / 12; runes.push(box(Math.cos(ang) * 4.2, 1 + Math.sin(ang) * 4.2, 0.7, 0.5, 0.5, 0.1, color)); }
    g.add(glowMesh(boxGeometry(runes)));
    const swirl = new T.Mesh(new T.CircleGeometry(3.6, 32), new T.MeshBasicMaterial({ color, transparent: true, opacity: 0.7, side: T.DoubleSide, depthWrite: false }));
    swirl.position.set(0, 1.4, 0);
    g.add(swirl);
    const inner = new T.Mesh(new T.RingGeometry(0.8, 2.6, 6, 1), new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.55, side: T.DoubleSide, depthWrite: false }));
    inner.position.set(0, 1.4, 0.05);
    g.add(inner);
    const light = new T.PointLight(color, 1.6, 40, 1.4);
    light.position.set(0, 3, 3);
    g.add(light);
    scene.add(g);
    portals.push({ g, swirl, inner, light });
  }

  /* ---------- небесные острова ---------- */
  let skyGroup = null;
  function addSky() {
    const HK = World.H * K;
    skyGroup = new T.Group();
    const grass = new T.MeshLambertMaterial({ color: '#86c95a' });
    const dirt = new T.MeshLambertMaterial({ color: '#8a6a44' });
    for (const I of World.SKY_ISLANDS) {
      const top = new T.Mesh(new T.CylinderGeometry(1, 1, 0.8, 48), grass);
      top.scale.set(I.rx * K, 1, I.ry * K);
      top.position.set(I.x * K, -0.39, I.y * K);
      top.receiveShadow = true;
      skyGroup.add(top);
      const depth = 10 + I.rx * K * 0.25;
      const under = new T.Mesh(new T.CylinderGeometry(1, 0.12, depth, 16, 3), dirt);
      under.scale.set(I.rx * K * 0.98, 1, I.ry * K * 0.98);
      under.position.set(I.x * K, -0.8 - depth / 2, I.y * K);
      skyGroup.add(under);
      // каменные выступы снизу
      const r = World.rng(Math.floor(I.x));
      const L = chunk(I.x * K, I.y * K);
      for (let i = 0; i < 26; i++) {
        const a = r() * Math.PI * 2, d = 0.5 + r() * 0.45, hh = 2 + r() * depth * 0.6;
        L.push(box((I.x + Math.cos(a) * I.rx * d * 0.85) * K, -1 - hh / 2 - (1 - d) * depth * 0.3, (I.y + Math.sin(a) * I.ry * d * 0.85) * K, 2 + r() * 3, hh, 2 + r() * 3, ['#7a5a3a', '#6c6970', '#8a6a44'][i % 3]));
      }
    }
    // лианы по краям островов и под мостами
    for (const v of World.VINES) {
      const L = chunk(v.x * K, v.y * K);
      L.push(box(v.x * K, -0.6 - v.len / 2, v.y * K, 0.25, v.len, 0.25, v.s < 0.5 ? '#2f9e44' : '#5c940d'));
      if (v.s < 0.35) L.push(box(v.x * K, -0.6 - v.len, v.y * K, 0.5, 0.5, 0.5, ['#ff8fab', '#ffe066', '#c77dff'][Math.floor(v.s * 9) % 3]));
    }
    // мосты из досок и лиан
    for (const b of World.SKY_BRIDGES) {
      const [ax, ay, bx, by] = b, len = Math.hypot(bx - ax, by - ay), n = Math.ceil(len / 22);
      const ang = Math.atan2(by - ay, bx - ax);
      const L = chunk((ax + bx) / 2 * K, (ay + by) / 2 * K);
      for (let i = 0; i <= n; i++) {
        const t = i / n, x = (ax + (bx - ax) * t) * K, z = (ay + (by - ay) * t) * K;
        L.push(box(x, -0.15, z, 1.8, 0.3, World.BRIDGE_W * 2 * K, i % 2 ? '#a0754a' : '#8a5a32', { ry: -ang }));
      }
      for (const s of [-1, 1]) {
        const ox = -Math.sin(ang) * World.BRIDGE_W * s, oy = Math.cos(ang) * World.BRIDGE_W * s;
        L.push(box(((ax + bx) / 2 + ox) * K, 1.2, ((ay + by) / 2 + oy) * K, len * K, 0.2, 0.2, '#2f9e44', { ry: -ang }));
        for (let i = 0; i <= n; i += 2) {
          const t = i / n;
          L.push(box((ax + (bx - ax) * t + ox) * K, 0.6, (ay + (by - ay) * t + oy) * K, 0.2, 1.2, 0.2, '#5c940d'));
        }
      }
    }
    // цветы на островах
    for (const f of World.FLOWERS) if (f.sky) chunk(f.x * K, f.y * K).push(box(f.x * K, 0.12, f.y * K, 0.4, 0.25, 0.4, f.c));
    // облака внизу и пропасть
    const cl = [], cr = World.rng(321);
    for (let i = 0; i < 240; i++) {
      const x = (World.SKY.x - 1200 + cr() * (World.SKY.w + 2400)) * K, z = HK + 8 + cr() * (World.SKY.y + World.SKY.h - World.H + 900) * K;
      const y = -12 - cr() * 40, w = 8 + cr() * 22, d = 5 + cr() * 12;
      cl.push(box(x, y, z, w, 2.5 + cr() * 2, d, '#ffffff'), box(x + w * 0.2, y + 1.5, z, w * 0.55, 2.2, d * 0.7, '#f1f3f5'));
    }
    const cloudMesh = new T.Mesh(boxGeometry(cl), new T.MeshLambertMaterial({ vertexColors: true, transparent: true, opacity: 0.88 }));
    skyGroup.add(cloudMesh);
    const abyss = new T.Mesh(new T.PlaneGeometry(9000, 4000), new T.MeshBasicMaterial({ color: '#cfe8ff' }));
    abyss.rotation.x = -Math.PI / 2;
    abyss.position.set(World.W * K / 2, -70, HK + 2000);
    skyGroup.add(abyss);
    // край земли: обрыв
    const cliff = new T.Mesh(boxGeometry([box(World.W * K / 2, -6, HK + 0.5, World.W * K, 12, 1, '#7a5a3a'), box(World.W * K / 2, -14, HK - 1, World.W * K, 6, 1, '#6c6970')]), mat);
    skyGroup.add(cliff);
    scene.add(skyGroup);
  }

  function buildStatic() {
    const list = [];
    // конюшня: стены, перегородки, кормушки, тюки сена
    const wood = '#8a5a32', dark = '#6b4423';
    for (const s of World.SOLIDS.slice(0, 6)) list.push(box((s.x + s.w / 2) * K, 1.6, (s.y + s.h / 2) * K, s.w * K, 3.2, s.h * K, wood));
    const St = World.STABLE;
    for (let c = 0; c <= 10; c++) {
      const x = (St.x + 10 + c * World.STALL_W) * K;
      list.push(box(x, 0.9, (St.y + 10 + World.STALL_H / 2) * K, 0.4, 1.8, World.STALL_H * K, dark));
      list.push(box(x, 0.9, (World.AISLE_Y2 + World.STALL_H / 2) * K, 0.4, 1.8, World.STALL_H * K, dark));
    }
    for (let c = 0; c < 10; c++) {
      const x0 = St.x + 10 + c * World.STALL_W;
      for (const yy of [World.AISLE_Y1, World.AISLE_Y2]) {
        list.push(box((x0 + 9) * K, 0.7, yy * K, 1.8, 1.4, 0.25, dark));
        list.push(box((x0 + World.STALL_W - 9) * K, 0.7, yy * K, 1.8, 1.4, 0.25, dark));
      }
      for (const row of [0, 1]) {
        const r = World.stallRect(c + row * 10);
        const fy = row ? r.y + r.h - 9 : r.y + 9;
        list.push(box((r.x + 20) * K, 0.6, fy * K, 2.4, 0.6, 1, '#9b7a3a'));
        list.push(box((r.x + r.w - 16) * K, 0.4, fy * K, 1.1, 0.8, 1.1, '#5a7d99'));
      }
    }
    for (const [x, y] of [[St.x - 30, St.y + 40], [St.x - 30, St.y + 80], [St.x + St.w + 30, St.y + St.h - 50]]) list.push(box(x * K, 0.6, y * K, 3.6, 1.2, 2.4, '#d8b85c'));
    // манеж
    fenceBoxes(list, World.ARENA, { side: 'left', a: World.GATE_A.y1, b: World.GATE_A.y2 }, '#ffffff', '#e9ecef', 1.3);
    for (const [L, p] of Object.entries(World.LETTERS)) {
      if (L === 'X') continue;
      const off = 22;
      const bx = p.side === 'left' ? p.x - off : p.side === 'right' ? p.x + off : p.x;
      const by = p.side === 'top' ? p.y - off : p.side === 'bottom' ? p.y + off : p.y;
      list.push(box(bx * K, 0.6, by * K, 1.4, 1.2, 1.4, '#ffffff'));
    }
    // левада
    fenceBoxes(list, World.PADDOCK, { side: 'bottom', a: World.PADDOCK_GATE.x1, b: World.PADDOCK_GATE.x2 }, '#8a5a32', '#5e3b1d', 1.5);
    const P = World.PADDOCK;
    list.push(box((P.x + P.w - 60) * K, 0.4, (P.y + 41) * K, 6, 0.8, 2.2, '#6b6f75'));
    list.push(box((P.x + P.w - 60) * K, 0.82, (P.y + 41) * K, 5.2, 0.05, 1.4, '#7cc3ea'));
    list.push(box((P.x + 55) * K, 0.8, (P.y + 47) * K, 5, 1.6, 3.4, '#6b4a2b'));
    list.push(box((P.x + 55) * K, 1.7, (P.y + 47) * K, 4.2, 0.4, 2.6, '#d8b85c'));
    // конкурное поле
    fenceBoxes(list, World.JUMPF, { side: 'top', a: World.JUMPF_GATE.x1, b: World.JUMPF_GATE.x2 }, '#ffffff', '#dee2e6', 1.3);
    // повозки
    for (const [W, stripe] of [[World.SELL, '#d63a3a'], [World.SHOP, '#2e9d4f']]) {
      const cx = (W.x + W.w / 2) * K, cz = (W.y + W.h / 2) * K, w = W.w * K, d = W.h * K;
      list.push(box(cx, 1.4, cz, w, 1.6, d, '#8a5a32'));
      for (const wx of [W.x + 22, W.x + W.w - 22]) for (const wz of [W.y - 3, W.y + W.h + 3]) list.push(box(wx * K, 0.9, wz * K, 2.2, 1.8, 0.4, '#3d2a1a'));
      const n = 8;
      for (let i = 0; i < n; i++) list.push(box((W.x + (W.w / n) * (i + 0.5)) * K, 3.3, cz, w / n, 2.2, d * 0.95, i % 2 ? '#ffffff' : stripe, {}));
      list.push(box(W.x * K - 2.5, 0.9, cz - d * 0.3, 5, 0.2, 0.2, '#6b4a2b'));
      list.push(box(W.x * K - 2.5, 0.9, cz + d * 0.3, 5, 0.2, 0.2, '#6b4a2b'));
      // продавец
      const sx = (W.x + W.w + 22) * K;
      list.push(box(sx, 1.1, cz, 0.9, 2.2, 1.2, '#4a6fa5'));
      list.push(box(sx, 2.7, cz, 1.2, 1.2, 1.2, '#f2c9a5'));
      list.push(box(sx, 3.4, cz, 2.4, 0.3, 2.4, '#b08850'));
      list.push(box(sx, 3.7, cz, 1.2, 0.5, 1.2, '#b08850'));
    }
    // фонарные столбы
    for (const l of World.LAMPS) list.push(box(l.x * K, 1.6, l.y * K, 0.3, 3.2, 0.3, '#343a40'));
    scene.add(meshOf(boxGeometry(list)));


    // деревья, грибы, камни
    for (const tr of World.TREES) addTree(tr);
    // горы и пещера
    for (const w of World.CAVE_WALLS) addRock(w, true);
    for (const w of World.CAVE_INNER_WALLS) addRock(w, false);
    // кристаллы и факелы в пещере
    for (const c of World.CRYSTALS) {
      const x = c.x * K, z = c.y * K, Gl = chunk(x, z, true);
      Gl.push(box(x, c.h / 2, z, 0.4, c.h, 0.4, c.c, { ry: c.s % 3 }));
      Gl.push(box(x + 0.3, c.h * 0.3, z + 0.2, 0.3, c.h * 0.6, 0.3, c.c, { rz: 0.3 }));
    }
    const C = World.CAVE;
    for (let x = C.x + 150; x < C.x + C.w; x += 420) for (let y = C.y + 150; y < C.y + C.h; y += 420) {
      if (World.blocked(x, y, 40)) continue;
      torches.push({ x, y });
      chunk(x * K, y * K).push(box(x * K, 1.2, y * K, 0.25, 2.4, 0.25, '#5b3a22'));
      chunk(x * K, y * K, true).push(box(x * K, 2.6, y * K, 0.5, 0.6, 0.5, '#ffb84d'));
    }
    // острова
    for (const I of World.ISLANDS) {
      const st = I.stable, cx = (st.x + st.w / 2) * K, cz = (st.y + st.h / 2) * K, L = chunk(cx, cz);
      L.push(box(cx, 0.05, cz, st.w * K, 0.1, st.h * K, '#e4c46c'));
      L.push(box(cx, 1.6, st.y * K + 0.5, st.w * K, 3.2, 1, '#8a5a32'));
      L.push(box(st.x * K + 0.5, 1.6, cz, 1, 3.2, st.h * K, '#8a5a32'));
      L.push(box((st.x + st.w) * K - 0.5, 1.6, cz, 1, 3.2, st.h * K, '#8a5a32'));
      for (let k = 1; k < 5; k++) L.push(box((st.x + k * st.w / 5) * K, 0.9, cz, 0.3, 1.8, st.h * K * 0.8, '#6b4423'));
      for (let k = 0; k < 5; k++) L.push(box((st.x + 34 + k * 68) * K, 0.4, (st.y + 20) * K, 2.2, 0.6, 1, '#9b7a3a'));
      fenceBoxes(L, I.pasture, { side: 'bottom', a: I.gate.x1, b: I.gate.x2 }, '#8a5a32', '#5e3b1d', 1.5);
      const pc = chunk(I.pen.x * K, I.pen.y * K);
      for (let k = 0; k < 24; k++) {
        const a = k / 24 * Math.PI * 2, a2 = (k + 1) / 24 * Math.PI * 2;
        if (Math.abs(a - Math.PI * 1.5) < 0.3) continue;
        const px = (I.pen.x + Math.cos(a) * I.pen.r) * K, pz = (I.pen.y + Math.sin(a) * I.pen.r) * K;
        pc.push(box(px, 0.7, pz, 0.35, 1.4, 0.35, '#ffffff'));
        if (Math.abs(a2 - Math.PI * 1.5) < 0.3) continue;
        const qx = (I.pen.x + Math.cos(a2) * I.pen.r) * K, qz = (I.pen.y + Math.sin(a2) * I.pen.r) * K;
        for (const hy of [0.6, 1.15]) pc.push(box((px + qx) / 2, hy, (pz + qz) / 2, Math.hypot(qx - px, qz - pz), 0.18, 0.18, '#f1f3f5', { ry: -Math.atan2(qz - pz, qx - px) }));
      }
      addPier(I.pier.x - 110, I.pier.y, -1);
    }
    addPier(World.PIER.x + 110, World.PIER.y, 1);
    // деревня
    for (const hh of World.HOUSES) addHouse(hh);
    const Wl = World.WELL, wl = chunk(Wl.x * K, Wl.y * K);
    for (let a = 0; a < 8; a++) wl.push(box(Wl.x * K + Math.cos(a / 8 * 6.28) * 2, 0.6, Wl.y * K + Math.sin(a / 8 * 6.28) * 2, 1.4, 1.2, 1.4, '#868e96'));
    wl.push(box(Wl.x * K, 0.3, Wl.y * K, 2.6, 0.2, 2.6, '#1864ab'));
    for (const s of [-1, 1]) wl.push(box(Wl.x * K + s * 2, 2.4, Wl.y * K, 0.3, 3.2, 0.3, '#6b4423'));
    wl.push(box(Wl.x * K, 4.1, Wl.y * K, 5, 0.4, 3, '#a33a2a'));
    const Bd = World.BOARD, bl = chunk(Bd.x * K, Bd.y * K);
    for (const s of [-1, 1]) bl.push(box(Bd.x * K + s * 1.6, 1.4, Bd.y * K, 0.3, 2.8, 0.3, '#6b4423'));
    bl.push(box(Bd.x * K, 2.2, Bd.y * K, 3.6, 1.8, 0.2, '#8a5a32'));
    for (let i = 0; i < 4; i++) bl.push(box(Bd.x * K - 1.2 + i * 0.8, 2.2 + (i % 2) * 0.3, Bd.y * K + 0.12, 0.6, 0.7, 0.04, '#fff9db'));
    addMarket();
    addSky();
    flushChunks();
    addPortal(World.PORTAL, '#9775fa');
    addPortal(World.SKY_PORTAL, '#9775fa');

    // озёра
    for (const L of World.LAKES) {
      const m = new T.Mesh(new T.CircleGeometry(1, 40), new T.MeshLambertMaterial({ color: L.magic ? '#c084fc' : '#3f8fc0', transparent: true, opacity: 0.82, emissive: L.magic ? '#6d28d9' : '#000000' }));
      m.scale.set(L.rx * K, L.ry * K, 1);
      m.rotation.x = -Math.PI / 2;
      m.position.set(L.x * K, 0.06, L.y * K);
      scene.add(m);
    }
    buildShrooms();

    // фонари
    lampMat = new T.MeshBasicMaterial({ color: '#adb5bd' });
    for (const l of World.LAMPS) {
      const m = new T.Mesh(new T.BoxGeometry(0.8, 0.8, 0.8), lampMat);
      m.position.set(l.x * K, 3.5, l.y * K);
      scene.add(m);
    }
    for (let i = 0; i < 6; i++) {
      const pl = new T.PointLight('#ffd08a', 0, 32, 1.6);
      scene.add(pl);
      lampLights.push(pl);
    }
    playerLight = new T.PointLight('#ffe2a8', 0, 26, 1.5);
    scene.add(playerLight);

    // буквы манежа — спрайты с текстом
    for (const [L, p] of Object.entries(World.LETTERS)) {
      if (L === 'X') continue;
      const off = 22;
      const bx = p.side === 'left' ? p.x - off : p.side === 'right' ? p.x + off : p.x;
      const by = p.side === 'top' ? p.y - off : p.side === 'bottom' ? p.y + off : p.y;
      const sp = textSprite(L, '#1c1c1c', '#ffffff');
      sp.position.set(bx * K, 2.2, by * K);
      sp.scale.set(1.8, 1.8, 1);
      scene.add(sp);
    }

    // искорки в Грибном королевстве
    const sp = [];
    const sr = World.rng(99);
    const M = World.MUSHROOM;
    for (let i = 0; i < 600; i++) sp.push((M.x + sr() * M.w) * K, 0.5 + sr() * 6, (M.y + sr() * M.h) * K);
    const sg = new T.BufferGeometry();
    sg.setAttribute('position', new T.Float32BufferAttribute(sp, 3));
    sparkles = new T.Points(sg, new T.PointsMaterial({ color: '#f3d9fa', size: 0.45, transparent: true, opacity: 0.85, depthWrite: false, blending: T.AdditiveBlending }));
    sparkles.userData.base = sp.slice();
    scene.add(sparkles);

    // кольца-подсказки, верёвка, предпросмотр стройки, холмик клада
    ring = new T.Mesh(new T.RingGeometry(3.6, 4.2, 40), new T.MeshBasicMaterial({ color: '#ffe066', transparent: true, opacity: 0.85, side: T.DoubleSide }));
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.08;
    scene.add(ring);
    letterRing = ring.clone();
    letterRing.material = ring.material.clone();
    letterRing.material.color.set('#ffb400');
    scene.add(letterRing);
    rope = new T.Line(new T.BufferGeometry().setFromPoints([new T.Vector3(), new T.Vector3()]), new T.LineBasicMaterial({ color: '#c9a35b' }));
    scene.add(rope);
    preview = new T.Mesh(new T.BoxGeometry(1, 1, 1), new T.MeshBasicMaterial({ color: '#69db7c', transparent: true, opacity: 0.45, depthWrite: false }));
    scene.add(preview);
    mound = new T.Group();
    mound.add(new T.Mesh(new T.BoxGeometry(1.6, 0.4, 1.6), new T.MeshLambertMaterial({ color: '#8a6a44' })));
    const sparkle = new T.Mesh(new T.BoxGeometry(0.4, 0.4, 0.4), new T.MeshBasicMaterial({ color: '#ffe066' }));
    sparkle.position.y = 1.2;
    mound.add(sparkle);
    scene.add(mound);
  }

  /* ---------- маленькие грибы ---------- */
  const SHROOM_LOOK = {
    white: { stem: '#f1e3c6', cap: '#8b5a2b', glow: false },
    chanterelle: { stem: '#f59f00', cap: '#ffb020', glow: false },
    amanita: { stem: '#f8f4ea', cap: '#e03131', glow: false, dots: true },
    glow: { stem: '#d7f5ff', cap: '#3bc9db', glow: true },
    violet: { stem: '#e5dbff', cap: '#9775fa', glow: true },
  };
  let shroomMeshes = {}, shroomVersion = '';
  function buildShrooms() {
    for (const [type, look] of Object.entries(SHROOM_LOOK)) {
      const cells = new Map();
      cells.set(key3(0, 0, 0), look.stem); cells.set(key3(0, 1, 0), look.stem);
      for (let x = -1; x <= 1; x++) for (let z = -1; z <= 1; z++) cells.set(key3(x, 2, z), look.cap);
      cells.set(key3(0, 3, 0), look.cap);
      if (look.dots) { cells.set(key3(1, 3, 0), '#ffffff'); cells.set(key3(-1, 3, 1), '#ffffff'); }
      const list = World.SHROOMS.filter(m => m.type === type);
      const im = new T.InstancedMesh(voxelGeometry(cells, 0.3, 4), look.glow ? glowMat : mat, Math.max(1, list.length));
      im.castShadow = false;
      im.userData.list = list;
      scene.add(im);
      shroomMeshes[type] = im;
    }
    updateShrooms(true);
  }
  function updateShrooms(force) {
    const ver = World.SHROOMS.filter(m => Farm.shroomPicked(m.id)).map(m => m.id).join(',');
    if (!force && ver === shroomVersion) return;
    shroomVersion = ver;
    const mtx = new T.Matrix4(), q = new T.Quaternion(), p = new T.Vector3(), s = new T.Vector3();
    for (const im of Object.values(shroomMeshes)) {
      im.userData.list.forEach((m, i) => {
        const sc = Farm.shroomPicked(m.id) ? 0.0001 : 0.8 + m.s * 0.7;
        p.set(m.x * K, 0, m.y * K); s.set(sc, sc, sc);
        q.setFromAxisAngle(new T.Vector3(0, 1, 0), m.s * 6);
        mtx.compose(p, q, s);
        im.setMatrixAt(i, mtx);
      });
      im.instanceMatrix.needsUpdate = true;
    }
  }

  function textSprite(text, color, bg) {
    const c = document.createElement('canvas');
    c.width = c.height = 64;
    const g = c.getContext('2d');
    if (bg) { g.fillStyle = bg; g.fillRect(4, 4, 56, 56); g.strokeStyle = '#555'; g.lineWidth = 3; g.strokeRect(4, 4, 56, 56); }
    g.fillStyle = color;
    g.font = 'bold 40px system-ui, sans-serif';
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(text, 32, 35);
    return new T.Sprite(new T.SpriteMaterial({ map: new T.CanvasTexture(c) }));
  }

  /* ---------- то, что меняется: жерди, препятствия ---------- */
  const RAILC = { cross: '#1c7ed6', vertical: '#e03131', oxer: '#2b8a3e', triple: '#f08c00', wall: '#c2410c' };
  function railBoxes(list, x, y, half, color, rx = 0) {
    const n = 8, seg = (half * 2) / n;
    for (let k = 0; k < n; k++) {
      const zz = -half + seg * (k + 0.5);
      list.push(box(x, y - Math.sin(rx) * zz, zz * Math.cos(rx), 0.32, 0.32, seg, k % 2 ? '#ffffff' : color, { rx }));
    }
  }
  function rebuild(name, keyStr, build) {
    const d = dynamic[name];
    if (d && d.key === keyStr) return;
    if (d) { d.obj.traverse(n => n.geometry && n.geometry.dispose()); scene.remove(d.obj); }
    const obj = build();
    scene.add(obj);
    dynamic[name] = { key: keyStr, obj };
  }

  function updateCourse(game) {
    const ex = game.exercise();
    const jump = ex && ex.type === 'jump' ? ex : null;
    const height = jump ? jump.height : 80;
    const keyStr = jump ? `${height}|${jump.i}|${jump.jumps.join(',')}` : 'idle';
    rebuild('course', keyStr, () => {
      const group = new T.Group();
      const H = height / 100 * 3.6; // 1 м ≈ 3,6 единицы (спина лошади ~1,6 м)
      World.COURSE.forEach((o, i) => {
        const list = [];
        const half = o.half * K, col = RAILC[o.type];
        const st = jump ? jump.jumps[i] : null;
        for (const z of [-half - 0.5, half + 0.5]) list.push(box(0, H / 2 + 0.6, z, 0.7, H + 1.2, 0.7, '#f8f9fa'));
        list.push(box(-0.3, 1.2, half + 1.0, 0.1, 2.4, 0.1, '#868e96'));
        list.push(box(-0.3, 2.1, half + 1.4, 0.05, 0.6, 0.8, '#e03131'));
        list.push(box(-0.3, 1.2, -half - 1.0, 0.1, 2.4, 0.1, '#868e96'));
        list.push(box(-0.3, 2.1, -half - 1.4, 0.05, 0.6, 0.8, '#ffffff'));
        const knocked = st === 'hit';
        if (o.type === 'wall') {
          list.push(box(0, (knocked ? H * 0.75 : H) / 2, 0, 1.2, knocked ? H * 0.75 : H, half * 2, '#b5532d'));
          if (knocked) list.push(box(1.6, 0.3, 0.8, 1, 0.6, 2, '#b5532d'));
        } else if (o.type === 'cross') {
          if (knocked) { railBoxes(list, 1.4, 0.2, half, col); railBoxes(list, 0, H * 0.3, half, col, 0.35); }
          else { railBoxes(list, 0, H * 0.55, half, col, 0.35); railBoxes(list, 0.35, H * 0.55, half, col, -0.35); }
        } else {
          const xs = o.type === 'oxer' ? [-0.8, 0.8] : o.type === 'triple' ? [-1.2, 0, 1.2] : [0];
          const hs = o.type === 'triple' ? [0.7, 0.85, 1] : xs.map(() => 1);
          xs.forEach((xx, k) => {
            if (o.type !== 'triple' || k === xs.length - 1) for (const zz of [-half - 0.5, half + 0.5]) list.push(box(xx, H / 2 + 0.6, zz, 0.6, H + 1.2, 0.6, '#f8f9fa'));
            const top = H * hs[k];
            if (knocked && k === xs.length - 1) railBoxes(list, xx + 1.5, 0.2, half, col);
            else railBoxes(list, xx, top, half, col);
            railBoxes(list, xx, top * 0.5, half, '#adb5bd');
          });
        }
        const m = meshOf(boxGeometry(list));
        m.position.set(o.x * K, 0, o.y * K);
        m.rotation.y = -o.a;
        group.add(m);
        const num = textSprite(String(o.n), st === 'ok' ? '#2b8a3e' : st === 'hit' ? '#c92a2a' : '#212529', jump && jump.i === i ? '#ffd43b' : '#ffffff');
        num.position.set((o.x + Math.cos(o.a + Math.PI / 2) * (o.half + 30)) * K, H + 2.4, (o.y + Math.sin(o.a + Math.PI / 2) * (o.half + 30)) * K);
        num.scale.set(1.8, 1.8, 1);
        group.add(num);
      });
      return group;
    });

    const cav = ex && ex.type === 'cav' ? ex : null;
    rebuild('cav', cav ? cav.poles.map(p => p.state).join(',') : 'idle', () => {
      const list = [], C = World.CAV, half = (C.y2 - C.y1) / 2 * K, cz = (C.y1 + C.y2) / 2 * K;
      C.poles.forEach((px, i) => {
        const st = cav ? cav.poles[i].state : null;
        for (const z of [-half, half]) {
          list.push(box(px * K, 0.35, cz + z, 0.25, 0.9, 0.25, '#6b4a2b', { rx: 0.7 }));
          list.push(box(px * K, 0.35, cz + z, 0.25, 0.9, 0.25, '#6b4a2b', { rx: -0.7 }));
        }
        const n = 8, seg = (half * 2) / n;
        for (let k = 0; k < n; k++) {
          const zz = cz - half + seg * (k + 0.5);
          list.push(box(px * K + (st === 'hit' ? 0.6 : 0), st === 'hit' ? 0.2 : 0.55, zz, 0.32, 0.32, seg, k % 2 ? '#ffffff' : st === 'ok' ? '#2e9d4f' : '#d63a3a'));
        }
      });
      return meshOf(boxGeometry(list));
    });
  }

  /* ---------- скачки, зайчики ---------- */
  let startPost = null;
  const bunnyGeo = {}, bunnyPool = [];
  function bunnyGeometry(c, belly) {
    const k = c + belly;
    if (bunnyGeo[k]) return bunnyGeo[k];
    const cells = new Map();
    const fill = (x0, x1, y0, y1, z0, z1, col) => { for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) cells.set(key3(x, y, z), col); };
    fill(-2, 1, 0, 2, -1, 1, c);       // тело
    fill(-1, 1, 0, 0, -1, 1, belly);
    fill(2, 3, 2, 3, -1, 1, c);        // голова
    fill(2, 2, 4, 6, -1, -1, c);       // уши
    fill(2, 2, 4, 6, 1, 1, c);
    fill(-3, -3, 1, 2, 0, 0, '#ffffff'); // хвостик
    cells.set(key3(4, 3, 0), '#e07a8a');
    cells.set(key3(3, 3, -2), '#1a1412'); cells.set(key3(3, 3, 2), '#1a1412');
    bunnyGeo[k] = voxelGeometry(cells, 0.32, 3);
    return bunnyGeo[k];
  }
  function updateExtras(game, t) {
    if (!startPost) {
      const st = Events.START, list = [box(st.x * K, 2, st.y * K, 0.4, 4, 0.4, '#495057')];
      for (let i = 0; i < 4; i++) for (let j = 0; j < 3; j++) list.push(box(st.x * K + 0.45 + i * 0.5, 3.5 - j * 0.5, st.y * K, 0.5, 0.5, 0.1, (i + j) % 2 ? '#111111' : '#ffffff'));
      startPost = meshOf(boxGeometry(list));
      scene.add(startPost);
    }
    const G2 = game.gates ? game.gates() : null;
    rebuild('gates', G2 ? `${G2.id}|${G2.next}` : 'none', () => {
      const group = new T.Group();
      if (!G2) return group;
      G2.list.forEach((g, i) => {
        const list = [], half = 55 * K;
        for (const z of [-half, half]) list.push(box(0, 2, z, 0.5, 4, 0.5, '#f8f9fa'));
        const n = 10, seg = (half * 2) / n;
        for (let k = 0; k < n; k++) {
          const c = g.finish ? (k % 2 ? '#111111' : '#ffffff') : (k % 2 ? '#ffffff' : i < G2.next ? '#2b8a3e' : i === G2.next ? '#ffd43b' : '#1c7ed6');
          list.push(box(0, 3.7, -half + seg * (k + 0.5), 0.2, 0.6, seg, c));
        }
        const m = meshOf(boxGeometry(list));
        m.position.set(g.x * K, 0, g.y * K);
        m.rotation.y = -g.a;
        group.add(m);
        const sp = textSprite(g.finish ? 'F' : String(g.n), '#212529', i === G2.next ? '#ffd43b' : '#ffffff');
        sp.position.set(g.x * K, 5.4, g.y * K); sp.scale.set(2, 2, 1);
        group.add(sp);
      });
      return group;
    });
    const bs = game.bunnies ? game.bunnies() : [];
    bs.forEach((b, i) => {
      let m = bunnyPool[i];
      if (!m) { m = new T.Mesh(bunnyGeometry(b.color, b.belly), mat); m.castShadow = true; scene.add(m); bunnyPool[i] = m; }
      m.geometry = bunnyGeometry(b.color, b.belly);
      m.visible = b.fade > 0.05;
      m.position.set(b.x * K, b.z * K, b.y * K);
      m.rotation.y = -b.angle;
    });
    for (let i = bs.length; i < bunnyPool.length; i++) bunnyPool[i].visible = false;
  }

  /* ---------- постройки игрока ---------- */
  function buildBoxes(b, list, glow) {
    const r = Farm.rectOf(b);
    const cx = (r.x + r.w / 2) * K, cz = (r.y + r.h / 2) * K, w = r.w * K, d = r.h * K;
    const along = r.w >= r.h;
    const t = b.type;
    if (t === 'bed') {
      list.push(box(cx, 0.2, cz, w, 0.4, d, '#6b4a2b'));
      list.push(box(cx, 0.42, cz, w - 0.6, 0.1, d - 0.6, b.wet > 0 ? '#4a3220' : '#7a5838'));
      const st = Farm.stageOf(b);
      if (st >= 0) {
        const c = Items.CROPS[b.crop];
        const n = 6;
        for (let i = 0; i < n; i++) for (let j = 0; j < 2; j++) {
          const px = along ? cx - w / 2 + (i + 0.5) * w / n : cx - w / 4 + j * w / 2;
          const pz = along ? cz - d / 4 + j * d / 2 : cz - d / 2 + (i + 0.5) * d / n;
          const hgt = [0.3, 0.7, 1.2, 1.5][st];
          if (b.crop === 'pumpkin' && st === 3) { if (i % 2 === 0) list.push(box(px, 0.9, pz, 1.2, 1, 1.2, c.color)); continue; }
          if (b.crop === 'sunflower' && st >= 2) { list.push(box(px, 0.5 + hgt, pz, 0.15, hgt * 2, 0.15, c.leaf)); if (st === 3) list.push(box(px, 0.5 + hgt * 2, pz, 0.8, 0.8, 0.2, c.color)); continue; }
          list.push(box(px, 0.45 + hgt / 2, pz, 0.35, hgt, 0.35, st === 3 && b.crop === 'oats' ? c.color : c.leaf));
          if (st === 3 && b.crop === 'carrot') list.push(box(px, 0.5, pz, 0.3, 0.2, 0.3, c.color));
          if (b.crop === 'magic' && st >= 2) glow.push(box(px, 0.5 + hgt, pz, 0.4, 0.3, 0.4, st === 3 ? '#f3d9fa' : c.color));
        }
      }
    } else if (t === 'fence') {
      const len = Math.max(w, d);
      for (let i = 0; i <= 3; i++) {
        const k = -len / 2 + i * len / 3;
        list.push(box(along ? cx + k : cx, 0.8, along ? cz : cz + k, 0.3, 1.6, 0.3, '#5e3b1d'));
      }
      for (const hy of [0.6, 1.2]) list.push(box(cx, hy, cz, along ? len : 0.18, 0.18, along ? 0.18 : len, '#8a5a32'));
    } else if (t === 'lamp') {
      list.push(box(cx, 1.6, cz, 0.3, 3.2, 0.3, '#343a40'));
      glow.push(box(cx, 3.5, cz, 0.8, 0.8, 0.8, '#ffe8a3'));
    } else if (t === 'flowerbed') {
      list.push(box(cx, 0.2, cz, w, 0.4, d, '#7a5838'));
      const rr = World.rng(b.id);
      for (let i = 0; i < 14; i++) {
        const px = cx + (rr() - 0.5) * (w - 0.6), pz = cz + (rr() - 0.5) * (d - 0.6);
        list.push(box(px, 0.6, pz, 0.15, 0.5, 0.15, '#2f9e44'));
        list.push(box(px, 0.9, pz, 0.4, 0.3, 0.4, ['#ff6b6b', '#ffd43b', '#f783ac', '#9775fa', '#ffffff'][i % 5]));
      }
    } else if (t === 'bench') {
      list.push(box(cx, 0.9, cz, along ? w : 1.6, 0.2, along ? 1.6 : d, '#8a5a32'));
      list.push(box(along ? cx : cx - 0.7, 1.6, along ? cz - 0.7 : cz, along ? w : 0.2, 1, along ? 0.2 : d, '#8a5a32'));
      for (const s of [-1, 1]) list.push(box(along ? cx + s * (w / 2 - 0.4) : cx, 0.4, along ? cz : cz + s * (d / 2 - 0.4), 0.3, 0.8, 0.3, '#5e3b1d'));
    } else if (t === 'trough') {
      list.push(box(cx, 0.5, cz, w, 1, d, '#868e96'));
      list.push(box(cx, 1.02, cz, w - 0.5, 0.05, d - 0.5, '#4dabf7'));
    } else if (t === 'haystack') {
      const s = b.used ? 0.5 : 1;
      list.push(box(cx, 1.2 * s, cz, w * 0.9, 2.4 * s, d * 0.9, '#d8b85c'));
      list.push(box(cx, 2.7 * s, cz, w * 0.6, 0.8 * s, d * 0.6, '#e4c46c'));
    } else if (t === 'tree') {
      list.push(box(cx, 1.5, cz, 0.8, 3, 0.8, '#6b4423'));
      list.push(box(cx, 4, cz, 3.4, 2.4, 3.4, '#4f8f3a'));
      list.push(box(cx, 5.3, cz, 2.2, 1, 2.2, '#6eae4c'));
      if (b.t <= 0) for (const [ax, az] of [[1.7, 0.5], [-1.2, 1.7], [0.4, -1.7], [-1.7, -0.6]]) list.push(box(cx + ax, 3.8, cz + az, 0.5, 0.5, 0.5, '#e03131'));
    } else if (t === 'bunnyhouse') {
      list.push(box(cx, 0.8, cz, w, 1.6, d, '#c0a080'));
      list.push(box(cx, 1.9, cz, w + 0.4, 0.6, d + 0.4, '#a33a2a'));
      list.push(box(cx, 2.4, cz, w * 0.6, 0.4, d * 0.6, '#a33a2a'));
      list.push(box(cx, 0.5, cz + d / 2 + 0.02, 0.8, 0.8, 0.05, '#2b2b2b'));
    } else if (t === 'well') {
      for (let a = 0; a < 8; a++) list.push(box(cx + Math.cos(a / 8 * 6.28) * 1.8, 0.6, cz + Math.sin(a / 8 * 6.28) * 1.8, 1.2, 1.2, 1.2, '#868e96'));
      list.push(box(cx, 0.3, cz, 2.2, 0.2, 2.2, '#1864ab'));
      for (const s of [-1, 1]) list.push(box(cx + s * 1.8, 2.4, cz, 0.3, 3.2, 0.3, '#6b4423'));
      list.push(box(cx, 4.1, cz, 4.4, 0.4, 2.6, '#a33a2a'));
    } else if (t === 'windmill') {
      for (let i = 0; i < 5; i++) list.push(box(cx, 1.5 + i * 3, cz, w * (0.8 - i * 0.1), 3, d * (0.8 - i * 0.1), i % 2 ? '#e9d8b5' : '#d8c4a0'));
      list.push(box(cx, 16.2, cz, w * 0.5, 1.6, d * 0.5, '#8c3b2a'));
    } else if (t === 'stable5') {
      list.push(box(cx, 0.05, cz, w, 0.1, d, '#e4c46c'));
      for (const s of World.BUILD_SOLIDS.filter(q => q.x >= r.x - 1 && q.y >= r.y - 1 && q.x + q.w <= r.x + r.w + 1 && q.y + q.h <= r.y + r.h + 1)) {
        list.push(box((s.x + s.w / 2) * K, 1.6, (s.y + s.h / 2) * K, s.w * K, 3.2, s.h * K, '#8a5a32'));
      }
      for (let k = 1; k < 5; k++) {
        if (b.rot) list.push(box(cx, 0.9, (r.y + k * r.h / 5) * K, w * 0.8, 1.8, 0.3, '#6b4423'));
        else list.push(box((r.x + k * r.w / 5) * K, 0.9, cz, 0.3, 1.8, d * 0.8, '#6b4423'));
      }
    }
  }
  function updateBuilds(game, t) {
    const S = game.S;
    const key = S.builds.map(b => `${b.id}:${b.type}:${b.rot}:${b.type === 'bed' ? Farm.stageOf(b) + (b.crop || '') + (b.wet > 0 ? 'w' : '') : ''}:${b.t > 0 ? 0 : 1}:${b.used ? 1 : 0}`).join(',');
    rebuild('builds', key, () => {
      const group = new T.Group(), list = [], glow = [];
      windmills = [];
      for (const b of S.builds) {
        buildBoxes(b, list, glow);
        if (b.type === 'windmill') {
          const bl = [];
          for (let i = 0; i < 4; i++) bl.push(box(0, 0, 0, 0.6, 9, 0.2, '#f8f4ea', { rz: i * Math.PI / 2 }));
          for (let i = 0; i < 4; i++) bl.push(box(Math.cos(i * Math.PI / 2 + Math.PI / 2) * 2.5, Math.sin(i * Math.PI / 2 + Math.PI / 2) * 2.5, 0, 1.6, 3.4, 0.1, '#d0bfa0', { rz: i * Math.PI / 2 }));
          const m = meshOf(boxGeometry(bl));
          m.position.set(b.x * K, 14, b.y * K + 3.4);
          group.add(m);
          windmills.push(m);
        }
      }
      if (list.length) group.add(meshOf(boxGeometry(list)));
      if (glow.length) group.add(glowMesh(boxGeometry(glow)));
      return group;
    });
    for (const w of windmills) w.rotation.z = t * 0.8;
    // предпросмотр стройки
    const mode = Farm.mode;
    preview.visible = !!(mode && !mode.remove);
    if (preview.visible) {
      const d = Farm.dims(mode.type, mode.rot);
      preview.scale.set(d.w * K, 2, d.h * K);
      preview.position.set(mode.x * K, 1, mode.y * K);
      preview.material.color.set(mode.ok ? '#69db7c' : '#ff6b6b');
    }
  }

  /* ---------- жители, привидения, сундук ---------- */
  const npcObjs = new Map();
  const ghostObjs = [];
  let chest = null;
  function updatePeople(game, t) {
    const p = game.S.player;
    for (const n of Quests.NPCS) {
      let o = npcObjs.get(n.id);
      if (!o) {
        o = makePersonObj(n.look, { ghost: n.ghost, fairy: n.fairy });
        o.group.position.set(n.x * K, 0, n.y * K);
        scene.add(o.group);
        npcObjs.set(n.id, o);
      }
      const d = Math.hypot(p.x - n.x, p.y - n.y);
      const want = d < 320 ? Math.atan2(p.y - n.y, p.x - n.x) : Math.sin(t * 0.3 + n.x) * 1.5;
      o.group.rotation.y += (-want - o.group.rotation.y) * 0.08;
      o.group.position.y = n.ghost || n.fairy ? 1 + Math.sin(t * 2 + n.x) * 0.5 : 0;
    }
    const gs = Creatures.ghosts();
    gs.forEach((g, i) => {
      let o = ghostObjs[i];
      if (!o) {
        if (g.kind === 'horse') {
          const fake = Horses.create({ breed: 'arab', age: 6 });
          fake.seed = g.seed;
          o = makeHorseObj(fake, Horses.pheno(fake), ghostMat);
        } else {
          const cells = new Map();
          for (let y = 0; y < 9; y++) {
            const r = y > 6 ? 1 : 2;
            for (let x = -r; x <= r; x++) for (let z = -r; z <= r; z++) {
              if (y < 2 && (x + z + 10) % 2) continue;
              cells.set(key3(x, y, z), '#ffffff');
            }
          }
          cells.set(key3(2, 6, -1), '#111111'); cells.set(key3(2, 6, 1), '#111111'); cells.set(key3(2, 4, 0), '#111111');
          const m = new T.Mesh(voxelGeometry(cells, 0.5, 1), ghostMat);
          const group = new T.Group(); group.add(m);
          o = { group, legs: [], tail: null, wings: [] };
        }
        scene.add(o.group);
        ghostObjs[i] = o;
      }
      o.group.visible = g.hidden <= 0;
      o.group.position.set(g.x * K, 1.5 + Math.sin(t * 2 + i) * 0.6, g.y * K);
      o.group.rotation.y = -g.angle;
    });
    ghostMat.opacity = 0.32 + Math.sin(t * 3) * 0.08;
    // сундук графа
    const opened = !!game.S.flags.chest_opened;
    rebuild('chest', opened ? 'open' : 'closed', () => {
      const c = World.CHEST, x = c.x * K, z = c.y * K, list = [];
      list.push(box(x, 0.7, z, 2.4, 1.4, 1.6, '#7a4a22'));
      list.push(box(x, 0.7, z, 2.5, 0.25, 1.7, '#ffd43b'));
      if (opened) list.push(box(x, 2.1, z - 0.9, 2.4, 1.4, 0.2, '#7a4a22', { rx: -0.3 }));
      else { list.push(box(x, 1.65, z, 2.4, 0.5, 1.6, '#8a5a32')); list.push(box(x, 1.2, z + 0.82, 0.4, 0.5, 0.1, '#ffd43b')); }
      return meshOf(boxGeometry(list));
    });
    // холмик над кладом, когда металлоискатель «кричит»
    let target = null;
    if (game.S.player.detector && Farm.signal() > 0.8) {
      let bd = 1e9;
      for (const s of Farm.spots().concat(game.S.bigTreasure ? [game.S.bigTreasure] : [])) { const d = Math.hypot(s.x - p.x, s.y - p.y); if (d < bd) { bd = d; target = s; } }
    }
    mound.visible = !!target;
    if (target) { mound.position.set(target.x * K, 0, target.y * K); mound.children[1].position.y = 1.2 + Math.sin(t * 6) * 0.3; }
  }

  /* ---------- инициализация ---------- */
  function init() {
    T = window.THREE;
    canvas3d = document.createElement('canvas');
    canvas3d.id = 'game3d';
    document.body.insertBefore(canvas3d, document.body.firstChild);
    renderer = new T.WebGLRenderer({ canvas: canvas3d, antialias: true });
    renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = T.PCFSoftShadowMap;
    scene = new T.Scene();
    scene.background = new T.Color('#9fd3f0');
    scene.fog = new T.Fog('#9fd3f0', 150, 320);
    camera = new T.PerspectiveCamera(45, 1, 1, 700);
    hemi = new T.HemisphereLight('#ffffff', '#5c7a3a', 0.65);
    scene.add(hemi);
    sun = new T.DirectionalLight('#fff4dd', 0.8);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    Object.assign(sun.shadow.camera, { left: -60, right: 60, top: 60, bottom: -60, near: 1, far: 240 });
    sun.shadow.bias = -0.0008;
    scene.add(sun);
    scene.add(sun.target);
    mat = new T.MeshLambertMaterial({ vertexColors: true });
    glowMat = new T.MeshBasicMaterial({ vertexColors: true });
    glassMat = new T.MeshBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.55, side: T.DoubleSide, depthWrite: false });
    ghostMat = new T.MeshBasicMaterial({ color: '#dbe4ff', transparent: true, opacity: 0.38, depthWrite: false });

    const ground = new T.Mesh(new T.PlaneGeometry(World.W * K, World.H * K), new T.MeshLambertMaterial({ map: groundTexture() }));
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(World.W * K / 2, 0, World.H * K / 2);
    ground.receiveShadow = true;
    scene.add(ground);
    // море вокруг мира — только до южного края земли, дальше — небо с облаками
    const outH = World.H * K + 4000;
    const outside = new T.Mesh(new T.PlaneGeometry(8000, outH), new T.MeshLambertMaterial({ color: '#2f7fb8' }));
    outside.rotation.x = -Math.PI / 2;
    outside.position.set(World.W * K / 2, -0.05, World.H * K - outH / 2);
    scene.add(outside);

    buildStatic();
    resize();
    addEventListener('resize', resize);
    ready = true;
  }

  function resize() {
    if (!renderer) return;
    renderer.setSize(innerWidth, innerHeight);
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
  }
  function setVisible(on) { if (canvas3d) canvas3d.style.display = on ? 'block' : 'none'; }
  function zoom(dy) { cam.zoom = Math.max(0.55, Math.min(1.8, cam.zoom * (dy > 0 ? 1.1 : 1 / 1.1))); }

  /* ---------- кадр ---------- */
  function syncHorse(h, x, y, angle, o) {
    const ph = Horses.pheno(h);
    const key = horseKey(h);
    let e = objs.get(h.id);
    if (!e || e.key !== key) {
      if (e) disposeObj(e);
      e = makeHorseObj(h, ph);
      e.key = key;
      objs.set(h.id, e);
      scene.add(e.group);
    }
    e.seen = true;
    const s = Horses.sizeOf(h);
    const lift = o.lift || 0;
    const fly = o.fly || 0;
    const hover = h.magic && h.magic.cloud ? 1.3 + Math.sin(o.t * 2 + (h.seed % 9)) * 0.35 : 0;
    e.group.position.set(x * K, hover + lift * 2.6 * s + fly * 9 + (fly ? Math.sin(o.t * 2) * 0.4 : 0), y * K);
    e.group.rotation.set(0, -angle, lift * 0.25 + fly * 0.08);
    e.group.scale.setScalar(s);
    const move = Math.min(1, (h.spd || 0) / 110);
    e.legs.forEach((l, i) => {
      const diag = (i === 0 || i === 3) ? 1 : -1;
      if (fly) l.rotation.z = (i < 2 ? 0.7 : -0.5) * fly;
      else l.rotation.z = lift ? (i < 2 ? 0.9 : -0.6) * lift : Math.sin(h.phase || 0) * diag * 0.55 * move;
    });
    e.tail.rotation.y = Math.sin(o.t * 2.2 + (h.seed % 7)) * 0.35;
    e.tail.rotation.z = move * 0.5 + fly * 0.4;
    for (const w of e.wings) {
      const f = w.f;
      const flap = fly ? Math.sin(o.t * f.speed) * f.amp : move > 0.6 ? Math.sin(o.t * f.speed * 0.7) * f.amp * 0.4 : f.rest;
      w.pivot.rotation.x = w.s * (flap + (fly ? 0.1 : 0));
    }
    if (o.rider) {
      const R = o.rider, k = `${R.pad}|${R.helmet}|${R.shirt}|${R.saddleStyle}|${R.saddleColor}|${R.bridleStyle}|${R.bridleColor}`;
      if (e.riderKey !== k) {
        if (e.rider) { e.rider.traverse(n => n.geometry && n.geometry.dispose()); e.group.remove(e.rider); }
        const rc = riderCells(R);
        e.rider = new T.Group();
        e.rider.add(meshOf(voxelGeometry(rc.cells, V, 3)));
        if (rc.glow.size) e.rider.add(glowMesh(voxelGeometry(rc.glow, V, 4)));
        e.group.add(e.rider);
        e.riderKey = k;
      }
      e.rider.visible = true;
    } else if (e.rider) e.rider.visible = false;
  }

  let girl = null;
  function syncGirl(p, t, on) {
    if (!girl || girl.shirt !== p.shirt) {
      if (girl) disposeObj(girl);
      girl = makePersonObj({ shirt: p.shirt || '#e05a8a' });
      scene.add(girl.group);
    }
    girl.group.visible = on;
    if (!on) return;
    girl.group.position.set(p.x * K, 0, p.y * K);
    girl.group.rotation.y = -p.angle;
    const sw = Math.sin(p.phase || 0) * Math.min(1, (p.spd || 0) / 60) * 0.6;
    girl.legs[0].rotation.z = sw;
    girl.legs[1].rotation.z = -sw;
  }

  function render(game) {
    if (!ready) return;
    const S = game.S, p = S.player, t = game.time();
    const m = game.mounted();
    const inCave = World.inRect(p.x, p.y, World.CAVE, 60);

    // камера следует за игроком, смотрит сверху под углом
    const narrow = innerWidth < 700;
    cam.h += ((p.fly ? 1.35 : 1) - cam.h) * 0.05;
    const dist = (narrow ? 1.3 : 1) * cam.zoom * cam.h;
    const far = Math.hypot(p.x * K - cam.x, p.y * K - cam.z) > 40;
    if (!cam.init || far) { cam.x = p.x * K; cam.z = p.y * K; cam.init = true; }
    cam.x += (p.x * K - cam.x) * 0.12;
    cam.z += (p.y * K - cam.z) * 0.12;
    camera.position.set(cam.x, 52 * dist, cam.z + 40 * dist);
    camera.lookAt(cam.x, p.fly ? 6 : 0, cam.z);

    // день и ночь; в пещере всегда темно
    const dl = inCave ? 0.04 : game.daylight();
    const day = new T.Color('#9fd3f0'), night = new T.Color(inCave ? '#050509' : '#0b1230'), dusk = new T.Color('#f4a261');
    const sky = night.clone().lerp(day, dl);
    if (dl > 0 && dl < 1 && !inCave) sky.lerp(dusk, Math.sin(dl * Math.PI) * 0.35);
    hemi.intensity = (inCave ? 0.12 : 0.25) + 0.45 * dl;
    sun.intensity = (inCave ? 0.03 : 0.12) + 0.75 * dl;
    const wet = game.weather ? game.weather() : 0;
    if (wet > 0 && !inCave) {
      sun.intensity *= 1 - 0.6 * wet;
      hemi.intensity *= 1 - 0.25 * wet;
      sky.lerp(new T.Color('#7d8794'), wet * 0.6);
    }
    const inSky = p.y > World.H - 150;
    if (inSky) sky.lerp(new T.Color('#bfe6ff'), 0.55 * dl + 0.1);
    scene.background = sky;
    scene.fog.color = sky;
    scene.fog.near = inCave ? 60 : 150; scene.fog.far = inCave ? 160 : 320;
    sun.color.set(dl > 0.2 ? (dl < 1 ? '#ffd2a1' : '#fff4dd') : '#9fb4ff');
    sun.position.set(cam.x + 30, 70, cam.z + 20);
    sun.target.position.set(cam.x, 0, cam.z);
    const dark = 1 - dl;
    lampMat.color.set(dark > 0.2 ? '#ffe8a3' : '#adb5bd');
    const lights = World.LAMPS.concat(Farm.lamps(), inCave ? torches : []);
    const near = lights.map(l => ({ l, d: Math.hypot(l.x - p.x, l.y - p.y) })).sort((a, b) => a.d - b.d);
    lampLights.forEach((pl, i) => {
      const l = near[i] && near[i].l;
      if (!l) { pl.intensity = 0; return; }
      pl.position.set(l.x * K, 3.4, l.y * K);
      pl.intensity = dark * 1.6;
    });
    // свет у игрока: огненная грива светит оранжевым, единорог — белым
    const mag = m && m.magic ? m.magic : {};
    playerLight.color.set(mag.mane === 'fire' ? '#ff8a3d' : mag.mane === 'ice' ? '#a5f3fc' : mag.horn ? '#fff9db' : '#ffe2a8');
    playerLight.distance = mag.mane || mag.horn ? 40 : 26;
    playerLight.position.set(p.x * K, 4 + (p.fly ? 9 : 0), p.y * K);
    playerLight.intensity = dark * (inCave ? 1.5 : 1.1) * (mag.mane || mag.horn ? 1.4 : 1);

    // лошади
    for (const e of objs.values()) e.seen = false;
    const view = 75; // радиус видимости в единицах
    const close = h => Math.abs(h.x * K - cam.x) < view && Math.abs(h.y * K - cam.z) < view;
    for (const h of S.horses) if (h.state !== 'ridden' && close(h)) syncHorse(h, h.x, h.y, h.angle, { t });
    for (const h of game.wild()) if (close(h)) syncHorse(h, h.x, h.y, h.angle, { t, fly: h.fly || 0 });
    const led = game.led();
    if (led) syncHorse(led, led.x, led.y, led.angle, { t });
    cam.fly = cam.fly || 0;
    cam.fly += ((p.fly ? 1 : 0) - cam.fly) * 0.06;
    if (m) syncHorse(m, p.x, p.y, p.angle, { t, rider: game.rider(), lift: game.riderLift(), fly: cam.fly });
    for (const r of (game.rivals ? game.rivals() : [])) if (close(r.h)) syncHorse(r.h, r.h.x, r.h.y, r.h.angle, { t, rider: r.rider });
    if (World.inRect(p.x, p.y, World.MARKET, 700)) for (const h of Market.stockHorses()) syncHorse(h, h.x, h.y, h.angle, { t });
    // порталы: вихрь крутится и мерцает
    for (const P of portals) {
      P.swirl.material.opacity = 0.55 + Math.sin(t * 3) * 0.15;
      P.inner.rotation.z = t * 2;
      P.swirl.material.color.setHSL((0.72 + Math.sin(t * 0.7) * 0.06) % 1, 0.8, 0.6);
      P.light.intensity = 1.3 + Math.sin(t * 4) * 0.4;
    }
    for (const [id, e] of objs) if (!e.seen) { disposeObj(e); objs.delete(id); }
    syncGirl(p, t, !m);

    // подсказки: кого можно поймать, куда ехать
    const target = game.catchable();
    ring.visible = !!target;
    if (target) {
      ring.position.set(target.x * K, 0.08, target.y * K);
      ring.scale.setScalar(Horses.sizeOf(target) * (1 + Math.sin(t * 5) * 0.06));
    }
    const ex = game.exercise();
    letterRing.visible = false;
    if (ex && ex.type === 'dres') {
      const tp = World.letterTarget(ex.targetLetter);
      letterRing.visible = true;
      letterRing.position.set(tp.x * K, 0.1, tp.y * K);
      letterRing.scale.setScalar(0.6 + Math.sin(t * 6) * 0.08);
    }
    rope.visible = !!led;
    if (led) {
      const a = rope.geometry.attributes.position;
      const s = Horses.sizeOf(led);
      a.setXYZ(0, p.x * K, m ? 7 : 3.2, p.y * K);
      a.setXYZ(1, (led.x + Math.cos(led.angle) * 50 * s) * K, 6.5 * s, (led.y + Math.sin(led.angle) * 50 * s) * K);
      a.needsUpdate = true;
    }
    // искорки над Грибным королевством
    if (Math.abs(cam.x - (World.MUSHROOM.x + World.MUSHROOM.w / 2) * K) < 260) {
      const pos = sparkles.geometry.attributes.position, b = sparkles.userData.base;
      for (let i = 0; i < pos.count; i++) pos.setY(i, b[i * 3 + 1] + Math.sin(t * 1.3 + i) * 0.8);
      pos.needsUpdate = true;
      sparkles.material.opacity = 0.35 + dark * 0.6;
    }
    updateShrooms(false);
    updateCourse(game);
    updateExtras(game, t);
    updateBuilds(game, t);
    updatePeople(game, t);
    renderer.render(scene, camera);
  }

  /* ---------- портреты лошадей для меню ---------- */
  let pr = null;
  function portrait(c, h) {
    if (!ready) return;
    if (!pr) {
      const pc = document.createElement('canvas');
      pc.width = 600; pc.height = 320;
      const r = new T.WebGLRenderer({ canvas: pc, antialias: true, alpha: true, preserveDrawingBuffer: true });
      const sc = new T.Scene();
      sc.add(new T.HemisphereLight('#ffffff', '#8a7a66', 0.8));
      const dl = new T.DirectionalLight('#ffffff', 0.6); dl.position.set(5, 10, 8); sc.add(dl);
      const camP = new T.PerspectiveCamera(30, 600 / 320, 0.1, 200);
      pr = { pc, r, sc, camP };
    }
    const o = makeHorseObj(h, Horses.pheno(h));
    const s = Horses.sizeOf(h) / (h.size || 1);
    o.group.scale.setScalar(s);
    o.group.rotation.y = -0.45;
    o.group.position.set(-1.5, 0, 0);
    for (const w of o.wings) w.pivot.rotation.x = w.s * 0.5;
    pr.sc.add(o.group);
    pr.camP.position.set(2, 6.5, 19);
    pr.camP.lookAt(1.2, 4.3, 0);
    pr.r.setClearColor(0x000000, 0);
    pr.r.render(pr.sc, pr.camP);
    pr.sc.remove(o.group);
    o.group.traverse(n => n.geometry && n.geometry.dispose());
    const ctx = c.getContext('2d');
    ctx.clearRect(0, 0, c.width, c.height);
    ctx.drawImage(pr.pc, 0, 0, c.width, c.height);
  }

  /* ---------- экран ↔ мир ---------- */
  function toWorld(clientX, clientY) {
    if (!ready) return null;
    const v = new T.Vector2((clientX / innerWidth) * 2 - 1, -(clientY / innerHeight) * 2 + 1);
    const rc = new T.Raycaster();
    rc.setFromCamera(v, camera);
    const out = new T.Vector3();
    if (!rc.ray.intersectPlane(new T.Plane(new T.Vector3(0, 1, 0), 0), out)) return null;
    return { x: out.x / K, y: out.z / K };
  }
  // h — высота в «пикселях карты»
  function project(x, y, h = 0) {
    const v = new T.Vector3(x * K, h * K, y * K).project(camera);
    return { x: (v.x + 1) / 2 * innerWidth, y: (1 - v.y) / 2 * innerHeight, ok: v.z < 1 };
  }

  return {
    load, render, toWorld, project, setVisible, zoom, portrait,
    get ready() { return ready; },
  };
})();

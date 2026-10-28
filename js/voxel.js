'use strict';
/*
 * Воксельная графика (3D из кубиков) на Three.js.
 * Рисует ту же игру, что и 2D-режим: логика общая, меняется только картинка.
 * 1 единица Three.js = 10 пикселей мира, ось Z сцены = ось Y карты.
 */
const Voxel = (() => {
  // сначала своя копия библиотеки (работает без интернета), потом CDN
  const THREE_URLS = ['js/vendor/three.min.js', 'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js'];
  const K = 0.1;        // пиксели мира → единицы сцены
  const V = 0.45;       // размер вокселя лошади
  let T = null;         // THREE
  let ready = false, loading = null;
  let renderer, scene, camera, hemi, sun, canvas3d, mat, ground;
  let lampMeshes = [], lampLights = [], playerLight;
  let dynamic = {};     // группы, которые пересобираются при смене состояния
  const objs = new Map();
  let ring, letterRing, rope;
  const camPos = { x: 0, z: 0 };

  /* ---------- загрузка библиотеки ---------- */
  function load() {
    if (ready) return Promise.resolve(true);
    if (loading) return loading;
    loading = new Promise(res => {
      const start = () => { try { init(); res(true); } catch (e) { console.error(e); res(false); } };
      if (window.THREE) return start();
      const tryUrl = i => {
        if (i >= THREE_URLS.length) return res(false);
        const s = document.createElement('script');
        s.src = THREE_URLS[i];
        s.onload = () => (window.THREE ? start() : tryUrl(i + 1));
        s.onerror = () => tryUrl(i + 1);
        document.head.appendChild(s);
      };
      tryUrl(0);
    }).then(ok => { if (!ok) loading = null; return ok; });
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

  /* ---------- модели ---------- */
  const key3 = (x, y, z) => `${x}|${y}|${z}`;
  const WHITE = '#f6f3ec';

  function horseCells(h, ph, B) {
    const rnd = World.rng(h.seed);
    const cells = new Map();
    const put = (x, y, z, c) => cells.set(key3(x, y, z), c);
    const blobs = ph.tob ? Array.from({ length: 3 + Math.floor(rnd() * 2) }, () => ({
      x: -7 + rnd() * 15, y: 8 + rnd() * 6, z: -2 + rnd() * 4, r: 2.4 + rnd() * 2,
    })) : [];
    const spot = ph.greyLevel > 0.6 ? '#3a3a3a' : Genetics.mix(ph.body, '#000000', 0.2);
    const bodyCol = (x, y, z, part, top) => {
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
    const neck = [[7, 11, 14, -2, 1], [8, 12, 15, -1, 0], [9, 13, 16, -1, 0], [10, 14, 16, -1, 0]];
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
    // грива
    const mane = B.fjordMane ? '#efe4cf' : ph.mane;
    for (const [x, , y1] of neck) {
      put(x, y1 + 1, -1, mane);
      put(x, y1 + 1, 0, B.fjordMane ? '#2a211b' : mane);
      if (B.longMane) for (let y = y1 - 2; y <= y1; y++) put(x, y, 1 + (x === 7 ? 1 : 0), mane);
    }
    put(11, 17, 0, ph.mane);                                                // чёлка
    return cells;
  }

  function legCells(h, ph, i) {
    const cells = new Map();
    const white = h.marks.legs[i] || ph.tob;
    for (let y = -7; y <= -1; y++) for (let x = -1; x <= 0; x++) for (let z = -1; z <= 0; z++) {
      let c = y >= -2 ? ph.body : ph.legs;
      if (ph.tob && y < -2) c = WHITE;
      else if (white && y <= -4) c = WHITE;
      if (y === -7) c = '#2b2420';
      cells.set(key3(x, y, z), c);
    }
    return cells;
  }

  function tailCells(ph) {
    const cells = new Map();
    const pts = [[-1, -1], [-1, -2], [-2, -2], [-2, -3], [-2, -4], [-3, -4], [-3, -5], [-3, -6], [-3, -7]];
    for (const [x, y] of pts) { cells.set(key3(x, y, -1), ph.mane); cells.set(key3(x, y, 0), ph.mane); }
    return cells;
  }

  function riderCells(R) {
    const cells = new Map();
    const put = (x, y, z, c) => cells.set(key3(x, y, z), c);
    const fill = (x0, x1, y0, y1, z0, z1, c) => { for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) put(x, y, z, c); };
    fill(-4, 1, 13, 13, -4, 3, R.pad);            // вальтрап
    fill(-3, 0, 14, 14, -2, 1, '#5b3a1e');        // седло
    fill(-4, -4, 14, 15, -2, 1, '#5b3a1e');
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
    return cells;
  }

  function girlBodyCells(shirt) {
    const cells = new Map();
    const fill = (x0, x1, y0, y1, z0, z1, c) => { for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) cells.set(key3(x, y, z), c); };
    fill(-1, 0, 7, 11, -2, 1, shirt);
    fill(-1, 0, 8, 11, -3, -3, shirt);
    fill(-1, 0, 8, 11, 2, 2, shirt);
    fill(-1, 0, 7, 7, -3, -3, '#f2c9a5');
    fill(-1, 0, 7, 7, 2, 2, '#f2c9a5');
    fill(-2, 1, 12, 15, -2, 1, '#f2c9a5');
    fill(-2, 1, 16, 16, -2, 1, '#7a4a22');
    fill(-2, -2, 12, 15, -2, 1, '#7a4a22');
    fill(-2, 1, 15, 15, -2, -2, '#7a4a22');
    fill(-2, 1, 15, 15, 1, 1, '#7a4a22');
    fill(-4, -3, 12, 14, -1, 0, '#7a4a22');
    cells.set(key3(1, 14, -1), '#2b2b2b'); cells.set(key3(1, 14, 0), '#2b2b2b');
    return cells;
  }
  function girlLegCells() {
    const cells = new Map();
    for (let y = -7; y <= -1; y++) for (let x = -1; x <= 0; x++) cells.set(key3(x, y, 0), y <= -6 ? '#1f1d22' : '#33415c');
    return cells;
  }

  function makeHorseObj(h, ph) {
    const B = Genetics.BREEDS[h.breed] || Genetics.BREEDS.mix;
    const group = new T.Group();
    group.add(meshOf(voxelGeometry(horseCells(h, ph, B), V, h.seed)));
    const legs = [];
    const LP = [[5, -1.5], [5, 1.5], [-6, -1.5], [-6, 1.5]];
    LP.forEach(([x, z], i) => {
      const pivot = new T.Group();
      pivot.position.set(x * V, 7 * V, z * V);
      pivot.add(meshOf(voxelGeometry(legCells(h, ph, i), V, h.seed + i)));
      group.add(pivot);
      legs.push(pivot);
    });
    const tail = new T.Group();
    tail.position.set(-8 * V, 12.5 * V, 0.5 * V);
    tail.add(meshOf(voxelGeometry(tailCells(ph), V, h.seed + 9)));
    group.add(tail);
    return { group, legs, tail, ph, rider: null, riderKey: '' };
  }

  function makeGirlObj(shirt) {
    const group = new T.Group();
    group.add(meshOf(voxelGeometry(girlBodyCells(shirt), V, 5)));
    const legs = [-1, 1].map(z => {
      const pivot = new T.Group();
      pivot.position.set(0, 7 * V, z * V);
      pivot.add(meshOf(voxelGeometry(girlLegCells(), V, 7)));
      group.add(pivot);
      return pivot;
    });
    return { group, legs, shirt };
  }

  function disposeObj(o) {
    o.group.traverse(n => { if (n.geometry) n.geometry.dispose(); });
    scene.remove(o.group);
  }

  /* ---------- статичная сцена ---------- */
  function groundTexture() {
    const S = 0.5;
    const c = document.createElement('canvas');
    c.width = World.W * S; c.height = World.H * S;
    const g = c.getContext('2d');
    g.scale(S, S);
    Draw.ground(g, { x: 0, y: 0, w: World.W, h: World.H });
    const A = World.ARENA;
    g.fillStyle = '#dcc394'; g.fillRect(A.x, A.y, A.w, A.h);
    g.strokeStyle = 'rgba(160,125,75,0.3)'; g.lineWidth = 26; g.strokeRect(A.x + 34, A.y + 34, A.w - 68, A.h - 68);
    const St = World.STABLE;
    g.fillStyle = '#bfb6a5'; g.fillRect(St.x, St.y, St.w, St.h);
    g.fillStyle = '#e4c46c';
    for (let i = 0; i < 20; i++) { const r = World.stallRect(i); g.fillRect(r.x + 2, r.y + 2, r.w - 4, r.h - 4); }
    const P = World.PADDOCK;
    g.fillStyle = 'rgba(70,120,40,0.18)'; g.fillRect(P.x, P.y, P.w, P.h);
    const J = World.JUMPF;
    g.fillStyle = 'rgba(60,110,30,0.16)'; g.fillRect(J.x, J.y, J.w, J.h);
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

    // деревья
    const tl = [];
    for (const tr of World.TREES) {
      const r = World.rng(tr.s);
      const x = tr.x * K, z = tr.y * K, R = tr.r * K;
      tl.push(box(x, 1.5, z, 0.9, 3, 0.9, tr.kind === 'birch' ? '#e9ecef' : '#6b4423'));
      const g1 = tr.kind === 'birch' ? '#7dbb4f' : '#4f8f3a', g2 = tr.kind === 'birch' ? '#a3d46c' : '#6eae4c';
      const n = 7 + Math.floor(R * 2);
      for (let i = 0; i < n; i++) {
        const a = r() * Math.PI * 2, d = r() * R * 0.6, sz = R * (0.5 + r() * 0.35);
        tl.push(box(x + Math.cos(a) * d, 3 + R * 0.5 + r() * R * 0.6, z + Math.sin(a) * d, sz, sz * 0.8, sz, r() < 0.4 ? g2 : g1));
      }
    }
    scene.add(meshOf(boxGeometry(tl)));

    // фонари
    const lampMat = new T.MeshBasicMaterial({ color: '#adb5bd' });
    for (const l of World.LAMPS) {
      const m = new T.Mesh(new T.BoxGeometry(0.8, 0.8, 0.8), lampMat);
      m.position.set(l.x * K, 3.5, l.y * K);
      scene.add(m);
    }
    lampMeshes = lampMat;
    for (let i = 0; i < 5; i++) {
      const pl = new T.PointLight('#ffd08a', 0, 32, 1.6);
      scene.add(pl);
      lampLights.push(pl);
    }
    playerLight = new T.PointLight('#ffe2a8', 0, 24, 1.5);
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

    // кольца-подсказки
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
    scene.fog = new T.Fog('#9fd3f0', 140, 300);
    camera = new T.PerspectiveCamera(45, 1, 1, 600);
    hemi = new T.HemisphereLight('#ffffff', '#5c7a3a', 0.65);
    scene.add(hemi);
    sun = new T.DirectionalLight('#fff4dd', 0.8);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    Object.assign(sun.shadow.camera, { left: -55, right: 55, top: 55, bottom: -55, near: 1, far: 220 });
    sun.shadow.bias = -0.0008;
    scene.add(sun);
    scene.add(sun.target);
    mat = new T.MeshLambertMaterial({ vertexColors: true });

    ground = new T.Mesh(new T.PlaneGeometry(World.W * K, World.H * K), new T.MeshLambertMaterial({ map: groundTexture() }));
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(World.W * K / 2, 0, World.H * K / 2);
    ground.receiveShadow = true;
    scene.add(ground);
    const outside = new T.Mesh(new T.PlaneGeometry(4000, 4000), new T.MeshLambertMaterial({ color: '#7fae55' }));
    outside.rotation.x = -Math.PI / 2;
    outside.position.set(World.W * K / 2, -0.05, World.H * K / 2);
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

  /* ---------- кадр ---------- */
  function syncHorse(h, x, y, angle, o) {
    const ph = Horses.pheno(h);
    let e = objs.get(h.id);
    if (!e || e.ph !== ph) {
      if (e) disposeObj(e);
      e = makeHorseObj(h, ph);
      objs.set(h.id, e);
      scene.add(e.group);
    }
    e.seen = true;
    const s = Horses.sizeOf(h);
    const lift = o.lift || 0;
    e.group.position.set(x * K, lift * 2.6 * s, y * K);
    e.group.rotation.set(0, -angle, lift * 0.25);
    e.group.scale.setScalar(s);
    const move = Math.min(1, (h.spd || 0) / 110);
    e.legs.forEach((l, i) => {
      const diag = (i === 0 || i === 3) ? 1 : -1;
      l.rotation.z = lift ? (i < 2 ? 0.9 : -0.6) * lift : Math.sin(h.phase || 0) * diag * 0.55 * move;
    });
    e.tail.rotation.y = Math.sin(o.t * 2.2 + (h.seed % 7)) * 0.35;
    e.tail.rotation.z = move * 0.5;
    if (o.rider) {
      const R = o.rider, k = `${R.pad}|${R.helmet}|${R.shirt}`;
      if (e.riderKey !== k) {
        if (e.rider) { e.rider.geometry.dispose(); e.group.remove(e.rider); }
        e.rider = meshOf(voxelGeometry(riderCells(R), V, 3));
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
      girl = makeGirlObj(p.shirt || '#e05a8a');
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

    // камера следует за игроком, смотрит сверху под углом
    const narrow = innerWidth < 700;
    const dist = narrow ? 1.3 : 1;
    const far = Math.hypot(p.x * K - camPos.x, p.y * K - camPos.z) > 40;
    if (!camPos.init || far) { camPos.x = p.x * K; camPos.z = p.y * K; camPos.init = true; }
    camPos.x += (p.x * K - camPos.x) * 0.12;
    camPos.z += (p.y * K - camPos.z) * 0.12;
    camera.position.set(camPos.x, 52 * dist, camPos.z + 40 * dist);
    camera.lookAt(camPos.x, 0, camPos.z);

    // день и ночь
    const dl = game.daylight();
    const day = new T.Color('#9fd3f0'), night = new T.Color('#0b1230'), dusk = new T.Color('#f4a261');
    const sky = night.clone().lerp(day, dl);
    if (dl > 0 && dl < 1) sky.lerp(dusk, Math.sin(dl * Math.PI) * 0.35);
    scene.background = sky;
    scene.fog.color = sky;
    hemi.intensity = 0.25 + 0.45 * dl;
    sun.intensity = 0.12 + 0.75 * dl;
    sun.color.set(dl > 0.2 ? (dl < 1 ? '#ffd2a1' : '#fff4dd') : '#9fb4ff');
    sun.position.set(camPos.x + 30, 70, camPos.z + 20);
    sun.target.position.set(camPos.x, 0, camPos.z);
    const dark = 1 - dl;
    lampMeshes.color.set(dark > 0.2 ? '#ffe8a3' : '#adb5bd');
    const near = World.LAMPS.map(l => ({ l, d: Math.hypot(l.x - p.x, l.y - p.y) })).sort((a, b) => a.d - b.d);
    lampLights.forEach((pl, i) => {
      const l = near[i].l;
      pl.position.set(l.x * K, 3.4, l.y * K);
      pl.intensity = dark * 1.6;
    });
    playerLight.position.set(p.x * K, 4, p.y * K);
    playerLight.intensity = dark * 1.1;

    // лошади
    for (const e of objs.values()) e.seen = false;
    const view = 70; // радиус видимости в единицах
    const close = h => Math.abs(h.x * K - camPos.x) < view && Math.abs(h.y * K - camPos.z) < view;
    for (const h of S.horses) if (h.state !== 'ridden' && close(h)) syncHorse(h, h.x, h.y, h.angle, { t });
    for (const h of game.wild()) if (close(h)) syncHorse(h, h.x, h.y, h.angle, { t });
    const led = game.led();
    if (led) syncHorse(led, led.x, led.y, led.angle, { t });
    if (m) syncHorse(m, p.x, p.y, p.angle, { t, rider: game.rider(), lift: game.riderLift() });
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
    updateCourse(game);
    renderer.render(scene, camera);
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
  function project(x, y, h = 0) {
    const v = new T.Vector3(x * K, h, y * K).project(camera);
    return { x: (v.x + 1) / 2 * innerWidth, y: (1 - v.y) / 2 * innerHeight, ok: v.z < 1 };
  }

  return {
    load, render, toWorld, project, setVisible,
    get ready() { return ready; },
  };
})();

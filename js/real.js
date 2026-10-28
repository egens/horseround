'use strict';
/*
 * Реалистичная 3D-графика на Three.js.
 * Те же данные игры, что и в 2D и в «кубиках», но:
 *  - лошади собраны по пропорциям настоящей лошади, со скелетом ног,
 *    шерстью, гривой и хвостом, окрас и отметины — по генам;
 *  - аллюры (шаг, рысь, галоп) анимированы с правильной последовательностью ног;
 *  - небо с солнцем, которое ходит по часам игры, мягкие тени, трава на ветру,
 *    вода, фонари ночью, звёзды.
 * Масштаб: 1 пиксель карты = 2,5 см, взрослая лошадь — 1,6 м в холке.
 */
const Real = (() => {
  const K = 0.025;
  let T = null;
  let ready = false, loading = null;
  let renderer, scene, camera, canvas3d;
  let hemi, sun, moon, sky, stars, fireflies, playerFill;
  let lampLights = [], lampGlass, halos = [];
  let grass, grassCenter = null, grassMask = null, grassTime = { value: 0 };
  let water, roofGroup, roofMats = [];
  const dynamic = {};
  const objs = new Map();
  let girl = null, ring, letterRing;
  const cam = { x: 0, z: 0, init: false, zoom: 1 };
  const mobile = Math.min(innerWidth, innerHeight) < 700;
  let tex = {};

  /* ================= загрузка ================= */
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

  /* ================= текстуры, нарисованные в коде ================= */
  const rng = s => World.rng(s);
  function canvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
  function toTex(c, repeat) {
    const t = new T.CanvasTexture(c);
    t.encoding = T.sRGBEncoding;
    t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
    if (repeat) { t.wrapS = t.wrapT = T.RepeatWrapping; }
    return t;
  }
  function noiseTex(size, base, specks, seed, repeat = true) {
    const c = canvas(size, size), g = c.getContext('2d'), r = rng(seed);
    g.fillStyle = base; g.fillRect(0, 0, size, size);
    for (const s of specks) {
      g.fillStyle = s.c;
      for (let i = 0; i < s.n; i++) {
        const x = r() * size, y = r() * size;
        if (s.line) { g.fillRect(x, y, s.w || (4 + r() * 10), s.h || 1); }
        else { const z = (s.s || 2) * (0.5 + r()); g.fillRect(x, y, z, z); }
      }
    }
    return toTex(c, repeat);
  }
  function plankTex(base, dark, seed, vertical = true) {
    const c = canvas(256, 256), g = c.getContext('2d'), r = rng(seed);
    g.fillStyle = base; g.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 8; i++) {
      g.fillStyle = `rgba(0,0,0,${0.03 + r() * 0.08})`;
      if (vertical) g.fillRect(i * 32, 0, 32, 256); else g.fillRect(0, i * 32, 256, 32);
      g.fillStyle = dark;
      if (vertical) g.fillRect(i * 32, 0, 2, 256); else g.fillRect(0, i * 32, 256, 2);
    }
    for (let i = 0; i < 900; i++) {
      g.fillStyle = r() < 0.5 ? 'rgba(0,0,0,0.06)' : 'rgba(255,255,255,0.05)';
      if (vertical) g.fillRect(r() * 256, r() * 256, 1, 8 + r() * 30); else g.fillRect(r() * 256, r() * 256, 8 + r() * 30, 1);
    }
    return toTex(c, true);
  }
  function stripeTex(c1, c2, n = 8) {
    const c = canvas(256, 16), g = c.getContext('2d');
    for (let i = 0; i < n; i++) { g.fillStyle = i % 2 ? c2 : c1; g.fillRect((256 / n) * i, 0, 256 / n + 1, 16); }
    g.fillStyle = 'rgba(0,0,0,0.12)'; g.fillRect(0, 12, 256, 4);
    g.fillStyle = 'rgba(255,255,255,0.25)'; g.fillRect(0, 2, 256, 3);
    return toTex(c, false);
  }
  function textTex(text, fg = '#1c1c1c', bg = '#ffffff', size = 128) {
    const c = canvas(size, size), g = c.getContext('2d');
    g.fillStyle = bg; g.fillRect(0, 0, size, size);
    g.strokeStyle = 'rgba(0,0,0,0.35)'; g.lineWidth = size * 0.05; g.strokeRect(0, 0, size, size);
    g.fillStyle = fg; g.font = `bold ${size * 0.62}px system-ui, sans-serif`;
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(text, size / 2, size * 0.54);
    return toTex(c, false);
  }
  function glowTex() {
    const c = canvas(64, 64), g = c.getContext('2d');
    const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    gr.addColorStop(0, 'rgba(255,230,170,1)'); gr.addColorStop(0.3, 'rgba(255,200,120,0.5)'); gr.addColorStop(1, 'rgba(255,180,90,0)');
    g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
    return new T.CanvasTexture(c);
  }
  // пряди волос: цвет + прозрачность между прядями
  function hairTex(color, seed, fjord = false) {
    const c = canvas(64, 256), g = c.getContext('2d'), r = rng(seed);
    g.clearRect(0, 0, 64, 256);
    for (let i = 0; i < 70; i++) {
      const x = r() * 64, w = 1 + r() * 2.5, len = 170 + r() * 86;
      const shade = r() * 0.35 - 0.15;
      g.fillStyle = shade > 0 ? Genetics.mix(color, '#ffffff', shade) : Genetics.mix(color, '#000000', -shade);
      g.fillRect(x, 0, w, len);
    }
    if (fjord) { g.fillStyle = '#2a211b'; g.fillRect(26, 0, 12, 256); }
    return toTex(c, false);
  }

  /* ================= геометрия ================= */
  const V3 = (x, y, z) => new T.Vector3(x, y, z);
  // «труба» по пути с эллиптическим сечением: A — радиус вверх-вниз, B — вбок
  function sweep(pts, A, B, seg = 24, caps = true) {
    const n = pts.length, P = pts.map(p => V3(p[0], p[1], p[2] || 0));
    const L = [0];
    for (let i = 1; i < n; i++) L[i] = L[i - 1] + P[i].distanceTo(P[i - 1]);
    const total = L[n - 1] || 1;
    const pos = [], uv = [], idx = [], up = V3(0, 1, 0);
    const rings = [];
    for (let i = 0; i < n; i++) {
      const t = P[Math.min(i + 1, n - 1)].clone().sub(P[Math.max(i - 1, 0)]).normalize();
      const nrm = up.clone().sub(t.clone().multiplyScalar(up.dot(t)));
      if (nrm.lengthSq() < 1e-6) nrm.set(1, 0, 0);
      nrm.normalize();
      const bin = t.clone().cross(nrm).normalize();
      rings.push({ t, nrm, bin });
      for (let j = 0; j <= seg; j++) {
        const v = j / seg, th = (v - 0.5) * Math.PI * 2;
        const p = P[i].clone().addScaledVector(nrm, Math.cos(th) * A[i]).addScaledVector(bin, Math.sin(th) * B[i]);
        pos.push(p.x, p.y, p.z);
        uv.push(L[i] / total, v);
      }
    }
    for (let i = 0; i < n - 1; i++) for (let j = 0; j < seg; j++) {
      const a = i * (seg + 1) + j, b = a + seg + 1;
      idx.push(a, a + 1, b, b, a + 1, b + 1);
    }
    if (caps) {
      for (const [ri, dir] of [[0, -1], [n - 1, 1]]) {
        const c = pos.length / 3;
        pos.push(P[ri].x, P[ri].y, P[ri].z);
        uv.push(ri ? 1 : 0, 0.5);
        for (let j = 0; j < seg; j++) {
          const a = ri * (seg + 1) + j;
          if (dir < 0) idx.push(c, a + 1, a); else idx.push(c, a, a + 1);
        }
      }
    }
    const g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new T.Float32BufferAttribute(uv, 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    // убрать шов по брюху: усредняем нормали первой и последней точки кольца
    const N = g.attributes.normal;
    for (let i = 0; i < n; i++) {
      const a = i * (seg + 1), b = a + seg;
      const x = (N.getX(a) + N.getX(b)) / 2, y = (N.getY(a) + N.getY(b)) / 2, z = (N.getZ(a) + N.getZ(b)) / 2;
      N.setXYZ(a, x, y, z); N.setXYZ(b, x, y, z);
    }
    g.userData.rings = rings;
    return g;
  }

  // капсула вдоль оси Y (низ в 0, верх в len)
  function capsule(r, len, seg = 12) {
    const pts = [];
    for (let i = 0; i <= 6; i++) { const a = -Math.PI / 2 + (i / 6) * (Math.PI / 2); pts.push(new T.Vector2(Math.cos(a) * r, r + Math.sin(a) * r)); }
    for (let i = 0; i <= 6; i++) { const a = (i / 6) * (Math.PI / 2); pts.push(new T.Vector2(Math.cos(a) * r, len - r + Math.sin(a) * r)); }
    return new T.LatheGeometry(pts, seg);
  }

  // сливаем много геометрий в одну (позиции, нормали, uv, цвета вершин)
  function merge(parts, withColor = false, withUv = true) {
    const pos = [], nor = [], uv = [], col = [];
    for (const { geo, matrix, color, uvScale } of parts) {
      let g = geo.index ? geo.toNonIndexed() : geo.clone();
      if (matrix) g.applyMatrix4(matrix);
      const P = g.attributes.position.array, Nn = g.attributes.normal.array, U = g.attributes.uv ? g.attributes.uv.array : null;
      const c = color ? new T.Color(color) : null;
      for (let i = 0; i < P.length / 3; i++) {
        pos.push(P[i * 3], P[i * 3 + 1], P[i * 3 + 2]);
        nor.push(Nn[i * 3], Nn[i * 3 + 1], Nn[i * 3 + 2]);
        if (withUv) uv.push(U ? U[i * 2] * (uvScale ? uvScale[0] : 1) : 0, U ? U[i * 2 + 1] * (uvScale ? uvScale[1] : 1) : 0);
        if (withColor) col.push(c.r, c.g, c.b);
      }
      g.dispose();
    }
    const g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(pos, 3));
    g.setAttribute('normal', new T.Float32BufferAttribute(nor, 3));
    if (withUv) g.setAttribute('uv', new T.Float32BufferAttribute(uv, 2));
    if (withColor) g.setAttribute('color', new T.Float32BufferAttribute(col, 3));
    return g;
  }
  const M = (x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1) =>
    new T.Matrix4().compose(V3(x, y, z), new T.Quaternion().setFromEuler(new T.Euler(rx, ry, rz)), V3(sx, sy, sz));
  // коробка, у которой текстура повторяется по размеру (tile — метров на один повтор)
  function boxUV(sx, sy, sz, tile = 1) {
    const g = new T.BoxGeometry(sx, sy, sz);
    const uv = g.attributes.uv;
    const dims = [[sz, sy], [sz, sy], [sx, sz], [sx, sz], [sx, sy], [sx, sy]];
    for (let f = 0; f < 6; f++) for (let k = 0; k < 4; k++) {
      const i = f * 4 + k;
      uv.setXY(i, uv.getX(i) * dims[f][0] / tile, uv.getY(i) * dims[f][1] / tile);
    }
    return g;
  }
  function mesh(geo, mat, cast = true, receive = true) {
    const m = new T.Mesh(geo, mat);
    m.castShadow = cast; m.receiveShadow = receive;
    return m;
  }
  const std = (o) => new T.MeshStandardMaterial(Object.assign({ roughness: 0.8, metalness: 0 }, o));

  /* ================= ЛОШАДЬ ================= */
  // сечения корпуса: x, центр по высоте, полувысота, полуширина (метры)
  const TORSO = [
    [-0.87, 1.30, 0.04, 0.04], [-0.83, 1.29, 0.21, 0.15], [-0.74, 1.25, 0.32, 0.24], [-0.57, 1.21, 0.37, 0.28],
    [-0.32, 1.17, 0.385, 0.29], [-0.06, 1.15, 0.395, 0.30], [0.20, 1.16, 0.385, 0.29], [0.42, 1.20, 0.37, 0.26],
    [0.60, 1.18, 0.32, 0.21], [0.72, 1.14, 0.24, 0.17], [0.79, 1.12, 0.08, 0.07],
  ];
  function torsoAt(x) {
    for (let i = 0; i < TORSO.length - 1; i++) {
      const a = TORSO[i], b = TORSO[i + 1];
      if (x >= a[0] && x <= b[0]) {
        const t = (x - a[0]) / (b[0] - a[0]);
        return { cy: a[1] + (b[1] - a[1]) * t, ry: a[2] + (b[2] - a[2]) * t, rz: a[3] + (b[3] - a[3]) * t };
      }
    }
    return { cy: 1.15, ry: 0.3, rz: 0.25 };
  }
  // кусок поверхности поверх корпуса (вальтрап, седло, подпруга)
  function bodyPatch(x0, x1, th0, th1, scale, nx = 10, nt = 12) {
    const pos = [], uv = [], idx = [];
    for (let i = 0; i <= nx; i++) {
      const x = x0 + (x1 - x0) * i / nx, s = torsoAt(x);
      for (let j = 0; j <= nt; j++) {
        const th = th0 + (th1 - th0) * j / nt;
        pos.push(x, s.cy + Math.cos(th) * s.ry * scale, Math.sin(th) * s.rz * scale);
        uv.push(i / nx, j / nt);
      }
    }
    for (let i = 0; i < nx; i++) for (let j = 0; j < nt; j++) {
      const a = i * (nt + 1) + j, b = a + nt + 1;
      idx.push(a, a + 1, b, b, a + 1, b + 1);
    }
    const g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new T.Float32BufferAttribute(uv, 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    return g;
  }

  const NECK = { pts: [[0.48, 1.30], [0.68, 1.52], [0.84, 1.72], [0.97, 1.88], [1.05, 1.99]], A: [0.30, 0.25, 0.195, 0.15, 0.12], B: [0.20, 0.165, 0.13, 0.105, 0.09] };
  const HEAD = { pts: [[0.99, 2.03], [1.09, 1.97], [1.19, 1.83], [1.29, 1.67], [1.37, 1.55], [1.42, 1.48], [1.435, 1.455]], A: [0.09, 0.14, 0.125, 0.10, 0.09, 0.075, 0.03], B: [0.085, 0.11, 0.09, 0.075, 0.072, 0.06, 0.025] };
  let WITHERS = null, POLL = null; // создаются после загрузки Three.js

  // окрас шерсти: развёртка корпуса/шеи/головы (u — вдоль, v — вокруг, 0.5 — спина)
  function coatCanvas(h, ph, part) {
    const W = part === 'body' ? 512 : 256, H = part === 'body' ? 256 : 128;
    const c = canvas(W, H), g = c.getContext('2d'), r = rng(h.seed + (part === 'body' ? 1 : part === 'neck' ? 2 : 3));
    const white = '#f3efe7';
    g.fillStyle = ph.body; g.fillRect(0, 0, W, H);
    // направление шерсти
    for (let i = 0; i < W * H / 60; i++) {
      g.fillStyle = r() < 0.5 ? 'rgba(255,255,255,0.035)' : 'rgba(0,0,0,0.045)';
      g.fillRect(r() * W, r() * H, 4 + r() * 9, 1);
    }
    const blob = (x, y, rx, ry, col, soft = false) => {
      g.fillStyle = col;
      for (const dx of [0, -W, W]) for (const dy of [0, -H, H]) {
        g.beginPath(); g.ellipse(x + dx, y + dy, rx, ry, 0, 0, Math.PI * 2); g.fill();
      }
      if (soft) {/* мягкий край */ }
    };
    if (ph.dapple) {
      for (let i = 0; i < (part === 'body' ? 70 : 25); i++) {
        const x = r() * W, y = H * (0.12 + r() * 0.76), rr = (part === 'body' ? 7 : 4) + r() * 6;
        const gr = g.createRadialGradient(x, y, 0, x, y, rr);
        gr.addColorStop(0, Genetics.mix(ph.body, '#ffffff', 0.45)); gr.addColorStop(1, 'rgba(255,255,255,0)');
        g.fillStyle = gr; g.beginPath(); g.arc(x, y, rr, 0, Math.PI * 2); g.fill();
      }
    }
    if (ph.roan && part !== 'head') {
      for (let i = 0; i < W * H / 9; i++) {
        const x = r() * W;
        if (part === 'body' && (x < W * 0.04 || x > W * 0.93)) continue;
        g.fillStyle = `rgba(255,255,255,${0.35 + r() * 0.35})`;
        g.fillRect(x, r() * H, 1.5, 1.5);
      }
    }
    if (ph.tob && part !== 'head') {
      const n = part === 'body' ? 3 + Math.floor(r() * 3) : (r() < 0.6 ? 1 : 0);
      for (let i = 0; i < n; i++) {
        const x = W * (part === 'body' ? 0.15 + r() * 0.65 : r()), rx = W * (0.08 + r() * 0.12), ry = H * (0.22 + r() * 0.2);
        for (let k = 0; k < 6; k++) blob(x + (r() - 0.5) * rx, H * 0.5 + (r() - 0.5) * ry * 0.6, rx * (0.6 + r() * 0.4), ry * (0.6 + r() * 0.4), white);
      }
      if (part === 'body' && r() < 0.6) blob(W * (0.3 + r() * 0.4), 0, W * 0.15, H * 0.2, white);
    }
    if (ph.leo && part === 'body') {
      const gr = g.createLinearGradient(0, 0, W * 0.6, 0);
      gr.addColorStop(0, white); gr.addColorStop(0.75, white); gr.addColorStop(1, 'rgba(243,239,231,0)');
      g.fillStyle = gr;
      g.beginPath(); g.ellipse(W * 0.12, H * 0.5, W * 0.48, H * 0.33, 0, 0, Math.PI * 2); g.fill();
      const spot = ph.greyLevel > 0.6 ? '#3a3a3a' : Genetics.mix(ph.body, '#000000', 0.15);
      for (let i = 0; i < 45; i++) {
        const a = r() * Math.PI * 2, d = Math.sqrt(r());
        const x = W * 0.12 + Math.cos(a) * d * W * 0.42, y = H * 0.5 + Math.sin(a) * d * H * 0.28;
        g.fillStyle = spot; g.beginPath(); g.ellipse(x, y, 4 + r() * 5, 3 + r() * 4, r() * 3, 0, Math.PI * 2); g.fill();
      }
    }
    if (ph.stripe && part !== 'head') { g.fillStyle = ph.stripe; g.fillRect(0, H / 2 - 2, W, 4); }
    if (part === 'head') {
      // морда темнее (или розовая у изабелловых и с лысиной)
      const muzzle = (ph.pinkSkin || h.marks.face === 3) ? '#d6a091' : Genetics.mix(ph.body, '#000000', 0.42);
      const gr = g.createLinearGradient(W * 0.72, 0, W * 0.92, 0);
      gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, muzzle);
      g.fillStyle = gr; g.fillRect(W * 0.72, 0, W * 0.28, H);
      g.fillStyle = muzzle; g.fillRect(W * 0.92, 0, W * 0.08, H);
      if (h.marks.face === 1) blob(W * 0.2, H * 0.5, W * 0.05, H * 0.06, white);
      if (h.marks.face === 2) {
        blob(W * 0.2, H * 0.5, W * 0.05, H * 0.06, white);
        g.fillStyle = white;
        g.beginPath(); g.moveTo(W * 0.2, H * 0.47); g.lineTo(W * 0.97, H * 0.44); g.lineTo(W * 0.97, H * 0.56); g.lineTo(W * 0.2, H * 0.53); g.fill();
      }
      if (h.marks.face === 3) { g.fillStyle = white; g.fillRect(W * 0.12, H * 0.3, W * 0.8, H * 0.4); }
    }
    // объём: брюхо темнее, спина чуть светлее
    const sh = g.createLinearGradient(0, 0, 0, H);
    sh.addColorStop(0, 'rgba(0,0,0,0.22)'); sh.addColorStop(0.28, 'rgba(0,0,0,0)');
    sh.addColorStop(0.5, 'rgba(255,255,255,0.06)'); sh.addColorStop(0.72, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,0.22)');
    g.fillStyle = sh; g.fillRect(0, 0, W, H);
    return c;
  }

  // текстура ноги сверху вниз: цвет корпуса → цвет ног (у гнедых чёрные «чулки»), белые отметины
  function legCanvas(h, ph, i, hind) {
    const c = canvas(8, 256), g = c.getContext('2d');
    const gr = g.createLinearGradient(0, 0, 0, 256);
    gr.addColorStop(0, ph.body); gr.addColorStop(hind ? 0.42 : 0.36, ph.body); gr.addColorStop(hind ? 0.55 : 0.5, ph.legs); gr.addColorStop(1, ph.legs);
    g.fillStyle = gr; g.fillRect(0, 0, 8, 256);
    const white = ph.tob ? 0.5 : h.marks.legs[i] ? 0.2 + (h.seed % 5) * 0.05 : 0;
    if (white) {
      const y0 = 256 * (1 - white);
      const wg = g.createLinearGradient(0, y0 - 6, 0, y0 + 6);
      wg.addColorStop(0, 'rgba(243,239,231,0)'); wg.addColorStop(1, '#f3efe7');
      g.fillStyle = wg; g.fillRect(0, y0 - 6, 8, 12);
      g.fillStyle = '#f3efe7'; g.fillRect(0, y0 + 6, 8, 256);
    }
    return { c, white: !!white };
  }

  // сегмент ноги: цилиндр сверху вниз, uv по всей длине ноги
  function legSeg(len, r0, r1, v0, v1) {
    const g = new T.CylinderGeometry(r0, r1, len, 10, 3);
    g.translate(0, -len / 2, 0);
    const uv = g.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setY(i, 1 - (v0 + (1 - uv.getY(i)) * (v1 - v0)));
    return g;
  }

  const shared = {};
  function sharedMats() {
    if (shared.hoof) return shared;
    shared.hoof = std({ color: '#2f2a27', roughness: 0.55 });
    shared.hoofLight = std({ color: '#8f8475', roughness: 0.6 });
    shared.eye = std({ color: '#120d0b', roughness: 0.08, metalness: 0.2 });
    shared.nostril = std({ color: '#1a1412', roughness: 0.9 });
    shared.leather = std({ color: '#4a2d17', roughness: 0.55 });
    shared.leatherDark = std({ color: '#2a1a10', roughness: 0.5 });
    shared.metal = std({ color: '#c8ccd0', roughness: 0.3, metalness: 0.9 });
    shared.skin = std({ color: '#f0c7a2', roughness: 0.7 });
    shared.boots = std({ color: '#1b1a1d', roughness: 0.35 });
    shared.breeches = std({ color: '#e9e0cc', roughness: 0.85 });
    shared.hair = std({ color: '#7a4a22', roughness: 0.8 });
    return shared;
  }

  function buildHorse(h, ph) {
    const B = Genetics.BREEDS[h.breed] || Genetics.BREEDS.mix;
    const S = sharedMats();
    const disposables = [];
    const coatMat = part => {
      const t = toTex(coatCanvas(h, ph, part));
      disposables.push(t);
      const m = std({ map: t, roughness: B.sheen ? 0.38 : 0.62 });
      disposables.push(m);
      return m;
    };
    const root = new T.Group();
    const body = new T.Group();
    root.add(body);

    // корпус
    const torso = mesh(sweep(TORSO.map(s => [s[0], s[1], 0]), TORSO.map(s => s[2]), TORSO.map(s => s[3]), 28), coatMat('body'));
    body.add(torso);

    // шея и голова на шарнирах (опустить к траве, повернуть)
    const neckPivot = new T.Group();
    neckPivot.position.copy(WITHERS);
    body.add(neckPivot);
    const neckGeo = sweep(NECK.pts.map(p => [p[0], p[1], 0]), NECK.A, NECK.B, 20);
    neckGeo.translate(-WITHERS.x, -WITHERS.y, 0);
    neckPivot.add(mesh(neckGeo, coatMat('neck')));
    const headPivot = new T.Group();
    headPivot.position.copy(POLL).sub(WITHERS);
    neckPivot.add(headPivot);
    const headGeo = sweep(HEAD.pts.map(p => [p[0], p[1], 0]), HEAD.A, HEAD.B, 20);
    headGeo.translate(-POLL.x, -POLL.y, 0);
    const headMat = coatMat('head');
    headPivot.add(mesh(headGeo, headMat));
    // глаза, ноздри, уши
    for (const z of [-1, 1]) {
      const eye = mesh(new T.SphereGeometry(0.024, 10, 8), S.eye, false);
      eye.position.set(1.135 - POLL.x, 1.905 - POLL.y, z * 0.098);
      headPivot.add(eye);
      const nos = mesh(new T.SphereGeometry(0.018, 8, 6), S.nostril, false);
      nos.scale.set(1, 0.6, 1);
      nos.position.set(1.425 - POLL.x, 1.49 - POLL.y, z * 0.04);
      headPivot.add(nos);
      const earG = new T.ConeGeometry(0.038, 0.15, 8);
      earG.translate(0, 0.075, 0);
      const ear = mesh(earG, headMat);
      ear.position.set(1.0 - POLL.x, 2.08 - POLL.y, z * 0.055);
      ear.rotation.set(z * 0.25, 0, -0.2);
      ear.scale.set(1, 1, 0.55);
      headPivot.add(ear);
    }

    // грива и чёлка
    const hairT = hairTex(B.fjordMane ? '#efe4cf' : ph.mane, h.seed, B.fjordMane);
    disposables.push(hairT);
    const hairMat = std({ map: hairT, alphaTest: 0.45, side: T.DoubleSide, roughness: 0.75, transparent: false });
    disposables.push(hairMat);
    const maneLen = B.longMane ? 0.48 : B.fjordMane ? 0.12 : 0.24;
    {
      const pos = [], uv = [], idx = [];
      const rings = neckGeo.userData.rings;
      const strands = 14;
      for (let s = 0; s < strands; s++) {
        const f = s / (strands - 1) * (NECK.pts.length - 1);
        const i0 = Math.min(Math.floor(f), NECK.pts.length - 2), t = f - i0;
        const lerp = (a, b) => a + (b - a) * t;
        const px = lerp(NECK.pts[i0][0], NECK.pts[i0 + 1][0]), py = lerp(NECK.pts[i0][1], NECK.pts[i0 + 1][1]);
        const nrm = rings[i0].nrm.clone().lerp(rings[i0 + 1].nrm, t).normalize();
        const tan = rings[i0].t.clone().lerp(rings[i0 + 1].t, t).normalize();
        const a = lerp(NECK.A[i0], NECK.A[i0 + 1]);
        const base = V3(px, py, 0).addScaledVector(nrm, a * 0.92);
        const w = 0.1;
        let end;
        if (B.fjordMane) end = base.clone().addScaledVector(nrm, maneLen);
        else end = base.clone().add(V3(0, -maneLen * (0.8 + (s % 3) * 0.1), 0.09 + lerp(NECK.B[i0], NECK.B[i0 + 1]) * 0.9));
        const mid = base.clone().lerp(end, 0.4).add(V3(0, 0, B.fjordMane ? 0 : 0.06));
        const k = pos.length / 3;
        for (const [p, v] of [[base, 1], [mid, 0.6], [end, 0]]) {
          const q0 = p.clone().addScaledVector(tan, -w / 2), q1 = p.clone().addScaledVector(tan, w / 2);
          pos.push(q0.x - WITHERS.x, q0.y - WITHERS.y, q0.z, q1.x - WITHERS.x, q1.y - WITHERS.y, q1.z);
          uv.push((s % 4) * 0.25, v, (s % 4) * 0.25 + 0.25, v);
        }
        idx.push(k, k + 2, k + 1, k + 1, k + 2, k + 3, k + 2, k + 4, k + 3, k + 3, k + 4, k + 5);
      }
      const g = new T.BufferGeometry();
      g.setAttribute('position', new T.Float32BufferAttribute(pos, 3));
      g.setAttribute('uv', new T.Float32BufferAttribute(uv, 2));
      g.setIndex(idx);
      g.computeVertexNormals();
      neckPivot.add(mesh(g, hairMat, true, false));
      // чёлка
      const fg = new T.PlaneGeometry(0.11, 0.2);
      fg.translate(0, -0.1, 0);
      const fl = mesh(fg, hairMat, false, false);
      fl.position.set(1.04 - POLL.x, 2.07 - POLL.y, 0);
      fl.rotation.set(0, Math.PI / 2, 0.55);
      headPivot.add(fl);
    }

    // хвост
    const tailPivot = new T.Group();
    tailPivot.position.set(-0.84, 1.42, 0);
    body.add(tailPivot);
    const tailLen = B.feather ? 1.05 : 0.9;
    const tailGeo = sweep(
      [[0, 0], [-0.08, -0.04], [-0.14, -0.18], [-0.17, -0.42], [-0.16, -tailLen * 0.8], [-0.14, -tailLen]].map(p => [p[0], p[1], 0]),
      [0.05, 0.06, 0.08, 0.09, 0.09, 0.02], [0.05, 0.06, 0.08, 0.1, 0.11, 0.03], 12);
    tailPivot.add(mesh(tailGeo, hairMat, true, false));
    // вторая «прядь» поверх — объём
    const tail2 = mesh(tailGeo.clone(), hairMat, false, false);
    tail2.scale.set(1.05, 0.95, 1.25);
    tail2.rotation.y = 0.15;
    tailPivot.add(tail2);

    // ноги: плечо/бедро → колено/скакательный → путо → копыто
    const legs = [];
    const LEGDEF = [
      { x: 0.47, y: 0.98, z: -0.15, hind: false }, { x: 0.47, y: 0.98, z: 0.15, hind: false },
      { x: -0.56, y: 1.1, z: -0.16, hind: true }, { x: -0.56, y: 1.1, z: 0.16, hind: true },
    ];
    LEGDEF.forEach((d, i) => {
      const { c, white } = legCanvas(h, ph, i, d.hind);
      const t = toTex(c); disposables.push(t);
      const m = std({ map: t, roughness: B.sheen ? 0.4 : 0.65 }); disposables.push(m);
      const L1 = d.hind ? 0.52 : 0.44, L2 = d.hind ? 0.40 : 0.33, L3 = 0.13, L4 = 0.085;
      const tot = L1 + L2 + L3;
      const top = new T.Group(); top.position.set(d.x, d.y, d.z); body.add(top);
      top.add(mesh(legSeg(L1 + 0.12, d.hind ? 0.14 : 0.11, 0.055, 0, L1 / tot), m));
      top.children[0].position.y = 0.12;
      const knee = new T.Group(); knee.position.y = -L1; top.add(knee);
      knee.add(mesh(legSeg(L2, 0.045, 0.038, L1 / tot, (L1 + L2) / tot), m));
      if (B.feather) {
        const fth = mesh(new T.CylinderGeometry(0.05, 0.1, 0.18, 10), hairMat, false);
        fth.position.y = -L2 - 0.05; knee.add(fth);
      }
      const boot = mesh(new T.CylinderGeometry(0.058, 0.058, 0.2, 10), std({ color: '#ffffff', roughness: 0.9 }), false);
      boot.position.y = -L2 + 0.12; boot.visible = false; knee.add(boot);
      disposables.push(boot.material);
      const fet = new T.Group(); fet.position.y = -L2; knee.add(fet);
      const past = mesh(legSeg(L3, 0.04, 0.042, (L1 + L2) / tot, 1), m);
      fet.add(past);
      const hoofG = new T.CylinderGeometry(0.045, 0.06, L4, 12);
      hoofG.translate(0.01, -L3 - L4 / 2, 0);
      fet.add(mesh(hoofG, white ? S.hoofLight : S.hoof));
      legs.push({ top, knee, fet, hind: d.hind, base: d.hind ? -0.26 : 0, kneeBase: d.hind ? 0.3 : 0, fetBase: d.hind ? 0.12 : 0.12, boot });
      // путо чуть наклонено вперёд
      fet.rotation.z = 0.12;
    });

    // амуниция (видна только под всадницей)
    const tack = new T.Group();
    body.add(tack);
    const padMat = std({ color: '#c0392b', roughness: 0.9 }); disposables.push(padMat);
    tack.add(mesh(bodyPatch(-0.32, 0.22, -1.25, 1.25, 1.025), padMat, true, false));
    tack.add(mesh(bodyPatch(-0.22, 0.12, -0.75, 0.75, 1.07), S.leather, true, false));
    tack.add(mesh(bodyPatch(-0.12, 0.1, 0.75, 1.55, 1.05), S.leather, false, false));
    tack.add(mesh(bodyPatch(-0.12, 0.1, -1.55, -0.75, 1.05), S.leather, false, false));
    tack.add(mesh(bodyPatch(0.12, 0.18, 1.2, Math.PI * 2 - 1.2, 1.02), S.leatherDark, false, false));
    const cantle = mesh(new T.SphereGeometry(0.1, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), S.leather);
    cantle.scale.set(0.5, 0.55, 1.4); cantle.position.set(-0.2, 1.58, 0); tack.add(cantle);
    const pommel = cantle.clone(); pommel.position.set(0.14, 1.6, 0); pommel.scale.set(0.5, 0.45, 1.1); tack.add(pommel);
    // уздечка
    const nose = mesh(new T.TorusGeometry(1, 0.012, 6, 24), S.leatherDark, false);
    nose.scale.set(0.085, 0.075, 0.075); nose.position.set(1.33 - POLL.x, 1.62 - POLL.y, 0); nose.rotation.set(0, Math.PI / 2, 0.55);
    headPivot.add(nose);
    const crown = nose.clone(); crown.scale.set(0.13, 0.12, 0.11); crown.position.set(1.05 - POLL.x, 1.97 - POLL.y, 0); crown.rotation.set(0, Math.PI / 2, 0.3);
    headPivot.add(crown);
    const reins = new T.Line(new T.BufferGeometry().setFromPoints([V3(), V3(), V3()]), new T.LineBasicMaterial({ color: '#2a1a10' }));
    disposables.push(reins.material);
    root.add(reins);
    tack.userData = { padMat, reins, nose, crown };

    root.traverse(o => { if (o.isMesh) o.castShadow = o.castShadow !== false; });
    return {
      root, body, neckPivot, headPivot, tailPivot, legs, tack, rider: null, ph,
      phase: Math.random(), graze: 0, gait: 0, disposables, idle: Math.random() * 10, lastSeen: 0,
    };
  }

  /* ---------- аллюры ---------- */
  // смещение фаз ног: [ЛП, ПП, ЛЗ, ПЗ] (передние левая/правая, задние левая/правая)
  const GAITS = {
    walk: { freq: 0.95, duty: 0.66, amp: 0.3, knee: 0.9, offs: [0.25, 0.75, 0, 0.5], bob: 0.015, nod: 0.07 },
    trot: { freq: 1.4, duty: 0.48, amp: 0.4, knee: 1.25, offs: [0, 0.5, 0.5, 0], bob: 0.045, nod: 0.03 },
    canter: { freq: 1.7, duty: 0.42, amp: 0.55, knee: 1.35, offs: [0.3, 0.45, 0.0, 0.3], bob: 0.06, nod: 0.12 },
    gallop: { freq: 2.15, duty: 0.36, amp: 0.68, knee: 1.6, offs: [0.45, 0.57, 0.0, 0.12], bob: 0.07, nod: 0.14 },
  };
  const smooth = t => t * t * (3 - 2 * t);
  function legPose(p, G, hind) {
    if (p < G.duty) {
      const t = p / G.duty;
      return { hip: G.amp * (1 - 2 * t), knee: 0, fet: -0.25 * Math.sin(Math.PI * t) };
    }
    const t = (p - G.duty) / (1 - G.duty);
    const flex = Math.sin(Math.PI * t) * G.knee;
    return { hip: -G.amp + 2 * G.amp * smooth(t), knee: hind ? flex * 0.8 : -flex, fet: hind ? -flex * 0.6 : -flex * 0.5 };
  }

  function animateHorse(e, h, o, dt) {
    const s = Horses.sizeOf(h);
    const spd = (h.spd || 0) * K / Math.max(0.6, s); // м/с в масштабе лошади
    let gname = null;
    if (o.gait != null) gname = spd < 0.25 ? null : ['walk', 'trot', 'canter'][o.gait];
    else if (spd > 0.25) gname = spd < 2.4 ? 'walk' : spd < 4.3 ? 'trot' : spd < 5.6 ? 'canter' : 'gallop';
    if (o.flee && spd > 3) gname = 'gallop';
    const G = gname ? GAITS[gname] : null;
    const lift = o.lift || 0;
    e.idle += dt;
    if (G) e.phase = (e.phase + dt * G.freq * Math.min(1.4, Math.max(0.6, spd / (gname === 'walk' ? 1.7 : gname === 'trot' ? 3.6 : 5.2)))) % 1;

    // ноги
    e.legs.forEach((l, i) => {
      let pose = { hip: 0, knee: 0, fet: 0 };
      if (lift > 0) {
        pose = l.hind ? { hip: -0.5 * lift, knee: 0.5 * lift, fet: -0.3 * lift } : { hip: 0.7 * lift, knee: -1.9 * lift, fet: -0.6 * lift };
      } else if (G) {
        pose = legPose((e.phase + G.offs[i]) % 1, G, l.hind);
      } else {
        // стоит: чуть отставленная задняя нога
        if (i === 3) pose = { hip: -0.05, knee: 0.15, fet: -0.2 };
      }
      l.top.rotation.z = l.base + pose.hip;
      l.knee.rotation.z = l.kneeBase + pose.knee;
      l.fet.rotation.z = 0.12 + pose.fet;
    });

    // корпус: покачивание и наклоны
    let bob = 0, pitch = 0;
    if (G) {
      const ph2 = e.phase * Math.PI * 2;
      if (gname === 'trot') bob = Math.abs(Math.sin(ph2 * 2)) * G.bob;
      else if (gname === 'walk') bob = Math.sin(ph2 * 2) * G.bob;
      else { bob = Math.sin(ph2) * G.bob; pitch = Math.sin(ph2 + 0.8) * 0.05; }
    }
    if (lift > 0) { const k = o.liftPhase || 0; pitch = (k < 0.5 ? 0.35 : -0.25) * Math.sin(Math.PI * k); bob = 0; }
    e.body.position.y = bob + (G ? 0 : Math.sin(e.idle * 1.2) * 0.004);
    e.body.rotation.z = pitch;
    e.root.position.y = lift * 1.1 * s;

    // шея: пастись, кивать в такт
    const grazeTarget = o.graze ? 1 : 0;
    e.graze += (grazeTarget - e.graze) * Math.min(1, dt * 1.5);
    let nod = 0;
    if (G) nod = Math.sin(e.phase * Math.PI * 2 * (gname === 'walk' ? 2 : 1)) * G.nod;
    e.neckPivot.rotation.z = -e.graze * 1.15 + nod + (gname === 'gallop' ? -0.25 : gname === 'canter' ? -0.12 : 0) + (lift > 0 ? -0.2 * lift : 0);
    e.headPivot.rotation.z = e.graze * 0.55 - nod * 0.5;
    e.neckPivot.rotation.y = G ? 0 : Math.sin(e.idle * 0.35 + h.seed) * 0.18 * (1 - e.graze);
    // хвост: помахивает, на галопе развевается
    const run = gname === 'gallop' || gname === 'canter' ? 1 : gname === 'trot' ? 0.5 : 0;
    e.tailPivot.rotation.y = Math.sin(e.idle * (G ? 3 : 1.4) + h.seed % 7) * (G ? 0.12 : 0.35);
    e.tailPivot.rotation.z = run * 0.9 + lift * 0.6;
  }

  /* ================= ЧЕЛОВЕК ================= */
  function buildHuman(c) {
    const S = sharedMats();
    const shirt = std({ color: c.shirt, roughness: 0.85 });
    const helmetMat = std({ color: c.helmet || '#222a3a', roughness: 0.25, metalness: 0.1 });
    const root = new T.Group();
    const pelvis = new T.Group(); pelvis.position.y = 0.74; root.add(pelvis);
    const hips = mesh(new T.SphereGeometry(0.12, 14, 10), c.breeches ? S.breeches : std({ color: '#33415c', roughness: 0.9 }));
    hips.scale.set(0.85, 0.7, 1.15); pelvis.add(hips);
    const torso = mesh(capsule(0.12, 0.44), shirt); torso.scale.set(0.82, 1, 1.25); torso.position.y = 0.0; pelvis.add(torso);
    const neck = mesh(new T.CylinderGeometry(0.04, 0.045, 0.1, 8), S.skin); neck.position.y = 0.48; pelvis.add(neck);
    const head = new T.Group(); head.position.y = 0.62; pelvis.add(head);
    head.add(mesh(new T.SphereGeometry(0.105, 18, 14), S.skin));
    for (const z of [-1, 1]) {
      const eye = mesh(new T.SphereGeometry(0.013, 8, 6), S.eye, false); eye.position.set(0.095, 0.015, z * 0.035); head.add(eye);
    }
    const hair = mesh(new T.SphereGeometry(0.112, 18, 12, 0, Math.PI * 2, 0, Math.PI * 0.62), S.hair);
    hair.rotation.z = 0.35; hair.position.x = -0.01; head.add(hair);
    const tail = mesh(capsule(0.035, 0.2), S.hair); tail.position.set(-0.11, -0.12, 0); tail.rotation.z = -0.3; head.add(tail);
    const helmet = mesh(new T.SphereGeometry(0.125, 18, 12, 0, Math.PI * 2, 0, Math.PI / 2), helmetMat);
    helmet.position.y = 0.01; head.add(helmet);
    const visor = mesh(new T.CylinderGeometry(0.06, 0.06, 0.012, 16, 1, false, -Math.PI / 2, Math.PI), helmetMat);
    visor.position.set(0.1, 0.02, 0); visor.scale.set(1.2, 1, 1.8); head.add(visor);
    const arms = [], legs = [];
    for (const z of [-1, 1]) {
      const sh = new T.Group(); sh.position.set(0, 0.4, z * 0.17); pelvis.add(sh);
      const up = mesh(capsule(0.042, 0.25), shirt); up.rotation.z = Math.PI; sh.add(up);
      const el = new T.Group(); el.position.y = -0.23; sh.add(el);
      const fo = mesh(capsule(0.036, 0.22), shirt); fo.rotation.z = Math.PI; el.add(fo);
      const hand = mesh(new T.SphereGeometry(0.035, 8, 6), S.skin); hand.position.y = -0.23; el.add(hand);
      arms.push({ sh, el, hand });
      const hip = new T.Group(); hip.position.set(0, -0.02, z * 0.08); pelvis.add(hip);
      const th = mesh(capsule(0.062, 0.36), c.breeches ? S.breeches : std({ color: '#33415c', roughness: 0.9 })); th.rotation.z = Math.PI; hip.add(th);
      const kn = new T.Group(); kn.position.y = -0.34; hip.add(kn);
      const shin = mesh(capsule(0.052, 0.34), S.boots); shin.rotation.z = Math.PI; kn.add(shin);
      const foot = mesh(new T.BoxGeometry(0.2, 0.06, 0.08), S.boots); foot.position.set(0.05, -0.33, 0); kn.add(foot);
      legs.push({ hip, kn });
    }
    root.traverse(o => { if (o.isMesh) o.castShadow = true; });
    return { root, pelvis, head, hair, tail, helmet, visor, arms, legs, shirt, helmetMat, phase: 0, key: '' };
  }

  function poseHuman(hm, mode, phase, amt = 1) {
    const sw = Math.sin(phase * Math.PI * 2) * amt;
    if (mode === 'ride') {
      hm.pelvis.position.set(0, 0, 0);
      hm.legs.forEach((l, i) => {
        const z = i ? 1 : -1;
        l.hip.rotation.set(-z * 0.62, 0, 1.05);
        l.kn.rotation.set(0, 0, -1.45);
      });
      hm.arms.forEach((a, i) => {
        const z = i ? 1 : -1;
        a.sh.rotation.set(z * 0.12, 0, 0.75);
        a.el.rotation.set(0, 0, 0.9);
      });
      hm.pelvis.rotation.z = 0.08;
      return;
    }
    hm.pelvis.rotation.z = 0;
    hm.pelvis.position.set(0, 0.74 + Math.abs(sw) * 0.02, 0);
    hm.legs.forEach((l, i) => {
      const s = i ? sw : -sw;
      l.hip.rotation.set(0, 0, s * 0.5);
      l.kn.rotation.set(0, 0, -Math.max(0, -s) * 0.7);
    });
    hm.arms.forEach((a, i) => {
      const s = i ? -sw : sw;
      a.sh.rotation.set((i ? 1 : -1) * 0.08, 0, s * 0.45);
      a.el.rotation.set(0, 0, 0.15 + Math.max(0, s) * 0.3);
    });
  }

  /* ================= ОКРУЖЕНИЕ ================= */
  function groundCanvas() {
    const S = 2048 / World.W;
    const c = canvas(2048, Math.round(World.H * S)), g = c.getContext('2d');
    g.scale(S, S);
    Draw.ground(g, { x: 0, y: 0, w: World.W, h: World.H });
    const A = World.ARENA;
    g.fillStyle = '#d6bd8c'; g.fillRect(A.x, A.y, A.w, A.h);
    g.strokeStyle = 'rgba(150,115,70,0.35)'; g.lineWidth = 30; g.strokeRect(A.x + 34, A.y + 34, A.w - 68, A.h - 68);
    const St = World.STABLE;
    g.fillStyle = '#a9a39a'; g.fillRect(St.x, St.y, St.w, St.h);
    g.fillStyle = '#d9b862';
    for (let i = 0; i < 20; i++) { const r = World.stallRect(i); g.fillRect(r.x, r.y, r.w, r.h); }
    const P = World.PADDOCK;
    g.fillStyle = 'rgba(90,110,40,0.22)'; g.fillRect(P.x, P.y, P.w, P.h);
    // вытоптанная земля у ворот и поилки
    g.fillStyle = 'rgba(140,110,70,0.35)';
    g.beginPath(); g.ellipse(World.PADDOCK_GATE.x1 + 55, P.y + P.h - 20, 90, 40, 0, 0, Math.PI * 2); g.fill();
    return c;
  }

  function makeGround() {
    const gc = groundCanvas();
    const ctx2 = gc.getContext('2d');
    const data = ctx2.getImageData(0, 0, gc.width, gc.height).data;
    grassMask = { w: gc.width, h: gc.height, s: gc.width / World.W, data };
    const map = toTex(gc);
    const detail = noiseTex(512, '#a8a8a8', [{ c: '#8c8c8c', n: 9000, s: 2 }, { c: '#c4c4c4', n: 9000, s: 2 }, { c: '#7a7a7a', n: 2500, line: true, w: 2, h: 6 }], 11);
    const mat = std({ map, roughness: 1 });
    mat.onBeforeCompile = sh => {
      sh.uniforms.detailMap = { value: detail };
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', '#include <common>\nuniform sampler2D detailMap;')
        .replace('#include <map_fragment>', '#include <map_fragment>\n  diffuseColor.rgb *= texture2D(detailMap, vUv * vec2(60.0, 38.0)).rgb * 1.12;');
    };
    const g = new T.PlaneGeometry(World.W * K, World.H * K, 1, 1);
    const ground = mesh(g, mat, false, true);
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(World.W * K / 2, 0, World.H * K / 2);
    scene.add(ground);
    const outside = mesh(new T.PlaneGeometry(600, 600), std({ color: '#5f8a3c', roughness: 1 }), false, true);
    outside.rotation.x = -Math.PI / 2;
    outside.position.set(World.W * K / 2, -0.02, World.H * K / 2);
    scene.add(outside);
  }

  function isGrass(x, y) {
    if (!grassMask || x < 0 || y < 0 || x >= World.W || y >= World.H) return false;
    const i = ((Math.floor(y * grassMask.s) * grassMask.w) + Math.floor(x * grassMask.s)) * 4;
    const r = grassMask.data[i], g = grassMask.data[i + 1], b = grassMask.data[i + 2];
    return g > r + 18 && g > b + 25;
  }

  function makeGrass() {
    const count = mobile ? 14000 : 42000;
    const bh = 0.32;
    const geo = new T.PlaneGeometry(0.045, bh, 1, 3);
    geo.translate(0, bh / 2, 0);
    const p = geo.attributes.position, colors = [];
    for (let i = 0; i < p.count; i++) {
      const y = p.getY(i) / bh;
      p.setX(i, p.getX(i) * (1 - y * 0.85));
      const c = new T.Color('#24451a').lerp(new T.Color('#86b04a'), y);
      colors.push(c.r, c.g, c.b);
    }
    geo.setAttribute('color', new T.Float32BufferAttribute(colors, 3));
    geo.computeVertexNormals();
    const mat = std({ vertexColors: true, side: T.DoubleSide, roughness: 0.95 });
    mat.onBeforeCompile = sh => {
      sh.uniforms.uTime = grassTime;
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', '#include <common>\nuniform float uTime;')
        .replace('#include <begin_vertex>', `#include <begin_vertex>
  float hh = position.y / ${bh.toFixed(2)};
  vec4 wp = instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0);
  float wind = sin(uTime * 1.6 + wp.x * 0.32 + wp.z * 0.21) * 0.09 + sin(uTime * 3.3 + wp.x * 1.7 + wp.z) * 0.025;
  transformed.x += wind * hh * hh;
  transformed.z += wind * 0.6 * hh * hh;`);
      // трава всегда смотрит нормалью вверх — ровное освещение с обеих сторон травинки
      sh.vertexShader = sh.vertexShader.replace('#include <beginnormal_vertex>', 'vec3 objectNormal = vec3(0.0, 1.0, 0.0);');
      sh.fragmentShader = sh.fragmentShader.replace('#include <normal_fragment_begin>', '#include <normal_fragment_begin>\n  normal = normalize(vNormal);');
    };
    grass = new T.InstancedMesh(geo, mat, count);
    grass.receiveShadow = true;
    grass.castShadow = false;
    grass.frustumCulled = false;
    // цвет каждой травинки; создаём заранее на всё количество (setColorAt берёт размер из count)
    grass.instanceColor = new T.InstancedBufferAttribute(new Float32Array(count * 3).fill(1), 3);
    grass.count = 0;
    scene.add(grass);
  }

  function scatterGrass(cx, cz) {
    const cell = 5, R = mobile ? 4 : 6; // клетки по 5 м, вокруг камеры
    const density = mobile ? 5 : 11;
    const per = cell * cell * density;
    const m = new T.Matrix4(), q = new T.Quaternion(), e = new T.Euler(), sc = V3(1, 1, 1), p = V3();
    const col = new T.Color();
    let n = 0;
    const gx = Math.floor(cx / cell), gz = Math.floor(cz / cell);
    for (let i = gx - R; i <= gx + R; i++) for (let j = gz - R; j <= gz + R; j++) {
      const r = rng((i * 73856093) ^ (j * 19349663));
      for (let k = 0; k < per && n < grass.instanceMatrix.count; k++) {
        const x = (i + r()) * cell, z = (j + r()) * cell;
        const a = r(), b = r(), c = r();
        if (!isGrass(x / K, z / K)) continue;
        p.set(x, 0, z);
        e.set((a - 0.5) * 0.4, b * Math.PI * 2, (c - 0.5) * 0.4);
        q.setFromEuler(e);
        const s = 0.6 + r() * 0.9;
        sc.set(1, s, 1);
        m.compose(p, q, sc);
        grass.setMatrixAt(n, m);
        col.setRGB(0.75 + r() * 0.3, 0.8 + r() * 0.25, 0.65 + r() * 0.3);
        grass.setColorAt(n, col);
        n++;
      }
    }
    grass.count = n;
    grass.instanceMatrix.needsUpdate = true;
    if (grass.instanceColor) grass.instanceColor.needsUpdate = true;
  }

  function makeSky() {
    const mat = new T.ShaderMaterial({
      side: T.BackSide, depthWrite: false, fog: false,
      uniforms: {
        top: { value: new T.Color('#3b7bd4') }, horizon: { value: new T.Color('#cfe6f5') },
        sunDir: { value: V3(0, 1, 0) }, sunCol: { value: new T.Color('#fff2c8') }, starAmt: { value: 0 },
      },
      vertexShader: `varying vec3 vDir; void main(){ vec4 wp = modelMatrix * vec4(position,1.0); vDir = normalize(wp.xyz - cameraPosition); gl_Position = projectionMatrix * viewMatrix * wp; }`,
      fragmentShader: `uniform vec3 top; uniform vec3 horizon; uniform vec3 sunDir; uniform vec3 sunCol; uniform float starAmt; varying vec3 vDir;
        float hash(vec3 p){ return fract(sin(dot(p, vec3(12.9898,78.233,45.164))) * 43758.5453); }
        void main(){
          float h = clamp(vDir.y, -0.2, 1.0);
          vec3 col = mix(horizon, top, pow(max(h, 0.0), 0.55));
          if (h < 0.0) col = mix(horizon, horizon * 0.7, -h * 5.0);
          float d = max(dot(vDir, normalize(sunDir)), 0.0);
          col += sunCol * (pow(d, 900.0) * 3.0 + pow(d, 12.0) * 0.25);
          float s = step(0.9975, hash(floor(vDir * 300.0))) * starAmt * smoothstep(0.0, 0.25, h);
          col += vec3(s);
          gl_FragColor = vec4(col, 1.0);
        }`,
    });
    sky = new T.Mesh(new T.SphereGeometry(450, 32, 16), mat);
    sky.renderOrder = -1;
    scene.add(sky);
  }

  // забор: столбы и жерди по сторонам прямоугольника с воротами
  function fence(r, gate, style, parts) {
    const segs = [];
    const { x, y, w, h } = r;
    const top = gate.side === 'top' ? [[x, y, gate.a, y], [gate.b, y, x + w, y]] : [[x, y, x + w, y]];
    const bottom = gate.side === 'bottom' ? [[x, y + h, gate.a, y + h], [gate.b, y + h, x + w, y + h]] : [[x, y + h, x + w, y + h]];
    const left = gate.side === 'left' ? [[x, y, x, gate.a], [x, gate.b, x, y + h]] : [[x, y, x, y + h]];
    segs.push(...top, ...bottom, ...left, [x + w, y, x + w, y + h]);
    const white = style === 'white';
    for (const [x1, y1, x2, y2] of segs) {
      const len = Math.hypot(x2 - x1, y2 - y1) * K, cx = (x1 + x2) / 2 * K, cz = (y1 + y2) / 2 * K;
      const ang = Math.atan2(y2 - y1, x2 - x1);
      const rails = white ? [0.55, 1.05] : [0.45, 0.85, 1.25];
      for (const ry of rails) {
        if (white) parts.push({ geo: boxUV(len, 0.13, 0.04, 2), matrix: M(cx, ry, cz, 0, -ang, 0) });
        else parts.push({ geo: new T.CylinderGeometry(0.045, 0.045, len, 8), matrix: M(cx, ry, cz, 0, -ang, Math.PI / 2), uvScale: [1, len / 2] });
      }
      const n = Math.max(1, Math.round(len / 2.5));
      for (let i = 0; i <= n; i++) {
        const px = (x1 + (x2 - x1) * i / n) * K, pz = (y1 + (y2 - y1) * i / n) * K;
        if (white) parts.push({ geo: boxUV(0.11, 1.25, 0.11, 1), matrix: M(px, 0.625, pz) });
        else parts.push({ geo: new T.CylinderGeometry(0.075, 0.085, 1.5, 8), matrix: M(px, 0.75, pz) });
      }
    }
  }

  function personStatic(x, z, ang, shirt, hat) {
    const hm = buildHuman({ shirt, helmet: '#7a5a30' });
    hm.helmet.visible = !!hat; hm.visor.visible = false;
    if (hat) { hm.helmet.scale.set(1.1, 0.8, 1.1); const brim = mesh(new T.CylinderGeometry(0.2, 0.2, 0.015, 20), hm.helmetMat); brim.position.y = 0.02; hm.head.add(brim); }
    poseHuman(hm, 'walk', 0, 0);
    hm.root.position.set(x, 0, z);
    hm.root.rotation.y = -ang;
    scene.add(hm.root);
  }

  function buildStatic() {
    const S = sharedMats();
    tex.wood = plankTex('#8a5a32', '#5e3b1d', 3);
    tex.woodGrey = plankTex('#8d7f6b', '#5f5446', 4, false);
    tex.white = noiseTex(128, '#f1f1ee', [{ c: '#e2e2de', n: 400, s: 2 }], 5);
    tex.straw = noiseTex(256, '#d8b65c', [{ c: '#b8923d', n: 1600, line: true, w: 10, h: 1.5 }, { c: '#f1d98c', n: 1600, line: true, w: 9, h: 1.5 }], 6);
    tex.roof = (() => {
      const c = canvas(256, 256), g = c.getContext('2d'), r = rng(9);
      g.fillStyle = '#7d3b2b'; g.fillRect(0, 0, 256, 256);
      for (let row = 0; row < 16; row++) for (let col = 0; col < 9; col++) {
        g.fillStyle = Genetics.mix('#7d3b2b', r() < 0.5 ? '#000000' : '#c0705a', r() * 0.25);
        g.fillRect(col * 32 - (row % 2) * 16, row * 16, 30, 14);
      }
      return toTex(c, true);
    })();
    tex.brick = (() => {
      const c = canvas(256, 128), g = c.getContext('2d'), r = rng(10);
      g.fillStyle = '#d9d2c5'; g.fillRect(0, 0, 256, 128);
      for (let row = 0; row < 8; row++) for (let col = 0; col < 9; col++) {
        g.fillStyle = Genetics.mix('#b5532d', r() < 0.5 ? '#6e2b14' : '#d9774a', r() * 0.35);
        g.fillRect(col * 32 - (row % 2) * 16 + 1, row * 16 + 1, 30, 14);
      }
      return toTex(c, true);
    })();
    const woodMat = std({ map: tex.wood, roughness: 0.85 });
    const greyWood = std({ map: tex.woodGrey, roughness: 0.9 });
    const paint = std({ map: tex.white, roughness: 0.6 });

    // ---- конюшня ----
    const St = World.STABLE;
    const wallParts = [];
    for (const s of World.SOLIDS.slice(0, 6)) wallParts.push({ geo: boxUV(s.w * K, 2.7, s.h * K, 2), matrix: M((s.x + s.w / 2) * K, 1.35, (s.y + s.h / 2) * K) });
    // перегородки денников: низ — доски, верх — решётка
    const barParts = [];
    for (let c = 0; c <= 10; c++) {
      const x = (St.x + 10 + c * World.STALL_W) * K;
      for (const [y0, y1] of [[St.y + 10, World.AISLE_Y1], [World.AISLE_Y2, St.y + St.h - 10]]) {
        const len = (y1 - y0) * K, cz = (y0 + y1) / 2 * K;
        wallParts.push({ geo: boxUV(0.07, 1.3, len, 2), matrix: M(x, 0.65, cz) });
        barParts.push({ geo: new T.BoxGeometry(0.06, 0.06, len), matrix: M(x, 2.1, cz) });
        for (let k = 1; k < 10; k++) barParts.push({ geo: new T.CylinderGeometry(0.012, 0.012, 0.8, 5), matrix: M(x, 1.7, y0 * K + len * k / 10) });
      }
    }
    for (let c = 0; c < 10; c++) {
      const x0 = (St.x + 10 + c * World.STALL_W) * K, w = World.STALL_W * K;
      for (const yy of [World.AISLE_Y1, World.AISLE_Y2]) {
        wallParts.push({ geo: boxUV(w, 1.3, 0.07, 2), matrix: M(x0 + w / 2, 0.65, yy * K) });
        barParts.push({ geo: new T.BoxGeometry(w, 0.06, 0.06), matrix: M(x0 + w / 2, 2.1, yy * K) });
        for (let k = 1; k < 8; k++) barParts.push({ geo: new T.CylinderGeometry(0.012, 0.012, 0.8, 5), matrix: M(x0 + w * k / 8, 1.7, yy * K) });
      }
    }
    scene.add(mesh(merge(wallParts), woodMat));
    scene.add(mesh(merge(barParts, false, false), S.metal, true, false));
    // кормушки, вёдра, сено в денниках
    const feedParts = [], bucketParts = [], hayParts = [];
    for (let i = 0; i < 20; i++) {
      const r = World.stallRect(i);
      const fz = (r.row ? r.y + r.h - 12 : r.y + 12) * K;
      feedParts.push({ geo: boxUV(0.6, 0.3, 0.35, 1), matrix: M((r.x + 22) * K, 0.85, fz) });
      hayParts.push({ geo: boxUV(0.5, 0.12, 0.28, 0.5), matrix: M((r.x + 22) * K, 1.0, fz) });
      bucketParts.push({ geo: new T.CylinderGeometry(0.15, 0.12, 0.3, 14), matrix: M((r.x + r.w - 16) * K, 0.85, fz) });
    }
    scene.add(mesh(merge(feedParts), woodMat));
    scene.add(mesh(merge(hayParts), std({ map: tex.straw, roughness: 1 }), false));
    scene.add(mesh(merge(bucketParts, false, false), std({ color: '#2f6fb0', roughness: 0.4 })));
    // крыша — прячется, когда ты рядом с конюшней
    roofGroup = new T.Group();
    const rw = St.w * K + 1.2, half = St.h * K / 2 + 0.6, rise = 2.1;
    const slope = Math.hypot(half, rise);
    const roofMat = std({ map: tex.roof, roughness: 0.75, transparent: true, side: T.DoubleSide });
    tex.roof.repeat.set(rw / 2, slope / 1.2);
    roofMats.push(roofMat);
    const cx = (St.x + St.w / 2) * K, cz = (St.y + St.h / 2) * K;
    for (const sgn of [-1, 1]) {
      const pl = mesh(new T.PlaneGeometry(rw, slope), roofMat, true, false);
      pl.position.set(cx, 2.7 + rise / 2, cz + sgn * half / 2);
      pl.rotation.x = -sgn * Math.atan2(half, rise);
      roofGroup.add(pl);
    }
    const ridge = mesh(new T.BoxGeometry(rw, 0.14, 0.2), std({ color: '#5a2a1e', roughness: 0.7, transparent: true }));
    roofMats.push(ridge.material);
    ridge.position.set(cx, 2.7 + rise + 0.03, cz);
    roofGroup.add(ridge);
    const gableShape = new T.Shape();
    gableShape.moveTo(-half + 0.6, 0); gableShape.lineTo(half - 0.6, 0); gableShape.lineTo(0, rise - 0.1); gableShape.lineTo(-half + 0.6, 0);
    const gMat = std({ map: tex.wood, roughness: 0.85, transparent: true, side: T.DoubleSide });
    roofMats.push(gMat);
    for (const gx of [St.x * K + 0.05, (St.x + St.w) * K - 0.05]) {
      const gm = mesh(new T.ShapeGeometry(gableShape), gMat);
      gm.position.set(gx, 2.7, cz); gm.rotation.y = Math.PI / 2;
      roofGroup.add(gm);
    }
    scene.add(roofGroup);
    // тюки сена
    const bales = [];
    for (const [x, y] of [[St.x - 30, St.y + 40], [St.x - 30, St.y + 80], [St.x + St.w + 30, St.y + St.h - 50], [St.x + St.w + 30, St.y + St.h - 20]]) bales.push({ geo: boxUV(0.9, 0.45, 0.5, 0.5), matrix: M(x * K, 0.225, y * K, 0, 0.1, 0) });
    scene.add(mesh(merge(bales), std({ map: tex.straw, roughness: 1 })));

    // ---- манеж ----
    const whiteParts = [];
    fence(World.ARENA, { side: 'left', a: World.GATE_A.y1, b: World.GATE_A.y2 }, 'white', whiteParts);
    fence(World.JUMPF, { side: 'top', a: World.JUMPF_GATE.x1, b: World.JUMPF_GATE.x2 }, 'white', whiteParts);
    scene.add(mesh(merge(whiteParts), paint));
    for (const [L, p] of Object.entries(World.LETTERS)) {
      if (L === 'X') continue;
      const off = 22;
      const bx = (p.side === 'left' ? p.x - off : p.side === 'right' ? p.x + off : p.x) * K;
      const bz = (p.side === 'top' ? p.y - off : p.side === 'bottom' ? p.y + off : p.y) * K;
      const m = mesh(new T.BoxGeometry(0.5, 0.55, 0.5), std({ map: textTex(L), roughness: 0.6 }));
      m.position.set(bx, 0.45, bz);
      scene.add(m);
    }
    // ---- левада ----
    const woodParts = [];
    fence(World.PADDOCK, { side: 'bottom', a: World.PADDOCK_GATE.x1, b: World.PADDOCK_GATE.x2 }, 'wood', woodParts);
    scene.add(mesh(merge(woodParts), greyWood));
    const P = World.PADDOCK;
    const trough = mesh(new T.BoxGeometry(1.5, 0.5, 0.55), std({ color: '#9aa1a8', metalness: 0.7, roughness: 0.35 }));
    trough.position.set((P.x + P.w - 60) * K, 0.25, (P.y + 41) * K); scene.add(trough);
    const tw = mesh(new T.PlaneGeometry(1.4, 0.45), std({ color: '#3d7ea6', roughness: 0.05, metalness: 0.3 }), false);
    tw.rotation.x = -Math.PI / 2; tw.position.set((P.x + P.w - 60) * K, 0.46, (P.y + 41) * K); scene.add(tw);
    const rack = mesh(boxUV(1.2, 1, 0.8, 1), woodMat); rack.position.set((P.x + 55) * K, 0.5, (P.y + 47) * K); scene.add(rack);
    const rackHay = mesh(boxUV(1.1, 0.3, 0.7, 0.5), std({ map: tex.straw, roughness: 1 })); rackHay.position.set((P.x + 55) * K, 1.1, (P.y + 47) * K); scene.add(rackHay);

    // ---- повозки ----
    for (const [W, stripe] of [[World.SELL, '#c92a2a'], [World.SHOP, '#2b8a3e']]) {
      const cx2 = (W.x + W.w / 2) * K, cz2 = (W.y + W.h / 2) * K, w = W.w * K, d = W.h * K;
      const wag = new T.Group();
      wag.position.set(cx2, 0, cz2);
      const bed = mesh(boxUV(w, 0.5, d, 1), woodMat); bed.position.y = 0.85; wag.add(bed);
      const sideL = mesh(boxUV(w, 0.35, 0.05, 1), woodMat); sideL.position.set(0, 1.25, -d / 2); wag.add(sideL);
      const sideR = sideL.clone(); sideR.position.z = d / 2; wag.add(sideR);
      const awnTex = stripeTex(stripe, '#f8f4ea', 10);
      awnTex.wrapS = T.RepeatWrapping;
      const awn = mesh(new T.CylinderGeometry(d / 2 + 0.05, d / 2 + 0.05, w + 0.2, 24, 1, true, 0, Math.PI), std({ map: awnTex, side: T.DoubleSide, roughness: 0.9 }));
      awn.rotation.set(0, 0, Math.PI / 2);
      awn.position.y = 1.45; wag.add(awn);
      for (const wx of [-w / 2 + 0.55, w / 2 - 0.55]) for (const wz of [-d / 2 - 0.08, d / 2 + 0.08]) {
        const wheel = new T.Group(); wheel.position.set(wx, 0.5, wz);
        wheel.add(mesh(new T.TorusGeometry(0.46, 0.04, 8, 28), S.leatherDark));
        for (let k = 0; k < 8; k++) { const sp = mesh(new T.CylinderGeometry(0.018, 0.018, 0.9, 5), woodMat); sp.rotation.z = (k / 8) * Math.PI; wheel.add(sp); }
        wheel.add(mesh(new T.CylinderGeometry(0.08, 0.08, 0.12, 10).rotateX(Math.PI / 2), S.leatherDark));
        wag.add(wheel);
      }
      for (const sz of [-0.35, 0.35]) { const sh = mesh(new T.CylinderGeometry(0.035, 0.035, 2, 6), woodMat); sh.rotation.z = Math.PI / 2 - 0.08; sh.position.set(-w / 2 - 0.95, 0.75, sz); wag.add(sh); }
      // ящики и бочки с товаром
      const crate = mesh(boxUV(0.45, 0.4, 0.45, 0.5), woodMat); crate.position.set(w / 2 + 0.5, 0.2, -d / 2 - 0.3); wag.add(crate);
      const barrel = mesh(new T.CylinderGeometry(0.25, 0.25, 0.6, 14), woodMat); barrel.position.set(w / 2 + 0.3, 0.3, d / 2 + 0.5); wag.add(barrel);
      scene.add(wag);
      personStatic((W.x + W.w + 22) * K, cz2, Math.PI, stripe === '#c92a2a' ? '#4a6fa5' : '#8a6d3b', true);
    }

    // ---- деревья ----
    const trunkParts = { oak: [], birch: [] }, leafParts = [];
    for (const tr of World.TREES) {
      const r = rng(tr.s);
      const x = tr.x * K, z = tr.y * K, sc = (tr.r / 40) * (0.9 + r() * 0.3);
      const hgt = 3.2 * sc + 1;
      trunkParts[tr.kind].push({ geo: new T.CylinderGeometry(0.12 * sc + 0.05, 0.22 * sc + 0.08, hgt, 9), matrix: M(x, hgt / 2, z), uvScale: [2, hgt] });
      for (let k = 0; k < 3; k++) {
        const a = r() * Math.PI * 2;
        trunkParts[tr.kind].push({ geo: new T.CylinderGeometry(0.04, 0.08, 1.4 * sc, 6), matrix: M(x + Math.cos(a) * 0.4 * sc, hgt * 0.8, z + Math.sin(a) * 0.4 * sc, Math.sin(a) * 0.8, 0, -Math.cos(a) * 0.8) });
      }
      const n = 6 + Math.floor(r() * 4);
      for (let k = 0; k < n; k++) {
        const a = r() * Math.PI * 2, d = r() * 1.3 * sc;
        const geo = new T.SphereGeometry(1, 14, 10);
        const p = geo.attributes.position, nn = geo.attributes.normal;
        const ph1 = r() * 6, ph2 = r() * 6;
        for (let i = 0; i < p.count; i++) {
          const x = p.getX(i), y = p.getY(i), zz = p.getZ(i);
          const f = 1 + Math.sin(x * 5 + ph1) * Math.sin(zz * 4 + y * 3 + ph2) * 0.12;
          p.setXYZ(i, x * f, y * f, zz * f);
          nn.setXYZ(i, x, y, zz); // мягкие нормали «шара» — крона выглядит пушистой
        }
        const rad = (0.85 + r() * 0.55) * sc;
        const green = tr.kind === 'birch' ? ['#6f9e3c', '#88b34a', '#5d8a33'] : ['#3f6e2a', '#4f7f31', '#365f24'];
        leafParts.push({ geo, matrix: M(x + Math.cos(a) * d, hgt + 0.4 * sc + r() * 1.2 * sc, z + Math.sin(a) * d, 0, r() * 3, 0, rad, rad * 0.85, rad), color: green[k % 3] });
      }
    }
    const bark = noiseTex(128, '#5c4030', [{ c: '#3e2a1e', n: 300, line: true, w: 2, h: 14 }, { c: '#7a5a44', n: 200, line: true, w: 2, h: 10 }], 12);
    const birch = noiseTex(128, '#eceae4', [{ c: '#2b2b2b', n: 60, line: true, w: 10, h: 2 }, { c: '#bdbab2', n: 200, s: 2 }], 13);
    scene.add(mesh(merge(trunkParts.oak), std({ map: bark, roughness: 0.95 })));
    if (trunkParts.birch.length) scene.add(mesh(merge(trunkParts.birch), std({ map: birch, roughness: 0.9 })));
    const leafMat = std({ vertexColors: true, roughness: 0.85 });
    seeThrough(leafMat);
    const leaves = mesh(merge(leafParts, true, false), leafMat);
    scene.add(leaves);

    // ---- пруд ----
    const PO = World.POND;
    const ripple = (() => {
      const c = canvas(256, 256), g = c.getContext('2d'), r = rng(21);
      g.fillStyle = 'rgb(128,128,255)'; g.fillRect(0, 0, 256, 256);
      for (let i = 0; i < 260; i++) {
        const x = r() * 256, y = r() * 256, rr = 6 + r() * 26;
        const gr = g.createRadialGradient(x, y, rr * 0.6, x, y, rr);
        gr.addColorStop(0, 'rgba(160,160,255,0)'); gr.addColorStop(0.5, 'rgba(170,150,255,0.35)'); gr.addColorStop(1, 'rgba(100,110,255,0)');
        g.fillStyle = gr; g.fillRect(x - rr, y - rr, rr * 2, rr * 2);
      }
      const t = new T.CanvasTexture(c); t.wrapS = t.wrapT = T.RepeatWrapping; t.repeat.set(6, 4);
      return t;
    })();
    water = mesh(new T.CircleGeometry(1, 48), std({ color: '#2e6a8a', roughness: 0.06, metalness: 0.35, normalMap: ripple, transparent: true, opacity: 0.93 }), false, true);
    water.scale.set(PO.rx * K, PO.ry * K, 1);
    water.rotation.x = -Math.PI / 2;
    water.position.set(PO.x * K, 0.04, PO.y * K);
    scene.add(water);
    const reedParts = [];
    const rr = rng(31);
    for (let i = 0; i < 90; i++) {
      const a = rr() * Math.PI * 2, f = 0.95 + rr() * 0.12;
      const x = PO.x * K + Math.cos(a) * PO.rx * K * f, z = PO.y * K + Math.sin(a) * PO.ry * K * f;
      const hgt = 0.6 + rr() * 0.8;
      reedParts.push({ geo: new T.ConeGeometry(0.02, hgt, 4), matrix: M(x, hgt / 2, z, (rr() - 0.5) * 0.3, 0, (rr() - 0.5) * 0.3), color: rr() < 0.8 ? '#5d7f31' : '#8a6d3b' });
    }
    scene.add(mesh(merge(reedParts, true, false), std({ vertexColors: true, roughness: 0.9 }), false));

    // ---- фонари ----
    const postParts = [];
    for (const l of World.LAMPS) {
      postParts.push({ geo: new T.CylinderGeometry(0.05, 0.07, 3, 8), matrix: M(l.x * K, 1.5, l.y * K) });
      postParts.push({ geo: new T.BoxGeometry(0.22, 0.04, 0.22), matrix: M(l.x * K, 3.35, l.y * K) });
    }
    scene.add(mesh(merge(postParts, false, false), std({ color: '#2b2f33', roughness: 0.5, metalness: 0.6 })));
    lampGlass = std({ color: '#fff3c4', emissive: new T.Color('#ffcf7a'), emissiveIntensity: 0, roughness: 0.2 });
    const glassParts = World.LAMPS.map(l => ({ geo: new T.BoxGeometry(0.2, 0.3, 0.2), matrix: M(l.x * K, 3.18, l.y * K) }));
    scene.add(mesh(merge(glassParts, false, false), lampGlass, false, false));
    const gt = glowTex();
    for (const l of World.LAMPS) {
      const sp = new T.Sprite(new T.SpriteMaterial({ map: gt, color: '#ffd28a', transparent: true, depthWrite: false, blending: T.AdditiveBlending }));
      sp.position.set(l.x * K, 3.18, l.y * K); sp.scale.set(2.2, 2.2, 1); sp.visible = false;
      scene.add(sp); halos.push(sp);
    }
    for (let i = 0; i < 5; i++) {
      const pl = new T.PointLight('#ffc977', 0, 16, 2);
      scene.add(pl); lampLights.push(pl);
    }
    playerFill = new T.PointLight('#ffe3b0', 0, 9, 2);
    scene.add(playerFill);

    // ---- светлячки ----
    const fp = [];
    const fr = rng(41);
    for (let i = 0; i < 160; i++) fp.push(World.FIELD.x * K + fr() * World.FIELD.w * K, 0.4 + fr() * 1.6, World.FIELD.y * K + fr() * World.FIELD.h * K);
    const fg = new T.BufferGeometry(); fg.setAttribute('position', new T.Float32BufferAttribute(fp, 3));
    fireflies = new T.Points(fg, new T.PointsMaterial({ color: '#e9ff8a', size: 0.12, map: gt, transparent: true, depthWrite: false, blending: T.AdditiveBlending }));
    fireflies.userData.base = fp.slice();
    scene.add(fireflies);

    // кольца-подсказки
    const ringMat = new T.MeshBasicMaterial({ color: '#ffe066', transparent: true, opacity: 0.8, depthWrite: false });
    ring = new T.Mesh(new T.RingGeometry(1.2, 1.4, 48), ringMat);
    ring.rotation.x = -Math.PI / 2; scene.add(ring);
    letterRing = new T.Mesh(new T.RingGeometry(0.7, 0.85, 40), ringMat.clone());
    letterRing.material.color.set('#ffb000'); letterRing.rotation.x = -Math.PI / 2; scene.add(letterRing);
  }

  // кроны деревьев не загораживают игрока: «вырезаем» листву между камерой и игроком
  const seeUniforms = { uCam: { value: null }, uPlayer: { value: null } };
  function seeThrough(mat) {
    mat.onBeforeCompile = sh => {
      sh.uniforms.uCam = seeUniforms.uCam;
      sh.uniforms.uPlayer = seeUniforms.uPlayer;
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vWPos;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\n  vWPos = (modelMatrix * vec4(transformed, 1.0)).xyz;');
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vWPos; uniform vec3 uCam; uniform vec3 uPlayer;')
        .replace('void main() {', `void main() {
  vec3 ab = uPlayer - uCam; float t = clamp(dot(vWPos - uCam, ab) / dot(ab, ab), 0.0, 1.0);
  float d = length(vWPos - (uCam + ab * t));
  float hole = 4.5 * smoothstep(0.2, 0.55, t);
  if (d < hole) {
    vec2 sp = floor(gl_FragCoord.xy);
    if (mod(sp.x + sp.y, 2.0) < 1.0 || d < hole * 0.7) discard;
  }`);
    };
  }

  /* ---------- препятствия и жерди (меняются по ходу упражнений) ---------- */
  const RAILC = { cross: '#1c7ed6', vertical: '#e03131', oxer: '#2b8a3e', triple: '#f08c00', wall: '#c2410c' };
  const railTexCache = {};
  function railMat(color) {
    if (!railTexCache[color]) railTexCache[color] = std({ map: stripeTex(color, '#ffffff', 8), roughness: 0.45 });
    return railTexCache[color];
  }
  function rebuild(name, key, build) {
    const d = dynamic[name];
    if (d && d.key === key) return;
    if (d) { d.obj.traverse(n => n.geometry && n.geometry.dispose()); scene.remove(d.obj); }
    const obj = build();
    scene.add(obj);
    dynamic[name] = { key, obj };
  }
  function rail(len, color) {
    const m = mesh(new T.CylinderGeometry(0.05, 0.05, len, 12), railMat(color));
    m.rotation.x = Math.PI / 2;
    return m;
  }

  function updateCourse(game) {
    const ex = game.exercise();
    const jump = ex && ex.type === 'jump' ? ex : null;
    const height = jump ? jump.height : 80;
    const key = jump ? `${height}|${jump.i}|${jump.jumps.join(',')}` : 'idle';
    rebuild('course', key, () => {
      const group = new T.Group();
      const H = height / 100;
      const standMat = std({ color: '#f8f9fa', roughness: 0.5 });
      const flowerMat = std({ map: noiseTex(64, '#3d6b2a', [{ c: '#e64980', n: 40, s: 3 }, { c: '#ffd43b', n: 40, s: 3 }, { c: '#ffffff', n: 30, s: 3 }], 7, true), roughness: 0.9 });
      World.COURSE.forEach((o, i) => {
        const g = new T.Group();
        g.position.set(o.x * K, 0, o.y * K);
        g.rotation.y = -o.a;
        const half = o.half * K;
        const st = jump ? jump.jumps[i] : null;
        const knocked = st === 'hit';
        const color = RAILC[o.type];
        const xs = o.type === 'oxer' ? [-0.45, 0.45] : o.type === 'triple' ? [-0.7, 0, 0.7] : [0];
        // стойки-крылья
        for (const z of [-half - 0.12, half + 0.12]) for (const x of xs) {
          const post = mesh(new T.BoxGeometry(0.1, H + 0.5, 0.1), standMat); post.position.set(x, (H + 0.5) / 2, z); g.add(post);
        }
        for (const z of [-half - 0.45, half + 0.45]) {
          const wing = mesh(boxUV(0.06, H + 0.3, 0.6, 1), railMat(color)); wing.position.set(0, (H + 0.3) / 2, z); g.add(wing);
          const foot = mesh(new T.BoxGeometry(0.7, 0.06, 0.7), standMat); foot.position.set(0, 0.03, z); g.add(foot);
        }
        // флажки: красный справа, белый слева
        for (const [z, c] of [[half + 0.75, '#e03131'], [-half - 0.75, '#ffffff']]) {
          const pole = mesh(new T.CylinderGeometry(0.015, 0.015, 1.6, 5), standMat); pole.position.set(0, 0.8, z); g.add(pole);
          const flag = mesh(new T.PlaneGeometry(0.3, 0.2), std({ color: c, side: T.DoubleSide, roughness: 0.8 })); flag.position.set(-0.15, 1.45, z); g.add(flag);
        }
        const plate = mesh(new T.PlaneGeometry(0.3, 0.3), std({ map: textTex(String(o.n), '#212529', jump && jump.i === i ? '#ffd43b' : '#ffffff'), side: T.DoubleSide }));
        plate.position.set(-0.05, H + 0.35, half + 0.45); plate.rotation.y = -Math.PI / 2; g.add(plate);
        const plate2 = plate.clone(); plate2.position.z = -half - 0.45; g.add(plate2);
        // цветочные ящики
        const fb = mesh(boxUV(0.35, 0.25, half * 1.6, 0.4), flowerMat); fb.position.set(-0.3, 0.125, 0); g.add(fb);
        if (o.type === 'wall') {
          const wh = knocked ? H * 0.8 : H;
          const wall = mesh(boxUV(0.5, wh, half * 2, 0.6), std({ map: tex.brick, roughness: 0.9 })); wall.position.y = wh / 2; g.add(wall);
          if (knocked) { const blk = mesh(boxUV(0.4, 0.2, 0.6, 0.6), wall.material); blk.position.set(0.7, 0.1, 0.3); g.add(blk); }
        } else if (o.type === 'cross') {
          for (const s of [-1, 1]) {
            const r = rail(half * 2.25, color);
            if (knocked && s > 0) { r.position.set(0.7, 0.05, 0); r.rotation.y = 0.2; }
            else { r.position.y = H * 0.55; r.rotation.set(Math.PI / 2 + s * 0.38, 0, 0); }
            g.add(r);
          }
        } else {
          const hs = o.type === 'triple' ? [0.7, 0.85, 1] : xs.map(() => 1);
          xs.forEach((x, k) => {
            const top = H * hs[k];
            const r = rail(half * 2.1, color);
            if (knocked && k === xs.length - 1) { r.position.set(x + 0.8, 0.05, 0.1); r.rotation.z = 0.12; }
            else r.position.set(x, top, 0);
            g.add(r);
            const r2 = rail(half * 2.1, '#adb5bd'); r2.position.set(x, top * 0.5, 0); g.add(r2);
          });
        }
        g.traverse(n => { if (n.isMesh) { n.castShadow = true; n.receiveShadow = true; } });
        group.add(g);
      });
      return group;
    });

    const cav = ex && ex.type === 'cav' ? ex : null;
    rebuild('cav', cav ? cav.poles.map(p => p.state).join(',') : 'idle', () => {
      const group = new T.Group(), C = World.CAV, len = (C.y2 - C.y1) * K, cz = (C.y1 + C.y2) / 2 * K;
      const wood = std({ color: '#7a5634', roughness: 0.8 });
      C.poles.forEach((px, i) => {
        const st = cav ? cav.poles[i].state : null;
        for (const z of [-len / 2, len / 2]) for (const s of [-1, 1]) {
          const leg = mesh(new T.BoxGeometry(0.06, 0.55, 0.06), wood); leg.position.set(px * K, 0.22, cz + z); leg.rotation.x = s * 0.6; group.add(leg);
        }
        const r = rail(len + 0.2, st === 'ok' ? '#2b8a3e' : '#d63a3a');
        if (st === 'hit') r.position.set(px * K + 0.4, 0.05, cz); else r.position.set(px * K, 0.32, cz);
        group.add(r);
      });
      group.traverse(n => { if (n.isMesh) n.castShadow = true; });
      return group;
    });
  }

  /* ================= инициализация ================= */
  function init() {
    T = window.THREE;
    WITHERS = V3(0.52, 1.42, 0);
    POLL = V3(1.03, 2.0, 0);
    canvas3d = document.createElement('canvas');
    canvas3d.id = 'game-real';
    canvas3d.className = 'game3d';
    document.body.insertBefore(canvas3d, document.body.firstChild);
    renderer = new T.WebGLRenderer({ canvas: canvas3d, antialias: true, powerPreference: 'high-performance' });
    renderer.setPixelRatio(Math.min(mobile ? 1.5 : 2, window.devicePixelRatio || 1));
    renderer.outputEncoding = T.sRGBEncoding;
    renderer.toneMapping = T.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = T.PCFSoftShadowMap;
    scene = new T.Scene();
    scene.fog = new T.FogExp2('#cfe6f5', 0.0085);
    camera = new T.PerspectiveCamera(50, 1, 0.2, 900);
    hemi = new T.HemisphereLight('#cfe6ff', '#5d6b3a', 0.55);
    scene.add(hemi);
    sun = new T.DirectionalLight('#fff1d6', 2.2);
    sun.castShadow = true;
    sun.shadow.mapSize.set(mobile ? 1024 : 2048, mobile ? 1024 : 2048);
    Object.assign(sun.shadow.camera, { left: -26, right: 26, top: 26, bottom: -26, near: 1, far: 160 });
    sun.shadow.bias = -0.0004;
    sun.shadow.normalBias = 0.03;
    scene.add(sun); scene.add(sun.target);
    moon = new T.DirectionalLight('#8fa8ff', 0);
    scene.add(moon); scene.add(moon.target);
    makeSky();
    makeGround();
    makeGrass();
    buildStatic();
    resize();
    addEventListener('resize', resize);
    canvas3d.addEventListener('wheel', e => { zoom(e.deltaY); e.preventDefault(); }, { passive: false });
    ready = true;
  }

  function resize() {
    if (!renderer) return;
    renderer.setSize(innerWidth, innerHeight);
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
  }
  function setVisible(on) { if (canvas3d) canvas3d.style.display = on ? 'block' : 'none'; }
  function zoom(dy) { cam.zoom = Math.max(0.45, Math.min(2.2, cam.zoom * (dy > 0 ? 1.1 : 1 / 1.1))); }

  /* ================= кадр ================= */
  function disposeHorse(e) {
    scene.remove(e.root);
    e.root.traverse(n => { if (n.geometry) n.geometry.dispose(); });
    e.disposables.forEach(d => d.dispose && d.dispose());
  }

  function syncHorse(h, x, y, angle, o, dt, now) {
    const ph = Horses.pheno(h);
    let e = objs.get(h.id);
    if (!e || e.ph !== ph) {
      if (e) disposeHorse(e);
      e = buildHorse(h, ph);
      objs.set(h.id, e);
      scene.add(e.root);
    }
    e.lastSeen = now;
    e.root.visible = true;
    const s = Horses.sizeOf(h);
    e.root.position.set(x * K, 0, y * K);
    e.root.rotation.y = -angle;
    e.root.scale.setScalar(s);
    animateHorse(e, h, o, dt);
    // амуниция и всадница
    const R = o.rider;
    e.tack.visible = !!R;
    e.tack.userData.reins.visible = !!R;
    e.legs.forEach(l => { l.boot.visible = !!(R && R.boots); if (R && R.boots) l.boot.material.color.set(R.boots); });
    if (R) {
      e.tack.userData.padMat.color.set(R.pad);
      const key = `${R.shirt}|${R.helmet}`;
      if (!e.rider || e.rider.key !== key) {
        if (e.rider) e.body.remove(e.rider.root);
        e.rider = buildHuman({ shirt: R.shirt, helmet: R.helmet, breeches: true });
        e.rider.key = key;
        e.rider.hair.visible = false;
        e.body.add(e.rider.root);
      }
      const hm = e.rider;
      hm.root.visible = true;
      const k = Math.max(0.78, s) / s;
      hm.root.scale.setScalar(k);
      poseHuman(hm, 'ride', 0);
      // посадка: на рыси облегчаемся, на галопе сидим глубже
      const post = o.gait === 1 && h.spd > 20 ? Math.max(0, Math.sin(e.phase * Math.PI * 4)) * 0.08 : 0;
      hm.root.position.set(-0.06, 1.6 + post, 0);
      hm.pelvis.position.y = 0;
      hm.root.rotation.z = o.gait === 2 ? 0.18 : 0.04;
      if (o.lift) hm.root.rotation.z = 0.45 * o.lift;
      // поводья от удил к рукам
      e.root.updateMatrixWorld(true);
      const bit = V3(1.36 - POLL.x, 1.6 - POLL.y, 0.08);
      e.headPivot.localToWorld(bit);
      const handL = V3(); hm.arms[0].hand.getWorldPosition(handL);
      const handR = V3(); hm.arms[1].hand.getWorldPosition(handR);
      const bitR = V3(1.36 - POLL.x, 1.6 - POLL.y, -0.08); e.headPivot.localToWorld(bitR);
      const pts = [handL, bit, bitR, handR].map(p => e.root.worldToLocal(p));
      const g = e.tack.userData.reins.geometry;
      g.setFromPoints(pts);
    } else if (e.rider) e.rider.root.visible = false;
  }

  function syncGirl(p, dt, on, shirt) {
    if (!girl || girl.key !== shirt) {
      if (girl) scene.remove(girl.root);
      girl = buildHuman({ shirt, helmet: '#222a3a' });
      girl.key = shirt;
      girl.helmet.visible = false; girl.visor.visible = false;
      scene.add(girl.root);
    }
    girl.root.visible = on;
    if (!on) return;
    girl.root.position.set(p.x * K, 0, p.y * K);
    girl.root.rotation.y = -p.angle;
    const spd = (p.spd || 0) * K;
    if (spd > 0.2) girl.phase = (girl.phase + dt * spd * 0.55) % 1;
    poseHuman(girl, 'walk', girl.phase, Math.min(1, spd / 2.5));
  }

  let lastT = 0;
  function render(game) {
    if (!ready) return;
    const S = game.S, p = S.player, t = game.time();
    const dt = Math.min(0.05, Math.max(0, t - lastT) || 0.016);
    lastT = t;
    const now = performance.now();
    const m = game.mounted();

    // камера: сверху-сзади, мир не вращается — управление как в 2D
    const far = Math.hypot(p.x * K - cam.x, p.y * K - cam.z) > 15;
    if (!cam.init || far) { cam.x = p.x * K; cam.z = p.y * K; cam.init = true; }
    cam.x += (p.x * K - cam.x) * 0.1;
    cam.z += (p.y * K - cam.z) * 0.1;
    const z = cam.zoom * (innerWidth < 700 ? 1.25 : 1);
    camera.position.set(cam.x, 9.5 * z + 1, cam.z + 13 * z);
    camera.lookAt(cam.x, 1, cam.z - 1);
    sky.position.copy(camera.position);
    seeUniforms.uCam.value = camera.position;
    seeUniforms.uPlayer.value = V3(p.x * K, 1.5, p.y * K);

    // солнце ходит по небу по игровым часам: восход на востоке (справа), закат на западе
    const hour = S.clock / 60;
    const a = (hour - 5.5) / 14.5 * Math.PI; // восход ~5:30, закат ~20:00
    const sunDir = V3(Math.cos(a), Math.sin(a), 0.45).normalize();
    const dl = game.daylight();
    const low = Math.max(0, 1 - Math.max(0, sunDir.y) * 3); // солнце у горизонта — тёплый свет
    sun.position.set(cam.x + sunDir.x * 60, Math.max(4, sunDir.y * 60), cam.z + sunDir.z * 60);
    sun.target.position.set(cam.x, 0, cam.z);
    sun.intensity = 2.4 * Math.max(0, Math.min(1, sunDir.y * 4)) * dl;
    sun.color.set('#fff1d6').lerp(new T.Color('#ff9a4a'), low * 0.8);
    moon.position.set(cam.x - sunDir.x * 60, 50, cam.z + 20);
    moon.target.position.set(cam.x, 0, cam.z);
    moon.intensity = (1 - dl) * 0.22;
    hemi.intensity = 0.05 + 0.5 * dl;
    hemi.color.set('#2a3a6a').lerp(new T.Color('#cfe6ff'), dl);
    const U = sky.material.uniforms;
    const dayTop = new T.Color('#2f6fd0'), dayHor = new T.Color('#cfe6f5');
    const nightTop = new T.Color('#050a1c'), nightHor = new T.Color('#1a2442');
    const duskHor = new T.Color('#f2a35e');
    U.top.value.copy(nightTop).lerp(dayTop, dl);
    U.horizon.value.copy(nightHor).lerp(dayHor, dl).lerp(duskHor, low * dl * 0.8);
    U.sunDir.value.copy(sunDir);
    U.sunCol.value.set('#fff2c8').lerp(new T.Color('#ff8c3a'), low).multiplyScalar(dl);
    U.starAmt.value = Math.max(0, 1 - dl * 1.5);
    scene.fog.color.copy(U.horizon.value);
    renderer.toneMappingExposure = 0.5 + dl * 0.4;

    // фонари ночью
    const dark = 1 - dl;
    lampGlass.emissiveIntensity = dark * 2.5;
    halos.forEach(hh => { hh.visible = dark > 0.2; hh.material.opacity = dark; });
    const near = World.LAMPS.map(l => ({ l, d: Math.hypot(l.x - p.x, l.y - p.y) })).sort((x, y) => x.d - y.d);
    lampLights.forEach((pl, i) => { const l = near[i].l; pl.position.set(l.x * K, 3.0, l.y * K); pl.intensity = dark * 2.2; });
    playerFill.position.set(p.x * K, 3, p.y * K + 1);
    playerFill.intensity = dark * 0.9;
    fireflies.visible = dark > 0.4;
    if (fireflies.visible) {
      const pos = fireflies.geometry.attributes.position, b = fireflies.userData.base;
      for (let i = 0; i < pos.count; i++) pos.setXYZ(i, b[i * 3] + Math.sin(t * 0.7 + i) * 0.6, b[i * 3 + 1] + Math.sin(t * 1.3 + i * 2) * 0.3, b[i * 3 + 2] + Math.cos(t * 0.5 + i) * 0.6);
      pos.needsUpdate = true;
      fireflies.material.opacity = (dark - 0.4) * 1.6;
    }
    if (water) water.material.normalMap.offset.set(t * 0.01, t * 0.006);

    // трава вокруг камеры
    grassTime.value = t;
    if (!grassCenter || Math.hypot(grassCenter.x - cam.x, grassCenter.z - cam.z) > 6) {
      grassCenter = { x: cam.x, z: cam.z };
      scatterGrass(cam.x, cam.z);
    }

    // крыша конюшни прозрачная, когда ты рядом
    const nearStable = World.inRect(p.x, p.y, World.STABLE, 260);
    roofMats.forEach(mm => { mm.opacity += ((nearStable ? 0 : 1) - mm.opacity) * 0.12; });
    roofGroup.visible = roofMats[0].opacity > 0.03;

    // лошади
    const R = 40;
    const close = h => Math.abs(h.x * K - cam.x) < R && Math.abs(h.y * K - cam.z) < R * 1.2;
    for (const e of objs.values()) e.root.visible = false;
    for (const h of S.horses) if (h.state !== 'ridden' && close(h)) syncHorse(h, h.x, h.y, h.angle, { graze: h.state === 'paddock' && h.spd < 5 }, dt, now);
    for (const h of game.wild()) if (close(h)) syncHorse(h, h.x, h.y, h.angle, { graze: h.spd < 5 && !(h.flee > 0), flee: h.flee > 0 }, dt, now);
    const led = game.led();
    if (led) syncHorse(led, led.x, led.y, led.angle, {}, dt, now);
    if (m) {
      const lift = game.riderLift();
      const ex = game.exercise();
      syncHorse(m, p.x, p.y, p.angle, { rider: game.rider(), gait: S.player.gait, lift, liftPhase: ex && ex.type === 'jump' && ex.air > 0 ? 1 - ex.air / 0.6 : 0.5 }, dt, now);
    }
    for (const [id, e] of objs) if (now - e.lastSeen > 4000) { disposeHorse(e); objs.delete(id); }
    syncGirl(p, dt, !m, S.player.shirt || '#e05a8a');

    // подсказки
    const target = game.catchable();
    ring.visible = !!target;
    if (target) { ring.position.set(target.x * K, 0.05, target.y * K); ring.scale.setScalar(Horses.sizeOf(target) * (1 + Math.sin(t * 5) * 0.06)); }
    const ex = game.exercise();
    letterRing.visible = !!(ex && ex.type === 'dres');
    if (letterRing.visible) { const tp = World.letterTarget(ex.targetLetter); letterRing.position.set(tp.x * K, 0.05, tp.y * K); letterRing.scale.setScalar(1 + Math.sin(t * 6) * 0.1); }
    updateCourse(game);
    updateRope(led, p, m);
    renderer.render(scene, camera);
  }

  let rope = null;
  function updateRope(led, p, m) {
    if (!rope) {
      rope = new T.Line(new T.BufferGeometry().setFromPoints([V3(), V3(), V3()]), new T.LineBasicMaterial({ color: '#b08a4a' }));
      scene.add(rope);
    }
    rope.visible = !!led;
    if (!led) return;
    const e = objs.get(led.id);
    const head = V3(1.3 - POLL.x, 1.62 - POLL.y, 0);
    if (e) e.headPivot.localToWorld(head);
    const hand = V3(p.x * K + Math.cos(p.angle) * 0.2, m ? 1.9 : 0.9, p.y * K + Math.sin(p.angle) * 0.2);
    const mid = hand.clone().lerp(head, 0.5); mid.y -= 0.4;
    rope.geometry.setFromPoints([hand, mid, head]);
  }

  /* ================= экран ↔ мир ================= */
  function toWorld(cx, cy) {
    if (!ready) return null;
    const rc = new T.Raycaster();
    rc.setFromCamera(new T.Vector2((cx / innerWidth) * 2 - 1, -(cy / innerHeight) * 2 + 1), camera);
    const out = V3();
    if (!rc.ray.intersectPlane(new T.Plane(V3(0, 1, 0), 0), out)) return null;
    return { x: out.x / K, y: out.z / K };
  }
  // h — высота в «пикселях карты» (как и x, y)
  function project(x, y, h = 0) {
    const v = V3(x * K, h * K, y * K).project(camera);
    return { x: (v.x + 1) / 2 * innerWidth, y: (1 - v.y) / 2 * innerHeight, ok: v.z < 1 };
  }

  return {
    load, render, toWorld, project, setVisible, zoom,
    get ready() { return ready; },
  };
})();

'use strict';
/*
 * Дополнительная 3D-графика:
 *  - лужи во время дождя и отражения лошадей в них (радужные лужи в волшебном биоме, радуга в лужах после дождя);
 *  - железная дорога, станция и поезд в пустыне;
 *  - олени и птицы; ИИ-игроки верхом;
 *  - праздничные украшения (тыквы, ёлочки, пасхальные яйца);
 *  - заставка рождения жеребёнка.
 */
const VoxelExtra = (() => {
  let X = null, T = null, K = 0.1, V = 0.45;
  const rnd01 = (a, b) => {
    let h = Math.imul(a | 0, 374761393) ^ Math.imul(b | 0, 668265263);
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  };

  /* ================= лужи и отражения ================= */
  const PCELL = 300, PRAD = 1300, POOL = 90;
  let puddles = [], puddleGeos = [], pMat, pRainbowMat, tintMat, tintArcMat, tintRainbowMat, pGroup, tGroup, anyPuddle = false;
  const NOPUDDLE = { desert: 1, cave: 1, tundra: 1, sea: 1, mountain: 1, grottocave: 1, sky: 1, dragonrock: 1 };

  function texRings() {
    const c = document.createElement('canvas'); c.width = c.height = 128;
    const g = c.getContext('2d');
    const cols = ['#ff6b6b', '#ff922b', '#ffd43b', '#51cf66', '#4dabf7', '#7950f2', '#cc5de8'];
    for (let i = cols.length - 1; i >= 0; i--) { g.fillStyle = cols[i]; g.beginPath(); g.arc(64, 64, 10 + i * 8, 0, Math.PI * 2); g.fill(); }
    return new T.CanvasTexture(c);
  }
  function texArc() {
    const c = document.createElement('canvas'); c.width = c.height = 128;
    const g = c.getContext('2d');
    g.fillStyle = '#c9e3f5'; g.fillRect(0, 0, 128, 128);
    const cols = ['#ff0000', '#ff8000', '#ffff00', '#00c000', '#0080ff', '#4b0082', '#8f00ff'];
    g.lineWidth = 6;
    cols.forEach((col, i) => { g.strokeStyle = col; g.beginPath(); g.arc(64, 20, 70 - i * 6, Math.PI * 0.15, Math.PI * 0.85); g.stroke(); });
    return new T.CanvasTexture(c);
  }
  function puddleGeo(seed) {
    const sh = new T.Shape(), ph = [rnd01(seed, 1) * 6.28, rnd01(seed, 2) * 6.28, rnd01(seed, 3) * 6.28];
    for (let i = 0; i <= 40; i++) {
      const a = i / 40 * Math.PI * 2;
      const r = 1 + 0.18 * Math.sin(2 * a + ph[0]) + 0.12 * Math.sin(3 * a + ph[1]) + 0.07 * Math.sin(5 * a + ph[2]);
      const x = Math.cos(a) * r, y = Math.sin(a) * r * 0.7;
      if (i) sh.lineTo(x, y); else sh.moveTo(x, y);
    }
    const g = new T.ShapeGeometry(sh);
    g.rotateX(Math.PI / 2);
    // UV по кругу 0..1 для радужных текстур
    const uv = g.attributes.uv, pos = g.attributes.position;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, pos.getX(i) * 0.5 + 0.5, pos.getZ(i) * 0.5 + 0.5);
    return g;
  }
  function initPuddles() {
    for (let i = 0; i < 6; i++) puddleGeos.push(puddleGeo(i * 13 + 5));
    const stencilWrite = { stencilWrite: true, stencilRef: 1, stencilFunc: T.AlwaysStencilFunc, stencilZPass: T.ReplaceStencilOp, stencilFail: T.KeepStencilOp, stencilZFail: T.KeepStencilOp };
    const stencilTest = { stencilWrite: true, stencilRef: 1, stencilFunc: T.EqualStencilFunc, stencilZPass: T.KeepStencilOp, stencilFail: T.KeepStencilOp, stencilZFail: T.KeepStencilOp };
    pMat = new T.MeshBasicMaterial(Object.assign({ color: '#7d9db6', transparent: true, opacity: 0.8, depthWrite: false, side: T.DoubleSide }, stencilWrite));
    pRainbowMat = new T.MeshBasicMaterial(Object.assign({ map: texRings(), transparent: true, opacity: 0.85, depthWrite: false, side: T.DoubleSide }, stencilWrite));
    tintMat = new T.MeshBasicMaterial(Object.assign({ color: '#b9d4e8', transparent: true, opacity: 0.42, depthTest: false, depthWrite: false, side: T.DoubleSide }, stencilTest));
    tintArcMat = new T.MeshBasicMaterial(Object.assign({ map: texArc(), transparent: true, opacity: 0.55, depthTest: false, depthWrite: false, side: T.DoubleSide }, stencilTest));
    tintRainbowMat = new T.MeshBasicMaterial(Object.assign({ map: pRainbowMat.map, transparent: true, opacity: 0.45, depthTest: false, depthWrite: false, side: T.DoubleSide }, stencilTest));
    pGroup = new T.Group(); tGroup = new T.Group();
    X.scene.add(pGroup); X.scene.add(tGroup);
    for (let i = 0; i < POOL; i++) {
      const m = new T.Mesh(puddleGeos[0], pMat);
      m.renderOrder = 3; m.visible = false; m.frustumCulled = false;
      pGroup.add(m);
      const tm = new T.Mesh(puddleGeos[0], tintMat);
      tm.layers.set(2); tm.renderOrder = 10; tm.visible = false; tm.frustumCulled = false;
      tGroup.add(tm);
      puddles.push({ m, tm });
    }
  }
  const regCache = new Map();
  function puddleOk(x, y, r) {
    const k = `${Math.floor(x / 50)}|${Math.floor(y / 50)}`;
    let v = regCache.get(k);
    if (v == null) {
      const reg = World.regionAt(x, y);
      v = !NOPUDDLE[reg] && !reg.startsWith('sky') && !World.blocked(x, y, r * 0.5) && !World.inRect(x, y, World.STABLE, 30) ? (reg === 'mushroom' ? 2 : 1) : 0;
      if (regCache.size > 6000) regCache.clear();
      regCache.set(k, v);
    }
    return v;
  }
  function updatePuddles(game, t) {
    const level = Events.puddles ? Events.puddles() : 0;
    const rb = Events.rainbow ? Events.rainbow() : 0;
    const p = game.S.player;
    let n = 0;
    anyPuddle = false;
    if (level > 0.03 && p.y < World.H) {
      const gx0 = Math.floor((p.x - PRAD) / PCELL), gx1 = Math.floor((p.x + PRAD) / PCELL);
      const gy0 = Math.floor((p.y - PRAD * 0.8) / PCELL), gy1 = Math.floor((p.y + PRAD * 0.8) / PCELL);
      for (let gx = gx0; gx <= gx1 && n < POOL; gx++) for (let gy = gy0; gy <= gy1 && n < POOL; gy++) {
        if (rnd01(gx, gy) > 0.5) continue;
        const x = (gx + 0.15 + rnd01(gx + 7, gy) * 0.7) * PCELL, y = (gy + 0.15 + rnd01(gx, gy + 9) * 0.7) * PCELL;
        const size = 45 + rnd01(gx + 3, gy + 5) * 85;
        const kind = puddleOk(x, y, size);
        if (!kind) continue;
        // лужа растёт от середины: сначала маленькая, потом во всю ширину
        const grow = Math.min(1, level * (1.2 + rnd01(gx + 11, gy + 2) * 0.8));
        if (grow < 0.08) continue;
        const P = puddles[n++];
        const geo = puddleGeos[Math.floor(rnd01(gx + 1, gy + 1) * 6)];
        P.m.geometry = geo; P.tm.geometry = geo;
        const sc = size * K * grow;
        P.m.scale.set(sc, 1, sc); P.tm.scale.set(sc, 1, sc);
        const ang = rnd01(gx + 2, gy + 4) * 6.28;
        P.m.rotation.y = ang; P.tm.rotation.y = ang;
        P.m.position.set(x * K, 0.075, y * K); P.tm.position.set(x * K, 0.08, y * K);
        P.m.material = kind === 2 ? pRainbowMat : pMat;
        P.tm.material = kind === 2 ? tintRainbowMat : rb > 0 ? tintArcMat : tintMat;
        P.m.visible = true; P.tm.visible = true;
        anyPuddle = true;
      }
    }
    for (let i = n; i < POOL; i++) { puddles[i].m.visible = false; puddles[i].tm.visible = false; }
    tintArcMat.opacity = 0.25 + Math.min(1, rb / 10) * 0.45;
    pRainbowMat.opacity = 0.7 + Math.sin(t * 2) * 0.12;
  }

  // кадр с отражениями: сцена → отражённые лошади только внутри луж (трафарет) → водная плёнка сверху
  const MIRROR = () => new T.Matrix4().makeScale(1, -1, 1);
  let mirror = null;
  function render(game, t) {
    const { renderer, scene, camera } = X;
    if (!anyPuddle) return false;
    try {
      renderer.autoClear = false;
      renderer.clear();
      renderer.render(scene, camera);
      // отражение
      const bg = scene.background;
      scene.background = null;
      renderer.clearDepth();
      renderer.shadowMap.autoUpdate = false;
      camera.updateMatrixWorld();
      const saved = camera.matrixWorld.clone();
      mirror = mirror || MIRROR();
      camera.matrixAutoUpdate = false;
      camera.matrix.copy(mirror).multiply(saved);
      camera.matrixWorld.copy(camera.matrix);
      camera.matrixWorldInverse.copy(camera.matrixWorld).invert();
      camera.matrixWorldNeedsUpdate = false;
      const mats = [X.mat, X.glowMat, X.glassMat];
      const keep = mats.map(m => [m.side, m.stencilWrite, m.stencilFunc, m.stencilRef, m.stencilZPass]);
      for (const m of mats) { m.side = m === X.glassMat ? T.DoubleSide : T.BackSide; m.stencilWrite = true; m.stencilFunc = T.EqualStencilFunc; m.stencilRef = 1; m.stencilZPass = T.KeepStencilOp; m.stencilFail = T.KeepStencilOp; m.stencilZFail = T.KeepStencilOp; }
      camera.layers.set(1);
      renderer.render(scene, camera);
      mats.forEach((m, i) => { [m.side, m.stencilWrite, m.stencilFunc, m.stencilRef, m.stencilZPass] = keep[i]; });
      camera.matrixAutoUpdate = true;
      camera.matrixWorldNeedsUpdate = true;
      camera.updateMatrixWorld();
      // водная плёнка поверх отражений (и радуга в лужах после дождя)
      camera.layers.set(2);
      renderer.render(scene, camera);
      camera.layers.set(0);
      scene.background = bg;
      renderer.shadowMap.autoUpdate = true;
      renderer.autoClear = true;
      return true;
    } catch (e) {
      console.error(e);
      anyPuddle = false;
      X.camera.layers.set(0);
      X.camera.matrixAutoUpdate = true;
      X.renderer.autoClear = true;
      return false;
    }
  }

  /* ================= железная дорога и поезд ================= */
  let train = null, smoke = [];
  function buildRails() {
    const R = World.RAIL, { box, chunk } = X;
    for (let x = R.x1; x < R.x2; x += 28) chunk(x * K, R.y * K).push(box(x * K, 0.08, R.y * K, 0.8, 0.16, 4.6, '#6b4a2b'));
    for (let x = R.x1; x < R.x2; x += 600) {
      const len = Math.min(600, R.x2 - x);
      for (const dz of [-14, 14]) chunk((x + len / 2) * K, R.y * K).push(box((x + len / 2) * K, 0.3, (R.y + dz) * K, len * K, 0.25, 0.25, '#adb5bd'));
    }
    // станция: платформа, домик, скамейка, фонарь
    const S = World.STATION, cx = (S.x + S.w / 2) * K, cz = (S.y + S.h / 2) * K, L = chunk(cx, cz), Gl = chunk(cx, cz, true);
    L.push(box(cx, 0.35, cz, S.w * K, 0.7, S.h * K, '#b5a68f'));
    L.push(box(cx, 0.72, (S.y + S.h) * K - 0.2, S.w * K, 0.06, 0.4, '#ffd43b'));
    const hx = (S.x + 110) * K, hz = (S.y - 25) * K;
    L.push(box(hx, 2, hz, 16, 4, 7, '#e9d8b5'));
    for (let i = 0; i < 4; i++) L.push(box(hx, 4.3 + i * 0.5, hz, 17 - i * 2.6, 0.5, 8 - i * 1.2, '#c0392b'));
    L.push(box(hx - 3, 1.2, hz + 3.55, 1.6, 2.4, 0.1, '#5b3a22'));
    for (const s of [-1, 1]) Gl.push(box(hx + s * 5 + 2, 2.4, hz + 3.55, 1.6, 1.1, 0.08, '#fff3bf'));
    L.push(box((S.x + 380) * K, 1.1, cz, 4, 0.3, 1.2, '#8a5a32'));
    L.push(box((S.x + 380) * K, 0.6, cz, 0.3, 1, 0.3, '#5e3b1d'));
    L.push(box((S.x + 470) * K, 2, cz, 0.3, 4, 0.3, '#343a40'));
    Gl.push(box((S.x + 470) * K, 4.2, cz, 0.8, 0.8, 0.8, '#ffe8a3'));
    const sign = X.textSprite('🚂', '#212529', '#fff3bf');
    sign.position.set(hx, 7.6, hz); sign.scale.set(3, 3, 1);
    X.scene.add(sign);
    X.flushChunks();
  }
  function buildTrain() {
    const { box, boxGeometry, meshOf, glowMesh } = X;
    const g = new T.Group();
    const loco = [], glow = [];
    // паровоз: смотрит в сторону +x
    loco.push(box(0, 2.4, 0, 9, 3, 3.6, '#1f1d22'), box(1.5, 2.6, 0, 6, 2.6, 2.8, '#c92a2a'), box(-3.5, 3.6, 0, 3, 4.6, 3.6, '#a61e1e'),
      box(-3.5, 6.1, 0, 3.6, 0.5, 4, '#1f1d22'), box(3.2, 5, 0, 0.9, 2.4, 0.9, '#1f1d22'), box(3.2, 6.3, 0, 1.4, 0.4, 1.4, '#ffd43b'),
      box(4.9, 1.3, 0, 1, 1, 3.6, '#ffd43b'), box(0.3, 4.1, 0, 0.8, 0.8, 0.8, '#ffd43b'));
    for (const x of [-3, 0, 3]) for (const z of [-1.9, 1.9]) loco.push(box(x, 0.9, z, 1.8, 1.8, 0.4, '#343a40'));
    glow.push(box(4.6, 3, 0, 0.3, 0.9, 0.9, '#fff3bf'));
    for (const z of [-1.82, 1.82]) glow.push(box(-3.5, 4.2, z, 1.8, 1.1, 0.06, '#ffe8a3'));
    const parts = [meshOf(boxGeometry(loco)), glowMesh(boxGeometry(glow))];
    const doors = [];
    const cols = ['#2e86de', '#2b8a3e', '#f08c00', '#7048e8'];
    cols.forEach((c, k) => {
      const ox = -9.6 - k * 10.2;
      const w = [box(ox, 2.6, 0, 9.2, 3.4, 3.6, c), box(ox, 4.5, 0, 9.6, 0.4, 4, '#495057'), box(ox + 5, 1.5, 0, 1.2, 0.3, 0.3, '#343a40')];
      for (const x of [-3, 3]) for (const z of [-1.9, 1.9]) w.push(box(ox + x, 0.9, z, 1.6, 1.6, 0.4, '#343a40'));
      const wg = [];
      for (const x of [-3.2, 3.2]) for (const z of [-1.82, 1.82]) wg.push(box(ox + x, 3.2, z, 1.8, 1, 0.06, '#fff3bf'));
      parts.push(meshOf(boxGeometry(w)), glowMesh(boxGeometry(wg)));
      for (const z of [-1.86, 1.86]) {
        const d = meshOf(boxGeometry([box(0, 0, 0, 2.2, 2.6, 0.12, '#f8f9fa')]));
        d.position.set(ox, 2.3, z);
        d.userData = { ox, z };
        doors.push(d);
        parts.push(d);
      }
    });
    parts.forEach(m => g.add(m));
    g.position.set(0, 0, World.RAIL.y * K);
    g.visible = false;
    X.scene.add(g);
    for (let i = 0; i < 14; i++) {
      const s = new T.Mesh(new T.BoxGeometry(1.2, 1.2, 1.2), new T.MeshLambertMaterial({ color: '#f1f3f5', transparent: true, opacity: 0.8 }));
      s.visible = false;
      X.scene.add(s);
      smoke.push({ m: s, life: 0 });
    }
    train = { g, doors };
  }
  function updateTrain(dt) {
    const st = Train.state();
    train.g.visible = !!st;
    if (!st) { smoke.forEach(s => (s.m.visible = false)); return; }
    train.g.position.x = st.x * K;
    const open = st.state === 'stop' ? Math.min(1, st.t / 1.2) : 0;
    for (const d of train.doors) d.position.x = d.userData.ox + open * 2.4;
    // дым из трубы
    if (Math.random() < (st.state === 'stop' ? 0.15 : 0.6)) {
      const s = smoke.find(q => q.life <= 0);
      if (s) { s.life = 1; s.m.position.set(st.x * K + 3.2, 7, World.RAIL.y * K); s.m.visible = true; }
    }
    for (const s of smoke) {
      if (s.life <= 0) continue;
      s.life -= dt * 0.5;
      s.m.position.y += dt * 3; s.m.position.x -= dt * (st.v * K * 0.6 + 1);
      s.m.scale.setScalar(1 + (1 - s.life) * 2.5);
      s.m.material.opacity = Math.max(0, s.life * 0.8);
      if (s.life <= 0) s.m.visible = false;
    }
  }

  /* ================= олени и птицы ================= */
  const deerObjs = new Map();
  let birdObjs = [];
  function deerObj(d) {
    const { voxelGeometry, key3, mat } = X;
    const cells = new Map(), head = new Map();
    const fill = (m, x0, x1, y0, y1, z0, z1, c) => { for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) m.set(key3(x, y, z), c); };
    const fur = d.fawn ? '#b07a45' : '#9a6a3c', belly = '#efe2cc';
    fill(cells, -5, 4, 7, 10, -2, 1, fur);
    fill(cells, -4, 3, 7, 7, -1, 0, belly);
    fill(cells, -6, -6, 9, 10, -1, 0, '#ffffff');                       // хвостик
    if (d.fawn) for (const [x, z] of [[-3, -2], [0, 1], [2, -2], [-1, 1]]) cells.set(key3(x, 10, z), '#f8f0e0');   // пятнышки оленёнка
    fill(head, 0, 1, 0, 4, -1, 0, fur);                                 // шея
    fill(head, 1, 3, 4, 5, -1, 0, fur);                                 // голова
    head.set(key3(4, 4, -1), '#2b2420'); head.set(key3(4, 4, 0), '#2b2420');
    head.set(key3(2, 5, -2), '#1a1412'); head.set(key3(2, 5, 1), '#1a1412');
    head.set(key3(1, 6, -2), fur); head.set(key3(1, 6, 1), fur);       // уши
    if (d.buck) for (const z of [-1, 0]) for (const [x, y] of [[1, 6], [1, 7], [0, 8], [2, 8], [-1, 9], [1, 9], [3, 9]]) head.set(key3(x, y, z * 3 + (z ? 1 : -1)), '#d8c3a0');
    const g = new T.Group();
    const s = d.fawn ? 0.75 : 1;
    const body = new T.Mesh(voxelGeometry(cells, V * 0.8, 3), mat); body.castShadow = true; g.add(body);
    const hp = new T.Group(); hp.position.set(4 * V * 0.8, 9 * V * 0.8, 0); g.add(hp);
    const hm = new T.Mesh(voxelGeometry(head, V * 0.8, 4), mat); hm.castShadow = true; hp.add(hm);
    const legs = [];
    for (const [x, z] of [[3, -1.5], [3, 1.5], [-4, -1.5], [-4, 1.5]]) {
      const lc = new Map();
      for (let y = -7; y <= -1; y++) lc.set(key3(0, y, 0), y === -7 ? '#2b2420' : fur);
      const pv = new T.Group(); pv.position.set(x * V * 0.8, 7 * V * 0.8, z * V * 0.8);
      const lm = new T.Mesh(voxelGeometry(lc, V * 0.8, 5), mat); lm.castShadow = true; pv.add(lm);
      g.add(pv); legs.push(pv);
    }
    g.scale.setScalar(s);
    g.traverse(n => n.layers.enable(1));
    X.scene.add(g);
    return { g, hp, legs };
  }
  function birdObj(col) {
    const { voxelGeometry, key3, mat } = X;
    const g = new T.Group();
    const c = new Map();
    for (let x = -1; x <= 1; x++) c.set(key3(x, 0, 0), col);
    c.set(key3(2, 0, 0), '#ffa94d');
    c.set(key3(-2, 0, 0), col);
    g.add(new T.Mesh(voxelGeometry(c, 0.26, 1), mat));
    const wings = [-1, 1].map(sd => {
      const w = new Map();
      for (let z = 1; z <= 3; z++) for (let x = -1; x <= 0; x++) w.set(key3(x, 0, z), col);
      const pv = new T.Group(); pv.position.set(0, 0.15, sd > 0 ? 0.26 : 0);
      const m = new T.Mesh(voxelGeometry(w, 0.26, 2), mat);
      if (sd < 0) m.scale.z = -1;
      pv.add(m); g.add(pv);
      return { pv, sd };
    });
    X.scene.add(g);
    return { g, wings };
  }
  function updateAnimals(game, t, info) {
    const cam = info.cam;
    const near = (x, y) => Math.abs(x * K - cam.x) < 80 && Math.abs(y * K - cam.z) < 80;
    const seen = new Set();
    for (const d of Creatures.deer()) {
      if (!near(d.x, d.y)) continue;
      seen.add(d.id);
      let o = deerObjs.get(d.id);
      if (!o) { o = deerObj(d); deerObjs.set(d.id, o); }
      o.g.position.set(d.x * K, 0, d.y * K);
      o.g.rotation.y = -d.angle;
      const move = Math.min(1, d.spd / 120);
      o.legs.forEach((l, i) => { l.rotation.z = Math.sin(d.phase) * ((i === 0 || i === 3) ? 1 : -1) * 0.6 * move; });
      o.hp.rotation.z = d.head < 0 ? -1.2 : Math.sin(d.phase * 2) * 0.05 * move;
    }
    for (const [id, o] of deerObjs) if (!seen.has(id)) { o.g.traverse(n => n.geometry && n.geometry.dispose()); X.scene.remove(o.g); deerObjs.delete(id); }
    const bs = Creatures.birds();
    if (!birdObjs.length) birdObjs = bs.map(b => birdObj(b.flock.col));
    const sky = game.S.player.y > World.H;
    bs.forEach((b, i) => {
      const o = birdObjs[i];
      o.g.visible = !sky;
      o.g.position.set(b.x * K, b.z, b.y * K);
      o.g.rotation.y = -b.angle;
      for (const w of o.wings) w.pv.rotation.x = w.sd * Math.sin(b.phase) * 0.8;
    });
  }

  /* ================= праздничные украшения ================= */
  let decor = {}, decorSpots = null, decorKind = null, decorGhosts = [];
  function spots() {
    if (decorSpots) return decorSpots;
    const out = [], r = World.rng(555);
    for (const road of World.ROADS.slice(0, 9)) for (let i = 0; i < road.length - 1; i++) {
      const [ax, ay] = road[i], [bx, by] = road[i + 1], L = Math.hypot(bx - ax, by - ay);
      for (let s = 120; s < L; s += 260) {
        const t = s / L, nx = -(by - ay) / L, ny = (bx - ax) / L, side = r() < 0.5 ? -1 : 1;
        const x = ax + (bx - ax) * t + nx * 60 * side, y = ay + (by - ay) * t + ny * 60 * side;
        if (!World.blocked(x, y, 22)) out.push({ x, y, s: r() });
      }
    }
    const F = World.FIELD;
    for (let i = 0; i < 18; i++) { const x = F.x + 100 + r() * (F.w - 200), y = F.y + 100 + r() * (F.h - 200); if (!World.blocked(x, y, 30)) out.push({ x, y, s: r() }); }
    decorSpots = out;
    return out;
  }
  function buildDecor(kind) {
    const { box, boxGeometry, meshOf, glowMesh } = X;
    const L = [], Gl = [];
    for (const p of spots()) {
      const x = p.x * K, z = p.y * K, s = 0.8 + p.s * 0.6;
      if (kind === 'halloween') {
        L.push(box(x, 0.8 * s, z, 2 * s, 1.6 * s, 1.8 * s, '#f76707'), box(x, 0.8 * s, z, 1.5 * s, 1.65 * s, 2 * s, '#ff922b'), box(x, 1.75 * s, z, 0.3, 0.5, 0.3, '#2b8a3e'));
        Gl.push(box(x - 0.4 * s, 1 * s, z + 0.92 * s, 0.35 * s, 0.35 * s, 0.1, '#ffd43b'), box(x + 0.4 * s, 1 * s, z + 0.92 * s, 0.35 * s, 0.35 * s, 0.1, '#ffd43b'), box(x, 0.55 * s, z + 0.92 * s, 1 * s, 0.22 * s, 0.1, '#ffd43b'));
      } else if (kind === 'newyear') {
        L.push(box(x, 0.6, z, 0.5, 1.2, 0.5, '#6b4423'));
        for (let i = 0; i < 4; i++) L.push(box(x, 1.4 + i * 1.1, z, (3.2 - i * 0.7) * s, 1.1, (3.2 - i * 0.7) * s, i % 2 ? '#1f5a2a' : '#2f7a3a'));
        const toys = ['#e03131', '#ffd43b', '#4dabf7', '#cc5de8', '#ffffff'];
        for (let i = 0; i < 6; i++) { const a = i * 1.1 + p.s * 6, rr = (1.4 - (i % 3) * 0.3) * s; Gl.push(box(x + Math.cos(a) * rr, 1.5 + (i % 3) * 1.1, z + Math.sin(a) * rr, 0.4, 0.4, 0.4, toys[i % toys.length])); }
        Gl.push(box(x, 6.1, z, 0.7, 0.7, 0.2, '#ffd43b'));
      } else {
        const cols = [['#ffb3d1', '#fff3bf'], ['#a5d8ff', '#ffffff'], ['#b2f2bb', '#ffd43b'], ['#e5dbff', '#ff8fab']][Math.floor(p.s * 4)];
        for (let i = 0; i < 5; i++) { const w = [1.2, 1.7, 1.9, 1.6, 1][i] * s; L.push(box(x, (0.4 + i * 0.6) * s, z, w, 0.6 * s, w, i === 2 ? cols[1] : cols[0])); }
        L.push(box(x + 1.4 * s, 0.35, z, 1.2, 0.7, 0.9, '#c0a080'), box(x + 1.4 * s, 0.85, z, 0.5, 0.4, 0.5, '#ffd43b'));
      }
    }
    const g = new T.Group();
    if (L.length) g.add(meshOf(boxGeometry(L)));
    if (Gl.length) g.add(glowMesh(boxGeometry(Gl)));
    g.visible = false;
    X.scene.add(g);
    return g;
  }
  function updateDecor(t) {
    const k = Holidays.current();
    if (k !== decorKind) {
      for (const g of Object.values(decor)) g.visible = false;
      if (k) { decor[k] = decor[k] || buildDecor(k); decor[k].visible = true; }
      decorKind = k;
    }
  }

  /* ================= ИИ-игроки ================= */
  function syncHorses(game, t, close) {
    for (const b of AI.bots()) if (close(b.h)) X.syncHorse(b.h, b.x, b.y, b.angle, { t, rider: b.look });
  }

  /* ================= заставка: рождение жеребёнка ================= */
  let bs = null;
  function birthScene(canvas, mare, foal, onDone) {
    if (!bs) {
      const r = new T.WebGLRenderer({ canvas, antialias: true, alpha: false });
      const sc = new T.Scene();
      sc.background = new T.Color('#ffe8cc');
      sc.add(new T.HemisphereLight('#ffffff', '#8a7a66', 0.75));
      const dl = new T.DirectionalLight('#fff4dd', 0.7); dl.position.set(6, 12, 9); sc.add(dl);
      const cam = new T.PerspectiveCamera(32, 1, 0.1, 200);
      const ground = X.meshOf(X.boxGeometry([X.box(0, -0.25, 0, 60, 0.5, 30, '#e4c46c'),
        X.box(-4, 0.7, -6, 3.6, 1.4, 2.4, '#d8b85c'), X.box(6, 0.6, -5, 3, 1.2, 2.2, '#d8b85c'),
        X.box(0, 3, -9, 40, 6, 0.6, '#8a5a32'), X.box(0, 6.2, -9, 40, 0.5, 1.2, '#6b4423')]));
      sc.add(ground);
      bs = { r, sc, cam, objs: [] };
    }
    bs.r.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
    bs.r.setSize(canvas.clientWidth || 600, canvas.clientHeight || 340, false);
    bs.cam.aspect = (canvas.clientWidth || 600) / (canvas.clientHeight || 340);
    bs.cam.updateProjectionMatrix();
    for (const o of bs.objs) { bs.sc.remove(o.group); o.group.traverse(n => n.geometry && n.geometry.dispose()); }
    const m = { ...mare, id: -1, act: null }, f = { ...foal, id: -2, act: { k: 'lie', t: 0, d: 99 } };
    const om = X.makeHorseObj(m, Horses.pheno(mare)), of = X.makeHorseObj(f, Horses.pheno(foal));
    bs.sc.add(om.group); bs.sc.add(of.group);
    bs.objs = [om, of];
    const hearts = [];
    for (let i = 0; i < 10; i++) {
      const hm = new T.Mesh(new T.BoxGeometry(0.5, 0.5, 0.5), new T.MeshBasicMaterial({ color: i % 2 ? '#ff6b9a' : '#ffa8c5', transparent: true, opacity: 0 }));
      bs.sc.add(hm); hearts.push(hm); bs.objs.push({ group: hm });
    }
    const D = 9.5, t0 = performance.now();
    let doneCalled = false;
    const frame = () => {
      const tt = (performance.now() - t0) / 1000;
      // мама нюхает и облизывает малыша, потом смотрит, как он встаёт
      m.act = tt < 3.2 ? { k: 'graze', t: Math.min(tt, 2.5) + 0.8, d: 6 } : tt < 7 ? { k: 'lookDown', t: 1, d: 2.5 } : { k: 'neigh', t: (tt - 7) % 1.8, d: 1.8 };
      if (tt < 2.8) f.act = { k: 'lie', t: tt, d: 99 };
      else if (tt < 7.4) f.act = { k: 'getup', t: (tt - 2.8) / 4.6 * 4.6, d: 4.6 };
      else f.act = { k: 'play', t: (tt - 7.4), d: 2.1 };
      if (f.act.k === 'play' && f.act.t > f.act.d) f.act = null;
      m.spd = 0; f.spd = 0;
      X.poseHorse(om, m, -42, 0, 0.25, { t: tt });
      X.poseHorse(of, f, 32, 26, Math.PI + 0.35, { t: tt });
      hearts.forEach((hm, i) => {
        const k = ((tt * 0.5 + i / hearts.length) % 1);
        hm.position.set(2 + Math.sin(i * 2.1 + tt) * 2, 2 + k * 6, 2.6 + Math.cos(i * 1.7) * 1.5);
        hm.material.opacity = tt > 6.5 ? Math.sin(k * Math.PI) * 0.9 : 0;
        hm.rotation.y = tt * 2 + i;
      });
      bs.cam.position.set(4 + Math.sin(tt * 0.2) * 2, 6.5, 19);
      bs.cam.lookAt(1.5, 2.2, 0);
      bs.r.render(bs.sc, bs.cam);
      if (tt < D || !doneCalled) {
        if (tt >= D - 1.5 && !doneCalled) { doneCalled = true; onDone && onDone(); }
        bs.raf = requestAnimationFrame(frame);
      }
    };
    cancelAnimationFrame(bs.raf);
    bs.raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(bs.raf);
  }

  /* ================= общий шаг ================= */
  function init(ctx) {
    X = ctx; T = ctx.T; K = ctx.K; V = ctx.V;
    // свет действует и на отражения (слой 1)
    X.scene.traverse(n => { if (n.isLight) { n.layers.enable(1); n.layers.enable(2); } });
    initPuddles();
    buildRails();
    buildTrain();
  }
  function update(game, t, dt, info) {
    updatePuddles(game, t);
    updateTrain(dt);
    updateAnimals(game, t, info);
    updateDecor(t);
  }

  return { init, update, render, syncHorses, birthScene };
})();

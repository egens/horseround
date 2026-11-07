'use strict';
/* Рисование на 2D-холсте: подписи, текстура земли для 3D-мира и миникарта */
const Draw = (() => {
  const TAU = Math.PI * 2;

  function ell(ctx, x, y, rx, ry, rot = 0) {
    ctx.moveTo(x + rx * Math.cos(rot), y + rx * Math.sin(rot));
    ctx.ellipse(x, y, rx, ry, rot, 0, TAU);
  }
  function fillEll(ctx, x, y, rx, ry, color, rot = 0) {
    ctx.fillStyle = color; ctx.beginPath(); ell(ctx, x, y, rx, ry, rot); ctx.fill();
  }

  function label(ctx, text, x, y, size = 16, color = '#3b2a1a') {
    ctx.font = `bold ${size}px "Trebuchet MS", system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 4;
    ctx.strokeStyle = 'rgba(255,255,255,0.85)';
    ctx.strokeText(text, x, y);
    ctx.fillStyle = color;
    ctx.fillText(text, x, y);
  }

  /* ---------- земля всего мира (текстура для 3D и миникарта) ---------- */
  // цвет земли и «крапинки» каждого биома
  const PAL = {
    farm: ['#86b85a', ['#78aa4d', '#97c76a', '#6f9e45']],
    field: ['#8fc260', ['#7fb251', '#a4d273', '#c7d96b']],
    village: ['#89bb5c', ['#78aa4d', '#97c76a', '#a99168']],
    farmland: ['#9cc46a', ['#8ab35a', '#b0d27c']],
    market: ['#c9b48a', ['#b9a378', '#d8c49a', '#a99168']],
    lake: ['#8cc063', ['#7cb253', '#a6d37a', '#c3e08a']],
    forest: ['#5d8c3c', ['#4f7d33', '#6e9c47', '#7a6a3a', '#4a6b2e']],
    mushroom: ['#4d7d5c', ['#3f6c4f', '#5f9070', '#8a63c9', '#b07fe0', '#3f8f86']],
    mountain: ['#7d7a80', ['#6c6970', '#8e8b92', '#5e5b62', '#86956a']],
    cave: ['#4a4652', ['#3d3945', '#57525f', '#2f2c36']],
    desert: ['#e8cf8f', ['#d9bd78', '#f2dca4', '#cfae66']],
    deepforest: ['#3f6b2e', ['#34592a', '#4a7a36', '#5c4a2a', '#2d4d24']],
    tundra: ['#eef3f7', ['#dde7ee', '#ffffff', '#c9d6e0', '#b7c9b0']],
    sea: ['#2f7fb8', ['#3a8fc8', '#2a6fa4', '#5aaee0', '#ffffff']],
    grotto: ['#7f9a5e', ['#6f8a50', '#94a86e', '#8a8a80', '#6b6b62', '#a3b37a']],
    grottocave: ['#38343e', ['#2e2a33', '#46414d', '#26232b']],
    foxwood: ['#3d6630', ['#325a28', '#4b7a38', '#7a4a1e', '#c0601a', '#2a4a22', '#d9822b']],
    dragonrock: ['#3d3437', ['#2a2427', '#4a3f43', '#6b2a1a', '#ff5a1f', '#1f1a1c']],
    steppe: ['#bcc56a', ['#a9b25a', '#cfd27e', '#d9c77a', '#93a24e']],
    i1: ['#8cc063', ['#7cb253', '#a6d37a', '#ffb3d9', '#fff3bf']],
    i4: ['#4a2219', ['#3d1a14', '#5a2a1f', '#341610', '#64301f']],
  };
  PAL.i2 = PAL.i3 = PAL.i1;
  const REGIONS = Object.keys(PAL);

  const polyPath = (g, pts) => { g.beginPath(); pts.forEach((p, i) => (i ? g.lineTo(p.x, p.y) : g.moveTo(p.x, p.y))); g.closePath(); };

  // s — масштаб: сколько пикселей холста на пиксель мира
  function worldGround(g, s, detail = true) {
    const rnd = World.rng(7);
    const px = 1 / s; // размер точки в мире, чтобы она была ~1 пиксель холста
    const W = World.W, H = World.H;
    // 1. клетки: биом в случайной точке клетки — края получаются неровными
    const cs = Math.max(26, 1.6 / s);
    const nx = Math.ceil(W / cs), ny = Math.ceil(H / cs);
    const grid = new Uint8Array(nx * ny);
    for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
      const x = (i + rnd()) * cs, y = (j + rnd()) * cs;
      let reg = World.regionAt(x, y);
      if (!PAL[reg]) reg = 'farm';
      grid[j * nx + i] = REGIONS.indexOf(reg);
      let c = PAL[reg][0];
      if (reg !== 'sea' && x > World.coastX(y) - 140 && !reg.startsWith('i')) c = '#e8d8a8';   // пляж у моря
      g.fillStyle = c;
      g.fillRect(i * cs, j * cs, cs + 0.5, cs + 0.5);
    }
    const regAt = (x, y) => REGIONS[grid[Math.min(ny - 1, Math.max(0, Math.floor(y / cs))) * nx + Math.min(nx - 1, Math.max(0, Math.floor(x / cs)))]];
    // 2. крапинки по биомам
    if (detail) {
      const n = Math.floor(W * H / 520);
      for (let i = 0; i < n; i++) {
        const x = rnd() * W, y = rnd() * H, reg = regAt(x, y), cols = PAL[reg][1];
        g.fillStyle = cols[Math.floor(rnd() * cols.length)];
        const sz = px * 1.6 * (0.5 + rnd());
        g.fillRect(x, y, sz, sz);
      }
      // барханы в пустыне
      g.strokeStyle = 'rgba(190,150,80,0.35)'; g.lineWidth = 18;
      for (let i = 0; i < 160; i++) {
        const x0 = rnd() * W, y0 = World.DESERT.y + rnd() * World.DESERT.h;
        if (regAt(x0, y0) !== 'desert') continue;
        g.beginPath(); g.moveTo(x0 - 220, y0); g.quadraticCurveTo(x0, y0 - 90, x0 + 220, y0); g.stroke();
      }
      // трещины с лавой на Драконьих скалах
      g.strokeStyle = 'rgba(255,110,40,0.55)'; g.lineWidth = 7;
      for (let i = 0; i < 260; i++) {
        let x = World.DRAGONROCK.x + rnd() * World.DRAGONROCK.w, y = rnd() * World.DRAGONROCK.h;
        if (regAt(x, y) !== 'dragonrock') continue;
        g.beginPath(); g.moveTo(x, y);
        for (let k = 0; k < 4; k++) { x += (rnd() - 0.5) * 160; y += (rnd() - 0.5) * 160; g.lineTo(x, y); }
        g.stroke();
      }
    }
    // 3. острова: мель, песок и трава по неровному контуру
    for (const I of World.ISLANDS) {
      g.fillStyle = '#4a9fd0'; polyPath(g, World.blobPoly(I, 120)); g.fill();
      g.fillStyle = I.bone ? '#5a3a2e' : '#ead9a6'; polyPath(g, World.blobPoly(I, 0)); g.fill();
      const pal = PAL[I.id] || PAL.i1;
      g.fillStyle = pal[0]; polyPath(g, World.blobPoly(I, -70)); g.fill();
      if (detail) for (let i = 0; i < 4000; i++) {
        const a = rnd() * TAU, d = Math.sqrt(rnd()) * World.shapeR(I, a) * 0.92;
        g.fillStyle = pal[1][Math.floor(rnd() * pal[1].length)];
        const sz = px * 1.6 * (0.5 + rnd());
        g.fillRect(I.x + Math.cos(a) * I.rx * d, I.y + Math.sin(a) * I.ry * d, sz, sz);
      }
      g.fillStyle = '#d9b862'; g.fillRect(I.stable.x, I.stable.y, I.stable.w, I.stable.h);
      g.fillStyle = 'rgba(70,120,40,0.25)'; g.fillRect(I.pasture.x, I.pasture.y, I.pasture.w, I.pasture.h);
      g.fillStyle = '#dcc394'; g.beginPath(); ell(g, I.pen.x, I.pen.y, I.pen.r, I.pen.r); g.fill();
      g.fillStyle = '#8a5a32'; g.fillRect(I.pier.x - 220, I.pier.y - 30, 240, 60);
    }
    g.fillStyle = '#8a5a32'; g.fillRect(World.PIER.x - 20, World.PIER.y - 30, 260, 60);
    // поля: полосы пшеницы и вспаханной земли
    const FL = World.FARMLAND;
    const strips = [[FL.x + 40, FL.y + 420, 520, 420], [FL.x + 1000, FL.y + 60, 560, 380]];
    for (const [x, y, w, h] of strips) {
      for (let i = 0; i < h; i += 40) { g.fillStyle = i % 80 ? '#e2c86a' : '#cdb25a'; g.fillRect(x, y + i, w, 36); }
    }
    g.fillStyle = '#8a6a44'; g.fillRect(FL.x + 620, FL.y + 470, 340, 330);
    for (let i = 0; i < 330; i += 30) { g.fillStyle = '#76583a'; g.fillRect(FL.x + 620, FL.y + 470 + i, 340, 8); }
    // деревенская площадь
    const Sq = World.SQUARE;
    g.fillStyle = '#cbb48a';
    g.beginPath(); ell(g, Sq.x, Sq.y, Sq.rx, Sq.ry); g.fill();
    // рынок: брусчатка
    const Mk = World.MARKET;
    g.fillStyle = PAL.market[0]; g.fillRect(Mk.x, Mk.y, Mk.w, Mk.h);
    if (detail) {
      g.strokeStyle = 'rgba(120,95,60,0.25)'; g.lineWidth = 2;
      for (let x = Mk.x; x <= Mk.x + Mk.w; x += 24) { g.beginPath(); g.moveTo(x, Mk.y); g.lineTo(x, Mk.y + Mk.h); g.stroke(); }
      for (let y = Mk.y; y <= Mk.y + Mk.h; y += 24) { g.beginPath(); g.moveTo(Mk.x, y); g.lineTo(Mk.x + Mk.w, y); g.stroke(); }
    }
    // портал в пещере: светящийся круг на полу
    g.fillStyle = 'rgba(151,117,250,0.45)'; g.beginPath(); ell(g, World.PORTAL.x, World.PORTAL.y + 20, 110, 70); g.fill();
    // дороги
    g.lineCap = 'round'; g.lineJoin = 'round';
    for (const [w, c] of [[56, '#b8986a'], [46, '#cdb07c']]) {
      g.strokeStyle = c; g.lineWidth = w;
      for (const p of World.ROADS) {
        g.beginPath(); g.moveTo(p[0][0], p[0][1]);
        for (let i = 1; i < p.length; i++) g.lineTo(p[i][0], p[i][1]);
        g.stroke();
      }
    }
    // железная дорога: насыпь из гравия и платформа станции
    const R = World.RAIL;
    g.fillStyle = '#9c8f7c'; g.fillRect(R.x1, R.y - 34, R.x2 - R.x1, 68);
    g.fillStyle = '#b5a68f'; g.fillRect(World.STATION.x, World.STATION.y, World.STATION.w, World.STATION.h);
    // озёра: берег, вода, блики — тоже неровные
    for (const L of World.LAKES) {
      g.fillStyle = L.magic ? '#c9a7e8' : L.ice ? '#ffffff' : L.lava ? '#2a2022' : '#d8c590';
      polyPath(g, World.blobPoly(L, 26)); g.fill();
      const gr = g.createRadialGradient(L.x - L.rx * 0.2, L.y - L.ry * 0.2, 10, L.x, L.y, L.rx * 1.1);
      gr.addColorStop(0, L.magic ? '#f0b8ff' : L.ice ? '#f4fbff' : L.lava ? '#ffd43b' : '#8fd0f0');
      gr.addColorStop(1, L.magic ? '#8a4fd8' : L.ice ? '#a5d8ff' : L.lava ? '#e8590c' : '#3f8fc0');
      g.fillStyle = gr;
      polyPath(g, World.blobPoly(L, 0)); g.fill();
    }
    // ферма: манеж, конюшня, левада, конкурное поле
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
    if (detail) for (const f of World.FLOWERS) { g.fillStyle = f.c; g.fillRect(f.x, f.y, Math.max(f.s, px * 1.5), Math.max(f.s, px * 1.5)); }
  }

  /* ---------- миникарта ---------- */
  const mmScale = c => Math.min(c.width / World.W, c.height / World.H);
  let mmBg = null;
  function minimap(mctx, S, game) {
    const c = mctx.canvas, k = mmScale(c);
    if (!mmBg || mmBg.width !== c.width) {
      mmBg = document.createElement('canvas');
      mmBg.width = c.width; mmBg.height = c.height;
      const g = mmBg.getContext('2d');
      g.fillStyle = '#2f7fb8'; g.fillRect(0, 0, c.width, c.height);
      g.scale(k, k);
      worldGround(g, k, false);
      g.fillStyle = '#8a5a32'; g.fillRect(World.STABLE.x, World.STABLE.y, World.STABLE.w, World.STABLE.h);
      g.fillStyle = '#3d6b2a';
      for (const t of World.TREES) {
        if (t.soft || t.kind === 'rock' || t.kind === 'cactus' || t.kind === 'drybush' || t.kind === 'bush') continue;
        g.fillStyle = t.kind === 'mesa' ? '#c0603a' : t.kind === 'snowrock' ? '#9aa5b1' : t.kind === 'snowspruce' ? '#5f8a75'
          : t.kind === 'spire' || t.kind === 'basalt' || t.kind === 'cavewall' || t.kind === 'cliff' ? '#4a4247' : t.kind === 'hill' ? '#6f8a50' : t.kind === 'bigskull' ? '#e9e2cf' : '#3d6b2a';
        g.fillRect(t.x - 25, t.y - 25, 50, 50);
      }
      g.fillStyle = '#6b4a2b';
      for (const hh of World.HOUSES) g.fillRect(hh.x, hh.y, hh.w, hh.h);
    }
    if (S.player.y > World.H) return skyMinimap(mctx, S, game);
    mctx.drawImage(mmBg, 0, 0);
    for (const b of S.builds || []) { const r = Farm.rectOf(b); mctx.fillStyle = '#a0522d'; mctx.fillRect(r.x * k, r.y * k, Math.max(2, r.w * k), Math.max(2, r.h * k)); }
    for (const w of game.wild()) {
      mctx.fillStyle = w.magic && w.magic.skeleton ? '#ffffff' : Horses.pheno(w).body;
      mctx.beginPath(); mctx.arc(w.x * k, w.y * k, 2, 0, TAU); mctx.fill();
    }
    for (const n of Quests.NPCS) {
      const mk = Quests.marker(n.id);
      mctx.fillStyle = mk === '❗' || mk === '❓' ? '#ffd43b' : '#74c0fc';
      mctx.fillRect(n.x * k - 2, n.y * k - 2, 4, 4);
    }
    if (S.bigTreasure) {
      const x = S.bigTreasure.x * k, y = S.bigTreasure.y * k;
      mctx.strokeStyle = '#e03131'; mctx.lineWidth = 2;
      mctx.beginPath(); mctx.moveTo(x - 4, y - 4); mctx.lineTo(x + 4, y + 4); mctx.moveTo(x + 4, y - 4); mctx.lineTo(x - 4, y + 4); mctx.stroke();
    }
    const p = S.player;
    mctx.fillStyle = '#ff2d75';
    mctx.strokeStyle = '#fff';
    mctx.lineWidth = 1.5;
    mctx.beginPath(); mctx.arc(p.x * k, p.y * k, 4, 0, TAU); mctx.fill(); mctx.stroke();
    const v = game.view();
    mctx.strokeStyle = 'rgba(255,255,255,0.8)';
    mctx.strokeRect(v.x * k, v.y * k, v.w * k, v.h * k);
  }

  // на небесных островах миникарта показывает только небо
  function skyMinimap(mctx, S, game) {
    const c = mctx.canvas, Z = World.SKY, k = Math.min(c.width / Z.w, c.height / Z.h);
    const ox = (c.width - Z.w * k) / 2, oy = (c.height - Z.h * k) / 2;
    const X = x => ox + (x - Z.x) * k, Y = y => oy + (y - Z.y) * k;
    mctx.fillStyle = '#bfe3ff'; mctx.fillRect(0, 0, c.width, c.height);
    mctx.strokeStyle = '#a0754a'; mctx.lineWidth = Math.max(2, World.BRIDGE_W * 2 * k);
    for (const b of World.SKY_BRIDGES) { mctx.beginPath(); mctx.moveTo(X(b[0]), Y(b[1])); mctx.lineTo(X(b[2]), Y(b[3])); mctx.stroke(); }
    for (const I of World.SKY_ISLANDS) {
      mctx.fillStyle = '#86c95a'; mctx.beginPath();
      World.blobPoly(I, 0, 40).forEach((q, i) => (i ? mctx.lineTo(X(q.x), Y(q.y)) : mctx.moveTo(X(q.x), Y(q.y))));
      mctx.closePath(); mctx.fill();
    }
    fillEll(mctx, X(World.SKY_PORTAL.x), Y(World.SKY_PORTAL.y), 4, 4, '#9775fa');
    for (const w of game.wild()) {
      if (w.y < World.H) continue;
      mctx.fillStyle = Horses.pheno(w).body;
      mctx.beginPath(); mctx.arc(X(w.x), Y(w.y), 2, 0, TAU); mctx.fill();
    }
    const p = S.player;
    mctx.fillStyle = '#ff2d75'; mctx.strokeStyle = '#fff'; mctx.lineWidth = 1.5;
    mctx.beginPath(); mctx.arc(X(p.x), Y(p.y), 4, 0, TAU); mctx.fill(); mctx.stroke();
  }

  return { label, fillEll, worldGround, minimap, mmScale };
})();

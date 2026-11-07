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
  function speckle(g, r, n, colors, rnd, size) {
    for (let i = 0; i < n; i++) {
      g.fillStyle = colors[Math.floor(rnd() * colors.length)];
      const s = size * (0.5 + rnd());
      g.fillRect(r.x + rnd() * r.w, r.y + rnd() * r.h, s, s);
    }
  }

  // s — масштаб: сколько пикселей холста на пиксель мира
  function worldGround(g, s, detail = true) {
    const rnd = World.rng(7);
    const px = 1 / s; // размер точки в мире, чтобы она была ~1 пиксель холста
    const area = (r, base, specks, n) => {
      g.fillStyle = base; g.fillRect(r.x, r.y, r.w, r.h);
      if (detail) speckle(g, r, n, specks, rnd, px * 1.6);
    };
    area({ x: 0, y: 0, w: World.W, h: World.H }, '#86b85a', ['#78aa4d', '#97c76a', '#6f9e45'], 60000);
    area(World.FIELD, '#8fc260', ['#7fb251', '#a4d273', '#c7d96b'], 9000);
    area(World.LAKELAND, '#8cc063', ['#7cb253', '#a6d37a', '#c3e08a'], 9000);
    for (const f of World.FOREST) area(f, '#5d8c3c', ['#4f7d33', '#6e9c47', '#7a6a3a', '#4a6b2e'], Math.floor(f.w * f.h / 900));
    // Грибное королевство: мох и фиолетовые искорки
    area(World.MUSHROOM, '#4d7d5c', ['#3f6c4f', '#5f9070', '#8a63c9', '#b07fe0', '#3f8f86'], 20000);
    // горы и пещера
    area(World.MOUNTAIN, '#7d7a80', ['#6c6970', '#8e8b92', '#5e5b62'], 9000);
    area(World.CAVE, '#4a4652', ['#3d3945', '#57525f', '#2f2c36'], 12000);
    // юг: пустыня с барханами, дремучий лес, заснеженная тундра
    area(World.DESERT, '#e8cf8f', ['#d9bd78', '#f2dca4', '#cfae66'], 30000);
    g.strokeStyle = 'rgba(190,150,80,0.35)'; g.lineWidth = 18;
    for (let i = 0; i < 40; i++) {
      const x0 = World.DESERT.x + rnd() * World.DESERT.w, y0 = World.DESERT.y + rnd() * World.DESERT.h;
      g.beginPath(); g.moveTo(x0 - 220, y0); g.quadraticCurveTo(x0, y0 - 90, x0 + 220, y0); g.stroke();
    }
    area(World.DEEPFOREST, '#3f6b2e', ['#34592a', '#4a7a36', '#5c4a2a', '#2d4d24'], 20000);
    area(World.TUNDRA, '#eef3f7', ['#dde7ee', '#ffffff', '#c9d6e0', '#b7c9b0'], 30000);
    // море и острова
    area(World.SEA, '#2f7fb8', ['#3a8fc8', '#2a6fa4', '#5aaee0', '#ffffff'], 40000);
    g.fillStyle = '#e8d8a8'; g.fillRect(World.SEA.x - 120, 0, 140, World.H);
    for (const I of World.ISLANDS) {
      g.fillStyle = '#4a9fd0'; g.beginPath(); ell(g, I.x, I.y, I.rx + 120, I.ry + 110); g.fill();
      g.fillStyle = '#ead9a6'; g.beginPath(); ell(g, I.x, I.y, I.rx, I.ry); g.fill();
      g.fillStyle = '#8cc063'; g.beginPath(); ell(g, I.x, I.y, I.rx - 70, I.ry - 60); g.fill();
      if (detail) speckle(g, { x: I.x - I.rx, y: I.y - I.ry, w: I.rx * 2, h: I.ry * 2 }, 2500, ['#7cb253', '#a6d37a', '#ffb3d9', '#fff3bf'], rnd, px * 1.6);
      g.fillStyle = '#d9b862'; g.fillRect(I.stable.x, I.stable.y, I.stable.w, I.stable.h);
      g.fillStyle = 'rgba(70,120,40,0.25)'; g.fillRect(I.pasture.x, I.pasture.y, I.pasture.w, I.pasture.h);
      g.fillStyle = '#dcc394'; g.beginPath(); ell(g, I.pen.x, I.pen.y, I.pen.r, I.pen.r); g.fill();
      g.fillStyle = '#8a5a32'; g.fillRect(I.pier.x - 220, I.pier.y - 30, 240, 60);
    }
    g.fillStyle = '#8a5a32'; g.fillRect(World.PIER.x - 20, World.PIER.y - 30, 260, 60);
    // поля: полосы пшеницы и вспаханной земли
    const FL = World.FARMLAND;
    g.fillStyle = '#9cc46a'; g.fillRect(FL.x, FL.y, FL.w, FL.h);
    const strips = [[FL.x + 40, FL.y + 420, 520, 420], [FL.x + 1000, FL.y + 60, 560, 380]];
    for (const [x, y, w, h] of strips) {
      for (let i = 0; i < h; i += 40) { g.fillStyle = i % 80 ? '#e2c86a' : '#cdb25a'; g.fillRect(x, y + i, w, 36); }
    }
    g.fillStyle = '#8a6a44'; g.fillRect(FL.x + 620, FL.y + 470, 340, 330);
    for (let i = 0; i < 330; i += 30) { g.fillStyle = '#76583a'; g.fillRect(FL.x + 620, FL.y + 470 + i, 340, 8); }
    // деревенская площадь
    g.fillStyle = '#cbb48a';
    g.beginPath(); ell(g, 2650, 2920, 330, 190); g.fill();
    // рынок: брусчатка
    area(World.MARKET, '#c9b48a', ['#b9a378', '#d8c49a', '#a99168'], 3000);
    if (detail) {
      g.strokeStyle = 'rgba(120,95,60,0.25)'; g.lineWidth = 2;
      for (let x = World.MARKET.x; x <= World.MARKET.x + World.MARKET.w; x += 24) { g.beginPath(); g.moveTo(x, World.MARKET.y); g.lineTo(x, World.MARKET.y + World.MARKET.h); g.stroke(); }
      for (let y = World.MARKET.y; y <= World.MARKET.y + World.MARKET.h; y += 24) { g.beginPath(); g.moveTo(World.MARKET.x, y); g.lineTo(World.MARKET.x + World.MARKET.w, y); g.stroke(); }
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
    // озёра: песчаный берег, вода, блики
    for (const L of World.LAKES) {
      g.fillStyle = L.magic ? '#c9a7e8' : L.ice ? '#ffffff' : '#d8c590';
      g.beginPath(); ell(g, L.x, L.y, L.rx + 28, L.ry + 22); g.fill();
      const gr = g.createRadialGradient(L.x - L.rx * 0.2, L.y - L.ry * 0.2, 10, L.x, L.y, L.rx);
      gr.addColorStop(0, L.magic ? '#f0b8ff' : L.ice ? '#f4fbff' : '#8fd0f0');
      gr.addColorStop(1, L.magic ? '#8a4fd8' : L.ice ? '#a5d8ff' : '#3f8fc0');
      g.fillStyle = gr;
      g.beginPath(); ell(g, L.x, L.y, L.rx, L.ry); g.fill();
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
  let mmBg = null;
  function minimap(mctx, S, game) {
    const c = mctx.canvas, k = c.width / World.W;
    if (!mmBg || mmBg.width !== c.width) {
      mmBg = document.createElement('canvas');
      mmBg.width = c.width; mmBg.height = c.height;
      const g = mmBg.getContext('2d');
      g.scale(k, k);
      worldGround(g, k, false);
      g.fillStyle = '#8a5a32'; g.fillRect(World.STABLE.x, World.STABLE.y, World.STABLE.w, World.STABLE.h);
      g.fillStyle = '#3d6b2a';
      for (const t of World.TREES) {
        if (t.kind === 'rock' || t.kind === 'cactus' || t.kind === 'drybush') continue;
        g.fillStyle = t.kind === 'mesa' ? '#c0603a' : t.kind === 'snowrock' ? '#9aa5b1' : t.kind === 'snowspruce' ? '#5f8a75' : '#3d6b2a';
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
    for (const I of World.SKY_ISLANDS) { fillEll(mctx, X(I.x), Y(I.y), I.rx * k, I.ry * k, '#86c95a'); }
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

  return { label, fillEll, worldGround, minimap };
})();

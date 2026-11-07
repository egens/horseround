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
      g.fillStyle = L.magic ? '#c9a7e8' : '#d8c590';
      g.beginPath(); ell(g, L.x, L.y, L.rx + 28, L.ry + 22); g.fill();
      const gr = g.createRadialGradient(L.x - L.rx * 0.2, L.y - L.ry * 0.2, 10, L.x, L.y, L.rx);
      gr.addColorStop(0, L.magic ? '#f0b8ff' : '#8fd0f0');
      gr.addColorStop(1, L.magic ? '#8a4fd8' : '#3f8fc0');
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
      for (const t of World.TREES) if (t.kind !== 'rock') g.fillRect(t.x - 25, t.y - 25, 50, 50);
      g.fillStyle = '#6b4a2b';
      for (const hh of World.HOUSES) g.fillRect(hh.x, hh.y, hh.w, hh.h);
    }
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

  return { label, fillEll, worldGround, minimap };
})();

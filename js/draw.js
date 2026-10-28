'use strict';
/* Рисование: лошади, всадница, ферма — всё вид сверху */
const Draw = (() => {
  const TAU = Math.PI * 2;
  const mix = Genetics.mix;

  function ell(ctx, x, y, rx, ry, rot = 0) {
    ctx.moveTo(x + rx * Math.cos(rot), y + rx * Math.sin(rot));
    ctx.ellipse(x, y, rx, ry, rot, 0, TAU);
  }
  function fillEll(ctx, x, y, rx, ry, color, rot = 0) {
    ctx.fillStyle = color; ctx.beginPath(); ell(ctx, x, y, rx, ry, rot); ctx.fill();
  }

  /* ================= ЛОШАДЬ ================= */
  // o: { t, rider:{pad, helmet, boots}, scale, noShadow, lift }
  function horse(ctx, h, x, y, ang, o = {}) {
    const ph = Horses.pheno(h);
    const B = Genetics.BREEDS[h.breed] || Genetics.BREEDS.mix;
    const s = (o.scale || 1) * Horses.sizeOf(h);
    const t = o.t || 0;
    const move = Math.min(1, (h.spd || 0) / 110);
    const phase = h.phase || 0;
    const rnd = World.rng(h.seed);
    const white = '#f6f3ec';
    const headTurn = h.headTurn || 0;

    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(ang);
    ctx.scale(s, s);
    // lift: 0..1 — насколько лошадь в воздухе (прыжок)
    const lift = typeof o.lift === 'number' ? o.lift : o.lift ? 0.35 : 0;
    if (!o.noShadow) fillEll(ctx, 3 + lift * 16, 5 + lift * 16, 44 - lift * 6, 18 - lift * 3, `rgba(0,0,0,${0.18 - lift * 0.06})`);
    if (lift) ctx.scale(1 + lift * 0.2, 1 + lift * 0.2);

    // ноги: по диагонали в такт; сверху видны в основном копыта
    const legs = [[15, -1], [15, 1], [-18, -1], [-18, 1]];
    for (let i = 0; i < 4; i++) {
      const diag = (i === 0 || i === 3) ? 1 : -1;
      const off = Math.sin(phase) * diag * 11 * move;
      const lx = legs[i][0] + off, ly = legs[i][1] * 9.5;
      const col = (h.marks.legs[i] || ph.tob) ? white : ph.legs;
      if (B.feather) fillEll(ctx, lx, ly, 7, 4.2, col);
      else fillEll(ctx, lx, ly, 5.5, 3.2, col);
      if (o.rider && o.rider.boots) fillEll(ctx, lx - 1, ly, 4, 3.4, o.rider.boots);
      fillEll(ctx, lx + 4.6, ly, 2.2, 2.6, '#2b2420');
    }

    // хвост: сужается к концу и покачивается
    const sway = Math.sin(t * 2.2 + h.seed % 7) * 0.3 + Math.sin(phase * 0.5) * 0.2 * move;
    const tl = (B.feather ? 52 : 46) + move * 4;
    const tipY = sway * 16;
    ctx.fillStyle = ph.mane;
    ctx.beginPath();
    ctx.moveTo(-27, -5);
    ctx.quadraticCurveTo(-38, -4 + tipY * 0.4, -tl, tipY - 1.5);
    ctx.quadraticCurveTo(-tl - 2, tipY, -tl, tipY + 1.5);
    ctx.quadraticCurveTo(-38, 4 + tipY * 0.4, -27, 5);
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = mix(ph.mane, '#000000', 0.18);
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(-30, 0);
    ctx.quadraticCurveTo(-38, tipY * 0.4, -tl + 4, tipY);
    ctx.stroke();

    // силуэт: круп + бочка + грудь + шея + голова
    const silhouette = () => {
      ctx.beginPath();
      ell(ctx, -2, 0, 28, 12.5);
      ell(ctx, -17, 0, 13, 13.8);
      ell(ctx, 13, 0, 12, 12.2);
      ell(ctx, 25, 0, 13, 8);
      ctx.save();
      ctx.translate(31, 0);
      ctx.rotate(headTurn);
      ell(ctx, 13, 0, 11, 6.6);
      ctx.restore();
    };
    silhouette();
    ctx.fillStyle = ph.body;
    ctx.fill();

    // узоры поверх тела
    ctx.save();
    silhouette();
    ctx.clip();
    if (ph.dapple) {
      const c = mix(ph.body, '#ffffff', 0.4);
      for (let i = 0; i < 22; i++) {
        const ax = -32 + rnd() * 50, ay = -12 + rnd() * 24;
        fillEll(ctx, ax, ay, 2.2 + rnd() * 2.2, 2 + rnd() * 2, c);
      }
    }
    if (ph.roan) {
      ctx.fillStyle = 'rgba(255,255,255,0.55)';
      for (let i = 0; i < 90; i++) {
        const ax = -30 + rnd() * 50, ay = -13 + rnd() * 26;
        ctx.fillRect(ax, ay, 1.3, 1.3);
      }
    }
    if (ph.tob) {
      const n = 3 + Math.floor(rnd() * 3);
      for (let i = 0; i < n; i++) {
        const ax = -28 + rnd() * 46, ay = -6 + rnd() * 12;
        fillEll(ctx, ax, ay, 6 + rnd() * 9, 10 + rnd() * 7, white, rnd() - 0.5);
      }
    }
    if (ph.leo) {
      fillEll(ctx, -13, 0, 18 + rnd() * 6, 14, white);
      const sc = ph.greyLevel > 0.6 ? '#3a3a3a' : (ph.body === white ? '#3b2a20' : mix(ph.body, '#000000', 0.15));
      for (let i = 0; i < 18; i++) {
        const a = rnd() * TAU, r = rnd() * 15;
        fillEll(ctx, -13 + Math.cos(a) * r, Math.sin(a) * r * 0.75, 1.6 + rnd() * 1.8, 1.4 + rnd() * 1.5, sc);
      }
    }
    if (B.sheen) {
      const gr = ctx.createLinearGradient(0, -14, 0, 14);
      gr.addColorStop(0, 'rgba(255,240,200,0)');
      gr.addColorStop(0.45, 'rgba(255,245,215,0.32)');
      gr.addColorStop(1, 'rgba(255,240,200,0)');
      ctx.fillStyle = gr;
      ctx.fillRect(-34, -15, 70, 30);
    }
    ctx.restore();

    // «ремень» у саврасых
    if (ph.stripe) {
      ctx.strokeStyle = ph.stripe;
      ctx.lineWidth = 2.6;
      ctx.beginPath();
      ctx.moveTo(-27, 0);
      ctx.lineTo(12, 0);
      ctx.stroke();
    }

    // голова
    ctx.save();
    ctx.translate(31, 0);
    ctx.rotate(headTurn);
    // отметины
    if (h.marks.face === 1) fillEll(ctx, 6, 0, 2.8, 2.3, white);
    else if (h.marks.face === 2) { fillEll(ctx, 6, 0, 2.8, 2.3, white); fillEll(ctx, 15, 0, 8, 1.8, white); }
    else if (h.marks.face === 3) fillEll(ctx, 13, 0, 10, 4.6, white);
    const muzzle = (ph.pinkSkin || h.marks.face === 3) ? '#d9a597' : mix(ph.body, '#000000', 0.35);
    fillEll(ctx, 21, 0, 5.4, 5.2, muzzle);
    fillEll(ctx, 24.2, -2.1, 1, 1.1, 'rgba(0,0,0,0.6)');
    fillEll(ctx, 24.2, 2.1, 1, 1.1, 'rgba(0,0,0,0.6)');
    // глаза и уши
    fillEll(ctx, 8.5, -6.2, 1.5, 1.2, '#1a1412');
    fillEll(ctx, 8.5, 6.2, 1.5, 1.2, '#1a1412');
    const ear = mix(ph.body, '#000000', 0.2);
    fillEll(ctx, 2.5, -4.6, 3.6, 1.9, ear, 0.3);
    fillEll(ctx, 2.5, 4.6, 3.6, 1.9, ear, -0.3);
    // чёлка
    fillEll(ctx, 4.5, 0, 4.5, 2.6, ph.mane);
    ctx.restore();

    // грива лежит на одну сторону шеи
    if (B.fjordMane) {
      fillEll(ctx, 23, 0, 12, 3.2, '#efe4cf');
      fillEll(ctx, 23, 0, 11, 1.2, '#2a211b');
    } else {
      const long = B.longMane;
      fillEll(ctx, 23, long ? 4 : 2.6, 12, long ? 5 : 3, ph.mane);
      ctx.strokeStyle = mix(ph.mane, '#000000', 0.2);
      ctx.lineWidth = 0.8;
      ctx.beginPath();
      for (let i = 0; i < 5; i++) {
        const mx = 14 + i * 4;
        ctx.moveTo(mx, 1);
        ctx.lineTo(mx - 2, (long ? 8 : 5) + (i % 2));
      }
      ctx.stroke();
    }

    // седло и всадница
    if (o.rider) {
      const R = o.rider;
      ctx.fillStyle = R.pad || '#c0392b';
      ctx.beginPath();
      ctx.roundRect(-15, -15.5, 24, 31, 5);
      ctx.fill();
      fillEll(ctx, -3, 0, 10.5, 10, '#5b3a1e');
      fillEll(ctx, -5, 0, 6.5, 7, '#7a4f2a');
      // ноги в сапогах
      fillEll(ctx, -1, -14, 6, 3, '#2c2a2f');
      fillEll(ctx, -1, 14, 6, 3, '#2c2a2f');
      // поводья
      ctx.strokeStyle = '#3b2412';
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(6, -4); ctx.lineTo(36, -4.5);
      ctx.moveTo(6, 4); ctx.lineTo(36, 4.5);
      ctx.stroke();
      // корпус, руки, шлем, хвостик
      fillEll(ctx, -4, 0, 6.5, 9.2, R.shirt || '#e05a8a');
      fillEll(ctx, 3, -6, 4.8, 2.2, R.shirt || '#e05a8a');
      fillEll(ctx, 3, 6, 4.8, 2.2, R.shirt || '#e05a8a');
      fillEll(ctx, 7, -4.5, 1.9, 1.9, '#f2c9a5');
      fillEll(ctx, 7, 4.5, 1.9, 1.9, '#f2c9a5');
      fillEll(ctx, -11, 0, 5, 2.6, '#7a4a22');
      fillEll(ctx, -3, 0, 6.6, 6.2, R.helmet || '#222a3a');
      fillEll(ctx, 3.2, 0, 2, 4.5, mix(R.helmet || '#222a3a', '#000000', 0.3));
      fillEll(ctx, -5, -2, 2.2, 1.6, 'rgba(255,255,255,0.25)');
    }
    ctx.restore();
  }

  /* ================= ДЕВОЧКА ПЕШКОМ ================= */
  function girl(ctx, p, t) {
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(p.angle);
    fillEll(ctx, 1, 3, 12, 10, 'rgba(0,0,0,0.18)');
    const sw = Math.sin(p.phase) * Math.min(1, p.spd / 60) * 6;
    fillEll(ctx, sw, -4.2, 4.6, 2.8, '#2c2a2f');
    fillEll(ctx, -sw, 4.2, 4.6, 2.8, '#2c2a2f');
    fillEll(ctx, 0, 0, 6, 9.5, p.shirt || '#e05a8a');
    fillEll(ctx, -sw * 0.6, -10, 4.5, 2.4, p.shirt || '#e05a8a');
    fillEll(ctx, sw * 0.6, 10, 4.5, 2.4, p.shirt || '#e05a8a');
    fillEll(ctx, -sw * 0.6 + 3.5, -10.5, 2, 2, '#f2c9a5');
    fillEll(ctx, sw * 0.6 + 3.5, 10.5, 2, 2, '#f2c9a5');
    fillEll(ctx, -9, Math.sin(t * 3) * 0.8, 5.5, 2.8, '#7a4a22');
    fillEll(ctx, 0.5, 0, 6.6, 6.3, '#f2c9a5');
    fillEll(ctx, -1, 0, 6.4, 6.4, '#7a4a22');
    fillEll(ctx, 4.2, 0, 1.8, 4.4, '#f2c9a5');
    ctx.restore();
  }

  /* ================= ОКРУЖЕНИЕ ================= */
  let grassPattern = null, fieldPattern = null, strawPattern = null, sandPattern = null;
  function makePattern(ctx, size, base, dots) {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const g = c.getContext('2d');
    g.fillStyle = base;
    g.fillRect(0, 0, size, size);
    const r = World.rng(size + base.length * 31 + dots.length);
    for (const d of dots) {
      g.fillStyle = d.c;
      for (let i = 0; i < d.n; i++) {
        const x = r() * size, y = r() * size;
        if (d.blade) { g.fillRect(x, y, 1.2, 3 + r() * 3); }
        else if (d.line) { g.save(); g.translate(x, y); g.rotate(r() * TAU); g.fillRect(0, 0, 7 + r() * 6, 1.4); g.restore(); }
        else g.fillRect(x, y, d.s || 2, d.s || 2);
      }
    }
    return ctx.createPattern(c, 'repeat');
  }
  function ensurePatterns(ctx) {
    if (grassPattern) return;
    grassPattern = makePattern(ctx, 160, '#86b85a', [
      { c: '#78aa4d', n: 260, blade: true }, { c: '#97c76a', n: 220, blade: true }, { c: '#6f9e45', n: 80 }]);
    fieldPattern = makePattern(ctx, 160, '#8fc260', [
      { c: '#7fb251', n: 300, blade: true }, { c: '#a4d273', n: 240, blade: true }, { c: '#c7d96b', n: 30 }]);
    strawPattern = makePattern(ctx, 80, '#e4c46c', [
      { c: '#c9a44b', n: 50, line: true }, { c: '#f3da8e', n: 50, line: true }]);
    sandPattern = makePattern(ctx, 120, '#dcc394', [
      { c: '#cdb27f', n: 160 }, { c: '#e8d3a8', n: 160 }, { c: '#c6a974', n: 40, s: 1 }]);
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

  function ground(ctx, view) {
    ensurePatterns(ctx);
    ctx.fillStyle = grassPattern;
    ctx.fillRect(view.x, view.y, view.w, view.h);
    const F = World.FIELD;
    ctx.fillStyle = fieldPattern;
    ctx.fillRect(F.x, F.y, F.w, F.h);
    // мягкая граница поля
    const gr = ctx.createLinearGradient(F.x - 60, 0, F.x + 40, 0);
    gr.addColorStop(0, 'rgba(134,184,90,1)');
    gr.addColorStop(1, 'rgba(134,184,90,0)');
    ctx.fillStyle = gr;
    ctx.fillRect(F.x - 1, F.y, 41, F.h);

    // тропинки
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    const paths = [
      [[860, 310], [940, 310], [940, 600], [1275, 600], [1275, 540]],
      [[1275, 600], [1650, 600], [1800, 560]],
      [[120, 310], [70, 310], [70, 850], [140, 850]],
      [[70, 850], [70, 1120], [270, 1120], [270, 1180]],
      [[1110, 600], [1110, 1000]],
      [[960, 850], [1110, 850]],
    ];
    for (const [w, c] of [[52, '#b8986a'], [44, '#cdb07c']]) {
      ctx.strokeStyle = c;
      ctx.lineWidth = w;
      for (const p of paths) {
        ctx.beginPath();
        ctx.moveTo(p[0][0], p[0][1]);
        for (let i = 1; i < p.length; i++) ctx.lineTo(p[i][0], p[i][1]);
        ctx.stroke();
      }
    }

    // цветы
    for (const f of World.FLOWERS) {
      if (f.x < view.x - 5 || f.x > view.x + view.w + 5 || f.y < view.y - 5 || f.y > view.y + view.h + 5) continue;
      ctx.fillStyle = f.c;
      ctx.fillRect(f.x, f.y, f.s, f.s);
    }

    // пруд
    const P = World.POND;
    fillEll(ctx, P.x, P.y, P.rx + 10, P.ry + 10, '#7d9b52');
    const pg = ctx.createRadialGradient(P.x - 40, P.y - 30, 10, P.x, P.y, P.rx);
    pg.addColorStop(0, '#8fd0f0');
    pg.addColorStop(1, '#3f8fc0');
    ctx.fillStyle = pg;
    ctx.beginPath();
    ell(ctx, P.x, P.y, P.rx, P.ry);
    ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.5)';
    ctx.lineWidth = 2;
    for (let i = 0; i < 4; i++) {
      ctx.beginPath();
      ctx.ellipse(P.x - 60 + i * 45, P.y - 20 + (i % 2) * 40, 20, 4, 0, 0, Math.PI);
      ctx.stroke();
    }
    ctx.strokeStyle = '#4c7a2e';
    ctx.lineWidth = 2;
    for (let i = 0; i < 26; i++) {
      const a = (i / 26) * TAU;
      const rx = Math.cos(a) * (P.rx + 4), ry = Math.sin(a) * (P.ry + 4);
      ctx.beginPath();
      ctx.moveTo(P.x + rx, P.y + ry);
      ctx.lineTo(P.x + rx * 1.06 + 3, P.y + ry * 1.08 - 10);
      ctx.stroke();
    }
  }

  function stable(ctx, S, game) {
    const R = World.STABLE;
    // пол прохода
    ctx.fillStyle = '#bfb6a5';
    ctx.fillRect(R.x, World.AISLE_Y1, R.w, World.AISLE_Y2 - World.AISLE_Y1);
    ctx.fillStyle = 'rgba(0,0,0,0.05)';
    for (let x = R.x; x < R.x + R.w; x += 40) ctx.fillRect(x, World.AISLE_Y1, 1, World.AISLE_Y2 - World.AISLE_Y1);
    // денники
    for (let i = 0; i < 20; i++) {
      const r = World.stallRect(i);
      ctx.fillStyle = strawPattern;
      ctx.fillRect(r.x, r.y, r.w, r.h);
      // кормушка и поилка у дальней стены
      const fy = r.row ? r.y + r.h - 14 : r.y + 4;
      ctx.fillStyle = '#6b4a2b';
      ctx.fillRect(r.x + 8, fy, 24, 10);
      ctx.fillStyle = '#9b7a3a';
      ctx.fillRect(r.x + 10, fy + 2, 20, 6);
      fillEll(ctx, r.x + r.w - 16, fy + 5, 7, 6, '#5a7d99');
      fillEll(ctx, r.x + r.w - 16, fy + 5, 5, 4, '#8cc6e8');
    }
    // перегородки
    ctx.fillStyle = '#7b5532';
    for (let c = 0; c <= 10; c++) {
      const x = R.x + 10 + c * World.STALL_W - 3;
      ctx.fillRect(x, R.y + 10, 6, World.STALL_H);
      ctx.fillRect(x, World.AISLE_Y2, 6, World.STALL_H);
    }
    // решётки денников со стороны прохода (с дверцей посередине)
    ctx.fillStyle = '#4a3423';
    for (let c = 0; c < 10; c++) {
      const x = R.x + 10 + c * World.STALL_W;
      ctx.fillRect(x, World.AISLE_Y1 - 3, 18, 6);
      ctx.fillRect(x + World.STALL_W - 18, World.AISLE_Y1 - 3, 18, 6);
      ctx.fillRect(x, World.AISLE_Y2 - 3, 18, 6);
      ctx.fillRect(x + World.STALL_W - 18, World.AISLE_Y2 - 3, 18, 6);
      ctx.fillStyle = 'rgba(74,52,35,0.45)';
      ctx.fillRect(x + 18, World.AISLE_Y1 - 1.5, World.STALL_W - 36, 3);
      ctx.fillRect(x + 18, World.AISLE_Y2 - 1.5, World.STALL_W - 36, 3);
      ctx.fillStyle = '#4a3423';
    }
    // стены
    ctx.fillStyle = '#8a5a32';
    for (const s of World.SOLIDS.slice(0, 6)) ctx.fillRect(s.x, s.y, s.w, s.h);
    ctx.strokeStyle = 'rgba(60,35,15,0.5)';
    ctx.lineWidth = 2;
    ctx.strokeRect(R.x + 1, R.y + 1, R.w - 2, R.h - 2);
    // номера и таблички с именами
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (let i = 0; i < 20; i++) {
      const r = World.stallRect(i);
      const plateY = r.row ? World.AISLE_Y2 + 10 : World.AISLE_Y1 - 10;
      const h = game.horseInStall(i);
      ctx.fillStyle = 'rgba(255,250,235,0.92)';
      ctx.fillRect(r.x + 6, plateY - 7, r.w - 12, 14);
      ctx.fillStyle = '#3b2a1a';
      ctx.font = 'bold 10px system-ui, sans-serif';
      let txt = String(i + 1);
      if (h) txt = h.name.length > 9 ? h.name.slice(0, 8) + '…' : h.name;
      ctx.fillText(txt, r.x + r.w / 2, plateY);
    }
    // тюки сена у ворот
    for (const [x, y] of [[R.x - 30, R.y + 40], [R.x - 30, R.y + 80], [R.x + R.w + 30, R.y + R.h - 50]]) {
      ctx.fillStyle = '#d8b85c';
      ctx.fillRect(x - 18, y - 12, 36, 24);
      ctx.strokeStyle = '#a98a3a';
      ctx.lineWidth = 2;
      ctx.strokeRect(x - 18, y - 12, 36, 24);
      ctx.beginPath(); ctx.moveTo(x - 6, y - 12); ctx.lineTo(x - 6, y + 12); ctx.moveTo(x + 6, y - 12); ctx.lineTo(x + 6, y + 12); ctx.stroke();
    }
    label(ctx, '🐴 КОНЮШНЯ', R.x + R.w / 2, R.y - 18, 20, '#5a3412');
  }

  function fenceRect(ctx, r, gate, color, post) {
    // gate: {side:'left'|'bottom', a, b}
    ctx.strokeStyle = color;
    ctx.lineWidth = 3;
    const seg = (x1, y1, x2, y2) => {
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
      ctx.save();
      ctx.translate(-2, -2);
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
      ctx.restore();
      const len = Math.hypot(x2 - x1, y2 - y1), n = Math.max(1, Math.round(len / 40));
      ctx.fillStyle = post;
      for (let i = 0; i <= n; i++) {
        const px = x1 + (x2 - x1) * i / n, py = y1 + (y2 - y1) * i / n;
        ctx.fillRect(px - 3, py - 3, 6, 6);
      }
    };
    const { x, y, w, h } = r;
    if (gate.side === 'top') { seg(x, y, gate.a, y); seg(gate.b, y, x + w, y); }
    else seg(x, y, x + w, y);
    seg(x + w, y, x + w, y + h);
    if (gate.side === 'bottom') { seg(x, y + h, gate.a, y + h); seg(gate.b, y + h, x + w, y + h); seg(x, y, x, y + h); }
    else if (gate.side === 'top') { seg(x, y + h, x + w, y + h); seg(x, y, x, y + h); }
    else { seg(x, y + h, x + w, y + h); seg(x, y, x, gate.a); seg(x, gate.b, x, y + h); }
  }

  function arena(ctx, S, game) {
    const A = World.ARENA;
    ctx.fillStyle = sandPattern;
    ctx.fillRect(A.x, A.y, A.w, A.h);
    // следы дорожки
    ctx.strokeStyle = 'rgba(160,125,75,0.25)';
    ctx.lineWidth = 26;
    ctx.strokeRect(A.x + 34, A.y + 34, A.w - 68, A.h - 68);
    // кавалетти
    const ex = game.exercise();
    const C = World.CAV;
    C.poles.forEach((px, i) => {
      const knocked = ex && ex.type === 'cav' && ex.poles[i].state === 'hit';
      const clean = ex && ex.type === 'cav' && ex.poles[i].state === 'ok';
      ctx.save();
      ctx.translate(px, (C.y1 + C.y2) / 2);
      if (knocked) ctx.rotate(0.25);
      // стойки-крестовины
      ctx.strokeStyle = '#6b4a2b';
      ctx.lineWidth = 4;
      for (const yy of [-(C.y2 - C.y1) / 2, (C.y2 - C.y1) / 2]) {
        ctx.beginPath(); ctx.moveTo(-7, yy - 7); ctx.lineTo(7, yy + 7); ctx.moveTo(7, yy - 7); ctx.lineTo(-7, yy + 7); ctx.stroke();
      }
      // жердь в полоску
      const len = C.y2 - C.y1;
      for (let k = 0; k < 8; k++) {
        ctx.fillStyle = k % 2 ? '#ffffff' : (clean ? '#2e9d4f' : '#d63a3a');
        ctx.fillRect(-3.5, -len / 2 + (len / 8) * k, 7, len / 8 + 0.5);
      }
      ctx.restore();
    });
    label(ctx, 'кавалетти', C.poles[2], C.y2 + 18, 12, '#6b4a2b');

    // ограждение
    fenceRect(ctx, A, { side: 'left', a: World.GATE_A.y1, b: World.GATE_A.y2 }, '#ffffff', '#e6e6e6');
    // буквы
    const target = ex && ex.type === 'dres' ? ex.targetLetter : null;
    for (const [L, p] of Object.entries(World.LETTERS)) {
      if (L === 'X') {
        if (target === 'X') {
          ctx.strokeStyle = 'rgba(255,255,255,0.8)';
          ctx.lineWidth = 2;
          ctx.beginPath(); ctx.moveTo(p.x - 10, p.y - 10); ctx.lineTo(p.x + 10, p.y + 10); ctx.moveTo(p.x + 10, p.y - 10); ctx.lineTo(p.x - 10, p.y + 10); ctx.stroke();
        }
        continue;
      }
      const off = 22;
      const bx = p.side === 'left' ? p.x - off : p.side === 'right' ? p.x + off : p.x;
      const by = p.side === 'top' ? p.y - off : p.side === 'bottom' ? p.y + off : p.y;
      ctx.fillStyle = target === L ? '#ffd43b' : '#ffffff';
      ctx.strokeStyle = '#555';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.roundRect(bx - 12, by - 12, 24, 24, 4);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = '#1c1c1c';
      ctx.font = 'bold 16px system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(L, bx, by + 1);
    }
    if (target) {
      const tp = World.letterTarget(target);
      const pulse = 22 + Math.sin(game.time() * 6) * 5;
      ctx.strokeStyle = 'rgba(255,200,0,0.9)';
      ctx.lineWidth = 4;
      ctx.beginPath(); ell(ctx, tp.x, tp.y, pulse, pulse); ctx.stroke();
    }
    label(ctx, '🏇 МАНЕЖ', A.x + A.w * 0.32, A.y - 26, 20, '#5a3412');
  }

  /* ---------- конкурное поле ---------- */
  const RAIL = { cross: ['#1c7ed6', '#fff'], vertical: ['#e03131', '#fff'], oxer: ['#2b8a3e', '#fff'], triple: ['#f08c00', '#fff'], wall: ['#c2410c', '#fff'] };
  function rail(ctx, x, half, colors, w = 6) {
    const n = 8, seg = (half * 2) / n;
    for (let k = 0; k < n; k++) {
      ctx.fillStyle = colors[k % 2];
      ctx.fillRect(x - w / 2, -half + k * seg, w, seg + 0.5);
    }
    ctx.strokeStyle = 'rgba(0,0,0,0.25)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x - w / 2, -half, w, half * 2);
  }
  function obstacle(ctx, o, st, current) {
    ctx.save();
    ctx.translate(o.x, o.y);
    ctx.rotate(o.a);
    const half = o.half, col = RAIL[o.type];
    if (current) {
      ctx.fillStyle = 'rgba(255,212,59,0.35)';
      ctx.beginPath(); ell(ctx, 0, 0, 34, half + 16); ctx.fill();
    }
    // тень
    ctx.fillStyle = 'rgba(0,0,0,0.15)';
    ctx.fillRect(-12, -half, 30, half * 2);
    const knocked = st === 'hit';
    if (o.type === 'wall') {
      ctx.fillStyle = '#b5532d';
      ctx.fillRect(-7, -half, 14, half * 2);
      ctx.strokeStyle = 'rgba(255,255,255,0.6)';
      ctx.lineWidth = 1;
      for (let yy = -half; yy < half; yy += 8) { ctx.beginPath(); ctx.moveTo(-7, yy); ctx.lineTo(7, yy); ctx.stroke(); }
      if (knocked) { ctx.fillStyle = '#b5532d'; ctx.fillRect(9, -half * 0.4, 9, 18); }
    } else if (o.type === 'cross') {
      ctx.save(); ctx.rotate(knocked ? 0 : 0.35); rail(ctx, 0, half - 4, col); ctx.restore();
      ctx.save(); ctx.rotate(knocked ? 0.1 : -0.35); ctx.translate(knocked ? 16 : 0, 0); rail(ctx, 0, half - 4, col); ctx.restore();
    } else {
      const xs = o.type === 'oxer' ? [-8, 8] : o.type === 'triple' ? [-12, 0, 12] : [0];
      xs.forEach((xx, i) => {
        if (knocked && i === xs.length - 1) { ctx.save(); ctx.translate(xx + 16, 4); ctx.rotate(0.18); rail(ctx, 0, half - 2, col); ctx.restore(); }
        else rail(ctx, xx, half - 2, col);
      });
    }
    // стойки
    ctx.fillStyle = '#f8f9fa';
    ctx.strokeStyle = '#868e96';
    for (const yy of [-half - 5, half + 5]) { ctx.fillRect(-14, yy - 4, 28, 8); ctx.strokeRect(-14, yy - 4, 28, 8); }
    // флажки: красный справа, белый слева — как на настоящих соревнованиях
    ctx.fillStyle = '#e03131';
    ctx.beginPath(); ctx.moveTo(-12, half + 9); ctx.lineTo(-2, half + 13); ctx.lineTo(-12, half + 17); ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.moveTo(-12, -half - 9); ctx.lineTo(-2, -half - 13); ctx.lineTo(-12, -half - 17); ctx.fill();
    ctx.restore();
    // номер
    const nx = o.x + Math.cos(o.a + Math.PI / 2) * (half + 30) - Math.cos(o.a) * 10;
    const ny = o.y + Math.sin(o.a + Math.PI / 2) * (half + 30) - Math.sin(o.a) * 10;
    ctx.fillStyle = st === 'ok' ? '#2b8a3e' : st === 'hit' ? '#c92a2a' : current ? '#f59f00' : '#ffffff';
    ctx.strokeStyle = '#343a40';
    ctx.lineWidth = 2;
    ctx.beginPath(); ell(ctx, nx, ny, 12, 12); ctx.fill(); ctx.stroke();
    ctx.fillStyle = st || current ? '#fff' : '#212529';
    ctx.font = 'bold 13px system-ui, sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(String(o.n), nx, ny + 1);
    if (current) {
      // стрелка направления прыжка
      ctx.save();
      ctx.translate(o.x - Math.cos(o.a) * 60, o.y - Math.sin(o.a) * 60);
      ctx.rotate(o.a);
      ctx.fillStyle = 'rgba(245,159,0,0.85)';
      ctx.beginPath(); ctx.moveTo(14, 0); ctx.lineTo(-6, -10); ctx.lineTo(-6, 10); ctx.closePath(); ctx.fill();
      ctx.restore();
    }
  }
  function jumpField(ctx, game) {
    const J = World.JUMPF;
    ctx.fillStyle = 'rgba(60,110,30,0.16)';
    ctx.fillRect(J.x, J.y, J.w, J.h);
    // следы маршрута
    ctx.strokeStyle = 'rgba(255,255,255,0.18)';
    ctx.lineWidth = 3;
    ctx.setLineDash([10, 12]);
    ctx.beginPath();
    World.COURSE.forEach((o, i) => (i ? ctx.lineTo(o.x, o.y) : ctx.moveTo(o.x - 120, o.y)));
    ctx.stroke();
    ctx.setLineDash([]);
    const ex = game.exercise();
    World.COURSE.forEach((o, i) => {
      const st = ex && ex.type === 'jump' ? ex.jumps[i] : null;
      obstacle(ctx, o, st, ex && ex.type === 'jump' && ex.i === i);
    });
    fenceRect(ctx, J, { side: 'top', a: World.JUMPF_GATE.x1, b: World.JUMPF_GATE.x2 }, '#ffffff', '#dee2e6');
    label(ctx, '🏆 КОНКУРНОЕ ПОЛЕ', J.x + J.w / 2, J.y - 22, 20, '#5a3412');
  }

  /* ---------- фонари и ночь ---------- */
  function lamps(ctx, dark, t) {
    for (const l of World.LAMPS) {
      fillEll(ctx, l.x + 3, l.y + 4, 6, 4, 'rgba(0,0,0,0.2)');
      ctx.fillStyle = '#343a40';
      ctx.fillRect(l.x - 2, l.y - 2, 4, 4);
      fillEll(ctx, l.x, l.y, 5, 5, dark > 0.2 ? '#ffe8a3' : '#adb5bd');
    }
  }
  // затемнение с «дырками» от фонарей; lights — в экранных координатах
  let darkCanvas = null;
  function night(ctx, w, h, dark, tint, lights, t) {
    if (dark <= 0.01 && !tint) return;
    if (!darkCanvas) darkCanvas = document.createElement('canvas');
    if (darkCanvas.width !== w || darkCanvas.height !== h) { darkCanvas.width = w; darkCanvas.height = h; }
    const d = darkCanvas.getContext('2d');
    d.globalCompositeOperation = 'source-over';
    d.clearRect(0, 0, w, h);
    d.fillStyle = `rgba(12,18,52,${dark})`;
    d.fillRect(0, 0, w, h);
    if (tint) { d.fillStyle = tint; d.fillRect(0, 0, w, h); }
    d.globalCompositeOperation = 'destination-out';
    for (const l of lights) {
      const g = d.createRadialGradient(l.x, l.y, 0, l.x, l.y, l.r);
      g.addColorStop(0, 'rgba(0,0,0,1)');
      g.addColorStop(0.5, 'rgba(0,0,0,0.7)');
      g.addColorStop(1, 'rgba(0,0,0,0)');
      d.fillStyle = g;
      d.fillRect(l.x - l.r, l.y - l.r, l.r * 2, l.r * 2);
    }
    ctx.drawImage(darkCanvas, 0, 0);
    if (dark > 0.15) {
      ctx.globalCompositeOperation = 'lighter';
      for (const l of lights) {
        const g = ctx.createRadialGradient(l.x, l.y, 0, l.x, l.y, l.r * 0.6);
        g.addColorStop(0, `rgba(255,190,90,${0.18 * dark})`);
        g.addColorStop(1, 'rgba(255,190,90,0)');
        ctx.fillStyle = g;
        ctx.fillRect(l.x - l.r, l.y - l.r, l.r * 2, l.r * 2);
      }
      ctx.globalCompositeOperation = 'source-over';
    }
  }

  function paddock(ctx) {
    const P = World.PADDOCK;
    ctx.fillStyle = 'rgba(70,120,40,0.18)';
    ctx.fillRect(P.x, P.y, P.w, P.h);
    // поилка и кормушка с сеном
    ctx.fillStyle = '#6b6f75';
    ctx.fillRect(P.x + P.w - 90, P.y + 30, 60, 22);
    ctx.fillStyle = '#7cc3ea';
    ctx.fillRect(P.x + P.w - 86, P.y + 34, 52, 14);
    ctx.fillStyle = '#6b4a2b';
    ctx.fillRect(P.x + 30, P.y + 30, 50, 34);
    ctx.fillStyle = '#d8b85c';
    ctx.fillRect(P.x + 34, P.y + 34, 42, 26);
    fenceRect(ctx, P, { side: 'bottom', a: World.PADDOCK_GATE.x1, b: World.PADDOCK_GATE.x2 }, '#8a5a32', '#5e3b1d');
    label(ctx, '🌿 ЛЕВАДА', P.x + P.w / 2, P.y - 22, 20, '#2f5a1a');
  }

  function wagon(ctx, W, stripe, t) {
    const { x, y, w, h } = W;
    fillEll(ctx, x + w / 2 + 4, y + h / 2 + 6, w / 2 + 12, h / 2 + 8, 'rgba(0,0,0,0.18)');
    // колёса
    ctx.fillStyle = '#3d2a1a';
    for (const wx of [x + 22, x + w - 22]) { ctx.fillRect(wx - 12, y - 8, 24, 8); ctx.fillRect(wx - 12, y + h, 24, 8); }
    // оглобли
    ctx.strokeStyle = '#6b4a2b';
    ctx.lineWidth = 4;
    ctx.beginPath(); ctx.moveTo(x, y + 18); ctx.lineTo(x - 50, y + 22); ctx.moveTo(x, y + h - 18); ctx.lineTo(x - 50, y + h - 22); ctx.stroke();
    // полосатый тент
    const n = 8;
    for (let i = 0; i < n; i++) {
      ctx.fillStyle = i % 2 ? '#ffffff' : stripe;
      ctx.fillRect(x + (w / n) * i, y, w / n + 0.5, h);
    }
    ctx.strokeStyle = 'rgba(0,0,0,0.3)';
    ctx.lineWidth = 2;
    ctx.strokeRect(x, y, w, h);
    ctx.fillStyle = 'rgba(0,0,0,0.12)';
    ctx.fillRect(x, y + h / 2 - 2, w, 4);
    // продавец
    const px = x + w + 22, py = y + h / 2;
    fillEll(ctx, px, py + 3, 10, 8, 'rgba(0,0,0,0.18)');
    fillEll(ctx, px, py, 6, 9, '#4a6fa5');
    fillEll(ctx, px, py, 6.5, 6.5, '#f2c9a5');
    fillEll(ctx, px - 1, py, 7.5, 7.5, '#3a2a1a');
    fillEll(ctx, px - 1, py, 9 + Math.sin(t * 2) * 0.3, 9, 'rgba(160,120,60,0.85)');
    label(ctx, W.name, x + w / 2, y - 22, 15, '#3b2a1a');
  }

  function treeTrunk(ctx, tr) {
    fillEll(ctx, tr.x + 8, tr.y + 10, tr.r * 0.9, tr.r * 0.7, 'rgba(0,0,0,0.2)');
  }
  function treeTop(ctx, tr) {
    const r = World.rng(tr.s);
    const base = tr.kind === 'birch' ? '#7dbb4f' : '#4f8f3a';
    const light = tr.kind === 'birch' ? '#a3d46c' : '#6eae4c';
    for (let i = 0; i < 6; i++) {
      const a = r() * TAU, d = r() * tr.r * 0.45;
      fillEll(ctx, tr.x + Math.cos(a) * d, tr.y + Math.sin(a) * d, tr.r * (0.55 + r() * 0.2), tr.r * (0.55 + r() * 0.2), base);
    }
    fillEll(ctx, tr.x - tr.r * 0.2, tr.y - tr.r * 0.25, tr.r * 0.45, tr.r * 0.4, light);
  }

  /* ================= МИНИКАРТА ================= */
  function minimap(mctx, S, game) {
    const c = mctx.canvas, k = c.width / World.W;
    mctx.fillStyle = '#86b85a';
    mctx.fillRect(0, 0, c.width, c.height);
    const F = World.FIELD;
    mctx.fillStyle = '#9ccb6c';
    mctx.fillRect(F.x * k, F.y * k, F.w * k, F.h * k);
    const rect = (r, col) => { mctx.fillStyle = col; mctx.fillRect(r.x * k, r.y * k, r.w * k, r.h * k); };
    rect(World.STABLE, '#8a5a32');
    rect(World.ARENA, '#dcc394');
    mctx.strokeStyle = '#5e3b1d';
    mctx.lineWidth = 1;
    const P = World.PADDOCK;
    mctx.strokeRect(P.x * k, P.y * k, P.w * k, P.h * k);
    rect(World.SELL, '#d63a3a');
    rect(World.SHOP, '#2e9d4f');
    mctx.fillStyle = '#3f8fc0';
    mctx.beginPath();
    mctx.ellipse(World.POND.x * k, World.POND.y * k, World.POND.rx * k, World.POND.ry * k, 0, 0, TAU);
    mctx.fill();
    for (const w of game.wild()) {
      mctx.fillStyle = Horses.pheno(w).body;
      mctx.beginPath(); mctx.arc(w.x * k, w.y * k, 2.5, 0, TAU); mctx.fill();
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

  return { horse, girl, ground, stable, arena, jumpField, lamps, night, paddock, wagon, treeTrunk, treeTop, minimap, label, fillEll };
})();

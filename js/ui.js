'use strict';
/* Интерфейс: панели, меню, всплывающие сообщения */
const UI = (() => {
  let G = null;
  const $ = id => document.getElementById(id);
  let el = {};
  let view = null;           // текущая открытая панель: функция, которая возвращает {title, html}
  let lastPrompt = null;
  const cache = {};
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const MEDALS = { gold: '🥇', silver: '🥈', bronze: '🥉' };

  function set(key, node, prop, value) {
    if (cache[key] === value) return;
    cache[key] = value;
    node[prop] = value;
  }
  function show(node, on) { node.classList.toggle('hidden', !on); }

  /* ---------- инициализация ---------- */
  function init(game) {
    G = game;
    el = {
      money: $('hud-money'), count: $('hud-count'), clock: $('hud-clock'), gfx: $('btn-gfx'), medals: $('hud-medals'), hint: $('hint'),
      prompt: $('prompt'), lassoBtn: $('btn-lasso'), ride: $('ride'), rideName: $('ride-name'),
      energy: $('ride-energy'), lead: $('lead'), leadName: $('lead-name'), exercise: $('exercise'),
      exTitle: $('ex-title'), exLine: $('ex-line'), exHint: $('ex-hint'), exLetter: $('ex-letter'),
      lift: $('btn-lift'), modal: $('modal'), mTitle: $('modal-title'), mBody: $('modal-body'),
      toasts: $('toasts'), lasso: $('lasso'),
    };
    $('btn-horses').onclick = () => openStable(G.atFarm());
    $('btn-inv').onclick = openInventory;
    el.gfx.onclick = () => G.act.setGfx({ '2d': 'voxel', voxel: 'real', real: '2d' }[G.S.gfx] || '2d');
    $('btn-help').onclick = openHelp;
    $('btn-sound').onclick = e => { e.currentTarget.textContent = Sound.toggle() ? '🔊' : '🔇'; };
    el.prompt.onclick = () => lastPrompt && lastPrompt.fn();
    el.lassoBtn.onclick = () => G.act.lasso();
    document.querySelectorAll('[data-gait]').forEach(b => (b.onclick = () => G.act.setGait(+b.dataset.gait)));
    $('btn-dismount').onclick = () => G.act.dismount();
    el.lift.onclick = () => G.act.liftLegs();
    el.lift.addEventListener('touchstart', e => { e.preventDefault(); G.act.liftLegs(); }, { passive: false });
    $('btn-release').onclick = () => G.act.releaseLed();
    $('btn-ex-cancel').onclick = () => G.act.cancelExercise();
    $('modal-close').onclick = closeModal;
    el.modal.addEventListener('pointerdown', e => { if (e.target === el.modal) closeModal(); });
    el.mBody.addEventListener('click', onModalClick);
    $('lasso-throw').onclick = () => G.resolveLasso();
  }

  /* ---------- HUD ---------- */
  function updateHud(d) {
    set('money', el.money, 'textContent', `🪙 ${d.money}`);
    set('count', el.count, 'textContent', `🐴 ${d.count}/${d.max}`);
    set('clock', el.clock, 'textContent', d.clock);
    set('gfx', el.gfx, 'textContent', { voxel: '🧊 Кубики', real: '🌄 Реализм' }[d.gfx] || '🗺️ 2D');
    const md = ['gold', 'silver', 'bronze'].filter(k => d.stats[k]).map(k => `${MEDALS[k]}${d.stats[k]}`).join(' ');
    set('medals', el.medals, 'textContent', md);
    show(el.medals, !!md);
    set('hint', el.hint, 'textContent', d.hint);
    show(el.hint, !!d.hint);

    lastPrompt = d.prompt;
    show(el.prompt, !!d.prompt);
    if (d.prompt) set('prompt', el.prompt, 'textContent', d.prompt.label + '  [E]');
    show(el.lassoBtn, d.canLasso);

    show(el.ride, !!d.mounted);
    if (d.mounted) {
      set('rideName', el.rideName, 'textContent', `🏇 ${d.mounted.name}`);
      el.energy.style.width = `${Math.round(d.mounted.energy)}%`;
      el.energy.style.background = d.mounted.energy < 25 ? '#e03131' : d.mounted.energy < 50 ? '#f08c00' : '#37b24d';
      document.querySelectorAll('[data-gait]').forEach(b => b.classList.toggle('active', +b.dataset.gait === d.mounted.gait));
    }
    show(el.lead, !!d.led);
    if (d.led) set('leadName', el.leadName, 'textContent', `🪢 ${d.led}`);

    const x = d.exercise;
    show(el.exercise, !!x);
    show(el.lift, !!(x && x.lift));
    if (x && x.lift) set('lift', el.lift, 'textContent', x.liftLabel);
    if (x) {
      set('exTitle', el.exTitle, 'textContent', x.title);
      set('exLine', el.exLine, 'textContent', x.line);
      set('exHint', el.exHint, 'textContent', x.hint);
      el.exHint.classList.toggle('bad', !x.ok);
      set('exLetter', el.exLetter, 'textContent', x.letter || '');
      show(el.exLetter, !!x.letter);
    }
  }

  function toast(msg, kind = '') {
    const t = document.createElement('div');
    t.className = 'toast ' + kind;
    t.textContent = msg;
    el.toasts.appendChild(t);
    while (el.toasts.children.length > 4) el.toasts.firstChild.remove();
    setTimeout(() => t.classList.add('out'), 4200);
    setTimeout(() => t.remove(), 4700);
  }

  /* ---------- модальное окно ---------- */
  function open(fn) {
    view = fn;
    render();
    el.modal.classList.remove('hidden');
    document.body.classList.add('modal-open');
    el.mBody.scrollTop = 0;
  }
  function render() {
    if (!view) return;
    const v = view();
    el.mTitle.textContent = v.title;
    const scroll = el.mBody.scrollTop;
    el.mBody.innerHTML = v.html;
    el.mBody.scrollTop = scroll;
    el.mBody.querySelectorAll('canvas[data-hid]').forEach(c => {
      const id = +c.dataset.hid;
      const h = G.S.horses.find(x => x.id === id) || (G.led() && G.led().id === id ? G.led() : null);
      if (h) portrait(c, h);
    });
  }
  function closeModal() {
    view = null;
    el.modal.classList.add('hidden');
    document.body.classList.remove('modal-open');
  }
  const isModalOpen = () => !!view;

  function portrait(c, h) {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = c.width, hh = c.height;
    c.style.width = w + 'px';
    c.style.height = hh + 'px';
    c.width = w * dpr; c.height = hh * dpr;
    const ctx = c.getContext('2d');
    ctx.scale(dpr, dpr);
    const k = (w * 0.74) / (112 * h.size);
    const copy = Object.assign({}, h, { spd: 0, headTurn: 0.12, phase: 0, _ph: null });
    Draw.horse(ctx, copy, w / 2 - 4 * k, hh / 2, 0, { t: 0.4, scale: k });
  }

  function bar(label, v, color) {
    v = Math.round(v);
    return `<div class="bar"><span>${label}</span><div class="track"><div style="width:${v}%;background:${color}"></div></div><b>${v}</b></div>`;
  }
  function skillBar(h, k) {
    const base = h.base[k], all = Horses.skill(h, k);
    return `<div class="bar"><span>${Horses.SKILLS[k]}</span><div class="track"><div style="width:${base}%;background:#748ffc"></div><div style="width:${all - base}%;background:#ffd43b"></div></div><b>${all}</b></div>`;
  }
  const careColor = v => (v < 25 ? '#e03131' : v < 50 ? '#f08c00' : '#37b24d');
  const sexIcon = h => (h.sex === 'f' ? '<span class="sex f">♀</span>' : '<span class="sex m">♂</span>');

  function statusBadges(h) {
    const b = [];
    if (h.state === 'paddock') b.push('🌿 в леваде');
    if (h.state === 'ridden') b.push('🏇 верхом');
    if (h.preg) b.push(`🍼 ждёт жеребёнка (${Math.ceil(Math.max(0, h.preg.t))} с)`);
    if (h.age < 3) b.push('🍼 малыш');
    if (h.hunger < 25) b.push('😟 голодная');
    if (h.clean < 25) b.push('🟫 грязная');
    return b.map(x => `<span class="badge">${x}</span>`).join('');
  }

  /* ---------- конюшня ---------- */
  function openStable(canAct) {
    open(() => {
      const S = G.S;
      let html = canAct ? '' : '<p class="note">Ты далеко от конюшни — можно только посмотреть. Подойди ближе, чтобы ухаживать за лошадьми.</p>';
      html += '<div class="stalls">';
      for (let i = 0; i < G.MAX_STALLS; i++) {
        const h = G.horseInStall(i);
        if (!h) { html += `<div class="stall empty"><div class="num">№${i + 1}</div><div>свободный денник</div></div>`; continue; }
        const ph = Horses.pheno(h);
        html += `<button class="stall" data-act="horse" data-id="${h.id}" data-can="${canAct ? 1 : 0}">
          <div class="num">№${i + 1}</div>
          <canvas width="150" height="78" data-hid="${h.id}"></canvas>
          <div class="nm">${sexIcon(h)} ${esc(h.name)}</div>
          <div class="sub">${esc(ph.name)}</div>
          <div class="sub">${esc(Genetics.BREEDS[h.breed].name)}, ${Horses.ageText(h)}</div>
          <div class="mini"><i style="width:${h.hunger}%;background:${careColor(h.hunger)}"></i></div>
          <div class="badges">${statusBadges(h)}</div>
        </button>`;
      }
      html += '</div>';
      return { title: `Конюшня — ${S.horses.length} из ${G.MAX_STALLS} денников`, html };
    });
  }

  function openHorse(id, canAct) {
    open(() => {
      const S = G.S, h = G.byId(id);
      if (!h) return { title: 'Лошадь', html: '<p>Этой лошади больше нет на ферме.</p><button class="btn" data-act="stable">← К конюшне</button>' };
      const ph = Horses.pheno(h);
      const B = Genetics.BREEDS[h.breed];
      const dis = canAct ? '' : 'disabled';
      let html = `<button class="btn ghost" data-act="stable" data-can="${canAct ? 1 : 0}">← Все лошади</button>
      <div class="horse-detail">
        <div class="pic"><canvas width="300" height="160" data-hid="${h.id}"></canvas></div>
        <div class="info">
          <h3>${sexIcon(h)} ${esc(h.name)}</h3>
          <div class="rename"><input id="rename-input" maxlength="20" value="${esc(h.name)}"><button class="btn small" data-act="rename" data-id="${h.id}">✏️ Переименовать</button></div>
          <table>
            <tr><td>Порода</td><td>${esc(B.name)}</td></tr>
            <tr><td>Пол, возраст</td><td>${Horses.sexText(h)}, ${Horses.ageText(h)}</td></tr>
            <tr><td>Окрас</td><td><b>${esc(ph.name)}</b></td></tr>
            <tr><td>Отметины</td><td>${Horses.marksText(h)}</td></tr>
            <tr><td>Гены окраса</td><td><code>${Genetics.genotypeText(h.g)}</code></td></tr>
            <tr><td>Нрав</td><td>${h.temper < 0.35 ? 'спокойный 😌' : h.temper < 0.6 ? 'обычный 🙂' : 'горячий 🔥'}</td></tr>
            <tr><td>Денник</td><td>№${h.stall + 1}</td></tr>
            <tr><td>Цена</td><td>${Horses.price(h)} 🪙</td></tr>
          </table>
          <div class="badges">${statusBadges(h)}</div>
        </div>
      </div>
      <div class="cols">
        <div><h4>Уход</h4>
          ${bar('Сытость', h.hunger, careColor(h.hunger))}
          ${bar('Энергия', h.energy, careColor(h.energy))}
          ${bar('Настроение', h.mood, careColor(h.mood))}
          ${bar('Чистота', h.clean, careColor(h.clean))}
        </div>
        <div><h4>Навыки <small>(синий — от природы, жёлтый — тренировки)</small></h4>
          ${Object.keys(Horses.SKILLS).map(k => skillBar(h, k)).join('')}
        </div>
      </div>
      <h4>Покормить</h4><div class="row">`;
      for (const [k, f] of Object.entries(G.FOOD)) {
        html += `<button class="btn food" data-act="feed" data-id="${h.id}" data-arg="${k}" ${dis || (S.inv[k] ? '' : 'disabled')}>${f.icon} ${f.name} <small>×${S.inv[k] || 0}</small></button>`;
      }
      html += `</div><h4>Действия</h4><div class="row">
        <button class="btn green" data-act="mount" data-id="${h.id}" ${dis || (h.state === 'ridden' ? 'disabled' : '')}>🏇 Сесть верхом</button>
        <button class="btn" data-act="paddock" data-id="${h.id}" ${dis || (h.state === 'ridden' ? 'disabled' : '')}>${h.state === 'paddock' ? '🏠 Вернуть в денник' : '🌿 Выпустить в леваду'}</button>
        <button class="btn" data-act="brush" data-id="${h.id}" ${dis}>🪮 Почистить</button>
        <button class="btn pink" data-act="breedmenu" data-id="${h.id}" ${dis || (Horses.isAdult(h) && !(h.sex === 'f' && h.preg) ? '' : 'disabled')}>💕 Скрестить</button>
      </div>`;
      if (!S.tack.saddle || !S.tack.bridle) html += '<p class="note">Чтобы ездить верхом, нужны седло и уздечка из повозки «Корм и амуниция».</p>';
      if (!Horses.isAdult(h)) html += '<p class="note">Ездить верхом и скрещивать можно с 3 лет. Жеребята растут быстро: 1 год = 2 минуты.</p>';
      return { title: `${h.name}`, html };
    });
  }

  function openBreed(id, partnerId) {
    open(() => {
      const h = G.byId(id);
      if (!h) return { title: 'Скрещивание', html: '' };
      const mare = h.sex === 'f' ? h : null;
      const partners = G.S.horses.filter(x => x.sex !== h.sex && Horses.isAdult(x) && !(x.sex === 'f' && x.preg));
      let html = `<button class="btn ghost" data-act="horse" data-id="${h.id}" data-can="1">← Назад</button>
        <p>Выбери ${mare ? 'жеребца' : 'кобылу'} в пару (${mare ? 'кобыла' : 'жеребец'} — ${esc(h.name)}). Окрас жеребёнка зависит от генов обоих родителей, а навыки — средние от родителей плюс немного удачи.</p>`;
      if (!partners.length) html += `<p class="note">Нет подходящих ${mare ? 'жеребцов' : 'кобыл'}: нужна взрослая лошадь (от 3 лет) другого пола. Поймай её в поле!</p>`;
      html += '<div class="stalls">';
      for (const p of partners) {
        const ph = Horses.pheno(p);
        html += `<button class="stall ${p.id === partnerId ? 'sel' : ''}" data-act="breedpick" data-id="${h.id}" data-arg="${p.id}">
          <canvas width="150" height="78" data-hid="${p.id}"></canvas>
          <div class="nm">${sexIcon(p)} ${esc(p.name)}</div>
          <div class="sub">${esc(ph.name)}</div>
          <div class="sub">${esc(Genetics.BREEDS[p.breed].name)}</div></button>`;
      }
      html += '</div>';
      const p = partnerId != null ? G.byId(partnerId) : null;
      if (p) {
        const m = mare || p, f = mare ? p : h;
        const pred = Genetics.predict(m.g, f.g);
        const breed = m.breed === f.breed ? Genetics.BREEDS[m.breed].name : 'Помесь';
        html += `<div class="predict"><h4>Каким может быть жеребёнок?</h4>
          <p>Мама: <b>${esc(m.name)}</b> (${esc(Horses.pheno(m).name)}) · папа: <b>${esc(f.name)}</b> (${esc(Horses.pheno(f).name)})</p>
          <p>Порода: <b>${esc(breed)}</b></p>
          ${pred.map(x => `<div class="bar"><span>${esc(x.name)}</span><div class="track"><div style="width:${x.pct}%;background:#f783ac"></div></div><b>${x.pct}%</b></div>`).join('')}
          <p class="small">Ветеринар: 30 🪙. Жеребёнок родится через 2,5 минуты, если будет свободный денник.</p>
          <button class="btn pink big" data-act="breed" data-id="${m.id}" data-arg="${f.id}">💕 Скрестить</button></div>`;
      }
      return { title: `Скрещивание: ${h.name}`, html };
    });
  }

  /* ---------- повозка: корм и амуниция ---------- */
  function openShop() {
    open(() => {
      const S = G.S;
      let html = `<p>У тебя: <b>${S.money} 🪙</b></p><h4>Корм и лакомства</h4><div class="shop">`;
      for (const [k, f] of Object.entries(G.FOOD)) {
        html += `<div class="item"><div class="ic">${f.icon}</div><div class="t"><b>${f.name}</b><small>${f.price} 🪙 · есть ${S.inv[k] || 0}${f.bait ? ' · приманка для лассо' : ''}</small></div>
          <button class="btn small" data-act="buyfood" data-arg="${k}" data-n="1">+1</button>
          <button class="btn small" data-act="buyfood" data-arg="${k}" data-n="5">+5</button></div>`;
      }
      html += '</div><h4>Амуниция</h4><div class="shop">';
      for (const [k, t] of Object.entries(G.TACK)) {
        const own = S.tack[k];
        const sw = own && t.colors
          ? `<div class="swatches">${G.COLORS.map(c => `<button class="sw ${own === c ? 'on' : ''}" style="background:${c}" data-act="color" data-arg="${k}" data-c="${c}"></button>`).join('')}</div>` : '';
        html += `<div class="item"><div class="ic">${t.icon}</div><div class="t"><b>${t.name}</b><small>${t.desc}</small>${sw}</div>`;
        if (!own) html += `<button class="btn small green" data-act="buytack" data-arg="${k}">${t.price} 🪙</button>`;
        else html += '<span class="own">есть ✔</span>';
        html += '</div>';
      }
      html += '</div>';
      return { title: '🛒 Повозка «Корм и амуниция»', html };
    });
  }

  /* ---------- повозка: продажа ---------- */
  function openSell() {
    open(() => {
      const S = G.S, near = G.nearSell();
      let html = near ? '<p>Торговец купит твоих лошадей. Цена зависит от навыков, редкости окраса, возраста и ухода.</p>'
        : '<p class="note">Подойди к повозке «Продажа лошадей», чтобы продать.</p>';
      const list = [];
      if (G.led()) list.push({ h: G.led(), led: true });
      for (const h of S.horses) if (h.state !== 'ridden') list.push({ h });
      if (!list.length) html += '<p>Пока нечего продавать.</p>';
      html += '<div class="stalls">';
      for (const { h, led } of list) {
        const ph = Horses.pheno(h);
        const price = led ? Math.round(Horses.price(h) * 0.85 / 5) * 5 : Horses.price(h);
        html += `<div class="stall"><canvas width="150" height="78" data-hid="${h.id}"></canvas>
          <div class="nm">${sexIcon(h)} ${esc(h.name)} ${led ? '<small>(пойманная)</small>' : ''}</div>
          <div class="sub">${esc(ph.name)}</div><div class="sub">${esc(Genetics.BREEDS[h.breed].name)}, ${Horses.ageText(h)}</div>
          <button class="btn small green" data-act="sell" data-id="${h.id}" data-arg="${led ? 'led' : ''}" ${near ? '' : 'disabled'}>Продать за ${price} 🪙</button></div>`;
      }
      html += '</div>';
      return { title: '💰 Повозка «Продажа лошадей»', html };
    });
  }

  /* ---------- рюкзак ---------- */
  function openInventory() {
    open(() => {
      const S = G.S, st = S.stats;
      const shirts = ['#e05a8a', '#4dabf7', '#69db7c', '#ffa94d', '#9775fa', '#ffffff', '#343a40'];
      let html = `<p>Монеты: <b>${S.money} 🪙</b></p><h4>Корм</h4><div class="row">`;
      for (const [k, f] of Object.entries(G.FOOD)) html += `<span class="chip">${f.icon} ${f.name}: ${S.inv[k] || 0}</span>`;
      html += '</div><h4>Амуниция</h4><div class="row">';
      for (const [k, t] of Object.entries(G.TACK)) if (S.tack[k]) html += `<span class="chip">${t.icon} ${t.name}</span>`;
      html += `<span class="chip">🪢 Простое лассо</span></div>
        <h4>Моя кофта</h4><div class="swatches">${shirts.map(c => `<button class="sw ${S.player.shirt === c ? 'on' : ''}" style="background:${c}" data-act="shirt" data-c="${c}"></button>`).join('')}</div>
        <h4>Достижения</h4><div class="row">
        <span class="chip">🤠 Поймано: ${st.caught}</span><span class="chip">🍼 Жеребят: ${st.foals}</span><span class="chip">💰 Продано: ${st.sold}</span>
        <span class="chip">🥇 ${st.gold}</span><span class="chip">🥈 ${st.silver}</span><span class="chip">🥉 ${st.bronze}</span></div>`;
      return { title: '🎒 Рюкзак', html };
    });
  }

  /* ---------- тренировка ---------- */
  function openTraining() {
    open(() => {
      const m = G.mounted();
      if (!m) return { title: 'Тренировка', html: '<p>Сначала сядь на лошадь.</p>' };
      const html = `<p>Тренируешь: <b>${esc(m.name)}</b> · энергия ${Math.round(m.energy)}%</p>
        ${skillBar(m, 'jump')}${skillBar(m, 'dressage')}
        <div class="train">
          <button class="card" data-act="train" data-arg="cav"><b>🚧 Кавалетти</b><span>5 жердей на земле. Едь по ним <b>рысью</b> слева направо и прямо перед каждой жердью жми <b>«Ноги выше!»</b> (Пробел). Развивает прыжки.</span></button>
          <button class="card" data-act="train" data-arg="easy"><b>🎠 Выездка: ${G.TESTS.easy.name}</b><span>Езди от буквы к букве нужным аллюром: шаг и рысь. Остановка в X — приветствие судьям.</span></button>
          <button class="card" data-act="train" data-arg="canter"><b>🏆 Выездка: ${G.TESTS.canter.name}</b><span>Шаг, рысь и галоп. Сложнее, но и награда больше!</span></button>
        </div>`;
      return { title: '🏆 Тренировка в манеже', html };
    });
  }

  function openJumping() {
    open(() => {
      const m = G.mounted();
      if (!m) return { title: 'Конкур', html: '<p>Сначала сядь на лошадь.</p>' };
      const comfy = G.comfortHeight(m);
      const html = `<p>Конкур — это прыжки через препятствия по порядку номеров. Едь <b>галопом</b>, проходи препятствия в сторону стрелки
        (красный флажок справа, белый — слева) и жми <b>«Прыжок!»</b> (Пробел) прямо перед жердями.</p>
        <p>За повал жерди — 4 штрафных очка, за отказ — тоже 4 (после трёх отказов — исключение). Норма времени — ${G.JUMP_NORM} секунд:
        за каждые начатые 4 секунды сверху — 1 штрафное очко.</p>
        <p><b>${esc(m.name)}</b>: прыжки ${Horses.skill(m, 'jump')}, энергия ${Math.round(m.energy)}%. Удобная высота — около <b>${comfy} см</b>.</p>
        <div class="train">${G.JUMP_HEIGHTS.map(h => `<button class="card" data-act="jump" data-arg="${h}"><b>${h} см</b>
          <span>${h <= comfy ? 'по силам ✔' : h - comfy <= 15 ? 'сложно, но можно' : 'очень высоко!'}${h === 60 ? ' · можно рысью' : ''}</span></button>`).join('')}</div>`;
      return { title: '🏆 Конкур', html };
    });
  }

  function jumpResult(r) {
    open(() => ({
      title: `Конкур ${r.height} см: результат`,
      html: `<div class="result"><div class="medal">${r.medal ? MEDALS[r.medal] : r.eliminated ? '🚫' : '🙂'}</div>
        ${r.eliminated ? '<p class="pct">Исключение</p><p>Три отказа — так бывает. Подъезжай к препятствию галопом и не останавливайся!</p>'
        : `<p class="pct">${r.faults} штр. оч.</p>
        <p>${r.faults === 0 ? 'Чистый маршрут! Браво!' : r.faults <= 4 ? 'Почти идеально!' : 'Хороший опыт — тренируйся ещё!'}</p>`}
        <table class="marks">
          <tr><td>Чисто пройдено</td><td><b>${r.clean} из ${r.total}</b></td></tr>
          <tr><td>Время</td><td><b>${r.t.toFixed(1)} с</b> (норма ${r.norm} с${r.over ? `, +${r.over} за время` : ''})</td></tr>
        </table>
        <p>Награда: <b>${r.money} 🪙</b> · Прыжки: ${r.skill}</p>
        <button class="btn green big" data-act="close">Отлично!</button></div>`,
    }));
  }

  function result(title, clean, total, money, medal, extra) {
    open(() => ({
      title: `${title}: результат`,
      html: `<div class="result"><div class="medal">${medal ? MEDALS[medal] : '🙂'}</div>
        <p>Чисто пройдено жердей: <b>${clean} из ${total}</b></p>
        <p>${clean === total ? 'Великолепно! Ни одной сбитой жерди!' : clean >= 3 ? 'Хорошо! Попробуй пройти все жерди чисто.' : 'Не сдавайся — держи рысь и жми вовремя.'}</p>
        <p>Награда: <b>${money} 🪙</b> · ${extra}</p>
        <button class="btn green big" data-act="close">Отлично!</button></div>`,
    }));
  }

  function dressageResult(name, marks, pct, money, medal, skill) {
    open(() => ({
      title: `Выездка: ${name}`,
      html: `<div class="result"><div class="medal">${medal ? MEDALS[medal] : '🙂'}</div>
        <p class="pct">${pct.toFixed(1)}%</p>
        <p>${pct >= 70 ? 'Судьи в восторге!' : pct >= 60 ? 'Очень хорошая езда!' : pct >= 50 ? 'Неплохо! Следи за аллюрами.' : 'Тренируйся: держи нужный аллюр на каждом отрезке.'}</p>
        <table class="marks">${marks.map(m => `<tr><td>${esc(m.text)}</td><td><b>${m.mark}</b></td></tr>`).join('')}</table>
        <p>Награда: <b>${money} 🪙</b> · Выездка: ${skill}</p>
        <button class="btn green big" data-act="close">Отлично!</button></div>`,
    }));
  }

  /* ---------- помощь ---------- */
  function openHelp() {
    open(() => ({
      title: '🐴 Лошадиная ферма — как играть',
      html: `<div class="help">
        <p>Ты — хозяйка лошадиной фермы! В большом поле справа бегает табун диких лошадей. Лови их, ухаживай, тренируй и разводи жеребят настоящих окрасов.</p>
        <h4>Управление</h4>
        <ul>
          <li><b>Стрелки / WASD</b> или <b>нажми на землю</b> — идти (можно держать палец/мышь)</li>
          <li><b>E</b> — открыть то, рядом с чем стоишь (конюшня, повозки, тренировка)</li>
          <li><b>Пробел</b> или <b>нажми на лошадь</b> — бросить лассо; на кавалетти — «ноги выше!»</li>
          <li><b>1 / 2 / 3</b> — шаг / рысь / галоп, <b>X</b> — слезть с лошади</li>
        </ul>
        <h4>Что можно делать</h4>
        <ul>
          <li>🤠 <b>Ловить лошадей.</b> Подойди к лошади и брось лассо — останови стрелку в зелёной зоне. Спокойных лошадей ловить легче; горячие убегают, их удобнее догонять верхом. Морковка или яблоко в рюкзаке помогают. Вместо пойманной в поле прибежит новая!</li>
          <li>🏠 <b>Конюшня на 20 денников.</b> Приведи пойманную лошадь в конюшню. Корми, чисти, выпускай в леваду.</li>
          <li>🏇 <b>Ездить верхом</b> — нужны седло и уздечка.</li>
          <li>🚧 <b>Кавалетти</b> и 🎠 <b>выездка</b> в манеже — за них дают монеты и медали, а лошадь становится лучше.</li>
          <li>💕 <b>Скрещивать</b> кобылу и жеребца. Окрас жеребёнка считается по настоящим генам: рыжая, гнедая, вороная, соловая, буланая, изабелловая, саврасая, мышастая, серая в яблоках, пегая, чубарая, чалая, серебристая…</li>
          <li>💰 <b>Повозки:</b> одна покупает лошадей, в другой продаются корм и амуниция.</li>
          <li>🏆 <b>Конкур</b> на конкурном поле: 8 препятствий, высота от 60 до 120 см.</li>
          <li>🌙 <b>День и ночь</b> сменяют друг друга (сутки — 8 минут). Ночью табун спит, и подкрасться к лошадям легче.</li>
        </ul>
        <h4>Графика</h4>
        <div class="gfx-pick">
          <button class="card ${G.S.gfx !== 'voxel' ? 'on' : ''}" data-act="gfx" data-arg="2d"><b>🗺️ Вид сверху (2D)</b><span>Рисованная карта. Работает везде, даже без интернета.</span></button>
          <button class="card ${G.S.gfx === 'voxel' ? 'on' : ''}" data-act="gfx" data-arg="voxel"><b>🧊 Кубики (3D)</b><span>Объёмный мир из вокселей с тенями и фонарями.</span></button>
          <button class="card ${G.S.gfx === 'real' ? 'on' : ''}" data-act="gfx" data-arg="real"><b>🌄 Реализм (3D)</b><span>Лошади настоящих пропорций с аллюрами, солнце по часам, трава на ветру, вода. Нужен мощный компьютер или планшет.</span></button>
        </div>
        <p>Переключать графику можно в любой момент кнопкой вверху. В 3D колесо мыши приближает и отдаляет камеру.</p>
        <p>Игра сохраняется сама.</p>
        <button class="btn green big" data-act="close">Играть!</button>
        <button class="btn ghost small" data-act="reset">Начать заново</button>
      </div>`,
    }));
  }

  /* ---------- лассо ---------- */
  function showLasso(l) {
    const w = l.w, ph = Horses.pheno(w);
    $('lasso-who').textContent = `${w.name} — ${Genetics.BREEDS[w.breed].name.toLowerCase()}, ${ph.name}, ${Horses.sexText(w)}`;
    $('lasso-temper').textContent = w.temper < 0.35 ? 'Нрав: спокойная 😌' : w.temper < 0.6 ? 'Нрав: обычная 🙂' : 'Нрав: горячая 🔥';
    $('lasso-bait').textContent = l.bait ? (l.bait === 'carrot' ? '🥕 Морковка помогает!' : '🍎 Яблоко помогает!') : '';
    const z = $('lasso-zone');
    z.style.left = `${(l.center - l.zone / 2) * 100}%`;
    z.style.width = `${l.zone * 100}%`;
    el.lasso.classList.remove('hidden');
    updateLasso(l);
  }
  function updateLasso(l) { $('lasso-needle').style.left = `${l.pos * 100}%`; }
  function hideLasso() { el.lasso.classList.add('hidden'); }
  const isLassoOpen = () => !el.lasso.classList.contains('hidden');

  /* ---------- клики внутри окна ---------- */
  let sellArm = null, resetArm = false;
  function onModalClick(e) {
    const b = e.target.closest('[data-act]');
    if (!b || b.disabled) return;
    const a = b.dataset.act, id = b.dataset.id != null ? +b.dataset.id : null, arg = b.dataset.arg;
    const h = id != null ? G.byId(id) : null;
    const can = b.dataset.can === '1' || G.atFarm();
    switch (a) {
      case 'close': closeModal(); break;
      case 'stable': openStable(G.atFarm()); break;
      case 'horse': openHorse(id, can); break;
      case 'feed': G.act.feed(h, arg); render(); break;
      case 'brush': G.act.brush(h); render(); break;
      case 'mount': G.act.mount(h); if (view) render(); break;
      case 'paddock': G.act.paddock(h); render(); break;
      case 'rename': G.act.rename(h, $('rename-input').value); render(); break;
      case 'breedmenu': openBreed(id, null); break;
      case 'breedpick': openBreed(id, +arg); break;
      case 'breed': G.act.breed(h, G.byId(+arg)); openHorse(id, true); break;
      case 'buyfood': G.act.buyFood(arg, +b.dataset.n); render(); break;
      case 'buytack': G.act.buyTack(arg); render(); break;
      case 'color': G.act.setColor(arg, b.dataset.c); render(); break;
      case 'shirt': G.act.setShirt(b.dataset.c); render(); break;
      case 'sell': {
        const target = arg === 'led' ? G.led() : h;
        if (!target) break;
        if (sellArm !== target.id) { sellArm = target.id; b.textContent = 'Точно продать? Нажми ещё раз'; b.classList.add('warn'); break; }
        sellArm = null;
        G.act.sell(target);
        render();
        break;
      }
      case 'train': G.act.startExercise(arg); break;
      case 'jump': G.act.startJumping(+arg); break;
      case 'gfx': G.act.setGfx(arg); render(); break;
      case 'reset':
        if (!resetArm) { resetArm = true; b.textContent = 'Точно? Всё сотрётся! Нажми ещё раз'; break; }
        resetArm = false;
        G.act.reset();
        break;
    }
    G.save();
  }

  return {
    init, updateHud, toast, closeModal, isModalOpen, openStable, openShop, openSell, openInventory,
    openHelp, openTraining, openJumping, jumpResult, result, dressageResult, showLasso, updateLasso, hideLasso, isLassoOpen,
  };
})();

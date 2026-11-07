'use strict';
/*
 * Персонажи (NPC), разговоры и задания.
 * Прогресс задания = насколько вырос счётчик в S.stats с момента, когда его взяли,
 * или флаг в S.flags (побывать где-то, открыть сундук).
 */
const Quests = (() => {
  let G = null;
  const pick = a => a[Math.floor(Math.random() * a.length)];

  // look — как выглядит персонаж в 3D
  const NPCS = [
    {
      id: 'galya', name: 'Бабушка Галя', x: World.OX + 1520, y: World.OY + 2740, role: 'огородница',
      look: { shirt: '#c2255c', pants: '#5c3d2e', hair: '#d0d0d0', hat: 'scarf', hatColor: '#f08c00' },
      hello: ['Здравствуй, внученька! Огород — это радость.', 'Морковка для лошадки — лучшее угощение!', 'Дождик польёт грядки сам, а в сухую погоду поливай.'],
      tips: ['Построй грядку через кнопку 🔨, купи семена в повозке и посади их.', 'Колодец рядом с грядками поливает их сам.'],
    },
    {
      id: 'misha', name: 'Тренер Дядя Миша', x: World.OX + 1000, y: World.OY + 330, role: 'тренер',
      look: { shirt: '#1c7ed6', pants: '#e9e0cc', hair: '#5a3d2b', hat: 'cap', hatColor: '#212529', beard: true },
      hello: ['Пятки вниз, спина прямая!', 'Хорошая всадница сначала заботится о лошади.', 'Тренируйся каждый день — и будет результат.'],
      tips: ['В манеже — выездка и кавалетти, ниже — конкурное поле.', 'Скачки начинаются у клетчатого столба у входа в поле.'],
    },
    {
      id: 'petr', name: 'Кузнец Пётр', x: World.OX + 2250, y: World.OY + 2830, role: 'кузнец',
      look: { shirt: '#495057', pants: '#343a40', hair: '#2b2b2b', hat: 'none', apron: '#6b4423', beard: true },
      hello: ['Подковать лошадку? Это я мигом!', 'В земле много старых подков — я их собираю.', 'Металлоискатель пищит всё чаще, когда клад близко.'],
      tips: ['Металлоискатель продаётся в повозке «Корм и амуниция». Включай его кнопкой 📡 или клавишей M.', 'Когда сигнал на максимуме — копай!'],
    },
    {
      id: 'vanya', name: 'Лесник Ваня', x: World.OX + 1600, y: World.OY + 3560, role: 'лесник',
      look: { shirt: '#2b8a3e', pants: '#5c4033', hair: '#a0522d', hat: 'hat', hatColor: '#5c7a3a' },
      hello: ['В лесу тихо... слышишь, как шуршат зайчики?', 'Грибы собирай пешком — с лошади не дотянешься.', 'Мухоморы не трогай, они ядовитые!'],
      tips: ['За лесом на востоке есть Грибное королевство. Говорят, там живут волшебные лошадки!'],
    },
    {
      id: 'lira', name: 'Фея Лира', x: World.OX + 6750, y: World.OY + 3250, role: 'фея', fairy: true,
      look: { shirt: '#e599f7', pants: '#d0bfff', hair: '#ffd43b', hat: 'crown', hatColor: '#fff3bf' },
      hello: ['Добро пожаловать в Грибное королевство! ✨', 'Мои лошадки умеют летать, а у кого-то грива горит огнём!', 'Пегасы пугливые — подкрадывайся тихо.'],
      tips: ['На пегасе можно взлететь: кнопка 🪽 или клавиша V.', 'Волшебные черты передаются жеребятам.', 'Волшебное семечко вырастит цветок с волшебной пыльцой.'],
    },
    {
      id: 'graf', name: 'Призрак графа Ветрова', x: World.OX + 7000, y: World.OY + 900, role: 'привидение', ghost: true,
      look: { shirt: '#dbe4ff', pants: '#dbe4ff', hair: '#ffffff', hat: 'tophat', hatColor: '#c5d0f5' },
      hello: ['Уууу... Не бойся, я добрый призрак.', 'Сто лет я ищу свой сундук... Он где-то в глубине пещеры.', 'Мои лошадки-скелеты гуляют здесь. Они совсем не злые!'],
      tips: ['Пещера идёт змейкой: сначала на север, потом на юг, потом снова на север.', 'Привидения пугают, но ничего плохого не делают.'],
    },
    {
      id: 'lola', name: 'Стилистка Лола', x: World.OX + 2850, y: World.OY + 2800, role: 'стилист',
      look: { shirt: '#f783ac', pants: '#212529', hair: '#9775fa', hat: 'none' },
      hello: ['Какая грива! Давай сделаем ей причёску?', 'Косички, бантики, ирокез — что пожелаешь!', 'Радужная грива — самая модная в этом сезоне!'],
      tips: ['Причёску можно поменять в конюшне: открой лошадь и нажми «💇 Грива».', 'Краски для гривы есть у меня и в повозке.'],
      shop: true,
    },
    {
      id: 'olya', name: 'Рыбачка Оля', x: World.OX + 4250, y: World.OY + 1150, role: 'рыбачка',
      look: { shirt: '#ffa94d', pants: '#1864ab', hair: '#e8590c', hat: 'hat', hatColor: '#fab005' },
      hello: ['Тише... рыба клюёт!', 'Большое озеро — самое красивое место на свете.', 'За озером горы, а в горах — пещера.'],
      tips: ['Вход в пещеру — с западной стороны гор, по дороге от озера.'],
    },
    {
      id: 'marina', name: 'Капитан Марина', x: World.PIER.x - 130, y: World.PIER.y + 100, role: 'капитан лодки',
      look: { shirt: '#ffffff', pants: '#1864ab', hair: '#f08c00', hat: 'cap', hatColor: '#1c3d6e' },
      hello: ['Свистать всех наверх! Куда поплывём?', 'На островах живут лошади с самыми удивительными крыльями!', 'Каждые пять минут на островах появляются новые дикие лошадки.'],
      tips: ['Лодка у причала: подойди и нажми «⛵ Лодка».', 'На каждом острове есть своя конюшня — можно оставить там лошадь.', 'Драконьи лошади очень горячие — лови их верхом.'],
    },
    {
      id: 'zara', name: 'Караванщица Зара', x: World.OX + 1850, y: World.OY + 7250, role: 'караванщица',
      look: { shirt: '#f4a261', pants: '#e9c46a', hair: '#2b2b2b', hat: 'scarf', hatColor: '#e76f51' },
      hello: ['В пустыне днём жарко, а ночью звёзды ярче всего!', 'Ахалтекинцы — потомки древних коней пустыни. Их шерсть блестит золотом.', 'У оазиса растут пальмы — там можно передохнуть.'],
      tips: ['Оазис — в самом сердце пустыни, иди по дороге на юг от леса.', 'Арабские лошади очень выносливые.'],
    },
    {
      id: 'aita', name: 'Северянка Айта', x: World.OX + 7400, y: World.OY + 6950, role: 'жительница тундры',
      look: { shirt: '#4361ee', pants: '#ffffff', hair: '#1b1b1b', hat: 'hat', hatColor: '#e63946' },
      hello: ['Брр! В тундре всегда снег, но якутские лошадки не мёрзнут.', 'У якутских лошадей густая шерсть и длинная грива — настоящие шубки!', 'Ледяное озеро замёрзло, по льду ходить нельзя.'],
      tips: ['Скалы со снегом высокие — обходи их.', 'Ледяные лошадки иногда забредают сюда из Грибного королевства.'],
    },
  ];

  // goal: { stat, n } — счётчик вырос на n; { flag } — флаг выставлен; { item, n } — отдать вещи
  const QUESTS = [
    { id: 'm1', npc: 'misha', title: 'Первая лошадь', text: 'Поймай в поле лошадь и приведи её в конюшню.', goal: { stat: 'caught', n: 1 }, reward: { money: 40, carrot: 5 } },
    { id: 'm2', npc: 'misha', title: 'Выездка', text: 'Проедь тест по выездке на 60% или больше.', goal: { stat: 'dres60', n: 1 }, reward: { money: 60 } },
    { id: 'm3', npc: 'misha', title: 'Чистые жерди', text: 'Пройди кавалетти без единой ошибки.', goal: { stat: 'cavClean', n: 1 }, reward: { money: 60, oats: 5 } },
    { id: 'm4', npc: 'misha', title: 'Чистый конкур', text: 'Пройди маршрут конкура 80 см или выше без штрафных очков.', goal: { stat: 'jump80', n: 1 }, reward: { money: 100 } },
    { id: 'm5', npc: 'misha', title: 'Чемпионка', text: 'Выиграй скачки.', goal: { stat: 'wins', n: 1 }, reward: { money: 150, dye_gold: 1 } },

    { id: 'g1', npc: 'galya', title: 'Первая грядка', text: 'Построй грядку (кнопка 🔨 «Стройка»).', goal: { stat: 'built_bed', n: 1 }, reward: { money: 20, seed_carrot: 4 } },
    { id: 'g2', npc: 'galya', title: 'Морковный урожай', text: 'Посади морковь и собери урожай два раза.', goal: { stat: 'harvest_carrot', n: 2 }, reward: { money: 50, seed_pumpkin: 2 } },
    { id: 'g3', npc: 'galya', title: 'Большой огород', text: 'Построй ещё три грядки.', goal: { stat: 'built_bed', n: 3 }, reward: { money: 60, seed_sunflower: 3 } },
    { id: 'g4', npc: 'galya', title: 'Тыква к празднику', text: 'Вырасти и собери тыкву.', goal: { stat: 'harvest_pumpkin', n: 1 }, reward: { money: 80, seed_magic: 1 } },

    { id: 'p1', npc: 'petr', title: 'Первый клад', text: 'Найди клад металлоискателем.', goal: { stat: 'treasures', n: 1 }, reward: { money: 40 } },
    { id: 'p2', npc: 'petr', title: 'Старые подковы', text: 'Принеси мне 2 старые подковы.', goal: { item: 'oldShoe', n: 2 }, reward: { money: 90, dye_blue: 1 } },
    { id: 'p3', npc: 'petr', title: 'Кладоискательница', text: 'Найди ещё 5 кладов.', goal: { stat: 'treasures', n: 5 }, reward: { money: 150 } },
    { id: 'p4', npc: 'petr', title: 'Золотая подкова', text: 'Принеси золотую подкову — их находят в земле или в сундуке.', goal: { item: 'goldShoe', n: 1 }, reward: { money: 300 } },

    { id: 'v1', npc: 'vanya', title: 'Прогулка по лесу', text: 'Зайди в лес к югу от деревни.', goal: { flag: 'visit_forest' }, reward: { money: 20 } },
    { id: 'v2', npc: 'vanya', title: 'Грибная корзинка', text: 'Собери 8 грибов (пешком, мухоморы не бери!).', goal: { stat: 'mushrooms', n: 8 }, reward: { money: 50, apple: 4 } },
    { id: 'v3', npc: 'vanya', title: 'Тайная тропа', text: 'Найди Грибное королевство на востоке за лесом.', goal: { flag: 'visit_mushroom' }, reward: { money: 60 } },
    { id: 'v4', npc: 'vanya', title: 'Друзья леса', text: 'Поймай 3 зайчиков.', goal: { stat: 'bunnies', n: 3 }, reward: { money: 60, sugar: 5 } },

    { id: 'f1', npc: 'lira', title: 'Волшебная лошадка', text: 'Поймай волшебную лошадку: пегаса, единорога, огненную или ледяную.', goal: { stat: 'magicCaught', n: 1 }, reward: { money: 100, dye_rainbow: 1 } },
    { id: 'f2', npc: 'lira', title: 'Небесная прогулка', text: 'Пролети на пегасе 30 секунд.', goal: { stat: 'flyTime', n: 30 }, reward: { money: 120, seed_magic: 2 } },
    { id: 'f3', npc: 'lira', title: 'Волшебный жеребёнок', text: 'Вырасти жеребёнка с волшебными чертами.', goal: { stat: 'magicFoals', n: 1 }, reward: { money: 200, dye_gold: 1 } },
    { id: 'f4', npc: 'lira', title: 'Пыльца для фей', text: 'Принеси 2 щепотки волшебной пыльцы.', goal: { item: 'pollen', n: 2 }, reward: { money: 150, dye_rainbow: 1 } },

    { id: 'c1', npc: 'graf', title: 'Сундук графа', text: 'Найди мой сундук в самой глубине пещеры.', goal: { flag: 'chest_opened' }, reward: { money: 100 } },
    { id: 'c2', npc: 'graf', title: 'Костяная лошадка', text: 'Поймай лошадь-скелет.', goal: { stat: 'skeletonCaught', n: 1 }, reward: { money: 150 } },

    { id: 'l1', npc: 'lola', title: 'Новая причёска', text: 'Сделай лошади новую причёску (в конюшне — «💇 Грива»).', goal: { stat: 'maneStyled', n: 1 }, reward: { money: 30, dye_pink: 1 } },
    { id: 'l2', npc: 'lola', title: 'Яркие краски', text: 'Покрась гриву лошади краской.', goal: { stat: 'maneDyed', n: 1 }, reward: { money: 50, dye_purple: 1 } },

    { id: 'o1', npc: 'olya', title: 'Большое озеро', text: 'Объедь Большое озеро: побывай у его восточного берега.', goal: { flag: 'visit_lake_east' }, reward: { money: 40 } },
    { id: 's1', npc: 'marina', title: 'Морское путешествие', text: 'Сплавай на лодке на любой остров.', goal: { islands: 1 }, reward: { money: 50 } },
    { id: 's2', npc: 'marina', title: 'Все три острова', text: 'Побывай на всех трёх островах.', goal: { islands: 3 }, reward: { money: 120, dye_blue: 1 } },
    { id: 's3', npc: 'marina', title: 'Лошадь-бабочка', text: 'Поймай лошадь с крыльями бабочки на Острове бабочек.', goal: { stat: 'wing_butterfly', n: 1 }, reward: { money: 150, dye_pink: 1 } },
    { id: 's4', npc: 'marina', title: 'Драконья лошадь', text: 'Поймай драконью лошадь на Драконьем острове.', goal: { stat: 'wing_dragon', n: 1 }, reward: { money: 200, dye_gold: 1 } },
    { id: 's5', npc: 'marina', title: 'Стрекоза и пчёлка', text: 'Поймай лошадь-стрекозу и лошадь-пчёлку.', goal: { stat: 'wingSmall', n: 2 }, reward: { money: 180, dye_mint: 1 } },
    { id: 's6', npc: 'marina', title: 'Крылья ворона', text: 'Поймай лошадь с крыльями ворона.', goal: { stat: 'wing_raven', n: 1 }, reward: { money: 160 } },

    { id: 'z1', npc: 'zara', title: 'Пески', text: 'Дойди до пустыни на юге.', goal: { flag: 'visit_desert' }, reward: { money: 40 } },
    { id: 'z2', npc: 'zara', title: 'Оазис', text: 'Найди оазис с пальмами в сердце пустыни.', goal: { flag: 'visit_oasis' }, reward: { money: 60, apple: 5 } },
    { id: 'z3', npc: 'zara', title: 'Конь пустыни', text: 'Поймай ахалтекинца или арабскую лошадь в пустыне.', goal: { stat: 'caught_desert', n: 1 }, reward: { money: 130 } },

    { id: 'a1', npc: 'aita', title: 'Северная гостья', text: 'Доберись до тундры на юго-востоке.', goal: { flag: 'visit_tundra' }, reward: { money: 40 } },
    { id: 'a2', npc: 'aita', title: 'Мохнатая лошадка', text: 'Поймай якутскую лошадь в тундре.', goal: { stat: 'caught_tundra', n: 1 }, reward: { money: 130, oats: 5 } },
    { id: 'a3', npc: 'aita', title: 'Сквозь чащу', text: 'Пройди дремучий лес между пустыней и тундрой.', goal: { flag: 'visit_deepforest' }, reward: { money: 50 } },

    { id: 'o2', npc: 'olya', title: 'Пещера в горах', text: 'Найди вход в пещеру и загляни внутрь.', goal: { flag: 'visit_cave' }, reward: { money: 60 } },
  ];

  // задания с доски в деревне — повторяются
  const BOARD = [
    { title: 'Ловец лошадей', text: 'Поймай 2 лошади.', goal: { stat: 'caught', n: 2 }, reward: { money: 70 } },
    { title: 'Урожайный день', text: 'Собери урожай 3 раза.', goal: { stat: 'harvest_total', n: 3 }, reward: { money: 60 } },
    { title: 'Охотник за кладами', text: 'Найди 2 клада.', goal: { stat: 'treasures', n: 2 }, reward: { money: 80 } },
    { title: 'Быстрые копыта', text: 'Займи место на пьедестале в скачках (1–3).', goal: { stat: 'podiums', n: 1 }, reward: { money: 80 } },
    { title: 'Грибник', text: 'Собери 6 грибов.', goal: { stat: 'mushrooms', n: 6 }, reward: { money: 50 } },
    { title: 'Зайкин друг', text: 'Поймай 2 зайчиков.', goal: { stat: 'bunnies', n: 2 }, reward: { money: 50 } },
    { title: 'Строитель', text: 'Построй 2 любые постройки.', goal: { stat: 'built_total', n: 2 }, reward: { money: 50 } },
    { title: 'Прыгунья', text: 'Пройди любой маршрут конкура.', goal: { stat: 'jumpRounds', n: 1 }, reward: { money: 60 } },
  ];

  function init(api) {
    G = api;
    const S = G.S;
    S.quests = S.quests || {};      // id → { state: 'active'|'done', base }
    S.flags = S.flags || {};
  }

  const byId = id => QUESTS.find(q => q.id === id);
  const npcById = id => NPCS.find(n => n.id === id);
  const stat = k => G.S.stats[k] || 0;

  function progress(q, st) {
    const g = q.goal;
    if (g.flag) return { cur: G.S.flags[g.flag] ? 1 : 0, need: 1 };
    if (g.islands) return { cur: Math.min(g.islands, World.ISLANDS.filter(I => G.S.flags['visit_' + I.id]).length), need: g.islands };
    if (g.item) return { cur: Math.min(g.n, G.S.inv[g.item] || 0), need: g.n };
    return { cur: Math.max(0, Math.min(g.n, Math.floor(stat(g.stat) - (st.base || 0)))), need: g.n };
  }
  const complete = (q, st) => { const p = progress(q, st); return p.cur >= p.need; };

  // следующее задание у персонажа: активное или первое невзятое
  function current(npcId) {
    for (const q of QUESTS.filter(x => x.npc === npcId)) {
      const st = G.S.quests[q.id];
      if (!st) return { q, st: null };
      if (st.state === 'active') return { q, st };
    }
    return null;
  }
  function marker(npcId) {
    const c = current(npcId);
    if (!c) return '';
    if (!c.st) return '❗';
    return complete(c.q, c.st) ? '❓' : '…';
  }

  function accept(q) {
    G.S.quests[q.id] = { state: 'active', base: q.goal.stat ? stat(q.goal.stat) : 0 };
    UI.toast(`📜 Новое задание: ${q.title}`, 'good');
    Sound.tick();
  }
  function rewardText(r) {
    return Object.entries(r).map(([k, v]) => (k === 'money' ? `${v} 🪙` : `${Items.icon(k)} ${Items.name(k)}${v > 1 ? ' ×' + v : ''}`)).join(', ');
  }
  function giveReward(r) {
    for (const [k, v] of Object.entries(r)) Farm.give(k, v);
  }
  function turnIn(q, st) {
    if (!complete(q, st)) return false;
    if (q.goal.item) G.S.inv[q.goal.item] -= q.goal.n;
    st.state = 'done';
    giveReward(q.reward);
    G.stat('questsDone');
    UI.toast(`🎉 Задание «${q.title}» выполнено! Награда: ${rewardText(q.reward)}`, 'good');
    Sound.fanfare();
    return true;
  }

  /* ---------- доска заданий ---------- */
  function boardState() {
    const S = G.S;
    if (!S.board) S.board = { i: Math.floor(Math.random() * BOARD.length), base: null };
    return S.board;
  }
  function boardQuest() {
    const b = boardState();
    return { q: BOARD[b.i], st: b.base == null ? null : { base: b.base, state: 'active' } };
  }
  function boardAccept() {
    const b = boardState(), q = BOARD[b.i];
    b.base = q.goal.stat ? stat(q.goal.stat) : 0;
    UI.toast(`📜 Задание с доски: ${q.title}`, 'good');
  }
  function boardTurnIn() {
    const b = boardState(), q = BOARD[b.i];
    if (!complete(q, { base: b.base })) return;
    giveReward(q.reward);
    G.stat('questsDone');
    UI.toast(`🎉 Задание с доски выполнено! +${rewardText(q.reward)}`, 'good');
    Sound.fanfare();
    let n = b.i;
    while (n === b.i) n = Math.floor(Math.random() * BOARD.length);
    b.i = n; b.base = null;
  }

  /* ---------- посещения мест ---------- */
  function updateVisits() {
    const S = G.S, p = S.player, f = S.flags;
    const reg = World.regionAt(p.x, p.y);
    const visit = (k, msg) => { if (!f[k]) { f[k] = true; if (msg) UI.toast(msg, 'good'); } };
    if (reg === 'forest') visit('visit_forest');
    if (reg === 'village') visit('visit_village', '🏘️ Ты пришла в деревню! Здесь живут кузнец, стилистка и есть доска заданий.');
    if (reg === 'mushroom') visit('visit_mushroom', '🍄 Грибное королевство! Здесь живут волшебные лошадки.');
    if (reg === 'cave') visit('visit_cave', '🦇 Ты в пещере. Здесь темно... и кто-то бродит.');
    if (reg === 'lake') visit('visit_lake');
    if (p.x > World.OX + 5450 && Math.abs(p.y - World.OY - 1150) < 600 && reg === 'lake') visit('visit_lake_east', '🌊 Восточный берег Большого озера!');
    if (reg === 'desert') visit('visit_desert', '🏜️ Пустыня! Здесь бегают зебры, а раз в 30 минут к станции приезжает поезд с лошадьми.');
    if (reg === 'tundra') visit('visit_tundra', '❄️ Тундра! Здесь живут мохнатые якутские лошади.');
    if (reg === 'deepforest') visit('visit_deepforest', '🌲 Дремучий лес. Здесь темно даже днём.');
    if (Math.hypot(p.x - World.OASIS.x, p.y - World.OASIS.y) < 520) visit('visit_oasis', '🌴 Оазис! Вода и пальмы посреди песков.');
    if (reg === 'grotto') visit('visit_grotto', '⛰️ Пещерные холмы! В маленьких пещерках живут лошади со светящимися узорами.');
    if (reg === 'foxwood') visit('visit_foxwood', '🦊 Лисий лес — густой и тёмный. Здесь живут лисьи лошади!');
    if (reg === 'dragonrock') visit('visit_dragonrock', '🐲 Драконьи скалы! Чешуйчатые лошади с драконьими крыльями.');
    if (reg === 'steppe') visit('visit_steppe', '🌾 Степь! Здесь бегают дикие лошади Пржевальского и олени.');
    const I = World.islandAt(p.x, p.y);
    if (I && !f['visit_' + I.id]) { visit('visit_' + I.id, `🏝️ ${I.name}! Здесь конюшня, пастбище, манеж и 5 диких лошадей.`); G.stat('islandsVisited'); }
  }

  function nearNpc(r = 80) {
    const p = G.S.player;
    let best = null, bd = r;
    for (const n of NPCS) { const d = Math.hypot(n.x - p.x, n.y - p.y); if (d < bd) { bd = d; best = n; } }
    return best;
  }

  function prompt() {
    const n = nearNpc();
    if (n) return { label: `💬 ${n.name}`, fn: () => UI.openNpc(n) };
    const p = G.S.player;
    if (Math.hypot(World.BOARD.x - p.x, World.BOARD.y - p.y) < 70) return { label: '📋 Доска заданий', fn: () => UI.openBoard() };
    return null;
  }

  function journal() {
    const list = [];
    for (const q of QUESTS) {
      const st = G.S.quests[q.id];
      if (st && st.state === 'active') list.push({ q, st, npc: npcById(q.npc), p: progress(q, st), done: complete(q, st) });
    }
    const b = boardQuest();
    if (b.st) list.push({ q: b.q, st: b.st, npc: { name: 'Доска заданий' }, p: progress(b.q, b.st), done: complete(b.q, b.st), board: true });
    return list;
  }
  const doneCount = () => Object.values(G.S.quests).filter(s => s.state === 'done').length;

  return {
    NPCS, QUESTS, init, current, marker, accept, turnIn, progress, complete, rewardText, journal, doneCount,
    boardQuest, boardAccept, boardTurnIn, updateVisits, nearNpc, prompt, npcById,
    hello: n => pick(n.hello), tip: n => pick(n.tips),
  };
})();

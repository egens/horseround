'use strict';
/* Каталоги: вещи в рюкзаке, семена и урожай, постройки, причёски и краски для гривы */
const Items = (() => {
  // всё, что лежит в рюкзаке (S.inv); sell — цена у торговца, 0 — не продаётся
  const ITEMS = {
    hay: { name: 'Сено', icon: '🌾', sell: 2 },
    oats: { name: 'Овёс', icon: '🥣', sell: 4 },
    carrot: { name: 'Морковка', icon: '🥕', sell: 2 },
    apple: { name: 'Яблоко', icon: '🍎', sell: 2 },
    sugar: { name: 'Сахар', icon: '🍬', sell: 1 },
    pumpkin: { name: 'Тыква', icon: '🎃', sell: 30 },
    sunflower: { name: 'Подсолнух', icon: '🌻', sell: 18 },
    pollen: { name: 'Волшебная пыльца', icon: '✨', sell: 40 },
    mushroom: { name: 'Гриб', icon: '🍄', sell: 6 },
    glowshroom: { name: 'Светящийся гриб', icon: '🔮', sell: 15 },
    seed_carrot: { name: 'Семена моркови', icon: '🌱', sell: 0 },
    seed_oats: { name: 'Семена овса', icon: '🌱', sell: 0 },
    seed_hay: { name: 'Семена травы', icon: '🌱', sell: 0 },
    seed_pumpkin: { name: 'Семена тыквы', icon: '🌱', sell: 0 },
    seed_sunflower: { name: 'Семена подсолнуха', icon: '🌱', sell: 0 },
    seed_magic: { name: 'Волшебное семечко', icon: '💫', sell: 0 },
    oldShoe: { name: 'Старая подкова', icon: '🧲', sell: 20 },
    oldCoin: { name: 'Старинная монета', icon: '🪙', sell: 40 },
    spoon: { name: 'Серебряная ложка', icon: '🥄', sell: 30 },
    brooch: { name: 'Брошь с камушком', icon: '💎', sell: 70 },
    bell: { name: 'Колокольчик', icon: '🔔', sell: 25 },
    goldShoe: { name: 'Золотая подкова', icon: '🏅', sell: 150 },
    crown: { name: 'Корона графа', icon: '👑', sell: 300 },
    map: { name: 'Карта сокровищ', icon: '🗺️', sell: 0 },
    milk: { name: 'Бутылочка молока', icon: '🍼', sell: 2 },
    horseshoes: { name: 'Новые подковы (4 шт.)', icon: '🔧', sell: 15 },
    dye_pink: { name: 'Розовая краска для гривы', icon: '🩷', sell: 0 },
    dye_blue: { name: 'Голубая краска для гривы', icon: '🩵', sell: 0 },
    dye_purple: { name: 'Фиолетовая краска для гривы', icon: '💜', sell: 0 },
    dye_mint: { name: 'Мятная краска для гривы', icon: '💚', sell: 0 },
    dye_gold: { name: 'Золотая краска для гривы', icon: '💛', sell: 0 },
    dye_rainbow: { name: 'Радужная краска для гривы', icon: '🌈', sell: 0 },
  };

  // грядки: что сажаем, сколько растёт (секунды игры), что собираем
  const CROPS = {
    carrot: { name: 'Морковь', seed: 'seed_carrot', time: 110, yield: ['carrot', 4], color: '#f76707', leaf: '#5c940d', seedPrice: 4 },
    oats: { name: 'Овёс', seed: 'seed_oats', time: 140, yield: ['oats', 4], color: '#e0c068', leaf: '#94a83a', seedPrice: 5 },
    hay: { name: 'Луговая трава', seed: 'seed_hay', time: 90, yield: ['hay', 5], color: '#8fbf4f', leaf: '#6b9a35', seedPrice: 3 },
    pumpkin: { name: 'Тыква', seed: 'seed_pumpkin', time: 200, yield: ['pumpkin', 1], color: '#f08c00', leaf: '#2f9e44', seedPrice: 10 },
    sunflower: { name: 'Подсолнух', seed: 'seed_sunflower', time: 160, yield: ['sunflower', 1], color: '#ffd43b', leaf: '#2b8a3e', seedPrice: 7 },
    magic: { name: 'Волшебный цветок', seed: 'seed_magic', time: 240, yield: ['pollen', 2], color: '#e599f7', leaf: '#3bc9db', seedPrice: 0 },
  };

  // постройки: размер в пикселях карты, цена, твёрдая ли
  const BUILDS = {
    bed: { name: 'Грядка', icon: '🟫', price: 20, w: 80, h: 44, solid: false, desc: 'Сажай морковь, овёс, тыквы' },
    fence: { name: 'Забор', icon: '🪵', price: 8, w: 90, h: 10, solid: true, desc: 'Секция деревянного забора' },
    lamp: { name: 'Фонарь', icon: '🏮', price: 35, w: 16, h: 16, solid: true, desc: 'Светит ночью' },
    flowerbed: { name: 'Клумба', icon: '🌷', price: 15, w: 60, h: 40, solid: false, desc: 'Красиво!' },
    bench: { name: 'Скамейка', icon: '🪑', price: 25, w: 70, h: 24, solid: true, desc: 'Отдохнуть после скачек' },
    trough: { name: 'Поилка', icon: '🚰', price: 35, w: 80, h: 28, solid: true, desc: 'Лошади в леваде рядом веселее' },
    haystack: { name: 'Стог сена', icon: '🌾', price: 20, w: 50, h: 50, solid: true, desc: 'Даёт 5 сена' },
    tree: { name: 'Яблонька', icon: '🌳', price: 30, w: 30, h: 30, solid: true, desc: 'Раз в 3 минуты дарит яблоки' },
    bunnyhouse: { name: 'Домик для зайчиков', icon: '🐰', price: 60, w: 50, h: 40, solid: true, desc: 'Зайчики приходят чаще' },
    well: { name: 'Колодец', icon: '🪣', price: 80, w: 50, h: 50, solid: true, desc: 'Грядки рядом поливаются сами' },
    windmill: { name: 'Мельница', icon: '🌬️', price: 250, w: 110, h: 110, solid: true, desc: 'Большая и красивая' },
    stable5: { name: 'Маленькая конюшня', icon: '🏠', price: 400, w: 340, h: 150, solid: false, desc: '+5 денников для лошадей' },
  };

  const MANE_STYLES = {
    normal: { name: 'Обычная', icon: '🐴' },
    long: { name: 'Длинная', icon: '💇' },
    short: { name: 'Короткая', icon: '✂️' },
    braids: { name: 'Косички', icon: '🎀' },
    mohawk: { name: 'Ирокез', icon: '⚡' },
    bows: { name: 'С бантиками', icon: '🎀' },
  };
  const DYES = {
    pink: { name: 'Розовая', color: '#ff8fc7', item: 'dye_pink', price: 25 },
    blue: { name: 'Голубая', color: '#74c0fc', item: 'dye_blue', price: 25 },
    purple: { name: 'Фиолетовая', color: '#b197fc', item: 'dye_purple', price: 25 },
    mint: { name: 'Мятная', color: '#8ce99a', item: 'dye_mint', price: 25 },
    gold: { name: 'Золотая', color: '#ffd43b', item: 'dye_gold', price: 60 },
    rainbow: { name: 'Радужная', color: 'rainbow', item: 'dye_rainbow', price: 100 },
  };
  const RAINBOW = ['#ff6b6b', '#ffa94d', '#ffe066', '#69db7c', '#4dabf7', '#9775fa'];

  // сёдла и уздечки: стиль (украшения) и цвет кожи
  const TACK_STYLES = {
    classic: { name: 'Классическое', icon: '🐴', saddle: 0, bridle: 0, desc: 'Простая кожа' },
    crystal: { name: 'Кристальное', icon: '💎', saddle: 180, bridle: 110, desc: 'Сверкающие кристаллики' },
    plant: { name: 'Цветочное', icon: '🌿', saddle: 150, bridle: 90, desc: 'Листья, лианы и цветы' },
    shell: { name: 'Ракушечное', icon: '🐚', saddle: 160, bridle: 100, desc: 'Оболочка из ракушек и жемчуга' },
  };
  const LEATHER = ['#5b3a1e', '#2b2b2b', '#8a5a32', '#f1e3c6', '#c92a2a', '#1c7ed6', '#e64980', '#7048e8', '#2b8a3e', '#f59f00'];

  const name = k => (ITEMS[k] ? ITEMS[k].name : k);
  const icon = k => (ITEMS[k] ? ITEMS[k].icon : '•');
  return { ITEMS, CROPS, BUILDS, MANE_STYLES, DYES, RAINBOW, TACK_STYLES, LEATHER, name, icon };
})();

'use strict';
/* Загрузка Three.js: сначала своя копия (работает без интернета), потом CDN */
const ThreeLoader = (() => {
  const URLS = ['js/vendor/three.min.js', 'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js'];
  let loading = null;
  function load() {
    if (window.THREE) return Promise.resolve(true);
    if (loading) return loading;
    loading = new Promise(res => {
      const tryUrl = i => {
        if (i >= URLS.length) return res(false);
        const s = document.createElement('script');
        s.src = URLS[i];
        s.onload = () => (window.THREE ? res(true) : tryUrl(i + 1));
        s.onerror = () => tryUrl(i + 1);
        document.head.appendChild(s);
      };
      tryUrl(0);
    }).then(ok => { if (!ok) loading = null; return ok; });
    return loading;
  }
  return { load };
})();

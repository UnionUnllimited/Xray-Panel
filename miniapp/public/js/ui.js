// Компоненты интерфейса из «Линзы»: шторки как в iOS, сегменты с жидким индикатором,
// линзирование таббара, тосты, пустые состояния.
import { haptic, setBack, setMain } from './tg.js';

/* ---------------- DOM и форматирование ---------------- */
export const $ = (s, el = document) => el.querySelector(s);
export const $$ = (s, el = document) => [...el.querySelectorAll(s)];
export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const fmt = (n) => Number(n).toLocaleString('ru-RU').replace(/ | /g, ' ');
export const plural = (n, a, b, c) => { const m10 = n % 10, m100 = n % 100; if (m10 === 1 && m100 !== 11) return a; if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return b; return c; };
const MSK = { timeZone: 'Europe/Moscow' };
export const dateLong = (ts) => new Date(ts).toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', year: 'numeric', ...MSK });
export const dateTime = (ts) => new Date(ts).toLocaleString('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', ...MSK }).replace('.', '');
export const daysWord = (d) => `${d} ${plural(d, 'день', 'дня', 'дней')}`;
export const devicesWord = (n) => `${n} ${plural(n, 'устройство', 'устройства', 'устройств')}`;
export const REDUCED = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
export const cssVar = (n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim();

export function money(amount, currency = 'RUB') {
  const n = fmt(Math.round(Number(amount) * 100) / 100);
  if (currency === 'XTR') return `${n} ⭐`;
  if (currency === 'USD' || currency === 'USDT') return `${n} $`;
  return `${n} ₽`;
}

export function bytes(b) {
  const n = Number(b) || 0;
  if (n < 1024 ** 3) return `${fmt(Math.round(n / 1024 ** 2))} МБ`;
  const gb = n / 1024 ** 3;
  return `${String(gb >= 100 ? Math.round(gb) : Math.round(gb * 10) / 10).replace('.', ',')} ГБ`;
}

document.addEventListener('error', (e) => {
  const img = e.target;
  if (!(img instanceof HTMLImageElement) || !img.dataset.fallback) return;
  const b = document.createElement('b');
  b.className = 'mono';
  b.textContent = img.dataset.fallback;
  img.replaceWith(b);
}, true);

export function avatarHTML(user, cls = '') {
  const letter = esc((user?.first_name || user?.username || '?').trim()[0] || '?');
  return `<span class="lgs avatar ${cls}">${user?.photo_url ? `<img src="${esc(user.photo_url)}" alt="" data-fallback="${letter}">` : `<b class="mono">${letter}</b>`}</span>`;
}

/* ---------------- Иконки ---------------- */
const svg = (w, body, sw = 1.9) => `<svg width="${w}" height="${w}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
export const icon = {
  chev: '<svg class="chev" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>',
  check: '<svg class="check" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m5 12 4.5 4.5L19 7"/></svg>',
  shield: svg(14, '<path d="M12 3 5 6v5c0 4.5 3 8 7 10 4-2 7-5.5 7-10V6z"/><path d="m9 12 2 2 4-4"/>', 2.4),
  bolt: svg(20, '<path d="M13 3 5 13.5h6L10 21l8-10.5h-6z"/>'),
  copy: svg(20, '<rect x="8.5" y="8.5" width="12" height="12" rx="2.5"/><path d="M15.5 8.5V6a2.5 2.5 0 0 0-2.5-2.5H6A2.5 2.5 0 0 0 3.5 6v7A2.5 2.5 0 0 0 6 15.5h2.5"/>'),
  share: svg(20, '<path d="M12 3v12M8 7l4-4 4 4"/><path d="M6 11H5a1 1 0 0 0-1 1v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7a1 1 0 0 0-1-1h-1"/>'),
  gift: svg(20, '<rect x="3.5" y="8.5" width="17" height="5" rx="1.5"/><path d="M5 13.5V19a1.5 1.5 0 0 0 1.5 1.5h11A1.5 1.5 0 0 0 19 19v-5.5M12 8.5v12M12 8.5S10.5 3.5 8 4.5c-2 .8-.8 4 4 4Zm0 0s1.5-5 4-4c2 .8.8 4-4 4Z"/>'),
  support: svg(20, '<path d="M4 13v-1a8 8 0 0 1 16 0v1"/><rect x="3.5" y="13" width="4" height="6" rx="1.5"/><rect x="16.5" y="13" width="4" height="6" rx="1.5"/><path d="M20 19c0 1.5-2 2.5-5 2.5h-2"/>'),
  ticket: svg(20, '<path d="M3.5 8.5a2 2 0 0 0 0 4v3A1.5 1.5 0 0 0 5 17h14a1.5 1.5 0 0 0 1.5-1.5v-3a2 2 0 0 1 0-4v-3A1.5 1.5 0 0 0 19 4H5a1.5 1.5 0 0 0-1.5 1.5z" transform="translate(0 1.5)"/><path d="M14 5.5v12" transform="translate(0 1.5)" stroke-dasharray="2 2.5"/>'),
  devices: svg(20, '<rect x="2.5" y="5" width="13" height="10" rx="1.8"/><path d="M6 19h6M9 15v4"/><rect x="17" y="9" width="4.5" height="10" rx="1.2"/>'),
  card: svg(20, '<rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19M6.5 15h4"/>'),
  info: svg(18, '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>', 2),
  x: svg(12, '<path d="M6 6l12 12M18 6 6 18"/>', 3),
  bot: svg(20, '<path d="m21.5 4.5-19 7.4 6.2 2.1 2.3 6.5 3.4-4.3 5 3.8z"/><path d="m8.7 14 7.8-6.3"/>', 2),
  history: svg(20, '<path d="M3.5 12a8.5 8.5 0 1 0 2.5-6"/><path d="M3.5 4v4h4M12 8v4.5l3 2"/>'),
  globe: svg(20, '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.3 3.6 5.2 3.6 8.5s-1.1 6.2-3.6 8.5c-2.5-2.3-3.6-5.2-3.6-8.5S9.5 5.8 12 3.5Z"/>')
};

/* ---------------- Тосты ---------------- */
let toastTimer;
export function toast(text, type) {
  const t = $('#toast');
  t.textContent = text;
  t.classList.add('show');
  if (type === 'error') haptic.notify('error');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 2400);
}
export const toastError = (e) => toast(e?.message || 'Что-то пошло не так', 'error');

/* ---------------- Шторки (страница отъезжает назад, как в iOS) ---------------- */
let sheetState = null;
let routeBack = null;
export function setRouteBack(fn) { routeBack = fn; if (!sheetState) setBack(fn); }

export function openSheet(title, html, onMount, { main, onClose } = {}) {
  if (sheetState) closeSheet(true);
  $('#sheetTitle').textContent = title;
  const content = document.createElement('div');
  content.className = 'sheet-inner';
  content.innerHTML = html;
  $('#sheetBody').replaceChildren(content);
  $('#overlay').classList.add('open');
  $('#sheet').classList.add('open');
  $('#page').classList.add('behind');
  document.body.classList.add('sheet-open');
  const prevMain = setMain(main || null);
  sheetState = { prevMain, onClose };
  setBack(() => closeSheet());
  $('#sheetBody').scrollTop = 0;
  if (onMount) onMount(content);
}
export function closeSheet(instant) {
  if (!sheetState) return;
  const { prevMain, onClose } = sheetState;
  sheetState = null;
  $('#overlay').classList.remove('open');
  $('#sheet').classList.remove('open');
  $('#page').classList.remove('behind');
  document.body.classList.remove('sheet-open');
  setMain(prevMain);
  setBack(routeBack);
  if (!instant) haptic.impact('light');
  onClose?.();
}
export const sheetIsOpen = () => Boolean(sheetState);
export const setSheetMain = (cfg) => { if (sheetState) setMain(cfg); };

/* ---------------- Сегменты с жидким индикатором ---------------- */
export function moveIndicator(seg, animate = true) {
  const ind = $('.seg-ind', seg);
  const active = $('[aria-selected="true"]', seg);
  if (!ind) return;
  if (!active || !seg.offsetWidth) { ind.style.width = '0px'; return; }
  const x = active.offsetLeft, w = active.offsetWidth;
  const prevX = parseFloat(ind.dataset.x), prevW = parseFloat(ind.dataset.w);
  ind.style.left = x + 'px';
  ind.style.width = w + 'px';
  ind.dataset.x = x; ind.dataset.w = w;
  if (!animate || REDUCED || isNaN(prevX) || prevX === x || !prevW) return;
  const spring = cssVar('--spring-bouncy');
  ind.animate([{ left: prevX + 'px', width: prevW + 'px' }, { left: x + 'px', width: w + 'px' }], { duration: 650, easing: spring });
  ind.animate([{ transform: 'scale(1,1)' }, { transform: 'scale(1.08,.86)', offset: 0.35 }, { transform: 'scale(.98,1.04)', offset: 0.7 }, { transform: 'scale(1,1)' }], { duration: 520, easing: 'ease-in-out' });
}

export function segHTML(items, current, attr = 'data-seg-val') {
  return `<div class="lg seg" role="tablist"><span class="seg-ind lgs"></span>${items.map((it) =>
    `<button type="button" role="tab" ${attr}="${esc(it.id)}" aria-selected="${String(it.id) === String(current)}">${esc(it.name)}</button>`).join('')}</div>`;
}

export function bindSeg(seg, onPick, attr = 'data-seg-val') {
  requestAnimationFrame(() => moveIndicator(seg, false));
  seg.addEventListener('click', (e) => {
    const b = e.target.closest(`[${attr}]`);
    if (!b || b.getAttribute('aria-selected') === 'true') return;
    haptic.select();
    $$(`[${attr}]`, seg).forEach((x) => x.setAttribute('aria-selected', x === b));
    moveIndicator(seg, true);
    onPick(b.getAttribute(attr));
  });
}

/* ---------------- Линзирование: SVG-преломление (только Chromium) ---------------- */
const LENS_OK = (() => {
  const ua = navigator.userAgent;
  return /Chrome|Chromium|Edg\//.test(ua) && !/iPhone|iPad|iPod/.test(ua) && CSS.supports('backdrop-filter', 'url(#x)');
})();
let lensSeq = 0;
function lensMap(w, h, radius, bezel) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(w, h);
  const r = Math.min(radius, h / 2, w / 2);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const px = x + 0.5 - w / 2, py = y + 0.5 - h / 2;
      const qx = Math.abs(px) - (w / 2 - r), qy = Math.abs(py) - (h / 2 - r);
      let dist, nx, ny;
      if (qx > 0 && qy > 0) { const len = Math.hypot(qx, qy); dist = len - r; nx = (qx / len) * Math.sign(px); ny = (qy / len) * Math.sign(py); }
      else { dist = Math.max(qx, qy) - r; if (qx > qy) { nx = Math.sign(px); ny = 0; } else { nx = 0; ny = Math.sign(py); } }
      const depth = -dist;
      let dx = 0, dy = 0;
      if (depth >= 0 && depth < bezel) { const t = 1 - depth / bezel; const m = t * t * (3 - 2 * t); dx = -nx * m; dy = -ny * m; }
      const i = (y * w + x) * 4;
      img.data[i] = 128 + dx * 127; img.data[i + 1] = 128 + dy * 127; img.data[i + 2] = 128; img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return c.toDataURL();
}
export function applyLens(el) {
  if (!LENS_OK || el.dataset.lensOn) return;
  el.dataset.lensOn = '1';
  const bezel = Number(el.dataset.lens) || 16;
  const build = () => {
    const w = Math.round(el.offsetWidth), h = Math.round(el.offsetHeight);
    if (!w || !h) return;
    const radius = parseFloat(getComputedStyle(el).borderTopLeftRadius) || h / 2;
    const id = el.dataset.lensId || ('lens' + (++lensSeq));
    el.dataset.lensId = id;
    let f = document.getElementById(id);
    if (!f) {
      f = document.createElementNS('http://www.w3.org/2000/svg', 'filter');
      f.setAttribute('id', id);
      f.setAttribute('color-interpolation-filters', 'sRGB');
      $('#lensDefs defs').appendChild(f);
    }
    f.innerHTML = `<feImage href="${lensMap(w, h, radius, bezel)}" x="0" y="0" width="${w}" height="${h}" result="map"/><feDisplacementMap in="SourceGraphic" in2="map" scale="${bezel * 2.2}" xChannelSelector="R" yChannelSelector="G"/>`;
    el.style.backdropFilter = `blur(3px) url(#${id}) saturate(1.8) brightness(1.05)`;
  };
  let t;
  new ResizeObserver(() => { clearTimeout(t); t = setTimeout(build, 80); }).observe(el);
}

/* ---------------- Общие блоки ---------------- */
export function emptyHTML(text, action = '', glyph = icon.info) {
  return `<div class="card empty mat"><span class="lgs ico">${glyph}</span><p>${text}</p>${action}</div>`;
}
export const skeletonHTML = (n = 2) => Array.from({ length: n }, () => '<div class="skeleton"></div>').join('');
export function errorHTML(e, retry = true) {
  return emptyHTML(esc(e?.message || 'Не удалось загрузить данные'), retry ? '<button type="button" class="lgb btn press" data-action="reload">Повторить</button>' : '');
}
export const row = (label, value = '', { nav = '', attrs = '', chev = true } = {}) =>
  `<button type="button" class="row press" ${nav ? `data-nav="${nav}"` : ''} ${attrs}><span>${label}</span><span class="row-flex"><span class="v">${value}</span>${chev ? icon.chev : ''}</span></button>`;

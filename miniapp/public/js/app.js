import { initTelegram, setMain, haptic, tg } from './tg.js';
import { $, $$, moveIndicator, applyLens, setRouteBack, closeSheet, sheetIsOpen, errorHTML, emptyHTML, esc, toastError } from './ui.js';
import { store, loadMe } from './store.js';
import home from './views/home.js';
import buy from './views/buy.js';
import connect from './views/connect.js';
import friends from './views/friends.js';
import { profile, devices, history as historyView } from './views/profile.js';

const ROOT_TABS = ['/', '/buy', '/connect', '/friends', '/profile'];

const routes = [
  ['/', home], ['/buy', buy], ['/connect', connect], ['/friends', friends], ['/profile', profile],
  ['/devices', devices], ['/history', historyView]
].map(([pattern, view]) => ({ re: new RegExp('^' + pattern + '$'), view }));

function parseHash() {
  const raw = location.hash.replace(/^#/, '') || '/';
  const [path, q = ''] = raw.split('?');
  return { path: path || '/', query: Object.fromEntries(new URLSearchParams(q)) };
}

const tabFor = (path) => (ROOT_TABS.includes(path) ? path : path === '/devices' ? '/connect' : '/profile');
const parentOf = (path) => (path === '/devices' ? '/connect' : '/profile');

/* ---------------- Роутер со своим индексом истории ---------------- */
// Telegram кладёт параметры запуска в hash (#tgWebAppData=…). SDK их уже прочитал,
// а hash нужен роутеру — убираем до первого рендера.
if (/^#tgWebApp/.test(location.hash)) history.replaceState(history.state, '', location.pathname + location.search);
let idx = history.state?.idx ?? 0;
let cleanup = null;
let renderSeq = 0;
const scrolls = new Map();
if (history.state?.idx === undefined) history.replaceState({ idx }, '', location.href);

export function navigate(to, { replace = false } = {}) {
  scrolls.set(idx, window.scrollY);
  if (replace) history.replaceState({ idx }, '', '#' + to);
  else history.pushState({ idx: ++idx }, '', '#' + to);
  render(false);
}

function goBack() {
  if (sheetIsOpen()) { closeSheet(); return; }
  haptic.impact('light');
  if (idx > 0) history.back();
  else navigate(parentOf(parseHash().path), { replace: true });
}

window.addEventListener('popstate', (e) => {
  if (sheetIsOpen()) closeSheet(true);
  scrolls.set(idx, window.scrollY);
  idx = e.state?.idx ?? 0;
  render(true);
});

function needTelegram(root) {
  const e = store.meError;
  root.innerHTML = `<div class="topbar"><span class="brand"><img src="img/logo.svg" alt="">Подписка</span></div>` +
    emptyHTML(e?.status === 403 ? esc(e.message) : tg ? esc(e?.message || 'Не удалось загрузить данные') : 'Приложение работает внутри Telegram: откройте его кнопкой в боте.',
      tg && e?.status !== 403 ? '<button type="button" class="lgb btn press" data-action="retry">Повторить</button>' : '');
}

export async function render(restoreScroll) {
  const seq = ++renderSeq;
  const { path, query } = parseHash();
  const match = routes.find((r) => r.re.test(path));
  if (!match) { navigate('/', { replace: true }); return; }

  if (typeof cleanup === 'function') cleanup();
  cleanup = null;
  if (sheetIsOpen()) closeSheet(true);
  setMain(null);
  const tab = tabFor(path);
  if (ROOT_TABS.includes(path)) store.lastTab = path;
  updateTabbar(tab);
  setRouteBack(ROOT_TABS.includes(path) ? null : goBack);

  const root = $('#view');
  root.innerHTML = '';
  root.classList.remove('mat');
  void root.offsetWidth;
  root.classList.add('mat');
  if (!restoreScroll) window.scrollTo(0, 0);

  if (!store.me) { needTelegram(root); return; }
  const ctx = { query, path, navigate, refresh: () => render(true), isCurrent: () => seq === renderSeq };
  try {
    cleanup = await match.view(root, ctx);
  } catch (e) {
    if (seq === renderSeq) root.innerHTML = errorHTML(e);
  }
  if (seq !== renderSeq) { if (typeof cleanup === 'function') cleanup(); return; }
  if (restoreScroll && scrolls.has(idx)) requestAnimationFrame(() => window.scrollTo(0, scrolls.get(idx)));
  $$('.seg', root).forEach((s) => moveIndicator(s, false));
}

/* ---------------- Таббар ---------------- */
function updateTabbar(tab) {
  const bar = $('.tabbar');
  $$('[data-nav]', bar).forEach((b) => b.setAttribute('aria-selected', b.dataset.nav === tab));
  moveIndicator(bar, true);
}

/* ---------------- Общие взаимодействия ---------------- */
document.addEventListener('pointerdown', (e) => {
  const el = e.target.closest('.press, .seg > button');
  if (!el) return;
  const target = el.classList.contains('press') ? el : el.closest('.seg');
  const r = target.getBoundingClientRect();
  target.style.setProperty('--gx', ((e.clientX - r.left) / r.width) * 100 + '%');
  target.style.setProperty('--gy', ((e.clientY - r.top) / r.height) * 100 + '%');
  const inner = e.target.closest('button.press, a.press');
  (inner && inner !== el ? inner : el).classList.add('pressed');
}, { passive: true });
const release = () => $$('.pressed').forEach((el) => el.classList.remove('pressed'));
['pointerup', 'pointercancel', 'dragstart', 'scroll'].forEach((ev) => document.addEventListener(ev, release, { capture: true, passive: true }));

document.addEventListener('click', async (e) => {
  const nav = e.target.closest('[data-nav]');
  if (nav) {
    e.preventDefault();
    const to = nav.dataset.nav;
    if (nav.closest('.tabbar')) {
      haptic.select();
      if (to === parseHash().path) { window.scrollTo({ top: 0, behavior: 'smooth' }); return; }
    }
    navigate(to);
    return;
  }
  if (e.target.closest('[data-action="reload"]')) render(true);
  if (e.target.closest('[data-action="retry"]')) { await loadMe(); render(false); }
});

$('#overlay').addEventListener('click', () => closeSheet());
$('#sheetClose').addEventListener('click', () => closeSheet());
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && sheetIsOpen()) closeSheet(); });
window.addEventListener('resize', () => $$('.seg').forEach((s) => moveIndicator(s, false)));
window.addEventListener('unhandledrejection', (e) => { if (e.reason?.status !== undefined) toastError(e.reason); });

/* ---------------- Запуск ---------------- */
initTelegram(() => $$('.seg').forEach((s) => moveIndicator(s, false)));
applyLens($('.tabbar'));
await loadMe();
const START = { buy: '/buy', connect: '/connect', friends: '/friends', profile: '/profile', devices: '/devices', history: '/history' };
const deep = START[tg?.initDataUnsafe?.start_param || new URLSearchParams(location.search).get('startapp') || ''];
if (deep && !location.hash) {
  history.replaceState({ idx: 0 }, '', '#/');
  navigate(deep);
} else {
  render(false);
}
requestAnimationFrame(() => moveIndicator($('.tabbar'), false));

import { store, sub, project } from '../store.js';
import { haptic, setMain, openLink, copyText, devicePlatform } from '../tg.js';
import { $, esc, icon, segHTML, bindSeg, emptyHTML, toast } from '../ui.js';

// Кастомные схемы (happ://, v2raytun://) из WebView Telegram не открываются —
// их открывает страница /redirect_app на странице подписки (subpage).
const DEEP = {
  Happ: (url) => `happ://add/${url}`,
  'Happ (вне РФ)': (url) => `happ://add/${url}`,
  'Happ (APK)': (url) => `happ://add/${url}`,
  V2RayTun: (url) => `v2raytun://import/${url}`
};

// Короткие подписи: пять платформ должны помещаться в сегмент на узком экране.
const SHORT = { ios: 'iOS', android: 'Android', windows: 'Windows', mac: 'macOS', linux: 'Linux' };

export default async function connect(root, { navigate }) {
  const s = sub();
  const p = project();
  if (!s || !s.sub_url) {
    root.innerHTML = '<div class="topbar"><h1 class="title">Подключение</h1></div>' +
      emptyHTML(s ? 'Ссылка подписки ещё не готова. Напишите в поддержку — поможем.' : 'Чтобы подключиться, нужна подписка. Оформите её или возьмите пробный период.',
        `<button type="button" class="lgb btn press" data-nav="${s ? '/profile' : '/buy'}">${s ? 'Профиль' : 'Выбрать тариф'}</button>`, icon.bolt);
    return;
  }
  const platforms = store.me.apps;
  const guess = devicePlatform();
  let current = platforms.find((x) => x.id === guess)?.id || platforms[0]?.id;

  root.innerHTML = `
    <div class="topbar"><h1 class="title">Подключение</h1></div>
    ${s.active ? '' : '<div class="callout bad">Подписка закончилась — подключение заработает после продления.</div>'}
    ${platforms.length ? `<div id="platBox">${segHTML(platforms.map((x) => ({ id: x.id, name: SHORT[x.id] || x.name })), current)}</div>` : ''}
    <section class="card panel stack" id="steps"></section>
    <section class="stack-sm">
      <p class="label">Ссылка подписки</p>
      <button type="button" class="card panel row-flex press" id="copyLink" style="text-align:left">
        <span class="grow code small" style="word-break:break-all;font-weight:500">${esc(s.sub_url)}</span>${icon.copy}</button>
      <p class="note">Ссылка личная: по ней подключаются ваши устройства. Не публикуйте её.</p>
    </section>
    <div class="card group">
      <button type="button" class="row press" id="openPage"><span class="row-flex">${icon.globe}<span>Страница подключения</span></span>${icon.chev}</button>
      ${store.me.features.devices ? `<button type="button" class="row press" data-nav="/devices"><span class="row-flex">${icon.devices}<span>Мои устройства</span></span>${icon.chev}</button>` : ''}
      ${p.support_url ? `<button type="button" class="row press" id="help"><span class="row-flex">${icon.support}<span>Не получается — помогите</span></span>${icon.chev}</button>` : ''}
    </div>`;

  const redirect = (deep) => `${p.sub_page_url}/redirect_app?target=${encodeURIComponent(deep)}`;

  const drawSteps = () => {
    const plat = platforms.find((x) => x.id === current);
    const apps = plat ? plat.apps : [];
    const main = apps.find((a) => DEEP[a.name]) || null;
    $('#steps', root).innerHTML = `
      <div class="stack-sm">
        <h3>1. Установите приложение</h3>
        ${apps.length ? `<div class="chips">${apps.map((a, i) => `<button type="button" class="${i === 0 ? 'lgb' : 'fill'} chip press" data-app="${esc(a.url)}">${esc(a.name)}</button>`).join('')}</div>`
          : '<p class="note" style="padding:0">Подойдёт любой клиент с поддержкой подписок: Happ, V2RayTun, Hiddify.</p>'}
      </div>
      <div class="stack-sm">
        <h3>2. Добавьте подписку</h3>
        <p class="note" style="padding:0">${main && p.sub_page_url ? `Нажмите кнопку — подписка сама откроется в ${esc(main.name.split(' ')[0])}.` : 'Скопируйте ссылку ниже и вставьте её в приложение: «Добавить» → «Из буфера».'}</p>
        ${main && p.sub_page_url ? `<button type="button" class="solid btn block press" id="addApp">${icon.bolt} Добавить в ${esc(main.name.split(' ')[0])}</button>` : ''}
      </div>
      <div class="stack-sm">
        <h3>3. Включите</h3>
        <p class="note" style="padding:0">Выберите любой сервер и нажмите кнопку подключения. Готово — серверы и настройки обновляются сами.</p>
      </div>`;
    $('#addApp', root)?.addEventListener('click', () => { haptic.impact('medium'); openLink(redirect(DEEP[main.name](s.sub_url))); });
  };

  if (platforms.length) bindSeg($('#platBox .seg', root), (v) => { current = v; drawSteps(); });
  drawSteps();

  root.addEventListener('click', (e) => {
    const a = e.target.closest('[data-app]');
    if (a) { haptic.impact('light'); openLink(a.dataset.app); }
  });
  const copy = async () => {
    haptic.impact('light');
    toast((await copyText(s.sub_url)) ? 'Ссылка скопирована' : 'Не удалось скопировать — выделите ссылку вручную');
  };
  $('#copyLink', root).addEventListener('click', copy);
  $('#openPage', root).addEventListener('click', () => { haptic.impact('light'); openLink(s.sub_url); });
  $('#help', root)?.addEventListener('click', () => openLink(p.support_url));

  if (!s.active) setMain({ text: 'Продлить подписку', shine: true, onClick: () => navigate('/buy') });
  else setMain({ text: 'Скопировать ссылку', onClick: copy });
}

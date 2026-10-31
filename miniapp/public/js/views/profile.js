import { get, post } from '../api.js';
import { store, loadMe, sub, project } from '../store.js';
import { haptic, openLink, themePref, setThemePref, confirmDialog, setMain } from '../tg.js';
import {
  $, $$, esc, icon, avatarHTML, dateLong, dateTime, money, fmt, daysWord, segHTML, bindSeg,
  emptyHTML, openSheet, closeSheet, setSheetMain, toast, toastError
} from '../ui.js';

function promoSheet() {
  openSheet('Промокод', `
    <label class="field"><span>Код</span>
      <input class="input code" id="promoCode" maxlength="64" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="Например, START30"></label>
    <div class="err" id="promoErr" hidden></div>
    <p class="note">Дни из промокода добавятся к подписке.</p>`, (box) => {
    const input = $('#promoCode', box);
    setTimeout(() => input.focus(), 350);
    const submit = async () => {
      const code = input.value.trim();
      if (!code) { $('#promoErr', box).textContent = 'Введите промокод'; $('#promoErr', box).hidden = false; return; }
      setSheetMain({ text: 'Активировать', progress: true, onClick: () => {} });
      try {
        const r = await post('/api/promo', { code });
        haptic.notify('success');
        await loadMe();
        closeSheet(true);
        toast(`Промокод принят: +${daysWord(r.days)}`);
      } catch (e) {
        $('#promoErr', box).textContent = e.message;
        $('#promoErr', box).hidden = false;
        haptic.notify('error');
        setSheetMain({ text: 'Активировать', onClick: submit });
      }
    };
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
    setSheetMain({ text: 'Активировать', onClick: submit });
  });
}

export async function profile(root) {
  const me = store.me;
  const u = me.user;
  const s = sub();
  const p = project();
  const name = [u.first_name, u.last_name].filter(Boolean).join(' ');
  root.innerHTML = `
    <div class="center stack-sm" style="align-items:center;padding-top:8px">
      ${avatarHTML(u, 'lg-size')}
      <h1 style="font-size:26px;font-weight:700">${esc(name)}</h1>
      <span class="muted">${u.username ? `@${esc(u.username)} · ` : ''}ID ${u.id}</span>
    </div>
    <div class="card group">
      <div class="row"><span>Подписка</span><span class="v">${s ? (s.active ? `до ${dateLong(s.end_at)}` : '<span class="tag bad">истекла</span>') : '<span class="tag neutral">нет</span>'}</span></div>
      ${s ? `<div class="row"><span>Устройства</span><span class="v">${s.limit_ip ? `до ${s.limit_ip}` : 'без лимита'}</span></div>` : ''}
    </div>
    <div class="card group">
      ${me.features.promo ? `<button type="button" class="row press" id="promo"><span class="row-flex">${icon.ticket}<span>Промокод</span></span>${icon.chev}</button>` : ''}
      ${me.features.devices ? `<button type="button" class="row press" data-nav="/devices"><span class="row-flex">${icon.devices}<span>Мои устройства</span></span>${icon.chev}</button>` : ''}
      <button type="button" class="row press" data-nav="/history"><span class="row-flex">${icon.history}<span>История платежей</span></span>${icon.chev}</button>
      ${p.support_url ? `<button type="button" class="row press" id="support"><span class="row-flex">${icon.support}<span>Поддержка</span></span>${icon.chev}</button>` : ''}
      ${p.bot_username ? `<button type="button" class="row press" id="bot"><span class="row-flex">${icon.bot}<span>Открыть бота</span></span>${icon.chev}</button>` : ''}
    </div>
    <section>
      <p class="label">Оформление</p>
      <div id="themeBox">${segHTML([{ id: 'auto', name: 'Авто' }, { id: 'light', name: 'Светлая' }, { id: 'dark', name: 'Тёмная' }], themePref())}</div>
      <p class="note" style="margin-top:8px">«Авто» — как в Telegram.</p>
    </section>`;
  $('#promo', root)?.addEventListener('click', () => { haptic.impact('light'); promoSheet(); });
  $('#support', root)?.addEventListener('click', () => openLink(p.support_url));
  $('#bot', root)?.addEventListener('click', () => openLink(`https://t.me/${p.bot_username}`));
  bindSeg($('#themeBox .seg', root), (v) => setThemePref(v));
}

const ago = (raw) => {
  const t = Date.parse(raw);
  return Number.isNaN(t) ? '' : dateTime(t);
};

export async function devices(root, { refresh }) {
  root.innerHTML = '<div class="topbar"><h1 class="title">Устройства</h1></div><div class="skeleton"></div>';
  const d = await get('/api/devices');
  if (!d.enabled) {
    root.innerHTML = '<div class="topbar"><h1 class="title">Устройства</h1></div>' + emptyHTML('Список устройств появится после первого подключения.', '', icon.devices);
    return;
  }
  root.innerHTML = `
    <div class="topbar"><h1 class="title">Устройства</h1></div>
    <div class="kpis">
      <div class="card kpi"><div class="k">Подключено</div><div class="v">${fmt(d.items.length)}</div></div>
      <div class="card kpi"><div class="k">Лимит</div><div class="v">${d.limit ? fmt(d.limit) : '∞'}</div></div>
    </div>
    ${d.items.length ? `<div class="card group">${d.items.map((x) => `
      <div class="row">
        <span class="grow" style="display:flex;flex-direction:column;gap:2px">
          <span style="font-weight:600">${esc(x.name)}</span>
          <span class="small muted">${esc([x.os, x.app].filter(Boolean).join(' · '))}${x.last_seen ? ` · ${esc(ago(x.last_seen))}` : ''}</span>
        </span>
        <button type="button" class="link-btn danger press" data-hwid="${esc(x.hwid)}">Отвязать</button>
      </div>`).join('')}</div>
      <p class="note">Отвязанное устройство освобождает место в лимите. Чтобы снова им пользоваться, просто обновите подписку в приложении.</p>`
    : emptyHTML('Пока ни одного устройства. Подключитесь — и оно появится здесь.', '<button type="button" class="lgb btn press" data-nav="/connect">Подключить</button>', icon.devices)}`;
  $$('[data-hwid]', root).forEach((b) => b.addEventListener('click', async () => {
    if (!(await confirmDialog('Отвязать устройство? Оно перестанет подключаться, пока вы снова не добавите подписку.'))) return;
    try {
      await post('/api/devices/delete', { hwid: b.dataset.hwid });
      haptic.notify('success');
      toast('Устройство отвязано');
      refresh();
    } catch (e) { toastError(e); }
  }));
}

const STATUS = {
  succeeded: '<span class="tag good">оплачен</span>',
  pending: '<span class="tag warn">ожидает</span>',
  processing: '<span class="tag warn">обработка</span>',
  failed: '<span class="tag bad">ошибка</span>',
  canceled: '<span class="tag neutral">отменён</span>',
  blocked: '<span class="tag bad">заблокирован</span>'
};
const KIND = { traffic_renewal: 'Трафик', device_limit_upgrade: 'Лимит устройств' };

export async function history(root, { navigate }) {
  root.innerHTML = '<div class="topbar"><h1 class="title">Платежи</h1></div><div class="skeleton"></div>';
  const { items } = await get('/api/payments');
  root.innerHTML = `<div class="topbar"><h1 class="title">Платежи</h1></div>
    ${items.length ? `<div class="card group">${items.map((x) => `
      <div class="row">
        <span class="grow" style="display:flex;flex-direction:column;gap:2px">
          <span style="font-weight:600">${esc(KIND[x.kind] || (x.days ? `Подписка на ${daysWord(x.days)}` : 'Подписка'))}</span>
          <span class="small muted">${esc(ago(x.created_at))} · ${esc(x.method)}</span>
        </span>
        <span style="display:flex;flex-direction:column;align-items:flex-end;gap:4px"><b>${money(x.amount, x.currency)}</b>${STATUS[x.status] || ''}</span>
      </div>`).join('')}</div>`
    : emptyHTML('Платежей пока нет.', '<button type="button" class="lgb btn press" data-nav="/buy">Выбрать тариф</button>', icon.card)}`;
  if (!items.length) setMain({ text: 'Выбрать тариф', onClick: () => navigate('/buy') });
}
